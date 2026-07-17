# Codespaces-Checkliste — Isaac weiterentwickeln

Kurzer Pfad für den **Haupt-Codespace** (Cloud-IDE, nicht 24/7-Server).

**Primär-URL:** https://isaac-main-qvvrvv7vg6xjc6x74.github.dev  
**Repo:** https://github.com/sco0rp88-ship-it/Isaac  
**One-click neu:** https://codespaces.new/sco0rp88-ship-it/Isaac?quickstart=1

Ausführlich: [`CODESPACES.md`](CODESPACES.md)

---

## 5 Schritte (Secrets → Rebuild → Start → Tests → Chat)

### 1) Secrets prüfen

Repo → **Settings → Secrets and variables → Codespaces**

| Secret | Free-Dev |
|--------|----------|
| `ACTIVE_PROVIDER` | **`gemini`** (ohne xAI-Credits) |
| `GOOGLE_API_KEY` / `GEMINI_API_KEY` | Pflicht für Gemini |
| `GROQ_API_KEY` | optional Fallback |
| `OPENROUTER_API_KEY` | optional Fallback |
| `XAI_API_KEY` | nur mit Credits |

Keine Keys in Git committen.

### 2) Rebuild (nach Secret-/Devcontainer-Änderungen)

Im Codespace: **⋯ (Codespaces) → Rebuild container**  
Warten bis `post-create` durch ist (venv, deps, sanity).

### 3) Kernel starten

```bash
bash .devcontainer/start-isaac.sh
```

Oder: **Terminal → Run Task → Isaac: Start Kernel**  
Dashboard: Port **8766** · Monitor WS: **8765**

### 4) Tests (Regression)

```bash
export ISAAC_DISABLE_VECTOR_MEMORY=1
.venv/bin/python -m py_compile \
  isaac_core.py executor.py low_complexity.py memory.py \
  relay.py logic.py watchdog.py task_checkpoint.py
.venv/bin/python sanity_check.py
.venv/bin/python -m unittest \
  tests_phase_a_stabilization \
  tests_state_io \
  tests_provider_configuration
```

Oder Tasks: **Isaac: Sanity Check** / **Isaac: Unit Tests**.

### 5) Chat smoke-test

Ohne LLM-Key (lokal):

- `Hallo Isaac` → Greeting  
- `Danke` → Acknowledgment  

Mit Gemini (Free):

- Normale Frage im Dashboard / Kernel  
- Bei Fehlern: `echo $ACTIVE_PROVIDER` und `echo ${GOOGLE_API_KEY:+set}` (Wert nicht loggen)

---

## Täglich weiterentwickeln

```bash
git pull origin main
# … Code ändern …
ISAAC_DISABLE_VECTOR_MEMORY=1 .venv/bin/python -m unittest \
  tests_phase_a_stabilization tests_state_io tests_provider_configuration -q
git checkout -b feature/kurz-name
git add -A && git commit -m "Kurz: was und warum"
git push -u origin HEAD
# gh pr create   # wenn gewünscht
```

Regeln: `AGENTS.md` — klein, validiert, Executor reklassifiziert nicht, normal chat ohne opportunistische Tools.

---

## Was im Codespace *nicht* erwartet wird

| Thema | Realität |
|-------|----------|
| 24/7 Isaac | Idle-Timeout (Free oft **30 min**); nach Idle neu starten |
| xAI/Grok gratis | braucht Credits → **gemini** nutzen |
| Ollama / lokales GPU | nicht im Free-CS |
| Termux / S8 / Android | externes Gerät, nicht diese VM |
| Vector Memory heavy | `ISAAC_DISABLE_VECTOR_MEMORY=1` (light) |
| Owner-Admin POSTs | nur aus Container-localhost / integriertem Terminal |

---

## Trouble schnell

| Problem | Fix |
|---------|-----|
| Keine LLM-Antwort | Secrets + Rebuild; `ACTIVE_PROVIDER=gemini` |
| Port 8766 zu | Kernel starten |
| `.venv` fehlt | `bash .devcontainer/post-create.sh` |
| Alte Secrets | Rebuild container |
| Idle disconnected | Codespace erneut öffnen / Start |

---

## Ein Terminal-Block (Copy-Paste)

```bash
# Nach Rebuild im Codespace:
export ISAAC_DISABLE_VECTOR_MEMORY=1
test -x .venv/bin/python || bash .devcontainer/post-create.sh
.venv/bin/python sanity_check.py
.venv/bin/python -m unittest \
  tests_phase_a_stabilization tests_state_io tests_provider_configuration -q
# Kernel (eigenes Terminal-Tab lassen laufen):
bash .devcontainer/start-isaac.sh
```

## Smoke-Suite (A–G + Digest + Render)

```bash
# Lokal / Codespace (ohne Secrets im Output):
ISAAC_DISABLE_VECTOR_MEMORY=1 python3 scripts/smoke_isaac.py

# Schnell ohne unittest:
python3 scripts/smoke_isaac.py --skip-unittest

# Live Render + Codespace-Ports (404 = soft, außer --strict-live):
python3 scripts/smoke_isaac.py \
  --render https://isaac-free.onrender.com \
  --codespace-host isaac-main-qvvrvv7vg6xjc6x74.github.dev \
  --codespace-ports 8766,8767
```
