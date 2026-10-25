extends Control
## 花饰分隔线。
##
## 原来标题/面板里的分隔线是一条 ColorRect 直线：深浅一压，读起来像表格的分隔线，
## 把上下两块切成两栏。换成 ornament.center_rule（中央宝珠 + 两侧梭形收尖）之后，
## 它才接得住上面的书法字。
##
## 只做两件事：按宽度委托给 ornament 画、按调用方的意图决定「定宽」还是「填满」。
## 纹样几何本身由 ornament.gd 负责（tests/test_ornament.gd 守着左右对称）。

const SELF_PATH := "res://scripts/ui/ornament_rule.gd"
const Ornament = preload("res://scripts/ui/ornament.gd")
const GameTheme = preload("res://scripts/ui/game_theme.gd")

## width < 0 表示「填满父容器」（面板里的分组线）；否则定宽靠左。
static func build(width: float = 340.0, height: float = 14.0, thickness: float = 1.5) -> Control:
	var rule := (load(SELF_PATH) as Script).new() as Control
	rule.name = "OrnamentRule"
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rule.set_meta("thickness", thickness)
	if width > 0.0:
		rule.custom_minimum_size = Vector2(width, height)
		# 定宽必须 SHRINK：放进 VBoxContainer 会被拉满整栏，
		# 那样中轴线会横穿到右边面板底下（标题那一栏踩过这个坑）。
		rule.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	else:
		rule.custom_minimum_size = Vector2(0.0, height)
		rule.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return rule

func _draw() -> void:
	if size.x < 40.0:
		return
	var thickness: float = float(get_meta("thickness", 1.5))
	var gold := GameTheme.GOLD
	Ornament.paint(
		self,
		Ornament.center_rule(size.x, size.y * 0.5, thickness),
		Color(gold.r, gold.g, gold.b, 0.55),
		thickness
	)
