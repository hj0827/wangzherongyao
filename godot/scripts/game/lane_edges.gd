extends RefCounted

# 路缘石。C17 拆分第四步：从 arena.gd 抽出三路路缘石的摆放与桥段让位。
#
# 用 MultiMesh：三路加起来一百多个石墩，逐个 MeshInstance3D 就是一百多个 draw call。
# 材质由调用方传入（石壁材质在 arena 里缓存，全图共用一份）。

const MapData = preload("res://sim/map_data.gd")
const MapView = preload("res://scripts/game/map_view.gd")
const LaneRoad = preload("res://scripts/game/lane_road.gd")
const BridgeBuilder = preload("res://scripts/game/bridge_builder.gd")

static func build(root: Node3D, stone: Material) -> void:
	var stones: Array = []
	var width := LaneRoad.surface_half_width() * 2.0
	for lane in MapData.LANE_ORDER:
		var path: Array = MapView.lane_path(lane)
		var windows := _arc_windows(str(lane), path)
		for stone_data in LaneRoad.edge_stones(path, width):
			# 桥上有自己的护栏。路缘石继续铺过去会和护栏叠成两条边，
			# 俯视看就是桥面镶了一圈牙 —— 桥段的路缘石必须让位。
			if _inside_window(float(stone_data.get("arc", 0.0)), windows):
				continue
			stones.append(stone_data)
	if stones.is_empty():
		return
	var box := BoxMesh.new()
	box.size = Vector3(2.05, 0.20, 0.42)
	var instance := MultiMeshInstance3D.new()
	instance.name = "road_edges"
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = box
	multimesh.instance_count = stones.size()
	for index in stones.size():
		var stone_data: Dictionary = stones[index]
		var pos: Vector2 = stone_data.pos
		var basis := Basis(Vector3.UP, float(stone_data.get("yaw", 0.0)))
		multimesh.set_instance_transform(index, Transform3D(basis, Vector3(pos.x, 0.08, pos.y)))
	instance.multimesh = multimesh
	instance.material_override = stone
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(instance)

# 路缘石要给谁让位：中路的桥面（桥有自己的护栏）。
# 边路 2026-10-28 起没有桥了 —— 角落改由广场铺石，广场里的路缘石在
# build() 里按 inside_corner_plaza 单独剔除。
# 以前这里也给边路跨河点开窗口，拆桥之后那个窗口会把广场外 5 米的路缘石一起剃掉，
# 留下一条没有石沿的路。
static func _arc_windows(lane: String, path: Array) -> Array:
	var entries: Array = []
	if lane == "mid":
		entries.append({"center": Vector2.ZERO, "half": BridgeBuilder.BRIDGE_SPAN_MID * 0.5})
	var windows: Array = []
	var total := LaneRoad.path_length(path)
	for entry in entries:
		var center := LaneRoad.nearest_arc(path, entry.center)
		var half := float(entry.half) + BridgeBuilder.BRIDGE_APPROACH + 0.5
		windows.append(Vector2(maxf(center - half, 0.0), minf(center + half, total)))
	return windows

static func _inside_window(arc: float, windows: Array) -> bool:
	for window in windows:
		if arc >= window.x and arc <= window.y:
			return true
	return false
