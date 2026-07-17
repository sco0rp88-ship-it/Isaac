#!/bin/sh
# Isaac Startup (portabel)
# Codespaces/Devcontainer: lieber  bash .devcontainer/start-isaac.sh
# Dieses Skript: gleicher Repo-Ordner wie die Datei (kein festes /root/Isaac/…).
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
cd "$ROOT"

if [ -f .env ]; then
  set -a
  # shellcheck disable=SC1091
  . ./.env
  set +a
fi

export ISAAC_DISABLE_VECTOR_MEMORY="${ISAAC_DISABLE_VECTOR_MEMORY:-1}"
export MONITOR_PORT="${MONITOR_PORT:-8765}"
export DASHBOARD_PORT="${DASHBOARD_PORT:-8766}"
export MONITOR_HTTP_PORT="${MONITOR_HTTP_PORT:-8766}"
export PYTHONUNBUFFERED=1

# In Codespaces / Free-Cloud an allen Interfaces binden + Unified WS (/ws am HTTP-Port)
if [ -n "${CODESPACES:-}" ] || [ -n "${GITHUB_CODESPACE_TOKEN:-}" ] || [ "${ISAAC_FREE_CLOUD:-0}" = "1" ]; then
  export ISAAC_BIND_HOST="${ISAAC_BIND_HOST:-0.0.0.0}"
  # Browser-Tab auf :8765 zeigt "missing Connection header" — Dashboard-Port + /ws nutzen
  if [ -n "${CODESPACES:-}" ] || [ -n "${GITHUB_CODESPACE_TOKEN:-}" ]; then
    export ISAAC_UNIFIED_PORT="${ISAAC_UNIFIED_PORT:-1}"
  fi
fi

echo "┌──────────────────────────────┐"
echo "│      Isaac - Startup         │"
echo "└──────────────────────────────┘"
echo "[Isaac] ROOT=$ROOT"
echo "[Isaac] Provider: ${ACTIVE_PROVIDER:-unset}"

# Ollama nur prüfen, wenn wirklich als Provider genutzt
PROVIDER="$(printf '%s' "${ACTIVE_PROVIDER:-}" | tr '[:upper:]' '[:lower:]')"
if [ "$PROVIDER" = "ollama" ] || [ "$PROVIDER" = "" ] && [ -z "${GROQ_API_KEY:-}${OPENROUTER_API_KEY:-}${GOOGLE_API_KEY:-}${GEMINI_API_KEY:-}" ]; then
  # leerer Provider ohne Cloud-Keys → historisches Ollama-Verhalten (optional)
  if [ "$PROVIDER" = "ollama" ]; then
    OLLAMA_URL="${OLLAMA_HOST:-http://127.0.0.1:11434}"
    echo "[Isaac] Prüfe Ollama: $OLLAMA_URL"
    if ! curl -fsS "$OLLAMA_URL/api/tags" >/dev/null 2>&1; then
      echo "[Isaac] Fehler: Ollama nicht erreichbar unter $OLLAMA_URL"
      echo "[Isaac] In Codespaces: ACTIVE_PROVIDER=gemini|groq|openrouter + API-Key Secret nutzen."
      exit 1
    fi
    echo "[Isaac] Ollama erreichbar ✓"
  fi
fi

mkdir -p logs runtime workspace data

if [ -x .venv/bin/python ]; then
  PY=".venv/bin/python"
elif [ -d .venv ]; then
  # shellcheck disable=SC1091
  . .venv/bin/activate
  PY="python"
else
  PY="python3"
  echo "[Isaac] Hinweis: kein .venv — nutze $PY"
  echo "[Isaac] Codespaces: bash .devcontainer/post-create.sh"
fi

echo "[Isaac] Starte isaac_core.py (Kernel + Dashboard) …"
echo "[Isaac] Dashboard: http://localhost:${MONITOR_HTTP_PORT}"
echo "[Isaac] WebSocket:  ws://localhost:${MONITOR_PORT}"
echo "[Isaac] Codespaces: Panel PORTS → Port Public → Browser-Icon"

# Vordergrund (Codespaces-freundlich). Für Hintergrund: ISAAC_START_BG=1
if [ "${ISAAC_START_BG:-0}" = "1" ]; then
  nohup "$PY" isaac_core.py > isaac.out 2>&1 &
  CORE_PID=$!
  echo "[Isaac] Core PID: $CORE_PID"
  echo "$CORE_PID" > runtime/isaac.pid
  printf '%s\n' "$CORE_PID" > runtime/monitor.pid
  sleep 2
  tail -n 40 isaac.out || true
else
  exec "$PY" isaac_core.py
fi
