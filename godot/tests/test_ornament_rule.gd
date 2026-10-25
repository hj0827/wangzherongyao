extends "res://tests/test_base.gd"

# 分隔线的回归守卫。
#
# 原来标题下面是一条 ColorRect 直线 —— 深浅一压，看着像表格的分隔线，把标题和说明
# 切成了两栏。换成 ornament.center_rule 之后（中央宝珠 + 两侧梭形收尖），才接得住
# 上面那行书法。
#
# 这里只守「委托关系」与布局契约：纹样几何本身由 test_ornament.gd 守着。
#   · 线必须不吃鼠标
#   · 定宽模式不能被容器拉满（否则会横穿到右边面板底下）
#   · 填满模式必须真的能填满（面板里的分组线需要这个）

const OrnamentRule = preload("res://scripts/ui/ornament_rule.gd")

func test_fixed_width_rule_shrinks_instead_of_stretching() -> void:
	var rule := OrnamentRule.build(340.0, 14.0)
	check(rule != null, "分隔线必须能建出来")
	near(rule.custom_minimum_size.x, 340.0, 0.01, "定宽分隔线必须保留请求的宽度")
	near(rule.custom_minimum_size.y, 14.0, 0.01, "分隔线高度必须保留请求的高度")
	eq(rule.size_flags_horizontal, Control.SIZE_SHRINK_BEGIN,
		"定宽分隔线在 VBox 里必须靠左收住，不能被拉满整栏")
	eq(rule.mouse_filter, Control.MOUSE_FILTER_IGNORE, "分隔线不能吃鼠标事件")

func test_fill_rule_expands_inside_a_panel() -> void:
	var rule := OrnamentRule.build(-1.0, 12.0)
	check((rule.size_flags_horizontal & Control.SIZE_EXPAND) != 0,
		"填满模式必须带 EXPAND，否则面板里的分组线只有 0 宽")
	check(rule.custom_minimum_size.x <= 1.0, "填满模式不该带固定宽度")
