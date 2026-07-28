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
- [ ] Menu tab ORDER review with Ian (current: Blocks Tools Special Kits
      Character Game)
- [ ] Overlapping center banners (loading label vs banner label)

## Features (medium)
- [ ] SPRINT (hold a key/stick-click to run faster, mild tradeoff)
- [ ] Held-item viewmodel: see your weapon/block in hand (first person and
      on other players' avatars), swing/recoil animation on use
- [ ] 3D item models instead of glowing orbs for crates + hand items
      (build like the critters: chunky procedural meshes per weapon)
- [ ] Better special-block icons (lantern/campfire/glowstone/lava glyphs)
- [ ] Bot AI that actually plays: seek crates, chase/shoot enemies, stay
      near team, revive ghosts (currently wander-only)

## Features (large)
- [ ] Rideable flying creatures (dragons/pterodactyls): grapple onto one,
      sit a mount point, steer it around — non-block creatures
- [ ] Worldgen themes that are truly different: a CASTLE world (one huge
      explorable castle), a CITY world, denser distinct biomes; option to
      import open-source Minecraft maps as arenas
- [ ] Multi-server flow: team eliminated -> back to lobby -> join the next
      match; multiple match servers at once
- [ ] Match arena pre-generation as its own compact map (250x250, capped
      height band) rather than reusing the persistent island

## Done this round
- [x] Population One ghosts + loud 6s revives; storm arrow + glowing wall
- [x] Sword-only night drops, empty slots, labeled crates, arena prefetch,
      no disk writes mid-match, full-roster lobby with bot teaming
