extends RefCounted

# 防御塔推进顺序：外塔 → 内塔 → 高地塔；任意一路高地塔倒下，基地才会暴露。
# 塔优先清兵，但敌方英雄在塔下攻击己方英雄时会被强制转火。

const MapLayout = preload("res://sim/map/map_layout.gd")

const EARLY_PROTECTION_TIME := 180.0
const EARLY_PROTECTION_SCALE := 0.5
const FORCED_AGGRO_WINDOW := 3.0

static func is_tower_vulnerable(tower: Dictionary, entities: Array) -> bool:
	var tier := str(tower.get("tier", "outer"))
	if tier == "outer" or tier == "":
		return true
	var required := "inner" if tier == "high" else "outer"
	var team := str(tower.get("team", ""))
	var lane := str(tower.get("lane", "mid"))
	for entity in entities:
		if str(entity.get("type", "")) != "tower":
			continue
		if str(entity.get("team", "")) != team or str(entity.get("lane", "")) != lane:
			continue
		if str(entity.get("tier", "")) != required:
			continue
		return not bool(entity.get("alive", true))
	return true

static func is_base_vulnerable(base: Dictionary, entities: Array) -> bool:
	var team := str(base.get("team", ""))
	var found := false
	for entity in entities:
		if str(entity.get("type", "")) != "tower":
			continue
		if str(entity.get("team", "")) != team or str(entity.get("tier", "")) != "high":
			continue
		found = true
		if bool(entity.get("alive", true)):
			return false
	return found

static func damage_scale(structure: Dictionary, time: float) -> float:
	if str(structure.get("type", "")) == "tower" and time < EARLY_PROTECTION_TIME:
		return EARLY_PROTECTION_SCALE
	return 1.0

static func select_target(structure: Dictionary, entities: Array, time: float) -> Dictionary:
	var team := str(structure.get("team", ""))
	var structure_pos := _pos(structure)
	var reach := float(structure.get("range", 9.0))
	var forced := _forced_aggro_target(structure, entities, time, structure_pos, reach)
	if not forced.is_empty():
		return forced
	var best_minion := {}
	var best_minion_distance := INF
	var best_hero := {}
	var best_hero_distance := INF
	for entity in entities:
		if not bool(entity.get("alive", true)):
			continue
		var entity_team := str(entity.get("team", ""))
		if entity_team == team or entity_team == "neutral":
			continue
		var distance := structure_pos.distance_to(_pos(entity))
		if distance > reach:
			continue
		match str(entity.get("type", "")):
			"minion":
				if distance < best_minion_distance:
					best_minion_distance = distance
					best_minion = entity
			"hero":
				if distance < best_hero_distance:
					best_hero_distance = distance
					best_hero = entity
	if not best_minion.is_empty():
		return best_minion
	return best_hero

# 己方英雄在塔下被谁打，塔就打谁；时间窗之外的旧仇恨不生效。
static func _forced_aggro_target(structure: Dictionary, entities: Array, time: float, structure_pos: Vector2, reach: float) -> Dictionary:
	var team := str(structure.get("team", ""))
	for ally in entities:
		if str(ally.get("type", "")) != "hero" or str(ally.get("team", "")) != team:
			continue
		if not bool(ally.get("alive", true)):
			continue
		if time - float(ally.get("last_hero_attacker_time", -999.0)) > FORCED_AGGRO_WINDOW:
			continue
		var attacker_id := int(ally.get("last_hero_attacker_id", -1))
		if attacker_id < 0:
			continue
		for attacker in entities:
			if int(attacker.get("id", -1)) != attacker_id:
				continue
			if str(attacker.get("type", "")) != "hero" or str(attacker.get("team", "")) == team:
				continue
			if not bool(attacker.get("alive", true)):
				continue
			if structure_pos.distance_to(_pos(attacker)) <= reach:
				return attacker
	return {}

static func _pos(entity: Dictionary) -> Vector2:
	var stored: Variant = entity.get("pos", null)
	if stored is Vector2:
		return stored
	return Vector2(float(entity.get("x", 0.0)), float(entity.get("y", 0.0)))
