extends Mission
## Walk the City: Troy at peace, by daylight, with a chronicle of each place.

var _seen: Dictionary = {}
var _current: String = ""


func _init() -> void:
	id = "roam"
	hero = "hector"
	preset = "day"


func prepare() -> void:
	var start := world.marker("agora")
	place_player(start + Vector3(0, 0.3, 6.0), 0.0)
	# People of the town.
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var streets := TroyBuilder.street_segments()
	for i in 34:
		var seg: Array = streets[rng.randi() % streets.size()]
		var a: Vector2 = seg[0]
		var b: Vector2 = seg[1]
		var p := a.lerp(b, rng.randf())
		var role := "townswoman" if i % 2 == 0 else "townsman"
		var route: Array[Vector3] = [TroyLayout.ground(a.x, a.y, 0.1), TroyLayout.ground(b.x, b.y, 0.1)]
		if i % 3 == 0:
			spawn(role, TroyLayout.ground(p.x + 1.5, p.y, 0.2), rng.randf() * TAU, {"stance": &"idle"})
		else:
			spawn(role, TroyLayout.ground(p.x, p.y, 0.2), 0.0, {"patrol": route, "aware": false})
	# The watch at the gates.
	for gate_id: String in ["south_gate", "scaean_gate", "dardanian_gate"]:
		var rec := world.gate(gate_id)
		var pos: Vector3 = rec["pos"]
		var n: Vector3 = rec["normal"]
		var side := Vector3(n.z, 0, -n.x)
		for s: float in [-1.0, 1.0]:
			var gp := pos + side * s * ((rec["width"] as float) * 0.5 + 1.2) + n * 3.4
			spawn("trojan_spearman", Vector3(gp.x, TroyLayout.height(gp.x, gp.z) + 0.2, gp.z), yaw_to(Vector3.ZERO, n), {"stance": &"sentry", "hold": true})
	spawn("priam", world.marker("palace") + Vector3(1.5, 0.3, 0.0), PI, {"stance": &"idle"})
	spawn("andromache", world.marker("house_hector") + Vector3(-1.0, 0.3, 1.0), PI * 0.5, {"stance": &"hold_child"})


func run() -> void:
	if touch != null:
		touch.chronicle_enabled = true
	hud.set_fade(1.0)
	Sfx.ambience(&"day")
	Sfx.music(&"lyre")
	if Game.is_harness():
		hud.set_fade(0.0)
	else:
		await wait(0.4)
		hud.fade(0.0, 2.0)
		await hud.title_card(text("title", "Ilios"), text("intro", ""), 5.0)
	hud.set_objective(text("hint", "Walk where you will"))
	# Name each place as the walker comes to it.
	var places: Dictionary = Data.codex.get("places", {})
	while true:
		await wait(0.4)
		var best := ""
		var best_d := INF
		for key: String in places:
			if not world.info["markers"].has(key):
				continue
			var radius := float((places[key] as Dictionary).get("radius", 16.0))
			var d := player.global_position.distance_to(world.marker(key))
			if d < radius and d < best_d:
				best_d = d
				best = key
		if best != _current:
			_current = best
			if best != "":
				var entry: Dictionary = places[best]
				hud.set_objective(str(entry.get("name", best)), null, "Tap READ for the chronicle" if Game.mobile else "Tab: read the chronicle")
				if not _seen.has(best):
					_seen[best] = true
					hud.toast(str(entry.get("name", best)), 3.0)
			else:
				hud.set_objective(text("hint", "Walk where you will"))


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"chronicle") and not ended:
		var places: Dictionary = Data.codex.get("places", {})
		if _current != "" and places.has(_current):
			var entry: Dictionary = places[_current]
			hud.say(str(entry.get("name", "")), str(entry.get("text", "")), 16.0)
		else:
			hud.hush()
