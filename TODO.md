# Voxel Battle — TODO

A live list of OPEN work only (git history is the record of done).

Ian's playtest list (2026-07-29 evening):
- [ ] VERIFY with Ian: fling bug (storm knockback feedback loop removed
      + 60 m/s speed clamp + world-bounds clamp), phantom join (buttons-
      only divergence), disconnect crash guard, banner "Ⓐ to close"
- [ ] TEAMS UI FULL REDESIGN (Players view is the single source of
      team setup):
      · up to 24 teams, no names — colors + letters A/B/C/D… (click
        name to rename, mouse OK)
      · "Add Team" / "Remove Team" buttons; X under each column deletes
        that team and evenly redistributes its COMPUTER players
      · "Add computer player" button: bots are numbered 1, 2, 3…; each
        add/remove evenly distributes bots across teams in CONTIGUOUS
        groups (1-4 A, 5-8 B, …); X at end of a bot row removes it
      · humans are never auto-moved; bots are
      · REMOVE bots-per-team picker and REMOVE the Teams count row from
        the Battle page (column count IS the team count)
      · cap is 24 PLAYERS total (current math stopped at 18)
- [ ] START FLOW: pressing Start Battle Royale dumps you on the Players
      view with no countdown visible and no obvious way the match
      begins — show a clear lobby countdown there
- [ ] BLOCK PICKER RESTRUCTURE like Minecraft:
      · Tools tab = Voxel Battle tools only
      · Blocks split into Minecraft-style category tabs
      · Special tab = ONLY our own inventions (Boom, Bouncy, Launchpad,
        Music, Sponge, Warp Stone, Party Popper, Glow Goo…) — anything
        vanilla (glass, ice, glowstone, lantern, campfire, torch) moves
        to the Minecraft categories
      · icons should resemble Minecraft's: torch/vine/ladder/bamboo
        currently all draw as a flower
      · new kits + better kit icons
- [ ] Fences should CONNECT to neighbors (drop unconnected arms; lone
      fence = post)
- [ ] Character orbit camera: vertical orbit too (look from below);
      face the flying direction when flying; crouch should read as a
      lean-forward/crouch pose
- [ ] Renderer button label: just "Full (restart required)" — drop the
      trailing text
- [ ] LT/RT should switch the TOP-LEVEL tab group (Build/Game/Options);
      LB/RB keep cycling pages
- [ ] VERIFY with Ian: phantom 2nd player from one controller is dead
      (rebuilt as real logic: an unclaimed pad is only join-eligible
      once its full input state DIVERGES from every claimed pad — a
      ghost mirrors forever and can never join; a real 2nd controller
      proves itself the instant someone touches it)
- [ ] VERIFY with Ian: team matrix, menu centering, controller stick+A
      navigation of all menu pages
- [ ] VERIFY with Ian: import fidelity pass — stained glass tints,
      species leaf colors, thin snow layers, trapdoor slabs, nether/end
      stand-ins (re-import a map and check it reads right)
