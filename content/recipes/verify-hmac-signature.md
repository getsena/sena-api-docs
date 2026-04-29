# Verify HMAC signature

Cada webhook que recibís de Sena viene firmado. **Siempre** verificá la firma antes de procesar el payload — sin verificar, un atacante puede falsificar requests al endpoint público de tu servicio.

## Headers de firma

```http
X-Sena-Signature: sha256=a1b2c3d4...
X-Sena-Timestamp: 1714327200
X-Sena-Event: invoice.created
X-Sena-Delivery: <uuid>
```

- `X-Sena-Signature` — `sha256=` seguido del HMAC-SHA256 en hex del string firmado
- `X-Sena-Timestamp` — timestamp UNIX cuando el evento fue firmado (para replay protection)

## Pasos de verificación

1. Leer `X-Sena-Timestamp` y `X-Sena-Signature`
2. Construir el string firmado: `f"{timestamp}.{raw_body}"` donde `raw_body` es el cuerpo del request como bytes (serializado con `sort_keys=True`)
3. Computar HMAC-SHA256 del string firmado usando tu `secret` como key
4. Comparar `sha256=<tu_hmac>` contra `X-Sena-Signature` usando comparación constant-time
5. (Recomendado) verificar que `X-Sena-Timestamp` esté dentro de ±5 minutos para evitar replay attacks

> **`raw_body`** son los bytes exactos del body del request. Sena envía el payload con `sort_keys=True` — si lo re-serializás por tu cuenta los bytes pueden diferir y la firma fallará. Capturá el body raw antes de cualquier parseo.

## Python (Django, Flask, FastAPI)

```python
import hashlib
import hmac
import time

WEBHOOK_SECRET = "whsec_abc..."  # de tu WebhookSubscription
TOLERANCE_SECONDS = 300


def verify_signature(raw_body: bytes, signature_header: str, timestamp_header: str, secret: str) -> bool:
    """Verifica la firma HMAC-SHA256 de un webhook de Sena.

    Args:
        raw_body: body del request como bytes (sin parsear).
        signature_header: valor del header X-Sena-Signature.
        timestamp_header: valor del header X-Sena-Timestamp.
        secret: secret de la WebhookSubscription.

    Returns:
        True si la firma es válida y el timestamp está dentro de la ventana.
    """
    if not signature_header or not timestamp_header:
        return False

    # Replay protection
    try:
        ts = int(timestamp_header)
    except ValueError:
        return False
    if abs(int(time.time()) - ts) > TOLERANCE_SECONDS:
        return False

    # Recompute HMAC: signed_input = f"{timestamp}.{raw_body}"
    signed_input = f"{ts}.".encode("utf-8") + raw_body
    expected_hex = hmac.new(secret.encode("utf-8"), signed_input, hashlib.sha256).hexdigest()
    expected = f"sha256={expected_hex}"
    return hmac.compare_digest(signature_header, expected)
```

### Django view

```python
import json

from django.http import HttpResponse
from django.http import HttpResponseForbidden
from django.views.decorators.csrf import csrf_exempt


@csrf_exempt
def webhook_endpoint(request):
    sig = request.headers.get("X-Sena-Signature", "")
    ts = request.headers.get("X-Sena-Timestamp", "")
    if not verify_signature(request.body, sig, ts, WEBHOOK_SECRET):
        return HttpResponseForbidden("Invalid signature")

    payload = json.loads(request.body)
    event_type = request.headers.get("X-Sena-Event")
    # ...procesar según event_type
    return HttpResponse(status=200)
```

### FastAPI endpoint

```python
from fastapi import FastAPI
from fastapi import Header
from fastapi import HTTPException
from fastapi import Request

app = FastAPI()


@app.post("/webhook")
async def webhook_endpoint(
    request: Request,
    x_sena_signature: str = Header(...),
    x_sena_timestamp: str = Header(...),
):
    raw_body = await request.body()
    if not verify_signature(raw_body, x_sena_signature, x_sena_timestamp, WEBHOOK_SECRET):
        raise HTTPException(status_code=403, detail="Invalid signature")

    payload = await request.json()
    # ...procesar
    return {"ok": True}
```

## Node.js (Express)

```javascript
const crypto = require("crypto");

const WEBHOOK_SECRET = "whsec_abc...";
const TOLERANCE_SECONDS = 300;

/**
 * Verifica la firma HMAC-SHA256 de un webhook de Sena.
 * @param {Buffer} rawBody - body del request como Buffer.
 * @param {string} signatureHeader - valor de X-Sena-Signature.
 * @param {string} timestampHeader - valor de X-Sena-Timestamp.
 * @param {string} secret - secret de la WebhookSubscription.
 * @returns {boolean}
 */
function verifySignature(rawBody, signatureHeader, timestampHeader, secret) {
  if (!signatureHeader || !timestampHeader) return false;

  const ts = parseInt(timestampHeader, 10);
  if (isNaN(ts)) return false;

  // Replay protection
  if (Math.abs(Math.floor(Date.now() / 1000) - ts) > TOLERANCE_SECONDS) {
    return false;
  }

  // signed_input = `${ts}.${rawBody}`
  const signedInput = Buffer.concat([
    Buffer.from(`${ts}.`, "utf8"),
    rawBody,
  ]);
  const expectedHex = crypto
    .createHmac("sha256", secret)
    .update(signedInput)
    .digest("hex");
  const expected = `sha256=${expectedHex}`;

  // Constant-time comparison
  if (expected.length !== signatureHeader.length) return false;
  return crypto.timingSafeEqual(
    Buffer.from(signatureHeader, "utf8"),
    Buffer.from(expected, "utf8"),
  );
}

// Express middleware
// IMPORTANTE: express.raw() para preservar el body como Buffer.
// Si usás express.json(), el body se parsea y re-serializa rompiendo la firma.
app.post("/webhook", express.raw({ type: "application/json" }), (req, res) => {
  const sig = req.header("X-Sena-Signature") || "";
  const ts = req.header("X-Sena-Timestamp") || "";

  if (!verifySignature(req.body, sig, ts, WEBHOOK_SECRET)) {
    return res.status(403).send("Invalid signature");
  }

  const event = JSON.parse(req.body.toString("utf8"));
  const eventType = req.header("X-Sena-Event");
  // ...procesar según eventType
  res.status(200).send();
});
```

## cURL (testing local)

Para generar un request firmado válido y probar tu endpoint:

```bash
SECRET="whsec_abc..."
TS=$(date +%s)
BODY='{"id":"inv_test","amount":"100000","direction":"receivable"}'

# Sena serializa con sort_keys=True — para testing el body simple ya está ordenado.
# La firma se computa sobre "${TS}.${BODY}" (bytes)
SIG=$(printf '%s.%s' "$TS" "$BODY" | openssl dgst -sha256 -hmac "$SECRET" -hex | awk '{print "sha256="$2}')

curl -X POST https://tu-endpoint.com/webhook \
  -H "X-Sena-Signature: ${SIG}" \
  -H "X-Sena-Timestamp: ${TS}" \
  -H "X-Sena-Event: invoice.created" \
  -H "X-Sena-Delivery: $(uuidgen | tr '[:upper:]' '[:lower:]')" \
  -H "Content-Type: application/json" \
  -d "$BODY"
```

## Errores comunes

| Síntoma | Causa | Fix |
|---|---|---|
| Firma siempre inválida | Verificás contra el body parseado/re-serializado | Capturá `request.body` (bytes) ANTES de parsear |
| Firma válida en test, inválida en prod | Framework parsea+re-serializa el JSON | En Express: `express.raw()`. En Django DRF: leer `request.body` antes de `request.data` |
| Error `Signature mismatch` con sort | Re-serializaste el JSON sin `sort_keys=True` | No re-serialices — usá los bytes raw del body |
| Replay attacks aceptados | No verificás el timestamp | Sumá la ventana de tolerancia (5 min recomendado) |
| Timing attack vulnerable | Usás `==` en vez de comparación constant-time | Python: `hmac.compare_digest`. Node: `crypto.timingSafeEqual` |

## Más sobre webhooks

- [Convenciones generales](../conventions.md) — IDs, errores, paginación
- [Authentication](../authentication.md) — API keys
- [API reference](../../) — endpoints `/webhook-subscriptions` y `/webhook-events`
