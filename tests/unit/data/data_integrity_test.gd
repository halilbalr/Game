extends TestCase
## The data files agree with each other and with the scripts that read them.

const DIR := "res://assets/data/"


func _json(file: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(DIR + file))
	return parsed if parsed is Dictionary else {}


func test_every_data_file_parses() -> void:
	for file: String in ["tuning.json", "weapons.json", "characters.json", "codex.json", "missions/horse.json",
			"missions/gate.json", "missions/roam.json"]:
		check(not _json(file).is_empty(), file)


func test_every_role_names_an_outfit_and_weapons_that_exist() -> void:
	var chars := _json("characters.json")
	var weapons := _json("weapons.json")
	var outfits: Dictionary = chars["outfits"]
	for role_id: String in chars["roles"]:
		var role: Dictionary = chars["roles"][role_id]
		check(outfits.has(role["outfit"]), "%s outfit %s" % [role_id, role["outfit"]])
		check(str(role["side"]) in ["achaean", "trojan"], "%s side" % role_id)
		check(float(role["health"]) > 0.0, "%s health" % role_id)
		for w: String in role["weapons"]:
			check(weapons.has(w), "%s weapon %s" % [role_id, w])


func test_every_weapon_has_the_numbers_combat_reads() -> void:
	var weapons := _json("weapons.json")
	for id: String in weapons:
		var w: Dictionary = weapons[id]
		for key: String in ["name", "kind", "damage", "reach", "arc_deg", "windup", "strike", "recover", "stamina"]:
			check(w.has(key), "%s.%s" % [id, key])
		check(str(w["kind"]) in ["thrust", "slash", "stab"], "%s kind" % id)
		check(float(w["reach"]) > 0.5 and float(w["reach"]) < 4.0, "%s reach" % id)


func test_spear_outreaches_sword_outreaches_dagger() -> void:
	var w := _json("weapons.json")
	check(float(w["spear"]["reach"]) > float(w["sword"]["reach"]))
	check(float(w["sword"]["reach"]) > float(w["dagger"]["reach"]))
	check(float(w["dagger"]["windup"]) < float(w["sword"]["windup"]), "the dagger is quickest")


func test_no_iron_in_the_armoury() -> void:
	# Pillar 2 of the brief: a real Bronze Age.
	var text := FileAccess.get_file_as_string(DIR + "weapons.json").to_lower()
	check(not "iron" in text and not "steel" in text)


func _referenced_keys(script_path: String, call_name: String) -> Array[String]:
	var out: Array[String] = []
	var re := RegEx.new()
	re.compile(call_name + "\\(\"([a-z_0-9]+)\"")
	for m in re.search_all(FileAccess.get_file_as_string(script_path)):
		out.append(m.get_string(1))
	return out


func test_mission_scripts_only_speak_lines_that_exist() -> void:
	for id: String in ["horse", "gate"]:
		var data := _json("missions/%s.json" % id)
		var path := "res://src/missions/mission_%s.gd" % id
		for key in _referenced_keys(path, "speak"):
			check((data["lines"] as Dictionary).has(key), "%s line '%s'" % [id, key])
		for key in _referenced_keys(path, "objective"):
			check((data["objectives"] as Dictionary).has(key), "%s objective '%s'" % [id, key])
		for key in _referenced_keys(path, "text"):
			check((data["text"] as Dictionary).has(key), "%s text '%s'" % [id, key])


func test_every_spoken_line_has_a_speaker_slot_and_text() -> void:
	for id: String in ["horse", "gate"]:
		var lines: Dictionary = _json("missions/%s.json" % id)["lines"]
		for key: String in lines:
			var entry: Array = lines[key]
			eq(entry.size(), 2, "%s.%s" % [id, key])
			check(str(entry[1]).length() > 3, "%s.%s is empty" % [id, key])


func test_chronicle_places_have_a_name_and_text() -> void:
	var places: Dictionary = _json("codex.json")["places"]
	check(places.size() >= 15)
	for key: String in places:
		check(str(places[key]["name"]) != "" and str(places[key]["text"]).length() > 40, key)


func test_every_effect_the_scripts_play_has_its_files() -> void:
	# Arrange: the effects index, and every sound id named in the scripts.
	var index: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://assets/audio/sfx/index.json"))
	check(index is Dictionary, "assets/audio/sfx/index.json parses")
	if not index is Dictionary:
		return
	var named := {}
	var call := RegEx.create_from_string("Sfx\\.play(?:_at)?\\(&\"([a-z_]+)\"")
	for path: String in _scripts("res://src"):
		for m: RegExMatch in call.search_all(FileAccess.get_file_as_string(path)):
			named[m.get_string(1)] = path
	# Those Sfx chooses itself, by weapon and by what a blow met.
	for id: String in ["whoosh_thrust", "whoosh_slash", "block", "stab", "hit_cut", "hit_pierce", "hit_head"]:
		named[id] = "src/core/sfx.gd"
	# Assert: each is listed, and every listed variant is on disk.
	check(named.size() > 15, "found the sound calls (%d)" % named.size())
	for id: String in named:
		check(index.has(id), "%s (played in %s) is not in the effects index" % [id, named[id]])
	for id: String in index:
		for i in int(index[id]):
			var file := "res://assets/audio/sfx/%s_%d.ogg" % [id, i + 1]
			check(ResourceLoader.exists(file), file)


func test_every_loop_a_screen_asks_for_exists() -> void:
	var call := RegEx.create_from_string("Sfx\\.(music|ambience)\\(&\"([a-z_]+)\"")
	var found := 0
	for path: String in _scripts("res://src"):
		for m: RegExMatch in call.search_all(FileAccess.get_file_as_string(path)):
			var dir := "music" if m.get_string(1) == "music" else "ambience"
			check(ResourceLoader.exists("res://assets/audio/%s/%s.ogg" % [dir, m.get_string(2)]),
				"%s asks for %s '%s'" % [path, dir, m.get_string(2)])
			found += 1
	check(found > 8, "found the music and ambience calls (%d)" % found)


func _scripts(dir: String) -> Array[String]:
	var out: Array[String] = []
	for f: String in DirAccess.get_files_at(dir):
		if f.ends_with(".gd"):
			out.append(dir.path_join(f))
	for d: String in DirAccess.get_directories_at(dir):
		out.append_array(_scripts(dir.path_join(d)))
	return out
