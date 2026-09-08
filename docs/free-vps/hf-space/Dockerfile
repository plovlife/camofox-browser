# Camofox-Browser für Hugging Face Spaces (Docker-SDK) — gratis, ohne Kreditkarte.
# Der Space braucht nur 2 Dateien: diese Dockerfile + README.md. Alles andere
# (App-Code, start.sh, nginx-Template) kommt per git clone aus dem Branch unten.
#
# HF-Spielregeln (huggingface.co/docs/hub/spaces-sdks-docker): Container läuft als
# UID 1000, ein Port nach außen (Default 7860, via app_port änderbar), Secrets kommen
# zur Laufzeit als Env-Vars, Platte ist flüchtig (Restart = alles weg).
#
# Basis: node:22-trixie-slim wie /Dockerfile (glibc 2.41 für better-sqlite3-Prebuilds).

FROM node:22-trixie-slim

ARG CAMOFOX_REPO=https://github.com/plovlife/camofox-browser.git
ARG CAMOFOX_BRANCH=arena/01a07f48-camofox-browser
# Camoufox-Browser, zur Build-Zeit reingebacken. Absichtlich DIESELBEN Pins wie
# /Dockerfile (nicht "latest"): Browser und camoufox-js-Lib müssen zusammenpassen.
ARG CAMOUFOX_VERSION=135.0.1
ARG CAMOUFOX_RELEASE=beta.24
ARG ARCH=x86_64

# --- root-Phase: Systempakete + globaler MCP-Gateway + HF-User anlegen ---
RUN apt-get update && apt-get install -y --no-install-recommends \
    libgtk-3-0 libdbus-glib-1-2 libxt6 libasound2 libx11-xcb1 libxcomposite1 \
    libxcursor1 libxdamage1 libxfixes3 libxi6 libxrandr2 libxrender1 libxss1 libxtst6 \
    libegl1 libgl1-mesa-dri libgbm1 \
    xvfb \
    fonts-liberation fonts-noto-color-emoji fontconfig \
    nginx gettext-base \
    git curl unzip ca-certificates build-essential python3 python3-minimal \
    && rm -rf /var/lib/apt/lists/*

# yt-dlp für YouTube-Transkripte (wie /Dockerfile)
RUN curl -fL -o /usr/local/bin/yt-dlp "https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp" \
    && chmod 755 /usr/local/bin/yt-dlp

# supergateway: macht aus dem MCP-stdio-Server einen HTTP-MCP-Server (fürs Handy)
RUN npm install -g supergateway@3

# HF-User (Container läuft als UID 1000 — am Ende gehört ihm alles)
RUN useradd -m -u 1000 user
ENV HOME=/home/user \
    PATH=/home/user/.local/bin:$PATH \
    NODE_ENV=production \
    CAMOFOX_PORT=9377

# --- App als root aufbauen, danach alles dem HF-User schenken ---
WORKDIR /home/user/app
RUN git clone --depth 1 -b "${CAMOFOX_BRANCH}" "${CAMOFOX_REPO}" src

WORKDIR /home/user/app/src
RUN npm ci --omit=dev
RUN sh scripts/install-plugin-deps.sh || echo "WARNUNG: plugin-deps teilweise fehlgeschlagen (Server läuft trotzdem)"

# Camoufox-Binary einbacken (gleicher Flow wie /Dockerfile, nur unter /home/user)
RUN mkdir -p /home/user/.cache/camoufox \
    && curl -fL -o /tmp/camoufox.zip "https://github.com/daijro/camoufox/releases/download/v${CAMOUFOX_VERSION}-${CAMOUFOX_RELEASE}/camoufox-${CAMOUFOX_VERSION}-${CAMOUFOX_RELEASE}-lin.${ARCH}.zip" \
    && (unzip -q /tmp/camoufox.zip -d /home/user/.cache/camoufox || true) \
    && rm /tmp/camoufox.zip \
    && chmod -R 755 /home/user/.cache/camoufox \
    && echo "{\"version\":\"${CAMOUFOX_VERSION}\",\"release\":\"${CAMOUFOX_RELEASE}\"}" > /home/user/.cache/camoufox/version.json \
    && test -f /home/user/.cache/camoufox/camoufox-bin && echo "Camoufox installiert ✅"

# Start-Skript + nginx-Template aus dem geclonten Branch übernehmen
# (Single Source of Truth: docs/free-vps/hf-space/ — kein Copy-Paste-Drift)
RUN cp /home/user/app/src/docs/free-vps/hf-space/start.sh /home/user/app/start.sh \
    && cp /home/user/app/src/docs/free-vps/hf-space/nginx.conf.template /home/user/app/nginx.conf.template \
    && chmod +x /home/user/app/start.sh \
    && chown -R user:user /home/user

USER user
WORKDIR /home/user/app
EXPOSE 7860
CMD ["/home/user/app/start.sh"]
