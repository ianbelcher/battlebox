class_name BotSlot
extends InputSlot
## Scripted "player" for smoke tests (WORLD_AUTOTEST=1): wanders, hops,
## digs and places on a schedule. Never touches real input devices.

var bot_index := 0

func _init(p_index: int) -> void:
	super(Kind.GAMEPAD, -100 - p_index)
	bot_index = p_index

func describe() -> String:
	return "Bot %d" % bot_index

func claim_key() -> String:
	return "bot:%d" % bot_index

func _t() -> float:
	return Time.get_ticks_msec() / 1000.0

func get_move_vector() -> Vector2:
	# A new heading every couple of seconds, unique per bot.
	var step := floori(_t() / 1.7) + bot_index * 31
	var angle := WorldGen.hash01(step, bot_index, 5) * TAU
	return Vector2(cos(angle), sin(angle)) * 0.9

func is_primary_pressed() -> bool:
	# Normal hops, plus an occasional quick double-tap to toggle flight.
	var fly_phase := fmod(_t() * 0.027 + bot_index * 0.45, 1.0)
	if fly_phase < 0.006 or (fly_phase > 0.009 and fly_phase < 0.015):
		return true
	return fmod(_t() * 0.31 + bot_index * 0.4, 1.0) > 0.92

func is_descend_pressed() -> bool:
	return fmod(_t() * 0.09 + bot_index * 0.6, 1.0) < 0.15

func is_dig_pressed() -> bool:
	return fmod(_t() * 0.2 + bot_index * 0.7, 1.0) < 0.06

func is_place_pressed() -> bool:
	var phase := fmod(_t() * 0.2 + bot_index * 0.7, 1.0)
	return phase > 0.5 and phase < 0.56

func cycle_direction() -> int:
	return 1 if fmod(_t() * 0.11 + bot_index, 1.0) < 0.02 else 0

func rotate_direction() -> int:
	# A quarter spin roughly every 12s, staggered per bot.
	return 1 if fmod(_t() * 0.08 + bot_index * 0.5, 1.0) < 0.015 else 0

func is_view_toggle_pressed() -> bool:
	# Hop in and out of first person every ~45s.
	return fmod(_t() * 0.022 + bot_index * 0.4, 1.0) < 0.01

func get_look_vector() -> Vector2:
	# Slow look wander so first-person frames aren't all the horizon.
	return Vector2(sin(_t() * 0.4 + bot_index), sin(_t() * 0.23 + bot_index * 2.0) * 0.5) * 0.4

func zoom_direction() -> int:
	var phase := fmod(_t() * 0.05 + bot_index * 0.3, 1.0)
	if phase < 0.01:
		return 1
	if phase > 0.5 and phase < 0.51:
		return -1
	return 0

func is_leave_pressed() -> bool:
	return false

func is_shoot_pressed() -> bool:
	return fmod(_t() * 0.15 + bot_index * 0.55, 1.0) < 0.03
