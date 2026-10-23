extends RefCounted

# 高地双子塔与水晶护盾。
# 任意一路高地塔倒下后双子塔解锁；双塔存活期间水晶带一层可再生护盾，
# 每失去一座双子塔护盾上限减半，双塔全毁时护盾立即破碎。

const TowerRules = preload("res://sim/map/tower_rules.gd")

const SHIELD_PER_GUARD := 1200.0
const SHIELD_REGEN_DELAY := 6.0
const SHIELD_REGEN_RATE := 320.0

static func alive_guards(team: String, entities: Array) -> int:
	var total := 0
	for entity in entities:
		if str(entity.get("type", "")) != "guard":
			continue
		if str(entity.get("team", "")) != team:
			continue
		if bool(entity.get("alive", false)):
			total += 1
	return total

static func is_guard_vulnerable(guard: Dictionary, entities: Array) -> bool:
	var team := str(guard.get("team", ""))
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

static func shield_max_for(team: String, entities: Array) -> float:
	return float(alive_guards(team, entities)) * SHIELD_PER_GUARD

# 每 tick 同步护盾上限、暴露瞬间充满、脱战延迟后回复。
static func tick(state: Dictionary, delta: float) -> void:
	var entities: Array = state.get("entities", [])
	for base in entities:
		if not (base is Dictionary):
			continue
		if str(base.get("type", "")) != "base":
			continue
		var shield_max := shield_max_for(str(base.get("team", "")), entities)
		base["guards_alive"] = alive_guards(str(base.get("team", "")), entities)
		base["shield_max"] = shield_max
		if not bool(base.get("alive", false)):
			base["shield"] = 0.0
			continue
		if not TowerRules.is_base_vulnerable(base, entities):
			base["exposed"] = false
			base["shield"] = 0.0
			continue
		if not bool(base.get("exposed", false)):
			base["exposed"] = true
			base["shield"] = shield_max
			base["last_shield_hit_time"] = -999.0
			continue
		var shield := minf(float(base.get("shield", 0.0)), shield_max)
		if shield_max <= 0.0:
			base["shield"] = 0.0
			continue
		var since_hit := float(state.get("time", 0.0)) - float(base.get("last_shield_hit_time", -999.0))
		if shield < shield_max and since_hit >= SHIELD_REGEN_DELAY:
			shield = minf(shield_max, shield + SHIELD_REGEN_RATE * delta)
		base["shield"] = shield

# 双子塔倒下时立刻收缩护盾上限，而不是等下一 tick —— 玩家看到塔碎的那一帧
# 护盾就该跟着变薄，否则会出现「塔没了但护盾还满着」的错位反馈。
static func on_guard_destroyed(state: Dictionary, guard: Dictionary) -> Dictionary:
	var team := str(guard.get("team", ""))
	var entities: Array = state.get("entities", [])
	var alive := alive_guards(team, entities)
	var shield_max := float(alive) * SHIELD_PER_GUARD
	var broken := alive <= 0
	for base in entities:
		if not (base is Dictionary):
			continue
		if str(base.get("type", "")) != "base" or str(base.get("team", "")) != team:
			continue
		base["guards_alive"] = alive
		base["shield_max"] = shield_max
		base["shield"] = 0.0 if broken else minf(float(base.get("shield", 0.0)), shield_max)
	return {"guards_alive": alive, "shield_max": shield_max, "broken": broken}
