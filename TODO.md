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

- [ ] **Space map, second pass.** The generator exists now (grey ground,
      glass biosphere domes with grass inside, steel bunkers with lit
      shafts, glowing ships parked in the sky). Ian should say what it
      needs — more ship variety, interiors, something to find.


- [ ] **3D held tool models** "kind of suck" — improve them. The icons
      are fine.
- [ ] **More kits — needs Ian to pick.** The importer now reads all three
      formats those sites hand out (see "Adding more kits"), so this is
      pure sourcing: download the builds you want, drop them in a folder,
      run the importer. 28 of the 143 MoreChineseStructures builds ship;
      the rest are street fragments or too big to stamp.
- [ ] Remaining vanilla stand-ins, accepted unless Ian's builds say
      otherwise: per-species door colours (doors are thin panels; generic
      wood/iron), glazed terracotta (imports as wool colours), tinted
      glass panes (keep pane shape, lose tint), signs/pressure
      plates/rails (thin decor → air by design).

---

## Adding more kits

**Where things live: `deployments/world/kits/`.** Paste links into
`kits/sources.txt`, run `./tools/import_kits.sh`, commit. The builds
themselves live in `kits/downloads/` and are COMMITTED — they're the
source of truth the game's kits are generated from, so re-running the
importer rebuilds every kit from that folder. `kits/README.md` has the
whole workflow.

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

**Formats: all three are supported.** `tests/import_structures.gd` sniffs
the file and reads whichever it is —
- `.nbt` — Minecraft structure block (datapacks). `{state, pos}` list.
- `.schem` — Sponge v1/v2/v3. Varint block stream, YZX order, name
  palette. This is what minecraft-schematics.com and Planet Minecraft
  serve today.
- `.schematic` — MCEdit/WorldEdit legacy. Flat 1.12 numeric ids plus a
  metadata nibble; `LEGACY_IDS` maps them to modern names, and stair
  facing comes out of the nibble so stairs don't import flat.

`tools/make_schem.py` writes fixtures in all of them, so the decoders can
be tested without downloading anything.

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
- Battle test hooks: `WORLD_BOT_WEAPON=<id>` arms every computer player at
  the drop (they otherwise start with a sword and must find a crate), and
  `WORLD_ORB_DEBUG=1` logs every bot shot — fired, hit, or stopped by a
  wall. Bots drop 16-30% of the world's size from the centre, so shrink
  the arena (battle.cfg `size=60`) if you want them to meet quickly.
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
