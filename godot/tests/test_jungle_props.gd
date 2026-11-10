extends "res://tests/test_base.gd"

# 野区环境道具（P0 SCENE-01 第二部分）。
# 石碑/符文/兽骨走 3 个 MultiMesh 批次，不再每个野点 5 个 MeshInstance。

const Arena = preload("res://scripts/game/arena.gd")
const MapLayout = preload("res://sim/map/map_layout.gd")

func _arena() -> Node3D:
	var arena: Node3D = Arena.new()
	arena._props_root = Node3D.new()
	arena.add_child(arena._props_root)
	arena._build_map_features()
	return arena

func test_jungle_props_use_three_batches() -> void:
	var arena := _arena()
	var steles := arena._props_root.get_node_or_null("jungle_steles") as MultiMeshInstance3D
	var runes := arena._props_root.get_node_or_null("jungle_runes") as MultiMeshInstance3D
	var bones := arena._props_root.get_node_or_null("jungle_bones") as MultiMeshInstance3D
	check(steles != null and runes != null and bones != null, "石碑/符文/兽骨各要一个批次")
	if steles == null or runes == null or bones == null:
		arena.free()
		return
	gt(float(steles.multimesh.instance_count), 8.0, "至少 8 个野点/首领坑要有石碑")
	eq(runes.multimesh.instance_count, steles.multimesh.instance_count, "符文数量与石碑一致")
	eq(bones.multimesh.instance_count, steles.multimesh.instance_count * 3, "每处三根兽骨")
	arena.free()

func test_jungle_props_stay_off_lanes_and_ground_marks() -> void:
	var arena := _arena()
	var steles := arena._props_root.get_node_or_null("jungle_steles") as MultiMeshInstance3D
	if steles == null:
		check(false, "石碑批次必须存在")
		arena.free()
		return
	var specs: Array = steles.get_meta("prop_specs", [])
	gt(float(specs.size()), 0.0, "石碑要带逐点元数据")
	for spec in specs:
		var point: Vector2 = spec.pos
		gt(arena._lane_distance(point), 5.0, "野区道具不能压兵线（%.2f）" % arena._lane_distance(point))
		check(not MapLayout.on_ground_mark(point, 0.1), "野区道具不能压在营地/首领坑贴地盘上")
	arena.free()
