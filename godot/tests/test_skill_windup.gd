extends "res://tests/test_base.gd"

# 项 3.3：技能前摇 / 后摇 / 打断（A3）。
#
# 规则真身在 match_sim 的 _begin_cast / _tick_casts：
#   1. 起手即扣蓝、进 CD；前摇结束才结算伤害。
#   2. 前摇吃硬控 -> 打断：退蓝、不退 CD，并发 skill_interrupt。
#   3. 结算后进入 recover：禁施法/普攻、不禁移动。
#
# 这些用例都走"输入 -> tick"的完整链路，而不是直调 _cast_r：
# 直调会绕过前摇，测不到本次改造。

const MatchSim = preload("res://sim/match_sim.gd")
const HeroDefs = preload("res://sim/hero_defs.gd")
const NetProtocol = preload("res://net/net_protocol.gd")
const TICK := 1.0 / 30.0

func _human(id: String, team: String, hero_type := "blade") -> Dictionary:
	return {"id": id, "name": id, "team": team, "hero_type": hero_type}

func _duel() -> Dictionary:
	# 场心对峙：离两座基地 65 米、离外塔 18 米，一次 tick 内不会被基地/塔干扰。
	var sim := MatchSim.new({
		"mode": "duel",
		"humans": [_human("p1", "blue", "blade"), _human("p2", "red", "tank")],
	})
	var blue: Dictionary = sim.get_hero_by_player("p1")
	var red: Dictionary = sim.get_hero_by_player("p2")
	blue.pos = Vector2.ZERO
	red.pos = Vector2(3.0, 0.0)
	blue.last_damage_time = 0.0
	red.last_damage_time = 0.0
	# 大招出生 0 级 = 未学习；直接点 1 级让本用例只验证前摇本身。
	blue["skill_r_level"] = 1
	sim.consume_events()
	return {"sim": sim, "blue": blue, "red": red}

func _input(overrides := {}) -> Dictionary:
	var out := {
		"seq": 1,
		"move": Vector2.ZERO,
		"aim": Vector2.ZERO,
		"skill_q": false,
		"skill_w": false,
		"skill_e": false,
		"skill_r": false,
	}
	for key in overrides:
		out[key] = overrides[key]
	return out

func _tick_for(sim: Object, seconds: float) -> void:
	var steps := int(ceil(seconds * MatchSim.TICK_RATE))
	for i in steps:
		sim.tick(TICK)

func _events_of(sim: Object, type: String) -> Array:
	return sim.consume_events().filter(func(ev): return str(ev.get("type", "")) == type)

# ---------------------------------------------------------------- 前摇窗口

func test_ult_spends_resources_at_windup_start_but_damage_lands_after_it() -> void:
	var ctx := _duel()
	var sim: Object = ctx.sim
	var blue: Dictionary = ctx.blue
	var red: Dictionary = ctx.red
	var hp0 := float(red.hp)
	var mp0 := float(blue.mp)
	sim.set_input("p1", _input({"aim": red.pos, "skill_r": true}))
	sim.tick(TICK)
	eq(str(blue.get("cast_slot", "")), "r", "按下大招必须先进入前摇，不能立刻结算")
	gt(float(blue.get("cast_left", 0.0)), 0.0, "前摇计时必须开始走")
	near(float(red.hp), hp0, 0.01, "前摇期间不能造成伤害")
	gt(float(blue.skill_r_cd), 0.0, "起手即进 CD（打断也不返还）")
	gt(mp0 - float(blue.mp), 90.0, "起手即扣蓝（大招 100，留一点回复余量）")
	sim.tick(TICK)
	near(float(red.hp), hp0, 0.01, "第二帧仍在前摇，不该提前结算")
	_tick_for(sim, 0.6)
	lt(float(red.hp), hp0, "前摇结束后伤害必须落地")
	eq(str(blue.get("cast_slot", "")), "", "结算后必须清空起手态")
	eq(_events_of(sim, "skill").size() > 0, true, "结算时必须补发 skill 事件给表现层")

# ---------------------------------------------------------------- 硬控打断

func test_hard_cc_during_windup_refunds_mana_keeps_cooldown_and_emits_interrupt() -> void:
	var ctx := _duel()
	var sim: Object = ctx.sim
	var blue: Dictionary = ctx.blue
	var red: Dictionary = ctx.red
	var hp0 := float(red.hp)
	var mp0 := float(blue.mp)
	sim.set_input("p1", _input({"aim": red.pos, "skill_r": true}))
	sim.tick(TICK)
	var mp_after_start := float(blue.mp)
	check(mp_after_start < mp0 - 90.0, "前置条件：起手必须已经扣蓝")
	var cd_after_start := float(blue.skill_r_cd)
	# 直接施加眩晕：等价于"看到起手再交控"。
	blue.stun_timer = 0.6
	sim.tick(TICK)
	eq(str(blue.get("cast_slot", "")), "", "前摇中吃硬控必须打断起手")
	gt(float(blue.mp), mp_after_start + 90.0, "打断必须退蓝")
	near(float(blue.skill_r_cd), cd_after_start - TICK, 0.05, "打断不退 CD")
	near(float(red.hp), hp0, 0.01, "被打断的技能不能造成伤害")
	var interrupts := _events_of(sim, "skill_interrupt")
	eq(interrupts.size(), 1, "打断必须发一条 skill_interrupt")
	if interrupts.size() == 1:
		eq(str(interrupts[0].get("slot", "")), "r", "事件必须带被打断的槽位")
		eq(str(interrupts[0].get("reason", "")), "control", "事件必须标明是被控打断")

# ---------------------------------------------------------------- 后摇

func test_recover_blocks_a_follow_up_cast_but_not_movement() -> void:
	var ctx := _duel()
	var sim: Object = ctx.sim
	var blue: Dictionary = ctx.blue
	var red: Dictionary = ctx.red
	sim.set_input("p1", _input({"aim": red.pos, "skill_r": true}))
	_tick_for(sim, 0.5)
	eq(str(blue.get("cast_slot", "")), "", "前置条件：前摇已结束")
	gt(float(blue.get("cast_recover", 0.0)), 0.0, "结算后必须进入后摇")
	var mp_before := float(blue.mp)
	# 后摇期间按 Q（不耗蓝、CD 空闲）：必须被后摇挡住。
	sim.set_input("p1", _input({"aim": red.pos, "skill_q": true}))
	sim.tick(TICK)
	eq(str(blue.get("cast_slot", "")), "", "后摇期间不能再起手")
	gt(float(blue.mp), mp_before - 1.0, "被后摇挡住的施法不能扣蓝")
	# 后摇结束后同一发 Q 能正常起手。输入保持按住，等后摇归零的那一帧自动起手。
	var started := false
	for i in 60:
		sim.tick(TICK)
		if str(blue.get("cast_slot", "")) == "q":
			started = true
			break
	check(started, "后摇结束后必须恢复施法")

# ---------------------------------------------------------------- 数据与协议

func test_every_skill_declares_a_windup_and_ults_are_the_slowest() -> void:
	for hero_type in HeroDefs.HEROES.keys():
		var hero_def: Dictionary = HeroDefs.get_hero(str(hero_type))
		for slot in HeroDefs.SKILL_SLOTS:
			check(hero_def.has(slot), "技能表缺槽位 %s/%s" % [hero_type, slot])
			var skill: Dictionary = hero_def[slot]
			check(skill.has("windup"), "技能必须声明 windup：%s/%s" % [hero_type, slot])
			check(skill.has("recover"), "技能必须声明 recover：%s/%s" % [hero_type, slot])
			gt(float(skill.get("windup", -1.0)), 0.0, "前摇必须为正：%s/%s" % [hero_type, slot])
		gt(float(hero_def.r.get("windup", 0.0)), 0.28, "大招前摇必须明显长于小技能：%s" % hero_type)

func test_cast_state_survives_the_wire_and_rejects_bad_slots() -> void:
	var ctx := _duel()
	var sim: Object = ctx.sim
	var blue: Dictionary = ctx.blue
	blue["cast_slot"] = "r"
	blue["cast_left"] = 0.3
	blue["cast_recover"] = 0.0
	var snapshot: Dictionary = sim.snapshot()
	var wire: Dictionary = NetProtocol.sanitize_snapshot(snapshot)
	eq(bool(wire.get("ok", false)), true, "前置条件：快照必须通过协议校验")
	var found := {}
	for entity in wire.get("snapshot", {}).get("entities", []):
		if int(entity.get("id", -1)) == int(blue["id"]):
			found = entity
			break
	check(not found.is_empty(), "客机必须收到该英雄")
	eq(str(found.get("cast_slot", "")), "r", "起手槽位必须过白名单")
	near(float(found.get("cast_left", 0.0)), 0.3, 0.001, "前摇剩余时间必须过白名单")
	# 伪造槽位必须被丢弃，避免客机按任意字符串画特效。
	var forged := snapshot.duplicate(true)
	for entity in forged.get("entities", []):
		if int(entity.get("id", -1)) == int(blue["id"]):
			entity["cast_slot"] = "not_a_slot"
			break
	var forged_wire: Dictionary = NetProtocol.sanitize_snapshot(forged)
	var forged_found := {}
	for entity in forged_wire.get("snapshot", {}).get("entities", []):
		if int(entity.get("id", -1)) == int(blue["id"]):
			forged_found = entity
			break
	eq(str(forged_found.get("cast_slot", "")), "", "非法槽位必须被协议层清空")
