FROM node:22-slim

ENV NODE_ENV=production
ENV HOME=/app
ENV PATH="/app/.local/bin:${PATH}"

WORKDIR /app

RUN apt-get update \
  && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    tar \
    bash \
    sed \
    grep \
    socat \
  && rm -rf /var/lib/apt/lists/*

# Pin Agentmemory for reproducible Railway builds.
RUN npm install -g @agentmemory/agentmemory@0.9.27

# Pin iii-engine to v0.11.2.
# Agentmemory 0.9.x currently expects this engine generation.
RUN mkdir -p /app/.local/bin \
  && curl -fsSL "https://github.com/iii-hq/iii/releases/download/iii/v0.11.2/iii-x86_64-unknown-linux-gnu.tar.gz" \
  | tar -xz -C /app/.local/bin \
  && chmod +x /app/.local/bin/iii

RUN mkdir -p /data /app

COPY start.sh /app/start.sh
RUN chmod +x /app/start.sh

# REST API (Railway domain targets this), streams, viewer, and the
# socat-republished viewer that the caddy service proxies. The engine
# bridge (49134) stays container-local and is deliberately not exposed.
EXPOSE 3111
EXPOSE 3112
EXPOSE 3113
EXPOSE 8083

CMD ["/app/start.sh"]
