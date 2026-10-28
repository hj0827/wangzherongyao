extends SceneTree

# 团战 CPU 基准：只跑模拟与快照构建，不开渲染窗口。
# 用法：godot --headless --path godot --script res://tools/bench_combat.gd
const MatchSim = preload("res://sim/match_sim.gd")

const HEROES := ["blade", "archer", "tank", "mage", "assassin"]

func _initialize() -> void:
	var humans: Array = []
	for i in 5:
		humans.append({"id": "b%d" % (i + 1), "name": "B%d" % (i + 1), "team": "blue", "hero_type": HEROES[i]})
		humans.append({"id": "r%d" % (i + 1), "name": "R%d" % (i + 1), "team": "red", "hero_type": HEROES[(i + 2) % HEROES.size()]})
	var sim = MatchSim.new({
		"mode": "team",
		"humans": humans,
		"bot_fill": false,
		"bot_ai": true,
	})

	# 先推进 10 秒，让兵线/野怪/第一波交战都进入热态。
	for i in 300:
		sim.tick(1.0 / MatchSim.TICK_RATE)

	var entities: int = sim.state.entities.size()
	var tick_us := _measure(300, func(): sim.tick(1.0 / MatchSim.TICK_RATE))

	var full_us := _measure(120, func(): sim.snapshot())
	var old_broadcast_us := _measure(60, func():
		sim.snapshot_for("blue")
		sim.snapshot_for("red")
	)
	var shared_us := _measure(60, func():
		var base: Dictionary = sim.snapshot()
		sim.snapshot_for("blue", null, base)
		sim.snapshot_for("red", null, base)
	)

	print("BENCH entities=%d tick=%.1fus snapshot_full=%.1fus broadcast_old=%.1fus broadcast_shared=%.1fus saved=%.0f%%" % [
		entities, tick_us, full_us, old_broadcast_us, shared_us,
		(1.0 - shared_us / maxf(old_broadcast_us, 0.001)) * 100.0,
	])
	quit()

func _measure(iterations: int, action: Callable) -> float:
	var start := Time.get_ticks_usec()
	for i in iterations:
		action.call()
	return float(Time.get_ticks_usec() - start) / float(iterations)
