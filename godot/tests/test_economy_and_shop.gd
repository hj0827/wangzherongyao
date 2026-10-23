extends "res://tests/test_base.gd"

const ItemShop = preload("res://sim/item_shop.gd")
const EconomySystem = preload("res://sim/economy_system.gd")

func _mock_hero() -> Dictionary:
	return {
		"id": 1,
		"type": "hero",
		"hero_type": "blade",
		"team": "blue",
		"alive": true,
		"gold": 0,
		"inventory": [],
		"level": 1,
		"base_hp": 1000.0,
		"max_hp": 1000.0,
		"hp": 1000.0,
		"base_ad": 80.0,
		"attack_damage": 80.0,
		"speed": 6.0,
		"base_speed": 6.0,
		"ability_power": 0.0,
		"crit_rate": 0.0,
	}

func test_item_catalogue_contains_core_categories() -> void:
	var items: Dictionary = ItemShop.CATALOGUE
	check(items.size() >= 8, "item catalogue has diverse items")
	check(items.has("iron_sword"), "has basic attack item")
	check(items.has("infinity_edge"), "has advanced attack item")
	check(items.has("cloth_armor"), "has basic defense item")
	check(items.has("ominous_shield"), "has advanced defense item")
	check(items.has("spell_tome"), "has basic magic item")
	check(items.has("boots"), "has boots")

func test_hero_gold_gain_and_natural_tick() -> void:
	var hero := _mock_hero()
	EconomySystem.tick_natural_gold(hero, 10.0)
	gt(int(hero.get("gold", 0)), 0, "natural gold tick accumulates over time")
	
	EconomySystem.award_minion_kill(hero, true) # Last hit
	var gold_lasthit: int = int(hero.get("gold", 0))
	EconomySystem.award_minion_kill(hero, false) # Non last hit
	var gold_assist: int = int(hero.get("gold", 0)) - gold_lasthit
	gt(gold_lasthit, gold_assist, "last hitting minion grants bonus gold")

func test_buy_item_deducts_gold_and_adds_to_inventory() -> void:
	var hero := _mock_hero()
	hero.gold = 300
	var ok: bool = ItemShop.buy_item(hero, "iron_sword")
	check(ok, "buy iron sword succeeds with sufficient gold")
	eq(hero.inventory.size(), 1, "inventory has 1 item")
	eq(hero.inventory[0], "iron_sword", "bought iron sword")
	eq(int(hero.gold), 300 - int(ItemShop.get_item("iron_sword").cost), "gold deducted")

func test_cannot_buy_beyond_six_items() -> void:
	var hero := _mock_hero()
	hero.gold = 10000
	for i in 6:
		var ok: bool = ItemShop.buy_item(hero, "iron_sword")
		check(ok, "bought slot %d" % i)
	var ok7: bool = ItemShop.buy_item(hero, "iron_sword")
	check(not ok7, "cannot buy more than 6 items")
	eq(hero.inventory.size(), 6, "inventory caps at 6")

func test_item_stats_recalculation() -> void:
	var hero := _mock_hero()
	hero.gold = 3000
	ItemShop.buy_item(hero, "infinity_edge")
	ItemShop.buy_item(hero, "boots")
	ItemShop.recalculate_stats(hero)
	
	gt(float(hero.attack_damage), float(hero.base_ad), "attack damage increased by infinity edge")
	gt(float(hero.crit_rate), 0.0, "crit rate increased by infinity edge")
	gt(float(hero.speed), float(hero.base_speed), "movement speed increased by boots")

func test_sell_item_refunds_portion_of_gold() -> void:
	var hero := _mock_hero()
	hero.gold = 1000
	ItemShop.buy_item(hero, "iron_sword")
	var gold_after_buy: int = int(hero.gold)
	
	var ok_sell: bool = ItemShop.sell_item(hero, 0)
	check(ok_sell, "sell item succeeds")
	eq(hero.inventory.size(), 0, "item removed from inventory")
	gt(int(hero.gold), gold_after_buy, "gold refunded after selling")

func test_quick_buy_recommends_affordable_build_item() -> void:
	var hero := _mock_hero()
	var build_order := ["boots", "iron_sword", "infinity_edge"]
	
	hero.gold = 100
	var rec1: String = ItemShop.get_quick_buy_recommendation(hero, build_order)
	eq(rec1, "", "cannot afford any item yet")
	
	hero.gold = 300
	var rec2: String = ItemShop.get_quick_buy_recommendation(hero, build_order)
	eq(rec2, "boots", "recommends first affordable item in build order")
