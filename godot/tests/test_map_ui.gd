extends "res://tests/test_base.gd"

# 地图信息层契约：小地图/情报面板能识别草丛、营地与首领坑；
# HUD 展示首领计时、野区增益与回城引导；野怪有独立 3D 表现。

const MapIntel = preload("res://sim/map_intel.gd")
const MapLayout = preload("res://sim/map/map_layout.gd")
const GameHUD = preload("res://scripts/ui/game_hud.gd")
const UnitVisual = preload("res://scripts/game/unit_visual.gd")

func test_intel_recognizes_bushes_camps_and_objective_pits() -> void:
	eq(str(MapIntel.region_at(MapLayout.BUSHES[0].pos).kind), "bush", "草丛区域有独立类型")
	var camp_region := MapIntel.region_at(MapLayout.CAMPS[0].pos)
	eq(str(camp_region.kind), "camp", "野区营地有独立类型")
	check(str(camp_region.note).contains("BUFF") or str(camp_region.name).contains("野"), "营地说明提到增益或野区")
	var small_camp: Dictionary = MapLayout.CAMPS.filter(func(camp): return str(camp.get("buff", "")) == "")[0]
	var small_region := MapIntel.region_at(small_camp.pos)
	eq(str(small_region.kind), "camp", "小野点也是营地类型")
	check(not str(small_region.note).contains("BUFF"), "小野点不能被情报层误报成红/蓝BUFF")
	check(str(small_region.note).contains("经验"), "小野点说明只给经验")
	var pit_region := MapIntel.region_at(MapLayout.OBJECTIVE_PITS[0].pos)
	eq(str(pit_region.kind), "objective", "首领坑有独立类型")
	check(str(pit_region.name).contains(str(MapLayout.OBJECTIVE_PITS[0].name)), "首领坑名称正确")

func test_intel_labels_monsters() -> void:
	var report := MapIntel.inspect({
		"entities": [{
			"id": 1, "type": "monster", "team": "neutral", "x": 0.0, "y": 0.0,
			"hp": 900.0, "max_hp": 900.0, "alive": true, "monster_type": "wolf", "name": "霜狼",
		}],
	}, Vector2.ZERO, "p1", "blue")
	eq(int(report.total), 1, "野怪进入情报列表")
	eq(str(report.units[0].label), "野怪", "野怪使用类型标签")

func _hud_snapshot() -> Dictionary:
	return {
		"time": 30.0,
		"wave": 2,
		"ended": false,
		"winner": "",
		"objectives": {"spawn_timer": 80.0, "blue_buff": 25.0, "red_buff": 0.0},
		"scores": {"blue": {"kills": 1, "towers": 2}, "red": {"kills": 0, "towers": 0}},
		"entities": [{
			"id": 1, "type": "hero", "team": "blue", "owner_id": "p1", "name": "你",
			"hero_type": "blade", "level": 3, "hp": 800.0, "max_hp": 1000.0,
			"mp": 100.0, "max_mp": 200.0, "alive": true, "kills": 1, "deaths": 0,
			"skill_q_cd": 0.0, "skill_e_cd": 0.0, "recalling": true, "recall_timer": 2.4,
			"buff_blue_timer": 25.0, "buff_red_timer": 0.0,
			"x": 0.0, "y": 0.0, "facing_x": 0.0, "facing_y": 1.0,
		}],
	}

func test_hud_shows_objective_timer_and_local_buffs() -> void:
	var hud := GameHUD.new()
	hud.setup("p1", "blue", "blade", "你", false, false)
	hud._ready()
	hud.update_snapshot(_hud_snapshot())
	check(hud._objective_label.text.contains("暴君"), "小地图下方显示首领计时")
	check(hud._objective_label.text.contains("01:20"), "首领倒计时格式化成 mm:ss")
	check(hud._role_label.text.contains("蓝BUFF"), "英雄信息栏显示蓝增益剩余时间")
	check(hud._role_label.text.contains("回城"), "回城引导显示在英雄信息栏")
	hud.free()

func test_monster_visual_uses_dedicated_model() -> void:
	var view := UnitVisual.new()
	view.setup("monster", "neutral", "wolf", "霜狼", false)
	eq(str(view.kind), "monster", "野怪使用独立表现类型")
	eq(str(view.monster_type), "wolf", "野怪模型类型写入表现层")
	check(view.model_root != null, "野怪模型已实例化")
	check(view.bar_mesh != null, "野怪有血条")
	view.set_snapshot({
		"x": 1.0, "y": 2.0, "hp": 50.0, "max_hp": 100.0, "alive": true,
	})
	view.free()
