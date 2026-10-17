extends Node
## Sound manager. All sound effects are synthesized at startup and all music is
## generated live by a small step sequencer, so the build ships no recorded or
## licensed audio. Buses: Music, SFX, Voice (announcer stingers).

const RATE := 22050
const POOL := 14

var sfx: Dictionary = {}
var _players: Array = []
var _voice: AudioStreamPlayer
var _music: AudioStreamPlayer
var _playback: AudioStreamGeneratorPlayback
var _rng := RandomNumberGenerator.new()

# Sequencer state
var track_id := ""
var _track: Dictionary = {}
var _transpose := 0
var _sample := 0
var _step := -1
var _spstep := 1000.0
var _bass_f := 0.0
var _bass_ph := 0.0
var _bass_env := 0.0
var _lead_f := 0.0
var _lead_ph := 0.0
var _lead_env := 0.0
var _pad_ph := [0.0, 0.0, 0.0]
var _pad_f := [0.0, 0.0, 0.0]
var _kick_env := 0.0
var _kick_ph := 0.0
var _snare_env := 0.0
var _hat_env := 0.0
var _lp := 0.0
var _noise_seed := 22222

const TRACKS := {
	"menu": {"bpm": 104, "root": 45, "prog": [0, -4, 3, -2], "bass": "1.1.1.1.1.1.1.1.", "kick": "1...1...1...1...", "snare": "....1.......1...", "hat": "..1...1...1...1.", "lead": [0, 7, 12, 7, 3, 7, 12, 15], "lead_rate": 2, "pad": true, "gain": 0.8},
	"select": {"bpm": 118, "root": 47, "prog": [0, 0, -4, -2], "bass": "1..1..1.1..1..1.", "kick": "1.....1.1.......", "snare": "....1.......1...", "hat": "1.1.1.1.1.1.1.1.", "lead": [0, 3, 7, 10, 12, 10, 7, 3], "lead_rate": 2, "pad": true, "gain": 0.8},
	"fight": {"bpm": 148, "root": 40, "prog": [0, 0, -4, -2], "bass": "1.11.11.1.11.1.1", "kick": "1...1...1...1.1.", "snare": "....1.......1...", "hat": "1111111111111111", "lead": [12, 10, 7, 10, 12, 15, 12, 7], "lead_rate": 2, "pad": false, "gain": 0.75},
	"survival": {"bpm": 132, "root": 38, "prog": [0, 1, 0, -2], "bass": "1.1.1.1.1.1.1.1.", "kick": "1..1..1.1..1..1.", "snare": "....1.......1..1", "hat": "1.1.1.1.1.1.1.1.", "lead": [0, 1, 0, 7, 6, 7, 0, 13], "lead_rate": 2, "pad": true, "gain": 0.75},
	"boss": {"bpm": 162, "root": 41, "prog": [0, 1, 6, 5], "bass": "1111111111111111", "kick": "1.1.1.1.1.1.1.1.", "snare": "....1.......1.1.", "hat": "1111111111111111", "lead": [12, 13, 12, 18, 17, 13, 12, 6], "lead_rate": 1, "pad": false, "gain": 0.72},
	"story": {"bpm": 90, "root": 43, "prog": [0, -3, -5, -2], "bass": "1.......1.......", "kick": "1.......1.......", "snare": "........1.......", "hat": "....1.......1...", "lead": [7, 0, 3, 7, 10, 7, 3, 0], "lead_rate": 4, "pad": true, "gain": 0.8},
	"victory": {"bpm": 126, "root": 48, "prog": [0, 5, 7, 0], "bass": "1...1...1...1...", "kick": "1...1...1...1...", "snare": "....1.......1...", "hat": "..1...1...1...1.", "lead": [0, 4, 7, 12, 7, 4, 12, 16], "lead_rate": 2, "pad": true, "gain": 0.8},
}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_make_buses()
	for i in POOL:
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		add_child(p)
		_players.append(p)
	_voice = AudioStreamPlayer.new()
	_voice.bus = "Voice"
	add_child(_voice)
	_music = AudioStreamPlayer.new()
	_music.bus = "Music"
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = RATE
	gen.buffer_length = 0.2
	_music.stream = gen
	add_child(_music)
	_build_sfx()


func _make_buses() -> void:
	for bus_name in ["Music", "SFX", "Voice"]:
		if AudioServer.get_bus_index(bus_name) == -1:
			AudioServer.add_bus()
			var idx := AudioServer.bus_count - 1
			AudioServer.set_bus_name(idx, bus_name)
			AudioServer.set_bus_send(idx, "Master")


func set_volumes(music: float, fx: float, voice: float, mute: bool) -> void:
	_set_bus("Music", music)
	_set_bus("SFX", fx)
	_set_bus("Voice", voice)
	AudioServer.set_bus_mute(0, mute)


func _set_bus(bus_name: String, v: float) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx >= 0:
		AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(0.0001, v)))


func play(id: String, pitch: float = 1.0, vol_db: float = 0.0) -> void:
	if not sfx.has(id):
		return
	var best: AudioStreamPlayer = _players[0]
	for p in _players:
		if not p.playing:
			best = p
			break
	best.stream = sfx[id]
	best.pitch_scale = pitch * _rng.randf_range(0.95, 1.05)
	best.volume_db = vol_db
	best.play()


func announce(id: String) -> void:
	if sfx.has(id):
		_voice.stream = sfx[id]
		_voice.play()


# --- Music -----------------------------------------------------------------------

func play_music(id: String, transpose: int = 0) -> void:
	if id == track_id and transpose == _transpose and _music.playing:
		return
	track_id = id
	_track = TRACKS.get(id, TRACKS["menu"])
	_transpose = transpose
	_sample = 0
	_step = -1
	_spstep = RATE * 60.0 / float(_track["bpm"]) / 4.0
	if not _music.playing:
		_music.play()
	_playback = _music.get_stream_playback()


func stop_music() -> void:
	track_id = ""
	_music.stop()
	_playback = null


func _process(_delta: float) -> void:
	if _playback == null or _track.is_empty():
		return
	var n := _playback.get_frames_available()
	if n <= 0:
		return
	var buf := PackedVector2Array()
	buf.resize(n)
	for i in n:
		var s := _music_sample()
		buf[i] = Vector2(s, s)
	_playback.push_buffer(buf)


func _midi(n: float) -> float:
	return 440.0 * pow(2.0, (n - 69.0) / 12.0)


func _noise() -> float:
	_noise_seed = (_noise_seed * 1103515245 + 12345) & 0x7fffffff
	return float(_noise_seed) / float(0x3fffffff) - 1.0


func _on_step(step: int) -> void:
	var t := _track
	var bar := (step / 16) % (t["prog"] as Array).size()
	var s16 := step % 16
	var root: int = t["root"] + t["prog"][bar] + _transpose
	var bass: String = t["bass"]
	if bass[s16] == "1":
		_bass_f = _midi(root + (12 if s16 % 8 == 6 else 0))
		_bass_env = 1.0
	if (t["kick"] as String)[s16] == "1":
		_kick_env = 1.0
		_kick_ph = 0.0
	if (t["snare"] as String)[s16] == "1":
		_snare_env = 1.0
	if (t["hat"] as String)[s16] == "1":
		_hat_env = 1.0
	var rate: int = t["lead_rate"]
	if s16 % rate == 0:
		var lead: Array = t["lead"]
		var idx := (step / rate) % lead.size()
		_lead_f = _midi(root + 24 + lead[idx])
		_lead_env = 1.0
	if s16 == 0 and t["pad"]:
		_pad_f = [_midi(root + 12), _midi(root + 15), _midi(root + 19)]


func _music_sample() -> float:
	var step := int(float(_sample) / _spstep)
	if step != _step:
		_step = step
		_on_step(step)
	_sample += 1
	var dt := 1.0 / RATE
	var out := 0.0
	# Bass: square wave through a one-pole lowpass.
	_bass_ph = fmod(_bass_ph + _bass_f * dt, 1.0)
	var bsq := 1.0 if _bass_ph < 0.5 else -1.0
	_lp += 0.12 * (bsq - _lp)
	out += _lp * 0.22 * (0.35 + 0.65 * _bass_env)
	_bass_env *= 0.9996
	# Lead: 25% pulse arpeggio.
	_lead_ph = fmod(_lead_ph + _lead_f * dt, 1.0)
	out += (1.0 if _lead_ph < 0.25 else -1.0) * 0.06 * _lead_env
	_lead_env *= 0.99985
	# Pad: soft triangle chord.
	if _track["pad"]:
		for i in 3:
			_pad_ph[i] = fmod(_pad_ph[i] + _pad_f[i] * dt, 1.0)
			out += (absf(_pad_ph[i] * 4.0 - 2.0) - 1.0) * 0.025
	# Drums.
	if _kick_env > 0.001:
		_kick_ph += (45.0 + 110.0 * _kick_env * _kick_env) * dt
		out += sin(_kick_ph * TAU) * 0.5 * _kick_env
		_kick_env *= 0.9988
	if _snare_env > 0.001:
		out += _noise() * 0.16 * _snare_env
		_snare_env *= 0.9982
	if _hat_env > 0.001:
		out += _noise() * 0.05 * _hat_env
		_hat_env *= 0.993
	return clampf(out * float(_track["gain"]), -1.0, 1.0)


# --- Sound effect synthesis --------------------------------------------------------

func _wav(data: PackedFloat32Array) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(data.size() * 2)
	for i in data.size():
		bytes.encode_s16(i * 2, int(clampf(data[i], -1.0, 1.0) * 32000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = bytes
	return w


## Generic voice: tone sweep + noise with envelope and lowpass.
func _synth(dur: float, f0: float, f1: float, wave: String, tone_amp: float, noise_amp: float, decay: float, lp: float = 1.0, vib: float = 0.0) -> PackedFloat32Array:
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var ph := 0.0
	var y := 0.0
	for i in n:
		var k := float(i) / n
		var env := pow(1.0 - k, decay) * minf(1.0, float(i) / 40.0)
		var f := lerpf(f0, f1, k) * (1.0 + vib * sin(float(i) * 0.004))
		ph = fmod(ph + f / RATE, 1.0)
		var tone := 0.0
		match wave:
			"sine": tone = sin(ph * TAU)
			"square": tone = 1.0 if ph < 0.5 else -1.0
			"saw": tone = ph * 2.0 - 1.0
			"tri": tone = absf(ph * 4.0 - 2.0) - 1.0
		var x := tone * tone_amp + _noise() * noise_amp
		y += lp * (x - y)
		out[i] = y * env
	return out


func _mix(a: PackedFloat32Array, b: PackedFloat32Array, gb: float = 1.0) -> PackedFloat32Array:
	var n := maxi(a.size(), b.size())
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		out[i] = (a[i] if i < a.size() else 0.0) + (b[i] if i < b.size() else 0.0) * gb
	return out


func _chord(dur: float, notes: Array, wave: String, decay: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for nt in notes:
		out = _mix(out, _synth(dur, _midi(nt), _midi(nt), wave, 0.22, 0.0, decay, 0.35))
	return out


func _build_sfx() -> void:
	sfx["hit_l"] = _wav(_mix(_synth(0.08, 220, 90, "sine", 0.7, 0.0, 2.0), _synth(0.05, 0, 0, "sine", 0.0, 0.6, 3.0, 0.5)))
	sfx["hit_m"] = _wav(_mix(_synth(0.13, 170, 60, "sine", 0.85, 0.0, 2.0), _synth(0.08, 0, 0, "sine", 0.0, 0.7, 2.5, 0.4)))
	sfx["hit_h"] = _wav(_mix(_synth(0.22, 130, 40, "sine", 1.0, 0.0, 1.6), _synth(0.14, 0, 0, "sine", 0.0, 0.8, 2.0, 0.3)))
	sfx["block"] = _wav(_mix(_synth(0.06, 1100, 700, "square", 0.25, 0.0, 3.0, 0.6), _synth(0.05, 0, 0, "sine", 0.0, 0.4, 4.0, 0.9)))
	sfx["whoosh"] = _wav(_synth(0.16, 0, 0, "sine", 0.0, 0.55, 1.2, 0.08))
	sfx["jump"] = _wav(_synth(0.08, 260, 420, "square", 0.12, 0.0, 2.0, 0.3))
	sfx["land"] = _wav(_synth(0.08, 120, 60, "sine", 0.4, 0.2, 3.0, 0.2))
	sfx["zap"] = _wav(_mix(_synth(0.28, 900, 300, "saw", 0.3, 0.3, 1.5, 0.6, 0.6), _synth(0.28, 1800, 600, "square", 0.1, 0.0, 2.0, 0.5, 1.2)))
	sfx["arrow"] = _wav(_mix(_synth(0.12, 0, 0, "sine", 0.0, 0.4, 1.5, 0.15), _synth(0.18, 420, 380, "tri", 0.35, 0.0, 2.0, 0.6, 0.3)))
	sfx["explode"] = _wav(_mix(_synth(0.6, 90, 30, "sine", 0.8, 0.0, 1.5), _synth(0.6, 0, 0, "sine", 0.0, 0.9, 1.4, 0.12)))
	sfx["beam"] = _wav(_synth(0.36, 620, 560, "saw", 0.35, 0.08, 0.8, 0.3, 0.8))
	sfx["wind"] = _wav(_synth(0.5, 0, 0, "sine", 0.0, 0.6, 0.7, 0.05))
	sfx["sonic"] = _wav(_mix(_synth(0.45, 1200, 1500, "sine", 0.3, 0.0, 0.9, 1.0, 1.5), _synth(0.45, 1320, 1180, "tri", 0.2, 0.05, 0.9, 0.8)))
	sfx["vibe"] = _wav(_mix(_synth(0.38, 220, 160, "sine", 0.5, 0.0, 1.0, 1.0, 3.0), _synth(0.38, 440, 330, "tri", 0.2, 0.05, 1.2, 0.5)))
	sfx["psi"] = _wav(_synth(0.4, 300, 520, "tri", 0.4, 0.02, 1.0, 0.8, 2.0))
	sfx["shot"] = _wav(_mix(_synth(0.07, 0, 0, "sine", 0.0, 0.9, 3.5, 0.7), _synth(0.07, 200, 80, "square", 0.3, 0.0, 3.0, 0.4)))
	sfx["slam"] = _wav(_mix(_synth(0.4, 80, 28, "sine", 1.0, 0.0, 1.4), _synth(0.3, 0, 0, "sine", 0.0, 0.8, 1.8, 0.1)))
	sfx["super"] = _wav(_mix(_synth(0.6, 200, 1200, "saw", 0.25, 0.0, 1.0, 0.5), _synth(0.6, 400, 2400, "sine", 0.2, 0.05, 1.0, 1.0, 0.5)))
	sfx["teleport"] = _wav(_synth(0.22, 1400, 200, "sine", 0.4, 0.05, 1.2, 1.0, 1.0))
	sfx["throw"] = _wav(_mix(_synth(0.15, 0, 0, "sine", 0.0, 0.5, 1.5, 0.1), _synth(0.2, 110, 50, "sine", 0.7, 0.0, 1.5)))
	sfx["static"] = _wav(_synth(0.3, 60, 60, "square", 0.15, 0.6, 1.0, 0.7))
	sfx["ko"] = _wav(_mix(_synth(1.0, 70, 30, "sine", 1.0, 0.0, 1.2), _synth(0.8, 0, 0, "sine", 0.0, 0.6, 1.5, 0.06)))
	sfx["menu_move"] = _wav(_synth(0.035, 880, 880, "square", 0.15, 0.0, 2.0, 0.5))
	sfx["menu_ok"] = _wav(_mix(_synth(0.06, 660, 660, "square", 0.15, 0.0, 1.5, 0.5), _synth(0.12, 990, 990, "square", 0.12, 0.0, 1.5, 0.5)))
	sfx["menu_back"] = _wav(_synth(0.08, 440, 330, "square", 0.15, 0.0, 1.5, 0.5))
	sfx["bell"] = _wav(_mix(_synth(1.0, 880, 880, "sine", 0.4, 0.0, 2.0), _synth(1.0, 1320, 1320, "sine", 0.2, 0.0, 2.5)))
	# Announcer stingers (no recorded voice): brass-like chords on the Voice bus.
	sfx["round"] = _wav(_chord(0.7, [52, 59, 64], "saw", 1.4))
	sfx["fight"] = _wav(_mix(_chord(0.8, [57, 64, 69, 73], "saw", 1.2), _synth(0.3, 0, 0, "sine", 0.0, 0.3, 2.0, 0.2)))
	sfx["ko_voice"] = _wav(_chord(1.2, [40, 47, 52, 55], "saw", 1.0))
	sfx["win"] = _wav(_chord(1.0, [60, 64, 67, 72], "saw", 1.2))
	sfx["super_voice"] = _wav(_chord(0.6, [62, 69, 74], "square", 1.5))
