class_name Weapons
## The weapon registry. Each entry is self-contained: to add or remove a
## weapon, edit this table and (if it changes terrain) its case in
## WorldNode.sv_shot / OrbView impact handling. Ids are wire format.

## Order here IS the order of the Tools tab. Shooters together, then the
## movement kit, then the three team-colour markers, then wings.
const WEAPONS := [
	{"id": 13, "name": "Sword", "color": Color("dfe4ea"), "cooldown": 0.4, "speed": 1.0,
		"blurb": "Trusty melee: swing at enemies and soft blocks up close"},
	{"id": 0, "name": "Little Shooter", "color": Color("ffe08a"), "cooldown": 0.09, "speed": 62.0,
		"blurb": "Rapid pellets: break soft blocks, light TNT from afar"},
	{"id": 1, "name": "Medium Shooter", "color": Color("ff7a3d"), "cooldown": 0.35, "speed": 34.0,
		"blurb": "Quick-fire explosions. Steel only chips on a direct hit"},
	{"id": 15, "name": "Big Shooter", "color": Color("d63d2e"), "cooldown": 2.0, "speed": 30.0,
		"blurb": "One shot every two seconds - but the boom is ENORMOUS"},
	{"id": 9, "name": "Napalm Rocket", "color": Color("f2e04a"), "cooldown": 0.7, "speed": 40.0,
		"blurb": "Mid-size blast that leaves quick-burning fire"},
	{"id": 2, "name": "Grapple", "color": Color("c9b3ff"), "cooldown": 0.9, "speed": 70.0,
		"blurb": "Hit a wall, get zipped to it. Great escapes"},
	{"id": 12, "name": "Digger", "color": Color("b5975f"), "cooldown": 1.2, "speed": 44.0,
		"blurb": "Drills a 3x3 tunnel 15 blocks through anything soft"},
	{"id": 14, "name": "Flare Gun", "color": Color("ff8ac2"), "cooldown": 3.0, "speed": 26.0,
		"blurb": "A star in YOUR TEAM'S colour, floating down over the field"},
	{"id": 11, "name": "Wings", "color": Color("eceff4"), "cooldown": 9.0, "speed": 1.0,
		"blurb": "Hold to glide from high places - but you can't shoot while soaring"},
	{"id": 8, "name": "Paint Bomb", "color": Color("b07df0"), "cooldown": 0.9, "speed": 36.0,
		"blurb": "Splats the landscape into random wool colors"},
	{"id": 18, "name": "Paint Sprayer", "color": Color("60d394"), "cooldown": 0.12, "speed": 46.0,
		"blurb": "Paints ONE block in YOUR TEAM'S colour - draw, mark, sign your work"},
	{"id": 19, "name": "Smoke Bomb", "color": Color("9aa6c4"), "cooldown": 4.0, "speed": 32.0,
		"blurb": "One team-coloured marker at a time: THAT is where we're going"},
	{"id": 17, "name": "Dragon Fire", "color": Color("ff7a1a"), "cooldown": 0.45, "speed": 44.0,
		"blurb": "Breathed from dragonback: big orange booms", "hidden": true},
	{"id": 3, "name": "Freeze Ray", "color": Color("aef7f0"), "cooldown": 0.8, "speed": 44.0,
		"blurb": "Turns water to ice and freezes Grumps solid", "hidden": true},
	{"id": 4, "name": "Block Sucker", "color": Color("62a851"), "cooldown": 0.5, "speed": 44.0,
		"blurb": "Vacuums the hit block into your next slot", "hidden": true},
	{"id": 10, "name": "Grump Whistle", "color": Color("8a5fd0"), "cooldown": 2.0, "speed": 30.0,
		"blurb": "Summons a wild Grump right there", "hidden": true},
	# Retired, ids left burned so nothing reuses them on the wire:
	#   5  Bridge Gun    6  Party Popper    7  Whirl Wand
	# None of them were any use in a game.
]

## What a player starts a battle holding. Everything else is loot.
## Sword to fight with, and all three TEAM-COLOUR markers: a flare to
## light a spot, a sprayer to paint one, smoke to point at one.
const STARTING_KIT := [13, 14, 18, 19]

static func count() -> int:
	return WEAPONS.size()

static func visible_ids() -> Array:
	var out: Array = []
	for w in WEAPONS:
		if not w.get("hidden", false):
			out.append(int(w.id))
	return out

static var _by_id: Dictionary = {}

static func spec(id: int) -> Dictionary:
	if _by_id.is_empty():
		for w in WEAPONS:
			_by_id[int(w.id)] = w
	return _by_id.get(id, WEAPONS[0])
