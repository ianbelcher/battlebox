extends Control
## Client UI shell (and server bootstrap). Two layers: the connect screen and
## the in-world screen (split-screen viewports + a thin shared overlay).
## When launched headless (or with --server / WORLD_ROLE=server) no UI is
## built at all; we just start listening.

const TITLE := "Boxel Battle"
const BG_TOP := Color("22304a")
const BG_BOTTOM := Color("10141f")
const GOLD := Color("ffd166")

const LEAVE_HOLD_SECONDS := 1.2

var _connect_screen: Control
var _game_screen: Control
var _split: SplitScreen
var _address_edit: LineEdit
var _status_label: Label
var _clock_label: Label
var _players_label: Label
var _survival_button: Button
var _battle_button: Button
var _lobby_panel: PanelContainer
var _lobby_label: Label
var _storm_tint: ColorRect
var _team_rows: VBoxContainer
var _wave_label: Label
var _banner: Label
var _vote_panel: PanelContainer
var _minimap: TextureRect
var _loading_label: Label

var _prev_pressed: Dictionary = {}
var _leave_hold: Dictionary = {}
var _in_world := false

func _ready() -> void:
	if _is_server_mode():
		if Net.start_server() == OK:
			Game.create_world()
		else:
			get_tree().quit(1)
		return
	# The 3D world lives in the root viewport's World3D but is only ever
	# rendered through the split-screen SubViewports (which share that world);
	# rendering it from the root too would waste a full pass and, with no
	# camera, spams fog/compute errors.
	get_viewport().disable_3d = true
	# Lets the Wireframe video toggle actually draw wireframes at runtime.
	RenderingServer.set_debug_generate_wireframes(true)
	_build_connect_screen()
	_build_game_screen()
	Net.connected_to_server.connect(_on_connected)
	Net.connection_failed.connect(func() -> void:
		_set_status("Couldn't reach the server. Is the address right?"))
	Net.server_disconnected.connect(_on_server_lost)
	Game.roster_changed.connect(_on_roster_changed)
	_show_screen(_connect_screen)
	var auto_url := OS.get_environment("WORLD_AUTOCONNECT")
	if not auto_url.is_empty():
		_address_edit.text = auto_url
		_on_connect_pressed()
	# WORLD_SHOTS=<dir>: save a screenshot every 1.5s (visual debugging).
	var shots_dir := OS.get_environment("WORLD_SHOTS")
	if not shots_dir.is_empty():
		var shot_timer := Timer.new()
		shot_timer.wait_time = 1.5
		var counter := [0]
		shot_timer.timeout.connect(func() -> void:
			counter[0] += 1
			get_viewport().get_texture().get_image().save_png(
				"%s/shot_%03d.png" % [shots_dir, counter[0]]))
		add_child(shot_timer)
		shot_timer.start()

func _is_server_mode() -> bool:
	if OS.get_environment("WORLD_ROLE") == "client":
		return false
	return DisplayServer.get_name() == "headless" \
		or OS.get_environment("WORLD_ROLE") == "server" \
		or "--server" in OS.get_cmdline_user_args()

# ------------------------------------------------------------------
# Screens
# ------------------------------------------------------------------

func _show_screen(screen: Control) -> void:
	for child in [_connect_screen, _game_screen]:
		if child != null:
			child.visible = child == screen

static func ui_scale() -> float:
	return clampf(DisplayServer.window_get_size().x / 1100.0, 1.15, 3.0)

func _make_label(text: String, size: int, color := Color.WHITE, outline := 0) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", int(size * ui_scale()))
	label.add_theme_color_override("font_color", color)
	if outline > 0:
		label.add_theme_color_override("font_outline_color", Color(0.05, 0.05, 0.1, 0.9))
		label.add_theme_constant_override("outline_size", outline)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return label

func _gradient_bg() -> TextureRect:
	var grad := Gradient.new()
	grad.colors = PackedColorArray([BG_TOP, BG_BOTTOM])
	grad.offsets = PackedFloat32Array([0.0, 1.0])
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill_from = Vector2(0, 0)
	tex.fill_to = Vector2(0, 1)
	var rect := TextureRect.new()
	rect.texture = tex
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_SCALE
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	return rect

func _build_connect_screen() -> void:
	_connect_screen = Control.new()
	_connect_screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	_connect_screen.add_child(_gradient_bg())
	add_child(_connect_screen)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_connect_screen.add_child(center)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 18)
	center.add_child(box)
	box.add_child(_make_label(TITLE, 72, GOLD, 10))
	box.add_child(_make_label("One world, always on. Type the server address and hop in.",
		20, Color(1, 1, 1, 0.65)))
	_address_edit = LineEdit.new()
	_address_edit.text = Net.default_server_url()
	_address_edit.add_theme_font_size_override("font_size", 22)
	_address_edit.custom_minimum_size = Vector2(500, 0)
	_address_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_address_edit)
	var button := Button.new()
	button.focus_mode = Control.FOCUS_NONE
	button.text = "  Connect  "
	button.add_theme_font_size_override("font_size", 30)
	button.pressed.connect(_on_connect_pressed)
	var holder := CenterContainer.new()
	holder.add_child(button)
	box.add_child(holder)
	_address_edit.text_submitted.connect(func(_t: String) -> void: _on_connect_pressed())
	_status_label = _make_label("", 18, Color("ff8888"))
	box.add_child(_status_label)

func _build_game_screen() -> void:
	_game_screen = Control.new()
	_game_screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	_game_screen.visible = false
	add_child(_game_screen)
	_split = SplitScreen.new()
	_game_screen.add_child(_split)
	_loading_label = _make_label("Flying in...", 26, GOLD, 6)
	_loading_label.set_anchors_preset(Control.PRESET_CENTER)
	_loading_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_loading_label.grow_vertical = Control.GROW_DIRECTION_BOTH
	_game_screen.add_child(_loading_label)

	# Top-right cluster: the minimap with the clock and player count under
	# it, all sized from the window (rebuilt on resize).
	_minimap = TextureRect.new()
	_minimap.stretch_mode = TextureRect.STRETCH_SCALE
	_minimap.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_minimap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Retired in favor of the per-player radar in each PlayerHud; the node
	# stays so the layout math and 3-player big map keep working.
	_minimap.visible = false
	_game_screen.add_child(_minimap)
	_clock_label = _make_label("", 20, Color.WHITE, 4)
	_game_screen.add_child(_clock_label)
	_players_label = _make_label("", 16, Color(1, 1, 1, 0.75), 4)
	_game_screen.add_child(_players_label)
	_wave_label = _make_label("", 20, Color("ff6b6b"), 4)
	_game_screen.add_child(_wave_label)
	_layout_topright()
	get_viewport().size_changed.connect(func() -> void:
		_layout_topright()
		if _split != null and _in_world:
			_split.update_layout())
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.04, 0.05, 0.08, 0.85)
	style.set_corner_radius_all(12)
	style.set_content_margin_all(int(14 * ui_scale()))
	# Reset vote panel.
	_vote_panel = PanelContainer.new()
	_vote_panel.add_theme_stylebox_override("panel", style.duplicate())
	_vote_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_vote_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_vote_panel.offset_top = 46
	_vote_panel.visible = false
	_game_screen.add_child(_vote_panel)
	var vote_row := HBoxContainer.new()
	vote_row.add_theme_constant_override("separation", 10)
	_vote_panel.add_child(vote_row)
	vote_row.add_child(_make_label("Reset the world with a NEW map?", 16, GOLD))
	var yes := Button.new()
	yes.focus_mode = Control.FOCUS_NONE
	yes.text = "Yes!"
	yes.pressed.connect(func() -> void:
		Game.world.sv_reset_answer.rpc_id(1, true)
		_vote_panel.visible = false)
	vote_row.add_child(yes)
	var no := Button.new()
	no.focus_mode = Control.FOCUS_NONE
	no.text = "No"
	no.pressed.connect(func() -> void:
		Game.world.sv_reset_answer.rpc_id(1, false)
		_vote_panel.visible = false)
	vote_row.add_child(no)
	var map_timer := Timer.new()
	map_timer.wait_time = 1.5
	map_timer.timeout.connect(_update_minimap)
	add_child(map_timer)
	map_timer.start()
	# Battle-royale lobby overlay: countdown + team picking per local player.
	_lobby_panel = PanelContainer.new()
	_lobby_panel.add_theme_stylebox_override("panel", style.duplicate())
	_lobby_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_lobby_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_lobby_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	_lobby_panel.visible = false
	_game_screen.add_child(_lobby_panel)
	var lobby_box := VBoxContainer.new()
	lobby_box.add_theme_constant_override("separation", int(12 * ui_scale()))
	_lobby_panel.add_child(lobby_box)
	_lobby_label = _make_label("BATTLE ROYALE", 34, GOLD, 6)
	lobby_box.add_child(_lobby_label)
	lobby_box.add_child(_make_label("Pick your team!", 20, Color.WHITE))
	var presets := HBoxContainer.new()
	presets.add_theme_constant_override("separation", int(8 * ui_scale()))
	lobby_box.add_child(presets)
	presets.add_child(_make_label("Storm:", 18, Color(1, 1, 1, 0.7)))
	for minutes in [3, 5, 8]:
		var preset_btn := Button.new()
		preset_btn.focus_mode = Control.FOCUS_NONE
		preset_btn.focus_mode = Control.FOCUS_NONE
		preset_btn.text = "%d min" % minutes
		preset_btn.add_theme_font_size_override("font_size", int(18 * ui_scale()))
		var m: int = minutes
		preset_btn.pressed.connect(func() -> void:
			Game.world.sv_match_config.rpc_id(1, m, -1))
		presets.add_child(preset_btn)
	var loot_btn := Button.new()
	loot_btn.focus_mode = Control.FOCUS_NONE
	loot_btn.focus_mode = Control.FOCUS_NONE
	loot_btn.text = "Loot only"
	loot_btn.toggle_mode = true
	loot_btn.add_theme_font_size_override("font_size", int(18 * ui_scale()))
	loot_btn.toggled.connect(func(on: bool) -> void:
		Game.world.sv_match_config.rpc_id(1, -1, 1 if on else 0))
	presets.add_child(loot_btn)
	_team_rows = VBoxContainer.new()
	_team_rows.add_theme_constant_override("separation", int(8 * ui_scale()))
	lobby_box.add_child(_team_rows)
	# Storm warning tint.
	_storm_tint = ColorRect.new()
	_storm_tint.color = Color(0.9, 0.15, 0.1, 0.0)
	_storm_tint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_storm_tint.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_game_screen.add_child(_storm_tint)
	# Center banner for survival results.
	_banner = _make_label("", 40, GOLD, 8)
	_banner.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_banner.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_banner.grow_vertical = Control.GROW_DIRECTION_BOTH
	_banner.visible = false
	_game_screen.add_child(_banner)

# ------------------------------------------------------------------
# Connection flow
# ------------------------------------------------------------------

func _on_connect_pressed() -> void:
	var url := _address_edit.text.strip_edges()
	if url.is_empty():
		return
	if not url.begins_with("ws://") and not url.begins_with("wss://"):
		url = "ws://" + url
	_set_status("Connecting...")
	Net.connect_to(url)

func _on_connected() -> void:
	print("Connected to world server as peer %d" % multiplayer.get_unique_id())
	_set_status("")
	var world := Game.create_world()
	_split.world = world
	world.world_ready.connect(func() -> void:
		_loading_label.visible = false
		# Progressively pull the whole island in the background so travel
		# never waits on the server.
		for i in 4:
			var radius: int = [8, 11, 14, 17][i]
			get_tree().create_timer(2.0 + i * 5.0).timeout.connect(func() -> void:
				if Game.world != null and Game.world.chunks != null:
					Game.world.chunks.prefetch(radius)))
	Game.video_changed.connect(_apply_video)
	world.survival_changed.connect(_refresh_survival)
	world.match_changed.connect(_refresh_match)
	world.match_won.connect(func(winner: int) -> void:
		_show_banner("TEAM %s WINS THE BATTLE!" % WorldNode.TEAM_NAMES[winner].to_upper() \
			if winner >= 0 else "The storm wins... nobody survived!"))
	world.reset_vote_started.connect(func() -> void: _vote_panel.visible = true)
	world.reset_result.connect(func(happened: bool) -> void:
		_vote_panel.visible = false
		_show_banner("A brand new world!" if happened else "Map reset was voted down"))
	world.survival_ended.connect(func(seconds: float, bonked: int) -> void:
		_show_banner("You survived %d:%02d and bonked %d Grumps!" % [
			int(seconds / 60.0), int(seconds) % 60, bonked])
	)
	_refresh_survival()
	_in_world = true
	_loading_label.visible = true
	_show_screen(_game_screen)
	_split.update_layout()
	_maybe_start_autotest()
	# Old machines: if we can't hold ~45fps after settling, drop the fancy
	# effects and render scale automatically (WORLD_LOWFX=1/0 forces it).
	var forced_fx := OS.get_environment("WORLD_LOWFX")
	if forced_fx == "1":
		_apply_low_fx()
	elif forced_fx != "0":
		get_tree().create_timer(14.0).timeout.connect(func() -> void:
			if _in_world and Engine.get_frames_per_second() < 45.0:
				_apply_low_fx()
				_show_banner("Smoother mode on!"))

## WORLD_AUTOTEST=<n>: join n bot players who wander, dig and build — lets a
## headless client soak-test a full world session.
func _maybe_start_autotest() -> void:
	var bots := OS.get_environment("WORLD_AUTOTEST")
	if not bots.is_valid_int() or bots.to_int() <= 0:
		return
	for i in mini(bots.to_int(), Game.MAX_LOCAL):
		Game.join_local(BotSlot.new(i))
	_split.update_layout()
	# Exercise the customization RPCs the way HUD swatch clicks would.
	get_tree().create_timer(3.0).timeout.connect(func() -> void:
		for slot: int in Game.local_inputs.keys():
			Game.cycle_local_style(slot, ["body", "shirt", "hat"][slot % 3], 1))
	# WORLD_AUTOTEST_BLOCK=<id>: pin every bot's hotbar to one block so a
	# smoke test can hammer a specific mechanic (booms, warp stones...).
	if OS.get_environment("WORLD_AUTOTEST_MATCH") == "1":
		get_tree().create_timer(6.0).timeout.connect(func() -> void:
			if Game.world != null:
				Game.world.sv_match_start.rpc_id(1, 0)
				for slot: int in Game.local_inputs.keys():
					Game.set_local_team(slot, slot % 4))
	if OS.get_environment("WORLD_AUTOTEST_SURVIVAL") == "1":
		get_tree().create_timer(8.0).timeout.connect(func() -> void:
			if Game.world != null:
				Game.world.sv_survival_start.rpc_id(1, 0))
	var forced := OS.get_environment("WORLD_AUTOTEST_BLOCK")
	if forced.is_valid_int():
		var pin := Timer.new()
		pin.wait_time = 2.0
		pin.timeout.connect(func() -> void:
			for child in Game.world.players.get_children():
				if child is Player and child.is_local:
					child.slots[2] = {"kind": "block", "id": forced.to_int()}
					child.selected_slot = 2)
		add_child(pin)
		pin.start()

func _on_server_lost() -> void:
	Net.go_offline()
	Game.reset_to_disconnected()
	_in_world = false
	_set_status("Lost the server connection.")
	_show_screen(_connect_screen)

func _set_status(text: String) -> void:
	if _status_label != null:
		_status_label.text = text

## Top-right minimap: top-block colors around the local players plus dots
## (gold = you, red = everyone else).
func _update_minimap() -> void:
	if not _in_world or Game.world == null or Game.world.chunks == null \
			or Game.world.players == null:
		return
	var center := Vector3(Game.world.spawn_pos)
	var locals: Array = []
	for child in Game.world.players.get_children():
		if child is Player and child.is_local:
			locals.append(child.position)
	if not locals.is_empty():
		center = Vector3.ZERO
		for pos: Vector3 in locals:
			center += pos
		center /= locals.size()
	var image := Image.create(96, 96, false, Image.FORMAT_RGB8)
	for py in 96:
		for px in 96:
			var wx := int(center.x) + (px - 48) * 2
			var wz := int(center.z) + (py - 48) * 2
			var block: int = Game.world.chunks.top_block(wx, wz)
			var color := Color(0.06, 0.07, 0.1)
			if block > 0:
				color = Blocks.top_color_of(block)
			image.set_pixel(px, py, color)
	if Game.world.match_phase == "BATTLE":
		var ring: float = Game.world.storm_radius
		for angle_i in 140:
			var a := angle_i * TAU / 140.0
			var px := 48 + int((cos(a) * ring - center.x) / 2.0)
			var py := 48 + int((sin(a) * ring - center.z) / 2.0)
			if px >= 0 and px < 96 and py >= 0 and py < 96:
				image.set_pixel(px, py, Color(1.0, 0.25, 0.2))
	for child in Game.world.players.get_children():
		if child is Player:
			var px := 48 + int((child.position.x - center.x) / 2.0)
			var py := 48 + int((child.position.z - center.z) / 2.0)
			if px >= 1 and px < 95 and py >= 1 and py < 95:
				var dot := Color("ffd166") if child.is_local else Color("ff4426")
				for dy in range(-1, 2):
					for dx in range(-1, 2):
						image.set_pixel(px + dx, py + dy, dot)
	_minimap.texture = ImageTexture.create_from_image(image)
	# The 3-player layout's fourth quarter shows a wide shared battle map.
	if _split != null and _split.big_map != null and is_instance_valid(_split.big_map):
		var wide := Image.create(120, 120, false, Image.FORMAT_RGB8)
		for py in 120:
			for px in 120:
				var wx := int(center.x) + (px - 60) * 4
				var wz := int(center.z) + (py - 60) * 4
				var block: int = Game.world.chunks.top_block(wx, wz)
				var color := Color(0.06, 0.07, 0.1)
				if block > 0:
					color = Blocks.top_color_of(block)
				wide.set_pixel(px, py, color)
		for child in Game.world.players.get_children():
			if child is Player:
				var px := 60 + int((child.position.x - center.x) / 4.0)
				var py := 60 + int((child.position.z - center.z) / 4.0)
				if px >= 1 and px < 119 and py >= 1 and py < 119:
					var dot := Color("ffd166") if child.is_local else Color("ff4426")
					for dy in range(-1, 2):
						for dx in range(-1, 2):
							wide.set_pixel(px + dx, py + dy, dot)
		_split.big_map.texture = ImageTexture.create_from_image(wide)

func _apply_low_fx() -> void:
	if Game.world == null:
		return
	if Game.world.sky != null:
		Game.world.sky.set_low_fx(true)
	if Game.world.chunks != null:
		Game.world.chunks.light_cap = 4
	if _split != null:
		_split.set_low_fx(true)
	print("Low-FX mode enabled (fps was %d)" % Engine.get_frames_per_second())

## Applies the advanced video settings (Game.video) everywhere: shadows,
## SSAO/glow, dynamic light cap, render resolution, even wireframe.
func _apply_video() -> void:
	var v: Dictionary = Game.video
	if Game.world != null and Game.world.sky != null:
		Game.world.sky.set_low_fx(not bool(v.fancy_light))
		Game.world.sky.allow_shadows = bool(v.shadows)
	if Game.world != null and Game.world.chunks != null:
		Game.world.chunks.light_cap = 8 if bool(v.lights) else 0
	if _split != null:
		_split.set_low_fx(not bool(v.res))
		_split.set_wireframe(bool(v.wire))

## Everything top-right scales with the window: map ~24% of height.
func _layout_topright() -> void:
	if _minimap == null:
		return
	var window := Vector2(DisplayServer.window_get_size())
	var map_px := clampf(window.y * 0.24, 150.0, 460.0)
	var clock_y := 6.0
	_minimap.custom_minimum_size = Vector2(map_px, map_px)
	_minimap.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_minimap.position = Vector2(window.x - map_px - 12, 12)
	_minimap.size = Vector2(map_px, map_px)
	_clock_label.add_theme_font_size_override("font_size", int(22 * ui_scale()))
	_players_label.add_theme_font_size_override("font_size", int(16 * ui_scale()))
	_wave_label.add_theme_font_size_override("font_size", int(22 * ui_scale()))
	# Clock sits under each hud's radar (radar is ~24% of cell height).
	_clock_label.position = Vector2(window.x - map_px - 12, clock_y)
	_clock_label.size.x = map_px
	_players_label.position = Vector2(window.x - map_px - 12, clock_y + 30 * ui_scale())
	_players_label.size.x = map_px
	_wave_label.position = Vector2(window.x - map_px - 12, clock_y + 56 * ui_scale())
	_wave_label.size.x = map_px

func _refresh_match() -> void:
	var world := Game.world
	if world == null:
		return
	var phase: String = world.match_phase
	_lobby_panel.visible = false  # the lobby lives in each player's menu now
	if phase == "LOBBY":
		_rebuild_team_rows()
	elif phase == "DROP":
		_show_banner("DROP! Glide to a good spot!")
	elif phase == "BATTLE":
		_show_banner("FIGHT! Stay inside the storm circle!")
	elif phase == "END":
		pass  # cl_match_end banner below

func _rebuild_team_rows() -> void:
	for child in _team_rows.get_children():
		child.queue_free()
	var me := multiplayer.get_unique_id()
	for id: String in Game.roster.keys():
		var entry: Dictionary = Game.roster[id]
		var is_bot: bool = entry.get("bot", false)
		var is_mine: bool = entry.peer == me and Game.local_inputs.has(entry.slot)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", int(8 * ui_scale()))
		var who := _make_label(("🤖 " if is_bot else "") + str(entry.name) + ":", 20,
			Color.WHITE if is_mine or is_bot else Color(1, 1, 1, 0.55))
		row.add_child(who)
		for t in 4:
			var btn := Button.new()
			btn.focus_mode = Control.FOCUS_NONE
			btn.text = WorldNode.TEAM_NAMES[t]
			btn.disabled = not (is_mine or is_bot)
			btn.add_theme_font_size_override("font_size", int(18 * ui_scale()))
			var col: Color = WorldNode.TEAM_COLORS[t]
			btn.add_theme_color_override("font_color",
				col if int(entry.get("team", -1)) != t else Color.BLACK)
			var team := t
			var s: int = entry.slot
			var target := id
			btn.pressed.connect(func() -> void:
				if is_mine:
					Game.set_local_team(s, team)
				else:
					Game.world.sv_set_bot_team.rpc_id(1, target, team)
				Sfx.play("pop", -4.0))
			row.add_child(btn)
		_team_rows.add_child(row)

func _refresh_survival() -> void:
	if _survival_button == null or Game.world == null:
		return
	_survival_button.visible = not Game.world.survival_active
	_wave_label.text = "Wave %d!" % Game.world.survival_wave \
		if Game.world.survival_active else ""

func _show_banner(text: String) -> void:
	_loading_label.visible = false
	_banner.text = text
	_banner.visible = true
	_banner.modulate.a = 1.0
	var tween := create_tween()
	tween.tween_interval(5.0)
	tween.tween_property(_banner, "modulate:a", 0.0, 1.0)
	tween.tween_callback(func() -> void: _banner.visible = false)

var _last_local_sig := ""

func _on_roster_changed() -> void:
	if _lobby_panel != null and _lobby_panel.visible:
		_rebuild_team_rows()
	# Only rebuild the split screen when the set of local players actually
	# changed - name/style/team edits must not tear down open menus.
	var sig := str(Game.local_inputs.keys())
	if _split != null and sig != _last_local_sig:
		_last_local_sig = sig
		_split.update_layout()
	if _players_label != null:
		_players_label.text = "%d playing" % Game.roster.size()

# ------------------------------------------------------------------
# Per-frame: join/leave polling, clock display, ambient audio
# ------------------------------------------------------------------

func _process(_delta: float) -> void:
	if Net.is_server or not _in_world:
		return
	_poll_join_leave(_delta)
	var world := Game.world
	if world == null:
		return
	if world.match_phase == "LOBBY":
		world.match_seconds = maxf(0.0, world.match_seconds - _delta)
		_lobby_label.text = "BATTLE ROYALE — starting in %d" % int(ceil(world.match_seconds))
	# The per-player red warning lives in each PlayerHud now.
	_storm_tint.color.a = 0.0
	var clock: float = world.clock
	var hour := int(fposmod(clock * 24.0, 24.0))
	var night: bool = clock > 0.78 or clock < 0.22
	_clock_label.text = "%s %02d:00" % ["☾" if night else "☀", hour]
	Sfx.play_ambient("crickets" if night else "birds")

func _claimed_keys() -> Dictionary:
	var keys := {}
	for input: InputSlot in Game.local_inputs.values():
		keys[input.claim_key()] = true
	return keys

func _poll_join_leave(delta: float) -> void:
	# Unclaimed devices can hop in any time.
	for slot: InputSlot in InputSlot.candidate_slots():
		var key := slot.claim_key()
		if _claimed_keys().has(key):
			continue
		if slot.is_primary_pressed() and not _prev_pressed.get(key, false):
			Game.join_local(slot)
			_split.update_layout()
		_prev_pressed[key] = slot.is_primary_pressed()
	# Claimed devices leave by HOLDING their leave control.
	for slot_index: int in Game.local_inputs.keys().duplicate():
		var input: InputSlot = Game.local_inputs[slot_index]
		var key := input.claim_key()
		if input.is_leave_pressed():
			_leave_hold[key] = _leave_hold.get(key, 0.0) + delta
			if _leave_hold[key] >= LEAVE_HOLD_SECONDS:
				_leave_hold.erase(key)
				Game.leave_local(slot_index)
				Sfx.play("pop")
				_split.update_layout()
		else:
			_leave_hold.erase(key)
