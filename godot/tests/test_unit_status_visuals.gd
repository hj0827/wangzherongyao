extends "res://tests/test_base.gd"

# 护盾泡 / BUFF 光环 / 减速环（P0 视觉升级）。
#
# 这些状态全部来自现有快照字段，不新增网络字段：
# shield / buff_red_timer / buff_blue_timer / slow_timer。

const UnitVisual = preload("res://scripts/game/unit_visual.gd")

func _snapshot(extra: Dictionary = {}) -> Dictionary:
	var data := {
		"x": 0.0, "y": 0.0, "hp": 1000.0, "max_hp": 1000.0,
		"mp": 400.0, "max_mp": 400.0, "alive": true,
		"facing_x": 0.0, "facing_y": 1.0, "moving": false,
	}
	for key in extra:
		data[key] = extra[key]
	return data

func test_shield_bubble_follows_shield_ratio() -> void:
	var view := UnitVisual.new()
	view.setup("hero", "blue", "blade", "你", true, "blue")
	view.set_snapshot(_snapshot({"shield": 250.0}), 1.0)
	check(view.shield_bubble != null and view.shield_bubble.visible, "有护盾时要显示护盾泡")
	view.set_snapshot(_snapshot({"shield": 0.0}), 1.0)
	check(not view.shield_bubble.visible, "护盾归零要隐藏护盾泡")
	view.free()

func test_red_and_blue_buff_auras_use_different_colours() -> void:
	var view := UnitVisual.new()
	view.setup("hero", "blue", "blade", "你", true, "blue")
	view.set_snapshot(_snapshot({"buff_red_timer": 12.0}), 1.0)
	check(view.buff_aura != null and view.buff_aura.visible, "红 BUFF 要显示光环")
	var red := (view.buff_aura.material_override as StandardMaterial3D).emission
	gt(red.r, red.b, "红 BUFF 光环偏红")
	view.set_snapshot(_snapshot({"buff_blue_timer": 12.0}), 1.0)
	var blue := (view.buff_aura.material_override as StandardMaterial3D).emission
	gt(blue.b, blue.r, "蓝 BUFF 光环偏蓝")
	view.set_snapshot(_snapshot(), 1.0)
	check(not view.buff_aura.visible, "BUFF 结束要隐藏光环")
	view.free()

func test_slow_ring_follows_slow_timer() -> void:
	var view := UnitVisual.new()
	view.setup("hero", "blue", "blade", "你", true, "blue")
	view.set_snapshot(_snapshot({"slow_timer": 1.5}), 1.0)
	check(view.slow_ring != null and view.slow_ring.visible, "减速时要显示冰环")
	view.set_snapshot(_snapshot(), 1.0)
	check(not view.slow_ring.visible, "减速结束要隐藏冰环")
	view.free()

func test_death_hides_all_status_fx_and_respawn_restores_state() -> void:
	var view := UnitVisual.new()
	view.setup("hero", "blue", "blade", "你", true, "blue")
	view.set_snapshot(_snapshot({
		"shield": 300.0, "buff_red_timer": 20.0, "slow_timer": 2.0,
	}), 1.0)
	check(view.shield_bubble.visible and view.buff_aura.visible and view.slow_ring.visible, "死亡前状态都在")
	var dead := _snapshot({"alive": false, "hp": 0.0})
	view.set_snapshot(dead, 1.0)
	check(not view.shield_bubble.visible, "死亡隐藏护盾泡")
	check(not view.buff_aura.visible, "死亡隐藏 BUFF 光环")
	check(not view.slow_ring.visible, "死亡隐藏减速环")
	view.set_snapshot(_snapshot({"shield": 300.0}), 1.0)
	check(view.shield_bubble.visible, "复活后护盾泡恢复显示")
	view.free()
