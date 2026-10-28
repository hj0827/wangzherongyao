extends "res://tests/test_base.gd"

# 石壁观感契约（2026-10-25）
#
# 现象：野区墙加好以后，画面上是一块块**木板** —— 长条形的深褐色等距横纹、
# 上下两条平行亮带，完全没有石头该有的重量。
#
# 真因不是贴图选错，而是 `BoxMesh` 的 UV 是「每面 0..1」：
# 一条 16 米长的墙把 1024px 的岩壁贴图横向拉成一格 16 米宽，
# 沉积岩的水平层理被拉成等距横线，叠上赭黄砂岩的暖色，就读成了木纹。
#
# 契约：
# 1. 墙体走**世界空间三平面投影**：贴图密度按「米」算，与墙长无关。
# 2. 赭黄砂岩必须去饱和 + 冷调，否则怎么调亮度都是木头色。
# 3. 墙顶要长草。俯视机位下顶面是最常被看见的面，那一道草绿顶边是「石壁」的唯一线索。
# 4. 野区墙与边界墙共用同一份材质，不能一处石头一处木板。
# 5. 尺寸仍然只从 sim 层常量取：看得见的厚度 == 挡人的厚度。

const Arena = preload("res://scripts/game/arena.gd")
const ArenaLook = preload("res://scripts/game/arena_look.gd")
const MapLayout = preload("res://sim/map/map_layout.gd")

const SHADER_PATH := "res://shaders/rock_wall.gdshader"
const ALBEDO_TEX := "res://assets/textures/cliff_side_Diffuse.jpg"
const NORMAL_TEX := "res://assets/textures/cliff_side_nor_gl.jpg"

func test_rock_wall_material_is_a_world_space_triplanar_shader() -> void:
	var material := ArenaLook.rock_wall_material()
	check(material is ShaderMaterial, "石壁要用 ShaderMaterial：StandardMaterial3D 没有去饱和与投影缩放的能力")
	if not (material is ShaderMaterial):
		return
	var shader := (material as ShaderMaterial).shader
	check(shader != null, "材质上必须挂着 shader")
	if shader == null:
		return
	eq(shader.resource_path, SHADER_PATH, "石壁 shader 应该独占一个文件，方便单测与复用")
	var code := shader.code
	# 世界坐标重建（MODEL_MATRIX * VERTEX）是三平面投影的前提；
	# 没有它就只能退回 mesh UV，而那正是「被拉成木板」的原因。
	check(code.contains("MODEL_MATRIX"), "shader 必须从世界坐标取贴图，不能依赖 mesh UV")
	check(code.contains("world_pos"), "shader 必须把世界坐标传给片元阶段")
	# 三个投影平面都要采样：缺一个就会在某些朝向上糊成一色。
	check(code.contains("tile_size"), "必须有一个按米计的贴图密度参数")

func test_shader_parameters_encode_the_stone_look() -> void:
	var material := ArenaLook.rock_wall_material()
	var albedo: Variant = material.get_shader_parameter("albedo_tex")
	check(albedo is Texture2D, "必须挂上岩壁漫反射贴图")
	if albedo is Texture2D:
		eq((albedo as Texture2D).resource_path, ALBEDO_TEX, "岩壁贴图来源要明确")
	check(material.get_shader_parameter("normal_tex") is Texture2D, "没有法线贴图，岩面会是一块平色板")
	check(material.get_shader_parameter("roughness_tex") is Texture2D, "粗糙度贴图决定石头和塑料的区别")

	# 贴图密度：一格贴图覆盖多少米。2~6 米是「一层岩壁块面」的合理尺度；
	# 小于 2 米石头碎成砂，大于 6 米又回到「一大片拉伸的纹理」。
	var tile: float = material.get_shader_parameter("tile_size")
	near(tile, clampf(tile, 2.0, 6.0), 0.001, "tile_size 必须在 2~6 米之间，当前 %.2f" % tile)

	# 去饱和：赭黄砂岩的色相是「木头」的直接来源。低于 0.6 就还是暖褐。
	var desat: float = material.get_shader_parameter("desaturate")
	gt(desat, 0.6, "贴图必须被拉到接近中性灰，否则一眼看过去就是木头")

	# 冷灰而不是暖褐：三通道差值必须小，且偏冷（蓝分量不低于红分量太多）。
	var tint: Color = material.get_shader_parameter("rock_tint")
	var spread: float = maxf(maxf(tint.r, tint.g), tint.b) - minf(minf(tint.r, tint.g), tint.b)
	lt(spread, 0.08, "岩石色应当接近中性，当前通道差 %.3f" % spread)
	gt(tint.b, tint.r - 0.02, "岩石要偏冷，红分量不该压过蓝分量")

	# 脊顶压暗：朝上的面在阳光下最亮，一条 16 米长的亮头顶边读起来就是
	# 「墙顶铺好的走道」。压沉它，顶面才像长着土和草的山脊。
	var crest: float = material.get_shader_parameter("crest_darken")
	lt(crest, 0.8, "墙顶必须比立面沉，当前 crest_darken=%.2f" % crest)
	gt(crest, 0.4, "墙顶压太黑会变成一条黑边，当前 crest_darken=%.2f" % crest)

	# 墙顶长草：俯视下顶面最常被看见，草绿顶边是读成「石壁」的关键。
	# 但也**不能是一整片草坪** —— moss 到 0.8 时顶面就是一块绿毯子，
	# 石头一点不露，反而比平顶更假。0.30~0.60 之间才是「石头上长了草」。
	var moss: float = material.get_shader_parameter("moss_amount")
	gt(moss, 0.3, "墙顶必须带草，当前 moss_amount=%.2f" % moss)
	lt(moss, 0.6, "草不能盖满顶面，必须露出石头，当前 moss_amount=%.2f" % moss)
	var moss_color: Color = material.get_shader_parameter("moss_color")
	gt(moss_color.g, moss_color.r, "草色要偏绿")
	gt(moss_color.g, moss_color.b, "草色要偏绿")

func test_every_jungle_wall_gets_a_named_barrier_with_sim_dimensions() -> void:
	var arena: Node3D = Arena.new()
	arena._props_root = Node3D.new()
	arena.add_child(arena._props_root)
	arena._build_map_features()
	var root: Node3D = arena._props_root
	for wall in MapLayout.WALLS:
		var node: Node = root.get_node_or_null(NodePath("wall_" + str(wall.id)))
		check(node != null, "墙体应当以 wall_<id> 命名挂进场景，测试与遮挡逻辑都靠这个名字找人")
		if node == null:
			continue
		var box := (node as MeshInstance3D).mesh as BoxMesh
		check(box != null, "墙体基座应当是 BoxMesh")
		if box == null:
			continue
		near(box.size.y, MapLayout.WALL_CORE_HEIGHT, 0.001, "基座高度必须等于 sim 常量：%s" % str(wall.id))
		near(box.size.z, MapLayout.WALL_THICKNESS, 0.001, "可视化厚度必须等于碰撞厚度：%s" % str(wall.id))
		near(box.size.x, (wall.a as Vector2).distance_to(wall.b), 0.01, "墙长必须等于两个端点距离")
	arena.free()

# ---------------------------------------------------------------- 砖缝
func test_shader_lays_staggered_masonry_courses() -> void:
	# 参考图里的城墙是一块块**砌**出来的：横向分层、竖向错缝、缝里发暗。
	# 只换贴图做不到 —— 三平面投影的岩壁纹理是「自然崖面」，没有一块砖的边界，
	# 16 米长的墙永远读成「一根灰色的原木」。
	# 契约：shader 用世界坐标铺一层错缝砖格，砖层高度按米给，与墙长无关。
	var material := ArenaLook.rock_wall_material()
	var course: float = material.get_shader_parameter("brick_course")
	var brick: float = material.get_shader_parameter("brick_length")
	# 一层砖 0.35~0.9 米：低于 0.35 是砖墙贴纸（12 米墙要铺 34 层），
	# 高于 0.9 只剩两三层，读不出「砌块」。
	gt(course, 0.35, "砖层太薄，会糊成细密横纹：%.2f" % course)
	lt(course, 0.9, "砖层太厚，一面墙只剩两三层：%.2f" % course)
	gt(brick, 0.7, "单块砖太短，会变成马赛克：%.2f" % brick)
	lt(brick, 2.2, "单块砖太长，错缝看不出来：%.2f" % brick)
	# 缝宽必须窄。宽过 0.09 米在 20 米机位下就是一张黑网格。
	var mortar: float = material.get_shader_parameter("mortar_width")
	gt(mortar, 0.004, "没有砖缝就还是一整块：%.3f" % mortar)
	lt(mortar, 0.09, "砖缝太宽会变成格子布：%.3f" % mortar)
	# 缝要比砖面暗，但不能黑成网格。
	var darken: float = material.get_shader_parameter("mortar_darken")
	gt(darken, 0.35, "砖缝压太黑：%.2f" % darken)
	lt(darken, 0.85, "砖缝不够暗，砌块边界看不出来：%.2f" % darken)
	var code: String = (material.shader as Shader).code
	check(code.contains("brick_course"), "shader 必须真的用上砖层高度")
	check(code.contains("fract"), "错缝靠取小数部分实现，缺了它砖缝会连成一条直线")

# ---------------------------------------------------------------- 岩脊
func _rock_batch(arena: Node3D, node_name: String) -> MultiMeshInstance3D:
	return arena._props_root.get_node_or_null(NodePath(node_name)) as MultiMeshInstance3D

func _rock_specs(arena: Node3D, node_name: String) -> Array:
	var batch := _rock_batch(arena, node_name)
	if batch == null:
		return []
	return batch.get_meta("rock_specs", [])

func test_every_jungle_wall_gets_an_irregular_rock_ridge() -> void:
	# 直方盒墙身 + 等距壁柱在俯视下是「一圈规整城墙」，四角尤其方。
	# 现在的识别特征是基座上方那条高低错落、朝向随机的岩脊。
	# 岩脊与墙脚石合并在 wall_rocks 一个 MultiMesh 里，逐个实例的元数据在 rock_specs。
	var arena: Node3D = Arena.new()
	arena._props_root = Node3D.new()
	arena.add_child(arena._props_root)
	arena._build_map_features()
	var stone: ShaderMaterial = arena._wall_stone_material()
	var batch := _rock_batch(arena, "wall_rocks")
	check(batch != null, "野区岩脊必须合成一个 MultiMesh 批次，不能再逐块建节点")
	if batch == null:
		arena.free()
		return
	eq(batch.material_override, stone, "整批岩脊必须与基座同材质")
	eq(batch.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "移动端最重的这批墙石不参与阴影 pass")
	var mesh: Mesh = batch.multimesh.mesh
	var groups := {}
	for spec in _rock_specs(arena, "wall_rocks"):
		if str(spec.get("kind", "")) != "ridge":
			continue
		var id := str(spec.get("wall_id", ""))
		if id == "":
			continue
		if not groups.has(id):
			groups[id] = []
		(groups[id] as Array).append(spec)
	for wall in MapLayout.WALLS:
		var id := str(wall.id)
		check(groups.has(id), "缺岩脊，这段墙又会读成一块方盒：%s" % id)
		if not groups.has(id):
			continue
		var list: Array = groups[id]
		gt(float(list.size()), 2.0, "岩脊至少三块，一块盖不住直顶边：%s" % id)
		var shortest := INF
		var tallest := -INF
		for spec in list:
			var height := float(spec.get("height", 0.0))
			var world_box: AABB = (spec.transform as Transform3D) * mesh.get_aabb()
			near(world_box.size.y, height, 0.05, "MultiMesh 实例的实际高度必须等于 spec 高度：%s" % id)
			gt(height, float(MapLayout.WALL_CORE_HEIGHT) + 0.1, "岩脊要高出基座：%s" % id)
			lt(height, MapLayout.WALL_TOP + 0.001, "岩脊高出了遮挡预算：%s" % id)
			shortest = minf(shortest, height)
			tallest = maxf(tallest, height)
		gt(tallest - shortest, 0.25, "岩脊高低必须有变化，等高的石头会读成一排齿：%s" % id)
	arena.free()

func test_wall_ridge_rocks_stay_inside_the_collision_footprint() -> void:
	# 岩脊只是视觉，不能比碰撞体宽出一大截：玩家会看到自己「走进石头里」。
	# 墙体碰撞半厚 0.8，英雄半径 0.55 → 人最多贴到离墙心 1.35 米。
	# 这里按 MultiMesh 每块实例的**真实顶点**算到墙线的最大距离。
	var walls := {}
	for wall in MapLayout.WALLS:
		walls[str(wall.id)] = wall
	var arena: Node3D = Arena.new()
	arena._props_root = Node3D.new()
	arena.add_child(arena._props_root)
	arena._build_map_features()
	var batch := _rock_batch(arena, "wall_rocks")
	if batch == null:
		check(false, "野区岩脊批次必须存在")
		arena.free()
		return
	var mesh: Mesh = batch.multimesh.mesh
	var limit := MapLayout.WALL_THICKNESS * 0.5 + 0.55 + 0.06
	for spec in _rock_specs(arena, "wall_rocks"):
		if str(spec.get("kind", "")) != "ridge":
			continue
		var wall: Dictionary = walls.get(str(spec.get("wall_id", "")), {})
		if wall.is_empty():
			continue
		var xform: Transform3D = spec.transform
		var furthest := 0.0
		for surface in mesh.get_surface_count():
			var arrays := mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			for vertex in vertices:
				var world: Vector3 = xform * vertex
				var distance := MapLayout.point_to_segment_distance(Vector2(world.x, world.z), wall.a, wall.b)
				furthest = maxf(furthest, distance)
		lt(furthest, limit, "岩脊伸进了英雄贴墙的位置：%s_%d（%.2f 米）" % [str(wall.id), int(spec.get("along", 0.0)), furthest])
	arena.free()

func test_jungle_walls_no_longer_build_buttresses_or_coping() -> void:
	# 等距壁柱 / 外挑压顶是上一版「砌筑城墙」的语言；用户反馈仍然太方。
	# 现在这些部件全部删掉，只保留低基座 + 岩脊，防止以后又被加回来。
	var source := FileAccess.get_file_as_string("res://scripts/game/arena.gd")
	check(not source.contains("\"buttress_"), "野区墙不该再有等距壁柱")
	check(not source.contains("\"coping_"), "野区墙/边界墙不该再有直压顶")
	check(not source.contains("_build_buttress"), "壁柱构建函数应当整段移除")

func test_wall_foot_rocks_use_the_same_stone_material() -> void:
	# 墙脚那几块 Rock.glb 原本用 glb 自带的灰白材质，和石壁贴在一起像
	# 「石墙脚下摆了几颗土豆」。同材质才能读成同一块山体塌下来的碎块。
	# 同时守住「每段墙至少 4 块、左右两侧都有」：这是把直墙脚啃成参差石根的关键。
	var arena: Node3D = Arena.new()
	arena._props_root = Node3D.new()
	arena.add_child(arena._props_root)
	arena._build_map_features()
	var stone: ShaderMaterial = arena._wall_stone_material()
	var batch := _rock_batch(arena, "wall_rocks")
	if batch == null:
		check(false, "墙脚石必须并入 wall_rocks 批次")
		arena.free()
		return
	eq(batch.material_override, stone, "墙脚石必须与墙身同材质")
	var groups := {}
	for spec in _rock_specs(arena, "wall_rocks"):
		if str(spec.get("kind", "")) != "footrock":
			continue
		var id := str(spec.get("wall_id", ""))
		if id == "":
			continue
		if not groups.has(id):
			groups[id] = []
		(groups[id] as Array).append(spec)
	for wall in MapLayout.WALLS:
		var id := str(wall.id)
		check(groups.has(id), "每段墙都要有墙脚石：%s" % id)
		if not groups.has(id):
			continue
		var list: Array = groups[id]
		gt(float(list.size()), 3.0, "每段墙至少 4 块墙脚石：%s" % id)
		var plus := 0
		var minus := 0
		var axis: Vector2 = (wall.b as Vector2) - (wall.a as Vector2)
		var perp := Vector2(-axis.y, axis.x).normalized()
		for spec in list:
			var side: float = ((spec.pos as Vector2) - (wall.a as Vector2)).dot(perp)
			if side >= 0.0:
				plus += 1
			else:
				minus += 1
		gt(float(plus), 0.0, "墙脚石必须左右两侧都有（右）：%s" % id)
		gt(float(minus), 0.0, "墙脚石必须左右两侧都有（左）：%s" % id)
	arena.free()

func test_jungle_and_boundary_walls_share_one_material() -> void:
	# 只看墙体名下的节点。场景里还有草丛（BushField）等其它 ShaderMaterial，
	# 早先按「凡是 ShaderMaterial」统计，草丛一改成 shader，这条就误报 3 份材质。
	var arena: Node3D = Arena.new()
	arena._props_root = Node3D.new()
	arena.add_child(arena._props_root)
	arena._build_map_features()
	arena._build_boundary_walls()
	var stone_ids := {}
	var barrier_count := 0
	for child in arena._props_root.get_children():
		if not (child is MeshInstance3D or child is MultiMeshInstance3D):
			continue
		var node_name := str(child.name)
		if not _is_stone_part(node_name):
			continue
		var material: Material = null
		if child is MultiMeshInstance3D:
			material = (child as MultiMeshInstance3D).material_override
		else:
			material = (child as MeshInstance3D).material_override
		if material is ShaderMaterial:
			stone_ids[material.get_instance_id()] = true
			if node_name.begins_with("wall_") and not node_name.begins_with("wall_end_"):
				barrier_count += 1
	gt(float(barrier_count), 7.0, "至少 8 段野区墙要吃到石壁材质")
	eq(stone_ids.size(), 1, "全图石壁只能有一份材质：混用会变成一处石头一处木板")
	arena.free()

# 墙体名下的所有部件：基座 / 岩脊批次 / 墙端露头 / 边界角岩。
func _is_stone_part(node_name: String) -> bool:
	for prefix in ["wall_end_", "wall_", "wall_rocks", "boundary_rocks", "ridge_", "corner_rock_", "footrock_", "rubble_"]:
		if node_name.begins_with(prefix):
			return true
	return false
