extends "res://tests/test_base.gd"

const MatchMenu = preload("res://scripts/game/match_menu.gd")
const TouchLayout = preload("res://scripts/ui/touch_layout.gd")
const UnitVisualScript = preload("res://scripts/game/unit_visual.gd")
const GameHUD = preload("res://scripts/ui/game_hud.gd")
const Arena = preload("res://scripts/game/arena.gd")

func test_back_key_is_delivered_to_game() -> void:
	eq(
		bool(ProjectSettings.get_setting("application/config/quit_on_go_back", true)),
		false,
		"Android BACK must reach the game instead of finishing the activity"
	)

func test_back_action_opens_and_closes_match_menu() -> void:
	eq(MatchMenu.back_action(false, false, false), "open", "offline BACK opens pause")
	eq(MatchMenu.back_action(false, true, false), "close", "offline BACK closes pause")
	eq(MatchMenu.back_action(true, false, false), "open", "online BACK opens the match menu")
	eq(MatchMenu.back_action(true, true, false), "close", "online BACK closes the match menu")
	eq(MatchMenu.back_action(true, false, true), "leave", "BACK after the result leaves the match")
	eq(MatchMenu.back_action(false, true, true), "leave", "result wins over an open overlay")

func test_online_menu_never_freezes_the_simulation() -> void:
	check(not MatchMenu.freezes_simulation(true), "online menu keeps the authoritative simulation running")
	check(MatchMenu.freezes_simulation(false), "offline pause freezes the simulation")
	eq(MatchMenu.title(true), "对局菜单", "online overlay is a match menu")
	eq(MatchMenu.title(false), "暂停", "offline overlay is a pause")
	check(MatchMenu.hint(true).contains("不会暂停"), "online hint explains the simulation keeps running")
	check(MatchMenu.hint(false).contains("放弃"), "offline hint explains leaving forfeits the match")
	eq(MatchMenu.pause_label(true), "菜单", "online button opens the menu")
	eq(MatchMenu.pause_label(false), "暂停", "offline button pauses")

func test_touch_targets_are_at_least_48dp_on_device() -> void:
	var dpi := 480.0
	var screen_h := 1080.0
	var viewport_h := 900.0
	var min_dp := TouchLayout.MIN_DP
	near(TouchLayout.dp_for_virtual(120.0, screen_h, viewport_h, dpi), 48.0, 0.01, "120 virtual px is 48dp on this phone")
	check(TouchLayout.dp_for_virtual(TouchLayout.PAUSE_BUTTON_SIZE.x, screen_h, viewport_h, dpi) >= min_dp - 0.01, "pause button width")
	check(TouchLayout.dp_for_virtual(TouchLayout.PAUSE_BUTTON_SIZE.y, screen_h, viewport_h, dpi) >= min_dp - 0.01, "pause button height")
	check(TouchLayout.dp_for_virtual(TouchLayout.SKILL_TOUCH_SIZE.x, screen_h, viewport_h, dpi) >= min_dp - 0.01, "skill button width")
	check(TouchLayout.dp_for_virtual(TouchLayout.SKILL_TOUCH_SIZE.y, screen_h, viewport_h, dpi) >= min_dp - 0.01, "skill button height")
	check(TouchLayout.dp_for_virtual(TouchLayout.PAUSE_MENU_BUTTON_HEIGHT, screen_h, viewport_h, dpi) >= min_dp - 0.01, "overlay buttons")
	check(TouchLayout.dp_for_virtual(TouchLayout.RESULT_BUTTON_SIZE.y, screen_h, viewport_h, dpi) >= min_dp - 0.01, "result button")
	check(TouchLayout.dp_for_virtual(TouchLayout.BUTTON_HEIGHT, screen_h, viewport_h, dpi) >= min_dp - 0.01, "menu buttons")
	near(TouchLayout.button_height(true, 58.0), TouchLayout.BUTTON_HEIGHT, 0.001, "touch mode uses the large button")
	near(TouchLayout.button_height(false, 58.0), 58.0, 0.001, "desktop keeps its compact button")

func test_mobile_3d_scale_reduces_fill_cost() -> void:
	var scale := float(ProjectSettings.get_setting("rendering/scaling_3d/scale.mobile", 1.0))
	check(scale <= 0.85, "mobile 3D scale must be <= 0.85 to reach 60 fps")
	check(scale >= 0.6, "mobile 3D scale must stay sharp enough to read the battlefield")

func test_skill_buttons_arc_around_the_left_of_attack() -> void:
	var viewport_size := Vector2(2000.0, 900.0)
	var attack := TouchLayout.attack_center(viewport_size)
	var centers := TouchLayout.skill_arc_centers(viewport_size)
	eq(centers.size(), 4, "four skills sit on the arc")
	for center in centers:
		near(center.distance_to(attack), TouchLayout.SKILL_ARC_RADIUS, 0.01, "skill center follows the attack arc radius")
		# 「在攻击键左侧」的口径是圆心在攻击键中点左边；R 正好落在正上方偏左
		# （264°），它的包围盒和攻击键的包围盒在 x 上重叠是必然的，不该按框去卡。
		lt(center.x, attack.x, "skills stay on the left side of the attack button")
		lt(center.y, attack.y, "skills stay above the attack button center")
		var rect := Rect2(center - TouchLayout.SKILL_TOUCH_SIZE * 0.5, TouchLayout.SKILL_TOUCH_SIZE)
		check(rect.position.x >= 0.0 and rect.position.y >= 0.0, "skill button stays on screen")
		check(rect.end.x <= viewport_size.x and rect.end.y <= viewport_size.y, "skill button stays inside the viewport")
		check(not rect.has_point(attack), "skill button does not cover the attack center")
	check(centers[0].y > centers[2].y, "Q sits lower, closer to the thumb than E")
	check(centers[1].y > centers[3].y, "W sits lower than R")
	for i in centers.size() - 1:
		var chord := centers[i].distance_to(centers[i + 1])
		check(chord >= TouchLayout.SKILL_TOUCH_SIZE.x + 8.0, "adjacent skill touch targets keep a gap")
	var gap := TouchLayout.SKILL_ARC_RADIUS - TouchLayout.ATTACK_BUTTON_SIZE * 0.5 - TouchLayout.SKILL_TOUCH_SIZE.x * 0.5
	check(gap >= 12.0, "skill circles clear the attack button")

func test_utility_buttons_form_a_bottom_row_like_honor_of_kings() -> void:
	# 王者常规布局：攻击键在最右，技能弧在左上，召唤师/传送/回城在技能弧左侧
	# 沿底部排成一行（召唤师离技能最近）。这条守的是位置、顺序，以及不许压到
	# 技能、攻击键和屏幕外。
	for viewport_size in [Vector2(1600.0, 900.0), Vector2(2000.0, 900.0), Vector2(2400.0, 1080.0)]:
		var attack := TouchLayout.attack_center(viewport_size)
		var attack_rect := Rect2(attack - Vector2(TouchLayout.ATTACK_BUTTON_SIZE, TouchLayout.ATTACK_BUTTON_SIZE) * 0.5, Vector2(TouchLayout.ATTACK_BUTTON_SIZE, TouchLayout.ATTACK_BUTTON_SIZE))
		var skill_rects: Array[Rect2] = []
		for center in TouchLayout.skill_arc_centers(viewport_size):
			skill_rects.append(Rect2(center - TouchLayout.SKILL_TOUCH_SIZE * 0.5, TouchLayout.SKILL_TOUCH_SIZE))
		var names := ["recall", "teleport", "summoner"]
		var slots := TouchLayout.utility_button_rects(viewport_size)
		eq(slots.size(), names.size(), "three utility sockets at %s" % viewport_size)
		for i in slots.size():
			var rect: Rect2 = slots[i]
			check(rect.position.x >= 0.0 and rect.position.y >= 0.0, "%s utility button stays on screen" % names[i])
			check(rect.end.x <= viewport_size.x and rect.end.y <= viewport_size.y, "%s utility button stays inside the viewport" % names[i])
			check(not rect.intersects(attack_rect), "%s utility button does not cover the attack key" % names[i])
			for j in skill_rects.size():
				check(not rect.intersects(skill_rects[j]), "%s utility button does not overlap skill %d" % [names[i], j])
			if i > 0:
				# 同一底边、横向排开：不是旧版的竖列。
				near(rect.position.y, slots[0].position.y, 0.001, "utility buttons share one bottom row")
				gt(rect.position.x, slots[i - 1].end.x, "utility buttons advance left to right")
		# 召唤师必须紧贴技能弧，回城离技能最远。
		var arc := TouchLayout.skill_arc_centers(viewport_size)
		var q_left := arc[0].x - TouchLayout.SKILL_TOUCH_SIZE.x * 0.5
		near(slots[2].end.x, q_left - TouchLayout.UTILITY_SKILL_GAP, 0.001, "summoner sits next to the skill arc")

func test_touch_skill_drag_aims_and_cancels() -> void:
	var hud := GameHUD.new()
	hud.setup("p1", "blue", "blade", "你", true, false)
	hud._ready()
	var results: Array = []
	hud.skill_aim_released.connect(func(slot, pos, cancelled): results.append({"slot": slot, "pos": pos, "cancelled": cancelled}))
	check(hud._skill_aim_layer != null, "touch HUD builds the aim overlay")
	hud._on_skill_drag_started("q", Vector2(1700.0, 760.0))
	check(hud._skill_aim_layer.visible, "dragging shows the aim overlay")
	eq(hud._aim_slot, "q", "aim slot is tracked while dragging")
	hud._on_skill_drag_updated("q", Vector2(1500.0, 500.0))
	hud._on_skill_drag_released("q", Vector2(1500.0, 500.0))
	eq(results.size(), 1, "release emits one intent")
	eq(results[0].slot, "q", "release carries the skill slot")
	eq(results[0].cancelled, false, "release outside the cancel zone casts")
	check(not hud._skill_aim_layer.visible, "aim overlay hides after release")
	
	var center: Vector2 = hud._cancel_zone_position()
	hud._on_skill_drag_started("w", Vector2(1700.0, 760.0))
	hud._on_skill_drag_released("w", center)
	eq(results.size(), 2, "cancelled drag still emits one intent")
	eq(results[1].cancelled, true, "release inside the cancel zone cancels the cast")
	hud.free()

func test_arena_skill_aim_release_queues_or_cancels() -> void:
	var arena: Node3D = Arena.new()
	arena._on_skill_aim_released("q", Vector2.ZERO, true)
	check(not arena._queued_q, "cancelled aim does not queue the skill")
	arena._on_skill_aim_released("q", Vector2.ZERO, false)
	check(arena._queued_q, "confirmed aim queues the skill")
	arena.free()

func test_critical_hit_triggers_hit_stop() -> void:
	var arena: Node3D = Arena.new()
	arena._process_events([{"type": "attack", "hero": 1, "crit": true}])
	check(arena._hit_stop.is_frozen(), "critical hit freezes the presentation briefly")
	arena._hit_stop.tick(0.1)
	check(not arena._hit_stop.is_frozen(), "hit stop expires")
	arena.free()

func test_hero_model_is_visibly_larger_than_minions() -> void:
	check(UnitVisualScript.HERO_HEIGHT >= 2.6, "heroes stand taller than 2.6 m")
	check(UnitVisualScript.MINION_HEIGHT <= 1.6, "minions stay small")
	var ratio: float = UnitVisualScript.HERO_HEIGHT / UnitVisualScript.MINION_HEIGHT
	check(ratio >= 2.0, "heroes read at least 2x taller than minions")
	near(
		UnitVisualScript.scale_for_height(1.82, UnitVisualScript.HERO_HEIGHT),
		UnitVisualScript.HERO_HEIGHT / 1.82,
		0.001,
		"hero scale is derived from the measured model height"
	)
	near(UnitVisualScript.scale_for_height(0.0, 2.4), 1.0, 0.001, "missing bounds keep the authored scale")

# ---------------------------------------------------------------- 攻击模式按钮

func test_attack_mode_buttons_sit_beside_the_attack_key() -> void:
	# 用户原话：「攻击的形式放在攻击键的附近的，也是攻击键的形式」。
	# 所以三颗模式按钮必须是紧贴攻击键的一列圆，而不是左下角那条横面板。
	for viewport in [Vector2(1600.0, 900.0), Vector2(2000.0, 900.0), Vector2(2400.0, 1080.0)]:
		var rects := TouchLayout.mode_button_rects(viewport)
		eq(rects.size(), 3, "three attack modes = three buttons at %s" % viewport)
		var attack := Rect2(
			TouchLayout.attack_center(viewport) - Vector2(TouchLayout.ATTACK_BUTTON_SIZE, TouchLayout.ATTACK_BUTTON_SIZE) * 0.5,
			Vector2(TouchLayout.ATTACK_BUTTON_SIZE, TouchLayout.ATTACK_BUTTON_SIZE)
		)
		for i in rects.size():
			var rect: Rect2 = rects[i]
			near(rect.size.x, rect.size.y, 0.01, "mode button %d is round (square box)" % i)
			check(rect.position.x >= 0.0 and rect.position.y >= 0.0, "mode button %d stays on screen at %s" % [i, viewport])
			check(rect.end.x <= viewport.x and rect.end.y <= viewport.y, "mode button %d stays inside the viewport at %s" % [i, viewport])
			check(not rect.intersects(attack), "mode button %d must not sit on the attack key at %s" % [i, viewport])
			# 「附近」= 离攻击键不超过一个攻击键半径：看得见、够得着。
			check(rect.get_center().distance_to(attack.get_center()) <= TouchLayout.ATTACK_BUTTON_SIZE * 2.2, "mode button %d drifts away from the attack key at %s" % [i, viewport])
			if i > 0:
				check(not rect.intersects(rects[i - 1]), "mode button %d overlaps its neighbour at %s" % [i, viewport])
		# 逐个技能比，不用弧的包围盒：Q 和 R 之间那条斜缝是空的，
		# 用包围盒会把缝里也算成禁区，逼着按钮缩成点不准的小圆。
		for center in TouchLayout.skill_arc_centers(viewport):
			var skill := Rect2(center - TouchLayout.SKILL_TOUCH_SIZE * 0.5, TouchLayout.SKILL_TOUCH_SIZE)
			for i in rects.size():
				check(not (rects[i] as Rect2).intersects(skill), "mode button %d covers a skill at %s" % [i, viewport])

func test_mobile_hud_builds_round_mode_buttons_instead_of_the_strip() -> void:
	# 接线检查：真机 HUD 必须建出这三颗按钮，并且不再把横条面板摆在左下角。
	var hud: Control = GameHUD.new()
	hud.setup("p1", "blue", "blade", "你", true, false)
	hud._ready()
	hud.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	hud.size = Vector2(2000.0, 900.0)
	hud._apply_layout()
	eq(hud._mode_buttons.size(), 3, "touch HUD builds three round mode buttons")
	check(hud._attack_cluster == null, "touch HUD no longer builds the desktop mode strip")
	eq(hud._lock_bar != null, true, "touch HUD builds the lock bar")
	var expected := TouchLayout.mode_button_rects(Vector2(2000.0, 900.0))
	for i in hud._mode_buttons.size():
		var node: Control = hud._mode_buttons[i]
		var rect := node.get_rect()
		near(rect.get_center().x, expected[i].get_center().x, 1.0, "mode button %d is placed from TouchLayout" % i)
		near(rect.get_center().y, expected[i].get_center().y, 1.0, "mode button %d is placed from TouchLayout" % i)
	hud.free()

func test_mode_button_source_draws_a_circle_like_the_attack_key() -> void:
	# 「也是攻击键的形式」：圆。用源码断言挡住「悄悄换成方按钮」。
	var source := FileAccess.get_file_as_string("res://scripts/ui/attack_mode_button.gd")
	check(source.contains("draw_circle("), "the mode button must draw a circle like the attack key")
	check(source.contains("draw_arc("), "the mode button keeps the same ring as the attack key")
	check(not source.contains("StyleBox"), "no panel style box: the button is drawn, not skinned")
