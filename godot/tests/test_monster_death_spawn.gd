extends "res://tests/test_base.gd"

# 野怪死亡下沉 + 重生 scale-in（P0 视觉升级）。
#
# 旧版死亡只是前倒 + 0.82 缩放，尸体以完整大小杵到复活；
# 现在最后 0.6s 沉进地面，重生从 0.25 倍缩放回场。

const UnitVisual = preload("res://scripts/game/unit_visual.gd")

func _alive() -> Dictionary:
	return {
		"x": 0.0, "y": 0.0, "hp": 500.0, "max_hp": 500.0, "alive": true,
		"facing_x": 0.0, "facing_y": 1.0, "moving": false,
	}

func test_death_sinks_into_the_ground_and_respawn_scales_back() -> void:
	var view := UnitVisual.new()
	view.setup("monster", "neutral", "boar", "三猪", false, "blue")
	var alive := _alive()
	view.set_snapshot(alive, 1.0)
	for i in 8:
		view.process_visual(0.05)
	var rest_y := view._model_rest_scale.y
	check(view._spawn_scale_timer <= 0.0, "初始缩放入场应已结束")

	var dead := alive.duplicate()
	dead["hp"] = 0.0
	dead["alive"] = false
	view.set_snapshot(dead, 1.0)
	for i in 20:
		view.process_visual(0.05)
	check(view.model_root.rotation.x < -0.2, "死亡先向前倒地")
	gt(view.model_root.scale.y, rest_y * 0.7, "倒地阶段还保持大体量")

	for i in 30:
		view.process_visual(0.05)
	lt(view.model_root.scale.y, rest_y * 0.3, "最后 0.6s 要沉入地面")
	lt(view.model_root.position.y, view._model_rest_position.y - 0.3, "下沉时整体向地面收")

	view.set_snapshot(alive, 1.0)
	gt(view._spawn_scale_timer, 0.0, "复活要触发缩放入场")
	view.process_visual(0.05)
	lt(view.model_root.scale.y, rest_y * 0.9, "重生第一帧要明显小于原体型")
	for i in 8:
		view.process_visual(0.05)
	near(view.model_root.scale.y, rest_y, 0.001, "0.25s 后回到原体型")
	near(view.model_root.rotation.x, 0.0, 0.001, "复活要收回倒地旋转")
	view.free()
