extends Control
class_name SkillButton

signal pressed

const GameTheme = preload("res://scripts/ui/game_theme.gd")
const TouchLayout = preload("res://scripts/ui/touch_layout.gd")

var slot := "q"
var key_text := "Q"
var skill_name := "技能"
var cooldown := 0.0
var cooldown_total := 1.0
var available := true
var disabled := false
var accent := GameTheme.GOLD
var touch_mode := false
var _hovered := false

func _ready() -> void:
	custom_minimum_size = TouchLayout.SKILL_TOUCH_SIZE if touch_mode else TouchLayout.SKILL_DESKTOP_SIZE
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	focus_mode = Control.FOCUS_NONE
	mouse_entered.connect(_on_hover.bind(true))
	mouse_exited.connect(_on_hover.bind(false))
	tooltip_text = "释放技能"

func _on_hover(value: bool) -> void:
	_hovered = value
	queue_redraw()

func _gui_input(event: InputEvent) -> void:
	if disabled:
		return
	if touch_mode:
		if event is InputEventScreenTouch:
			var touch := event as InputEventScreenTouch
			if touch.pressed:
				pressed.emit()
				accept_event()
		return
	if event is InputEventMouseButton:
		var mouse := event as InputEventMouseButton
		if mouse.button_index == MOUSE_BUTTON_LEFT and mouse.pressed:
			pressed.emit()
			accept_event()

func set_state(new_cooldown: float, new_total: float, new_name: String, can_use: bool, is_disabled: bool) -> void:
	cooldown = new_cooldown
	cooldown_total = maxf(new_total, 0.01)
	skill_name = new_name
	available = can_use
	disabled = is_disabled
	queue_redraw()

func _draw() -> void:
	var font := GameTheme.FONT_REGULAR
	var center := Vector2(size.x * 0.5, 44.0)
	var radius := 35.0
	var key_size := 34
	var cooldown_size := 20
	var name_y := 96.0
	var status_y := 110.0
	var name_size := 14
	var status_size := 11
	if touch_mode:
		radius = minf(size.x * 0.5 - 8.0, size.y * 0.5 - 16.0)
		center = Vector2(size.x * 0.5, radius + 4.0)
		key_size = 40
		cooldown_size = 24
		name_y = size.y - 14.0
		status_y = size.y - 1.0
		name_size = 16
		status_size = 12
	var border := accent
	if disabled:
		border = Color(0.35, 0.38, 0.4, 0.7)
	elif not available:
		border = Color(0.4, 0.45, 0.5, 0.8)
	elif _hovered:
		border = GameTheme.GOLD_LIGHT

	draw_circle(center + Vector2(0, 4), radius + 3.0, Color(0.0, 0.0, 0.0, 0.5))
	draw_circle(center, radius, Color(0.035, 0.06, 0.08, 0.96))
	draw_circle(center, radius - 5.0, Color(0.06, 0.1, 0.13, 0.9))
	if not disabled and available:
		var glow := accent
		glow.a = 0.08
		draw_circle(center, radius - 2.0, glow)

	if cooldown > 0.001:
		var fraction := clampf(cooldown / cooldown_total, 0.0, 1.0)
		var points := PackedVector2Array()
		points.append(center)
		var steps := 26
		for i in steps + 1:
			var angle := -PI * 0.5 + TAU * fraction * (float(i) / float(steps))
			points.append(center + Vector2(cos(angle), sin(angle)) * (radius - 1.0))
		draw_colored_polygon(points, Color(0.0, 0.01, 0.02, 0.74))
		var text := "%.1f" % cooldown
		draw_string(font, center + Vector2(-radius, cooldown_size * 0.35), text, HORIZONTAL_ALIGNMENT_CENTER, radius * 2.0, cooldown_size, Color(0.95, 0.96, 1.0))
	else:
		var key_color := GameTheme.GOLD_LIGHT if available and not disabled else GameTheme.MUTED
		draw_string(font, center + Vector2(-radius, key_size * 0.38), key_text, HORIZONTAL_ALIGNMENT_CENTER, radius * 2.0, key_size, key_color)

	draw_arc(center, radius, 0.0, TAU, 48, border, 2.0, true)
	var name_color := GameTheme.TEXT if not disabled else GameTheme.MUTED
	draw_string(font, Vector2(0, name_y), skill_name, HORIZONTAL_ALIGNMENT_CENTER, size.x, name_size, name_color)
	if not available and not disabled:
		draw_string(font, Vector2(0, status_y), "法力不足", HORIZONTAL_ALIGNMENT_CENTER, size.x, status_size, Color(0.45, 0.62, 0.95))
