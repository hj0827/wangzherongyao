extends "res://tests/test_base.gd"

# 墙体中段岩石变体（P1 WALL-01 的第二部分）。
# 不替换 wall_rocks 的契约批次，只叠加一批更低/更窄的 Rock_Group 轮廓。

const Arena = preload("res://scripts/game/arena.gd")
const MapLayout = preload("res://sim/map/map_layout.gd")

func test_wall_ridge_variants_exist_and_stay_low() -> void:
	var arena: Node3D = Arena.new()
	arena._props_root = Node3D.new()
	arena.add_child(arena._props_root)
	arena._build_map_features()
	var node := arena._props_root.get_node_or_null(NodePath("wall_ridge_variants")) as MultiMeshInstance3D
	check(node != null, "墙中段变体必须合成一个 MultiMesh 批次")
	if node == null:
		arena.free()
		return
	gt(float(node.multimesh.instance_count), 20.0, "变体数量要够打散重复")
	eq(node.material_override, arena._wall_stone_material(), "变体必须与墙身同材质")
	var specs: Array = node.get_meta("rock_specs", [])
	gt(float(specs.size()), 20.0, "变体要带逐块元数据")
	for spec in specs:
		eq(str(spec.get("kind", "")), "variant", "只允许 variant 类型")
		lt(float(spec.get("height", 0.0)), MapLayout.WALL_TOP, "变体不能高过墙顶预算")
		gt(float(spec.get("height", 0.0)), MapLayout.WALL_CORE_HEIGHT, "变体要高出基座")
	arena.free()
