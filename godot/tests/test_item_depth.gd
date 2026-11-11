extends "res://tests/test_base.gd"

# 装备深度（穿透 / 吸血 / 合成树）的链路守卫。
# 三类断言缺一不可：
#  1. 数据自洽：每件成装原价 = 组件原价之和 + 合成费，组件 id 都真实存在；
#  2. 合成经济：组件齐备时只扣合成费、消耗组件、满格也能升级；
#  3. 战斗生效：穿透真的降低目标有效抗性，吸血真的按实际扣血回血，
#     且这两个字段都穿过实体快照、计分板与联机白名单
#     （漏一处 = 单机对、联机静默丢）。

const MatchSim = preload("res://sim/match_sim.gd")
const ItemShop = preload("res://sim/item_shop.gd")
const NetProtocol = preload("res://net/net_protocol.gd")

func _mock_hero() -> Dictionary:
	return {
		"id": 1, "type": "hero", "hero_type": "blade", "team": "blue",
		"alive": true, "gold": 0, "inventory": [], "level": 1,
		"base_hp": 1000.0, "max_hp": 1000.0, "hp": 1000.0,
		"base_ad": 80.0, "attack_damage": 80.0,
		"speed": 6.0, "base_speed": 6.0,
		"ability_power": 0.0, "crit_rate": 0.0,
	}

func _duel() -> Dictionary:
	var sim := MatchSim.new({
		"mode": "duel",
		"humans": [
			{"id": "p1", "name": "p1", "team": "blue", "hero_type": "blade"},
			{"id": "p2", "name": "p2", "team": "red", "hero_type": "tank"},
		],
		"bot_fill": false,
	})
	var a: Dictionary = sim.get_hero_by_player("p1")
	var b: Dictionary = sim.get_hero_by_player("p2")
	a.pos = Vector2.ZERO
	b.pos = Vector2(3.0, 0.0)
	a.last_damage_time = 0.0
	b.last_damage_time = 0.0
	return {"sim": sim, "a": a, "b": b}

# 不在实体列表里的临时受害者：直调 _damage 时不会被基地/兵线介入污染。
func _victim(team := "red", hp := 1000.0) -> Dictionary:
	return {"id": 999, "type": "hero", "team": team, "alive": true,
		"pos": Vector2(30.0, 30.0), "hp": hp, "max_hp": hp, "radius": 0.5,
		"armor": 0.0, "magic_resist": 0.0}

# ---------------------------------------------------------------- 数据自洽

func test_every_recipe_price_matches_components_plus_combine_cost() -> void:
	for item_id in ItemShop.CATALOGUE:
		var item: Dictionary = ItemShop.get_item(str(item_id))
		var recipe: Array = ItemShop.recipe_of(str(item_id))
		if recipe.is_empty():
			continue
		var total := int(ItemShop.combine_cost_of(str(item_id)))
		for cid in recipe:
			check(ItemShop.CATALOGUE.has(str(cid)), "%s 的组件 %s 必须在目录里" % [item_id, cid])
			total += int(ItemShop.get_item(str(cid)).get("cost", 0))
		eq(int(item.get("cost", 0)), total, "%s 原价 = 组件原价之和 + 合成费" % item_id)

func test_depth_catalogue_has_penetration_lifesteal_and_recipes() -> void:
	for required in ["meteor", "blood_sickle", "dagger", "sapphire", "star_breaker",
			"bloodweeper", "shadow_blade", "void_staff", "glacial_buckler"]:
		check(ItemShop.CATALOGUE.has(required), "缺少装备 %s" % required)
	gt(float(ItemShop.get_item("star_breaker").get("armor_pen", 0.0)), 0.0, "碎星锤有物理穿透")
	gt(float(ItemShop.get_item("void_staff").get("magic_pen", 0.0)), 0.0, "虚无法杖有法术穿透")
	gt(float(ItemShop.get_item("bloodweeper").get("lifesteal", 0.0)), 0.0, "泣血之刃有吸血")
	check(not ItemShop.recipe_of("star_breaker").is_empty(), "碎星锤有合成树")
	check(not ItemShop.recipe_of("infinity_edge").is_empty(), "无尽战刃有合成树")

# ---------------------------------------------------------------- 合成经济

func test_combining_only_charges_the_combine_cost() -> void:
	var hero := _mock_hero()
	hero.gold = 3000
	check(ItemShop.buy_item(hero, "meteor"), "先买陨星")
	check(ItemShop.buy_item(hero, "iron_sword"), "再买铁剑")
	check(ItemShop.can_buy(hero, "star_breaker"), "组件齐备后可以合成")
	check(ItemShop.buy_item(hero, "star_breaker"), "合成碎星锤")
	eq(hero.inventory.size(), 1, "合成后只剩成装")
	eq(str(hero.inventory[0]), "star_breaker", "成装在背包里")
	eq(int(hero.gold), 3000 - 600 - 250 - 1450, "只扣组件价 + 合成费")
	eq(float(hero.get("armor_pen", 0.0)), 60.0, "合成后穿透立即生效")

func test_combine_is_allowed_with_a_full_inventory() -> void:
	var hero := _mock_hero()
	hero.gold = 1450
	hero.inventory = ["meteor", "iron_sword", "iron_sword", "iron_sword", "iron_sword", "iron_sword"]
	eq(hero.inventory.size(), 6, "六格已满")
	check(ItemShop.can_buy(hero, "star_breaker"), "满格但组件齐备时仍可升级")
	check(ItemShop.buy_item(hero, "star_breaker"), "满格合成成功")
	eq(hero.inventory.size(), 5, "合成净减一格")
	eq(int(hero.gold), 0, "只扣合成费")

func test_combine_requires_every_component() -> void:
	var hero := _mock_hero()
	hero.gold = 1450  # 只够合成费，不够整件原价 2300
	hero.inventory = ["meteor", "cloth_armor", "cloth_armor", "cloth_armor", "cloth_armor", "cloth_armor"]
	check(not ItemShop.has_all_components(hero, "star_breaker"), "缺铁剑时组件不齐")
	check(not ItemShop.can_buy(hero, "star_breaker"), "组件不齐且买不起整件时不能购买")
	check(not ItemShop.buy_item(hero, "star_breaker"), "buy_item 必须失败")
	eq(hero.inventory.size(), 6, "失败的购买不能改动背包")

func test_recalculate_stats_aggregates_penetration_and_lifesteal() -> void:
	var hero := _mock_hero()
	hero.inventory = ["star_breaker", "void_staff", "bloodweeper"]
	ItemShop.recalculate_stats(hero)
	eq(float(hero.get("armor_pen", 0.0)), 60.0, "物理穿透 = 60")
	eq(float(hero.get("magic_pen", 0.0)), 45.0, "法术穿透 = 45")
	eq(float(hero.get("lifesteal", 0.0)), 0.25, "吸血 = 25%")
	# 卸掉装备后必须回到 0，不能残留。
	hero.inventory = []
	ItemShop.recalculate_stats(hero)
	eq(float(hero.get("armor_pen", 0.0)), 0.0, "卸装后物理穿透归零")
	eq(float(hero.get("magic_pen", 0.0)), 0.0, "卸装后法术穿透归零")
	eq(float(hero.get("lifesteal", 0.0)), 0.0, "卸装后吸血归零")

func test_quick_buy_walks_the_recipe_in_component_order() -> void:
	var hero := _mock_hero()
	var order := ["meteor", "iron_sword", "star_breaker"]
	hero.gold = 1000
	eq(ItemShop.get_quick_buy_recommendation(hero, order), "meteor", "先推荐组件陨星")
	hero.gold = 400
	hero.inventory = ["meteor"]
	eq(ItemShop.get_quick_buy_recommendation(hero, order), "iron_sword", "组件齐前推荐铁剑")
	hero.inventory = ["meteor", "iron_sword"]
	hero.gold = 100
	eq(ItemShop.get_quick_buy_recommendation(hero, order), "", "组件齐但合成费不足时不推荐")
	hero.gold = 1450
	eq(ItemShop.get_quick_buy_recommendation(hero, order), "star_breaker", "合成费够了就推荐成装")

# ---------------------------------------------------------------- 战斗生效

func test_armor_penetration_reduces_effective_resistance() -> void:
	var sim: Object = _duel().sim
	var attacker: Dictionary = sim.get_hero_by_player("p1")
	var plain := _victim()
	plain.armor = float(MatchSim.MATCH_MITIGATION_K)
	var before_plain := float(plain.hp)
	sim._damage(plain, 200.0, attacker, "physical")
	near(before_plain - float(plain.hp), 100.0, 0.01, "无穿透时护甲=K 减半")

	attacker["armor_pen"] = float(MatchSim.MATCH_MITIGATION_K)
	var pierced := _victim()
	pierced.armor = float(MatchSim.MATCH_MITIGATION_K)
	var before_pierced := float(pierced.hp)
	sim._damage(pierced, 200.0, attacker, "physical")
	near(before_pierced - float(pierced.hp), 200.0, 0.01, "穿透=护甲时伤害不再减半")

func test_magic_penetration_only_applies_to_magic_damage() -> void:
	var sim: Object = _duel().sim
	var attacker: Dictionary = sim.get_hero_by_player("p1")
	attacker["magic_pen"] = float(MatchSim.MATCH_MITIGATION_K)
	var victim := _victim()
	victim.magic_resist = float(MatchSim.MATCH_MITIGATION_K)
	victim.armor = float(MatchSim.MATCH_MITIGATION_K)
	var before := float(victim.hp)
	sim._damage(victim, 200.0, attacker, "magic")
	near(before - float(victim.hp), 200.0, 0.01, "法术穿透抵消魔抗")
	var before_physical := float(victim.hp)
	sim._damage(victim, 200.0, attacker, "physical")
	near(before_physical - float(victim.hp), 100.0, 0.01, "物理伤害不受法术穿透影响")

func test_lifesteal_heals_from_physical_damage_only() -> void:
	var sim: Object = _duel().sim
	var attacker: Dictionary = sim.get_hero_by_player("p1")
	attacker["hp"] = 500.0
	attacker["lifesteal"] = 0.25
	var victim := _victim()
	sim._damage(victim, 100.0, attacker, "physical")
	near(float(attacker.hp), 525.0, 0.01, "物理伤害 100 × 25% 回 25 血")

	sim._damage(victim, 100.0, attacker, "magic")
	near(float(attacker.hp), 525.0, 0.01, "法术伤害不触发吸血")

	var minion := {"id": 900, "type": "minion", "team": "red", "alive": true,
		"pos": Vector2(30.0, 30.0), "hp": 500.0, "max_hp": 500.0, "radius": 0.4}
	sim._damage(minion, 100.0, attacker, "physical")
	near(float(attacker.hp), 550.0, 0.01, "打小兵也回血")

	# 吸血不能超过最大生命。
	var tanky := _victim("red", 999999.0)
	attacker["hp"] = float(attacker.max_hp) - 1.0
	sim._damage(tanky, 4000.0, attacker, "physical")
	eq(float(attacker.hp), float(attacker.max_hp), "吸血不会超过最大生命")

# ---------------------------------------------------------------- 快照 / 联机

func test_penetration_and_lifesteal_reach_snapshot_and_wire() -> void:
	var ctx := _duel()
	var hero: Dictionary = ctx.a
	hero.armor_pen = 60.0
	hero.magic_pen = 45.0
	hero.lifesteal = 0.25
	var shot: Dictionary = ctx.sim._snapshot_entity(hero)
	eq(float(shot.get("armor_pen", -1.0)), 60.0, "snapshot.armor_pen")
	eq(float(shot.get("magic_pen", -1.0)), 45.0, "snapshot.magic_pen")
	eq(float(shot.get("lifesteal", -1.0)), 0.25, "snapshot.lifesteal")

	var wire: Dictionary = NetProtocol._sanitize_entity(shot, 58.0)
	eq(float(wire.get("armor_pen", -1.0)), 60.0, "wire.armor_pen")
	eq(float(wire.get("magic_pen", -1.0)), 45.0, "wire.magic_pen")
	eq(float(wire.get("lifesteal", -1.0)), 0.25, "wire.lifesteal")

	var hostile: Dictionary = shot.duplicate(true)
	hostile["armor_pen"] = -10.0
	hostile["magic_pen"] = 1e9
	hostile["lifesteal"] = 5.0
	var clean: Dictionary = NetProtocol._sanitize_entity(hostile, 58.0)
	eq(float(clean.get("armor_pen", -999.0)), 0.0, "负穿透钳到 0")
	eq(float(clean.get("magic_pen", -999.0)), NetProtocol.MAX_RESISTANCE, "穿透封顶")
	eq(float(clean.get("lifesteal", -999.0)), 1.0, "吸血钳到 100%")

func test_board_carries_penetration_and_lifesteal() -> void:
	var ctx := _duel()
	var hero: Dictionary = ctx.a
	hero.armor_pen = 60.0
	hero.magic_pen = 45.0
	hero.lifesteal = 0.25
	var board: Dictionary = ctx.sim._snapshot_board()
	var row: Dictionary = (board.blue as Array)[0]
	eq(float(row.get("armor_pen", -1.0)), 60.0, "board.armor_pen")
	eq(float(row.get("magic_pen", -1.0)), 45.0, "board.magic_pen")
	eq(float(row.get("lifesteal", -1.0)), 0.25, "board.lifesteal")
