#!/usr/bin/env bash
# Start Isaac kernel + dashboard/monitor in Codespaces / Dev Container
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

mkdir -p logs runtime workspace data

if [ ! -x .venv/bin/python ]; then
  echo "[Isaac] .venv fehlt — führe post-create aus …"
  bash .devcontainer/post-create.sh
fi

# Load .env into process env if present (without printing secrets)
if [ -f .env ]; then
  set -a
  # shellcheck disable=SC1091
  source .env 2>/dev/null || true
  set +a
fi

export ISAAC_DISABLE_VECTOR_MEMORY="${ISAAC_DISABLE_VECTOR_MEMORY:-1}"
export MONITOR_PORT="${MONITOR_PORT:-8765}"
export DASHBOARD_PORT="${DASHBOARD_PORT:-8766}"
export MONITOR_HTTP_PORT="${MONITOR_HTTP_PORT:-8766}"
export PYTHONUNBUFFERED=1
export PYTHONDONTWRITEBYTECODE=1

# Codespaces: bind so port forward works
export ISAAC_BIND_HOST="${ISAAC_BIND_HOST:-0.0.0.0}"

if [ -z "${GROQ_API_KEY:-}" ] && [ -z "${OPENROUTER_API_KEY:-}" ] && [ -z "${GOOGLE_API_KEY:-}" ] && [ -z "${GEMINI_API_KEY:-}" ]; then
  echo "[Isaac] HINWEIS: Kein LLM-API-Key gesetzt."
  echo "         Setze GROQ_API_KEY als Codespaces-Secret und rebuild den Codespace,"
  echo "         oder exportiere den Key im Terminal."
  echo "         Lightweight-Pfade (Hallo/Danke) funktionieren trotzdem lokal."
fi

echo "[Isaac] Starte Kernel (Dashboard :${MONITOR_HTTP_PORT}, WS :${MONITOR_PORT})"
echo "[Isaac] Provider: ${ACTIVE_PROVIDER:-groq}"
exec .venv/bin/python isaac_core.py
