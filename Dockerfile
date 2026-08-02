FROM node:22-bookworm AS builder

ARG SOURCE_REVISION=unknown

ENV DEBIAN_FRONTEND=noninteractive \
    ELECTRON_SKIP_BINARY_DOWNLOAD=1 \
    NPM_CONFIG_PREFIX=/opt/npm-global

LABEL org.opencontainers.image.source="https://github.com/mzmrk/codex-web" \
      org.opencontainers.image.revision="$SOURCE_REVISION"

RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates curl git unzip \
    && rm -rf /var/lib/apt/lists/* \
    && mkdir -p /opt/codex-web /opt/npm-global \
    && chown -R node:node /opt/codex-web /opt/npm-global

USER node
WORKDIR /opt/codex-web

COPY --chown=node:node . .

RUN npm ci --no-audit --no-fund \
    && npm install --global --no-audit --no-fund @openai/codex@latest


FROM node:22-bookworm AS runtime

ARG SOURCE_REVISION=unknown

ENV DEBIAN_FRONTEND=noninteractive \
    HOME=/home/node \
    HOST=0.0.0.0 \
    PORT=8214 \
    CODEX_CLI_PATH=/opt/npm-global/bin/codex \
    CODEX_PASSWORDLESS_SUDO=false \
    PGID=1000 \
    PUID=1000 \
    NPM_CONFIG_PREFIX=/opt/npm-global \
    PATH=/opt/npm-global/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

LABEL org.opencontainers.image.source="https://github.com/mzmrk/codex-web" \
      org.opencontainers.image.revision="$SOURCE_REVISION"

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        git \
        gosu \
        g++ \
        make \
        patch \
        passwd \
        python3 \
        sudo \
        unzip \
    && rm -rf /var/lib/apt/lists/* \
    && mkdir -p /home/node/.codex /opt/npm-global \
    && chown -R node:node /home/node/.codex /opt/npm-global

COPY --from=builder --chown=node:node /opt/codex-web /opt/codex-web
COPY --from=builder --chown=node:node /opt/npm-global /opt/npm-global
COPY --chown=root:root --chmod=0755 docker/entrypoint.sh /usr/local/bin/codex-web-entrypoint

USER root
WORKDIR /opt/codex-web

EXPOSE 8214

ENTRYPOINT ["/usr/local/bin/codex-web-entrypoint"]
CMD ["node", "src/server/main.js", "--host", "0.0.0.0", "--port", "8214"]
