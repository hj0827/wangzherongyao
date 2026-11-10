extends "res://tests/test_base.gd"

# 主堡陷落演出（P1 STRUCT-02 的第一版）。
# match_end 只带 winner；表现层反推败方基地，在水晶位置起大范围爆炸 + 冲击环。

const Arena = preload("res://scripts/game/arena.gd")

func test_match_end_explodes_the_losing_base() -> void:
	var arena: Node3D = Arena.new()
	arena._effects_root = Node3D.new()
	arena.add_child(arena._effects_root)
	arena._init_vfx_pools()
	# 这个测试不挂进真正的主循环；清空粒子池避免 create_timer 拿不到 SceneTree。
	arena._hit_particles_pool.clear()
	arena._hit_particles_active.clear()
	arena._process_events([{"type": "match_end", "winner": "blue"}])
	gt(float(arena._ring_active.size()), 0.0, "主堡陷落要起一圈冲击环")
	gt(arena._camera_shake, 0.0, "主堡陷落要有震屏")
	arena.free()
