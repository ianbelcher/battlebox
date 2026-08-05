# Voxel Battle — TODO

**Outstanding work only.** Git history is the record of what's done.
**This file is the single source of truth** — everything Ian asks for gets
written here, not into any assistant's private memory, so any session (or
any tool) can pick the work up cold.

---

## Open work

From Ian, 5/8, testing a 6v6v6v6. Roughly in the order they spoil a game.

### The match itself

- [x] **A battle must NOT end when the last human dies.** The computer
      players carry on and finish it; the humans watch. Ending it there
      is why a game stopped with teams still standing.
- [x] **Nobody is ever removed from a team.** A whole team "disappeared"
      mid-match. Only a HUMAN may leave a game.
- [x] **`alive / total` is wrong.** The alive number looks right; the
      total is not. Total should be the SIZE OF THE TEAM and stay put all
      match, so a wiped team reads 0/6 and is still listed.
- [x] **"N players left" disagrees with the teams.** Seven standing on
      the panel while the top line said thirteen. One definition,
      everywhere.
- [x] **Dead players should be able to move around and watch** —
      invisible, unable to shoot, free to wander back to their base and
      be revived there.

### Loot and the hotbar

- [x] **Picking loot up must not SELECT it.** Mid-fight your weapon
      switches out from under you.
- [x] **Never two of the same weapon in the hotbar.** Collecting a
      duplicate still denies it to everyone else; it just does not stack
      up in the bar.
- [x] **The Tools tab should let you pick what you have collected.** It
      is currently not selectable at all in a battle.

### The map in the corner

- [x] **Bigger, and readable.** Wash the terrain out — lower contrast,
      greyer — so the blips carry the picture.
- [x] **Take the yellow dots off it** (loot, and whatever else is
      speckling it). It should read as a radar, not a satellite photo.
- [x] **Zooming with X/V should zoom the map too.**
- [x] **A MAP TAB in the player menu**: pan with the right stick, zoom
      with up/down on the left.

### Elsewhere

- [x] **The final scoreboard vanishes too fast.** Also wanted as a TAB in
      the player menu, so it can be read whenever.
- [x] **The sword's tip is on backwards** — the cone points back down the
      blade instead of out.
- [x] **The paint sprayer only paints some blocks.** It should cover far
      more of them.
- [ ] **Computer players go stupid when running from the storm** — they
      get stuck against things and will not dig their way out.


- [x] **Space map — anything more?** Everything asked for is done: domes
      sit on the ground, loot stays off roofs and hulls, landmarks are on
      a 56-block grid so a map gets several caverns, the cavern entrance
      is a ramped archway, ships have hulls, cockpits, fins and engines
      in three sizes. Interiors, or something to FIND in there, needs a
      steer from Ian.
- [ ] **More kits — needs Ian to pick.** Pure sourcing: download the
      builds you want, drop them in a folder, run the importer. 28 of the
      143 MoreChineseStructures builds ship; the rest are street
      fragments or too big to stamp. See "Adding more kits" below.
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

## Nothing is persisted

**The server keeps NOTHING on disk about a game in progress** — not
where players stood, not what they carried, not the team layout, not the
mode, not the world's blocks. A restart is a clean table: fresh terrain,
default teams, no computer players, creative mode.

That is deliberate, and it is the fix for a whole family of bugs. The
world is thrown away on every restart AND every resize, so anything
remembered from the last one only ever made nonsense of the new one:
positions from a map twice the size (players falling to bedrock outside
the new edge), crates hanging in the void, a battle running over terrain
that no longer existed. Do not add persistence back without a reason
better than convenience.

## Placing a player

**A computer player's position lives in `_bots`, NOT in
`_player_state`.** That is what stranded Alpha and Bravo outside the map
and put them back in the same spot on every regenerate: the world reset
cleared `_player_state` and never touched `_bots`, so bots simply stood
wherever they had been standing in the world before. `_do_world_reset()`
now re-places every bot AND rebuilds its `_player_state` entry (clearing
that wholesale had been deleting the bots' entries too, which makes a
bot invisible to the radar, to targeting and to crate pickup).

`_server_tick_bots()` also pulls any bot found outside the world back in,
and `sv_pos()` does the same for a person — clients report their own
position, so one still running in the world that was just replaced will
send coordinates from it. Neither is a substitute for placing them
properly; they are there so no future path can strand anyone.

**Test hooks**, all for whole-sequence behaviours that otherwise need a
person driving the menu: `WORLD_RESIZE_TEST=<size>` spawns four computer
players and resizes the world after 12s, logging where everyone ends up;
`WORLD_KICK_TEST=1` kicks the first human after 15s; `WORLD_WIN_TEST=<team>`
hands out some knockouts and ends the battle for that team after 22s, so
the end-of-match scoreboard and the win count can be checked.

**`ChunkStore.safe_stand()` is the only thing allowed to decide where a
person ends up.** Joining, respawning, a match starting, a world reset —
all of it goes through there, and what comes out is always inside the
slab and always on solid ground. `tests/placement.gd` hammers it across
world sizes and themes.

Players kept turning up off the map because each caller did its own
bounds check, so each new caller was a fresh chance to forget — and the
one that mattered most was wrong anyway: `WorldGen.find_spawn()`
spiralled out to 88 blocks whatever the world's size, so on a 50-block
map the world's own spawn point was off the map, and every other path
falls back to it.

**Use `floori()`, never `int()`, on a world coordinate.** `int()`
truncates towards zero, so `int(-45.5)` is `-45` — a different column
from the one `-45.5` sits in. Every coordinate west or north of the
origin is off by one if you get this wrong, which is half the map.

## The edge of the map

**The slab is SQUARE, and each axis is clamped on its own** — which is
what makes you SLIDE along the wall instead of stopping dead when you
walk into it at an angle. `WorldNode.world_half()` is the only thing
that decides how far you can walk.

Players used to be stopped by a CIRCLE of `world_radius`, a fixed 250 or
400 whatever the map's real size, so on any smaller world you strolled
past the terrain — and the server, seeing somebody outside the map,
teleported them to the spawn. Walking to the edge of your own world threw
you into the middle of it. `world_radius` still exists for the ocean
backdrop's draw distance; do not use it for anything else.

`sv_pos()` quietly clamps a position just outside and only resets one
WILDLY outside (32+ blocks), which is a stale world rather than a walk.

## Leaving the game

**The ✕ in the world menu gives up that player's SEAT on their own
machine.** Three players become two, the split screen rebuilds, and if
they were the last one there the join prompt comes back over a spectator
view — the connection stays up.

`Game._drop_kicked_seats()` only drops a seat it has SEEN confirmed in a
roster broadcast and then watched vanish. Registration is a round trip
and the server sends the roster on connect, before this machine's players
are in it, so dropping seats on any missing id wiped every one of them
the moment anybody was kicked.

## Counting who is still alive

**"standing / still in the game".** A DOWNED player is still in
`alive_ids` — they can be revived — so counting that alone left every
team reading 8/8 however many were on the floor. Both the top score line
and the per-team panel now count: still-in = in `alive_ids`, standing =
in `alive_ids` and NOT in `client_downed`. Anyone eliminated drops out of
both, so a team of eight that loses one reads 5/7, not 5/8.

`cl_downed_state` emits `match_score_changed`; only elimination used to,
which is why downing half a team moved nothing on screen.

**A match's result is recorded once.** `_result_recorded` is set the
moment a battle is decided and cleared as the next opens — several
players eliminated in the same tick used to count two wins for one game.

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
