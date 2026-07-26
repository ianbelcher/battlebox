#!/usr/bin/env sh

# Shell 'strict' mode
set -ue

ROLE="${1:-server}"

case "$ROLE" in
  server)
    exec /opt/world/server/world-server.x86_64 --headless
    ;;
  web)
    exec nginx -g "daemon off;"
    ;;
  *)
    echo "Unknown role '$ROLE' (expected 'server' or 'web')" >&2
    exit 1
    ;;
esac
