---
title: Poll import status
slug: recipe-poll-import-status
category:
  uri: recipes
position: 3
---

# Recipe — Poll import status

**Goal**: implementar el patrón estándar de polling para batch imports async, con backoff exponencial, timeout, y manejo de errores per-item.

Aplica a todos los `POST /imports/*` (invoices, transactions, companies, contacts, documents).

## Patrón básico

```python
import time
import requests
import os

api_base = os.environ["SENA_API_BASE"]
auth = {"Authorization": f"Bearer {os.environ['SENA_API_KEY']}"}


def wait_for_import(import_id: str, *, timeout_s: int = 300, poll_interval_s: float = 1.0) -> dict:
    """Polleá un ApiImport hasta estado terminal o timeout.

    Args:
        import_id: el `imp_<uuid_hex>` retornado por POST /imports/*
        timeout_s: máximo tiempo a esperar (default 5 min, suficiente para 5000 items)
        poll_interval_s: intervalo inicial entre polls (sube con backoff)

    Returns:
        El último ApiImport state (dict). El status estará en uno de:
        completed | completed_with_errors | failed.

    Raises:
        TimeoutError si excede timeout_s
    """
    start = time.monotonic()
    interval = poll_interval_s
    while True:
        resp = requests.get(f"{api_base}/api/public/v1/imports/{import_id}", headers=auth)
        resp.raise_for_status()
        state = resp.json()
        if state["status"] in ("completed", "completed_with_errors", "failed"):
            return state
        if time.monotonic() - start > timeout_s:
            raise TimeoutError(f"Import {import_id} no terminó en {timeout_s}s (status={state['status']})")
        time.sleep(interval)
        interval = min(interval * 1.5, 10.0)  # backoff hasta 10s
```

Uso:

```python
state = wait_for_import("imp_abc123...")
print(f"Total: {state['total_count']}, OK: {state['success_count']}, errores: {state['error_count']}")
```

## Backoff exponencial

¿Por qué subir el `interval` con cada poll en vez de quedarte en 1s?

- **Imports chicos** (< 100 items) suelen terminar antes de 2s. Polleás 1-2 veces, listo.
- **Imports grandes** (5000 items) tardan ~30s. Pollear cada 1s genera 30 requests innecesarios y consume cuota rate-limit.
- Subiendo el intervalo a max 10s, un import de 5min toma ~10 polls totales (no 300).

## Inspeccionar resultados per-item

Una vez `completed_with_errors`, los detalles vienen del endpoint de results:

```python
def fetch_all_results(import_id: str) -> list[dict]:
    """Itera todos los results, paginado."""
    out = []
    offset = 0
    while True:
        resp = requests.get(
            f"{api_base}/api/public/v1/imports/{import_id}/results",
            headers=auth,
            params={"limit": 1000, "offset": offset},
        )
        resp.raise_for_status()
        body = resp.json()
        out.extend(body["data"])
        if not body["pagination"]["has_more"]:
            break
        offset += 1000
    return out


results = fetch_all_results(import_id)
errors = [r for r in results if not r["ok"]]
created = [r for r in results if r["ok"] and r["action"] == "created"]
updated = [r for r in results if r["ok"] and r["action"] == "updated"]

print(f"Creados: {len(created)}, actualizados: {len(updated)}, errores: {len(errors)}")

if errors:
    print("\nErrores:")
    for err in errors[:10]:  # primeros 10
        print(f"  idx={err['idx']} ext={err['external_id']!r} err={err['error']}")
```

Cada result tiene:

```json
{
  "idx": 42,
  "external_id": "FACT-001",
  "ok": true,
  "id": "inv_abc123...",
  "action": "created"
}
```

O en error:

```json
{
  "idx": 43,
  "external_id": "FACT-002",
  "ok": false,
  "error": "unknown_company: Company 'co_xyz...' no existe..."
}
```

## Cuándo hacer abort vs continue

`on_error` en el body del POST:

| Modo | Comportamiento | Cuándo usar |
|---|---|---|
| `continue` (default) | Item fallido → registrá error, seguí con el resto | Sync nocturno, donde querés cargar lo que se pueda y revisar errores luego |
| `abort` | Primer item fallido → rollback del chunk + status `failed` | Ingest crítico donde un fallo invalida el batch entero (ej. una migración inicial) |

**Importante**: `abort` rollbackea solo el **chunk** (500 items) donde ocurrió el error, no el batch entero. Items en chunks anteriores ya commiteados quedan creados. Esto es por performance — un batch de 5000 items con on_error=abort en el item 4999 no es viable rollbackear todo.

Si necesitás all-or-nothing absoluto, hacelo en chunks de tamaño que tu sistema tolere y maneja el rollback application-side.

## Patrón production-ready

```python
def sync_invoices_batch(invoices: list[dict]) -> dict:
    """Sync de N invoices con polling + retry de transporte.

    Retorna dict con stats. No raisea por errores per-item.
    """
    import_id = post_batch(invoices)
    state = wait_for_import(import_id, timeout_s=600)
    results = fetch_all_results(import_id)

    stats = {
        "import_id": import_id,
        "total": state["total_count"],
        "success": state["success_count"],
        "errors": state["error_count"],
        "duration_s": (
            datetime.fromisoformat(state["finished_at"]) -
            datetime.fromisoformat(state["started_at"])
        ).total_seconds() if state["finished_at"] else None,
        "error_items": [r for r in results if not r["ok"]],
    }
    return stats


def post_batch(invoices: list[dict]) -> str:
    """POST con retry en errores 5xx/transporte."""
    for attempt in range(3):
        try:
            resp = requests.post(
                f"{api_base}/api/public/v1/imports/invoices",
                headers={**auth, "Idempotency-Key": str(uuid.uuid4()), "Content-Type": "application/json"},
                json={"items": invoices, "on_error": "continue"},
                timeout=30,
            )
            if resp.status_code >= 500:
                raise RuntimeError(f"5xx: {resp.status_code} {resp.text}")
            resp.raise_for_status()
            return resp.json()["id"]
        except (requests.RequestException, RuntimeError) as exc:
            if attempt == 2:
                raise
            time.sleep(2 ** attempt)  # 1s, 2s
```

> Si querés que un retry use el mismo `Idempotency-Key` para deduplicar el POST inicial: persistí el UUID antes del primer intento y reusalo en los retries.
