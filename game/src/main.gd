extends Control
## Client UI shell (and server bootstrap). Two layers: the connect screen and
## the in-world screen (split-screen viewports + a thin shared overlay).
## When launched headless (or with --server / WORLD_ROLE=server) no UI is
## built at all; we just start listening.

const TITLE := "Belcher World"
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
var _wave_label: Label
var _banner: Label
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

func _make_label(text: String, size: int, color := Color.WHITE, outline := 0) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
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
	_loading_label = _make_label("Flying in...", 34, GOLD, 6)
	_loading_label.set_anchors_preset(Control.PRESET_CENTER)
	_loading_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_loading_label.grow_vertical = Control.GROW_DIRECTION_BOTH
	_game_screen.add_child(_loading_label)

	# Thin shared overlay: world clock + player count, top center.
	var top := PanelContainer.new()
	top.set_anchors_preset(Control.PRESET_CENTER_TOP)
	top.grow_horizontal = Control.GROW_DIRECTION_BOTH
	top.offset_top = 6
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.04, 0.05, 0.08, 0.6)
	style.set_corner_radius_all(10)
	style.content_margin_left = 14.0
	style.content_margin_right = 14.0
	style.content_margin_top = 4.0
	style.content_margin_bottom = 4.0
	top.add_theme_stylebox_override("panel", style)
	_game_screen.add_child(top)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	top.add_child(row)
	_clock_label = _make_label("", 17, Color.WHITE)
	row.add_child(_clock_label)
	_players_label = _make_label("", 17, Color(1, 1, 1, 0.7))
	row.add_child(_players_label)
	_survival_button = Button.new()
	_survival_button.text = "⚔ Attack!"
	_survival_button.add_theme_font_size_override("font_size", 15)
	_survival_button.tooltip_text = "Start a Grump attack — defend yourselves!"
	_survival_button.pressed.connect(func() -> void:
		if Game.world != null and not Game.world.survival_active:
			Game.world.sv_survival_start.rpc_id(1, 0))
	row.add_child(_survival_button)
	_wave_label = _make_label("", 17, Color("ff6b6b"))
	row.add_child(_wave_label)
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
		_loading_label.visible = false)
	world.survival_changed.connect(_refresh_survival)
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
	if OS.get_environment("WORLD_AUTOTEST_SURVIVAL") == "1":
		get_tree().create_timer(8.0).timeout.connect(func() -> void:
			if Game.world != null:
				Game.world.sv_survival_start.rpc_id(1, 0))
	var forced := OS.get_environment("WORLD_AUTOTEST_BLOCK")
	if forced.is_valid_int():
		var index := Blocks.HOTBAR.find(forced.to_int())
		if index >= 0:
			var pin := Timer.new()
			pin.wait_time = 2.0
			pin.timeout.connect(func() -> void:
				for child in Game.world.players.get_children():
					if child is Player and child.is_local:
						child.hotbar_index = index)
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

func _refresh_survival() -> void:
	if _survival_button == null or Game.world == null:
		return
	_survival_button.visible = not Game.world.survival_active
	_wave_label.text = "Wave %d!" % Game.world.survival_wave \
		if Game.world.survival_active else ""

func _show_banner(text: String) -> void:
	_banner.text = text
	_banner.visible = true
	_banner.modulate.a = 1.0
	var tween := create_tween()
	tween.tween_interval(5.0)
	tween.tween_property(_banner, "modulate:a", 0.0, 1.0)
	tween.tween_callback(func() -> void: _banner.visible = false)

func _on_roster_changed() -> void:
	if _split != null:
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
