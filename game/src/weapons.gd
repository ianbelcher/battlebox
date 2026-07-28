class_name Weapons
## The weapon registry. Each entry is self-contained: to add or remove a
## weapon, edit this table and (if it changes terrain) its case in
## WorldNode.sv_shot / OrbView impact handling. Ids are wire format.

const WEAPONS := [
	{"id": 0, "name": "Blaster", "color": Color("ffe08a"), "cooldown": 0.13, "speed": 44.0,
		"blurb": "Rapid pellets: break soft blocks, light TNT from afar"},
	{"id": 1, "name": "Bazooka", "color": Color("ff7a3d"), "cooldown": 1.1, "speed": 34.0,
		"blurb": "Big explosions. Steel only chips on a direct hit"},
	{"id": 2, "name": "Grapple", "color": Color("c9b3ff"), "cooldown": 0.9, "speed": 50.0,
		"blurb": "Hit a wall, get zipped to it. Great escapes"},
	{"id": 3, "name": "Freeze Ray", "color": Color("aef7f0"), "cooldown": 0.8, "speed": 44.0,
		"blurb": "Turns water to ice and freezes Grumps solid", "hidden": true},
	{"id": 4, "name": "Block Sucker", "color": Color("62a851"), "cooldown": 0.5, "speed": 44.0,
		"blurb": "Vacuums the hit block into your next slot", "hidden": true},
	{"id": 5, "name": "Bridge Gun", "color": Color("d6c396"), "cooldown": 0.8, "speed": 40.0,
		"blurb": "Shoots a plank walkway toward where it lands"},
	{"id": 6, "name": "Party Popper", "color": Color("ef9fc8"), "cooldown": 1.0, "speed": 36.0,
		"blurb": "Confetti blast: harmlessly flings everyone nearby"},
	{"id": 7, "name": "Whirl Wand", "color": Color("3ad4c2"), "cooldown": 1.2, "speed": 36.0,
		"blurb": "A gust that hurls friends skyward and scatters Grumps"},
	{"id": 8, "name": "Paint Bomb", "color": Color("b07df0"), "cooldown": 0.9, "speed": 36.0,
		"blurb": "Splats the landscape into random wool colors"},
	{"id": 9, "name": "Napalm Rocket", "color": Color("f2e04a"), "cooldown": 0.7, "speed": 40.0,
		"blurb": "Mid-size blast that leaves quick-burning fire"},
	{"id": 14, "name": "Flare Gun", "color": Color("ff8ac2"), "cooldown": 3.0, "speed": 26.0,
		"blurb": "Fires a bright star that floats down and lights the night"},
	{"id": 13, "name": "Sword", "color": Color("dfe4ea"), "cooldown": 0.4, "speed": 1.0,
		"blurb": "Trusty melee: swing at enemies and soft blocks up close"},
	{"id": 12, "name": "Digger", "color": Color("b5975f"), "cooldown": 1.2, "speed": 44.0,
		"blurb": "Drills a 3x3 tunnel 15 blocks through anything soft"},
	{"id": 11, "name": "Wings", "color": Color("eceff4"), "cooldown": 9.0, "speed": 1.0,
		"blurb": "Hold to glide from high places - but you can't shoot while soaring"},
	{"id": 10, "name": "Grump Whistle", "color": Color("8a5fd0"), "cooldown": 2.0, "speed": 30.0,
		"blurb": "Summons a wild Grump right there", "hidden": true},
]

static func count() -> int:
	return WEAPONS.size()

static func visible_ids() -> Array:
	var out: Array = []
	for w in WEAPONS:
		if not w.get("hidden", false):
			out.append(int(w.id))
	return out

static func spec(id: int) -> Dictionary:
	return WEAPONS[clampi(id, 0, WEAPONS.size() - 1)]
