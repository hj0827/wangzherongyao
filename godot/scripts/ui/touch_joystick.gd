extends Control
class_name TouchJoystick

signal moved(value: Vector2)

const GameTheme = preload("res://scripts/ui/game_theme.gd")

var radius := 94.0
var deadzone := 0.18
var touch_mode := true
var value := Vector2.ZERO

var _touch_index := -1
var _mouse_active := false
var _knob := Vector2.ZERO

func _ready() -> void:
	custom_minimum_size = Vector2(260, 260)
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_NONE

static func stick_vector(center: Vector2, point: Vector2, radius_value: float, deadzone_value: float) -> Vector2:
	if radius_value <= 0.0:
		return Vector2.ZERO
	var offset := point - center
	var length := offset.length()
	var inner := clampf(deadzone_value, 0.0, 0.95) * radius_value
	if length <= inner:
		return Vector2.ZERO
	var strength := clampf((length - inner) / maxf(radius_value - inner, 0.001), 0.0, 1.0)
	return offset / length * strength

func reset() -> void:
	_touch_index = -1
	_mouse_active = false
	_apply(Vector2.ZERO, Vector2.ZERO)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed and _touch_index == -1:
			_touch_index = touch.index
			_update_from(touch.position)
			accept_event()
		elif not touch.pressed and touch.index == _touch_index:
			_touch_index = -1
			_apply(Vector2.ZERO, Vector2.ZERO)
			accept_event()
	elif event is InputEventScreenDrag:
		var drag := event as InputEventScreenDrag
		if drag.index == _touch_index:
			_update_from(drag.position)
			accept_event()
	elif not touch_mode and event is InputEventMouseButton:
		var mouse := event as InputEventMouseButton
		if mouse.button_index == MOUSE_BUTTON_LEFT:
			_mouse_active = mouse.pressed
			if mouse.pressed:
				_update_from(mouse.position)
			else:
				_apply(Vector2.ZERO, Vector2.ZERO)
			accept_event()
	elif not touch_mode and event is InputEventMouseMotion and _mouse_active:
		_update_from((event as InputEventMouseMotion).position)

func _update_from(point: Vector2) -> void:
	var center := size * 0.5
	_apply(stick_vector(center, point, radius, deadzone), (point - center).limit_length(radius))

func _apply(new_value: Vector2, knob: Vector2) -> void:
	if value.is_equal_approx(new_value) and _knob.is_equal_approx(knob):
		return
	value = new_value
	_knob = knob
	queue_redraw()
	moved.emit(value)

func _draw() -> void:
	var center := size * 0.5
	draw_circle(center + Vector2(0, 5), radius + 8.0, Color(0.0, 0.0, 0.0, 0.32))
	draw_circle(center, radius + 6.0, Color(0.02, 0.04, 0.055, 0.72))
	draw_arc(center, radius, 0.0, TAU, 64, Color(0.62, 0.48, 0.24, 0.7), 2.0, true)
	draw_arc(center, radius * 0.62, 0.0, TAU, 48, Color(0.5, 0.4, 0.22, 0.32), 1.0, true)
	var knob_pos := center + _knob
	var knob_radius := 36.0
	draw_circle(knob_pos + Vector2(0, 3), knob_radius, Color(0.0, 0.0, 0.0, 0.4))
	draw_circle(knob_pos, knob_radius, Color(0.09, 0.13, 0.16, 0.96))
	draw_circle(knob_pos, knob_radius - 4.0, Color(0.14, 0.19, 0.22, 0.9))
	var edge := GameTheme.GOLD_LIGHT if value.length() > 0.001 else Color(0.62, 0.48, 0.24, 0.8)
	draw_arc(knob_pos, knob_radius, 0.0, TAU, 40, edge, 2.0, true)
	draw_string(GameTheme.FONT_REGULAR, Vector2(0, size.y - 8.0), "移动", HORIZONTAL_ALIGNMENT_CENTER, size.x, 12, Color(0.72, 0.65, 0.5, 0.75))
