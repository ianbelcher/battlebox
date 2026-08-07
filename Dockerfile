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
# Truncated HERE rather than by the caller, so every build agrees on the
# format no matter who started it. deploy.sh and the workflow both compare
# what the site serves against this, and a full sha from one caller and a
# short one from another would read as "the deploy did not take".
RUN printf '%s\n' "$GIT_SHA" | cut -c1-12 > /game/version.txt

# First import populates the .godot cache; it can exit non-zero on a cold
# cache even when it succeeds, hence the guard.
RUN godot --headless --path /game --import || true

# Boot the project and refuse to build if any script failed to compile.
#
# This is not belt-and-braces, it is the only thing that catches it.
# `--export-release` succeeds with a GDScript parse error in the project:
# it packs the broken script and exits 0. The result installs, serves,
# passes a version check and answers a websocket — and then the game boots
# with a dead autoload and does nothing. A deploy of that looks green at
# every single step.
#
# Booting is what surfaces it, because that is when scripts are compiled.
# --quit-after gives it a fixed number of frames so it cannot hang here.
RUN godot --headless --path /game --quit-after 240 > /tmp/boot.log 2>&1 || true; \
    if grep -qiE "SCRIPT ERROR|Parse Error|Compile Error|Failed to load script" /tmp/boot.log; then \
      echo "=== FATAL: the project does not compile ==="; \
      grep -iE -A2 "SCRIPT ERROR|Parse Error|Compile Error|Failed to load script" /tmp/boot.log; \
      exit 1; \
    fi; \
    echo "project compiles clean"

# Every symbol the UI draws has a bundled font that can draw it.
#
# Tofu is invisible to every other check here and to the browser test: a
# box with a code point in it is a SUCCESSFUL draw. Nothing errors, nothing
# logs, the screenshot looks fine unless a person reads it. On a desktop it
# cannot even be reproduced, because Godot quietly borrows missing glyphs
# from the operating system — the hearts only read "2665" in a browser,
# which has nothing to borrow from.
#
# tests/ui_glyphs.gd works out what to check by reading src/ rather than
# from a list, so adding a new emoji to a menu fails the build on the day
# it is added instead of shipping a box to the kids.
RUN godot --headless --path /game --script res://tests/ui_glyphs.gd

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
