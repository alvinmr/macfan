#!/usr/bin/env bash
# Regenerates Resources/Icon/artwork.png with an image model, from Resources/Icon/prompt.txt.
# Works with any OpenAI-compatible /images/generations endpoint.
#
#   OPENAI_API_KEY=sk-... scripts/generate-icon-art.sh
#   IMAGE_API_BASE=http://localhost:20128/v1 IMAGE_MODEL=cx/gpt-image-2.5 scripts/generate-icon-art.sh   # 9router
#
# Then run `make icon` to rebuild the .icns. Review the result before committing it.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
API_BASE="${IMAGE_API_BASE:-https://api.openai.com/v1}"
MODEL="${IMAGE_MODEL:-gpt-image-1}"
OUT="$ROOT/Resources/Icon/artwork.png"
RESPONSE="$(mktemp)"
trap 'rm -f "$RESPONSE"' EXIT

AUTH=()
if [[ -n "${OPENAI_API_KEY:-}" ]]; then
  AUTH=(-H "Authorization: Bearer $OPENAI_API_KEY")
fi

PAYLOAD="$(python3 -c '
import json, sys
print(json.dumps({
    "model": sys.argv[1],
    "prompt": open(sys.argv[2]).read().strip(),
    "n": 1,
    "size": "1024x1024",
    "quality": "high",
    "output_format": "png",
}))' "$MODEL" "$ROOT/Resources/Icon/prompt.txt")"

echo "▸ Generating with $MODEL via $API_BASE"
curl -sS --fail-with-body -m 300 "$API_BASE/images/generations" \
  -H "Content-Type: application/json" ${AUTH[@]+"${AUTH[@]}"} \
  -d "$PAYLOAD" -o "$RESPONSE"

python3 - "$RESPONSE" "$OUT" <<'EOF'
import base64, json, sys, urllib.request
response, out = sys.argv[1], sys.argv[2]
item = json.load(open(response))["data"][0]
if item.get("b64_json"):
    data = base64.b64decode(item["b64_json"])
else:
    data = urllib.request.urlopen(item["url"]).read()
open(out, "wb").write(data)
EOF
sips -Z 1024 "$OUT" >/dev/null
echo "✓ $OUT — now run: make icon"
