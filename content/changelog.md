# Changelog — Sena Public API

Cambios al contrato público (`/api/public/v1/*`). El namespace `v1` se mantiene compatible: solo se agregan campos opcionales y endpoints. Cualquier cambio breaking pasa a `v2` con notice de 12 meses mínimo.

## 2026-04-28 — R1 ingestion completa

**Endpoints agregados:**

- `POST/GET/PATCH /api/public/v1/invoices` (+ `void` action)
- `POST/GET /api/public/v1/transactions`
- `POST/GET/PATCH /api/public/v1/companies`
- `POST/GET/PATCH /api/public/v1/contacts`
- `POST/GET/PATCH /api/public/v1/documents`
- `GET/POST/PATCH/DELETE /api/public/v1/document-types`
- `POST /api/public/v1/imports/{invoices,transactions,companies,contacts}` — batch async JSON, hasta 5000 items
- `POST /api/public/v1/imports/documents` — batch async multipart (manifest + zip)
- `GET /api/public/v1/imports/{id}` — status del batch
- `GET /api/public/v1/imports/{id}/results` — per-item results paginados
- `GET /api/public/v1/imports` — historial paginado
- `GET /api/public/v1/me` — info del API client (scopes, mode)
- `GET /api/public/v1/me/audit` — audit log del propio cliente
- `GET /api/public/v1/health` — sin auth, para uptime monitors
- `GET /api/public/v1/schema` — OpenAPI 3.1 spec (este sitio se renderiza desde acá)
- `GET /api/public/v1/docs` — Swagger UI

**Características transversales:**

- Stripe-style IDs (`inv_`, `tx_`, `co_`, `ct_`, `doc_`, `dt_`, `imp_`)
- Idempotency-Key (24h cache)
- Cursor-based pagination
- RFC 7807 Problem Details para errores
- Multi-tenant via API key (sin `X-Organization-Id` desde el cliente)
- Sandbox isolation: `sk_test_*` opera contra org gemela
- Audit log per request (`/me/audit`)

## Convenciones de versionado

- **Aditivos** (campo opcional nuevo, endpoint nuevo, código de error nuevo en el catálogo): publicados sin notice. Backwards-compatible.
- **Deprecations**: header `Sunset: <ISO date>` en el response. Mínimo 90 días antes del remove.
- **Breaking**: solo en `/api/public/v2/`. La `v1` se sostiene mínimo 12 meses post-anuncio. Email a `contact_email` de cada API client afectado.
