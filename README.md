# Belcher World

A cozy isometric "local MMO" for the kids (ages ~4-8), and a deliberate
stress test of Godot 4's Forward+ renderer as an Unreal/Unity alternative.
One persistent voxel world runs forever on the cluster; any machine on the
LAN connects a native client and drops 1-4 local players into it (keyboard
splits + gamepads, dynamic split screen). Explore, dig, build, collect
flowers and shells, pet the sheep, plant trees, light lanterns for the
night — nothing can hurt you.

The world is either **procedurally generated** (a friendly island: meadows,
forests, beaches, lakes, snowy hills) or **imported from a real Minecraft
save** — including the family Minecraft server's world, whose NFS volume the
server mounts read-only. Kids can walk around their own Minecraft builds in
isometric Forward+ lighting; Godot-side edits are stored as an overlay and
the Minecraft save is never modified.

## Playing

1. Open `http://<node-ip>:30811`, download the build for your machine, run it.
2. Press **Connect** (the address is pre-filled: `ws://10.0.0.200:30810`).
3. Press **Space** / **Enter** / gamepad **A** to jump in — up to 4 per
   machine, the screen splits automatically. Characters (name, look,
   position, treasures) persist per device and per name.

| Player     | Move       | Jump  | Dig / collect / pet | Place | Cycle block | Spin view  | Zoom (out/in) | 1st person | Leave (hold) |
| ---------- | ---------- | ----- | ------------------- | ----- | ----------- | ---------- | ------------- | ---------- | ------------ |
| Keyboard   | WASD       | Space | E                   | F     | Tab / R     | Z / C      | X / V         | T          | Q            |
| Gamepads   | Left stick | A     | B                   | X     | Bumpers     | R stick ←→ | R stick ↓ / ↑ | Y          | Back/Select  |

One keyboard player per machine (normal WASD controls) plus any number of
gamepads. Each player spins their own isometric camera in quarter turns (to
peek behind hills and houses) and steps through six zoom levels, from
over-the-shoulder to a map-like overview (chunk streaming widens
automatically when zoomed out); movement stays camera-relative.
**First person** (T / gamepad Y) puts you behind your character's eyes —
mouse look with left-click dig / right-click place on keyboard, right-stick
look on gamepads, Esc or T to come back out. It's the view for digging
yourself out of a hole. **Double-tap jump to fly** — hold jump to rise,
Shift / left trigger to sink, land (or double-tap again) to stop; flyers
strike a superhero pose. Characters are chunky mini-figures — click your
name chip
to type a name, and click the three swatches to cycle **skin tone**,
**shirt color** and **hat** (7 of each, remembered per device). Blocks are
infinite (creative-style); digging flowers, shells,
mushrooms and berries counts treasures (✦). Saplings grow into trees after a
couple of minutes, fresh flowers bloom at dawn, fireflies come out at night,
and walking up to a critter and pressing dig pets it.

The hotbar is ~48 blocks: wood/stone/wool building families, gold and
diamond, a glow set (glowstone, three crystal colors, harmless swimmable
"glow goo" lava — all real lights), and the **fun machines**:

| Block | What it does |
| ----- | ------------ |
| Boom Block | 3-second sparking fuse, then a real crater. Blast launches nearby players (harmlessly) and sets off other boom blocks — chain reactions welcome |
| Firework | Launches after a moment and bursts in colour over the world |
| Bouncy Block | Trampoline — returns most of your fall, higher each drop |
| Launch Pad | Step on, get flung skyward |
| Music Block | Plays a marimba note when stepped on, pitched by position — build a walkable tune |
| Sponge | Instantly drinks all water/goo nearby — drain a pond |
| Warp Stone | Stand on one, teleport to the nearest other one — build portal networks |
| Party Popper | Dig it: confetti and a crowd cheer |

## The tech (what's being stress-tested)

- **Forward+ renderer, native clients only** — real directional sun +
  moon shadows, SSAO, glow, filmic tonemapping, day/night sky; every
  lantern/campfire is a real OmniLight3D with flicker and particles.
  `WORLD_MAXFX=1` additionally enables SDFGI and volumetric fog.
- **1-4 SubViewports** share a single World3D, each with an orthographic
  isometric camera — split-screen costs one scene, N renders.
- **Voxel pipeline in GDScript**: seeded biome worldgen, 16x16x80 chunks,
  zstd-compressed streaming over WebSocket, face-culled meshing with
  per-vertex ambient occlusion (with the AO-aware quad-diagonal flip),
  per-position color jitter, wind-sway and water shaders driven by vertex
  data (UV2) — no textures, no art assets, no physics engine (hand-rolled
  voxel AABB movement with kid-friendly auto-hop and buoyancy).
- **Server-authoritative multiplayer**: the headless server owns chunks,
  edits, the clock, critters, growth and per-character persistence;
  machines are authoritative only over their own players' positions
  (`peer:slot` ids, as in Belcher Party).

## World sources

| Env                | Default          | Meaning |
| ------------------ | ---------------- | ------- |
| `WORLD_SOURCE`     | `procedural`     | `procedural` or `mca` |
| `WORLD_SEED`       | `20260726`       | procedural seed |
| `WORLD_DATA_DIR`   | `user://world`   | persistence dir (chunk edit overlay, clock, players) |
| `WORLD_MCA_DIR`    | —                | Minecraft world dir (or its `region/` dir) |
| `WORLD_MCA_Y0`     | `40`             | Minecraft y that becomes world floor +1 |
| `WORLD_MCA_CENTER` | `0,0`            | Minecraft x,z that becomes our origin (chunk-aligned) |

The `.mca` importer parses Anvil region files directly in GDScript (NBT,
1.16+ packed palettes, 1.18+ section layout, zlib/gzip) and maps ~200 block
types onto the game's 35-block palette (unknown solids read as stone, thin
decorations vanish). Missing chunks become open ocean. In the cluster
deployment the Minecraft volume is mounted read-only at `/minecraft`; see
`_configurations/world.yaml` for the switch.

## Local development

```sh
# Terminal 1: dedicated server (headless implies server role)
godot --headless --path game

# Terminals 2+: clients (connect to ws://127.0.0.1:9081)
WORLD_ROLE=client WORLD_AUTOCONNECT=ws://127.0.0.1:9081 godot --path game
```

Dev/test hooks: `WORLD_AUTOTEST=<n>` joins n wandering bot players,
`WORLD_FAST=1` shrinks the day to 90s and sapling growth to 8s,
`WORLD_SHOTS=<dir>` saves a screenshot every 1.5s, `WORLD_DEBUG=1` logs
player physics state. The importer has a standalone test:

```sh
python3 tools/make_mca.py /tmp/fixture   # or point at any 1.18+ world's region dir
WORLD_MCA_DIR=/tmp/fixture godot --headless --path game -s res://tests/test_mca.gd
```

## Deployment

One image, two roles (`server` + nginx `web` serving the downloads page) —
NodePorts 30810 (game) / 30811 (downloads). World data persists on the NAS
(`10.0.0.215:/data-pool/services/world/data` — create the directory before
first apply). LAN-only by design; config changes in
`_configurations/world.yaml` are applied manually, CI only bumps images.

## GDScript gotchas (hard-won, do not regress)

- Never `var x := dict.field` or `var x := arr[i].method()` — Variant can't
  infer; type the variable explicitly (this repo's most common parse error).
- `set_anchors_preset()` inside `_ready()` freezes the control at the
  parent's *current* (possibly zero) size via offsets; use
  `set_anchors_and_offsets_preset()` for code-built UI.
- Godot front faces wind **clockwise**; custom-shader vertex colors arrive
  sRGB and must be `pow(c, 2.2)`'d before ALBEDO.
- Volumetric fog + orthographic cameras = flat gray wash; keep it off for
  iso cameras.
- After adding a `class_name`, run `godot --headless --import` or other
  scripts won't see it.
