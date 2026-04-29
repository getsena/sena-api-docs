---
title: "Upload invoice with PDF"
slug: "recipe-upload-invoice-with-pdf"
category: "recipes"
order: 2
---

# Recipe — Upload invoice with PDF

**Goal**: subir una factura a Sena junto con su PDF (DTE chileno o equivalente). Útil para clientes con facturación electrónica donde el PDF es la fuente legal del documento.

**Endpoints involucrados**:
1. `POST /api/public/v1/companies` — la empresa contraparte
2. `POST /api/public/v1/invoices` — el invoice (deuda)
3. `POST /api/public/v1/documents` — el PDF asociado, vinculado al invoice

## Paso 1 — Setup

```bash
export SENA_API_KEY="sk_test_AbCd..."
export SENA_API_BASE="https://sandbox.cobranzasena.cl"
export AUTH="Authorization: Bearer $SENA_API_KEY"
```

## Paso 2 — Crear la Company y el Invoice

```bash
# Company
co_response=$(curl -sS -X POST "$SENA_API_BASE/api/public/v1/companies" \
  -H "$AUTH" -H "Content-Type: application/json" \
  -d '{ "tax_id": "77000000-0", "legal_name": "Deudor SpA", "country": "chile" }')
co_id=$(echo "$co_response" | jq -r .id)
echo "Company: $co_id"

# Invoice
inv_response=$(curl -sS -X POST "$SENA_API_BASE/api/public/v1/invoices" \
  -H "$AUTH" -H "Content-Type: application/json" \
  -H "Idempotency-Key: $(uuidgen)" \
  -d "{
    \"company_id\": \"$co_id\",
    \"invoice_number\": \"33-12345\",
    \"amount\": \"100000.00\",
    \"currency\": \"CLP\",
    \"due_date\": \"2026-05-30\",
    \"direction\": \"receivable\",
    \"external_id\": \"DTE-33-12345\"
  }")
inv_id=$(echo "$inv_response" | jq -r .id)
echo "Invoice: $inv_id"
```

## Paso 3 — Identificar el `document_type_id`

Los DocumentTypes de sistema están seedeados con códigos SII chilenos. Listalos:

```bash
curl -sS "$SENA_API_BASE/api/public/v1/document-types" -H "$AUTH" | \
  jq '.data[] | select(.code == "33") | { id, code, name, category }'
# {
#   "id": "dt_a1b2c3...",
#   "code": "33",
#   "name": "Factura Electrónica",
#   "category": "factura"
# }
```

Anotá el `id`:

```bash
dt_id="dt_a1b2c3..."
```

> **Nota**: si vas a hacer esto frecuentemente, cacheá los IDs de DocumentTypes que usás. Son estables.

## Paso 4 — Subir el Document con el PDF

El endpoint `POST /documents` es **JSON-only** para el caso single (la API actual no acepta `multipart/form-data` aquí — ese sería `/imports/documents`). Para single file la opción es:

**Opción A — Document metadata-only + invoice link** (PDF queda en tu storage, no en Sena):

```bash
curl -sS -X POST "$SENA_API_BASE/api/public/v1/documents" \
  -H "$AUTH" -H "Content-Type: application/json" \
  -H "Idempotency-Key: $(uuidgen)" \
  -d "{
    \"document_type_id\": \"$dt_id\",
    \"company_id\": \"$co_id\",
    \"name\": \"DTE 33-12345\",
    \"external_id\": \"dte-33-12345\",
    \"metadata\": {
      \"file_url\": \"https://tu-storage.com/dte-33-12345.pdf\",
      \"sii_track_id\": \"567890\"
    },
    \"invoice_ids\": [\"$inv_id\"]
  }"
```

**Opción B — batch via `/imports/documents` con un solo item** (PDF queda en Sena):

```bash
# Armar el zip con el PDF
zip -j /tmp/batch.zip /path/to/dte-33-12345.pdf

# Manifest
cat > /tmp/manifest.json <<EOF
{
  "items": [
    {
      "external_id": "dte-33-12345",
      "document_type_id": "$dt_id",
      "company_id": "$co_id",
      "name": "DTE 33-12345",
      "file_path": "dte-33-12345.pdf",
      "metadata": { "sii_track_id": "567890" }
    }
  ],
  "on_error": "continue"
}
EOF

curl -sS -X POST "$SENA_API_BASE/api/public/v1/imports/documents" \
  -H "$AUTH" \
  -H "Idempotency-Key: $(uuidgen)" \
  -F "manifest=<@/tmp/manifest.json;type=application/json" \
  -F "archive=@/tmp/batch.zip"
```

El response es `202 Accepted` con un `imp_<id>`. Poll `GET /imports/{id}` hasta `completed` y leé los results.

## Paso 5 — Vincular después (si lo creaste sin `invoice_ids`)

`POST /documents` y `POST /invoices` ambos aceptan `invoice_ids[]` y `document_ids[]` respectivamente. El vínculo es bidireccional via la tabla M2M `InvoiceDocument`.

```bash
curl -sS -X POST "$SENA_API_BASE/api/public/v1/invoices/$inv_id/link-document" \
  -H "$AUTH" -H "Content-Type: application/json" \
  -d "{ \"document_id\": \"$doc_id\" }"
```

(Endpoint `link-document` es del API interno por ahora; en R2 se publica en el namespace público).

## Casos comunes

### El PDF ya está en mi S3 / Azure Blob

Usá Opción A (metadata-only). Sena no necesita una copia — guarda solo metadata + URL externa. Más eficiente para storage.

### Necesito que Sena tenga el archivo (compliance)

Usá Opción B (batch import multipart). Los archivos quedan en el blob storage de Sena. Para grandes volúmenes podés batchear hasta 5000 documents en un solo zip + manifest.

### Vincular un Document a múltiples Invoices

Pasá un array en `invoice_ids`:

```json
{ "invoice_ids": ["inv_abc...", "inv_def..."] }
```

Útil para Notas de Crédito que afectan a varias facturas.
