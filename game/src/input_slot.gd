class_name InputSlot
extends RefCounted
## One local player's physical controls. Up to four of these per machine:
## two keyboard layouts plus any number of gamepads. Everything is polled
## directly (no InputMap) so slots never fight over actions.
##
##                 move        jump    dig/collect  place  cycle block  leave (hold)
## Keyboard WASD   WASD        Space   E            F      Tab / R      Q
## Keyboard Arrows Arrows      Enter   .            ,      Right Shift  Backspace
## Gamepad         Left stick  A       B            X      Y / bumpers  Back/Select

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
			if Input.is_joy_button_pressed(device, JOY_BUTTON_DPAD_LEFT):
				v.x = -1.0
			if Input.is_joy_button_pressed(device, JOY_BUTTON_DPAD_RIGHT):
				v.x = 1.0
			if Input.is_joy_button_pressed(device, JOY_BUTTON_DPAD_UP):
				v.y = -1.0
			if Input.is_joy_button_pressed(device, JOY_BUTTON_DPAD_DOWN):
				v.y = 1.0
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

func is_jump_pressed() -> bool:
	return is_primary_pressed()

## Dig a block, collect a treasure, pet a critter.
func is_dig_pressed() -> bool:
	match kind:
		Kind.KEYBOARD_WASD:
			return Input.is_physical_key_pressed(KEY_E)
		Kind.KEYBOARD_ARROWS:
			return Input.is_physical_key_pressed(KEY_PERIOD)
		_:
			return Input.is_joy_button_pressed(device, JOY_BUTTON_B)

## Place the selected block.
func is_place_pressed() -> bool:
	match kind:
		Kind.KEYBOARD_WASD:
			return Input.is_physical_key_pressed(KEY_F)
		Kind.KEYBOARD_ARROWS:
			return Input.is_physical_key_pressed(KEY_COMMA)
		_:
			return Input.is_joy_button_pressed(device, JOY_BUTTON_X)

## Cycle the hotbar selection. Returns -1, 0 or +1.
func cycle_direction() -> int:
	match kind:
		Kind.KEYBOARD_WASD:
			if Input.is_physical_key_pressed(KEY_TAB):
				return 1
			if Input.is_physical_key_pressed(KEY_R):
				return -1
		Kind.KEYBOARD_ARROWS:
			if Input.is_physical_key_pressed(KEY_SHIFT) \
					and not Input.is_physical_key_pressed(KEY_LEFT):
				return 1
		Kind.GAMEPAD:
			if Input.is_joy_button_pressed(device, JOY_BUTTON_RIGHT_SHOULDER) \
					or Input.is_joy_button_pressed(device, JOY_BUTTON_Y):
				return 1
			if Input.is_joy_button_pressed(device, JOY_BUTTON_LEFT_SHOULDER):
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
static func candidate_slots() -> Array[InputSlot]:
	var slots: Array[InputSlot] = []
	slots.append(InputSlot.new(Kind.KEYBOARD_WASD))
	slots.append(InputSlot.new(Kind.KEYBOARD_ARROWS))
	for device_id in Input.get_connected_joypads():
		slots.append(InputSlot.new(Kind.GAMEPAD, device_id))
	return slots
