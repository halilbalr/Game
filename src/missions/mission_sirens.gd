extends SeaMission
## The Sirens, and Scylla and Charybdis. Odysseus stops his men's ears with
## wax and is bound to the mast to hear the Sirens' song; then he takes the
## helm through the strait, keeping under Scylla's cliff to escape the
## whirlpool, and loses six men to her.
## Source: Odyssey 12.153-263.

const START := Vector3(0.0, 0.0, 420.0)
const SIRENS := Vector2(-170.0, -140.0)
const SCYLLA := Vector2(230.0, -950.0)
const CHARYBDIS_ROCK := Vector2(-160.0, -950.0)
const WHIRL := Vector2(-50.0, -950.0)
const EXIT := Vector3(10.0, 0.0, -1320.0)
const SUN_ISLE := Vector2(80.0, -2000.0)
## Seconds in each turn of the whirlpool: sucking down, then spewing out.
const SUCK := 13.0
const SPEW := 7.0

var _whirl_on: bool = false
var _whirl_t: float = 0.0
var _longing: float = 0.0
var _resisting: bool = false
var _struggles: int = 0
var _necks: Array = []


func _init() -> void:
	super()
	id = "sirens"
	preset = "day"
	music = [&"sea", &"sirens", &"odyssey", &"lament"]
	ambience = [&"sea", &"strait"]
	outfits = ["odysseus", "achaean", "oarsman"]


func build_islands() -> void:
	# The Sirens' island: a low green meadow.
	var meadow := Island.new(SIRENS, Vector2(95.0, 70.0), 14.0, 21)
	meadow.meadow = 1.0
	sea_world.add_island(meadow)
	# Scylla's rock: a sheer cliff whose peak is lost in cloud.
	var cliff := Island.new(SCYLLA, Vector2(160.0, 300.0), 160.0, 33)
	cliff.cliffs = 1.0
	sea_world.add_island(cliff)
	# Charybdis's rock: low, with a great fig tree on it.
	var low := Island.new(CHARYBDIS_ROCK, Vector2(60.0, 45.0), 9.0, 41)
	sea_world.add_island(low)
	var fig := MeshInstance3D.new()
	fig.mesh = Props.tree_mesh("fig", 5)
	fig.scale = Vector3.ONE * 2.6
	sea_world.add_child(fig)
	fig.position = Vector3(CHARYBDIS_ROCK.x + 10.0, low.height(CHARYBDIS_ROCK.x + 10.0, CHARYBDIS_ROCK.y) - 0.3, CHARYBDIS_ROCK.y)
	# The island of the Sun, far ahead.
	sea_world.add_island(Island.new(SUN_ISLE, Vector2(260.0, 160.0), 40.0, 5))


var _mouth := Vector3.INF


## The mouth of Scylla's cave, halfway up her cliff, facing the strait:
## found by walking in from the sea until the cliff stands that high.
func _cave_mouth() -> Vector3:
	if _mouth == Vector3.INF:
		var x := SCYLLA.x - 260.0
		while sea_world.ground_height(x, SCYLLA.y) < 62.0 and x < SCYLLA.x:
			x += 1.0
		_mouth = Vector3(x - 1.5, 62.0, SCYLLA.y)
	return _mouth


func prepare() -> void:
	ship.place(START, 0.0)
	board(ship.helm, true)
	var mouth := MeshInstance3D.new()
	var dark := SphereMesh.new()
	dark.radius = 9.0
	dark.height = 12.0
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.02, 0.02, 0.025)
	m.roughness = 1.0
	dark.material = m
	mouth.mesh = dark
	add_child(mouth)
	mouth.global_position = _cave_mouth() + Vector3(-2.0, 0.0, 0.0)
	mouth.scale = Vector3(0.4, 1.0, 1.0)


func _physics_process(delta: float) -> void:
	if ended or ship == null:
		return
	# The song pulls the eyes toward the island; looking at it feeds the longing.
	if _resisting:
		var isle := Vector3(SIRENS.x, 4.0, SIRENS.y)
		var err := player._aim_error(isle)
		player.add_look(clampf(err.x, -1.0, 1.0) * 0.5 * delta, 0.0)
		var looking := absf(err.x) < 0.45
		_longing = clampf(_longing + (0.22 if looking else -0.12) * delta, 0.0, 1.0)
		hud.set_meter("THE SONG", _longing)
		# The longer he listens, the harder he strains at the ropes.
		player.action_drive = maxf(player.action_drive - delta * 0.8, smoothstep(0.35, 1.0, _longing))
	# Charybdis: sucking down, then spewing out, and drawing the ship in.
	if _whirl_on:
		_whirl_t += delta
		var cycle := fposmod(_whirl_t, SUCK + SPEW)
		var sucking := cycle < SUCK
		var depth := 8.0 * sin(PI * minf(cycle / SUCK, 1.0)) if sucking else 0.0
		sea_world.sea.vortex = Vector4(WHIRL.x, WHIRL.y, 42.0, depth)
		var to := Vector3(WHIRL.x, 0.0, WHIRL.y) - ship.global_position
		to.y = 0.0
		var d := to.length()
		# The flow she makes: in toward her eye and round it, strongest close.
		ship.current = Vector3.ZERO
		if sucking and d < 160.0:
			var pull := depth / 8.0 * 4.2 * clampf(1.0 - d / 160.0, 0.0, 1.0) ** 1.5
			var swirl := Vector3(-to.z, 0.0, to.x).normalized()
			ship.current = to.normalized() * pull + swirl * pull * 0.6
			# Close to her, the churning water flies over the side.
			if d < 80.0 and randf() < delta * 1.2 * (1.0 - d / 80.0):
				lens.splash(0.2 + 0.4 * (1.0 - d / 80.0))
			if d < 20.0 and depth > 4.0 and not autoplay and not Game.args.has("god"):
				fail(text("charybdis_title"), text("charybdis_text"), "text_charybdis_text")
		elif not sucking and d < 90.0:
			ship.current = -to.normalized() * 1.2


func run() -> void:
	hud.set_fade(1.0)
	Sfx.music(&"sea")
	Sfx.ambience(&"sea")
	scene_begin()
	await wait(0.5)
	hud.fade(0.0, 2.0 if not autoplay else 0.1)
	await card(9.0)
	scene_end()
	objective("sirens", Vector3(0.0, 0.0, 160.0))
	mark("sailing")
	await sail_to(Vector3(0.0, 0.0, 160.0), 40.0)

	# Wax, and the mast.
	ship.speed = 0.0
	ship.controlled = false
	scene_begin()
	await speak("warn")
	scene_end()
	var wax := add_interactable(Vector3.ZERO, "Knead the wax", 2.0, 3.0, 0.0)
	wax.reparent(ship.helm, false)
	wax.position = Vector3(0.6, 0.6, -1.0)
	wax.action = &"wax"
	objective("wax", wax)
	await used(wax)
	wax.queue_free()
	hud.set_objective("")
	await hud.fade(1.0, 0.8 if not autoplay else 0.05)
	# To the mast: two of the crew bind him to it, turn on turn.
	board(ship.mast_spot, false)
	player.rotation.y = 0.0
	ship.set_sail(false)
	ship.max_speed = 3.2
	ship.autopilot_to = Vector3(0.0, 0.0, -420.0)
	var binders: Array[Humanoid] = []
	for side: float in [-1.0, 1.0]:
		# Either side of him, a little forward, working round him and the mast.
		var at := Vector3(side * 0.75, 0.14, -1.7)
		var h := ship.add_hand(at, atan2(at.x, at.z + 1.2), 40 + int(side))
		h.stance = &"tie"
		binders.append(h)
	player.set_action(&"bound")
	hud.fade(0.0, 0.8 if not autoplay else 0.05)
	scene_begin()
	# The turns of rope go on while the story is told.
	var tie := func() -> void:
		for i in 5:
			await wait(0.9)
			ship.show_bonds(i + 1)
			Sfx.play(&"pickup", -12.0)
	tie.call()
	mark("tying")
	await speak("wax")
	await wait(0.5)
	ship.show_bonds(5)
	# Their work done, they go to the benches left empty and take up the oars.
	await hud.fade(1.0, 0.4 if not autoplay else 0.05)
	ship.man_station(binders[0], 1)
	ship.man_station(binders[1], Ship.OARS_A_SIDE + 1)
	hud.fade(0.0, 0.5 if not autoplay else 0.05)
	await speak("calm")
	scene_end()

	# The song.
	Sfx.music(&"sirens")
	objective("resist")
	hud.toast(text("hint_resist"), 8.0)
	mark("song")
	_resisting = true
	var lines := ["siren_1", "siren_2", "siren_3"]
	var i := 0
	while ship.global_position.z > -330.0 and not autoplay:
		if i < lines.size():
			await speak(lines[i])
			i += 1
		else:
			await wait(0.5)
		if _longing >= 1.0:
			_struggles += 1
			player._shake = 0.6
			player.action_drive = 1.0
			await speak("struggle")
			await speak("tighter")
			_longing = 0.3
	_resisting = false
	hud.set_meter("", -1.0)
	hud.set_objective("")
	Sfx.music(&"sea")
	scene_begin()
	await speak("passed")
	scene_end()

	# The strait. Set free, he goes back to the steering oar.
	await hud.fade(1.0, 0.6 if not autoplay else 0.05)
	ship.show_bonds(0)
	ship.autopilot_to = null
	ship.max_speed = 5.0
	board(ship.helm, true)
	hud.fade(0.0, 0.6 if not autoplay else 0.05)
	Sfx.music(&"odyssey")
	Sfx.ambience(&"strait")
	scene_begin()
	await speak("strait_warn")
	scene_end()
	objective("strait", Vector3(20.0, 0.0, -760.0))
	hud.toast(text("hint_strait"), 9.0)
	_whirl_on = true
	await sail_to(Vector3(20.0, 0.0, -760.0), 50.0)
	objective("scylla", Vector3(SCYLLA.x - 175.0, 0.0, SCYLLA.y + 40.0))
	mark("strait")
	await speak("charybdis")
	await until(func() -> bool: return ship.global_position.z < SCYLLA.y + 30.0 or autoplay)
	await _scylla()
	await speak("scylla")
	await speak("pitiful")
	objective("through", EXIT)
	await sail_to(EXIT, 60.0)
	_whirl_on = false
	ship.current = Vector3.ZERO
	sea_world.sea.vortex = Vector4.ZERO
	hud.set_objective("")
	Sfx.music(&"lament")
	scene_begin()
	await speak("through")
	scene_end()
	await hud.fade(1.0, 2.5)
	complete(text("end_title"), text("end_text"))


## Six necks dart down from the cave and each takes a man from his bench.
func _scylla() -> void:
	var mouth := _cave_mouth()
	var victims := ship.rowers.slice(maxi(ship.rowers.size() - 6, 0))
	for k in victims.size():
		var neck := _neck()
		add_child(neck)
		_necks.append(neck)
	Sfx.play_at(&"roar", mouth, 8.0)
	var t := 0.0
	var reach_time := 0.9
	var hold := 0.35
	var back := 1.3
	var taken := false
	while t < reach_time + hold + back:
		await get_tree().physics_frame
		t += get_physics_process_delta_time() * (10.0 if autoplay else 1.0)
		var k := 0.0
		if t < reach_time:
			k = smoothstep(0.0, 1.0, t / reach_time)
		elif t < reach_time + hold:
			k = 1.0
			if not taken:
				taken = true
				for v in victims:
					if is_instance_valid(v):
						Sfx.play_at(&"death", v.global_position + Vector3(0, 1, 0))
				ship.lose_rowers(victims.size())
				player._shake = 0.8
		else:
			k = 1.0 - smoothstep(0.0, 1.0, (t - reach_time - hold) / back)
		for n in _necks.size():
			var bench := ship.global_position + ship.global_transform.basis * Vector3((-0.85 if n % 2 == 0 else 0.85), 1.2, -6.0 + int(n / 2) * 2.4)
			_pose_neck(_necks[n], mouth + Vector3(0, (n - 2.5) * 1.5, (n - 2.5) * 2.0), bench, k, n)
	for n in _necks:
		n.queue_free()
	_necks.clear()


## A neck: a chain of scaled segments ending in a head with rows of teeth.
func _neck() -> Node3D:
	var root := Node3D.new()
	var seg := SphereMesh.new()
	seg.radius = 0.5
	seg.height = 1.0
	seg.radial_segments = 8
	seg.rings = 4
	var skin := StandardMaterial3D.new()
	skin.albedo_color = Color(0.22, 0.26, 0.22)
	skin.roughness = 0.45
	seg.material = skin
	for i in 22:
		var mi := MeshInstance3D.new()
		mi.mesh = seg
		root.add_child(mi)
	var head := MeshInstance3D.new()
	var gb := GeoBuilder.new()
	gb.chunk_size = 0.0
	var skull := func(u: float, v: float) -> Vector3:
		var th := PI * v
		return Vector3(sin(th) * cos(u * TAU) * 0.7, sin(th) * sin(u * TAU) * 0.55, -cos(th) * 1.6)
	Sculpt.grid(gb, &"skin", 12, 8, skull, Color(0.22, 0.26, 0.22), true, null)
	# Three rows of teeth, thick and close set (Odyssey 12.91-92).
	for row in 3:
		for j in 9:
			var a := lerpf(-1.2, 1.2, j / 8.0)
			var at := Vector3(sin(a) * (0.55 - row * 0.08), -0.08 - row * 0.05, -0.6 - cos(a) * 0.9 + row * 0.25)
			Sculpt.lathe(gb, &"ivory", Transform3D(Basis(Vector3.RIGHT, PI), at), PackedVector2Array([Vector2(0.07, 0.0), Vector2(0.0, 0.28)]), 5,
				Color(0.92, 0.88, 0.76), 1.0, 1)
	head.mesh = gb.build_mesh(Mats.all())
	head.name = "Head"
	root.add_child(head)
	return root


func _pose_neck(neck: Node3D, from: Vector3, to: Vector3, k: float, n: int) -> void:
	var tip := from.lerp(to, k)
	var ctrl := from + (to - from) * 0.35 + Vector3(0, 25.0 * (1.0 - k * 0.5), 0) + Vector3(0, 0, (n - 2.5) * 3.0)
	var count := neck.get_child_count() - 1
	for i in count:
		var s := float(i) / count
		var p := from.lerp(ctrl, s).lerp(ctrl.lerp(tip, s), s)
		var seg := neck.get_child(i) as Node3D
		seg.global_position = p
		seg.scale = Vector3.ONE * lerpf(2.4, 1.1, s)
	var head := neck.get_node("Head") as Node3D
	head.global_position = tip
	var dir := (tip - ctrl).normalized()
	if dir.length_squared() > 0.1:
		head.look_at(tip + dir, Vector3.UP)
