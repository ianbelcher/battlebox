# Voxel Battle — TODO

**Outstanding work only.** Git history is the record of what's done.
**This file is the single source of truth** — everything Ian asks for gets
written here, not into any assistant's private memory, so any session (or
any tool) can pick the work up cold.

---

## Open work

Nothing outstanding. Ian will say what is next.

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

## Computer players and the ground

**`surface_y()` is the TOP of a column, which for anything with a roof
is the roof.** Never use it to decide where a body can stand — use
`WorldNode._walk_y(wx, wz, from_y)`, which finds the floor reachable
from a given height and needs two blocks of headroom.

Getting this wrong is subtle and it bit hard: a computer player inside a
castle saw a wall in every direction (nothing was ever one step up from
the roof), AND the code that keeps a bot on the ground lerped it toward
`surface_y + 1`, dragging it up through the ceiling onto the
battlements. They ended up standing on roofs turning on the spot at the
same coordinates for a whole match. On a castle map it was 5 of 12; with
`_walk_y` it is 0 or 1.

Blocked bots run a small breadth-first search over the local heightmap
(`_bot_path_step`) — 17x17, capped, recomputed at most every 0.6s —
and dig through when there is genuinely no route. Falls are FREE: jumping
off a roof to get out of the storm is the right move.

**Test hook:** `WORLD_BOT_DEBUG=1` reports, every ten seconds, how far
each live computer player actually got and names any that have not
moved. Stuck is invisible in a screenshot, so it needs a number — and
the number only counts bots that are alive and not downed, or it means
nothing.

## Tweens

**`create_tween()` binds the tween to the node that CALLS it, not to the
node it animates.** Get that backwards with `.set_loops()` and you have
an immortal tween stepping over a freed object for the rest of the
session.

That is what locked up both machines mid-game: the smoke marker built
fourteen infinite tweens with the WORLD's `create_tween()`, so taking
the marker down freed the puffs and left every tween alive and looping,
for every bomb anyone had ever thrown. Godot reports each invalid step,
and printing errors with backtraces is slow enough to stop a client
dead. Measured with `WORLD_SMOKE_TEST=1` (a bomb a second): 672 client
errors in a minute with the bug, 0 with one tween bound to the marker.

Call `create_tween()` **on the node being animated**, and kill it
explicitly when you tear that node down.

## Weapon icons

`assets/ui/weapons/w<id>.png` is a render of that weapon's HELD MODEL,
not a drawing. `tests/weapon_icons.gd` makes them — it frames each model
from its own bounds, so weapons modelled around wildly different origins
all come out centred and the same size:

```sh
WORLD_ICON_IDS=18,19 WORLD_ICON_OUT=$PWD/assets/ui/weapons \
  godot --path game --resolution 256x256 res://tests/weapon_icons.tscn
```

It needs a real window — a headless run has no renderer. A weapon with
no PNG falls back to BlockIcon's hand-drawn shapes, which look like a
different game beside the rendered ones.

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
