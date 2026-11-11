extends "res://tests/test_base.gd"

# UI 骨架资产（视觉升级第二批）：
# 9-slice 边框套装 / 击杀横幅 + 连杀纹章 / MVP 结算背景与勋章。
#
# 这些资产不是手绘的，而是由 res://tools/make_ui_assets.gd 程序化生成
# （确定性、可重复、零版权风险）。手绘/位图替换时只需覆盖同名 PNG，
# 本文件与 game_theme 的访问器都不需要改 —— 这也是"资产骨架先行"的意义：
# 美术到位前，界面已经按最终结构在跑。

const GameTheme = preload("res://scripts/ui/game_theme.gd")
const GameHUD = preload("res://scripts/ui/game_hud.gd")
const ShopPanel = preload("res://scripts/ui/shop_panel.gd")
const ItemShop = preload("res://sim/item_shop.gd")

func _hud() -> Control:
	var hud: Control = GameHUD.new()
	hud.setup("p1", "blue", "blade", "苍刃", false, false)
	hud._ready()
	# 进树是为了 create_tween 有 SceneTree；_ready 自带幂等闸。
	var tree := Engine.get_main_loop() as SceneTree
	tree.root.add_child(hud)
	hud._apply_layout()
	hud.snapshot = {"scores": {"blue": {"towers": 2}}, "time": 600.0}
	return hud

# ---------------------------------------------------------------- 资产存在

func test_frame_set_has_panel_button_and_quality_tiers() -> void:
	var panel := GameTheme.ornate_panel()
	check(panel.texture != null, "缺少 9-slice 面板边框")
	gt(float(panel.texture_margin_left), 0.0, "面板边框必须声明 9-slice margin")
	var button := GameTheme.button_frame()
	check(button.texture != null, "缺少按钮 9-slice 边框")
	for quality in ["basic", "rare", "epic", "legendary"]:
		var frame := GameTheme.quality_frame(str(quality))
		check(frame.texture != null, "缺少品质框：%s" % quality)
		if frame.texture != null:
			gt(float(frame.texture.get_width()), 32.0, "品质框太小：%s" % quality)
	check(GameTheme.quality_frame("unknown_tier").texture != null,
		"未知品质要回落到基础框，不能返回空边框")
	# 反自证：不同品质必须真的指向不同 PNG，而不是都回落成同一张。
	check(GameTheme.quality_frame("basic").texture != GameTheme.quality_frame("epic").texture,
		"basic 与 epic 必须是两张不同的品质框")

# ---------------------------------------------------------------- UI-07 队伍色边框 / 小地图金框

func _dominant_hue(image: Image) -> float:
	var img: Image = image.duplicate()
	if img.is_compressed():
		img.decompress()
	img.convert(Image.FORMAT_RGBA8)
	var sx := 0.0
	var sy := 0.0
	var count := 0
	for y in img.get_height():
		for x in img.get_width():
			var color := img.get_pixel(x, y)
			if color.a < 0.5 or color.s < 0.25:
				continue
			sx += cos(color.h * TAU)
			sy += sin(color.h * TAU)
			count += 1
	if count == 0:
		return -1.0
	return fposmod(atan2(sy, sx) / TAU, 1.0)

func test_team_panels_recolor_the_gold_frame_into_team_hues() -> void:
	var blue := GameTheme.team_panel("blue")
	var red := GameTheme.team_panel("red")
	check(blue.texture != null and red.texture != null, "蓝/红队伍面板必须都有边框")
	check(blue.texture != red.texture, "蓝/红必须是两张不同色相的边框")
	var blue_hue := _dominant_hue(blue.texture.get_image())
	var red_hue := _dominant_hue(red.texture.get_image())
	check(blue_hue > 0.45 and blue_hue < 0.72, "蓝方边框主色相应在蓝色区间，实际 %.2f" % blue_hue)
	check(red_hue > 0.9 or red_hue < 0.08, "红方边框主色相应在红色区间，实际 %.2f" % red_hue)
	check(GameTheme.team_panel("blue") == blue, "同一队伍的面板必须缓存，不能每次重染")

func test_minimap_frame_is_a_compact_gold_border() -> void:
	var frame := GameTheme.minimap_frame()
	check(frame.texture != null, "小地图要有金框")
	gt(float(frame.texture_margin_left), 0.0, "小地图金框必须是 9-slice")
	lt(float(frame.texture_margin_left), 24.0, "小地图金框的切片必须比大面板更窄，避免吃掉地图面积")

func test_kill_banner_asset_is_four_to_one() -> void:
	var banner := GameTheme.kill_banner()
	check(banner != null, "缺少击杀横幅底图")
	if banner != null:
		eq(banner.get_width(), 1024, "击杀横幅宽度")
		eq(banner.get_height(), 256, "击杀横幅高度")

func test_streak_emblems_cover_one_to_five() -> void:
	for streak in [1, 2, 3, 4, 5]:
		check(GameTheme.streak_emblem(streak) != null, "缺少连杀纹章：%d" % streak)
	check(GameTheme.streak_emblem(0) == null, "0 连杀不该有纹章")
	check(GameTheme.streak_emblem(6) == null, "超出 5 连杀不该有纹章")

func test_mvp_background_and_medals_exist_and_differ() -> void:
	check(GameTheme.mvp_background() != null, "缺少结算页背景")
	var mvp := GameTheme.mvp_medal(true)
	var part := GameTheme.mvp_medal(false)
	check(mvp != null, "缺少 MVP 勋章")
	check(part != null, "缺少参战勋章")
	check(mvp != part, "MVP 与参战必须是两枚不同勋章")

# ---------------------------------------------------------------- 接线

func test_shop_item_cells_use_quality_frames() -> void:
	var panel := ShopPanel.new()
	panel.setup("blade", false)
	var checked := 0
	for item_id in panel._item_cells:
		var cell: Control = panel._item_cells[item_id]
		var style := cell.get_theme_stylebox("panel")
		check(style is StyleBoxTexture, "商店格子要套品质框：%s" % item_id)
		if style is StyleBoxTexture:
			# 直接按"品质 → 文件名"取图对比，不走 GameTheme.quality_frame()：
			# 否则把 quality_frame 写死成 basic 时，两边一起变，断言恒真。
			var quality := ItemShop.quality_of(str(item_id))
			var expected: Texture2D = load(GameTheme.QUALITY_FRAME_DIR + quality + ".png")
			check((style as StyleBoxTexture).texture == expected,
				"品质框与品质不符：%s（%s）" % [item_id, quality])
			checked += 1
	gt(float(checked), 0.0, "至少要验到一件装备")
	panel.free()

func test_hud_kill_banner_shows_both_avatars() -> void:
	var hud := _hud()
	hud.show_kill_banner("苍刃", "blade", "星璃", "mage", 0, true)
	check(hud._kill_banner.visible, "英雄击杀要弹出击杀横幅")
	check(hud._kill_banner_bg.texture != null, "横幅要有底图")
	check(hud._kill_banner_killer.texture != null, "横幅要有击杀者头像")
	check(hud._kill_banner_victim.texture != null, "横幅要有受害者头像")
	check(hud._kill_banner_text.text.contains("苍刃") and hud._kill_banner_text.text.contains("星璃"),
		"横幅要写清双方名字：%s" % hud._kill_banner_text.text)
	check(hud._kill_banner_emblem.texture == null, "没有连杀时不显示纹章")
	hud.free()

func test_hud_kill_banner_emblem_follows_streak() -> void:
	var hud := _hud()
	hud.show_kill_banner("苍刃", "blade", "星璃", "mage", 3, true)
	# 同样按"等级 → 文件名"直接取图，避免拿 streak_emblem() 自证。
	var triple: Texture2D = load(GameTheme.STREAK_EMBLEM_DIR + "triple.png")
	check(hud._kill_banner_emblem.texture == triple, "三杀要显示 streak_triple.png")
	hud.show_kill_banner("苍刃", "blade", "星璃", "mage", 0, true)
	check(hud._kill_banner_emblem.texture == null, "后续无连杀要收起纹章")
	hud.free()

func test_hud_tower_kill_banner_has_only_victim() -> void:
	var hud := _hud()
	hud.show_kill_banner("防御塔", "", "星璃", "mage", 0, false)
	check(hud._kill_banner.visible, "防御塔击杀也要有横幅")
	check(hud._kill_banner_killer.texture == null, "非英雄击杀不显示击杀者头像")
	check(not hud._kill_banner_killer_frame.visible, "没有击杀者时整个头像位要收起，不能留一个空金环")
	check(hud._kill_banner_victim.texture != null, "受害者头像要在")
	check(hud._kill_banner_victim_frame.visible, "有受害者时头像位要在")
	hud.free()

func test_result_overlay_uses_mvp_assets() -> void:
	var hud := _hud()
	hud.show_result("blue", {"kills": 5, "deaths": 1})
	check(hud._result_bg.texture == GameTheme.mvp_background(), "结算页要用 MVP 背景")
	check(hud._result_medal.texture == GameTheme.mvp_medal(true), "5/1 要挂 MVP 勋章")
	hud.show_result("red", {"kills": 0, "deaths": 3})
	check(hud._result_medal.texture == GameTheme.mvp_medal(false), "0/3 要挂参战勋章")
	hud.free()
