extends Control
class_name SkillButton

signal pressed
signal drag_started(slot: String, screen_pos: Vector2)
signal drag_updated(slot: String, screen_pos: Vector2)
signal drag_released(slot: String, screen_pos: Vector2)

const GameTheme = preload("res://scripts/ui/game_theme.gd")
const TouchLayout = preload("res://scripts/ui/touch_layout.gd")
const SkillGlyph = preload("res://scripts/ui/skill_glyph.gd")

## 手游键面：圆占满方框、居中、双层金环、键面上不写字。
##
## 旧皮肤在 128x148 的框里把圆心抬到 y=60，为的是在下面留一行技能名 ——
## 那是键鼠的信息需求（键鼠还得知道按 Q 还是 E）。手游玩家看的是图标，
## 手上也没有 Q/E/R 键，名字和键位角标只会把可点的圆压小。
## 圆心回到正中之后，圆从 112 涨到 116 直径，图标也跟着变大。
const TOUCH_CIRCLE_INSET := 6.0
const TOUCH_OUTER_RING := 3.2
const TOUCH_INNER_RING := 1.6
const TOUCH_RING_GAP := 4.2
const TOUCH_GLYPH_FILL := 0.92
const TOUCH_NAME_SIZE := 14

## 键鼠键面：保持原样（方形卡 + 技能名 + 键位角标）。
const DESKTOP_CENTER_Y := 44.0
const DESKTOP_RADIUS := 35.0
const DESKTOP_NAME_Y := 96.0
const DESKTOP_STATUS_Y := 110.0

var slot := "q"
var key_text := "Q"
var skill_name := "技能"
## 技能族标识（slash/burst/dash…）。图标由它决定，见 skill_glyph.gd。
var skill_kind := ""
var cooldown := 0.0
var cooldown_total := 1.0
var available := true
var disabled := false
var accent := GameTheme.GOLD
var touch_mode := false
var _hovered := false
var _touch_index := -1

## 两套键面的几何唯一真身。绘制和测试都读它，避免「改了 `_draw` 里的数、
## 测试还在验旧值」这种假绿。
## - center / radius：圆盘
## - glyph_fill：图标半径 = radius * glyph_fill
## - ring_outer_width / ring_inner_width / ring_gap：双层金环（内环中心 = radius - gap）
## - show_name / show_key_badge：键面上写不写字
static func skin_metrics(box: Vector2, touch := true) -> Dictionary:
	if touch:
		return {
			"center": box * 0.5,
			"radius": minf(box.x, box.y) * 0.5 - TOUCH_CIRCLE_INSET,
			"glyph_fill": TOUCH_GLYPH_FILL,
			"ring_outer_width": TOUCH_OUTER_RING,
			"ring_inner_width": TOUCH_INNER_RING,
			"ring_gap": TOUCH_RING_GAP,
			"show_name": false,
			"show_key_badge": false,
		}
	return {
		"center": Vector2(box.x * 0.5, DESKTOP_CENTER_Y),
		"radius": DESKTOP_RADIUS,
		"glyph_fill": 1.0,
		"ring_outer_width": 2.0,
		"ring_inner_width": 0.0,
		"ring_gap": 0.0,
		"show_name": true,
		"show_key_badge": true,
	}

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
			if touch.pressed and _touch_index < 0:
				_touch_index = touch.index
				pressed.emit()
				drag_started.emit(slot, touch.position)
				accept_event()
		return
	if event is InputEventMouseButton:
		var mouse := event as InputEventMouseButton
		if mouse.button_index == MOUSE_BUTTON_LEFT and mouse.pressed:
			pressed.emit()
			accept_event()

# 手指移出按钮矩形后 _gui_input 不再收到事件，拖拽/取消必须在全局 _input 里跟。
func _input(event: InputEvent) -> void:
	if not touch_mode or _touch_index < 0:
		return
	if event is InputEventScreenDrag:
		var drag := event as InputEventScreenDrag
		if drag.index == _touch_index:
			drag_updated.emit(slot, drag.position)
	elif event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.index == _touch_index and not touch.pressed:
			_touch_index = -1
			drag_released.emit(slot, touch.position)

func cancel_drag() -> void:
	_touch_index = -1

func set_state(new_cooldown: float, new_total: float, new_name: String, can_use: bool, is_disabled: bool) -> void:
	cooldown = new_cooldown
	cooldown_total = maxf(new_total, 0.01)
	skill_name = new_name
	available = can_use
	disabled = is_disabled
	queue_redraw()

func _draw() -> void:
	var font := GameTheme.FONT_REGULAR
	var skin := skin_metrics(size, touch_mode)
	var center: Vector2 = skin["center"]
	var radius: float = skin["radius"]
	var border := _border_color()

	draw_circle(center + Vector2(0, 4), radius + 3.0, Color(0.0, 0.0, 0.0, 0.5))
	draw_circle(center, radius, Color(0.035, 0.06, 0.08, 0.96))
	draw_circle(center, radius - 5.0, Color(0.06, 0.1, 0.13, 0.9))
	if not disabled and available:
		var glow := accent
		glow.a = 0.08
		draw_circle(center, radius - 2.0, glow)

	# 图标先画，冷却扇形后盖：扇形是半透明的，图标必须在它下面才读得出「正在转」。
	var glyph_color := accent.lightened(0.35)
	glyph_color.a = 0.92
	if disabled:
		glyph_color = GameTheme.MUTED
	elif not available:
		glyph_color = Color(0.52, 0.58, 0.64, 0.8)
	if cooldown > 0.001:
		glyph_color.a = 0.26
	SkillGlyph.paint(self, skill_kind, center, radius * float(skin["glyph_fill"]), glyph_color)

	if cooldown > 0.001:
		_draw_cooldown(center, radius, font)

	_draw_rings(center, radius, skin, border)

	if bool(skin["show_key_badge"]):
		_draw_key_badge(center, radius, font, border)
	if bool(skin["show_name"]) and skill_name != "":
		var name_y := DESKTOP_NAME_Y if not touch_mode else center.y + radius + 18.0
		var name_size := 14 if not touch_mode else TOUCH_NAME_SIZE
		draw_string(
			font,
			Vector2(0, name_y),
			skill_name,
			HORIZONTAL_ALIGNMENT_CENTER,
			size.x,
			name_size,
			GameTheme.TEXT if not disabled else GameTheme.MUTED
		)
	if bool(skin["show_name"]) and not available and not disabled:
		var status_y := DESKTOP_STATUS_Y if not touch_mode else size.y - 2.0
		draw_string(font, Vector2(0, status_y), "法力不足", HORIZONTAL_ALIGNMENT_CENTER, size.x, 11, Color(0.45, 0.62, 0.95))

func _border_color() -> Color:
	if disabled:
		return Color(0.35, 0.38, 0.4, 0.7)
	if not available:
		return Color(0.4, 0.45, 0.5, 0.8)
	if _hovered:
		return GameTheme.GOLD_LIGHT
	return accent

## 双层金环：外圈压暗当金属边，内圈提亮当高光。
## 单条粗描边在深色战场上会糊成一圈灰边，两层才读得出「这是个按钮」。
func _draw_rings(center: Vector2, radius: float, skin: Dictionary, border: Color) -> void:
	var outer := float(skin["ring_outer_width"])
	var inner := float(skin["ring_inner_width"])
	if outer <= 0.0:
		return
	if inner <= 0.0:
		draw_arc(center, radius, 0.0, TAU, 56, border, outer, true)
		return
	draw_arc(center, radius, 0.0, TAU, 64, border.darkened(0.32), outer, true)
	draw_arc(center, radius - float(skin["ring_gap"]), 0.0, TAU, 64, border.lightened(0.22), inner, true)

func _draw_cooldown(center: Vector2, radius: float, font: Font) -> void:
	var fraction := clampf(cooldown / cooldown_total, 0.0, 1.0)
	var points := PackedVector2Array()
	points.append(center)
	var steps := 26
	for i in steps + 1:
		var angle := -PI * 0.5 + TAU * fraction * (float(i) / float(steps))
		points.append(center + Vector2(cos(angle), sin(angle)) * (radius - 1.0))
	draw_colored_polygon(points, Color(0.0, 0.01, 0.02, 0.7))
	var cooldown_size := 24 if touch_mode else 20
	draw_string(
		font,
		center + Vector2(-radius, cooldown_size * 0.35),
		_cooldown_text(),
		HORIZONTAL_ALIGNMENT_CENTER,
		radius * 2.0,
		cooldown_size,
		Color(0.95, 0.96, 1.0)
	)

## 键位字母从「按钮正中 34px」降级成右下角的小角标：
## 正中让给图标，字母只负责回答「按哪个键」。这也是王者荣耀的做法。
func _draw_key_badge(center: Vector2, radius: float, font: Font, border: Color) -> void:
	var badge := SkillGlyph.badge_center(center, radius)
	var br := SkillGlyph.badge_radius(radius)
	draw_circle(badge + Vector2(0.0, 1.0), br + 1.5, Color(0.0, 0.0, 0.0, 0.5))
	draw_circle(badge, br, Color(0.05, 0.08, 0.1, 0.97))
	draw_arc(badge, br, 0.0, TAU, 24, border, 1.2, true)
	var key_color := GameTheme.GOLD_LIGHT if available and not disabled else GameTheme.MUTED
	draw_string(
		font,
		badge + Vector2(-br, br * 0.40),
		key_text,
		HORIZONTAL_ALIGNMENT_CENTER,
		br * 2.0,
		int(br * 1.25),
		key_color
	)

## 冷却读数：两位数以上只留整数，否则「28.0」在 20px 里挤成一团。
func _cooldown_text() -> String:
	if cooldown >= 10.0:
		return "%d" % int(ceil(cooldown))
	return "%.1f" % cooldown
