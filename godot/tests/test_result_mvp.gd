extends "res://tests/test_base.gd"

# 结算页 MVP（P1 UI-06 的第一版）。
# 只读现有快照的 kills/deaths：kills>=3 且 kills>deaths 显示 MVP，否则参战。

const GameHUD = preload("res://scripts/ui/game_hud.gd")

func _hud() -> Control:
	var hud: Control = GameHUD.new()
	hud.setup("p1", "blue", "blade", "苍刃", false, false)
	hud._ready()
	var tree := Engine.get_main_loop() as SceneTree
	tree.root.add_child(hud)
	hud._apply_layout()
	hud.snapshot = {"scores": {"blue": {"towers": 2}}, "time": 600.0}
	return hud

func test_winner_with_good_kda_gets_mvp_badge_and_avatar() -> void:
	var hud := _hud()
	hud.show_result("blue", {"kills": 5, "deaths": 1})
	check(hud._result_overlay.visible, "结算遮罩要显示")
	check(hud._result_avatar.texture != null, "结算页要有本地英雄头像")
	eq(hud._result_badge.text, "MVP", "5/1 应显示 MVP")
	hud.free()

func test_poor_kda_shows_participation_badge() -> void:
	var hud := _hud()
	hud.show_result("blue", {"kills": 0, "deaths": 3})
	eq(hud._result_badge.text, "参战", "0/3 不应强行显示 MVP")
	hud.free()

func test_loss_still_shows_avatar() -> void:
	var hud := _hud()
	hud.show_result("red", {"kills": 1, "deaths": 2})
	check(hud._result_avatar.texture != null, "失败结算也要有英雄头像")
	check(hud._result_title.text.contains("战"), "失败标题要正确")
	hud.free()

# ---------------------------------------------------------------- UI-06 结算数据条 / 点赞

func test_result_bars_normalize_against_team_peak() -> void:
	var hud := _hud()
	hud.snapshot = {
		"scores": {"blue": {"towers": 2}},
		"time": 600.0,
		"entities": [
			{"type": "hero", "team": "blue", "kills": 4, "assists": 1,
				"damage_dealt": 20000.0, "damage_taken": 8000.0},
			{"type": "hero", "team": "blue", "kills": 1, "assists": 2,
				"damage_dealt": 10000.0, "damage_taken": 16000.0},
			# 敌方数值不参与归一化：否则 50000 会把本队所有人的条压扁。
			{"type": "hero", "team": "red", "kills": 9, "assists": 0,
				"damage_dealt": 50000.0, "damage_taken": 30000.0},
		],
	}
	hud.show_result("blue", {
		"kills": 1, "assists": 2, "deaths": 2,
		"damage_dealt": 10000.0, "damage_taken": 16000.0,
	})
	near(float(hud._result_bars["dealt"].bar.value), 0.5, 0.01, "输出条按本队峰值 20000 归一化")
	near(float(hud._result_bars["taken"].bar.value), 1.0, 0.01, "承伤条取本队最高")
	near(float(hud._result_bars["join"].bar.value), 0.6, 0.01, "参团 = (1+2)/本队总击杀 5")
	eq(str(hud._result_bars["dealt"].value.text), "10.0k", "输出读数使用 k 缩写")
	eq(str(hud._result_bars["join"].value.text), "60%", "参团读数显示百分比")
	hud.free()

func test_result_like_is_one_shot_ui_only() -> void:
	var hud := _hud()
	hud.show_result("blue", {"kills": 3, "deaths": 1})
	eq(str(hud._like_button.text), "点赞", "结算页提供点赞入口")
	hud._on_result_like()
	eq(str(hud._like_button.text), "已点赞 (1)", "点赞后给出本地反馈")
	check(hud._like_button.disabled, "同一局只能点一次")
	hud.show_result("blue", {"kills": 3, "deaths": 1})
	check(not hud._like_button.disabled, "重新结算时恢复可点")
	eq(str(hud._like_button.text), "点赞", "重新结算时计数归零")
	hud.free()
