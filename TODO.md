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
- [ ] Bots per-team COUNT control + smarter still (pathing around
      obstacles/water, weapon choice by range, retreat when hurt) —
      server-side bots v1 shipped: menu add/remove runs them on the
      server with hunt/loot/revive/storm-awareness
- [ ] Team structure rework: up to 24 players total; configurable team
      count and size, up to 24 teams (free-for-all)
- [ ] Verify the game-loop live (shipped: END -> 20s countdown -> fresh
      copy of the same map -> new lobby; host = first human, only the
      host can change settings/start/stop the loop)
- [ ] Sword should swing like a real sword (proper arc animation)
