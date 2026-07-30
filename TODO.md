# Voxel Battle — TODO

A live list of OPEN work only (git history is the record of done).

- [ ] ICONS MEGA-REDO (BIG — asked multiple times): every block icon
      redrawn to read like Minecraft's actual iconography — kids can't
      read, the picture must say what it is (leaves ≠ plain green cube:
      mottled leaf texture; recognizable flowers; log with bark + ring;
      etc). Exceptions: Special (ours), Kits (fine), Tools (fine as
      icons — but the 3D held tool models "kind of suck", improve them)
- [ ] MISSING BLOCKS: add the ground "plates" (carpets in wool colors,
      pressure-plate look) and sweep for other common vanilla blocks
      still absent
- [ ] CATEGORY TAXONOMY: use Minecraft's own creative taxonomy —
      Building Blocks / Colored Blocks / Natural / Functional — instead
      of our invented Building/Nature/Colors/Lights split
- [ ] BATTLE FLOW REWORK:
      · Start button lives at the TOP of the Game group with the
        countdown shown in it once clicked; tabs (Battle/Players/World)
        sit under it
      · World page = SELECT the world for the next battle (gold
        highlight on the currently selected world, persisted) — do NOT
        instantly switch the world and slam the menu shut
      · starting must not yank everyone to the Players tab; humans are
        auto-assigned a team the moment the lobby opens (never
        team-less), anyone can still switch
- [ ] UI PROFESSIONAL PASS:
      · padding inside every tab view (content is flush to the edges)
      · hover turns button text white which hides the selected state —
        selected must stay YELLOW, hover must not mask it
      · Players list: rows far too tall (chevron + name + robot icon
        huge) — compact rows, no scrolling for a full 24 lobby
      · hide "+ Computer player" at 24 players; add "− Computer player"
        (removes the most recent)
