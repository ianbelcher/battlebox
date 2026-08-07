# BattleBox — TODO

**Outstanding work only.** Git history is the record of what's done.
**This file is the single source of truth** — everything Ian asks for gets
written here, not into any assistant's private memory, so any session (or
any tool) can pick the work up cold.

---

## Open work

Nothing outstanding. Ian will say what is next.

---

## Where this runs

`battlebox.games` is **one DigitalOcean droplet in San Francisco** —
`battlebox-games`, `s-2vcpu-4gb`, sfo3, Ubuntu 24.04, **143.110.238.17** —
not the home cluster. It used to be a k8s deployment on `r710-2` reachable
only from the LAN; that is gone: namespace, both Services, the NodePorts
(30810-30812), the NFS volume and the self-signed certificate. The only
thing left on the cluster is the **build runner**
(`k8s/gh-runner.yaml`), which builds the image and pushes it.

Getting in: `ssh deploy@143.110.238.17`, or `root@` for the box itself.
Both accept Ian's own key; CI logs in as `deploy` with a key of its own
(`DEPLOY_SSH_KEY`, generated for this and used nowhere else). The droplet
IP is deliberately NOT in DNS — the A records are proxied, so the origin
address is not public and does not need to be.

**Cloudflare** proxies both records (apex and www) and the zone is on
**Full**. It should be **Full (strict)**, which the real Let's Encrypt
certificate on the origin makes valid; the API token in use can read zone
settings but not write them, so that one switch is a dashboard click.

Three GitHub secrets make a deploy work — `DEPLOY_HOST` (the IP),
`DEPLOY_HOST_KEY` (the droplet's host keys, pinned so CI never has to
trust whatever answers) and `DEPLOY_SSH_KEY`. Rebuild the box and the
first two change.

```
Cloudflare ──▶ Caddy ──▶ nginx (web role) ──▶ Godot server (server role)
   proxy,      real LE      entry page,           the world itself
   caching     certificate  downloads, /play/,
                            /ws relay
```

`server` and `web` are the **same image** run with a different argument,
sharing one network namespace (`network_mode: service:server`), which is
why `nginx.conf` can say `proxy_pass http://127.0.0.1:9081` — the same
arrangement the two containers had inside a k8s pod. Recreating `server`
tears down the namespace `web` lives in, so `deploy.sh` always brings the
whole stack up together rather than restarting one container.

**Nothing on that box needs backing up.** The game writes no files at all
(see *Nothing is persisted*), so the only volume is Caddy's certificate
store, and losing that just means Caddy fetches a new certificate. The
droplet is disposable: rebuild it from `deploy/cloud-init.sh` and re-run
the workflow.

## Playing in a browser

The **Web** export is served at `https://battlebox.games/play/` alongside
the native downloads. Same source, same server, same world — desktop and
browser players share one game, and the browser is the front door: the
entry page leads with it and the downloads sit underneath.

Four things about it are load-bearing and all four look optional:

- **It must be https, with a certificate the browser trusts.** Godot's
  browser build meshes chunks on real threads, which needs
  `SharedArrayBuffer`, which browsers only hand to a *cross-origin
  isolated* page: the two `Cross-Origin-*` headers in `nginx.conf`, and
  those only count in a secure context. Reaching the container directly
  over plain http (a port-forward, `127.0.0.1:8081` on the droplet) gets a
  game that downloads in full and then dies on startup. That is expected
  there, not a bug.
- **The websocket is proxied through the same origin** as the page, at
  `/ws`. A page served over https cannot open a plain `ws://` socket at
  all: the browser blocks it as mixed content, silently, leaving the game
  on "Finding the world…" with nothing to click.
- **The certificate is Caddy's**, a real Let's Encrypt one renewed over
  HTTP-01. That is why port 80 is open on the droplet even though nothing
  is served there. Close it and the certificate expires 60 days later,
  quietly, on a day nobody is deploying. Cloudflare must stay on **Full
  (strict)** — it is this certificate that makes that valid.
- **`project.godot` sets `renderer/rendering_method.web`** to
  `gl_compatibility`. A browser has no Vulkan; without that override the
  web build inherits Forward+ and renders nothing.

Anything calling `OS.create_process` / `OS.execute` has to be hidden on
web — a browser has no such thing. That is the self-updater (already
gated to Windows/Linux) and the Lite/Full renderer switch (gated on
`OS.has_feature("web")` in both menus).

**The menu key is `` ` ``, not Escape.** A browser keeps Escape for
releasing the mouse and will not give it up, so pressing it dropped you
out of mouse-look and opened a menu you never asked for. Escape still
closes the menu; only opening moved.

**Fonts are bundled now, and they have to be.** The game shipped none
for years: on a desktop Godot silently borrows missing glyphs from the
operating system's fonts, and all 51 symbols the UI is built from came
from there. A browser has none to borrow, so every one drew as a box
with its code point in it — the hearts read "2665". Three fonts, because
no one of them has the lot, and the obvious guesses are wrong: DejaVu
lacks every circled letter (ⒶⒷⓍⓎ, the gamepad caps), and Noto Sans
Symbols **2** does not have them either despite the name — only Noto
Sans Symbols does. `tests/ui_glyphs.gd` scans the UI source for symbols
and asserts a bundled font can draw each one, so adding a new emoji to a
menu fails the test rather than shipping a box to the kids.

Loading them is web-only: on a desktop the system fonts do it better
(macOS draws them in colour). And note where it is installed —
`ThemeDB.fallback_font` alone does nothing, because that is only
consulted when a theme lookup finds nothing at all, and the default
theme does define a font. `ThemeDB.get_default_theme().default_font` is
the one Controls actually read.

To test it for real rather than guess: `tools/webtest.sh` exports the
build, serves it with the production `nginx.conf` behind a stand-in for
Caddy, and drives it in headless Chrome — asserting the page is isolated,
threads are on, and it actually reaches the world. A run that merely fails
to crash proves nothing.

## Nothing is persisted

**The server writes NOTHING to disk. Not one file.** Not where players
stood, not what they carried, not the team layout, not the mode, not the
world's blocks, not the seed, not the clock. A restart is a clean table:
freshly generated terrain, default teams, no computer players, creative
mode. The container has no volume, and there is nothing on that box to
back up.

That is deliberate, and it is the fix for a whole family of bugs. The
world is thrown away on every restart AND every resize, so anything
remembered from the last one only ever made nonsense of the new one:
positions from a map twice the size (players falling to bedrock outside
the new edge), crates hanging in the void, a battle running over terrain
that no longer existed. Do not add persistence back without a reason
better than convenience.

It took two passes to actually be true. The first removed the *reading*:
chunk files and `players.cfg` were deleted at startup, so a restart really
was a clean table. But the *writing* stayed — every edited chunk was still
zstd-compressed out to its own file every 25 seconds, alongside the clock
and a `world.cfg` holding the seed, theme and size. That was compression
and disk I/O on the server's only thread, on a timer, producing files
whose sole purpose was to be deleted on the next boot. All of it is gone
now; `WORLD_DATA_DIR` is gone with it.

**What a fresh world is, is now decided entirely by the environment**
(`WORLD_SEED`, `WORLD_THEME`, `WORLD_SIZE`, `WORLD_SOURCE`) plus whatever
anyone changes from the menu afterwards. There is no third source of truth
in a file. A side effect worth knowing: the map, size and time of day
chosen from the menu no longer survive a restart, because that was the
`world.cfg` doing it — the "clean table" quietly wasn't one.

**The rule this bought, and the one thing that can break it:** an edited
chunk may never be dropped from `ChunkStore._cache`. It has no file to come
back from now, so evicting one would silently regenerate the terrain under
somebody's fort. `trim_cache()` skips anything in `_edited`, and the memory
ceiling that leaves is the world's size, not the uptime — at most 49x49
chunks of 20 KiB, so under 50 MiB even if every corner is dug out.

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

## Aiming

**In first person the shot IS the sight line.** It starts at the eye and
travels along `look_dir()`, so whatever the crosshair is on is what gets
hit — at any range, with nothing to be right at one distance and wrong at
another. `Weapons.shot_ray()` is the single source of truth for where a
shot starts and which way it goes.

Do not "fix" this by moving the muzzle out to the gun and angling the
shot back in. That was tried twice. Converging on a fixed 40 blocks is a
rifle zeroed at 40m — 1.26 blocks off at 150, 2.40 at 250, against a
player 0.6 wide. Converging on the REAL target fixes where the shot ends
but not where it goes: it still travels a diagonal chord beside the sight
line the whole way, so it detonates on blocks the crosshair is not on and
slips round the edge of cover the crosshair is looking past — 0.45 blocks
off the line at a range of ONE block, which is worse up close, not
better. Third person keeps the hip muzzle because it has no crosshair.

The first few frames ARE drawn down and to the right, so a shot appears
to leave the gun rather than the middle of your face
(`Weapons.muzzle_lead`). That moves the MESH ONLY — the orb carries its
true position in `orb.pos`, and everything deciding what a shot hits
reads that, never `node.position`. Do not let the two merge.

`tests/aim_convergence.gd` samples the whole PATH, not the endpoint — an
endpoint-only test passed the converged version happily. It calls
`Weapons.shot_ray()` rather than reimplementing it, and it FAILS if it
measured nothing: its first version printed "PASS — 0 samples" when the
function it was testing could not even be loaded. That has now happened
TWICE, both times because the test reached for something on a script
that references autoloads — which a `--script` run cannot load. Anything
a test needs to check lives on `Weapons` for that reason.

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

- **Ship every round**: commit → push to `master` → wait for the
  `build and deploy` workflow on **that exact commit sha** → **restart
  Ian's debug client** and confirm it reconnected. He tests every round
  and needs to know he's on the new build.
  The workflow is not "green when it compiled": its last two steps check
  that `https://battlebox.games/downloads/version.txt` is this commit and
  that `/play/` still comes back cross-origin isolated. A green tick means
  it is live.
- Debug client: `WORLD_ROLE=client WORLD_AUTOCONNECT=wss://battlebox.games/ws
  WORLD_DEBUG=1 godot --path <abs path to game>`, pid kept in
  `/tmp/world-dev-client.pid`.
- Downloads / version endpoint: `https://battlebox.games/downloads/`
  (`version.txt` holds the built commit sha — check it when Ian says a
  feature is missing; he may have downloaded mid-deploy). The sandboxed
  shell can't reach it; `dangerouslyDisableSandbox` can.
- **On the droplet** (`ssh deploy@143.110.238.17`, everything under
  `/srv/battlebox`): `docker compose ps`, `docker compose logs -f server`,
  and `./deploy.sh <sha>` to roll to any built image by hand. `deploy/` in
  this repo is copied there by CI on every deploy, so edit it HERE — a
  change made on the box is overwritten on the next push.
- **Testing a websocket by hand: pass `--http1.1`.** Over HTTP/2 the
  `Connection` and `Upgrade` headers are illegal, so curl drops them, the
  request lands as an ordinary GET, the WebSocket server rejects it and you
  get a **502 that looks exactly like a broken proxy and is not**. Both
  deploy checks do this correctly; a hand-run one is where it bites.
- **A green build does not mean the game runs — that had to be built in.**
  `--export-release` exits 0 with a GDScript parse error in the project: it
  packs the broken script, and the result serves the right `version.txt`,
  answers `/ws` with 101 and draws a canvas, while the autoload is dead and
  nothing works. The Dockerfile now boots the project (`--quit-after 240`)
  and fails on any `SCRIPT ERROR` / `Parse Error` / `Compile Error`, and
  `webtest_play.js` fails on the same strings in the browser console.
  Neither guard is optional; both exist because that exact thing shipped.
- **Test before shipping.** Headless server + client with `WORLD_AUTOTEST`
  and `WORLD_SHOTS` screenshots; check BOTH split-screen seats for anything
  UI-related.
- **The world menu has two rules; breaking either makes it unusable.**
  (1) Never rebuild it on a timer — rebuilding rows every frame destroys
  the text box being typed in and the button being clicked. (2) Never read
  `size` in `_ready()` — it is 0 there, so fonts bake at minimum scale and
  never grow. Both are documented at the top of `world_menu.gd`.
- Battle test hooks: `WORLD_BOT_WEAPON=<id>` arms every computer player at
  the drop (they otherwise start with a sword and must find a crate), and
  `WORLD_ORB_DEBUG=1` logs every bot shot — fired, hit, or stopped by a
  wall. `WORLD_AUTOTEST_MATCH=<secs>` (any number above 1) starts a fresh
  battle on that interval, which is the only way to check anything that
  has to be the SAME from one round to the next — one battle can never
  show it. `WORLD_CLOCK=<0..1>` pins the time of day (0 midnight, 0.25
  dawn, 0.5 noon, 0.75 dusk) so night lighting can be looked at on purpose
  rather than waited for.
  Every battle start logs its team sites; those coordinates must be
  identical round to round in the same world. Bots drop 16-30% of the world's size from the centre, so shrink
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
