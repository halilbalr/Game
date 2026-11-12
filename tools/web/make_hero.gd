extends SceneTree
## Crops the HUD out of a retained screenshot and saves it as the JPEG used
## behind the Artifact page's title card.
##   godot --headless --path . -s res://tools/web/make_hero.gd -- <in.png> <out.jpg>


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var img := Image.load_from_file(args[0])
	# Keep the middle of the frame: objective text, bars and weapon line fall outside it.
	var region := Rect2i(int(img.get_width() * 0.10), int(img.get_height() * 0.14),
		int(img.get_width() * 0.90), int(img.get_height() * 0.72))
	var crop := img.get_region(region)
	crop.resize(1100, int(1100.0 * crop.get_height() / crop.get_width()), Image.INTERPOLATE_LANCZOS)
	crop.save_jpg(args[1], 0.7)
	print("hero: %dx%d" % [crop.get_width(), crop.get_height()])
	quit()
