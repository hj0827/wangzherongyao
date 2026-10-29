extends "res://tests/test_base.gd"

# 边路必须贴着方框（边界城墙）走。
#
# 起因：改之前 top / bottom 是跨越大半个地图的大弧线 —— 中心线离边界 12~32 米
# （均值 16.6 米），路外沿最近也隔着 8.25 米空草地。玩家看到的不是「沿边走的
# 上路」，而是野区里两条斜穿的路。
#
# 参考王者峡谷：边路是沿地图两条边跑的 L 形，路外沿离边界只剩几米。
# 但「贴多近」有物理上限，不能靠眼睛定：
#   可走范围 = BOUNDS - 英雄半径 - CAMERA_WALL_MARGIN
#            = 58 - 0.55 - 3.8 = 53.65
#   路中心最外 = 53.65 - LANE_HALF_WIDTH(3.75) = 49.9
# 再往外铺就是「看得见的路面，人走不上去」—— 那种假路比不贴边更糟。

const MapData = preload("res://sim/map_data.gd")
const MapLayout = preload("res://sim/map/map_layout.gd")
const Collision = preload("res://sim/map/collision.gd")
const Arena = preload("res://scripts/game/arena.gd")

const HERO_RADIUS := 0.55
# 贴边判据：路面外沿到边界墙内表面的距离。4.25 是当前实测值，
# 上限放 5.0 是为了留一点微调空间，但必须远小于旧版的 8.25。
const MAX_OUTER_GAP := 5.0
const MIN_OUTER_GAP := 1.0

# 沿平滑后的兵线按弧长均匀采样。用平滑线而不是折线，因为玩家看到的是这条。
func _samples(lane: String, step := 0.5) -> Array:
	var path: Array = MapLayout.smoothed_lane(lane, 6)
	var out: Array = []
	for index in range(path.size() - 1):
		var a: Vector2 = path[index]
		var b: Vector2 = path[index + 1]
		var span := a.distance_to(b)
		var count := maxi(1, int(ceil(span / step)))
		for k in count:
			out.append(a.lerp(b, float(k) / float(count)))
	out.append(path[path.size() - 1])
	return out

# 点到方框内表面的距离（负数表示已经出了边界）。
func _frame_gap(point: Vector2) -> float:
	return MapLayout.boundary_inner() - maxf(absf(point.x), absf(point.y))

func _ratio(count: int, total: int) -> float:
	if total <= 0:
		return 0.0
	return float(count) / float(total)

func test_side_lanes_run_along_the_boundary_frame() -> void:
	# 旧版：0% 的采样点在 10 米内，均值 16.6。新版：均值 8.6，85% 在 10 米内。
	# 用「均值 + 覆盖比例」两个数，而不是「是否经过某个坐标」——
	# 后者会把航点写死，以后微调一下路就红了。
	for lane in ["top", "bottom"]:
		var samples := _samples(lane)
		var total := samples.size()
		var sum := 0.0
		var near := 0
		for point in samples:
			var gap := _frame_gap(point)
			sum += gap
			if gap <= 10.0:
				near += 1
		var mean := sum / float(total)
		lt(mean, 10.0, "%s 路中心线平均离边界 %.2f 米，必须 ≤ 10 米才算贴边" % [lane, mean])
		gt(_ratio(near, total), 0.8, "%s 路只有 %.0f%% 的段落贴边（要求 ≥ 80%%）" % [lane, _ratio(near, total) * 100.0])

func test_road_surface_never_reaches_the_boundary_wall() -> void:
	# 两个方向都要挡：贴得不够（旧版 8.25）和贴过头（路面穿墙 / 跨过可走边界）。
	for lane in ["top", "bottom"]:
		var samples := _samples(lane)
		var total := samples.size()
		var hugging := 0
		for point in samples:
			var outer := _frame_gap(point) - float(MapData.LANE_HALF_WIDTH)
			gt(outer, MIN_OUTER_GAP, "%s 路外沿离边界只剩 %.2f 米，已经压到墙根" % [lane, outer])
			if outer <= MAX_OUTER_GAP:
				hugging += 1
		gt(_ratio(hugging, total), 0.6,
			"%s 路只有 %.0f%% 的路面外沿在 %.1f 米内（要求 ≥ 60%%）" % [lane, _ratio(hugging, total) * 100.0, MAX_OUTER_GAP])

func test_the_whole_road_surface_is_walkable() -> void:
	# 「贴着方框」和「整幅路面都能走」是同一个约束的两面：
	# 路面外沿一旦越过 clamp_bounds，玩家沿边跑就会撞上隐形墙。
	for lane in ["top", "bottom"]:
		var samples := _samples(lane)
		var worst := 0.0
		for index in range(1, samples.size() - 1):
			var tangent: Vector2 = (samples[index + 1] as Vector2) - (samples[index - 1] as Vector2)
			if tangent.length() < 0.0001:
				continue
			var normal := Vector2(-tangent.y, tangent.x).normalized()
			for side in [1.0, -1.0]:
				var edge: Vector2 = (samples[index] as Vector2) + normal * float(side) * float(MapData.LANE_HALF_WIDTH)
				var settled: Vector2 = Collision.clamp_bounds(edge, HERO_RADIUS)
				worst = maxf(worst, settled.distance_to(edge))
		lt(worst, 1.0, "%s 路缘被夹回 %.2f 米：路面伸进了走不到的相机边距里" % [lane, worst])

func test_lane_edge_offset_matches_the_walkable_budget() -> void:
	# 把「为什么不能更贴」写成契约：贴边偏移 = 可走边界 - 路半宽。
	# 以后谁想把路再往外挪 3 米，这条会直接告诉他挪出去的部分走不了。
	var budget: float = float(MapData.BOUNDS) - HERO_RADIUS - float(MapData.CAMERA_WALL_MARGIN) - float(MapData.LANE_HALF_WIDTH)
	near(float(MapData.LANE_EDGE_OFFSET), budget, 0.3,
		"贴边偏移 %.2f 必须贴近可走预算 %.2f（超出就是玩家走不到的路面）" % [float(MapData.LANE_EDGE_OFFSET), budget])
	lt(float(MapData.LANE_EDGE_OFFSET), float(MapData.BOUNDS) - float(MapData.LANE_HALF_WIDTH),
		"路面外沿必须留在边界墙以内")

func test_edge_lanes_form_one_l_shape() -> void:
	# 边路要读成「沿两条边跑的 L」，而不是斜穿。判据用位移分解：
	# 一条直边贡献的水平行程接近全长，另一条贡献的垂直行程接近全长。
	# 旧版是弧线，两个方向上各只有全长的一部分（92 / 92，且分布均匀，
	# 说明它是 45° 斜着趟过去的）。
	for lane in ["top", "bottom"]:
		var samples := _samples(lane)
		var run_x := 0.0
		var run_y := 0.0
		for index in range(samples.size() - 1):
			var delta: Vector2 = (samples[index + 1] as Vector2) - (samples[index] as Vector2)
			run_x += absf(delta.x)
			run_y += absf(delta.y)
		# 两条边各 96 米，扣掉基地两端的圆角后仍有 90 米以上。
		gt(run_x, 88.0, "%s 路沿 x 方向只走了 %.1f 米，不像一条贴着上下边的长直段" % [lane, run_x])
		gt(run_y, 88.0, "%s 路沿 y 方向只走了 %.1f 米，不像一条贴着左右边的长直段" % [lane, run_y])

func test_straight_runs_are_sampled_densely_enough_to_stay_straight() -> void:
	# Chaikin 的切角范围与相邻段长成正比。直段上如果只留两个端点，
	# 拐角会把 96 米长边各削掉二十多米，路又变回弧线。
	# 判据：同一条边上的相邻航点间距不超过 SAMPLING_LIMIT。
	var sampling_limit := float(MapData.LANE_EDGE_SAMPLE) + 6.0
	for lane in ["top", "bottom"]:
		for axis in ["x", "y"]:
			var coordinate := -float(MapData.LANE_EDGE_OFFSET)
			var along: Array[float] = []
			for point in MapData.lane_path(lane):
				var p: Vector2 = point
				var fixed := p.y if axis == "x" else p.x
				if absf(fixed - coordinate) > 0.01:
					continue
				along.append(p.x if axis == "x" else p.y)
			if along.size() < 2:
				continue
			along.sort()
			for index in range(1, along.size()):
				var span := along[index] - along[index - 1]
				lt(span, sampling_limit, "%s 路的 %s 边有 %.1f 米没有航点，拐角会把这段削成弧" % [lane, axis, span])

func test_every_river_crossing_sits_on_solid_stone() -> void:
	# 边路贴边之后必然跨河：河道沿 y = x 一直通到地图两端，L 形边路的拐角
	# 正好落在上面。如果那里只有一块悬在水上的路面，玩家看到的是
	# 「一条土路横在河面上」。
	#
	# 2026-10-28 变了兜底方式：玩家要求「把这个角落全部铺上……不需要那个桥」，
	# 于是角落不再建桥，改由**角落广场**整块盖住跨河段。契约本身没变：
	# 每一个跨河点都必须落在石面上（桥面或广场面），不能是悬空路面。
	var crossings: Array = MapLayout.lane_river_crossings()
	eq(crossings.size(), 2, "上下路各有一个跨河点")
	var arena := Arena.new()
	arena._props_root = Node3D.new()
	arena.add_child(arena._props_root)
	arena.call("_build_river")
	var bridges := 0
	var plazas := 0
	for child in arena._props_root.get_children():
		var node_name := str(child.name)
		if node_name.begins_with("Bridge"):
			bridges += 1
		elif node_name.begins_with("CornerPlaza"):
			plazas += 1
	eq(bridges, 1, "只剩中路一座桥：边路跨河改由角落广场铺石")
	eq(plazas, 2, "两个空角落各一块广场")
	for crossing in crossings:
		var covered := false
		for child in arena._props_root.get_children():
			var node_name := str(child.name)
			if not (node_name.begins_with("Bridge") or node_name.begins_with("CornerPlaza")):
				continue
			if _bridge_covers(child, crossing.pos):
				covered = true
				break
		check(covered, "%s 路的跨河点没有落在任何石面上 —— 那里就是一块悬空的路面" % str(crossing.lane))
	# 桥和广场都不能穿出边界墙：桥面贴边，广场外沿本身就塞在墙基座下面。
	# 允许到墙心线（BOUNDARY_CENTER）为止 —— 再往外就顶穿墙身了。
	for child in arena._props_root.get_children():
		var node_name := str(child.name)
		if not (node_name.begins_with("Bridge") or node_name.begins_with("CornerPlaza")):
			continue
		var node := child as MeshInstance3D
		var limit := MapLayout.boundary_inner() - 0.5 if node_name.begins_with("Bridge") else MapLayout.BOUNDARY_CENTER
		for vertex in _bridge_vertices(node):
			var corner := Vector2(vertex.x, vertex.z)
			lt(maxf(absf(corner.x), absf(corner.y)), limit,
				"%s 的角点 (%s) 顶进了边界墙" % [node_name, str(corner)])
	arena.free()

func _bridge_vertices(node: MeshInstance3D) -> PackedVector3Array:
	var out := PackedVector3Array()
	if node == null or node.mesh == null:
		return out
	var arrays := node.mesh.surface_get_arrays(0)
	var raw: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	for vertex in raw:
		out.append(node.transform * vertex)
	return out

# 点是否落在桥面的顶面三角形里（桥面不再是旋转 90° 的直板，不能再按局部矩形算）。
func _bridge_covers(node: MeshInstance3D, point: Vector2) -> bool:
	if node == null or node.mesh == null:
		return false
	var arrays := node.mesh.surface_get_arrays(0)
	var raw: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	for index in raw.size() / 3:
		var a := node.transform * raw[index * 3]
		var b := node.transform * raw[index * 3 + 1]
		var c := node.transform * raw[index * 3 + 2]
		if a.y <= 0.01 or b.y <= 0.01 or c.y <= 0.01:
			continue
		if _point_in_triangle(Vector2(a.x, a.z), Vector2(b.x, b.z), Vector2(c.x, c.z), point):
			return true
	return false

func _point_in_triangle(a: Vector2, b: Vector2, c: Vector2, p: Vector2) -> bool:
	var d1 := (b - a).cross(p - a)
	var d2 := (c - b).cross(p - b)
	var d3 := (a - c).cross(p - c)
	var has_neg := d1 < -0.0001 or d2 < -0.0001 or d3 < -0.0001
	var has_pos := d1 > 0.0001 or d2 > 0.0001 or d3 > 0.0001
	return not (has_neg and has_pos)

func test_edge_lanes_keep_clear_of_objectives_and_camps() -> void:
	# 贴边不等于可以压过野区要素：路面盖住首领坑就是「看着能打，其实走不进去」。
	# 判据是「路面外沿不进入区域边缘」，间隙 > 0.5 米。
	for lane in ["top", "bottom"]:
		var samples := _samples(lane)
		for camp in MapLayout.CAMPS:
			var closest := INF
			for point in samples:
				closest = minf(closest, (point as Vector2).distance_to(camp.pos))
			gt(closest, float(camp.radius) + float(MapData.LANE_HALF_WIDTH) + 0.5,
				"%s 路压到了野区营地 %s" % [lane, str(camp.id)])
		for pit in MapLayout.OBJECTIVE_PITS:
			var closest := INF
			for point in samples:
				closest = minf(closest, (point as Vector2).distance_to(pit.pos))
			gt(closest, float(pit.radius) + float(MapData.LANE_HALF_WIDTH) + 0.5,
				"%s 路压到了首领坑 %s" % [lane, str(pit.id)])

func test_pads_sit_off_the_lane_deep_in_the_corner() -> void:
	# 传送阵与兵线的关系在 2026-10-28 经历了第二版：
	#   ① 河岸走廊（离路远，但离角落也远）；
	#   ② 角落桥正中（压在跨河点上，兵线从阵上穿过）；
	#   ③ 现在是**角落广场的最角落**：广场把路面盖在下面，兵线在阵旁边的石台上走。
	# 所以这条要守的是「阵不能盖到路面上去」——广场面比路面高 2cm，
	# 阵盘压在路面上就是「石台上一块会走位的地砖」，视觉和判定都乱。
	for pad in MapLayout.TELEPORT_PADS:
		var from_lane := MapLayout.distance_to_lanes(pad.pos) - MapData.LANE_HALF_WIDTH
		gt(from_lane, 0.0, "%s 的阵心不能落在兵线路面上（离路缘 %.2f 米）" % [str(pad.id), from_lane])
		# 每个阵只属于一条边路的拐角 —— 另一条在对面角落，离它几十米远。
		var far_lane := ""
		var far := 0.0
		for lane in ["top", "bottom"]:
			var closest := INF
			for point in _samples(str(lane)):
				closest = minf(closest, (point as Vector2).distance_to(pad.pos))
			if closest > far:
				far = closest
				far_lane = str(lane)
		gt(far, 40.0, "%s 不该同时贴两条边路（对面那条 %s 只有 %.1f 米）" % [str(pad.id), far_lane, far])
