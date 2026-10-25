extends Control
class_name TouchJoystick

signal moved(value: Vector2)

const GameTheme = preload("res://scripts/ui/game_theme.gd")

## 摇杆的皮肤：一个「刻度盘」，不是一颗写了字的按钮。
##
## 旧皮肤在盘下面画了「移动」两个字 —— 真机上那是纯噪声：拇指正压在上面，
## 谁都知道这是走路用的，字只会把盘挤小。现在改成 8 向刻度：
## 不用写字也能读出「这是个有方向的盘」，而且拖出去看刻度就知道自己推了多远。
##
## 几何全部走 `dial_metrics()`，绘制与测试共用同一个函数，避免改了 `_draw`
## 里的魔数、测试还在验旧值。
const DIAL_TICKS := 8
# 盘半径 = 半框 - 呼吸位。260 的框里留 26，给外发光和刻度尾巴。
const DIAL_INSET := 26.0
const DIAL_GLOW := 8.0
# 滑块相对盘的直径。0.42 是「比盘明显小一档，又不至于点不到」的临界值。
const KNOB_SCALE := 0.42
# 刻度长度相对盘半径。
const TICK_SCALE := 0.13

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

## 盘面几何的唯一真身（绘制与测试共用）。
## - radius：金色外环的半径
## - glow：外发光比外环再宽出去多少
## - knob_radius：滑块半径
## - tick_length：8 向刻度的长度
static func dial_metrics(box: Vector2) -> Dictionary:
	# 无头测试里节点还没进树，size 是 0 —— 这里兜个底，避免算出负半径。
	var radius_value := maxf(minf(box.x, box.y) * 0.5 - DIAL_INSET, 1.0)
	return {
		"radius": radius_value,
		"glow": DIAL_GLOW,
		"knob_radius": radius_value * KNOB_SCALE,
		"tick_length": radius_value * TICK_SCALE,
		"ticks": DIAL_TICKS,
	}

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
	# 摇到哪儿算满，必须和画出来的盘对齐：用 dial_metrics 而不是旧的 94 常量。
	var dial: float = dial_metrics(size)["radius"]
	radius = dial
	_apply(stick_vector(center, point, dial, deadzone), (point - center).limit_length(dial))

func _apply(new_value: Vector2, knob: Vector2) -> void:
	if value.is_equal_approx(new_value) and _knob.is_equal_approx(knob):
		return
	value = new_value
	_knob = knob
	queue_redraw()
	moved.emit(value)

func _draw() -> void:
	var metrics := dial_metrics(size)
	var center := size * 0.5
	var dial: float = metrics["radius"]
	var glow: float = metrics["glow"]
	var knob_radius: float = metrics["knob_radius"]
	var tick_length: float = metrics["tick_length"]
	var engaged := value.length() > 0.001

	# 1) 外发光：拖出去时亮起来，回答「我的手被认到了」。
	var halo := GameTheme.GOLD
	halo.a = 0.16 if engaged else 0.07
	draw_circle(center, dial + glow, halo)
	# 2) 底盘
	draw_circle(center + Vector2(0, 5), dial + 6.0, Color(0.0, 0.0, 0.0, 0.32))
	draw_circle(center, dial + 6.0, Color(0.02, 0.04, 0.055, 0.72))
	# 3) 双层金环 + 内圈参考环
	draw_arc(center, dial, 0.0, TAU, 72, Color(0.62, 0.48, 0.24, 0.7), 2.0, true)
	draw_arc(center, dial * 0.62, 0.0, TAU, 48, Color(0.5, 0.4, 0.22, 0.32), 1.0, true)
	# 4) 8 向刻度：不写字也能看出「这是个方向盘」。
	#    主方向（上下左右）画长一点，斜向画短一点，45° 的四个脚尖一眼就能数清。
	for i in DIAL_TICKS:
		var angle := TAU * float(i) / float(DIAL_TICKS) - PI * 0.5
		var main := i % 2 == 0
		var length := tick_length if main else tick_length * 0.6
		var direction := Vector2(cos(angle), sin(angle))
		var inner_point := center + direction * (dial - 6.0 - length)
		var outer_point := center + direction * (dial - 6.0)
		var tick_color := Color(0.72, 0.58, 0.30, 0.55 if not engaged else 0.8)
		draw_line(inner_point, outer_point, tick_color, 2.4 if main else 1.6, true)
	# 5) 滑块
	var knob_pos := center + _knob
	draw_circle(knob_pos + Vector2(0, 3), knob_radius, Color(0.0, 0.0, 0.0, 0.4))
	draw_circle(knob_pos, knob_radius, Color(0.09, 0.13, 0.16, 0.96))
	draw_circle(knob_pos, knob_radius - 4.0, Color(0.14, 0.19, 0.22, 0.9))
	var edge := GameTheme.GOLD_LIGHT if engaged else Color(0.62, 0.48, 0.24, 0.8)
	draw_arc(knob_pos, knob_radius, 0.0, TAU, 40, edge, 2.0, true)
