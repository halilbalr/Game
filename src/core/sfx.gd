extends Node
## Autoload "Sfx": every sound in the game, synthesised at start-up.
##
## Nothing is recorded: bronze is a handful of inharmonic partials, a voice is
## a pulse train through two formant filters, the lyre is a plucked-string
## model. The bank is built on a worker thread so the menu appears at once;
## a sound asked for before it exists is simply skipped.

const RATE := 22050
const POOL_3D := 14
const POOL_2D := 5

var _bank: Dictionary = {}
var _ready_flag: bool = false
var _thread: Thread
var _players_3d: Array[AudioStreamPlayer3D] = []
var _players_2d: Array[AudioStreamPlayer] = []
var _next_3d: int = 0
var _next_2d: int = 0
var _ambience_a: AudioStreamPlayer
var _ambience_b: AudioStreamPlayer
var _music: AudioStreamPlayer
var _want_ambience: StringName = &""
var _want_music: StringName = &""
var _playing_ambience: StringName = &""
var _playing_music: StringName = &""
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i in POOL_3D:
		var p := AudioStreamPlayer3D.new()
		p.unit_size = 7.0
		p.max_distance = 80.0
		p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		add_child(p)
		_players_3d.append(p)
	for i in POOL_2D:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_players_2d.append(p)
	_ambience_a = AudioStreamPlayer.new()
	_ambience_b = AudioStreamPlayer.new()
	_music = AudioStreamPlayer.new()
	for p: AudioStreamPlayer in [_ambience_a, _ambience_b, _music]:
		p.volume_db = -60.0
		add_child(p)
	_rng.seed = 2401
	if DisplayServer.get_name() == "headless":
		return
	_thread = Thread.new()
	_thread.start(_build_bank)


func _exit_tree() -> void:
	if _thread != null and _thread.is_started():
		_thread.wait_to_finish()


func _process(_delta: float) -> void:
	if not _ready_flag:
		return
	if _want_ambience != _playing_ambience:
		_playing_ambience = _want_ambience
		_crossfade(_want_ambience)
	if _want_music != _playing_music:
		_playing_music = _want_music
		_music.stop()
		if _bank.has(_want_music):
			_music.stream = _bank[_want_music]
			_music.volume_db = -13.0
			_music.play()


func _crossfade(id: StringName) -> void:
	var old := _ambience_a if _ambience_a.playing else _ambience_b
	var fresh := _ambience_b if old == _ambience_a else _ambience_a
	var tw := create_tween()
	tw.set_parallel(true)
	if old.playing:
		tw.tween_property(old, "volume_db", -60.0, 2.0)
		tw.chain().tween_callback(old.stop)
	if _bank.has(id):
		fresh.stream = _bank[id]
		fresh.volume_db = -60.0
		fresh.play()
		tw.tween_property(fresh, "volume_db", -9.0, 2.0)


## Plays a named sound at a world position.
func play_at(id: StringName, pos: Vector3, volume_db: float = 0.0) -> void:
	if not _ready_flag or not _bank.has(id):
		return
	var p := _players_3d[_next_3d]
	_next_3d = (_next_3d + 1) % POOL_3D
	p.stream = _bank[id]
	p.global_position = pos
	p.volume_db = volume_db
	p.pitch_scale = randf_range(0.93, 1.07)
	p.play()


## Plays a named sound with no position (interface, the player's own body).
func play(id: StringName, volume_db: float = 0.0) -> void:
	if not _ready_flag or not _bank.has(id):
		return
	var p := _players_2d[_next_2d]
	_next_2d = (_next_2d + 1) % POOL_2D
	p.stream = _bank[id]
	p.volume_db = volume_db
	p.pitch_scale = randf_range(0.95, 1.05)
	p.play()


## Starts a named ambience loop, cross-fading from any other ("" for silence).
func ambience(id: StringName) -> void:
	_want_ambience = id


## Starts a named piece of music ("" stops it).
func music(id: StringName) -> void:
	_want_music = id


# --- synthesis -------------------------------------------------------------------

func _buf(seconds: float) -> PackedFloat32Array:
	var b := PackedFloat32Array()
	b.resize(int(seconds * RATE))
	return b


func _noise() -> float:
	return _rng.randf() * 2.0 - 1.0


## Adds a decaying sine partial.
func _partial(b: PackedFloat32Array, at: float, freq: float, amp: float, decay: float, sweep: float = 0.0) -> void:
	var start := int(at * RATE)
	var n := mini(b.size() - start, int(decay * 6.0 * RATE))
	var phase := 0.0
	for i in n:
		var t := float(i) / RATE
		phase += (freq + sweep * t) / RATE
		b[start + i] += sin(phase * TAU) * amp * exp(-t / decay)


## Adds low-passed noise with an attack-decay envelope.
func _burst(b: PackedFloat32Array, at: float, amp: float, attack: float, decay: float, cutoff: float, cutoff_end: float = -1.0) -> void:
	var start := int(at * RATE)
	var n := mini(b.size() - start, int((attack + decay * 6.0) * RATE))
	var y := 0.0
	if cutoff_end < 0.0:
		cutoff_end = cutoff
	for i in n:
		var t := float(i) / RATE
		var k := float(i) / maxf(n, 1.0)
		var a := clampf(lerpf(cutoff, cutoff_end, k) / (RATE * 0.5), 0.001, 1.0)
		y += a * (_noise() - y)
		var env := (t / attack) if t < attack else exp(-(t - attack) / decay)
		b[start + i] += y * amp * env


## Adds a voiced sound: a pulse train through two formants.
func _voice(b: PackedFloat32Array, at: float, dur: float, f0a: float, f0b: float, f1: float, f2: float, amp: float, breath: float = 0.15) -> void:
	var start := int(at * RATE)
	var n := mini(b.size() - start, int(dur * RATE))
	var phase := 0.0
	var y1a := 0.0
	var y1b := 0.0
	var y2a := 0.0
	var y2b := 0.0
	var r1 := 0.965
	var r2 := 0.955
	var c1 := -2.0 * r1 * cos(TAU * f1 / RATE)
	var c2 := -2.0 * r2 * cos(TAU * f2 / RATE)
	var jitter := 0.0
	for i in n:
		var k := float(i) / n
		jitter = lerpf(jitter, _noise(), 0.02)
		phase += lerpf(f0a, f0b, k) * (1.0 + jitter * 0.06) / RATE
		var saw := 2.0 * (phase - floorf(phase)) - 1.0
		var src := saw * 0.8 + _noise() * breath
		var o1 := src * (1.0 - r1) * 2.2 - c1 * y1a - r1 * r1 * y1b
		y1b = y1a
		y1a = o1
		var o2 := src * (1.0 - r2) * 2.2 - c2 * y2a - r2 * r2 * y2b
		y2b = y2a
		y2a = o2
		var env := minf(k * 14.0, 1.0) * minf((1.0 - k) * 5.0, 1.0)
		b[start + i] += (o1 + o2 * 0.6) * amp * env


## Adds a plucked string (Karplus-Strong).
func _pluck(b: PackedFloat32Array, at: float, freq: float, amp: float, sustain: float = 0.996) -> void:
	var start := int(at * RATE)
	var period := maxi(int(RATE / freq), 2)
	var line := PackedFloat32Array()
	line.resize(period)
	for i in period:
		line[i] = _noise()
	# Soften the pluck.
	for i in range(1, period):
		line[i] = line[i] * 0.6 + line[i - 1] * 0.4
	var n := mini(b.size() - start, int(2.6 * RATE))
	var idx := 0
	for i in n:
		var nxt := (idx + 1) % period
		var v := (line[idx] + line[nxt]) * 0.5 * sustain
		line[idx] = v
		b[start + i] += v * amp
		idx = nxt


func _bronze(b: PackedFloat32Array, at: float, amp: float, decay: float, pitch: float = 1.0) -> void:
	# Inharmonic partials of a struck plate.
	for part: Array in [[812.0, 1.0], [1371.0, 0.7], [2203.0, 0.55], [3154.0, 0.4], [4480.0, 0.25], [5930.0, 0.15]]:
		_partial(b, at, (part[0] as float) * pitch * _rng.randf_range(0.97, 1.03), amp * (part[1] as float) * 0.3,
			decay * _rng.randf_range(0.6, 1.1))
	_burst(b, at, amp * 0.6, 0.001, 0.012, 9000.0)


func _to_stream(b: PackedFloat32Array, loop: bool = false, gain: float = 1.0) -> AudioStreamWAV:
	var peak := 0.001
	for v in b:
		peak = maxf(peak, absf(v))
	var scale := gain * 0.92 / peak
	var n := b.size()
	if loop:
		# Blend the tail into the head so the loop has no seam.
		var fade := mini(int(0.4 * RATE), n / 4)
		for i in fade:
			var k := float(i) / fade
			b[i] = b[i] * k + b[n - fade + i] * (1.0 - k)
		n -= fade
	var bytes := PackedByteArray()
	bytes.resize(n * 2)
	for i in n:
		bytes.encode_s16(i * 2, int(clampf(b[i] * scale, -1.0, 1.0) * 32767.0))
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = RATE
	s.stereo = false
	s.data = bytes
	if loop:
		s.loop_mode = AudioStreamWAV.LOOP_FORWARD
		s.loop_begin = 0
		s.loop_end = n
	return s


func _mix(dst: PackedFloat32Array, src: PackedFloat32Array, at: float, amp: float) -> void:
	var start := int(at * RATE)
	var n := mini(src.size(), dst.size() - start)
	for i in n:
		dst[start + i] += src[i] * amp


func _lowpass(b: PackedFloat32Array, cutoff: float) -> void:
	var a := clampf(cutoff / (RATE * 0.5), 0.001, 1.0)
	var y := 0.0
	for i in b.size():
		y += a * (b[i] - y)
		b[i] = y


func _build_bank() -> void:
	var t0 := Time.get_ticks_msec()
	var bank: Dictionary = {}
	var b: PackedFloat32Array

	b = _buf(0.34)
	_burst(b, 0.0, 1.0, 0.12, 0.05, 900.0, 3800.0)
	bank[&"whoosh"] = _to_stream(b, false, 0.5)

	b = _buf(0.3)
	_partial(b, 0.0, 95.0, 1.0, 0.05, -160.0)
	_burst(b, 0.0, 0.8, 0.002, 0.03, 1400.0, 500.0)
	_burst(b, 0.02, 0.4, 0.01, 0.05, 2600.0)
	var hit := b
	bank[&"hit"] = _to_stream(b)

	b = _buf(0.5)
	_partial(b, 0.0, 150.0, 1.0, 0.05, -200.0)
	_burst(b, 0.0, 0.7, 0.001, 0.035, 1800.0)
	_bronze(b, 0.0, 0.5, 0.09, 0.8)
	var block := b
	bank[&"block"] = _to_stream(b)

	b = _buf(0.9)
	_bronze(b, 0.0, 1.0, 0.2)
	var clang := b
	bank[&"clang"] = _to_stream(b, false, 0.8)

	b = _buf(0.35)
	_partial(b, 0.0, 72.0, 1.0, 0.07, -90.0)
	_burst(b, 0.0, 0.5, 0.003, 0.05, 700.0)
	bank[&"thud"] = _to_stream(b, false, 0.8)

	b = _buf(0.3)
	_burst(b, 0.0, 0.8, 0.004, 0.035, 2600.0, 600.0)
	_partial(b, 0.0, 80.0, 0.6, 0.05)
	bank[&"stab"] = _to_stream(b, false, 0.55)

	b = _buf(0.3)
	_voice(b, 0.0, 0.2, 150.0, 105.0, 620.0, 1150.0, 1.0, 0.3)
	var grunt := b
	bank[&"grunt"] = _to_stream(b, false, 0.6)

	b = _buf(0.45)
	_voice(b, 0.0, 0.34, 170.0, 110.0, 700.0, 1250.0, 1.0, 0.35)
	bank[&"hurt"] = _to_stream(b, false, 0.7)

	b = _buf(1.1)
	_voice(b, 0.0, 0.9, 210.0, 85.0, 760.0, 1180.0, 1.0, 0.3)
	var death := b
	bank[&"death"] = _to_stream(b, false, 0.8)

	b = _buf(0.7)
	_voice(b, 0.0, 0.5, 190.0, 250.0, 520.0, 1750.0, 1.0, 0.2)
	var shout := b
	bank[&"shout"] = _to_stream(b, false, 0.9)

	b = _buf(0.14)
	_burst(b, 0.0, 1.0, 0.004, 0.02, 1100.0, 400.0)
	_partial(b, 0.0, 60.0, 0.5, 0.03)
	bank[&"step"] = _to_stream(b, false, 0.6)

	b = _buf(0.25)
	_partial(b, 0.0, 420.0, 0.8, 0.03)
	_burst(b, 0.0, 0.6, 0.001, 0.01, 5000.0)
	bank[&"pickup"] = _to_stream(b, false, 0.5)

	b = _buf(2.2)
	_pluck(b, 0.0, 329.6, 0.8)
	_pluck(b, 0.22, 493.9, 0.7)
	bank[&"objective"] = _to_stream(b, false, 0.55)

	# The horn of the watch: a reed-bright tone with a slow swell.
	b = _buf(2.4)
	var horn_phase := 0.0
	var hy := 0.0
	for i in b.size():
		var t := float(i) / RATE
		horn_phase += (164.0 + 3.0 * sin(t * 5.0)) / RATE
		var saw := 2.0 * (horn_phase - floorf(horn_phase)) - 1.0
		hy += 0.16 * (saw - hy)
		b[i] = hy * minf(t * 3.0, 1.0) * minf((2.4 - t) * 2.0, 1.0)
	var horn := b
	bank[&"horn"] = _to_stream(b, false, 0.8)

	b = _buf(1.5)
	for k in 2:
		var ph := 0.0
		var ay := 0.0
		var start := int(k * 0.7 * RATE)
		for i in int(0.55 * RATE):
			var t := float(i) / RATE
			ph += 262.0 / RATE
			var saw := 2.0 * (ph - floorf(ph)) - 1.0
			ay += 0.25 * (saw - ay)
			b[start + i] = ay * minf(t * 12.0, 1.0) * minf((0.55 - t) * 8.0, 1.0)
	bank[&"alarm"] = _to_stream(b, false, 0.7)

	b = _buf(1.6)
	_burst(b, 0.0, 0.6, 0.5, 0.25, 500.0, 900.0)
	_partial(b, 1.05, 110.0, 1.0, 0.08, -60.0)
	_burst(b, 1.05, 0.7, 0.002, 0.05, 900.0)
	bank[&"bar"] = _to_stream(b, false, 0.8)

	# Gate hinges: a slow stick-slip groan.
	b = _buf(3.2)
	var gp := 0.0
	var gy := 0.0
	for i in b.size():
		var t := float(i) / RATE
		var f := 52.0 + 30.0 * sin(t * 1.7) + 14.0 * sin(t * 6.3)
		gp += f / RATE
		var saw := 2.0 * (gp - floorf(gp)) - 1.0
		gy += 0.3 * (saw * (0.6 + 0.4 * _noise()) - gy)
		b[i] = gy * minf(t * 2.0, 1.0) * minf((3.2 - t) * 1.5, 1.0) * (0.7 + 0.3 * sin(t * 9.0))
	_burst(b, 2.9, 0.9, 0.002, 0.06, 700.0)
	bank[&"gate"] = _to_stream(b, false, 0.8)

	b = _buf(1.3)
	for k in 3:
		_partial(b, k * 0.36, 185.0, 1.0, 0.035, -40.0)
		_burst(b, k * 0.36, 0.5, 0.001, 0.012, 2400.0)
	bank[&"knock"] = _to_stream(b, false, 0.8)

	b = _buf(1.2)
	_burst(b, 0.0, 0.5, 0.3, 0.12, 700.0, 1400.0)
	_partial(b, 0.75, 130.0, 1.0, 0.06, -50.0)
	bank[&"hatch"] = _to_stream(b, false, 0.7)

	b = _buf(1.4)
	_burst(b, 0.0, 1.0, 0.25, 0.3, 300.0, 1200.0)
	bank[&"fire"] = _to_stream(b, false, 0.8)

	b = _buf(4.0)
	_burst(b, 0.0, 1.0, 0.004, 0.05, 5000.0, 800.0)
	_burst(b, 0.03, 1.0, 0.15, 0.9, 160.0, 70.0)
	_burst(b, 0.6, 0.6, 0.3, 0.7, 120.0, 60.0)
	bank[&"thunder"] = _to_stream(b)

	b = _buf(0.6)
	_bronze(b, 0.0, 0.5, 0.12, 1.3)
	_partial(b, 0.0, 120.0, 0.5, 0.04)
	bank[&"helmet"] = _to_stream(b, false, 0.5)

	# --- ambience loops ---
	# Night: crickets over a breath of wind.
	b = _buf(9.0)
	var wy := 0.0
	for i in b.size():
		var t := float(i) / RATE
		wy += 0.02 * (_noise() - wy)
		b[i] = wy * (1.2 + 0.8 * sin(t * 0.7) + 0.4 * sin(t * 1.9 + 1.0))
	for k in 46:
		var at := _rng.randf() * 8.3
		var f := _rng.randf_range(3900.0, 4700.0)
		var amp := _rng.randf_range(0.01, 0.035)
		var start := int(at * RATE)
		for i in int(0.5 * RATE):
			var t := float(i) / RATE
			b[start + i] += sin(TAU * f * t) * amp * maxf(0.0, sin(TAU * 21.0 * t)) * minf(t * 20.0, 1.0) * minf((0.5 - t) * 20.0, 1.0)
	bank[&"night"] = _to_stream(b, true, 0.5)

	# Day: wind and cicadas.
	b = _buf(9.0)
	wy = 0.0
	var cy := 0.0
	for i in b.size():
		var t := float(i) / RATE
		wy += 0.03 * (_noise() - wy)
		cy += 0.7 * (_noise() - cy)
		var cic := (_noise() - cy) * 0.02 * (0.5 + 0.5 * sin(TAU * 46.0 * t)) * (0.6 + 0.4 * sin(t * 0.9))
		b[i] = wy * (1.0 + 0.7 * sin(t * 0.6)) + cic
	bank[&"day"] = _to_stream(b, true, 0.45)

	# The feast heard through the planks: muffled voices, a drum, a lyre.
	b = _buf(10.0)
	for k in 60:
		var at := _rng.randf() * 9.0
		_voice(b, at, _rng.randf_range(0.25, 0.7), _rng.randf_range(110.0, 220.0), _rng.randf_range(100.0, 240.0),
			_rng.randf_range(450.0, 800.0), _rng.randf_range(1000.0, 1700.0), _rng.randf_range(0.15, 0.4), 0.2)
	for k in 20:
		_partial(b, k * 0.5, 82.0, 0.5, 0.06, -30.0)
	for k in 10:
		_pluck(b, _rng.randf() * 7.0, [164.8, 196.0, 220.0, 246.9, 293.7][k % 5], 0.25)
	_lowpass(b, 650.0)
	bank[&"feast"] = _to_stream(b, true, 0.55)

	# Battle: bronze, shields, voices, over the roar of many men.
	b = _buf(10.0)
	var ry := 0.0
	for i in b.size():
		var t := float(i) / RATE
		ry += 0.05 * (_noise() - ry)
		b[i] = ry * (2.2 + 0.8 * sin(t * 1.3) + 0.5 * sin(t * 3.1))
	for k in 34:
		_mix(b, clang, _rng.randf() * 9.0, _rng.randf_range(0.02, 0.07))
	for k in 30:
		_mix(b, block, _rng.randf() * 9.3, _rng.randf_range(0.05, 0.14))
	for k in 24:
		_mix(b, hit, _rng.randf() * 9.5, _rng.randf_range(0.05, 0.12))
	for k in 22:
		_mix(b, shout, _rng.randf() * 9.2, _rng.randf_range(0.03, 0.09))
	for k in 12:
		_mix(b, death, _rng.randf() * 8.8, _rng.randf_range(0.03, 0.07))
	for k in 16:
		_mix(b, grunt, _rng.randf() * 9.5, _rng.randf_range(0.05, 0.1))
	var battle := b.duplicate()
	bank[&"battle"] = _to_stream(b, true, 0.42)
	_lowpass(battle, 900.0)
	bank[&"battle_far"] = _to_stream(battle, true, 0.3)

	# The sack: battle and fire.
	b = _buf(10.0)
	var fy := 0.0
	for i in b.size():
		var t := float(i) / RATE
		fy += 0.035 * (_noise() - fy)
		b[i] = fy * (3.0 + 1.2 * sin(t * 0.9) + 0.7 * sin(t * 2.3))
	for k in 160:
		_burst(b, _rng.randf() * 9.8, _rng.randf_range(0.05, 0.3), 0.0005, 0.004, 7000.0)
	_mix(b, battle, 0.0, 2.0)
	for k in 14:
		_mix(b, shout, _rng.randf() * 9.2, _rng.randf_range(0.04, 0.09))
	for k in 10:
		_mix(b, clang, _rng.randf() * 9.0, _rng.randf_range(0.03, 0.06))
	bank[&"sack"] = _to_stream(b, true, 0.5)

	# Lyre: a slow air in the Greek Dorian mode (E F G A B C D) over a drone.
	b = _buf(26.0)
	var scale: Array[float] = [164.81, 174.61, 196.0, 220.0, 246.94, 261.63, 293.66, 329.63, 349.23, 392.0]
	var tune: Array = [[0.0, 7], [1.2, 6], [1.8, 5], [2.4, 4], [3.6, 5], [4.2, 4], [4.8, 3], [6.0, 4],
		[7.2, 2], [7.8, 3], [8.4, 4], [9.6, 3], [10.2, 2], [10.8, 1], [12.0, 0],
		[13.2, 4], [13.8, 5], [14.4, 7], [15.6, 6], [16.2, 5], [16.8, 4], [18.0, 3],
		[19.2, 4], [19.8, 2], [20.4, 1], [21.6, 0], [22.8, 4], [23.6, 0]]
	for note: Array in tune:
		_pluck(b, note[0], scale[note[1]], 0.6, 0.9972)
	for k in 9:
		_pluck(b, k * 2.4 + 0.02, 82.41, 0.42, 0.9985)
		_pluck(b, k * 2.4 + 1.21, 123.47, 0.3, 0.998)
	bank[&"lyre"] = _to_stream(b, true, 0.6)

	print("Sfx: %d sounds synthesised in %d ms" % [bank.size(), Time.get_ticks_msec() - t0])
	_finish.call_deferred(bank)


func _finish(bank: Dictionary) -> void:
	_bank = bank
	_ready_flag = true
	if _thread != null:
		_thread.wait_to_finish()
		_thread = null
