extends RefCounted

# 中路桥的几何与材质。C17 拆分第二步：从 arena.gd 抽出桥面 / 裙板 / 接坡 /
# 护栏 / 桥墩的构建，节点命名与数值逐位保持原样（测试按 Bridge* / bridge_* 数构件）。
#
# 桥面是**兵线路径截出来的一段连续带**，不是一块旋转 45° 的直板 ——
# 直板会把桥端斜着切进路面，护栏从路中间断开。

const LaneRoad = preload("res://scripts/game/lane_road.gd")
const MapView = preload("res://scripts/game/map_view.gd")
const ModelUtils = preload("res://scripts/game/model_utils.gd")

# 桥体尺寸。中路在河心（地图中心）。
const BRIDGE_WIDTH := 10.6
const BRIDGE_SPAN_MID := 26.0
const BRIDGE_SPAN_EDGE := 20.0
# 桥面高出路面 2cm：路面最上层 0.055，桥面 0.075。压低会被路面盖住，
# 抬高就会在桥头出现一道台阶。
const BRIDGE_DECK_Y := 0.075
# 桥头接坡：把桥面从 10.6m 收到路肩 9.75m，高度压到 0.05（低于路面 0.055 的一半），
# 接坡尾端直接沉进路面，接缝只有一条材质线，没有台阶。
const BRIDGE_APPROACH := 1.6
const BRIDGE_APPROACH_Y := 0.05
# 护栏：0.42m 高的矮栏，沿路缘弯过去；两端各一根门柱收口。
# 偏移 4.6 贴着桥面外沿（半宽 5.3）留 0.7m 走边，同时避开路面石墩（4.31）。
const BRIDGE_RAIL_OFFSET := 4.6
const BRIDGE_RAIL_WIDTH := 0.34
const BRIDGE_RAIL_HEIGHT := 0.42
const BRIDGE_RAIL_STEP := 1.7
const BRIDGE_RAIL_INSET := 0.9
const BRIDGE_POST_SIZE := 0.56
const BRIDGE_POST_HEIGHT := 0.95
const BRIDGE_POST_CAP := 0.74
const BRIDGE_POST_CAP_HEIGHT := 0.16
# 桥墩顶面必须低于桥面：旧版顶面在 0.4m，俯视就是桥面上多了几个圆饼。
const BRIDGE_PIER_HEIGHT := 2.2
const BRIDGE_PIER_TOP := 0.0
# 桥侧裙板落到水面（-0.42）以下，斜俯视时桥缘才不会露出水缝。
const BRIDGE_SKIRT_BOTTOM := -0.65

# 把整座桥挂到 root 下。label 是路名（mid / top / bottom），center/span 决定截取哪一段兵线。
static func build(root: Node3D, label: String, center: Vector2, span: float) -> void:
	var path: Array = LaneRoad.slice_around(MapView.lane_path(label), center, span * 0.5)
	if path.size() < 2:
		return
	var deck_mat := make_deck_material()
	var rail_mat := make_rail_material()

	var deck := MeshInstance3D.new()
	# 名字即接口：测试靠 Bridge* 数桥、验「跨河点真的落在桥面上」。
	deck.name = "Bridge" if label == "mid" else "Bridge_" + label
	deck.mesh = _deck_mesh(path)
	deck.material_override = deck_mat
	ModelUtils.enable_shadows(deck, true)
	root.add_child(deck)

	_build_skirt(root, label, path, deck_mat)
	_build_approaches(root, label, path, deck_mat)
	_build_rails(root, label, path, rail_mat)
	_build_piers(root, label, path, rail_mat)

static func make_deck_material() -> StandardMaterial3D:
	# 与石壁同一套 cliff AO：桥面和野区墙必须是同一种石头。
	var material := StandardMaterial3D.new()
	material.albedo_texture = load("res://assets/textures/cliff_side_AO.jpg")
	material.albedo_color = Color(0.48, 0.49, 0.50)
	material.normal_enabled = true
	material.normal_texture = load("res://assets/textures/cliff_side_nor_gl.jpg")
	material.normal_scale = 1.3
	material.roughness = 0.95
	# 连续带的 UV：横向 0..1 铺满桥宽，纵向按弧长（LaneRoad.UV_PER_METER）。
	# 这里按「接近方形」补比例，否则 AO 贴图会被拉成一条条。
	material.uv1_scale = Vector3(4.0, 3.0, 1.0)
	return material

static func make_rail_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_texture = load("res://assets/textures/cliff_side_AO.jpg")
	material.albedo_color = Color(0.56, 0.57, 0.58)
	material.normal_enabled = true
	material.normal_texture = load("res://assets/textures/cliff_side_nor_gl.jpg")
	material.normal_scale = 1.1
	material.roughness = 1.0
	material.uv1_scale = Vector3(2, 2, 2)
	return material

static func _deck_mesh(path: Array) -> ArrayMesh:
	var data := LaneRoad.ribbon(path, BRIDGE_WIDTH, BRIDGE_DECK_Y)
	var points: PackedVector3Array = data.points
	var uvs: PackedVector2Array = data.uvs
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for index in points.size():
		st.set_normal(Vector3.UP)
		st.set_uv(uvs[index])
		st.add_vertex(points[index])
	return st.commit()

# 桥侧裙板：桥面是一条没有厚度的连续带，斜俯视能直接从边缘看进水缝里，
# 读成「一块飘在河上的石板」。两侧沿桥缘落一道到水面以下的石壁，桥才有截面。
static func _build_skirt(root: Node3D, label: String, path: Array, material: Material) -> void:
	var skirt := MeshInstance3D.new()
	skirt.name = "bridge_skirt_" + label
	skirt.mesh = _skirt_mesh(path)
	skirt.material_override = material
	ModelUtils.enable_shadows(skirt, true)
	root.add_child(skirt)

static func _skirt_mesh(path: Array) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var half := BRIDGE_WIDTH * 0.5
	for side in [-1.0, 1.0]:
		var edge: Array = LaneRoad.offset_path(path, side * half)
		for index in edge.size() - 1:
			var a: Vector2 = edge[index]
			var b: Vector2 = edge[index + 1]
			var segment := a.distance_to(b)
			if segment < 0.0001:
				continue
			var direction := (b - a) / segment
			# 左缘的外法线是 (-dy, dx)，右缘反过来。
			var outward: Vector2 = Vector2(-direction.y, direction.x) * float(side)
			var normal := Vector3(outward.x, 0.0, outward.y)
			var quad := [
				Vector3(a.x, BRIDGE_DECK_Y, a.y),
				Vector3(b.x, BRIDGE_DECK_Y, b.y),
				Vector3(a.x, BRIDGE_SKIRT_BOTTOM, a.y),
				Vector3(b.x, BRIDGE_SKIRT_BOTTOM, b.y),
			]
			var quad_uv := [Vector2(0, 1), Vector2(1, 1), Vector2(0, 0), Vector2(1, 0)]
			# 与 lane_road.ribbon 同一套绕序：桥外侧看到的面，右手定则法线朝桥内。左右缘相反。
			var order := [0, 1, 2, 1, 3, 2] if side > 0.0 else [0, 2, 1, 1, 2, 3]
			for corner in order:
				st.set_normal(normal)
				st.set_uv(Vector2(quad_uv[corner].x * segment * LaneRoad.UV_PER_METER, quad_uv[corner].y))
				st.add_vertex(quad[corner])
	return st.commit()

# 桥头接坡：桥面 10.6 宽收成路肩 9.75 宽，高度从 0.075 压到 0.05（沉进路面）。
# 没有这一块，桥面就是在路上被刀切出来的一块板。
static func _build_approaches(root: Node3D, label: String, path: Array, material: Material) -> void:
	var deck_half := BRIDGE_WIDTH * 0.5
	var road_half := float(LaneRoad.layer_half_widths()[0])
	for end in 2:
		var index := 0 if end == 0 else path.size() - 1
		var neighbor := 1 if end == 0 else path.size() - 2
		var center: Vector2 = path[index]
		var direction := (center - (path[neighbor] as Vector2)).normalized()
		var normal := Vector2(-direction.y, direction.x)
		var outer := center + direction * BRIDGE_APPROACH
		var ramp := MeshInstance3D.new()
		ramp.name = "ramp_%s_%d" % [label, end]
		ramp.mesh = _ramp_mesh(
			center + normal * deck_half,
			center - normal * deck_half,
			outer + normal * road_half,
			outer - normal * road_half
		)
		ramp.material_override = material
		ramp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(ramp)

static func _ramp_mesh(inner_left: Vector2, inner_right: Vector2, outer_left: Vector2, outer_right: Vector2) -> ArrayMesh:
	var a_l := Vector3(inner_left.x, BRIDGE_DECK_Y, inner_left.y)
	var a_r := Vector3(inner_right.x, BRIDGE_DECK_Y, inner_right.y)
	var b_l := Vector3(outer_left.x, BRIDGE_APPROACH_Y, outer_left.y)
	var b_r := Vector3(outer_right.x, BRIDGE_APPROACH_Y, outer_right.y)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# 与 lane_road.ribbon 同一绕序：相机在上方，几何法线朝下 = 正面。
	# 但着色法线必须朝上 —— 用几何法线（朝下）会被当成背光面，整块接坡烤成黑的。
	for triangle in [[a_l, a_r, b_l], [a_r, b_r, b_l]]:
		var uv := 0.0
		for vertex in triangle:
			st.set_normal(Vector3.UP)
			st.set_uv(Vector2(uv, 0.0))
			st.add_vertex(vertex)
			uv += 1.0
	return st.commit()

# 护栏：沿路缘弯过去的一排矮栏，两端各一根门柱 + 石帽收口。
# 全部塞进一个 MultiMesh：一百多段，逐个 MeshInstance3D 就是一百多个 draw call。
static func _build_rails(root: Node3D, label: String, path: Array, material: Material) -> void:
	var transforms: Array[Transform3D] = []
	for side in [-1.0, 1.0]:
		var rail_path := LaneRoad.offset_path(path, side * BRIDGE_RAIL_OFFSET)
		var total := LaneRoad.path_length(rail_path)
		var start := BRIDGE_RAIL_INSET
		var finish := total - BRIDGE_RAIL_INSET
		if finish - start < 1.0:
			continue
		var steps := maxi(int(ceil((finish - start) / BRIDGE_RAIL_STEP)), 1)
		var step := (finish - start) / float(steps)
		for index in steps:
			var station := LaneRoad.sample(rail_path, start + step * (float(index) + 0.5))
			transforms.append(_box_transform(
				station.pos, station.dir,
				Vector3(BRIDGE_RAIL_WIDTH, BRIDGE_RAIL_HEIGHT, step + 0.06),
				BRIDGE_DECK_Y + BRIDGE_RAIL_HEIGHT * 0.5
			))
		for arc in [start, finish]:
			var station := LaneRoad.sample(rail_path, arc)
			transforms.append(_box_transform(
				station.pos, station.dir,
				Vector3(BRIDGE_POST_SIZE, BRIDGE_POST_HEIGHT, BRIDGE_POST_SIZE),
				BRIDGE_DECK_Y + BRIDGE_POST_HEIGHT * 0.5
			))
			transforms.append(_box_transform(
				station.pos, station.dir,
				Vector3(BRIDGE_POST_CAP, BRIDGE_POST_CAP_HEIGHT, BRIDGE_POST_CAP),
				BRIDGE_DECK_Y + BRIDGE_POST_HEIGHT + BRIDGE_POST_CAP_HEIGHT * 0.5
			))
	if transforms.is_empty():
		return
	var box := BoxMesh.new()
	box.size = Vector3.ONE
	var instance := MultiMeshInstance3D.new()
	instance.name = "bridge_rails_" + label
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = box
	multimesh.instance_count = transforms.size()
	for index in transforms.size():
		multimesh.set_instance_transform(index, transforms[index])
	instance.multimesh = multimesh
	# headless 的 dummy 渲染器读不回 MultiMesh 实例变换，测试只能靠这份记录量护栏走向。
	instance.set_meta("rail_transforms", transforms)
	instance.material_override = material
	ModelUtils.enable_shadows(instance, true)
	root.add_child(instance)

# 单位盒 + 朝向 dir 的长轴（局部 +Z）。缩放写进基里，MultiMesh 才能共用一个盒子。
static func _box_transform(pos: Vector2, heading: Vector2, size: Vector3, center_y: float) -> Transform3D:
	var yaw := atan2(heading.x, heading.y)
	var basis := Basis(Vector3.UP, yaw) * Basis.from_scale(size)
	return Transform3D(basis, Vector3(pos.x, center_y, pos.y))

static func _build_piers(root: Node3D, label: String, path: Array, material: Material) -> void:
	# 桥墩只做水下的支撑：顶面压到桥面以下，俯视时才不会在桥面上多出几个圆饼。
	var total := LaneRoad.path_length(path)
	var center := total * 0.5
	var index := 0
	for along in [-1.0, 1.0]:
		var station := LaneRoad.sample(path, center + along * total * 0.23)
		var normal := Vector2(-station.dir.y, station.dir.x)
		for side in [-1.0, 1.0]:
			var pos: Vector2 = station.pos + normal * 3.8 * side
			var pier := MeshInstance3D.new()
			pier.name = "bridge_pier_%s_%d" % [label, index]
			var cylinder := CylinderMesh.new()
			cylinder.top_radius = 0.52
			cylinder.bottom_radius = 0.66
			cylinder.height = BRIDGE_PIER_HEIGHT
			cylinder.radial_segments = 12
			pier.mesh = cylinder
			pier.material_override = material
			pier.position = Vector3(pos.x, BRIDGE_PIER_TOP - BRIDGE_PIER_HEIGHT * 0.5, pos.y)
			ModelUtils.enable_shadows(pier, true)
			root.add_child(pier)
			index += 1
