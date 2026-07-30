class_name InputSlot
extends RefCounted
## One local player's physical controls: the keyboard (one player, normal
## WASD controls) plus any number of gamepads. Everything is polled directly
## (no InputMap) so slots never fight over actions.
##
##           move        jump    dig        place      picker     spin   zoom     1st person  leave(hold)
## Keyboard  WASD        Space   L-click/G  R-click/F  E          Z / C  X / V    T           Q
## Gamepad   Left stick  A       B          X          D-pad up   R stick ←→ / ↕  Y      Back/Select
##
## Tab / R and the bumpers still quick-cycle the selection; E (or D-pad up)
## opens the full picker with names. In first person the right stick looks
## around; on keyboard the mouse looks. Esc leaves first person.

enum Kind { KEYBOARD_WASD, KEYBOARD_ARROWS, GAMEPAD }

const DEADZONE := 0.25

var kind: Kind
var device: int = -1  # joypad device id when kind == GAMEPAD

func _init(p_kind: Kind, p_device: int = -1) -> void:
	kind = p_kind
	device = p_device

func describe() -> String:
	match kind:
		Kind.KEYBOARD_WASD:
			return "Keyboard WASD"
		Kind.KEYBOARD_ARROWS:
			return "Keyboard Arrows"
		_:
			return "Gamepad %d" % (device + 1)

## Unique key so the same physical device can't join twice. Also the profile
## key each device's character is saved under.
func claim_key() -> String:
	if kind == Kind.GAMEPAD:
		return "pad:%d" % device
	return "kb:%d" % kind

func get_move_vector() -> Vector2:
	var v := Vector2.ZERO
	match kind:
		Kind.KEYBOARD_WASD:
			v.x = _key_axis(KEY_A, KEY_D)
			v.y = _key_axis(KEY_W, KEY_S)
		Kind.KEYBOARD_ARROWS:
			v.x = _key_axis(KEY_LEFT, KEY_RIGHT)
			v.y = _key_axis(KEY_UP, KEY_DOWN)
		Kind.GAMEPAD:
			v.x = Input.get_joy_axis(device, JOY_AXIS_LEFT_X)
			v.y = Input.get_joy_axis(device, JOY_AXIS_LEFT_Y)
			if v.length() < DEADZONE:
				v = Vector2.ZERO
	return v.limit_length(1.0)

## The big friendly "join" button: Space, Enter, or A. In the world it jumps.
func is_primary_pressed() -> bool:
	match kind:
		Kind.KEYBOARD_WASD:
			return Input.is_physical_key_pressed(KEY_SPACE)
		Kind.KEYBOARD_ARROWS:
			return Input.is_physical_key_pressed(KEY_ENTER)
		_:
			return Input.is_joy_button_pressed(device, JOY_BUTTON_A)

## Jump / fly up: A, or LB while airborne (Ian's pad layout).
func is_jump_pressed() -> bool:
	if kind == Kind.GAMEPAD and Input.is_joy_button_pressed(device, JOY_BUTTON_LEFT_SHOULDER):
		return true
	return is_primary_pressed()

## Dig a block, collect a treasure, pet a critter (and zap Grumps).
func is_dig_pressed() -> bool:
	match kind:
		Kind.KEYBOARD_WASD:
			return Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) \
				or Input.is_physical_key_pressed(KEY_G)
		Kind.KEYBOARD_ARROWS:
			return Input.is_physical_key_pressed(KEY_PERIOD)
		_:
			return Input.is_joy_button_pressed(device, JOY_BUTTON_B) \
				or Input.is_joy_button_pressed(device, JOY_BUTTON_RIGHT_SHOULDER)

## Place the selected block.
func is_place_pressed() -> bool:
	match kind:
		Kind.KEYBOARD_WASD:
			return Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT) \
				or Input.is_physical_key_pressed(KEY_F)
		Kind.KEYBOARD_ARROWS:
			return Input.is_physical_key_pressed(KEY_COMMA)
		_:
			return Input.get_joy_axis(device, JOY_AXIS_TRIGGER_RIGHT) > 0.5

## Cycle the hotbar selection. Returns -1, 0 or +1.
func cycle_direction() -> int:
	match kind:
		Kind.KEYBOARD_WASD:
			if Input.is_physical_key_pressed(KEY_TAB):
				return 1
		Kind.GAMEPAD:
			if Input.is_joy_button_pressed(device, JOY_BUTTON_RIGHT_SHOULDER):
				return 1
			if Input.is_joy_button_pressed(device, JOY_BUTTON_LEFT_SHOULDER):
				return -1
	return 0

## Throw an orb (R / middle click / right trigger) — always available.
func is_shoot_pressed() -> bool:
	match kind:
		Kind.KEYBOARD_WASD:
			return Input.is_physical_key_pressed(KEY_R) \
				or Input.is_mouse_button_pressed(MOUSE_BUTTON_MIDDLE)
		Kind.GAMEPAD:
			return Input.get_joy_axis(device, JOY_AXIS_TRIGGER_RIGHT) > 0.5
	return false

## Hotbar slot select: number keys 1-8; D-pad left/right cycles on pads.
## Returns 0-7 direct, -1 none, 10/11 cycle prev/next.
func slot_pick() -> int:
	match kind:
		Kind.KEYBOARD_WASD:
			for i in 8:
				if Input.is_physical_key_pressed(KEY_1 + i):
					return i
		Kind.GAMEPAD:
			if Input.is_joy_button_pressed(device, JOY_BUTTON_DPAD_LEFT):
				return 10
			if Input.is_joy_button_pressed(device, JOY_BUTTON_DPAD_RIGHT):
				return 11
	return -1

## Open the tabbed menu (Esc / Start).
func is_menu_pressed() -> bool:
	match kind:
		Kind.KEYBOARD_WASD:
			return Input.is_physical_key_pressed(KEY_ESCAPE)
		Kind.GAMEPAD:
			return Input.is_joy_button_pressed(device, JOY_BUTTON_START) \
				or Input.is_joy_button_pressed(device, JOY_BUTTON_X)
	return false

## Open/close the block & structure picker (E / D-pad up).
func is_picker_pressed() -> bool:
	match kind:
		Kind.KEYBOARD_WASD:
			return Input.is_physical_key_pressed(KEY_E)
		Kind.GAMEPAD:
			return false  # pads open the menu with X/Start
	return false

## Directional input for navigating the picker grid.
func get_ui_vector() -> Vector2:
	if kind == Kind.GAMEPAD:
		var v := Vector2.ZERO
		if Input.is_joy_button_pressed(device, JOY_BUTTON_DPAD_LEFT):
			v.x = -1.0
		if Input.is_joy_button_pressed(device, JOY_BUTTON_DPAD_RIGHT):
			v.x = 1.0
		if Input.is_joy_button_pressed(device, JOY_BUTTON_DPAD_DOWN):
			v.y = 1.0
		if Input.is_joy_button_pressed(device, JOY_BUTTON_DPAD_UP):
			v.y = -1.0
		if v == Vector2.ZERO:
			v = get_move_vector()
		return v
	return get_move_vector()

## Sprint (Shift on the ground / click the left stick).
func is_sprint_pressed() -> bool:
	match kind:
		Kind.KEYBOARD_WASD:
			return Input.is_physical_key_pressed(KEY_SHIFT)
		Kind.GAMEPAD:
			return Input.is_joy_button_pressed(device, JOY_BUTTON_LEFT_STICK)
	return false

## Descend while flying (Shift / left trigger).
func is_descend_pressed() -> bool:
	match kind:
		Kind.KEYBOARD_WASD:
			return Input.is_physical_key_pressed(KEY_SHIFT)
		Kind.GAMEPAD:
			return Input.get_joy_axis(device, JOY_AXIS_TRIGGER_LEFT) > 0.5
	return false

## Toggle between the isometric view and first person (T / gamepad Y).
func is_view_toggle_pressed() -> bool:
	match kind:
		Kind.KEYBOARD_WASD:
			return Input.is_physical_key_pressed(KEY_T)
		Kind.GAMEPAD:
			return Input.is_joy_button_pressed(device, JOY_BUTTON_Y)
	return false

## First-person look input per frame (gamepad right stick; the keyboard
## looks with the mouse, handled by the player via input events).
func get_look_vector() -> Vector2:
	if kind != Kind.GAMEPAD:
		return Vector2.ZERO
	var v := Vector2(
		Input.get_joy_axis(device, JOY_AXIS_RIGHT_X),
		Input.get_joy_axis(device, JOY_AXIS_RIGHT_Y))
	if v.length() < DEADZONE:
		return Vector2.ZERO
	return v

## Spin the camera a quarter turn. Returns -1, 0 or +1 (caller edge-latches).
func rotate_direction() -> int:
	match kind:
		Kind.KEYBOARD_WASD:
			if Input.is_physical_key_pressed(KEY_Z):
				return -1
			if Input.is_physical_key_pressed(KEY_X):
				return 1
		Kind.KEYBOARD_ARROWS:
			if Input.is_physical_key_pressed(KEY_SEMICOLON):
				return -1
			if Input.is_physical_key_pressed(KEY_APOSTROPHE):
				return 1
		Kind.GAMEPAD:
			var x := Input.get_joy_axis(device, JOY_AXIS_RIGHT_X)
			if x < -0.6:
				return -1
			if x > 0.6:
				return 1
	return 0

## Step the zoom. Returns -1 (out), 0 or +1 (in); caller edge-latches.
func zoom_direction() -> int:
	match kind:
		Kind.KEYBOARD_WASD:
			if Input.is_physical_key_pressed(KEY_C):
				return -1
			if Input.is_physical_key_pressed(KEY_V):
				return 1
		Kind.KEYBOARD_ARROWS:
			if Input.is_physical_key_pressed(KEY_BRACKETLEFT):
				return -1
			if Input.is_physical_key_pressed(KEY_BRACKETRIGHT):
				return 1
		Kind.GAMEPAD:
			if Input.is_joy_button_pressed(device, JOY_BUTTON_DPAD_UP):
				return 1
			if Input.is_joy_button_pressed(device, JOY_BUTTON_DPAD_DOWN):
				return -1
	return 0

## Leave is HELD (not tapped) so a stray press never drops a kid's character.
func is_leave_pressed() -> bool:
	match kind:
		Kind.KEYBOARD_WASD:
			return Input.is_physical_key_pressed(KEY_Q)
		Kind.KEYBOARD_ARROWS:
			return Input.is_physical_key_pressed(KEY_BACKSPACE)
		_:
			return Input.is_joy_button_pressed(device, JOY_BUTTON_BACK)

func _key_axis(neg: Key, pos: Key) -> float:
	var v := 0.0
	if Input.is_physical_key_pressed(neg):
		v -= 1.0
	if Input.is_physical_key_pressed(pos):
		v += 1.0
	return v

## All slots that could join right now (used by the drop-in poller).
## One keyboard player only — the arrows layout confused everyone.
static func candidate_slots() -> Array[InputSlot]:
	var slots: Array[InputSlot] = []
	slots.append(InputSlot.new(Kind.KEYBOARD_WASD))
	for device_id in Input.get_connected_joypads():
		slots.append(InputSlot.new(Kind.GAMEPAD, device_id))
	return slots
