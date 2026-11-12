extends Mission
## The Scaean Gate. Hector parts from Andromache, leads the sortie, holds the
## ground before the gate, and meets Patroclus in the armour of Achilles.
## Sources: Iliad 6.237-529 and 16.684-867.

var andromache: Soldier
var nurse: Soldier
var paris: Soldier
var patroclus: Soldier
var _allies: Array[Soldier] = []
var _gp: Vector3
var _inward: Vector3
var _side: Vector3
var _oak: Vector3
var _out: Vector3


func _init() -> void:
	id = "gate"
	hero = "hector"
	preset = "evening"


func _g(p: Vector3, lift: float = 0.15) -> Vector3:
	return Vector3(p.x, TroyLayout.height(p.x, p.z) + lift, p.z)


func prepare() -> void:
	var gate := world.gate("scaean_gate")
	_gp = gate["pos"]
	_out = (gate["normal"] as Vector3).normalized()
	_inward = -_out
	_side = Vector3(_inward.z, 0, -_inward.x)
	_oak = world.marker("oak")
	var start := _g(_gp + _inward * 52.0)
	place_player(start, yaw_to(start, _gp))
	player.combat_enabled = false
	# Andromache, and the nurse with Astyanax, under the tower.
	var meet := _g(_gp + _inward * 12.0 + _side * 3.0)
	andromache = spawn("andromache", meet, yaw_to(meet, start), {"stance": &"idle", "invulnerable": true})
	nurse = spawn("townswoman", _g(meet + _side * 1.3 + _inward * 0.4), yaw_to(meet, start),
		{"stance": &"hold_child", "invulnerable": true, "name": "Nurse", "variant": 1})
	nurse.figure.add_child(_child_bundle())
	# The watch on the gate and people of the town looking on.
	for sgn: float in [-1.0, 1.0]:
		spawn("trojan_spearman", _g(_gp + _inward * 3.5 + _side * sgn * 4.4), yaw_to(_gp, _gp + _inward), {"stance": &"sentry", "hold": true, "engage_range": 6.0})
	for i in 5:
		var p := _g(_gp + _inward * (20.0 + i * 5.0) + _side * (7.0 if i % 2 == 0 else -7.0))
		spawn("townsman" if i % 2 == 0 else "townswoman", p, yaw_to(p, _gp), {"stance": &"idle", "invulnerable": true})
	# The Trojan line at the oak.
	_allies = spawn_group(["trojan_spearman", "trojan_swordsman", "trojan_spearman"], 10, _g(_oak + _inward * 6.0), 6.0,
		yaw_to(_gp, _oak), {"damage_scale": 0.7, "hold": true, "engage_range": 10.0})


func _child_bundle() -> Node3D:
	var gb := GeoBuilder.new()
	gb.chunk_size = 0.0
	var wrap := PackedVector2Array([Vector2(0.0, -0.2), Vector2(0.07, -0.16), Vector2(0.09, 0.0), Vector2(0.075, 0.12), Vector2(0.0, 0.16)])
	gb.lathe(&"tint", Transform3D(Basis(Vector3(0, 0, 1), 1.2), Vector3.ZERO), wrap, 8, Color(0.86, 0.8, 0.66))
	var head := PackedVector2Array([Vector2(0.0, -0.07), Vector2(0.06, -0.03), Vector2(0.065, 0.02), Vector2(0.0, 0.07)])
	gb.lathe(&"tint", Transform3D(Basis.IDENTITY, Vector3(-0.2, 0.09, 0.0)), head, 8, Color(0.78, 0.6, 0.48))
	var mi := MeshInstance3D.new()
	mi.mesh = gb.build_mesh(Mats.all())
	mi.position = Vector3(0.02, 1.2, -0.27)
	return mi


func _release_allies() -> void:
	for s in _allies:
		if is_instance_valid(s) and s.is_alive():
			s.hold = false
			s.engage_range = float(Data.tune("ai.engage_range", 24.0))
			s.set_goal(_g(_oak + Vector3(randf_range(-9, 9), 0, randf_range(-7, 7))), 3.0)


func _reinforce(count: int) -> void:
	var from := _g(_gp + _out * 6.0)
	for s in spawn_group(["trojan_spearman", "trojan_swordsman"], count, from, 2.5, yaw_to(_gp, _oak), {"damage_scale": 0.7}):
		s.set_goal(_g(_oak + Vector3(randf_range(-9, 9), 0, randf_range(-7, 7))), 3.0)
		_allies.append(s)


func _wave(roles: Array, count: int, offset: Vector3) -> Array[Soldier]:
	var from := _g(_oak + _out * 88.0 + offset)
	var wave := spawn_group(roles, count, from, 7.0, yaw_to(from, _oak))
	for s in wave:
		s.set_goal(_g(_oak + Vector3(randf_range(-8, 8), 0, randf_range(-8, 8))), 4.0)
	Sfx.play(&"horn", -4.0)
	return wave


func run() -> void:
	hud.set_fade(1.0)
	await wait(0.5)
	if not autoplay:
		await hud.title_card(text("title"), text("intro"), 8.0)
	hud.fade(0.0, 2.5 if not autoplay else 0.1)
	Sfx.ambience(&"battle_far")
	objective("find", andromache)
	await reach(andromache.global_position, 4.5)
	player.move_enabled = false
	player.look_toward(andromache.global_position + Vector3(0, 1.5, 0))
	hud.set_objective("")
	mark("andromache")
	await speak("andromache_1")
	await speak("andromache_2")
	await speak("andromache_3")
	await speak("hector_1")
	await speak("hector_2")
	player.look_toward(nurse.global_position + Vector3(0, 1.3, 0))
	await speak("child")
	var helm := add_interactable(nurse.global_position, "Take off your helmet", 0.0, 6.0, 1.2)
	objective("helmet", nurse)
	await used(helm)
	helm.queue_free()
	hud.set_objective("")
	Sfx.play(&"helmet")
	await speak("laugh")
	await speak("prayer")
	await speak("fate")
	var home := _g(_gp + _inward * 70.0)
	andromache.set_goal(home, 2.0)
	nurse.set_goal(home + Vector3(1.5, 0, 0), 2.0)
	await speak("parting")
	# Paris comes down from the citadel in his armour (Iliad 6.503-529).
	var from := _g(_gp + _inward * 40.0)
	paris = spawn("paris", from, yaw_to(from, _gp), {"invulnerable": true, "damage_scale": 0.6})
	paris.set_goal(player.global_position + _inward * 2.0, 2.0)
	await wait(4.0)
	await speak("paris_1")
	await speak("hector_3")
	paris.clear_goal()
	paris.leader = player
	paris.follow_offset = Vector3(-2.0, 0, 1.5)
	player.move_enabled = true
	player.combat_enabled = true

	# The sortie.
	objective("sortie", _oak)
	await reach(_oak + _inward * 8.0, 13.0)
	await speak("rally")
	_release_allies()
	var wave := _wave(["achaean_spearman", "achaean_swordsman", "achaean_spearman"], 8, Vector3.ZERO)
	objective("hold", null)
	mark("battle")
	hud.toast(text("hint_block"), 8.0)
	Sfx.ambience(&"battle")
	await speak("wave_1")
	await all_dead(wave)

	player.heal(35.0)
	_reinforce(3)
	await wait(4.0)
	wave = _wave(["achaean_swordsman", "achaean_spearman", "achaean_spearman", "myrmidon"], 6, _side * 18.0)
	wave.append_array(_wave(["achaean_spearman", "achaean_swordsman"], 5, _side * -26.0))
	objective("hold2", null)
	hud.toast(text("hint_throw"), 8.0)
	await speak("wave_2")
	await all_dead(wave)

	# Patroclus (Iliad 16).
	player.heal(40.0)
	_reinforce(4)
	await wait(3.5)
	await speak("achilles_cry")
	var myrmidons := _wave(["myrmidon"], 9, Vector3.ZERO)
	var pfrom := _g(_oak + _out * 80.0)
	patroclus = spawn("patroclus", pfrom, yaw_to(pfrom, _oak), {"damage_scale": 1.0})
	patroclus.player_kill_only = true
	patroclus.set_goal(_g(_gp + _out * 16.0 - _side * 9.0), 4.0)
	hud.set_boss(patroclus)
	mark("patroclus")
	objective("myrmidons", patroclus)
	await speak("patroclus_1")
	# Three times at the angle of the wall.
	await until(func() -> bool:
		return not patroclus.is_alive() or patroclus.global_position.distance_to(_gp) < 34.0 \
			or patroclus.health < patroclus.max_health * 0.7 or autoplay)
	if patroclus.is_alive():
		patroclus.stagger(1.6)
		Sfx.play(&"thunder")
		await speak("apollo_2")
		await speak("apollo_1")
		patroclus.set_goal(_g(_oak), 4.0)
	await until(func() -> bool:
		var left := 0
		for m in myrmidons:
			if is_instance_valid(m) and m.is_alive():
				left += 1
		return not patroclus.is_alive() or patroclus.health < patroclus.max_health * 0.5 or left <= 2 or autoplay)
	if patroclus.is_alive():
		# Apollo, unseen.
		Sfx.play(&"thunder")
		var env := world.atmosphere.env
		var base_fog := env.fog_density
		var tw := create_tween()
		tw.tween_property(env, "fog_density", 0.03, 1.2)
		tw.tween_interval(5.0)
		tw.tween_property(env, "fog_density", base_fog, 4.0)
		patroclus.stagger(4.0)
		patroclus.figure.remove_helmet()
		patroclus.skill = 0.3
		patroclus.health = minf(patroclus.health, patroclus.max_health * 0.38)
		await speak("apollo_strike")
		patroclus.health = minf(patroclus.health, patroclus.max_health * 0.26)
		Blood.spray(battle, patroclus.global_position + Vector3(0, 1.2, 0), Vector3.UP, 1.5)
		patroclus.stagger(1.5)
		await speak("euphorbus")
		objective("patroclus", patroclus)
		await speak("hector_4")
	await all_dead([patroclus])
	hud.set_boss(null)
	hud.set_objective("")
	await wait(1.0)
	await speak("patroclus_2")
	await speak("patroclus_3")
	await speak("hector_5")
	await hud.fade(1.0, 2.5)
	complete(text("end_title"), text("end_text"))
