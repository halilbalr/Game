extends Mission
## The Wooden Horse. Odysseus on the last night of Troy: silence inside the
## horse, a way through the sleeping city, the watch at the Scaean Gate, and
## the fight to the house of Deiphobus.
## Sources: Odyssey 4.271-289, 8.492-520; Little Iliad; Sack of Ilium.

var horse: WoodenHorse
var menelaus: Soldier
var deiphobus: Soldier
var _stealth: bool = false
var _alarms: Dictionary = {}
var _gate_watch: Array[Soldier] = []
var _inside: Array[Soldier] = []
var _fire_target: float = 0.0
var _fire_level: float = 0.0
var _fire_sites: Array = []
var _fire_timer: float = 0.0
var _sack: bool = false
var _reinforce_timer: float = 0.0
var _allies_spawned: int = 0


func _init() -> void:
	id = "horse"
	hero = "odysseus"
	preset = "night"
	music = [&"night", &"battle", &"lament"]
	ambience = [&"feast", &"night", &"sack"]


func _watch(pos: Vector3, yaw: float, opts: Dictionary = {}) -> Soldier:
	var o := {"aware": false, "stance": &"sentry"}
	o.merge(opts, true)
	return spawn("trojan_sentry", pos + Vector3(0, 0.15, 0), yaw, o)


func _sleeper(pos: Vector3, yaw: float, lying: bool = false) -> Soldier:
	return spawn("trojan_sentry", pos + Vector3(0, 0.15, 0), yaw,
		{"aware": false, "asleep": true, "stance": &"lie" if lying else &"sit"})


func _g(x: float, z: float) -> Vector3:
	return TroyLayout.ground(x, z)


func prepare() -> void:
	(gates["scaean_gate"] as GateDoors).snap(false, true)
	(gates["dardanian_gate"] as GateDoors).snap(false, true)
	horse = WoodenHorse.new()
	add_child(horse)
	horse.global_position = world.marker("horse")
	horse.rotation.y = PI * 0.5
	horse.build()
	# The men in the horse.
	var names := ["menelaus", "diomedes", "achaean_spearman", "achaean_swordsman", "myrmidon"]
	var labels := ["Menelaus", "Diomedes", "Anticlus", "Epeius", "Neoptolemus"]
	for i in names.size():
		var xf := horse.bench(i)
		var s := spawn(names[i], xf.origin, xf.basis.get_euler().y,
			{"stance": &"hide", "invulnerable": true, "engage_range": 0.0, "name": labels[i]})
		_inside.append(s)
	place_player(horse.seat(), PI * 0.5 + PI)
	player.move_enabled = false
	player.combat_enabled = false

	# The citadel after the feast.
	_sleeper(_g(8.0, 24.0), 2.0)
	_sleeper(_g(-14.0, 26.0), -1.0, true)
	_sleeper(_g(14.0, 6.0), 0.5, true)
	_sleeper(_g(-18.0, 2.0), 1.2)
	_watch(_g(2.0, 44.0), 0.0, {"patrol": [_g(2.0, 40.0), _g(-1.5, 66.0)]})
	var south := world.marker("south_gate")
	_watch(south + Vector3(1.6, 0, -5.0), PI)
	_sleeper(south + Vector3(-2.6, 0, -6.5), 1.6)
	# The lower town.
	var agora := world.marker("agora")
	_watch(agora + Vector3(8, 0, 2), 0.0, {"patrol": [agora + Vector3(10, 0, -6), agora + Vector3(-10, 0, 8), agora + Vector3(4, 0, 12)]})
	_sleeper(agora + Vector3(-12, 0, 9), 0.4, true)
	_watch(_g(-46.0, 124.0), -1.9)
	_watch(_g(-49.0, 122.0), 1.3)
	_watch(_g(-100.0, 144.0), 1.0, {"patrol": [_g(-98.0, 143.0), _g(-146.0, 167.0)]})
	_sleeper(_g(-124.0, 151.0), 2.6)
	# The watch at the Scaean Gate.
	var gate := world.gate("scaean_gate")
	var gp: Vector3 = gate["pos"]
	var inward: Vector3 = -(gate["normal"] as Vector3)
	var side := Vector3(inward.z, 0, -inward.x)
	var fire_pos := gp + inward * 9.0 + side * 3.5
	var brazier := Fire.new(0.3, false, true)
	add_child(brazier)
	brazier.global_position = Vector3(fire_pos.x, TroyLayout.height(fire_pos.x, fire_pos.z) + 0.55, fire_pos.z)
	_gate_watch.append(_watch(_g(fire_pos.x + side.x * 1.3, fire_pos.z + side.z * 1.3), yaw_to(side, Vector3.ZERO)))
	_gate_watch.append(_watch(_g(fire_pos.x - side.x * 1.3, fire_pos.z - side.z * 1.3), yaw_to(-side, Vector3.ZERO)))
	var p1 := gp + inward * 6.0 - side * 9.0
	var p2 := gp + inward * 6.0 + side * 13.0
	_gate_watch.append(_watch(_g(p1.x, p1.z), 0.0, {"patrol": [_g(p1.x, p1.z), _g(p2.x, p2.z)]}))
	var sp := gp + inward * 3.2 - side * 4.2
	_gate_watch.append(_sleeper(_g(sp.x, sp.z), yaw_to(Vector3.ZERO, inward)))
	battle.sentry_alerted.connect(_on_alert)
	# Houses that will burn, nearest the gate first.
	for h: Dictionary in world.info["houses"]:
		var hp: Vector3 = h["pos"]
		if _near_route(hp):
			_fire_sites.append(h)
	_fire_sites.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return (a["pos"] as Vector3).distance_squared_to(gp) < (b["pos"] as Vector3).distance_squared_to(gp))


## True for houses within sight of the route from the Scaean Gate to the citadel.
func _near_route(p: Vector3) -> bool:
	var route: Array[Vector2] = [Vector2(-195.0, 191.0), Vector2(-96.0, 140.0), Vector2(0.0, 106.0), Vector2(0.0, 80.0)]
	var q := Vector2(p.x, p.z)
	for i in route.size() - 1:
		var a := route[i]
		var ab := route[i + 1] - a
		var t := clampf((q - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
		if q.distance_to(a + ab * t) < 34.0:
			return true
	return false


func _on_alert(s: Soldier) -> void:
	if not _stealth or ended:
		return
	if not _alarms.has(s):
		_alarms[s] = float(Data.tune("stealth.alarm_seconds", 7.0))
		hud.toast("He has seen you. Silence him before he rouses the city!", 4.0)
		Sfx.play(&"alarm")


func _process(delta: float) -> void:
	if ended:
		return
	if _stealth:
		var worst := 0.0
		for s in battle.living(&"trojan"):
			if not s.aware or s.asleep:
				worst = maxf(worst, s.detection)
		var alarmed := false
		var least := INF
		var total := float(Data.tune("stealth.alarm_seconds", 7.0))
		for s: Soldier in _alarms.keys():
			if not is_instance_valid(s) or not s.is_alive():
				_alarms.erase(s)
				continue
			_alarms[s] = maxf(float(_alarms[s]) - delta, 0.0)
			alarmed = true
			least = minf(least, float(_alarms[s]))
			# His shout wakes the men nearest him.
			if float(_alarms[s]) < total - 2.0:
				for o in battle.living(&"trojan"):
					if (not o.aware or o.asleep) and o.global_position.distance_to(s.global_position) < 9.0:
						o.alert(player)
		hud.set_stealth(true, 1.0 if alarmed else worst, least if alarmed else -1.0, total)
		if alarmed and least <= 0.0 and not autoplay and not Game.args.has("noalarm"):
			fail(text("alarm_title"), text("alarm_text"), "text_alarm_text")
	if _sack:
		_fire_level = move_toward(_fire_level, _fire_target, delta * 0.02)
		world.atmosphere.set_fire(_fire_level)
		Mats.set_soot(_fire_level * 0.55)
		_fire_timer -= delta
		if _fire_timer <= 0.0 and not _fire_sites.is_empty() and get_tree().get_nodes_in_group(&"house_fires").size() < 16:
			_fire_timer = 3.5
			_ignite(_fire_sites.pop_front())
		_reinforce_timer -= delta
		if _reinforce_timer <= 0.0:
			_reinforce_timer = 10.0
			_reinforce()


func _ignite(h: Dictionary) -> void:
	var f := Fire.new(1.9, true)
	f.light.omni_range = 26.0
	f.add_to_group(&"house_fires")
	add_child(f)
	f.global_position = (h["pos"] as Vector3) + Vector3(randf_range(-1.5, 1.5), (h["h"] as float) + 0.2, randf_range(-1.5, 1.5))
	Sfx.play_at(&"fire", f.global_position)


func _reinforce() -> void:
	var common := 0
	for s in battle.living(&"achaean"):
		if not s.hero:
			common += 1
	if common >= 7 or _allies_spawned > 30:
		return
	var rear: Array[Vector3] = [world.marker("scaean_gate"), _g(-96.0, 140.0), world.marker("agora"), world.marker("south_gate")]
	var goal := world.marker("house_deiphobus")
	var best := Vector3.INF
	var best_score := -INF
	for r in rear:
		var d := r.distance_to(player.global_position)
		if d < 22.0 or d > 90.0:
			continue
		var score := r.distance_to(goal)
		if score > best_score:
			best_score = score
			best = r
	if best == Vector3.INF:
		return
	for s in spawn_group(["achaean_spearman", "achaean_swordsman", "myrmidon"], 3, best, 2.5, 0.0,
			{"leader": player, "damage_scale": 0.7}):
		_allies_spawned += 1


func run() -> void:
	hud.set_fade(1.0)
	Sfx.music(&"night")
	scene_begin()
	await wait(0.5)
	await card(9.0)
	hud.fade(0.0, 3.0 if not autoplay else 0.1)
	objective("wait")
	mark("inside")
	Sfx.ambience(&"feast")
	await wait(2.0)
	await speak("menelaus_1")
	await speak("diomedes_1")
	await wait(1.5)
	Sfx.play(&"knock")
	await speak("steps")
	await speak("helen_1")
	await wait(0.8)
	await speak("helen_2")
	await wait(0.8)
	await speak("helen_3")
	scene_end()

	# Anticlus must be stopped (Odyssey 4.285-288).
	var anticlus := _inside[2]
	anticlus.figure.stance = &"idle"
	hud.say("", str((data["lines"]["anticlus"] as Array)[1]), 8.0)
	if not autoplay:
		Sfx.speak(id, "anticlus")
	objective("anticlus", anticlus)
	var held := {"done": false}
	var it := add_interactable(anticlus.global_position, "Stop his mouth", 0.0, 4.5, 1.0)
	it.aim_cone = 1.2
	it.used.connect(func(_p: Node3D) -> void: held["done"] = true)
	if autoplay:
		it.interact(player)
	var t := 0.0
	while not held["done"] and t < 9.0:
		await wait(0.1)
		t += 0.1
	it.queue_free()
	if not held["done"]:
		fail(text("anticlus_title"), text("anticlus_text"), "text_anticlus_text")
		return
	anticlus.figure.stance = &"hide"
	objective("wait")
	scene_begin()
	await speak("held")
	await speak("athena_gone")
	await wait(1.5)
	Sfx.ambience(&"night")
	await speak("quiet")
	Sfx.play(&"knock")
	await speak("sinon")
	scene_end()

	# Out through the belly.
	var hatch := add_interactable(horse.hatch(), "Open the hatch", 1.2, 4.0, 0.0)
	objective("hatch", horse.hatch())
	await used(hatch)
	hatch.queue_free()
	Sfx.play(&"hatch")
	await hud.fade(1.0, 1.0)
	for s in _inside:
		s.queue_free()
		battle.soldiers.erase(s)
	_inside.clear()
	var foot := horse.rope_foot()
	place_player(foot + Vector3(0, 0.2, 0), 0.0)
	player.look_toward(world.marker("south_gate") + Vector3(0, 1.5, 0))
	player.move_enabled = true
	player.combat_enabled = true
	var dio := spawn("diomedes", _g(foot.x - 1.8, foot.z + 3.4) + Vector3(0, 0.2, 0), PI, {"invulnerable": true, "engage_range": 0.0})
	var men := spawn("menelaus", _g(foot.x + 2.0, foot.z + 4.0) + Vector3(0, 0.2, 0), PI, {"invulnerable": true, "engage_range": 0.0})
	_stealth = true
	mark("exit")
	await hud.fade(0.0, 1.6 if not Game.args.has("stop") else 0.05)
	await speak("plan")
	dio.set_goal(world.marker("palace"), 3.0)
	men.set_goal(world.marker("palace") + Vector3(3, 0, 0), 3.0)
	# The marker stands just beyond the gate, inside the zone that advances the script.
	objective("citadel", world.marker("south_gate") + Vector3(0, 0, 5.0))
	hud.toast(text("hint_stealth"), 9.0)
	await speak("athena_1")

	await reach(world.marker("south_gate") + Vector3(0, 0, 6.0), 6.0)
	for s: Soldier in [dio, men]:
		battle.soldiers.erase(s)
		s.queue_free()
	var gate := world.gate("scaean_gate")
	var gp: Vector3 = gate["pos"]
	var inward: Vector3 = -(gate["normal"] as Vector3)
	objective("town", gp + inward * 14.0)
	await speak("south_gate")
	await reach(gp + inward * 22.0, 15.0)
	objective("watch", gp + inward * 8.0)
	mark("gate")
	await speak("at_gate")
	await all_dead(_gate_watch)
	await speak("gate_clear")

	# The bar.
	var doors: GateDoors = gates["scaean_gate"]
	var bar := add_interactable(doors.bar_position() + inward * 0.6, text("hint_bar", "Lift the bar"), 2.6, 3.4, 0.0)
	bar.prompt = "Lift the bar"
	objective("bar", doors.bar_position())
	hud.toast(text("hint_bar"), 6.0)
	await used(bar)
	bar.queue_free()
	_stealth = false
	_alarms.clear()
	hud.set_stealth(false)
	doors.lift_bar()
	await wait(1.8)
	doors.open(4.0)
	await wait(2.5)
	await _begin_sack(gp, inward)


func _begin_sack(gp: Vector3, inward: Vector3) -> void:
	_sack = true
	_fire_target = 0.85
	Sfx.ambience(&"sack")
	Sfx.music(&"battle")
	Sfx.play(&"horn")
	# The army that sailed back from Tenedos.
	var outside := gp - inward * 9.0
	for s in spawn_group(["achaean_spearman", "achaean_swordsman", "myrmidon", "achaean_spearman"], 11,
			Vector3(outside.x, TroyLayout.height(outside.x, outside.z), outside.z), 5.0, yaw_to(-inward, Vector3.ZERO),
			{"leader": player, "damage_scale": 0.7}):
		_allies_spawned += 1
	menelaus = spawn("menelaus", Vector3(outside.x, TroyLayout.height(outside.x, outside.z) + 0.2, outside.z) + inward * 4.0,
		yaw_to(-inward, Vector3.ZERO), {"leader": player, "invulnerable": true, "damage_scale": 0.8,
		"follow_offset": Vector3(1.8, 0, 1.6)})
	# The city wakes in arms.
	for s in battle.living(&"trojan"):
		s.alert(player)
	var posts: Array = [
		[_g(-150.0, 168.0), 5], [_g(-104.0, 143.0), 5], [_g(-52.0, 124.0), 5],
		[world.marker("agora"), 6], [world.marker("south_gate") + Vector3(0, 0, -7.0), 5],
		[_g(0.0, 46.0), 4], [_g(8.0, 16.0), 4],
	]
	for post: Array in posts:
		spawn_group(["trojan_spearman", "trojan_swordsman", "trojan_spearman"], post[1], post[0], 3.0, 0.0)
	var house := world.marker("house_deiphobus")
	deiphobus = spawn("deiphobus", house + Vector3(0, 0.3, 0), yaw_to(house, world.marker("court")), {"hold": true})
	var guards := spawn_group(["trojan_spearman", "trojan_swordsman"], 4, house, 3.0, 0.0, {"hold": true})
	player.heal(40.0)
	mark("sack")
	await speak("opened")
	objective("deiphobus", house)
	await speak("menelaus_2")
	await reach(world.marker("south_gate") + Vector3(0, 0, 8.0), 12.0)
	await speak("menelaus_3")
	await reach(house, 17.0)
	hud.set_boss(deiphobus)
	mark("deiphobus")
	objective("kill_deiphobus", deiphobus)
	deiphobus.hold = false
	for g in guards:
		g.hold = false
	await speak("deiphobus_1")
	await all_dead([deiphobus])
	hud.set_boss(null)
	hud.set_objective("")
	Sfx.music(&"lament")
	scene_begin()
	await wait(1.2)
	await speak("deiphobus_dead")
	scene_end()
	await hud.fade(1.0, 2.5)
	complete(text("end_title"), text("end_text"))
