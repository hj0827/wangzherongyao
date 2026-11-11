extends "res://tests/test_base.gd"

# 金边 9-slice 面板的**接线守卫**（第二批的后续：把边框从商店/结算推到常驻面板）。
#
# 为什么单开一组：`test_ui_assets_p1.gd` 验的是"资产在不在、访问器对不对"，
# 而这一类 bug 的典型形态是"资产在、访问器绿、但没人用"——即 01-repo-reality §4
# 记的 8 模块事故。所以这里直接建**真实节点**，把它实际挂上的 StyleBox 翻出来看。
#
# 同时钉住一条容易回退的约束：新面板的内容边距必须与旧 StyleBoxFlat 一致，
# 否则"换皮"会悄悄改变面板最小尺寸，把已经标定过的布局顶出去。

const GameTheme = preload("res://scripts/ui/game_theme.gd")
const GameHUD = preload("res://scripts/ui/game_hud.gd")
const Scoreboard = preload("res://scripts/ui/scoreboard.gd")
const MainApp = preload("res://scripts/app/main.gd")
const GameSession = preload("res://net/game_session.gd")
const LanDiscovery = preload("res://net/lan_discovery.gd")

func _hud() -> Control:
	var hud: Control = GameHUD.new()
	hud.setup("p1", "blue", "blade", "苍刃", false, false)
	hud._ready()
	var tree := Engine.get_main_loop() as SceneTree
	tree.root.add_child(hud)
	hud._apply_layout()
	return hud

func _main_app() -> Node:
	var main: Node = MainApp.new()
	main.session = GameSession.new()
	main.discovery = LanDiscovery.new()
	main._connect_session()
	main._build_shell()
	main._show_menu()
	main._show_hero_select()
	return main

func _frame_of(control: Control) -> StyleBoxTexture:
	var style := control.get_theme_stylebox("panel")
	if style is StyleBoxTexture:
		return style as StyleBoxTexture
	return null

# ---------------------------------------------------------------- 访问器契约

func test_panel_frame_keeps_style_default_content_margins() -> void:
	var frame := GameTheme.panel_frame()
	check(frame.texture != null, "缺少金边面板贴图")
	near(frame.content_margin_left, 14.0, 0.01, "左内边距必须与 style() 默认一致")
	near(frame.content_margin_right, 14.0, 0.01, "右内边距必须与 style() 默认一致")
	near(frame.content_margin_top, 10.0, 0.01, "上内边距必须与 style() 默认一致")
	near(frame.content_margin_bottom, 10.0, 0.01, "下内边距必须与 style() 默认一致")
	gt(float(frame.texture_margin_left), 0.0, "9-slice 必须声明切片边距")

func test_panel_frame_tint_changes_modulate_not_texture() -> void:
	# 选中/未选中共用同一张贴图，靠 modulate 区分：少一张资产，也不会出现"两个金边版本"。
	var bright := GameTheme.panel_frame(6.0, 6.0)
	var dim := GameTheme.panel_frame(6.0, 6.0, Color(0.6, 0.58, 0.62))
	check(bright.texture == dim.texture, "两种状态必须共用同一张贴图")
	check(bright.modulate_color != dim.modulate_color, "两种状态必须有不同 modulate")

# ---------------------------------------------------------------- 生产接线

func test_scoreboard_panel_is_a_gold_frame() -> void:
	var board: Object = Scoreboard.new()
	board.setup(false)
	var frame := _frame_of(board._panel)
	check(frame != null, "计分板面板必须是 9-slice 金边（否则这块还在用纯色圆角框）")
	if frame != null:
		check(frame.texture == GameTheme.panel_frame().texture, "计分板用的不是 panel_gold")
		near(frame.content_margin_left, 14.0, 0.01, "计分板内容边距不能被换皮改掉")
	board.free()

func test_pause_panel_is_a_gold_frame() -> void:
	var hud := _hud()
	var panel := hud._pause_overlay.get_child(0) as Control
	check(panel != null, "暂停覆盖层必须有一个面板")
	if panel != null:
		var frame := _frame_of(panel)
		check(frame != null, "暂停面板必须是 9-slice 金边")
		if frame != null:
			check(frame.texture == GameTheme.panel_frame().texture, "暂停面板用的不是 panel_gold")
			near(frame.content_margin_top, 10.0, 0.01, "暂停面板内容边距不能被换皮改掉")
	hud.free()

func test_hero_cards_and_quote_banner_use_gold_frames() -> void:
	var main := _main_app()
	eq(main._hero_cards.size(), 5, "五个英雄卡都要建出来")
	var selected_type := str(main.local_hero)
	var other_type := ""
	for hero_type in main._hero_cards:
		if str(hero_type) != selected_type:
			other_type = str(hero_type)
			break
	check(other_type != "", "至少要有两个英雄可比")
	var selected_frame := _frame_of(main._hero_cards[selected_type])
	var other_frame := _frame_of(main._hero_cards[other_type])
	check(selected_frame != null, "选人卡片必须是 9-slice 金边")
	check(other_frame != null, "未选中卡片同样要金边（只是调暗）")
	if selected_frame != null and other_frame != null:
		check(selected_frame.texture == other_frame.texture, "选中/未选中共用同一张金边")
		# 未选中必须真的更暗：否则玩家看不出当前选的是谁。
		var sel_lum := selected_frame.modulate_color.r + selected_frame.modulate_color.g + selected_frame.modulate_color.b
		var oth_lum := other_frame.modulate_color.r + other_frame.modulate_color.g + other_frame.modulate_color.b
		check(sel_lum > oth_lum, "选中的卡片要比未选中更亮（sel=%.2f other=%.2f）" % [sel_lum, oth_lum])
		near(selected_frame.content_margin_left, 6.0, 0.01, "卡片内容边距必须保持 6（否则卡片会变高）")
	var quote := _frame_of(main._quote_banner)
	check(quote != null, "台词横幅必须是 9-slice 金边")
	if quote != null:
		near(quote.content_margin_left, 28.0, 0.01, "台词横幅左内边距必须保持 28")
		near(quote.content_margin_top, 8.0, 0.01, "台词横幅上内边距必须保持 8")
	main.free()
