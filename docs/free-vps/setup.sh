#!/usr/bin/env bash
# ============================================================================
# camofox free-VPS bootstrap — Ubuntu 22.04/24.04 (ARM64 Ampere A1 oder x86_64)
#
# Setzt auf einem frischen VPS auf:
#   1. Node.js 22 + Build-Essentials
#   2. camofox-browser nach /opt/camofox-browser (inkl. Camoufox-Binary-Fetch)
#   3. systemd-Dienst, hart: loopback-only + Bearer-Key + Telemetry aus
#   4. Firewall (nur SSH; 9377 bleibt intern)
#   5. Keep-Alive gegen Oracle-Idle-Reclaim
#   6. optional (--with-ollama): Ollama, pullt qwen3.8:27b NUR wenn genug RAM
#
# Aufruf (als root oder via sudo):  sudo bash setup.sh [--with-ollama]
# Danach: Zugang via  ssh -L 9377:localhost:9377 <user>@<vps>
# ============================================================================
set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
  echo "FEHLER: bitte als root laufen lassen: sudo bash $0" >&2
  exit 1
fi

export DEBIAN_FRONTEND=noninteractive
APT="apt-get -y -o Dpkg::Options::=--force-confold"

echo "==> [1/6] Systempakete"
$APT update
$APT install git curl ca-certificates xz-utils openssl

# --- Node.js 22 -------------------------------------------------------------
need_node=1
if command -v node >/dev/null 2>&1; then
  major="$(node -p 'process.versions.node.split(".")[0]' 2>/dev/null || echo 0)"
  [ "${major:-0}" -ge 22 ] && need_node=0
fi
if [ "$need_node" -eq 1 ]; then
  echo "==> Installiere Node.js 22 (NodeSource)"
  curl -fsSL https://deb.nodesource.com/setup_22.x | bash -
  $APT install nodejs
fi
node --version

# --- Service-User -----------------------------------------------------------
echo "==> [2/6] Service-Account"
id -u camofox &>/dev/null || useradd -r -m -d /var/lib/camofox -s /usr/sbin/nologin camofox

# --- App-Code ---------------------------------------------------------------
APP=/opt/camofox-browser
if [ ! -d "$APP/.git" ]; then
  echo "==> [3/6] Clone camofox-browser"
  git clone --depth 1 https://github.com/jo-inc/camofox-browser "$APP"
else
  echo "==> [3/6] Repo vorhanden, Update"
  git -C "$APP" pull --ff-only || true
fi

# Auf einem VPS mit normalem Egress funktioniert der normale Installpfad:
# postinstall laedt das passende Camoufox-Binary (linux-arm64/-x86_64, ~650 MB).
cd "$APP"
sudo -u camofox -H env "PATH=$PATH" HOME=/var/lib/camofox \
  npm install --no-audit --no-fund

# Fetch absichern (idempotent; postinstall hat ihn ggf. schon durch)
sudo -u camofox -H env "PATH=$PATH" HOME=/var/lib/camofox \
  npx camoufox-js fetch || echo "WARN: camoufox fetch lief nicht durch -- Server prueft beim Start erneut"

# --- Konfiguration + Key ----------------------------------------------------
echo "==> [4/6] Config & API-Key"
mkdir -p /etc/camofox
ACCESS_KEY="$(openssl rand -hex 32)"
umask 077
cat > /etc/camofox/camofox.env <<EOF
CAMOFOX_PORT=9377
CAMOFOX_BIND_HOST=127.0.0.1
CAMOFOX_ACCESS_KEY=$ACCESS_KEY
CAMOFOX_ADMIN_KEY=$ACCESS_KEY
MAX_SESSIONS=3
MAX_TABS_PER_SESSION=5
BROWSER_IDLE_TIMEOUT_MS=300000
TAB_INACTIVITY_MS=300000
MAX_OLD_SPACE_SIZE=512
CAMOFOX_CRASH_REPORT_ENABLED=false
PROMETHEUS_ENABLED=1
EOF
chmod 600 /etc/camofox/camofox.env
echo "    API-Key (in Agent-/MCP-Config): $ACCESS_KEY"

# --- systemd ----------------------------------------------------------------
cat > /etc/systemd/system/camofox.service <<'EOF'
[Unit]
Description=camofox-browser - anti-detection browser REST API for AI agents
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=camofox
Group=camofox
Environment=HOME=/var/lib/camofox
EnvironmentFile=/etc/camofox/camofox.env
WorkingDirectory=/opt/camofox-browser
ExecStart=/usr/bin/node /opt/camofox-browser/server.js
Restart=always
RestartSec=5
MemoryMax=6G
TasksMax=512
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=full

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable --now camofox

# Firewall: nur SSH offen lassen (9377 bindet ohnehin auf 127.0.0.1)
if command -v ufw >/dev/null 2>&1; then
  ufw allow OpenSSH >/dev/null || true
  ufw --force enable >/dev/null || true
fi

# --- Keep-Alive gegen Oracle-Idle-Reclaim -----------------------------------
# Reclaim-Schwelle (Pure-Free-Accounts, 7-Tage-Fenster): CPU-p95 <20%,
# Netz <20%, RAM <20% (A1). Echte Nutzung ist der beste Schutz; der Pulse
# (taeglich 30 min Last auf 1 Kern, nice) ist die Basis-Absicherung.
echo "==> [5/6] Keep-Alive (Oracle Idle-Schutz)"
cat > /usr/local/bin/camofox-idle-pulse <<'EOF'
#!/bin/bash
# 30 min leichter CPU-Puls (1 Kern, nice) + health-Check + Mini-Egress.
logger -t camofox-idle-pulse "pulse start"
end=$((SECONDS + 1800))
while [ "$SECONDS" -lt "$end" ]; do
  dd if=/dev/zero bs=1M count=256 status=none | sha256sum >/dev/null
done
curl -sf http://127.0.0.1:9377/health >/dev/null 2>&1 || logger -t camofox-idle-pulse "health FAILED"
curl -sI --max-time 8 https://pypi.org/simple/ >/dev/null 2>&1 || true
logger -t camofox-idle-pulse "pulse done"
EOF
chmod +x /usr/local/bin/camofox-idle-pulse
cat > /etc/cron.d/camofox-keepalive <<'EOF'
# taeglich 03:17 UTC Reclaim-Puls; alle 30 min health-Log (fail-silent)
17 3 * * * root /usr/local/bin/camofox-idle-pulse >/var/log/camofox-idle-pulse.log 2>&1
*/30 * * * * root curl -sf http://127.0.0.1:9377/health >/dev/null 2>&1 || true
EOF

# --- optional: Ollama --------------------------------------------------------
echo "==> [6/6] Modell-Backend"
if [ "${1:-}" = "--with-ollama" ]; then
  curl -fsSL https://ollama.com/install.sh | sh
  TOTAL_GB=$(awk '/MemTotal/{printf "%d", $2/1048576}' /proc/meminfo)
  if [ "$TOTAL_GB" -ge 20 ]; then
    echo "    RAM=${TOTAL_GB}GB -> ollama pull qwen3.8:27b (18 GB)"
    ollama pull qwen3.8:27b || echo "WARN: pull fehlgeschlagen"
  else
    echo "    ACHTUNG: nur ${TOTAL_GB} GB RAM -> Qwen3.8-27B (Q4=18GB) passt LOCAL nicht."
    echo "    Empfehlung: Modell via Cloudflare Workers AI / Groq (kostenlose APIs,"
    echo "    siehe docs/free-vps-research.md Abschnitt 4) ODER lokal <=8B:"
    echo "      ollama pull llama3.1:8b   # grob 5 GB, laeuft noch brauchbar"
  fi
else
  cat <<'EOF'
    Modell laeuft NICHT lokal (Default, empfohlen):
      VPS = camofox + MCP  |  Gehirn = Qwen3.8-27B via kostenlose API
    Cloudflare Workers AI (Free Tier 10k Neurons/Tag, OpenAI-kompatibel):
      curl https://api.cloudflare.com/client/v4/accounts/$CF_ACCOUNT_ID/ai/v1/chat/completions \
        -H "Authorization: Bearer $CF_API_TOKEN" -H 'Content-Type: application/json' \
        -d '{"model":"@cf/qwen/qwen3.8-27b","messages":[{"role":"user","content":"hallo"}]}'
    Alternativ erneut ausfuehren mit:  --with-ollama
EOF
fi

# --- Smoke-Test ---------------------------------------------------------------
sleep 4
echo "==> Smoke-Test"
curl -sf http://127.0.0.1:9377/health && echo
echo "Fertig. Naechste Schritte:"
echo "  1) Tunnel vom Laptop:   ssh -L 9377:localhost:9377 <user>@<vps>"
echo "  2) Test:                curl -H 'Authorization: Bearer $ACCESS_KEY' http://127.0.0.1:9377/"
echo "  3) MCP-Config des Agenten (.mcp.json):"
echo '     {"mcpServers":{"camofox":{"command":"node","args":["/opt/camofox-browser/mcp/server.mjs"],'
echo '       "env":{"CAMOFOX_BASE_URL":"http://127.0.0.1:9377","CAMOFOX_ACCESS_KEY":"'$ACCESS_KEY'"}}}}'
