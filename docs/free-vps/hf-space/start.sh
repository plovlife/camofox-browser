#!/usr/bin/env bash
# Camofox-Browser auf Hugging Face Spaces: startet REST-API (127.0.0.1:9377),
# MCP-Bridge(n) (Streamable HTTP :8001, optional SSE :8002) und nginx als
# einzige Tür nach außen (:7860). Läuft im Space-Container als User 1000.
set -euo pipefail

APP=/home/user/app
SRC="$APP/src"
RUN="$APP/run"
mkdir -p "$RUN"/tmp/{client,proxy,fastcgi,uwsgi,scgi}

# --- Pflicht-Secret (steht NIE im Repo, nur in Space Settings → Secrets) ---
if [ -z "${CAMOFOX_ACCESS_KEY:-}" ]; then
  echo "FEHLER: CAMOFOX_ACCESS_KEY ist nicht gesetzt!" >&2
  echo "Space Settings → Secrets → CAMOFOX_ACCESS_KEY=<dein-64-hex-key> (siehe ANLEITUNG.md Schritt 4)." >&2
  exit 1
fi

# Nginx-Port (HF-Standard 7860). Heißt absichtlich NICHT PORT — camofox würde
# $PORT sonst als eigenen Port lesen (lib/config.js) und mit nginx kollidieren.
NGINX_PORT="${NGINX_PORT:-7860}"
export CAMOFOX_ACCESS_KEY NGINX_PORT

# --- nginx-Konfig rendern (nur diese 2 Vars; $http_* usw. bleiben unangetastet) ---
envsubst '${CAMOFOX_ACCESS_KEY} ${NGINX_PORT}' < "$APP/nginx.conf.template" > "$RUN/nginx.conf"
nginx -t -c "$RUN/nginx.conf" -p "$RUN/"

# --- 1) camofox REST-API (nur Loopback — nginx ist die einzige Tür!) ---
cd "$SRC"
CAMOFOX_BIND_HOST=127.0.0.1 \
CAMOFOX_PORT=9377 \
CAMOFOX_CRASH_REPORT_ENABLED="${CAMOFOX_CRASH_REPORT_ENABLED:-false}" \
MAX_SESSIONS="${MAX_SESSIONS:-3}" \
MAX_TABS_PER_SESSION="${MAX_TABS_PER_SESSION:-5}" \
node --max-old-space-size="${MAX_OLD_SPACE_SIZE:-512}" server.js &

echo "warte auf camofox REST ..."
for _ in $(seq 1 45); do
  if curl -sf http://127.0.0.1:9377/health >/dev/null; then
    echo "camofox REST bereit ✅"
    break
  fi
  sleep 2
done
curl -sf http://127.0.0.1:9377/health >/dev/null || {
  echo "FEHLER: camofox REST startet nicht (Details stehen weiter oben im Log)."
  exit 1
}

# --- 2) MCP-Bridge(n) via supergateway (stdio → HTTP, fürs Handy) ---
# CAMOFOX_BASE_URL ist Pflicht: sonst würde die MCP-Config $PORT lesen und auf 7860 zeigen.
export CAMOFOX_BASE_URL=http://127.0.0.1:9377
export CAMOFOX_USER_ID="${CAMOFOX_USER_ID:-hf-space}"
export CAMOFOX_SESSION_KEY="${CAMOFOX_SESSION_KEY:-operit}"

supergateway --stdio "node $SRC/mcp/server.mjs" \
  --outputTransport streamableHttp --streamableHttpPath /mcp \
  --port 8001 --stateful &
echo "MCP Streamable HTTP bereit ✅ (→ /mcp)"

if [ -n "${PUBLIC_BASE_URL:-}" ]; then
  supergateway --stdio "node $SRC/mcp/server.mjs" \
    --port 8002 --baseUrl "$PUBLIC_BASE_URL" --ssePath /sse --messagePath /message &
  echo "MCP SSE bereit ✅ (→ /sse + /message)"
else
  echo "PUBLIC_BASE_URL nicht gesetzt → SSE-Brücke übersprungen (Streamable HTTP reicht für Operit)."
fi

# --- 3) nginx in den Vordergrund (Container lebt, solange nginx lebt) ---
exec nginx -c "$RUN/nginx.conf" -p "$RUN/" -g 'daemon off;'
