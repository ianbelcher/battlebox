class_name FakePad
extends InputSlot
## A gamepad that isn't there (WORLD_FAKE_PADS=<n>). Everything except the
## button reads comes from the real InputSlot, so the join path, the claim
## keys and the twin-pad divergence check all run exactly as they would
## with hardware — which BotSlot-driven tests never do.

var pad_index := 0

func _init(p_index: int) -> void:
	super(InputSlot.Kind.GAMEPAD, 900 + p_index)
	pad_index = p_index

func describe() -> String:
	return "Fake pad %d" % (pad_index + 1)

## Real pads key off the joypad GUID; there isn't one, so keep it stable
## and distinct per fake pad.
func claim_key() -> String:
	return "fakepad:%d" % pad_index

func legacy_claim_key() -> String:
	return claim_key()

## Holds A, which is the join button — that is the whole point.
func is_primary_pressed() -> bool:
	return true

## WORLD_FAKE_PAD_HOLD=lb|rb: pretend that shoulder button is held down, so
## a headless run can prove LB still only jumps and never cycles the hotbar.
static func _hold() -> String:
	return OS.get_environment("WORLD_FAKE_PAD_HOLD")

func is_jump_pressed() -> bool:
	return _hold() == "lb" or super()

func cycle_direction() -> int:
	# Mirrors InputSlot's gamepad branch: RB only.
	return 1 if _hold() == "rb" else 0

func tab_cycle_direction() -> int:
	match _hold():
		"rb": return 1
		"lb": return -1
	return 0
