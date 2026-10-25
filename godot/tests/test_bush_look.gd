extends "res://tests/test_base.gd"

# 草丛观感契约（2026-10-25）
#
# 现象：草丛是 7 个墨绿色球体 + 一块半透明的绿色**正方形**，俯视像几个气球摆在一块绿玻璃上。
#
# 根因：
# 1. 球体没有叶片的轮廓、层次和透光，只能读成「绿色团块」。
# 2. 地面区域用 PlaneMesh（矩形）直接给了个 alpha 色块，四条直边在草地上非常刺眼。
#
# 契约：
# 1. 草丛由大量叶簇几何组成（不是 SphereMesh），叶片双面、有背光、根固定、叶尖随风摆。
# 2. 每片叶子有独立的颜色明暗，避免整丛一个色。
# 3. 地面只保留一圈**径向淡出**的柔和暗斑，不能出现方形边界。
# 4. 草丛高度要能藏住英雄下半身，但不能盖住头顶血条。

const Arena = preload("res://scripts/game/arena.gd")
const MapLayout = preload("res://sim/map/map_layout.gd")
const ModelUtils = preload("res://scripts/game/model_utils.gd")

const LEAF_SHADER := "res://shaders/bush_leaf.gdshader"
const FLOOR_SHADER := "res://shaders/bush_floor.gdshader"

func _arena_with_features() -> Node3D:
	var arena: Node3D = Arena.new()
	arena._props_root = Node3D.new()
	arena.add_child(arena._props_root)
	arena._build_map_features()
	return arena

func test_bushes_are_leaf_clusters_not_spheres() -> void:
	var arena := _arena_with_features()
	for bush in MapLayout.BUSHES:
		var node := arena._props_root.get_node_or_null(NodePath(str(bush.id))) as MeshInstance3D
		check(node != null, "草丛必须以 sim id 命名挂进场景：" + str(bush.id))
		if node == null:
			continue
		check(not (node.mesh is SphereMesh), "草丛不能再用球体拼：" + str(bush.id))
		var mesh := node.mesh as ArrayMesh
		check(mesh != null, "草丛网格应当是叶簇 ArrayMesh：" + str(bush.id))
		if mesh == null:
			continue
		var arrays := mesh.surface_get_arrays(0)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		gt(float(verts.size()), 2000.0, "叶簇数量不足，俯视会露出大片空隙：" + str(bush.id))
		check(
			(mesh.surface_get_format(0) & Mesh.ARRAY_FORMAT_COLOR) != 0,
			"叶簇必须带逐叶顶点色，否则整丛只有一个色：" + str(bush.id)
		)
	arena.free()

func test_bush_leaf_material_sways_rooted_and_lights_the_backside() -> void:
	var arena := _arena_with_features()
	var node := arena._props_root.get_node_or_null(NodePath(str(MapLayout.BUSHES[0].id))) as MeshInstance3D
	check(node != null, "草丛节点存在")
	if node:
		var material := node.material_override as ShaderMaterial
		check(material != null, "草丛必须用 ShaderMaterial 做风摆与透光")
		if material:
			check(material.shader != null, "材质上必须挂着 shader")
			if material.shader:
				eq(material.shader.resource_path, LEAF_SHADER, "叶片 shader 应独占一个文件")
				var code := material.shader.code
				check(code.contains("cull_disabled"), "叶片必须双面渲染，从背面看不能消失")
				check(code.contains("BACKLIGHT"), "叶片必须有背光透光，否则逆光是一团死黑")
				check(code.contains("UV.y"), "风摆权重必须来自叶片高度")
				check(code.contains("TIME"), "草丛要有轻微风摆，否则像塑料道具")
			var sway: float = material.get_shader_parameter("sway_amount")
			gt(sway, 0.0, "风摆幅度必须大于 0")
	arena.free()

func test_bush_floor_fades_radially_instead_of_a_square_tint() -> void:
	var arena := _arena_with_features()
	for bush in MapLayout.BUSHES:
		var node := arena._props_root.get_node_or_null(NodePath(str(bush.id) + "_floor")) as MeshInstance3D
		check(node != null, "草丛地面暗斑必须独立成节点：" + str(bush.id))
		if node == null:
			continue
		var plane := node.mesh as PlaneMesh
		check(plane != null, "地面暗斑仍然用 PlaneMesh 承载")
		if plane:
			near(plane.size.x, float(bush.radius) * 2.0, 0.6, "暗斑尺寸要覆盖草丛区域")
		var material := node.material_override as ShaderMaterial
		check(material != null, "地面暗斑必须用 shader 做径向淡出")
		if material and material.shader:
			eq(material.shader.resource_path, FLOOR_SHADER, "地面暗斑 shader 应独占一个文件")
			var code := material.shader.code
			check(code.contains("distance(UV"), "必须按 UV 到中心的距离计算透明度")
			check(code.contains("smoothstep"), "边缘必须柔化，不能出现方形硬边")
	arena.free()

func test_bush_height_hides_the_legs_but_not_the_health_bar() -> void:
	var arena := _arena_with_features()
	for bush in MapLayout.BUSHES:
		var node := arena._props_root.get_node_or_null(NodePath(str(bush.id))) as MeshInstance3D
		check(node != null, "草丛节点存在：" + str(bush.id))
		if node == null:
			continue
		var box := ModelUtils.relative_aabb(node)
		var radius := float(bush.radius)
		gt(box.size.y, 1.1, "草丛太矮就藏不住人：" + str(bush.id))
		lt(box.size.y, 1.9, "草丛高过头会盖住头顶血条：" + str(bush.id))
		# 叶簇外沿要铺满玩法半径，否则会出现「站在草边却没进草」的视觉错位。
		gt(box.size.x, radius * 1.4, "草丛视觉直径小于玩法直径：" + str(bush.id))
	arena.free()
