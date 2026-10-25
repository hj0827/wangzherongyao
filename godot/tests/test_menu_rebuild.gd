extends "res://tests/test_base.gd"

# 主菜单改版后的**接线**守卫（几何与数据各有自己的用例，这里只问「真的用上了吗」）。
#
# 本仓库踩过「文件在 + 测试绿 ≠ 功能在跑」的坑：模块写完了但生产代码没引用，
# 屏幕上什么都没变，而测试全绿。所以这一组直接建一个 MainApp，把它真正画出来的
# 节点树翻一遍：
#
#   · 丝带层必须在，而且排在内容**下面**（排在后面就被面板整个盖住，等于没画）
#   · 丝带层不能吃鼠标（否则右栏按钮点不到 —— 这是最容易犯的致命错）
#   · 四个入口按钮都要在，且键稳定
#   · 主推按钮必须带 3px 竖条 + 金边（否则「主推」只存在于数据里）
#   · 面板必须半透（否则丝带穿不过去，缝合效果就没了）
#   · 点主推按钮必须真的进选人，并且是单机 1V1

const MainApp = preload("res://scripts/app/main.gd")
const GameSession = preload("res://net/game_session.gd")
const LanDiscovery = preload("res://net/lan_discovery.gd")
const MenuLayout = preload("res://scripts/ui/menu_layout.gd")
const GameTheme = preload("res://scripts/ui/game_theme.gd")

const EPS := 0.02

func _build_menu() -> Node:
	var main: Node = MainApp.new()
	main.session = GameSession.new()
	main.discovery = LanDiscovery.new()
	main._connect_session()
	main._build_shell()
	main._show_menu()
	return main

func _collect_labels(node: Node, out: Array) -> void:
	for child in node.get_children():
		var label := child as Label
		if label != null:
			out.append(label.text)
		_collect_labels(child, out)

func _find_child_by_name(node: Node, target: String) -> Node:
	for child in node.get_children():
		if child.name == target:
			return child
		var found := _find_child_by_name(child, target)
		if found != null:
			return found
	return null

func test_ribbon_layer_sits_behind_the_content_and_ignores_the_mouse() -> void:
	var main := _build_menu()
	var ribbons: Control = main._ribbon_layer
	check(ribbons != null, "主菜单必须挂上丝带层")
	if ribbons != null:
		eq(ribbons.get_parent(), main._screen_root, "丝带层必须和内容同属 Screen 层")
		eq(ribbons.get_index(), 0, "丝带层必须是第一个子节点（先画 = 压在内容下面）")
		eq(ribbons.mouse_filter, Control.MOUSE_FILTER_IGNORE,
			"丝带层必须忽略鼠标，否则整块右栏按钮都点不到")
	main.queue_free()

func test_all_four_entries_are_wired_by_stable_keys() -> void:
	var main := _build_menu()
	var buttons: Dictionary = main._menu_buttons
	eq(buttons.size(), 4, "四个入口按钮必须全部建出来")
	for entry in MenuLayout.entries():
		var key := str(entry.get("key"))
		check(buttons.has(key), "缺少入口按钮：%s" % key)
	main.queue_free()

func test_group_headers_are_rendered() -> void:
	var main := _build_menu()
	var texts: Array = []
	_collect_labels(main._screen_root, texts)
	for group in MenuLayout.groups():
		check(texts.has(str((group as Dictionary).get("label"))),
			"分组标题没有画出来：%s" % str((group as Dictionary).get("label")))
		check(texts.has(str((group as Dictionary).get("label_en"))),
			"分组英文小标没有画出来：%s" % str((group as Dictionary).get("label_en")))
	main.queue_free()

func test_primary_button_carries_its_own_emphasis() -> void:
	var main := _build_menu()
	var primary: Dictionary = MenuLayout.primary()
	var button: Button = main._menu_buttons.get(str(primary.get("key")))
	check(button != null, "主推按钮必须存在")
	if button != null:
		eq(bool(button.get_meta("primary", false)), true, "主推按钮必须打上 primary 标记")
		var bar := _find_child_by_name(button, "PrimaryBar")
		check(bar != null, "主推按钮左侧必须有那根 3px 竖条（唯一的视线锚点）")
		if bar != null:
			near((bar as Control).custom_minimum_size.x, 3.0, 0.01, "竖条宽度必须是 3px")
			eq((bar as Control).mouse_filter, Control.MOUSE_FILTER_IGNORE, "竖条不能挡按钮点击")
		var style := button.get_theme_stylebox("normal")
		check(style is StyleBoxFlat, "主推按钮必须有独立的底样式")
		if style is StyleBoxFlat:
			var border: Color = (style as StyleBoxFlat).border_color
			near(border.r, GameTheme.GOLD.r, EPS, "主推按钮必须是金边（红分量）")
			near(border.g, GameTheme.GOLD.g, EPS, "主推按钮必须是金边（绿分量）")
			near(border.b, GameTheme.GOLD.b, EPS, "主推按钮必须是金边（蓝分量）")
	main.queue_free()

func test_secondary_buttons_do_not_get_the_primary_treatment() -> void:
	# 四个都加金边 = 四个都不是主推。
	var main := _build_menu()
	var primary_key := str(MenuLayout.primary().get("key"))
	for key in main._menu_buttons:
		if str(key) == primary_key:
			continue
		var button: Button = main._menu_buttons[key]
		eq(bool(button.get_meta("primary", false)), false, "非主推按钮不能打 primary 标记：%s" % str(key))
		check(_find_child_by_name(button, "PrimaryBar") == null, "非主推按钮不能有 3px 竖条：%s" % str(key))
	main.queue_free()

func test_panel_is_translucent_so_the_ribbon_shows_through() -> void:
	# 面板底下压着丝带。面板不透，丝带就「被吃掉」，右栏又变回一张贴纸。
	var main := _build_menu()
	var panel: PanelContainer = main._menu_panel
	check(panel != null, "主菜单必须有战场选择面板")
	if panel != null:
		var style := panel.get_theme_stylebox("panel")
		check(style is StyleBoxFlat, "面板必须有底样式")
		if style is StyleBoxFlat:
			var alpha: float = (style as StyleBoxFlat).bg_color.a
			lt(alpha, 0.90, "面板底色必须半透（当前 alpha = %.2f），否则丝带穿不过去" % alpha)
			gt(alpha, 0.60, "面板也不能透到字看不清（当前 alpha = %.2f）" % alpha)
	main.queue_free()

func test_primary_button_actually_starts_a_solo_duel() -> void:
	var main := _build_menu()
	var primary: Dictionary = MenuLayout.primary()
	var button: Button = main._menu_buttons.get(str(primary.get("key")))
	check(button != null, "主推按钮必须存在")
	if button != null:
		button.pressed.emit()
		eq(main.screen, "hero_select", "点主推必须进入选人界面")
		eq(main._pending_mode, str(primary.get("mode")), "主推必须按数据里的模式开局")
		eq(main._pending_online, bool(primary.get("online")), "主推必须按数据里的联机状态开局")
	main.queue_free()
