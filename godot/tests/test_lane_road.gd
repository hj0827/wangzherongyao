extends "res://tests/test_base.gd"

# 三路路面（3D 地图上看得见的那三条路）的回归守卫。
#
# 起因：小地图上清清楚楚三条路，进到战场里却是一整片草地 —— 一根路都没有。
# 根因是 `_lane_ribbon` 的三角形绕序反了：Godot 的 CULL_BACK 会把「右手定则法线
# 朝向相机」的三角形当背面剔掉，所以路面网格一直存在、一直不显示。
#
# 这里的契约：
#   1. 画出来的路面宽度 = 模拟层的路宽（MapData.LANE_HALF_WIDTH），不多不少；
#   2. 每个路面三角形都必须和地形网格**同一个绕序方向**（法线朝下），否则看不见；
#   3. 路面是一条连续带，不是一段段四边形拼的（拼的会在拐角漏缝）；
#   4. 三条路各走各的，中间要留出野区，不能连成一整块。

const MapData = preload("res://sim/map_data.gd")
const MapLayout = preload("res://sim/map/map_layout.gd")
const LaneRoad = preload("res://scripts/game/lane_road.gd")
const Arena = preload("res://scripts/game/arena.gd")

const EPS := 0.02

# 一条笔直的测试路径，方便把「宽度 / 绕序 / 覆盖」算成具体数字。
func _straight_path() -> Array:
	return [Vector2(-20.0, 0.0), Vector2(0.0, 0.0), Vector2(20.0, 0.0)]

func _triangle(points: PackedVector3Array, index: int) -> Array:
	return [points[index * 3], points[index * 3 + 1], points[index * 3 + 2]]

# 右手定则法线。Godot 里「正面」= 法线背对相机，所以从上方看，
# 可见的地面三角形法线必须朝下（-Y）。地形网格就是这个方向（见 terrain_builder）。
func _facing(a: Vector3, b: Vector3, c: Vector3) -> Vector3:
	return (b - a).cross(c - a)

func _area_xz(a: Vector3, b: Vector3, c: Vector3) -> float:
	return absf((b - a).cross(c - a).y) * 0.5

func test_road_width_equals_the_simulated_lane_width() -> void:
	# 「模拟层说路有多宽，玩家看到的路就有多宽」。差得多了会变成
	# 「明明站在路上却被判定在野区」/「看着能过其实撞墙」。
	near(LaneRoad.surface_half_width(), float(MapData.LANE_HALF_WIDTH), EPS,
		"画出来的路面半宽必须等于模拟层路宽")
	near(LaneRoad.surface_half_width() * 2.0, 7.5, EPS, "路面全宽 7.5m")

	var points := LaneRoad.ribbon_triangles(_straight_path(), LaneRoad.surface_half_width() * 2.0, LaneRoad.SURFACE_Y)
	gt(float(points.size()), 0.0, "笔直路径必须生成三角形")
	# 直路上，所有顶点到中心线（y=0）的距离都不该超过半宽。
	for index in points.size():
		var p := points[index]
		near(p.y, LaneRoad.SURFACE_Y, EPS, "路面高度必须统一")
		lt(absf(p.z), LaneRoad.surface_half_width() + EPS, "路面顶点不能跑出半宽")
	# 必须有顶点正好压在半宽上，否则实际画出来比声明的窄。
	var widest := 0.0
	for index in points.size():
		widest = maxf(widest, absf(points[index].z))
	near(widest, LaneRoad.surface_half_width(), 0.05, "路缘必须顶到半宽")

func test_every_road_triangle_faces_down_like_the_terrain() -> void:
	# 这条就是本次 bug 的回归：绕序反了 → 法线朝上 → 被背面剔除 → 草地上一根路都没有。
	for lane in MapData.LANE_ORDER:
		var path: Array = MapLayout.smoothed_lane(str(lane), 2)
		var points := LaneRoad.ribbon_triangles(path, 7.5, LaneRoad.SURFACE_Y)
		gt(float(points.size()), 0.0, "路 %s 必须生成三角形" % str(lane))
		var count := points.size() / 3
		for index in count:
			var tri := _triangle(points, index)
			var normal := _facing(tri[0], tri[1], tri[2])
			lt(normal.y, -0.5, "路面三角形法线必须朝下（与地形同绕序），否则会被背面剔除：%s #%d" % [str(lane), index])

func test_road_band_covers_the_whole_lane() -> void:
	# 用面积守恒验证「整条路都铺满了」：面积 ≈ 路宽 × 路长。
	# 少铺了会出现一段露草地，多铺了会压到野区。
	for lane in MapData.LANE_ORDER:
		var path: Array = MapLayout.smoothed_lane(str(lane), 2)
		var points := LaneRoad.ribbon_triangles(path, 7.5, LaneRoad.SURFACE_Y)
		var area := 0.0
		for index in points.size() / 3:
			var tri := _triangle(points, index)
			area += _area_xz(tri[0], tri[1], tri[2])
		var expected := 7.5 * LaneRoad.path_length(path)
		near(area / expected, 1.0, 0.03, "路 %s 的铺装面积必须接近 路宽×路长" % str(lane))
	# 而且铺的确实是整条兵线，不是只铺了中间一段。
	for lane in MapData.LANE_ORDER:
		var path: Array = MapLayout.smoothed_lane(str(lane), 2)
		gt(LaneRoad.path_length(path), MapLayout.lane_length(str(lane)) * 0.85,
			"路 %s 的长度不能因为平滑而缩水太多" % str(lane))

func test_road_is_one_continuous_strip() -> void:
	# 一段段四边形拼起来的带子，在拐角外侧会漏出楔形缝（草地从缝里透出来）。
	# 连续带的顶点数 = 2 × 路径点数，三角形数 = 2 × (点数 - 1)。
	var path := _straight_path()
	var points := LaneRoad.ribbon_triangles(path, 7.5, LaneRoad.SURFACE_Y)
	eq(points.size() / 3, 2 * (path.size() - 1), "三角形数必须 = 2 × (路点 - 1)")
	# 拐角处也要有覆盖：在路径拐点上下各 1m 取点，必须落在某个三角形内。
	var bent := [Vector2(-10.0, 0.0), Vector2(0.0, 0.0), Vector2(0.0, 10.0)]
	var bent_points := LaneRoad.ribbon_triangles(bent, 7.5, LaneRoad.SURFACE_Y)
	# 拐角内侧、外侧、以及外侧那个楔形缺口（x>0 / y<0 那一小块）都要铺到。
	for corner in [Vector2(0.0, -1.0), Vector2(-1.0, 0.0), Vector2(0.0, 1.0), Vector2(1.0, -1.0)]:
		check(_covered(bent_points, corner), "拐点附近必须被路面覆盖：%s" % str(corner))

func _covered(points: PackedVector3Array, point: Vector2) -> bool:
	for index in points.size() / 3:
		var tri := _triangle(points, index)
		if _in_triangle(Vector2(tri[0].x, tri[0].z), Vector2(tri[1].x, tri[1].z), Vector2(tri[2].x, tri[2].z), point):
			return true
	return false

func _in_triangle(a: Vector2, b: Vector2, c: Vector2, p: Vector2) -> bool:
	var d1 := (b - a).cross(p - a)
	var d2 := (c - b).cross(p - b)
	var d3 := (a - c).cross(p - c)
	var has_neg := d1 < -0.0001 or d2 < -0.0001 or d3 < -0.0001
	var has_pos := d1 > 0.0001 or d2 > 0.0001 or d3 > 0.0001
	return not (has_neg and has_pos)

func test_edge_stones_run_down_both_sides() -> void:
	# 王者峡谷的三条路两侧都有石质路肩，玩家靠它一眼分清「路」和「野区」。
	for lane in MapData.LANE_ORDER:
		var path: Array = MapLayout.smoothed_lane(str(lane), 2)
		var stones := LaneRoad.edge_stones(path, 7.5)
		gt(float(stones.size()), 20.0, "路 %s 的路缘石数量太少" % str(lane))
		var left := 0
		var right := 0
		for stone in stones:
			var offset := float(stone.get("offset", 0.0))
			if offset < 0.0:
				left += 1
			else:
				right += 1
			near(absf(offset), 7.5 * 0.5 + LaneRoad.EDGE_STONE_INSET, 0.05, "路缘石必须贴着路缘")
		lt(0.0, float(left), "路 %s 左侧必须有路缘石" % str(lane))
		lt(0.0, float(right), "路 %s 右侧必须有路缘石" % str(lane))
		# 左右数量必须相等（成对摆放），否则会有一侧看起来是断的。
		eq(left, right, "路 %s 两侧路缘石必须成对" % str(lane))

func test_three_lanes_stay_apart_in_the_open_field() -> void:
	# 三条路如果在中段就靠在一起，看起来会是一整片空地而不是「上中下三路」。
	for a in MapData.LANE_ORDER:
		for b in MapData.LANE_ORDER:
			if str(a) >= str(b):
				continue
			var closest := INF
			for step in 9:
				var t := 0.2 + 0.075 * float(step)
				var pa := MapLayout.point_along_lane(str(a), t)
				var pb := MapLayout.point_along_lane(str(b), t)
				closest = minf(closest, pa.distance_to(pb))
			gt(closest, 6.0, "路 %s 与 %s 在中段必须拉开距离（当前最近 %.2f）" % [str(a), str(b), closest])

func test_surface_sits_above_terrain_but_stays_flat() -> void:
	# 太贴地会和地形 z-fighting（远处路面闪成一片斑），太高会变成一块悬空的板。
	gt(LaneRoad.SURFACE_Y, 0.02, "路面必须离地，否则和地形打架")
	lt(LaneRoad.SURFACE_Y, 0.15, "路面不能抬成台阶，英雄会像站在板子上")
	# 三层铺装必须由低到高，层与层之间不能共面。
	var heights: Array = LaneRoad.layer_heights()
	eq(heights.size(), 3, "路面必须有三层铺装（路肩 / 路面 / 中央走道）")
	for index in range(1, heights.size()):
		gt(float(heights[index]), float(heights[index - 1]) + 0.004, "铺装层高度必须递增且不共面")

func test_arena_actually_builds_three_lanes() -> void:
	# "数据对 + 文件在" ≠ "路真的建出来了"。真跑一次构建，数节点。
	var arena = Arena.new()
	arena._props_root = Node3D.new()
	arena.add_child(arena._props_root)
	arena.call("_build_lanes")
	var lane_nodes := 0
	var stone_node: Node = null
	for child in arena._props_root.get_children():
		if str(child.name).begins_with("lane_"):
			lane_nodes += 1
		if str(child.name).begins_with("road_edges"):
			stone_node = child
	eq(lane_nodes, 9, "三条路 × 三层铺装 = 9 个路面节点")
	check(stone_node != null, "路缘石要有一个统一节点")
	# 一百多个石墩必须走 MultiMesh，否则就是一百多个 draw call。
	check(stone_node is MultiMeshInstance3D, "路缘石必须用 MultiMesh 合批")
	if stone_node is MultiMeshInstance3D:
		gt(float(stone_node.multimesh.instance_count), 90.0, "三路两侧的路缘石总数应该上百")
	# 每个路面节点都必须真的带网格（空节点是最常见的"看起来建了其实没画"）。
	for child in arena._props_root.get_children():
		if str(child.name).begins_with("lane_"):
			check(child is MeshInstance3D, "%s 必须是网格节点" % str(child.name))
			gt(float(child.mesh.get_surface_count()), 0.0, "%s 必须有实际几何" % str(child.name))
	arena.free()
