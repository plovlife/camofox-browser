# 🦊 Camofox aufs Handy — Anleitung ohne Kreditkarte (nur mit Smartphone machbar)

**Was du am Ende hast:** Auf dem Sofa tippen → Handy denkt via OpenRouter nach →
dein Gratis-Computer bei Hugging Face klickt im echten Browser. Kosten: **0 €.**

**Was du brauchst:** Handy + E-Mail-Adresse. Sonst nichts. Kein PC, keine Karte.
⏱️ ca. 45–90 Min (davon fast nur Warten — der Space lädt beim ersten Start den Browser runter).

> **Stand 08.09.2026:** Hugging Face verlangt fürs Docker-SDK neuerdings PRO ($9/Monat).
> Darum läuft das Setup über die **Gradio-Hülle** (gratis-Kontingent: bis zu 2 Spaces,
> unsere GPU-Uhr bleibt bei 0, weil wir gar keine GPU benutzen). Für dich ändert das
> fast nichts — nur 3 statt 2 Dateien. Falls HF wieder alles umstellt: melden, wir passen an.

---

## Schritt 0: Deinen Schlüssel erzeugen 🔑 (2 Min)

Alles bei dir wird mit **einem** Schlüssel abgeschlossen. Erzeug ihn in Operit AI:

1. Operit AI öffnen → Ubuntu-Terminal
2. Eintippen (oder kopieren):
   ```bash
   openssl rand -hex 32
   ```
   Falls `openssl` fehlt, nimm stattdessen:
   ```bash
   python3 -c "import secrets;print(secrets.token_hex(32))"
   ```
3. Raus kommt eine lange Zeile aus Buchstaben+Zahlen (64 Zeichen lang), z. B. `a3f9c1…`
4. **Abfotografieren oder in deine Notizen-App kopieren.** Das ist ab jetzt dein `SCHLÜSSEL`.
   Ein Key reicht für alle Geräte (wie ein Hausschlüssel mit mehreren Kopien 🏠).
   Verlier ihn nicht — aber keine Panik: du kannst ihn jederzeit neu setzen (Schritt 4).

## Schritt 1: Hugging-Face-Konto (5 Min)

1. Im Handy-Browser: **huggingface.co/join** öffnen
2. Konto erstellen (E-Mail + Passwort reicht, **kein Zahlungsmittel nötig**)
3. E-Mail bestätigen (Link im Postfach anklicken)
4. Fertig. Merk dir deinen **Benutzernamen** — du brauchst ihn gleich.

## Schritt 2: Space erstellen (3 Min)

„Space" = Hugging Faces Wort für *deinen Gratis-Computer*.

1. Auf huggingface.co oben auf dein Profil → **New Space** (oder direkt: huggingface.co/new-space)
2. Ausfüllen:
   - **Space name:** `camofox-browser` (oder wie du willst)
   - **SDK:** `Gradio` ⚠️ (Docker braucht PRO — Gradio ist unser gratis-Weg!)
   - **Hardware** (falls gefragt): **ZeroGPU** lassen — das ist dein Gratis-Kontingent
     (bis zu 2 Spaces; wir verbrauchen 0 GPU-Minuten, weil unser Code keine GPU anfasst)
   - **Visibility:** `Public` — muss bei gratis so sein, **keine Angst**: Im nächsten Schritt
     kommt der Schlüssel drauf. Das ist wie ein Haus mit öffentlicher Adresse, aber
     abgeschlossener Tür 🔒
3. **Create Space** tippen

## Schritt 3: 3 Dateien hochladen (8 Min)

Dein Space braucht genau **3 kleine Dateien**. Links antippen, alles kopieren:

1. 📄 **app.py** (Start-Knopf, ~40 Zeilen):
   👉 `https://raw.githubusercontent.com/plovlife/camofox-browser/arena/01a07f48-camofox-browser/docs/free-vps/hf-space/gradio/app.py`
2. 📄 **packages.txt** (System-Pakete, ~25 Zeilen, eine pro Zeile, keine Kommentare dazu!):
   👉 `https://raw.githubusercontent.com/plovlife/camofox-browser/arena/01a07f48-camofox-browser/docs/free-vps/hf-space/gradio/packages.txt`
3. 📄 **README.md** (Mini-Beschreibung):
   👉 `https://raw.githubusercontent.com/plovlife/camofox-browser/arena/01a07f48-camofox-browser/docs/free-vps/hf-space/gradio/README.md`

Für **jede** Datei im Space: Reiter **Files** → **Add file** → **Create a new file** →
Dateinamen EXAKT so schreiben (`app.py`, `packages.txt`, `README.md`) → Inhalt
einfügen → **Commit**. Nach dem dritten Commit fängt der Space automatisch an zu bauen. 🏗️

> Um den Rest (Node, App-Code, Browser, Start-Skripte) musst du dich **nicht** kümmern —
> der Space lädt beim Start alles automatisch nach. Dauert beim ersten Mal (Schritt 5).

## Schritt 4: Schlüssel als Secret hinterlegen (3 Min)

1. Im Space oben auf **Settings** → Bereich **Secrets** (ggf. runterscrollen)
2. **Add secret**:
   - Name: `CAMOFOX_ACCESS_KEY`
   - Wert: dein `SCHLÜSSEL` aus Schritt 0
3. Speichern. Der Space startet danach automatisch neu (nochmal ein paar Min warten).

**Optional (nur für den SSE-Notfallweg):** Unter **Variables** eine Variable anlegen:
- Name: `PUBLIC_BASE_URL`
- Wert: `https://DEINNAME-camofox-browser.hf.space` (DEINNAME = dein HF-Benutzername aus
  Schritt 1, kleingeschrieben). Brauchst du nur, falls Operit mal kein Streamable-HTTP
  kann — im Normalfall ignorieren.

## Schritt 5: Bauen + Starten lassen ☕ (15–30 Min Warten beim ersten Mal)

1. Im Space auf **Logs** tippen. Du siehst alles live. Zwei Phasen:
   - **Build** (~10–20 Min): System-Pakete werden installiert.
   - **Start** (~5–10 Min): Node + App + Browser (~700 MB) werden geladen.
2. Warten, bis oben **Running** steht und im Log sinngemäß erscheint:
   ```
   [bootstrap] starte Launcher aus dem Repo ...
   [launcher] Node v22.22.3 bereit ✅
   [launcher] Browser ist da ✅ (via postinstall)
   [launcher] camofox REST bereit ✅
   [launcher] MCP Streamable HTTP bereit ✅ (→ /mcp)
   [proxy] hört auf :7860 ✅
   ```
3. Falls es beim ersten Mal mit Netzwerk-Timeout abbricht: keine Panik — oben **⋮ → Factory reboot**
   (baut sauber neu). Zweitversuche klappen fast immer.

## Schritt 6: Test — lebt er? (2 Min)

Deine Space-Adresse (merk sie dir, das ist ab jetzt „dein Computer"):

```
https://DEINNAME-camofox-browser.hf.space
```

1. Im Handy-Browser öffnen + `/health` dranhängen:
   `https://DEINNAME-camofox-browser.hf.space/health`
   → Du siehst eine Status-Seite mit `ok`. **Das heißt: er lebt!** 🎉
   (`/health` ist absichtlich offen — das ist auch der Wecker nach dem Sleep, s. Schritt 9.)
2. Schloss-Test in Operits Ubuntu-Terminal:
   ```bash
   curl -s -o /dev/null -w "%{http_code}\n" https://DEINNAME-camofox-browser.hf.space/mcp
   ```
   → Es muss **`401`** kommen. 401 = *Tür da, aber abgeschlossen.* Genau richtig! 🔒
   Mit Schlüssel dran muss eine **andere** Zahl kommen (z. B. 400/404/405):
   ```bash
   curl -s -o /dev/null -w "%{http_code}\n" "https://DEINNAME-camofox-browser.hf.space/mcp?key=DEIN-SCHLÜSSEL"
   ```
   Faustregel: **401 ohne Schlüssel, was anderes mit Schlüssel = alles korrekt.** ✅

## Schritt 7: Operit verbinden (5 Min)

1. **Modell prüfen:** In Operit ein OpenRouter-Modell mit **Tool-Calling** wählen
   (ohne Tool-Calling kann die KI keine Werkzeuge benutzen!). Was gerade gratis ist,
   wechselt ständig — aktuell nachschauen auf `openrouter.ai/models?supported_parameters=tools`
   (nur `:free`-Modelle aus der Liste nehmen). Klassiker aus der Qwen-Familie:
   `qwen/qwen3-coder:free` u. ä. — aber verlass dich auf die Live-Liste, nicht aufs Gedächtnis.
2. **MCP-Server hinzufügen:** In Operit zu MCP/Skills/Werkzeuge (heißt je nach Version leicht
   anders) → **Remote-MCP-Server hinzufügen** → als URL eintragen:
   ```
   https://DEINNAME-camofox-browser.hf.space/mcp?key=DEIN-SCHLÜSSEL
   ```
   (Ja, mit `?key=…` hinten dran — das ist der Trick, damit es ohne Header-Einstellung geht.
   Profi-Alternative: URL ohne `?key=`, dafür Header `Authorization: Bearer DEIN-SCHLÜSSEL`.)
3. Speichern. Operit sollte jetzt **11 Werkzeuge** finden (`camofox_create_tab`,
   `camofox_snapshot`, `camofox_click`, …). Falls 0 Tools: Schritt 10 lesen.

## Schritt 8: Erster Auftrag 🚀 (3 Min)

Tipp in Operit (mit Tool-Modell + verbundenem MCP):

> **„Öffne example.com und sag mir die Hauptüberschrift der Seite."**

Was dann passiert: Operit ruft `camofox_create_tab` → `camofox_snapshot` auf deinem Space
auf und antwortet mit der Überschrift. Du hast gerade einen echten Browser ferngesteuert. 😎

Danach ausprobieren: *„Geh auf heise.de und fass die Top-Meldung in 3 Sätzen zusammen."*

**Haushalten:** Jeder Klick/Schritt = 1 OpenRouter-Anfrage. Bei 50/Tag (ohne Einzahlung)
sind das ca. **4–8 kleine Aufträge pro Tag**. Lange Aufträge in kleine zerlegen!

## Schritt 9: Alltags-Wissen 📌

- 😴 **Sleep:** Nach längerer Ruhe schläft der Space ein. Aufwecken: `/health`-Seite
  einmal aufrufen, dann **5–10 Minuten** warten (Browser wird neu geladen). Normal, kein Fehler.
  Tipp: weck ihn per `/health`, BEVOR du in Operit den Auftrag tippst.
- 🎮 **GPU-Quote:** Wir verbrauchen **0 Minuten** — unser Code fasst keine GPU an.
  Dein Gratis-Kontingent bleibt unangetastet.
- 💨 **Vergesslich:** Nach Neustart sind Browser-Cookies weg (Platte ist flüchtig).
  Logins musst du dann neu machen. Deine Chats in Operit bleiben trotzdem erhalten.
- 🔒 **Geheim halten:** Space-URL + Schlüssel niemals teilen, posten oder screenshotten.
- 📊 **Logs lesen:** Bei Problemen zuerst Space → **Logs** (die letzten Zeilen sagen fast immer,
  was los ist).

## Schritt 10: Fehler-Tabelle 🩺

| Was du siehst | Was es heißt | Was du tust |
|---|---|---|
| `401` überall | Schlüssel falsch oder Secret fehlt | Secret `CAMOFOX_ACCESS_KEY` in Settings prüfen (Schritt 4) |
| `404` auf `/mcp…` | Pfad/URL vertippt | URL Zeichen für Zeichen vergleichen |
| Build-Fehler `Unable to locate package X` | Ein Paketname passt nicht zu HFs Debian-Version | Die Log-Zeile an mich schicken — ich fixe `packages.txt`, du lädst sie neu hoch |
| `[launcher] FEHLER: …` | Start-Problem (Netz/timeout) | Log-Ausschnitt an mich schicken |
| Space startet ewig (>30 Min beim 1. Mal) | Build hängt oder Netzwerk-Schluckauf | ⋮ → **Factory reboot**, nochmal warten |
| Operit findet 0 Tools | URL falsch / Space schläft / Key falsch | Erst `/health` aufrufen (wecken + warten!), dann URL+Key prüfen |
| OpenRouter-`429` | **Tageslimit (50) aufgebraucht** — liegt NICHT am Space! | Bis morgen warten (Reset um Mitternacht UTC) oder $10-Trick für 1.000/Tag |
| KI klickt nicht, redet nur | Modell kann kein Tool-Calling | Modell aus der Tool-Liste wählen (Schritt 7) |
| Leere/komische Antworten | Gratis-Modell überlastet | Anderes `:free`-Modell versuchen |

---

**Kosten-Bilanz: 0 €** 🎉 Spätere Upgrades (alle optional): HF PRO ($9/Monat: Docker-SDK + immer-an),
OpenRouter $10 einmalig (1.000 statt 50 Anfragen/Tag), Oracle-VPS mit echter Bankkarte.
