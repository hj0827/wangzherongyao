extends SceneTree
# pacing_report.gd — 对局节奏与联机事件压力的可复现测量工具。
#   godot --headless --path godot --script res://tools/pacing_report.gd
# 输出：①英雄字段覆盖面 ②1v1/5v5 人机对局里程碑 ③5v5 事件包溢出统计（对齐 net_protocol.MAX_EVENTS=32 截断）。

const MatchSim = preload("res://sim/match_sim.gd")
const HeroDefs = preload("res://sim/hero_defs.gd")
const ItemShop = preload("res://sim/item_shop.gd")
const NetProtocol = preload("res://net/net_protocol.gd")

const FIELDS := ["armor", "magic_resist", "crit_rate", "crit_damage", "ability_power", "attack_speed", "cooldown_reduction", "hp_regen", "mana_regen", "penetration", "lifesteal", "shield", "haste_timer", "slow_timer", "cc_immune_timer", "buff_red_timer", "buff_blue_timer", "passive_stacks", "revealed_timer", "gold", "cs", "xp", "level"]


func _init() -> void:
	print("== hero_def declared fields (blade) ==")
	var probe: Dictionary = HeroDefs.get_hero("blade")
	var present: Array = []
	for f in FIELDS:
		if probe.has(f):
			present.append(f)
	print("present: ", _j(present))
	print("missing: ", _j(_missing(probe)))

	for mode in ["duel", "team"]:
		var m := {"mode": mode, "humans": [], "bot_fill": true, "bot_ai": true}
		_measure(m)
	_event_overflow_report()
	quit()


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
	while not sim.ended and sim.state.time < 900.0:
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
	print("event-batch pressure (5v5 bots, 10Hz flush, limit=%d): batches=%d over_limit=%d (%.1f%%) max_events_per_batch=%d" % [
		limit, batches, over, 100.0 * float(over) / maxf(1.0, float(batches)), max_seen])


func _missing(def: Dictionary) -> Array:
	var out: Array = []
	for f in FIELDS:
		if not def.has(f):
			out.append(f)
	return out


func _measure(match_config: Dictionary) -> void:
	print("--- mode=%s ---" % match_config["mode"])
	var sim = MatchSim.new(match_config)
	var dt := 1.0 / MatchSim.TICK_RATE
	var marks := {}
	var first_tower := -1.0
	var first_blood := -1.0
	var tower_deaths_by_min := {}
	var hero_deaths := 0
	var peak := 0
	var guard := 0
	var iter := 0
	while not sim.ended and sim.state.time < 900.0:
		sim.tick(dt)
		iter += 1
		peak = maxi(peak, sim.state.entities.size())
		for ev in sim.consume_events():
			var t := str(ev.get("type", ""))
			if t == "tower_destroyed":
				if first_tower < 0.0:
					first_tower = float(sim.state.time)
				guard += 1
			if t == "death" and str(ev.get("entity_type", "")) == "hero":
				hero_deaths += 1
				if first_blood < 0.0:
					first_blood = float(sim.state.time)
		for m in [60, 120, 180, 300, 420, 600]:
			var key := "t%d" % m
			if float(sim.state.time) >= float(m) and not marks.has(key):
				marks[key] = _snap(sim)
	print("ended=%s winner=%s duration=%s" % [sim.ended, sim.state.winner, _fmt(float(sim.state.time))])
	print("first_tower=%s first_blood=%s towers_dead=%d hero_deaths=%d peak_entities=%d" % [
		_fmt(first_tower), _fmt(first_blood), guard, hero_deaths, peak])
	for m in [60, 120, 180, 300, 420, 600]:
		var key := "t%d" % m
		if marks.has(key):
			print("  @%3ds %s" % [m, marks[key]])
	var hero: Dictionary = {}
	for e in sim.state.entities:
		if str(e.get("type", "")) == "hero":
			hero = e
			break
	var live: Array = []
	for f in FIELDS:
		if hero.has(f):
			live.append(f)
	print("sim_hero_fields_present: ", _j(live))
	print("sim_hero_fields_missing: ", _j(_missing(hero)))
	print("final: lvl=%d net=%d cs=%d items=%d k/d/a=%d/%d/%d" % [
		int(hero.get("level", 1)), _net(hero), int(hero.get("cs", 0)),
		(hero.get("inventory", []) as Array).size(),
		int(hero.get("kills", 0)), int(hero.get("deaths", 0)), int(hero.get("assists", 0))])


func _snap(sim) -> String:
	var hero: Dictionary = {}
	var towers_dead := 0
	var minions := 0
	for e in sim.state.entities:
		var t := str(e.get("type", ""))
		if t == "hero" and hero.is_empty():
			hero = e
		if t == "tower" and not bool(e.get("alive", true)):
			towers_dead += 1
		if t == "minion" and bool(e.get("alive", true)):
			minions += 1
	if hero.is_empty():
		return "?"
	return "lvl=%2d gold=%5d cs=%3d items=%d dead_towers=%d minions_alive=%d wave=%d" % [
		int(hero.get("level", 1)), _net(hero), int(hero.get("cs", 0)),
		(hero.get("inventory", []) as Array).size(), towers_dead, minions, int(sim.state.wave)]


func _net(h: Dictionary) -> int:
	var v := int(h.get("gold", 0))
	for id in h.get("inventory", []):
		v += int(ItemShop.get_item(str(id)).get("cost", 0))
	return v


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
