extends Node
## Autoload "Game": boot arguments, settings, input map and screen flow.

signal settings_changed

const SETTINGS_PATH := "user://settings.cfg"

## Command-line user arguments (after `--`), as key -> value.
var args: Dictionary = {}
var settings: Dictionary = {
	"mouse_sensitivity": 1.0, "fov": 75.0, "blood": true, "quality": 1,
	"master_volume": 0.8, "fullscreen": true, "invert_y": false, "head_bob": true,
}
var main: Node


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for raw in OS.get_cmdline_user_args():
		var a := raw.trim_prefix("--")
		var eq := a.find("=")
		if eq >= 0:
			args[a.substr(0, eq)] = a.substr(eq + 1)
		else:
			args[a] = "1"
	if args.has("quality"):
		settings["quality"] = int(args["quality"])


## True when the game was started by the automated capture or test harness.
func is_harness() -> bool:
	return args.has("shot") or args.has("autoplay")
