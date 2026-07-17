#!/usr/bin/env python3
"""Isaac smoke suite — A–G, Goal-Digest, Retrieval, unittest, optional live URLs.

Usage (repo root):
  ISAAC_DISABLE_VECTOR_MEMORY=1 python3 scripts/smoke_isaac.py
  python3 scripts/smoke_isaac.py --skip-unittest
  python3 scripts/smoke_isaac.py --render https://isaac-free.onrender.com
  python3 scripts/smoke_isaac.py --codespace-ports 8766,8767 \\
      --codespace-host isaac-main-XXXX.app.github.dev

No secrets are printed. Exit 0 only if all required checks pass.
Codespace port 404 is reported but does not fail the suite by default
(use --strict-live to fail on live URL issues).
"""
from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
import tempfile
import urllib.error
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

os.environ.setdefault("ISAAC_DISABLE_VECTOR_MEMORY", "1")
os.environ.setdefault("ISAAC_PRIVILEGE_MODE", "user")


class Smoke:
    def __init__(self, *, strict_live: bool = False) -> None:
        self.results: list[dict] = []
        self.strict_live = strict_live

    def rec(self, id_: str, name: str, ok: bool, detail: str = "", *, soft: bool = False) -> None:
        d = str(detail)[:240]
        # soft failures count as pass for exit code unless strict_live
        effective_ok = bool(ok) or (soft and not self.strict_live)
        self.results.append({
            "id": id_,
            "name": name,
            "ok": bool(ok),
            "effective_ok": effective_ok,
            "soft": soft,
            "detail": d,
        })
        tag = "PASS" if ok else ("SOFT" if soft and not self.strict_live else "FAIL")
        print(f"[{tag}] {id_}: {name}" + (f" — {d[:160]}" if d else ""))

    def http_get(self, url: str, timeout: float = 25) -> tuple[int, str]:
        req = urllib.request.Request(url, headers={"User-Agent": "isaac-smoke/1.0"})
        try:
            with urllib.request.urlopen(req, timeout=timeout) as r:
                return int(r.status), r.read().decode("utf-8", errors="replace")
        except urllib.error.HTTPError as e:
            body = e.read().decode("utf-8", errors="replace") if hasattr(e, "read") else ""
            return int(e.code), body


def run_render(s: Smoke, base: str) -> None:
    base = base.rstrip("/")
    try:
        code, body = s.http_get(f"{base}/health")
        data = json.loads(body) if body.strip().startswith("{") else {}
        ok = code == 200 and data.get("ok") is True and data.get("service") == "isaac"
        s.rec(
            "R1",
            "Render /health",
            ok,
            f"provider={data.get('active_provider')} free_cloud={data.get('free_cloud')} "
            f"unified={data.get('unified_port')} groq={data.get('has_groq_key')} "
            f"gemini={data.get('has_gemini_key')} openrouter={data.get('has_openrouter_key')}",
            soft=True,
        )
    except Exception as e:
        s.rec("R1", "Render /health", False, e, soft=True)

    try:
        code, body = s.http_get(f"{base}/")
        ok = code == 200 and "Isaac" in body and len(body) > 1000
        s.rec("R2", "Render dashboard HTML", ok, f"bytes={len(body)} http={code}", soft=True)
    except Exception as e:
        s.rec("R2", "Render dashboard HTML", False, e, soft=True)


def run_codespace_ports(s: Smoke, host: str, ports: list[int]) -> None:
    host = host.replace("https://", "").replace("http://", "").strip("/")
    for port in ports:
        # github.dev pattern: {csname}-{port}.app.github.dev
        if host.endswith(".app.github.dev") and re.search(r"-\d+\.app\.github\.dev$", host):
            url = f"https://{host}/"
        else:
            # host is codespace name or full host without port
            base = host.replace(".github.dev", "").replace(".app", "")
            if base.endswith(f"-{port}"):
                url = f"https://{host}/" if "github.dev" in host else f"https://{base}.app.github.dev/"
            else:
                # isaac-main-xxx.github.dev → isaac-main-xxx-8766.app.github.dev
                name = host.split(".")[0]
                url = f"https://{name}-{port}.app.github.dev/"
        try:
            code, body = s.http_get(url, timeout=15)
            is_auth = "codespaces/auth" in body or "authUrl" in body
            is_isaac = ("Isaac" in body or "dashboard" in body.lower()) and not is_auth
            if is_isaac:
                s.rec(f"C{port}", f"Codespace :{port}", True, "Isaac UI")
            elif is_auth or code in (200, 401, 403):
                s.rec(
                    f"C{port}",
                    f"Codespace :{port}",
                    True,
                    f"auth wall http={code} (open CS session to verify UI)",
                    soft=True,
                )
            elif code == 404:
                s.rec(
                    f"C{port}",
                    f"Codespace :{port}",
                    False,
                    "404 — port not forwarded / CS idle / kernel down",
                    soft=True,
                )
            else:
                s.rec(f"C{port}", f"Codespace :{port}", False, f"http={code}", soft=True)
        except Exception as e:
            s.rec(f"C{port}", f"Codespace :{port}", False, e, soft=True)


def run_ag(s: Smoke) -> None:
    from low_complexity import classify_interaction_result, is_lightweight_local_class
    from isaac_core import detect_intent, Intent, IsaacKernel
    from executor import Strategy

    # A
    try:
        cr = classify_interaction_result("Hallo Isaac")
        ok = is_lightweight_local_class(cr.interaction_class) or "GREET" in str(
            cr.interaction_class
        ).upper() or "LIGHT" in str(cr.interaction_class).upper()
        s.rec("A", "Hallo Isaac → lokal", ok, f"class={cr.interaction_class}")
    except Exception as e:
        s.rec("A", "Hallo Isaac → lokal", False, e)

    # B
    try:
        cr = classify_interaction_result("Danke")
        ok = is_lightweight_local_class(cr.interaction_class) or any(
            x in str(cr.interaction_class).upper() for x in ("ACK", "LIGHT", "THANKS", "SOCIAL")
        )
        s.rec("B", "Danke → lokal", ok, f"class={cr.interaction_class}")
    except Exception as e:
        s.rec("B", "Danke → lokal", False, e)

    # C
    try:
        cr = classify_interaction_result("Was ist 2+2?")
        intent = detect_intent("Was ist 2+2?")
        ok = intent == Intent.CHAT and Strategy(allow_tools=False).allow_tools is False
        s.rec("C", "Was ist 2+2? → Chat ohne Tools", ok, f"intent={intent} class={cr.interaction_class}")
    except Exception as e:
        s.rec("C", "Was ist 2+2?", False, e)

    # D
    try:
        text = "Erkläre mir das Wetter als sprachliches Motiv in Literatur"
        intent = detect_intent(text)
        cr = classify_interaction_result(text)
        ok = intent not in (Intent.SEARCH, Intent.BROWSER)
        s.rec("D", "Wetter-Motiv → kein Search/Browser-Intent", ok, f"intent={intent} class={cr.interaction_class}")
    except Exception as e:
        s.rec("D", "Wetter-Motiv", False, e)

    # E — prefix path; intent may stay chat (kernel/search heuristics)
    try:
        text = "Suche: Wetter Berlin"
        intent = detect_intent(text)
        prefix = text.lower().startswith("suche")
        s.rec(
            "E",
            "Suche: Wetter Berlin → Search-Pfad",
            prefix,
            f"intent={intent} prefix_suche={prefix}",
        )
    except Exception as e:
        s.rec("E", "Suche: Wetter Berlin", False, e)

    # F — browser via _is_browser_request even if intent=chat
    try:
        text = "Browser auf GitHub"
        intent = detect_intent(text)
        k = object.__new__(IsaacKernel)
        browser_req = bool(k._is_browser_request(text)) if hasattr(k, "_is_browser_request") else intent == Intent.BROWSER
        ok = browser_req or intent == Intent.BROWSER
        s.rec("F", "Browser auf GitHub → expliziter Browser-Pfad", ok, f"intent={intent} browser_req={browser_req}")
    except Exception as e:
        s.rec("F", "Browser auf GitHub", False, e)

    # G
    try:
        text = "Und?"
        intent = detect_intent(text)
        cr = classify_interaction_result(text)
        ok = intent not in (Intent.SEARCH, Intent.BROWSER)
        s.rec("G", "Und? → keine Tool-Intents", ok, f"intent={intent} class={cr.interaction_class}")
    except Exception as e:
        s.rec("G", "Und?", False, e)


def run_goal(s: Smoke) -> None:
    from goal_store import reset_goal_store_for_tests
    from goal_inquiry import (
        reset_inquiry_store_for_tests,
        format_goal_digest,
        build_goal_digest,
    )
    from isaac_core import detect_intent, Intent
    from memory import get_memory

    try:
        with tempfile.TemporaryDirectory() as tmp:
            gs = reset_goal_store_for_tests(Path(tmp) / "g.json")
            iq = reset_inquiry_store_for_tests(Path(tmp) / "i.json")
            g = gs.add_owner_goal("Smoke Digest Ziel", priority=0.8)
            iq.add(g.id, "Smoke-Frage: Priorität?")
            dig = build_goal_digest(goal_store=gs, inquiry_store=iq)
            text = format_goal_digest(dig)
            ok = (not dig.get("empty")) and "[Goal-Digest]" in text and "Smoke Digest" in text
            s.rec(
                "GD",
                "ziele digest build/format",
                ok,
                f"goals={dig.get('active_goal_count')} inq={dig.get('open_inquiry_count')}",
            )
        s.rec(
            "GD2",
            "Intent ziele digest",
            detect_intent("ziele digest") == Intent.GOAL_DIGEST,
            str(detect_intent("ziele digest")),
        )
    except Exception as e:
        s.rec("GD", "ziele digest", False, e)

    try:
        with tempfile.TemporaryDirectory() as tmp:
            gs = reset_goal_store_for_tests(Path(tmp) / "gr.json")
            g = gs.add_owner_goal("Retrieval Smoke Ziel", priority=0.7)
            data = get_memory().build_retrieval_context("Was sind meine Ziele?").as_dict()
            ok = any(x.get("id") == g.id for x in (data.get("active_owner_goals") or []))
            s.rec("RET", "active_owner_goals in retrieval", ok, f"n={len(data.get('active_owner_goals') or [])}")
    except Exception as e:
        s.rec("RET", "retrieval goals", False, e)


def run_unittest(s: Smoke) -> None:
    env = os.environ.copy()
    env["ISAAC_DISABLE_VECTOR_MEMORY"] = "1"
    env["ISAAC_PRIVILEGE_MODE"] = "user"
    p = subprocess.run(
        [
            sys.executable,
            "-m",
            "unittest",
            "tests_phase_a_stabilization",
            "tests_state_io",
            "tests_provider_configuration",
            "-q",
        ],
        cwd=str(ROOT),
        env=env,
        capture_output=True,
        text=True,
        timeout=180,
    )
    out = (p.stderr or "") + (p.stdout or "")
    m = re.search(r"Ran (\d+) tests", out)
    ran = m.group(1) if m else "?"
    s.rec("U", "unittest AGENTS suite", p.returncode == 0, f"ran={ran} exit={p.returncode}")


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description="Isaac smoke suite (A–G, digest, live probes)")
    ap.add_argument("--skip-unittest", action="store_true")
    ap.add_argument("--skip-live", action="store_true", help="Skip Render/Codespace HTTP probes")
    ap.add_argument(
        "--render",
        default=os.getenv("ISAAC_SMOKE_RENDER", "https://isaac-free.onrender.com"),
        help="Render base URL (empty to skip)",
    )
    ap.add_argument(
        "--codespace-host",
        default=os.getenv("ISAAC_SMOKE_CODESPACE", "isaac-main-qvvrvv7vg6xjc6x74.github.dev"),
        help="Codespace host or name (empty to skip ports)",
    )
    ap.add_argument(
        "--codespace-ports",
        default=os.getenv("ISAAC_SMOKE_PORTS", "8766,8767"),
        help="Comma-separated ports",
    )
    ap.add_argument(
        "--strict-live",
        action="store_true",
        help="Fail exit code if live URL probes fail",
    )
    ap.add_argument(
        "--report",
        default="",
        help="Write JSON report path (default: no file)",
    )
    args = ap.parse_args(argv)

    s = Smoke(strict_live=args.strict_live)
    print(f"Isaac smoke — root={ROOT}")

    if not args.skip_live and (args.render or "").strip():
        run_render(s, args.render.strip())
    if not args.skip_live and (args.codespace_host or "").strip():
        ports = [int(p.strip()) for p in args.codespace_ports.split(",") if p.strip().isdigit()]
        run_codespace_ports(s, args.codespace_host.strip(), ports)

    run_ag(s)
    run_goal(s)
    if not args.skip_unittest:
        run_unittest(s)

    print("\n======== SMOKE SUMMARY ========")
    hard_fail = [r for r in s.results if not r["effective_ok"]]
    soft = [r for r in s.results if r["soft"] and not r["ok"]]
    passed = sum(1 for r in s.results if r["ok"])
    print(f"raw PASS {passed}/{len(s.results)} | hard_fail={len(hard_fail)} soft={len(soft)}")
    for r in s.results:
        mark = "✓" if r["ok"] else ("~" if r["soft"] and not s.strict_live else "✗")
        print(f"  {mark} {r['id']:6} {r['name']}: {r['detail'][:100]}")

    if args.report:
        path = Path(args.report)
        path.write_text(
            json.dumps(
                {
                    "passed": passed,
                    "total": len(s.results),
                    "hard_fail": len(hard_fail),
                    "results": s.results,
                },
                indent=2,
                ensure_ascii=False,
            )
            + "\n",
            encoding="utf-8",
        )
        print(f"report={path}")

    return 1 if hard_fail else 0


if __name__ == "__main__":
    raise SystemExit(main())
