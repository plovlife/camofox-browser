#!/usr/bin/env python3
# Camofox Gradio-Space Launcher: richtet Node ein, installiert die App,
# holt den Browser (falls postinstall ihn nicht geholt hat) und startet
# REST-API + MCP-Bridge(n) + Reverse-Proxy auf 7860. Nur Python-Stdlib.
#
# Aufruf: launcher.py <repo-pfad>  (kommt von app.py; ohne Arg = cwd)
# WICHTIG: Der Proxy-Port heisst APP_PORT, NIEMALS PORT — Server und MCP
# lesen $PORT als Fallback und wuerden sonst mit dem Proxy kollidieren.
import os
import stat
import subprocess
import sys
import tarfile
import time
import urllib.request
import zipfile

NODE_VERSION = "v22.22.3"
NODE_URL = f"https://nodejs.org/dist/{NODE_VERSION}/node-{NODE_VERSION}-linux-x64.tar.xz"
# Fallback-Browser (identisch zu /Dockerfile) — nur falls der postinstall-Fetch
# (immer kompatibel zur camoufox-js-Lib) scheitern sollte.
CAMOUFOX_VERSION = "135.0.1"
CAMOUFOX_RELEASE = "beta.24"
CAMOUFOX_URL = (
    "https://github.com/daijro/camoufox/releases/download/"
    f"v{CAMOUFOX_VERSION}-{CAMOUFOX_RELEASE}/"
    f"camoufox-{CAMOUFOX_VERSION}-{CAMOUFOX_RELEASE}-lin.x86_64.zip"
)
SUPERGATEWAY = "supergateway@3"
APP_PORT = os.environ.get("APP_PORT", "7860")

HOME = os.path.expanduser("~")
WORK = os.path.join(HOME, "work")
REPO = sys.argv[1] if len(sys.argv) > 1 else os.getcwd()
NODE_DIR = os.path.join(WORK, "node")
NODE = os.path.join(NODE_DIR, "bin", "node")
NPM = os.path.join(NODE_DIR, "bin", "npm")


def log(msg):
    print(f"[launcher] {msg}", flush=True)


def run(cmd, **kw):
    log("+ " + " ".join(cmd))
    return subprocess.run(cmd, check=False, **kw)  # noqa: PLW1510 - Returncode wird geprueft


def download(url, dest, retries=3):
    for i in range(1, retries + 1):
        try:
            log(f"lade {url.split('/')[-1]} (Versuch {i}) ...")
            urllib.request.urlretrieve(url, dest)
            return
        except Exception as e:  # noqa: BLE001 - Retry-Log
            log(f"FEHLER Versuch {i}: {e}")
            if i == retries:
                raise
            time.sleep(5)


def main():
    if not os.environ.get("CAMOFOX_ACCESS_KEY", "").strip():
        log("FEHLER: CAMOFOX_ACCESS_KEY fehlt! Space Settings -> Secrets setzen (ANLEITUNG Schritt 4).")
        sys.exit(1)

    env = dict(os.environ)
    env["PATH"] = f"{NODE_DIR}/bin:{HOME}/.local/bin:" + env.get("PATH", "")
    env["HOME"] = HOME
    env["npm_config_cache"] = os.path.join(WORK, "npm-cache")

    # 1) Node.js (Binary-Tarball, kein apt/root noetig)
    if not os.path.exists(NODE):
        os.makedirs(WORK, exist_ok=True)
        tpath = os.path.join(WORK, "node.tar.xz")
        download(NODE_URL, tpath)
        log("entpacke Node ...")
        with tarfile.open(tpath, "r:xz") as t:
            t.extractall(WORK)
        want = os.path.join(WORK, f"node-{NODE_VERSION}-linux-x64")
        if os.path.isdir(NODE_DIR):
            import shutil

            shutil.rmtree(NODE_DIR)
        os.rename(want, NODE_DIR)
        os.remove(tpath)
    r = run([NODE, "--version"], capture_output=True, text=True, env=env)
    if r.returncode != 0:
        log(f"FEHLER: Node startet nicht: {(r.stderr or '').strip()}")
        sys.exit(1)
    log(f"Node {(r.stdout or '').strip()} bereit ✅")

    # 2) npm install (postinstall laedt dabei automatisch den passenden Browser)
    log("npm ci (installiert App + laedt Browser, dauert ein paar Minuten) ...")
    r = run([NPM, "ci", "--omit=dev", "--no-audit", "--no-fund"], cwd=REPO, env=env)
    if r.returncode != 0:
        log("npm ci fehlgeschlagen — Fallback ohne Build-Skripte ...")
        r = run(
            [NPM, "ci", "--omit=dev", "--no-audit", "--no-fund", "--ignore-scripts"],
            cwd=REPO,
            env=env,
        )
        if r.returncode != 0:
            log("FEHLER: npm ci scheitert auch ohne Skripte. Log oben lesen + mir schicken.")
            sys.exit(1)

    # 3) Browser da? Sonst pinned Fallback-Download (~650 MB, ohne GitHub-API)
    cache = os.path.join(HOME, ".cache", "camoufox")
    if not os.path.exists(os.path.join(cache, "version.json")):
        log("postinstall hat den Browser nicht geholt — manueller Fallback-Download ...")
        os.makedirs(cache, exist_ok=True)
        zpath = os.path.join(WORK, "camoufox.zip")
        download(CAMOUFOX_URL, zpath)
        with zipfile.ZipFile(zpath) as z:
            z.extractall(cache)
        # zipfile erhaelt keine Exec-Bits → wie im Dockerfile alles ausfuehrbar machen
        for root, _dirs, files in os.walk(cache):
            for f in files:
                p = os.path.join(root, f)
                os.chmod(p, os.stat(p).st_mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)
        with open(os.path.join(cache, "version.json"), "w") as fh:
            fh.write(f'{{"version":"{CAMOUFOX_VERSION}","release":"{CAMOUFOX_RELEASE}"}}')
        os.remove(zpath)
        if os.path.exists(os.path.join(cache, "camoufox-bin")):
            log("Browser-Fallback fertig ✅")
        else:
            log("FEHLER: camoufox-bin fehlt auch nach Fallback. Log oben lesen + mir schicken.")
            sys.exit(1)
    else:
        log("Browser ist da ✅ (via postinstall)")

    # 4) supergateway: macht aus dem MCP-stdio-Server einen HTTP-MCP-Server
    run([NPM, "install", "-g", "--prefix", os.path.join(HOME, ".local"), SUPERGATEWAY], env=env)

    # 5) camofox REST starten + auf /health warten (nur Loopback!)
    srv = dict(env)
    srv.update(
        {
            "CAMOFOX_BIND_HOST": "127.0.0.1",
            "CAMOFOX_PORT": "9377",
            "CAMOFOX_CRASH_REPORT_ENABLED": os.environ.get("CAMOFOX_CRASH_REPORT_ENABLED", "false"),
            "MAX_SESSIONS": os.environ.get("MAX_SESSIONS", "3"),
            "MAX_TABS_PER_SESSION": os.environ.get("MAX_TABS_PER_SESSION", "5"),
        }
    )
    heap = os.environ.get("MAX_OLD_SPACE_SIZE", "512")
    log("starte camofox REST ...")
    subprocess.Popen([NODE, f"--max-old-space-size={heap}", "server.js"], cwd=REPO, env=srv)  # noqa: RUF100
    ok = False
    for _ in range(60):
        try:
            with urllib.request.urlopen("http://127.0.0.1:9377/health", timeout=5) as resp:
                if resp.status == 200:
                    ok = True
                    break
        except Exception:  # noqa: BLE001 - noch nicht bereit, weiterwarten
            pass
        time.sleep(2)
    if not ok:
        log("FEHLER: camofox REST antwortet nicht (Logs oben lesen + mir schicken).")
        sys.exit(1)
    log("camofox REST bereit ✅")

    # 6) MCP-Bridge(n) via supergateway (stdio → HTTP, fuers Handy)
    # CAMOFOX_BASE_URL ist Pflicht: sonst wuerde die MCP-Config $PORT lesen.
    mcp = dict(env)
    mcp.update(
        {
            "CAMOFOX_BASE_URL": "http://127.0.0.1:9377",
            "CAMOFOX_USER_ID": os.environ.get("CAMOFOX_USER_ID", "hf-space"),
            "CAMOFOX_SESSION_KEY": os.environ.get("CAMOFOX_SESSION_KEY", "operit"),
        }
    )
    sg = os.path.join(HOME, ".local", "bin", "supergateway")
    stdio_cmd = f"{NODE} {REPO}/mcp/server.mjs"
    subprocess.Popen(
        [sg, "--stdio", stdio_cmd, "--outputTransport", "streamableHttp",
         "--streamableHttpPath", "/mcp", "--port", "8001", "--stateful"],
        env=mcp,
    )
    log("MCP Streamable HTTP bereit ✅ (→ /mcp)")
    if os.environ.get("PUBLIC_BASE_URL", "").strip():
        subprocess.Popen(
            [sg, "--stdio", stdio_cmd, "--port", "8002",
             "--baseUrl", os.environ["PUBLIC_BASE_URL"].strip(),
             "--ssePath", "/sse", "--messagePath", "/message"],
            env=mcp,
        )
        log("MCP SSE bereit ✅ (→ /sse + /message)")
    else:
        log("PUBLIC_BASE_URL nicht gesetzt → SSE-Brücke übersprungen.")

    # 7) Proxy in den Vordergrund (Container lebt, solange der Proxy lebt)
    proxy = os.path.join(REPO, "docs", "free-vps", "hf-space", "gradio", "proxy.mjs")
    pxy = dict(env)
    pxy["APP_PORT"] = APP_PORT
    log(f"starte Reverse-Proxy auf :{APP_PORT} ...")
    os.execvpe(NODE, [NODE, proxy], pxy)


if __name__ == "__main__":
    main()
