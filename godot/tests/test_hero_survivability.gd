extends "res://tests/test_base.gd"

# 英雄生存性回归测试。
#
# 来源是实际体感问题：1 级英雄站进一波兵 8 秒就死、打个野怪掉 65% 血，
# 导致前期完全没法正常对线。这里把"活多久""掉多少血"变成可断言的数字，
# 避免以后调数值时无声退化。
#
# 关键测量手法（踩过的坑都写在注释里）：
#   - 必须把英雄挪离泉水，否则每秒 18% 最大生命的回复会盖过一切伤害；
#   - 必须把其它单位移出 entities，否则敌方小兵会去打自家小兵，
#     根本打不到英雄，测出来是假的安全；
#   - 伤害用 hit 事件累加，不用 hp 差值（脱战回血与死亡溢出会污染）。

const MatchSim = preload("res://sim/match_sim.gd")
const HeroDefs = preload("res://sim/hero_defs.gd")

const TICK := 1.0 / MatchSim.TICK_RATE
const HEROES := ["blade", "mage", "tank", "archer"]

# 1 级英雄站在第一波兵里（不操作）必须活过这个秒数。
const WAVE1_MIN_TTK := 15.0
# 站桩也必须会被打死：上限秒数，防止用"把英雄改成不死"来让上面那条通过。
const WAVE1_MAX_TTK := 40.0
# 1 级单挑一座野区营地，最多允许掉多少最大生命比例。
const JUNGLE_MAX_COST := {"blade": 0.25, "mage": 0.40, "tank": 0.25, "archer": 0.25}

# ---------- 场景搭建 ----------

func _new_sim(hero_type: String) -> Object:
	var sim: Object = MatchSim.new({
		"mode": "duel",
		"humans": [{"id": "me", "name": "me", "team": "blue", "hero_type": hero_type}],
		"bot_fill": false,
		"bot_ai": false,
	})
	var hero: Dictionary = sim.get_hero_by_player("me")
	hero.mp = 0.0
	return sim

func _entity(sim: Object, type: String, team: String) -> Dictionary:
	for entity in sim.state.entities:
		if entity.type == type and str(entity.team) == team and bool(entity.alive):
			return entity
	return {}

# 只留下要观测的单位。真实对局里敌方小兵会优先打自家小兵，不做隔离就测不到"站着挨打"。
func _isolate(sim: Object, keep: Array) -> void:
	var ids := {}
	for entity in keep:
		ids[int(entity.id)] = true
	sim.state.entities = sim.state.entities.filter(func(e): return ids.has(int(e.id)))

func _tick(sim: Object, hero: Dictionary, acc: Dictionary) -> void:
	sim.tick(TICK)
	for event in sim.state.events:
		if str(event.get("type", "")) == "hit" and int(event.get("target", -2)) == int(hero.id):
			acc["hits"] = int(acc["hits"]) + 1
			acc["taken"] = float(acc["taken"]) + float(event.get("amount", 0.0))
	sim.state.events.clear()

# ---------- 测量 ----------

# 返回英雄被这一波兵打死所需要的秒数；撑过 40 秒则返回上限值。
func _wave_ttk(hero_type: String, wave_number: int) -> float:
	var sim: Object = _new_sim(hero_type)
	var hero: Dictionary = sim.get_hero_by_player("me")

	var guard := 0
	while sim.state.entities.filter(func(e): return e.type == "minion" and e.team == "red" and e.alive).size() < 3 and guard < 600:
		sim.tick(TICK)
		guard += 1
		sim.state.events.clear()

	var minions: Array = sim.state.entities.filter(func(e): return e.type == "minion" and e.team == "red" and e.alive)
	check(minions.size() >= 3, "wave %d should spawn three minions" % wave_number)
	if minions.size() < 3:
		return WAVE1_MAX_TTK

	for m in minions:
		var stats: Dictionary = MatchSim.WaveRules.stats(str(m.minion_type), wave_number)
		m.hp = float(stats.hp)
		m.max_hp = float(stats.max_hp)
		m.attack_damage = float(stats.attack_damage)
		m.attack_interval = float(stats.attack_interval)
		m.attack_cd = 0.0

	var keep: Array = [hero]
	keep.append_array(minions)
	_isolate(sim, keep)

	# 挪到地图中央：站在泉水里每秒回 18% 最大生命，永远死不了。
	var anchor := Vector2.ZERO
	hero.pos = anchor
	var offsets := [Vector2(0.0, -1.2), Vector2.ZERO, Vector2(0.0, 1.2)]
	for i in minions.size():
		minions[i].pos = anchor + offsets[i]

	var acc := {"hits": 0, "taken": 0.0}
	var elapsed := 0.0
	while elapsed < WAVE1_MAX_TTK:
		_tick(sim, hero, acc)
		elapsed += TICK
		if not bool(hero.alive):
			return elapsed
		for i in minions.size():
			if bool(minions[i].alive):
				minions[i].pos = anchor + offsets[i]
	return WAVE1_MAX_TTK

# 返回 1 级英雄单挑野区营地掉掉的最大生命比例。
func _jungle_cost(hero_type: String) -> float:
	var sim: Object = _new_sim(hero_type)
	var hero: Dictionary = sim.get_hero_by_player("me")
	var monster: Dictionary = _entity(sim, "monster", "neutral")
	check(not monster.is_empty(), "jungle camp should exist")
	if monster.is_empty():
		return 1.0
	_isolate(sim, [hero, monster])

	var acc := {"hits": 0, "taken": 0.0}
	var elapsed := 0.0
	while elapsed < 40.0 and bool(monster.alive) and bool(hero.alive):
		hero.pos = monster.pos + Vector2(2.2, 0.0)
		sim.inputs["me"] = {"attack": true, "aim": monster.pos}
		_tick(sim, hero, acc)
		elapsed += TICK
	check(not bool(hero.alive) or not bool(monster.alive), "jungle fight should finish within 40s")
	return float(acc["taken"]) / maxf(float(hero.max_hp), 1.0)

# ---------- 用例 ----------

func test_level_one_hero_survives_a_full_wave() -> void:
	for hero_type in HEROES:
		var ttk := _wave_ttk(hero_type, 1)
		gt(ttk, WAVE1_MIN_TTK, "%s should survive wave 1 longer than %.0fs (got %.1fs)" % [hero_type, WAVE1_MIN_TTK, ttk])

func test_a_hero_still_dies_if_it_never_moves() -> void:
	# 下限：上面那条不能靠"把英雄改成不死"来通过。
	for hero_type in HEROES:
		var ttk := _wave_ttk(hero_type, 1)
		lt(ttk, WAVE1_MAX_TTK, "%s must still die to a wave if it just stands there (got %.1fs)" % [hero_type, ttk])

func test_later_waves_are_deadlier_than_the_first() -> void:
	var first := _wave_ttk("blade", 1)
	var tenth := _wave_ttk("blade", 10)
	lt(tenth, first, "wave 10 must kill faster than wave 1 (%.1fs vs %.1fs)" % [tenth, first])
	gt(tenth, 2.0, "wave 10 should not delete a hero instantly")

func test_jungle_camp_cost_is_survivable_at_level_one() -> void:
	for hero_type in HEROES:
		var cost := _jungle_cost(hero_type)
		var limit := float(JUNGLE_MAX_COST[hero_type])
		lt(cost, limit, "%s should lose less than %.0f%% hp to one jungle camp (got %.0f%%)" % [
			hero_type, limit * 100.0, cost * 100.0,
		])

func test_pve_damage_to_heroes_is_scaled_but_minion_vs_minion_is_not() -> void:
	# 只对英雄打折：小兵互殴与推塔的数值必须原样，否则兵线节奏会被连带改掉。
	var sim: Object = _new_sim("blade")
	var guard := 0
	while _entity(sim, "minion", "red").is_empty() and guard < 300:
		sim.tick(TICK)
		sim.state.events.clear()
		guard += 1

	var hero: Dictionary = sim.get_hero_by_player("me")
	var attacker: Dictionary = _entity(sim, "minion", "red")
	var victim: Dictionary = _entity(sim, "minion", "blue")
	check(not attacker.is_empty() and not victim.is_empty(), "both sides should have minions")
	if attacker.is_empty() or victim.is_empty():
		return

	var hero_before := float(hero.hp)
	sim._damage(hero, 100.0, attacker)
	var to_hero := hero_before - float(hero.hp)

	var victim_before := float(victim.hp)
	sim._damage(victim, 100.0, attacker)
	var to_minion := victim_before - float(victim.hp)

	near(to_hero, 100.0 * float(MatchSim.PVE_HERO_DAMAGE_SCALE), 0.01, "heroes take scaled pve damage")
	near(to_minion, 100.0, 0.01, "minions keep full pve damage")
	lt(to_hero, to_minion, "heroes must take strictly less pve damage than minions")

func test_monster_damage_to_heroes_is_scaled_too() -> void:
	var sim: Object = _new_sim("blade")
	var hero: Dictionary = sim.get_hero_by_player("me")
	var monster: Dictionary = _entity(sim, "monster", "neutral")
	check(not monster.is_empty(), "jungle camp should exist")
	if monster.is_empty():
		return
	var before := float(hero.hp)
	sim._damage(hero, 100.0, monster)
	near(before - float(hero.hp), 100.0 * float(MatchSim.PVE_HERO_DAMAGE_SCALE), 0.01, "monsters take the same pve scale")

func test_boss_objectives_keep_full_damage() -> void:
	# 主宰 / 暴君是逼团点，不能跟着小野怪一起被削弱，否则大龙变成免费野区。
	var sim: Object = _new_sim("blade")
	var hero: Dictionary = sim.get_hero_by_player("me")
	check(MatchSim.Objectives.PITS.size() > 0, "objective pits should exist")
	if MatchSim.Objectives.PITS.is_empty():
		return
	var boss: Dictionary = MatchSim.Objectives.monster_stats(MatchSim.Objectives.PITS[0])
	var before := float(hero.hp)
	sim._damage(hero, 100.0, boss)
	near(before - float(hero.hp), 100.0, 0.01, "boss objectives must keep full damage")

func test_hero_health_is_not_inflated_into_sponges() -> void:
	# 抬血量的副作用护栏：不能把英雄改成"谁都打不死"。
	# 参照不用"自己打自己"——坦克攻击力本来就低，那样算出来必然超标。
	var strongest_ad := 0.0
	var largest_hp := 0.0
	var smallest_hp := INF
	for hero_type in HEROES:
		var def: Dictionary = HeroDefs.get_hero(hero_type)
		strongest_ad = maxf(strongest_ad, float(def.attack_damage))
		largest_hp = maxf(largest_hp, float(def.max_hp))
		smallest_hp = minf(smallest_hp, float(def.max_hp))
	var worst_seconds := largest_hp / strongest_ad
	lt(worst_seconds, 30.0, "the tankiest hero must still die to sustained autos (%.1fs)" % worst_seconds)
	var fastest_seconds := smallest_hp / strongest_ad
	gt(fastest_seconds, 6.0, "the squishiest hero must not die in a couple of autos (%.1fs)" % fastest_seconds)

func test_hero_health_order_is_preserved() -> void:
	var tank := float(HeroDefs.get_hero("tank").max_hp)
	var blade := float(HeroDefs.get_hero("blade").max_hp)
	var archer := float(HeroDefs.get_hero("archer").max_hp)
	var mage := float(HeroDefs.get_hero("mage").max_hp)
	gt(tank, blade, "tank should keep the highest health pool")
	gt(blade, archer, "blade should have more health than archer")
	gt(archer, mage, "archer should have more health than mage")
