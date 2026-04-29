# Authentication

La Sena Public API autentica con **API keys**. No hay OAuth de usuario final. Las keys se provisionan desde el admin de Sena, una por integración.

## Header

Hay dos formas equivalentes:

```http
Authorization: Bearer sk_live_AbCd...
```

```http
X-Sena-API-Key: sk_live_AbCd...
```

Recomendamos `Authorization: Bearer` (estándar industria; lo soportan todas las herramientas — Postman, Insomnia, generadores de SDK).

## Modos: live vs test

Cada API key tiene un **mode** fijo: `live` o `test`. El mode está embebido en el prefix de la key:

- `sk_live_<43chars>` — opera contra tu organización **real**.
- `sk_test_<43chars>` — opera contra una organización **sandbox** gemela. Mismos scopes, mismos endpoints, mismas validaciones — pero los datos viven en una org separada que NO afecta producción.

Cada cliente de Cobranza Sena tiene exactamente una org sandbox enlazada a su org real. Cuando tu key `sk_test_...` crea un `Invoice`, ese invoice queda en la sandbox. Es seguro romper cosas ahí.

> **Tip**: usá un único entry point en tu código que lea `SENA_API_KEY` desde env. Pasar de sandbox a prod es solo cambiar la variable.

## Scopes

Cada key tiene una lista de scopes que define qué puede hacer. Los scopes siguen el patrón `<acción>:<recurso>`:

| Scope | Permite |
|---|---|
| `read:invoices` | GET /invoices |
| `write:invoices` | POST/PATCH /invoices, void |
| `read:transactions` | GET /transactions |
| `write:transactions` | POST /transactions |
| `read:companies` | GET /companies |
| `write:companies` | POST/PATCH /companies |
| `read:contacts` | GET /contacts |
| `write:contacts` | POST/PATCH /contacts |
| `read:documents` | GET /documents |
| `write:documents` | POST /documents |
| `read:document_types` | GET /document-types |
| `write:document_types` | POST/PATCH /document-types |
| `read:imports` | GET /imports/* |
| `write:imports` | POST /imports/* (combinado con `write:<resource>`) |
| `read:audit` | GET /me/audit |

Si llamás un endpoint sin el scope correspondiente, recibís `403 insufficient_scope` con el code en el body Problem Details.

Para uploads en batch necesitás dos scopes simultáneos: `write:imports` + `write:invoices` (o `write:transactions`, etc.).

## Rate limit

Por defecto: **60 requests/minuto** por key. La cuota viaja en cada response:

```http
X-RateLimit-Limit: 60
X-RateLimit-Remaining: 47
X-RateLimit-Reset: 1714327200
```

Si excedés: `429 rate_limit_exceeded` con `Retry-After: <segundos>`. Backoff exponencial recomendado.

Tiers superiores (`high_volume` 600/min, `internal_ops` 1200/min) se piden por ticket — no son self-service.

## Rotación

Cada API client puede tener **múltiples keys vivas** simultáneamente. Eso permite rotación sin downtime:

1. Generás una key nueva (`sk_live_NEW...`)
2. Tu integración usa la nueva
3. Una vez verificado, revocás la vieja desde el admin

Las keys revocadas devuelven `401 unauthorized` inmediato.

## Buenas prácticas

- **Nunca** commitear keys al código. Usar gestores de secrets (1Password, Vault, AWS Secrets Manager).
- **Una key por servicio**. Si tenés un sync ERP y un script de admin, dos keys con scopes mínimos cada una. Aislás blast radius.
- **Rotar al menos anualmente**. Programá un recordatorio.
- **Sandbox para cualquier integración nueva**. La sandbox es gratis y comparte el catálogo (Currency, DocumentType de sistema) con prod, así que los flows son representativos.

## Errores de auth comunes

| Status | Code | Significado |
|---|---|---|
| 401 | `unauthorized` | API key ausente, malformada, expirada o revocada |
| 403 | `insufficient_scope` | Key OK pero falta el scope para este endpoint |
| 403 | `wrong_mode` | Intentaste pegarle a un endpoint que requiere `mode=live` con una key `mode=test` (o viceversa) |
