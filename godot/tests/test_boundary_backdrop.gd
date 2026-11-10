extends "res://tests/test_base.gd"

# 边界外背景岩峰（P1 WALL-04 第一版）。
# 不动碰撞/遮挡预算，只在边界外侧加更高的岩体，让墙后读成山体而不是空天。

const Arena = preload("res://scripts/game/arena.gd")
const MapLayout = preload("res://sim/map/map_layout.gd")

func test_boundary_backdrop_exists_outside_the_walkable_area() -> void:
	var arena: Node3D = Arena.new()
	arena._props_root = Node3D.new()
	arena.add_child(arena._props_root)
	arena._build_boundary_walls()
	var node := arena._props_root.get_node_or_null(NodePath("boundary_backdrop")) as MultiMeshInstance3D
	check(node != null, "边界外必须有背景岩峰批次")
	if node == null:
		arena.free()
		return
	gt(float(node.multimesh.instance_count), 20.0, "背景岩峰数量要够形成山体")
	eq(node.material_override, arena._wall_stone_material(false), "背景岩峰用自然岩壁材质")
	var inner := MapLayout.boundary_inner()
	for spec in node.get_meta("rock_specs", []):
		var pos: Vector2 = spec.get("pos", Vector2.ZERO)
		check(absf(pos.x) > inner or absf(pos.y) > inner, "背景岩峰必须在可走边界之外")
		gt(float(spec.get("height", 0.0)), MapLayout.BOUNDARY_TOP, "背景岩峰要高过墙顶")
	arena.free()
