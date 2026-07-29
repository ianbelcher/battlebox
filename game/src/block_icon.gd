class_name BlockIcon
extends Control
## Hand-drawn item icons, no textures: blocks are shaded iso cubes, plants
## draw as flowers, the special machine blocks get symbol overlays, and every
## weapon is a bold colored roundel with its initial.

var block_id := 0
var kind := "block"   # block / weapon / structure
var dimmed := false
var badge := ""

func _init(p_block := 0, p_kind := "block") -> void:
	block_id = p_block
	kind = p_kind
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _dim(c: Color) -> Color:
	return c.darkened(0.3) if dimmed else c

func _draw() -> void:
	if kind == "empty":
		draw_circle(size * 0.5, size.x * 0.06, Color(1, 1, 1, 0.2))
		return
	var w := size.x
	var h := size.y
	var mid := Vector2(w, h) * 0.5
	if kind == "weapon":
		var spec := Weapons.spec(block_id)
		var c := _dim(spec.color)
		# Big colorful glyph on a soft tinted plate — no more circles.
		draw_rect(Rect2(w * 0.05, h * 0.05, w * 0.9, h * 0.9), Color(c.r, c.g, c.b, 0.16))
		draw_rect(Rect2(w * 0.05, h * 0.05, w * 0.9, h * 0.9),
			Color(c.r, c.g, c.b, 0.85), false, w * 0.035)
		var ink := Color(c.lightened(0.22), 1.0)
		draw_set_transform(mid * -0.4, 0.0, Vector2(1.4, 1.4))
		match block_id:
			13:  # Sword: diagonal blade, crossguard, pommel.
				draw_line(mid + Vector2(-w * 0.1, w * 0.14), mid + Vector2(w * 0.16, -w * 0.12), ink, w * 0.07)
				draw_colored_polygon(PackedVector2Array([mid + Vector2(w * 0.13, -w * 0.16),
					mid + Vector2(w * 0.24, -w * 0.2), mid + Vector2(w * 0.2, -w * 0.09)]), ink)
				draw_line(mid + Vector2(-w * 0.16, w * 0.02), mid + Vector2(-w * 0.02, w * 0.2), ink, w * 0.05)
				draw_circle(mid + Vector2(-w * 0.16, w * 0.2), w * 0.045, ink)
			0:  # Blaster: three speed pellets.
				for i in 3:
					draw_circle(mid + Vector2((i - 1) * w * 0.16, (i - 1) * -w * 0.05), w * 0.07, ink)
			1:  # Bazooka: rocket.
				draw_rect(Rect2(mid.x - w * 0.2, mid.y - w * 0.08, w * 0.28, w * 0.16), ink)
				draw_colored_polygon(PackedVector2Array([mid + Vector2(w * 0.08, -w * 0.14),
					mid + Vector2(w * 0.26, 0), mid + Vector2(w * 0.08, w * 0.14)]), ink)
			2:  # Grapple: hook.
				draw_arc(mid + Vector2(0, w * 0.04), w * 0.16, PI * 0.1, PI * 1.4, 12, ink, w * 0.06)
				draw_line(mid + Vector2(w * 0.12, -w * 0.1), mid + Vector2(w * 0.22, -w * 0.22), ink, w * 0.06)
			3:  # Freeze: snowflake.
				for i in 3:
					var a := i * PI / 3.0
					draw_line(mid - Vector2(cos(a), sin(a)) * w * 0.2,
						mid + Vector2(cos(a), sin(a)) * w * 0.2, ink, w * 0.05)
			4:  # Sucker: inward arrows.
				for i in 4:
					var a := i * TAU / 4.0 + TAU / 8.0
					var dir := Vector2(cos(a), sin(a))
					draw_line(mid + dir * w * 0.24, mid + dir * w * 0.08, ink, w * 0.055)
			5:  # Bridge: planks.
				for i in 3:
					draw_rect(Rect2(mid.x - w * 0.2 + i * w * 0.14, mid.y - w * 0.16, w * 0.1, w * 0.32), ink)
			6:  # Party: dots.
				for i in 5:
					var a := i * TAU / 5.0
					draw_circle(mid + Vector2(cos(a), sin(a)) * w * 0.16, w * 0.06,
						[Color("d63d2e"), Color(0.1, 0.3, 0.8), Color(0.1, 0.5, 0.2)][i % 3])
			7:  # Whirl: spiral arcs.
				draw_arc(mid, w * 0.1, 0, PI * 1.5, 10, ink, w * 0.05)
				draw_arc(mid, w * 0.2, PI, PI * 2.6, 10, ink, w * 0.05)
			8:  # Paint: drips.
				draw_circle(mid + Vector2(-w * 0.1, -w * 0.05), w * 0.09, Color("d63d2e"))
				draw_circle(mid + Vector2(w * 0.1, -w * 0.02), w * 0.08, Color(0.15, 0.3, 0.75))
				draw_circle(mid + Vector2(0, w * 0.14), w * 0.07, Color(0.15, 0.55, 0.25))
			9:  # Napalm: flame.
				draw_colored_polygon(PackedVector2Array([mid + Vector2(0, -w * 0.22),
					mid + Vector2(w * 0.14, w * 0.1), mid + Vector2(0, w * 0.2),
					mid + Vector2(-w * 0.14, w * 0.1)]), Color("d63d2e"))
				draw_circle(mid + Vector2(0, w * 0.06), w * 0.08, Color("ffd166"))
			10:  # Grump whistle: angry eyes.
				for side in [-1.0, 1.0]:
					draw_circle(mid + Vector2(side * w * 0.1, -w * 0.03), w * 0.07, ink)
					draw_line(mid + Vector2(side * w * 0.04, -w * 0.16),
						mid + Vector2(side * w * 0.18, -w * 0.1), ink, w * 0.045)
			11:  # Wings.
				for side in [-1.0, 1.0]:
					draw_colored_polygon(PackedVector2Array([mid,
						mid + Vector2(side * w * 0.26, -w * 0.14),
						mid + Vector2(side * w * 0.18, w * 0.1)]), ink)
			12:  # Digger: shovel.
				draw_line(mid + Vector2(-w * 0.12, -w * 0.18), mid + Vector2(w * 0.04, w * 0.02), ink, w * 0.055)
				draw_colored_polygon(PackedVector2Array([mid + Vector2(w * 0.0, -w * 0.02),
					mid + Vector2(w * 0.2, w * 0.08), mid + Vector2(w * 0.06, w * 0.2)]), ink)
			15:  # Big Shooter: fat rocket.
				draw_rect(Rect2(mid.x - w * 0.24, mid.y - w * 0.12, w * 0.34, w * 0.24), ink)
				draw_colored_polygon(PackedVector2Array([mid + Vector2(w * 0.1, -w * 0.2),
					mid + Vector2(w * 0.32, 0), mid + Vector2(w * 0.1, w * 0.2)]), ink)
			14:  # Flare gun: rising star.
				draw_line(mid + Vector2(0, w * 0.2), mid + Vector2(0, -w * 0.08), ink, w * 0.06)
				for star_i in 4:
					var sa := star_i * TAU / 4.0 + 0.4
					draw_line(mid + Vector2(0, -w * 0.14),
						mid + Vector2(0, -w * 0.14) + Vector2(cos(sa), sin(sa)) * w * 0.12, ink, w * 0.04)
			_:
				draw_circle(mid, w * 0.1, ink)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		return
	if kind == "structure":
		var c := _dim(Structures.spec(block_id).color)
		draw_colored_polygon(PackedVector2Array([Vector2(w * 0.5, h * 0.06),
			Vector2(w * 0.95, h * 0.45), Vector2(w * 0.05, h * 0.45)]), c)
		draw_rect(Rect2(w * 0.16, h * 0.45, w * 0.68, h * 0.47), c.darkened(0.25))
		draw_rect(Rect2(w * 0.4, h * 0.62, w * 0.2, h * 0.3), Color(0.08, 0.08, 0.12, 0.8))
		return
	# Blocks.
	if Blocks.is_cross(block_id):
		# Flower/plant glyph: stem + petals in the block's color.
		var c := _dim(Blocks.color_of(block_id))
		draw_rect(Rect2(mid.x - w * 0.04, h * 0.45, w * 0.08, h * 0.45), _dim(Color("5d8f43")))
		for angle_i in 6:
			var a := angle_i * TAU / 6.0
			draw_circle(Vector2(mid.x, h * 0.34) + Vector2(cos(a), sin(a)) * w * 0.16, w * 0.11, c)
		draw_circle(Vector2(mid.x, h * 0.34), w * 0.1, _dim(Color("ffd166")))
		return
	var top := _dim(Blocks.top_color_of(block_id))
	var side := _dim(Blocks.color_of(block_id))
	var ty := h * 0.28
	var my := h * 0.55
	draw_colored_polygon(PackedVector2Array([Vector2(mid.x, 0), Vector2(w, ty * 0.5),
		Vector2(mid.x, ty), Vector2(0, ty * 0.5)]), Color(top.r, top.g, top.b))
	draw_colored_polygon(PackedVector2Array([Vector2(0, ty * 0.5), Vector2(mid.x, ty),
		Vector2(mid.x, h), Vector2(0, my)]), Color(side.r * 0.72, side.g * 0.72, side.b * 0.72))
	draw_colored_polygon(PackedVector2Array([Vector2(mid.x, ty), Vector2(w, ty * 0.5),
		Vector2(w, my), Vector2(mid.x, h)]), Color(side.r * 0.55, side.g * 0.55, side.b * 0.55))
	# Symbol overlays so the machine blocks read at a glance.
	var overlay := Color(1, 1, 1, 0.9)
	match block_id:
		Blocks.BOOM:
			for i in 8:
				var a := i * TAU / 8.0
				draw_line(mid, mid + Vector2(cos(a), sin(a)) * w * 0.28, overlay, w * 0.045)
		Blocks.LAUNCHER:
			draw_colored_polygon(PackedVector2Array([Vector2(mid.x, h * 0.22),
				Vector2(w * 0.72, h * 0.55), Vector2(w * 0.28, h * 0.55)]), overlay)
		Blocks.TELEPORT:
			draw_circle(mid, w * 0.24, overlay, false, w * 0.06)
		Blocks.NOTE:
			draw_rect(Rect2(w * 0.36, h * 0.24, w * 0.07, h * 0.4), overlay)
			draw_circle(Vector2(w * 0.34, h * 0.64), w * 0.09, overlay)
			draw_rect(Rect2(w * 0.43, h * 0.24, w * 0.18, h * 0.08), overlay)
		Blocks.BOUNCY:
			for i in 3:
				draw_line(Vector2(w * 0.28, h * (0.35 + i * 0.14)),
					Vector2(w * 0.72, h * (0.35 + i * 0.14)), overlay, w * 0.05)
		Blocks.SPONGE:
			for pos in [Vector2(0.36, 0.4), Vector2(0.6, 0.34), Vector2(0.5, 0.58), Vector2(0.66, 0.55)]:
				draw_circle(Vector2(w * pos.x, h * pos.y), w * 0.06, Color(0.4, 0.35, 0.1, 0.8))
		Blocks.CONFETTI:
			for i in 6:
				var a := i * TAU / 6.0 + 0.4
				draw_circle(mid + Vector2(cos(a), sin(a)) * w * 0.22, w * 0.06,
					[Color("ff6b6b"), Color("ffd166"), Color("4a9df8")][i % 3])
		Blocks.LANTERN, Blocks.GLOWSTONE:
			for i in 6:
				var a := i * TAU / 6.0
				draw_line(mid + Vector2(cos(a), sin(a)) * w * 0.14,
					mid + Vector2(cos(a), sin(a)) * w * 0.26, Color(1, 1, 0.8, 0.9), w * 0.04)
			draw_circle(mid, w * 0.1, Color(1, 0.95, 0.7))
		Blocks.CAMPFIRE, Blocks.LAVA:
			draw_colored_polygon(PackedVector2Array([mid + Vector2(0, -w * 0.2),
				mid + Vector2(w * 0.12, w * 0.08), mid + Vector2(0, w * 0.16),
				mid + Vector2(-w * 0.12, w * 0.08)]), Color(1, 0.5, 0.15, 0.95))
		Blocks.GLASS, Blocks.ICE:
			draw_line(mid + Vector2(-w * 0.16, w * 0.12), mid + Vector2(w * 0.04, -w * 0.16), Color(1, 1, 1, 0.8), w * 0.05)
			draw_line(mid + Vector2(-w * 0.02, w * 0.16), mid + Vector2(w * 0.14, -w * 0.06), Color(1, 1, 1, 0.6), w * 0.04)
		Blocks.FIREWORK:
			draw_line(Vector2(w * 0.35, h * 0.65), Vector2(w * 0.62, h * 0.3), overlay, w * 0.05)
			for i in 5:
				var a := i * TAU / 5.0
				draw_line(Vector2(w * 0.62, h * 0.3),
					Vector2(w * 0.62, h * 0.3) + Vector2(cos(a), sin(a)) * w * 0.12, overlay, w * 0.03)

	# Material textures so the family blocks read as more than flat color.
	if block_id >= Blocks.M_STONE and block_id < Blocks.M_SOIL:
		for i in 6:
			draw_circle(mid + Vector2(sin(i * 2.4 + block_id) * w * 0.16,
				cos(i * 1.7 + block_id) * w * 0.13 + w * 0.04), w * 0.025, Color(0, 0, 0, 0.32))
	elif block_id >= Blocks.M_SOIL and block_id < Blocks.M_SNOW:
		for i in 3:
			var gy := h * (0.42 + i * 0.14)
			draw_line(Vector2(w * 0.3, gy), Vector2(w * 0.7, gy + w * 0.04),
				Color(0, 0, 0, 0.24), w * 0.03)
	elif block_id >= Blocks.M_STEEL and block_id < Blocks.M_STONE:
		for rivet in [Vector2(0.34, 0.38), Vector2(0.66, 0.38), Vector2(0.34, 0.72), Vector2(0.66, 0.72)]:
			draw_circle(Vector2(w * rivet.x, h * rivet.y), w * 0.028, Color(1, 1, 1, 0.4))
	elif block_id >= Blocks.M_SNOW and block_id < Blocks.MAX_BLOCK:
		for i in 3:
			var p := mid + Vector2(sin(i * 2.1 + block_id) * w * 0.15, cos(i * 2.8) * w * 0.12)
			draw_line(p - Vector2(w * 0.035, 0), p + Vector2(w * 0.035, 0), Color(1, 1, 1, 0.75), w * 0.02)
			draw_line(p - Vector2(0, w * 0.035), p + Vector2(0, w * 0.035), Color(1, 1, 1, 0.75), w * 0.02)
