extends Control
class_name TouchActionButton

signal pressed
signal released

const GameTheme = preload("res://scripts/ui/game_theme.gd")
const SkillGlyph = preload("res://scripts/ui/skill_glyph.gd")

## 图标键面：普攻键在大拇指正下方，手游里它不写字，只给一个剑形图标 + 金环。
## 留空 `icon_kind` 就走原来那套「文字 + 小提示」，暂停 / 回城 / 传送这类
## 只有两三个字的功能键继续用文字更清楚。
const ICON_FILL := 1.0
const OUTER_RING := 3.0
const INNER_RING := 1.4
const RING_GAP := 4.0
## 键体离方框边的距离。留 10（原来是 4）是为了给外发光腾地方 ——
## 发光必须画在框内，否则会盖到旁边的模式圆上。
const BODY_INSET := 10.0
## 外发光比键体再宽出去多少。手游的攻击键在战场上永远是「亮着的那一颗」，
## 靠的就是这圈半透明光环，而不是加粗描边。
const GLOW_WIDTH := 8.0

var label := "攻击"
var hint := ""
## 技能族标识（见 skill_glyph.gd）。非空即画图标；空串则画 `label` 文字。
var icon_kind := ""
var accent := GameTheme.GOLD
var touch_mode := true
var disabled := false
var held := false

var _touch_index := -1

## 键面上写不写字，由有没有图标决定 —— 图和字同时出现会把圆挤满。
static func draws_label(kind: String) -> bool:
	return kind == ""

## 圆形键面的几何唯一真身（绘制与测试共用）。
## glow_radius 是外发光的半径，必须落在方框内（键体已经为它让出 10px）。
static func icon_metrics(box: Vector2) -> Dictionary:
	var radius := minf(box.x, box.y) * 0.5 - BODY_INSET
	return {
		"center": box * 0.5,
		"radius": radius,
		"glow_radius": radius + GLOW_WIDTH,
		"glyph_fill": ICON_FILL,
		"ring_outer_width": OUTER_RING,
		"ring_inner_width": INNER_RING,
		"ring_gap": RING_GAP,
	}

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
	var metrics := icon_metrics(size)
	var center: Vector2 = metrics["center"]
	var radius: float = metrics["radius"]
	var glow_radius: float = metrics["glow_radius"]
	var border := accent
	if disabled:
		border = Color(0.36, 0.39, 0.42, 0.7)
	elif held:
		border = GameTheme.GOLD_LIGHT
	# 外发光先画：它是「键在战场上永远亮着」的那一层，被键体压住一半才自然。
	if not disabled:
		var halo := accent
		halo.a = 0.26 if held else 0.13
		draw_circle(center, glow_radius, halo)
	draw_circle(center + Vector2(0, 5), radius + 2.0, Color(0.0, 0.0, 0.0, 0.42))
	draw_circle(center, radius, Color(0.03, 0.055, 0.075, 0.9))
	draw_circle(center, radius - 5.0, Color(0.07, 0.11, 0.14, 0.94))
	if not disabled:
		var glow := accent
		glow.a = 0.35 if held else 0.1
		draw_circle(center, radius - 3.0, glow)
	if draws_label(icon_kind):
		_draw_caption(center, radius)
	else:
		_draw_glyph(center, radius)
	_draw_rings(center, radius, border)

## 双层金环：外圈压暗当金属边、内圈提亮当高光。单层粗描边在深色战场上会糊掉。
func _draw_rings(center: Vector2, radius: float, border: Color) -> void:
	var outer := OUTER_RING + (0.8 if held else 0.0)
	draw_arc(center, radius, 0.0, TAU, 64, border.darkened(0.32), outer, true)
	draw_arc(center, radius - RING_GAP, 0.0, TAU, 64, border.lightened(0.22), INNER_RING, true)

func _draw_glyph(center: Vector2, radius: float) -> void:
	var color := accent.lightened(0.35)
	color.a = 0.92
	if disabled:
		color = GameTheme.MUTED
	elif held:
		color = GameTheme.GOLD_LIGHT
	SkillGlyph.paint(self, icon_kind, center, radius * ICON_FILL, color)

func _draw_caption(center: Vector2, radius: float) -> void:
	var font_size := 24 if size.x >= 120.0 else 18
	draw_string(
		GameTheme.FONT_REGULAR,
		center + Vector2(-radius, 4.0 + font_size * 0.35),
		label,
		HORIZONTAL_ALIGNMENT_CENTER,
		radius * 2.0,
		font_size,
		GameTheme.TEXT if not disabled else GameTheme.MUTED
	)
	if hint != "":
		draw_string(
			GameTheme.FONT_REGULAR,
			center + Vector2(-radius, radius - 8.0),
			hint,
			HORIZONTAL_ALIGNMENT_CENTER,
			radius * 2.0,
			11,
			Color(0.62, 0.68, 0.73, 0.8)
		)
