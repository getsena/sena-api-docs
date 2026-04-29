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

## Estado del proyecto

R1 backend está al 98% en `sena-api-core`. Este repo arranca con:

- Snapshot del schema generado el 2026-04-28 desde `sena-api-core` post Phase I.1
- Scalar bundle vía CDN (sin build step)
- Recipes scaffolded (Markdown)
- Sin deploy todavía — review local, decisiones de hosting / dominio pendientes

## Hosting — readme.io

El sitio se sirve desde [readme.io](https://readme.com/) en `https://docs.somossena.com/`.

### Sync automático (GitHub Action)

`.github/workflows/sync-readme.yml` corre en cada push a `main` y sincroniza:

1. `openapi/schema.json` → API Reference de readme.io
2. `content/**/*.md` → Guides de readme.io (cada archivo lleva frontmatter con `title`, `slug`, `category`, `order`)

### Configuración (one-time, en GitHub repo settings)

**Secret** → Settings → Secrets and variables → Actions → New repository secret:
- `README_API_KEY` — API key de readme.io con permisos de write

**Variable** (opcional, si la versión cambia) → Variables tab:
- `README_VERSION` — default `v1`

### Setup inicial (una sola vez, manual en readme.io UI)

Proyecto: `sena-qkdy` (https://dash.readme.com/project/sena-qkdy). Versión: `1.0`. Custom domain `docs.somossena.com` ya configurado.

Falta crear las **Categories** que el frontmatter referencia:
- `getting-started` (Quickstart, Authentication)
- `concepts` (Conventions, Errors, Changelog)
- `recipes` (Sync ERP, Upload PDF, Poll status, HMAC)

Después configurar el secret `README_API_KEY` en GitHub repo settings y push a `main` — el workflow sincroniza todo.

### Triggear sync manual

Settings → Actions → "Sync to readme.io" → Run workflow

## Estructura

```
sena-api-docs/
├── .github/workflows/
│   └── sync-readme.yml     # CI sync con readme.io
├── index.html              # Preview local con Scalar (zero install)
├── openapi/
│   └── schema.json         # OpenAPI 3.1 — snapshot, regenerable via script
├── content/                # Markdown guides (con frontmatter readme.io)
│   ├── quickstart.md
│   ├── authentication.md
│   ├── conventions.md
│   ├── errors.md
│   ├── changelog.md
│   └── recipes/
│       ├── sync-erp-invoices.md
│       ├── upload-invoice-with-pdf.md
│       ├── poll-import-status.md
│       └── verify-hmac-signature.md
└── scripts/
    └── sync-schema.sh      # Refresca openapi/schema.json desde sena-api-core local
```
