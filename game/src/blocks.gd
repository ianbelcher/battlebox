class_name Blocks
## The block palette. Every block is a flat-colored voxel (vertex colors, no
## textures) — the look comes from per-face shading, baked ambient occlusion,
## a per-position color jitter and the Forward+ lighting on top.

enum {
	AIR = 0,
	GRASS = 1,
	DIRT = 2,
	STONE = 3,
	SAND = 4,
	WATER = 5,
	LOG = 6,
	LEAVES = 7,
	PLANKS = 8,
	COBBLE = 9,
	SNOW = 10,
	FLOWER_RED = 11,
	FLOWER_YELLOW = 12,
	FLOWER_PINK = 13,
	TALL_GRASS = 14,
	PUMPKIN = 15,
	MUSHROOM = 16,
	LANTERN = 17,
	CAMPFIRE = 18,
	SAPLING = 19,
	BRICK = 20,
	GLASS = 21,
	WOOL_RED = 22,
	WOOL_ORANGE = 23,
	WOOL_YELLOW = 24,
	WOOL_GREEN = 25,
	WOOL_BLUE = 26,
	WOOL_PURPLE = 27,
	WOOL_WHITE = 28,
	WOOL_BLACK = 29,
	ICE = 30,
	SHELL = 31,
	BERRY_BUSH = 32,
	PATH = 33,
	BEDROCK = 34,
	MARBLE = 35,
	SLATE = 36,
	SANDSTONE = 37,
	BIRCH_PLANKS = 38,
	DARK_PLANKS = 39,
	CHERRY_PLANKS = 40,
	MOSSY_COBBLE = 41,
	GOLD = 42,
	DIAMOND = 43,
	GLOWSTONE = 44,
	CRYSTAL_PINK = 45,
	CRYSTAL_BLUE = 46,
	CRYSTAL_GREEN = 47,
	LAVA = 48,
	WOOL_PINK = 49,
	WOOL_TEAL = 50,
	WOOL_BROWN = 51,
	BOOM = 52,
	FIREWORK = 53,
	BOUNCY = 54,
	LAUNCHER = 55,
	NOTE = 56,
	SPONGE = 57,
	TELEPORT = 58,
	CONFETTI = 59,
	MAX_BLOCK = 60,
}

## Per-block info, indexed by block id:
##   color: base albedo
##   top: optional distinct top-face color (grass, path, pumpkin lid...)
##   solid: players collide with it
##   opaque: hides neighboring faces (false = translucent or plant)
##   cross: rendered as two crossed quads instead of a cube
##   translucent: rendered in the see-through surface (water/glass/ice)
##   sway: vertex wind animation strength (plants, leaves)
##   emit: emissive energy (lantern glow, campfire, berries pop slightly)
##   light: spawns a real OmniLight3D (energy) — the Forward+ showcase
##   collect: digging it counts as a treasure
##   unbreakable: bedrock
const INFO := {
	AIR: {"name": "Air", "color": Color(0, 0, 0, 0), "solid": false, "opaque": false},
	GRASS: {"name": "Grass", "color": Color("6c9a3f"), "top": Color("7fb84e"), "solid": true, "opaque": true},
	DIRT: {"name": "Dirt", "color": Color("8a6242"), "solid": true, "opaque": true},
	STONE: {"name": "Stone", "color": Color("8d9296"), "solid": true, "opaque": true},
	SAND: {"name": "Sand", "color": Color("e6d29a"), "solid": true, "opaque": true},
	WATER: {"name": "Water", "color": Color(0.18, 0.45, 0.75, 0.62), "solid": false, "opaque": false, "translucent": true},
	LOG: {"name": "Log", "color": Color("6e523a"), "top": Color("a8845f"), "solid": true, "opaque": true},
	LEAVES: {"name": "Leaves", "color": Color("4f8a3d"), "solid": true, "opaque": true, "sway": 0.35},
	PLANKS: {"name": "Planks", "color": Color("b08d5e"), "solid": true, "opaque": true},
	COBBLE: {"name": "Cobble", "color": Color("7a7d80"), "solid": true, "opaque": true},
	SNOW: {"name": "Snow", "color": Color("eef3f6"), "solid": true, "opaque": true},
	FLOWER_RED: {"name": "Poppy", "color": Color("e2574c"), "solid": false, "opaque": false, "cross": true, "sway": 1.0, "collect": true},
	FLOWER_YELLOW: {"name": "Buttercup", "color": Color("f5c542"), "solid": false, "opaque": false, "cross": true, "sway": 1.0, "collect": true},
	FLOWER_PINK: {"name": "Blossom", "color": Color("ef8fc0"), "solid": false, "opaque": false, "cross": true, "sway": 1.0, "collect": true},
	TALL_GRASS: {"name": "Wild Grass", "color": Color("5d8f43"), "solid": false, "opaque": false, "cross": true, "sway": 1.0},
	PUMPKIN: {"name": "Pumpkin", "color": Color("dd7d2a"), "top": Color("b8641f"), "solid": true, "opaque": true},
	MUSHROOM: {"name": "Mushroom", "color": Color("d95f4b"), "solid": false, "opaque": false, "cross": true, "sway": 0.4, "collect": true},
	LANTERN: {"name": "Lantern", "color": Color("ffd98a"), "solid": true, "opaque": false, "emit": 2.2, "light": 3.2},
	CAMPFIRE: {"name": "Campfire", "color": Color("ff9d45"), "solid": false, "opaque": false, "emit": 2.6, "light": 4.2},
	SAPLING: {"name": "Sapling", "color": Color("70a94e"), "solid": false, "opaque": false, "cross": true, "sway": 0.8},
	BRICK: {"name": "Brick", "color": Color("aa5d49"), "solid": true, "opaque": true},
	GLASS: {"name": "Glass", "color": Color(0.75, 0.87, 0.94, 0.3), "solid": true, "opaque": false, "translucent": true},
	WOOL_RED: {"name": "Red Wool", "color": Color("cc4b4b"), "solid": true, "opaque": true},
	WOOL_ORANGE: {"name": "Orange Wool", "color": Color("e08c3a"), "solid": true, "opaque": true},
	WOOL_YELLOW: {"name": "Yellow Wool", "color": Color("e8c94a"), "solid": true, "opaque": true},
	WOOL_GREEN: {"name": "Green Wool", "color": Color("62a851"), "solid": true, "opaque": true},
	WOOL_BLUE: {"name": "Blue Wool", "color": Color("4a76c9"), "solid": true, "opaque": true},
	WOOL_PURPLE: {"name": "Purple Wool", "color": Color("9a5fc2"), "solid": true, "opaque": true},
	WOOL_WHITE: {"name": "White Wool", "color": Color("e9e6df"), "solid": true, "opaque": true},
	WOOL_BLACK: {"name": "Black Wool", "color": Color("3a3d45"), "solid": true, "opaque": true},
	ICE: {"name": "Ice", "color": Color(0.68, 0.82, 0.94, 0.75), "solid": true, "opaque": false, "translucent": true},
	SHELL: {"name": "Seashell", "color": Color("f2e0d0"), "solid": false, "opaque": false, "cross": true, "collect": true},
	BERRY_BUSH: {"name": "Berry Bush", "color": Color("3f7a38"), "solid": false, "opaque": false, "cross": true, "sway": 0.5, "emit": 0.35, "collect": true},
	PATH: {"name": "Path", "color": Color("9c7f52"), "top": Color("b5975f"), "solid": true, "opaque": true},
	BEDROCK: {"name": "Bedrock", "color": Color("4c4c52"), "solid": true, "opaque": true, "unbreakable": true},
	# --- Building families ---
	MARBLE: {"name": "Marble", "color": Color("e8e6e0"), "solid": true, "opaque": true},
	SLATE: {"name": "Slate", "color": Color("4a5568"), "solid": true, "opaque": true},
	SANDSTONE: {"name": "Sandstone", "color": Color("d9c78f"), "top": Color("e3d4a3"), "solid": true, "opaque": true},
	BIRCH_PLANKS: {"name": "Birch Planks", "color": Color("d6c396"), "solid": true, "opaque": true},
	DARK_PLANKS: {"name": "Dark Planks", "color": Color("5d4430"), "solid": true, "opaque": true},
	CHERRY_PLANKS: {"name": "Cherry Planks", "color": Color("d4a0a8"), "solid": true, "opaque": true},
	MOSSY_COBBLE: {"name": "Mossy Cobble", "color": Color("6d7d68"), "solid": true, "opaque": true},
	GOLD: {"name": "Gold", "color": Color("f2c744"), "solid": true, "opaque": true, "emit": 0.25},
	DIAMOND: {"name": "Diamond", "color": Color("7de8e0"), "solid": true, "opaque": true, "emit": 0.25},
	WOOL_PINK: {"name": "Pink Wool", "color": Color("ef9fc8"), "solid": true, "opaque": true},
	WOOL_TEAL: {"name": "Teal Wool", "color": Color("3aa8a0"), "solid": true, "opaque": true},
	WOOL_BROWN: {"name": "Brown Wool", "color": Color("7a5b40"), "solid": true, "opaque": true},
	# --- Glow set ---
	GLOWSTONE: {"name": "Glowstone", "color": Color("ffe08a"), "solid": true, "opaque": false, "emit": 2.4, "light": 3.6},
	CRYSTAL_PINK: {"name": "Pink Crystal", "color": Color(0.95, 0.55, 0.8, 0.65), "solid": true, "opaque": false, "translucent": true, "emit": 1.5, "light": 2.0},
	CRYSTAL_BLUE: {"name": "Blue Crystal", "color": Color(0.45, 0.7, 0.98, 0.65), "solid": true, "opaque": false, "translucent": true, "emit": 1.5, "light": 2.0},
	CRYSTAL_GREEN: {"name": "Green Crystal", "color": Color(0.5, 0.95, 0.6, 0.65), "solid": true, "opaque": false, "translucent": true, "emit": 1.5, "light": 2.0},
	LAVA: {"name": "Glow Goo", "color": Color(1.0, 0.48, 0.14, 0.85), "solid": false, "opaque": false, "translucent": true, "emit": 1.7, "light": 3.0},
	# --- Fun machines ---
	BOOM: {"name": "Boom Block", "color": Color("d63d2e"), "top": Color("8f2318"), "solid": true, "opaque": true, "emit": 0.35},
	FIREWORK: {"name": "Firework", "color": Color("c94fd4"), "top": Color("f2e04a"), "solid": true, "opaque": true, "emit": 0.3},
	BOUNCY: {"name": "Bouncy Block", "color": Color(0.5, 0.88, 0.45, 0.7), "solid": true, "opaque": false, "translucent": true, "emit": 0.2},
	LAUNCHER: {"name": "Launch Pad", "color": Color("8a5fe8"), "top": Color("c9b3ff"), "solid": true, "opaque": true, "emit": 0.4},
	NOTE: {"name": "Music Block", "color": Color("e0a63d"), "top": Color("6d4a26"), "solid": true, "opaque": true},
	SPONGE: {"name": "Sponge", "color": Color("d8c94a"), "solid": true, "opaque": true},
	TELEPORT: {"name": "Warp Stone", "color": Color("4de0d4"), "top": Color("aef7f0"), "solid": true, "opaque": true, "emit": 0.9, "light": 1.6},
	CONFETTI: {"name": "Party Popper", "color": Color("f2e8f7"), "top": Color("ef9fc8"), "solid": true, "opaque": true, "emit": 0.3},
}

## What the place-hotbar offers, in order: build stuff first, glow stuff,
## then the fun machines. Everything is infinite (creative style) — the cozy
## loop is building, not resource grinding.
const HOTBAR: Array[int] = [
	PLANKS, BIRCH_PLANKS, DARK_PLANKS, CHERRY_PLANKS, LOG,
	COBBLE, MOSSY_COBBLE, STONE, MARBLE, SLATE, BRICK, SANDSTONE, SAND,
	GLASS, ICE, SNOW, GOLD, DIAMOND,
	WOOL_RED, WOOL_ORANGE, WOOL_YELLOW, WOOL_GREEN, WOOL_TEAL, WOOL_BLUE,
	WOOL_PURPLE, WOOL_PINK, WOOL_BROWN, WOOL_WHITE, WOOL_BLACK,
	LANTERN, CAMPFIRE, GLOWSTONE, CRYSTAL_PINK, CRYSTAL_BLUE, CRYSTAL_GREEN, LAVA,
	BOOM, FIREWORK, BOUNCY, LAUNCHER, NOTE, SPONGE, TELEPORT, CONFETTI,
	FLOWER_RED, FLOWER_YELLOW, SAPLING, PUMPKIN,
]

static func info(id: int) -> Dictionary:
	return INFO.get(id, INFO[AIR])

static func color_of(id: int) -> Color:
	var i: Dictionary = info(id)
	var c: Color = i.color
	return c

static func top_color_of(id: int) -> Color:
	var i: Dictionary = info(id)
	return i.get("top", i.color)

static func is_solid(id: int) -> bool:
	return bool(info(id).get("solid", false))

static func is_opaque(id: int) -> bool:
	return bool(info(id).get("opaque", false))

static func is_cross(id: int) -> bool:
	return bool(info(id).get("cross", false))

static func is_translucent(id: int) -> bool:
	return bool(info(id).get("translucent", false))

## Swimmable stuff (water and glow goo).
static func is_liquid(id: int) -> bool:
	return id == WATER or id == LAVA

static func is_collectible(id: int) -> bool:
	return bool(info(id).get("collect", false))

static func is_breakable(id: int) -> bool:
	if id == AIR:
		return false
	return not bool(info(id).get("unbreakable", false))

static func sway_of(id: int) -> float:
	return float(info(id).get("sway", 0.0))

static func emit_of(id: int) -> float:
	return float(info(id).get("emit", 0.0))

static func light_of(id: int) -> float:
	return float(info(id).get("light", 0.0))

static func display_name(id: int) -> String:
	return str(info(id).get("name", "?"))
