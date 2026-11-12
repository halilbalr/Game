extends Node
## Autoload "Data": loads the JSON files under assets/data once at boot.
## Gameplay numbers live in those files, not in scripts.

const DIR := "res://assets/data/"

var tuning: Dictionary = {}
var weapons: Dictionary = {}
var characters: Dictionary = {}
var codex: Dictionary = {}
var _missions: Dictionary = {}


func _ready() -> void:
	tuning = load_json(DIR + "tuning.json")
	weapons = load_json(DIR + "weapons.json")
	characters = load_json(DIR + "characters.json")
	codex = load_json(DIR + "codex.json")


## Reads a JSON object from [param path]; returns an empty dictionary on failure.
static func load_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_warning("Data: missing %s" % path)
		return {}
	var text := FileAccess.get_file_as_string(path)
	var parsed: Variant = JSON.parse_string(text)
	if parsed is Dictionary:
		return parsed
	push_error("Data: %s is not a JSON object" % path)
	return {}


## Script and objective text for a mission, by id.
func mission(id: String) -> Dictionary:
	if not _missions.has(id):
		_missions[id] = load_json(DIR + "missions/%s.json" % id)
	return _missions[id]


## A tuning value addressed as "section.key", with a fallback.
func tune(path: String, fallback: Variant = 0.0) -> Variant:
	var node: Variant = tuning
	for part in path.split("."):
		if node is Dictionary and (node as Dictionary).has(part):
			node = (node as Dictionary)[part]
		else:
			return fallback
	return node
