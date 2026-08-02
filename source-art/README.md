# Source art

The original art packs the game's models were extracted from. **Only this
README is in git** — the zips are tens of megabytes and what ships is the
extracted `.glb`/`.obj` under `game/assets/models/`.

Keep the zips here if you have them; nothing at runtime reads this
directory. They matter when art needs regenerating rather than just using.

| File | Extracted to | Notes |
| --- | --- | --- |
| `voxel_dinosaurs_pack.zip` | `game/assets/models/dinos/` | |
| `farm_animals_pack_upload.zip` | `game/assets/models/farm/` | |
| `jungle_animals_pack.zip` | `game/assets/models/jungle/` | |
| `voxel_forest_animals_pack.zip` | `game/assets/models/forest/` | |
| `little_people_in_voxel_v2.zip` | `game/assets/models/people/` | **Still needed.** `tools/rig_people.py` re-cuts the MagicaVoxel file inside it into rigged body parts; re-run the tool after any change there. |
| `Little_People_in_Voxel.zip` | — | Superseded v1 of the above, kept only for reference. |

Everything else the game uses is either generated (`tools/`,
`tests/import_structures.gd`) or committed directly.
