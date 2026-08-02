# Voxel Battle — TODO

Live list of OPEN work. Git history is the record of what's done.
**This file is the single source of truth** — everything Ian asks for
gets written here, not into any assistant's private memory, so any
session (or any tool) can pick the work up cold.

---

## NEXT UP — Ian's priority order (agreed 2/8)

### ~~1. Little People characters — rig them~~ DONE
Rigged, not deleted. `tools/rig_people.py` re-cuts all 30 from the
MagicaVoxel source into Body / ArmL / ArmR / LegL / LegR OBJs; the pivots
are derived from each limb's own bounding box so `_swing_limb` walks them.
One shared 256x1 palette texture, one uniform scale (so they are all the
same size, matched to the Kenney kids), and the picker icons are real
portraits now instead of a palette strip. Re-run the tool after any art
change; eyeball it with `res://tests/rig_preview.tscn`.

### 2. Player menu (the per-player modal) — controls and character tab
- [ ] **Character selection becomes a TAB in the tool chooser**, beside
      Building / Natural / Colored / Functional / Special / Kits. Stop
      using LB for it — LB is needed to move between picker tabs
- [ ] **Controller must work properly** in this modal (it's the player's
      own menu). LB/RB cycle tabs, stick/D-pad moves, A picks
- [ ] Caveat: if that player is on **keyboard+mouse**, then keyboard and
      mouse must work for *their* modal. Input follows the player's own
      device
- [ ] Character grid: moving IS choosing (already done), right stick
      spins the preview (already done), verify both on a real controller

### 3. World menu (Escape modal) — remaining items
Mouse capture, window size, text scale, prose removal, bigger add/remove
buttons and "Custom worlds" are DONE (commit 27f9d7b1). Still open:

- [ ] **Controllers must NOT drive this modal at all** — keyboard and
      mouse only. Verify no controller input reaches it
- [ ] **Battle tab reorganisation:**
  - [ ] Default mode is **Just building**, and the chosen mode PERSISTS
        across restarts (battle royale stays selected if that's how it
        was left)
  - [ ] **Arena size** and **Flying** apply in BOTH modes (they're not
        battle-only settings)
  - [ ] **Game length** moves BELOW those and only shows in battle mode
  - [ ] **Remove the "Start the battle" button entirely**
  - [ ] All these settings must be changeable **while the battle loop is
        running**
- [ ] Verify rename / team / kick actually work now the cursor is back

### 4. City map — start over
The current generator is a boxy grid on fixed sizes and Ian has asked
three times now. Rebuild it:

- [ ] **Proper roads** — wide, with dashed centre lines
- [ ] **Smaller side streets** branching off them
- [ ] **Pavements** along the sides of roads
- [ ] **Green** at the sides of buildings; keep and improve parks
- [ ] **Street lights** along roads
- [ ] **Bigger steps**, and NOT jammed against corners (currently very
      hard to walk up)
- [ ] **No sky islands in the city** — they make no sense there
- [ ] Vary building footprints and heights; stop the uniform grid look

### 5. Connection must look after itself (BLOCKER for the kids)
- [ ] The connect screen makes a child find a mouse and click Connect
      before they can play. **Just connect to the default server
      immediately** on launch (`Net.default_server_url()`), straight into
      the game. A way to choose a different server can come back later,
      tucked in the world menu
- [ ] **Auto-reconnect.** If the client drops, it must say so on screen
      (a clear "Disconnected — reconnecting…" banner) and **keep retrying
      by itself** until it's back. A child must never have to find the
      mouse, click Connect, or restart the app to get back into the world

### 6. Fliers that don't fly
- [ ] **Pterodactyls don't move at all**, and one or two of the birds sit
      in one spot. Fliers (`Creatures.FLIER`: pterodactyl, owl, parrot,
      toucan, the old bird) need to actually roam
- [ ] Hint for whoever picks this up: in `world.gd::_move_critter` the
      FLIER branch only runs *after* the `to_target.length() > 0.3`
      check, and it pins `next.y` to ground+1 — so if a flier's wander
      target lands where it already is, or the ground under it is
      unreachable, it never moves. Give fliers their own wander logic
      (bigger roaming radius, ignore ground validity, keep the view's
      `fly_height` offset)

### 7. Water flow
- [ ] Water should only spread **laterally when it lands on something**.
      Otherwise it falls straight down like a waterfall. Today, breaking
      a pool makes it creep outwards across the ground

### 8. Snake
- [ ] The jungle python (`creatures.gd`) must **not move** — it's
      modelled lying down / rotated, so walking looks wrong. Make it a
      stationary critter

---

## Kits / schematics (in progress)

Ian wants real **WorldEdit-style schematics** — builds actually made in
Minecraft (`.schem` from WorldEdit, `.nbt` from vanilla structure
blocks) — pasted into the world as Kits, not MagicaVoxel colour art.

**Why `.nbt`/`.schem` and not `.vox`:** `.vox` models are arbitrary
coloured voxels, so they import as coloured cubes. `.schem`/`.nbt` carry
real Minecraft block types (oak planks, cobble, stairs, glass), which map
onto our blocks and stay diggable.

**We already have the hard parts:** `src/mca.gd` contains a complete
GDScript NBT reader (all 13 tag types, gzip) and `Mca.map_block()` with a
~295-entry Minecraft-name → our-block-id table.

- [ ] Write the importer: `.nbt` first (it's already a list of
      `{state, pos}` + palette — no bit-packing), then Sponge `.schem`
      (adds a varint-decoded, YZX-ordered block array)
- [ ] Generate kit data offline into a `structures_imported.gd` rather
      than hand-coding; keep `structures.gd` as the index/metadata layer
- [ ] Auto-populate `src/credits.gd` `BUILDS` from the import manifest

**Sourcing status (researched 2/8):** 130 files were downloaded to a
session scratchpad (NOT in git — they'd need re-fetching), in two tiers:
- **45 `.nbt` files, MIT-licensed**, from
  `github.com/Silicon23/MoreChineseStructures` (author: Silicon23) —
  houses, yurts, cave dwellings, shrines, temples, wells, stables.
  22 are clearly original; 23 reuse vanilla jigsaw filenames and may be
  Mojang-derived. **These are the only ones cleared to ship.**
- **85 files NOT cleared** — from a HuggingFace dataset whose MIT tag
  covers the packaging only, not the builds. No author and no source URL
  recorded per build, and 18 carry an "all rights reserved" notice.
  Usable to test the importer; not to ship.
- Dead ends: Stardust Labs (Structory/Incendium) forbid redistribution;
  Dungeons and Taverns / Explorify / Geophilic are all-rights-reserved;
  CTOV / Towns and Towers are CC-BY-**NC**.
- Gotcha: that dataset's pre-parsed JSON **drops all block states**, so
  stairs import flat. Use raw `.nbt`/`.schem`, not the JSON.
- **Ian to decide:** ship the clean 22, all 45 MIT, or keep the rest for
  private use only.

---

## Longer-term / not started

- [ ] **Space map** — floating spaceships built from glow blocks, barren
      grey rolling hills, biosphere domes, underground bunkers. (A
      `space` entry already appears in the map list; the generator
      doesn't exist yet, so picking it currently does nothing useful.)
- [ ] **Startup camera** — the title screen orbits empty space at 0,0.
      If players are already on the server, follow one of them around
      instead
- [ ] 3D held tool models "kind of suck" — improve them (icons are fine)
- [ ] Remaining vanilla stand-ins, accepted unless Ian's builds say
      otherwise: per-species door colours (doors are thin panels;
      generic wood/iron), glazed terracotta (imports as wool colours),
      tinted glass panes (keep pane shape, lose tint), signs/pressure
      plates/rails (thin decor → air by design)

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
  feature is missing; he may have downloaded mid-deploy).
- **Test before shipping.** Headless server + client with `WORLD_DATA_DIR`,
  `WORLD_AUTOTEST`, and `WORLD_SHOTS` screenshots; check BOTH split-screen
  seats for anything UI-related.
- Test hooks: `WORLD_DINOS_NOW=1`, `WORLD_DRAGON_NOW=1`,
  `WORLD_MENU_TEST=1`, `WORLD_VIDEO_DEBUG=1`, `WORLD_AUTOTEST_PICK=<char>`
  (drives the picker UI — only works when the character page is on screen),
  `WORLD_AUTOTEST_WHO=p13,p29` (pins each seat's character directly).
- Character rig contact sheet, no server needed:
  `WORLD_RIG_SHOT=/tmp/rig.png WORLD_RIG_WHO=a,p0,p9 WORLD_RIG_ROT=180
  godot --path <game> --resolution 1000x340 res://tests/rig_preview.tscn`
  (`WORLD_RIG_FROM`/`WORLD_RIG_COUNT` walk the p-series; `ROT=90` gives the
  side-on walk cycle, which is where a bad pivot shows up).
- Godot runs must use an **absolute** `--path` (the shell cwd resets
  between commands, and `--path .` silently loads the wrong project and
  hangs).
- Never `pkill -f godot` (it matches the running script's own text) —
  use `pgrep -x godot` and skip the debug-client pid.
- Source art zips live in `deployments/world/*.zip` and are **gitignored**
  on purpose; the extracted models under `game/assets/models/` are what's
  committed.
- Creature/character content is data-driven: `src/creatures.gd` (every
  animal, dinosaur and the dragon) and `src/avatar_factory.gd` (playable
  characters). Add or retire entries there — no other file needs editing.
