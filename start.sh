#!/usr/bin/env bash
set -euo pipefail

export HOME=/app
export PATH="/app/.local/bin:${PATH}"

# agentmemory derives its whole port quartet from the REST anchor:
# streams = REST+1, viewer = REST+2, iii-engine bridge = REST+46023.
# The engine binary always binds its bridge on the fixed default 49134,
# so only a 3111 anchor lines up. Anchoring on Railway's $PORT (8080)
# made the worker dial ws://localhost:54103, where nothing listens, so
# it never registered and every /agentmemory/* route returned 404.
# The Railway service domain must target container port 3111.
REST_PORT=3111

# Persistent Railway volume paths.
export III_DATA_DIR="${III_DATA_DIR:-/data}"
export AGENTMEMORY_DATA_DIR="${AGENTMEMORY_DATA_DIR:-/data}"

mkdir -p /data
mkdir -p /app
mkdir -p /app/.agentmemory

echo "[railway] Starting agentmemory"
echo "[railway] REST_PORT=${REST_PORT}"
echo "[railway] HOME=${HOME}"
echo "[railway] III_DATA_DIR=${III_DATA_DIR}"
echo "[railway] AGENTMEMORY_DATA_DIR=${AGENTMEMORY_DATA_DIR}"

echo "[railway] Fixing /data permissions..."
chown -R 65532:65532 /data || true
chmod 755 /data || true

echo "[railway] Testing /data write access..."
echo "ok" > /data/.railway-write-test
cat /data/.railway-write-test
rm -f /data/.railway-write-test

DIST_DIR="/usr/local/lib/node_modules/@agentmemory/agentmemory/dist"
SOURCE_CONFIG="${DIST_DIR}/iii-config.docker.yaml"
DEFAULT_CONFIG="${DIST_DIR}/iii-config.yaml"
RAILWAY_CONFIG="/app/iii-config.railway.yaml"

if [ ! -f "$SOURCE_CONFIG" ]; then
  echo "[railway] ERROR: missing ${SOURCE_CONFIG}"
  echo "[railway] dist content:"
  ls -la "$DIST_DIR" || true
  exit 1
fi

# Start from Agentmemory's official Docker config.
cp "$SOURCE_CONFIG" "$RAILWAY_CONFIG"

# iii-config.docker.yaml already binds 0.0.0.0 and uses /data paths;
# these stay as a guard in case the upstream source config changes.
# Do NOT patch viewer ports or compiled JS files.
sed -i "s/host: 127.0.0.1/host: 0.0.0.0/g" "$RAILWAY_CONFIG"
sed -i "s/host: localhost/host: 0.0.0.0/g" "$RAILWAY_CONFIG"

# The REST port stays at the config's canonical 3111 so the engine
# bridge (49134) and streams (3112) stay aligned with the anchor.

# Agentmemory internally loads this default config path.
cp "$RAILWAY_CONFIG" "$DEFAULT_CONFIG"

echo "[railway] Overwrote default config:"
echo "[railway] ${DEFAULT_CONFIG}"

echo "[railway] Effective config preview:"
cat "$DEFAULT_CONFIG"

echo "[railway] Expected:"
echo "[railway] API listener should be 0.0.0.0:${REST_PORT}"
echo "[railway] Stream listener should be 0.0.0.0:3112"
echo "[railway] Engine bridge should be ws://localhost:49134"
echo "[railway] Viewer should be 127.0.0.1:3113 (republished via socat)"

echo "[railway] Writing /app/.agentmemory/.env from Railway variables..."

cat > /app/.agentmemory/.env <<EOF
AGENTMEMORY_DATA_DIR=${AGENTMEMORY_DATA_DIR}
III_DATA_DIR=${III_DATA_DIR}
AGENTMEMORY_REQUIRE_HTTPS=${AGENTMEMORY_REQUIRE_HTTPS:-1}
AGENTMEMORY_SECRET=${AGENTMEMORY_SECRET:-}
PUBLIC_AGENTMEMORY_URL=${PUBLIC_AGENTMEMORY_URL:-}
AGENTMEMORY_AUTO_COMPRESS=${AGENTMEMORY_AUTO_COMPRESS:-false}
AGENTMEMORY_INJECT_CONTEXT=${AGENTMEMORY_INJECT_CONTEXT:-false}
EOF

echo "[railway] Writing /app/.agentmemory/preferences.json to skip interactive first-run..."

cat > /app/.agentmemory/preferences.json <<EOF
{
  "schemaVersion": 1,
  "lastAgent": null,
  "lastAgents": [],
  "lastProvider": null,
  "skipSplash": true,
  "skipNpxHint": true,
  "skipGlobalInstall": true,
  "skipConsoleInstall": true,
  "firstRunAt": "2026-05-15T00:00:00.000Z"
}
EOF

chmod 600 /app/.agentmemory/.env || true
chmod 600 /app/.agentmemory/preferences.json || true

echo "[railway] Agentmemory env preview:"
grep -v "SECRET" /app/.agentmemory/.env || true

echo "[railway] Agentmemory preferences preview:"
cat /app/.agentmemory/preferences.json || true

echo "[railway] Node homedir check:"
node -e 'const os=require("os"); console.log(os.homedir())'

echo "[railway] Launching agentmemory..."

# The viewer binds 127.0.0.1 (src/viewer/server.ts resolveViewerHost),
# so Railway's network can't reach it directly. socat republishes it on
# 8083, which the caddy service fronts with basic auth. The viewer sits
# at REST+2 = 3113, so it moves with the anchor.
export VIEWER_PUBLIC_PORT="${VIEWER_PUBLIC_PORT:-8083}"
export VIEWER_INTERNAL_PORT="${VIEWER_INTERNAL_PORT:-3113}"

# The viewer refuses any Host header outside its allowlist as a
# DNS-rebinding defence (src/viewer/server.ts isHostAllowed), and on a
# loopback bind that allowlist only covers localhost/127.0.0.1. Caddy
# forwards the browser's original Host, so the public caddy domain must
# be listed explicitly or every proxied request is refused. Allow the
# private hop too, in case the proxy rewrites Host to the upstream.
VIEWER_HOSTS_DEFAULT="${RAILWAY_PRIVATE_DOMAIN:-agentmemory.railway.internal}:${VIEWER_PUBLIC_PORT}"
if [ -n "${RAILWAY_SERVICE_AGENTMEMORY_VIEWER_CADDY_URL:-}" ]; then
  VIEWER_HOSTS_DEFAULT="${VIEWER_HOSTS_DEFAULT},${RAILWAY_SERVICE_AGENTMEMORY_VIEWER_CADDY_URL}"
fi
export VIEWER_ALLOWED_HOSTS="${VIEWER_ALLOWED_HOSTS:-${VIEWER_HOSTS_DEFAULT}}"

echo "[railway] VIEWER_ALLOWED_HOSTS=${VIEWER_ALLOWED_HOSTS}"
echo "[railway] Starting viewer proxy:"
echo "[railway] [::]:${VIEWER_PUBLIC_PORT} (dual-stack) -> 127.0.0.1:${VIEWER_INTERNAL_PORT}"

# Bind IPv6 with ipv6only=0 (dual-stack). Railway environments created
# before 2025-10-16 resolve *.railway.internal to IPv6 addresses ONLY,
# so an IPv4-only 0.0.0.0 listener is unreachable over private
# networking and the caddy service in front of it 502s.
socat TCP6-LISTEN:${VIEWER_PUBLIC_PORT},ipv6only=0,fork,reuseaddr TCP:127.0.0.1:${VIEWER_INTERNAL_PORT} &

exec agentmemory \
  --port "${REST_PORT}" \
  --verbose