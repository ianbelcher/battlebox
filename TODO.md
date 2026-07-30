# Voxel Battle — TODO

A live list of OPEN work only (git history is the record of done).

- [ ] ICON PHILOSOPHY CHANGE: stop iso-cube-plus-overlay-lines. Icons
      should be flat, distinctive, Minecraft-texture-style art per
      block (front-face view with a real pattern fill), like MC item
      icons — different things must look DIFFERENT at a glance
- [ ] IN-WORLD BLOCK FACES: bookshelf/crafting table/chest placed in
      the world are just brown cubes — signature blocks need real face
      detail in the terrain renderer (procedural face textures via
      face UVs + block id, like the plant silhouettes)
- [ ] Functional tab chips render way bigger than other tabs — make
      picker chip size consistent across all block tabs
- [ ] WORLD SWITCHING decoupled from battle: selecting a world while
      NO battle is running should switch the world right away (and
      still record it as the battle world); battle royale is a MODE

- [ ] Vanilla sweep leftovers (low priority): per-species fence/door
      colors, glazed terracotta patterns, purpur block, mycelium
      purple top, tinted glass panes
- [ ] ICONS MEGA-REDO (BIG — asked multiple times): every block icon
      redrawn to read like Minecraft's actual iconography — kids can't
      read, the picture must say what it is (leaves ≠ plain green cube:
      mottled leaf texture; recognizable flowers; log with bark + ring;
      etc). Exceptions: Special (ours), Kits (fine), Tools (fine as
      icons — but the 3D held tool models "kind of suck", improve them)
