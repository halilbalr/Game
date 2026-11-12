extends Mission
## Debug arena: two war bands meet on the plain. Used to test combat AI.
## Launched with `-- --scene=arena`; with --autoplay it reports the winner and quits.

var _achaeans: Array[Soldier] = []
var _trojans: Array[Soldier] = []


func _init() -> void:
	id = "arena"
	hero = "hector"
	preset = "day"


func prepare() -> void:
	var oak := world.marker("oak")
	place_player(oak + Vector3(6, 0.3, 14), yaw_to(oak + Vector3(6, 0, 14), oak))
	player.invulnerable = Game.args.has("spectate")
	_trojans = spawn_group(["trojan_spearman", "trojan_swordsman", "trojan_spearman"], 8, oak + Vector3(0, 0, 10), 4.0, PI)
	_achaeans = spawn_group(["achaean_spearman", "achaean_swordsman", "myrmidon"], 8, oak + Vector3(-22, 0, -6), 4.0, 0.0)


func run() -> void:
	hud.set_objective("Arena: Trojans against Achaeans")
	var t0 := Time.get_ticks_msec()
	await until(func() -> bool:
		var over := battle.living(&"achaean").is_empty() or battle.living(&"trojan").is_empty()
		return over or Time.get_ticks_msec() - t0 > 60000)
	print("ARENA RESULT: achaeans %d, trojans %d, %.1f s" % [battle.living(&"achaean").size(),
		battle.living(&"trojan").size(), (Time.get_ticks_msec() - t0) * 0.001])
	if Game.args.has("autoplay"):
		get_tree().quit(0)
