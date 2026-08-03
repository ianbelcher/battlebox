# Voxel Battle — TODO

**Outstanding work only.** Git history is the record of what's done.
**This file is the single source of truth** — everything Ian asks for gets
written here, not into any assistant's private memory, so any session (or
any tool) can pick the work up cold.

---

## Needs Ian on real hardware

- [ ] **Controller pass over the player menu.** LB/RB step through the
      picker's tabs (Tools / Build / Nature / Colors / Lights / Special /
      Kits / You), the stick moves the grid, A picks. Verified in the
      automated harness only.
- [ ] **Rename / team / kick** in the world menu's Players tab. The rows,
      team swatches and ✕ all render and the cursor is free, but nobody
      has clicked them on a real machine.

## Open work

- [ ] **World size is a soft edge, not a wall.** Picking a size on the Map
      tab now eases players back at the boundary in both modes, but the
      terrain still generates past it and blocks can still be placed
      out there. A real border (visible edge, generation limit) is the
      proper job.

- [ ] **Space map** — floating spaceships built from glow blocks, barren
      grey rolling hills, biosphere domes, underground bunkers. A `space`
      entry already appears in the map list; the generator doesn't exist,
      so picking it currently does nothing useful.
- [ ] **Startup camera** — the title screen orbits empty space at 0,0. If
      players are already on the server, follow one of them around
      instead. (Lower stakes now: with auto-connect the title screen is
      only seen while connecting or reconnecting.)
- [ ] **3D held tool models** "kind of suck" — improve them. The icons
      are fine.
- [ ] **Sponge `.schem` support** — THE unlock for kit variety. Ian wants
      to pull builds from minecraft-schematics.com and the like, and
      almost everything there is `.schem`/`.schematic`, not the `.nbt` the
      importer currently reads. Only the container differs: `.schem` wraps
      the same palette + block data in a gzipped NBT with a
      **varint-encoded, YZX-ordered** `BlockData` array (and old
      `.schematic` uses flat numeric block ids needing a 1.12 id→name
      table). `Mca._read_compound` already parses the NBT; this is a
      decode loop and a reorder, not new infrastructure. Those sites have
      no bulk API and per-build licensing is usually unstated, so keep
      downloading manual and record the author/URL per build in the
      import manifest (`credits.gd` reads it automatically).
- [ ] **More kits.** 28 of the 143 builds in the MoreChineseStructures
      pack ship; the rest are village street fragments or too big to
      stamp. Adding more is one line each in `WANTED` — see below.
- [ ] Remaining vanilla stand-ins, accepted unless Ian's builds say
      otherwise: per-species door colours (doors are thin panels; generic
      wood/iron), glazed terracotta (imports as wool colours), tinted
      glass panes (keep pane shape, lose tint), signs/pressure
      plates/rails (thin decor → air by design).

---

## Adding more kits

Ian wants real **WorldEdit-style schematics** — builds actually made in
Minecraft — pasted in as Kits, not MagicaVoxel colour art. `.schem`/`.nbt`
carry real Minecraft block types (oak planks, cobble, stairs, glass) which
map onto our blocks and stay diggable; a `.vox` would import as anonymous
coloured cubes.

**Licensing, settled 2/8:** the shipped kits come from
`github.com/Silicon23/MoreChineseStructures` (author: Silicon23), **MIT**.
An earlier session worried some files might be Mojang-derived vanilla
jigsaw pieces — checked, they are not: all 143 `.nbt` live in the author's
own `data/mcs/` namespace, and `data/minecraft/` holds three JSON config
files and no structures. The whole pack is fine to ship.

```bash
git clone --depth 1 https://github.com/Silicon23/MoreChineseStructures.git
# WORLD_NBT_ALL=1 lists every candidate with its size; add the ones you
# want to WANTED in game/tests/import_structures.gd, then:
WORLD_NBT_DIR=<repo>/data/mcs/structure \
WORLD_NBT_OUT=<abs>/game/src/structures_imported.gd \
WORLD_NBT_BY="Silicon23" WORLD_NBT_LICENSE=MIT \
WORLD_NBT_SOURCE="github.com/Silicon23/MoreChineseStructures" \
godot --headless --path <abs>/game --script res://tests/import_structures.gd
godot --headless --path <abs>/game --import   # register the new class
```

Dead ends already checked, don't re-research them: Stardust Labs
(Structory/Incendium) forbid redistribution; Dungeons and Taverns /
Explorify / Geophilic are all-rights-reserved; CTOV / Towns and Towers are
CC-BY-**NC**. A HuggingFace dataset of 85 builds is MIT only on its
packaging, has no per-build author, and 18 carry "all rights reserved" —
usable for testing the importer, not for shipping. Its pre-parsed JSON
also drops all block states, so stairs import flat; use raw `.nbt`/`.schem`.

---

## How this project runs (for whoever picks it up)

- **Ship every round**: commit → push → wait for CI on **that exact commit
  sha** → wait for the k8s rollout → **restart Ian's debug client** and
  confirm it reconnected. He tests every round and needs to know he's on
  the new build.
- Debug client: `WORLD_ROLE=client WORLD_AUTOCONNECT=ws://10.0.0.200:30810
  WORLD_DEBUG=1 godot --path <abs path to game>`, pid kept in
  `/tmp/world-dev-client.pid`.
- Downloads / version endpoint: `http://10.0.0.200:30811/downloads/`
  (`version.txt` holds the built commit sha — check it when Ian says a
  feature is missing; he may have downloaded mid-deploy). The sandboxed
  shell can't reach it; `dangerouslyDisableSandbox` can.
- **Test before shipping.** Headless server + client with `WORLD_DATA_DIR`,
  `WORLD_AUTOTEST` and `WORLD_SHOTS` screenshots; check BOTH split-screen
  seats for anything UI-related.
- **The world menu has two rules; breaking either makes it unusable.**
  (1) Never rebuild it on a timer — rebuilding rows every frame destroys
  the text box being typed in and the button being clicked. (2) Never read
  `size` in `_ready()` — it is 0 there, so fonts bake at minimum scale and
  never grow. Both are documented at the top of `world_menu.gd`.
- Test hooks: `WORLD_DINOS_NOW=1`, `WORLD_DRAGON_NOW=1`,
  `WORLD_MENU_TEST=1` (+ `WORLD_MENU_TAB=<n>` to land on a world-menu
  tab), `WORLD_VIDEO_DEBUG=1`, `WORLD_FLIER_DEBUG=1`,
  `WORLD_AUTOTEST_MENU=1` + `WORLD_AUTOTEST_TAB=<n>` for the player menu,
  `WORLD_AUTOTEST_WHO=p13,p29` to pin each seat's character (what you
  usually want), `WORLD_AUTOTEST_PICK=<char>` to drive the picker UI
  instead (only works when the character page is already on screen).
- **`WORLD_FAKE_PADS=<n>` pretends n gamepads are plugged in**, each
  holding A, and drives the REAL gamepad code through the real join path.
  Use it for anything touching controls: `WORLD_AUTOTEST` bots are
  `BotSlot`, which overrides every button, so bot runs prove nothing about
  controllers — that gap is how the LB-jump regression shipped.
  `WORLD_FAKE_PAD_HOLD=lb|rb` holds a shoulder button.
  Note a fake pad won't join while bots are in the roster: `BotSlot` is
  GAMEPAD-kind, so the twin-pad divergence check treats them as mirrors.
- `WORLD_MENU_PROBE=1` drives the Escape menu with synthetic input and
  reports what responded: Escape opens it, mouse clicks land on tabs and
  buttons, Tab moves the keyboard highlight, joypad buttons are ignored.
  Screenshots only prove a menu RENDERS — this proves it responds.
- Contact sheets that need no server — rig poses, map generators — and the
  art/kit regeneration commands are in `README.md` under **Local
  development**.
- Godot runs must use an **absolute** `--path` (the shell cwd resets
  between commands, and `--path .` silently loads the wrong project and
  hangs). Scripts run with `--script` must do their work in
  `_initialize()`, not `_init()`, or the process never exits.
- After generating a new `class_name` script, run
  `godot --headless --path <game> --import` or nothing can see the class.
- Never `pkill -f godot` (it matches the running script's own text) — use
  `pgrep -x godot` and skip the debug-client pid.
- Source art zips live in `source-art/` and are **gitignored** on purpose;
  what ships is the extracted models under `game/assets/models/`. The
  Little People rig is regenerated from the zip there, so keep it.
- Creature/character content is data-driven: `src/creatures.gd` (every
  animal, dinosaur and the dragon) and `src/avatar_factory.gd` (playable
  characters). Add or retire entries there — no other file needs editing.
