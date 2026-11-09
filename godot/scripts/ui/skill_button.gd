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
# 触屏键面刻意不写任何文字。实测圆内右下角（badge 口径）离心 44.1px，
# 距半径 58 只剩 13.9px —— 连"6级"（22x22 @14px）都会压出圆外，
# 所以未学状态改用**纯图形**表达（斜杠），不依赖字号，也就不会越界。
# 以下四个比例是绘制与几何守卫的唯一真身（守卫不另写字面量）。
const TOUCH_LOCK_STRIPE_RATIO := 0.62   # 斜杠端点离心距离 = radius * 该比例
const TOUCH_LOCK_STROKE_RATIO := 0.14   # 黑色描边线宽
const TOUCH_LOCK_CORE_RATIO := 0.075    # 亮线线宽
const TOUCH_LOCK_DIM_RATIO := 0.92      # 压暗底圆半径

## 键鼠键面：保持原样（方形卡 + 技能名 + 键位角标）。
const DESKTOP_CENTER_Y := 44.0
const DESKTOP_RADIUS := 35.0
const DESKTOP_NAME_Y := 96.0
const DESKTOP_STATUS_Y := 110.0
# 桌面技能名的字号。原来在 _draw 里写死 14，提出来当唯一真身：
# 宽度守卫（test_level_caption_never_outgrows_the_desktop_button）要按同一个字号量像素。
const DESKTOP_NAME_SIZE := 14

## 技能等级读数（项 2，链路 6）。静态函数：HUD 与测试都能直接按类名调用，
## 不需要实例化 Control —— 无头测试里实例化 + _ready 生命周期是另一类坑。
## 0 级 = 未学习，只显示"未学"而不显示数字 0：否则玩家会以为"0 级也能放"。
static func level_caption(level: int) -> String:
	if level <= 0:
		return "未学"
	return "%d级" % level

## 键面上那一行"技能名 + 等级"的组合。level < 0 表示这个键不显示等级
## （召唤师键没有等级概念，画个"1级"是错的）。
## 单独抽成静态函数，是为了让宽度守卫能按**真实最坏组合**量像素，
## 而不是只量"6级"这种必然通过的短串。
static func composed_name(skill_name: String, level: int) -> String:
	if level < 0:
		return skill_name
	if skill_name == "":
		return level_caption(level)
	return "%s %s" % [skill_name, level_caption(level)]

var slot := "q"
var key_text := "Q"
var skill_name := "技能"
## 技能等级（项 2）。-1 = 不显示等级（召唤师键没有等级概念）。
## 默认 -1 而不是 1：漏接线时键面退回成"只有技能名"，
## 不会显示一个看起来正确、其实是假的"1级"。
var level := -1
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
			# 项 2：触屏键面不写技能名（拇指压在上面，名字是噪声），也不写等级数字
			# —— 实测圆内可用余量只有 13.9px，任何两字读数都会压出圆外。
			# 未学状态改用纯图形（斜杠）表达：玩家反复按一个放不出来的大招、
			# 又不知道为什么，是最糟的体验，所以这个提示必须有，但不必是文字。
			"show_lock_mark": true,
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
		# 桌面走"技能名 + 等级"同一行（composed_name），不用图形锁标。
		"show_lock_mark": false,
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

func set_state(new_cooldown: float, new_total: float, new_name: String, can_use: bool, is_disabled: bool, new_level := -1) -> void:
	cooldown = new_cooldown
	cooldown_total = maxf(new_total, 0.01)
	skill_name = new_name
	available = can_use
	disabled = is_disabled
	# new_level 默认 -1（不显示）而不是沿用旧值：HUD 每帧都会把快照里的等级传进来，
	# 沿用旧值会让"忘了传"这件事在界面上看起来完全正常。
	level = new_level
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
		var name_size := DESKTOP_NAME_SIZE if not touch_mode else TOUCH_NAME_SIZE
		# 项 2：键面那一行是"技能名 + 等级"。level<0（召唤师键）时 composed_name
		# 只回技能名，不会画出一个假的"1级"。
		draw_string(
			font,
			Vector2(0, name_y),
			composed_name(skill_name, level),
			HORIZONTAL_ALIGNMENT_CENTER,
			size.x,
			name_size,
			GameTheme.TEXT if not disabled else GameTheme.MUTED
		)
	if bool(skin["show_name"]) and not available and not disabled:
		var status_y := DESKTOP_STATUS_Y if not touch_mode else size.y - 2.0
		draw_string(font, Vector2(0, status_y), "法力不足", HORIZONTAL_ALIGNMENT_CENTER, size.x, 11, Color(0.45, 0.62, 0.95))
	# 项 2：触屏端"未学"提示用纯图形（圆内斜杠），尺寸全部按半径比例算，
	# 不依赖字号 —— 实测任何文字读数都会压出圆外，图形不会。
	# level<0（召唤师键）没有等级概念，不画。
	if bool(skin["show_lock_mark"]) and shows_lock_mark(level):
		_draw_lock_mark(center, radius)

# 斜杠锁标的几何真身。端点用单位向量 (0.7071,0.7071) 乘 radius*ratio，
# 合成离心距离就恰好是 radius*ratio —— 写成 Vector2(r,r)*k 会多算 sqrt(2) 倍，
# 第一版就是这么把读数算出了圆外（守卫当时还是绿的，因为它只比了 x 分量）。
## 该不该画"未学"锁标（项 2）。抽成纯函数是为了能被测试直接钉住：
## 判定留在 _draw 里的话，无头测试调不到它，"已学技能被误画锁标"就抓不出来
## （变异验证 N27 实测就是这样逃过检测的）。
static func shows_lock_mark(level: int) -> bool:
	# 只有"确实未学"（level==0）才画。level<0 是召唤师键，没有等级概念。
	return level == 0

func _draw_lock_mark(center: Vector2, radius: float) -> void:
	# 压暗底圆表达"现在不能用"，斜杠表达"还没学"。
	draw_circle(center, radius * TOUCH_LOCK_DIM_RATIO, Color(0.02, 0.03, 0.05, 0.55))
	var reach := radius * TOUCH_LOCK_STRIPE_RATIO
	var dir := Vector2(0.7071, 0.7071)
	var from := center - dir * reach
	var to := center + dir * reach
	# 黑描边 + 亮线两层：单条亮线压在暗图标上对比不足，读不出"被划掉"。
	draw_line(from, to, Color(0, 0, 0, 0.85), radius * TOUCH_LOCK_STROKE_RATIO, true)
	draw_line(from, to, Color(0.92, 0.42, 0.35, 0.95), radius * TOUCH_LOCK_CORE_RATIO, true)

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
