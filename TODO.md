# Voxel Battle — TODO

A live list of OPEN work only (git history is the record of done).

Ian's playtest list (2026-07-29 evening):
- [ ] One controller A-press creates TWO local players it then controls
      (join double-fire — debounce/dedupe joins)
- [ ] MENU REDESIGN for controllers: more, smaller tabs — split Battle
      Royale / Computer players / Video into their own tabs; consider two
      LEVELS of tabs (Build: tools/blocks/special/kits · Game: battle,
      bots, world · Options: character, video). Tabs must change ONLY
      with LB/RB (left/right in a picker currently changes tabs too)
- [ ] Blocks picker on small screens shrinks chips to fit — keep chip
      size and scroll instead
- [ ] Battle options must SHOW the selected value (highlight the active
      length/size/loot buttons)
- [ ] First arena size = 50 (not 25); options 50/100/150/200/250
- [ ] SERVER-SIDE BOTS: computer players run on the server, added from
      the menu (never as local split-screen players — remove that);
      set the NUMBER of bots per team
- [ ] Team structure rework: up to 24 players total; configurable team
      count and size, up to 24 teams (free-for-all)
- [ ] Computer players need to be MUCH smarter: pathing around
      obstacles, target selection, weapon choice by range, retreat when
      low, loot when unarmed, revive teammates reliably
- [ ] BATTLE FLOW rework: end-of-battle winner banner on every screen
      (dismissable); all humans dead -> "no winner" end; then a countdown
      to the NEXT game; map recreated/reset between games (game-loop is
      the normal mode); the FIRST human to join controls the battle
      settings and can stop the loop
- [ ] CAMERA: right stick orbits FREELY around the player (no isometric
      snap); Y (pad) / T (keyboard) cycles orbit -> top-down -> first
      person
- [ ] Sword should swing like a real sword (proper arc animation)
- [ ] Movement: normal = walking, audible to nearby players; Shift =
      CREEP (slow + silent), like Minecraft sneak
