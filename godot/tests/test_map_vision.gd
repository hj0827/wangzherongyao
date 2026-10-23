extends "res://tests/test_base.gd"

# 视野与草丛契约：远距离不可见、草丛隐藏、贴近显形、攻击显形、墙体遮挡。
# 快照过滤是「全图透视」问题的第一道防线，客机只应收到自己能看到的单位。

const Vision = preload("res://sim/map/vision.gd")
const MapLayout = preload("res://sim/map/map_layout.gd")
const MapData = preload("res://sim/map_data.gd")
const Collision = preload("res://sim/map/collision.gd")

func _hero(id: int, team: String, pos: Vector2, extra := {}) -> Dictionary:
	var data := {
		"id": id,
		"type": "hero",
		"team": team,
		"x": pos.x,
		"y": pos.y,
		"radius": 0.55,
		"alive": true,
		"hp": 1000.0,
		"max_hp": 1000.0,
		"revealed_timer": 0.0,
	}
	for key in extra:
		data[key] = extra[key]
	return data

func test_nearby_enemy_is_visible_and_far_enemy_is_not() -> void:
	var entities := [
		_hero(1, "blue", Vector2.ZERO),
		_hero(2, "red", Vector2(6.0, 0.0)),
		_hero(3, "red", Vector2(50.0, 50.0)),
	]
	check(Vision.is_visible(entities[1], "blue", entities), "视野半径内的敌人必须可见")
	check(not Vision.is_visible(entities[2], "blue", entities), "远处敌人不能全图可见")

func test_bush_conceals_enemy_until_someone_gets_close() -> void:
	var bush: Dictionary = MapLayout.BUSHES[0]
	var entities := [
		_hero(1, "blue", bush.pos + Vector2(0.0, -6.0)),
		_hero(2, "red", bush.pos),
	]
	check(not Vision.is_visible(entities[1], "blue", entities), "草丛里的敌人不能被远处英雄看到")
	entities.append(_hero(3, "blue", bush.pos + Vector2(1.2, 0.0)))
	check(Vision.is_visible(entities[1], "blue", entities), "友军贴近草丛必须显形")

func test_attacking_reveals_bush_camper_for_a_short_time() -> void:
	var bush: Dictionary = MapLayout.BUSHES[0]
	var entities := [
		_hero(1, "blue", bush.pos + Vector2(0.0, -6.0)),
		_hero(2, "red", bush.pos, {"revealed_timer": 1.2}),
	]
	check(Vision.is_visible(entities[1], "blue", entities), "刚攻击过的敌人必须短暂暴露")

func test_walls_block_vision() -> void:
	var wall: Dictionary = MapLayout.WALLS[0]
	var segment: Vector2 = wall.b - wall.a
	var normal := Vector2(-segment.y, segment.x).normalized()
	var mid: Vector2 = (wall.a + wall.b) * 0.5
	var viewer_pos: Vector2 = mid - normal * 3.5
	var target_pos: Vector2 = mid + normal * 3.5
	check(Collision.segment_blocked(viewer_pos, target_pos), "测试点必须横跨墙体")
	var entities := [
		_hero(1, "blue", viewer_pos),
		_hero(2, "red", target_pos),
	]
	check(not Vision.is_visible(entities[1], "blue", entities), "隔墙的敌人不应可见")

func test_filter_snapshot_keeps_allies_and_only_visible_enemies() -> void:
	var snapshot := {
		"time": 8.0,
		"entities": [
			_hero(1, "blue", Vector2.ZERO),
			_hero(2, "blue", Vector2(30.0, 30.0)),
			_hero(3, "red", Vector2(5.0, 0.0)),
			_hero(4, "red", Vector2(-50.0, 50.0)),
		],
		"scores": {"blue": {"kills": 1, "towers": 0}, "red": {"kills": 0, "towers": 0}},
	}
	var filtered: Dictionary = Vision.filter_snapshot(snapshot, "blue")
	var ids: Array = filtered.entities.map(func(entity): return int(entity.id))
	check(ids.has(1) and ids.has(2), "友军无论多远都必须保留")
	check(ids.has(3), "视野内敌人必须保留")
	check(not ids.has(4), "视野外敌人必须剔除")
	near(float(filtered.time), 8.0, 0.001, "过滤快照保留时间戳")
	eq(snapshot.entities.size(), 4, "过滤不能修改原始快照")

func test_filter_snapshot_keeps_revealed_enemy_in_fog() -> void:
	var bush: Dictionary = MapLayout.BUSHES[0]
	var hidden_hero := _hero(2, "red", bush.pos, {"revealed_timer": 0.8})
	var snapshot := {
		"entities": [
			_hero(1, "blue", bush.pos + Vector2(0.0, -6.0)),
			hidden_hero,
		],
	}
	var filtered: Dictionary = Vision.filter_snapshot(snapshot, "blue")
	eq(filtered.entities.size(), 2, "刚交过手的草丛敌人短暂可见")
	hidden_hero["revealed_timer"] = 0.0
	var hidden: Dictionary = Vision.filter_snapshot(snapshot, "blue")
	eq(hidden.entities.size(), 1, "暴露时间结束后草丛重新隐藏该敌人")

func test_filter_events_hides_fog_combat_but_keeps_own_and_global_events() -> void:
	var snapshot := {
		"time": 12.0,
		"entities": [
			_hero(1, "blue", Vector2.ZERO),
			_hero(2, "red", Vector2(5.0, 0.0)),
			_hero(3, "red", Vector2(50.0, 50.0)),
		],
		"events": [
			{"type": "attack", "hero": 2, "x": 5.0, "y": 0.0},
			{"type": "attack", "hero": 3, "x": 50.0, "y": 50.0},
			{"type": "purchase", "hero": 3, "buy_item": "iron_sword"},
			{"type": "purchase", "hero": 1, "buy_item": "boots"},
			{"type": "wave", "wave": 3},
			{"type": "skill_cast", "caster_id": 3, "pos": [50.0, 50.0]},
		],
	}
	var filtered: Dictionary = Vision.filter_snapshot(snapshot, "blue")
	var types: Array = filtered.events.map(func(event): return str(event.type))
	eq(types.size(), 3, "只下发己方、可见与全局事件")
	eq(types.count("attack"), 1, "雾中攻击被剔除，视野内攻击保留")
	check(types.has("wave"), "全局兵线播报保留")
	eq(filtered.events[1].hero, 1, "保留的购买事件来自己方")
	eq(filtered.events[1].type, "purchase", "己方购买保留")
	eq(snapshot.events.size(), 6, "事件过滤不能修改原始快照")
