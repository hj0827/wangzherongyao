extends "res://tests/test_base.gd"

# 桥的几何契约（2026-10-25 重做）。
#
# 背景：上下路的跨河点正好压在 L 形拐角的圆角上。旧实现三座桥都是同一块 45° 的直板，
# 拐角处桥端斜着切穿路面、护栏从路中间断开、桥角戳进草地 —— 俯视就是「一块石板斜扣在拐角上」。
# 现在的契约：
#   1. 桥面是兵线路径截出来的一段连续带：桥心 = 跨河点，桥端垂直于路面、落在直段上；
#   2. 护栏沿路缘弯过去，两端用门柱收口，整条护栏压在桥面以内；
#   3. 桥墩顶面必须低于桥面（旧版高出 0.33m，俯视是桥面上多了几个圆饼）；
#   4. 桥端接坡把桥面从 10.6m 收到路肩 9.75m、并压到路面高度，不能留台阶；
#   5. 任何桥角都不能顶进边界墙。
#
# 高度/宽度是表现层契约，写死在这里（改桥面高度必须先改这条测试）。

const Arena = preload("res://scripts/game/arena.gd")
const LaneRoad = preload("res://scripts/game/lane_road.gd")
const MapView = preload("res://scripts/game/map_view.gd")
const MapLayout = preload("res://sim/map/map_layout.gd")

const EPS := 0.02
const DECK_Y := 0.075
const ROAD_Y := 0.05
const RAIL_OFFSET := 4.6
const SHORE_WIDTH := 9.75  # 路肩全宽：桥端接坡收到这里就算「接进路面」

func _arena() -> Node3D:
	var arena: Node3D = Arena.new()
	arena._props_root = Node3D.new()
	arena.add_child(arena._props_root)
	return arena

func _find(arena: Node3D, node_name: String) -> Node:
	for child in arena._props_root.get_children():
		if str(child.name) == node_name:
			return child
	return null

func _top_bridge_crossing() -> Vector2:
	for entry in MapLayout.lane_river_crossings():
		if str(entry.lane) == "top":
			return entry.pos
	return Vector2.ZERO

func _vertices(node: MeshInstance3D) -> PackedVector3Array:
	var out := PackedVector3Array()
	if node == null or node.mesh == null:
		return out
	var arrays := node.mesh.surface_get_arrays(0)
	var raw: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	for vertex in raw:
		out.append(node.transform * vertex)
	return out

# 桥面三角形的 XZ 包含测试。
func _covers(node: MeshInstance3D, point: Vector2) -> bool:
	var arrays := node.mesh.surface_get_arrays(0)
	var raw: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	for index in raw.size() / 3:
		var a := node.transform * raw[index * 3]
		var b := node.transform * raw[index * 3 + 1]
		var c := node.transform * raw[index * 3 + 2]
		if a.y <= 0.01 or b.y <= 0.01 or c.y <= 0.01:
			continue
		if _in_triangle(a, b, c, Vector3(point.x, 0.0, point.y)):
			return true
	return false

func _in_triangle(a: Vector3, b: Vector3, c: Vector3, p: Vector3) -> bool:
	var d1 := (b - a).cross(p - a).y
	var d2 := (c - b).cross(p - b).y
	var d3 := (a - c).cross(p - c).y
	var has_neg := d1 < -0.0001 or d2 < -0.0001 or d3 < -0.0001
	var has_pos := d1 > 0.0001 or d2 > 0.0001 or d3 > 0.0001
	return not (has_neg and has_pos)

func _distance_to_lane(lane: String, point: Vector2) -> float:
	var path: Array = MapView.lane_path(lane)
	var best := INF
	for index in path.size() - 1:
		best = minf(best, MapLayout.point_to_segment_distance(point, path[index], path[index + 1]))
	return best

func _lane_direction_at(lane: String, point: Vector2) -> Vector2:
	var path: Array = MapView.lane_path(lane)
	var best := INF
	var direction := Vector2.RIGHT
	for index in path.size() - 1:
		var a: Vector2 = path[index]
		var b: Vector2 = path[index + 1]
		var distance := MapLayout.point_to_segment_distance(point, a, b)
		if distance < best:
			best = distance
			direction = (b - a).normalized()
	return direction

func test_bridge_deck_follows_the_lane_around_the_corner() -> void:
	var arena := _arena()
	var crossing := _top_bridge_crossing()
	check(crossing.length() > 1.0, "上路必须有跨河点")
	arena.call("_build_bridge", "top", crossing, Arena.BRIDGE_SPAN_EDGE)
	var deck := _find(arena, "Bridge_top") as MeshInstance3D
	check(deck != null, "上路桥面必须存在（桥是路的一部分）")
	if deck == null:
		arena.free()
		return
	check(_covers(deck, crossing), "跨河点必须落在桥面上，否则那段路面是悬空的")
	var verts := _vertices(deck)
	var top := PackedVector3Array()
	for vertex in verts:
		if vertex.y > 0.0:
			top.append(vertex)
	gt(float(top.size()), 4.0, "桥面必须有顶面顶点")
	for vertex in top:
		near(vertex.y, DECK_Y, EPS, "桥面高度必须统一")

	# 跨河点压在圆角上，桥必须跟着路弯；直板会在拐角外侧离开兵线。
	for vertex in top:
		var offset := _distance_to_lane("top", Vector2(vertex.x, vertex.z))
		lt(offset, Arena.BRIDGE_WIDTH * 0.5 + 0.35,
			"桥面顶点离路心 %.2fm，已经离开兵线 —— 这是直板扣在弯道上的形状" % offset)

	# 桥端：在兵线弧长上各截半个桥长，端边必须垂直于当地路面、宽度正好一个桥宽。
	var path: Array = MapView.lane_path("top")
	var half_span := Arena.BRIDGE_SPAN_EDGE * 0.5
	var slice := LaneRoad.slice_around(path, crossing, half_span)
	gt(float(slice.size()), 2.0, "跨河点两端的路面本身在转弯，桥面必须截出中间路点")
	for end in 2:
		var index := 0 if end == 0 else slice.size() - 1
		var neighbor := 1 if end == 0 else slice.size() - 2
		var point: Vector2 = slice[index]
		var direction := (point - (slice[neighbor] as Vector2)).normalized()
		var normal := Vector2(-direction.y, direction.x)
		for side in [-1.0, 1.0]:
			var expected: Vector2 = point + normal * Arena.BRIDGE_WIDTH * 0.5 * side
			var closest := INF
			for vertex in top:
				closest = minf(closest, Vector2(vertex.x, vertex.z).distance_to(expected))
			lt(closest, 0.06, "桥端角点必须落在 (%.2f, %.2f)：端边垂直于路面、宽度 10.6m" % [expected.x, expected.y])

	# 桥面必须沿兵线铺满整个桥长，而不能缩在跨河点附近。
	var center_arc := LaneRoad.nearest_arc(path, crossing)
	var reach := 0.0
	for vertex in top:
		reach = maxf(reach, absf(LaneRoad.nearest_arc(path, Vector2(vertex.x, vertex.z)) - center_arc))
	near(reach, half_span, 0.2, "桥面覆盖的弧长必须是 %.1fm" % Arena.BRIDGE_SPAN_EDGE)
	arena.free()

func test_bridge_rails_follow_the_curve_and_close_with_posts() -> void:
	var arena := _arena()
	var crossing := _top_bridge_crossing()
	arena.call("_build_bridge", "top", crossing, Arena.BRIDGE_SPAN_EDGE)
	var rails := _find(arena, "bridge_rails_top") as MultiMeshInstance3D
	check(rails != null, "桥护栏必须是沿路缘跟随的连续构件")
	if rails == null:
		arena.free()
		return
	# headless 的 dummy 渲染器不保存 MultiMesh 实例变换（读回来全是单位矩阵），
	# 构建时把同一份变换记到 meta 上，这里量的是真正交给渲染器的数据。
	var transforms: Array = rails.get_meta("rail_transforms", [])
	check(transforms.size() > 0, "护栏变换必须记录在节点上")
	eq(rails.multimesh.instance_count, transforms.size(), "MultiMesh 实例数必须与护栏变换一致")
	var posts := 0
	var bars := 0
	for index in transforms.size():
		var transform: Transform3D = transforms[index]
		var scale := transform.basis.get_scale()
		var pos := Vector2(transform.origin.x, transform.origin.z)
		var offset := _distance_to_lane("top", pos)
		lt(offset, Arena.BRIDGE_WIDTH * 0.5, "护栏必须压在桥面以内（离路心 %.2f）" % offset)
		near(offset, RAIL_OFFSET, 0.45, "护栏必须贴着路缘弯过去（离路心 %.2f）" % offset)
		if scale.y > 0.7:
			posts += 1
			continue
		bars += 1
		var direction := _lane_direction_at("top", pos)
		var rail_dir := Vector2(transform.basis.z.x, transform.basis.z.z).normalized()
		gt(absf(rail_dir.dot(direction)), 0.97, "护栏长边必须跟着路面方向（拐角处转了角就是断开）")
		gt(float(transform.origin.y), DECK_Y, "护栏必须站在桥面上")
	eq(posts, 4, "两条护栏各有两端，必须用 4 根门柱收口")
	gt(float(bars), 8.0, "两条护栏都要有足够的栏段")
	arena.free()

func test_bridge_has_a_side_skirt_below_the_waterline() -> void:
	# 桥面是一条只有顶面的连续带。没有侧裙板时，斜俯视能直接从桥缘看进水缝，
	# 桥就读成一块飘在河上的石板。裙板必须压到水面（-0.42）以下，且严格贴着桥缘。
	var arena := _arena()
	var crossing := _top_bridge_crossing()
	arena.call("_build_bridge", "top", crossing, Arena.BRIDGE_SPAN_EDGE)
	var skirt := _find(arena, "bridge_skirt_top") as MeshInstance3D
	check(skirt != null, "桥必须有侧裙板")
	if skirt != null:
		var verts := _vertices(skirt)
		gt(float(verts.size()), 8.0, "侧裙板必须沿整座桥铺开")
		var lowest := INF
		for vertex in verts:
			lowest = minf(lowest, vertex.y)
			near(_distance_to_lane("top", Vector2(vertex.x, vertex.z)), Arena.BRIDGE_WIDTH * 0.5, 0.05,
				"裙板必须严格贴在桥缘上")
		lt(lowest, -0.42, "裙板必须沉到水面以下，否则桥缘还是一条水缝")
	arena.free()

func test_bridge_piers_stay_below_the_deck() -> void:
	var arena := _arena()
	var crossing := _top_bridge_crossing()
	arena.call("_build_bridge", "top", crossing, Arena.BRIDGE_SPAN_EDGE)
	var piers := 0
	for child in arena._props_root.get_children():
		if not str(child.name).begins_with("bridge_pier_top"):
			continue
		piers += 1
		var pier := child as MeshInstance3D
		check(pier != null and pier.mesh is CylinderMesh, "桥墩必须是柱体")
		if pier != null and pier.mesh is CylinderMesh:
			var height := (pier.mesh as CylinderMesh).height
			var top := pier.position.y + height * 0.5
			lt(top, DECK_Y + 0.001, "桥墩顶面必须藏在桥面以下（现在高出 %.2fm）" % top)
			lt(pier.position.y - height * 0.5, 0.0, "桥墩必须扎到水面以下")
	eq(piers, 4, "一座桥四根桥墩")
	arena.free()

func test_bridge_approaches_meet_the_road_without_a_step() -> void:
	var arena := _arena()
	var crossing := _top_bridge_crossing()
	arena.call("_build_bridge", "top", crossing, Arena.BRIDGE_SPAN_EDGE)
	var ramps := 0
	for end in 2:
		var node := _find(arena, "ramp_top_%d" % end) as MeshInstance3D
		check(node != null, "桥端必须有接坡，否则桥面就是一块切在路上的板")
		if node == null:
			continue
		ramps += 1
		var verts := _vertices(node)
		var inner: Array = []
		var outer: Array = []
		for vertex in verts:
			if absf(vertex.y - DECK_Y) <= 0.005:
				inner.append(vertex)
			elif absf(vertex.y - ROAD_Y) <= 0.02:
				outer.append(vertex)
		gt(float(inner.size()), 1.0, "接坡的桥面侧必须有顶点")
		gt(float(outer.size()), 1.0, "接坡的路面侧必须有顶点")
		if inner.size() > 1:
			near(_max_span(inner), Arena.BRIDGE_WIDTH, 0.1, "接坡内侧必须正好接住桥面宽度")
		if outer.size() > 1:
			near(_max_span(outer), SHORE_WIDTH, 0.1, "接坡外侧必须收进路肩，不能比路还宽")
	eq(ramps, 2, "桥的两端都要有接坡")
	arena.free()

func _max_span(vertices: Array) -> float:
	var span := 0.0
	for i in vertices.size():
		for j in range(i + 1, vertices.size()):
			span = maxf(span, (vertices[i] as Vector3).distance_to(vertices[j]))
	return span

func test_mid_bridge_keeps_its_span_and_rail_direction() -> void:
	var arena := _arena()
	arena.call("_build_bridge", "mid", Vector2.ZERO, Arena.BRIDGE_SPAN_MID)
	var deck := _find(arena, "Bridge") as MeshInstance3D
	check(deck != null, "中路桥面存在")
	if deck == null:
		arena.free()
		return
	check(_covers(deck, Vector2.ZERO), "中路桥必须盖住河道中心")
	# 中路沿 (1,-1) 方向跨 26 米；垂直方向是桥宽。
	var along := Vector2(0.70710678, -0.70710678)
	var across := Vector2(0.70710678, 0.70710678)
	var reach := 0.0
	var half_width := 0.0
	for vertex in _vertices(deck):
		reach = maxf(reach, absf(Vector2(vertex.x, vertex.z).dot(along)))
		half_width = maxf(half_width, absf(Vector2(vertex.x, vertex.z).dot(across)))
	near(reach, Arena.BRIDGE_SPAN_MID * 0.5, 0.1, "中路桥长必须是 26m")
	near(half_width, Arena.BRIDGE_WIDTH * 0.5, 0.1, "中路桥宽必须是 10.6m")

	var rails := _find(arena, "bridge_rails_mid") as MultiMeshInstance3D
	check(rails != null, "中路桥必须有护栏")
	if rails != null:
		for transform in rails.get_meta("rail_transforms", []):
			if (transform as Transform3D).basis.get_scale().y > 0.7:
				continue
			var direction := Vector2(transform.basis.z.x, transform.basis.z.z).normalized()
			gt(absf(direction.dot(along)), 0.97, "护栏长边必须与桥面长边平行（转 90° 就会横在桥面上）")
	arena.free()

func test_bridge_corners_stay_inside_the_boundary_wall() -> void:
	# 边桥离边界墙只有 10 米出头：桥面贴着兵线走之后，任何一角都不能顶进墙里。
	var arena := _arena()
	var crossings: Array = MapLayout.lane_river_crossings()
	arena.call("_build_bridge", "mid", Vector2.ZERO, Arena.BRIDGE_SPAN_MID)
	for crossing in crossings:
		arena.call("_build_bridge", str(crossing.lane), crossing.pos, Arena.BRIDGE_SPAN_EDGE)
	var limit := MapLayout.boundary_inner() - 0.5
	var decks := 0
	for child in arena._props_root.get_children():
		var name := str(child.name)
		if name != "Bridge" and not name.begins_with("Bridge_"):
			continue
		decks += 1
		var deck := child as MeshInstance3D
		for vertex in _vertices(deck):
			lt(maxf(absf(vertex.x), absf(vertex.z)), limit,
				"%s 的角点 (%s) 顶进了边界墙" % [name, str(Vector2(vertex.x, vertex.z))])
	eq(decks, 3, "三路各一座桥：中路 + 上路 + 下路")
	arena.free()
