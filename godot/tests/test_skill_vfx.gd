extends "res://tests/test_base.gd"

# 技能特效契约：
# 任何技能（Q/W/E/R）与召唤师技能都必须产出「渲染请求」，且配方按技能 kind 区分，
# 而不是按英雄类型。渲染层只消费 SkillFx.requests()，不允许再按事件名各写一套。
#
# 背景：W/R 走 SkillSystem.cast_skill()，发出的事件是 skill_cast / summoner_cast，
# 而 arena 只处理 type == "skill"。于是大招放出去毫无表现，且不报任何错。

const SkillFx = preload("res://scripts/game/skill_fx.gd")
const HeroDefs = preload("res://sim/hero_defs.gd")
const SkillSystem = preload("res://sim/skill_system.gd")
const MatchSim = preload("res://sim/match_sim.gd")
const UnitVisual = preload("res://scripts/game/unit_visual.gd")
const Arena = preload("res://scripts/game/arena.gd")

const ALL_KINDS := [
	"slash", "spin", "dash", "leap_slam", "burst", "line", "slow", "meteor_storm",
	"quake", "charge", "shield", "taunt_aura", "arrow", "aoe_shot", "haste",
	"arrow_barrage", "evade",
]

func _create_sim() -> MatchSim:
	return MatchSim.new({
		"mode": "duel",
		"humans": [
			{"id": "p1", "team": "blue", "hero_type": "blade"},
			{"id": "p2", "team": "red", "hero_type": "tank"},
		],
		"bot_fill": false,
	})

func test_every_hero_skill_kind_has_recipe() -> void:
	var kinds := {}
	for hero_type in HeroDefs.HEROES:
		var def: Dictionary = HeroDefs.get_hero(str(hero_type))
		for slot in ["q", "w", "e", "r"]:
			var skill: Dictionary = def.get(slot, {})
			var kind := str(skill.get("kind", ""))
			if kind != "":
				kinds[kind] = true
	gt(float(kinds.size()), 8.0, "英雄技能 kind 数量")
	for kind in kinds:
		var recipe: Dictionary = SkillFx.recipe(str(kind))
		check(not recipe.is_empty(), "%s 必须有特效配方" % str(kind))
		var rings: Array = recipe.get("rings", [])
		var particles: Array = recipe.get("particles", [])
		check(rings.size() + particles.size() > 0, "%s 至少要有环或粒子" % str(kind))

func test_unknown_kind_falls_back_instead_of_going_silent() -> void:
	var recipe: Dictionary = SkillFx.recipe("kind_that_does_not_exist")
	check(not recipe.is_empty(), "未知 kind 必须有兜底配方，不能静默无特效")
	var rings: Array = recipe.get("rings", [])
	var particles: Array = recipe.get("particles", [])
	check(rings.size() + particles.size() > 0, "兜底配方也要有可见元素")

func test_different_kinds_have_different_recipes() -> void:
	var seen := {}
	for kind in ALL_KINDS:
		var recipe: Dictionary = SkillFx.recipe(str(kind))
		var key := "%s|%s|%s|%s" % [
			str(recipe.get("rings", [])),
			str(recipe.get("particles", [])),
			str(recipe.get("projectile", 0.0)),
			str(recipe.get("trail", 0)),
		]
		seen[key] = true
	gt(float(seen.size()), 10.0, "17 种 kind 的配方不能大面积撞车")
	check(str(SkillFx.recipe("slash")) != str(SkillFx.recipe("spin")), "苍刃 Q 与 W 必须长得不一样")

func test_w_and_r_emit_renderable_payload() -> void:
	var sim := _create_sim()
	var blue: Dictionary = sim.get_hero_by_player("p1")
	var red: Dictionary = sim.get_hero_by_player("p2")
	red["pos"] = (blue["pos"] as Vector2) + Vector2(2.0, 0.0)
	sim.consume_events()
	SkillSystem.cast_skill(blue, "w", red["pos"], sim)
	SkillSystem.cast_skill(blue, "r", red["pos"], sim)
	var requests: Array = SkillFx.requests(sim.consume_events())
	eq(requests.size(), 2, "W/R 各产出一条渲染请求")
	if requests.size() < 2:
		return
	var expect_slot := ["w", "r"]
	var expect_kind := ["spin", "leap_slam"]
	for index in 2:
		var request: Dictionary = requests[index]
		eq(str(request.get("slot", "")), str(expect_slot[index]), "槽位透传")
		eq(str(request.get("kind", "")), str(expect_kind[index]), "kind 透传")
		eq(str(request.get("hero_type", "")), "blade", "英雄类型透传")
		check(not (request.get("recipe", {}) as Dictionary).is_empty(), "%s 配方非空" % str(expect_slot[index]))
		check((request.get("aim", Vector2.ZERO) as Vector2).distance_to(Vector2.ZERO) > 0.1, "%s 有瞄准点" % str(expect_slot[index]))

func test_summoner_spell_has_render_request() -> void:
	var sim := _create_sim()
	var blue: Dictionary = sim.get_hero_by_player("p1")
	var start: Vector2 = blue["pos"]
	sim.consume_events()
	SkillSystem.cast_summoner_spell(blue, "flash", start + Vector2(2.0, 0.0), sim)
	var requests: Array = SkillFx.requests(sim.consume_events())
	eq(requests.size(), 1, "召唤师技能也走同一条渲染链路")
	if requests.is_empty():
		return
	eq(str(requests[0].get("summoner", "")), "flash", "召唤师技能标识")
	check(not (requests[0].get("recipe", {}) as Dictionary).is_empty(), "闪现配方非空")

func test_q_and_e_events_still_render() -> void:
	var requests: Array = SkillFx.requests([
		{"type": "skill", "slot": "q", "hero": 7, "hero_type": "blade", "kind": "slash", "x": 0.0, "y": 0.0, "aim_x": 3.0, "aim_y": 0.0},
		{"type": "skill", "slot": "e", "hero": 7, "hero_type": "blade", "kind": "dash", "x": 0.0, "y": 0.0, "aim_x": 5.0, "aim_y": 0.0},
	])
	eq(requests.size(), 2, "Q/E 事件仍产出请求")
	if requests.size() < 2:
		return
	eq(int(requests[0].get("hero_id", -1)), 7, "Q 取 hero 字段")
	eq(str(requests[1].get("kind", "")), "dash", "E 的 kind 透传")

func test_old_event_without_kind_still_renders() -> void:
	var requests: Array = SkillFx.requests([
		{"type": "skill", "slot": "w", "hero": 3, "hero_type": "mage", "x": 1.0, "y": 2.0, "aim_x": 4.0, "aim_y": 2.0},
	])
	eq(requests.size(), 1, "缺 kind 的老事件不能丢")
	if requests.is_empty():
		return
	eq(str(requests[0].get("kind", "")), "line", "按 hero_type + slot 反查 kind")

func test_cast_animation_differs_per_slot() -> void:
	for hero_type in ["blade", "archer", "assassin", "mage"]:
		var e_anim := UnitVisual.cast_anim("e", str(hero_type))
		var r_anim := UnitVisual.cast_anim("r", str(hero_type))
		var w_anim := UnitVisual.cast_anim("w", str(hero_type))
		check(r_anim != e_anim, "%s 的大招不能播 E 的动作" % str(hero_type))
		check(w_anim != e_anim, "%s 的 W 不能播 E 的动作" % str(hero_type))
		check(r_anim != "", "%s 大招动作非空" % str(hero_type))

# 端到端接线：arena 真的把 skill_cast / summoner_cast 交给了技能表现链路。
# 只测 SkillFx 不够 —— 上一版就是「函数写好了、arena 没调用」，测试全绿但玩家看不到。
func test_arena_dispatches_every_skill_event_to_fx() -> void:
	var arena: Node3D = Arena.new()
	# 不建 3D 特效节点：_spawn_skill_fx 在计数之后就会早退，避免在无头环境里建节点/开补间。
	arena._process_events([
		{"type": "skill", "slot": "q", "hero": 1, "hero_type": "blade", "kind": "slash", "x": 0.0, "y": 0.0, "aim_x": 2.0, "aim_y": 0.0},
		{"type": "skill_cast", "slot": "w", "caster_id": 1, "hero_type": "blade", "kind": "spin", "x": 0.0, "y": 0.0, "aim_x": 2.0, "aim_y": 0.0},
		{"type": "skill_cast", "slot": "r", "caster_id": 1, "hero_type": "blade", "kind": "leap_slam", "x": 0.0, "y": 0.0, "aim_x": 3.0, "aim_y": 0.0},
		{"type": "summoner_cast", "caster_id": 1, "spell_id": "flash", "hero_type": "blade", "x": 0.0, "y": 0.0, "aim_x": 4.0, "aim_y": 0.0},
	])
	eq(arena.skill_fx_count, 4, "Q / W / R / 召唤师技能都要接到技能表现链路")
	arena.free()

# 粒子池是固定大小的：池空时不能「静默丢掉这一簇」，而要抢占最老的那簇。
# 抢占有两个必须守住的不变量：① 同一个节点不会被同时借给两处；
# ② 池与活动列表永不相交（相交就意味着同一节点会被两处同时改颜色/位置）。
func test_particle_slot_pick_never_borrows_the_same_node_twice() -> void:
	var pool := ["n0", "n1", "n2"]
	var active := []
	var steals := 0
	for i in 8:
		var slot: Dictionary = Arena.take_particle_slot(pool, active)
		check(not slot.is_empty(), "第 %d 次取用不能失败（池空了要抢占，不能返回空）" % i)
		if slot.is_empty():
			return
		var node: String = str(slot.get("node", ""))
		check(not active.has(node), "借出的节点不能在活动列表里重复出现")
		if bool(slot.get("stolen", false)):
			steals += 1
		active.append(node)
		for held in active:
			check(not pool.has(held), "同一个节点不能同时在池和活动列表里")
	eq(active.size(), 3, "活动节点数恒等于池容量，不会偷偷新建")
	eq(steals, 5, "池空之后每次都靠抢占解决")
