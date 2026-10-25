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
		check(box != null, "墙体网格应当是 BoxMesh")
		if box == null:
			continue
		near(box.size.y, MapLayout.WALL_HEIGHT, 0.001, "墙高必须等于 sim 常量：%s" % str(wall.id))
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

# ---------------------------------------------------------------- 壁柱
func test_every_jungle_wall_gets_buttresses_that_rise_above_the_coping() -> void:
	# 参考图上最显眼的节奏是**壁柱**：墙面每隔几米一根微凸方柱，
	# 柱顶一块小方帽，帽顶越出压顶石一条线。
	# 这不是「顶脊碎石」——碎石是自然岩体塌下来的样子，壁柱才是「人砌的城墙」。
	var arena: Node3D = Arena.new()
	arena._props_root = Node3D.new()
	arena.add_child(arena._props_root)
	arena._build_map_features()
	var stone: ShaderMaterial = arena._wall_stone_material()
	var groups := {}
	for child in arena._props_root.get_children():
		if not str(child.name).begins_with("buttress_"):
			continue
		var id := str((child as Node).get_meta("wall_id", ""))
		if id == "":
			continue
		if not groups.has(id):
			groups[id] = []
		(groups[id] as Array).append(child)
	for wall in MapLayout.WALLS:
		var id := str(wall.id)
		check(groups.has(id), "缺壁柱，这段墙读成一块水泥板：%s" % id)
		if not groups.has(id):
			continue
		var list: Array = groups[id]
		gt(float(list.size()), 1.0, "壁柱至少两根，一根读不出节奏：%s" % id)
		var body: MeshInstance3D = list[0] as MeshInstance3D
		var box: BoxMesh = body.mesh as BoxMesh
		check(box != null, "壁柱应当是 BoxMesh：%s" % id)
		if box == null:
			continue
		# 外挑：与墙面齐平的柱子等于不存在。
		gt(box.size.z, MapLayout.WALL_THICKNESS + 0.1, "壁柱没有外挑出墙面：%s" % id)
		lt(box.size.z, MapLayout.WALL_THICKNESS + 1.2, "壁柱外挑过多会变成一排墩子：%s" % id)
		# 柱身必须**越出墙顶**：那条起伏线才是城墙的识别特征。
		var body_top: float = body.position.y + box.size.y * 0.5
		gt(body_top, MapLayout.WALL_HEIGHT + 0.05, "柱身没有高过墙身：%s" % id)
		# 柱帽：压在最上面、比柱身更宽的一块薄板。
		var bodies := 0
		var caps := 0
		for node in list:
			var cap_box: BoxMesh = ((node as MeshInstance3D).mesh) as BoxMesh
			if cap_box == null:
				continue
			var kind := str((node as Node).get_meta("kind", ""))
			if kind == "cap":
				caps += 1
				gt(cap_box.size.x, box.size.x, "柱帽要比柱身宽，才读得出「压顶」")
				var cap_top: float = (node as Node3D).position.y + cap_box.size.y * 0.5
				lt(cap_top, MapLayout.WALL_TOP + 0.001, "柱帽高出了遮挡预算：%s" % id)
			elif kind == "body":
				bodies += 1
		eq(caps, bodies, "每根壁柱正好一块柱帽：%s" % id)
		# 壁柱和墙身是同一块料 —— 不同材质会变成「墙上贴了一排柱子」。
		for node in list:
			eq((node as MeshInstance3D).material_override, stone, "壁柱必须与墙身同材质：%s" % id)
	arena.free()

func test_buttress_spacing_is_even_because_it_is_masonry_not_scatter() -> void:
	# 跟「顶脊要抖」正好相反：壁柱是砌筑出来的，**等距才是对的**。
	# 抖动的壁柱读成「塌了一段」，等距的壁柱读成「一段城墙」。
	var arena: Node3D = Arena.new()
	arena._props_root = Node3D.new()
	arena.add_child(arena._props_root)
	arena._build_map_features()
	for wall in MapLayout.WALLS:
		var id := str(wall.id)
		var offsets: Array = []
		for child in arena._props_root.get_children():
			if not str(child.name).begins_with("buttress_"):
				continue
			if str((child as Node).get_meta("wall_id", "")) != id:
				continue
			if str((child as Node).get_meta("kind", "")) != "body":
				continue
			offsets.append(float((child as Node).get_meta("along", 0.0)))
		if offsets.size() < 3:
			continue
		offsets.sort()
		var gaps: Array = []
		for i in range(1, offsets.size()):
			gaps.append(float(offsets[i]) - float(offsets[i - 1]))
		var ratio: float = float(gaps.max()) / maxf(float(gaps.min()), 0.001)
		lt(ratio, 1.35, "壁柱间距要基本等距（最长/最短 = %.2f）：%s" % [ratio, id])
		# 而且不能密到变成一圈齿：间距必须大于 1.6 米。
		gt(float(gaps.min()), 1.6, "壁柱间距太小，会读成一排齿：%s" % id)
	arena.free()

func test_nothing_is_scattered_on_the_wall_crest() -> void:
	# 「墙顶撒碎石」是上一版用来破「水泥平顶」的办法，但那和参考图的
	# 砌石城墙是两套语言：一处是塌方，一处是砌筑。
	# 顶边现在由**压顶石 + 柱帽**负责，不再需要随机岩石。
	var source := FileAccess.get_file_as_string("res://scripts/game/arena.gd")
	check(not source.contains("\"ridge_"), "墙顶不该再撒碎石，顶边改由壁柱帽负责")
	check(not source.contains("\"crest_boundary_"), "边界墙顶不该再撒碎石")

func test_wall_foot_rocks_use_the_same_stone_material() -> void:
	# 墙脚那几块 Rock.glb 原本用 glb 自带的灰白材质，和石壁贴在一起像
	# 「石墙脚下摆了几颗土豆」。同材质才能读成同一块山体塌下来的碎块。
	var arena: Node3D = Arena.new()
	arena._props_root = Node3D.new()
	arena.add_child(arena._props_root)
	arena._build_map_features()
	var stone: ShaderMaterial = arena._wall_stone_material()
	var found := 0
	for wall in MapLayout.WALLS:
		for i in 16:
			var rock: Node3D = arena._props_root.get_node_or_null(NodePath("footrock_%s_%d" % [str(wall.id), i]))
			if rock == null:
				continue
			found += 1
			for node in rock.find_children("*", "MeshInstance3D", true, false):
				var mesh_instance := node as MeshInstance3D
				if mesh_instance.mesh == null:
					continue
				for surface in mesh_instance.mesh.get_surface_count():
					eq(mesh_instance.get_surface_override_material(surface), stone, "墙脚石必须与墙身同材质")
	gt(float(found), 20.0, "墙脚石要逐块命名为 footrock_<id>_<i>，遮挡与测试都靠名字找人")
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
		if not (child is MeshInstance3D):
			continue
		var node_name := str(child.name)
		if not _is_stone_part(node_name):
			continue
		var material := (child as MeshInstance3D).material_override
		if material is ShaderMaterial:
			stone_ids[material.get_instance_id()] = true
			if node_name.begins_with("wall_") and not node_name.begins_with("wall_end_"):
				barrier_count += 1
	gt(float(barrier_count), 7.0, "至少 8 段野区墙要吃到石壁材质")
	eq(stone_ids.size(), 1, "全图石壁只能有一份材质：混用会变成一处石头一处木板")
	arena.free()

# 墙体名下的所有部件：墙身 / 压顶石 / 壁柱与柱帽 / 墙脚石 / 墙端露头。
func _is_stone_part(node_name: String) -> bool:
	for prefix in ["wall_end_", "wall_", "coping_", "buttress_", "footrock_"]:
		if node_name.begins_with(prefix):
			return true
	return false
