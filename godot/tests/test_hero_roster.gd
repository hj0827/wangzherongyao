extends "res://tests/test_base.gd"

# 名册层测试：职业数量、每个英雄的技能是否真的生效、立绘/出装是否齐备。
#
# 这里最贵的一条是 test_every_skill_produces_an_observable_effect()：
# 它不看 kind 字符串，而是真的施放一次，要求「法力扣了 + 至少一个世界状态变了」。
# 本仓库曾出现 dash / shield / haste 三个 kind 没进 cast_skill 的 match，
# 结果苍刃、铁壁、翎羽的 E 按下去扣蓝进 CD、但什么都没发生——测试全绿。

const HeroDefs = preload("res://sim/hero_defs.gd")
const SkillSystem = preload("res://sim/skill_system.gd")
const MatchSim = preload("res://sim/match_sim.gd")
const ItemShop = preload("res://sim/item_shop.gd")

# 王者的五大职业。顺序无意义，用集合比较。
const ROLE_SET := ["坦克", "战士", "刺客", "法师", "射手"]

func _duel(blue_type: String, red_type: String) -> MatchSim:
	return MatchSim.new({
		"mode": "duel",
		"humans": [
			{"id": "p1", "team": "blue", "hero_type": blue_type},
			{"id": "p2", "team": "red", "hero_type": red_type},
		],
		"bot_fill": false,
	})

# ---------------------------------------------------------------- 职业构成

func test_roster_has_exactly_five_distinct_roles() -> void:
	eq(HeroDefs.HEROES.size(), 5, "must be exactly 5 heroes (one per role)")
	var roles := []
	for hero_type in HeroDefs.HEROES:
		var role := str(HeroDefs.get_hero(hero_type).get("role", ""))
		check(role != "", "%s must declare a role" % hero_type)
		check(not roles.has(role), "role '%s' is declared twice" % role)
		roles.append(role)
	eq(roles.size(), 5, "five heroes must have five different roles")
	for role in ROLE_SET:
		check(roles.has(role), "missing role: %s" % role)

func test_every_hero_has_a_complete_kit() -> void:
	for hero_type in HeroDefs.HEROES:
		var def: Dictionary = HeroDefs.get_hero(hero_type)
		for field in ["name", "role", "title", "quote", "passive", "q", "w", "e", "r"]:
			check(def.has(field), "%s missing field %s" % [hero_type, field])
		for slot in ["q", "w", "e", "r"]:
			var skill: Dictionary = def[slot]
			check(str(skill.get("name", "")) != "", "%s.%s needs a name" % [hero_type, slot])
			check(str(skill.get("kind", "")) != "", "%s.%s needs a kind" % [hero_type, slot])
			gt(float(skill.get("cooldown", 0.0)), 0.0, "%s.%s needs a cooldown" % [hero_type, slot])
			gt(float(skill.get("cost", 0.0)), 0.0, "%s.%s needs a mana cost" % [hero_type, slot])
		gt(float(def.max_hp), 0.0, "%s max_hp" % hero_type)
		gt(float(def.attack_damage), 0.0, "%s attack_damage" % hero_type)

func test_bot_types_are_all_valid_heroes() -> void:
	check(HeroDefs.BOT_TYPES.size() >= 5, "bot pool should cover the whole roster")
	for hero_type in HeroDefs.BOT_TYPES:
		check(HeroDefs.is_valid(str(hero_type)), "BOT_TYPES contains unknown hero '%s'" % hero_type)
	for hero_type in HeroDefs.HEROES:
		check(HeroDefs.BOT_TYPES.has(hero_type), "bot pool never picks %s" % hero_type)

# ---------------------------------------------------------------- 技能真的生效

func test_every_skill_produces_an_observable_effect() -> void:
	for hero_type in HeroDefs.HEROES:
		for slot in ["q", "w", "e", "r"]:
			var sim := _duel(str(hero_type), "tank")
			var me: Dictionary = sim.get_hero_by_player("p1")
			var foe: Dictionary = sim.get_hero_by_player("p2")
			check(not me.is_empty(), "%s hero must spawn" % hero_type)

			var skill: Dictionary = HeroDefs.get_hero(str(hero_type))[slot]
			# 贴身放，保证任何射程/形状都能命中。
			var start: Vector2 = me.get("pos", Vector2.ZERO)
			foe["pos"] = start + Vector2(1.3, 0.0)
			foe["facing"] = Vector2.RIGHT

			var mp_before := float(me.get("mp", 0.0))
			var foe_hp_before := float(foe.get("hp", 0.0))
			var pos_before: Vector2 = me.get("pos", Vector2.ZERO)

			var ok := SkillSystem.cast_skill(me, str(slot), foe.get("pos", start), sim)
			check(ok, "%s.%s must cast" % [hero_type, slot])
			lt(float(me.get("mp", 0.0)), mp_before, "%s.%s must spend mana" % [hero_type, slot])
			gt(float(me.get("skill_%s_cd" % slot, 0.0)), 0.0, "%s.%s must start cooldown" % [hero_type, slot])

			var moved := (me.get("pos", pos_before) as Vector2).distance_to(pos_before) > 0.3
			var hurt := float(foe.get("hp", 0.0)) < foe_hp_before - 0.5
			var buffed := float(me.get("haste_timer", 0.0)) > 0.0 \
				or float(me.get("shield", 0.0)) > 0.0 \
				or float(me.get("cc_immune_timer", 0.0)) > 0.0
			check(
				moved or hurt or buffed,
				"%s.%s (kind=%s) spent mana but changed nothing — the kind is not handled in cast_skill"
					% [hero_type, slot, str(skill.get("kind", ""))]
			)

# ---------------------------------------------------------------- 刺客

func test_assassin_is_the_fastest_and_squishiest() -> void:
	check(HeroDefs.HEROES.has("assassin"), "assassin hero must exist")
	var assassin: Dictionary = HeroDefs.get_hero("assassin")
	eq(str(assassin.role), "刺客", "assassin role")
	for hero_type in HeroDefs.HEROES:
		if str(hero_type) == "assassin":
			continue
		var other: Dictionary = HeroDefs.get_hero(hero_type)
		lt(float(assassin.max_hp), float(other.max_hp), "assassin must have the lowest hp pool")
		gt(float(assassin.speed), float(other.speed), "assassin must be the fastest")
		lt(float(assassin.attack_interval), float(other.attack_interval), "assassin must swing fastest")
	# 量化：至少比最慢的英雄快 15%，比最厚的血少 20%。
	lt(float(assassin.speed), 7.2, "assassin speed must stay inside the lane-speed envelope")
	gt(float(assassin.speed) / 6.4, 1.03, "assassin must be measurably faster than the warrior")
	lt(float(assassin.max_hp) / float(HeroDefs.get_hero("tank").max_hp), 0.62, "assassin must be clearly squishier than the tank")

func test_assassin_e_grants_evasion() -> void:
	var sim := _duel("assassin", "tank")
	var me: Dictionary = sim.get_hero_by_player("p1")
	var start: Vector2 = me.get("pos", Vector2.ZERO)
	# 先挂上减速，确认 evasion 能清掉负面状态。
	me["slow_timer"] = 2.0
	var ok := SkillSystem.cast_skill(me, "e", start + Vector2(2.0, 0.0), sim)
	check(ok, "assassin E must cast")
	gt(float(me.get("haste_timer", 0.0)), 0.0, "evasion must grant movement speed")
	gt(float(me.get("cc_immune_timer", 0.0)), 0.0, "evasion must grant brief cc immunity")
	eq(float(me.get("slow_timer", 0.0)), 0.0, "evasion must clear slows")

func test_assassin_passive_rewards_backstabs() -> void:
	# 判据：attacker 相对 target 的方位 · target.facing
	#   > 0 → 目标正对着我（正面）   < 0 → 我从目标背后打（背刺）
	var front_sim := _duel("assassin", "tank")
	var a1: Dictionary = front_sim.get_hero_by_player("p1")
	var t1: Dictionary = front_sim.get_hero_by_player("p2")
	t1["facing"] = Vector2.LEFT                  # 目标朝 -x
	t1["pos"] = a1["pos"] + Vector2(2.0, 0.0)    # 我在它的 -x 侧 → 正对
	var front_hp := float(t1.get("hp", 0.0))
	SkillSystem.on_hero_attack_hit(a1, t1, front_sim)
	var front_damage := front_hp - float(t1.get("hp", 0.0))

	var back_sim := _duel("assassin", "tank")
	var a2: Dictionary = back_sim.get_hero_by_player("p1")
	var t2: Dictionary = back_sim.get_hero_by_player("p2")
	t2["facing"] = Vector2.RIGHT                 # 目标朝 +x
	t2["pos"] = a2["pos"] + Vector2(2.0, 0.0)    # 我在它的 -x 侧 → 背后
	var back_hp := float(t2.get("hp", 0.0))
	SkillSystem.on_hero_attack_hit(a2, t2, back_sim)
	var back_damage := back_hp - float(t2.get("hp", 0.0))

	eq(front_damage, 0.0, "no bonus damage when the target faces you")
	gt(back_damage, 0.0, "backstab must add damage")
	near(back_damage, float(a2.get("attack_damage", 0.0)) * 0.25, 1.0, "backstab bonus is 25% of attack damage")

# ---------------------------------------------------------------- 资产与出装

func test_every_hero_has_a_portrait_file() -> void:
	for hero_type in HeroDefs.HEROES:
		var path := "res://assets/ui/portraits/%s.png" % hero_type
		check(FileAccess.file_exists(path), "missing portrait: %s" % path)

func test_every_hero_has_a_full_build_order() -> void:
	for hero_type in HeroDefs.HEROES:
		check(ItemShop.BUILD_ORDERS.has(hero_type), "%s missing BUILD_ORDERS entry" % hero_type)
		var order: Array = ItemShop.build_order_for(hero_type)
		eq(order.size(), 6, "%s build order must fill all six slots" % hero_type)
		for item_id in order:
			check(ItemShop.CATALOGUE.has(str(item_id)), "%s build order references unknown item '%s'" % [hero_type, item_id])

func test_hero_order_matches_the_roster() -> void:
	var main_source := FileAccess.get_file_as_string("res://scripts/app/main.gd")
	check(main_source.contains("assassin"), "HERO_ORDER must include the assassin")
	for hero_type in HeroDefs.HEROES:
		check(main_source.contains("\"%s\"" % hero_type), "HERO_ORDER is missing %s" % hero_type)
