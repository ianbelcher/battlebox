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
- [ ] **Both menus were restyled** (see "The look of the menus" below).
      Every tab was checked in the screenshot harness at 1080p and in a
      two-way split, but nobody has looked at them on the TV. Watch for
      text that is too small across a living room.

## Open work

Everything below came from Ian in one go on 4/8/2026, in priority order
as agreed: bugs that spoil a game first, then the things that make it a
better game. Tick them off here as they ship.

### Bounds — things leaving the play area

- [x] **Nothing may be placed outside the world size.** Crates, kits,
      structures, animals and decoration are all placed without checking
      `battle_size`, so on a small world they land off the grid. Every
      placement goes through one bounds check.
- [x] **No player may be dropped outside the grid** either — same check
      on the drop path.

### Roster and teams

- [x] **Name computer players from the phonetic alphabet** — Alpha,
      Bravo, Charlie, Delta … Zulu. Humans keep animal names (newt, duck,
      bee, bear), so the two are told apart at a glance. The current
      names sort alphanumerically, so "Bot 10" lands between "Bot 1" and
      "Bot 2" and the roster reads as nonsense. 24 bots max, 26 letters —
      it fits. Computers always sort AFTER humans.
- [x] **Make bot team assignment legible.** Right now you cannot tell
      what team a bot landed on or why.
- [x] **A counts row at the top of the team grid**: how many players are
      on each team.
- [x] **The world menu runs off the right edge** once there are enough
      teams — the swatch row does not wrap or scroll.

### Creatures

- [x] **Far fewer animals, scaled to the world.** A 50×50 world is
      swamped with them.
- [x] **Drop snakes.** They cannot move around properly.

### Weapons

- [x] **Medium shooter is far too destructive** — roughly halve the
      blast.
- [x] **No explosion may leave a 2-block height differential.** Getting
      stuck in a crater you cannot walk out of is not fun. Craters should
      come out walkable — no step taller than one block anywhere around
      the rim. (Digging down under your own feet is still your problem.)
- [x] **Remove** the bridge gun, the party popper and the world wand —
      none of them are useful.
- [x] **Starting loadout: sword, paint sprayer, flare gun.**
- [x] **New — paint sprayer.** Works like the paint bomb but sprays in
      YOUR TEAM's colour, so you can draw lines and mark things.
- [x] **Flare gun fires your team's colour.**
- [x] **New — smoke bomb.** A team-coloured marker you throw to say
      "we're taking that building". Not for hiding. **Only ever one in
      the world at a time** — throwing a new one clears the previous.
- [x] **Weapon order**: flare gun, paint bomb, paint sprayer together;
      then wings; napalm rocket moves to just after the big shooter.

### Loot

- [x] **The lights over loot flicker** — they switch off and back on.
- [x] **Ration loot to the world's size and, partly, to how many are
      playing.** Two players on a huge map should not be hunting ten
      crates between them.

### Drops

- [x] **Drop teams TOGETHER** — a team of four (or seventeen) lands as a
      group with about one block between them, so they start together and
      can fly out from there. **Spread the groups well across the map** so
      every team gets its own space.

### Space map

- [ ] **Biodomes must sit on the ground.** Sample every block under the
      dome's circular footprint and set it at the LOWEST of them, instead
      of leaving it hanging in the air.
- [ ] **Weapons/loot still spawn floating high in the air** on this map.
- [ ] **More than one cavern.** A large space world currently gets one.
- [ ] **An angled archway leading down into a cavern**, rather than the
      bare hole it is now.
- [ ] **Better spaceships.** They are meant to be the floating-island
      feature of this map and they look terrible.

### Scoreboard

- [ ] **Track games won per team.** The end of a match announces "Team
      Blue wins", and there is a leaderboard.
- [ ] **The board has two sides**: teams by games won on one, players by
      TOTAL frags on the other — with each player's team, their running
      total, and what they got in the game just finished.
- [ ] **Resets when the map changes.** Players coming and going does not
      reset it.

### Bots

- [ ] **Better bot play, with a spread of skill** — some genuinely good
      players, some genuinely bad ones.

### Older items

- [ ] **Space map, second pass.** The generator exists now (grey ground,
      glass biosphere domes with grass inside, steel bunkers with lit
      shafts, glowing ships parked in the sky). Beyond the fixes listed
      above, Ian should say what else it needs — interiors, something to
      find.
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

## The look of the menus

**`game/src/ui_theme.gd` is the single source of truth.** Both menus — X
(`player_hud.gd`, the picker) and Escape (`world_menu.gd`) — build a
`Theme` from it and hang it on their panel; everything underneath
inherits. A call site says WHAT a control is and never how to paint it.
If you find yourself typing a colour, a corner radius or a font size
anywhere else, that is the bug.

- **Design pixels.** Sizes in `UiTheme` are at scale 1.0;
  `UiTheme.px(n, sc)` scales them. Scale comes from the VIEWPORT
  (`UiTheme.scale_for`), never from a control's own `size`.
- **Rescaling** = rebuild the Theme and re-assign it. A Theme is a plain
  resource, so this repaints without touching a single node — which is
  what keeps the world menu's "never rebuild rows" rule intact.
- **TabContainer styleboxes must be set on `"TabContainer"`, not on its
  inner TabBar.** TabContainer pushes its own theme values onto that
  TabBar on every theme change, so direct TabBar overrides are silently
  thrown away. That is why the world menu's gold tabs never appeared for
  months — it looked like unstyled Godot because it *was*.
- **Scrollbar width comes from its stylebox's minimum size.** A stylebox
  with no content margins is a scrollbar zero pixels wide, and content
  runs off the bottom of a tab with nothing on screen to say so.
- Eight tabs only just fit a half-width split-screen cell. If you add a
  picker tab, re-check a two-seat run or "Tools" disappears behind scroll
  arrows no child will ever find.

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
