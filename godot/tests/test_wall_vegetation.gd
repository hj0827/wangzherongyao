extends "res://tests/test_base.gd"

# 墙脚植被（P0 视觉升级，WALL-01 的植被部分）。
#
# 旧版墙脚只有碎石，石壁像一条灰石头直接插进草地。现在沿墙脚铺草簇，
# 一个 MultiMesh 批次、不投影、不参与碰撞。

const Arena = preload("res://scripts/game/arena.gd")
const MapLayout = preload("res://sim/map/map_layout.gd")
const MapData = preload("res://sim/map_data.gd")

func _arena_with_props() -> Node3D:
	var arena: Node3D = Arena.new()
	arena._props_root = Node3D.new()
	arena.add_child(arena._props_root)
	arena._build_map_features()
	return arena

func test_wall_tufts_batch_exists_and_is_cheap() -> void:
	var arena := _arena_with_props()
	var node := arena._props_root.get_node_or_null(NodePath("wallfoot_grass")) as MultiMeshInstance3D
	check(node != null, "墙脚草必须是一个 MultiMesh 批次")
	if node == null:
		arena.free()
		return
	gt(float(node.multimesh.instance_count), 100.0, "墙脚草数量要够铺满全图")
	eq(node.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "墙脚草不投影")
	check(node.material_override is ShaderMaterial, "墙脚草用草地 shader（会随风摆）")
	arena.free()

func test_wall_tufts_sit_beside_walls_not_on_the_lane() -> void:
	var arena := _arena_with_props()
	var node := arena._props_root.get_node_or_null(NodePath("wallfoot_grass")) as MultiMeshInstance3D
	if node == null:
		check(false, "墙脚草批次必须存在")
		arena.free()
		return
	var points: Array = node.get_meta("tuft_points", [])
	var segments: Array = []
	for wall in MapLayout.WALLS:
		segments.append({"a": wall.a, "b": wall.b, "thick": MapLayout.WALL_THICKNESS})
	for wall in MapLayout.boundary_walls():
		segments.append({"a": wall.a, "b": wall.b, "thick": MapLayout.BOUNDARY_THICK})
	var checked := 0
	for i in mini(points.size(), 80):
		var point: Vector2 = points[i]
		var nearest := 999.0
		for seg in segments:
			var d := MapLayout.point_to_segment_distance(point, seg.a, seg.b)
			nearest = minf(nearest, d)
		# 墙与墙相交的转角处，草离另一段墙可能只有 0.3~0.7m；只要不在墙心即可。
		check(nearest >= 0.2, "草不能埋进墙体中心（%.2f）" % nearest)
		check(nearest <= 2.0, "草要贴着墙脚（%.2f）" % nearest)
		# 草簇不能落在兵线路面正中：墙本身离路面有净空，这里加一道保险。
		var lane_d := 999.0
		for lane in MapData.LANE_ORDER:
			for j in range(MapData.lane_path(lane).size() - 1):
				var path: Array = MapData.lane_path(lane)
				lane_d = minf(lane_d, MapLayout.point_to_segment_distance(point, path[j], path[j + 1]))
		gt(lane_d, MapData.LANE_HALF_WIDTH - 0.01, "墙脚草不能长在路面里（%.2f）" % lane_d)
		checked += 1
	gt(float(checked), 0.0, "至少要检查到一簇草")
	arena.free()
