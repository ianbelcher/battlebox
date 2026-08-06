# Build stage: export the Godot project several times from the same source —
# a headless Linux server binary, native desktop clients (Linux, Windows,
# macOS) that the web role serves as downloads, and a browser build.
#
# The browser build renders with gl_compatibility (WebGL2) rather than the
# Forward+ the desktop clients use; project.godot sets that per-platform,
# so it is the same source with no separate configuration.
FROM ubuntu:24.04 AS build

ARG GODOT_VERSION=4.7.1
ARG GIT_SHA=dev

RUN apt-get update \
    && apt-get install -y --no-install-recommends wget unzip ca-certificates libfontconfig1 \
    && rm -rf /var/lib/apt/lists/*

RUN wget -q "https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}-stable/Godot_v${GODOT_VERSION}-stable_linux.x86_64.zip" \
    && unzip -q "Godot_v${GODOT_VERSION}-stable_linux.x86_64.zip" \
    && mv "Godot_v${GODOT_VERSION}-stable_linux.x86_64" /usr/local/bin/godot \
    && rm "Godot_v${GODOT_VERSION}-stable_linux.x86_64.zip"

RUN wget -q "https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}-stable/Godot_v${GODOT_VERSION}-stable_export_templates.tpz" \
    && mkdir -p "/root/.local/share/godot/export_templates/${GODOT_VERSION}.stable" \
    && unzip -q "Godot_v${GODOT_VERSION}-stable_export_templates.tpz" -d /tmp/templates \
    && mv /tmp/templates/templates/* "/root/.local/share/godot/export_templates/${GODOT_VERSION}.stable/" \
    && rm -rf /tmp/templates "Godot_v${GODOT_VERSION}-stable_export_templates.tpz"

COPY game /game
RUN echo "$GIT_SHA" > /game/version.txt

# First import populates the .godot cache; it can exit non-zero on a cold
# cache even when it succeeds, hence the guard.
RUN godot --headless --path /game --import || true

RUN mkdir -p /game/build/server /game/build/downloads /game/build/play \
    && godot --headless --path /game --export-release "Linux Server" build/server/world-server.x86_64 \
    && godot --headless --path /game --export-release "Linux Client" build/downloads/voxel-battle-linux.x86_64 \
    && godot --headless --path /game --export-release "Windows Client" build/downloads/voxel-battle-windows.exe \
    && godot --headless --path /game --export-release "macOS Client" build/downloads/voxel-battle-macos.zip \
    && godot --headless --path /game --export-release "Web" build/play/index.html \
    && cp /game/version.txt /game/build/downloads/version.txt \
    && cp /game/version.txt /game/build/play/version.txt

# Runtime stage: one image, two roles. The k8s deployment runs two containers
# from this image — `server` (the world) and `web` (nginx serving the
# downloads page over http, and the browser game over https).
#
# The browser game MUST be https: it needs SharedArrayBuffer for Godot's
# worker threads, and browsers only grant that to a "cross-origin isolated"
# page, which requires a secure context. openssl is here to mint the
# self-signed certificate that provides one (see entrypoint.sh).
FROM ubuntu:24.04

RUN apt-get update \
    && apt-get install -y --no-install-recommends nginx openssl ca-certificates libfontconfig1 \
    && rm -rf /var/lib/apt/lists/*

# The browser build is served as application/wasm or it will not start.
# Assert it rather than trust it: a silently-wrong content type would look
# like a game bug, not a packaging one.
RUN grep -q "application/wasm" /etc/nginx/mime.types

COPY nginx.conf /etc/nginx/nginx.conf

# Check the config against THIS nginx, at build time.
#
# A config that is valid on a newer nginx and invalid here does not fail
# quietly: nginx refuses to start, the web container crash-loops, the pod
# never becomes ready, and Kubernetes then pulls the GAME SERVER out of
# its Service as well — so a typo in a web server config takes the whole
# game offline. That happened with "http2 on;", which is 1.25.1+ while
# this image is on 1.24.
#
# nginx -t needs the certificate files to exist, so mint a throwaway pair
# purely for the test and delete them; the real one is created at startup
# on the shared volume.
RUN mkdir -p /opt/world/tls \
    && openssl req -x509 -newkey rsa:2048 -nodes -days 1 \
       -keyout /opt/world/tls/world.key -out /opt/world/tls/world.crt \
       -subj "/CN=config check" >/dev/null 2>&1 \
    && nginx -t \
    && rm -f /opt/world/tls/world.crt /opt/world/tls/world.key

COPY --from=build /game/build/server /opt/world/server
COPY maps /opt/world/maps
COPY --from=build /game/build/downloads /opt/world/web/downloads
COPY --from=build /game/build/play /opt/world/web/play
COPY web/index.html /opt/world/web/index.html
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh /opt/world/server/world-server.x86_64

EXPOSE 9081 8081 8443
ENTRYPOINT ["/entrypoint.sh"]
CMD ["server"]
