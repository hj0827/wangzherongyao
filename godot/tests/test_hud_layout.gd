extends "res://tests/test_base.gd"

## HUD 分区护栏。
##
## 目标不是「好看」，而是三条能自动判定的硬约束：
## 1. 任意两块常驻 HUD 不许重叠（这次实机就是播报压在商店按钮上）；
## 2. 中央视野安全区必须是空的（兵线交汇、敌人出现、自己站位都在那儿）；
## 3. 所有分区必须留在安全边距内，不许贴边出血。
##
## 只测常驻分区。播报条 / 阵亡遮罩 / 结算面板是瞬时的，本来就该盖在战场正中间。

const HudLayout = preload("res://scripts/ui/hud_layout.gd")
const GameHUD = preload("res://scripts/ui/game_hud.gd")
const GameTheme = preload("res://scripts/ui/game_theme.gd")

const PC_ZONES := ["minimap", "score", "shop", "feed", "bush", "hero", "skills", "mode", "hints"]
# 触屏的技能弧由 TouchLayout 单独负责（已有 test_mobile_ui 覆盖），这里只测它周围的固定分区。
# pause 必须在这张表里：它原来是写死的 offset，结果被锁定头像条压住而没人测得出来。
const TOUCH_ZONES := ["minimap", "score", "shop", "feed", "joystick", "hero", "hints", "pause"]

const DESKTOP_SIZES := [
	Vector2(1280.0, 720.0),
	Vector2(1366.0, 768.0),
	Vector2(1600.0, 900.0),
	Vector2(1920.0, 1080.0),
	Vector2(2560.0, 1440.0),
	# 1080p 显示器上把窗口拖到 1080 宽时，canvas_items + expand 的实际画布尺寸。
	Vector2(1600.0, 858.0),
]
const TOUCH_SIZES := [
	Vector2(1600.0, 900.0),
	Vector2(2000.0, 900.0),
	Vector2(2400.0, 1080.0),
]

func _overlaps(zones: Dictionary, names: Array) -> Array:
	var bad: Array = []
	for i in names.size():
		for j in range(i + 1, names.size()):
			var a: Rect2 = zones[names[i]]
			var b: Rect2 = zones[names[j]]
			if a.intersects(b):
				bad.append("%s %s vs %s %s" % [names[i], a, names[j], b])
	return bad

# ---------------------------------------------------------------- 桌面端

func test_desktop_zones_never_overlap_each_other() -> void:
	for viewport in DESKTOP_SIZES:
		var zones := HudLayout.zones(viewport, false)
		var bad := _overlaps(zones, PC_ZONES)
		eq(bad.size(), 0, "HUD zones collide at %s: %s" % [viewport, bad])

func test_desktop_zones_stay_inside_the_safe_margin() -> void:
	for viewport in DESKTOP_SIZES:
		var zones := HudLayout.zones(viewport, false)
		var m := HudLayout.MARGIN
		for name in PC_ZONES:
			var rect: Rect2 = zones[name]
			check(rect.position.x >= m - 0.01 and rect.position.y >= m - 0.01, "%s leaks past the top/left margin at %s" % [name, viewport])
			check(rect.end.x <= viewport.x - m + 0.01, "%s leaks past the right margin at %s" % [name, viewport])
			check(rect.end.y <= viewport.y - m + 0.01, "%s leaks past the bottom margin at %s" % [name, viewport])

func test_center_playfield_is_never_covered() -> void:
	# 常驻 HUD 一律不许进入中央视野区；草丛提示是瞬时状态字，允许压在比分下面。
	var permanent := ["minimap", "score", "shop", "feed", "hero", "skills", "mode", "hints"]
	for viewport in DESKTOP_SIZES:
		var zones := HudLayout.zones(viewport, false)
		var safe := HudLayout.safe_center(viewport)
		check(safe.size.x > viewport.x * 0.4, "the safe center must cover a real part of the screen")
		for name in permanent:
			var rect: Rect2 = zones[name]
			check(not rect.intersects(safe), "%s covers the center of the battlefield at %s" % [name, viewport])

func test_skill_row_hugs_the_bottom_right_corner() -> void:
	var viewport := Vector2(1600.0, 900.0)
	var zones := HudLayout.zones(viewport, false)
	var m := HudLayout.MARGIN
	var skills: Rect2 = zones["skills"]
	near(skills.end.x, viewport.x - m, 0.01, "the skill row ends on the right margin")
	near(skills.end.y, viewport.y - m, 0.01, "the skill row sits on the bottom margin")
	eq(HudLayout.SKILL_COUNT, 5, "four skills plus the summoner spell")
	for i in HudLayout.SKILL_COUNT:
		var rect := HudLayout.skill_rect(skills, i)
		near(rect.size.x, HudLayout.SKILL_W, 0.01, "skill %d keeps its width" % i)
		if i > 0:
			var prev := HudLayout.skill_rect(skills, i - 1)
			near(rect.position.x - prev.end.x, HudLayout.SKILL_GAP, 0.01, "skill %d keeps the row gap" % i)
	var last := HudLayout.skill_rect(skills, HudLayout.SKILL_COUNT - 1)
	near(last.end.x, skills.end.x, 0.01, "the last skill closes the row")

func test_attack_mode_strip_sits_above_the_skill_row() -> void:
	var viewport := Vector2(1600.0, 900.0)
	var zones := HudLayout.zones(viewport, false)
	var mode: Rect2 = zones["mode"]
	var skills: Rect2 = zones["skills"]
	check(mode.end.y <= skills.position.y, "the attack-mode strip must not touch the skill row")
	near(mode.end.y, skills.position.y - HudLayout.MODE_GAP, 0.01, "a fixed gap separates them")
	near(mode.end.x, skills.end.x, 0.01, "both clusters share the right edge")
	check(mode.position.y > HudLayout.safe_center(viewport).end.y, "the mode strip stays under the playfield")

func test_narrow_window_keeps_the_hero_card_off_the_skill_row() -> void:
	for width in [1280.0, 1152.0, 1024.0]:
		var viewport := Vector2(width, 720.0)
		var zones := HudLayout.zones(viewport, false)
		var hero: Rect2 = zones["hero"]
		var skills: Rect2 = zones["skills"]
		check(hero.end.x < skills.position.x, "hero card collides with the skill row at %.0f px" % width)
		check(skills.position.x - hero.end.x >= 24.0, "the gap between them stays readable at %.0f px" % width)

func test_key_legend_fits_inside_its_zone() -> void:
	# 键位提示原来是「一行 76 个字塞进 840px」，实机被裁成一串碎片。
	# 这里量的是真实字体宽度，而不是猜：每一行都必须放得下。
	var font: Font = GameTheme.FONT_REGULAR
	var lines: Array = GameHUD.KEY_HINT_LINES
	check(lines.size() >= 2, "the legend must be split into two readable lines")
	for i in lines.size():
		var available := HudLayout.HINT_W - 28.0
		var width := font.get_string_size(str(lines[i]), HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
		check(width <= available, "legend line %d needs %.0f px but only %.0f are available" % [i, width, available])
	check(HudLayout.HINT_H >= float(lines.size()) * 20.0, "the hint zone must be tall enough for every line")

func test_key_legend_leaves_a_real_gap_above_the_hero_card() -> void:
	var zones := HudLayout.zones(Vector2(1600.0, 900.0), false)
	var hints: Rect2 = zones["hints"]
	var hero: Rect2 = zones["hero"]
	check(hints.end.y <= hero.position.y - 8.0, "the legend must not sit on the status card's top edge")

func test_score_stays_centered_at_every_size() -> void:	for viewport in DESKTOP_SIZES:
		var zones := HudLayout.zones(viewport, false)
		var score: Rect2 = zones["score"]
		near(score.get_center().x, viewport.x * 0.5, 0.01, "the scoreboard stays optically centered")

func test_minimum_window_is_never_below_the_layout_floor() -> void:
	# 窗口再小，设计稿就会被整体缩放糊掉。窗口最小值必须 >= 分区表的下限。
	check(HudLayout.MIN_VIEWPORT.x >= 1280.0 and HudLayout.MIN_VIEWPORT.y >= 720.0, "the layout floor is 1280 x 720")
	for viewport in DESKTOP_SIZES:
		check(
			viewport.x >= HudLayout.MIN_VIEWPORT.x and viewport.y >= HudLayout.MIN_VIEWPORT.y,
			"tested desktop size %s must not be below the layout floor" % viewport
		)

# ---------------------------------------------------------------- 触屏端

func test_touch_zones_never_overlap_each_other() -> void:
	for viewport in TOUCH_SIZES:
		var zones := HudLayout.zones(viewport, true)
		var bad := _overlaps(zones, TOUCH_ZONES)
		eq(bad.size(), 0, "touch HUD zones collide at %s: %s" % [viewport, bad])

func test_touch_keeps_the_joystick_under_the_left_thumb() -> void:
	for viewport in TOUCH_SIZES:
		var zones := HudLayout.zones(viewport, true)
		var stick: Rect2 = zones["joystick"]
		check(stick.position.x <= 16.0, "the joystick hugs the left edge")
		check(stick.end.y >= viewport.y - 48.0, "the joystick sits inside the thumb reach")
		check(stick.size.x >= 220.0, "the joystick stays thumb-sized")

func test_pc_and_touch_use_different_bottom_layouts() -> void:
	var viewport := Vector2(1600.0, 900.0)
	var pc := HudLayout.zones(viewport, false)
	var touch := HudLayout.zones(viewport, true)
	near((pc["hero"] as Rect2).position.x, HudLayout.MARGIN, 0.01, "desktop parks the status card in the lower-left corner")
	near((pc["hero"] as Rect2).end.y, viewport.y - HudLayout.MARGIN, 0.01, "desktop card sits on the bottom margin")
	check(touch.has("joystick"), "touch reserves a joystick zone")
	check(not pc.has("joystick"), "desktop does not reserve a joystick")
	check((touch["hero"] as Rect2).size.x < (pc["hero"] as Rect2).size.x, "the phone card is a narrow column, not a wide strip")

func test_touch_status_card_tucks_under_the_minimap() -> void:
	# 参考手游的做法：底部没有横着的大卡 —— 血量看头顶血条，金币和等级挂在小地图下面。
	for viewport in TOUCH_SIZES:
		var zones := HudLayout.zones(viewport, true)
		var hero: Rect2 = zones["hero"]
		var minimap: Rect2 = zones["minimap"]
		near(hero.position.x, minimap.position.x, 0.01, "the card shares the minimap's left edge at %s" % viewport)
		near(hero.position.y, minimap.end.y + HudLayout.TOUCH_CARD_GAP, 0.01, "the card hangs right under the minimap at %s" % viewport)
		near(hero.size.x, minimap.size.x, 0.01, "the card is exactly as wide as the minimap column at %s" % viewport)
		lt(hero.end.y, viewport.y * 0.5, "the card stays in the upper half at %s" % viewport)
		lt(hero.end.y, (zones["joystick"] as Rect2).position.y, "the card never reaches the thumb zone at %s" % viewport)
		# 卡变窄了，面积必须跟着掉：否则只是把大卡挪了个地方。
		var old_area := 840.0 * 180.0
		lt(hero.get_area(), old_area * 0.25, "the phone card covers less than a quarter of the old 840x180 strip at %s" % viewport)

func test_touch_card_fits_every_readout_it_keeps() -> void:
	# 收窄不等于丢信息：头像 + 血条 + 蓝条 + 金币 + KDA 都还得在这根柱子里放得下。
	var card := HudLayout.zones(Vector2(2000.0, 900.0), true)["hero"] as Rect2
	var inner := card.size.x - 28.0
	check(inner >= 190.0, "the inner width still fits a portrait and two bars (%.0f px)" % inner)
	check(card.size.y >= 108.0, "the column keeps room for a portrait, two bars and a footer (%.0f px)" % card.size.y)

# ---------------------------------------------------------------- 接线

func test_real_hud_nodes_do_not_overlap_each_other() -> void:
	# 分区表算得对，不代表摆出来的节点不重叠：PanelContainer 会被内容的最小尺寸顶大，
	# 计划值写小了，面板就往外挤。这里直接建出真实 HUD 量 get_rect()。
	var hud: Control = GameHUD.new()
	hud.setup("p1", "blue", "blade", "苍刃", false, false)
	hud._ready()
	# 先把根节点从「铺满父级」改成左上角定位，才能在无头环境里直接给它一个确定的尺寸。
	hud.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	hud.size = Vector2(1600.0, 900.0)
	hud._apply_layout()
	var nodes := {
		"score": hud._score_panel,
		"minimap": hud._minimap_panel,
		"hero": hud._hero_panel,
		"feed": hud._feed_box,
		"hint": hud._hint_box,
		"shop": hud._shop_button,
		"mode": hud._attack_cluster,
		"skill_q": hud._skill_q,
		"skill_f": hud._summoner_button,
	}
	var keys := nodes.keys()
	for i in keys.size():
		for j in range(i + 1, keys.size()):
			var a: Control = nodes[keys[i]]
			var b: Control = nodes[keys[j]]
			if a == null or b == null:
				continue
			var ra := a.get_rect()
			var rb := b.get_rect()
			check(not ra.intersects(rb), "real HUD: %s %s overlaps %s %s" % [keys[i], ra, keys[j], rb])
	# 面板实际尺寸也不许超出安全边距（不然会被窗口边切掉）。
	var m := HudLayout.MARGIN
	for key in keys:
		var node: Control = nodes[key]
		if node == null:
			continue
		var rect := node.get_rect()
		check(rect.end.y <= 900.0 - m + 0.01, "real HUD: %s hangs past the bottom margin (%s)" % [key, rect])
	hud.free()

func test_zone_sizes_cover_the_measured_minimum_sizes() -> void:
	# 这些最小值是从跑起来的 HUD 里量出来的（tools/probe_hud_rects.gd 输出 min=...）。
	# 分区尺寸一旦小于它，控件就会往外顶，压住邻居。
	check(HudLayout.SCORE_H >= 77.0, "the scoreboard really measures 77 px tall")
	check(HudLayout.HERO_H >= 149.0, "the hero card really measures 149 px tall")
	check(HudLayout.SHOP_H >= 53.0, "the shop button really measures 53 px tall")
	check(HudLayout.SKILL_W >= 96.0 and HudLayout.SKILL_H >= 112.0, "skill buttons are fixed at 96 x 112")
	check(HudLayout.MODE_H >= 84.0, "the compact attack-mode strip keeps its two 30 px rows")
	check(HudLayout.MINIMAP_H >= 248.0, "the minimap panel needs 248 px for the map plus the objective line")

func test_game_hud_reads_the_shared_layout() -> void:
	# 防「分区表写好了但没人用」：HUD 必须从 HudLayout 取坐标。
	var source := FileAccess.get_file_as_string("res://scripts/ui/game_hud.gd")
	check(source.contains("HudLayout.zones("), "GameHUD must position panels from HudLayout.zones()")
	check(source.contains("func _apply_layout"), "GameHUD must re-apply the layout on resize")
	check(not source.contains("offset_left = -430.0"), "the old hand-written feed offsets must be gone")
	# 键位表不该永久压在战场上：进场十几秒后要淡出，改到 Esc 菜单里查。
	check(source.contains("_fade_hints_after("), "the key legend must fade out instead of sitting on the battlefield")
	check(source.contains("KEY_HINTS"), "the key legend must still be reachable from the pause menu")
