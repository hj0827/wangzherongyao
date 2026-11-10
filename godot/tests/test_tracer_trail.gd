extends "res://tests/test_base.gd"

# 弹道拖尾（P1 FX-06 第一版）。
# 独立 12 个光点池；普攻弹丸生成时同时起一条更小的拖尾，不抢占主弹丸池。

const Arena = preload("res://scripts/game/arena.gd")

func test_trail_pool_prebuilt() -> void:
	var arena: Node3D = Arena.new()
	arena._effects_root = Node3D.new()
	arena.add_child(arena._effects_root)
	arena._init_vfx_pools()
	eq(arena._trail_pool.size(), 12, "拖尾池必须预建 12 个")
	for node in arena._trail_pool:
		check(not node.visible, "拖尾节点默认隐藏")
	arena.free()

func test_tracer_spawns_a_trail_without_stealing_the_tracer_pool() -> void:
	var arena: Node3D = Arena.new()
	arena._effects_root = Node3D.new()
	arena.add_child(arena._effects_root)
	arena._init_vfx_pools()
	arena._spawn_tracer(Vector3(0, 1, 0), Vector3(5, 1, 0), Color(1, 0.8, 0.4), 0.1, 0.2)
	eq(arena._tracer_active.size(), 1, "主弹丸池借出一个")
	eq(arena._trail_active.size(), 1, "拖尾池同时借出一个")
	var trail: MeshInstance3D = arena._trail_active[0]
	check(trail.visible, "拖尾要可见")
	var material := trail.material_override as StandardMaterial3D
	check(material != null and material.albedo_color.a > 0.0, "拖尾要有初始透明度")
	arena.free()
