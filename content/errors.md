---
title: "Error catalog"
slug: "errors"
category: "concepts"
order: 2
---

# Error catalog

Todos los errores de la API pública siguen [RFC 7807 Problem Details](./conventions.md#errores--rfc-7807-problem-details). El campo `code` es estable: una vez publicado, su significado no cambia. Nuevos codes se agregan acá.

## Por status code

### 4xx — Cliente

| Status | Code | Cuándo ocurre |
|---|---|---|
| 400 | `malformed_body` | Body no parseable como JSON, o tipo distinto a object |
| 400 | `malformed_manifest` | En `POST /imports/documents`, el field `manifest` no es JSON válido |
| 400 | `missing_manifest` | En `POST /imports/documents`, faltó el field `manifest` |
| 400 | `missing_archive` | En `POST /imports/documents`, faltó el field `archive` (zip) |
| 400 | `empty_batch` | `items` vacío en POST /imports/* |
| 400 | `idempotency_key_required` | POST /imports/* sin header Idempotency-Key |
| 400 | `invalid_filter` | Query param de filtro mal formateado (ej. `?status_code=abc`) |
| 401 | `unauthorized` | API key ausente, malformada, expirada o revocada |
| 403 | `insufficient_scope` | API key OK pero falta scope para este endpoint |
| 403 | `wrong_mode` | Mismatch entre `mode` de la key (live/test) y el endpoint |
| 404 | `resource_not_found` | El recurso no existe en tu organización (también cubre cross-tenant) |
| 409 | `conflict_immutable_resource` | Re-POST de Transaction con mismo `external_id` y body distinto |
| 413 | `payload_too_large` | Batch con más de 5000 items |
| 422 | `unknown_company` | `company_id` referenciado no existe en tu organización |
| 422 | `unknown_document_type` | `document_type_id` referenciado no existe |
| 422 | `external_id_required` | Campos requeridos para computar `external_id` faltantes |
| 422 | `external_id_invalid` | `external_id` provisto no matchea el regex `[A-Za-z0-9._:\-@+]{1,128}` |
| 422 | `immutable_resource` | Intento de PATCH/DELETE sobre un recurso del sistema (ej. DocumentType `is_system=True`) |
| 422 | `validation_error` | Campos del body invalidan reglas de negocio |
| 429 | `rate_limit_exceeded` | Excediste tu cuota por minuto. Header `Retry-After` indica segundos |

### 5xx — Servidor

| Status | Code | Cuándo ocurre |
|---|---|---|
| 500 | `internal_error` | Bug nuestro. Reportá con el `request_id` |
| 503 | `service_unavailable` | Mantenimiento programado o downstream caído |

## Patrones de manejo

### Retries

| Status | Retry? |
|---|---|
| 4xx (excepto 429) | **No.** Es un problema en tu request, retry no lo arregla. Loggeá y revisá. |
| 429 | **Sí**, después del `Retry-After`. Backoff exponencial si lo seguís golpeando. |
| 500/503 | **Sí**, con backoff exponencial (ej. 1s, 2s, 4s, 8s, máximo 5 intentos). |

Para retries de POST, usá `Idempotency-Key` para evitar duplicados.

### `unknown_company` / `unknown_document_type`

La API pública **NO autocrea** Companies ni DocumentTypes implícitos. Si recibís estos errores:

1. Verificá que creaste la entidad referenciada (`POST /companies` antes que `POST /invoices`)
2. Verificá que el `company_id` que pasás es un Stripe-style ID (`co_<32hex>`), no el `tax_id` ni el UUID con guiones
3. Verificá que el recurso pertenece a **tu** organización (cross-tenant también devuelve `unknown_*`, no `forbidden`)

### `conflict_immutable_resource` (Transactions)

Las Transactions son **inmutables post-creación**. Re-POST con mismo `external_id`:

- **Body byte-idéntico** → `200 OK`, retorna la transaction existente. Idempotente.
- **Body distinto** → `409 conflict_immutable_resource`. Resolución: NO mutar; si necesitás corregir, anulá vía operaciones de reconciliación (R3) y creá una transaction nueva con `external_id` distinto.

### `validation_error`

Trae detalle por campo:

```json
{
  "code": "validation_error",
  "errors": [
    { "path": "amount", "code": "min_value", "message": "Debe ser positivo." },
    { "path": "currency", "code": "invalid_choice", "message": "'XYZ' no es una currency válida." }
  ]
}
```

`path` es el JSON path del campo erróneo. Útil para mapear a tu form/UI.

## Reportar bugs

Si encontrás un error que no parece corresponder a tu request o el `code` no está documentado: abrir ticket con el `request_id` del response. El `request_id` está en el body Problem Details y también en el header `X-Request-Id` de la respuesta.

```bash
# Capturá el request_id en tu logging
echo "$response" | jq '.request_id'
```
