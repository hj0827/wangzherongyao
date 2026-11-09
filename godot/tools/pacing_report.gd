extends SceneTree
# pacing_report.gd — 对局节奏与联机事件压力的可复现测量工具（项 6）。
#   godot --headless --path godot --script res://tools/pacing_report.gd -- --samples=12
# 输出：①英雄字段覆盖面 ②多 seed × 多阵容的对局节奏统计 ③5v5 事件包溢出统计。
#
# 为什么必须多样本：单局数字会骗人。同种子同阵容跑出来的"15 分钟未分胜负"
# 也可能只是撞上测量上限，而不是真的推不完 —— 这个工具上一版就犯过这个错
# （900 秒硬上限把"还没打完"打印成"15m00s 未分胜负"）。

const MatchSim = preload("res://sim/match_sim.gd")
const HeroDefs = preload("res://sim/hero_defs.gd")
const ItemShop = preload("res://sim/item_shop.gd")
const NetProtocol = preload("res://net/net_protocol.gd")

const FIELDS := ["armor", "magic_resist", "crit_rate", "crit_damage", "ability_power", "attack_speed", "cooldown_reduction", "hp_regen", "mana_regen", "penetration", "lifesteal", "shield", "haste_timer", "slow_timer", "cc_immune_timer", "buff_red_timer", "buff_blue_timer", "passive_stacks", "revealed_timer", "gold", "cs", "xp", "level"]

# 单局上限放到 30 分钟：MOBA 的僵局可能确实超过 15 分钟，
# 把上限设在 15 分钟会把"僵局"和"测不到"混成同一个结论。
const MATCH_LIMIT := 1800.0
# 阵容样本：每队 5 人，用不同职业组合覆盖"全近战/全远程/缺前排"等极端。
const COMPOSITIONS := [
	["blade", "tank", "assassin", "mage", "archer"],   # 标准
	["tank", "tank", "blade", "blade", "mage"],        # 双前排
	["mage", "mage", "archer", "archer", "assassin"],  # 全脆皮
	["blade", "tank", "archer", "archer", "mage"],     # 缺刺客
]

var _samples := 8


func _init() -> void:
	_parse_args()
	print("== pacing report: samples=%d compositions=%d limit=%.0fs ==" % [_samples, COMPOSITIONS.size(), MATCH_LIMIT])
	_field_report()
	_mode_report("duel")
	_mode_report("team")
	_event_overflow_report()
	quit()


func _parse_args() -> void:
	for arg in OS.get_cmdline_user_args():
		var text := str(arg)
		if text.begins_with("--samples="):
			_samples = maxi(1, int(text.split("=")[1]))


func _field_report() -> void:
	print("--- hero_def declared fields (blade) ---")
	var probe: Dictionary = HeroDefs.get_hero("blade")
	var present: Array = []
	for f in FIELDS:
		if probe.has(f):
			present.append(f)
	print("present: ", _j(present))
	print("missing: ", _j(_missing(probe)))


func _mode_report(mode: String) -> void:
	var durations: Array[float] = []
	var first_towers: Array[float] = []
	var first_bloods: Array[float] = []
	var undecided := 0
	var total := 0
	var blue_wins := 0
	var levels: Array[float] = []
	for comp_index in COMPOSITIONS.size():
		for sample in _samples:
			var cfg := _config_for(mode, comp_index, sample)
			var result := _run_one(cfg)
			total += 1
			if not bool(result["ended"]):
				undecided += 1
			else:
				durations.append(float(result["duration"]))
				if str(result["winner"]) == "blue":
					blue_wins += 1
			if float(result["first_tower"]) > 0.0:
				first_towers.append(float(result["first_tower"]))
			if float(result["first_blood"]) > 0.0:
				first_bloods.append(float(result["first_blood"]))
			levels.append(float(result["median_level"]))
	print("=== mode=%s (n=%d, compositions=%d x seeds=%d) ===" % [mode, total, COMPOSITIONS.size(), _samples])
	if durations.is_empty():
		print("  decided=0  undecided=%d  <-- 所有样本都没在 %.0fs 内结束" % [undecided, MATCH_LIMIT])
	else:
		durations.sort()
		var decided := durations.size()
		print("  decided=%d/%d (%.0f%%)  undecided=%d  timeout_at=%.0fs" % [
			decided, total, 100.0 * float(decided) / float(total), undecided, MATCH_LIMIT])
		print("  duration  min=%s  median=%s  p90=%s  max=%s" % [
			_fmt(durations[0]), _fmt(_pct(durations, 0.5)), _fmt(_pct(durations, 0.9)), _fmt(durations[decided - 1])])
		# 目标带 8–12 分钟：命中率是最该看的一个数（验收表 6.2）。
		var in_band := 0
		for d in durations:
			if d >= 480.0 and d <= 720.0:
				in_band += 1
		print("  in 8-12min band: %d/%d = %.0f%%" % [in_band, decided, 100.0 * float(in_band) / float(decided)])
		print("  blue win rate: %.0f%%" % (100.0 * float(blue_wins) / float(decided)))
	levels.sort()
	if not levels.is_empty():
		print("  median hero level at end: %.0f" % _pct(levels, 0.5))
	if not first_towers.is_empty():
		first_towers.sort()
		print("  first tower: median=%s  p90=%s" % [_fmt(_pct(first_towers, 0.5)), _fmt(_pct(first_towers, 0.9))])
	if not first_bloods.is_empty():
		first_bloods.sort()
		print("  first blood: median=%s" % _fmt(_pct(first_bloods, 0.5)))


func _config_for(mode: String, comp_index: int, sample: int) -> Dictionary:
	var comp: Array = COMPOSITIONS[comp_index % COMPOSITIONS.size()]
	var seed_value := 0x2F6E2B1 + sample * 7919 + comp_index * 104729
	if mode == "duel":
		# 1v1 用循环的两职业对打，避免"永远是苍刃打苍刃"这种单一镜像。
		var a: String = comp[sample % comp.size()]
		var b: String = comp[(sample + 1) % comp.size()]
		return {
			"mode": "duel",
			"humans": [
				{"id": "blue1", "team": "blue", "hero_type": a},
				{"id": "red1", "team": "red", "hero_type": b},
			],
			"bot_fill": false,
			"bot_ai": true,
			"seed": seed_value,
		}
	return {
		"mode": "team",
		"humans": [],
		"bot_fill": true,
		"bot_ai": true,
		"seed": seed_value,
		"bot_comp": comp,
	}


func _run_one(match_config: Dictionary) -> Dictionary:
	var sim = MatchSim.new(match_config)
	var dt := 1.0 / MatchSim.TICK_RATE
	var first_tower := -1.0
	var first_blood := -1.0
	while not sim.ended and sim.state.time < MATCH_LIMIT:
		sim.tick(dt)
		for ev in sim.consume_events():
			var t := str(ev.get("type", ""))
			if t == "tower_destroyed" and first_tower < 0.0:
				first_tower = float(sim.state.time)
			if t == "death" and str(ev.get("entity_type", "")) == "hero" and first_blood < 0.0:
				first_blood = float(sim.state.time)
	var levels: Array[float] = []
	for e in sim.state.entities:
		if str(e.get("type", "")) == "hero":
			levels.append(float(e.get("level", 1)))
	levels.sort()
	return {
		"ended": sim.ended,
		"winner": str(sim.state.winner),
		"duration": float(sim.state.time),
		"first_tower": first_tower,
		"first_blood": first_blood,
		"median_level": _pct(levels, 0.5) if not levels.is_empty() else 0.0,
	}


func _pct(sorted_values: Array, ratio: float) -> float:
	if sorted_values.is_empty():
		return 0.0
	var index := clampi(int(round(ratio * float(sorted_values.size() - 1))), 0, sorted_values.size() - 1)
	return float(sorted_values[index])


# 事件包压力：按 10Hz 广播节奏累计两次广播之间的全部 30Hz 事件，
# 数出超过 net_protocol.MAX_EVENTS 的批次 —— 超出部分在真实联机里会被静默丢弃。
func _event_overflow_report() -> void:
	var m := {"mode": "team", "humans": [], "bot_fill": true, "bot_ai": true}
	var sim = MatchSim.new(m)
	var dt := 1.0 / MatchSim.TICK_RATE
	var limit := int(NetProtocol.MAX_EVENTS)
	var batches := 0
	var over := 0
	var max_seen := 0
	var pending := 0
	var flush_timer := 0.0
	while not sim.ended and sim.state.time < MATCH_LIMIT:
		sim.tick(dt)
		pending += sim.consume_events().size()
		flush_timer += dt
		if flush_timer >= 0.1:
			flush_timer = 0.0
			batches += 1
			max_seen = maxi(max_seen, pending)
			if pending > limit:
				over += 1
			pending = 0
	print("=== event-batch pressure (5v5 bots, 10Hz flush, limit=%d) ===" % limit)
	print("  batches=%d over_limit=%d (%.1f%%) max_events_per_batch=%d" % [
		batches, over, 100.0 * float(over) / maxf(1.0, float(batches)), max_seen])


func _missing(def: Dictionary) -> Array:
	var out: Array = []
	for f in FIELDS:
		if not def.has(f):
			out.append(f)
	return out


func _j(a: Array) -> String:
	var s := ""
	for i in a.size():
		s += str(a[i])
		if i < a.size() - 1:
			s += ", "
	return s


func _fmt(t: float) -> String:
	if t < 0.0:
		return "never"
	return "%dm%02ds" % [int(t / 60.0), int(fmod(t, 60.0))]
