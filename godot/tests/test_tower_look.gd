extends "res://tests/test_base.gd"

# 防御塔观感契约（2026-10-25）
#
# 参考图（王者荣耀）：米黄石雕塔身 + 外扩的花瓣裙摆基座 + 竖棱收分塔柱
# + 笼状塔冠里发光的阵营核心 + 塔脚暖色光池 + 上飘花瓣。
#
# 旧塔是一个贴图瞭望塔 glb + 一颗悬空小球，和参考图没有关系；
# 而且 glb 的材质和程序化地形对不上，读起来像贴上去的模型。
# 这批断言守住「塔由程序化石构件搭出来」和「光效真的挂在塔上」，
# 免得以后又退回一个随手 load 的场景。

const Arena = preload("res://scripts/game/arena.gd")
const TowerVisual = preload("res://scripts/game/tower_visual.gd")
const ModelUtils = preload("res://scripts/game/model_utils.gd")

const TOWER_ID := 31

func _make_arena(entities: Array) -> Node3D:
	var arena: Node3D = Arena.new()
	arena._structures_root = Node3D.new()
	arena.add_child(arena._structures_root)
	arena._sync_structures({"entities": entities}, true)
	return arena

func _tower_entity(extra: Dictionary = {}) -> Dictionary:
	var entity := {
		"id": TOWER_ID, "type": "tower", "team": "red", "tier": "outer",
		"x": 0.0, "y": 0.0, "hp": 3200.0, "max_hp": 3200.0,
		"alive": true, "vulnerable": true, "range": 8.0, "radius": 1.4,
	}
	entity.merge(extra, true)
	return entity

func _record(arena: Node3D) -> Dictionary:
	return arena._structure_views.get(TOWER_ID, {})

func test_tower_is_procedural_stone_not_the_old_watchtower_glb() -> void:
	var source := FileAccess.get_file_as_string("res://scripts/game/arena.gd")
	check(not source.contains("WatchTower_SecondAge_Level3.glb"), "防御塔不能再用旧瞭望塔 glb")
	check(source.contains("TowerVisual.build("), "防御塔要由程序化石塔模块生成")
	check(ResourceLoader.exists("res://shaders/tower_glow.gdshader"), "塔脚光池着色器必须存在")
	near(TowerVisual.CORE_HEIGHT, float(Arena.TOWER_CRYSTAL_HEIGHT), 0.001, "塔冠核心高度必须和光束枪口一致")

func test_tower_reads_as_flared_petal_base_and_tapered_shaft() -> void:
	var arena := _make_arena([_tower_entity()])
	var record := _record(arena)
	check(not record.is_empty(), "防御塔视图已创建")
	var model: Node3D = record.get("model")
	check(model != null, "塔视图持有模型引用")
	if model == null:
		arena.free()
		return
	var box := ModelUtils.relative_aabb(model)
	var girth := maxf(box.size.x, box.size.z)
	gt(box.size.y, 8.2, "塔要够高（当前 %.2f m）" % box.size.y)
	lt(girth, 3.0, "塔身不能变胖挡住英雄（当前 %.2f m）" % girth)
	gt(box.size.y / maxf(girth, 0.001), 2.8, "塔还是要细而尖（宽高比 %.2f）" % (box.size.y / maxf(girth, 0.001)))
	gt(float(record.get("bar_height", 0.0)), box.size.y, "血条必须悬在模型顶之上")
	# 裙摆外扩、塔柱收分：参考图里基座明显比柱身宽一圈。
	gt(TowerVisual.BASE_RADIUS, TowerVisual.SHAFT_TOP_RADIUS + 0.7, "基座花瓣裙摆必须外扩")
	gt(TowerVisual.SHAFT_BOTTOM_RADIUS, TowerVisual.SHAFT_TOP_RADIUS + 0.2, "塔柱必须向上收分")
	# 暖色石料：偏米黄，不是灰白也不是土黄。
	var stone: Color = TowerVisual.STONE_LIGHT
	gt(stone.r, stone.g, "石料要偏暖")
	gt(stone.g, stone.b, "石料要偏暖")
	gt(stone.r, 0.68, "石料要够亮，才能和草地拉开")
	arena.free()

func test_tower_crown_holds_an_emissive_team_core() -> void:
	var arena := _make_arena([_tower_entity()])
	var record := _record(arena)
	var core: MeshInstance3D = record.get("core")
	check(core != null, "塔冠里要有发光核心")
	if core != null:
		near(core.position.y, float(Arena.TOWER_CRYSTAL_HEIGHT), 0.001, "核心要在枪口高度上")
		check(core.mesh != null, "核心要有网格")
		var mat := core.material_override as StandardMaterial3D
		check(mat != null, "核心用 StandardMaterial3D，才能吃发光和泛光")
		if mat != null:
			check(mat.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED, "核心必须不受光照，直接当光源读")
			check(mat.emission_enabled, "核心必须自发光")
			gt(float(mat.emission_energy_multiplier), 1.5, "核心发光要足够亮")
			gt(mat.emission.r, mat.emission.g, "红方核心必须偏红")
			gt(mat.emission.r, mat.emission.b, "红方核心必须偏红")
	var model: Node3D = record.get("model")
	var glow: MeshInstance3D = record.get("glow")
	check(glow != null, "塔脚要有地面光池")
	if glow != null and model != null:
		check(not model.is_ancestor_of(glow), "地面光池不能算进塔身 AABB，否则会破坏细高契约")
		near(glow.position.y, TowerVisual.GROUND_GLOW_Y, 0.001, "光池要贴地")
		var glow_mat := glow.material_override as ShaderMaterial
		check(glow_mat != null, "光池用径向淡出着色器，不能是方形色块")
		if glow_mat != null:
			var glow_color: Color = glow_mat.get_shader_parameter("glow_color")
			check(glow_color.r > glow_color.b, "红方光池要偏暖")
	arena.free()

func test_tower_has_orbiting_petals_outside_the_body() -> void:
	var arena := _make_arena([_tower_entity()])
	var record := _record(arena)
	var spin: Node3D = record.get("spin")
	check(spin != null, "塔顶要有环绕花瓣")
	var model: Node3D = record.get("model")
	if spin != null and model != null:
		check(not model.is_ancestor_of(spin), "花瓣不能算进塔身 AABB")
		var meshes := spin.find_children("*", "MeshInstance3D", true, false)
		check(not meshes.is_empty(), "花瓣要有可见网格")
		if not meshes.is_empty():
			var petals := meshes[0] as MeshInstance3D
			check(petals.mesh != null, "花瓣网格不能为空")
			check(petals.material_override is StandardMaterial3D, "花瓣要有自己的材质")
		check(TowerVisual.PETAL_COUNT >= 5, "花瓣数量要够，才读得出飘落感")
	arena.free()

func test_tower_range_glow_band_follows_the_warning_state() -> void:
	# 参考图里范围是一圈又宽又亮的暖色光带；但它的颜色仍必须和
	# range_ring_state 共用同一套判定 —— 敌人进圈整条光带变红。
	var arena: Node3D = Arena.new()
	arena._structures_root = Node3D.new()
	arena.add_child(arena._structures_root)
	arena._local_entity_id = 501
	var inside := {"id": 501, "type": "hero", "team": "blue", "x": 3.0, "y": 0.0, "alive": true}
	arena._sync_structures({"entities": [_tower_entity(), inside]}, true)
	var record := _record(arena)
	var band: MeshInstance3D = record.get("range_band")
	check(band != null, "范围圈要有一条柔和光带，不只是细线")
	var band_mat: StandardMaterial3D = record.get("range_band_mat")
	check(band_mat != null, "光带材质要能被每帧刷新")
	var warned := Color(0.0, 0.0, 0.0, 0.0)
	if band_mat != null:
		warned = band_mat.albedo_color
		gt(warned.r - warned.g, 0.3, "敌人进圈时整条光带必须变红")
		gt(warned.a, 0.15, "警戒光带要够亮才看得见")
	var outside := inside.duplicate(true)
	outside["x"] = 12.0
	arena._sync_structures({"entities": [_tower_entity(), outside]}, false)
	if band_mat != null:
		var calm: Color = band_mat.albedo_color
		lt(calm.a, 0.12, "平时光带要压暗，不能整张地图都是红圈")
		check(calm.a < warned.a, "警戒必须比平时更亮")
	arena.free()
