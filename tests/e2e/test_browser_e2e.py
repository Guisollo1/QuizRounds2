#!/usr/bin/env python3
"""QuizRounds2 browser E2E gate.

Runs the real simulator UI in Chromium. It deliberately uses the local simulator so
CI does not depend on a live Supabase project, secrets, Wi-Fi, or external services.
This complements (not replaces) the deterministic state/realtime validators.
"""
from __future__ import annotations

import contextlib
import http.server
import os
import socket
import sys
import threading
import shutil
from pathlib import Path

BUILD = "3.68-r86"
EXPECTED_SCENARIOS = 4


def fail(message: str) -> None:
    raise AssertionError(message)


def self_check(site_root: Path) -> int:
    required = [
        "simulator.html",
        f"assets/js/simulator-v{BUILD}.js",
        f"assets/js/motion-v{BUILD}.js",
        f"assets/css/simulator-v{BUILD}.css",
        "assets/vendor/qr-bundle.js",
        "version.json",
    ]
    missing = [x for x in required if not (site_root / x).exists()]
    if missing:
        print("E2E SELF-CHECK: REPROVADO")
        for item in missing:
            print(f" - ausente: {item}")
        return 1
    html = (site_root / "simulator.html").read_text(encoding="utf-8")
    selectors = [
        'id="simLoginForm"', 'id="simApp"', 'id="runStabilityBtn"',
        'id="stabilityBadge"', 'id="prepareSimBtn"', 'id="startSimBtn"',
        'id="openPlayerPreviewBtn"', 'id="joinTestPlayerBtn"',
        'id="disconnectTestPlayerBtn"', 'id="reopenTestPlayerBtn"',
        'id="projectorFinal"', 'id="simStateBadge"',
    ]
    absent = [s for s in selectors if s not in html]
    if absent:
        print("E2E SELF-CHECK: REPROVADO")
        for item in absent:
            print(f" - seletor ausente: {item}")
        return 1
    print(f"E2E SELF-CHECK: APROVADO — {BUILD} / {EXPECTED_SCENARIOS} cenários de navegador definidos")
    return 0


class QuietHandler(http.server.SimpleHTTPRequestHandler):
    def log_message(self, *_args) -> None:
        pass

    def end_headers(self) -> None:
        self.send_header("Cache-Control", "no-store, no-cache, must-revalidate")
        super().end_headers()


@contextlib.contextmanager
def static_server(root: Path):
    previous = os.getcwd()
    os.chdir(root)
    try:
        with socket.socket() as s:
            s.bind(("127.0.0.1", 0))
            port = s.getsockname()[1]
        server = http.server.ThreadingHTTPServer(("127.0.0.1", port), QuietHandler)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        try:
            yield f"http://127.0.0.1:{port}"
        finally:
            server.shutdown()
            server.server_close()
            thread.join(timeout=3)
    finally:
        os.chdir(previous)


def install_error_watch(page, label: str):
    errors: list[str] = []
    page.on("pageerror", lambda exc: errors.append(f"pageerror: {exc}"))
    page.on("console", lambda msg: errors.append(f"console.error: {msg.text}") if msg.type == "error" else None)
    return errors


def login(page):
    page.locator("#simLoginUser").fill("admin")
    page.locator("#simLoginPassword").fill("quiz123")
    page.locator('#simLoginForm button[type="submit"]').click()
    page.locator("#simApp").wait_for(state="visible", timeout=5000)


def scenario_auth_and_logic(browser, base: str):
    page = browser.new_page(viewport={"width": 1440, "height": 1000})
    errors = install_error_watch(page, "auth_logic")
    page.goto(f"{base}/simulator.html?qr_build={BUILD}", wait_until="networkidle")
    if BUILD not in page.title():
        fail(f"simulator title não contém {BUILD}")
    page.locator("#simLoginPassword").fill("senha-errada")
    page.locator('#simLoginForm button[type="submit"]').click()
    page.locator("#simLoginMsg").wait_for(state="visible")
    if "inválidos" not in page.locator("#simLoginMsg").inner_text().lower():
        fail("login inválido não foi rejeitado")
    login(page)
    page.locator('.sim-tab[data-tab="tests"]').click()
    page.locator("#runStabilityBtn").click()
    page.locator("#stabilityBadge").wait_for(state="visible")
    if page.locator("#stabilityBadge").inner_text().strip() != "SUÍTE LOCAL APROVADA":
        fail(f"suíte local não aprovou: {page.locator('#stabilityBadge').inner_text()}")
    if page.locator(".stability-check.fail").count() != 0:
        fail("suíte local exibiu verificações com falha")
    if errors:
        fail("erros de browser em auth/logic: " + " | ".join(errors[:5]))
    page.close()


def scenario_full_event_100(browser, base: str):
    page = browser.new_page(viewport={"width": 1600, "height": 1000})
    errors = install_error_watch(page, "full_event")
    page.goto(
        f"{base}/simulator.html?autorun=1&fulltest=1&bots=100&qr_build={BUILD}",
        wait_until="domcontentloaded",
    )
    page.locator("#simStateBadge").wait_for(state="visible", timeout=5000)
    # Full test deliberately runs real timers/DOM updates; 45 s leaves headroom on slower CI runners.
    page.wait_for_function(
        "() => document.querySelector('#simStateBadge')?.textContent?.trim() === 'FINISHED'",
        timeout=45000,
    )
    log = page.locator("#simLog").inner_text()
    if "SIMULAÇÃO LOCAL FINALIZADA" not in log:
        fail("fluxo completo não registrou finalização")
    if page.locator("#stabilityBadge").inner_text().strip() != "SUÍTE LOCAL APROVADA":
        fail("suíte determinística não aprovou durante o fluxo completo")
    if not page.locator("#projectorFinal").is_visible():
        fail("projetor final não ficou visível")
    if page.locator("#projectorFinalRanking li").count() < 5:
        fail("ranking final não renderizou pelo menos 5 posições")
    if errors:
        fail("erros de browser no fluxo completo: " + " | ".join(errors[:5]))
    page.close()


def scenario_player_reconnect(browser, base: str):
    page = browser.new_page(viewport={"width": 1440, "height": 1000})
    errors = install_error_watch(page, "player_reconnect")
    page.goto(f"{base}/simulator.html?qr_build={BUILD}", wait_until="networkidle")
    login(page)
    page.locator('.sim-tab[data-tab="config"]').click()
    page.locator("#simSpeed").select_option("10")
    page.locator("#prepareSimBtn").click()
    page.wait_for_function("() => document.querySelector('#simStateBadge')?.textContent?.trim() === 'LOBBY'", timeout=5000)
    page.locator("#openPlayerPreviewBtn").click()
    page.locator("#testPlayerPin").fill("482731")
    page.locator("#testPlayerName").fill("Jogador E2E")
    page.locator("#joinTestPlayerBtn").click()
    page.locator("#phoneLobby").wait_for(state="visible", timeout=3000)
    if page.locator("#phonePlayerName").inner_text().strip() != "Jogador E2E":
        fail("nome do jogador não foi preservado")
    page.locator("#disconnectTestPlayerBtn").click()
    page.locator("#phoneDisconnected").wait_for(state="visible", timeout=3000)
    page.locator("#reopenTestPlayerBtn").click()
    page.locator("#phoneLobby").wait_for(state="visible", timeout=3000)
    page.locator("#startSimBtn").click()
    page.wait_for_function("() => document.querySelector('#simStateBadge')?.textContent?.trim() === 'RUNNING'", timeout=5000)
    page.locator("#phoneQuestion").wait_for(state="visible", timeout=3000)
    if page.locator("#phoneChoiceAnswers button").count() == 0:
        fail("primeiro round não renderizou alternativas no celular")
    page.locator("#phoneChoiceAnswers button").first.click()
    page.locator("#closeSimRoundBtn").click()
    page.wait_for_function("() => document.querySelector('#simStateBadge')?.textContent?.trim() === 'RESULT'", timeout=3000)
    page.locator("#phoneResult").wait_for(state="visible", timeout=3000)
    if errors:
        fail("erros de browser no reconnect: " + " | ".join(errors[:5]))
    page.close()


def scenario_mobile_layout(browser, base: str):
    page = browser.new_page(viewport={"width": 390, "height": 844}, device_scale_factor=1)
    errors = install_error_watch(page, "mobile")
    page.goto(f"{base}/simulator.html?qr_build={BUILD}", wait_until="networkidle")
    card = page.locator("#simLoginView .sim-login-card").bounding_box()
    if not card:
        fail("card de login móvel não renderizou")
    if card["width"] > 390 + 2:
        fail(f"card de login excede viewport móvel: {card['width']}")
    login(page)
    page.locator("#openPlayerPreviewBtn").click()
    drawer = page.locator("#playerPreviewDrawer")
    drawer.wait_for(state="visible", timeout=3000)
    box = drawer.bounding_box()
    if not box or box["width"] > 390 + 2:
        fail("drawer do celular não cabe no viewport móvel")
    if errors:
        fail("erros de browser no layout móvel: " + " | ".join(errors[:5]))
    page.close()


def run(site_root: Path) -> int:
    try:
        from playwright.sync_api import sync_playwright
    except Exception as exc:
        print(f"E2E BROWSER: REPROVADO — Playwright não instalado ({exc})")
        return 2

    scenarios = [
        ("autenticação + suíte lógica", scenario_auth_and_logic),
        ("evento completo 100 jogadores", scenario_full_event_100),
        ("jogador + reconexão + resposta", scenario_player_reconnect),
        ("viewport móvel", scenario_mobile_layout),
    ]
    passed = 0
    with static_server(site_root) as base, sync_playwright() as p:
        explicit = os.environ.get("PLAYWRIGHT_CHROMIUM_EXECUTABLE_PATH", "").strip()
        candidates = [explicit, shutil.which("chromium"), shutil.which("chromium-browser"), shutil.which("google-chrome"), shutil.which("google-chrome-stable")]
        executable = next((x for x in candidates if x and Path(x).exists()), None)
        launch_kwargs = {"headless": True}
        if executable:
            launch_kwargs["executable_path"] = executable
            launch_kwargs["args"] = ["--no-sandbox"]
        browser = p.chromium.launch(**launch_kwargs)
        try:
            for name, fn in scenarios:
                try:
                    fn(browser, base)
                    passed += 1
                    print(f"✓ E2E {name}")
                except Exception as exc:
                    print(f"✗ E2E {name}: {exc}")
                    raise
        finally:
            browser.close()
    print(f"E2E BROWSER: APROVADO ({passed}/{len(scenarios)} cenários, Chromium real) — {BUILD}")
    return 0


def main() -> int:
    args = sys.argv[1:]
    if args and args[0] == "--self-check":
        root = Path(args[1] if len(args) > 1 else ".").resolve()
        return self_check(root)
    root = Path(args[0] if args else "_site").resolve()
    if not root.exists():
        print(f"E2E BROWSER: REPROVADO — diretório ausente: {root}")
        return 1
    return run(root)


if __name__ == "__main__":
    raise SystemExit(main())
