extends SceneTree

const TEST_FILES := [
	"res://tests/test_match.gd",
	"res://tests/test_room_manager.gd",
	"res://tests/test_net_protocol.gd",
	"res://tests/test_net_session.gd",
	"res://tests/test_net_team.gd",
	"res://tests/test_lan_discovery.gd",
	"res://tests/test_mobile_input.gd",
	"res://tests/test_mobile_ui.gd",
	"res://tests/test_motion_smoothing.gd",
]

func _initialize() -> void:
	var total := 0
	var failed := 0
	var failures: Array[String] = []
	for path in TEST_FILES:
		var script: Script = load(path)
		if script == null or not script.can_instantiate():
			failures.append("Cannot load test suite: " + path)
			failed += 1
			continue
		var probe: Object = script.new()
		for method in probe.get_method_list():
			var name: String = method.get("name", "")
			if not name.begins_with("test_"):
				continue
			total += 1
			var suite: Object = script.new()
			suite.set("current_test", name)
			suite.call(name)
			var errors: Array = suite.get("failures")
			if errors.is_empty():
				print("  PASS  ", path.get_file(), " :: ", name)
			else:
				failed += 1
				for message in errors:
					var line := "%s :: %s -> %s" % [path.get_file(), name, message]
					print("  FAIL  ", line)
					failures.append(line)
	print("")
	print("TESTS: %d  PASSED: %d  FAILED: %d" % [total, total - failed, failed])
	if not failures.is_empty():
		print("FAILURES:")
		for message in failures:
			print(" - ", message)
	quit(0 if failed == 0 else 1)
