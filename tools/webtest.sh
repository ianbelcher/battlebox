#!/usr/bin/env bash
#
# Prove the browser build actually works, in a real browser.
#
#   deployments/world/tools/webtest.sh
#
# Exports the Web preset, serves it over local https with the PRODUCTION
# nginx.conf (paths rewritten, nothing else), starts a headless world
# server, and drives the whole thing in headless Chrome.
#
# It asserts the three things that are each individually fatal and each
# individually invisible:
#   - the page is cross-origin isolated  (no isolation -> no threads)
#   - SharedArrayBuffer exists           (no SAB -> Godot dies on startup)
#   - the game reaches the world server over wss
# and then joins a player, because loading is not playing.
#
# Needs: godot 4.7.1 with web export templates, nginx, node, Google Chrome.

set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(dirname "$HERE")"
GAME="$ROOT/game"
WORK="${WORLD_WEBTEST_DIR:-/tmp/world-webtest}"
PORT_HTTPS=8443
PORT_GAME=9081

echo "==> exporting the Web build"
mkdir -p "$GAME/build/play"
godot --headless --path "$GAME" --export-release "Web" "$GAME/build/play/index.html" \
  2>&1 | tail -2

echo "==> staging into $WORK"
rm -rf "$WORK"
mkdir -p "$WORK"/{tls,www/play,logs,data}
cp -r "$GAME/build/play/." "$WORK/www/play/"
cp "$ROOT/web/index.html" "$WORK/www/index.html"

# A throwaway certificate for the test. Production mints its own on the
# shared volume; this one only has to make the browser treat the page as a
# secure context.
openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
  -keyout "$WORK/tls/world.key" -out "$WORK/tls/world.crt" \
  -subj "/CN=Voxel Battle test" \
  -addext "subjectAltName=DNS:localhost,IP:127.0.0.1" >/dev/null 2>&1

# The real nginx.conf with only the paths moved — testing a hand-written
# copy of the config would prove nothing about the one we ship.
MIME="$(nginx -V 2>&1 | tr ' ' '\n' | grep -- '--conf-path=' | cut -d= -f2)"
MIME="$(dirname "${MIME:-/etc/nginx/nginx.conf}")/mime.types"
python3 - "$ROOT/nginx.conf" "$WORK" "$MIME" <<'PY'
import sys
src, work, mime = sys.argv[1], sys.argv[2], sys.argv[3]
s = open(src).read()
s = s.replace('user www-data;\n', '')
s = s.replace('pid /run/nginx.pid;', f'pid {work}/nginx.pid;')
s = s.replace('include /etc/nginx/mime.types;', f'include {mime};')
s = s.replace('/opt/world/tls', f'{work}/tls')
s = s.replace('/opt/world/web', f'{work}/www')
s = s.replace('events {', f'error_log {work}/logs/error.log warn;\nevents {{')
open(f'{work}/nginx.conf', 'w').write(s)
PY

cleanup() {
  nginx -s quit -c "$WORK/nginx.conf" -p "$WORK" 2>/dev/null || true
  [ -n "${SERVER_PID:-}" ] && kill "$SERVER_PID" 2>/dev/null || true
}
trap cleanup EXIT

echo "==> starting nginx and a world server"
nginx -t -c "$WORK/nginx.conf" -p "$WORK" 2>&1 | tail -1
nginx -c "$WORK/nginx.conf" -p "$WORK"
WORLD_DATA_DIR="$WORK/data" WORLD_PORT="$PORT_GAME" \
  godot --headless --path "$GAME" > "$WORK/logs/server.log" 2>&1 &
SERVER_PID=$!
sleep 8
grep -i listening "$WORK/logs/server.log" || { echo "server never listened"; exit 1; }

echo "==> driving it in Chrome"
cd "$WORK"
npm init -y >/dev/null 2>&1
npm install puppeteer-core >/dev/null 2>&1
cp "$HERE/webtest_play.js" "$WORK/play.js"
node play.js "https://localhost:$PORT_HTTPS/play/" 90 "$WORK/shot.png"
