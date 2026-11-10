extends "res://tests/test_base.gd"

# 技能地面残留（P1 FX-04 的第一版）。
# 12 个贴地柔光 quad，池化；1.6s 内淡出，池空抢最老的一枚，战斗期不 new。

const Arena = preload("res://scripts/game/arena.gd")
const SkillFx = preload("res://scripts/game/skill_fx.gd")
const FxTextures = preload("res://scripts/game/fx_textures.gd")

func _arena() -> Node3D:
	var arena: Node3D = Arena.new()
	arena._effects_root = Node3D.new()
	arena.add_child(arena._effects_root)
	arena._init_vfx_pools()
	return arena

func test_pool_is_prebuilt_and_uses_the_soft_glow_texture() -> void:
	var arena := _arena()
	eq(arena._decal_pool.size(), Arena.DECAL_POOL_LIMIT, "地面残留必须预建满池")
	for node in arena._decal_pool:
		check(not node.visible, "预建节点默认隐藏")
		var material := node.material_override as StandardMaterial3D
		check(material != null and material.albedo_texture == FxTextures.rune(), "残留使用共享柔光贴图")
	arena.free()

func test_spawn_fades_and_returns_to_pool() -> void:
	var arena := _arena()
	arena._spawn_decal(Vector2(3.0, -2.0), Color(1.0, 0.5, 0.2), 2.0)
	eq(arena._decal_active.size(), 1, "生成一枚残留")
	var entry: Dictionary = arena._decal_active[0]
	var node := entry.get("node") as MeshInstance3D
	check(node != null and node.visible, "残留节点可见")
	var material := node.material_override as StandardMaterial3D
	check(material != null and material.albedo_color.a > 0.0, "残留有初始透明度")
	var initial_energy := material.emission_energy_multiplier
	arena._update_decals(1.0)
	check(material.albedo_color.a < 0.55, "时间过半后透明度下降")
	lt(material.emission_energy_multiplier, initial_energy, "自发光也要跟着淡出")
	arena._update_decals(1.0)
	eq(arena._decal_active.size(), 0, "到时间后归还池")
	check(not node.visible, "归还后隐藏")
	eq(arena._decal_pool.size(), Arena.DECAL_POOL_LIMIT, "池数量恢复")
	arena.free()

func test_pool_empty_steals_oldest_instead_of_dropping() -> void:
	var arena := _arena()
	for i in Arena.DECAL_POOL_LIMIT + 1:
		arena._spawn_decal(Vector2(float(i), 0.0), Color.WHITE, 1.0)
	eq(arena._decal_active.size(), Arena.DECAL_POOL_LIMIT, "池空时抢最老，不静默丢弃")
	var seen := {}
	for entry in arena._decal_active:
		var node: MeshInstance3D = entry.get("node")
		check(not seen.has(node.get_instance_id()), "同一节点不能同时借给两处")
		seen[node.get_instance_id()] = true
	arena.free()

func test_skill_fx_actually_spawns_a_decal() -> void:
	var arena := _arena()
	# 用一条只有 aim 环、没有粒子的最小配方：既验证 _spawn_skill_fx 真的调用
	# _spawn_decal，又不需要 SceneTree 的 create_timer（测试不把 Arena 挂进树）。
	arena._spawn_skill_fx({
		"hero_id": -1, "slot": "q", "hero_type": "blade", "kind": "slash",
		"from": Vector2.ZERO, "aim": Vector2(5.0, 0.0),
		"recipe": {
			"rings": [{"at": "aim", "from": 0.4, "to": 2.0, "dur": 0.2, "alpha": 0.5}],
			"particles": [], "projectile": 0.0, "trail": 0, "beam": 0,
			"shake": 0.0, "hit_stop": 0.0,
		},
	})
	gt(float(arena._decal_active.size()), 0.0, "技能表现链路必须真的生成地面残留")
	arena.free()
