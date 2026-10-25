extends "res://tests/test_base.gd"

# 野区墙体的回归守卫（2026-10-25）。
#
# 起因：地图上只有 4 段孤立的短墙，野区是「一片空地 + 几块石头」，
# 玩家读不出「这里能走、那里是石壁」，也不像 MOBA 的野区地形。
# 需求是「参考王者荣耀给地图加墙体」。
#
# 墙是**有碰撞的**（collision 直接读 MapLayout.WALLS），所以加墙最大的风险
# 不是好看不好看，而是把地图切开：小兵沿折线走、并不寻路，野怪追人也是直线逼近，
# 一道横在通道上的墙会让它们贴墙抖动、或者直接把某块野区封死。
# 因此这里的重点是「加了墙以后地图仍然处处走得通」。
#
# 契约：
# 1. 每条墙都必须有关于 y = -x 的镜像孪生（上下路对称）。
# 2. 墙体不能压住三条兵线的路面（小兵不寻路，被墙挡住就卡死）。
# 3. 墙体不能盖住草丛 / 野区营地 / 首领坑 / 传送阵。
# 4. 从蓝方泉水出发，红方泉水、四个营地、两个首领坑、两座传送阵全部可达。
# 5. 墙体要有分量：段数够多、单段不能长到把野区拦腰截断。

const MapData = preload("res://sim/map_data.gd")
const MapLayout = preload("res://sim/map/map_layout.gd")
const Collision = preload("res://sim/map/collision.gd")
const Arena = preload("res://scripts/game/arena.gd")

const HERO_RADIUS := 0.55
const EPS := 0.01
# 玩家实际能站的极限，与 collision.clamp_bounds 同源。
const WALK_LIMIT := MapData.BOUNDS - HERO_RADIUS - MapData.CAMERA_WALL_MARGIN

func _wall_half() -> float:
	return MapLayout.WALL_THICKNESS * 0.5

# 沿墙段均匀取 9 个点：只看端点会漏掉「两端安全、中间正好压住营地」的情况。
func _wall_samples(wall: Dictionary, count := 9) -> Array:
	var points: Array = []
	for index in count:
		points.append((wall.a as Vector2).lerp(wall.b, float(index) / float(count - 1)))
	return points

func test_every_wall_has_a_mirror_twin_across_the_river_axis() -> void:
	# 已有 test_map_layout 只校验了 a 点的镜像；这里把两端一起校验，
	# 避免「起点镜像上了、方向却是歪的」这种半对状态。
	var keys := {}
	for wall in MapLayout.WALLS:
		keys["%s|%s" % [_key(wall.a), _key(wall.b)]] = true
	for wall in MapLayout.WALLS:
		var a: Vector2 = MapLayout.mirror(wall.a)
		var b: Vector2 = MapLayout.mirror(wall.b)
		var straight: bool = keys.has("%s|%s" % [_key(a), _key(b)])
		var swapped: bool = keys.has("%s|%s" % [_key(b), _key(a)])
		check(straight or swapped, "墙体缺少关于 y=-x 的镜像孪生：%s" % str(wall.id))

func _key(point: Vector2) -> String:
	return "%.2f_%.2f" % [point.x, point.y]

func test_walls_never_sit_on_a_minion_lane() -> void:
	# 小兵沿折线航点直走 + 滑墙，不寻路。墙一旦压进路面就是「小兵永远卡在那里」。
	for wall in MapLayout.WALLS:
		for point in _wall_samples(wall):
			var distance: float = MapLayout.distance_to_lanes(point)
			gt(
				distance,
				MapData.LANE_HALF_WIDTH + _wall_half() + 0.9,
				"墙体压住了兵线：%s（离路中心 %.2f 米）" % [str(wall.id), distance]
			)

func test_walls_leave_room_for_bushes_camps_pits_and_teleports() -> void:
	# 草丛只要求「墙表面不进入草丛半径」—— 地形本来就允许草贴着石壁长。
	# 营地 / 首领坑 / 传送阵多留半个身位，它们是要站进去打的场地。
	for wall in MapLayout.WALLS:
		for point in _wall_samples(wall):
			for bush in MapLayout.BUSHES:
				gt(
					point.distance_to(bush.pos),
					float(bush.radius) + _wall_half(),
					"墙体盖住了草丛：%s / %s" % [str(wall.id), str(bush.id)]
				)
			for camp in MapLayout.CAMPS:
				gt(
					point.distance_to(camp.pos),
					float(camp.radius) + _wall_half() + 0.5,
					"墙体盖住了野区营地：%s / %s" % [str(wall.id), str(camp.id)]
				)
			for pit in MapLayout.OBJECTIVE_PITS:
				gt(
					point.distance_to(pit.pos),
					float(pit.radius) + _wall_half() + 0.5,
					"墙体盖住了首领坑：%s / %s" % [str(wall.id), str(pit.id)]
				)
			for pad in MapLayout.TELEPORT_PADS:
				gt(
					point.distance_to(pad.pos),
					3.0 + _wall_half(),
					"墙体盖住了传送阵：%s / %s" % [str(wall.id), str(pad.id)]
				)

func test_the_whole_map_stays_connected_after_the_walls() -> void:
	# 从蓝方泉水做一次网格 BFS。目标点全部要能走到 —— 少一个就说明墙把这块封死了。
	var step := 1.0
	var cells := int(ceil(WALK_LIMIT * 2.0 / step)) + 1
	var start := _cell_index(MapData.BLUE_BASE, step, cells)
	check(not Collision.is_blocked(MapData.BLUE_BASE, HERO_RADIUS), "出生点自己不该被墙挡住")

	var visited := {}
	visited[start] = true
	var queue: Array[int] = [start]
	var head := 0
	while head < queue.size():
		var index: int = queue[head]
		head += 1
		var column: int = index % cells
		var row: int = index / cells
		for offset in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var next_column: int = column + offset.x
			var next_row: int = row + offset.y
			if next_column < 0 or next_row < 0 or next_column >= cells or next_row >= cells:
				continue
			var next_index: int = next_row * cells + next_column
			if visited.has(next_index):
				continue
			var point := _cell_point(next_column, next_row, step)
			if Collision.is_blocked(point, HERO_RADIUS):
				continue
			visited[next_index] = true
			queue.append(next_index)

	# 连通分量必须铺满绝大部分可走区域，不能只是个「大房间」。
	var walkable := 0
	for row in cells:
		for column in cells:
			if not Collision.is_blocked(_cell_point(column, row, step), HERO_RADIUS):
				walkable += 1
	var ratio := float(visited.size()) / float(maxi(walkable, 1))
	gt(ratio, 0.97, "可走区域被墙切碎了：最大连通块只占 %.1f%%" % (ratio * 100.0))

	var targets: Array = [
		{"name": "红方泉水", "pos": MapData.RED_BASE},
	]
	for camp in MapLayout.CAMPS:
		targets.append({"name": "营地 %s" % str(camp.id), "pos": camp.pos})
	for pit in MapLayout.OBJECTIVE_PITS:
		targets.append({"name": "首领坑 %s" % str(pit.id), "pos": pit.pos})
	for pad in MapLayout.TELEPORT_PADS:
		targets.append({"name": "传送阵 %s" % str(pad.id), "pos": pad.pos})
	for lane in MapData.LANE_ORDER:
		var path: Array = MapData.lane_path(str(lane))
		for index in path.size():
			targets.append({"name": "%s 航点 %d" % [lane, index], "pos": path[index]})
	for target in targets:
		var pos: Vector2 = target.pos
		var hit := false
		# 目标点本身可能贴着墙（判定半径 0.55），所以允许 2 米内任意一格到达。
		for radius_cell in [Vector2i.ZERO, Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var probe: Vector2 = Collision.clamp_bounds(pos + Vector2(radius_cell) * 1.0, HERO_RADIUS)
			if visited.has(_cell_index(probe, step, cells)):
				hit = true
				break
		check(hit, "加了墙以后走不到 %s（%.1f, %.1f）" % [str(target.name), pos.x, pos.y])

func _cell_point(column: int, row: int, step: float) -> Vector2:
	return Vector2(-WALK_LIMIT + float(column) * step, -WALK_LIMIT + float(row) * step)

func _cell_index(point: Vector2, step: float, cells: int) -> int:
	var column := clampi(int(round((point.x + WALK_LIMIT) / step)), 0, cells - 1)
	var row := clampi(int(round((point.y + WALK_LIMIT) / step)), 0, cells - 1)
	return row * cells + column

func test_walls_are_dense_enough_and_short_enough_to_shape_a_jungle() -> void:
	gt(float(MapLayout.WALLS.size()), 8.0, "野区墙体至少 9 段，4 段撑不起「野区地形」")
	var longest := 0.0
	for wall in MapLayout.WALLS:
		longest = maxf(longest, (wall.a as Vector2).distance_to(wall.b))
	lt(longest, 30.0, "单段墙超过 30 米就会把野区拦腰截断，长墙必须拆成带缺口的几段")
	# 四个野区（蓝/红 × 上/下）都要有墙，不能只在一侧堆石头。
	var quadrant_counts := {
		"blue_top": 0, "blue_bottom": 0, "red_top": 0, "red_bottom": 0,
	}
	for wall in MapLayout.WALLS:
		var center: Vector2 = (wall.a + wall.b) * 0.5
		var side := "blue" if center.x - center.y > 0.0 else "red"
		var half_side := "top" if center.x + center.y < 0.0 else "bottom"
		quadrant_counts["%s_%s" % [side, half_side]] += 1
	for quadrant in quadrant_counts:
		gt(float(quadrant_counts[quadrant]), 1.0, "野区 %s 至少要有 2 段墙" % quadrant)

func test_walls_do_not_cross_each_other() -> void:
	# 两道墙交叉 = 两个盒子互相穿模，俯视看是一坨歪掉的多边形，
	# 而且交点处的碰撞法线会来回翻转，贴上去会抖。
	var crossed := 0
	for i in MapLayout.WALLS.size():
		for j in range(i + 1, MapLayout.WALLS.size()):
			var first: Dictionary = MapLayout.WALLS[i]
			var second: Dictionary = MapLayout.WALLS[j]
			var hit: Variant = Geometry2D.segment_intersects_segment(first.a, first.b, second.a, second.b)
			if hit != null:
				check(false, "墙与墙交叉穿模：%s × %s" % [str(first.id), str(second.id)])
				crossed += 1
	eq(crossed, 0, "墙体之间不能交叉")

func test_walls_are_tall_enough_to_read_as_a_rock_face() -> void:
	# 1.7 米的墙在 51° 俯视下只剩一条石坎，读不出「这是墙」。
	gt(float(MapLayout.WALL_HEIGHT), 2.0, "野区墙体必须高过英雄，才读得出是石壁")
	gt(float(MapLayout.WALL_HEIGHT), float(MapLayout.WALL_THICKNESS), "墙高必须大于墙厚，否则是个石墩")

func test_base_decor_buildings_are_gone() -> void:
	# 用户 2026-10-25：基地左右两边的房子和摊子（神庙 / 集市 / 兵营 / 木箱木桶）全部删除，红方同样。
	var source := FileAccess.get_file_as_string("res://scripts/game/arena.gd")
	for token in [
		"Market_FirstAge_Level3",
		"Barracks_FirstAge_Level3",
		"Temple_FirstAge_Level3",
		"TownCenter_SecondAge_Level3",
		"Crate.glb",
		"Barrel.glb",
	]:
		check(not source.contains(token), "基地旁不该再有装饰建筑：%s" % token)
	check(not source.contains("_build_base_decor"), "基地装饰构建函数应当整段移除")
	var arena = Arena.new()
	check(not arena.has_method("_build_base_decor"), "Arena 上不应再存在 _build_base_decor")
	arena.free()
