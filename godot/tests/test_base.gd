extends RefCounted

var current_test := ""
var failures: Array[String] = []

func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)

func eq(actual: Variant, expected: Variant, message: String) -> void:
	if actual != expected:
		failures.append("%s (expected %s, got %s)" % [message, str(expected), str(actual)])

func near(actual: float, expected: float, epsilon: float, message: String) -> void:
	if absf(actual - expected) > epsilon:
		failures.append("%s (expected %.3f +/- %.3f, got %.3f)" % [message, expected, epsilon, actual])

func lt(actual: float, expected: float, message: String) -> void:
	if actual >= expected:
		failures.append("%s (expected < %s, got %s)" % [message, str(expected), str(actual)])

func gt(actual: float, expected: float, message: String) -> void:
	if actual <= expected:
		failures.append("%s (expected > %s, got %s)" % [message, str(expected), str(actual)])

# 源码守卫的通用坑：直接 contains("xxx(") 时，把调用**注释掉**字符串还在，
# 守卫照样绿 —— 接线已经断了却测不出来。必须逐行看，跳过注释行。
func has_live_line(source: String, needle: String) -> bool:
	for line in source.split("\n"):
		var trimmed := line.strip_edges()
		if trimmed.begins_with("#"):
			continue
		if trimmed.contains(needle):
			return true
	return false
