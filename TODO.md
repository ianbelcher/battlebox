# Voxel Battle — TODO

A live list of OPEN work only (git history is the record of done).

Ian's playtest list (2026-07-29 evening):
- [ ] OVERNIGHT DIRECTIVE (Ian, before bed 2026-07-29): after all items
      are done, iterate on the overall UI and feel of the app and tune
      it as much as possible for the best user experience
- [ ] VERIFY with Ian: picker categories (Building/Nature/Colors/
      Lights/Special/Kits), real torch/vine/ladder/bamboo + shaped
      icons, connected fences/walls/panes, 3 new kits, vertical orbit,
      crouch pose, fly lean
- [ ] VERIFY with Ian: teams redesign (add/remove/rename teams, numbered
      bots with contiguous distribution, X controls, lobby countdown on
      the Players page, LT/RT group switch)
- [ ] VERIFY with Ian: fling bug (storm knockback feedback loop removed
      + 60 m/s speed clamp + world-bounds clamp), phantom join (buttons-
      only divergence), disconnect crash guard, banner "Ⓐ to close"
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
