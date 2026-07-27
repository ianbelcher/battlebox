class_name BlockIcon
extends Control
## A little isometric cube drawn from a block's palette colors — readable
## "icons" for the hotbar and picker without any texture assets.

var block_id := 0
var kind := "block"   # block / weapon / structure
var dimmed := false

func _init(p_block := 0, p_kind := "block") -> void:
	block_id = p_block
	kind = p_kind
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _draw() -> void:
	if kind == "weapon":
		var c := Color("ffe08a") if block_id == 0 else Color("ff7a3d")
		if dimmed:
			c = c.darkened(0.3)
		var mid := size * 0.5
		if block_id == 0:
			# Blaster: barrel + three speed lines.
			draw_rect(Rect2(size.x * 0.15, mid.y - size.y * 0.1, size.x * 0.55, size.y * 0.2), c)
			for i in 3:
				draw_rect(Rect2(size.x * 0.75, mid.y - size.y * 0.18 + i * size.y * 0.15,
					size.x * 0.18, size.y * 0.06), c)
		else:
			# Bazooka: fat rocket with fins.
			draw_rect(Rect2(size.x * 0.2, mid.y - size.y * 0.14, size.x * 0.5, size.y * 0.28), c)
			draw_colored_polygon(PackedVector2Array([Vector2(size.x * 0.7, mid.y - size.y * 0.14),
				Vector2(size.x * 0.92, mid.y), Vector2(size.x * 0.7, mid.y + size.y * 0.14)]), c)
			draw_colored_polygon(PackedVector2Array([Vector2(size.x * 0.2, mid.y - size.y * 0.14),
				Vector2(size.x * 0.08, mid.y - size.y * 0.3), Vector2(size.x * 0.2, mid.y)]), c)
		return
	if kind == "structure":
		var c := Blocks.color_of(block_id) if block_id > 0 else Color("d6c396")
		if dimmed:
			c = c.darkened(0.3)
		# Little house glyph.
		draw_colored_polygon(PackedVector2Array([Vector2(size.x * 0.5, size.y * 0.08),
			Vector2(size.x * 0.92, size.y * 0.45), Vector2(size.x * 0.08, size.y * 0.45)]), c)
		draw_rect(Rect2(size.x * 0.2, size.y * 0.45, size.x * 0.6, size.y * 0.45), c.darkened(0.25))
		return
	var top := Blocks.top_color_of(block_id)
	var side := Blocks.color_of(block_id)
	if dimmed:
		top = top.darkened(0.25)
		side = side.darkened(0.25)
	var w := size.x
	var h := size.y
	var mx := w * 0.5
	var ty := h * 0.28
	var my := h * 0.55
	# Top diamond, then left/right faces with distinct shading.
	draw_colored_polygon(PackedVector2Array([Vector2(mx, 0), Vector2(w, ty * 0.5),
		Vector2(mx, ty), Vector2(0, ty * 0.5)]), Color(top.r, top.g, top.b))
	draw_colored_polygon(PackedVector2Array([Vector2(0, ty * 0.5), Vector2(mx, ty),
		Vector2(mx, h), Vector2(0, my)]), Color(side.r * 0.72, side.g * 0.72, side.b * 0.72))
	draw_colored_polygon(PackedVector2Array([Vector2(mx, ty), Vector2(w, ty * 0.5),
		Vector2(w, my), Vector2(mx, h)]), Color(side.r * 0.55, side.g * 0.55, side.b * 0.55))
