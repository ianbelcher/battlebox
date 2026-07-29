# Boxel Battle (was Belcher World) — working list (Ian + Claude)

## AUDIT — Ian's asks, current status (keep this honest!)

DONE this overnight run:
- [x] VIDEO SETTINGS DONE PROPERLY (Ian's ask): presets deleted; every
      setting individual — Draw distance slider IN BLOCKS (48-208),
      Render scale % slider, Shadow quality slider, checkboxes for
      Shadows/SSAO/Glow/Dynamic lights/Wireframe, all persisted to disk;
      Renderer: Full/Lite switch IN-GAME (game restarts itself — no bat
      files, those are deleted); "Smoother mode" auto-override and its
      banner removed entirely
- [x] Startup jank: meshing is now TIME-budgeted (5ms/frame, 12ms in
      matches) instead of chunk-counted — load-in no longer hitches
- [x] Renamed to just BOXEL everywhere (title, server log, downloads are
      boxel-macos.zip / boxel-windows.exe / boxel-linux.x86_64)
- [x] PERFORMANCE ROUND: X-Ray Goggles removed; Wireframe back as a video
      toggle; Draw distance option (Near/Normal/Far) drives the streaming
      ring; shadow atlas shrinks on lower presets (4096/2048/1024); radar
      rebuilds 3x less often under 20fps; LITE launchers shipped
      (belcher-world-windows-LITE.bat / linux-lite.sh) that start the game
      on the GL Compatibility renderer — verified working, this is the fix
      for old PCs where Vulkan crawls at 1fps. Download page explains it
- [x] Lite-mode look: GL renderer auto-boosts sun+ambient 1.45x —
      screenshot-verified it now matches the Forward+ look
- [x] Battle UI is an in-menu SECTION (no modal): Game tab = BATTLE ROYALE
      (Start + "Game length: 3/5/8/Unlimited" + Teams inline), WORLD
      (Classic/Desert/Isles/Castle/City/Skylands/Ian's World buttons),
      PLAYERS (add/remove bot together). Video is its own tab
- [x] Map/biome picker for battles: WORLD buttons switch the server map
      live (sv_new_map) — including "Ian's World" = the imported r.0.0.mca
      (auto-found in maps/, center 256,256; Dockerfile ships it)
- [x] Real cave NETWORKS (connected tunnel worms + vast caverns + water
      pools + stalagmites/stalactites + crystals) with walkable funnel
      entrances from the surface
- [x] SKYLANDS theme: floating island grid, parabolic 2-wide plank
      bridges, waterfalls off rims, guaranteed spawn island
- [x] City + castle stairs rebuilt: 2 wide, proper headroom holes, roof
      access; eye height now BELOW collision top (1.65/1.85, avatar 1.15)
      so your head can never see inside blocks
- [x] Little/Medium/Big Shooters (Big = 2s cooldown, enormous blast);
      underwater blue tint; sword held up + sweeping swing

STILL OPEN (next session — do these first):
- [x] Menu theme passes 1-3: uniform rounded buttons with hover/press
      states + styled tab bar (gold underline on the active tab)
- [x] Unlimited is truly unlimited: storm never closes, match ends only
      when one team stands
- [x] Kit chips show real per-structure preview icons (house, tower,
      tree, bridge, campsite, pool, garden, fort, bunker, sniper,
      barricade) in the picker grid and hotbar
- [x] X-Ray Goggles crate pickup: while held, every player glows through
      the walls (private per-player render layer). Wireframe stays as a
      video toggle for now per Ian
- [x] Wireframe requires a debug build (clients export release), so the
      toggle now only appears in dev builds — a true developer tool. The
      other video toggles use runtime settings that work everywhere
- [x] Dedicated compact ARENA map: new "Arena" world button — tight
      ~250x250 island, storm starts at 140 and drop ring scales, whole
      map resident instantly
- [x] Map LIBRARY: maps/ subfolders (region files + map.cfg with
      name/center/y0) appear automatically as WORLD buttons — the server
      broadcasts its library to every client. maps/README.md documents
      adding maps + good CC sources (minecraftmaps.com, Planet Minecraft)
- [ ] Multi-server lobby flow — likely SUPERSEDED by live map switching +
      in-place matches on one server; confirm with Ian before building
- [x] Clock/player-count moved under each player's own radar (the global
      top-right clock overlapped player 2's radar in splits)
- [x] Full theme screenshot sweep at 2560x1440: desert, isles, arena and
      Ian's MCA world all render clean (0 script errors); arena verified
      as a great compact battle island; clock font shrunk to stop edge
      clipping
- [ ] Ask Ian what "themes drop together in the main play" meant

The durable backlog. Claude: keep this file updated every iteration —
strike items when shipped, add new asks immediately.

## Bugs / polish (small)
- [x] Digger felt like a 10s cooldown: server range check rejected shots
      while moving (fixed: wider check + ~1.2s cadence, tunnel-as-you-run)
- [x] Picker auto-advance left the NEXT (empty) slot selected, so the
      weapon you just picked wasn't in hand (fixed: stays on filled slot)
- [x] Shots left the body at chest height, not matching the crosshair
      (fixed: muzzle at eye line, converges with crosshair)
- [x] Menu tabs reordered: Tools first (battle game), then Blocks etc.
- [x] Overlapping center banners fixed

## Features (medium)
- [x] SPRINT: hold Shift / click left stick, 1.55x on the ground
- [x] Held items visible: right-hand item on every avatar (replicated) +
      first-person viewmodel (per-player render layer). Swing/recoil anim
      still open
- [x] ItemFactory: procedural 3D models for all weapons; crates show them
- [x] Special-block icon glyphs (lantern/glow/fire/glass)
- [x] BotBrain v1: seeks crates, chases and shoots enemies, revives
      teammates. Still basic (no pathfinding around cliffs)

## Features (large)

- [ ] BIG: map picker when starting a Battle Royale — choose a SAVED MAP
      (imported Minecraft .mca worlds, starting with maps/r.0.0.mca which
      imports cleanly: WORLD_SOURCE=mca WORLD_MCA_DIR=maps
      WORLD_MCA_CENTER=256,256) or an auto-generated biome theme. Needs:
      server-side multi-map support (world store per map), lobby UI row,
      map handoff without restarting the server
- [ ] BIG: research + download open-source Minecraft maps/builds online
      (minecraftmaps.com, Planet Minecraft CC-licensed packs) as an arena
      library; document per-map WORLD_MCA_CENTER/Y0 settings
- [ ] Menu UX beauty pass round 2 (Ian: still janky) — spacing, selector
      sizing, consistent button styles, hover/press feedback
- [ ] Verify the Wireframe video toggle works in exported release builds
      (set_debug_generate_wireframes may be debug-only)
- [ ] Clarify with Ian: "themes drop together in the main play"
- [ ] NOTE: old saves placed 10-column family blocks (ids 95-102) now render
      as gaps after the 8-column rename — a New Map clears it
- [x] DRAGONS: rare soaring beasts; grapple one to mount and ride its
      flight, jump to dismount. Steering is v2
- [x] CITY theme (street grid, glass-windowed buildings, lamps, parks) and
      CASTLES rebuilt as ONE mega-castle (curtain walls, towers, hollow
      keep with floors). Minecraft-map arena import still open
- [ ] Multi-server flow: team eliminated -> back to lobby -> join the next
      match; multiple match servers at once
- [ ] Match arena pre-generation as its own compact map (250x250, capped
      height band) rather than reusing the persistent island

## Done this round

- [x] Weapons.spec() looked up by ARRAY POSITION — the tools reorder gave
      every weapon the wrong cooldown/speed (rapid bazooka, broken
      blaster). Now a by-id lookup; bazooka kept fun-fast (0.35s)
- [x] Bare bones video actually works: DayNight was re-enabling shadows
      every frame; Video panel moved to its OWN tab with all toggles
- [x] Battle Royale is a proper modal: Start BR opens it (storm presets,
      team list, GO); when a match opens it pops for EVERY player without
      hijacking their menu. Game tab = Start BR / add+remove bot / new map
- [x] Blocks tab: one material family per line (8 per row) + texture
      overlays; kit chips 2x bigger; menu borders de-yellowed
- [x] Sword (and viewmodel) swings when used; bigger character preview
- [x] Per-player storm tint, hearts from the drop, castle keep halls with
      stairs + chandeliers, r.0.0.mca imported + verified

- [x] Materials renamed with REAL names in 8 rainbow-aligned columns:
      steel (Bronze/Copper/Gold Alloy/Emerald Steel/Cobalt/Amethyst
      Steel/Silver/Iron), stone (Ruby/Topaz/Amber/Jade/Lapis/Amethyst/
      Gypsum/Coal), ORGANIC (Redwood/Timber/Sand/Turf/Clay/Lavender/
      Birch/Peat — and organic BURNS + spreads fire), snow (…/Ash).
      NOTE: old saves' family blocks (ids shifted) may show gaps
- [x] Tools tab: combat row (Sword, Blaster, Bazooka, Grapple, Digger,
      Napalm, Flare) then utility row (Wings, Bridge, Popper, Whirl,
      Paint); square colorful icons instead of circles, new sword glyph,
      material texture overlays on family block icons
- [x] Real swimming: hold jump to rise, Shift to dive; grapple works from
      water; build up from the seabed
- [x] Video presets in Game tab: Fancy / Simple / Bare bones
- [x] Battle lobby moved into the menu: starting a match auto-opens
      EVERY player's menu on the Game tab with storm presets
      (3/5/8/Endless), sword-only toggle and a proper team picker list
- [x] Menu cleanups: duplicate in-menu slot row removed, radar no longer
      overlays the menu
- [x] Progressive whole-island preload after joining (radius 8→17)

- [x] RADAR MATH FIXED: screen-to-world used +yaw instead of -yaw, so the
      map was mirrored/inverted — now rotates correctly against you
- [x] Wider streaming ring (7-13 chunks) so travel doesn't pop in
- [x] Crates fade beyond 140m (no more loot floating past the terrain)
- [x] City v3: 26-block grid with wide sandstone-edged roads, traffic
      lights at intersections, car parks with parked cars, staircases
      inside every building (stairwell holes in slabs), open lift shafts
      in towers for grappling, glowstone floor markers
- [x] Client crash guard: block edits above the world ceiling ignored

- [x] Radar rotates with facing (forward = up) + 128px detail pass
- [x] Storm wall roof removed (cylinder caps) — no more red ceiling
- [x] Sword now hits players you LOOK at (was using stale walk heading)
- [x] Drop glide fixed (stale on_floor canceled it instantly)
- [x] Chunk mesh bursts (4/frame) during matches/backlogs + prefetch 15 —
      arena actually preloaded
- [x] Team-colored glow light on every player during matches
- [x] Top-down 5th camera state reachable again (rotate wrapped at 4)
- [x] Keys: Z/X rotate, C/V zoom (were interleaved)
- [x] City v2: parks with flowers/bushes, varied building footprints and
      heights, real floors every 5 levels, ivy walls, rooftop gardens

- [x] Storm rework: wall is now a solid-looking 12-block-high red wall (no
      emission, no sky-wide red wash); 12-block warning band outside it
      before damage kicks in (then hits every 1.6s); the storm CHEWS the
      terrain — surface blocks just outside the wall pop away with booms
- [x] Battle royale start repopulates loot: 40 fresh crates scattered
      across the island every match (plus richer ambient pool)
- [x] Per-player radar: every player has their own map centered on them —
      terrain, storm ring, crates (gold), other players (team colors), you
      (white). Shared minimap retired
- [x] Flare Gun: fires a bright star skyward that floats down lighting a
      huge area for ~8s
- [x] Gear slot: chestplates (steel/gold), shoulder pads, capes, backpack,
      glowing badge — accessories over the shirt
- [x] Characters no longer welded to a controller: Character tab has a
      "Character: ◀ ▶" picker to switch between all saved characters
- [x] Remove-computer-player button in the Game tab
- [x] Character tab fits in split-screen (hint text removed, preview
      scales to the cell)

- [x] FIXED the "menu always opens on Kits" bug for real: BlockPicker.open()
      flips tab-child visibility which yanks TabContainer to the last picker
      (Kits) — pickers now open before the tab is set, guarded from
      polluting the last-tab memory
- [x] FULL character customization: 7 parts (skin, face, hair, hat, shirt,
      pants, shoes) — 8 faces (glasses/sunglasses/freckles/sleepy...),
      12 hairs (spiky/long/ponytail/afro/mohawk...), 13 hats incl. knight
      helmet, viking horns, wizard hat, top hat, headphones, chef hat,
      12 shirts with stripe/band patterns, pants + shoes colors. All saved
      per controller as before

- [x] Weapon feel pass: viewmodel re-centered + Doom-style parabolic run
      bob, long weapons pushed forward, gun hides when zoomed, shots leave
      the right-hand muzzle and converge on the crosshair, hand item no
      longer doubles in first person
- [x] Shots explode/break blocks at ANY distance (server capped at 34m)
- [x] Menu reopens on the last-used tab (was always the same one)
- [x] Character tab: preview large + on the right, style changes keep the
      spin instead of restarting it
- [x] Sprint footsteps audible <30m (walking silent)
- [x] Population One ghosts + loud 6s revives; storm arrow + glowing wall
- [x] Sword-only night drops, empty slots, labeled crates, arena prefetch,
      no disk writes mid-match, full-roster lobby with bot teaming
