extends "res://tests/test_base.gd"

const InputAssist = preload("res://scripts/game/input_assist.gd")
const TouchJoystick = preload("res://scripts/ui/touch_joystick.gd")

func test_stick_vector_respects_deadzone() -> void:
	eq(TouchJoystick.stick_vector(Vector2(100, 100), Vector2(100, 100), 100.0, 0.2), Vector2.ZERO, "center is idle")
	eq(TouchJoystick.stick_vector(Vector2(100, 100), Vector2(110, 100), 100.0, 0.2), Vector2.ZERO, "inside deadzone is idle")

func test_stick_vector_direction_and_strength() -> void:
	var half := TouchJoystick.stick_vector(Vector2.ZERO, Vector2(50, 0), 100.0, 0.0)
	near(half.x, 0.5, 0.001, "half tilt x")
	near(half.y, 0.0, 0.001, "half tilt y")
	var up := TouchJoystick.stick_vector(Vector2.ZERO, Vector2(0, -30), 100.0, 0.0)
	near(up.x, 0.0, 0.001, "up keeps x zero")
	near(up.y, -0.3, 0.001, "up keeps direction")

func test_stick_vector_clamps_outside_radius() -> void:
	var full: Vector2 = TouchJoystick.stick_vector(Vector2.ZERO, Vector2(260, 0), 100.0, 0.2)
	near(full.x, 1.0, 0.001, "outside radius clamps to one")
	near(full.y, 0.0, 0.001, "outside radius keeps axis")
	var diagonal: Vector2 = TouchJoystick.stick_vector(Vector2.ZERO, Vector2(141.4, 141.4), 100.0, 0.2)
	near(diagonal.length(), 1.0, 0.001, "diagonal clamps to unit length")
	var flat: Vector2 = TouchJoystick.stick_vector(Vector2.ZERO, Vector2(80, 0), 0.0, 0.0)
	eq(flat, Vector2.ZERO, "zero radius is idle")

func _entities() -> Array:
	return [
		{"type": "hero", "team": "red", "alive": true, "x": 3.0, "y": 0.0},
		{"type": "hero", "team": "red", "alive": true, "x": 6.0, "y": 0.0},
		{"type": "minion", "team": "red", "alive": true, "x": 2.0, "y": 0.0},
		{"type": "hero", "team": "blue", "alive": true, "x": 1.0, "y": 0.0},
		{"type": "hero", "team": "red", "alive": false, "x": 0.5, "y": 0.0},
		{"type": "tower", "team": "red", "alive": true, "x": 4.0, "y": 0.0},
	]

func test_nearest_enemy_prefers_hero_and_skips_allies() -> void:
	var target: Dictionary = InputAssist.nearest_enemy(_entities(), "blue", Vector2.ZERO, 9.0)
	eq(str(target.get("type", "")), "hero", "auto aim prefers a hero")
	near(float(target.get("x", -1.0)), 3.0, 0.001, "nearest living enemy hero")

func test_nearest_enemy_respects_range_and_structures() -> void:
	eq(InputAssist.nearest_enemy(_entities(), "blue", Vector2.ZERO, 1.5), {}, "nothing inside short range")
	var structures_only := [{"type": "tower", "team": "red", "alive": true, "x": 4.0, "y": 0.0}]
	eq(InputAssist.nearest_enemy(structures_only, "blue", Vector2.ZERO, 9.0), {}, "towers excluded by default")
	var tower: Dictionary = InputAssist.nearest_enemy(structures_only, "blue", Vector2.ZERO, 9.0, true)
	eq(str(tower.get("type", "")), "tower", "towers included when requested")

func test_aim_point_prefers_manual_then_auto() -> void:
	var manual: Dictionary = InputAssist.aim_point(Vector2(10, 5), true, _entities(), "blue", Vector2.ZERO, 9.0)
	eq(str(manual.get("source", "")), "manual", "manual aim wins")
	eq(manual.get("aim"), Vector2(10, 5), "manual aim kept")
	var auto: Dictionary = InputAssist.aim_point(Vector2.ZERO, false, _entities(), "blue", Vector2.ZERO, 9.0)
	eq(str(auto.get("source", "")), "auto", "fallback is auto aim")
	near(float(auto.aim.x), 3.0, 0.001, "auto aim targets hero x")
	var none: Dictionary = InputAssist.aim_point(Vector2.ZERO, false, _entities(), "blue", Vector2.ZERO, 1.0)
	eq(str(none.get("source", "")), "none", "no target keeps source none")
	var origin_touch: Dictionary = InputAssist.aim_point(Vector2.ZERO, true, _entities(), "blue", Vector2.ZERO, 9.0)
	eq(str(origin_touch.get("source", "")), "manual", "touching world origin is still manual")

func test_touch_control_detection() -> void:
	check(InputAssist.wants_touch_controls({}, false, true), "touchscreen enables touch controls")
	check(InputAssist.wants_touch_controls({}, true, false), "mobile feature enables touch controls")
	check(not InputAssist.wants_touch_controls({}, false, false), "desktop mouse stays desktop")
	check(InputAssist.wants_touch_controls({"touch_controls": true}, false, false), "config can force touch controls")
	check(not InputAssist.wants_touch_controls({"touch_controls": false}, true, true), "config can force desktop controls")

func test_camera_relative_move_up_follows_camera() -> void:
	var blue_forward := Vector2(1.0, 1.0).normalized()
	var up: Vector2 = InputAssist.camera_relative_move(Vector2(0.0, -1.0), blue_forward)
	near(up.x, blue_forward.x, 0.001, "blue joystick up walks toward the enemy base on x")
	near(up.y, blue_forward.y, 0.001, "blue joystick up walks toward the enemy base on y")
	var red_forward := Vector2(-1.0, -1.0).normalized()
	var red_up: Vector2 = InputAssist.camera_relative_move(Vector2(0.0, -1.0), red_forward)
	near(red_up.x, red_forward.x, 0.001, "red joystick up follows the reversed camera on x")
	near(red_up.y, red_forward.y, 0.001, "red joystick up follows the reversed camera on y")

func test_camera_relative_move_right_and_strength() -> void:
	var forward := Vector2(1.0, 1.0).normalized()
	var right: Vector2 = InputAssist.camera_relative_move(Vector2(1.0, 0.0), forward)
	near(right.x, -forward.y, 0.001, "joystick right maps to camera right on x")
	near(right.y, forward.x, 0.001, "joystick right maps to camera right on y")
	var axis_right: Vector2 = InputAssist.camera_relative_move(Vector2(1.0, 0.0), Vector2(1.0, 0.0))
	near(axis_right.x, 0.0, 0.001, "camera facing +x has no x component on its right")
	near(axis_right.y, 1.0, 0.001, "camera facing +x looks right toward +y")
	var half_up: Vector2 = InputAssist.camera_relative_move(Vector2(0.0, -0.5), forward)
	near(half_up.length(), 0.5, 0.001, "analog strength survives the camera conversion")
	var raw: Vector2 = InputAssist.camera_relative_move(Vector2(0.3, 0.4), Vector2.ZERO)
	eq(raw, Vector2(0.3, 0.4), "missing camera forward falls back to raw stick")
