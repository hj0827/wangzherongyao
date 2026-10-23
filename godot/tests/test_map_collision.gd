extends "res://tests/test_base.gd"

# 地形碰撞契约：墙体阻挡、贴墙滑行、视线遮挡、边界与脱困。
# 模拟层用同一套 API，英雄/小兵/机器人不会穿墙，也不会被墙卡死。

const Collision = preload("res://sim/map/collision.gd")
const MapLayout = preload("res://sim/map/map_layout.gd")
const MapData = preload("res://sim/map_data.gd")

func _wall_mid_and_normal(wall: Dictionary) -> Array:
	var mid: Vector2 = (wall.a + wall.b) * 0.5
	var segment: Vector2 = wall.b - wall.a
	var normal := Vector2(-segment.y, segment.x).normalized()
	return [mid, normal]

func test_circle_cannot_stand_inside_a_wall() -> void:
	var data := _wall_mid_and_normal(MapLayout.WALLS[0])
	var mid: Vector2 = data[0]
	var normal: Vector2 = data[1]
	check(Collision.is_blocked(mid, 0.55), "墙体中心必须判定为阻挡")
	var resolved: Vector2 = Collision.resolve_circle(mid, 0.55)
	check(not Collision.is_blocked(resolved, 0.55), "解算后必须脱离墙体")
	gt(absf((resolved - mid).dot(normal)), MapLayout.WALL_THICKNESS * 0.5, "必须被推到墙皮之外")
	check(absf(resolved.x) <= MapData.BOUNDS and absf(resolved.y) <= MapData.BOUNDS, "解算不能把人推到地图外")

func test_moving_into_wall_slides_along_it() -> void:
	var data := _wall_mid_and_normal(MapLayout.WALLS[0])
	var mid: Vector2 = data[0]
	var normal: Vector2 = data[1]
	var tangent := Vector2(-normal.y, normal.x)
	var start: Vector2 = mid - normal * 3.0 - tangent * 2.0
	var goal: Vector2 = mid + normal * 3.0 + tangent * 2.0
	var moved: Vector2 = Collision.move(start, goal, 0.55)
	check(not Collision.is_blocked(moved, 0.55), "移动结果不能卡在墙里")
	lt((moved - mid).dot(normal), 0.0, "不能穿到墙的另一侧")
	gt((moved - start).dot(tangent), 1.0, "撞击墙体时应保留切向位移，形成贴墙滑行")

func test_wall_blocks_line_of_sight_but_not_parallel_sight() -> void:
	var data := _wall_mid_and_normal(MapLayout.WALLS[0])
	var mid: Vector2 = data[0]
	var normal: Vector2 = data[1]
	var tangent := Vector2(-normal.y, normal.x)
	var across_a: Vector2 = mid - normal * 4.0
	var across_b: Vector2 = mid + normal * 4.0
	check(Collision.segment_blocked(across_a, across_b), "横穿墙体必须遮挡视线")
	var side_a: Vector2 = mid + normal * 3.0 - tangent * 6.0
	var side_b: Vector2 = mid + normal * 3.0 + tangent * 6.0
	check(not Collision.segment_blocked(side_a, side_b), "沿墙同侧不应被遮挡")

func test_nearest_free_finds_space_next_to_wall() -> void:
	var data := _wall_mid_and_normal(MapLayout.WALLS[0])
	var mid: Vector2 = data[0]
	var free_point: Vector2 = Collision.nearest_free(mid, 0.55)
	check(not Collision.is_blocked(free_point, 0.55), "nearest_free 必须返回可站立点")
	lt(free_point.distance_to(mid), 6.0, "脱困点不能离目标太远")

func test_map_bounds_are_shared_with_simulation() -> void:
	var outside := Vector2(MapData.BOUNDS + 20.0, -MapData.BOUNDS - 20.0)
	var resolved: Vector2 = Collision.resolve_circle(outside, 0.55)
	lt(absf(resolved.x), MapData.BOUNDS, "x 必须收进地图边界")
	lt(absf(resolved.y), MapData.BOUNDS, "y 必须收进地图边界")
