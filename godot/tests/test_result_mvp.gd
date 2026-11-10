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
