extends SceneTree
## Runs every `*_test.gd` suite under res://tests and exits 0 when all pass.
##
##   godot --headless --path . -s res://tests/run_tests.gd
##
## Pass a substring after `--` to run only matching suites.


func _initialize() -> void:
	_run.call_deferred()


func _collect(dir_path: String, out: Array[String]) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	for sub in dir.get_directories():
		_collect(dir_path.path_join(sub), out)
	for file in dir.get_files():
		if file.ends_with("_test.gd"):
			out.append(dir_path.path_join(file))


func _run() -> void:
	var filter := ""
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		filter = args[0]
	var suites: Array[String] = []
	_collect("res://tests", suites)
	suites.sort()
	var total := 0
	var failed := 0
	var checks := 0
	for path in suites:
		if filter != "" and not filter in path:
			continue
		var script := load(path) as GDScript
		if script == null or not script.can_instantiate():
			printerr("FAIL  %s: does not load" % path)
			failed += 1
			continue
		var suite := script.new() as TestCase
		suite.tree = self
		for method: Dictionary in script.get_script_method_list():
			var method_name: String = method["name"]
			if not method_name.begins_with("test_"):
				continue
			total += 1
			var before := suite.failures.size()
			suite.begin(method_name)
			await suite.call(method_name)
			if suite.failures.size() > before:
				failed += 1
				for i in range(before, suite.failures.size()):
					printerr("FAIL  %s  %s" % [path.get_file(), suite.failures[i]])
			else:
				print("ok    %s  %s" % [path.get_file(), method_name])
		checks += suite.checks
	print("%d tests, %d checks, %d failed" % [total, checks, failed])
	quit(1 if failed > 0 else 0)
