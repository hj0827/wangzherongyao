extends "res://tests/test_base.gd"

# 项 6：地图公平性与节奏标定契约。
#
# 这一组守的是两类**只靠"能跑通"永远发现不了**的问题：
#   1. 地图不对称 —— 边路塔位曾按"沿路径量弧长"各自计算，而两侧路径采样点不点对称，
#      导致边路塔离自家基地相差 0.295 m（中路恰好 0）。偏差小、方向恒定，
#      等于给一侧稳定的对线优势，肉眼与单局测试都看不出来。
#   2. 解锁口径写成 ALL —— 基地/双子塔曾要求"三路高地塔全倒"，
#      而注释、测试名与实际规则都是"任意一路"。

const MapLayout = preload("res://sim/map/map_layout.gd")
const MapData = preload("res://sim/map_data.gd")
const MatchSim = preload("res://sim/match_sim.gd")

# 双方地图元素必须满足的对称变换。与出生点同一套：绕地图中心 180°，(x,y) -> (-x,-y)。
const POINT_MIRROR_TOLERANCE := 0.01

# ---------------------------------------------------------------- 地图对称

func test_every_tower_has_a_point_symmetric_twin() -> void:
	var blue: Array = []
	var red: Array = []
	for slot in MapLayout.tower_slots():
		if str(slot.team) == "blue":
			blue.append(slot)
		else:
			red.append(slot)
	eq(blue.size(), red.size(), "双方塔数必须相同")
	for b in blue:
		var image := Vector2(-b.pos.x, -b.pos.y)
		var best := INF
		for r in red:
			best = minf(best, image.distance_to(r.pos))
		check(best <= POINT_MIRROR_TOLERANCE,
			"蓝方 %s/%s 的镜像点找不到对称的红方塔（最近 %.3f m）" % [str(b.lane), str(b.tier), best])

func test_side_lane_towers_are_equidistant_from_their_own_base() -> void:
	# 这条直接钉住那个 0.295 m 的历史偏差：边路两侧塔离自家基地的距离必须相等。
	# 它比"镜像点匹配"更容易读懂，也更能说明"为什么不公平"。
	for lane in ["mid", "top", "bottom"]:
		for tier in ["outer", "inner", "high"]:
			var bp: Vector2 = MapLayout.tower_anchor(lane, "blue", tier)
			var rp: Vector2 = MapLayout.tower_anchor(lane, "red", tier)
			var d_blue := bp.distance_to(MapData.BLUE_BASE)
			var d_red := rp.distance_to(MapData.RED_BASE)
			near(d_blue, d_red, 0.01,
				"%s/%s 两侧塔离自家基地距离必须相等（蓝 %.3f vs 红 %.3f）" % [lane, tier, d_blue, d_red])

func test_all_towers_stay_on_their_lane_path() -> void:
	# 防"为了对称而把塔挪到路外"：塔必须仍落在本路折线上。
	for slot in MapLayout.tower_slots():
		var path: Array = MapData.lane_path(str(slot.lane))
		var best := INF
		for i in range(path.size() - 1):
			best = minf(best, _distance_to_segment(slot.pos, path[i], path[i + 1]))
		lt(best, 0.05, "塔 %s/%s/%s 必须落在本路路径上（偏离 %.3f m）" % [
			str(slot.team), str(slot.lane), str(slot.tier), best])

func _distance_to_segment(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var length_sq := ab.length_squared()
	if length_sq < 0.0001:
		return p.distance_to(a)
	var t := clampf((p - a).dot(ab) / length_sq, 0.0, 1.0)
	return p.distance_to(a + ab * t)

# ---------------------------------------------------------------- 节奏参数

func test_wave_interval_and_first_wave_delay_are_sane() -> void:
	# 兵线间隔是节奏最直接的旋钮。钉住合理区间，避免有人为了"加快"把它改成 5 秒，
	# 那样一波还没打完就压下一波，小兵会无限堆积。
	check(MatchSim.WAVE_INTERVAL >= 12.0 and MatchSim.WAVE_INTERVAL <= 30.0,
		"兵线间隔应在 12~30 秒之间（当前 %.1f）" % MatchSim.WAVE_INTERVAL)
	check(MatchSim.FIRST_WAVE_DELAY >= 0.0 and MatchSim.FIRST_WAVE_DELAY <= 5.0,
		"首波延迟应在 0~5 秒之间（当前 %.1f）" % MatchSim.FIRST_WAVE_DELAY)

func test_pacing_sample_supports_seed_and_composition() -> void:
	# 节奏抽样依赖这两个开关。若它们静默失效，"多阵容多 seed"就退化成一局跑 N 次，
	# 统计出来的中位数毫无意义。
	var a := MatchSim.new({"mode": "team", "humans": [], "bot_fill": true, "seed": 12345})
	var b := MatchSim.new({"mode": "team", "humans": [], "bot_fill": true, "seed": 999})
	check(int(a.get("_rng_state")) != int(b.get("_rng_state")), "不同 seed 必须产生不同随机起点")
	var comp := ["mage", "mage", "archer", "archer", "assassin"]
	var c := MatchSim.new({"mode": "team", "humans": [], "bot_fill": true, "bot_comp": comp})
	var mages := 0
	for e in c.state.entities:
		if str(e.get("type", "")) == "hero" and str(e.get("controller", "")) == "bot":
			if str(e.get("hero_type", "")) == "mage":
				mages += 1
	gt(mages, 0, "bot_comp 指定的阵容必须真的被采用（否则抽样覆盖不到极端组合）")

func test_zero_seed_does_not_freeze_the_rng() -> void:
	# seed=0 会让 LCG 退化成常数序列（暴击永远相同），必须回落到默认种子。
	var sim := MatchSim.new({"mode": "duel", "humans": [], "bot_fill": true, "seed": 0})
	var first := int(sim.get("_rng_state"))
	check(first != 0, "seed=0 必须回落到默认种子，不能让 RNG 卡死在 0")
