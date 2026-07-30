# Voxel Battle — TODO

A live list of OPEN work only (git history is the record of done).

Ian's playtest list (2026-07-29 evening):
- [ ] MENU REDESIGN for controllers: more, smaller tabs — split Battle
      Royale / Computer players / Video into their own tabs; consider two
      LEVELS of tabs (Build: tools/blocks/special/kits · Game: battle,
      bots, world · Options: character, video). [Tab bar no longer eats
      arrow input — LB/RB only — shipped; full redesign still open]
- [ ] Blocks picker on small screens shrinks chips to fit — keep chip
      size and scroll instead
- [ ] SERVER-SIDE BOTS: computer players run on the server, added from
      the menu (never as local split-screen players — remove that);
      set the NUMBER of bots per team
- [ ] Team structure rework: up to 24 players total; configurable team
      count and size, up to 24 teams (free-for-all)
- [ ] Computer players need to be MUCH smarter: pathing around
      obstacles, target selection, weapon choice by range, retreat when
      low, loot when unarmed, revive teammates reliably
- [ ] Verify the game-loop live (shipped: END -> 20s countdown -> fresh
      copy of the same map -> new lobby; host = first human, only the
      host can change settings/start/stop the loop)
- [ ] Sword should swing like a real sword (proper arc animation)
