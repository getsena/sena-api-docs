# sena-api-docs

Sitio de documentación de la **Sena Public API** — la API HTTP REST para integradores externos (`/api/public/v1/*`).

Este repo es la fuente de verdad del sitio público de developers. Renderizado con [Scalar](https://scalar.com/) sobre el OpenAPI spec auto-generado desde `sena-api-core`.

## Preview local

Hay dos formas:

### 1. Abrir el HTML directo (zero install)

```bash
open index.html
```

`index.html` carga Scalar via CDN y apunta a `openapi/schema.json`. Funciona offline una vez que el bundle se cachea.

### 2. Servir con un static server (refresh automático)

```bash
npx http-server . -p 5500 -c-1
# o
python3 -m http.server 5500
```

Después abrir `http://localhost:5500`.

## Sincronizar el schema

El archivo `openapi/schema.json` es un **snapshot** del endpoint público de `sena-api-core`. Para regenerarlo:

```bash
# sena-api-core debe estar corriendo (docker compose up core)
./scripts/sync-schema.sh
```

El script descarga `http://localhost:8001/api/public/v1/schema?format=json`, valida que no haya paths fuera del namespace público, y reemplaza `openapi/schema.json`.

## Estructura

```
sena-api-docs/
├── index.html              # Scalar + schema embebido (entrypoint del sitio)
├── openapi/
│   └── schema.json         # OpenAPI 3.1 — snapshot, regenerable via script
├── content/                # Markdown que complementa la spec (recipes, guides)
│   ├── quickstart.md       # Tu primera factura en 5 min
│   ├── authentication.md   # API keys, modos live/test, rotación
│   ├── conventions.md      # Stripe IDs, Idempotency-Key, errores RFC 7807, paginación
│   ├── errors.md           # Catálogo de error codes
│   ├── changelog.md        # Cambios del contrato público
│   └── recipes/
│       ├── sync-erp-invoices.md
│       ├── upload-invoice-with-pdf.md
│       └── poll-import-status.md
└── scripts/
    └── sync-schema.sh      # Refresca openapi/schema.json
```

## Estado del proyecto

R1 backend está al 98% en `sena-api-core`. Este repo arranca con:

- Snapshot del schema generado el 2026-04-28 desde `sena-api-core` post Phase I.1
- Scalar bundle vía CDN (sin build step)
- Recipes scaffolded (Markdown)
- Sin deploy todavía — review local, decisiones de hosting / dominio pendientes

## Roadmap

- [ ] Decidir hosting (Cloudflare Pages, Vercel, Static Web Apps Azure, etc.)
- [x] Hostname elegido: `docs.somossena.com` (servido por readme.io)
- [ ] CI: webhook desde `sena-api-core` que regenera `openapi/schema.json` al mergear `main`
- [ ] Recipes con código testeado (Python, Node, cURL)
- [ ] SDK references cuando existan
