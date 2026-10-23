extends "res://tests/test_base.gd"

# 防御塔推进规则契约：外塔 → 内塔 → 高地塔依次解锁，高地塔倒下后基地暴露；
# 塔优先打小兵，但敌方英雄在塔下攻击友军时会被强制转火。

const TowerRules = preload("res://sim/map/tower_rules.gd")

func _tower(id: int, team: String, lane: String, tier: String, pos := Vector2.ZERO, alive := true) -> Dictionary:
	return {
		"id": id,
		"type": "tower",
		"team": team,
		"lane": lane,
		"tier": tier,
		"pos": pos,
		"radius": 2.0,
		"range": 8.0,
		"alive": alive,
		"hp": 100.0,
		"max_hp": 100.0,
	}

func _base(id: int, team: String) -> Dictionary:
	return {
		"id": id,
		"type": "base",
		"team": team,
		"pos": Vector2.ZERO,
		"radius": 7.0,
		"range": 9.0,
		"alive": true,
		"hp": 100.0,
		"max_hp": 100.0,
	}

func test_tower_order_outer_then_inner_then_high() -> void:
	var outer := _tower(1, "red", "mid", "outer")
	var inner := _tower(2, "red", "mid", "inner")
	var high := _tower(3, "red", "mid", "high")
	var entities := [outer, inner, high]
	check(TowerRules.is_tower_vulnerable(outer, entities), "外塔从开局起可被攻击")
	check(not TowerRules.is_tower_vulnerable(inner, entities), "外塔未倒时内塔无敌")
	check(not TowerRules.is_tower_vulnerable(high, entities), "外塔未倒时高地塔无敌")
	outer.alive = false
	check(TowerRules.is_tower_vulnerable(inner, entities), "外塔倒下后内塔解锁")
	check(not TowerRules.is_tower_vulnerable(high, entities), "内塔未倒时高地塔仍无敌")
	inner.alive = false
	check(TowerRules.is_tower_vulnerable(high, entities), "内塔倒下后高地塔解锁")

func test_tower_order_is_scoped_to_one_lane() -> void:
	var top_outer := _tower(1, "red", "top", "outer")
	var mid_inner := _tower(2, "red", "mid", "inner")
	var entities := [top_outer, mid_inner]
	check(TowerRules.is_tower_vulnerable(mid_inner, entities), "别的路的外塔不保护本路内塔")
	check(not TowerRules.is_tower_vulnerable(mid_inner, [_tower(3, "red", "mid", "outer")]), "本路外塔未倒时内塔受保护")

func test_base_is_locked_until_a_high_tower_falls() -> void:
	var base := _base(9, "red")
	var outer := _tower(1, "red", "mid", "outer")
	var inner := _tower(2, "red", "mid", "inner")
	var high := _tower(3, "red", "mid", "high")
	var entities := [base, outer, inner, high]
	check(not TowerRules.is_base_vulnerable(base, entities), "高地塔全在时基地不可攻击")
	outer.alive = false
	inner.alive = false
	check(not TowerRules.is_base_vulnerable(base, entities), "高地塔仍在时基地仍受保护")
	high.alive = false
	check(TowerRules.is_base_vulnerable(base, entities), "任意一路高地塔倒下后基地暴露")

func test_tower_prefers_minions_but_switches_to_diving_hero() -> void:
	var tower := _tower(10, "blue", "mid", "outer", Vector2.ZERO)
	var own_hero := {
		"id": 1, "type": "hero", "team": "blue", "pos": Vector2(2.0, 0.0), "alive": true,
		"last_hero_attacker_id": 3, "last_hero_attacker_time": 99.0,
	}
	var enemy_minion := {"id": 2, "type": "minion", "team": "red", "pos": Vector2(3.0, 0.0), "alive": true}
	var diving_hero := {"id": 3, "type": "hero", "team": "red", "pos": Vector2(4.0, 0.0), "alive": true}
	var entities := [tower, own_hero, enemy_minion, diving_hero]
	eq(int(TowerRules.select_target(tower, entities, 100.0).id), 3, "英雄在塔下攻击友军时，防御塔必须强制转火")
	own_hero["last_hero_attacker_time"] = -999.0
	eq(int(TowerRules.select_target(tower, entities, 100.0).id), 2, "没有嘲讽事件时优先清小兵")
	diving_hero["pos"] = Vector2(20.0, 0.0)
	eq(int(TowerRules.select_target(tower, entities, 100.0).id), 2, "范围外的英雄不能吸引防御塔")

func test_early_protection_halves_tower_damage() -> void:
	var tower := _tower(1, "red", "mid", "outer")
	near(TowerRules.damage_scale(tower, 30.0), 0.5, 0.001, "开局三分钟内防御塔有 50% 减伤")
	near(TowerRules.damage_scale(tower, 200.0), 1.0, 0.001, "保护期结束后伤害正常")
	near(TowerRules.damage_scale(_base(2, "red"), 30.0), 1.0, 0.001, "基地不受防御塔保护期影响")
