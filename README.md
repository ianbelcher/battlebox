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
2. It connects itself. There is no server-picker screen — the client dials
   the saved address (`ws://10.0.0.200:30810` by default) the moment it
   launches, and if the link ever drops it says so and keeps retrying until
   it's back, putting everyone who was playing straight back in their seat.
   To point it somewhere else, use **Server** in the ` menu's Map tab.
3. Press **Space** / **Enter** / gamepad **A** to jump in — up to 4 per
   machine, the screen splits automatically. Characters (name, look,
   position, treasures) persist per device and per name.

Controls are Minecraft-shaped. **First person is the default view**; T / Y
switches to the isometric overview and back.

| Player   | Move       | Jump  | Break        | Place         | Throw orb    | Picker/Menu     | Cycle | Spin/Zoom (overview) | Leave (hold) |
| -------- | ---------- | ----- | ------------ | ------------- | ------------ | --------------- | ----- | -------------------- | ------------ |
| Keyboard | WASD       | Space | Left click/G | Right click/F | R / M-click  | E / `           | Tab   | Z C / X V            | Q            |
| Gamepads | Left stick | A     | B            | X             | Right trigger| D-pad up / Start| Bumpers | Right stick        | Back         |

**E** (or **X** / **Start** on a pad) opens the Minecraft-style picker.
Its tabs run Tools, Build, Nature, Colors, Lights, Special, Kits and
**You** — your character is a tab like any other — and the **bumpers**
(Tab / Shift+Tab) step through them in either direction. **`** opens the
separate WORLD menu, which is keyboard-and-mouse only on purpose: a
grown-up can sort out the map, the battle setup, who's playing and the
video settings while the kids keep running around on their controllers.
**Orbs** can be thrown any time — they harmlessly bonk friends and they're
your weapon during Grump attacks.

One keyboard player per machine (normal WASD controls) plus any number of
gamepads. Each player spins their own isometric camera in quarter turns (to
peek behind hills and houses) and steps through six zoom levels, from
over-the-shoulder to a map-like overview (chunk streaming widens
automatically when zoomed out); movement stays camera-relative.
First person means mouse look on keyboard and right-stick look on
gamepads. **Double-tap jump to fly** — hold jump to rise,
Shift / left trigger to sink, land (or double-tap again) to stop; flyers
strike a superhero pose. Characters are chunky mini-figures — 18 Kenney kids plus 30 "Little
People" re-cut into rigged body parts so they walk, swing and crouch like
everyone else. Pick one on the **You** tab (moving the cursor IS choosing);
click your name chip to type a name. Blocks are
infinite (creative-style); digging flowers, shells,
mushrooms and berries counts treasures (✦). Saplings grow into trees after a
couple of minutes, fresh flowers bloom at dawn, fireflies come out at night,
and walking up to a critter and pressing dig pets it. Ten animal kinds
(sheep, bunnies, butterflies, fireflies, ducks, chickens, crabs, frogs,
deer, penguins) wander their own terrain with distance-faded, pitch-varied
voices. Biomes are small and dramatic — dense jungles, pine groves, flower
fields, swamps — with **glowing caverns** underground and **floating sky
islands** to find by flying. Water flows: blow up a pond wall and it pours
into the crater — falling water drops like a waterfall and only spreads out
once it lands. The picker's **building kits** stamp whole prefabs that
never overwrite existing builds: hand-written ones (house, watchtower,
giant tree, bridge, camp, fort wall, pool, garden) plus real Minecraft
builds imported from structure-block `.nbt`, which arrive as proper planks,
cobble, stairs and glass and stay diggable.

**⚔ Attack!** (top bar) starts a survival raid: waves of Grumps rise from
low ground and water and march on the players. They can only step up one
block — real forts really work. Orbs bonk them; getting caught costs a
heart; when everyone has been knocked down the raid ends with your
survival time and everyone respawns. Nothing is ever lost.

The hotbar is ~48 blocks: wood/stone/wool building families, gold and
diamond, a glow set (glowstone, three crystal colors, harmless swimmable
"glow goo" lava — all real lights), and the **fun machines**:

| Block | What it does |
| ----- | ------------ |
| Boom Block | Safe until **clicked** — then a sparking fuse and a real crater. Every charge *touching* it detonates together in one scaled-up mega-blast; nearby loose ones chain. Click a lit one to defuse |
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

## Layout

```
game/            the Godot project (src/, assets/, tests/)
game/src/        every script; gameplay is data-driven from creatures.gd,
                 blocks.gd, structures.gd and avatar_factory.gd
game/tests/      headless harnesses — rig contact sheet, map renders,
                 the .mca importer test, the kit importer
tools/           offline generators run by hand (rig_people.py, make_mca.py)
maps/            selectable Minecraft maps, one folder each (see its README)
source-art/      the original art zips — gitignored, README explains why
web/             the downloads landing page nginx serves
TODO.md          the outstanding-work list, and how this project runs
```

## Local development

```sh
# Terminal 1: dedicated server (headless implies server role)
godot --headless --path game

# Terminals 2+: clients (connect to ws://127.0.0.1:9081)
WORLD_ROLE=client WORLD_AUTOCONNECT=ws://127.0.0.1:9081 godot --path game
```

Dev/test hooks: `WORLD_AUTOTEST=<n>` joins n wandering bot players,
`WORLD_AUTOTEST_WHO=p13,p29` pins each seat's character, `WORLD_FAST=1`
shrinks the day to 90s and sapling growth to 8s, `WORLD_SHOTS=<dir>` saves
a screenshot every 1.5s, `WORLD_DEBUG=1` logs player physics state.
`TODO.md` lists the rest.

Three things can be checked without running a server at all:

```sh
# Character rig: a posed contact sheet (ROT=90 is the side-on walk cycle,
# which is where a bad pivot shows up).
WORLD_RIG_SHOT=/tmp/rig.png WORLD_RIG_WHO=a,p0,p9 WORLD_RIG_ROT=180 \
  godot --path game --resolution 1000x340 res://tests/rig_preview.tscn

# Map generators: a top-down render of any theme.
WORLD_MAP_OUT=/tmp/city.png WORLD_MAP_THEME=city WORLD_MAP_SPAN=8 \
  WORLD_MAP_ZOOM=4 godot --headless --path game --script res://tests/city_map.gd

# The .mca importer's standalone test.
python3 tools/make_mca.py /tmp/fixture   # or any 1.18+ world's region dir
WORLD_MCA_DIR=/tmp/fixture godot --headless --path game -s res://tests/test_mca.gd
```

### Regenerating art and kits

```sh
# Rigged Little People characters, from source-art/little_people_in_voxel_v2.zip
python3 tools/rig_people.py

# Kits, from a datapack of Minecraft structure-block .nbt files
WORLD_NBT_DIR=<pack>/data/mcs/structure WORLD_NBT_OUT=$PWD/game/src/structures_imported.gd \
  WORLD_NBT_BY="Silicon23" WORLD_NBT_LICENSE=MIT \
  godot --headless --path game --script res://tests/import_structures.gd

godot --headless --path game --import   # always, after generating either
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

