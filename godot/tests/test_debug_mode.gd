extends "res://tests/test_base.gd"

# 开发者调试模式契约：
# 1. 作弊开关真的改变模拟结算（无敌 / 无限蓝 / 无冷却），而不是只改 UI。
# 2. 世界操作（加钱 / 升级 / 回血 / 传送 / 清兵 / 刷野）都能落到实体上。
# 3. 调试字段不能进快照；客机拿不到 sim，天然无效。
# 4. 面板调用的每个 backend 方法都必须在 Arena 上存在，入口 F3 必须接线。

const MatchSim = preload("res://sim/match_sim.gd")
const Arena = preload("res://scripts/game/arena.gd")
const DebugPanel = preload("res://scripts/ui/debug_panel.gd")

func _human(id: String, team: String, hero_type := "blade") -> Dictionary:
	return {"id": id, "name": id, "team": team, "hero_type": hero_type}

func _match() -> Object:
	return MatchSim.new({
		"mode": "duel",
		"humans": [_human("p1", "blue"), _human("p2", "red")],
		"bot_fill": false,
		"bot_ai": false,
	})

func _tick_for(sim: Object, seconds: float) -> void:
	var steps := int(ceil(seconds * MatchSim.TICK_RATE))
	for i in steps:
		sim.tick(1.0 / MatchSim.TICK_RATE)

func test_god_mode_blocks_damage_without_stopping_aggro() -> void:
	var sim := _match()
	var blue: Dictionary = sim.get_hero_by_player("p1")
	var red: Dictionary = sim.get_hero_by_player("p2")
	blue["debug_god"] = true
	var hp_before := float(blue.hp)
	sim.apply_damage(int(blue.id), 99999.0, int(red.id))
	near(float(blue.hp), hp_before, 0.001, "无敌时血量不变")
	check(bool(blue.alive), "无敌时不会被击杀")
	eq(int(blue.get("deaths", 0)), 0, "无敌时不计死亡")
	blue["debug_god"] = false
	sim.apply_damage(int(blue.id), 99999.0, int(red.id))
	check(not bool(blue.alive), "关闭无敌后正常死亡")

func test_no_cooldown_zeroes_every_skill_and_summoner_timer() -> void:
	var sim := _match()
	var blue: Dictionary = sim.get_hero_by_player("p1")
	blue["debug_no_cooldown"] = true
	blue["skill_q_cd"] = 5.0
	blue["skill_w_cd"] = 6.0
	blue["skill_e_cd"] = 7.0
	blue["skill_r_cd"] = 8.0
	blue["summoner_cd"] = 30.0
	sim.tick(1.0 / MatchSim.TICK_RATE)
	near(float(blue.skill_q_cd), 0.0, 0.001, "Q 冷却被清零")
	near(float(blue.skill_w_cd), 0.0, 0.001, "W 冷却被清零")
	near(float(blue.skill_e_cd), 0.0, 0.001, "E 冷却被清零")
	near(float(blue.skill_r_cd), 0.0, 0.001, "R 冷却被清零")
	near(float(blue.summoner_cd), 0.0, 0.001, "召唤师技能冷却被清零")
	blue["debug_no_cooldown"] = false
	blue["skill_q_cd"] = 5.0
	sim.tick(1.0 / MatchSim.TICK_RATE)
	gt(float(blue.skill_q_cd), 4.9, "关闭后冷却正常倒计时")

func test_infinite_mana_refills_every_tick() -> void:
	var sim := _match()
	var blue: Dictionary = sim.get_hero_by_player("p1")
	blue["debug_infinite_mana"] = true
	blue["mp"] = 0.0
	sim.tick(1.0 / MatchSim.TICK_RATE)
	near(float(blue.mp), float(blue.max_mp), 0.001, "无限法力每 tick 回满")
	blue["debug_infinite_mana"] = false
	blue["mp"] = 0.0
	sim.tick(1.0 / MatchSim.TICK_RATE)
	lt(float(blue.mp), float(blue.max_mp), "关闭后回到正常回蓝")

func test_debug_gold_level_heal_and_teleport_apply_to_the_hero() -> void:
	var sim := _match()
	var blue: Dictionary = sim.get_hero_by_player("p1")
	eq(int(blue.gold), 0, "初始金币为 0")
	check(sim.debug_add_gold("p1", 1000), "加钱成功")
	eq(int(blue.gold), 1000, "金币加到英雄身上")

	blue["xp"] = 50.0
	check(sim.debug_level_up("p1"), "升级成功")
	eq(int(blue.level), 2, "等级 +1")
	near(float(blue.xp), 0.0, 0.001, "升级只补到刚好一级，不会连升")

	sim.apply_damage(int(blue.id), 200.0, -1)
	check(sim.debug_heal("p1"), "回血成功")
	near(float(blue.hp), float(blue.max_hp), 0.001, "生命回满")
	near(float(blue.mp), float(blue.max_mp), 0.001, "法力回满")

	var destination: Vector2 = (blue.pos as Vector2) + Vector2(2.0, 0.0)
	check(sim.debug_teleport_hero("p1", destination), "传送成功")
	lt((blue.pos as Vector2).distance_to(destination), 1.6, "英雄被传送到目标点附近")

func test_debug_world_actions_clear_minions_and_respawn_monsters() -> void:
	var sim := _match()
	_tick_for(sim, 2.0)
	var minions := 0
	for entity in sim.state.entities:
		if str(entity.get("type", "")) == "minion":
			minions += 1
	gt(float(minions), 0.0, "两秒后第一波小兵已经刷出")
	eq(sim.debug_clear_minions(), minions, "清兵返回实际移除数量")
	for entity in sim.state.entities:
		check(str(entity.get("type", "")) != "minion", "清兵后场上没有小兵")

	var monster: Dictionary = {}
	for entity in sim.state.entities:
		if str(entity.get("type", "")) == "monster":
			monster = entity
			break
	check(not monster.is_empty(), "开局野区有野怪")
	if monster.is_empty():
		return
	sim.apply_damage(int(monster.id), 999999.0, -1)
	check(not bool(monster.alive), "野怪被击杀")
	gt(float(monster.respawn_timer), 0.0, "野怪进入重生倒计时")
	check(sim.debug_respawn_monsters() >= 1, "刷野至少复活一只")
	check(bool(monster.alive), "野怪复活")
	near(float(monster.hp), float(monster.max_hp), 0.001, "复活后满血")

func test_debug_flags_never_leak_into_snapshots() -> void:
	var sim := _match()
	var blue: Dictionary = sim.get_hero_by_player("p1")
	blue["debug_god"] = true
	blue["debug_no_cooldown"] = true
	blue["debug_infinite_mana"] = true
	var shot: Dictionary = sim.snapshot()
	var found := false
	for entity in shot.get("entities", []):
		if int(entity.get("id", -1)) != int(blue.id):
			continue
		found = true
		check(not entity.has("debug_god"), "调试字段不能下发到快照")
		check(not entity.has("debug_no_cooldown"), "调试字段不能下发到快照")
		check(not entity.has("debug_infinite_mana"), "调试字段不能下发到快照")
	check(found, "快照里包含本地英雄")

func test_arena_exposes_every_debug_panel_command() -> void:
	var arena := Arena.new()
	for method in [
		"debug_metrics", "debug_set_time_scale", "debug_set_paused", "debug_step",
		"debug_set_god", "debug_set_infinite_mana", "debug_set_no_cooldown",
		"debug_add_gold", "debug_level_up", "debug_heal", "debug_teleport_to_cursor",
		"debug_clear_minions", "debug_respawn_camps", "debug_set_reveal",
		"debug_set_no_hit_stop", "debug_set_no_shake",
	]:
		check(arena.has_method(method), "DebugPanel 调用的方法必须存在：" + method)
	# 面板用 _call(has_method) 静默跳过不存在的接口，源码守卫是唯一能抓住漏接线的测试。
	var source := FileAccess.get_file_as_string("res://scripts/game/arena.gd")
	check(has_live_line(source, "KEY_F3"), "F3 必须接线到调试面板")
	check(has_live_line(source, "_build_debug_panel()"), "战场构建时必须装配调试面板")
	check(has_live_line(source, "_trigger_hit_stop"), "顿帧触发要经过可关闭的包装")
	arena.free()

func test_debug_panel_builds_and_disables_cheats_on_guests() -> void:
	var arena := Arena.new()
	var panel = DebugPanel.new()
	panel.setup(arena)
	panel.set_open(true)
	check(panel.root != null, "面板宿主已创建")
	check(panel._status.text.contains("FPS"), "状态栏显示 FPS/实体数")
	check(not panel._cheat_controls.is_empty(), "面板注册了作弊控件")
	arena.authoritative = false
	panel._refresh_status()
	for control in panel._cheat_controls:
		check(control.disabled, "客机必须禁用所有作弊控件")
	panel.free()
	arena.free()
