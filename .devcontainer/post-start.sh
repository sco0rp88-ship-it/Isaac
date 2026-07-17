#!/usr/bin/env bash
# Runs every time the Codespace starts (fast, non-blocking-ish).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

mkdir -p logs runtime workspace data

# Re-inject secrets if Codespaces refreshed them (no values logged)
if [ -f .env ] && [ -x .venv/bin/python ]; then
  for key in GROQ_API_KEY OPENROUTER_API_KEY GOOGLE_API_KEY GEMINI_API_KEY; do
    val="${!key:-}"
    [ -z "$val" ] && continue
    .venv/bin/python - "$key" "$val" <<'PY'
import sys, re, pathlib
key, val = sys.argv[1], sys.argv[2]
path = pathlib.Path(".env")
if not path.exists():
    raise SystemExit(0)
text = path.read_text(encoding="utf-8")
pat = re.compile(rf"^{re.escape(key)}=.*$", re.M)
if pat.search(text):
    text = pat.sub(f"{key}={val}", text, count=1)
else:
    text = text.rstrip() + f"\n{key}={val}\n"
path.write_text(text, encoding="utf-8")
print(f"[Isaac] post-start: {key} synced into .env")
PY
  done
fi

if [ -x .venv/bin/python ]; then
  echo "[Isaac] venv OK — start with: bash .devcontainer/start-isaac.sh"
else
  echo "[Isaac] .venv fehlt — führe aus: bash .devcontainer/post-create.sh"
fi
