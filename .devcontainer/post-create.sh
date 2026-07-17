#!/usr/bin/env bash
# Isaac Codespaces / Dev Container bootstrap
# Usage: post-create.sh [--update]
set -euo pipefail

MODE="${1:-create}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

log() { echo "[Isaac] $*"; }
warn() { echo "[Isaac] WARN: $*" >&2; }

log "Codespaces setup ($MODE) in $ROOT"

# ── Python venv ──────────────────────────────────────────────────────────────
if [ ! -x .venv/bin/python ]; then
  log "Erstelle .venv (Python $(python3 --version 2>/dev/null || true))"
  python3 -m venv .venv
fi

.venv/bin/pip install --upgrade pip setuptools wheel >/dev/null

log "Installiere requirements.txt …"
.venv/bin/pip install -r requirements.txt

# Optional free-cloud extras if present (non-fatal)
if [ -f requirements-free.txt ]; then
  .venv/bin/pip install -r requirements-free.txt 2>/dev/null || warn "requirements-free optional skipped"
fi

# ── Playwright (Browser-Tools; non-fatal in bare CI) ─────────────────────────
if [ "${ISAAC_SKIP_PLAYWRIGHT:-0}" != "1" ]; then
  log "Playwright Chromium …"
  if .venv/bin/python -c "import playwright" 2>/dev/null; then
    .venv/bin/playwright install-deps chromium 2>/dev/null \
      || sudo -n .venv/bin/playwright install-deps chromium 2>/dev/null \
      || warn "playwright system deps skipped (need sudo or preinstalled)"
    .venv/bin/playwright install chromium 2>/dev/null \
      || warn "playwright chromium install skipped"
  fi
fi

# ── Runtime dirs ─────────────────────────────────────────────────────────────
mkdir -p logs runtime workspace data

# ── .env from example + Codespaces secrets ───────────────────────────────────
if [ ! -f .env ]; then
  if [ -f .env.example ]; then
    cp .env.example .env
    log ".env aus .env.example erstellt"
  else
    cat > .env <<'EOF'
ISAAC_OWNER=Steffen
ACTIVE_PROVIDER=groq
ISAAC_DISABLE_VECTOR_MEMORY=1
MONITOR_PORT=8765
DASHBOARD_PORT=8766
MONITOR_HTTP_PORT=8766
EOF
    log ".env Minimal-Template erstellt"
  fi
fi

# Inject Codespaces / host secrets into .env without printing values
inject_secret() {
  local key="$1"
  local val="${!key:-}"
  [ -z "$val" ] && return 0
  if grep -qE "^${key}=" .env 2>/dev/null; then
    # portable in-place replace
    .venv/bin/python - "$key" "$val" <<'PY'
import sys, re, pathlib
key, val = sys.argv[1], sys.argv[2]
path = pathlib.Path(".env")
text = path.read_text(encoding="utf-8")
pat = re.compile(rf"^{re.escape(key)}=.*$", re.M)
if pat.search(text):
    text = pat.sub(f"{key}={val}", text, count=1)
else:
    text = text.rstrip() + f"\n{key}={val}\n"
path.write_text(text, encoding="utf-8")
PY
  else
    printf '\n%s=%s\n' "$key" "$val" >> .env
  fi
  log "Secret ${key} in .env übernommen (Wert nicht geloggt)"
}

inject_secret GROQ_API_KEY
inject_secret OPENROUTER_API_KEY
inject_secret GOOGLE_API_KEY
inject_secret GEMINI_API_KEY
inject_secret XAI_API_KEY
inject_secret GROK_API_KEY
inject_secret OPENAI_API_KEY
inject_secret COGNEE_API_KEY

# Non-secret overrides from Codespaces env
if [ -n "${ACTIVE_PROVIDER:-}" ]; then
  inject_secret ACTIVE_PROVIDER
fi
if [ -n "${ISAAC_OWNER:-}" ]; then
  inject_secret ISAAC_OWNER
fi

# Codespaces-friendly defaults if still empty
if ! grep -qE '^ACTIVE_PROVIDER=.+' .env 2>/dev/null || grep -qE '^ACTIVE_PROVIDER=$' .env 2>/dev/null; then
  if grep -qE '^ACTIVE_PROVIDER=' .env; then
    sed -i 's/^ACTIVE_PROVIDER=.*/ACTIVE_PROVIDER=groq/' .env 2>/dev/null \
      || .venv/bin/python -c "import pathlib,re;p=pathlib.Path('.env');t=p.read_text();p.write_text(re.sub(r'^ACTIVE_PROVIDER=.*','ACTIVE_PROVIDER=groq',t,flags=re.M))"
  fi
fi

# Force vector memory off in Codespaces by default (onnx/chroma heavy)
export ISAAC_DISABLE_VECTOR_MEMORY="${ISAAC_DISABLE_VECTOR_MEMORY:-1}"

# ── Validate ─────────────────────────────────────────────────────────────────
log "py_compile Kernmodule …"
.venv/bin/python -m py_compile \
  isaac_core.py executor.py low_complexity.py memory.py \
  relay.py logic.py watchdog.py task_checkpoint.py

log "sanity_check.py …"
.venv/bin/python sanity_check.py

if [ "$MODE" != "--update" ] && [ "$MODE" != "update" ]; then
  log "Unit tests (stabilization suite) …"
  ISAAC_DISABLE_VECTOR_MEMORY=1 .venv/bin/python -m unittest \
    tests_phase_a_stabilization \
    tests_state_io \
    tests_provider_configuration \
    -q || warn "Einige Tests fehlgeschlagen — Codespace ist trotzdem nutzbar"
fi

cat <<EOF

=== Isaac Codespaces bereit ===
1. Secrets (falls noch nicht gesetzt):
   Repo → Settings → Secrets and variables → Codespaces
   • GROQ_API_KEY      (empfohlen)  https://console.groq.com/keys
   • OPENROUTER_API_KEY (optional)
   • GOOGLE_API_KEY     (optional)

2. Isaac starten:
   bash .devcontainer/start-isaac.sh
   # oder VS Code Task: "Isaac: Start Kernel"

3. Dashboard: Port 8766 (auto-forward / Browser)
   WebSocket Monitor: Port 8765

4. Docs: docs/CODESPACES.md
EOF
