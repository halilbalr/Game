extends Node
## Autoload "Sfx": effects, ambience, music and the characters' voices.
##
## Every sound is a file under assets/audio, rendered ahead of time by the
## generators in tools/audio: synthesised, and the voices spoken by a speech
## model. Nothing is a recording. Effects come in several variants, listed
## in assets/audio/sfx/index.json; each play picks one at random (never the
## one heard last) and nudges its pitch and level, so that no two blows in a
## fight sound alike.

const POOL_3D := 20
const POOL_2D := 6
const SFX_DIR := "res://assets/audio/sfx/"
const AMBIENCE_DIR := "res://assets/audio/ambience/"
const MUSIC_DIR := "res://assets/audio/music/"
const VOICE_DIR := "res://assets/audio/voice/"
const MUSIC_DB := -9.0
const AMBIENCE_DB := -9.0
const VOICE_DB := 1.5
## How far music and ambience drop while someone is speaking.
const DUCK_DB := 8.0

## Effect id -> its variants (Array of AudioStream).
var _effects: Dictionary = {}
var _last_pick: Dictionary = {}
## Browser only: effects still to be handed to the page's audio engine.
var _to_register: Array[AudioStream] = []
## File path -> stream, for every music or ambience loop loaded so far.
var _loops: Dictionary = {}
## Paths of the loops the current screen asked to keep (see preload_loops).
var _keep: Array[String] = []
var _players_3d: Array[AudioStreamPlayer3D] = []
var _players_2d: Array[AudioStreamPlayer] = []
var _next_3d: int = 0
var _next_2d: int = 0
var _ambience_a: AudioStreamPlayer
var _ambience_b: AudioStreamPlayer
var _music_a: AudioStreamPlayer
var _music_b: AudioStreamPlayer
var _music_now: AudioStreamPlayer
var _ambience_now: AudioStreamPlayer
var _speech: AudioStreamPlayer
var _voice_until: float = 0.0
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
	_music_a = AudioStreamPlayer.new()
	_music_b = AudioStreamPlayer.new()
	for p: AudioStreamPlayer in [_ambience_a, _ambience_b, _music_a, _music_b]:
		p.volume_db = -60.0
		add_child(p)
	_speech = AudioStreamPlayer.new()
	_speech.volume_db = VOICE_DB
	# Speech stops with the game when it is paused; music does not.
	_speech.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(_speech)
	_rng.seed = 2401
	_load_effects()


func _load_effects() -> void:
	var index: Variant = JSON.parse_string(FileAccess.get_file_as_string(SFX_DIR + "index.json"))
	if not index is Dictionary:
		push_error("Sfx: %sindex.json is missing or broken; there will be no effects" % SFX_DIR)
		return
	for id: String in index:
		var variants: Array[AudioStream] = []
		for i in int(index[id]):
			var stream := load("%s%s_%d.ogg" % [SFX_DIR, id, i + 1]) as AudioStream
			if stream != null:
				variants.append(stream)
		_effects[StringName(id)] = variants
		if OS.has_feature("web"):
			_to_register.append_array(variants)


func _process(delta: float) -> void:
	if not _to_register.is_empty():
		# In a browser a sound is decoded for the page's audio engine the first
		# time it plays. Do that for the effects now, one a frame, rather than
		# at the first blow of a fight.
		var stream: AudioStream = _to_register.pop_back()
		if not AudioServer.is_stream_registered_as_sample(stream):
			AudioServer.register_stream_as_sample(stream)
	if _want_music != _playing_music:
		_playing_music = _want_music
		_music_now = _start(_loop(MUSIC_DIR, _want_music), _music_a, _music_b, _music_now)
	if _want_ambience != _playing_ambience:
		_playing_ambience = _want_ambience
		_ambience_now = _start(_loop(AMBIENCE_DIR, _want_ambience), _ambience_a, _ambience_b, _ambience_now)
	var duck := DUCK_DB if is_speaking() else 0.0
	_fade(_music_a, MUSIC_DB - duck if _music_a == _music_now else -60.0, delta)
	_fade(_music_b, MUSIC_DB - duck if _music_b == _music_now else -60.0, delta)
	_fade(_ambience_a, AMBIENCE_DB - duck * 0.6 if _ambience_a == _ambience_now else -60.0, delta)
	_fade(_ambience_b, AMBIENCE_DB - duck * 0.6 if _ambience_b == _ambience_now else -60.0, delta)


## Starts a loop on whichever of two players is free and returns it (null
## for silence); [method _fade] brings it up and the other one down.
func _start(stream: AudioStream, a: AudioStreamPlayer, b: AudioStreamPlayer, now: AudioStreamPlayer) -> AudioStreamPlayer:
	if stream == null:
		return null
	# A free player, or else the quieter one (it is on its way out). Never the
	# one sounding now, or its fade-out would be cut short.
	var fresh := b if now == a else a
	if now == null and a.playing and (not b.playing or b.volume_db < a.volume_db):
		fresh = b
	if fresh.playing:
		fresh.stop()
		_let_go(fresh)
	fresh.stream = stream
	fresh.volume_db = -40.0
	fresh.play()
	return fresh


func _fade(p: AudioStreamPlayer, target: float, delta: float) -> void:
	if not p.playing:
		return
	# Up quickly, down slowly: about a second in, two and a half out.
	p.volume_db = move_toward(p.volume_db, target, delta * (34.0 if target > p.volume_db else 20.0))
	if target <= -60.0 and p.volume_db <= -59.0:
		p.stop()
		_let_go(p)


## A loop the screen now showing did not ask for (the title music fading out
## as a mission starts) is not coming back: in a browser, release it.
func _let_go(p: AudioStreamPlayer) -> void:
	if OS.has_feature("web") and p.stream != null and not p.stream.resource_path in _keep:
		_forget(p.stream)
		_loops.erase(p.stream.resource_path)
		p.stream = null


## A looping stream by name from [param dir] (MUSIC_DIR or AMBIENCE_DIR:
## "night" is both a piece of music and a night's ambience).
func _loop(dir: String, id: StringName) -> AudioStream:
	if id == &"":
		return null
	var path := dir + String(id) + ".ogg"
	if _loops.has(path):
		return _loops[path]
	if not ResourceLoader.exists(path):
		push_warning("Sfx: no loop at %s" % path)
		return null
	var track := load(path) as AudioStreamOggVorbis
	track.loop = true
	_loops[path] = track
	return track


func _loop_playing(stream: AudioStream) -> bool:
	for p: AudioStreamPlayer in [_music_a, _music_b, _ambience_a, _ambience_b]:
		if p.playing and p.stream == stream:
			return true
	return false


## Loads the music and ambience a mission will use, during its loading
## screen, so that the first bar does not cost a dropped frame in the middle
## of a fight. In a browser this decodes them for the page's audio engine,
## and releases the loops of an earlier mission that this one does not use.
## [codeblock]Sfx.preload_loops([&"night", &"battle"], [&"feast", &"sack"])[/codeblock]
func preload_loops(music_ids: Array, ambience_ids: Array) -> void:
	var keep: Array[String] = []
	_keep = keep
	for pair: Array in [[MUSIC_DIR, music_ids], [AMBIENCE_DIR, ambience_ids]]:
		for id: StringName in pair[1]:
			var stream := _loop(pair[0], id)
			if stream == null:
				continue
			keep.append(String(pair[0]) + String(id) + ".ogg")
			if OS.has_feature("web") and not AudioServer.is_stream_registered_as_sample(stream):
				AudioServer.register_stream_as_sample(stream)
	if OS.has_feature("web"):
		for path: String in _loops.keys():
			if not path in keep and not _loop_playing(_loops[path]):
				_forget(_loops[path])
				_loops.erase(path)


## Speaks a recorded line: assets/audio/voice/<group>/<key>.ogg. Returns its
## length in seconds, or 0 when there is no such file.
## [codeblock]var seconds := Sfx.speak("horse", "helen_1")[/codeblock]
func speak(group: String, key: String) -> float:
	var path := "%s%s/%s.ogg" % [VOICE_DIR, group, key]
	if not ResourceLoader.exists(path):
		return 0.0
	var stream := load(path) as AudioStream
	_speech.stop()
	_forget(_speech.stream)
	_speech.stream = stream
	_speech.play()
	_voice_until = Time.get_ticks_msec() * 0.001 + stream.get_length()
	return stream.get_length()


## Cuts off whoever is speaking.
func hush_voice() -> void:
	_speech.stop()
	_forget(_speech.stream)
	_speech.stream = null
	_voice_until = 0.0


## In a browser the page's audio engine keeps a decoded copy of every stream
## it has played, and the engine never lets go of one. A line of speech is
## heard once and a mission's loops are not needed by the next, so their
## copies are released by hand through a hook that tools/web/pack_artifact.py
## adds to the engine script. Without the hook (the plain web export) this
## does nothing.
func _forget(stream: AudioStream) -> void:
	if stream != null and OS.has_feature("web"):
		JavaScriptBridge.eval("window.__odysseyDropSample && window.__odysseyDropSample('%d')" % stream.get_instance_id(), true)


## True while a spoken line is playing.
func is_speaking() -> bool:
	return _speech.playing and Time.get_ticks_msec() * 0.001 < _voice_until + 0.3


## One variant of an effect, never the one played last (null if unknown).
func _pick(id: StringName) -> AudioStream:
	var variants: Array = _effects.get(id, [])
	if variants.is_empty():
		return null
	var i := _rng.randi() % variants.size()
	if variants.size() > 1 and i == int(_last_pick.get(id, -1)):
		i = (i + 1 + _rng.randi() % (variants.size() - 1)) % variants.size()
	_last_pick[id] = i
	return variants[i]


## Plays a named effect at a world position.
## [codeblock]Sfx.play_at(&"clang", hit_point, -4.0)[/codeblock]
func play_at(id: StringName, pos: Vector3, volume_db: float = 0.0) -> void:
	var stream := _pick(id)
	if stream == null:
		return
	var p := _players_3d[_next_3d]
	_next_3d = (_next_3d + 1) % POOL_3D
	p.stream = stream
	p.global_position = pos
	p.volume_db = volume_db + _rng.randf_range(-1.5, 1.0)
	p.pitch_scale = _rng.randf_range(0.94, 1.06)
	p.play()


## Plays a named effect with no position (interface, the player's own body).
## [codeblock]Sfx.play(&"hurt")[/codeblock]
func play(id: StringName, volume_db: float = 0.0) -> void:
	var stream := _pick(id)
	if stream == null:
		return
	var p := _players_2d[_next_2d]
	_next_2d = (_next_2d + 1) % POOL_2D
	p.stream = stream
	p.volume_db = volume_db + _rng.randf_range(-1.0, 0.5)
	p.pitch_scale = _rng.randf_range(0.96, 1.04)
	p.play()


## The sound of a weapon swung through the air: a cut sings higher than a
## thrust. [param weapon] is a row of assets/data/weapons.json.
func swing_sound(weapon: Dictionary) -> StringName:
	return &"whoosh_slash" if str(weapon.get("kind", "thrust")) == "slash" else &"whoosh_thrust"


## Plays the sound of a blow landing, chosen from what it met: a shield, a
## man taken unawares, a blade's cut or a point's thrust, and a helmet when
## it struck the head. [param result] is what receive_hit returned.
## [codeblock]Sfx.strike(target.global_position, "sword", result)[/codeblock]
func strike(pos: Vector3, weapon_id: String, result: Dictionary) -> void:
	if result.is_empty():
		return
	if result.get("blocked", false):
		play_at(&"block", pos)
		return
	if result.get("stealth", false):
		play_at(&"stab", pos)
		return
	var weapon: Dictionary = Data.weapons.get(weapon_id, {})
	play_at(&"hit_cut" if str(weapon.get("kind", "thrust")) == "slash" else &"hit_pierce", pos)
	if result.get("zone", &"body") == &"head":
		play_at(&"hit_head", pos, -3.0)


## Starts a named ambience loop, cross-fading from any other ("" for silence).
func ambience(id: StringName) -> void:
	_want_ambience = id


## Starts a named piece of music ("" stops it).
func music(id: StringName) -> void:
	_want_music = id
