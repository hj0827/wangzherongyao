extends "res://tests/test_base.gd"

# 首领刷新演出（P1 MON-04 的第一版）。
# sim 已有 objective_spawn 事件；表现层补全局播报 + 两个首领坑的地面冲击/粒子。

const Arena = preload("res://scripts/game/arena.gd")
const MapView = preload("res://scripts/game/map_view.gd")
const MapLayout = preload("res://sim/map/map_layout.gd")

func test_objective_spawn_banner_is_announced() -> void:
	var banner := MapView.event_banner({"type": "objective_spawn"})
	check(not banner.is_empty(), "首领刷新必须有播报")
	check(str(banner.get("text", "")).contains("暴君"), "播报要点名暴君")
	check(bool(banner.get("announce", false)), "首领刷新要走全局横幅")
	check(str(banner.get("feed", "")).contains("增伤"), "信息流要说明奖励")

func test_objective_spawn_spawns_a_ring_at_both_pits() -> void:
	var arena: Node3D = Arena.new()
	var tree := Engine.get_main_loop() as SceneTree
	arena._effects_root = Node3D.new()
	arena.add_child(arena._effects_root)
	arena._init_vfx_pools()
	# 这个测试不挂进真正的主循环，粒子池的 create_timer 会拿不到 SceneTree；
	# 只保留环池，验证冲击环即可（生产里两池都在）。
	arena._hit_particles_pool.clear()
	arena._hit_particles_active.clear()
	tree.root.add_child(arena)
	arena._process_events([{"type": "objective_spawn"}])
	check(arena._ring_active.size() >= MapLayout.OBJECTIVE_PITS.size() * 2, "两个首领坑各起冲击环 + 2 秒预警环")
	gt(arena._zoom_kick, 0.0, "首领刷新要有镜头轻推")
	# 预警环从更大半径起跳（3.0），与 1.0 起跳的冲击环区分：
	# tween 还没推进时，scale 就是 from_scale。
	var warning_rings := 0
	for ring in arena._ring_active:
		if (ring as Node3D).scale.x > 2.5:
			warning_rings += 1
	check(warning_rings >= MapLayout.OBJECTIVE_PITS.size(), "每个首领坑都要有慢速预警环")
	arena.free()

func test_objective_kill_leaves_a_gold_decal() -> void:
	var arena: Node3D = Arena.new()
	arena._effects_root = Node3D.new()
	arena.add_child(arena._effects_root)
	arena._init_vfx_pools()
	arena._hit_particles_pool.clear()
	arena._hit_particles_active.clear()
	arena._process_events([{"type": "objective_killed", "x": 0.0, "y": 0.0}])
	gt(float(arena._decal_active.size()), 0.0, "首领死亡要留下金色地面残留")
	arena.free()
