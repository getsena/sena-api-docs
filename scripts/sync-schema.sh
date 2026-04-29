#!/usr/bin/env bash
# Re-genera openapi/schema.json desde la API local (sena-api-core corriendo en :8001).
#
# Uso:
#   ./scripts/sync-schema.sh
#
# Requiere sena-api-core levantado vía docker-compose del workspace raíz.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
URL="${SENA_API_BASE:-http://localhost:8001}/api/public/v1/schema?format=json"
OUT="$REPO_ROOT/openapi/schema.json"

echo "→ Descargando schema desde $URL"
curl -sSf "$URL" -o "$OUT"

PATHS=$(python3 -c "import json; print(len(json.load(open('$OUT')).get('paths', {})))")
echo "✓ schema actualizado ($(wc -c < "$OUT") bytes, $PATHS paths)"

# Verificación: ningún path debe filtrar fuera del namespace público.
LEAKS=$(python3 -c "
import json
spec = json.load(open('$OUT'))
leaks = [p for p in spec.get('paths', {}) if not p.startswith('/api/public/v1/')]
if leaks:
    for p in leaks:
        print(f'  - {p}')
    exit(1)
")
echo "✓ todos los paths bajo /api/public/v1/"
