# Boxel — TODO

A live list of OPEN work only. Items leave the list when they are
absolutely done (git history is the record of what shipped and when).

## Now
- [ ] DRAGONS v2 (Ian): current "dragons" are chicken-sized and can't be
      grappled/mounted. Wanted: LARGE flying dragons (Aerodactyl-in-
      Cobblemon scale), grapple or approach to MOUNT, then actually FLY it
      (steer with look/move, gain/lose height); while riding you keep a
      crosshair and can breathe fire — shots like the Medium Shooter but
      with big ORANGE fireball explosions (no lingering fire spread)
- [ ] Plant variety: several new cross-plants (fern, dead bush, cattail,
      daisy, bluebell, wild wheat...) with distinct shapes/colors,
      scattered by biome/moisture
- [ ] More block types for building + richer Minecraft import palette
      (dirt_path/gravel/stone_bricks/mud/andesite/deepslate -> sensible
      Boxel blocks) so imported roads read as roads
- [ ] Confirm on Ian's Mac: movement jank while new areas appear should be
      gone now (chunks never unload/re-pull anymore; far ones just hide)
- [ ] Skybox: verify the dark-moon disc is gone and the horizon band looks
      good at day + night (first pass shipped; review in-game)

## Waiting on Ian
- [ ] Is a multi-server lobby flow still wanted, now that one server
      switches maps live and runs matches in place?

## Notes
- Map library: maps/<folder>/ with region .mca files + map.cfg
  (name/center_x/center_z/y0) shows up automatically as a Maps button.
  Current: Custom 1-4 (the four regions Ian added).
- Arena (generated) = a small ~250x250 battle island: fights start fast,
  the storm ring is scaled down to fit, whole map loads instantly.
  > Please remove this.
