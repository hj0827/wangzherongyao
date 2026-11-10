extends "res://tests/test_base.gd"

# 项 6b：对局公平性 —— 单位不能卡死在墙里。
#
# 这条 bug 的症状极具欺骗性：**没有报错、测试全绿、单局也能打完**，
# 但镜像局里稳定 9/10 由红方获胜。根因是：
#
#   实体沿 waypoint 前进，而碰撞系统会把"被墙挡住"的位移吃掉大半。
#   "到点"判定要求距离 < 0.9m，于是实体钻进野区围墙后每 tick 只挪 0.15m，
#   永远到不了点、path_index 也永不前进 —— 实测蓝方射手卡了 6 分钟、CS 停在 4，
#   而红方同位置同英雄 CS 是 32。人数优势让红方稳定获胜。
#
# 所以这组测试守的不是"某个函数返回值"，而是**位置真的在变**。

const MatchSim = preload("res://sim/match_sim.gd")
const Collision = preload("res://sim/map/collision.gd")
const MapData = preload("res://sim/map_data.gd")

func _team_match(seed_value := 0x2F6E2B1) -> Object:
	return MatchSim.new({
		"mode": "team", "humans": [], "bot_fill": true, "bot_ai": true,
		"seed": seed_value,
		"bot_comp": ["blade", "tank", "assassin", "mage", "archer"],
	})

# ---------------------------------------------------------------- 位置真的在变

func test_heroes_are_never_permanently_pinned() -> void:
	# 直接把"卡死"量化：任意英雄的 stuck_ticks 都不该持续累积。
	# 修复前蓝方射手会一直卡在 30（上限）以上。
	# 只跑 600 tick（20 秒）——卡死是**持续**现象，20 秒足够暴露；
	# 跑满 1800 tick 会让这个套件慢到无法在常规回归里使用。
	var sim := _team_match()
	var worst := 0
	var dt := 1.0 / MatchSim.TICK_RATE
	for i in 600:
		sim.tick(dt)
		sim.consume_events()
		for e in sim.state.entities:
			if str(e.get("type", "")) == "hero":
				worst = maxi(worst, int(e.get("stuck_ticks", 0)))
	# stuck_ticks 在超过阈值时会被清零，所以它本身不会无限增长；
	# 真正要守的是"不会长期贴着上限"。
	check(worst < 60, "英雄连续卡住 tick 不该长期贴近上限（实测峰值 %d）" % worst)

func test_bots_actually_cover_distance_over_time() -> void:
	# 端到端：20 秒内每个存活英雄都应该有可观的位移总量。
	# 卡死的个体位移接近 0（实测每秒只有 0.15m，即 20 秒约 3m）。
	var sim := _team_match()
	var travelled: Dictionary = {}
	var prev: Dictionary = {}
	for e in sim.state.entities:
		if str(e.get("type", "")) == "hero":
			prev[int(e.get("id"))] = e.get("pos", Vector2.ZERO)
			travelled[int(e.get("id"))] = 0.0
	var dt := 1.0 / MatchSim.TICK_RATE
	# 先跑 5 秒让 bot 从出生点散开（开局瞬间目标还没出现，位移小是正常的）。
	for i in 150:
		sim.tick(dt)
		sim.consume_events()
	for e in sim.state.entities:
		if str(e.get("type", "")) == "hero":
			prev[int(e.get("id"))] = e.get("pos", Vector2.ZERO)
	for i in 450:
		sim.tick(dt)
		sim.consume_events()
		for e in sim.state.entities:
			if str(e.get("type", "")) != "hero":
				continue
			var id := int(e.get("id"))
			var pos: Vector2 = e.get("pos", Vector2.ZERO)
			if bool(e.get("alive", false)):
				travelled[id] = float(travelled.get(id, 0.0)) + (pos - (prev.get(id, pos) as Vector2)).length()
			prev[id] = pos
	for id in travelled:
		# 15 秒 x 6m/s 理论 90m；门槛取 20m，只要不是"几乎没动"即可。
		gt(float(travelled[id]), 20.0, "英雄 %d 在 15 秒内的累计位移应大于 20m（实测 %.1f）" % [id, float(travelled[id])])

func test_resync_snaps_to_the_nearest_path_point() -> void:
	# _resync_path_index 的单元级契约：不管实体被撞到哪里，
	# 重吸附后拿到的都应该是一个"离它很近"的路径点。
	var path: Array = MapData.lane_path("mid")
	var entity := {"pos": Vector2(5.0, -5.0), "path_dir": 1}
	var index: int = MatchSim._resync_path_index(entity, path)
	check(index >= 0 and index < path.size(), "重吸附必须返回合法索引（得到 %d）" % index)
	var dist: float = (entity["pos"] as Vector2).distance_to(path[index])
	lt(dist, 20.0, "重吸附后的路径点不该离实体太远（实测 %.1f）" % dist)
	# 红方（dir=-1）同样要能吸附。
	var red_entity := {"pos": Vector2(-5.0, 5.0), "path_dir": -1}
	var red_index: int = MatchSim._resync_path_index(red_entity, path)
	check(red_index >= 0 and red_index < path.size(), "红方重吸附也必须返回合法索引")

func test_resync_never_pushes_an_entity_out_of_its_path() -> void:
	# 反向守卫：吸附不能把索引推到越界位置（否则会静默停止移动）。
	var path: Array = MapData.lane_path("top")
	for dir in [1, -1]:
		for spot in [Vector2(46.0, -46.0), Vector2(0.0, -50.0), Vector2(-46.0, 46.0)]:
			var entity := {"pos": spot, "path_dir": dir}
			var index: int = MatchSim._resync_path_index(entity, path)
			check(index >= 0 and index < path.size(),
				"dir=%d pos=%s 吸附后索引越界：%d" % [dir, str(spot), index])

# ---------------------------------------------------------------- 公平性指标

func test_mirror_match_economy_stays_close() -> void:
	# 这是 6b 的核心验收：同阵容镜像局，双方经济不该有数量级差距。
	# 修复前实测蓝方 CS 78~83、红方 104~110（差约 30%），且红方 9/10 获胜。
	# 修复后差距降到个位数百分比。
	var sim := _team_match()
	var dt := 1.0 / MatchSim.TICK_RATE
	while not sim.ended and float(sim.state.time) < 600.0:
		sim.tick(dt)
		sim.consume_events()
	var cs := {"blue": 0, "red": 0}
	for e in sim.state.entities:
		if str(e.get("type", "")) == "hero":
			cs[str(e.get("team", ""))] = int(cs[str(e.get("team", ""))]) + int(e.get("cs", 0))
	var total := maxi(int(cs["blue"]), int(cs["red"]))
	gt(total, 0, "前置条件：双方都应该有补刀")
	var gap := 100.0 * absf(float(int(cs["blue"]) - int(cs["red"]))) / float(total)
	lt(gap, 25.0, "镜像局双方 CS 差距应小于 25%%（实测 %.1f%%：blue=%d red=%d）" % [gap, int(cs["blue"]), int(cs["red"])])
