extends "res://tests/test_base.gd"

# 基地水晶美术二轮（2026-11-12 下午）：能量外壳 / 环 / 晶屑 / 光柱 / 护盾 / 台基。
#
# 这一组只抓「新增的观感有没有真的接上、会不会静默失效」，不抓像素；
# 像素由 tools/crystal_gallery.gd 出图人工对照。
#
# 四条最容易静默失效的地方，逐条钉住：
#   1. ShaderMaterial 不在 OcclusionFade 的作用面里 —— 外壳会贴脸不淡；
#   2. shader 里的状态量藏在 TIME 里 —— 无头测不到「残血真的暗了」；
#   3. 内置常量重定义 —— 编译失败后材质回落纯白，headless 全绿（首版 portal 踩过）；
#   4. 新部件只写了 build 没写 apply_state —— 又是一个「文件在、没人调」。

const Arena = preload("res://scripts/game/arena.gd")
const CrystalVisual = preload("res://scripts/game/crystal_visual.gd")
const Occlusion = preload("res://scripts/game/occlusion_fade.gd")

func _blue() -> Dictionary:
	return CrystalVisual.build(Arena.BLUE, "blue")

func _source(path: String) -> String:
	return FileAccess.get_file_as_string(path)

# ---------------- 能量外壳 ----------------

func test_energy_shell_reuses_the_gem_geometry_and_draws_after_it() -> void:
	var state := _blue()
	var shell := state.node.find_child("gem_energy", true, false) as MeshInstance3D
	check(shell != null, "必须建出 gem_energy 能量外壳")
	if shell == null:
		state.node.free()
		return
	check(shell.mesh == (state.gem as MeshInstance3D).mesh, "外壳必须复用 gem 网格，不新建几何")
	var material := shell.material_override as ShaderMaterial
	check(material != null, "外壳必须挂 ShaderMaterial")
	if material:
		eq(material.render_priority, 3, "外壳 render_priority 必须夹在 gem(2) 与裂纹(4) 之间")
	gt(shell.scale.x, 1.0, "外壳要略大于晶体，否则共面 z-fighting")
	lt(shell.scale.x, 1.10, "外壳不能胖成一圈雾")
	state.node.free()

func test_energy_shell_state_is_driven_by_gdscript_not_hidden_in_time() -> void:
	var state := _blue()
	var material := state.gem_energy_material as ShaderMaterial
	for key in ["phase", "intensity", "damage", "fade_alpha"]:
		check(material.get_shader_parameter(key) != null, "外壳 shader 缺状态量：%s" % key)
	CrystalVisual.apply_state(state, 0.0)
	var t0 := float(material.get_shader_parameter("phase"))
	CrystalVisual.apply_state(state, 0.5)
	gt(float(material.get_shader_parameter("phase")), t0, "phase 必须由 apply_state 推进")
	CrystalVisual.apply_damage(state, 0.10)
	CrystalVisual.apply_state(state, 0.0)
	gt(float(material.get_shader_parameter("damage")), 0.5, "残血必须传进外壳 shader")
	lt(float(material.get_shader_parameter("intensity")), 1.0, "残血外壳亮度必须收")
	state.node.free()

func test_energy_shell_follows_the_occlusion_fade() -> void:
	# 回归重点：ShaderMaterial 不在 OcclusionFade 作用面里，不专门同步的话
	# 英雄贴脸时柱身/晶体都淡了，只剩一圈加色亮边糊在屏幕上。
	var state := _blue()
	var material := state.gem_energy_material as ShaderMaterial
	var names: Array[String] = []
	for part in state.fade_parts:
		names.append(str((part as Node).name))
	check(not names.has("gem_energy"), "ShaderMaterial 不该进 OcclusionFade 的 StandardMaterial3D 名单")
	Occlusion.set_part_alpha(state.gem, Occlusion.MIN_VISIBLE)
	CrystalVisual.apply_state(state, 0.0)
	near(float(material.get_shader_parameter("fade_alpha")), Occlusion.MIN_VISIBLE, 0.0001,
			"主体淡到下限后，外壳必须一起淡")
	Occlusion.set_part_alpha(state.gem, 1.0)
	CrystalVisual.apply_state(state, 0.0)
	near(float(material.get_shader_parameter("fade_alpha")), 1.0, 0.0001,
			"走远后外壳必须恢复满亮度")
	state.node.free()

func test_energy_shader_does_not_redefine_builtin_constants() -> void:
	# TAU / PI 重定义会让 shader 编译失败 → 材质回落纯白，headless 测试全绿。
	var source := _source("res://shaders/crystal_energy.gdshader")
	for name in ["TAU", "PI"]:
		check(not source.contains("const float " + name), "不能重定义内置常量 %s" % name)
	check(source.contains("uniform float phase"), "外壳必须由 phase 驱动")
	check(source.contains("fade_alpha"), "外壳必须能跟随淡化")

# ---------------- 环 / 晶屑 / 台基 ----------------

func test_rings_are_lit_and_carry_runes() -> void:
	var state := _blue()
	for i in CrystalVisual.RING_COUNT:
		gt(float(CrystalVisual.RING_SPECS[i]["tube"]), 0.030, "第 %d 道环太细，远景是铁丝" % i)
	var body := state.node.find_child("ring_body_0", true, false) as MeshInstance3D
	var glow := state.node.find_child("ring_glow_0", true, false) as MeshInstance3D
	check(body != null and glow != null, "环体与光晕层必须都在")
	if body and glow:
		var material := body.material_override as StandardMaterial3D
		check(material.emission_enabled, "环体必须自发光，否则 gl_compatibility 下是深褐色铁丝")
		gt(material.emission_energy_multiplier, 0.80, "环体自发光不足以脱离铁丝观感")
		gt(material.emission.b, 0.30, "蓝方环体自发光要掺队伍蓝")
		# 符文菱形的半高是 tube*3.2，明显高过光晕环的管径。
		gt(body.mesh.get_aabb().size.y, glow.mesh.get_aabb().size.y * 1.5,
				"悬浮环必须比纯 torus 多出等距符文几何")
	state.node.free()

func test_orbit_shards_are_blades_not_droplets() -> void:
	var state := _blue()
	var shard := (state.shards as Array)[0] as MeshInstance3D
	var box := shard.mesh.get_aabb()
	gt(box.size.y, box.size.x, "晶片应长轴朝上")
	gt(box.size.x, box.size.z, "晶片腰部应宽于厚度")
	lt(shard.scale.z, shard.scale.x, "实例必须压薄，等比缩放会把它变回一颗水滴")
	gt((state.shard_material as StandardMaterial3D).emission_energy_multiplier, 0.70,
			"晶屑要比本体亮，否则 21 米机位只剩深色小点")
	state.node.free()

func test_crystal_tip_keeps_faction_colour_and_mesh_budget_holds() -> void:
	var blue_tip: Color = CrystalVisual.palette("blue").gem_tip
	var red_tip: Color = CrystalVisual.palette("red").gem_tip
	lt(blue_tip.g, 0.95, "蓝方晶尖不能是一截近白白帽")
	gt(red_tip.r - red_tip.b, 0.50, "红方晶尖必须仍是红/橙")
	var state := _blue()
	var meshes: Array = state.node.find_children("*", "MeshInstance3D", true, false)
	lt(float(meshes.size()), 34.0, "二轮新增部件后仍在网格预算内：%d" % meshes.size())
	state.node.free()

func test_dais_dropped_the_dark_radial_blocks() -> void:
	var source := _source("res://scripts/game/crystal_visual.gd")
	check(not source.contains("Vector3(0.94, 0.07, 0.56)"), "井盖式黑辐条不能回来")
	check(has_live_line(source, "gold.lerp(light, 0.30)"), "径向铜嵌条必须真的建出来")

func test_box_top_face_uses_the_top_colour_not_the_side_shadow() -> void:
	# 实拍回归（2026-11-12 二轮收尾）：上面那条只查源码文本，抓不到着色错位。
	# _add_box 曾把 top_color 标在 +z 竖直侧面上，真正朝上的面拿 side_color。
	# 结果俯视时「浅石板拼花」是八块深色板砖、铜嵌条是暗褐细线——
	# 源码里浅色明明还在，测试也全绿，只有出图才看得出来。
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	CrystalVisual._add_box(st, Vector3.ZERO, Vector3(1.0, 0.2, 1.0), 0.0,
			Color.WHITE, Color.BLACK)
	var arrays: Array = st.commit().surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	var top_lit := 0
	var top_dark := 0
	var bottom_dark := 0
	# 必须按法线挑面：四个竖直侧面也各有顶点落在 y=+half，
	# 按 y 筛会把侧面的暗色顶点算成"顶面没刷亮"。
	for i in verts.size():
		if normals[i].y > 0.9:
			if colors[i].r > 0.9:
				top_lit += 1
			else:
				top_dark += 1
		elif normals[i].y < -0.9 and colors[i].r < 0.1:
			bottom_dark += 1
	gt(float(top_lit), 0.0, "朝上的顶面必须真的拿到 top_color")
	eq(top_dark, 0, "顶面不能残留 side_color 的暗色顶点，否则俯视又是黑板砖")
	gt(float(bottom_dark), 0.0, "底面仍应是侧色，避免整体被刷成一块白板")

# ---------------- 光柱 / 法阵 / 护盾 ----------------

func test_beam_sigil_and_shield_keep_old_contracts_and_gain_new_looks() -> void:
	var beam := _source("res://shaders/crystal_beam.gdshader")
	check(beam.contains("uniform float mote_gain"), "光柱必须暴露上升光屑强度")
	check(beam.contains("uniform float intensity"), "旧契约 intensity 不能丢")
	var sigil := _source("res://shaders/crystal_sigil.gdshader")
	check(sigil.contains("float ground"), "法阵必须带贴地柔光池")
	check(sigil.contains("spin_speed"), "旧契约 spin_speed 不能丢")
	var shield := _source("res://shaders/crystal_shield.gdshader")
	check(shield.contains("uniform float strength"), "旧契约 strength 不能丢")
	check(shield.contains("UV.y - 0.93"), "护盾顶部要有能量汇聚环")

	var state := CrystalVisual.build(Arena.RED, "red")
	var shield_material := state.shield_material as ShaderMaterial
	var edge: Color = shield_material.get_shader_parameter("edge_color")
	gt(edge.r - edge.b, 0.40, "红方护盾边缘必须仍是红色，不能洗成米白肥皂泡")
	var inner := state.beam_inner_material as ShaderMaterial
	var outer := state.beam_outer_material as ShaderMaterial
	gt(float(inner.get_shader_parameter("mote_gain")), float(outer.get_shader_parameter("mote_gain")),
			"内芯光屑应比外焰明显")
	var hot: Color = inner.get_shader_parameter("hot_color")
	lt(hot.b, 0.99, "红方光柱热色不能是纯白灯管")
	state.node.free()

func test_beam_is_faction_coloured_not_a_white_tube() -> void:
	# 二轮出图复盘：0.52 白化 + blend_add 在浅色地面上把柱子烧成白/粉白灯管，
	# 红蓝两座基地只剩底座分色。热色必须离白远一点，内芯 alpha 也不能太高。
	var red := CrystalVisual.build(Arena.RED, "red")
	var inner := red.beam_inner_material as ShaderMaterial
	var hot: Color = inner.get_shader_parameter("hot_color")
	# Arena.RED 本身 r-b 约 0.74；0.52 白化后只剩 0.35，0.30 白化后约 0.52。
	gt(hot.r - hot.b, 0.45, "红方光柱热色必须明显偏红，不能被白化洗成粉白")
	var beam_color: Color = inner.get_shader_parameter("beam_color")
	lt(beam_color.a, 0.26, "内芯 alpha 过高会在 blend_add 下前后两面叠成白线")
	var outer_box: AABB = (red.beam_outer as MeshInstance3D).mesh.get_aabb()
	gt(outer_box.size.x, 1.40, "外焰太细时 21 米机位下光柱几乎消失")
	red.node.free()

	var blue := CrystalVisual.build(Arena.BLUE, "blue")
	var blue_hot: Color = (blue.beam_inner_material as ShaderMaterial).get_shader_parameter("hot_color")
	gt(blue_hot.b - blue_hot.r, 0.30, "蓝方光柱热色必须明显偏蓝")
	blue.node.free()

# ---------------- 接线 ----------------

func test_energy_layer_is_not_dead_code() -> void:
	var source := _source("res://scripts/game/crystal_visual.gd")
	check(has_live_line(source, "ENERGY_SHADER"), "必须预加载能量外壳 shader")
	check(has_live_line(source, "_energy_material(team_color, palette_data)"), "build 必须真的建外壳材质")
	check(has_live_line(source, "set_shader_parameter(\"fade_alpha\", fade)"), "apply_state 必须同步淡化")
	check(has_live_line(source, "set_shader_parameter(\"phase\", time)"), "apply_state 必须推时间轴")
