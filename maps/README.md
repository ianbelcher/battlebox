# Boxel Battle map library

Loose `r.*.mca` region files in this folder = **Ian's World**.

To add another map: make a subfolder (e.g. `maps/skyblock/`) and drop the
Minecraft region files in it (either directly or as a `region/` subdir),
plus an optional `map.cfg`:

    [map]
    name="Sky Block"
    center_x=256
    center_z=256
    y0=40

Every folder shows up automatically as a button in the in-game WORLD
section — the server rescans on every connect. Good sources for freely
licensed maps: minecraftmaps.com and Planet Minecraft (check each map's
license; prefer CC0/CC-BY packs and keep the credit in map.cfg's name).
