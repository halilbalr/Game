extends Node
## Harness only (`--bot`): plays the mission through the real input path.
## Walks to the objective marker along the navigation mesh, fights what it
## meets, and holds Use on anything it can use. It cannot sneak.

var mission: Mission
var _tick: int = 0
var _path := PackedVector3Array()
var _path_i: int = 0
var _repath: int = 0
var _last_pos := Vector3.ZERO
var _stuck: int = 0


func _release() -> void:
	for action: StringName in [&"move_forward", &"attack", &"throw", &"block", &"interact", &"sprint", &"move_left"]:
		Input.action_release(action)


func _physics_process(_delta: float) -> void:
	var p := mission.player
	if mission.ended or not p.is_alive() or not p.control_enabled:
		_release()
		return
	p.bot_control = true
	_tick += 1
	if _tick % 900 == 0:
		print("bot t=%ds pos=%s objective='%s' focus=%s enemies=%d allies=%d" % [_tick / 60, str(p.global_position.round()),
			mission.hud.objective_text(), str(p.focus != null), mission.battle.enemies_of(p.side).size(),
			mission.battle.living(p.side).size()])
		if Game.args.has("verbose"):
			for e in mission.battle.enemies_of(p.side):
				var s := e as Soldier
				if s != null and s.global_position.distance_to(p.global_position) < 45.0:
					print("   enemy %s at %s d=%.1f aware=%s asleep=%s state=%d hold=%s" % [s.name, str(s.global_position.round()),
						s.global_position.distance_to(p.global_position), str(s.aware), str(s.asleep), s.state, str(s.hold)])
	Input.action_release(&"attack")
	Input.action_release(&"throw")
	if p.focus != null:
		Input.action_press(&"interact")
	else:
		Input.action_release(&"interact")
	var here := p.global_position
	var enemy := mission.battle.nearest_enemy(here, p.side, 40.0)
	var goal := mission.hud.marker_position()
	var dest := Vector3.INF
	var fight := false
	if enemy != null and (goal == Vector3.INF or here.distance_to(enemy.global_position) < 13.0):
		dest = enemy.global_position
		fight = true
	elif goal != Vector3.INF:
		dest = goal
	if dest == Vector3.INF or not p.move_enabled:
		Input.action_release(&"move_forward")
		# Seated or held in talk: at least look where the script points.
		if goal != Vector3.INF and not p.move_enabled:
			p.look_toward(goal + Vector3(0, 0.6, 0))
		return
	_repath -= 1
	if _repath <= 0:
		_repath = 24
		_path = NavigationServer3D.map_get_path(p.get_world_3d().navigation_map, here, dest, true)
		_path_i = 1
	while _path_i < _path.size() and Vector2(here.x - _path[_path_i].x, here.z - _path[_path_i].z).length() < 1.1:
		_path_i += 1
	var next := dest
	if _path_i < _path.size():
		next = _path[_path_i]
	var dist := here.distance_to(dest)
	if fight and dist < 3.4:
		p.look_toward(enemy.global_position + Vector3(0, 1.2, 0))
	elif p.focus != null:
		p.look_toward(p.focus.focus_point())
	else:
		p.look_toward(Vector3(next.x, p.eye_position().y, next.z))
	var reach := float(Data.weapons.get(p.current_weapon(), {}).get("reach", 1.8))
	var arrived := (fight and dist < reach * 0.72) or (not fight and dist < 1.6)
	if arrived:
		Input.action_release(&"move_forward")
		Input.action_release(&"sprint")
	else:
		Input.action_press(&"move_forward")
		if not fight:
			Input.action_press(&"sprint")
	if fight and dist < reach + 0.15 and _tick % 42 == 0:
		Input.action_press(&"attack")
	if fight and _tick % 160 > 118 and dist < 4.0:
		Input.action_press(&"block")
	else:
		Input.action_release(&"block")
	# Sidestep when wedged against something.
	if _tick % 30 == 0:
		if not arrived and here.distance_to(_last_pos) < 0.25:
			_stuck += 1
		else:
			_stuck = 0
		_last_pos = here
	if _stuck >= 2:
		Input.action_press(&"move_left")
		_repath = 0
	else:
		Input.action_release(&"move_left")
