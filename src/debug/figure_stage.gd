extends Node3D
## Debug stage: a line-up of every outfit in a few poses, for screenshots.
## Launched with `-- --scene=figures`.


func _ready() -> void:
	var atmo := Atmosphere.new()
	add_child(atmo)
	atmo.apply(Game.args.get("preset", "day"), Game.settings["quality"])
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(80, 80)
	ground.mesh = plane
	ground.material_override = Mats.get_mat(&"paving")
	add_child(ground)
	var outfits: Dictionary = Data.characters.get("outfits", {})
	var ids := ["odysseus", "menelaus", "diomedes", "patroclus", "achaean", "achaean", "achaean", "myrmidon",
		"hector", "deiphobus", "paris", "trojan", "trojan", "trojan", "trojan_watch", "andromache", "townswoman",
		"townsman", "priam"]
	var stances: Array[StringName] = [&"guard", &"guard", &"guard", &"guard", &"guard", &"sentry", &"guard", &"guard",
		&"guard", &"guard", &"idle", &"guard", &"sentry", &"guard", &"sit", &"hold_child", &"idle", &"idle", &"idle"]
	for i in ids.size():
		var h := Humanoid.new()
		add_child(h)
		var weapon := "spear"
		if ids[i] in ["andromache", "townswoman", "townsman", "priam"]:
			weapon = ""
		elif i % 5 == 2:
			weapon = "sword"
		h.setup(ids[i], outfits.get(ids[i], {}), i, weapon)
		h.stance = stances[i]
		var row := i / 10
		h.position = Vector3((i % 10) * 1.5 - 6.75, 0, -row * 2.4)
		h.rotation.y = PI
		if i == 6:
			h.blocking = true
		if i == 7:
			h.speed = 4.0
		if i == 13:
			h.lie_dead(true)
