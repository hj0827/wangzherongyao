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
