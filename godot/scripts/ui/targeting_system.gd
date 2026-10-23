extends RefCounted

# UI 侧的锁敌入口。真正的裁决在 sim/targeting_rules.gd，模拟与界面共用一套规则。
const TargetingRules = preload("res://sim/targeting_rules.gd")

const MAX_LOCK_DISTANCE := TargetingRules.MAX_LOCK_DISTANCE

static func is_lock_valid(hero: Dictionary, locked_id: int, entities: Array) -> bool:
	return TargetingRules.is_lock_valid(hero, locked_id, entities)

static func resolve_attack_target(
	hero: Dictionary,
	entities: Array,
	attack_mode: String,
	locked_target_id: int,
	drag_direction: Vector2
) -> Dictionary:
	return TargetingRules.resolve_attack_target(hero, entities, attack_mode, locked_target_id, drag_direction)
