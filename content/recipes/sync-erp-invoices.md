---
title: "Sync ERP invoices"
slug: "recipe-sync-erp-invoices"
category: "recipes"
order: 1
---

# Recipe — Sync ERP invoices

**Goal**: cargar las facturas pendientes del último mes desde tu ERP a Sena en un solo batch async. Tipo de uso: integración inicial o sync nocturno.

**Tiempo**: ~5 min de lectura. ~3 min de implementación.

**Lo que vamos a hacer**:
1. Asegurarnos de que las Companies existen (POST /imports/companies)
2. Cargar las invoices en batch (POST /imports/invoices)
3. Pollear el estado hasta `completed`
4. Inspeccionar resultados per-item

## Setup

```bash
export SENA_API_KEY="sk_test_AbCd..."
export SENA_API_BASE="https://sandbox.cobranzasena.cl"
```

## Paso 1 — Sync companies

Primero las Companies. La API NO autocrea Companies al crear Invoices — `unknown_company` falla el item. Mejor cargarlas primero en batch propio.

Asumimos que tu ERP exporta un CSV con columnas `tax_id, legal_name, country`. Lo transformás a este JSON:

```python
import requests
import os
import uuid

api_base = os.environ["SENA_API_BASE"]
headers = {
    "Authorization": f"Bearer {os.environ['SENA_API_KEY']}",
    "Content-Type": "application/json",
    "Idempotency-Key": str(uuid.uuid4()),  # un UUID por batch
}

# Items extraídos de tu ERP
companies = [
    {"tax_id": "77000000-0", "legal_name": "Deudor SpA", "country": "chile"},
    {"tax_id": "88000000-0", "legal_name": "Cliente Premium Ltda", "country": "chile"},
    # ...hasta 5000 items
]

resp = requests.post(
    f"{api_base}/api/public/v1/imports/companies",
    headers=headers,
    json={"items": companies, "on_error": "continue"},
)
resp.raise_for_status()
import_id = resp.json()["id"]   # ej. "imp_abc123..."
print(f"Companies import encolado: {import_id}")
```

`on_error=continue` (default) marca per-item los errores y sigue con el resto. Si preferís all-or-nothing, pasá `"abort"`.

## Paso 2 — Pollear hasta completed

```python
import time

while True:
    resp = requests.get(
        f"{api_base}/api/public/v1/imports/{import_id}",
        headers={"Authorization": headers["Authorization"]},
    )
    state = resp.json()
    print(f"  status={state['status']} success={state['success_count']} errors={state['error_count']}")
    if state["status"] in ("completed", "completed_with_errors", "failed"):
        break
    time.sleep(2)

if state["status"] == "failed":
    raise RuntimeError(f"Import {import_id} falló")
```

Para batches chicos (< 100 items) el resultado suele estar listo casi inmediato — el worker procesa en sub-segundo. Para batches de 5000 items contás con varios segundos.

## Paso 3 — Sync invoices

Ya con Companies en Sena, cargás las Invoices. Necesitás los `company_id` Stripe-style. Si guardaste el mapping `tax_id → company_id` cuando lo creaste, perfecto. Si no, los recuperás de los results del paso 1:

```python
resp = requests.get(
    f"{api_base}/api/public/v1/imports/{import_id}/results",
    headers={"Authorization": headers["Authorization"]},
    params={"limit": 1000},
)
# Cada item: {"idx": 0, "external_id": "", "ok": true, "id": "co_abc...", "action": "created"}
tax_to_co_id = {
    companies[r["idx"]]["tax_id"]: r["id"]
    for r in resp.json()["data"]
    if r["ok"]
}
```

Ahora armás el invoice batch:

```python
invoices = [
    {
        "company_id": tax_to_co_id["77000000-0"],
        "invoice_number": "F-2026-001",
        "amount": "150000.00",
        "currency": "CLP",
        "due_date": "2026-05-30",
        "direction": "receivable",
        "external_id": "F-2026-001",   # tu folio interno
    },
    # ...resto
]

resp = requests.post(
    f"{api_base}/api/public/v1/imports/invoices",
    headers={**headers, "Idempotency-Key": str(uuid.uuid4())},
    json={"items": invoices, "on_error": "continue"},
)
invoice_import_id = resp.json()["id"]
```

Polleás como en el paso 2.

## Paso 4 — Inspeccionar errores

```python
resp = requests.get(
    f"{api_base}/api/public/v1/imports/{invoice_import_id}/results",
    headers={"Authorization": headers["Authorization"]},
    params={"limit": 1000},
)
errors = [r for r in resp.json()["data"] if not r["ok"]]
for err in errors:
    print(f"  invoice idx={err['idx']} external_id={err['external_id']} error={err['error']}")
```

Errores comunes:

- `unknown_company`: el `company_id` que pasaste no existe. Probablemente el batch de companies tuvo este `tax_id` con error. Cargalos primero.
- `external_id_invalid`: el `external_id` tiene caracteres inválidos (`[A-Za-z0-9._:\-@+]{1,128}`).
- `validation_error`: revisar `errors[].path` para el campo problemático.

## Re-correr el batch

Si la corrida tuvo errores y arreglaste el dato en tu ERP, podés re-correr el mismo `Idempotency-Key`:

- Si la key sigue cacheada (24h), recibís el response viejo (el batch fallido). Esto **no es lo que querés**.
- Generá un `Idempotency-Key` nuevo. La API entera es upsert por `(org, external_id)`, así que reposear los items que sí funcionaron es no-op (action: `updated` con datos idénticos).

## Producción: cron job

Patrón típico:

```python
# crontab: cada noche a las 2am
def nightly_sync():
    new_invoices = export_from_erp(since=yesterday())
    if not new_invoices:
        return
    sync_companies_referenced_by(new_invoices)
    sync_invoices(new_invoices)
    notify_ops_channel("sync ok")
```

Al ser el endpoint upsert por `external_id`, podés reposear el mismo invoice múltiples veces sin duplicación. La idempotencia natural (mismo external_id → update) cubre los retries de transporte más allá de las 24h del `Idempotency-Key`.
