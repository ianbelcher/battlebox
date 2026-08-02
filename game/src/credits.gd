class_name Credits
## Who made the art we didn't. Shown on the world menu's Credits page.
##
## ADD AN ENTRY whenever a new pack or build goes in — especially for
## imported Minecraft builds, where each one belongs to the person who
## built it. "license" should be the actual licence name, and "url" the
## page it came from, so anyone can check our working.

const ENTRIES := [
	{"group": "Art packs", "name": "Kenney Game Assets",
		"by": "Kenney (kenney.nl)", "license": "CC0",
		"what": "Blocky Characters, Cube Pets, Blaster Kit, Nature Kit, sounds"},
	{"group": "Art packs", "name": "Voxel Dinosaurs Pack",
		"by": "pack author", "license": "as purchased",
		"what": "10 animated dinosaurs"},
	{"group": "Art packs", "name": "Farm / Forest / Jungle Animal Packs",
		"by": "pack author", "license": "as purchased",
		"what": "29 animated animals"},
	{"group": "Art packs", "name": "Little People in Voxel",
		"by": "pack author", "license": "as purchased",
		"what": "30 playable characters"},
	{"group": "Art packs", "name": "Boss dragon",
		"by": "Meshy (meshy.ai)", "license": "CC0",
		"what": "The rideable dragon"},
	{"group": "Engine", "name": "Godot Engine",
		"by": "Juan Linietsky, Ariel Manzur and contributors",
		"license": "MIT", "what": "The engine this runs on"},
]

## Imported Minecraft builds get appended here by the kit importer, one
## entry per build, so each builder is named individually.
const BUILDS: Array = []

static func groups() -> Array:
	var seen: Array = []
	for entry: Dictionary in ENTRIES:
		if not seen.has(str(entry.group)):
			seen.append(str(entry.group))
	return seen

static func in_group(group: String) -> Array:
	var out: Array = []
	for entry: Dictionary in ENTRIES:
		if str(entry.group) == group:
			out.append(entry)
	return out
