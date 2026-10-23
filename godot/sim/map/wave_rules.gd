extends RefCounted

# 兵线组成与成长：近战 / 远程 / 每三波炮车；高地塔倒下后该路改出超级兵。
# 统计值随波次增长，让后期兵线对建筑有真实压力。

const MapLayout = preload("res://sim/map/map_layout.gd")

const WAVE_SIZE := 3

static func composition(wave_number: int, super_enabled: bool) -> Array:
	var units := ["melee", "melee", "ranged"]
	if wave_number > 0 and wave_number % 3 == 0:
		units[0] = "cannon"
	if super_enabled:
		var replaced := false
		for index in units.size():
			if units[index] == "melee":
				units[index] = "super"
				replaced = true
				break
		if not replaced:
			units[0] = "super"
	return units

static func stats(minion_type: String, wave_number: int) -> Dictionary:
	var wave := maxi(1, wave_number)
	var data := {
		"minion_type": "melee",
		"hp": 420.0 + float(wave) * 38.0,
		"max_hp": 420.0 + float(wave) * 38.0,
		"attack_damage": 34.0 + float(wave) * 2.4,
		"attack_range": 1.6,
		"attack_interval": 1.1,
		"move_speed": 4.4,
		"radius": 0.5,
	}
	match minion_type:
		"ranged":
			data.minion_type = "ranged"
			data.hp = 300.0 + float(wave) * 26.0
			data.max_hp = data.hp
			data.attack_damage = 40.0 + float(wave) * 2.6
			data.attack_range = 5.2
			data.attack_interval = 1.2
			data.move_speed = 4.2
			data.radius = 0.45
		"cannon":
			data.minion_type = "cannon"
			data.hp = 780.0 + float(wave) * 58.0
			data.max_hp = data.hp
			data.attack_damage = 58.0 + float(wave) * 3.2
			data.attack_range = 6.0
			data.attack_interval = 1.5
			data.move_speed = 4.0
			data.radius = 0.7
		"super":
			data.minion_type = "super"
			data.hp = 1450.0 + float(wave) * 90.0
			data.max_hp = data.hp
			data.attack_damage = 90.0 + float(wave) * 4.5
			data.attack_range = 2.0
			data.attack_interval = 1.2
			data.move_speed = 4.2
			data.radius = 0.8
	return data

# team 出超级兵的条件：敌方该路高地塔已经倒下。
static func super_unlocked(lane: String, team: String, entities: Array) -> bool:
	var enemy := "red" if team == "blue" else "blue"
	for entity in entities:
		if str(entity.get("type", "")) != "tower":
			continue
		if str(entity.get("team", "")) != enemy or str(entity.get("lane", "")) != lane:
			continue
		if str(entity.get("tier", "")) == "high":
			return not bool(entity.get("alive", true))
	return false
