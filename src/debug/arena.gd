extends Mission
## Debug arena: two war bands meet on the plain. Used to test combat.
## Launched with `-- --scene=arena`. With --autoplay it reports the result and
## quits; with --bot a scripted player fights through the real input path;
## with --spectate the player cannot be hurt.

var _achaeans: Array[Soldier] = []
var _trojans: Array[Soldier] = []
var _tick: int = 0
var _start_frame: int = 0


func _init() -> void:
	id = "arena"
	hero = "hector"
	preset = "day"


func prepare() -> void:
	var oak := world.marker("oak")
	place_player(oak + Vector3(6, 0.3, 14), yaw_to(oak + Vector3(6, 0, 14), oak))
	player.invulnerable = Game.args.has("spectate")
	player.bot_control = Game.args.has("bot")
	var size := int(Game.args.get("size", "8"))
	var allies := int(Game.args.get("allies", str(size)))
	if allies > 0:
		_trojans = spawn_group(["trojan_spearman", "trojan_swordsman", "trojan_spearman"], allies, oak + Vector3(0, 0, 10), 4.0, PI)
	_achaeans = spawn_group(["achaean_spearman", "achaean_swordsman", "myrmidon"], size, oak + Vector3(-22, 0, -6), 4.0, 0.0)
	_start_frame = Engine.get_physics_frames()


func _physics_process(_delta: float) -> void:
	if not player.bot_control or ended:
		return
	_tick += 1
	for action: StringName in [&"attack", &"throw"]:
		Input.action_release(action)
	if not player.is_alive():
		Input.action_release(&"move_forward")
		return
	var enemy := battle.nearest_enemy(player.global_position, player.side, 80.0)
	if enemy == null:
		Input.action_release(&"move_forward")
		Input.action_release(&"block")
		return
	player.look_toward(enemy.global_position + Vector3(0, 1.2, 0))
	var dist := player.global_position.distance_to(enemy.global_position)
	if dist > 2.3:
		Input.action_press(&"move_forward")
	else:
		Input.action_release(&"move_forward")
	if dist < 2.9 and _tick % 45 == 0:
		Input.action_press(&"attack")
	elif dist > 9.0 and dist < 18.0 and _tick % 150 == 0:
		Input.action_press(&"throw")
	if _tick % 180 > 130 and dist < 4.0:
		Input.action_press(&"block")
	else:
		Input.action_release(&"block")


func run() -> void:
	hud.set_objective("Arena: Trojans against Achaeans")
	var limit := int(Game.args.get("seconds", "90")) * 60
	await until(func() -> bool:
		var over := battle.living(&"achaean").is_empty() or (battle.living(&"trojan").is_empty() and not player.is_alive())
		return over or Engine.get_physics_frames() - _start_frame > limit)
	print("ARENA RESULT: achaeans %d, trojans %d, game time %.1f s, player kills %d, health %.0f, spears %d" % [
		battle.living(&"achaean").size(), battle.living(&"trojan").size(),
		(Engine.get_physics_frames() - _start_frame) / 60.0, player.kills, player.health, player.spears])
	if Game.args.has("autoplay"):
		get_tree().quit(0)
