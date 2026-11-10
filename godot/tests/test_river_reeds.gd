extends "res://tests/test_base.gd"

# 河岸芦苇（P1 SCENE-02 的第一版）。
# 沿河道两岸（x = z）铺高草簇，避开兵线、桥心与营地；单批次、不投影。

const Arena = preload("res://scripts/game/arena.gd")

func test_river_reeds_exist_and_sit_on_the_banks() -> void:
	var arena: Node3D = Arena.new()
	arena._props_root = Node3D.new()
	arena.add_child(arena._props_root)
	arena._build_map_features()
	var node := arena._props_root.get_node_or_null(NodePath("river_reeds")) as MultiMeshInstance3D
	check(node != null, "河岸芦苇必须是一个 MultiMesh 批次")
	if node == null:
		arena.free()
		return
	gt(float(node.multimesh.instance_count), 20.0, "芦苇数量要够形成河岸带")
	eq(node.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "芦苇不投影")
	check(node.material_override is ShaderMaterial, "芦苇用草地 shader")
	var points: Array = node.get_meta("reed_points", [])
	gt(float(points.size()), 20.0, "芦苇要带逐株位置")
	for point in points:
		var p: Vector2 = point
		var river_d := absf(p.x - p.y) * 0.70710678
		check(river_d >= 8.5 and river_d <= 13.0, "芦苇要长在岸线附近（%.2f）" % river_d)
		gt(arena._lane_distance(p), 4.0, "芦苇不能长进兵线路面")
		gt(p.length(), 12.0, "芦苇不能长到桥心/地图中心")
	arena.free()
