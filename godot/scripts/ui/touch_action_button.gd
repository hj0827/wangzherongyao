extends Control
class_name TouchActionButton

signal pressed
signal released

const GameTheme = preload("res://scripts/ui/game_theme.gd")

var label := "攻击"
var hint := ""
var accent := GameTheme.GOLD
var touch_mode := true
var disabled := false
var held := false

var _touch_index := -1

func _ready() -> void:
	focus_mode = Control.FOCUS_NONE
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

func _gui_input(event: InputEvent) -> void:
	if disabled:
		return
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed and _touch_index == -1:
			_touch_index = touch.index
			_set_held(true)
			accept_event()
		elif not touch.pressed and touch.index == _touch_index:
			_touch_index = -1
			_set_held(false)
			accept_event()
	elif touch_mode:
		return
	elif event is InputEventMouseButton:
		var mouse := event as InputEventMouseButton
		if mouse.button_index == MOUSE_BUTTON_LEFT:
			_set_held(mouse.pressed)
			accept_event()

func reset() -> void:
	_touch_index = -1
	_set_held(false)

func _set_held(value: bool) -> void:
	if held == value:
		return
	held = value
	queue_redraw()
	if held:
		pressed.emit()
	else:
		released.emit()

func _draw() -> void:
	var center := size * 0.5
	var radius := minf(size.x, size.y) * 0.5 - 4.0
	var border := accent
	if disabled:
		border = Color(0.36, 0.39, 0.42, 0.7)
	elif held:
		border = GameTheme.GOLD_LIGHT
	draw_circle(center + Vector2(0, 5), radius + 2.0, Color(0.0, 0.0, 0.0, 0.42))
	draw_circle(center, radius, Color(0.03, 0.055, 0.075, 0.9))
	draw_circle(center, radius - 5.0, Color(0.07, 0.11, 0.14, 0.94))
	if not disabled:
		var glow := accent
		glow.a = 0.35 if held else 0.1
		draw_circle(center, radius - 3.0, glow)
	draw_arc(center, radius, 0.0, TAU, 56, border, 3.0 if held else 2.0, true)
	var font_size := 24 if size.x >= 120.0 else 18
	draw_string(GameTheme.FONT_REGULAR, center + Vector2(-radius, 4.0 + font_size * 0.35), label, HORIZONTAL_ALIGNMENT_CENTER, radius * 2.0, font_size, GameTheme.TEXT if not disabled else GameTheme.MUTED)
	if hint != "":
		draw_string(GameTheme.FONT_REGULAR, center + Vector2(-radius, radius - 8.0), hint, HORIZONTAL_ALIGNMENT_CENTER, radius * 2.0, 11, Color(0.62, 0.68, 0.73, 0.8))
