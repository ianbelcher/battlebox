# Boxel — TODO

A live list of OPEN work only. Items leave the list when they are done
(git history is the record).

## Now
- [ ] DRAGONS v2: LARGE flying dragons (Aerodactyl-in-Cobblemon scale),
      mountable (grapple or touch), actually flyable (steer with look +
      move, rise/fall, jump to dismount), fire breath while riding —
      shots like the Medium Shooter but with big ORANGE fireball
      explosions, no lingering fire spread
- [ ] Character tab rework: smaller ◀ ▶ buttons; name field at the top of
      the RIGHT column above the preview; separator lines between the
      character picker and the style rows; preview as large as possible,
      NO auto-rotation — drag on the preview to turn the character
- [ ] Game tab with several players must fit/scroll cleanly (scrolling
      shipped — verify with 3-4 players and long team lists)
- [ ] Sky islands: less grid-like (jitter positions), mix of big and small
      islands, wider height range, some vertical connections between
      stacked islands
- [ ] Castle interior is still a mess — proper rooms/halls redesign
- [ ] Plant variety: fern, dead bush, cattail, daisy, bluebell, wild
      wheat... distinct shapes/colors, scattered by biome
- [ ] More block types + richer Minecraft import palette (dirt_path,
      gravel, stone_bricks, mud, andesite, deepslate...) so imported
      roads read as roads
- [ ] Mac window resize fights the mouse capture (window can only shrink);
      release the mouse while the window is being resized
- [ ] Multiple local players each stream their own area (by design), but
      review draw distance interplay Ian saw with 3+ players
- [ ] Verify with Ian: block-edit jank should be FIXED now (meshing moved
      to a worker thread — nothing blocks the render thread anymore)

## Later
- [ ] Multi-instance servers (Ian: ws://ip:port/servername, one shared
      game per named server; multi-tenant later)

## Notes
- Map library: maps/<folder>/ + region .mca files + map.cfg — see
  maps/README.md. Current maps: Custom 1-4.
