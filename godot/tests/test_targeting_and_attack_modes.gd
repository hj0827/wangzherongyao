extends "res://tests/test_base.gd"

const TargetingSystem = preload("res://scripts/ui/targeting_system.gd")

func _entity(id: int, type: String, team: String, pos: Vector2, hp := 1000.0, alive := true) -> Dictionary:
	return {
		"id": id,
		"type": type,
		"team": team,
		"pos": pos,
		"hp": hp,
		"max_hp": 1000.0,
		"alive": alive,
		"attack_range": 6.5,
	}

func test_default_attack_prefers_hero_over_minion_and_tower() -> void:
	var hero := _entity(1, "hero", "blue", Vector2.ZERO)
	var enemy_tower := _entity(10, "tower", "red", Vector2(3.0, 0.0))
	var enemy_minion := _entity(20, "minion", "red", Vector2(4.0, 0.0))
	var enemy_hero := _entity(30, "hero", "red", Vector2(5.0, 0.0))
	var entities := [hero, enemy_tower, enemy_minion, enemy_hero]
	
	var target: Dictionary = TargetingSystem.resolve_attack_target(hero, entities, "default", -1, Vector2.ZERO)
	eq(int(target.get("id", -1)), 30, "默认模式下优先锁定敌方英雄")

func test_minion_button_forces_minion_priority() -> void:
	var hero := _entity(1, "hero", "blue", Vector2.ZERO)
	var enemy_tower := _entity(10, "tower", "red", Vector2(3.0, 0.0))
	var enemy_minion := _entity(20, "minion", "red", Vector2(4.0, 0.0))
	var enemy_hero := _entity(30, "hero", "red", Vector2(2.0, 0.0))
	var entities := [hero, enemy_tower, enemy_minion, enemy_hero]
	
	var target: Dictionary = TargetingSystem.resolve_attack_target(hero, entities, "minion", -1, Vector2.ZERO)
	eq(int(target.get("id", -1)), 20, "补刀键必须强制优先攻击小兵，哪怕敌方英雄贴脸")

func test_tower_button_forces_tower_priority() -> void:
	var hero := _entity(1, "hero", "blue", Vector2.ZERO)
	var enemy_tower := _entity(10, "tower", "red", Vector2(4.0, 0.0))
	var enemy_minion := _entity(20, "minion", "red", Vector2(2.0, 0.0))
	var enemy_hero := _entity(30, "hero", "red", Vector2(1.5, 0.0))
	var entities := [hero, enemy_tower, enemy_minion, enemy_hero]
	
	var target: Dictionary = TargetingSystem.resolve_attack_target(hero, entities, "tower", -1, Vector2.ZERO)
	eq(int(target.get("id", -1)), 10, "推塔键必须强制优先攻击防御塔")

func test_avatar_lock_overrides_distance_and_hits_specific_hero() -> void:
	var hero := _entity(1, "hero", "blue", Vector2.ZERO)
	var enemy_near := _entity(30, "hero", "red", Vector2(2.0, 0.0))
	var enemy_far := _entity(31, "hero", "red", Vector2(5.5, 0.0))
	var entities := [hero, enemy_near, enemy_far]
	
	# Locked on enemy_far (e.g. clicking enemy avatar)
	var target: Dictionary = TargetingSystem.resolve_attack_target(hero, entities, "default", 31, Vector2.ZERO)
	eq(int(target.get("id", -1)), 31, "头像锁定特定敌方英雄后，优先打击该锁定目标")

func test_avatar_lock_auto_releases_when_dead_or_out_of_range() -> void:
	var hero := _entity(1, "hero", "blue", Vector2.ZERO)
	var dead_enemy := _entity(31, "hero", "red", Vector2(4.0, 0.0), 0.0, false)
	var entities := [hero, dead_enemy]
	
	check(TargetingSystem.is_lock_valid(hero, 31, entities) == false, "死亡目标自动失效")
	
	var far_enemy := _entity(32, "hero", "red", Vector2(20.0, 0.0))
	entities = [hero, far_enemy]
	check(TargetingSystem.is_lock_valid(hero, 32, entities) == false, "脱离锁敌超距自动失效")

func test_wheel_targeting_picks_entity_closest_to_drag_direction() -> void:
	var hero := _entity(1, "hero", "blue", Vector2.ZERO)
	var enemy_up := _entity(10, "hero", "red", Vector2(0.0, -4.0))
	var enemy_right := _entity(11, "hero", "red", Vector2(4.0, 0.0))
	var entities := [hero, enemy_up, enemy_right]
	
	var drag_vec := Vector2(1.0, 0.1).normalized() # Aiming right
	var target: Dictionary = TargetingSystem.resolve_attack_target(hero, entities, "default", -1, drag_vec)
	eq(int(target.get("id", -1)), 11, "轮盘拖拽朝右侧时，精准选取右侧目标")
