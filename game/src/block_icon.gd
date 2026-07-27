class_name BlockIcon
extends Control
## A little isometric cube drawn from a block's palette colors — readable
## "icons" for the hotbar and picker without any texture assets.

var block_id := 0
var dimmed := false

func _init(p_block := 0) -> void:
	block_id = p_block
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _draw() -> void:
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
