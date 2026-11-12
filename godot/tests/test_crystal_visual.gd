extends "res://tests/test_base.gd"

# 基地水晶重做（2026-11-12）：造型分层、淡化契约、状态驱动与生产接线。
#
# 这组测试只抓「结构 / 材质契约 / 状态曲线 / 接线」，不抓像素。
# 像素由 tools/crystal_gallery.gd 出图，人工看对比图。
#
# 依次锁死：
#   1. 五层造型都在（台基 / 柱座 / 晶簇 / 环+碎片 / 光柱+法阵+护盾）；
#   2. dais 不淡化、pedestal/gem 必须淡化且常驻 ALPHA（OcclusionFade 的旧契约不能回退）；
#   3. 晶簇顶高于柱座、台基宽于晶簇（俯视可读性）；
#   4. 血量 → 残破单调、阈值一致、晶簇变暗；
#   5. 碎片真的在转、不会穿台座；
#   6. 护盾量 → 壳厚 + 法阵亮环；
#   7. Arena 每帧真的在驱动它（不是「文件在、没人调」）；
#   8. 几何缓存复用、材质逐座新建（OcclusionFade 改 alpha 不串局）。

const Arena = preload("res://scripts/game/arena.gd")
const CrystalVisual = preload("res://scripts/game/crystal_visual.gd")
const Occlusion = preload("res://scripts/game/occlusion_fade.gd")
const ModelUtils = preload("res://scripts/game/model_utils.gd")

func _base_entity(team := "blue", hp := 5000.0, shield := 0.0, shield_max := 0.0) -> Dictionary:
	return {
		"id": 7001 if team == "blue" else 7002,
		"type": "base",
		"team": team,
		"tier": "core",
		"x": 0.0,
		"y": 0.0,
		"hp": hp,
		"max_hp": 5000.0,
		"alive": true,
		"shield": shield,
		"shield_max": shield_max,
		"guards_alive": 2,
		"vulnerable": true,
		"radius": 4.0,
		"range": 9.0,
	}

func _arena_record(entity: Dictionary = {}) -> Dictionary:
	var arena: Node3D = Arena.new()
	arena._structures_root = Node3D.new()
	arena.add_child(arena._structures_root)
	var target := entity if not entity.is_empty() else _base_entity()
	arena._sync_structures({"entities": [target]}, true)
	return {"arena": arena, "record": arena._structure_views.get(int(target.id), {})}

func _all_meshes(root: Node) -> Array:
	var result: Array = []
	for node in root.find_children("*", "MeshInstance3D", true, false):
		result.append(node)
	return result

# ---------------- 造型层 ----------------

func test_crystal_builds_every_documented_layer() -> void:
	var state := CrystalVisual.build(Arena.BLUE, "blue")
	var root: Node3D = state.node
	for name in ["dais", "base_trim", "pedestal", "pedestal_glow", "gem_spin", "gem",
			"gem_edges", "halo", "crystal_shield", "cracks", "beam_inner", "beam_outer",
			"base_sigil_blue"]:
		check(root.find_child(name, true, false) != null, "缺少造型层：%s" % name)
	for i in CrystalVisual.RING_COUNT:
		check(root.find_child("ring_%d" % i, true, false) != null, "缺少第 %d 道金环" % i)
	for i in CrystalVisual.SHARD_COUNT:
		check(root.find_child("shard_%d" % i, true, false) != null, "缺少第 %d 块轨道碎片" % i)
	for i in 3:
		check(root.find_child("base_ring_blue_%d" % i, true, false) != null, "缺少第 %d 道广场同心环" % i)
	# 节点预算：主堡是全图最大的单件造型，但也不该无限膨胀（当前 27 个 MeshInstance）。
	var meshes := _all_meshes(root)
	lt(float(meshes.size()), 34.0, "主堡网格数超出预算：%d" % meshes.size())
	root.free()

func test_crystal_clears_the_pedestal_and_fits_inside_the_dais() -> void:
	# 俯视可读性：晶簇必须「浮」在柱座上方，台基必须比晶簇宽一圈。
	var state := CrystalVisual.build(Arena.BLUE, "blue")
	var root: Node3D = state.node
	var dais := root.find_child("dais", true, false) as MeshInstance3D
	var pedestal := root.find_child("pedestal", true, false) as MeshInstance3D
	var gem := root.find_child("gem", true, false) as MeshInstance3D
	check(dais != null and pedestal != null and gem != null, "三段主体必须存在")
	if dais and pedestal and gem:
		var dais_box := dais.get_aabb()
		var pedestal_box := pedestal.get_aabb()
		var gem_box := gem.get_aabb()
		gt(CrystalVisual.GEM_BASE_Y, CrystalVisual.PEDESTAL_TOP, "晶簇底部必须高于柱座顶面（悬浮缝）")
		gt(CrystalVisual.DAIS_RADIUS, CrystalVisual.GEM_RADIUS * 2.0, "台基半径必须大于晶簇直径")
		gt(dais_box.size.x, gem_box.size.x * 2.0, "台基实际宽度必须罩住晶簇：%.2f vs %.2f" % [dais_box.size.x, gem_box.size.x])
		lt(pedestal_box.size.y, CrystalVisual.GEM_HEIGHT, "柱座不能比晶簇还高，否则读成一根柱子")
		gt(CrystalVisual.BAR_HEIGHT, CrystalVisual.GEM_TOP, "血条必须悬在晶尖之上")
	root.free()

func test_team_palettes_keep_the_same_silhouette_but_different_materials() -> void:
	var blue := CrystalVisual.build(Arena.BLUE, "blue")
	var red := CrystalVisual.build(Arena.RED, "red")
	var blue_stone: Color = CrystalVisual.palette("blue").stone_light
	var red_stone: Color = CrystalVisual.palette("red").stone_light
	check(blue_stone != red_stone, "两阵营的石材基色必须不同")
	# 蓝方冷、红方暖：红方石材的红色分量必须高于蓝色分量。
	check(blue_stone.b > blue_stone.r, "蓝方石头应偏冷")
	check(red_stone.r > red_stone.b, "红方石头应偏暖")
	# 自发光仍是阵营色：这是 21 米机位下最先读到的信号。
	var blue_gem: StandardMaterial3D = blue.gem_material
	var red_gem: StandardMaterial3D = red.gem_material
	near(blue_gem.emission.r, Arena.BLUE.r, 0.001, "蓝方晶簇自发光应为蓝队色")
	near(red_gem.emission.r, Arena.RED.r, 0.001, "红方晶簇自发光应为红队色")
	check((blue.dais as MeshInstance3D).mesh != (red.dais as MeshInstance3D).mesh, "阵营石材顶点色写在几何里，网格不能跨阵营复用")
	blue.node.free()
	red.node.free()

func test_geometry_is_cached_but_materials_are_built_per_base() -> void:
	# 几何复用：同一局重开/重播时不必重算 SurfaceTool。
	var first := CrystalVisual.build(Arena.BLUE, "blue")
	var count_after_first := CrystalVisual.mesh_count()
	var second := CrystalVisual.build(Arena.BLUE, "blue")
	eq(CrystalVisual.mesh_count(), count_after_first, "第二座同阵营主堡不应新增几何缓存")
	check((first.dais as MeshInstance3D).mesh == (second.dais as MeshInstance3D).mesh, "台基网格应复用")
	check((first.gem as MeshInstance3D).mesh == (second.gem as MeshInstance3D).mesh, "晶簇网格应复用")
	# 材质不复用：OcclusionFade 直接改 albedo.a，跨局共用会把上一局的半透明带进新局。
	check((first.gem as MeshInstance3D).material_override != (second.gem as MeshInstance3D).material_override, "晶簇材质必须逐座新建")
	check((first.dais as MeshInstance3D).material_override != (second.dais as MeshInstance3D).material_override, "台基材质必须逐座新建")
	first.node.free()
	second.node.free()

# ---------------- 淡化契约 ----------------

func test_fade_parts_match_occlusion_contract() -> void:
	var built := _arena_record()
	var record: Dictionary = built.record
	check(not record.is_empty(), "基地视图必须创建")
	var parts: Array = Occlusion.fade_parts(record)
	var names: Array[String] = []
	for part in parts:
		names.append(str((part as Node).name))
	check(not names.has("dais"), "dais 绝不能进淡化名单：%s" % str(names))
	check(names.has("pedestal"), "柱身必须淡化：%s" % str(names))
	check(names.has("gem"), "宝石必须淡化：%s" % str(names))
	for part in parts:
		var mesh := part as MeshInstance3D
		check(mesh != null, "淡化部件必须是 MeshInstance3D")
		if mesh == null:
			continue
		var material := mesh.material_override as StandardMaterial3D
		check(material != null, "淡化部件必须有 StandardMaterial3D：%s" % mesh.name)
		if material != null:
			eq(material.transparency, BaseMaterial3D.TRANSPARENCY_ALPHA, "淡化部件必须常驻 ALPHA：%s" % mesh.name)
	# 贴脸 → 全部让路；dais 保持不透明。
	near(Occlusion.apply(record, 0.0), Occlusion.MIN_VISIBLE, 0.0001, "贴脸时整体降到下限")
	var dais := (built.arena as Node).find_child("dais", true, false) as MeshInstance3D
	var dais_mat := dais.material_override as StandardMaterial3D
	near(dais_mat.albedo_color.a, 1.0, 0.0001, "英雄贴脸时 dais 仍不透明")
	near(Occlusion.apply(record, 40.0), 1.0, 0.0001, "远离后恢复满不透明")
	(built.arena as Node).free()

func test_damage_does_not_undo_the_occlusion_fade() -> void:
	# 回归：apply_damage 重建 albedo 时如果写死 alpha=1，英雄贴着水晶会看到它突然变实。
	var built := _arena_record()
	var state: Dictionary = built.record.get("crystal_visual", {})
	Occlusion.apply(built.record, 0.0)
	CrystalVisual.apply_damage(state, 0.1)
	for part in state.fade_parts:
		var mesh := part as MeshInstance3D
		var material := mesh.material_override as StandardMaterial3D
		if material != null:
			near(material.albedo_color.a, Occlusion.MIN_VISIBLE, 0.0001, "残破改色不能把 alpha 弹回不透明：%s" % mesh.name)
	(built.arena as Node).free()

# ---------------- 残破曲线 ----------------

func test_damage_tone_is_thresholded_and_monotonic() -> void:
	eq(CrystalVisual.damage_tone(1.0), 0.0, "满血无残破")
	eq(CrystalVisual.damage_tone(CrystalVisual.DAMAGE_THRESHOLD), 0.0, "阈值处刚好开始残破")
	eq(CrystalVisual.damage_tone(0.9), 0.0, "阈值以上不残破")
	var prev := -1.0
	# 从半血往空血走：血量递减，残破必须单调不减。
	for step in 30:
		var ratio: float = 0.5 * (1.0 - float(step) / 29.0)
		var tone := CrystalVisual.damage_tone(ratio)
		check(tone >= prev - 0.00001, "残破必须随血量下降单调上升：ratio=%.3f" % ratio)
		prev = tone
		near(tone, 1.0 - ratio / CrystalVisual.DAMAGE_THRESHOLD, 0.0001, "阈值以下应是线性")
	near(CrystalVisual.damage_tone(0.0), 1.0, 0.0001, "空血应完全残破")

func test_apply_damage_shows_cracks_and_dims_the_crystal() -> void:
	var state := CrystalVisual.build(Arena.BLUE, "blue")
	var gem_mat: StandardMaterial3D = state.gem_material
	var dais_mat: StandardMaterial3D = state.dais_material
	var light: OmniLight3D = state.light
	var energy_full := float(state.gem_base_energy)
	CrystalVisual.apply_state(state, 0.0)
	var energy_before := gem_mat.emission_energy_multiplier
	CrystalVisual.apply_damage(state, 0.15)
	check((state.cracks as MeshInstance3D).visible, "残血必须显示裂纹")
	gt(CrystalVisual.damage_tone(0.15), 0.5, "15% 血应超过半残破")
	lt(dais_mat.albedo_color.r, 0.95, "残血台基应变暗")
	# 自发光在下一帧状态更新里收：残破越重越小，但有底。
	CrystalVisual.apply_state(state, 0.0)
	var energy_after := gem_mat.emission_energy_multiplier
	lt(energy_after, energy_before, "残血晶簇自发光应变弱")
	gt(energy_after, energy_full * 0.30, "残血也必须看得见，不能彻底熄灭")
	lt(light.light_energy, float(state.light_base_energy) * 1.1, "残血点光应减弱")
	# 无残破时裂纹必须隐藏。
	CrystalVisual.apply_damage(state, 1.0)
	check(not (state.cracks as MeshInstance3D).visible, "满血不应显示裂纹")
	state.node.free()

# ---------------- 轨道 ----------------

func test_orbit_shards_move_and_never_sink_into_the_dais() -> void:
	var at_zero := CrystalVisual.shard_orbit(0, 0.0)
	var at_two := CrystalVisual.shard_orbit(0, 2.0)
	gt(at_zero.distance_to(at_two), 0.5, "碎片必须真的在转")
	for i in CrystalVisual.SHARD_COUNT:
		var last := Vector3.ZERO
		for step in 6:
			var point := CrystalVisual.shard_orbit(i, float(step) * 1.1)
			gt(point.y, CrystalVisual.PEDESTAL_TOP + 0.8, "碎片不能沉进柱座：shard=%d y=%.2f" % [i, point.y])
			var radius := Vector2(point.x, point.z).length()
			gt(radius, CrystalVisual.GEM_RADIUS, "碎片轨道必须在晶簇外侧")
			lt(radius, CrystalVisual.DAIS_RADIUS, "碎片不能飞出台基外沿")
			if step > 0:
				gt(point.distance_to(last), 0.05, "同一块碎片相邻采样应移动")
			last = point
	# 不同碎片同一时刻不应重叠：相位/半径/高度必须错开。
	var seen: Array[Vector3] = []
	for i in CrystalVisual.SHARD_COUNT:
		var point := CrystalVisual.shard_orbit(i, 1.3)
		for other in seen:
			gt(point.distance_to(other), 0.5, "两块碎片在同一时刻重叠了")
		seen.append(point)

# ---------------- 护盾 ----------------

func test_shield_strength_and_material_parameters() -> void:
	eq(CrystalVisual.shield_strength(0.0, 2400.0), 0.0, "无护盾强度为 0")
	near(CrystalVisual.shield_strength(1200.0, 2400.0), 0.5, 0.0001, "半盾强度为 0.5")
	near(CrystalVisual.shield_strength(9999.0, 2400.0), 1.0, 0.0001, "过量护盾封顶 1")
	near(CrystalVisual.shield_strength(500.0, 0.0), 1.0, 0.0001, "上限缺失时按满强度处理")
	var state := CrystalVisual.build(Arena.RED, "red")
	var shield := state.shield as MeshInstance3D
	var material := state.shield_material as ShaderMaterial
	CrystalVisual.apply_shield(state, 2400.0, 2400.0)
	check(shield.visible, "有护盾时必须显形")
	near(float(material.get_shader_parameter("strength")), 1.0, 0.0001, "满盾 shader strength 应为 1")
	CrystalVisual.apply_shield(state, 600.0, 2400.0)
	near(float(material.get_shader_parameter("strength")), 0.25, 0.0001, "四分之一盾 strength 应为 0.25")
	CrystalVisual.apply_shield(state, 0.0, 2400.0)
	check(not shield.visible, "护盾破碎后必须隐藏")
	# 法阵同步读护盾强度：破盾后外圈亮环要消失（无头也能断言）。
	CrystalVisual.apply_state(state, 0.0)
	var sigil := state.sigil_material as ShaderMaterial
	near(float(sigil.get_shader_parameter("shield")), 0.0, 0.0001, "破盾后法阵护盾环应为 0")
	state.node.free()

# ---------------- Arena 接线 ----------------

func test_arena_records_and_drives_the_crystal_state() -> void:
	var built := _arena_record()
	var record: Dictionary = built.record
	var state: Dictionary = record.get("crystal_visual", {})
	check(not state.is_empty(), "基地记录必须带 crystal_visual")
	if state.is_empty():
		(built.arena as Node).free()
		return
	check(record.get("spin") == state.get("spin"), "记录的 spin 必须就是 CrystalVisual 的晶簇根")
	var spin := state.spin as Node3D
	var shard := (state.shards as Array)[0] as Node3D
	var angle_before := spin.rotation.y
	var shard_before := shard.position
	(built.arena as Node)._sync_structures({"entities": [_base_entity()]}, false, 1.0)
	(built.arena as Node)._sync_structures({"entities": [_base_entity()]}, false, 1.0)
	gt(absf(spin.rotation.y - angle_before), 0.01, "Arena 每帧必须推进晶簇自转")
	gt(shard.position.distance_to(shard_before), 0.05, "Arena 每帧必须推进碎片轨道")
	# 血量 20% → 记录残破 tone 应同步，裂纹可见。
	var hurt := _base_entity("blue", 1000.0)
	(built.arena as Node)._sync_structures({"entities": [hurt]}, false, 0.1)
	gt(float(record.get("damage_tone", 0.0)), 0.5, "Arena 必须把血量变化交给 CrystalVisual")
	check((state.cracks as MeshInstance3D).visible, "低血主堡必须显示裂纹")
	(built.arena as Node).free()

func test_arena_show_shield_state_on_crystal_and_sigil() -> void:
	var built := _arena_record(_base_entity("red", 5000.0, 2400.0, 2400.0))
	var record: Dictionary = built.record
	var state: Dictionary = record.get("crystal_visual", {})
	var shield := record.get("crystal_shield") as MeshInstance3D
	check(shield != null and shield.visible, "有护盾时基地显示水晶护盾")
	var sigil := state.sigil_material as ShaderMaterial
	near(float(sigil.get_shader_parameter("shield")), 1.0, 0.0001, "满盾时法阵护盾环应为 1")
	(built.arena as Node)._sync_structures({"entities": [_base_entity("red", 5000.0, 0.0, 0.0)]}, false, 0.1)
	check(shield != null and not shield.visible, "破盾后隐藏水晶护盾")
	near(float(sigil.get_shader_parameter("shield")), 0.0, 0.0001, "破盾后法阵护盾环归零")
	(built.arena as Node).free()

func test_production_wiring_is_not_dead_code() -> void:
	var source := FileAccess.get_file_as_string("res://scripts/game/arena.gd")
	for needle in ["CrystalVisual.build(", "CrystalVisual.apply_state(", "CrystalVisual.apply_damage(", "CrystalVisual.apply_shield("]:
		check(has_live_line(source, needle), "arena.gd 必须真正调用 %s（不能只写在注释里）" % needle)
	check(has_live_line(source, '"crystal_visual": crystal_visual'), "基地记录必须暴露 crystal_visual")
	# 着色器契约：旧测试按 spin_speed 找刻线；新测试按 strength / intensity 读状态。
	var sigil := FileAccess.get_file_as_string("res://shaders/crystal_sigil.gdshader")
	check(sigil.contains("spin_speed"), "法阵 shader 必须保留 spin_speed 键")
	var shield := FileAccess.get_file_as_string("res://shaders/crystal_shield.gdshader")
	check(shield.contains("uniform float strength"), "护盾 shader 必须暴露 strength")
	var beam := FileAccess.get_file_as_string("res://shaders/crystal_beam.gdshader")
	check(beam.contains("uniform float intensity"), "光柱 shader 必须暴露 intensity")
