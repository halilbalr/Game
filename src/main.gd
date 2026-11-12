extends Node
## Entry scene. Opens the menu, or jumps straight to a mission or a debug
## stage when asked on the command line:
##   -- --mission=horse|gate|roam   start a mission directly
##   -- --scene=figures             line-up of outfits
##   -- --shot=/abs/file.png        save screenshots and quit (with --cams, --frames)
##   -- --autoplay                  let the mission script play itself (logic test)


func _ready() -> void:
	Game.main = self
	var scene: String = Game.args.get("scene", "")
	if scene == "figures":
		add_child((load("res://src/debug/figure_stage.gd") as GDScript).new())
	elif scene == "arena":
		add_child((load("res://src/debug/arena.gd") as GDScript).new())
	elif Game.args.has("mission"):
		await Game.start_mission(Game.args["mission"])
	else:
		await Game.start_menu()
	if Game.args.has("shot"):
		await _capture()


func _capture() -> void:
	var frames := int(Game.args.get("frames", "30"))
	var cams: PackedStringArray = PackedStringArray()
	if Game.args.has("cams"):
		cams = (Game.args["cams"] as String).split(";")
	var free_cam: Camera3D = null
	var count := maxi(cams.size(), 1)
	for ci in count:
		if not cams.is_empty():
			# "x,y,z,yaw,pitch": a free camera overriding the scene's own.
			var c := cams[ci].split(",")
			if free_cam == null:
				free_cam = Camera3D.new()
				free_cam.far = 9000.0
				free_cam.fov = float(Game.args.get("fov", "70"))
				add_child(free_cam)
			free_cam.position = Vector3(float(c[0]), float(c[1]), float(c[2]))
			free_cam.rotation = Vector3(float(c[4]), float(c[3]), 0.0)
			free_cam.make_current()
		for i in (frames if ci == 0 else 6):
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		var path: String = (Game.args["shot"] as String).replace(".png", "_%d.png" % ci)
		img.save_png(path)
		print("shot saved: ", path)
	get_tree().quit()
