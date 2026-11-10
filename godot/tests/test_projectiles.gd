extends "res://tests/test_base.gd"

# 项 3：弹道飞行。非指向技能在 sim 内成为**实体**，飞行途中才结算命中。
#
# 这一组守的是差距文档 §3.2 认定的"操作上限层面最根本的差距"：
# 改造前所有技能在施放的那个 tick 就 _damage 完毕，arena 只是事后补一段
# "弹丸飞过去"的特效。落点在按下瞬间就定了，玩家**物理上不可能**靠走位规避。
#
# 判定原则：
#   - 只把"真的飞出去"的远程技能变成投射物；
#   - 位移/自身增益/近战范围保持瞬发（它们本来就没有飞行过程）；
#   - 伤害仍走 _damage —— 护甲/魔抗/减伤只有一份实现，弹道不复制它。

const MatchSim = preload("res://sim/match_sim.gd")
const SkillSystem = preload("res://sim/skill_system.gd")
const ProjectileSystem = preload("res://sim/projectile_system.gd")
const HeroDefs = preload("res://sim/hero_defs.gd")
const TargetingRulesRef = preload("res://sim/targeting_rules.gd")
const NetProtocol = preload("res://net/net_protocol.gd")

func _duel(blue_hero: String, red_hero: String) -> Object:
	return MatchSim.new({
		"mode": "duel",
		"humans": [
			{"id": "p1", "team": "blue", "hero_type": blue_hero},
			{"id": "p2", "team": "red", "hero_type": red_hero},
		],
		"bot_fill": false,
		"bot_ai": false,
	})

func _projectiles(sim: Object) -> Array:
	var out: Array = []
	for e in sim.state.entities:
		if str(e.get("type", "")) == "projectile":
			out.append(e)
	return out

# ---------------------------------------------------------------- 证据：延后结算

func test_arrow_skill_does_not_damage_on_the_cast_tick() -> void:
	# 改造前：施放瞬间 hp 就掉。改造后：先有弹道实体，命中才掉血。
	# 这是项 3 的核心断言 —— 它同时证明"不是瞬发"和"确实发射了实体"。
	var sim := _duel("archer", "tank")
	var me: Dictionary = sim.get_hero_by_player("p1")
	var foe: Dictionary = sim.get_hero_by_player("p2")
	foe["pos"] = me.pos + Vector2(6.0, 0.0)
	var hp_before := float(foe.hp)
	var ok := SkillSystem.cast_skill(me, "q", foe.pos, sim)
	check(ok, "射手 Q 必须能施放")
	check(float(foe.hp) == hp_before, "施放当 tick 不应扣血（旧行为是瞬发结算）")
	var flying := _projectiles(sim)
	gt(flying.size(), 0, "必须真的生成投射物实体，而不是只发一段特效")

func test_projectile_eventually_hits_a_stationary_target() -> void:
	# 延后结算不能变成"永远打不中"。站着不动的目标必须被命中。
	var sim := _duel("archer", "tank")
	var me: Dictionary = sim.get_hero_by_player("p1")
	var foe: Dictionary = sim.get_hero_by_player("p2")
	foe["pos"] = me.pos + Vector2(6.0, 0.0)
	var hp_before := float(foe.hp)
	SkillSystem.cast_skill(me, "q", foe.pos, sim)
	var dt := 1.0 / MatchSim.TICK_RATE
	for i in 60:
		sim.tick(dt)
		sim.consume_events()
		if float(foe.hp) < hp_before - 1.0:
			break
	lt(float(foe.hp), hp_before - 1.0, "站着不动的目标最终必须被命中")

func test_single_target_projectile_is_destroyed_on_hit() -> void:
	# 命中即销毁是"单体弹"的定义。若不销毁，同一发子弹会沿路径继续飞，
	# 把沿途每个敌人都打一遍 —— 那是一发普攻秒团的形态。
	# 用判定函数直接验证：命中后该实体必须 alive=false。
	var proj := {
		"type": "projectile", "team": "blue", "id": 1, "pos": Vector2.ZERO,
		"dir": Vector2.RIGHT, "speed": 26.0, "radius": 0.45, "aoe_radius": 0.0,
		"lifetime": 2.5, "age": 0.0, "alive": true, "hit_ids": [], "target_mode": "single",
	}
	var victim := {
		"id": 55, "type": "hero", "team": "red", "alive": true, "hp": 100.0,
		"pos": Vector2(0.6, 0.0), "radius": 0.5,
	}
	var entities := [proj, victim]
	var hits: Array = ProjectileSystem.tick(entities, 1.0 / MatchSim.TICK_RATE)
	gt(hits.size(), 0, "前置条件：这一 tick 必须命中")
	eq(bool(proj.get("alive", true)), false, "单体弹命中后必须立刻销毁")
	# 反向对照：范围弹命中后必须**继续飞**（贯穿），否则陨石只能打一个人。
	var aoe_proj := proj.duplicate(true)
	aoe_proj["aoe_radius"] = 2.0
	aoe_proj["target_mode"] = "aoe"
	aoe_proj["hit_ids"] = []
	aoe_proj["alive"] = true
	var aoe_hits: Array = ProjectileSystem.tick([aoe_proj, victim.duplicate(true)], 1.0 / MatchSim.TICK_RATE)
	gt(aoe_hits.size(), 0, "前置条件：范围弹这一 tick 必须命中")
	eq(bool(aoe_proj.get("alive", true)), true, "范围弹命中后必须继续飞行（贯穿）")

func test_expired_projectile_is_marked_dead() -> void:
	# 寿命兜底：即使一路都没撞到东西也必须消失。
	# 旧断言只看"最终实体数为 0"，而 cleanup 在 tick 末尾无条件清扫，
	# 于是 alive 标志根本没被置 false 也照样变 0 —— 那条断言是恒真的。
	# 这里直接断 alive 标志本身。
	var proj := {
		"type": "projectile", "team": "blue", "id": 2, "pos": Vector2.ZERO,
		"dir": Vector2.RIGHT, "speed": 26.0, "radius": 0.45, "aoe_radius": 0.0,
		"lifetime": 0.05, "age": 0.0, "alive": true, "hit_ids": [], "target_mode": "single",
	}
	var entities := [proj]
	# 空地，没有任何目标；推两 tick 让 age 超过 lifetime。
	ProjectileSystem.tick(entities, 1.0 / MatchSim.TICK_RATE)
	ProjectileSystem.tick(entities, 1.0 / MatchSim.TICK_RATE)
	eq(bool(proj.get("alive", true)), false, "超过寿命的投射物必须被标记销毁")

func test_projectiles_are_reclaimed_and_do_not_accumulate() -> void:
	# 每个 tick 都在 append 实体。若不回收，一场对局会堆上万实体，
	# 表现为越打越卡（而且是那种"看起来只是性能差"的隐性 bug）。
	var sim := _duel("archer", "tank")
	var me: Dictionary = sim.get_hero_by_player("p1")
	var foe: Dictionary = sim.get_hero_by_player("p2")
	foe["pos"] = me.pos + Vector2(20.0, 0.0)
	var dt := 1.0 / MatchSim.TICK_RATE
	for shot in 5:
		me["skill_q_cd"] = 0.0
		me["mp"] = 999.0
		SkillSystem.cast_skill(me, "q", foe.pos, sim)
		for i in 120:
			sim.tick(dt)
			sim.consume_events()
	eq(_projectiles(sim).size(), 0, "飞完的投射物必须被回收，不能无限累积")

# ---------------------------------------------------------------- 证据：可被走位规避

func test_standing_still_is_hit_but_dodging_is_missed() -> void:
	# 同一发子弹、同一个初始瞄准点，唯一变量是"目标有没有横移"。
	# 这是差距文档 §3.2 说"物理上不可能 miss"的那个断言的直接反证。
	var still_hit := _fire_at_dodging_target(false)
	var dodged_hit := _fire_at_dodging_target(true)
	eq(still_hit, true, "不动的目标必须被命中（对照组）")
	eq(dodged_hit, false, "横移躲开的目标必须 miss —— 否则走位规避仍然不存在")

func _fire_at_dodging_target(dodge: bool) -> bool:
	var sim := _duel("archer", "tank")
	var me: Dictionary = sim.get_hero_by_player("p1")
	var foe: Dictionary = sim.get_hero_by_player("p2")
	# 6m 距离、弹速 26 m/s ≈ 0.23s 飞行（约 7 帧）。
	# 走位速度必须取英雄**真实移速**级别：用 4 m/s 这种慢速时，
	# 7 帧只横移 0.8m，小于判定半径（弹体 0.45 + 目标 body），
	# 于是"躲了还是中"——那是测量参数不当，不是弹道没生效。
	# 这里取 7 m/s（苍刃/翎羽一档），7 帧横移 ≈1.6m，明确大于判定宽度。
	foe["pos"] = me.pos + Vector2(6.0, 0.0)
	var aim: Vector2 = foe.pos
	var hp_before := float(foe.hp)
	SkillSystem.cast_skill(me, "q", aim, sim)
	var dt := 1.0 / MatchSim.TICK_RATE
	var dodge_step := Vector2(0.0, 7.0 * dt)
	for i in 60:
		if dodge:
			foe["pos"] = (foe.get("pos", aim) as Vector2) + dodge_step
		sim.tick(dt)
		sim.consume_events()
		if float(foe.hp) < hp_before - 1.0:
			return true
		if _projectiles(sim).is_empty():
			break
	return float(foe.hp) < hp_before - 1.0

func test_fast_projectile_never_tunnels_through_a_thin_target() -> void:
	# 一步走 26/30 ≈ 0.87m。若命中判定只检查**落点**而不是扫掠线段，
	# 薄目标会被整段跳过 —— 表现为"偶尔不掉血"，是最难复现的一类 bug。
	# 直接对判定函数做单元级验证：构造一个正好落在两点之间的目标。
	var from := Vector2(0.0, 0.0)
	var to := Vector2(4.0, 0.0)
	var proj := {
		"type": "projectile", "team": "blue", "id": 1,
		"radius": 0.45, "aoe_radius": 0.0, "hit_ids": [],
	}
	# 目标中心在 from→to 的中点，但距两端都 2m，远超判定半径 0.45+0.5。
	var mid_target := {
		"id": 77, "type": "hero", "team": "red", "alive": true, "hp": 100.0,
		"pos": Vector2(2.0, 0.0), "radius": 0.5,
	}
	var entities := [proj, mid_target]
	var hit: Dictionary = ProjectileSystem._resolve(proj, from, to, entities)
	check(not hit.is_empty(), "扫掠线段必须抓到落在中段的目标（单点判定会漏）")
	# 反向对照：把目标挪到线段之外 3m，必须抓不到。
	mid_target["pos"] = Vector2(2.0, 3.0)
	eq(ProjectileSystem._resolve(proj, from, to, entities).is_empty(), true, "线段外的目标不能被命中")

func test_projectiles_are_never_valid_targets() -> void:
	# 变异验证 P4 的教训：只断"英雄能选中"是不够的 ——
	# 必须直接断"投射物自身不可选中"，且要用**带 hp 的**投射物来试，
	# 否则 `has("hp")` 那道守卫被删掉也测不出来（真实投射物碰巧没有 hp）。
	var fake_with_hp := {
		"id": 88888, "type": "projectile", "team": "red", "alive": true,
		"hp": 999.0, "pos": Vector2.ZERO, "radius": 0.45,
	}
	eq(TargetingRulesRef.is_combat_unit(fake_with_hp), false,
		"即使带 hp，type=projectile 也不是战斗单位")
	# 真实索敌里混入这样一枚弹体，英雄仍必须选到真目标。
	var sim := _duel("blade", "tank")
	var me: Dictionary = sim.get_hero_by_player("p1")
	var foe: Dictionary = sim.get_hero_by_player("p2")
	foe["pos"] = me.pos + Vector2(1.5, 0.0)
	sim.state.entities.append(fake_with_hp.duplicate(true))
	sim.state.entities[sim.state.entities.size() - 1]["pos"] = me.pos + Vector2(0.1, 0.0)
	var picked: Dictionary = TargetingRulesRef.resolve_attack_target(
		me, sim.state.entities, "default", -1, Vector2.ZERO)
	eq(int(picked.get("id", -1)), int(foe.id), "索敌不能选中带 hp 的投射物")

# ---------------------------------------------------------------- 联机：弹道必须过白名单

func test_projectile_survives_the_wire() -> void:
	# 仓库反复踩过的坑：新实体只在单机生效，联机静默丢（GDScript 读不到键不报错）。
	# 这条直接走"真 sim 快照 → 协议清洗"两段，验证客机能拿到画弹道所需的全部字段。
	var sim := _duel("archer", "tank")
	var me: Dictionary = sim.get_hero_by_player("p1")
	var foe: Dictionary = sim.get_hero_by_player("p2")
	foe["pos"] = me.pos + Vector2(8.0, 3.0)
	SkillSystem.cast_skill(me, "q", foe.pos, sim)
	var snapshot: Dictionary = sim.snapshot()
	# 先在原始快照里确认真的有一枚弹，否则下面的断言会"空过"。
	var raw_projectiles := 0
	for e in snapshot.get("entities", []):
		if str(e.get("type", "")) == "projectile":
			raw_projectiles += 1
	gt(raw_projectiles, 0, "前置条件：快照里必须有投射物")
	var wire: Dictionary = NetProtocol.sanitize_snapshot(snapshot)
	eq(bool(wire.get("ok", false)), true, "前置条件：快照必须通过协议校验")
	# 注意层级：sanitize_snapshot 返回 {ok, snapshot:{...}}，实体在 wire["snapshot"]["entities"]。
	# 直接查 wire["entities"] 会永远为空 —— 那种"写错层级"的测试会伪装成功能缺失。
	var wire_snapshot: Dictionary = wire.get("snapshot", {})
	var seen := 0
	for e in wire_snapshot.get("entities", []):
		if str(e.get("type", "")) != "projectile":
			continue
		seen += 1
		# 方向必须是单位向量：客机靠它外推位置，非单位向量会让弹道速度失控。
		var dx := float(e.get("dir_x", 0.0))
		var dy := float(e.get("dir_y", 0.0))
		var length := sqrt(dx * dx + dy * dy)
		# W2 教训：协议端曾把缺失的 dir_x 默认成 1.0，归一化后得到 (0.94,0.33)，
		# 与真实方向 (0.94,0.35) 极其接近 —— "快照漏发方向"于是伪装成"弹道略歪"，
		# 断言全绿。现在缺失一律输出零向量，所以下面两条能真正抓住它。
		gt(length, 0.001, "方向不能是零向量（说明 dir_x/dir_y 没传到客机）")
		near(length, 1.0, 0.02, "清洗后的方向必须是单位向量（实得 %.3f）" % length)
		gt(float(e.get("speed", 0.0)), 0.0, "客机需要速度才能外推位置")
		gt(float(e.get("lifetime", 0.0)), 0.0, "客机需要寿命才能决定何时移除")
		check(str(e.get("kind", "")) != "", "客机需要 kind 决定弹体外观")
		# W2 教训：只断"是单位向量"抓不住"方向字段丢了"——
		# 协议端给 dir_x 的默认值是 1.0，丢了以后 (1,0) 依然是单位向量，断言恒真。
		# 必须拿清洗后的方向**与发射时的真实方向比对**。
		var shot_dir: Vector2 = ((foe.pos as Vector2) - (me.pos as Vector2)).normalized()
		var wire_dir := Vector2(dx, dy)
		check(wire_dir.dot(shot_dir) > 0.99,
			"清洗后的方向必须与发射方向一致（发射 %s vs 收到 %s）" % [str(shot_dir), str(wire_dir)])
	gt(seen, 0, "投射物必须通过 ENTITY_TYPES 白名单（否则联机看不到弹道）")

func test_wire_never_carries_projectile_damage() -> void:
	# 信任根在主机：客机不结算伤害，所以协议不该下发 damage。
	# 下发了就等于给客机一份"我可以自己扣血"的数据，是伪造入口。
	var raw := {
		"bounds": 64.0,
		"mode": "duel",
		"time": 1.0,
		"ended": false,
		"entities": [{
			"id": 1, "type": "projectile", "team": "blue",
			"x": 0.0, "y": 0.0, "radius": 0.45, "hp": 0.0, "max_hp": 0.0, "alive": true,
			"dir_x": 1.0, "dir_y": 0.0, "speed": 26.0, "lifetime": 1.0, "age": 0.0,
			"kind": "arrow", "slot": "q", "owner_id": 3, "aoe_radius": 0.0,
			"damage": 185.0, "hit_ids": [7, 8], "target_mode": "single",
		}],
		"events": [],
	}
	var wire: Dictionary = NetProtocol.sanitize_snapshot(raw)
	eq(bool(wire.get("ok", false)), true, "前置条件：快照必须通过协议校验")
	var wire_entities: Array = wire.get("snapshot", {}).get("entities", [])
	var entity: Dictionary = wire_entities[0] if not wire_entities.is_empty() else {}
	check(not entity.is_empty(), "前置条件：投射物必须保留")
	eq(entity.has("damage"), false, "协议不得下发 damage（客机不结算伤害）")
	eq(entity.has("hit_ids"), false, "协议不得下发 hit_ids（主机内部记账）")
	eq(entity.has("target_mode"), false, "协议不得下发 target_mode")

# ---------------------------------------------------------------- 边界：不是所有技能都该弹道化

func test_instant_kinds_stay_instant() -> void:
	# 位移/自身增益/近战范围本来就没有飞行过程，硬做成弹道是错的：
	# 会让"按了立刻生效"的操作手感消失，且 E 闪避这类技能根本不该有弹体。
	for kind in ["dash", "shield", "haste", "evade", "leap_slam", "spin", "taunt_aura", "charge"]:
		eq(ProjectileSystem.is_projectile_kind(kind), false, "%s 不应弹道化" % kind)

func test_ranged_kinds_are_projectiles() -> void:
	for kind in ["arrow", "burst", "aoe_shot", "line", "arrow_barrage", "meteor_storm"]:
		eq(ProjectileSystem.is_projectile_kind(kind), true, "%s 必须是投射物" % kind)

func test_dash_skill_still_moves_the_caster_immediately() -> void:
	# 反向守卫：如果为了弹道化把整条 cast 路径改成异步，位移技能会失灵。
	var sim := _duel("blade", "tank")
	var me: Dictionary = sim.get_hero_by_player("p1")
	var start: Vector2 = me.pos
	SkillSystem.cast_skill(me, "e", start + Vector2(5.0, 0.0), sim)
	gt((me.pos as Vector2).distance_to(start), 1.0, "位移技能必须仍然当场位移")
	eq(_projectiles(sim).size(), 0, "位移技能不该生成投射物")

# ---------------------------------------------------------------- 接线：索敌不得选中弹体

func test_targeting_never_selects_a_projectile() -> void:
	# 投射物带 team/pos/alive/radius，能通过所有距离与阵营检查。
	# 一旦被选成目标，普攻会"打在弹道上"，且 _damage 拿不到 hp 会刷脚本错误。
	var TargetingRules = preload("res://sim/targeting_rules.gd")
	eq(TargetingRules.is_combat_unit({"type": "projectile", "alive": true, "pos": Vector2.ZERO}),
		false, "投射物不是战斗单位")
	eq(TargetingRules.is_combat_unit({"type": "hero", "alive": true, "hp": 100.0}), true, "英雄是战斗单位")
	eq(TargetingRules.is_combat_unit({"type": "minion", "alive": true, "hp": 100.0}), true, "小兵是战斗单位")
	eq(TargetingRules.is_combat_unit({"type": "hero", "alive": false, "hp": 100.0}), false, "死掉的英雄不可选")
	# 用真实索敌验证：把一个投射物放在英雄脚下，不能被选中。
	var sim := _duel("blade", "tank")
	var me: Dictionary = sim.get_hero_by_player("p1")
	var foe: Dictionary = sim.get_hero_by_player("p2")
	foe["pos"] = me.pos + Vector2(1.0, 0.0)
	sim.state.entities.append({
		"id": 99999, "type": "projectile", "team": "red", "pos": me.pos + Vector2(0.2, 0.0),
		"alive": true, "radius": 0.45,
	})
	var picked: Dictionary = TargetingRules.resolve_attack_target(me, sim.state.entities, "default", -1, Vector2.ZERO)
	eq(int(picked.get("id", -1)), int(foe.id), "索敌必须选真英雄，不能选投射物")
