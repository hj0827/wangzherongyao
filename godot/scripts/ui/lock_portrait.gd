extends Control
class_name LockPortrait

## 「遇见英雄」之后浮在他头顶的敌人头像。点一下就锁定。
##
## 位置由 LockBar 每帧按敌人的屏幕投影算（不再固定排在右上角）：
## 头像跟着人走，「这颗头像是谁」就不用猜了。
##
## 画法：底色圆 + 圆环（敌红 / 锁定金）+ 一个被 shader 裁成圆的立绘。
## 立绘用 GameTheme.hero_avatar()，那个函数已经把 1024 的立绘裁到「头肩」并降采样过，
## 直接用整张立绘缩到 110px 会只剩一团颜色。
##
## 为什么不做血条：头像只有 120px，再套一圈血量弧会只剩 90px 的有效点击区，
## 而且血量在战场里本来就看得到。这里只回答一个问题——「点谁」。

signal pressed

const GameTheme = preload("res://scripts/ui/game_theme.gd")
const ROUND_SHADER = preload("res://shaders/ui_round_mask.gdshader")

const AVATAR_INSET := 4.0
# 128 是「缩到 110px 还不糊」的最小源尺寸。再大只是白占显存。
const AVATAR_SOURCE := 128

var hero_type := ""
var active := false
var touch_mode := true

var _avatar: TextureRect
var _touch_index := -1

func setup(mobile: bool) -> void:
	touch_mode = mobile
	build()

# 构建和 _ready 分开：无头测试里的节点从没进过场景树，_ready 不会触发。
func build() -> void:
	if _avatar != null:
		return
	focus_mode = Control.FOCUS_NONE
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_avatar = TextureRect.new()
	_avatar.name = "Avatar"
	_avatar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_avatar.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_avatar.stretch_mode = TextureRect.STRETCH_SCALE
	# 必须先铺 anchor 再给内缩 offset。只写 offset_left/right 的话，
	# 默认 anchor 全在左上角，宽会被算成 offset_right - offset_left = -8，
	# 控件在树里、纹理也在，但一个像素都不画 —— 屏幕上是三个空黑圈。
	_avatar.anchor_left = 0.0
	_avatar.anchor_top = 0.0
	_avatar.anchor_right = 1.0
	_avatar.anchor_bottom = 1.0
	_avatar.offset_left = AVATAR_INSET
	_avatar.offset_top = AVATAR_INSET
	_avatar.offset_right = -AVATAR_INSET
	_avatar.offset_bottom = -AVATAR_INSET
	var material := ShaderMaterial.new()
	material.shader = ROUND_SHADER
	_avatar.material = material
	add_child(_avatar)
	_apply_texture()

func _ready() -> void:
	build()

func set_hero(type_id: String) -> void:
	if hero_type == type_id and _avatar != null and _avatar.texture != null:
		return
	hero_type = type_id
	_apply_texture()

func set_active(value: bool) -> void:
	if active == value:
		return
	active = value
	queue_redraw()

func _apply_texture() -> void:
	if _avatar == null:
		return
	_avatar.texture = GameTheme.hero_avatar(hero_type, AVATAR_SOURCE)

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
	var radius := minf(size.x, size.y) * 0.5 - 2.0
	if radius <= 3.0:
		return
	# 敌红环 = 「这儿有个人」；金色 = 「已经锁上了」。这两个状态必须一眼分得开，
	# 玩家点完要知道自己到底锁没锁上。
	var ring := Color(0.88, 0.36, 0.32, 0.92)
	if active:
		ring = GameTheme.GOLD_LIGHT
		var glow := GameTheme.GOLD
		glow.a = 0.30
		draw_circle(center + Vector2(0.0, 3.0), radius + 4.0, glow)
	draw_circle(center + Vector2(0.0, 3.0), radius + 1.0, Color(0.0, 0.0, 0.0, 0.48))
	draw_circle(center, radius, Color(0.05, 0.03, 0.04, 0.92))
	draw_arc(center, radius, 0.0, TAU, 44, ring, 3.0 if active else 2.0, true)
