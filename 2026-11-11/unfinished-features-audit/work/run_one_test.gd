extends SceneTree

const SUITE := "res://tests/test_mobile_ui.gd"
const FILTER := "test_"

func _initialize() -> void:
	var script: Script = load(SUITE)
	var probe: Object = script.new()
	var failed := 0
	var ran := 0
	for method in probe.get_method_list():
		var name: String = method.get("name", "")
		if not name.begins_with("test_") or not name.contains(FILTER):
			continue
		ran += 1
		var suite: Object = script.new()
		suite.set("current_test", name)
		suite.call(name)
		var errors: Array = suite.get("failures")
		if errors.is_empty():
			print("  PASS  ", name)
		else:
			failed += 1
			for message in errors:
				print("  FAIL  ", name, " -> ", message)
	print("RAN: %d  FAILED: %d" % [ran, failed])
	quit(0 if failed == 0 else 1)
