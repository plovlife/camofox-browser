# Deep Dive: Kostenloser VPS für camofox-browser + MCP + Qwen3.8-27B

*Recherchestand: 08.09.2026. Getrieben durch die Frage: Was ist JETZT noch wirklich gratis, und wie passt
"Seen/Qwen 3.8 27B" + camofox-MCP rein?*

---

## TL;DR – die Entscheidung

| | Empfehlung |
|---|---|
| **VPS** | **Oracle Cloud Always Free, Ampere A1 (ARM)** – 2 OCPU / 12 GB RAM / 200 GB Disk / 10 TB Egress, forever free. ⚠️ Seit 15.06.2026 nur noch **die Hälfte** (vorher 4/24), Durchsetzung seit 18.08.2026. |
| **camofox** | Läuft auf ARM ✅ – offizieller **linux-arm64 Build** existiert (654 MB, live über GitHub-API verifiziert). Auf dem VPS funktioniert auch `npm install` + Auto-Fetch, den wir in der Sandbox nicht hatten. |
| **MCP** | `node mcp/server.mjs` (stdio) direkt neben der REST-API auf dem VPS. Forwardet `CAMOFOX_ACCESS_KEY` automatisch als Bearer. |
| **Qwen3.8-27B lokal?** | ❌ Auf 12 GB RAM nicht machbar (Q4_K_M = ~18 GB, Q2 = ~10,7 GB → ohne Swap kein Platz für OS+Browser; und CPU-only ~1–2 tok/s = unbenutzbar für Agent-Loops). |
| **Qwen3.8-27B trotzdem gratis?** | ✅ **Cloudflare Workers AI hostet Qwen3.8-27B seit 17.08.2026 im Free Tier** (10.000 Neurons/Tag, unterstützt Function Calling → genau das, was der Agent für MCP braucht). |

**Architektur-Empfehlung:** VPS = Hände (camofox + MCP), Cloudflare = Gehirn (Qwen3.8-27B über API).
Alles zusammen: 0 €/Monat, Modell-Downloads nur optional.

---

## 1. Was "kostenloser VPS" 2026 noch bedeutet

Der Markt hat sich 2025/26 massiv verschlechtert – fast jeder ältere Guide ist veraltet:

| Anbieter | Was's gibt | Dauer | Haken |
|---|---|---|---|
| **Oracle Cloud (OCI)** | 2× ARM OCPU + 12 GB RAM, 2× AMD-Micro (1 GB), 200 GB Storage, 10 TB Egress/Monat | forever | Am 15.06.2026 **still halbiert** (vorher 4/24); Idle-Reclaim (s. u.); A1-Kapazität je Region knapp; Kreditkarte zur Verifizierung |
| **Google Cloud** | 1× e2-micro (2 shared vCPU, 1 GB RAM), 30 GB Disk | forever | Nur 3 US-Regionen; 1 GB RAM → camofox grenzwertig, Modell unmöglich; Egress ab 1 GB/Monat kostenpflichtig |
| **AWS** | Nur noch $100–200 Credits, Free-Plan-Modell | 6 Monate | 12-Monats-Free-Tier (t2/t3.micro) **abgeschafft für Accounts nach 15.07.2025** |
| **Azure** | B1s/B2ats 750 h/Monat + $200 | 12 Mon. / 30 T. | Läuft aus, danach Auto-Billing im Blick behalten |
| **Fly.io / Railway** | $5-Monatsguthaben bzw. Trial-Credit | – | Reicht für camofox solo, nicht mit Browser-Last |
| **Render** | 750 Instance-Hours | forever | Spin-down nach 15 min Idle → für Browser-Sessions (Session-Timeout 30 min!) kontraproduktiv |
| **GratisVPS / VPSWala / Hax** | 0,5–2 GB Community-Kisten | forever | Ohne Karten-Pflicht, aber ohne jede Vertrauenswürdigkeit – **niemals** mit importierten Cookies/Browser-Profilen betreiben |
| **IBM LinuxONE** | 1 VM (s390x) | 12 Mon. | Camoufox-Builds existieren nur für x86_64/arm64 → Ausschluss |
| **Realitäts-Check** | Hetzner CX22 (ARM, 4 vCPU/8 GB) | ~3,8 € | Kein Gratis-Tier, aber der ehrliche "es funktioniert einfach"-Punkt |

**Zwischenfazit:** Oracle A1 ist der einzige Gratis-VPS, der camofox + MCP + etwas Drumherum seriös kann. Alle
Specs unten beziehen sich darauf.

### Oracle-A1-Mathematik (warum 2/12 exakt passt)

- Neues Kontingent: **1.500 OCPU-hours + 9.000 GB-hours/Monat** (vorher 3.000/18.000).
- 2 OCPU × 744 h = 1.488 OCPU-h ✅, 12 GB × 744 h = 8.928 GB-h ✅ → **2 OCPU/12 GB dürfen 24/7 laufen**, ohne dass auch nur eine Stunde drüber ist.
- Jederzeit mehr (z. B. kurz 4/24) ist als **PAYG-Account** möglich und kostet innerhalb des Gratis-Kontingents 0 €;
  Support-Auskünge zur Abgrenzung Free vs. PAYG sind seit Juni 2026 widersprüchlich → Budget-Alarm auf 1 $ setzen
  und Kostenanalyse abonnieren.
- ⚠️ **Idle-Reclaim (nur Pure-Free-Accounts):** Instanz gilt als idle, wenn über 7 Tage CPU-p95 < 20 %,
  Netzwerk < 20 % **und** (A1-only) RAM < 20 %. Dann Stopp, nach ~30 Tagen Delete – und der A1-Platz in
  beliebten Regionen ist oft weg. Gegenmaßnahmen: echte Nutzung (Agent-Tasks, Health-Checks), täglicher
  CPU-Puls (im Setup-Script drin), oder PAYG-Konvertierung (kein Reclaim, bleibt bei 0 € in den Limits).

## 2. Passt camofox da rein? Ja – mit frischem Wind.

Live gegen `api.github.com` geprüft (Releases sind über das GitHub-API erreichbar):

- Aktuellster Camoufox-Build `v152.0.4-beta.30` liefert **`camoufox-152.0.4-beta.30-lin.arm64.zip` (654 MB)**
  ⇒ `npx camoufox-js fetch` auf dem Oracle-ARM-VM funktioniert out of the box.
- Ressourcen: Server ~150–180 MB RSS idle, pro aktiver Browser-Session grob +400–700 MB, `BROWSER_IDLE_TIMEOUT_MS`
  killt den Browser nach 5 min → die 12 GB sind komfortabel, solange **kein** 27B-Modell daneben läuft.
- npm-Registry ist vom VPS aus erreichbar → `npm install` ohne `--ignore-scripts`-Tricks, better-sqlite3 baut sauber.

### Härtung (Pflicht, der Kiste hängt öffentlich!)

| Maßnahme | Umsetzung |
|---|---|
| API absichern | `CAMOFOX_ACCESS_KEY=<64-hex>` → alle Routen außer `/health` brauchen `Authorization: Bearer` |
| Kein offener Port | `CAMOFOX_BIND_HOST=127.0.0.1`; Zugriff via `ssh -L 9377:localhost:9377` oder Tailscale (gratis) |
| Admin-Routen | `CAMOFOX_ADMIN_KEY` für `POST /stop` |
| Telemetry | `CAMOFOX_CRASH_REPORT_ENABLED=false` (oder bewusst an lassen – anonymisiert) |
| VNC | aus lassen (`ENABLE_VNC` unset) – kein noVNC an der Öffentlichkeit |
| Limits | `MAX_SESSIONS` runter (z. B. 3), `MAX_OLD_SPACE_SIZE=512`, systemd `MemoryMax=6G` |

## 3. Qwen3.8-27B: der Stand (Release Mitte August 2026)

- **Releases:** 14.08.2026, Apache-2.0, dense 27,3B + 461M-Vision-Encoder (Text/Bild/Video), 262K Kontext
  (YaRN ~1M), Thinking-Modus, **natives Tool-Calling** → sauber für MCP-Agenten.
- **Ollama-Support seit v0.32.12:** `ollama run qwen3.8:27b` = 18 GB (Q4_K_M).
- **Größenleiter:** Q4_K_M 17,1–17,9 GB · IQ4_XS 15,7 · Q3_K_XL 13,4 · Q2_K_XL 10,7 · IQ2_XXS 9,0 GB
  (unter Q3 deutlich spürbarer Qualitätsverlust, besonders bei Reasoning/Agentic).

### Lokal auf dem Gratis-VPS? Durchgerechnet: nein.

| | 2× A1 OCPU / 12 GB |
|---|---|
| Q4_K_M 18 GB | passt nicht in 12 GB (OS ~0,7 + camofox ~1,5 GB) |
| Q2_K_XL 10,7 GB | "passt" nur ohne Browser – mit Swap bei ~1 tok/s |
| Speed | Dense 27B ist speicherbandbreiten-limitiert; RK3588-8-Kern-Benchmarks: 1–1,5 tok/s für 27–32B. Ampere A1 mit 2 OCPU ähnlich. Ein 400-Token-Agent-Step = 7+ Minuten. |
| Fazit | **Lokal erst ab ~20–24 GB RAM sinnvoll** (dann Q4, ~1–3 tok/s auf ARM-CPU – immer noch batch-only). Auf 12 GB: Modell weglassen oder ≤ 7–8B. |

## 4. Modell gratis per API – die echte Option

| Provider | Modell (gratis) | Limits | Anmerkung |
|---|---|---|---|
| **Cloudflare Workers AI** | **Qwen3.8-27B** (seit 17.08.2026!) | 10.000 Neurons/Tag (Free Plan) | ⭐ Passt exakt. OpenAI-kompatible API, Tool-Calling unterstützt. Kein VPS-Account-Konter: Rechenlast liegt komplett bei Cloudflare. |
| Groq | Qwen**3.6**-27B (Vorgänger) | 30 req/min, 1.000 req/Tag, 200K tok/Tag | Sehr schnell; wenn CF-Limits zwickten → Fallback |
| OpenRouter | `:free`-Varianten, roster wechselt | 20 req/min, 50 req/Tag (1.000 nach $10-Einmalzahlung) | Gut zum Experimentieren, zu knapp als Primär-Backbone |
| NVIDIA NIM | 120+ Open-Weights, ~1.000 req/Tag | Dev/Trial-Status | Weitere Redundanz-Schiene |

Aufruf vom VPS aus (OpenAI-kompatibler Endpunkt der Workers AI):

```bash
curl -s https://api.cloudflare.com/client/v4/accounts/$CF_ACCOUNT_ID/ai/v1/chat/completions \
  -H "Authorization: Bearer $CF_API_TOKEN" -H 'Content-Type: application/json' \
  -d '{
    "model": "@cf/qwen/qwen3.8-27b",
    "messages": [{"role":"user","content":"Nenne 3 Fakten über Camoufox."}],
    "tools": [],
    "stream": false
  }'
```

> Modell-Handle und Pfad können bei Cloudflare je nach Veröffentlichungsstand variieren
> (`/ai/v1/chat/completions` = OpenAI-kompatibler Beta-Endpoint, `/ai/run/@cf/...` = natives
> Workers-AI-REST). Vor Produktivnutzung kurz gegen das eigene Dashboard validieren.

## 5. Empfohlenes Setup (die Architektur)

```
┌─────────────── Oracle A1 2 OCPU/12 GB (Ubuntu ARM) ───────────────┐
│  systemd: camofox.service (127.0.0.1:9377, Bearer-Key)             │
│     ├─ REST-API  ──►  Camoufox-Browser (arm64, lazy, idle-kill)    │
│     └─ MCP stdio  ──►  Agent-Harness (OpenClaw / Claude Code / …)  │
│  cron: keep-alive-Pulse (Reclaim-Schutz)                           │
└───────────────┬──────────────────────────────────────────────────┬─┘
                │ SSH-Tunnel / Tailscale (Admin, API-Key)          │ HTTPS
                                                           ┌───────▼────────┐
                                                           │ Cloudflare      │
                                                           │ Workers AI      │
                                                           │ Qwen3.8-27B     │
                                                           │ (10k Neurons/Tag)│
                                                           └─────────────────┘
```

1. **VPS provisionieren:** [Setup-Script](free-vps/setup.sh) via SSH-Copy → richtet Node 22, camofox
   (`/opt/camofox-browser`), systemd-Unit, Firewall, Keep-Alive ein.
2. **Agent anbinden:** `.mcp.json` des Agenten → `node /opt/camofox-browser/mcp/server.mjs` mit
   `CAMOFOX_BASE_URL` + `CAMOFOX_ACCESS_KEY` (beides wird automatisch als Bearer geforwardet).
   Alternativ OpenClaw-Plugin: `openclaw plugins install @askjo/camofox-browser` (11 Tools).
3. **LLM-Backend:** Workers-AI-Endpoint + Token in die Agenten-Config (`qwen3.8-27b`, tools an).
4. **Monitoring:** `/health`, `/metrics` (Prometheus-Flag ist im Script an), `GET /tabs/:id/stats`.

## 6. Risiken & offene Punkte

- **Oracle-Kapazität:** A1-Instanzen sind in EU-/US-Ost-Regionen zeitweise "out of capacity". Workarounds:
  Home-Region mit Kapazität wählen (einmal festgelegt!), immer-vs-gelegentlich-Instanz, PAYG-Upgrade erhöht
  die Trefferquote deutlich.
- **Halbierung war ohne Ankündigung** – weitere Kontingent-Kürzungen sind nicht ausgeschlossen.
  → Profile/Persistenz (`~/.camofox/profiles`) regelmäßig sichern; Setup-Script ist reproduzierbar.
- **10k Neurons/Tag sind ein Tagesbudget** – für einen Agenten mit vielen Tool-Loops pro Task wird das bei
  intensiver Nutzung eng (Faustregel: reicht für ein paar Dutzend längere Sessions/Tag). Fallback: Groq Qwen3.6-27B.
- **Free Tier ≠ Datenabwesenheit:** Prompts an Groq/CF/OpenRouter verlassen die VM. Wer das nicht will,
  braucht 24+ GB RAM lokal (oder 16 GB mit Q3) – dann aber bewusst mit 1–3 tok/s.
- **Community-"Gratis"-VPS (ohne Kreditkarte):** geeignet zum Testen, **ungeeignet** für Session-Import/Cookies –
  Betreiber haben root auf eurer Browser-Profil-Festplatte.

## 7. Quellen (Auswahl)

- Oracle-Halbierung: [InfoQ 03.07.2026](https://www.infoq.com/news/2026/07/oracle-cloud-free-tier-limits/),
  [daily.dev](https://daily.dev/posts/oracle-quietly-halves-free-tier-ampere-a1-compute-limits-with-no-public-announcement-ldgjrd9vs),
  [TerminalBytes](https://terminalbytes.com/oracle-cloud-free-tier-changes-2026/),
  [Linuxiac](https://linuxiac.com/oracle-quietly-cuts-free-tier-ampere-a1-resources-in-half/),
  [FullMetalBrackets (PAYG-Analyse)](https://fullmetalbrackets.com/blog/oci-free-tier-breakdown),
  [r/oraclecloud Thread](https://www.reddit.com/r/oraclecloud/comments/1ubk2qy/new_always_free_tier_limits_21june2026_update/)
- Idle-Reclaim: [OraCommit 02.02.2026](https://oracommit.blogspot.com/2026/02/understanding-oci-always-free-compute.html),
  [r/selfhosted Thread](https://www.reddit.com/r/selfhosted/comments/12fg9d9/oracle_free_tier_reclamation/)
- Free-VPS-Vergleich 2026: [klymentiev.com](https://klymentiev.com/blog/free-vps),
  [mrplanb.com](https://www.mrplanb.com/datacenter/free-vps-tiers),
  [agentdeals.dev](https://agentdeals.dev/cloud-free-tier-comparison-2026),
  [vashishthakapoor.com](https://vashishthakapoor.com/best-free-vps-hosting/)
- AWS-Umstellung: [CostGoat](https://costgoat.com/pricing/amazon-ec2),
  [cloudwebschool](https://cloudwebschool.com/docs/aws/fundamentals/aws-free-tier/),
  [dev.to/aws-builders](https://dev.to/aws-builders/whats-new-in-aws-free-tier-2025-2ba5)
- Qwen3.8-27B: [tokios docs](https://docs.tokios.com/models/qwen3.8),
  [Ollama-Launch (OrcaRouter)](https://www.orcarouter.ai/blog/qwen-3-8-27b-ollama),
  [Quant-Größen (oFlight)](https://www.oflight.co.jp/en/columns/qwen3-8-27b-requirements-vram-local-2026),
  [Sitepoint Setup-Guide](https://www.sitepoint.com/qwen3-8-27b-local-gpu-setup-ollama/),
  [tech-insider 12 Steps](https://tech-insider.org/how-to-run-qwen3-8-27b-locally-ollama-2026/)
- Gratis-APIs: [KDnuggets 05.09.2026 (Cloudflare listet Qwen3.8-27B)](https://www.kdnuggets.com/5-free-llm-api-providers-you-can-use-in-2026),
  [continuumcode-Vergleich](https://continuumcode.ai/guides/free-llm-api/),
  [stationx](https://app.stationx.net/articles/free-llm-api)
- CPU-27B-Tempo: [TuringPi RK3588-Benchmarks](https://turingpi.com/run-llm-locally-arm-rk3588-ollama-llama-cpp/)
- Camoufox-Assets: `GET https://api.github.com/repos/daijro/camoufox/releases/latest` (654 MB arm64-Linux-Build,
  am 08.09.2026 in diesem Repo live abgefragt)

---

## Anhang A: Community-Screening (Reddit · 4PDA · FMHY · XDA) — 08.09.2026

Anforderung für diesen Anhang: VPS (Linux **oder** Windows), auf dem **Qwen3.8-27B lokal „einwandfrei"** läuft
(⇒ ≥ 20–24 GB nur fürs Modell, Windows rechnet mit ~32 GB+).

### Reddit — Konvergenz auf Oracle, mit Grauzonen-Tricks
- Community-kuratierte Guides (r/hermesagent VPS-Megathread, 06/2026; r/selfhosted „Cheap VPS", 06/2026) nennen
  einhellig **Oracle Free Tier als einziges relevantes „gratis + groß"**. Wichtige Community-Details:
  - **Karten-Ablehnungen sind weit verbreitet**; Workarounds: andere/virtuelle Karte (privacy.com), „dritter Versuch klappt oft".
  - **PAYG-Upgrade**: kein Billing unterhalb der Limits, **kein Idle-Reclaim**, bessere Capacity-Chancen;
    Community-Konsens nach der Halbierung: *PAYG-Accounts behalten de facto 4/24 gratis* — offizielle Doku sagt
    das nicht → Budget-Alarm auf $1 als Sicherung.
  - Erste Instanz **sofort** in Max-Konfiguration anlegen (Reservierung gilt, solange man sie nicht löscht);
    bei „out of capacity": Retry-Skript / Provisionierung per OCI CLI (Klassiker-Thread auf habr/4PDA).
  - Skepsis dokumentiert: „Oracle kann Accounts ohne Warning löschen" — Backups & reproduzierbares Setup (siehe `setup.sh`).
- **Zum Modell**: r/ollama (05/2026) deckt sich exakt mit unserer Rechnung: *„20+ VRAM and 32 GB RAM, um ~30B-Modelle
  perfekt zu fahren"*; Free-Tier von **Ollama Cloud wurde massiv gekürzt** (Session- + Wochenlimits) → als Backbone untauglich.
  Community-Tempolaten für Oracle-ARM (7B: 5–10 t/s, 13B-quant: 2–5 t/s) ⇒ 27B-dicht ≈ 1–3 t/s: **läuft, aber nicht „einwandfrei"**.
- **Zeitfenster-Ansatz** (Credits statt Forever): GCP $300/90 d ⇒ 8 vCPU/32 GB ~5–7 Wochen; AWS $200/6 Mon.;
  Vultr $250/30 d; **Azure for Students $100 ohne Kreditkarte** gilt in r/selfhosted als „einziges echtes Free ohne
  Billing-Risiko" (Studienstatus vorausgesetzt).

### 4PDA — Oracle-Kultur, aber VPN-Fokus; ehrliches Fazit: keine Extras
- Der Oracle-Tipp steht auch hier seit Jahren in den Threads (z. B. im großen WireGuard-Topic:
  „на Oracle free tier арендуйте бесплатно виртуалку с arm-процессором ampere").
- Wichtige 4PDA-spezifische Learnings für Oracle: **Heimatregion für immer festgelegt**, A1-Kapazität regional knapp,
  „Konto ggf. über Freund in EU registrieren" (RU-Karten werden abgelehnt), Up-/Downgrade-Move über PAYG als Weg zur A1-Instanz,
  und: Oracle-IPs werden in Russland zusätzlich durch DPI gefiltert (für uns in den USA irrelevant).
- Grundstimmung zu „бесплатный VPS": skeptisch („die Hälfte der Gratis-Angebote ist für RU tot"),
  Inland-Alternativen sind Trial-Guthaben (Yandex Cloud & Co.), nicht forever free.
- **Kein** 4PDA-Fund, der 24–32 GB+ RAM forever-free bietet.

### FMHY — bestätigt Oracle ⭐ und liefert das eigentliche Modell-Puzzlestück
- `fmhy.net/developer-tools` (Hosting Tools): **„Oracle Cloud — Free VPS / Requires Real Information / Guide"** ist der
  offiziell empfohlene Weg; dazu Indizes: FreeHosts, Awesome-Web-Hosting, VPS Comparison Chart, servers.fyi.
  Eine dedizierte „VPS"-Seite existiert bei FMHY nicht — wer dort 32-GB-Garantien sucht, sucht am falschen Ort.
- `fmhy.net/ai` ist die eigentliche Fundgrube für „Modell gratis **ohne** eigene 18-GB-Kiste":
  - **Tryingopen** — listet **„Qwen3.8 27B, Unlimited (12 messages per chat)"** + „OpenAI Bridge" (API-Zugang).
  - **NVIDIA NIM** — „Kimi K3 / DeepSeek V4 Pro / MiniMax M3 — Unlimited / No Sign-Up".
  - Qwen Studio (chat.qwen.ai — Qwen3.8 Max), Z.ai (GLM 5.3), Google AI Studio (Gemini 3.8 Flash), Together (~110/Tag).
  - Expliziter Warnhinweis, der zu unserem Setup passt: keine persönlichen Daten in Cloud-AIs; Agenten in
    Containern laufen lassen, nie auf Maschinen mit Wichtigem.
- ⇒ FMHY-Community-Logik für unser Szenario: **VPS (Oracle) für die Exekution (camofox+MCP), Gratis-API fürs Modell.**

### XDA-Developers — Fehlanzeige (auch ein Ergebnis)
- Keine relevante aktuelle Free-VPS-/LLM-Kultur: Treffer im Server-Tag sind 2012er-Fundstücke
  (kostenloser Dev-Host mit 820 KB/s Uplink, Hyper-V-Basteleien). Für diese Frage trägt XDA nichts bei.

### Konsens-Matrix (Community-Screening)

| Weg | RAM | 27B lokal „einwandfrei"? | Windows? | forever free? |
|---|---|---|---|---|
| Oracle 2/12 (neu) | 12 GB | ❌ (passt nicht rein) | ❌ | ✅ |
| Oracle 4/24 via PAYG-Grauzone | 24 GB | ⚠️ Q4 18 GB passt, ~1–3 t/s, Linux only | ❌ | ✅ (mit Restrisiko) |
| GCP $300-Trial n2-standard-8 | 32 GB | ✅ läuft richtig (CPU ~3–6 t/s) | ⚠️ eng, geht | ❌ (90 Tage) |
| Azure Students $100 | 32–64 GB wählbar | ✅ (D32a für ~1–2 Wochen) | ✅ | ❌ (12 Mon. Guthaben-Takt) |
| AWS $200/6 Mon. r7g.xlarge | 32 GB | ✅ (~40 Tage Laufzeit) | ⚠️ | ❌ |
| **Empfehlung (Community-Konsens)** | 12–24 GB Oracle | **Modell via Gratis-API** (CF Workers AI / Tryingopen-Bridge / NIM), camofox auf dem VPS | ❌ (Windows braucht das Modell nicht) | ✅ |

---

## Anhang B: Wie andere es machen — Ökosystem „Gratis-Webchats als API"

Recherchestand 08.09.2026, Quellen: GitHub (live via API geprüft) + DeepWiki + Community-Artikel.

### Die vier verbreiteten Archetypen

1. **Router/Pool-Architektur (g4f, „GPT4Free")** — der De-facto-Standard:
   40+ Provider hinter einer OpenAI-kompatiblen FastAPI, automatische Provider-Rotation mit
   Failover/Retry, Auth über HAR-Dateien/Cookies/Browser-Automation, Docker-Deployment, **eingebauter
   MCP-Server** (`g4f-mcp`). Kernprinzip: *jeder Scraper ist wegwerfbar*, Stabilität entsteht durch
   Redundanz, nicht durch Sorgfalt.
2. **Single-Target-Bridges** (LMArenaBridge ⭐403, radio-house-api ⭐10): nur eine Site, Python/FastAPI,
   **bindet bewusst an 127.0.0.1** (localhost-only!), Frontends kommen darüber. radio-house dokumentiert
   offen die Praxis: „Modelle können verschwinden/nicht funktionieren, claude/gpt ~5 Requests je 30–40 min,
   Tool-Calls nur *emuliert*". ⇒ Als Agent-Backbone disqualifiziert, als Chat-Zutat ok.
3. **Resilienz-Layer drumherum** (Free-GPT4-WEB-API, Scrapfly-Anleitungen): Provider-Fallback +
   Health-Monitoring + Blacklist, **Residential-Proxy-Pools**, „virtual users" (= Session-/Account-Rotation),
   Pacing/Retries statt fester Rate-Limits. Technischer Grundkonsens: Vanilla-Playwright wird sofort
   erkannt (TLS-Fingerprint + Turnstile), nötig ist Anti-Detection (→ exakt die Camoufox-Nische) und
   SSE-Streaming hat „kein sauberes Completion-Event" → Polling-Muster nötig.
4. **Serverless-Twist** (g4f.dev): Cloudflare Workers als Router, Multi-Window-Rate-Limits pro
   Nutzer-Tier, Usage-Tracking in D1/R2, eigene API-Keys für Konsumenten — so skalieren die das,
   ohne VPS.

### Frontend-Seite (Smartphone)

- **Open WebUI**: wenn's ein Backend gibt (schnellster Draht, „anything OpenAI-compatible is a first-class provider").
- **LibreChat**: wenn's mehrere Provider + Zugriffsregeln pro Nutzer braucht; `endpoints.custom` deckt
  sogar Cloudflare Workers AI nativ ab; deployt als JS-Backend teils kostenlos auf CF/Vercel.
- Access-Regel der Community: Model-Backends **niemals** öffentlich, Frontend via nginx/Cloudflare-TLS,
  Backend-Port privat; Handy = PWA im Browser oder Telegram/WhatsApp-Kanal (OpenClaw-Modell).

### Realitäts-Check: So endet es für die meisten

OmniRoutes „Free Tiers"-Wiki führt 19 Provider, deren ToS Self-hosted-Proxies/OAuth-Weitergabe
explizit verbieten — mit konkreten Folgen: **Gemini CLI OAuth + Dritt-Tools = Massen-BANS**,
Kiro verbietet „OpenClaw & similar harnesses" namentlich, Qwens freie OAuth-Schiene wurde
eingestellt, DuckDuckGo verbietet automatisiertes Abfragen. Der dev.to-Autgeber, der ChatGPTs UI
komplett reverse-engineerte (stealth patches, Cloudflare bypass, virtual displays), titelt selbst:
*„…and here's why you shouldn't"*. Community-Lehre: **Brücken sind Beifahrer, nie Motor.**

### Blaupause für unseren Fall (aus den Mustern abgeleitet)

```
Handy (PWA: Open WebUI/LibreChat, via Tailscale/CF-Access)
  └─► LibreChat/OpenWebUI ── primär: Workers AI (Qwen3.8-27B) · NIM · Groq   [sanktioniert, schnell]
                          └─ sekundär: arena-bridge als Provider/Kanal       [Berater bei Bedarf]
VPS: camofox (Browser-Hände, MCP)  +  bridge nach Muster 1+3:
     Browser nur für Login (VNC → storage_state exportieren), danach XHR-Replay,
     Localhost-Bind, Bearer-Key, Blacklisting+Pacing, Failover-Flag,
     Erwartung: DOM-Bruch alle paar Wochen = 1-h-Fix, nicht Projekt-Risiko.
```

---

## Anhang C: Ohne Kreditkarte — was wirklich geht (08.09.2026)

Ausgangslage: Nutzer hat **keine Kreditkarte**, aber Operit AI + OpenRouter-free (ohne Einzahlung)
bereits auf dem Smartphone. Oracle/AWS/GCP/Azure fallen damit als VPS weg (alle verlangen
Karten-Verifizierung).

### C.1 Ehrlicher Befund: virtuelle Karten retten Oracle nicht

Community-Konsens auf r/oraclecloud: Oracle erkennt virtuelle/Prepaid-Karten und lehnt das
Signup ab („doesn't accept virtual cards or single-use cards", „prepaid cards are not allowed").
Revolut-virtuell scheitert reproduzierbar; selbst physische Revolut-Debitkarten werden
überwiegend abgelehnt, echte Bank-Debitkarten sind „erlaubt, aber nicht empfohlen".
Quellen: [Thread 1](https://www.reddit.com/r/oraclecloud/comments/1advntm/cloud_free_tier_without_card/),
[Thread 2](https://www.reddit.com/r/oraclecloud/comments/1eymxam/card_verification_failed_for_free_tier/),
[Thread 3](https://www.reddit.com/r/oraclecloud/comments/1fy7y5c/oracle_free_tier_with_revolut_credit_card/)
⇒ **Oracle ohne echte Bankkarte: nicht einplanen.**

### C.2 No-Card-Anbieter im Vergleich (für camofox: ≥ ~2 GB RAM, Docker/Root, Egress nötig)

| Anbieter | Gratis-Leistung | Karte? | camofox-tauglich? |
|---|---|---|---|
| **Hugging Face Spaces** (Docker-SDK) | **2 vCPU / 16 GB RAM**, ~50 GB ephemeral Disk, unmetered Build-Minuten | ❌ nein | ✅ **Ja — Top-Empfehlung** |
| GitHub Codespaces | 120 Core-h/Monat (60 h auf 2-Core), 15 GB | ❌ nein | ⚠️ nur Testen (30-min-Idle-Stopp) |
| GratisVPS | 1 vCPU / 512 MB–1 GB | ❌ nein | ❌ zu klein für Browser |
| VPSWala | 1 ARM vCPU / 2 GB | ❌ nein | ❌ grenzwertig + Vertrauensfrage |
| Fly.io / Render free | 256–512 MB | ❌ nein | ❌ zu klein |
| Cloudflare Workers | Serverless | ❌ nein | ❌ kein Browser möglich |

Quellen: [HF-Free-Tier](https://toolfreebie.com/hugging-face-spaces-free-gpu/),
[n8n-auf-Spaces (16 GB/Docker-Beleg)](https://tomo.dev/en/posts/deploy-n8n-for-free-using-huggingface-space/),
[HF-Pricing](https://www.metacto.com/blogs/the-true-cost-of-hugging-face-a-guide-to-pricing-and-integration),
[Codespaces 120 h ohne Karte](https://cosyra.com/guides/codespaces-on-iphone.html),
[30-min-Idle](https://github.com/orgs/community/discussions/193854),
[No-Card-Vergleich](https://vashishthakapoor.com/best-free-vps-hosting/),
[TopTech-Vergleich](https://toptechalternative.com/free-vps-hosting/).

### C.3 Empfohlene Architektur ohne Karte: HF Space als Hände

```
Handy: Operit AI (OpenRouter :free, 50 Req/Tag ohne Einzahlung)
  │  HTTPS (public *.hf.space-URL + fetter CAMOFOX_ACCESS_KEY als Bearer)
  ▼
HF Space (Docker, gratis, ohne Karte): camofox REST :9377 (+ MCP-Bridge :8000 via Reverse-Proxy)
  │  camofox-Browser läuft IN der 16-GB-Kiste (mehr RAM als Oracle-Free!)
  ▼
Gehirn bleibt OpenRouter (Denken), Space macht nur die Klicks
```

**Konditionen (verifiziert):**
- Docker-Spaces: `sdk: docker` im README-YAML, Default-Port `7860`, per `app_port`
  änderbar; Secrets werden zur Laufzeit als Env-Vars injiziert; Container läuft als
  **UID 1000**; Platte ist **flüchtig** (Restart = alles weg, Persistenz nur via
  Storage-Bucket/Datasets/extern). Quelle: [HF Docker-Spaces-Doku](https://huggingface.co/docs/hub/spaces-sdks-docker)
- Sleep nach **48 h Idle**, Wake bei Besuch in ~30–90 s; gratis Spaces sind **public**
  (Custom-Domain/privat = Pro $9/Monat). Quelle: [HF-Free-Tier](https://toolfreebie.com/hugging-face-spaces-free-gpu/)
- Unsere `Dockerfile` passt fast: Camoufox wird zur Build-Zeit reingebacken (Build-Netz
  bei HF ist offen), nötig ist nur eine HF-Variante (`Dockerfile.hf`): User mit UID 1000,
  Cache/Pfade unter `/home/user`, Port via `app_port`, Secrets als Env.
- ✅ **Umgesetzt (08.09.2026): `docs/free-vps/hf-space/`** — `Dockerfile`, `start.sh`,
  `nginx.conf.template`, Space-`README.md`, Laien-`ANLEITUNG.md`. Der Space braucht nur
  Dockerfile+README.md; App-Code, start.sh und nginx-Template kommen zur Build-Zeit per
  `git clone` aus diesem Branch. nginx (einzige Tür, :7860, non-root, temp-Pfade unter
  `/home/user/app/run`) routet `/` → camofox-REST (127.0.0.1:9377, Auth macht camofox
  selbst), `/mcp` → supergateway-Streamable-HTTP (:8001, `--stateful`), `/sse`+`/message` →
  supergateway-SSE (:8002, nur wenn `PUBLIC_BASE_URL` gesetzt). MCP-Routen prüfen
  `Authorization: Bearer` **oder** `?key=` (SSE: nur Bearer — die `/message`-URL kommt
  vom Server ohne Query zurück). Fallen beim Bau vermieden: `$PORT` heißt `NGINX_PORT`
  (Server+MCP lesen `$PORT` als Fallback!), `CAMOFOX_BASE_URL` explizit gesetzt,
  Camoufox-Pins identisch zu `/Dockerfile` (Lib-Kompat).

**Haken, offen benannt:**
1. Public-URL ⇒ `CAMOFOX_ACCESS_KEY` (64-hex) ist Pflicht, kein Nice-to-have.
2. Flüchtige Platte ⇒ Browser-Profile/Cookies nach Rebuild weg; Setup bleibt
   reproduzierbar (Docker-Build), Cookies bei Bedarf re-importieren.
3. Sleep ⇒ erster Aufruf des Tages dauert ~1 Minute (für Laien-Alltag ok, für 24/7-Agenten nicht).
4. Operit↔Space braucht die MCP-Bridge (supergateway, s. Anhang B) — im Space per
   Nginx-Reverse-Proxy auf einen Port legen (HF exponiert nur einen Port nach außen).

### C.4 Zweit- und Drittwege

- **GitHub Codespaces** (120 Core-h/Monat, ohne Karte): perfekt, um `Dockerfile.hf`
  zu bauen/testen und per Port-Forwarding kurz vom Handy zu erreichen; Idle-Stopp nach
  30 Min ⇒ kein Dauerbetrieb.
- **Ganz ohne Server:** Operit AI hat Web-Browsing + Deep Search eingebaut — für
  Recherche-Tasks reicht Handy + OpenRouter oft schon; camofox dann später nachrüsten.
- **Später:** echte Visa/Mastercard-Debit einer echten Bank (kein virtuell/prepaid) hat
  bei Oracle die besten Chancen — aber ohne Garantie, erst versuchen wenn's sich ergibt.

### C.5 Update 08.09.2026 nachmittags: Docker braucht PRO — Gradio-Wrapper ist der neue Weg

Der Nutzer hat am New-Space-Screen gemeldet: Docker-SDK nur mit PRO wählbar. Verifiziert —
offizielle Doku: „Gradio and Docker Spaces run on compute and require a paid plan to create:
PRO for personal accounts" — gratis bleiben Static (unbegrenzt) und **bis zu 2 Gradio-Spaces
auf ZeroGPU** für Konten „in good standing":
[Spaces-Overview](https://huggingface.co/docs/hub/en/spaces-overview),
[Spaces-Launch](https://huggingface.co/spaces/launch),
[Pricing](https://huggingface.co/pricing) (PRO $9/Monat: „Host your own ZeroGPU, Gradio & Docker Spaces").
ZeroGPU-Details: Gradio-only, GPU-Zuteilung nur während aktiver Inferenz (idle kostet nichts),
Free: 5 GPU-Min/Tag + 2 Spaces ([aiweekly 31.08.2026](https://aiweekly.co/learning-ai/machine-learning/how-to-use-hugging-face)).
Unsere App ruft nie GPU auf → 0 Min Verbrauch; der Space läuft als normaler CPU-Container
(2 vCPU/16 GB). Präzedenz für Non-Gradio-Apps auf Gradio-SDK: n8n-Tutorial ([tomo.dev](https://tomo.dev/en/posts/deploy-n8n-for-free-using-huggingface-space/)).

**Neue Umsetzung: `docs/free-vps/hf-space/gradio/`** (Docker-Variante in `hf-space/` bleibt
für PRO-Nutzer gültig):
- Space braucht 3 Paste-Dateien: `app.py` (30-Zeilen-Bootstrap: lädt Branch-ZIP, entpackt,
  exekutiert Launcher aus dem Repo = Single Source of Truth), `packages.txt` (apt-Libs +
  Fonts + build-essential, als root zur Build-Zeit — Feature verifiziert:
  [hub-docs spaces-dependencies](https://github.com/huggingface/hub-docs/blob/main/docs/hub/spaces-dependencies.md)),
  `README.md` (`sdk: gradio`). Kein `requirements.txt` nötig (nur Stdlib).
- `launcher.py` (repo-seitig, jederzeit fixbar ohne Re-Paste): lädt Node-v22.22.3-Tarball,
  `npm ci` (postinstall holt dabei den Lib-kompatiblen Browser; Fallback: `--ignore-scripts` +
  pinned Direkt-Download v135.0.1-beta.24 ohne GitHub-API), installiert `supergateway@3`
  nach `~/.local`, startet REST (127.0.0.1:9377, wartet auf /health), Bridges (:8001
  streamable `--stateful`, :8002 SSE nur mit `PUBLIC_BASE_URL`), exekutiert `proxy.mjs`.
- `proxy.mjs` (null Deps): eine Tür (`APP_PORT`, Default 7860 — nie `$PORT`!),
  `/` → 9377, `/mcp` → 8001 (Bearer ODER `?key=`), `/sse`+`/message` → 8002 (nur Bearer,
  kein Upstream-Timeout auf `/sse`). Funktional in der Sandbox getestet (401-Fälle,
  Weiterleitung inkl. Body/Query, `/health`-Passthrough).
- Code-Fakten: xvfb optional (server.js fällt auf headless zurück), better-sqlite3 wird
  von server.js/lib nirgends importiert (npm-Fallback ungefährlich).
- ANLEITUNG.md auf Gradio umgeschrieben (3 Dateien, ZeroGPU-Hinweis, längere Zeiten:
  Build 10–20 Min + Erststart 5–10 Min, Sleep-Wake 5–10 Min).



