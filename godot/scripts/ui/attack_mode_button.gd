extends Control
class_name AttackModeButton

## 真机上的攻击模式按钮（普攻 / 补刀 / 推塔）。
##
## 视觉必须和 TouchActionButton（攻击键）是同一套画法：圆形底 + **双层金环** + 居中文字。
## 它贴在攻击键左边、只比它小一档，换上别的长相立刻会被读成「另一个系统的按钮」——
## 实机上第一版就是这样：76px 单线小圆夹在技能弧里，玩家找不到「改打谁」。
## 区别只在语义：攻击键是「按住」，这里是「选中态」（active），所以选中时多一层内发光。

signal pressed

const GameTheme = preload("res://scripts/ui/game_theme.gd")

## 与 touch_action_button.gd 的圆环参数保持一致（那边是攻击键的真身）。
const OUTER_RING := 3.0
const INNER_RING := 1.4
const RING_GAP := 4.0

var label := "普攻"
var accent := GameTheme.GOLD
var active := false
var touch_mode := true

var _touch_index := -1

func _ready() -> void:
	setup(touch_mode)

# 触摸响应所需的属性放在 setup 里而不是 _ready：无头测试的节点从没进过场景树，
# _ready 不触发，控件就成了一个点不动的摆设 —— 而测试正是要点它。
func setup(mobile: bool) -> void:
	touch_mode = mobile
	focus_mode = Control.FOCUS_NONE
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

func set_active(value: bool) -> void:
	if active == value:
		return
	active = value
	queue_redraw()

func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed and _touch_index == -1:
			_touch_index = touch.index
			accept_event()
			pressed.emit()
		elif not touch.pressed and touch.index == _touch_index:
			_touch_index = -1
			accept_event()
	elif touch_mode:
		return
	elif event is InputEventMouseButton:
		var mouse := event as InputEventMouseButton
		if mouse.button_index == MOUSE_BUTTON_LEFT and mouse.pressed:
			accept_event()
			pressed.emit()

func _draw() -> void:
	var center := size * 0.5
	var radius := minf(size.x, size.y) * 0.5 - 3.0
	var border := accent
	var text_color := GameTheme.MUTED
	if active:
		border = GameTheme.GOLD_LIGHT
		text_color = GameTheme.GOLD_LIGHT
	draw_circle(center + Vector2(0.0, 4.0), radius + 2.0, Color(0.0, 0.0, 0.0, 0.42))
	draw_circle(center, radius, Color(0.03, 0.055, 0.075, 0.9))
	draw_circle(center, radius - 5.0, Color(0.07, 0.11, 0.14, 0.94))
	if active:
		# 选中态必须一眼看出来：这个圆的全部意义就是回答「现在打谁」。
		var fill := accent
		fill.a = 0.30
		draw_circle(center, radius - 3.0, fill)
		draw_circle(center, radius - 9.0, Color(0.42, 0.33, 0.14, 0.55))
	else:
		var glow := accent
		glow.a = 0.10
		draw_circle(center, radius - 3.0, glow)
	# 双层金环（外圈压暗当金属边、内圈提亮当高光）—— 和攻击键逐参数一致，
	# 少一层就退回「技能弧里的小挂件」。
	var outer := OUTER_RING + (0.8 if active else 0.0)
	draw_arc(center, radius, 0.0, TAU, 64, border.darkened(0.32), outer, true)
	draw_arc(center, radius - RING_GAP, 0.0, TAU, 64, border.lightened(0.22), INNER_RING, true)
	var font_size := 22 if size.x >= 88.0 else 17
	draw_string(
		GameTheme.FONT_REGULAR,
		center + Vector2(-radius, 3.0 + font_size * 0.35),
		label,
		HORIZONTAL_ALIGNMENT_CENTER,
		radius * 2.0,
		font_size,
		text_color
	)
