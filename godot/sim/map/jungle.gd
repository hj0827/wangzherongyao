extends RefCounted

# 野区：四座镜像营地，击杀后获得红/蓝增益，70 秒重新刷新。
# 蓝增益缩短技能冷却，红增益提升普攻伤害。

const MapLayout = preload("res://sim/map/map_layout.gd")

const RESPAWN_TIME := 70.0
const BUFF_DURATION := 60.0
const BLUE_COOLDOWN_SCALE := 0.8
const RED_DAMAGE_SCALE := 1.12

static var CAMPS: Array = MapLayout.CAMPS.duplicate(true)

static func monster_stats(camp: Dictionary) -> Dictionary:
	var pos: Vector2 = camp.get("pos", Vector2.ZERO)
	var is_red := str(camp.get("buff", "")) == "red"
	var hp := 780.0 if is_red else 720.0
	var damage := 62.0 if is_red else 55.0
	return {
		"type": "monster",
		"team": "neutral",
		"monster_type": str(camp.get("monster_type", "wolf")),
		"name": str(camp.get("name", "野怪")),
		"camp_id": str(camp.get("id", "")),
		"buff_type": str(camp.get("buff", "")),
		"pos": pos,
		"x": pos.x,
		"y": pos.y,
		"radius": 1.0,
		"hp": hp,
		"max_hp": hp,
		"attack_damage": damage,
		"attack_range": 1.8,
		"attack_interval": 1.4,
		"leash_range": 11.0,
		"move_speed": 3.4,
		"respawn_time": RESPAWN_TIME,
		"alive": true,
	}

static func apply_buff(hero: Dictionary, buff_type: String) -> bool:
	match buff_type:
		"blue":
			hero["buff_blue_timer"] = BUFF_DURATION
			return true
		"red":
			hero["buff_red_timer"] = BUFF_DURATION
			return true
	return false

static func tick_buffs(hero: Dictionary, delta: float) -> void:
	hero["buff_blue_timer"] = maxf(0.0, float(hero.get("buff_blue_timer", 0.0)) - delta)
	hero["buff_red_timer"] = maxf(0.0, float(hero.get("buff_red_timer", 0.0)) - delta)

static func cooldown_scale(hero: Dictionary) -> float:
	if float(hero.get("buff_blue_timer", 0.0)) > 0.0:
		return BLUE_COOLDOWN_SCALE
	return 1.0

static func damage_scale(hero: Dictionary) -> float:
	if float(hero.get("buff_red_timer", 0.0)) > 0.0:
		return RED_DAMAGE_SCALE
	return 1.0
