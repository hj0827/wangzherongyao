extends "res://tests/test_base.gd"

# C4/C6：节奏标定旋钮（验收 6.3「首塔时刻带收敛」）。
#
# 首塔时刻由「塔血 / 保护期 / 兵线成长」三者联动决定，而调它们会连带影响
# 项 2 的大招门槛（验收表 6.3 已注明这个耦合）。所以两头都要钉死：
#   ① 默认值必须与 2026-11-10 的标定基线逐位相同 —— 否则"标定"会静默漂移；
#   ② config["balance"] 的覆盖必须真的落到实体上 —— 否则旋钮是假的，
#      下次有人按 --balance= 调参时会发现数字纹丝不动（本仓库最典型的静默失效）。
const MatchSim = preload("res://sim/match_sim.gd")
const TowerRules = preload("res://sim/map/tower_rules.gd")

func _duel(balance := {}) -> Object:
	var cfg := {"mode": "duel", "humans": [], "bot_fill": true, "bot_ai": true}
	if not balance.is_empty():
		cfg["balance"] = balance
	return MatchSim.new(cfg)

func _tower(sim: Object, team: String, tier: String) -> Dictionary:
	for e in sim.state.entities:
		if str(e.get("type", "")) == "tower" and str(e.get("team", "")) == team \
				and str(e.get("tier", "")) == tier:
			return e
	return {}

func _first_minion(sim: Object) -> Dictionary:
	for e in sim.state.entities:
		if str(e.get("type", "")) == "minion":
			return e
	return {}

# ---------------------------------------------------------------- 基线值

func test_default_tower_and_wave_values_are_the_documented_baseline() -> void:
	# 标定基线：外/内/高地塔 2800/3200/3600，塔攻 150/170/190，兵线 18 秒一波，
	# 保护期 180 秒内对塔伤害 50%。这些数字写进汇报后就不该再悄悄改。
	eq(float(MatchSim.TOWER_HP["outer"]), 2800.0, "外塔血量基线")
	eq(float(MatchSim.TOWER_HP["inner"]), 3200.0, "内塔血量基线")
	eq(float(MatchSim.TOWER_HP["high"]), 3600.0, "高地塔血量基线")
	eq(float(MatchSim.TOWER_DAMAGE["outer"]), 150.0, "外塔攻击基线")
	eq(float(MatchSim.WAVE_INTERVAL), 18.0, "兵线间隔基线")
	eq(float(TowerRules.EARLY_PROTECTION_TIME), 180.0, "塔保护期基线")
	near(TowerRules.damage_scale({"type": "tower"}, 30.0), 0.5, 0.001, "保护期内对塔伤害 50%")
	near(TowerRules.damage_scale({"type": "tower"}, 200.0), 1.0, 0.001, "保护期结束后恢复 100%")
	near(float(MatchSim.BALANCE_DEFAULTS["tower_hp_scale"]), 1.3, 0.001, "默认塔血 ×1.3（C4/C6 标定版）")
	near(float(MatchSim.BALANCE_DEFAULTS["minion_hp_scale"]), 1.0, 0.001, "默认不缩放小兵血量")

func test_default_match_uses_calibrated_tower_hp() -> void:
	# 不传 balance 的对局必须与标定版一致：外塔 2800 × 1.3 = 3640。
	# 小兵数值不缩放（首波仍是 458 血 / 36.4 攻），避免把兵线节奏一起带偏。
	var sim := _duel()
	var tower := _tower(sim, "blue", "outer")
	check(not tower.is_empty(), "外塔必须存在")
	near(float(tower.hp), 2800.0 * 1.3, 0.01, "默认外塔血量 = 3640")
	sim.tick(MatchSim.FIRST_WAVE_DELAY + 0.1)
	var minion := _first_minion(sim)
	check(not minion.is_empty(), "首波兵必须已刷出")
	near(float(minion.max_hp), 420.0 + 38.0, 0.01, "默认首波近战兵血量不变")
	near(float(minion.attack_damage), 34.0 + 2.4, 0.01, "默认首波近战兵攻击不变")

# ---------------------------------------------------------------- 旋钮真的生效

func test_balance_overrides_reach_towers_minions_and_protection() -> void:
	var sim := _duel({
		"tower_hp_scale": 2.0,
		"tower_damage_scale": 1.5,
		"minion_hp_scale": 2.0,
		"minion_damage_scale": 0.5,
		"wave_interval_scale": 2.0,
		"early_protection_time": 600.0,
		"early_protection_damage_scale": 0.25,
	})
	var tower := _tower(sim, "blue", "outer")
	check(not tower.is_empty(), "外塔必须存在")
	near(float(tower.hp), 5600.0, 0.01, "tower_hp_scale=2 → 外塔 5600")
	near(float(tower.max_hp), 5600.0, 0.01, "max_hp 同步缩放")
	near(float(tower.attack_damage), 225.0, 0.01, "tower_damage_scale=1.5 → 225")

	sim.tick(MatchSim.FIRST_WAVE_DELAY + 0.1)
	var minion := _first_minion(sim)
	check(not minion.is_empty(), "首波兵必须已刷出")
	near(float(minion.max_hp), 916.0, 0.01, "minion_hp_scale=2 → 458*2")
	near(float(minion.attack_damage), 18.2, 0.01, "minion_damage_scale=0.5 → 36.4*0.5")
	# 首波在 MatchSim._init 里就用 _update_wave(FIRST_WAVE_DELAY) 刷出，
	# 构造完成时 wave_timer 已是 36；所以 tick(1.1) 全部扣在下一波计时上。
	near(float(sim.state.wave_timer), MatchSim.WAVE_INTERVAL * 2.0 - 1.1, 0.01,
		"wave_interval_scale=2 → 下一波 36 秒")

	near(TowerRules.damage_scale(tower, 300.0,
		sim.balance_value("early_protection_time"),
		sim.balance_value("early_protection_damage_scale")), 0.25, 0.001,
		"覆盖后的保护期参数必须被 _damage 实际使用")

# ---------------------------------------------------------------- C7：5v5 节奏回归

func test_five_v_five_bot_match_stays_inside_the_pacing_band() -> void:
	# 验收 6.2：加入装备后局时曾从 8:04 回弹到 15:00，此后没有持续断言。
	# 用固定种子跑完一整局 bot 5v5，把「局时」与「首塔」钉成回归带：
	# 上限抓回弹（15:00 那种），下限抓被压得过紧。
	# 单局替代不了抽样工具的分布结论，但足以在数值改动后第一时间报警。
	var sim := MatchSim.new({
		"mode": "team", "humans": [], "bot_fill": true, "bot_ai": true,
		"seed": 0x2F6E2B1,
		"bot_comp": ["blade", "tank", "assassin", "mage", "archer"],
	})
	var dt := 1.0 / MatchSim.TICK_RATE
	var first_tower := -1.0
	var limit := 900.0
	while not sim.ended and sim.state.time < limit:
		sim.tick(dt)
		for ev in sim.consume_events():
			if str(ev.get("type", "")) == "tower_destroyed" and first_tower < 0.0:
				first_tower = float(sim.state.time)
	check(sim.ended, "5v5 bot 对局必须在 15 分钟内结束，否则节奏已回弹")
	if not sim.ended:
		return
	var duration := float(sim.state.time)
	check(duration >= 420.0, "局时 %.0fs 低于 7 分钟，节奏被压得过紧" % duration)
	check(duration <= 810.0, "局时 %.0fs 超过 13.5 分钟，节奏回弹（曾回到 15:00）" % duration)
	check(first_tower > 0.0, "整局必须能观测到首塔")
	check(first_tower >= 60.0, "首塔 %.0fs 早于 1 分钟，对线期被压没了" % first_tower)
	check(first_tower <= 360.0, "首塔 %.0fs 晚于 6 分钟，推塔节奏过慢" % first_tower)
