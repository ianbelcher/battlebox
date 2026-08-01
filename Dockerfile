# Build stage: export the Godot project several times from the same source —
# a headless Linux server binary plus native desktop clients (Linux, Windows,
# macOS) that the web role serves as downloads. There is no browser build:
# the clients use the Forward+ renderer, which the web export can't do.
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

RUN mkdir -p /game/build/server /game/build/downloads \
    && godot --headless --path /game --export-release "Linux Server" build/server/world-server.x86_64 \
    && godot --headless --path /game --export-release "Linux Client" build/downloads/voxel-battle-linux.x86_64 \
    && godot --headless --path /game --export-release "Windows Client" build/downloads/voxel-battle-windows.exe \
    && godot --headless --path /game --export-release "macOS Client" build/downloads/voxel-battle-macos.zip \
    && cp /game/version.txt /game/build/downloads/version.txt

# Runtime stage: one image, two roles. The k8s deployment runs two containers
# from this image — `server` (the world) and `web` (nginx serving the
# downloads page). Plain http is fine: there's no browser game needing a
# secure context, just file downloads.
FROM ubuntu:24.04

RUN apt-get update \
    && apt-get install -y --no-install-recommends nginx ca-certificates libfontconfig1 \
    && rm -rf /var/lib/apt/lists/*

COPY --from=build /game/build/server /opt/world/server
COPY maps /opt/world/maps
COPY --from=build /game/build/downloads /opt/world/web/downloads
COPY web/index.html /opt/world/web/index.html
COPY nginx.conf /etc/nginx/nginx.conf
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh /opt/world/server/world-server.x86_64

EXPOSE 9081 8081
ENTRYPOINT ["/entrypoint.sh"]
CMD ["server"]
