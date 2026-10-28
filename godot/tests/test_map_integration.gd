extends "res://tests/test_base.gd"

# 地图系统与模拟层的集成契约：
# 18 塔与逐塔解锁、兵种波次、野怪增益、首领刷新、视野快照、网络白名单。

const MatchSim = preload("res://sim/match_sim.gd")
const MapLayout = preload("res://sim/map/map_layout.gd")
const MapData = preload("res://sim/map_data.gd")
const TowerRules = preload("res://sim/map/tower_rules.gd")
const NetProtocol = preload("res://net/net_protocol.gd")

func _sim(mode := "duel", bot_ai := false) -> Object:
	return MatchSim.new({
		"mode": mode,
		"humans": [{"id": "p1", "name": "Tester", "team": "blue", "hero_type": "blade"}],
		"bot_fill": true,
		"bot_ai": bot_ai,
	})

func _tower(sim: Object, team: String, lane: String, tier: String) -> Dictionary:
	for entity in sim.state.entities:
		if entity.type == "tower" and entity.team == team and entity.lane == lane and str(entity.get("tier", "")) == tier:
			return entity
	return {}

func _base(sim: Object, team: String) -> Dictionary:
	for entity in sim.state.entities:
		if entity.type == "base" and entity.team == team:
			return entity
	return {}

func _kill(sim: Object, entity: Dictionary, source_id := -1) -> void:
	sim.apply_damage(int(entity.id), 999999.0, source_id)

func _count(sim: Object, type: String, predicate := Callable()) -> int:
	var total := 0
	for entity in sim.state.entities:
		if entity.type != type or not bool(entity.get("alive", false)):
			continue
		if predicate.is_valid() and not bool(predicate.call(entity)):
			continue
		total += 1
	return total

func test_duel_and_team_modes_spawn_three_tiers_of_towers() -> void:
	var duel := _sim()
	eq(_count(duel, "tower"), 6, "1v1 中路双方各三塔")
	for team in ["blue", "red"]:
		for tier in MapLayout.TOWER_TIERS:
			check(not _tower(duel, team, "mid", tier).is_empty(), "1v1 缺少 %s %s" % [team, tier])

	var team_sim := _sim("team")
	eq(_count(team_sim, "tower"), 18, "5v5 三路双方共 18 塔")
	eq(_count(team_sim, "base"), 2, "双方各一座主堡")

func test_tower_gating_and_base_exposure_flow() -> void:
	var sim := _sim()
	var outer := _tower(sim, "red", "mid", "outer")
	var inner := _tower(sim, "red", "mid", "inner")
	var high := _tower(sim, "red", "mid", "high")
	var red_base := _base(sim, "red")
	check(not outer.is_empty() and not inner.is_empty() and not high.is_empty(), "红方三塔齐全")
	check(not red_base.is_empty(), "红方基地存在")

	var max_hp := float(outer.max_hp)
	sim.apply_damage(int(outer.id), 1000.0)
	near(float(outer.hp), max_hp - 500.0, 0.1, "开局保护期塔伤减半")

	var inner_hp := float(inner.hp)
	sim.apply_damage(int(inner.id), 999999.0)
	near(float(inner.hp), inner_hp, 0.001, "外塔未倒时内塔免疫伤害")
	var base_hp := float(red_base.hp)
	sim.apply_damage(int(red_base.id), 999999.0)
	near(float(red_base.hp), base_hp, 0.001, "高地塔未倒时基地免疫伤害")
	check(not sim.ended, "打不动保护建筑时比赛不能结束")

	_kill(sim, outer)
	_kill(sim, inner)
	check(not TowerRules.is_base_vulnerable(red_base, sim.state.entities), "高地塔仍在时基地仍锁定")
	_kill(sim, high)
	check(TowerRules.is_base_vulnerable(red_base, sim.state.entities), "高地塔倒下后基地暴露")
	_kill(sim, red_base)
	check(sim.ended, "基地被摧毁后比赛结束")
	eq(str(sim.state.winner), "blue", "蓝方获胜")

func test_wave_three_has_cannon_and_high_tower_unlocks_super_minion() -> void:
	var sim := _sim()
	var first_wave_cannon := 0
	for entity in sim.state.entities:
		if entity.type == "minion" and str(entity.get("minion_type", "")) == "cannon":
			first_wave_cannon += 1
	eq(first_wave_cannon, 0, "首波没有炮车")
	eq(_count(sim, "minion", func(entity): return str(entity.get("minion_type", "")) == "ranged"), 2, "双方各一名远程兵")

	sim.state.wave = 2
	sim.state.wave_timer = 0.001
	sim.tick(0.01)
	gt(_count(sim, "minion", func(entity): return str(entity.get("minion_type", "")) == "cannon"), 0, "第三波开始出现炮车")

	_kill(sim, _tower(sim, "red", "mid", "outer"))
	_kill(sim, _tower(sim, "red", "mid", "inner"))
	_kill(sim, _tower(sim, "red", "mid", "high"))
	sim.state.wave_timer = 0.001
	sim.tick(0.01)
	gt(_count(sim, "minion", func(entity): return entity.team == "blue" and str(entity.get("minion_type", "")) == "super"), 0, "红方高地塔倒下后蓝方出超级兵")

func test_jungle_camps_spawn_buff_monsters_and_apply_buffs() -> void:
	var sim := _sim()
	var monsters: Array = sim.state.entities.filter(func(entity): return entity.type == "monster" and not bool(entity.get("objective", false)))
	eq(monsters.size(), 12, "12 个野点各一只野怪")
	var buff_monsters: Array = monsters.filter(func(entity): return str(entity.get("buff_type", "")) != "")
	var small_monsters: Array = monsters.filter(func(entity): return str(entity.get("buff_type", "")) == "")
	eq(buff_monsters.size(), 4, "四个 buff 怪")
	eq(small_monsters.size(), 8, "八个小野点")
	for monster in buff_monsters:
		eq(str(monster.team), "neutral", "野怪中立")
		check(str(monster.get("buff_type", "")) in ["blue", "red"], "buff 怪携带红蓝增益")
	for monster in small_monsters:
		gt(float(monster.get("xp", 0.0)), 0.0, "小野点也要给经验")
	var hero: Dictionary = sim.get_hero_by_player("p1")
	var blue_camp: Dictionary = buff_monsters.filter(func(monster): return str(monster.get("buff_type", "")) == "blue")[0]
	_kill(sim, blue_camp, int(hero.id))
	gt(float(hero.get("buff_blue_timer", 0.0)), 0.0, "击杀蓝BUFF野怪后获得蓝增益")
	check(not bool(blue_camp.alive), "野怪死亡")

func test_objectives_spawn_at_two_minutes_and_grant_team_buff() -> void:
	var sim := _sim()
	eq(_count(sim, "monster", func(entity): return bool(entity.get("objective", false))), 0, "两分钟前首领未刷新")
	sim.state.objective.spawn_timer = 0.001
	sim.tick(0.01)
	eq(_count(sim, "monster", func(entity): return bool(entity.get("objective", false))), 2, "两分钟后暴君与主宰同时刷新")
	var hero: Dictionary = sim.get_hero_by_player("p1")
	var boss: Dictionary = sim.state.entities.filter(func(entity): return entity.type == "monster" and bool(entity.get("objective", false)))[0]
	_kill(sim, boss, int(hero.id))
	gt(float(sim.state.objectives.buffs.blue), 0.0, "击杀首领后蓝方获得增伤")
	eq(float(sim.state.objectives.buffs.red), 0.0, "红方没有增益")

func test_snapshot_exposes_map_fields_and_filters_enemy_vision() -> void:
	var sim := _sim()
	var snap: Dictionary = sim.snapshot()
	var tower: Dictionary = snap.entities.filter(func(entity): return entity.type == "tower")[0]
	check(tower.has("tier"), "塔快照携带层级")
	check(tower.has("vulnerable"), "塔快照携带可攻击状态")
	var monster: Dictionary = snap.entities.filter(func(entity): return entity.type == "monster")[0]
	check(monster.has("monster_type") and monster.has("camp_id"), "野怪快照携带类型与营地")
	var hero: Dictionary = snap.entities.filter(func(entity): return entity.type == "hero" and entity.owner_id == "p1")[0]
	check(hero.has("recalling") and hero.has("recall_timer"), "英雄快照携带回城状态")
	check(hero.has("buff_red_timer") and hero.has("buff_blue_timer"), "英雄快照携带野区增益")
	check(snap.has("objectives"), "快照携带首领与团队增益状态")

	var blue_view: Dictionary = sim.snapshot_for("blue")
	var blue_ids: Array = blue_view.entities.map(func(entity): return entity.id)
	var blue_hero: Dictionary = snap.entities.filter(func(entity): return entity.type == "hero" and entity.team == "blue")[0]
	var red_hero: Dictionary = snap.entities.filter(func(entity): return entity.type == "hero" and entity.team == "red")[0]
	check(blue_ids.has(blue_hero.id), "己方英雄在视野快照中")
	check(not blue_ids.has(red_hero.id), "远处敌方英雄不在视野快照中")
	eq(blue_view.entities.size() < snap.entities.size(), true, "视野快照必须剔除不可见单位")

func test_network_whitelist_carries_new_map_fields() -> void:
	var result: Dictionary = NetProtocol.sanitize_snapshot({
		"time": 1.0,
		"mode": "team",
		"bounds": 58.0,
		"entities": [
			{"id": 1, "type": "monster", "team": "neutral", "x": 0.0, "y": 0.0, "alive": true, "monster_type": "wolf", "camp_id": "blue_buff_blue", "buff_type": "blue", "objective": false},
			{"id": 2, "type": "tower", "team": "red", "lane": "mid", "tier": "high", "x": 1.0, "y": 1.0, "alive": true, "vulnerable": false},
			{"id": 3, "type": "minion", "team": "blue", "lane": "mid", "minion_type": "cannon", "x": 2.0, "y": 2.0, "alive": true},
		],
		"objectives": {"spawn_timer": 60.0, "blue_buff": 12.0, "red_buff": 0.0},
		"scores": {},
		"events": [],
	})
	check(bool(result.ok), "带地图字段的快照通过白名单")
	var snapshot: Dictionary = result.snapshot
	eq(str(snapshot.entities[0].type), "monster", "野怪类型保留")
	eq(str(snapshot.entities[0].monster_type), "wolf", "野怪模型类型保留")
	eq(str(snapshot.entities[1].tier), "high", "塔层级保留")
	eq(bool(snapshot.entities[1].vulnerable), false, "塔可攻击状态保留")
	eq(str(snapshot.entities[2].minion_type), "cannon", "兵种保留")
	near(float(snapshot.objectives.spawn_timer), 60.0, 0.001, "首领计时保留")
	eq(bool(NetProtocol.sanitize_input({"recall": true}).recall), true, "回城输入通过白名单")
