# Conventions

## Identifiers — Stripe-style IDs

Todo recurso de la API expone dos identificadores:

- **`id`** — Stripe-style, formato `<prefix>_<32hex>`. Ejemplos: `inv_abc...`, `co_def...`, `tx_123...`. Inmutable, único globalmente. **Este es el ID que usás para referenciar el recurso en otros endpoints.**
- **`external_id`** — string libre que vos podés setear en el POST. Hasta 128 chars (`[A-Za-z0-9._:\-@+]`). Usalo para mapear con tu propio sistema (ej. el folio interno de tu ERP). Único por organización.

Prefijos por recurso:

| Recurso | Prefix |
|---|---|
| Invoice | `inv_` |
| Transaction | `tx_` |
| Company | `co_` |
| Contact | `ct_` |
| Document | `doc_` |
| DocumentType | `dt_` |
| ApiImport | `imp_` |

Cuando un endpoint pide otro recurso por referencia (ej. `company_id` en el body de `POST /invoices`), pasás el Stripe-style ID:

```json
{ "company_id": "co_3f1a2b8c9d4e5f6789ab12cd34ef5678", ... }
```

## Lookup en URL — id, uuid, external_id

Los endpoints de detalle resuelven cualquiera de los tres:

```http
GET /api/public/v1/invoices/inv_abc...           # Stripe ID
GET /api/public/v1/invoices/3f1a2b8c-9d4e-5f67-89ab-12cd34ef5678   # UUID
GET /api/public/v1/invoices/FACT-001             # external_id
```

El primer prefix matched gana (Stripe → UUID → external_id).

## Idempotency-Key

Para POSTs que mutan estado (Invoice, Document, batch imports), pasá el header:

```http
Idempotency-Key: 550e8400-e29b-41d4-a716-446655440000
```

Si re-postear el mismo body con la misma key dentro de 24h, recibís el response cacheado (mismo status, mismo body) sin re-ejecutar la operación. Útil para retries de transporte.

**Reglas**:
- Generá un UUID v4 nuevo por cada operación lógica del cliente. Mismo retry → misma key. Operación nueva → key nueva.
- En `POST /imports/*` la `Idempotency-Key` es **obligatoria** (`400 idempotency_key_required` sin ella).
- En POSTs simples (Invoice, Company, Contact, Document, Transaction) la dedup natural ocurre por `external_id` (mismo external_id → upsert / 409 conflict según recurso). `Idempotency-Key` es solo para retries inmediatos.

## Errores — RFC 7807 Problem Details

Todos los errores devuelven `Content-Type: application/problem+json` con esta forma:

```http
HTTP/1.1 422 Unprocessable Entity
Content-Type: application/problem+json
```

```json
{
  "type": "https://docs.cobranzasena.cl/errors/unknown_company",
  "title": "Unknown company",
  "status": 422,
  "detail": "Company 'co_ffff...' no existe en esta organización.",
  "instance": "/api/public/v1/invoices",
  "code": "unknown_company",
  "request_id": "req_abc123"
}
```

Campos:

- **`code`** (string, parte del contrato) — slug machine-readable. Estable: si lo agregamos al [error catalog](./errors.md), no cambia su significado.
- **`title`** — string corto para humanos.
- **`detail`** — explicación específica del incidente. Variable.
- **`status`** — espeja el HTTP status code.
- **`request_id`** — espeja `X-Request-Id`. Usalo si abrís un ticket de soporte.

Errores de validación de campos agregan `errors`:

```json
{
  "code": "validation_error",
  "errors": [
    { "path": "amount", "code": "min_value", "message": "Debe ser positivo." }
  ]
}
```

Catálogo completo en [errors.md](./errors.md).

## Pagination — cursor-based

Listados (`GET /invoices`, `GET /imports`, etc.) usan paginación cursor, no offset:

```http
GET /api/public/v1/invoices?limit=100&cursor=eyJpZCI6MTIzNDV9
```

Response:

```json
{
  "data": [...],
  "pagination": {
    "limit": 100,
    "has_more": true,
    "next_cursor": "eyJpZCI6MTI0NDV9",
    "prev_cursor": null
  }
}
```

- `limit` default 50, max 500.
- `cursor` es opaco — no parses su contenido.
- Para iterar todo: empezá sin cursor, leé `next_cursor`, repetí hasta `has_more=false`.
- Default ordering: `(created DESC, id DESC)`. Algunos endpoints aceptan `?ordering=`.

Ventaja vs offset: estable bajo inserts concurrentes (offset salta o duplica filas si llegan datos nuevos).

## Filtros estándar

Todos los recursos: `?external_id=`, `?created_after=`, `?created_before=` (ISO 8601).

Filtros específicos por recurso:

| Recurso | Filtros adicionales |
|---|---|
| Invoices | `?status=`, `?direction=`, `?due_date_lte/gte=`, `?amount_lte/gte=`, `?currency=`, `?company_id=` |
| Transactions | `?date_lte/gte=`, `?currency=` |
| Companies | `?country=`, `?tax_id=` |
| Contacts | `?company_id=`, `?email=` |

## Amount, currency, date

- **Amount**: string decimal, no float. `"10000.00"`, no `10000.0`.
- **Currency**: ISO 4217 code (`"CLP"`, `"USD"`, `"UF"`).
- **Date**: ISO 8601 date `"2026-05-30"` (sin tiempo) para `due_date`, ISO 8601 datetime para timestamps (`created`, `modified`, `started_at`).
- **RUT chileno**: en `tax_id` aceptamos `"77.000.000-0"`, `"77000000-0"`, `"770000000"` — normalizamos internamente. La respuesta lo devuelve canónico (`"77000000-0"`).

## Multi-tenant

Cada API key está atada a una organización. **Nunca** pasás `X-Organization-Id`. Los queries scopean automáticamente. Cross-tenant leakage retorna `404` (no `403`) — el endpoint se comporta como si el recurso no existiera para vos.

## Sandbox vs prod

Mismos endpoints, mismos contratos. La key define el target. Detalle en [authentication.md](./authentication.md).
