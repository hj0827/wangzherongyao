extends "res://tests/test_base.gd"

# 兵线规则契约：近战 / 远程 / 炮车兵种组合、炮车节奏、超级兵解锁条件与成长曲线。
# 让兵线不只是「三个一样的小人」，而是能配合推塔节奏的波次。

const WaveRules = preload("res://sim/map/wave_rules.gd")

func _tower(id: int, team: String, lane: String, tier: String, alive := true) -> Dictionary:
	return {"id": id, "type": "tower", "team": team, "lane": lane, "tier": tier, "alive": alive}

func test_normal_wave_has_melee_and_ranged() -> void:
	var wave: Array = WaveRules.composition(1, false)
	eq(wave.size(), 3, "普通波次三名小兵")
	eq(wave.count("ranged"), 1, "每波一名远程兵")
	eq(wave.count("melee"), 2, "其余为近战兵")
	check(not wave.has("cannon"), "第一波没有炮车")

func test_every_third_wave_includes_cannon() -> void:
	for wave_number in [3, 6, 9]:
		var wave: Array = WaveRules.composition(wave_number, false)
		check(wave.has("cannon"), "第 %d 波必须有炮车" % wave_number)
		eq(wave.size(), 3, "炮车替换一名近战兵，波次人数不变")

func test_super_minion_replaces_melee_when_high_tower_falls() -> void:
	var wave: Array = WaveRules.composition(5, true)
	check(wave.has("super"), "高地塔倒下后该路出超级兵")
	eq(wave.count("melee"), 1, "超级兵占用一个近战位")
	eq(wave.size(), 3, "波次人数保持稳定")

func test_minion_stats_scale_with_wave_and_role() -> void:
	var melee: Dictionary = WaveRules.stats("melee", 1)
	var melee_late: Dictionary = WaveRules.stats("melee", 10)
	var ranged: Dictionary = WaveRules.stats("ranged", 1)
	var cannon: Dictionary = WaveRules.stats("cannon", 1)
	var super_minion: Dictionary = WaveRules.stats("super", 1)
	gt(float(melee_late.hp), float(melee.hp), "后期小兵更肉")
	gt(float(melee_late.attack_damage), float(melee.attack_damage), "后期小兵伤害更高")
	gt(float(ranged.attack_range), float(melee.attack_range), "远程兵射程更远")
	gt(float(cannon.hp), float(melee.hp), "炮车比近战兵更肉")
	gt(float(super_minion.hp), float(cannon.hp), "超级兵是波次里最肉的单位")
	eq(str(melee.minion_type), "melee", "属性表带兵种")

func test_super_unlock_is_per_lane_and_team() -> void:
	var entities := [
		_tower(1, "red", "mid", "outer"),
		_tower(2, "red", "mid", "inner"),
		_tower(3, "red", "mid", "high"),
		_tower(4, "red", "top", "high"),
		_tower(5, "blue", "mid", "high"),
	]
	check(not WaveRules.super_unlocked("mid", "blue", entities), "红方中路高地塔未倒时蓝方不出超级兵")
	entities[2].alive = false
	check(WaveRules.super_unlocked("mid", "blue", entities), "红方中路高地塔倒下后蓝方中路出超级兵")
	check(not WaveRules.super_unlocked("bottom", "blue", entities), "其他路不受影响")
	check(not WaveRules.super_unlocked("mid", "red", entities), "蓝方没有高地塔倒下，红方不出超级兵")
