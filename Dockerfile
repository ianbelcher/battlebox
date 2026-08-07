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
    && godot --headless --path /game --export-release "Linux Server" build/server/battlebox-server.x86_64 \
    && godot --headless --path /game --export-release "Linux Client" build/downloads/battlebox-linux.x86_64 \
    && godot --headless --path /game --export-release "Windows Client" build/downloads/battlebox-windows.exe \
    && godot --headless --path /game --export-release "macOS Client" build/downloads/battlebox-macos.zip \
    && godot --headless --path /game --export-release "Web" build/play/index.html \
    && cp /game/version.txt /game/build/downloads/version.txt \
    && cp /game/version.txt /game/build/play/version.txt

# Runtime stage: one image, two roles. The deployment runs two containers
# from this image — `server` (the world) and `web` (nginx serving the entry
# page, the native downloads and the browser build). They share a network
# namespace, so nginx proxies the game socket to the server on loopback.
#
# No TLS in here. Caddy terminates https for battlebox.games in front of
# this, with Cloudflare in front of that — see deploy/.
FROM ubuntu:24.04

RUN apt-get update \
    && apt-get install -y --no-install-recommends nginx ca-certificates libfontconfig1 curl \
    && rm -rf /var/lib/apt/lists/*

# The browser build is served as application/wasm or it will not start.
# Assert it rather than trust it: a silently-wrong content type would look
# like a game bug, not a packaging one.
RUN grep -q "application/wasm" /etc/nginx/mime.types

COPY nginx.conf /etc/nginx/nginx.conf

# Check the config against THIS nginx, at build time.
#
# A config that is valid on a newer nginx and invalid here does not fail
# quietly: nginx refuses to start and the web container crash-loops, so the
# site is down while the image looks fine. That happened once with
# "http2 on;", which is 1.25.1+ while this image is on 1.24. Catching it
# here means a bad config fails the build instead of the deployment.
RUN nginx -t

COPY --from=build /game/build/server /opt/battlebox/server
COPY maps /opt/battlebox/maps
COPY --from=build /game/build/downloads /opt/battlebox/web/downloads
COPY --from=build /game/build/play /opt/battlebox/web/play
COPY web/index.html /opt/battlebox/web/index.html
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh /opt/battlebox/server/battlebox-server.x86_64

EXPOSE 9081 8081
ENTRYPOINT ["/entrypoint.sh"]
CMD ["server"]
