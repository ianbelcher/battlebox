class_name Creatures
## ==================================================================
## THE CREATURE REGISTRY — the one file to touch when adding, tuning
## or retiring a creature.
##
## TO ADD ONE:    drop its model under assets/models/, then add an
##                entry below with a NEW id. Ids are the network wire
##                format, so never renumber the existing ones.
## TO RETIRE ONE: delete its entry. Leave the model file alone — it
##                simply stops being spawned.
## TO TUNE ONE:   change "height" (in BLOCKS — the model is scaled to
##                match, whatever units it was made in), "speed",
##                "weight" (spawn chance) or its animation names.
##
## Ids 0-11 are the original hand-built critters: they have no "model"
## so CritterView draws them from code as before, but they still live
## here so speeds and spawn rules are all in one place.
## ==================================================================

## How a creature gets around.
const GROUND := 0   # walks the surface, falls when the ground goes
const FLIER := 1    # soars above the terrain
const SWIMMER := 2  # stays in the water

## Where it is allowed to appear.
const LAND := "land"
const WATER := "water"
const SAND := "sand"
const SNOW := "snow"
const ANY := "any"

## Standard clip names in the voxel dinosaur pack, so entries stay short.
const DINO_ANIMS := {"idle": "Idle 01", "walk": "Walk 01", "run": "Run 01",
	"hurt": "Get Hit 01", "die": "Death 01", "eat": "Eat 01"}

## Standard clip names in the Kenney Cube Pets pack.
const PET_ANIMS := {"idle": "idle", "walk": "walk", "run": "run",
	"eat": "eat", "cheer": "dance"}

const DEFS := {
	# ---------- dinosaurs (animated voxel pack) ----------
	12: {"name": "T-rex", "model": "res://assets/models/dinos/trex.gltf",
		"height": 4.4, "move": GROUND, "speed": 2.8, "habitat": LAND,
		"weight": 0.05, "anims": DINO_ANIMS},
	13: {"name": "Velociraptor", "model": "res://assets/models/dinos/velociraptor.gltf",
		"height": 1.9, "move": GROUND, "speed": 3.4, "habitat": LAND,
		"weight": 0.10, "anims": DINO_ANIMS},
	14: {"name": "Triceratops", "model": "res://assets/models/dinos/triceratops.gltf",
		"height": 3.0, "move": GROUND, "speed": 1.8, "habitat": LAND,
		"weight": 0.09, "anims": DINO_ANIMS},
	15: {"name": "Stegosaurus", "model": "res://assets/models/dinos/stegosaurus.gltf",
		"height": 3.4, "move": GROUND, "speed": 1.5, "habitat": LAND,
		"weight": 0.09, "anims": DINO_ANIMS},
	16: {"name": "Ankylosaurus", "model": "res://assets/models/dinos/ankylosaurus.gltf",
		"height": 2.2, "move": GROUND, "speed": 1.4, "habitat": LAND,
		"weight": 0.08, "anims": DINO_ANIMS},
	17: {"name": "Brachiosaurus", "model": "res://assets/models/dinos/brachiosaurus.gltf",
		"height": 7.5, "move": GROUND, "speed": 1.3, "habitat": LAND,
		"weight": 0.06, "anims": DINO_ANIMS},
	18: {"name": "Carnotaurus", "model": "res://assets/models/dinos/carnotaurus.gltf",
		"height": 3.4, "move": GROUND, "speed": 2.9, "habitat": LAND,
		"weight": 0.06, "anims": DINO_ANIMS},
	19: {"name": "Pachycephalosaurus",
		"model": "res://assets/models/dinos/pachycephalosaurus.gltf",
		"height": 2.4, "move": GROUND, "speed": 2.2, "habitat": LAND,
		"weight": 0.08, "anims": DINO_ANIMS},
	20: {"name": "Pterodactyl", "model": "res://assets/models/dinos/pterodactyl.gltf",
		"height": 1.8, "move": FLIER, "speed": 3.2, "habitat": ANY,
		"weight": 0.07, "fly_height": 6.0,
		"anims": {"idle": "Glide 01", "walk": "Flying 01", "run": "Flying 01",
			"die": "Death 01"}},
	21: {"name": "Plesiosaur", "model": "res://assets/models/dinos/plesiosaur.gltf",
		"height": 2.6, "move": SWIMMER, "speed": 2.4, "habitat": WATER,
		"weight": 0.30,
		"anims": {"idle": "Idle 01", "walk": "Swim 01", "run": "Quick Swim 01",
			"die": "Death 01"}},

	# ---------- the boss dragon (its own model + flight logic) ----------
	11: {"name": "Dragon", "model": "res://assets/models/dragon.glb",
		"height": 6.0, "move": FLIER, "speed": 2.4, "habitat": LAND,
		"weight": 0.0, "unique": true, "rideable": true, "fly_height": 8.0},

	# ---------- everyday animals (Kenney Cube Pets, animated) ----------
	# weight 0 = the classic critter table places these, not the roll.
	0: {"name": "Cow", "model": "res://assets/models/pets/animal-cow.glb",
		"height": 1.15, "move": GROUND, "speed": 1.2, "habitat": LAND,
		"weight": 0.0, "anims": PET_ANIMS},
	1: {"name": "Bunny", "model": "res://assets/models/pets/animal-bunny.glb",
		"height": 0.75, "move": GROUND, "speed": 2.2, "habitat": LAND,
		"weight": 0.0, "anims": PET_ANIMS},
	2: {"name": "Bee", "model": "res://assets/models/pets/animal-bee.glb",
		"height": 0.6, "move": GROUND, "speed": 1.6, "habitat": LAND,
		"weight": 0.0, "anims": PET_ANIMS, "hover": 0.8},
	3: {"name": "Firefly", "move": GROUND, "speed": 0.9, "habitat": LAND,
		"weight": 0.0},  # no model: drawn in code as a glowing mote
	4: {"name": "Beaver", "model": "res://assets/models/pets/animal-beaver.glb",
		"height": 0.8, "move": SWIMMER, "speed": 1.1, "habitat": WATER,
		"weight": 0.0, "anims": PET_ANIMS},
	5: {"name": "Chick", "model": "res://assets/models/pets/animal-chick.glb",
		"height": 0.6, "move": GROUND, "speed": 1.4, "habitat": LAND,
		"weight": 0.0, "anims": PET_ANIMS},
	6: {"name": "Crab", "model": "res://assets/models/pets/animal-crab.glb",
		"height": 0.5, "move": GROUND, "speed": 0.8, "habitat": SAND,
		"weight": 0.0, "anims": PET_ANIMS},
	7: {"name": "Caterpillar", "model": "res://assets/models/pets/animal-caterpillar.glb",
		"height": 0.5, "move": GROUND, "speed": 1.3, "habitat": LAND,
		"weight": 0.0, "anims": PET_ANIMS},
	8: {"name": "Deer", "model": "res://assets/models/pets/animal-deer.glb",
		"height": 1.2, "move": GROUND, "speed": 1.8, "habitat": LAND,
		"weight": 0.0, "anims": PET_ANIMS},
	9: {"name": "Penguin", "model": "res://assets/models/pets/animal-penguin.glb",
		"height": 0.8, "move": GROUND, "speed": 0.9, "habitat": SNOW,
		"weight": 0.0, "anims": PET_ANIMS},
	10: {"name": "Parrot", "model": "res://assets/models/pets/animal-parrot.glb",
		"height": 0.7, "move": FLIER, "speed": 3.0, "habitat": ANY,
		"weight": 0.0, "anims": PET_ANIMS, "fly_height": 4.0},
}

static func has(kind: int) -> bool:
	return DEFS.has(kind)

static func def(kind: int) -> Dictionary:
	return DEFS.get(kind, {})

static func model_of(kind: int) -> String:
	return str(DEFS.get(kind, {}).get("model", ""))

static func speed_of(kind: int) -> float:
	return float(DEFS.get(kind, {}).get("speed", 1.2))

static func move_of(kind: int) -> int:
	return int(DEFS.get(kind, {}).get("move", GROUND))

static func anim_of(kind: int, role: String) -> String:
	return str(DEFS.get(kind, {}).get("anims", {}).get(role, ""))

static func fly_height(kind: int) -> float:
	return float(DEFS.get(kind, {}).get("fly_height", 0.0))

## Weighted pick among registry creatures that suit this ground. Returns
## -1 when nothing rolls, and the caller falls back to the classic
## critter table — so dinosaurs join the world without displacing it.
static func roll(habitat: String) -> int:
	var total := 0.0
	for kind: int in DEFS:
		var entry: Dictionary = DEFS[kind]
		var where := str(entry.get("habitat", LAND))
		if float(entry.get("weight", 0.0)) <= 0.0:
			continue
		if where != habitat and where != ANY:
			continue
		total += float(entry.weight)
	if total <= 0.0:
		return -1
	var pick := randf()
	if pick > total:
		return -1  # most rolls leave room for the ordinary animals
	var walked := 0.0
	for kind: int in DEFS:
		var entry: Dictionary = DEFS[kind]
		var where := str(entry.get("habitat", LAND))
		if float(entry.get("weight", 0.0)) <= 0.0:
			continue
		if where != habitat and where != ANY:
			continue
		walked += float(entry.weight)
		if pick <= walked:
			return kind
	return -1
