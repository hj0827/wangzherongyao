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
		# 项 1：防御装第一次真正给出"减伤"而不是只堆血。布甲 = 护甲 +15。
		"armor": 15.0,
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
		"armor": 40.0,
		"hp_regen": 12.0,
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
		# 抵抗之靴：名字里的"抵抗"这次落到魔抗上（以前只是个名字）。
		"magic_resist": 25.0,
	},
}

const BUILD_ORDERS := {
	"blade": ["boots", "iron_sword", "infinity_edge", "cloth_armor", "ominous_shield", "resistance_boots"],
	"mage": ["spell_tome", "boots", "echo_wand", "cloth_armor", "ominous_shield", "resistance_boots"],
	"tank": ["cloth_armor", "boots", "ominous_shield", "resistance_boots", "iron_sword", "infinity_edge"],
	"archer": ["boots", "iron_sword", "infinity_edge", "cloth_armor", "resistance_boots", "ominous_shield"],
	"assassin": ["boots", "iron_sword", "infinity_edge", "resistance_boots", "cloth_armor", "ominous_shield"],
}

static func get_item(item_id: String) -> Dictionary:
	return CATALOGUE.get(item_id, {})

static func ids_by_category(category: String) -> Array:
	if category == "" or category == "all":
		return CATALOGUE.keys()
	var ids: Array = []
	for item_id in CATALOGUE:
		if str(CATALOGUE[item_id].get("category", "")) == category:
			ids.append(item_id)
	return ids

# 品质由价格推导，不新增一件装备一个手填字段：
# 250/300/220 这类基础件是 basic，710 左右的过渡件是 rare，2000+ 的成装是 epic。
static func quality_of(item_id: String) -> String:
	var cost := int(get_item(item_id).get("cost", 0))
	if cost >= 2000:
		return "epic"
	if cost >= 500:
		return "rare"
	return "basic"

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
	var base_armor: float = float(hero.get("base_armor", hero.get("armor", 0.0)))
	var base_mr: float = float(hero.get("base_magic_resist", hero.get("magic_resist", 0.0)))
	var base_hp_re: float = float(hero.get("base_hp_regen", hero.get("hp_regen", 0.0)))
	var base_mp_re: float = float(hero.get("base_mana_regen", hero.get("mana_regen", 0.0)))
	
	var bonus_ad: float = 0.0
	var bonus_ap: float = 0.0
	var bonus_hp: float = 0.0
	var bonus_speed: float = 0.0
	var bonus_crit: float = 0.0
	var bonus_armor: float = 0.0
	var bonus_mr: float = 0.0
	var bonus_hp_re: float = 0.0
	var bonus_mp_re: float = 0.0
	var bonus_cdr: float = 0.0
	var bonus_as: float = 0.0
	var bonus_crit_dmg: float = 0.0
	
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
		bonus_armor += float(item.get("armor", 0.0))
		bonus_mr += float(item.get("magic_resist", 0.0))
		bonus_hp_re += float(item.get("hp_regen", 0.0))
		bonus_mp_re += float(item.get("mana_regen", 0.0))
		bonus_cdr += float(item.get("cooldown_reduction", 0.0))
		bonus_as += float(item.get("attack_speed", 0.0))
		bonus_crit_dmg += float(item.get("crit_damage", 0.0))
		
	hero["attack_damage"] = base_ad + bonus_ad
	hero["ability_power"] = bonus_ap
	hero["max_hp"] = base_hp + bonus_hp
	hero["speed"] = base_speed + bonus_speed
	hero["crit_rate"] = bonus_crit
	# 项 1：新属性同样"基础 + 装备"聚合计账。CDR 的上限钳制在结算侧
	# （match_sim.hero_cooldown_scale）统一处理，这里保留原始累加值。
	hero["armor"] = base_armor + bonus_armor
	hero["magic_resist"] = base_mr + bonus_mr
	hero["hp_regen"] = base_hp_re + bonus_hp_re
	hero["mana_regen"] = base_mp_re + bonus_mp_re
	hero["cooldown_reduction"] = bonus_cdr
	# 攻速与暴伤也必须走同一条聚合路径，否则将来任何一件加攻速/暴伤的装备
	# 都会"字段写了、没人读"——本仓库最典型的静默失效形态。
	# 基础值一律从 base_* 取：写回后的 hero["attack_speed"] 已含加成，
	# 直接拿它当基础会在每次重算时把加成再叠一遍。
	hero["attack_speed"] = float(hero.get("base_attack_speed", 0.0)) + bonus_as
	hero["crit_damage"] = float(hero.get("base_crit_damage", 1.5)) + bonus_crit_dmg

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
