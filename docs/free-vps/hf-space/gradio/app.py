# Camofox Space-Bootstrapper (Gradio-SDK): laedt diesen Branch als ZIP,
# entpackt ihn und startet den eigentlichen Launcher aus dem Repo.
# Absichtlich winzig und stabil — alle Logik lebt im Repo (fixbar ohne Re-Paste).
# Nur Python-Stdlib, keine Abhaengigkeiten.
import os
import shutil
import subprocess
import sys
import urllib.request
import zipfile

BRANCH = "arena/01a07f48-camofox-browser"
ZIP_URL = f"https://github.com/plovlife/camofox-browser/archive/refs/heads/{BRANCH}.zip"
WORK = os.path.join(os.path.expanduser("~"), "work")


def log(msg):
    print(f"[bootstrap] {msg}", flush=True)


def main():
    shutil.rmtree(WORK, ignore_errors=True)
    os.makedirs(WORK, exist_ok=True)
    zpath = os.path.join(WORK, "repo.zip")
    log(f"lade Branch {BRANCH} ...")
    for attempt in (1, 2, 3):
        try:
            urllib.request.urlretrieve(ZIP_URL, zpath)
            break
        except Exception as e:  # noqa: BLE001 - Layman-Log, dann weiter
            log(f"Download-Versuch {attempt} fehlgeschlagen: {e}")
            if attempt == 3:
                raise
    log("entpacke ...")
    with zipfile.ZipFile(zpath) as z:
        z.extractall(WORK)
    tops = [d for d in os.listdir(WORK) if os.path.isdir(os.path.join(WORK, d))]
    assert len(tops) == 1, f"unerwarteter Zip-Inhalt: {tops}"
    repo = os.path.join(WORK, tops[0])
    launcher = os.path.join(repo, "docs", "free-vps", "hf-space", "gradio", "launcher.py")
    log("starte Launcher aus dem Repo ...")
    os.execv(sys.executable, [sys.executable, launcher, repo])


if __name__ == "__main__":
    main()
