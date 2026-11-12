extends Node
## Entry scene. Starts the menu, or jumps straight into a mission when asked
## to on the command line (used by the screenshot harness).


func _ready() -> void:
	Game.main = self
	var world := TroyWorld.new()
	add_child(world)
	world.build(Game.args.get("preset", "day"), Game.settings["quality"])
	var cam := Camera3D.new()
	cam.far = 9000.0
	cam.fov = 70.0
	add_child(cam)
	# --cams="x,y,z,yaw,pitch;..." renders one screenshot per camera.
	var cams: PackedStringArray = (Game.args.get("cams", "-60,60,260,-0.25,-0.3") as String).split(";")
	cam.make_current()
	var frames := int(Game.args.get("frames", "30"))
	for ci in cams.size():
		var c: PackedStringArray = cams[ci].split(",")
		cam.position = Vector3(float(c[0]), float(c[1]), float(c[2]))
		cam.rotation = Vector3(float(c[4]), float(c[3]), 0.0)
		if not Game.args.has("shot"):
			break
		for i in frames if ci == 0 else 6:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		var path: String = (Game.args["shot"] as String).replace(".png", "_%d.png" % ci)
		img.save_png(path)
		print("shot saved: ", path)
	if Game.args.has("shot"):
		get_tree().quit()
