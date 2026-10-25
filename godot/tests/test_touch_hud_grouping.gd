extends "res://tests/test_base.gd"

## 真机 HUD 的「分组」护栏。
##
## 用户的原话是「真机页面很混乱，攻击的形式放在攻击键的附近，也是攻击键的形式；
## 锁定是遇见英雄之后出现对方的头像，然后点击用一根线连着」。
##
## 「混乱」不是审美问题，是三条可以量出来的事：
## 1. 攻击方式三颗圆只有攻击键的一半大（76 vs 152），读不成「同一族」；
## 2. 技能弧半径 330 / 间距 25°，圆心距 143，画出来的圆直径 116 —— 只剩 27px 缝，
##    四颗连成一串，看不出是四个按钮；
## 3. 传送 / 回城 / 召唤师三颗 96 的小圆横在技能弧左边，和模式圆混在同一片小圆堆里。
##
## 锁定从「右上角固定槽位」改成「浮在敌方英雄头顶」：右上角离右手拇指最远，
## 45dp 的头像放在那儿等于让人换手；而且三颗 120 的头像会和技能弧最上一颗抢
## 同一块地（攻击键正上方就是 R 的家）。跟着人走之后，头像、线、人都落在同一处，
## 不占任何常驻 HUD 分区。

const TouchLayout = preload("res://scripts/ui/touch_layout.gd")
const HudLayout = preload("res://scripts/ui/hud_layout.gd")
const LockBar = preload("res://scripts/ui/lock_bar.gd")
const GameHUD = preload("res://scripts/ui/game_hud.gd")
const TargetingRules = preload("res://sim/targeting_rules.gd")

const SIZES := [
	Vector2(1600.0, 900.0),
	Vector2(2000.0, 900.0),
	Vector2(2400.0, 1080.0),
]

func _attack_rect(viewport: Vector2) -> Rect2:
	var box := Vector2(TouchLayout.ATTACK_BUTTON_SIZE, TouchLayout.ATTACK_BUTTON_SIZE)
	return Rect2(TouchLayout.attack_center(viewport) - box * 0.5, box)

func _skill_rects(viewport: Vector2) -> Array[Rect2]:
	var rects: Array[Rect2] = []
	for center in TouchLayout.skill_arc_centers(viewport):
		rects.append(Rect2(center - TouchLayout.SKILL_TOUCH_SIZE * 0.5, TouchLayout.SKILL_TOUCH_SIZE))
	return rects

func _gap(a: Rect2, b: Rect2) -> float:
	# 两个矩形之间最短的空隙（相切 = 0，重叠 = 负数，取较大的那一维）。
	var dx := maxf(maxf(a.position.x - b.end.x, b.position.x - a.end.x), 0.0)
	var dy := maxf(maxf(a.position.y - b.end.y, b.position.y - a.end.y), 0.0)
	if a.intersects(b):
		var ox := minf(a.end.x, b.end.x) - maxf(a.position.x, b.position.x)
		var oy := minf(a.end.y, b.end.y) - maxf(a.position.y, b.position.y)
		return -minf(ox, oy)
	return sqrt(dx * dx + dy * dy) if dx > 0.0 and dy > 0.0 else maxf(dx, dy)

# ---------------------------------------------------------------- 攻击簇

func test_mode_buttons_are_scaled_to_the_attack_key_family() -> void:
	# 「也是攻击键的形式」不只是「也是圆的」：差一倍直径就变成另一个系统的按钮。
	# 88 是攻击键 152 的 0.58 —— 缩一档的同族，而不是半尺寸的挂件。
	# 下限 28dp 而不是谷歌的 48dp：这三颗是低频的「换打法」键，王者同类键约 30dp；
	# 再大就顶进 E 的触摸框（见 TouchLayout 里那段走廊推算）。
	for viewport in SIZES:
		var size := TouchLayout.MODE_BUTTON_SIZE
		gt(size, TouchLayout.ATTACK_BUTTON_SIZE * 0.55, "mode buttons read as the same family as the attack key at %s" % viewport)
		lt(size, TouchLayout.ATTACK_BUTTON_SIZE * 0.72, "mode buttons must stay clearly smaller than the attack key at %s" % viewport)
		var dp := TouchLayout.dp_for_virtual(size, 1080.0, viewport.y, 480.0)
		gt(dp, 28.0, "mode buttons are too small to hit at %s (%.1f dp)" % [viewport, dp])

func test_mode_buttons_form_one_tight_column_left_of_the_attack_key() -> void:
	# 「放在攻击键附近」= 贴着它左沿的一列，间隙小于一颗拇指的宽度。
	for viewport in SIZES:
		var attack := _attack_rect(viewport)
		var rects := TouchLayout.mode_button_rects(viewport)
		eq(rects.size(), 3, "three modes = three buttons at %s" % viewport)
		var first: Rect2 = rects[0]
		near(first.end.x, attack.position.x - TouchLayout.MODE_BUTTON_INSET, 0.01, "the column sits right against the attack key at %s" % viewport)
		near(first.end.y, attack.end.y, 0.01, "the column is bottom-aligned with the attack key at %s" % viewport)
		for i in rects.size():
			var rect: Rect2 = rects[i]
			near(rect.size.x, rect.size.y, 0.01, "mode button %d is round at %s" % [i, viewport])
			check(rect.position.x >= 0.0 and rect.position.y >= 0.0, "mode button %d stays on screen at %s" % [i, viewport])
			check(rect.end.x <= viewport.x and rect.end.y <= viewport.y, "mode button %d stays inside the viewport at %s" % [i, viewport])
			check(not rect.intersects(attack), "mode button %d must not sit on the attack key at %s" % [i, viewport])
			if i > 0:
				near(rect.position.y, rects[i - 1].position.y - rect.size.y - TouchLayout.MODE_BUTTON_GAP, 0.01, "mode button %d keeps the column rhythm at %s" % [i, viewport])

func test_mode_buttons_never_cover_a_skill() -> void:
	# 一列模式圆加大到 92 之后最容易踩的雷：挤进 E / R 的触摸框里。
	for viewport in SIZES:
		var rects := TouchLayout.mode_button_rects(viewport)
		for skill in _skill_rects(viewport):
			for i in rects.size():
				check(not (rects[i] as Rect2).intersects(skill), "mode button %d covers a skill at %s" % [i, viewport])

# ---------------------------------------------------------------- 技能弧

func test_skill_arc_opens_up_so_neighbours_stop_touching() -> void:
	# 画出来的圆直径是 box 的短边减 12（见 skill_button.TOUCH_CIRCLE_INSET），
	# 所以「看起来不粘」的口径是圆心距 >= 116 + 36。
	for viewport in SIZES:
		var centers := TouchLayout.skill_arc_centers(viewport)
		eq(centers.size(), 4, "four skills on the arc at %s" % viewport)
		var drawn := minf(TouchLayout.SKILL_TOUCH_SIZE.x, TouchLayout.SKILL_TOUCH_SIZE.y) - 12.0
		for i in range(1, centers.size()):
			gt(
				centers[i - 1].distance_to(centers[i]),
				drawn + 36.0,
				"skills %d and %d are still glued together at %s (%.0f px apart)" % [i - 1, i, viewport, centers[i - 1].distance_to(centers[i])]
			)

func test_skill_arc_stays_in_the_bottom_right_thumb_corner() -> void:
	# 试过「窄屏自动收半径、把 W 的触摸框推出中央视野区」，结果是圆心距掉到 148
	# —— 又变回「连成一串」。16:9 下四颗 128 的触摸框 + 152 的攻击键挤在 432px 宽的
	# 地块里，W/E 擦进视野区右下角是物理极限（见 TouchLayout 里那段推算）。
	# 所以这里守的是真正可守的三条：留在右半屏、不出画、不压到顶部信息带。
	for viewport in SIZES:
		for i in _skill_rects(viewport).size():
			var rect: Rect2 = _skill_rects(viewport)[i]
			gt(rect.get_center().x, viewport.x * 0.5, "skill %d drifts into the left half at %s" % [i, viewport])
			check(rect.position.x >= 0.0 and rect.position.y >= 0.0, "skill %d leaks past the top/left edge at %s" % [i, viewport])
			check(rect.end.x <= viewport.x, "skill %d leaks past the right edge at %s" % [i, viewport])
			check(rect.end.y <= viewport.y, "skill %d leaks past the bottom edge at %s" % [i, viewport])
			var top_band: Rect2 = HudLayout.zones(viewport, true)["minimap"]
			check(rect.position.y > top_band.end.y, "skill %d climbs into the minimap band at %s" % [i, viewport])

# ---------------------------------------------------------------- 功能键

func test_utility_buttons_leave_the_thumb_core() -> void:
	# 传送 / 回城 / 召唤师是低频键，不该跟模式圆挤在同一片小圆堆里：
	# 至少离攻击键两个半径远，并且自成一条竖列。
	for viewport in SIZES:
		var rects := TouchLayout.utility_button_rects(viewport)
		eq(rects.size(), 3, "summoner + teleport + recall = three utility keys at %s" % viewport)
		var attack := _attack_rect(viewport)
		for i in rects.size():
			var rect: Rect2 = rects[i]
			near(rect.size.x, rect.size.y, 0.01, "utility key %d is round at %s" % [i, viewport])
			gt(
				rect.get_center().distance_to(attack.get_center()),
				TouchLayout.ATTACK_BUTTON_SIZE * 2.0,
				"utility key %d still crowds the attack key at %s" % [i, viewport]
			)
			check(rect.position.x >= 0.0 and rect.position.y >= 0.0, "utility key %d stays on screen at %s" % [i, viewport])
			check(rect.end.x <= viewport.x and rect.end.y <= viewport.y, "utility key %d stays inside the viewport at %s" % [i, viewport])
			if i > 0:
				# 功能列是从上往下画的（rects[0] 在最上），所以下一颗的 y 更大。
				near(rect.position.y, rects[i - 1].end.y + TouchLayout.UTILITY_BUTTON_GAP, 0.01, "utility key %d keeps the column rhythm at %s" % [i, viewport])

func test_utility_buttons_never_cover_a_skill_mode_or_the_attack_key() -> void:
	for viewport in SIZES:
		var rects := TouchLayout.utility_button_rects(viewport)
		var attack := _attack_rect(viewport)
		var modes := TouchLayout.mode_button_rects(viewport)
		var skills := _skill_rects(viewport)
		for rect in rects:
			check(not (rect as Rect2).intersects(attack), "a utility key sits on the attack key at %s" % viewport)
			for mode in modes:
				gt(_gap(rect, mode), 15.0, "a utility key touches a mode button at %s (%.0f px)" % [viewport, _gap(rect, mode)])
			for skill in skills:
				gt(_gap(rect, skill), 15.0, "a utility key touches a skill at %s (%.0f px)" % [viewport, _gap(rect, skill)])

# ---------------------------------------------------------------- 锁定：跟着人走

func _bar(viewport: Vector2) -> Control:
	var bar: Control = LockBar.new()
	bar.setup(true)
	bar.size = viewport
	return bar

func _target(id: int, dist: float, screen: Vector2, hero_type := "blade") -> Dictionary:
	return {"id": id, "hero_type": hero_type, "name": "敌人%d" % id, "screen": screen, "dist": dist}

func test_lock_portrait_hangs_above_the_enemy_it_belongs_to() -> void:
	# 「遇见英雄之后出现对方的头像」—— 头像是那个人的头部标记，不是 HUD 上的一个格子。
	var bar := _bar(Vector2(2000.0, 900.0))
	bar.set_targets([_target(7, 6.0, Vector2(900.0, 520.0))])
	var slot: Rect2 = bar.portrait_rect(0)
	near(slot.get_center().x, 900.0, 0.01, "the portrait is horizontally centered on the enemy")
	lt(slot.end.y, 520.0, "the portrait hangs above the enemy's feet point")
	near(slot.end.y, 520.0 - LockBar.HEAD_CLEARANCE, 0.01, "the portrait keeps a fixed clearance over the head")
	near(slot.size.x, LockBar.PORTRAIT_SIZE, 0.01, "the portrait keeps its thumb-sized box")

func test_lock_portrait_stays_inside_the_screen_at_the_edges() -> void:
	# 人站在屏幕边上时，头像不能跟着出画（那样等于没有头像）。
	var bar := _bar(Vector2(2000.0, 900.0))
	bar.set_targets([
		_target(1, 4.0, Vector2(10.0, 20.0)),
		_target(2, 5.0, Vector2(1995.0, 895.0)),
	])
	for i in bar.target_count():
		var slot: Rect2 = bar.portrait_rect(i)
		check(slot.position.x >= 0.0 and slot.position.y >= 0.0, "portrait %d leaks off the left/top edge (%s)" % [i, slot])
		check(slot.end.x <= 2000.0 and slot.end.y <= 900.0, "portrait %d leaks off the right/bottom edge (%s)" % [i, slot])

func test_crowded_portraits_never_stack_on_each_other() -> void:
	# 团战时两个敌人可能站在屏幕上同一个点：头像必须自己错开，否则永远点不到下面那个。
	var bar := _bar(Vector2(2000.0, 900.0))
	var targets: Array = []
	for i in 5:
		targets.append(_target(i + 1, 3.0 + float(i), Vector2(1000.0, 480.0)))
	bar.set_targets(targets)
	eq(bar.target_count(), TouchLayout.MAX_LOCK_PORTRAITS, "a crowd still caps the portraits")
	for i in range(1, bar.target_count()):
		check(not bar.portrait_rect(i).intersects(bar.portrait_rect(i - 1)), "portrait %d stacks on its neighbour" % i)

func test_the_lock_line_is_short_enough_to_read() -> void:
	# 「点击用一根线连着」：线是「头像 → 这个人」的短线，不是横穿半个屏幕的长线。
	var bar := _bar(Vector2(2000.0, 900.0))
	bar.set_targets([_target(7, 6.0, Vector2(900.0, 520.0))])
	bar.set_locked(7)
	var line: Array = bar.line_endpoints()
	eq(line.size(), 2, "a locked target draws exactly one line")
	if line.size() < 2:
		return
	var slot: Rect2 = bar.portrait_rect(0)
	near(line[0].x, slot.get_center().x, 0.01, "the line leaves the portrait's centre")
	near(line[1].x, 900.0, 0.01, "the line lands on the enemy")
	near(line[1].y, 520.0, 0.01, "the line lands on the enemy")
	lt(line[0].distance_to(line[1]), LockBar.PORTRAIT_SIZE + LockBar.HEAD_CLEARANCE, "the line must stay a short tether")

func test_tapping_the_head_portrait_locks_and_tapping_again_releases() -> void:
	var bar := _bar(Vector2(2000.0, 900.0))
	var seen: Array = []
	bar.lock_changed.connect(func(target_id: int): seen.append(target_id))
	bar.set_targets([_target(7, 6.0, Vector2(900.0, 520.0))])
	bar.press_portrait(0)
	eq(bar.locked_target, 7, "tapping the head portrait locks that enemy")
	bar.press_portrait(0)
	eq(bar.locked_target, -1, "tapping it again releases the lock")
	eq(seen, [7, -1], "both taps reach the simulation")

func test_lock_no_longer_claims_a_reserved_hud_zone() -> void:
	# 锁定改跟人走之后，右上角那块「锁定条分区」不该再占着常驻 HUD 的位置。
	for viewport in SIZES:
		var zones := HudLayout.zones(viewport, true)
		check(not zones.has("lock"), "the fixed lock-zone reservation is gone at %s" % viewport)

# ---------------------------------------------------------------- 接线

func _hud(viewport: Vector2) -> Control:
	var hud: Control = GameHUD.new()
	hud.setup("p1", "blue", "blade", "苍刃", true, false)
	hud._ready()
	hud.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	hud.size = viewport
	hud._apply_layout()
	return hud

func test_hud_places_utility_keys_from_touch_layout() -> void:
	var hud := _hud(Vector2(2000.0, 900.0))
	var expected := TouchLayout.utility_button_rects(Vector2(2000.0, 900.0))
	var nodes := [hud._summoner_button, hud._teleport_button, hud._recall_button]
	for i in nodes.size():
		var node: Control = nodes[i]
		check(node != null, "utility key %d exists" % i)
		if node == null:
			continue
		var rect := node.get_rect()
		near(rect.get_center().x, expected[i].get_center().x, 1.0, "utility key %d is placed from TouchLayout" % i)
		near(rect.get_center().y, expected[i].get_center().y, 1.0, "utility key %d is placed from TouchLayout" % i)
	hud.free()

func test_utility_keys_shrink_to_their_slot() -> void:
	# 探针抓到的真 bug：召唤师键是 SkillButton，custom_minimum_size 是 128x148，
	# 摆进 96 的格子后被最小尺寸顶大 40px，实拍里压住了下面的「传送」。
	# 无头测试量 get_rect() 量不出来（没进场景树时最小尺寸不生效），所以量最小尺寸本身。
	var hud := _hud(Vector2(2000.0, 900.0))
	var expected := TouchLayout.utility_button_rects(Vector2(2000.0, 900.0))
	var nodes := [hud._summoner_button, hud._teleport_button, hud._recall_button]
	for i in nodes.size():
		var node: Control = nodes[i]
		if node == null:
			continue
		var declared := node.get_combined_minimum_size()
		check(
			declared.x <= expected[i].size.x + 0.01 and declared.y <= expected[i].size.y + 0.01,
			"utility key %d declares a %s minimum, larger than its %s slot" % [i, declared, expected[i].size]
		)
	hud.free()

func test_mode_button_draws_a_ring_like_the_attack_key() -> void:
	# 「也是攻击键的形式」：同一套双层金环。源码断言挡住「悄悄退回单线圆」。
	var source := FileAccess.get_file_as_string("res://scripts/ui/attack_mode_button.gd")
	check(source.contains("draw_arc("), "the mode button keeps the ring of the attack key")
	check(source.contains("ring_gap") or source.contains("RING_GAP"), "the mode button keeps the double ring of the attack key")
