extends SeaMission
## The Cyclops. Odysseus lands on the shore of the Cyclopes, is shut in the
## cave of Polyphemus, blinds him, escapes under the rams, and rows away
## under the rocks he hurls.
## Source: Odyssey 9.105-566.

const BEACH := Vector2(10.0, 197.0)
const CAVE := Vector2(40.0, 108.0)
const CAVE_FLOOR := 14.0
const HILLTOP := Vector2(-95.0, 168.0)
const GOAT_ISLAND := Vector2(-420.0, 640.0)
const START := Vector3(70.0, 0.0, 520.0)

var cave: Cave
var giant: Humanoid
var men: Array[Soldier] = []
var sheep: Array[Node3D] = []
var stake: MeshInstance3D
var _rock_hit: bool = false


func _init() -> void:
	super()
	id = "cyclops"
	preset = "day"
	music = [&"sea", &"night", &"odyssey", &"lament"]
	ambience = [&"sea", &"cave"]
	outfits = ["odysseus", "achaean", "oarsman", "polyphemus"]


func build_islands() -> void:
	# The land of the Cyclopes: a high island of hills, with a beach below
	# a cave and a path climbing to it.
	var land := Island.new(Vector2(0.0, 0.0), Vector2(250.0, 195.0), 58.0, 11)
	land.cliffs = 0.3
	land.walked = true
	land.flats.append([BEACH, 20.0, 0.9])
	land.flats.append([Vector2(20.0, 176.0), 11.0, 4.2])
	land.flats.append([Vector2(29.0, 156.0), 11.0, 8.0])
	land.flats.append([Vector2(36.0, 137.0), 11.0, 11.6])
	land.flats.append([CAVE, 22.0, CAVE_FLOOR])
	land.hills.append([HILLTOP, 42.0, 34.0])
	sea_world.add_island(land)
	# Across the bay, the wooded goat island where the fleet waits.
	var goats := Island.new(GOAT_ISLAND, Vector2(120.0, 90.0), 20.0, 3)
	sea_world.add_island(goats)
	cave = Cave.new()
	sea_world.add_child(cave)
	cave.position = Vector3(CAVE.x, CAVE_FLOOR, CAVE.y)
	var rock := ShaderMaterial.new()
	rock.shader = load("res://assets/shaders/island.gdshader")
	cave.build(rock)
	# Walkable ground is found without the door stone, which moves.
	cave.remove_child(cave.stone)
	sea_world.bake_navigation(AABB(Vector3(-20.0, -4.0, 85.0), Vector3(100.0, 40.0, 140.0)))
	cave.add_child(cave.stone)


func _cave_point(local: Vector3) -> Vector3:
	return cave.to_global(local)


func prepare() -> void:
	ship.place(START, yaw_to(START, Vector3(BEACH.x, 0.0, BEACH.y)))
	board(ship.helm, true)
	cave.set_door(false, 0.0)
	# The fire, the giant (out with his flocks until evening).
	var fire := Fire.new(0.7, true, true)
	add_child(fire)
	# The only light in a shut cave: let it reach the walls and the giant.
	fire.light.omni_range = 18.0
	fire.light.light_energy *= 1.8
	fire.global_position = _cave_point(cave.hearth) + Vector3(0, 0.15, 0)
	giant = Humanoid.new()
	add_child(giant)
	giant.setup("polyphemus", Data.characters["outfits"]["polyphemus"], 0, "")
	giant.scale = Vector3.ONE * 3.2
	giant.visible = false
	# Lambs and kids in the folds.
	for i in 6:
		var a := PI + (i - 2.5) * 0.28
		var p := _cave_point(Vector3(sin(a), 0, cos(a)) * 8.0)
		sheep.append(Flock.place(self, p, a, false))
		sheep[-1].scale = Vector3.ONE * 0.6


## Walks the giant to [param to] over [param seconds], his legs keeping step.
func _giant_walk(to: Vector3, seconds: float) -> void:
	giant.look_at(Vector3(to.x, giant.global_position.y, to.z))
	giant.speed = 1.4
	var tw := create_tween()
	tw.tween_property(giant, "global_position", to, seconds if not autoplay else 0.05)
	await tw.finished
	giant.speed = 0.0


## Two more of the men are gone.
func _eaten() -> void:
	await hud.fade(1.0, 0.6 if not autoplay else 0.05)
	Sfx.play(&"death", -6.0)
	for i in 2:
		if men.is_empty():
			break
		var m: Soldier = men.pop_back()
		battle.soldiers.erase(m)
		m.queue_free()
	await wait(1.0)
	hud.fade(0.0, 0.8 if not autoplay else 0.05)


func _flock_inside() -> void:
	for i in 10:
		var a := -0.9 + i * 0.2
		var p := _cave_point(Vector3(sin(a) * 6.0, 0, cos(a) * 6.0 - 1.0))
		sheep.append(Flock.place(self, p, a + PI, i % 3 == 0))


func _shake(amount: float) -> void:
	player._shake = maxf(player._shake, amount)


func run() -> void:
	hud.set_fade(1.0)
	Sfx.music(&"sea")
	Sfx.ambience(&"sea")
	scene_begin()
	await wait(0.5)
	hud.fade(0.0, 2.0 if not autoplay else 0.1)
	await card(9.0)
	scene_end()
	objective("land", Vector3(BEACH.x, 0.0, BEACH.y + 18.0))
	hud.toast(text("hint_sail"), 9.0)
	mark("sailing")
	await sail_to(Vector3(BEACH.x, 0.0, BEACH.y + 18.0), 26.0)

	# Ashore with twelve men.
	await hud.fade(1.0, 0.8 if not autoplay else 0.05)
	ship.place(Vector3(BEACH.x, 0.0, BEACH.y + 15.0), PI)
	ship.moored = true
	var landing := Vector3(BEACH.x, ground_y(BEACH.x, BEACH.y - 2.0) + 0.3, BEACH.y - 2.0)
	go_ashore(landing, yaw_to(landing, _cave_point(Vector3.ZERO)))
	for s in spawn_group(["achaean_spearman", "achaean_swordsman"], 12, landing + Vector3(0, 0, 4), 3.0, 0.0,
			{"leader": player, "invulnerable": true, "engage_range": 0.0}, true):
		men.append(s)
	hud.fade(0.0, 0.8 if not autoplay else 0.05)
	await speak("arrive")
	objective("cave", _cave_point(Vector3(0, 0, Cave.R + 6.0)))
	mark("ashore")
	await reach(_cave_point(Vector3(0, 0, Cave.R + 6.0)), 6.0)
	objective("explore", _cave_point(Vector3(0, 0, 2.0)))
	await reach(_cave_point(Vector3(0, 0, 2.0)), 5.0)
	hud.set_objective("")
	Sfx.ambience(&"cave")
	scene_begin()
	await speak("cave_in")
	await speak("companion_1")
	await speak("odysseus_wait")
	scene_end()

	# He comes home.
	await hud.fade(1.0, 1.2 if not autoplay else 0.05)
	sea_world.set_preset("night")
	Sfx.music(&"night")
	_flock_inside()
	cave.set_door(true, 0.0)
	giant.visible = true
	giant.global_position = _cave_point(cave.seat)
	giant.look_at(_cave_point(Vector3.ZERO))
	player.move_enabled = false
	place_player(_cave_point(Vector3(-2.5, 0.3, 1.5)), yaw_to(_cave_point(Vector3(-2.5, 0, 1.5)), giant.global_position))
	player.look_toward(giant.head_position())
	hud.fade(0.0, 1.0 if not autoplay else 0.05)
	mark("polyphemus")
	scene_begin()
	await speak("return")
	await speak("poly_1")
	await speak("odysseus_1")
	await speak("poly_2")
	scene_end()
	await _eaten()
	scene_begin()
	await speak("eats")
	await speak("plan")
	scene_end()
	await _eaten()
	scene_begin()
	await speak("morning")
	scene_end()
	giant.visible = false
	for s in sheep.slice(6):
		s.visible = false
	player.move_enabled = true

	# The stake.
	await speak("club")
	objective("stake", cave.club)
	var cut := add_interactable(cave.club.global_position + Vector3(0, 0.4, 0), "Cut a stake from the club", 2.0, 4.5, 0.0)
	cut.action = &"chop"
	await used(cut)
	cut.queue_free()
	Sfx.play(&"spear_stick", -4.0)
	stake = _stake_mesh()
	add_child(stake)
	stake.visible = false
	# The stake is in his hands from here to the fire.
	player.set_action(&"fire")
	mark("carry")
	objective("fire", _cave_point(cave.hearth))
	var harden := add_interactable(_cave_point(cave.hearth) + Vector3(0, 0.3, 0), "Harden the point in the fire", 3.0, 3.5, 0.0)
	harden.action = &"fire"
	await used(harden)
	harden.queue_free()
	Sfx.play(&"fire", -4.0)
	scene_begin()
	await speak("hardened")
	scene_end()
	# Hidden under the dung that lay thick about the cave.
	player.set_action(&"")

	# Evening: the wine.
	await hud.fade(1.0, 1.0 if not autoplay else 0.05)
	for s in sheep:
		s.visible = true
	giant.visible = true
	giant.global_position = _cave_point(cave.seat + Vector3(0, 0, -2.0))
	giant.stance = &"sit"
	hud.fade(0.0, 1.0 if not autoplay else 0.05)
	scene_begin()
	await speak("evening")
	scene_end()
	await _eaten()
	var at_giant := giant.global_position + (_cave_point(Vector3.ZERO) - giant.global_position).normalized() * 3.0
	for i in 3:
		# The marker shows where to stand and hold up the bowl, before his knees.
		objective("wine", at_giant)
		var bowl := add_interactable(at_giant + Vector3(0, 0.3, 0), "Give him the wine", 0.0, 5.0, 2.0)
		await used(bowl)
		bowl.queue_free()
		hud.set_objective("")
		# The bowl held up to him while he drinks.
		player.set_action(&"bowl")
		mark("bowl")
		scene_begin()
		match i:
			0:
				await speak("wine_1")
				await speak("poly_wine")
			1:
				await speak("wine_2")
				await speak("poly_wine")
			2:
				await speak("name")
				await speak("poly_gift")
		scene_end()
		player.set_action(&"")
	giant.stance = &"lie"
	giant.global_position = _cave_point(cave.bed)
	scene_begin()
	await speak("sleep")
	scene_end()

	# The eye.
	# The stake out of hiding, its point heated in the embers again.
	player.set_action(&"stake")
	objective("eye", giant.head_position())
	mark("eye")
	var eye := add_interactable(giant.head_position(), "Drive the stake into his eye", 2.4, 4.5, 0.0)
	eye.action = &"stake"
	await used(eye)
	eye.queue_free()
	giant.blind()
	Sfx.play(&"fire", 0.0)
	Sfx.play(&"roar", 0.0)
	_shake(1.0)
	giant.stance = &"cheer"
	giant.global_position = _cave_point(cave.bed + Vector3(0, 0, 1.5))
	scene_begin()
	# Twisting it in, as a shipwright bores a ship's timber, then letting go.
	player.viewmodel.progress = 1.0
	await wait(1.2)
	player.set_action(&"")
	await speak("blinded")
	await speak("others")
	await speak("poly_nobody")
	await speak("others_2")
	await speak("laugh")
	await hud.fade(1.0, 1.2 if not autoplay else 0.05)
	sea_world.set_preset("day")
	cave.set_door(false, 0.0)
	giant.stance = &"sit"
	giant.global_position = _cave_point(Vector3(0, 0, Cave.R - 1.5))
	giant.look_at(_cave_point(Vector3(0, 0, -10)))
	hud.fade(0.0, 1.0 if not autoplay else 0.05)
	await speak("dawn")
	scene_end()

	# Out under the rams.
	var ram: Node3D = sheep[6]
	ram.global_position = _cave_point(cave.rams_spot)
	objective("ram", ram)
	var cling := add_interactable(ram.global_position + Vector3(0, 0.5, 0), "Cling under the ram", 1.5, 3.5, 0.0)
	cling.action = &"cling"
	await used(cling)
	cling.queue_free()
	# Under the ram's belly, fists in the fleece, carried past the blind giant's hands.
	player.set_action(&"cling")
	player.stoop = true
	mark("under_ram")
	await wait(2.0)
	await hud.fade(1.0, 1.0 if not autoplay else 0.05)
	player.set_action(&"")
	player.stoop = false
	Sfx.play(&"step", -4.0)
	var yard := _cave_point(Vector3(0, 0.3, Cave.R + 8.0))
	place_player(yard, yaw_to(yard, Vector3(BEACH.x, 0, BEACH.y)))
	ram.global_position = yard + Vector3(1.5, -0.3, 0.5)
	for i in men.size():
		men[i].global_position = yard + Vector3(-2.0 + (i % 3) * 1.5, 0.0, 2.0 + int(i / 3) * 1.5)
	hud.fade(0.0, 0.8 if not autoplay else 0.05)
	scene_begin()
	await speak("ram_line")
	scene_end()
	Sfx.music(&"odyssey")
	await speak("run")
	objective("ship", ship.global_position)
	mark("run")
	await reach(Vector3(BEACH.x, ground_y(BEACH.x, BEACH.y), BEACH.y), 8.0)

	# Away, under his rocks.
	await hud.fade(1.0, 0.6 if not autoplay else 0.05)
	for m in men:
		battle.soldiers.erase(m)
		m.queue_free()
	men.clear()
	ship.place(Vector3(BEACH.x, 0.0, BEACH.y + 24.0), PI)
	board(ship.helm, true)
	giant.stance = &"idle"
	giant.global_position = Vector3(HILLTOP.x, ground_y(HILLTOP.x, HILLTOP.y), HILLTOP.y)
	hud.fade(0.0, 0.6 if not autoplay else 0.05)
	var out := Vector3(60.0, 0.0, 330.0)
	objective("row", out)
	hud.toast(text("hint_dodge"), 8.0)
	mark("escape")
	await sail_to(out, 30.0)
	await speak("taunt")
	await _throw_rock(1.0)
	await speak("crew_1")
	var home := Vector3(GOAT_ISLAND.x + 60.0, 0.0, GOAT_ISLAND.y - 110.0)
	objective("open", home)
	await wait(3.0)
	await _throw_rock(1.0)
	await speak("boast")
	await speak("prayer")
	await _throw_rock(1.6)
	await sail_to(home, 40.0)
	Sfx.music(&"lament")
	await hud.fade(1.0, 2.5)
	complete(text("end_title"), text("end_text"))


## The giant hurls a rock at the ship: a shadow shows where it will fall.
## [param size] scales the rock and its wave.
func _throw_rock(size: float) -> void:
	if ended:
		await _never
	giant.look_at(Vector3(ship.global_position.x, giant.global_position.y, ship.global_position.z))
	giant.stance = &"cheer"
	Sfx.play_at(&"roar", giant.global_position + Vector3(0, 5, 0), 4.0)
	var flight := 2.8
	# Where the ship will be, give or take.
	var lead := ship.global_position + ship.forward() * ship.speed * flight
	var target := Vector3(lead.x + randf_range(-4.0, 4.0), 0.0, lead.z + randf_range(-4.0, 4.0))
	var ring := _ring_mesh(6.0 * size)
	add_child(ring)
	ring.global_position = target + Vector3(0, 0.3, 0)
	var rock := MeshInstance3D.new()
	rock.mesh = Clutter.stone_mesh()
	rock.scale = Vector3.ONE * 7.0 * size
	add_child(rock)
	var from := giant.head_position() + Vector3(0, 3, 0)
	var t := 0.0
	while t < flight:
		await get_tree().physics_frame
		if ended:
			await _never
		t += get_physics_process_delta_time() * (20.0 if autoplay else 1.0)
		var k := minf(t / flight, 1.0)
		rock.global_position = from.lerp(target, k) + Vector3(0, sin(k * PI) * 60.0, 0)
		rock.rotation += Vector3(0.03, 0.05, 0.02)
		ring.scale = Vector3.ONE * (0.4 + 0.6 * k)
	rock.queue_free()
	ring.queue_free()
	giant.stance = &"idle"
	Sfx.play_at(&"splash", target, 6.0)
	_splash(target, size)
	_shake(0.6 * size)
	var d := Vector2(ship.global_position.x - target.x, ship.global_position.z - target.z)
	# Close by, the sea it throws up comes down over the ship.
	if d.length() < 50.0:
		lens.splash(clampf(1.25 - d.length() / 40.0, 0.25, 1.0))
	if d.length() < 8.0 * size and not autoplay and not Game.args.has("god"):
		fail(text("wreck_title"), text("wreck_text"), "text_wreck_text")
		await _never
	# The wave it raises throws the ship about.
	ship.drift += Vector3(d.x, 0.0, d.y).normalized() * 4.0 * size / maxf(d.length() / 20.0, 1.0)


func _splash(at: Vector3, size: float) -> void:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.emitting = false
	p.amount = 90
	p.lifetime = 2.2
	p.explosiveness = 0.95
	p.direction = Vector3.UP
	p.spread = 25.0
	p.initial_velocity_min = 10.0 * size
	p.initial_velocity_max = 22.0 * size
	p.gravity = Vector3(0, -9.8, 0)
	p.scale_amount_min = 0.6 * size
	p.scale_amount_max = 1.6 * size
	var drop := SphereMesh.new()
	drop.radius = 0.35
	drop.height = 0.7
	drop.radial_segments = 6
	drop.rings = 3
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.88, 0.93, 0.95)
	m.roughness = 0.3
	drop.material = m
	p.mesh = drop
	add_child(p)
	p.global_position = at
	p.emitting = true
	get_tree().create_timer(3.0).timeout.connect(p.queue_free)


func _ring_mesh(radius: float) -> MeshInstance3D:
	var torus := TorusMesh.new()
	torus.inner_radius = radius * 0.85
	torus.outer_radius = radius
	torus.rings = 24
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.05, 0.08, 0.1, 0.55)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	torus.material = m
	var mi := MeshInstance3D.new()
	mi.mesh = torus
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


## A fathom of olive wood, its point glowing from the fire.
func _stake_mesh() -> MeshInstance3D:
	var gb := GeoBuilder.new()
	gb.chunk_size = 0.0
	var along := Basis(Vector3(0, 0, 1), PI * 0.5)
	Sculpt.lathe(gb, &"hide", Transform3D(along, Vector3.ZERO), PackedVector2Array([Vector2(0.0, -1.0), Vector2(0.12, -0.95),
		Vector2(0.11, 0.6), Vector2(0.05, 0.95)]), 8, Color(0.42, 0.36, 0.24), 1.0, 2)
	Sculpt.lathe(gb, &"ember", Transform3D(along, Vector3.ZERO), PackedVector2Array([Vector2(0.05, 0.94), Vector2(0.0, 1.05)]), 8, Color.WHITE, 1.0, 1)
	var mi := MeshInstance3D.new()
	mi.mesh = gb.build_mesh(Mats.all())
	return mi
