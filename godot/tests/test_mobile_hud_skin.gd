extends "res://tests/test_base.gd"

## 手机端 HUD 皮肤护栏：照着手游（王者荣耀）的操作区，把「PC 缩小版」的
## 方形技能卡改成手游该有的样子 —— 圆形金环技能键 + 大号普攻键，键面上不再写字。
##
## 为什么这些能自动判：绘制参数全部抽成 `*_metrics()` 纯函数，
## 断言的是「圆心在哪、半径多大、画不画字、几层环」这些数，而不是截图。
## 桌面端不受影响：它走 `desktop` 分支，仍然带技能名和键位角标。

const SkillButton = preload("res://scripts/ui/skill_button.gd")
const TouchActionButton = preload("res://scripts/ui/touch_action_button.gd")
const TouchLayout = preload("res://scripts/ui/touch_layout.gd")
const GameHUD = preload("res://scripts/ui/game_hud.gd")

# ---------------------------------------------------------------- 技能圆

func test_touch_skill_orb_is_centered_and_fills_the_button() -> void:
	var box := TouchLayout.SKILL_TOUCH_SIZE
	var m := SkillButton.skin_metrics(box)
	var center: Vector2 = m["center"]
	var radius: float = m["radius"]
	near(center.x, box.x * 0.5, 0.01, "the orb sits on the horizontal center of its box")
	# 真机键面上不写字（show_name=false），所以 box 下部那条「名字条」已经没有了：
	# 圆心取整个 box 的正中。SKILL_TOUCH_SIZE 仍是 128x148，底部那 20px 留着待收。
	near(center.y, box.y * 0.5, 0.01, "the orb centres in the whole box now that the caption is gone")
	near(
		radius,
		box.x * 0.5 - SkillButton.TOUCH_CIRCLE_INSET,
		0.01,
		"the orb keeps a fixed inset inside its box"
	)
	gt(radius * 2.0, 112.0, "the orb is at least 112 px across — it is the main tap target")
	check(center.x - radius >= -0.01 and center.y - radius >= -0.01, "the orb never bleeds out of the top-left of its box")
	check(center.x + radius <= box.x + 0.01, "the orb never bleeds out of the right edge of its box")
	check(center.y + radius <= box.y + 0.01, "the orb never bleeds out of the bottom edge of its box")

func test_touch_skill_orb_drops_the_keyboard_labels() -> void:
	var m := SkillButton.skin_metrics(TouchLayout.SKILL_TOUCH_SIZE, true)
	eq(m["show_name"], false, "hands do not need the skill name printed under the orb")
	eq(m["show_key_badge"], false, "hands do not need a Q / E / R badge on the orb")
	# 桌面端反过来：键鼠玩家必须看得见按哪个键。
	var desk := SkillButton.skin_metrics(TouchLayout.SKILL_DESKTOP_SIZE, false)
	eq(desk["show_name"], true, "the desktop skin still prints the skill name")
	eq(desk["show_key_badge"], true, "the desktop skin still prints the key badge")

func test_touch_skill_orb_wears_a_two_tone_gold_ring() -> void:
	var m := SkillButton.skin_metrics(TouchLayout.SKILL_TOUCH_SIZE)
	var outer: float = m["ring_outer_width"]
	var inner: float = m["ring_inner_width"]
	var gap: float = m["ring_gap"]
	var radius: float = m["radius"]
	check(outer >= 2.5, "the outer gold band reads at arm's length (>= 2.5 px, got %.1f)" % outer)
	check(inner >= 1.0, "the inner bright ring is at least 1 px (got %.1f)" % inner)
	check(inner < outer, "the inner bright ring is thinner than the outer gold band (%.1f vs %.1f)" % [inner, outer])
	gt(gap, 0.0, "the two rings stay apart instead of merging into one fat stroke")
	gt(radius - gap - inner * 0.5, 0.0, "the inner ring stays inside the orb")
	# draw_arc 的线宽是「中心线两侧各一半」，所以判的是外沿/内沿，不是中心线：
	# 内环的外沿不许越过外环的内沿，否则两环粘成一条粗线。
	lt(radius - gap + inner * 0.5, radius - outer * 0.5, "the inner ring never runs into the outer band")

func test_touch_orb_uses_more_of_the_box_than_the_old_skin() -> void:
	# 旧皮肤：radius = min(128/2 - 8, 148/2 - 16) = 56，且圆心在 y=60。
	# 新皮肤至少要和它一样大，否则「换成圆」会看起来比原来更小。
	var m := SkillButton.skin_metrics(TouchLayout.SKILL_TOUCH_SIZE)
	check(float(m["radius"]) >= 56.0, "the round skin is not allowed to shrink the tap target (got %.1f)" % float(m["radius"]))

# ---------------------------------------------------------------- 普攻键

func test_attack_key_draws_a_blade_glyph_instead_of_the_word() -> void:
	eq(TouchActionButton.draws_label(""), true, "a plain action button (pause / recall) still shows its caption")
	eq(TouchActionButton.draws_label("slash"), false, "the attack key drops the word once it has a glyph")
	var box := Vector2(TouchLayout.ATTACK_BUTTON_SIZE, TouchLayout.ATTACK_BUTTON_SIZE)
	var m := TouchActionButton.icon_metrics(box)
	var center: Vector2 = m["center"]
	near(center.x, box.x * 0.5, 0.01, "the attack glyph is horizontally centered")
	near(center.y, box.y * 0.5, 0.01, "the attack glyph is vertically centered")
	gt(float(m["radius"]), 60.0, "the attack glyph is drawn big (got %.1f)" % float(m["radius"]))
	check(center.x + float(m["radius"]) <= box.x + 0.01, "the attack glyph stays inside its key")

func test_attack_key_outranks_the_skills() -> void:
	var box := Vector2(TouchLayout.ATTACK_BUTTON_SIZE, TouchLayout.ATTACK_BUTTON_SIZE)
	var attack := TouchActionButton.icon_metrics(box)
	var skill := SkillButton.skin_metrics(TouchLayout.SKILL_TOUCH_SIZE)
	gt(float(attack["radius"]), float(skill["radius"]), "the main attack key must read bigger than a skill key")
	gt(TouchLayout.ATTACK_BUTTON_SIZE, TouchLayout.SKILL_TOUCH_SIZE.x, "the attack key's box is wider than a skill's")

# ---------------------------------------------------------------- 接线

func test_touch_hud_wires_the_mobile_skin() -> void:
	# 防「皮肤写好了但没人用」：真机 HUD 建出来的普攻键必须带图标。
	var hud: Control = GameHUD.new()
	hud.setup("p1", "blue", "blade", "你", true, false)
	hud._ready()
	check(hud._attack_button != null, "the touch HUD builds an attack key")
	if hud._attack_button != null:
		gt(String(hud._attack_button.get("icon_kind")).length(), 0, "the attack key must be built with a glyph, not the word 攻击")
		eq(TouchActionButton.draws_label(str(hud._attack_button.get("icon_kind"))), false, "so the word is not painted on top of the glyph")
		check(hud._skill_q != null and hud._skill_q.touch_mode, "the skill keys are built in touch mode")
	hud.free()
