#!/usr/bin/env sh

# Shell 'strict' mode
set -ue

ROLE="${1:-server}"

# Where the https certificate is kept. This is on the shared volume ON
# PURPOSE: a certificate generated into the image would be a NEW one on
# every deploy, and because it is self-signed, every player would have to
# click through the browser's warning again every time we ship. Generated
# once and kept, everyone accepts it once and never sees it again.
TLS_STORE="${WORLD_TLS_DIR:-/data/tls}"
TLS_LIVE=/opt/world/tls
# Names the certificate claims. Browsers check the address you typed
# against this list, so the node's own IP has to be in it — that is what
# gets typed. Override to add a hostname.
TLS_HOSTS="${WORLD_TLS_HOSTS:-DNS:localhost,IP:127.0.0.1,IP:10.0.0.200}"

ensure_cert() {
  mkdir -p "$TLS_STORE" "$TLS_LIVE"
  if [ ! -f "$TLS_STORE/world.crt" ] || [ ! -f "$TLS_STORE/world.key" ]; then
    echo "No certificate in $TLS_STORE — generating one (valid 10 years)."
    # Ten years: an expired certificate would lock the kids out of the
    # game with an error they cannot click past, for no reason.
    openssl req -x509 -newkey rsa:2048 -nodes \
      -keyout "$TLS_STORE/world.key" -out "$TLS_STORE/world.crt" \
      -days 3650 -subj "/CN=Voxel Battle" \
      -addext "subjectAltName=$TLS_HOSTS" >/dev/null 2>&1 || true
  fi
  # Say so plainly if that did not work. nginx will refuse to start
  # without these two files, and this container also serves the downloads
  # page — so a silent failure here takes the native players down too,
  # with nothing in the log but a missing-file error from cp.
  if [ ! -s "$TLS_STORE/world.crt" ] || [ ! -s "$TLS_STORE/world.key" ]; then
    echo "FATAL: could not create a certificate in $TLS_STORE." >&2
    echo "  Is the volume writable? Retrying openssl with output:" >&2
    openssl req -x509 -newkey rsa:2048 -nodes \
      -keyout "$TLS_STORE/world.key" -out "$TLS_STORE/world.crt" \
      -days 3650 -subj "/CN=Voxel Battle" \
      -addext "subjectAltName=$TLS_HOSTS" >&2 || true
    [ -s "$TLS_STORE/world.crt" ] || exit 1
  fi
  # nginx runs as www-data and the volume is NFS; copy rather than point
  # at the share so a permissions quirk there cannot stop the web server.
  cp "$TLS_STORE/world.crt" "$TLS_LIVE/world.crt"
  cp "$TLS_STORE/world.key" "$TLS_LIVE/world.key"
  chmod 600 "$TLS_LIVE/world.key"
}

case "$ROLE" in
  server)
    exec /opt/world/server/world-server.x86_64 --headless
    ;;
  web)
    ensure_cert
    exec nginx -g "daemon off;"
    ;;
  *)
    echo "Unknown role '$ROLE' (expected 'server' or 'web')" >&2
    exit 1
    ;;
esac
