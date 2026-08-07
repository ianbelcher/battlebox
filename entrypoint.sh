#!/usr/bin/env sh

# Shell 'strict' mode
set -ue

# One image, two roles. `server` is the world; `web` is nginx serving the
# entry page, the native downloads and the browser build, and proxying the
# game socket through to `server` on loopback.
#
# TLS is deliberately NOT here. The public deployment puts Caddy in front
# holding a real Let's Encrypt certificate for battlebox.games, with
# Cloudflare in front of that. This image used to mint its own self-signed
# certificate, which meant every player clicked through a browser warning
# before they could play; a real certificate is both safer and one less
# thing for a nine-year-old to get past.

ROLE="${1:-server}"

case "$ROLE" in
  server)
    exec /opt/battlebox/server/battlebox-server.x86_64 --headless
    ;;
  web)
    exec nginx -g "daemon off;"
    ;;
  *)
    echo "Unknown role '$ROLE' (expected 'server' or 'web')" >&2
    exit 1
    ;;
esac
