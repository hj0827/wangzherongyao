extends "res://tests/test_base.gd"

# 项 2：技能等级化 + 大招解锁门槛（验收表 2.1–2.4，差距文档 §3.2）。
#
# 本项定身的规则：
#  - 每升 1 级获得 1 点技能点（1 级不给）。
#  - Q/W/E 出生 1 级、上限 6 级；R 出生 **0 级 = 未学习**，上限 3 级。
#    用 0 而不是"1 级但锁住"：否则会出现「等级 1 却放不出来」的歧义状态，
#    伤害公式也得额外解释一次。
#  - 技能伤害 = 表内 damage + damage_grow * (技能等级 - 1)，两条施法路径同源
#    （Q/E 走 match_sim，W/R 走 skill_system）。
#  - R 只能在英雄 4/7/10 级时升到 1/2/3 级。
#  - 默认按英雄预设方案自动加点（移动端不能忍受逐次手点），可切手动。
#
# 时序隔离同项 1：英雄搬到场心，避开基地火力（射程 9）与泉水。

const MatchSim = preload("res://sim/match_sim.gd")
const SkillSystem = preload("res://sim/skill_system.gd")
const HeroDefs = preload("res://sim/hero_defs.gd")
const NetProtocol = preload("res://net/net_protocol.gd")
# TouchLayout 没有 class_name（其余 UI 类有），必须显式 preload 才能按类名引用。
const TouchLayout = preload("res://scripts/ui/touch_layout.gd")
const SkillGlyph = preload("res://scripts/ui/skill_glyph.gd")
const Arena = preload("res://scripts/game/arena.gd")
const TICK := 1.0 / 30.0

func _duel(attacker_type := "blade", victim_type := "tank", auto_points := true) -> Dictionary:
	var sim := MatchSim.new({
		"mode": "duel",
		"humans": [_human("p1", "blue", attacker_type), _human("p2", "red", victim_type)],
		"auto_skill_points": auto_points,
	})
	var a: Dictionary = sim.get_hero_by_player("p1")
	var b: Dictionary = sim.get_hero_by_player("p2")
	a.pos = Vector2.ZERO
	b.pos = Vector2(3.0, 0)
	a.last_damage_time = 0.0
	b.last_damage_time = 0.0
	return {"sim": sim, "a": a, "b": b}

func _human(id: String, team: String, hero_type: String) -> Dictionary:
	return {"id": id, "name": id, "team": team, "hero_type": hero_type}

# 精确升 1 级：喂"刚好够升一级"的经验。
# 两个坑都要避开：
#  - 不能喂 100000 这种大数 —— _add_xp 的 while 会一路冲到 MAX_LEVEL，
#    于是"升 1 级"的断言全在测 15 级。
#  - 要先清零残留经验，否则原本快升级的英雄喂"一级所需"会连升两级。
func _gain_levels(sim: Object, hero: Dictionary, levels: int) -> void:
	for i in levels:
		if int(hero.level) >= MatchSim.MAX_LEVEL:
			return
		hero.xp = 0.0
		sim._add_xp(hero, sim._xp_needed(int(hero.level)))

func _q_damage(sim: Object, attacker: Dictionary, victim: Dictionary) -> float:
	attacker.skill_q_cd = 0.0
	attacker.mp = float(attacker.max_mp)
	victim.hp = victim.max_hp
	var before := float(victim.hp)
	sim._cast_q(attacker, victim.pos)
	return before - float(victim.hp)

func _w_damage(sim: Object, attacker: Dictionary, victim: Dictionary) -> float:
	attacker.skill_w_cd = 0.0
	attacker.mp = float(attacker.max_mp)
	victim.hp = victim.max_hp
	var before := float(victim.hp)
	SkillSystem.cast_skill(attacker, "w", victim.pos, sim)
	return before - float(victim.hp)

func _r_damage(sim: Object, attacker: Dictionary, victim: Dictionary) -> float:
	attacker.skill_r_cd = 0.0
	attacker.mp = float(attacker.max_mp)
	victim.hp = victim.max_hp
	var before := float(victim.hp)
	SkillSystem.cast_skill(attacker, "r", victim.pos, sim)
	return before - float(victim.hp)

# ---------------------------------------------------------------- 2.1 技能点 / 等级 / 成长

func test_hero_starts_with_normal_skills_learned_and_ult_unlearned() -> void:
	var hero: Dictionary = _duel().a
	eq(int(hero.get("skill_q_level", -1)), 1, "Q 出生 1 级")
	eq(int(hero.get("skill_w_level", -1)), 1, "W 出生 1 级")
	eq(int(hero.get("skill_e_level", -1)), 1, "E 出生 1 级")
	eq(int(hero.get("skill_r_level", -99)), 0, "R 出生 0 级 = 未学习")
	eq(int(hero.get("skill_points", -1)), 0, "1 级没有技能点")

func test_each_hero_level_awards_one_skill_point() -> void:
	var ctx := _duel("blade", "tank", false)
	var sim: Object = ctx.sim
	var hero: Dictionary = ctx.a
	_gain_levels(sim, hero, 1)
	eq(int(hero.level), 2, "升到 2 级")
	eq(int(hero.skill_points), 1, "升到 2 级给 1 点")
	_gain_levels(sim, hero, 4)
	eq(int(hero.skill_points), 5, "累计 5 点（手动模式不代劳）")

func test_spending_a_point_raises_that_skill_level() -> void:
	var ctx := _duel("blade", "tank", false)
	var sim: Object = ctx.sim
	var hero: Dictionary = ctx.a
	_gain_levels(sim, hero, 3)
	var before := int(hero.skill_q_level)
	sim.spend_skill_point(hero, "q")
	eq(int(hero.skill_q_level), before + 1, "加点后 Q 等级 +1")
	eq(int(hero.skill_points), 2, "只消耗 1 点")

func test_skill_level_increases_damage_on_both_cast_paths() -> void:
	# 关键守卫：Q 走 match_sim._cast_q，W 走 skill_system.cast_skill。
	# 只有一条路径读技能等级 = 一半技能永远不成长，而且不报错。
	var ctx := _duel("blade", "tank", false)
	var sim: Object = ctx.sim
	var hero: Dictionary = ctx.a
	var victim: Dictionary = ctx.b
	_gain_levels(sim, hero, 10)
	hero.skill_points = 20
	sim.spend_skill_point(hero, "q")
	sim.spend_skill_point(hero, "q")
	var q_lv3 := _q_damage(sim, hero, victim)
	var grow := float(HeroDefs.get_hero("blade").q.get("damage_grow", 0.0))
	hero.skill_q_level = 1
	var q_lv1 := _q_damage(sim, hero, victim)
	gt(q_lv3, q_lv1, "Q 3 级必须强于 1 级（%.1f vs %.1f）" % [q_lv3, q_lv1])
	near(q_lv3 - q_lv1, 2.0 * grow, 0.01, "Q 伤害差 = 2 级 * damage_grow（grow=%.1f）" % grow)

	hero.skill_w_level = 3
	var w_lv3 := _w_damage(sim, hero, victim)
	hero.skill_w_level = 1
	var w_lv1 := _w_damage(sim, hero, victim)
	gt(w_lv3, w_lv1, "W（skill_system 路径）也必须随技能等级成长")

func test_damage_grow_is_declared_for_every_damage_skill() -> void:
	# 数据完整性守卫：漏写 damage_grow 会默认 0 = 该技能永远不成长，
	# 数值不报错、测试不红，正是本仓库反复踩的形态。
	var missing: Array[String] = []
	for hero_type in HeroDefs.HEROES:
		var def: Dictionary = HeroDefs.HEROES[hero_type]
		for slot in ["q", "w", "e", "r"]:
			var skill: Variant = def.get(slot, null)
			if not (skill is Dictionary):
				continue
			if float((skill as Dictionary).get("damage", 0.0)) <= 0.0:
				continue
			var grow: Variant = (skill as Dictionary).get("damage_grow", null)
			if grow == null or float(grow) <= 0.0:
				missing.append("%s.%s" % [hero_type, slot])
	check(missing.is_empty(), "伤害技能缺 damage_grow：%s" % ", ".join(missing))

func test_skill_level_is_capped_per_slot() -> void:
	var ctx := _duel("blade", "tank", false)
	var sim: Object = ctx.sim
	var hero: Dictionary = ctx.a
	_gain_levels(sim, hero, 14)
	hero.skill_points = 40
	for i in 12:
		sim.spend_skill_point(hero, "q")
	eq(int(hero.skill_q_level), MatchSim.MAX_SKILL_LEVEL_NORMAL, "Q 封顶 6 级")
	for i in 12:
		sim.spend_skill_point(hero, "r")
	eq(int(hero.skill_r_level), MatchSim.MAX_SKILL_LEVEL_ULT, "R 封顶 3 级")
	gt(int(hero.skill_points), 0, "封顶后点数不被吞掉（还能给别人）")

func test_spending_without_points_fails() -> void:
	var ctx := _duel("blade", "tank", false)
	var sim: Object = ctx.sim
	var hero: Dictionary = ctx.a
	hero.skill_points = 0
	var before := int(hero.skill_q_level)
	check(not sim.spend_skill_point(hero, "q"), "没点不能加")
	eq(int(hero.skill_q_level), before, "等级不变")

func test_spending_on_illegal_slot_is_rejected_without_burning_points() -> void:
	var ctx := _duel("blade", "tank", false)
	var sim: Object = ctx.sim
	var hero: Dictionary = ctx.a
	hero.skill_points = 5
	check(not sim.spend_skill_point(hero, "z"), "非法槽位拒绝")
	check(not sim.spend_skill_point(hero, ""), "空槽位拒绝")
	eq(int(hero.skill_points), 5, "非法请求不吞点")

# ---------------------------------------------------------------- 2.2 大招解锁门槛

func test_ultimate_cannot_be_learned_below_hero_level_four() -> void:
	var ctx := _duel("blade", "tank", false)
	var sim: Object = ctx.sim
	var hero: Dictionary = ctx.a
	_gain_levels(sim, hero, 2)
	eq(int(hero.level), 3, "现在 3 级")
	hero.skill_points = 5
	check(not sim.spend_skill_point(hero, "r"), "3 级不许学大招")
	eq(int(hero.skill_r_level), 0, "R 仍未学习")
	eq(int(hero.skill_points), 5, "被拒的加点不吞点")

func test_ultimate_unlocks_at_four_seven_ten() -> void:
	var ctx := _duel("blade", "tank", false)
	var sim: Object = ctx.sim
	var hero: Dictionary = ctx.a
	hero.skill_points = 20
	# 4 级 → R1
	_gain_levels(sim, hero, 3)
	eq(int(hero.level), 4, "现在 4 级")
	check(sim.spend_skill_point(hero, "r"), "4 级可学 R1")
	eq(int(hero.skill_r_level), 1, "R 到 1 级")
	# 6 级还不能 R2
	_gain_levels(sim, hero, 2)
	eq(int(hero.level), 6, "现在 6 级")
	check(not sim.spend_skill_point(hero, "r"), "6 级不许学 R2（要 7 级）")
	# 7 级 → R2
	_gain_levels(sim, hero, 1)
	eq(int(hero.level), 7, "现在 7 级")
	check(sim.spend_skill_point(hero, "r"), "7 级可学 R2")
	eq(int(hero.skill_r_level), 2, "R 到 2 级")
	# 9 级还不能 R3，10 级可以
	_gain_levels(sim, hero, 2)
	eq(int(hero.level), 9, "现在 9 级")
	check(not sim.spend_skill_point(hero, "r"), "9 级不许学 R3（要 10 级）")
	_gain_levels(sim, hero, 1)
	eq(int(hero.level), 10, "现在 10 级")
	check(sim.spend_skill_point(hero, "r"), "10 级可学 R3")
	eq(int(hero.skill_r_level), 3, "R 到 3 级")

func test_locked_ultimate_cast_fails_without_side_effects() -> void:
	var ctx := _duel("blade", "tank", false)
	var sim: Object = ctx.sim
	var hero: Dictionary = ctx.a
	var victim: Dictionary = ctx.b
	_gain_levels(sim, hero, 2)          # 3 级，R 未学
	var hp_before := float(victim.hp)
	var mp_before := float(hero.mp)
	var ok := SkillSystem.cast_skill(hero, "r", victim.pos, sim)
	check(not ok, "3 级放 R 必须失败")
	eq(float(victim.hp), hp_before, "锁定时不掉血")
	eq(float(hero.skill_r_cd), 0.0, "锁定时不进冷却")
	eq(float(hero.mp), mp_before, "锁定时不扣蓝")

func test_unlocked_ultimate_casts_and_ranks_up() -> void:
	var ctx := _duel("blade", "tank", false)
	var sim: Object = ctx.sim
	var hero: Dictionary = ctx.a
	var victim: Dictionary = ctx.b
	_gain_levels(sim, hero, 3)          # 4 级
	hero.skill_points = 20
	sim.spend_skill_point(hero, "r")
	var dmg_r1 := _r_damage(sim, hero, victim)
	gt(dmg_r1, 0.0, "4 级大招能打出伤害")
	sim.spend_skill_point(hero, "r")     # 需要 7 级，应被拒
	eq(int(hero.skill_r_level), 1, "4 级时 R 仍 1 级")
	_gain_levels(sim, hero, 3)           # 7 级
	check(sim.spend_skill_point(hero, "r"), "7 级可升 R2")
	var dmg_r2 := _r_damage(sim, hero, victim)
	gt(dmg_r2, dmg_r1, "R2 必须强于 R1（%.1f vs %.1f）" % [dmg_r2, dmg_r1])

func test_arena_actually_consults_the_block_reason() -> void:
	# skill_block_reason 有真身、有测试，但如果 arena 不叫它，玩家照样
	# 按了大招没反应又不知道为什么 —— 就是"函数在、测试绿、生产引用 0"。
	# 用 has_live_line 而不是 contains：把调用注释掉时 contains 仍然绿。
	var arena_src := FileAccess.get_file_as_string("res://scripts/game/arena.gd")
	check(has_live_line(arena_src, "_skill_block_reason(slot)"),
		"arena._on_skill_button 必须真的问一次阻塞原因")
	check(has_live_line(arena_src, "HeroDefs.skill_block_reason("),
		"arena 的判定必须委托给 HeroDefs 真身，不能自己再写一份")
	# 反向守卫：旧的那份重复判定不许回来（两份实现会漂移）。
	check(not arena_src.contains("func _skill_blocked"),
		"arena 不该再留一份自己的技能阻塞判定")

func test_block_reason_never_vetoes_non_skill_slots() -> void:
	# 回城 / 传送 / 召唤师也走 arena._on_skill_button 这同一个入口。
	# 如果 skill_block_reason 对这些槽位返回非空（哪怕只是"没有这个技能"），
	# 回城键就会被当成"被否决"直接 return —— 按了没反应，而且不报错。
	# 真身里那句"非技能槽返回空串"就是为这件事存在的，必须钉住。
	var ctx := _duel("blade", "tank", false)
	var hero: Dictionary = ctx.a
	for slot in ["recall", "teleport", "summoner", "attack", ""]:
		eq(HeroDefs.skill_block_reason(hero, slot), "", "%s 不该被技能判定否决" % slot)
	# 快照还没就绪（本地英雄查不到）时也不能否决，否则开局第一帧按什么都没反应。
	eq(HeroDefs.skill_block_reason({}, "q"), "", "空英雄不否决")

func test_locked_ultimate_reports_a_displayable_reason() -> void:
	# HUD 必须能回答"按了为什么没反应"，否则玩家认为游戏卡了。
	var ctx := _duel("blade", "tank", false)
	var sim: Object = ctx.sim
	var hero: Dictionary = ctx.a
	hero.level = 2
	var reason: String = HeroDefs.skill_block_reason(hero, "r")
	check(reason != "", "锁定必须有可显示原因")
	check(str(reason).contains("4"), "原因要说明需要 4 级：%s" % reason)

func test_ready_skill_has_no_block_reason() -> void:
	var ctx := _duel("blade", "tank", false)
	var sim: Object = ctx.sim
	var hero: Dictionary = ctx.a
	hero.level = 6
	hero.skill_q_cd = 0.0
	hero.mp = float(hero.max_mp)
	eq(HeroDefs.skill_block_reason(hero, "q"), "", "可用技能不该有阻塞原因")

func test_block_reason_distinguishes_cooldown_mana_and_lock() -> void:
	var ctx := _duel("blade", "tank", false)
	var sim: Object = ctx.sim
	var hero: Dictionary = ctx.a
	hero.level = 6
	hero.skill_q_cd = 5.0
	check(str(HeroDefs.skill_block_reason(hero, "q")).contains("冷却"), "CD 中要说冷却")
	hero.skill_q_cd = 0.0
	hero.mp = 0.0
	check(str(HeroDefs.skill_block_reason(hero, "q")).contains("法力"), "缺蓝要说法力")

# ---------------------------------------------------------------- 2.4 自动加点（移动端刚需）

func test_auto_plan_spends_points_without_player_input() -> void:
	var ctx := _duel("blade", "tank", true)
	var sim: Object = ctx.sim
	var hero: Dictionary = ctx.a
	_gain_levels(sim, hero, 10)
	eq(int(hero.skill_points), 0, "自动模式下点数被即时分配")
	var total := int(hero.skill_q_level) + int(hero.skill_w_level) + int(hero.skill_e_level) + int(hero.skill_r_level)
	# 出生 q/w/e=1、r=0 合计 3，加 10 点 = 13
	eq(total, 13, "10 点全部落到技能上（实际 q=%d w=%d e=%d r=%d）" % [
		int(hero.skill_q_level), int(hero.skill_w_level), int(hero.skill_e_level), int(hero.skill_r_level)])

func test_auto_plan_learns_ultimate_once_unlocked() -> void:
	var ctx := _duel("blade", "tank", true)
	var sim: Object = ctx.sim
	var hero: Dictionary = ctx.a
	_gain_levels(sim, hero, 2)          # 3 级
	eq(int(hero.skill_r_level), 0, "3 级前自动方案不能点 R（还没解锁）")
	_gain_levels(sim, hero, 1)          # 4 级
	gt(int(hero.skill_r_level), 0, "4 级后自动方案必须把大招学上")

func test_auto_plan_never_exceeds_caps_or_gates() -> void:
	var ctx := _duel("blade", "tank", true)
	var sim: Object = ctx.sim
	var hero: Dictionary = ctx.a
	_gain_levels(sim, hero, 14)         # 顶到 15 级
	eq(int(hero.level), MatchSim.MAX_LEVEL, "顶满 15 级")
	lte_check(hero)

func lte_check(hero: Dictionary) -> void:
	check(int(hero.skill_q_level) <= MatchSim.MAX_SKILL_LEVEL_NORMAL, "Q 不越上限")
	check(int(hero.skill_w_level) <= MatchSim.MAX_SKILL_LEVEL_NORMAL, "W 不越上限")
	check(int(hero.skill_e_level) <= MatchSim.MAX_SKILL_LEVEL_NORMAL, "E 不越上限")
	check(int(hero.skill_r_level) <= MatchSim.MAX_SKILL_LEVEL_ULT, "R 不越上限")
	eq(int(hero.skill_points), 0, "顶满后点数不堆积")

func test_manual_mode_keeps_points_for_the_player() -> void:
	var ctx := _duel("blade", "tank", false)
	var sim: Object = ctx.sim
	var hero: Dictionary = ctx.a
	_gain_levels(sim, hero, 5)
	eq(int(hero.skill_points), 5, "手动模式攒点，等玩家分配")

func test_every_hero_ships_a_level_by_level_skill_plan() -> void:
	# skill_plan 是**逐等级表**（第 i 项 = 升到 i+2 级时点哪个槽），不是优先级列表。
	# 优先级 + "点最低的合法技能" 会和 4/7/10 门槛打架：
	# 表里排到 r 但等级不够时，那一点就被吞掉且不报错，点数永远差一笔。
	# 逐等级表让"哪一级点什么"成为数据，门槛校验只需保证 r 落在 4/7/10。
	var bad: Array[String] = []
	for hero_type in HeroDefs.HEROES:
		var plan: Variant = HeroDefs.HEROES[hero_type].get("skill_plan", null)
		if not (plan is Array):
			bad.append("%s(缺)" % hero_type)
			continue
		if (plan as Array).size() != MatchSim.MAX_LEVEL - 1:
			bad.append("%s(长度%d≠%d)" % [hero_type, (plan as Array).size(), MatchSim.MAX_LEVEL - 1])
	check(bad.is_empty(), "skill_plan 必须是 MAX_LEVEL-1=14 项的逐等级表：%s" % ", ".join(bad))

func test_skill_plan_only_names_legal_slots() -> void:
	var legal := {"q": true, "w": true, "e": true, "r": true}
	var bad: Array[String] = []
	for hero_type in HeroDefs.HEROES:
		var plan: Array = HeroDefs.HEROES[hero_type].get("skill_plan", [])
		for entry in plan:
			if not legal.has(str(entry)):
				bad.append("%s:%s" % [hero_type, str(entry)])
	check(bad.is_empty(), "skill_plan 含非法槽位：%s" % ", ".join(bad))

func test_skill_plan_places_ultimate_only_at_unlock_levels() -> void:
	# 表里 r 必须只出现在 4/7/10 级，否则自动加点会在未解锁时撞门槛、吞点。
	var bad: Array[String] = []
	for hero_type in HeroDefs.HEROES:
		var plan: Array = HeroDefs.HEROES[hero_type].get("skill_plan", [])
		for i in plan.size():
			var level := i + 2   # 第 0 项对应升到 2 级
			if str(plan[i]) == "r" and not MatchSim.ULT_UNLOCK_LEVELS.has(level):
				bad.append("%s 在 %d 级点 R" % [hero_type, level])
	check(bad.is_empty(), "大招加点必须落在解锁级：%s" % ", ".join(bad))

func test_skill_plan_never_exceeds_slot_caps() -> void:
	# 某槽位在表里出现次数超过它的可点次数 = 自动加点会撞上限、吞点。
	# q/w/e 出生 1 级还能点 5 次；r 出生 0 级能点 3 次。
	var bad: Array[String] = []
	for hero_type in HeroDefs.HEROES:
		var plan: Array = HeroDefs.HEROES[hero_type].get("skill_plan", [])
		var counts := {"q": 0, "w": 0, "e": 0, "r": 0}
		for entry in plan:
			var s := str(entry)
			if counts.has(s):
				counts[s] = int(counts[s]) + 1
		for s in ["q", "w", "e"]:
			if int(counts[s]) > MatchSim.MAX_SKILL_LEVEL_NORMAL - 1:
				bad.append("%s.%s=%d" % [hero_type, s, int(counts[s])])
		if int(counts.r) > MatchSim.MAX_SKILL_LEVEL_ULT:
			bad.append("%s.r=%d" % [hero_type, int(counts.r)])
	check(bad.is_empty(), "skill_plan 超出槽位上限：%s" % ", ".join(bad))

# ---------------------------------------------------------------- 链路 3/4：快照与白名单

func test_skill_levels_reach_the_snapshot() -> void:
	var ctx := _duel("blade", "tank", false)
	var sim: Object = ctx.sim
	var hero: Dictionary = ctx.a
	hero.skill_q_level = 4
	hero.skill_w_level = 3
	hero.skill_e_level = 2
	hero.skill_r_level = 2
	hero.skill_points = 3
	var shot: Dictionary = sim._snapshot_entity(hero)
	eq(int(shot.get("skill_q_level", -1)), 4, "snapshot.skill_q_level")
	eq(int(shot.get("skill_w_level", -1)), 3, "snapshot.skill_w_level")
	eq(int(shot.get("skill_e_level", -1)), 2, "snapshot.skill_e_level")
	eq(int(shot.get("skill_r_level", -1)), 2, "snapshot.skill_r_level")
	eq(int(shot.get("skill_points", -1)), 3, "snapshot.skill_points")

func test_skill_levels_survive_the_net_whitelist() -> void:
	# 漏白名单 = 单机正常、客机技能永远显示未学习（且不报错）。
	var clean: Dictionary = NetProtocol._sanitize_entity(_wire_hero({
		"skill_q_level": 4, "skill_w_level": 3, "skill_e_level": 2,
		"skill_r_level": 3, "skill_points": 5,
	}), 58.0)
	eq(int(clean.get("skill_q_level", -1)), 4, "wire.skill_q_level")
	eq(int(clean.get("skill_w_level", -1)), 3, "wire.skill_w_level")
	eq(int(clean.get("skill_e_level", -1)), 2, "wire.skill_e_level")
	eq(int(clean.get("skill_r_level", -1)), 3, "wire.skill_r_level")
	eq(int(clean.get("skill_points", -1)), 5, "wire.skill_points")

func test_whitelist_clamps_hostile_skill_levels() -> void:
	var clean: Dictionary = NetProtocol._sanitize_entity(_wire_hero({
		"skill_q_level": -9, "skill_w_level": 999, "skill_e_level": 2,
		"skill_r_level": 99, "skill_points": 100000,
	}), 58.0)
	eq(int(clean.get("skill_q_level", -1)), 0, "负等级钳到 0")
	check(int(clean.get("skill_w_level", 0)) <= MatchSim.MAX_SKILL_LEVEL_NORMAL, "普通技能钳到上限")
	check(int(clean.get("skill_r_level", 0)) <= MatchSim.MAX_SKILL_LEVEL_ULT, "大招钳到上限")
	check(int(clean.get("skill_points", 0)) <= MatchSim.MAX_LEVEL, "技能点钳到合理上限")

func _wire_hero(overrides: Dictionary) -> Dictionary:
	var hero := {
		"id": 3, "type": "hero", "team": "blue", "alive": true,
		"x": 1.0, "y": 2.0, "hp": 100.0, "max_hp": 200.0, "radius": 0.5,
		"owner_id": "p1", "name": "n", "hero_type": "blade", "controller": "human",
		"lane": "mid", "level": 8, "xp": 0.0, "mp": 10.0, "max_mp": 20.0,
		"kills": 0, "deaths": 0, "speed": 6.0, "shield": 0.0,
	}
	for key in overrides:
		hero[key] = overrides[key]
	return hero

# ---------------------------------------------------------------- 链路 2/4：升级输入键

func test_upgrade_input_is_whitelisted() -> void:
	# 新输入键必须进 EMPTY_INPUT + sanitize_input，否则联机按了没反应。
	var clean: Dictionary = NetProtocol.sanitize_input({"upgrade_slot": "q", "seq": 3})
	eq(str(clean.get("upgrade_slot", "?")), "q", "upgrade_slot 过白名单")
	var hostile: Dictionary = NetProtocol.sanitize_input({"upgrade_slot": "zzz"})
	eq(str(hostile.get("upgrade_slot", "x")), "", "非法槽位清空")
	var empty: Dictionary = NetProtocol.sanitize_input({})
	eq(str(empty.get("upgrade_slot", "x")), "", "缺键默认空串")

func test_input_schema_declares_every_key_that_gets_sanitized() -> void:
	# EMPTY_INPUT 是输入字典的 **schema 声明**（05-ui-and-feel §5.1 要求新键必须进这里）。
	# 只在 sanitize_input 里赋值而漏进 EMPTY_INPUT，功能"碰巧"还能跑
	# （GDScript 给字典赋新键不报错），但声明与实际脱节 ——
	# 下一个人照 EMPTY_INPUT 读输入形状，就会漏掉这个键。
	# 反向也要成立：EMPTY_INPUT 声明了却没被 sanitize 处理 = 该键永远取默认值。
	var declared: Dictionary = NetProtocol.EMPTY_INPUT
	check(declared.has("upgrade_slot"), "EMPTY_INPUT 必须声明 upgrade_slot")
	var sanitized: Dictionary = NetProtocol.sanitize_input({})
	var missing: Array[String] = []
	for key in declared.keys():
		if not sanitized.has(key):
			missing.append(str(key))
	check(missing.is_empty(), "sanitize_input 没有产出 EMPTY_INPUT 声明的键：%s" % ", ".join(missing))
	# arena 侧的 _local_input 必须与协议同构，否则客机提交的字典形状不一致。
	var arena_src := FileAccess.get_file_as_string("res://scripts/game/arena.gd")
	check(arena_src.contains('"upgrade_slot": ""'), "arena._local_input 必须声明同一个键")

func test_upgrade_input_moves_through_the_sim_once() -> void:
	var ctx := _duel("blade", "tank", false)
	var sim: Object = ctx.sim
	var hero: Dictionary = ctx.a
	_gain_levels(sim, hero, 4)
	var before := int(hero.skill_q_level)
	sim.set_input(str(hero.owner_id), {"seq": 1, "upgrade_slot": "q"})
	sim.tick(TICK)
	eq(int(hero.skill_q_level), before + 1, "输入键真的把点加上去")
	eq(int(hero.skill_points), 3, "只消耗 1 点")
	# 意图只消费一次：下一条纯移动输入不能重放加点（与 buy_item 同一套纪律）。
	sim.set_input(str(hero.owner_id), {"seq": 2, "move": Vector2(1, 0)})
	sim.tick(TICK)
	eq(int(hero.skill_q_level), before + 1, "加点意图不被重放")

func test_upgrade_input_survives_the_wire() -> void:
	# 客机发的加点输入过完白名单后仍要能被 sim 消费。
	var raw := {"seq": 7, "upgrade_slot": "w"}
	var clean: Dictionary = NetProtocol.sanitize_input(raw)
	var ctx := _duel("blade", "tank", false)
	var sim: Object = ctx.sim
	var hero: Dictionary = ctx.a
	_gain_levels(sim, hero, 4)
	var before := int(hero.skill_w_level)
	sim.set_input(str(hero.owner_id), clean)
	sim.tick(TICK)
	eq(int(hero.skill_w_level), before + 1, "过网后的加点输入仍然生效")

# ---------------------------------------------------------------- 链路 6：UI 真的读到了

# 三个显示函数都做成 static：外部可用类名直接调，HUD 内部也能直接调，
# 不需要实例化 Control（无头测试里实例化 + _ready 生命周期是另一类坑）。

func test_skill_button_renders_its_level() -> void:
	# 等级进了快照但按钮不显示 = 玩家不知道自己点到几级（且不报错）。
	var text: String = SkillButton.level_caption(3)
	check(text.contains("3"), "按钮要显示技能等级：%s" % text)

func test_skill_button_shows_lock_for_unlearned_ultimate() -> void:
	var locked_text: String = SkillButton.level_caption(0)
	check(locked_text.contains("未学"), "未学大招要显示锁定：%s" % locked_text)
	# 锁定态不能同时显示数字 0，否则玩家以为"0 级也能放"。
	check(not locked_text.contains("0"), "锁定态不显示数字等级：%s" % locked_text)

func test_level_caption_never_outgrows_the_desktop_button() -> void:
	# 项 1 的教训：定宽控件 + clip_text 时，超宽被静默裁掉而字符串断言照样绿。
	# 量的是**真实最坏组合**（最长技能名 + 最大等级读数），不是单独一串 ——
	# 单独量 "6 级" 必然通过，等于没测。
	var font: Font = GameTheme.FONT_REGULAR
	var avail := float(TouchLayout.SKILL_DESKTOP_SIZE.x)
	var worst_w := 0.0
	var worst_text := ""
	for hero_type in HeroDefs.HEROES:
		var def: Dictionary = HeroDefs.HEROES[hero_type]
		for slot in ["q", "w", "e", "r"]:
			var skill: Dictionary = def.get(slot, {})
			if skill.is_empty():
				continue
			var combo := SkillButton.composed_name(str(skill.get("name", "")), HeroDefs.MAX_SKILL_LEVEL_NORMAL)
			var w := font.get_string_size(combo, HORIZONTAL_ALIGNMENT_LEFT, -1, SkillButton.DESKTOP_NAME_SIZE).x
			if w > worst_w:
				worst_w = w
				worst_text = combo
	check(worst_w <= avail,
		"最坏键面读数 '%s' 需要 %.1fpx，桌面键面只有 %.1fpx" % [worst_text, worst_w, avail])

func test_hud_surfaces_remaining_skill_points() -> void:
	# 剩余点数必须可见，否则"攒了 5 点却没提示"等于功能没做。
	var text: String = GameHUD.skill_points_caption({"skill_points": 3})
	check(text.contains("3"), "点数要显示出来：%s" % text)
	var none: String = GameHUD.skill_points_caption({"skill_points": 0})
	eq(none, "", "0 点不占文案位")

func test_hud_wires_skill_levels_into_the_buttons() -> void:
	# 行为守卫，不用源码文本守卫：实现里读的是动态键 "skill_%s_level" % slot，
	# 源码根本不含字面量 skill_q_level，用 contains 查必然假失败；
	# 反过来 contains 查得到也证明不了"真的传给了按钮"。
	# 所以走真实链路：真 sim 出快照 → 真 HUD.update_snapshot → 读按钮字段。
	# （构造方式沿用 test_economy_panel.gd 的 _hud()，那套在无头下已验证可用。）
	var sim := MatchSim.new({
		"mode": "duel",
		"humans": [_human("p1", "blue", "blade"), _human("p2", "red", "tank")],
		"auto_skill_points": false,
		"bot_fill": false,
	})
	var hero: Dictionary = sim.get_hero_by_player("p1")
	hero.skill_q_level = 4
	hero.skill_w_level = 2
	hero.skill_e_level = 6
	hero.skill_r_level = 0
	hero.skill_points = 3
	var hud: Control = GameHUD.new()
	hud.setup("p1", "blue", "blade", "苍刃", false, false)
	hud._ready()
	hud.size = Vector2(1600.0, 900.0)
	hud._apply_layout()
	hud.update_snapshot(sim.snapshot())
	eq(int(hud._skill_q.level), 4, "HUD 必须把 Q 等级传给按钮")
	eq(int(hud._skill_w.level), 2, "HUD 必须把 W 等级传给按钮")
	eq(int(hud._skill_e.level), 6, "HUD 必须把 E 等级传给按钮")
	eq(int(hud._skill_r.level), 0, "未学的大招要传 0，按钮才画得出「未学」")
	check(str(hud._role_label.text).contains("技能点 3"), "状态行要显示剩余点数：%s" % hud._role_label.text)
	# 召唤师键没有等级概念：HUD 必须不传等级（level<0），否则键面会画出一个假的"1级"。
	check(int(hud._summoner_button.level) < 0, "召唤师键不该有技能等级：%d" % int(hud._summoner_button.level))
	hud.free()

func test_touch_button_expresses_locked_state_without_text() -> void:
	# 触屏键面不写技能名（拇指压在上面，名字是噪声），也**写不下等级数字**：
	# 实测圆内右下角（badge 口径）离心 44.1px，距半径 58 只剩 13.9px，
	# 连"6级"（22x22 @14px）都会压出圆外。所以未学状态必须是纯图形。
	# 这条守的是"show_name=false 顺手把未学提示也一起关掉"的连坐失效。
	var touch_skin: Dictionary = SkillButton.skin_metrics(TouchLayout.SKILL_TOUCH_SIZE, true)
	eq(bool(touch_skin["show_name"]), false, "触屏不写技能名")
	eq(bool(touch_skin["show_lock_mark"]), true, "触屏必须能表达未学（图形锁标）")
	var desk_skin: Dictionary = SkillButton.skin_metrics(TouchLayout.SKILL_DESKTOP_SIZE, false)
	eq(bool(desk_skin["show_name"]), true, "桌面写技能名（等级并进同一行）")
	eq(bool(desk_skin["show_lock_mark"]), false, "桌面用文字，不画图形锁标")

func test_lock_mark_geometry_stays_inside_the_circle() -> void:
	# 斜杠端点与线宽都必须落在圆内。尺寸全部按半径比例给，
	# 所以这里验的是"比例本身安全"，而不是某个像素值 —— 换分辨率也不会失效。
	# 端点公式 center ± (0.7071,0.7071)*radius*ratio，合成距离恰为 radius*ratio
	# （(0.7071,0.7071) 是单位向量；写成 Vector2(r,r)*k 会多算 sqrt(2) 倍）。
	var skin: Dictionary = SkillButton.skin_metrics(TouchLayout.SKILL_TOUCH_SIZE, true)
	var radius: float = float(skin["radius"])
	var ratio := float(SkillButton.TOUCH_LOCK_STRIPE_RATIO)
	check(ratio > 0.0 and ratio < 1.0, "斜杠比例必须落在 (0,1)：%f" % ratio)
	var stroke_half := radius * float(SkillButton.TOUCH_LOCK_STROKE_RATIO) * 0.5
	check(radius * ratio + stroke_half < radius,
		"斜杠端点 %.1f + 半线宽 %.1f 越出半径 %.1f" % [radius * ratio, stroke_half, radius])

func test_lock_mark_stroke_stays_readable_not_a_wall() -> void:
	# N26 教训：线宽 0.62r 在几何上"没越界"，但会把整枚图标糊成一条色带，
	# 玩家读不出"被划掉"反而以为键面坏了。几何安全 != 视觉可用，必须分开钉。
	# 斜杠要压在 0.92r 的图标上还能读出图标，线宽就得远小于图标半径。
	var stroke := float(SkillButton.TOUCH_LOCK_STROKE_RATIO)
	var glyph := float(SkillButton.TOUCH_GLYPH_FILL)
	check(stroke > 0.0, "线宽必须是正数：%f" % stroke)
	check(stroke <= 0.2, "斜杠线宽 %.2f 太粗，会糊掉图标（上限 0.2r）" % stroke)
	check(stroke < glyph * 0.35, "线宽 %.2f 必须明显细于图标半径 %.2f，否则读不出斜杠" % [stroke, glyph])
	# 描边与亮线是两层：亮线必须细于描边，否则黑边完全被盖住、失去描边意义。
	check(float(SkillButton.TOUCH_LOCK_CORE_RATIO) < stroke,
		"亮线 %.3f 必须细于黑描边 %.3f" % [float(SkillButton.TOUCH_LOCK_CORE_RATIO), stroke])

func test_lock_mark_only_appears_when_skill_is_unlearned() -> void:
	# N27 教训：判定写在 _draw 里就测不到，改成纯函数才能钉。
	# "已学的技能被画上一道斜杠"比"未学没提示"更糟 —— 玩家会以为技能被禁用了。
	eq(SkillButton.shows_lock_mark(0), true, "未学（0 级）要画锁标")
	eq(SkillButton.shows_lock_mark(1), false, "已学 1 级不能画锁标")
	eq(SkillButton.shows_lock_mark(6), false, "满级不能画锁标")
	eq(SkillButton.shows_lock_mark(-1), false, "召唤师键没有等级概念，不画锁标")

func test_summoner_button_does_not_show_a_skill_level() -> void:
	# 召唤师键没有等级概念。画一个"1级"是错的（会让人以为召唤师技能可以升级）。
	eq(SkillButton.composed_name("闪现", -1), "闪现", "level<0 时不显示等级")

func test_composed_name_actually_prints_the_level() -> void:
	# N22 教训：只验 button.level 字段不够 —— 字段对了但没被组合进键面文案，
	# 玩家照样看不到等级。composed_name 是纯函数，直接钉它的输出。
	var text: String = SkillButton.composed_name("裂空斩", 4)
	check(text.contains("4"), "键面文案必须含等级数字：%s" % text)
	check(text.contains("裂空斩"), "键面文案不能丢掉技能名：%s" % text)
	# 未学的大招：文案是"未学"，不能是"裂地崩山 0"。
	var ult: String = SkillButton.composed_name("裂地崩山", 0)
	check(ult.contains("未学"), "未学大招文案要显示未学：%s" % ult)
	check(not ult.contains("0"), "未学大招文案不能出现数字 0：%s" % ult)

# ---------------------------------------------------------------- bot 侧（不能因新规则卡死）

func test_manual_mode_only_holds_points_for_humans_not_bots() -> void:
	# 设置里关掉自动加点只该影响玩家自己的英雄：bot 没有人点，
	# 若也攒点就会整局不成长（改设置 = 队友变弱），且不报错。
	# 「人类攒点」已由 test_manual_mode_keeps_points_for_the_player 覆盖。
	var sim := MatchSim.new({
		"mode": "team", "humans": [], "bot_fill": true, "bot_ai": true,
		"auto_skill_points": false,
	})
	var tick := 1.0 / MatchSim.TICK_RATE
	for i in int(300.0 * MatchSim.TICK_RATE):
		sim.tick(tick)
		sim.state.events.clear()
	var bots := 0
	var leveled := 0
	for entity in sim.state.entities:
		if str(entity.get("type", "")) != "hero":
			continue
		if str(entity.get("controller", "")) != "bot":
			continue
		bots += 1
		if int(entity.get("level", 1)) > 1:
			leveled += 1
		eq(int(entity.get("skill_points", -1)), 0, "bot 不受玩家自动加点开关影响，点数必须花掉")
	gt(bots, 0, "这局必须有 bot，否则用例空转")
	gt(leveled, 0, "bot 必须真的升过级，否则「点数已花掉」是空断言")

# ---------------------------------------------------------------- B7：触屏手动加点入口

func test_touch_hud_shows_level_button_only_when_points_remain() -> void:
	var hud: Control = GameHUD.new()
	hud.setup("p1", "blue", "blade", "苍刃", true, false)
	hud._ready()
	hud.size = Vector2(1600.0, 900.0)
	hud._apply_layout()
	hud._sync_level_ui({"skill_points": 0})
	check(not hud._level_button.visible, "0 点不显示加点入口")
	hud._sync_level_ui({"skill_points": 2})
	check(hud._level_button.visible, "触屏有剩余点数必须给出加点入口")
	hud.free()

func test_desktop_hud_hides_level_button() -> void:
	var hud: Control = GameHUD.new()
	hud.setup("p1", "blue", "blade", "苍刃", false, false)
	hud._ready()
	hud.size = Vector2(1600.0, 900.0)
	hud._apply_layout()
	hud._sync_level_ui({"skill_points": 2})
	check(not hud._level_button.visible, "桌面有 Ctrl+技能，不重复放按钮")
	hud.free()

func test_level_choice_emits_upgrade_request() -> void:
	var hud: Control = GameHUD.new()
	hud.setup("p1", "blue", "blade", "苍刃", true, false)
	hud._ready()
	hud.size = Vector2(1600.0, 900.0)
	hud._apply_layout()
	var got: Array = []
	hud.upgrade_requested.connect(func(slot): got.append(slot))
	hud._level_panel.visible = true
	hud._on_level_choice("w")
	eq(got, ["w"], "选 W 必须发出 upgrade_requested")
	check(not hud._level_panel.visible, "选择后关闭浮层")
	hud.free()

func test_level_panel_disables_maxed_skill() -> void:
	var hud: Control = GameHUD.new()
	hud.setup("p1", "blue", "blade", "苍刃", true, false)
	hud._ready()
	hud.size = Vector2(1600.0, 900.0)
	hud._apply_layout()
	hud._sync_level_ui({
		"skill_points": 1, "skill_q_level": MatchSim.MAX_SKILL_LEVEL_NORMAL,
		"skill_w_level": 1, "skill_e_level": 1, "skill_r_level": 0,
	})
	check(hud._level_buttons["q"].disabled, "满级技能在浮层里必须置灰")
	check(not hud._level_buttons["w"].disabled, "未满级技能可点")
	check(not hud._level_buttons["r"].disabled, "0 级大招在门口可点（等级门槛交给 sim）")
	hud.free()

func test_arena_accepts_only_legal_upgrade_slots() -> void:
	var arena: Node3D = Arena.new()
	arena._on_upgrade_requested("q")
	eq(arena._queued_upgrade, "q", "合法槽位进队列")
	arena._on_upgrade_requested("z")
	eq(arena._queued_upgrade, "q", "非法槽位不得覆盖队列")
	arena.free()

func test_bots_level_their_skills_and_cast_their_ultimate() -> void:
	# 验收表 2.4 的真机口径：不操作也能正常成长。bot 走同一套自动方案。
	var sim := MatchSim.new({
		"mode": "team", "humans": [], "bot_fill": true, "bot_ai": true,
	})
	var tick := 1.0 / MatchSim.TICK_RATE
	for i in int(300.0 * MatchSim.TICK_RATE):
		sim.tick(tick)
		sim.state.events.clear()
	var learned_normal := 0
	var learned_ult := 0
	for entity in sim.state.entities:
		if str(entity.get("type", "")) != "hero":
			continue
		if int(entity.get("level", 1)) < 4:
			continue
		learned_normal += 1
		if int(entity.get("skill_r_level", 0)) >= 1:
			learned_ult += 1
	gt(learned_normal, 0, "5 分钟内应有英雄升到 4 级以上")
	eq(learned_ult, learned_normal, "升到 4 级的 bot 都必须被自动方案学上大招")
	for entity in sim.state.entities:
		if str(entity.get("type", "")) != "hero":
			continue
		eq(int(entity.get("skill_points", -1)), 0, "bot 的点数不该堆积")
