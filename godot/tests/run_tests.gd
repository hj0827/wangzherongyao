extends SceneTree

# 自动发现 res://tests/test_*.gd 并逐个跑里面的 test_* 方法。
# 不维护硬编码清单：新增测试文件即生效，TDD 时「先写测试」不会因为忘记注册而被静默跳过。
# test_base.gd 是基类（不是用例），排除。

const TEST_DIR := "res://tests"
const EXCLUDE := ["test_base.gd"]

func _discover_tests() -> Array[String]:
	var files: Array[String] = []
	var dir := DirAccess.open(TEST_DIR)
	if dir == null:
		push_error("Cannot open test directory: " + TEST_DIR)
		return files
	for name in dir.get_files():
		if not name.begins_with("test_") or not name.ends_with(".gd"):
			continue
		if EXCLUDE.has(name):
			continue
		files.append(TEST_DIR + "/" + name)
	files.sort()
	return files

func _initialize() -> void:
	var total := 0
	var failed := 0
	var failures: Array[String] = []
	var test_files := _discover_tests()
	if test_files.is_empty():
		print("FAILED: no test_*.gd found under ", TEST_DIR)
		quit(1)
		return
	for path in test_files:
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
