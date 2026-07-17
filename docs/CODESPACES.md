# Isaac in GitHub Codespaces

One-click cloud dev environment for the Isaac kernel (Python 3.12, Dashboard, Tests).

## Open

**5-Minuten-Checkliste:** [`CODESPACES_CHECKLISTE.md`](CODESPACES_CHECKLISTE.md)

**Haupt-Codespace:** https://isaac-main-qvvrvv7vg6xjc6x74.github.dev


[![Open in GitHub Codespaces](https://github.com/codespaces/badge.svg)](https://codespaces.new/sco0rp88-ship-it/Isaac?quickstart=1)

Or: **Code → Codespaces → Create codespace on `main`**.

Machine recommendation: **2-core / 8 GB** (or higher). The devcontainer asks for at least 2 CPUs / 4 GB.

## First start (what happens)

| Phase | Script | Effect |
|-------|--------|--------|
| Create | `.devcontainer/post-create.sh` | venv, `requirements.txt`, Playwright Chromium, `.env`, `sanity_check`, unit tests |
| Start | `.devcontainer/post-start.sh` | re-sync Codespaces secrets into `.env` |
| Run | `.devcontainer/start-isaac.sh` or Task **Isaac: Start Kernel** | `isaac_core.py` + Dashboard |

Ports (auto-forwarded):

| Port | Service |
|------|---------|
| **8766** | Dashboard (HTTP) — opens in browser |
| **8765** | Monitor WebSocket |

## Secrets (required for LLM chat)

**Do not commit API keys.** Set **Codespaces secrets**:

Repository → **Settings → Secrets and variables → Codespaces**

| Secret | Required | Where |
|--------|----------|--------|
| `GROQ_API_KEY` | **Recommended** (free) | https://console.groq.com/keys |
| `XAI_API_KEY` / `GROK_API_KEY` | Optional (Grok) | https://console.x.ai |
| `OPENROUTER_API_KEY` | Optional | https://openrouter.ai/keys |
| `GOOGLE_API_KEY` / `GEMINI_API_KEY` | Optional | https://aistudio.google.com/apikey |
| `ACTIVE_PROVIDER` | Optional | `groq` (default) / `openrouter` / `gemini` |
| `ISAAC_OWNER` | Optional | Default owner label |

The `devcontainer.json` **recommends** these secrets at codespace creation (GitHub UI prompt).

After adding secrets: **Codespaces → ⋯ → Rebuild container** (or restart) so env is injected.

`post-create` / `post-start` copy secret values into local `.env` (gitignored) without logging them.

## Daily workflow

```bash
# Start kernel + dashboard
bash .devcontainer/start-isaac.sh

# Or VS Code / Codespaces UI
# Terminal → Run Task → "Isaac: Start Kernel"
# Debug: F5 → "Isaac: Kernel (isaac_core.py)"
```

Validation (same as CI / AGENTS.md):

```bash
export ISAAC_DISABLE_VECTOR_MEMORY=1
.venv/bin/python -m py_compile isaac_core.py executor.py low_complexity.py memory.py relay.py logic.py watchdog.py task_checkpoint.py
.venv/bin/python sanity_check.py
.venv/bin/python -m unittest tests_phase_a_stabilization tests_state_io tests_provider_configuration
```

Lightweight paths work **without** any API key:

- `Hallo Isaac` → local greeting  
- `Danke` → local acknowledgment  

Normal chat needs a provider key (`GROQ_API_KEY` recommended in Codespaces).

## Security notes

- `.env`, `data/`, logs are **gitignored** — do not force-add them.
- Sensitive dashboard **owner/updater** POSTs stay **localhost-only** by design (`monitor_server.py`). In Codespaces use the integrated terminal for privileged ops, not the public forwarded URL for admin actions.
- `ISAAC_BIND_HOST=0.0.0.0` is set by `start-isaac.sh` so port forwarding works; that is for the Codespace VM, not the public internet.
- Vector memory is **off by default** (`ISAAC_DISABLE_VECTOR_MEMORY=1`) to keep images light (no heavy onnx/chroma runtime).

## VS Code Tasks & Debug

| Task | Purpose |
|------|---------|
| Isaac: Start Kernel | Run kernel |
| Isaac: Sanity Check | `sanity_check.py` |
| Isaac: Unit Tests | Stabilization suite |
| Isaac: py_compile Core | Syntax gate |
| Isaac: Eval Harness | `evals.eval_runner` |
| Isaac: Bootstrap | Re-run post-create |

Launch configurations: **Isaac: Kernel**, Sanity Check, Unittest current file.

## Prebuilds

Workflow: `.github/workflows/codespaces-prebuild.yml`  
Triggers on changes to `.devcontainer/**`, `requirements*.txt`, and `main` pushes so create-time is faster.

Enable prebuilds in the GitHub UI if needed:

**Settings → Codespaces → Prebuilds → Set up prebuild** (branch `main`, path `.devcontainer/devcontainer.json`).

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| No LLM answers | Set `GROQ_API_KEY` Codespaces secret → Rebuild |
| Port 8766 not open | Start kernel; check **PORTS** panel; `bash .devcontainer/start-isaac.sh` |
| `.venv` missing | `bash .devcontainer/post-create.sh` |
| Playwright errors | Optional; `ISAAC_SKIP_PLAYWRIGHT=1` on bootstrap, or re-run install |
| Tests fail on chroma/onnx | Ensure `ISAAC_DISABLE_VECTOR_MEMORY=1` |
| Secrets not in env | Rebuild container after adding secrets |

## Architecture reminder

Codespaces is a **dev/runtime host**, not a redesign of Isaac:

```
classify → retrieve → strategy → task → execute → evaluate → memory update
```

Executor does not reclassify. Normal chat does not opportunistically call tools. See `AGENTS.md`.
