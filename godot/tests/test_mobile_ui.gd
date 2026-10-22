extends "res://tests/test_base.gd"

const MatchMenu = preload("res://scripts/game/match_menu.gd")
const TouchLayout = preload("res://scripts/ui/touch_layout.gd")
const UnitVisualScript = preload("res://scripts/game/unit_visual.gd")

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
	eq(centers.size(), 2, "two skills sit on the arc")
	for center in centers:
		near(center.distance_to(attack), TouchLayout.SKILL_ARC_RADIUS, 0.01, "skill center follows the attack arc radius")
		lt(center.x, attack.x - 40.0, "skills stay on the left side of the attack button")
		lt(center.y, attack.y, "skills stay above the attack button center")
		var rect := Rect2(center - TouchLayout.SKILL_TOUCH_SIZE * 0.5, TouchLayout.SKILL_TOUCH_SIZE)
		check(rect.position.x >= 0.0 and rect.position.y >= 0.0, "skill button stays on screen")
		check(rect.end.x <= viewport_size.x and rect.end.y <= viewport_size.y, "skill button stays inside the viewport")
		check(not rect.has_point(attack), "skill button does not cover the attack center")
	check(centers[0].y > centers[1].y, "Q sits lower, closer to the thumb than E")
	var chord := centers[0].distance_to(centers[1])
	check(chord >= TouchLayout.SKILL_TOUCH_SIZE.x + 8.0, "adjacent skill touch targets keep a gap")
	var gap := TouchLayout.SKILL_ARC_RADIUS - TouchLayout.ATTACK_BUTTON_SIZE * 0.5 - TouchLayout.SKILL_TOUCH_SIZE.x * 0.5
	check(gap >= 12.0, "skill circles clear the attack button")

func test_hero_model_is_visibly_larger_than_minions() -> void:
	check(UnitVisualScript.HERO_HEIGHT >= 2.2, "heroes stand taller than 2.2 m")
	check(UnitVisualScript.MINION_HEIGHT <= 1.6, "minions stay small")
	var ratio: float = UnitVisualScript.HERO_HEIGHT / UnitVisualScript.MINION_HEIGHT
	check(ratio >= 1.6, "heroes read at least 1.6x taller than minions")
	near(
		UnitVisualScript.scale_for_height(1.82, UnitVisualScript.HERO_HEIGHT),
		UnitVisualScript.HERO_HEIGHT / 1.82,
		0.001,
		"hero scale is derived from the measured model height"
	)
	near(UnitVisualScript.scale_for_height(0.0, 2.4), 1.0, 0.001, "missing bounds keep the authored scale")
