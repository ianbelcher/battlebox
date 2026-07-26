extends Node
## Sound effects synthesized at startup so the project needs no audio assets.
## Soft bell/marimba tones (sines with gentle harmonics and exponential decay)
## plus looping nature ambients that follow the world clock.

const RATE := 22050
const PLAYER_POOL := 8

const TIMBRES := {
	"bell": {"ring": 0.9, "h2": 0.35, "h3": 0.12},
	"soft": {"ring": 0.35, "h2": 0.2, "h3": 0.05},
	"thump": {"ring": 0.2, "h2": 0.0, "h3": 0.0},
}

var _streams: Dictionary = {}
var _players: Array[AudioStreamPlayer] = []
var _next := 0
var _ambients: Dictionary = {}
var _ambient_player: AudioStreamPlayer
var _current_ambient := ""

func _ready() -> void:
	for i in PLAYER_POOL:
		var player := AudioStreamPlayer.new()
		add_child(player)
		_players.append(player)
	_streams = {
		"join": _notes([[660, 0.09], [880, 0.1]], 0.5, "soft"),
		"tick": _notes([[1047, 0.1]], 0.35, "soft"),
		"jump": _notes([[440, 0.05], [660, 0.07]], 0.35, "soft"),
		"land": _notes([[180, 0.08]], 0.5, "thump"),
		"dig": _notes([[150, 0.09]], 0.6, "thump"),
		"place": _notes([[520, 0.06], [420, 0.08]], 0.45, "soft"),
		"collect": _notes([[880, 0.07], [1175, 0.08], [1568, 0.12]], 0.5),
		"pet": _notes([[988, 0.07], [1319, 0.09], [1760, 0.14]], 0.45, "soft"),
		"pop": _notes([[988, 0.06]], 0.45, "soft"),
		"splash": _notes([[740, 0.04], [520, 0.05], [620, 0.06]], 0.4, "soft"),
	}
	_ambient_player = AudioStreamPlayer.new()
	_ambient_player.volume_db = -16.0
	add_child(_ambient_player)
	_ambients = {
		"crickets": _crickets(8),
		"birds": _birds(),
	}

const STABLE_PITCH := ["join", "collect", "pet"]

func play(clip: String, volume_db := 0.0, pitch := 0.0) -> void:
	if _players.is_empty() or not _streams.has(clip):
		return
	var player := _players[_next]
	_next = (_next + 1) % _players.size()
	player.stream = _streams[clip]
	player.volume_db = volume_db
	if pitch > 0.0:
		player.pitch_scale = pitch
	else:
		player.pitch_scale = 1.0 if clip in STABLE_PITCH else randf_range(0.9, 1.1)
	player.play()

func play_ambient(clip: String) -> void:
	if clip == _current_ambient:
		return
	_current_ambient = clip
	if _ambient_player == null:
		return
	if clip.is_empty() or not _ambients.has(clip):
		_ambient_player.stop()
		return
	_ambient_player.stream = _ambients[clip]
	_ambient_player.play()

func _notes(notes: Array, volume: float, timbre := "bell") -> AudioStreamWAV:
	var spec: Dictionary = TIMBRES[timbre]
	var ring: float = spec.ring
	var total := ring
	for note: Array in notes:
		total += note[1]
	var count := int(total * RATE)
	var buf := PackedFloat32Array()
	buf.resize(count)
	var start := 0.0
	for note: Array in notes:
		if note[0] > 0.0:
			_render_note(buf, start, note[0], spec)
		start += note[1]
	return _to_wav(buf, volume)

func _to_wav(buf: PackedFloat32Array, volume: float, loop := false) -> AudioStreamWAV:
	var count := buf.size()
	var peak := 0.0001
	for sample in buf:
		peak = maxf(peak, absf(sample))
	var data := PackedByteArray()
	data.resize(count * 2)
	for i in count:
		data.encode_s16(i * 2, int(clampf(buf[i] / peak * volume, -1.0, 1.0) * 32767.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.stereo = false
	wav.data = data
	if loop:
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		wav.loop_end = count
	return wav

func _render_note(buf: PackedFloat32Array, start_s: float, freq: float, spec: Dictionary) -> void:
	var ring: float = spec.ring
	var h2: float = spec.h2
	var h3: float = spec.h3
	var start_i := int(start_s * RATE)
	var length := mini(int(ring * RATE), buf.size() - start_i)
	var decay := 5.0 / ring
	var is_thump: bool = h2 == 0.0 and h3 == 0.0
	var w := TAU * freq
	for s in length:
		var t := float(s) / RATE
		var env := exp(-t * decay) * minf(1.0, s / (0.003 * RATE))
		var value: float
		if is_thump:
			value = sin(w * t * (1.0 + 0.6 * exp(-t * 25.0)))
		else:
			value = sin(w * t) \
				+ 0.4 * sin(w * 1.006 * t) \
				+ h2 * sin(w * 2.0 * t) * exp(-t * decay * 0.8) \
				+ h3 * sin(w * 3.01 * t) * exp(-t * decay * 1.6)
		buf[start_i + s] += value * env

func _crickets(chirp_count: int) -> AudioStreamWAV:
	var seconds := 4.0
	var buf := PackedFloat32Array()
	buf.resize(int(seconds * RATE))
	for chirp in chirp_count:
		var start := randf() * (seconds - 0.4)
		var freq := 4100.0 + randf() * 500.0
		for pulse in 3:
			var pulse_start := int((start + pulse * 0.07) * RATE)
			var pulse_len := int(0.035 * RATE)
			for i in pulse_len:
				var t := float(i) / RATE
				var env := sin(PI * i / pulse_len)
				if pulse_start + i < buf.size():
					buf[pulse_start + i] += sin(TAU * freq * t) * env * 0.4
	return _to_wav(buf, 0.5, true)

func _birds() -> AudioStreamWAV:
	var seconds := 4.0
	var buf := PackedFloat32Array()
	buf.resize(int(seconds * RATE))
	for chirp in 6:
		var start := randf() * (seconds - 0.3)
		var f_start := 1900.0 + randf() * 900.0
		var f_end := f_start * (0.75 + randf() * 0.5)
		var chirp_len := int((0.09 + randf() * 0.08) * RATE)
		var chirp_start := int(start * RATE)
		var phase := 0.0
		for i in chirp_len:
			var frac := float(i) / chirp_len
			phase += TAU * lerpf(f_start, f_end, frac) / RATE
			var env := sin(PI * frac)
			if chirp_start + i < buf.size():
				buf[chirp_start + i] += sin(phase) * env * 0.5
	return _to_wav(buf, 0.4, true)
