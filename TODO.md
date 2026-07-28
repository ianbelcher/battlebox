# Belcher World — working list (Ian + Claude)

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
