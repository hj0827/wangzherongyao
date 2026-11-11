extends RefCounted

# 装备目录。cost 是**整件原价**，必须等于「recipe 里各组件 cost 之和 + combine_cost」，
# 由 test_item_depth 逐件校验 —— 两处手写价格最容易在后续调整时漂移。
# 穿透（armor_pen / magic_pen）按固定值从目标抗性里先减，再进减伤公式；
# 吸血（lifesteal）按「本次实际扣掉的血」比例回给来源英雄。
const CATALOGUE := {
	# ---- 攻击 ----
	"iron_sword": {
		"id": "iron_sword",
		"name": "铁剑",
		"category": "attack",
		"cost": 250,
		"ad": 20.0,
	},
	"meteor": {
		"id": "meteor",
		"name": "陨星",
		"category": "attack",
		"cost": 600,
		"ad": 30.0,
		"armor_pen": 15.0,
	},
	"dagger": {
		"id": "dagger",
		"name": "匕首",
		"category": "attack",
		"cost": 420,
		"attack_speed": 0.15,
	},
	"blood_sickle": {
		"id": "blood_sickle",
		"name": "血镰",
		"category": "attack",
		"cost": 500,
		"ad": 15.0,
		"lifesteal": 0.08,
	},
	"infinity_edge": {
		"id": "infinity_edge",
		"name": "无尽战刃",
		"category": "attack",
		"cost": 2140,
		"ad": 110.0,
		"crit": 0.20,
		"crit_damage": 0.40,
		"recipe": ["iron_sword", "dagger"],
		"combine_cost": 1470,
	},
	"shadow_blade": {
		"id": "shadow_blade",
		"name": "影刃",
		"category": "attack",
		"cost": 2000,
		"ad": 60.0,
		"attack_speed": 0.35,
		"crit": 0.15,
		"recipe": ["dagger", "iron_sword"],
		"combine_cost": 1330,
	},
	"star_breaker": {
		"id": "star_breaker",
		"name": "碎星锤",
		"category": "attack",
		"cost": 2300,
		"ad": 90.0,
		"armor_pen": 60.0,
		"recipe": ["meteor", "iron_sword"],
		"combine_cost": 1450,
	},
	"bloodweeper": {
		"id": "bloodweeper",
		"name": "泣血之刃",
		"category": "attack",
		"cost": 2200,
		"ad": 100.0,
		"lifesteal": 0.25,
		"recipe": ["blood_sickle", "iron_sword"],
		"combine_cost": 1450,
	},
	# ---- 法术 ----
	"spell_tome": {
		"id": "spell_tome",
		"name": "咒术典籍",
		"category": "magic",
		"cost": 300,
		"ap": 40.0,
	},
	"sapphire": {
		"id": "sapphire",
		"name": "蓝宝石",
		"category": "magic",
		"cost": 400,
		"cooldown_reduction": 0.10,
	},
	"echo_wand": {
		"id": "echo_wand",
		"name": "回响之杖",
		"category": "magic",
		"cost": 2100,
		"ap": 240.0,
		"speed": 0.4,
		"recipe": ["spell_tome", "sapphire"],
		"combine_cost": 1400,
	},
	"void_staff": {
		"id": "void_staff",
		"name": "虚无法杖",
		"category": "magic",
		"cost": 2100,
		"ap": 180.0,
		"magic_pen": 45.0,
		"recipe": ["spell_tome", "sapphire"],
		"combine_cost": 1400,
	},
	# ---- 防御 ----
	"cloth_armor": {
		"id": "cloth_armor",
		"name": "布甲",
		"category": "defense",
		"cost": 220,
		"hp": 220.0,
		# 项 1：防御装第一次真正给出"减伤"而不是只堆血。布甲 = 护甲 +15。
		"armor": 15.0,
	},
	"ominous_shield": {
		"id": "ominous_shield",
		"name": "不祥征兆",
		"category": "defense",
		"cost": 2180,
		"hp": 1200.0,
		"armor": 40.0,
		"hp_regen": 12.0,
		"recipe": ["cloth_armor"],
		"combine_cost": 1960,
	},
	"glacial_buckler": {
		"id": "glacial_buckler",
		"name": "极寒风暴",
		"category": "defense",
		"cost": 2100,
		"hp": 500.0,
		"armor": 30.0,
		"cooldown_reduction": 0.20,
		"recipe": ["cloth_armor", "sapphire"],
		"combine_cost": 1480,
	},
	# ---- 移动 ----
	"boots": {
		"id": "boots",
		"name": "神速之靴",
		"category": "movement",
		"cost": 250,
		"speed": 0.6,
	},
	"resistance_boots": {
		"id": "resistance_boots",
		"name": "抵抗之靴",
		"category": "movement",
		"cost": 710,
		"speed": 1.1,
		# 抵抗之靴：名字里的"抵抗"这次落到魔抗上（以前只是个名字）。
		"magic_resist": 25.0,
		"recipe": ["boots"],
		"combine_cost": 460,
	},
}

# 快捷购买顺序 = 六件最终装。组件不在这里重复列：get_quick_buy_recommendation
# 会按 recipe 逐件展开，先推荐缺失组件，组件齐了再推荐成装（只收合成费）。
const BUILD_ORDERS := {
	"blade": ["boots", "infinity_edge", "ominous_shield", "star_breaker", "bloodweeper", "glacial_buckler"],
	"mage": ["boots", "echo_wand", "void_staff", "ominous_shield", "glacial_buckler", "resistance_boots"],
	"tank": ["boots", "ominous_shield", "glacial_buckler", "resistance_boots", "star_breaker", "bloodweeper"],
	"archer": ["boots", "infinity_edge", "shadow_blade", "bloodweeper", "resistance_boots", "star_breaker"],
	"assassin": ["boots", "shadow_blade", "infinity_edge", "bloodweeper", "resistance_boots", "star_breaker"],
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

static func recipe_of(item_id: String) -> Array:
	return get_item(item_id).get("recipe", [])

static func combine_cost_of(item_id: String) -> int:
	return int(get_item(item_id).get("combine_cost", 0))

# 组件是否齐备（按数量比，不是按"存在"）：同一组件出现在两条配方里时，
# 只有一份组件不能让两件成装都合成。
static func has_all_components(hero: Dictionary, item_id: String) -> bool:
	var recipe: Array = recipe_of(item_id)
	if recipe.is_empty():
		return false
	var inv: Array = hero.get("inventory", [])
	var needed: Dictionary = {}
	for cid in recipe:
		needed[str(cid)] = int(needed.get(str(cid), 0)) + 1
	for cid in needed:
		var owned := 0
		for entry in inv:
			if str(entry) == str(cid):
				owned += 1
		if owned < int(needed[cid]):
			return false
	return true

# 按数量找出第一件仍然缺失的组件；全部齐备返回空串。
# 返回单件组件（而不是整条缺失清单），因为快捷购买一次只买一件。
static func first_missing_component(hero: Dictionary, item_id: String) -> String:
	var recipe: Array = recipe_of(item_id)
	if recipe.is_empty():
		return ""
	var inv: Array = hero.get("inventory", [])
	var needed: Dictionary = {}
	for cid in recipe:
		needed[str(cid)] = int(needed.get(str(cid), 0)) + 1
	for cid in needed:
		var owned := 0
		for entry in inv:
			if str(entry) == str(cid):
				owned += 1
		if owned < int(needed[cid]):
			return str(cid)
	return ""

static func can_buy(hero: Dictionary, item_id: String) -> bool:
	if not CATALOGUE.has(item_id):
		return false
	var gold: int = int(hero.get("gold", 0))
	# 组件齐备时是"合成升级"：只付合成费，且不受 6 格上限限制
	# （组件本来就在格子里，升级是净减格子）。
	if has_all_components(hero, item_id):
		return gold >= combine_cost_of(item_id)
	var inventory: Array = hero.get("inventory", [])
	if inventory.size() >= 6:
		return false
	return gold >= int(CATALOGUE[item_id].cost)

static func buy_item(hero: Dictionary, item_id: String) -> bool:
	if not can_buy(hero, item_id):
		return false
	var inv: Array = hero.get("inventory", [])
	if has_all_components(hero, item_id):
		for cid in recipe_of(item_id):
			inv.erase(str(cid))
		hero["gold"] = int(hero.get("gold", 0)) - combine_cost_of(item_id)
	else:
		hero["gold"] = int(hero.get("gold", 0)) - int(CATALOGUE[item_id].cost)
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
	var bonus_armor_pen: float = 0.0
	var bonus_magic_pen: float = 0.0
	var bonus_lifesteal: float = 0.0
	
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
		bonus_armor_pen += float(item.get("armor_pen", 0.0))
		bonus_magic_pen += float(item.get("magic_pen", 0.0))
		bonus_lifesteal += float(item.get("lifesteal", 0.0))
		
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
	# 穿透按固定值累加（结算侧 target_resist = max(0, resist - pen)），
	# 吸血按固定比例累加（结算侧按实际扣血回血）。
	hero["armor_pen"] = bonus_armor_pen
	hero["magic_pen"] = bonus_magic_pen
	hero["lifesteal"] = bonus_lifesteal

static func get_quick_buy_recommendation(hero: Dictionary, build_order: Array) -> String:
	var gold: int = int(hero.get("gold", 0))
	var inv: Array = hero.get("inventory", [])
	var has_room := inv.size() < 6
	for item_id in build_order:
		var sid: String = str(item_id)
		if inv.has(sid):
			continue
		var item: Dictionary = get_item(sid)
		if item.is_empty():
			continue
		# 成装：组件齐才可能推荐（且只需合成费）；组件没齐时先推荐第一件
		# 买得起的缺失组件，让合成树真的被「一步步走完」。
		if not recipe_of(sid).is_empty():
			if has_all_components(hero, sid):
				if gold >= combine_cost_of(sid):
					return sid
				continue
			var missing := first_missing_component(hero, sid)
			if missing != "" and has_room and gold >= int(get_item(missing).cost):
				return missing
			return ""
		if has_room and gold >= int(item.cost):
			return sid
	return ""
