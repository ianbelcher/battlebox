class_name AvatarFactory
## Builds the character model: a chunky, friendly mini-figure (think toy
## figure) with head, torso, swinging arms and legs. A style dictionary
## {body, face, hair, hat, shirt, pants, shoes} picks every part; each is
## cycled from the HUD swatches and remembered per device.
##
## Limb pivots are named LegL/LegR/ArmL/ArmR so the player animation can
## swing them while walking.

const ATTRS: Array[String] = ["body", "face", "hair", "hat", "shirt", "pants", "shoes", "gear"]
const GEAR_COUNT := 8

const SKIN_COLORS: Array[Color] = [
	Color("f5cfa8"), Color("e0ac7e"), Color("a9714b"), Color("6f4a2f"),
	Color("9fe2c5"), Color("c9a9f5"), Color("ffd97a"),
]
const FACE_COUNT := 8
## Hair entries: kind + color baked together so one row cycles both.
const HAIRS: Array = [
	{"kind": "none", "c": Color.BLACK},
	{"kind": "tuft", "c": Color("6b4a2f")},
	{"kind": "short", "c": Color("6b4a2f")},
	{"kind": "short", "c": Color("f2d16b")},
	{"kind": "spiky", "c": Color("2a2a33")},
	{"kind": "spiky", "c": Color("d4553a")},
	{"kind": "long", "c": Color("6b4a2f")},
	{"kind": "long", "c": Color("f2d16b")},
	{"kind": "ponytail", "c": Color("2a2a33")},
	{"kind": "afro", "c": Color("3d2a1c")},
	{"kind": "mohawk", "c": Color("51c979")},
	{"kind": "curls", "c": Color("ff9ff3")},
]
const HAT_COUNT := 13
## Shirt entries: base color + accent + pattern overlay.
const SHIRTS: Array = [
	{"c": Color("ff6b6b"), "a": Color("ff6b6b"), "p": "plain"},
	{"c": Color("4a9df8"), "a": Color("4a9df8"), "p": "plain"},
	{"c": Color("51c979"), "a": Color("51c979"), "p": "plain"},
	{"c": Color("ffd166"), "a": Color("ffd166"), "p": "plain"},
	{"c": Color("b07df0"), "a": Color("b07df0"), "p": "plain"},
	{"c": Color("3ad4c2"), "a": Color("3ad4c2"), "p": "plain"},
	{"c": Color("ff9f68"), "a": Color("ff9f68"), "p": "plain"},
	{"c": Color("e8ecf4"), "a": Color("ff6b6b"), "p": "stripe"},
	{"c": Color("2a3550"), "a": Color("ffd166"), "p": "stripe"},
	{"c": Color("51c979"), "a": Color("e8ecf4"), "p": "stripe"},
	{"c": Color("4a9df8"), "a": Color("e8ecf4"), "p": "band"},
	{"c": Color("2a2a33"), "a": Color("ff6b6b"), "p": "band"},
]
const PANTS_COLORS: Array[Color] = [
	Color("3a4a6b"), Color("2a2a33"), Color("6b4a2f"), Color("4a6b3a"),
	Color("8a3a4a"), Color("e8ecf4"), Color("d4a13a"), Color("5a3a8a"),
]
const SHOE_COLORS: Array[Color] = [
	Color("2a2a33"), Color("e8ecf4"), Color("d4553a"), Color("4a9df8"),
	Color("6b4a2f"), Color("ffd166"), Color("51c979"), Color("ff9ff3"),
]

static func random_style() -> Dictionary:
	var all := characters()
	return {"who": all[randi() % all.size()]}

## Everyone is a Kenney character now. Legacy editor styles map to a
## stable pick (hash of the old dict) so returning players keep one
## consistent look until they choose their own.
static func normalize_style(style) -> Dictionary:
	if not (style is Dictionary):
		return random_style()
	var all := characters()
	if style.has("who") and str(style.who) in all:
		return {"who": str(style.who)}
	return {"who": all[posmod(str(style).hash(), all.size())]}

static func skin_color(style: Dictionary) -> Color:
	return SKIN_COLORS[posmod(int(style.get("body", 0)), SKIN_COLORS.size())]

static func shirt_color(style: Dictionary) -> Color:
	return SHIRTS[posmod(int(style.get("shirt", 0)), SHIRTS.size())].c

static func material(color: Color, emissive := false) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.7
	if emissive:
		mat.emission_enabled = true
		mat.emission = color
		mat.emission_energy_multiplier = 0.8
	return mat

static func _box(size: Vector3, color: Color) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	instance.mesh = mesh
	instance.material_override = material(color)
	return instance

static func _sphere(radius: float, color: Color) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	instance.mesh = mesh
	instance.material_override = material(color)
	return instance

static func _cone(bottom: float, height: float, color: Color) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.02
	mesh.bottom_radius = bottom
	mesh.height = height
	instance.mesh = mesh
	instance.material_override = material(color)
	return instance

static func _cylinder(radius: float, height: float, color: Color) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	instance.mesh = mesh
	instance.material_override = material(color)
	return instance

## The character faces -Z. Total height ~1.5 (fits the 1.25 collision box
## with the head poking into the generous 2-block clearance).
## Kenney Blocky Characters (CC0): 18 ready-made kids to pick from.
const KENNEY_CHARS := ["a", "b", "c", "d", "e", "f", "g", "h", "i", "j",
	"k", "l", "m", "n", "o", "p", "q", "r"]

## Little People in Voxel (30 more). The pack ships one static mesh per
## character, so `tools/rig_people.py` re-cuts them from the MagicaVoxel
## source into five OBJs — body, arms, legs — that the procedural
## `_swing_limb` animation in player.gd drives like the legacy rig.
## Keys are "p0".."p29" so they can never collide with the Kenney letters.
const PEOPLE_COUNT := 30
## Node name -> file suffix. Body carries the head; the four limb pivots
## are named exactly what player.gd looks for.
const PEOPLE_PARTS := {
	"Body": "body", "ArmL": "arm-l", "ArmR": "arm-r",
	"LegL": "leg-l", "LegR": "leg-r",
}
## The parts are exported in voxel units, so ONE scale covers all 30 and
## they end up the same size as each other (and as the Kenney kids): the
## shared 25-voxel frame lands at ~1.55, hips at 0.43 and shoulders at
## 0.87 — near enough the legacy rig that held items line up.
const PERSON_SCALE := 0.062
## Every part's UVs index one 256x1 palette strip. Godot's OBJ importer
## quietly ignores the .mtl's map_Kd, so the material is built here — and
## shared, so all 30 characters draw with one texture.
static var _person_material: StandardMaterial3D

static func person_material() -> StandardMaterial3D:
	if _person_material == null:
		_person_material = StandardMaterial3D.new()
		_person_material.albedo_texture = load(
			"res://assets/models/people/people-palette.png")
		# Nearest, no mipmaps: neighbouring palette entries are unrelated
		# colours and must never blend into each other.
		_person_material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		_person_material.roughness = 0.85
	return _person_material

## Everything the character picker offers, in order.
static func characters() -> Array:
	var all: Array = KENNEY_CHARS.duplicate()
	for i in PEOPLE_COUNT:
		all.append("p%d" % i)
	return all

static func is_person(who: String) -> bool:
	return who.begins_with("p") and who.length() > 1 and who.substr(1).is_valid_int()

static func model_of(who: String) -> String:
	if is_person(who):
		return "res://assets/models/people/Character-%s-body.obj" % who.substr(1)
	return "res://assets/models/chars/character-%s.glb" % who

static func portrait_of(who: String) -> String:
	if is_person(who):
		return "res://assets/models/people/Character-%s.png" % who.substr(1)
	return "res://assets/ui/chars/character-%s.png" % who

static func build_character(style: Dictionary) -> Node3D:
	style = normalize_style(style)
	if style.has("who"):
		var who := str(style.who)
		if is_person(who):
			var person := _build_person(who)
			if person != null:
				person.set_meta("style", str(style))
				return person
		else:
			var res: Resource = load(model_of(who)) \
				if ResourceLoader.exists(model_of(who)) else null
			if res is PackedScene:
				var inst: Node3D = (res as PackedScene).instantiate()
				var root := Node3D.new()
				inst.scale = Vector3.ONE * 0.52
				inst.rotation_degrees = Vector3(0, 180, 0)
				root.add_child(inst)
				var ap := inst.find_child("AnimationPlayer", true, false) as AnimationPlayer
				if ap != null:
					for anim_name in ["idle", "walk", "sprint", "holding-right",
							"die", "sit"]:
						if ap.has_animation(anim_name):
							ap.get_animation(anim_name).loop_mode = Animation.LOOP_LINEAR
					ap.play("idle")
					root.set_meta("ap", ap)
				root.set_meta("style", str(style))
				return root
	return _build_legacy(style)

## Assembles a Little Person from its five part meshes. Each limb hangs
## under a pivot placed at the top centre of its own bounding box — the
## shoulder or the hip — which is exactly what _swing_limb rotates.
static func _build_person(who: String) -> Node3D:
	var index := who.substr(1)
	var root := Node3D.new()
	var built := 0
	for node_name in PEOPLE_PARTS:
		var path := "res://assets/models/people/Character-%s-%s.obj" % [
			index, PEOPLE_PARTS[node_name]]
		if not ResourceLoader.exists(path):
			continue
		var mesh := load(path) as Mesh
		if mesh == null:
			continue
		built += 1
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.material_override = person_material()
		mi.scale = Vector3.ONE * PERSON_SCALE
		if node_name == "Body":
			mi.name = node_name
			root.add_child(mi)
			continue
		var box := mesh.get_aabb()
		var joint := Vector3(box.get_center().x, box.end.y, box.get_center().z)
		var pivot := Node3D.new()
		pivot.name = node_name
		pivot.position = joint * PERSON_SCALE
		mi.position = -joint * PERSON_SCALE
		pivot.add_child(mi)
		if node_name == "ArmR":
			# Where a held tool sits: the far end of this arm, which is
			# shorter on some of the 30 than on the legacy rig.
			pivot.set_meta("hand",
				Vector3(0, (box.position.y - joint.y + 0.5) * PERSON_SCALE, -0.05))
		root.add_child(pivot)
	if built == 0:
		root.queue_free()
		return null
	return root

static func _build_legacy(style: Dictionary) -> Node3D:
	var skin := skin_color(style)
	var shirt_spec: Dictionary = SHIRTS[int(style.shirt)]
	var shirt: Color = shirt_spec.c
	var pants: Color = PANTS_COLORS[int(style.pants)]
	var shoes: Color = SHOE_COLORS[int(style.shoes)]
	var root := Node3D.new()

	for side in [-1.0, 1.0]:
		# Legs: pivot at the hip, mesh hanging below, shoes at the bottom.
		var leg_pivot := Node3D.new()
		leg_pivot.name = "LegL" if side < 0 else "LegR"
		leg_pivot.position = Vector3(side * 0.12, 0.42, 0)
		var leg := _box(Vector3(0.17, 0.42, 0.22), pants)
		leg.position = Vector3(0, -0.21, 0)
		leg_pivot.add_child(leg)
		var shoe := _box(Vector3(0.19, 0.11, 0.26), shoes)
		shoe.position = Vector3(0, -0.38, -0.02)
		leg_pivot.add_child(shoe)
		root.add_child(leg_pivot)
		# Arms: pivot at the shoulder, skin hands at the ends.
		var arm_pivot := Node3D.new()
		arm_pivot.name = "ArmL" if side < 0 else "ArmR"
		arm_pivot.position = Vector3(side * 0.33, 0.88, 0)
		var arm := _box(Vector3(0.15, 0.42, 0.18), shirt)
		arm.position = Vector3(0, -0.16, 0)
		arm_pivot.add_child(arm)
		var hand := _sphere(0.075, skin)
		hand.position = Vector3(0, -0.4, 0)
		arm_pivot.add_child(hand)
		root.add_child(arm_pivot)

	var torso := _box(Vector3(0.5, 0.5, 0.3), shirt)
	torso.position = Vector3(0, 0.67, 0)
	root.add_child(torso)
	match str(shirt_spec.p):
		"stripe":
			for dy in [-0.09, 0.09]:
				var stripe := _box(Vector3(0.52, 0.09, 0.32), shirt_spec.a)
				stripe.position = Vector3(0, 0.67 + dy, 0)
				root.add_child(stripe)
		"band":
			var band := _box(Vector3(0.14, 0.52, 0.32), shirt_spec.a)
			band.position = Vector3(0, 0.67, 0)
			root.add_child(band)

	var head := _box(Vector3(0.42, 0.4, 0.42), skin)
	head.name = "Head"
	head.position = Vector3(0, 1.13, 0)
	root.add_child(head)
	_attach_face(root, style, skin)
	_attach_hair(root, style)
	_attach_gear(root, style)
	attach_hat(root, style)
	root.set_meta("style", str(style))
	return root

## Eyes, mouth and extras vary by face type so siblings look different even
## in the same shirt.
static func _attach_face(root: Node3D, style: Dictionary, skin: Color) -> void:
	var face := posmod(int(style.get("face", 0)), FACE_COUNT)
	var eye_r := 0.065 if face == 7 else 0.055
	if face != 5:  # sunglasses replace the eyes entirely
		for side in [-1.0, 1.0]:
			var eye := _sphere(eye_r, Color.WHITE)
			eye.position = Vector3(side * 0.1, 1.17, -0.21)
			root.add_child(eye)
			var pupil := _sphere(0.028, Color(0.08, 0.08, 0.12))
			pupil.position = Vector3(side * 0.1, 1.17, -0.245)
			root.add_child(pupil)
	match face:
		0:  # Classic smile.
			var mouth := _box(Vector3(0.12, 0.03, 0.02), Color(0.45, 0.2, 0.18))
			mouth.position = Vector3(0, 1.03, -0.215)
			root.add_child(mouth)
		1:  # Big happy grin + rosy cheeks.
			var grin := _box(Vector3(0.2, 0.05, 0.02), Color(0.45, 0.2, 0.18))
			grin.position = Vector3(0, 1.03, -0.215)
			root.add_child(grin)
			for side in [-1.0, 1.0]:
				var cheek := _sphere(0.035, Color("ff9ff3"))
				cheek.position = Vector3(side * 0.155, 1.09, -0.21)
				root.add_child(cheek)
		2:  # Sleepy: heavy lids, tiny mouth.
			for side in [-1.0, 1.0]:
				var lid := _box(Vector3(0.13, 0.05, 0.03), skin.darkened(0.18))
				lid.position = Vector3(side * 0.1, 1.21, -0.225)
				root.add_child(lid)
			var yawn := _box(Vector3(0.06, 0.03, 0.02), Color(0.45, 0.2, 0.18))
			yawn.position = Vector3(0, 1.02, -0.215)
			root.add_child(yawn)
		3:  # Determined: angled brows.
			for side in [-1.0, 1.0]:
				var brow := _box(Vector3(0.13, 0.035, 0.03), Color(0.15, 0.12, 0.1))
				brow.position = Vector3(side * 0.1, 1.24, -0.22)
				brow.rotation_degrees = Vector3(0, 0, side * -16.0)
				root.add_child(brow)
			var mouth := _box(Vector3(0.1, 0.03, 0.02), Color(0.45, 0.2, 0.18))
			mouth.position = Vector3(0, 1.03, -0.215)
			root.add_child(mouth)
		4:  # Round glasses.
			for side in [-1.0, 1.0]:
				var rim := _box(Vector3(0.15, 0.14, 0.02), Color(0.12, 0.12, 0.16))
				rim.position = Vector3(side * 0.1, 1.17, -0.222)
				root.add_child(rim)
				var lens := _box(Vector3(0.11, 0.1, 0.015), Color(0.75, 0.85, 0.95))
				lens.position = Vector3(side * 0.1, 1.17, -0.232)
				root.add_child(lens)
			var bridge := _box(Vector3(0.06, 0.03, 0.02), Color(0.12, 0.12, 0.16))
			bridge.position = Vector3(0, 1.18, -0.222)
			root.add_child(bridge)
			var mouth := _box(Vector3(0.12, 0.03, 0.02), Color(0.45, 0.2, 0.18))
			mouth.position = Vector3(0, 1.03, -0.215)
			root.add_child(mouth)
		5:  # Cool sunglasses.
			var shades := _box(Vector3(0.34, 0.1, 0.03), Color(0.06, 0.06, 0.1))
			shades.position = Vector3(0, 1.17, -0.225)
			root.add_child(shades)
			var smirk := _box(Vector3(0.1, 0.03, 0.02), Color(0.45, 0.2, 0.18))
			smirk.position = Vector3(0.03, 1.03, -0.215)
			root.add_child(smirk)
		6:  # Freckles.
			var grin := _box(Vector3(0.16, 0.04, 0.02), Color(0.45, 0.2, 0.18))
			grin.position = Vector3(0, 1.03, -0.215)
			root.add_child(grin)
			for spot in [Vector3(-0.14, 1.1, -0.215), Vector3(-0.09, 1.08, -0.215),
					Vector3(0.09, 1.08, -0.215), Vector3(0.14, 1.1, -0.215)]:
				var freckle := _sphere(0.014, skin.darkened(0.4))
				freckle.position = spot
				root.add_child(freckle)
		7:  # Surprised: big eyes, round mouth.
			var gasp := _sphere(0.045, Color(0.3, 0.12, 0.1))
			gasp.position = Vector3(0, 1.03, -0.21)
			root.add_child(gasp)

static func _attach_hair(root: Node3D, style: Dictionary) -> void:
	var spec: Dictionary = HAIRS[posmod(int(style.get("hair", 1)), HAIRS.size())]
	var hc: Color = spec.c
	var hair := Node3D.new()
	hair.name = "Hair"
	match str(spec.kind):
		"tuft":
			var tuft := _sphere(0.1, hc)
			tuft.position = Vector3(0, 1.36, 0)
			hair.add_child(tuft)
		"short":
			var top := _box(Vector3(0.44, 0.12, 0.44), hc)
			top.position = Vector3(0, 1.36, 0)
			hair.add_child(top)
			var fringe := _box(Vector3(0.44, 0.08, 0.06), hc)
			fringe.position = Vector3(0, 1.3, -0.19)
			hair.add_child(fringe)
		"spiky":
			for i in 3:
				var spike := _cone(0.06, 0.18, hc)
				spike.position = Vector3(-0.12 + i * 0.12, 1.4, 0)
				hair.add_child(spike)
		"long":
			var top := _box(Vector3(0.44, 0.12, 0.44), hc)
			top.position = Vector3(0, 1.36, 0)
			hair.add_child(top)
			var back := _box(Vector3(0.44, 0.5, 0.1), hc)
			back.position = Vector3(0, 1.1, 0.18)
			hair.add_child(back)
		"ponytail":
			var top := _box(Vector3(0.44, 0.12, 0.44), hc)
			top.position = Vector3(0, 1.36, 0)
			hair.add_child(top)
			var bun := _sphere(0.09, hc)
			bun.position = Vector3(0, 1.36, 0.24)
			hair.add_child(bun)
			var tail := _box(Vector3(0.09, 0.34, 0.09), hc)
			tail.position = Vector3(0, 1.18, 0.27)
			hair.add_child(tail)
		"afro":
			var puff := _sphere(0.3, hc)
			puff.position = Vector3(0, 1.42, 0)
			hair.add_child(puff)
		"mohawk":
			var strip := _box(Vector3(0.09, 0.22, 0.44), hc)
			strip.position = Vector3(0, 1.42, 0)
			hair.add_child(strip)
		"curls":
			for offset in [Vector3(-0.13, 1.38, 0), Vector3(0, 1.43, 0), Vector3(0.13, 1.38, 0)]:
				var curl := _sphere(0.11, hc)
				curl.position = offset
				hair.add_child(curl)
	root.add_child(hair)

## Wearable extras layered over the shirt: armor, capes, a backpack.
static func _attach_gear(root: Node3D, style: Dictionary) -> void:
	var gear := Node3D.new()
	gear.name = "Gear"
	match posmod(int(style.get("gear", 0)), GEAR_COUNT):
		0:
			pass
		1:  # Steel chestplate.
			var plate := _box(Vector3(0.56, 0.4, 0.36), Color("aab4c4"))
			plate.material_override.roughness = 0.3
			plate.position = Vector3(0, 0.72, 0)
			gear.add_child(plate)
		2:  # Gold chestplate.
			var plate := _box(Vector3(0.56, 0.4, 0.36), Color("ffd166"))
			plate.material_override.roughness = 0.25
			plate.position = Vector3(0, 0.72, 0)
			gear.add_child(plate)
		3:  # Shoulder pads.
			for side in [-1.0, 1.0]:
				var pad := _box(Vector3(0.22, 0.12, 0.26), Color("aab4c4"))
				pad.position = Vector3(side * 0.34, 0.94, 0)
				gear.add_child(pad)
		4:  # Red hero cape.
			var cape := _box(Vector3(0.5, 0.74, 0.05), Color("d4553a"))
			cape.position = Vector3(0, 0.6, 0.2)
			gear.add_child(cape)
		5:  # Blue hero cape.
			var cape := _box(Vector3(0.5, 0.74, 0.05), Color("4a9df8"))
			cape.position = Vector3(0, 0.6, 0.2)
			gear.add_child(cape)
		6:  # Backpack.
			var pack := _box(Vector3(0.34, 0.4, 0.18), Color("6b4a2f"))
			pack.position = Vector3(0, 0.72, 0.26)
			gear.add_child(pack)
			var flap := _box(Vector3(0.34, 0.12, 0.2), Color("8a6a42"))
			flap.position = Vector3(0, 0.88, 0.26)
			gear.add_child(flap)
		7:  # Glowing star badge.
			var badge := _sphere(0.06, Color("ffd166"))
			badge.material_override = material(Color("ffd166"), true)
			badge.position = Vector3(0.14, 0.8, -0.17)
			gear.add_child(badge)
	root.add_child(gear)

## Every hat sits on the head top (y ~1.33). Hats are a Node3D so they can
## be made of several parts (helmets, horns, headphones...).
static func attach_hat(root: Node3D, style: Dictionary) -> void:
	var old := root.get_node_or_null("Hat")
	if old != null:
		old.queue_free()
	var hat := Node3D.new()
	hat.name = "Hat"
	var gold := Color("ffd166")
	var accent := shirt_color(style).lightened(0.2)
	match posmod(int(style.get("hat", 0)), HAT_COUNT):
		0:  # Bare head — hair does the talking.
			pass
		1:  # Party cone.
			var cone := _cone(0.18, 0.4, gold)
			cone.position = Vector3(0, 1.5, 0)
			hat.add_child(cone)
		2:  # Crown.
			var crown := _cylinder(0.2, 0.16, gold)
			crown.position = Vector3(0, 1.4, 0)
			hat.add_child(crown)
			for i in 4:
				var jewel := _sphere(0.03, [Color("ff6b6b"), Color("4a9df8"),
					Color("51c979"), Color("b07df0")][i])
				var angle := TAU * i / 4.0
				jewel.position = Vector3(sin(angle) * 0.2, 1.44, cos(angle) * 0.2)
				hat.add_child(jewel)
		3:  # Cap with a little brim.
			var cap := _sphere(0.26, accent)
			cap.position = Vector3(0, 1.34, 0)
			cap.scale = Vector3(1, 0.55, 1)
			hat.add_child(cap)
			var brim := _box(Vector3(0.3, 0.04, 0.18), accent.darkened(0.2))
			brim.position = Vector3(0, 1.33, -0.28)
			hat.add_child(brim)
		4:  # Bow.
			var bow := _sphere(0.12, Color("ff9ff3"))
			bow.position = Vector3(0.14, 1.36, 0)
			bow.scale = Vector3(1, 0.9, 0.6)
			hat.add_child(bow)
		5:  # Bobble antenna.
			var stalk := _box(Vector3(0.03, 0.16, 0.03), Color(0.3, 0.3, 0.36))
			stalk.position = Vector3(0, 1.42, 0)
			hat.add_child(stalk)
			var ball := _sphere(0.08, Color("1dd1a1"))
			ball.material_override = material(Color("1dd1a1"), true)
			ball.position = Vector3(0, 1.56, 0)
			hat.add_child(ball)
		6:  # Halo disc.
			var disc := _cylinder(0.26, 0.05, Color("f5f6fa"))
			disc.position = Vector3(0, 1.46, 0)
			hat.add_child(disc)
		7:  # Knight helmet with a visor slit.
			var shell := _box(Vector3(0.48, 0.36, 0.48), Color("aab4c4"))
			shell.position = Vector3(0, 1.24, 0)
			hat.add_child(shell)
			var visor := _box(Vector3(0.3, 0.06, 0.03), Color(0.08, 0.08, 0.12))
			visor.position = Vector3(0, 1.17, -0.245)
			hat.add_child(visor)
			var plume := _box(Vector3(0.06, 0.18, 0.3), Color("ff6b6b"))
			plume.position = Vector3(0, 1.5, 0)
			hat.add_child(plume)
		8:  # Viking: leather band and big horns.
			var band := _cylinder(0.24, 0.12, Color("6b4a2f"))
			band.position = Vector3(0, 1.36, 0)
			hat.add_child(band)
			for side in [-1.0, 1.0]:
				var horn := _cone(0.07, 0.26, Color("f0ead6"))
				horn.position = Vector3(side * 0.28, 1.44, 0)
				horn.rotation_degrees = Vector3(0, 0, side * -50.0)
				hat.add_child(horn)
		9:  # Wizard: tall cone and wide brim.
			var brim := _cylinder(0.34, 0.05, Color("5a3a8a"))
			brim.position = Vector3(0, 1.36, 0)
			hat.add_child(brim)
			var cone := _cone(0.22, 0.5, Color("5a3a8a"))
			cone.position = Vector3(0, 1.62, 0)
			hat.add_child(cone)
			var star := _sphere(0.05, gold)
			star.material_override = material(gold, true)
			star.position = Vector3(0, 1.62, -0.18)
			hat.add_child(star)
		10:  # Top hat.
			var brim := _cylinder(0.28, 0.04, Color(0.1, 0.1, 0.14))
			brim.position = Vector3(0, 1.36, 0)
			hat.add_child(brim)
			var tube := _cylinder(0.17, 0.32, Color(0.1, 0.1, 0.14))
			tube.position = Vector3(0, 1.54, 0)
			hat.add_child(tube)
			var ribbon := _cylinder(0.175, 0.07, Color("ff6b6b"))
			ribbon.position = Vector3(0, 1.42, 0)
			hat.add_child(ribbon)
		11:  # Headphones.
			var band := _box(Vector3(0.5, 0.06, 0.12), Color(0.15, 0.15, 0.2))
			band.position = Vector3(0, 1.38, 0)
			hat.add_child(band)
			for side in [-1.0, 1.0]:
				var cup := _sphere(0.1, Color(0.15, 0.15, 0.2))
				cup.position = Vector3(side * 0.24, 1.17, 0)
				cup.scale = Vector3(0.7, 1, 1)
				hat.add_child(cup)
				var pad := _sphere(0.05, accent)
				pad.position = Vector3(side * 0.28, 1.17, 0)
				hat.add_child(pad)
		12:  # Chef hat.
			var base := _cylinder(0.2, 0.22, Color("f5f6fa"))
			base.position = Vector3(0, 1.44, 0)
			hat.add_child(base)
			var puff := _sphere(0.22, Color("f5f6fa"))
			puff.position = Vector3(0, 1.6, 0)
			puff.scale = Vector3(1, 0.7, 1)
			hat.add_child(puff)
	root.add_child(hat)
