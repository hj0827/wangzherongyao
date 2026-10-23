extends RefCounted

const CATALOGUE := {
	"iron_sword": {
		"id": "iron_sword",
		"name": "铁剑",
		"category": "attack",
		"cost": 250,
		"ad": 20.0,
		"ap": 0.0,
		"hp": 0.0,
		"speed": 0.0,
		"crit": 0.0,
	},
	"infinity_edge": {
		"id": "infinity_edge",
		"name": "无尽战刃",
		"category": "attack",
		"cost": 2140,
		"ad": 110.0,
		"ap": 0.0,
		"hp": 0.0,
		"speed": 0.0,
		"crit": 0.20,
	},
	"spell_tome": {
		"id": "spell_tome",
		"name": "咒术典籍",
		"category": "magic",
		"cost": 300,
		"ad": 0.0,
		"ap": 40.0,
		"hp": 0.0,
		"speed": 0.0,
		"crit": 0.0,
	},
	"echo_wand": {
		"id": "echo_wand",
		"name": "回响之杖",
		"category": "magic",
		"cost": 2100,
		"ad": 0.0,
		"ap": 240.0,
		"hp": 0.0,
		"speed": 0.4,
		"crit": 0.0,
	},
	"cloth_armor": {
		"id": "cloth_armor",
		"name": "布甲",
		"category": "defense",
		"cost": 220,
		"ad": 0.0,
		"ap": 0.0,
		"hp": 220.0,
		"speed": 0.0,
		"crit": 0.0,
	},
	"ominous_shield": {
		"id": "ominous_shield",
		"name": "不祥征兆",
		"category": "defense",
		"cost": 2180,
		"ad": 0.0,
		"ap": 0.0,
		"hp": 1200.0,
		"speed": 0.0,
		"crit": 0.0,
	},
	"boots": {
		"id": "boots",
		"name": "神速之靴",
		"category": "movement",
		"cost": 250,
		"ad": 0.0,
		"ap": 0.0,
		"hp": 0.0,
		"speed": 0.6,
		"crit": 0.0,
	},
	"resistance_boots": {
		"id": "resistance_boots",
		"name": "抵抗之靴",
		"category": "movement",
		"cost": 710,
		"ad": 0.0,
		"ap": 0.0,
		"hp": 0.0,
		"speed": 1.1,
		"crit": 0.0,
	},
}

const BUILD_ORDERS := {
	"blade": ["boots", "iron_sword", "infinity_edge", "cloth_armor", "ominous_shield", "resistance_boots"],
	"mage": ["spell_tome", "boots", "echo_wand", "cloth_armor", "ominous_shield", "resistance_boots"],
	"tank": ["cloth_armor", "boots", "ominous_shield", "resistance_boots", "iron_sword", "infinity_edge"],
	"archer": ["boots", "iron_sword", "infinity_edge", "cloth_armor", "resistance_boots", "ominous_shield"],
}

static func get_item(item_id: String) -> Dictionary:
	return CATALOGUE.get(item_id, {})

static func build_order_for(hero_type: String) -> Array:
	return BUILD_ORDERS.get(hero_type, BUILD_ORDERS["blade"])

static func can_buy(hero: Dictionary, item_id: String) -> bool:
	if not CATALOGUE.has(item_id):
		return false
	var inventory: Array = hero.get("inventory", [])
	if inventory.size() >= 6:
		return false
	var item: Dictionary = CATALOGUE[item_id]
	return int(hero.get("gold", 0)) >= int(item.cost)

static func buy_item(hero: Dictionary, item_id: String) -> bool:
	if not can_buy(hero, item_id):
		return false
	var item: Dictionary = CATALOGUE[item_id]
	var cost: int = int(item.cost)
	hero["gold"] = int(hero.get("gold", 0)) - cost
	var inv: Array = hero.get("inventory", [])
	inv.append(item_id)
	hero["inventory"] = inv
	recalculate_stats(hero)
	return true

static func sell_item(hero: Dictionary, slot_index: int) -> bool:
	var inv: Array = hero.get("inventory", [])
	if slot_index < 0 or slot_index >= inv.size():
		return false
	var item_id: String = str(inv[slot_index])
	var item: Dictionary = get_item(item_id)
	var refund: int = int(float(item.get("cost", 0)) * 0.6)
	inv.remove_at(slot_index)
	hero["inventory"] = inv
	hero["gold"] = int(hero.get("gold", 0)) + refund
	recalculate_stats(hero)
	return true

static func recalculate_stats(hero: Dictionary) -> void:
	var base_ad: float = float(hero.get("base_ad", hero.get("attack_damage", 70.0)))
	var base_speed: float = float(hero.get("base_speed", hero.get("speed", 6.0)))
	var base_hp: float = float(hero.get("base_hp", hero.get("max_hp", 1000.0)))
	
	var bonus_ad: float = 0.0
	var bonus_ap: float = 0.0
	var bonus_hp: float = 0.0
	var bonus_speed: float = 0.0
	var bonus_crit: float = 0.0
	
	var inv: Array = hero.get("inventory", [])
	for item_id in inv:
		var item: Dictionary = get_item(str(item_id))
		if item.is_empty():
			continue
		bonus_ad += float(item.get("ad", 0.0))
		bonus_ap += float(item.get("ap", 0.0))
		bonus_hp += float(item.get("hp", 0.0))
		bonus_speed += float(item.get("speed", 0.0))
		bonus_crit += float(item.get("crit", 0.0))
		
	hero["attack_damage"] = base_ad + bonus_ad
	hero["ability_power"] = bonus_ap
	hero["max_hp"] = base_hp + bonus_hp
	hero["speed"] = base_speed + bonus_speed
	hero["crit_rate"] = bonus_crit

static func get_quick_buy_recommendation(hero: Dictionary, build_order: Array) -> String:
	var gold: int = int(hero.get("gold", 0))
	var inv: Array = hero.get("inventory", [])
	if inv.size() >= 6:
		return ""
	for item_id in build_order:
		var sid: String = str(item_id)
		if inv.has(sid):
			continue
		var item: Dictionary = get_item(sid)
		if item.is_empty():
			continue
		if gold >= int(item.cost):
			return sid
	return ""
