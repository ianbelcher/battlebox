# Voxel Battle — TODO

Live list of OPEN work. Git history is the record of what's done.
**This file is the single source of truth** — everything Ian asks for
gets written here, not into any assistant's private memory, so any
session (or any tool) can pick the work up cold.

---

## NEXT UP

Ian's whole agreed list (1-8, agreed 2/8) is **done and shipped**; what
each change actually does is recorded in the git history and summarised
under "Recently finished" below. What's left is the longer-term list,
plus the two things only Ian can check on real hardware.

### Needs Ian on real hardware
- [ ] **Controller check of the player menu.** LB/RB now step through the
      picker's tabs (Tools / Build / Nature / Colors / Lights / Special /
      Kits / You), the stick moves the grid and A picks. Verified in the
      automated harness; needs one pass on an actual pad.
- [ ] **Rename / team / kick** in the world menu's Players tab — the rows,
      team swatches and ✕ all render and the cursor is free, but nobody
      has clicked them on a real machine yet.

### Longer-term / not started
- [ ] **Space map** — floating spaceships built from glow blocks, barren
      grey rolling hills, biosphere domes, underground bunkers. (A
      `space` entry already appears in the map list; the generator
      doesn't exist yet, so picking it currently does nothing useful.)
- [ ] **Startup camera** — the title screen orbits empty space at 0,0.
      If players are already on the server, follow one of them around
      instead. (Note: with auto-connect the title screen is now only
      seen while connecting or reconnecting, so this matters less.)
- [ ] 3D held tool models "kind of suck" — improve them (icons are fine)
- [ ] **More kits.** The importer handles any structure-block `.nbt`; 28
      of the 143 in the MoreChineseStructures pack are shipped. Adding
      more is one line each in `WANTED` (see below). Sponge `.schem`
      support (varint-decoded, YZX-ordered block array) is still
      unwritten — nothing needs it yet.
- [ ] Remaining vanilla stand-ins, accepted unless Ian's builds say
      otherwise: per-species door colours (doors are thin panels;
      generic wood/iron), glazed terracotta (imports as wool colours),
      tinted glass panes (keep pane shape, lose tint), signs/pressure
      plates/rails (thin decor → air by design)

---

## Recently finished (2/8)

- **Little People rigged.** `tools/rig_people.py` re-cuts all 30 from the
  MagicaVoxel source into Body/ArmL/ArmR/LegL/LegR OBJs; pivots come from
  each limb's bounding box so `player.gd::_swing_limb` walks them. One
  uniform scale, one shared palette texture, real portrait icons.
- **Character is a picker tab**, beside Kits. LB/RB step the tabs both
  ways (they used to only go forwards, and LB was stolen by the character
  page). Keyboard players still click; controller players still poll.
- **World menu is keyboard/mouse only** — every control in it is
  `FOCUS_NONE` (or `FOCUS_CLICK`), which is what a gamepad walks to drive
  Godot UI, so pads can't reach it while still driving their players.
- **Battle tab reorganised**: default mode is Just building and it
  persists; Arena size and Flying apply in both modes and sit above Game
  length, which only shows in battle mode; the Start button is gone
  (picking Battle royale starts it); every setting applies mid-battle.
- **City rebuilt** — road centre lines every 40 blocks, every other one a
  wide avenue with a dashed centre line, pavements, grass verges, street
  trees and lights, varied building footprints and heights, wide interior
  stairs out in the middle of the floor plate, parks with ponds, paths and
  flower beds. No sky islands over the city, and no wild scatter on it.
- **Connection looks after itself**: no server-select screen (it dials
  `Game.server_url()` on launch), a "Lost the world — reconnecting…"
  banner, endless retries with a stuck-attempt watchdog, and the same
  seats rejoin automatically. The address box only appears after four
  failed attempts; the world menu's Map tab has a Server field.
- **Fliers roam** (`_move_flier`): wide waypoints, no ground veto, the
  terrain only sets a floor. **Water falls** instead of creeping — it
  only spreads sideways once it has landed. **The python sits still**
  (`Creatures.STILL`).
- **Kits from real Minecraft builds**: `tests/import_structures.gd` reads
  structure-block `.nbt`, maps the palette through `McaWorld.map_entry()`
  and writes `src/structures_imported.gd`. 28 kits ship; the Credits tab
  reads its build list straight off that file so it can't drift.

---

## Kits / schematics — how to add more

Ian wants real **WorldEdit-style schematics** — builds actually made in
Minecraft — pasted in as Kits, not MagicaVoxel colour art. `.schem`/`.nbt`
carry real Minecraft block types (oak planks, cobble, stairs, glass) which
map onto our blocks and stay diggable; a `.vox` would import as anonymous
coloured cubes.

**Licensing, settled 2/8:** the shipped kits come from
`github.com/Silicon23/MoreChineseStructures` (author: Silicon23),
**MIT**. An earlier session worried that some files might be Mojang-derived
vanilla jigsaw pieces — checked and they are not: all 143 `.nbt` live in
the author's own `data/mcs/` namespace, and `data/minecraft/` holds only
three JSON config files and no structures. So the whole pack is fine to
ship; we ship 28 of it because the rest are village street/connector
fragments or too big to stamp.

To add more:
```bash
git clone --depth 1 https://github.com/Silicon23/MoreChineseStructures.git
# add names to WANTED in tests/import_structures.gd (WORLD_NBT_ALL=1
# lists every candidate with its size), then:
WORLD_NBT_DIR=<repo>/data/mcs/structure \
WORLD_NBT_OUT=<abs>/game/src/structures_imported.gd \
WORLD_NBT_BY="Silicon23" WORLD_NBT_LICENSE=MIT \
WORLD_NBT_SOURCE="github.com/Silicon23/MoreChineseStructures" \
godot --headless --path <abs>/game --script res://tests/import_structures.gd
godot --headless --path <abs>/game --import   # register the new class
```
Dead ends already checked: Stardust Labs (Structory/Incendium) forbid
redistribution; Dungeons and Taverns / Explorify / Geophilic are
all-rights-reserved; CTOV / Towns and Towers are CC-BY-**NC**. A
HuggingFace dataset of 85 builds is MIT only on its packaging, has no
per-build author, and 18 carry "all rights reserved" — usable for testing
the importer, not for shipping. That dataset's pre-parsed JSON also drops
all block states, so stairs import flat; use raw `.nbt`/`.schem`.

---

## How this project runs (for whoever picks it up)

- **Ship every round**: commit → push → wait for CI on **that exact
  commit sha** → wait for the k8s rollout → **restart Ian's debug client**
  and confirm it reconnected. He tests every round and needs to know he's
  on the new build.
- Debug client: `WORLD_ROLE=client WORLD_AUTOCONNECT=ws://10.0.0.200:30810
  WORLD_DEBUG=1 godot --path <abs path to game>`, pid kept in
  `/tmp/world-dev-client.pid`.
- Downloads / version endpoint: `http://10.0.0.200:30811/downloads/`
  (`version.txt` holds the built commit sha — check it when Ian says a
  feature is missing; he may have downloaded mid-deploy). Note the
  sandboxed shell can't reach it; `dangerouslyDisableSandbox` can.
- **Test before shipping.** Headless server + client with `WORLD_DATA_DIR`,
  `WORLD_AUTOTEST`, and `WORLD_SHOTS` screenshots; check BOTH split-screen
  seats for anything UI-related.
- Test hooks: `WORLD_DINOS_NOW=1`, `WORLD_DRAGON_NOW=1`,
  `WORLD_MENU_TEST=1` (+ `WORLD_MENU_TAB=<n>` to land on a world-menu
  tab), `WORLD_VIDEO_DEBUG=1`, `WORLD_FLIER_DEBUG=1`,
  `WORLD_AUTOTEST_MENU=1` + `WORLD_AUTOTEST_TAB=<n>` for the player menu,
  `WORLD_AUTOTEST_PICK=<char>` (drives the picker UI — only works when the
  character page is on screen), `WORLD_AUTOTEST_WHO=p13,p29` (pins each
  seat's character directly, which is what you usually want).
- Character rig contact sheet, no server needed:
  `WORLD_RIG_SHOT=/tmp/rig.png WORLD_RIG_WHO=a,p0,p9 WORLD_RIG_ROT=180
  godot --path <game> --resolution 1000x340 res://tests/rig_preview.tscn`
  (`WORLD_RIG_FROM`/`WORLD_RIG_COUNT` walk the p-series; `ROT=90` gives the
  side-on walk cycle, which is where a bad pivot shows up).
- Map generator contact sheet, no server needed:
  `WORLD_MAP_OUT=/tmp/city.png WORLD_MAP_THEME=city WORLD_MAP_SPAN=8
  WORLD_MAP_ZOOM=4 godot --headless --path <game>
  --script res://tests/city_map.gd`.
- Godot runs must use an **absolute** `--path` (the shell cwd resets
  between commands, and `--path .` silently loads the wrong project and
  hangs). Scripts run with `--script` must do their work in
  `_initialize()`, not `_init()`, or the process never exits.
- After generating a new `class_name` script, run
  `godot --headless --path <game> --import` or nothing can see the class.
- Never `pkill -f godot` (it matches the running script's own text) —
  use `pgrep -x godot` and skip the debug-client pid.
- Source art zips live in `deployments/world/*.zip` and are **gitignored**
  on purpose; the extracted models under `game/assets/models/` are what's
  committed. `little_people_in_voxel_v2.zip` is the rig's source — keep it.
- Creature/character content is data-driven: `src/creatures.gd` (every
  animal, dinosaur and the dragon) and `src/avatar_factory.gd` (playable
  characters). Add or retire entries there — no other file needs editing.
