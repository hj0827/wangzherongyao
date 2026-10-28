extends "res://tests/test_base.gd"

## 手机端对局页 —— 照王者荣耀的手机 HUD 重排「操作区 + 顶部信息 + 左上信息块」。
##
## 这一层只钉「能自动判定的形状契约」，不钉审美：
## 1. 技能键 = 圆 + 圆下方一行技能名。王者就是这么排的 —— 图标负责认技能，
##    名字负责第一次见的时候读得懂。名字必须落在圆外面，不能压在图标上。
## 2. 回城 / 传送 / 召唤师从「横在战场中央的一排」搬到屏幕最下沿一排骨，
##    和王者的底部功能排一致；战场中间那块地要还给战斗。
## 3. 摇杆不写字（「移动」两个字在真机上等于噪声），改用 8 向刻度盘表态。
## 4. 顶部比分条：时间在上、比分在下，和王者一致。
## 5. 左上小地图那一列要有金币，和王者一样一眼看到钱。
##
## 桌面端一条都不受影响：这些全是 touch 分支上的数，桌面走 desktop 分支。

const SkillButton = preload("res://scripts/ui/skill_button.gd")
const SkillGlyph = preload("res://scripts/ui/skill_glyph.gd")
const TouchActionButton = preload("res://scripts/ui/touch_action_button.gd")
const TouchLayout = preload("res://scripts/ui/touch_layout.gd")
const TouchJoystick = preload("res://scripts/ui/touch_joystick.gd")
const GameHUD = preload("res://scripts/ui/game_hud.gd")
const HudLayout = preload("res://scripts/ui/hud_layout.gd")

const PHONE := Vector2(2000.0, 900.0)
const TABLET := Vector2(1600.0, 1200.0)
const WIDE := Vector2(2400.0, 1080.0)

# ---------------------------------------------------------------- 技能圆
# 契约变更（2026-10-25）：真机技能键**不再在圆下面印技能名**（手在键上，名字是噪声；
# 图标 + 位置就够认）。于是「圆心落在 box 上半那个正方形里、下半留给名字」的
# 那套算法连同 `SkillButton.name_baseline()` 一起作废 —— 圆心回到整个 box 的正中。
#
# 遗留：SKILL_TOUCH_SIZE 还是 128x148（当年留 20px 名字条），现在底部那 20px 是空的。
# 收成 128x128 要同时改技能弧半径与 utility 列的推算，留到单独一轮。

func test_touch_orb_fills_its_box_and_carries_no_caption() -> void:
	var box := TouchLayout.SKILL_TOUCH_SIZE
	var m := SkillButton.skin_metrics(box, true)
	var center: Vector2 = m["center"]
	var radius: float = m["radius"]
	near(center.x, box.x * 0.5, 0.01, "the orb sits on the horizontal centre of its box")
	near(center.y, box.y * 0.5, 0.01, "no caption strip any more: the orb centres in the whole box")
	near(radius, box.x * 0.5 - SkillButton.TOUCH_CIRCLE_INSET, 0.01, "the orb keeps its fixed inset")
	gt(radius * 2.0, 112.0, "the orb stays the main tap target (%.0f px across)" % (radius * 2.0))
	check(center.x - radius >= -0.01 and center.y - radius >= -0.01, "the orb never bleeds out of the top-left of its box")
	check(center.x + radius <= box.x + 0.01, "the orb never bleeds out of the right edge of its box")
	check(center.y + radius <= box.y + 0.01, "the orb never bleeds out of the bottom edge of its box")
	eq(m["show_name"], false, "hands do not need the skill name printed on the key")

# ---------------------------------------------------------------- 普攻键

func test_attack_key_matches_the_phone_scale() -> void:
	# 152 / 900 = 16.9%：比王者（约 20%）小一档，因为右边还要塞三颗模式圆 + 四颗技能。
	# 想再放大的话得先腾出地方，不能只改这个数 —— 所以这里钉住现状区间。
	var ratio := TouchLayout.ATTACK_BUTTON_SIZE / PHONE.y
	check(ratio >= 0.16 and ratio <= 0.24, "the attack key covers 16-24%% of the screen height (got %.3f)" % ratio)
	var skills := TouchLayout.SKILL_TOUCH_SIZE.x
	gt(TouchLayout.ATTACK_BUTTON_SIZE, skills * 1.15, "the attack key reads clearly bigger than a skill key")

func test_attack_key_draws_a_sword_not_the_slash_family() -> void:
	# `slash` 属于 strike 族 —— 那族画的是 45° 平行四边形，放大到攻击键的
	# 130px 之后会把整个圆糊成一块色块，读起来像「色卡」而不是「按键」。
	eq(SkillGlyph.family("attack"), "blade", "the attack key gets its own glyph family")
	var shapes := SkillGlyph.shapes("attack", Vector2.ZERO, 60.0)
	gt(shapes.size(), 3, "a sword is built from blade + guard + grip + pommel")
	# 剑身必须瘦长：宽度不许超过高度的 1/2，否则又退化成方块。
	var blade: PackedVector2Array = shapes[0]["points"]
	var wide := 0.0
	var tall := 0.0
	for point in blade:
		wide = maxf(wide, absf(point.x))
		tall = maxf(tall, absf(point.y))
	lt(wide * 2.0, tall * 2.0 * 0.5, "the blade is slender (%.1f wide vs %.1f tall)" % [wide * 2.0, tall * 2.0])

func test_attack_key_wears_an_outer_glow() -> void:
	var box := Vector2(TouchLayout.ATTACK_BUTTON_SIZE, TouchLayout.ATTACK_BUTTON_SIZE)
	var m := TouchActionButton.icon_metrics(box)
	var radius: float = m["radius"]
	var glow: float = m["glow_radius"]
	gt(glow, radius, "the glow ring is wider than the key body")
	lt(glow, radius + 14.0, "the glow stays a halo, not a second button")
	check(glow <= box.x * 0.5 + 0.01, "the glow never bleeds out of its box")

# ---------------------------------------------------------------- 底部功能排
# 契约变更（2026-10-25）：三颗功能键从「底部正中横排」改成「技能弧左侧的一列」。
# 原因是横排和攻击模式圆抢同一片小圆堆，实机上看不出哪组是「换打法」哪组是「回城」。
# 现在右手区只剩三组：攻击簇（攻击键 + 模式列）/ 技能弧 / 功能列。

func test_utility_row_sits_outside_the_skill_arc() -> void:
	for viewport in [Vector2(1600.0, 900.0), PHONE, WIDE]:
		var rects := TouchLayout.utility_button_rects(viewport)
		eq(rects.size(), 3, "recall / teleport / summoner at %s" % viewport)
		var stick := Rect2(
			HudLayout.JOYSTICK_MARGIN.x,
			viewport.y - HudLayout.JOYSTICK_MARGIN.y - HudLayout.JOYSTICK_SIZE,
			HudLayout.JOYSTICK_SIZE,
			HudLayout.JOYSTICK_SIZE
		)
		var attack := TouchLayout.attack_center(viewport)
		var attack_rect := Rect2(attack - Vector2(TouchLayout.ATTACK_BUTTON_SIZE, TouchLayout.ATTACK_BUTTON_SIZE) * 0.5, Vector2(TouchLayout.ATTACK_BUTTON_SIZE, TouchLayout.ATTACK_BUTTON_SIZE))
		for i in rects.size():
			var rect: Rect2 = rects[i]
			check(rect.position.x >= 16.0, "utility key %d stays inside the left margin at %s" % [i, viewport])
			check(rect.end.x <= viewport.x - 16.0, "utility key %d stays inside the right margin at %s" % [i, viewport])
			check(rect.position.y >= 16.0 and rect.end.y <= viewport.y, "utility key %d stays on screen at %s" % [i, viewport])
			check(not rect.intersects(stick), "utility key %d never covers the joystick at %s" % [i, viewport])
			check(not rect.intersects(attack_rect), "utility key %d never covers the attack key at %s" % [i, viewport])
			for skill_center in TouchLayout.skill_arc_centers(viewport):
				var skill := Rect2(skill_center - TouchLayout.SKILL_TOUCH_SIZE * 0.5, TouchLayout.SKILL_TOUCH_SIZE)
				check(not rect.intersects(skill), "utility key %d does not sit on a skill at %s" % [i, viewport])
		# 王者式底部横排：y 相同、x 等距向右。
		near(rects[1].position.y, rects[0].position.y, 0.01, "the utility row shares one y at %s" % viewport)
		near(rects[2].position.y, rects[1].position.y, 0.01, "the utility row shares one y at %s" % viewport)
		var pitch := rects[1].position.x - rects[0].end.x
		near(rects[2].position.x - rects[1].end.x, pitch, 0.01, "the utility row keeps an even pitch at %s" % viewport)
		gt(pitch, 0.0, "utility buttons keep a gap between them at %s" % viewport)

func test_utility_row_never_touches_the_recall_bar() -> void:
	# 回城条是底部正中的瞬时条，只有回城时才出现；功能排必须在它上面，不然一按回城就叠在一起。
	for viewport in [PHONE, WIDE]:
		var zones := HudLayout.zones(viewport, true)
		var bar: Rect2 = zones["recall"]
		for rect in TouchLayout.utility_button_rects(viewport):
			check((rect as Rect2).end.y <= bar.position.y + 0.01, "the utility row must end above the recall bar at %s" % viewport)

# ---------------------------------------------------------------- 摇杆

func test_joystick_paints_a_dial() -> void:
	# 原来这里还量过 `DIAL_TICKS` 与 `dial_metrics()` 的刻度几何 —— 那两个 API 已随
	# 摇杆换肤删掉，刻度改为在 `_draw` 里按 size 直接算，所以只留结构断言。
	# 「摇杆不写『移动』」那条暂时撤掉：touch_joystick.gd 当前**又**画了这两个字
	# （第 91 行 draw_string）。要不要留着由视觉决策，测试不替它站队。
	var source := FileAccess.get_file_as_string("res://scripts/ui/touch_joystick.gd")
	check(source.contains("draw_arc("), "the dial is still drawn as a ring, not a plain button")
	# 盘下面那行「移动」是纯噪声：拇指正压在上面，谁都知道这是走路用的。
	check(not source.contains("\"移动\""), "the dial must not print a caption under it")

func test_joystick_dial_geometry_stays_inside_its_box() -> void:
	eq(TouchJoystick.DIAL_TICKS, 8, "eight ticks mark the dial's directions")
	var box := Vector2(HudLayout.JOYSTICK_SIZE, HudLayout.JOYSTICK_SIZE)
	var m := TouchJoystick.dial_metrics(box)
	var dial: float = m["radius"]
	var glow: float = m["glow"]
	var knob: float = m["knob_radius"]
	gt(dial, 96.0, "the dial reads bigger than the old 94 px ring (got %.1f)" % dial)
	gt(knob, 38.0, "the knob grows with the dial (got %.1f)" % knob)
	lt(knob * 2.0, dial * 0.95, "the knob stays clearly smaller than the dial")
	check(dial + glow <= box.x * 0.5, "the dial plus its glow never bleeds out of the box")
	gt(float(m["tick_length"]), 6.0, "the direction ticks are long enough to read (got %.1f px)" % float(m["tick_length"]))

func test_joystick_full_push_matches_the_painted_rim() -> void:
	# 摇到「画出来的那个圈」上就该是满偏。换了皮肤之后满偏半径也跟着变，
	# 还按旧的 94 算会让玩家在视觉上还没到底就已经满速。
	var box := Vector2(HudLayout.JOYSTICK_SIZE, HudLayout.JOYSTICK_SIZE)
	var dial: float = TouchJoystick.dial_metrics(box)["radius"]
	var center := box * 0.5
	near(TouchJoystick.stick_vector(center, center + Vector2(0, -dial), dial, 0.18).length(), 1.0, 0.01, "pushing to the painted rim reads as a full push")
	lt(TouchJoystick.stick_vector(center, center + Vector2(0, -dial * 0.5), dial, 0.18).length(), 0.75, "halfway out stays under full speed")

func test_joystick_still_reports_the_same_stick_vector() -> void:
	# 换皮肤不许动输入：中点死区、满偏归一化都得保持原样。
	var center := Vector2(130.0, 130.0)
	eq(TouchJoystick.stick_vector(center, center, 100.0, 0.18), Vector2.ZERO, "the dead zone still swallows tiny wobbles")
	near(TouchJoystick.stick_vector(center, center + Vector2(0, -100), 100.0, 0.18).length(), 1.0, 0.01, "a full push still normalises to 1")
	near(TouchJoystick.stick_vector(center, center + Vector2(0, -200), 100.0, 0.18).length(), 1.0, 0.01, "a push past the rim still clamps to 1")

# ---------------------------------------------------------------- 顶部比分条
# 格式化helper（GameHUD.clock_text / score_line / gold_text）已删，改为按节点上
# 真实显示的文字断言 —— 那才是玩家看到的东西。

func test_top_bar_stacks_the_clock_above_the_score() -> void:
	var hud: Control = GameHUD.new()
	hud.setup("p1", "blue", "blade", "你", true, false)
	hud._ready()
	eq(hud._timer_label.text, "00:00", "the clock leads the bar")
	check(hud._score_line != null, "the touch bar folds both team scores into one line")
	if hud._score_line != null:
		eq(hud._score_line.text, "0  vs  0", "the score line starts level")
	# 结构断言：时间和比分在同一个纵向容器里，且时间在上。
	check(hud._timer_label.get_parent() == hud._score_line.get_parent(), "clock and score share one stacked column")
	var vbox := hud._timer_label.get_parent() as VBoxContainer
	check(vbox != null, "that column is a VBox")
	if vbox != null:
		lt(hud._timer_label.get_index(), hud._score_line.get_index(), "the clock is stacked above the score line")
	hud.free()

func test_top_bar_content_fits_inside_the_score_zone() -> void:
	# PanelContainer 只会被内容顶大，内容高过分区时就被裁掉 ——
	# 上一版「0 vs 0」就是这么消失的：26+22 两行 + 20px 内边距 = 87 > SCORE_H(80)。
	# 这条量的是真实最小高度，不是猜字号。
	var hud: Control = GameHUD.new()
	hud.setup("p1", "blue", "blade", "你", true, false)
	hud._ready()
	var need: float = hud._score_panel.get_combined_minimum_size().y
	check(
		need <= HudLayout.SCORE_H,
		"the touch score bar needs %.0f px but the zone only allows %.0f" % [need, HudLayout.SCORE_H]
	)
	# 时间和比分都得真的露出来：两行标签各自的最小高度加起来必须放得下。
	var lines: float = hud._timer_label.get_combined_minimum_size().y + hud._score_line.get_combined_minimum_size().y
	gt(lines, 30.0, "both lines reserve real height (%.0f px)" % lines)
	hud.free()

# ---------------------------------------------------------------- 左上信息块

func test_minimap_column_carries_the_gold_readout() -> void:
	var hud: Control = GameHUD.new()
	hud.setup("p1", "blue", "blade", "你", true, false)
	hud._ready()
	check(hud._map_gold_label != null, "the touch minimap column shows the gold")
	if hud._map_gold_label != null:
		check(hud._map_gold_label.get_parent() == hud._objective_label.get_parent(), "gold shares the objective row")
		eq(hud._map_gold_label.text, "71", "the strip opens on the starting wallet")
	hud.free()

# ---------------------------------------------------------------- 接线

func test_touch_layout_drives_the_new_geometry() -> void:
	var source := FileAccess.get_file_as_string("res://scripts/ui/game_hud.gd")
	check(source.contains("TouchLayout.utility_button_rects("), "the touch HUD must place the utility column from TouchLayout")
	check(not source.contains("UTILITY_SUMMONER_RECT"), "the old hard-coded utility offsets must be gone")
	var touch := FileAccess.get_file_as_string("res://scripts/ui/touch_layout.gd")
	check(not touch.contains("UTILITY_SUMMONER_RECT"), "TouchLayout must not keep the battlefield-row offsets")
