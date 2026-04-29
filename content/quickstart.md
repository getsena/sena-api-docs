# Quickstart — tu primera factura en 5 minutos

Esta guía cubre el camino más corto desde cero hasta tener una factura sincronizada en Sena vía la API pública.

## Lo que vas a hacer

1. Obtener una API key de **sandbox** (no toca datos reales)
2. Crear una `Company` (tu cliente o proveedor)
3. Crear una `Invoice` (deuda asociada a esa Company)
4. Verificar el resultado

Tiempo estimado: 5 minutos. Lenguaje: cURL en los ejemplos. La API es JSON sobre HTTPS.

## 1. API key

Las keys se provisionan desde el admin de Sena. Una vez creada, se muestra **una sola vez** — guardala en tu password manager.

Las keys tienen el formato `sk_<mode>_<43chars>`:

- `sk_test_...` — modo sandbox. Toca una organización gemela, NO afecta tus datos reales.
- `sk_live_...` — modo producción.

Para el resto del quickstart, exportá tu key sandbox:

```bash
export SENA_API_KEY="sk_test_AbCd..."
export SENA_API_BASE="https://sandbox.cobranzasena.cl"   # cambiar a api.cobranzasena.cl en prod
```

## 2. Crear una Company

Companies representan a un cliente o proveedor. Una misma Company es global — varias organizaciones pueden referenciar la misma `Company` (ej. dos PYMEs que ambas le deben dinero al mismo deudor). La relación org ↔ Company se crea automáticamente en este POST.

```bash
curl -X POST "$SENA_API_BASE/api/public/v1/companies" \
  -H "Authorization: Bearer $SENA_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "tax_id": "77000000-0",
    "legal_name": "Deudor SpA",
    "country": "chile"
  }'
```

Response (`201 Created`):

```json
{
  "id": "co_3f1a2b8c9d4e5f6789ab12cd34ef5678",
  "tax_id": "77000000-0",
  "legal_name": "Deudor SpA",
  "country": "chile",
  "created": "2026-04-28T20:00:00Z",
  "modified": "2026-04-28T20:00:00Z"
}
```

Anotá el `id` — lo usás en el siguiente paso.

> **Idempotencia:** si re-postear el mismo `tax_id + country`, recibís `200 OK` con la Company existente (no `409`). El `legal_name` se actualiza si cambió.

## 3. Crear una Invoice

Invoices representan deudas. Cada Invoice referencia una Company (`company_id`) — la API NO autocrea Companies en este endpoint, solo en `POST /companies`. Si pasás un `company_id` que no existe en tu org, recibís `422 unknown_company`.

```bash
curl -X POST "$SENA_API_BASE/api/public/v1/invoices" \
  -H "Authorization: Bearer $SENA_API_KEY" \
  -H "Content-Type: application/json" \
  -H "Idempotency-Key: $(uuidgen)" \
  -d '{
    "company_id": "co_3f1a2b8c9d4e5f6789ab12cd34ef5678",
    "invoice_number": "12345",
    "amount": "10000.00",
    "currency": "CLP",
    "due_date": "2026-05-30",
    "direction": "receivable"
  }'
```

Response (`201 Created`):

```json
{
  "id": "inv_a1b2c3d4e5f6789012345abcdef67890",
  "external_id": "inv_3f1a2b8c9d4e5f6789ab12cd34ef5678_12345",
  "invoice_number": "12345",
  "amount": "10000.00",
  "currency": "CLP",
  "due_date": "2026-05-30",
  "direction": "receivable",
  "status": "pending",
  "created": "2026-04-28T20:00:01Z",
  "modified": "2026-04-28T20:00:01Z"
}
```

## 4. Verificar

Listá tus invoices recientes:

```bash
curl "$SENA_API_BASE/api/public/v1/invoices" \
  -H "Authorization: Bearer $SENA_API_KEY"
```

Deberías ver el invoice creado en el array `data`.

## Próximos pasos

- [Authentication](./authentication.md) — modos live/test, rotación de keys, scopes
- [Conventions](./conventions.md) — Idempotency-Key, errores, paginación, Stripe IDs
- [Recipes — Sync ERP invoices](./recipes/sync-erp-invoices.md) — cargar miles de facturas en batch
- [Recipes — Upload invoice with PDF](./recipes/upload-invoice-with-pdf.md) — adjuntar el archivo del DTE

## Troubleshooting

| Error | Causa común | Fix |
|---|---|---|
| `401 unauthorized` | Header Authorization ausente o mal formateado | `Authorization: Bearer sk_test_...` (con el "Bearer ") |
| `403 insufficient_scope` | API key sin el scope que el endpoint pide | Verificá los scopes asignados a tu key en el admin |
| `422 unknown_company` | `company_id` no existe en tu org | Crear la Company primero con `POST /companies` |
| `429 rate_limit_exceeded` | Más de 60 req/min en tu key | Esperá 60s o pedí aumento de tier |
