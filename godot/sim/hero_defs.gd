extends RefCounted

# 一队五人的默认职业配置：五大职业各一人。
const BOT_TYPES := ["blade", "tank", "assassin", "mage", "archer"]

const HEROES := {
	"blade": {
		"name": "苍刃",
		"role": "战士",
		"title": "裂空之刃",
		"quote": "剑气破长空，唯我立苍穹！",
		"video_path": "res://assets/ui/hero_videos/hero_blade.ogv",
		"max_hp": 1320.0,
		"max_mp": 420.0,
		"hp_growth": 95.0,
		"mp_growth": 24.0,
		"damage_growth": 7.5,
		"speed": 6.4,
		"radius": 0.55,
		"attack_damage": 78.0,
		"attack_range": 2.0,
		"attack_interval": 0.88,
		"passive": {"name": "绝影疾刃", "desc": "连续普攻积攒刀气，达到3层后下一次攻击附带额外伤害。"},
		"q": {"name": "裂空斩", "cost": 60.0, "cooldown": 4.5, "range": 5.5, "damage": 190.0, "kind": "slash"},
		"w": {"name": "旋风斩", "cost": 50.0, "cooldown": 6.0, "range": 3.8, "damage": 160.0, "kind": "spin"},
		"e": {"name": "疾风步", "cost": 40.0, "cooldown": 8.0, "range": 6.5, "damage": 0.0, "kind": "dash"},
		"r": {"name": "裂地崩山", "cost": 100.0, "cooldown": 28.0, "range": 7.0, "damage": 380.0, "kind": "leap_slam"},
	},
	"mage": {
		"name": "星璃",
		"role": "法师",
		"title": "星辰织者",
		"quote": "星辰流转，万象皆入我织网！",
		"video_path": "res://assets/ui/hero_videos/hero_mage.ogv",
		"max_hp": 1060.0,
		"max_mp": 560.0,
		"hp_growth": 74.0,
		"mp_growth": 38.0,
		"damage_growth": 6.0,
		"speed": 5.9,
		"radius": 0.50,
		"attack_damage": 55.0,
		"attack_range": 5.6,
		"attack_interval": 1.0,
		"passive": {"name": "星灵共鸣", "desc": "技能命中目标时返还法力并造成法术印记。"},
		"q": {"name": "星陨", "cost": 80.0, "cooldown": 5.5, "range": 8.0, "damage": 215.0, "kind": "burst"},
		"w": {"name": "虚空织流", "cost": 65.0, "cooldown": 7.5, "range": 7.2, "damage": 140.0, "kind": "line"},
		"e": {"name": "星界禁锢", "cost": 70.0, "cooldown": 10.0, "range": 6.5, "damage": 80.0, "kind": "slow"},
		"r": {"name": "星河天倾", "cost": 130.0, "cooldown": 32.0, "range": 8.5, "damage": 420.0, "kind": "meteor_storm"},
	},
	"tank": {
		"name": "铁壁",
		"role": "坦克",
		"title": "不破之盾",
		"quote": "山岳不动，吾身即是不破之城！",
		"video_path": "res://assets/ui/hero_videos/hero_tank.ogv",
		"max_hp": 1780.0,
		"max_mp": 380.0,
		"hp_growth": 130.0,
		"mp_growth": 20.0,
		"damage_growth": 6.0,
		"speed": 5.5,
		"radius": 0.65,
		"attack_damage": 62.0,
		"attack_range": 2.1,
		"attack_interval": 1.0,
		"passive": {"name": "不屈重甲", "desc": "生命值低于40%时触发减伤与自动回血护盾。"},
		"q": {"name": "震地", "cost": 55.0, "cooldown": 6.0, "range": 4.5, "damage": 145.0, "kind": "quake"},
		"w": {"name": "野蛮冲撞", "cost": 50.0, "cooldown": 8.0, "range": 5.5, "damage": 120.0, "kind": "charge"},
		"e": {"name": "守护壁垒", "cost": 65.0, "cooldown": 12.0, "range": 0.0, "damage": 0.0, "kind": "shield"},
		"r": {"name": "不破要塞", "cost": 90.0, "cooldown": 30.0, "range": 5.0, "damage": 220.0, "kind": "taunt_aura"},
	},
	"archer": {
		"name": "翎羽",
		"role": "射手",
		"title": "逐风之矢",
		"quote": "箭出无回，疾风所至破千军！",
		"video_path": "res://assets/ui/hero_videos/hero_archer.ogv",
		"max_hp": 1100.0,
		"max_mp": 440.0,
		"hp_growth": 78.0,
		"mp_growth": 28.0,
		"damage_growth": 8.0,
		"speed": 6.1,
		"radius": 0.50,
		"attack_damage": 66.0,
		"attack_range": 6.4,
		"attack_interval": 0.82,
		"passive": {"name": "灵动之风", "desc": "普攻命中敌方英雄提升移速与攻速。"},
		"q": {"name": "穿云箭", "cost": 55.0, "cooldown": 4.8, "range": 9.0, "damage": 185.0, "kind": "arrow"},
		"w": {"name": "爆裂疾射", "cost": 60.0, "cooldown": 7.0, "range": 7.5, "damage": 150.0, "kind": "aoe_shot"},
		"e": {"name": "鹰眼", "cost": 50.0, "cooldown": 10.0, "range": 0.0, "damage": 0.0, "kind": "haste", "duration": 3.0},
		"r": {"name": "万箭归宗", "cost": 110.0, "cooldown": 26.0, "range": 9.5, "damage": 390.0, "kind": "arrow_barrage"},
	},
	"assassin": {
		"name": "墨鸦",
		"role": "刺客",
		"title": "暗影之刺",
		"quote": "三息之内，取你首级！",
		"video_path": "res://assets/ui/hero_videos/hero_assassin.ogv",
		"max_hp": 940.0,
		"max_mp": 400.0,
		"hp_growth": 66.0,
		"mp_growth": 22.0,
		"damage_growth": 9.5,
		"speed": 6.9,
		"radius": 0.48,
		"attack_damage": 84.0,
		"attack_range": 2.0,
		"attack_interval": 0.74,
		"passive": {"name": "暗影背刺", "desc": "从目标背后命中时，额外造成 25% 普攻伤害。"},
		"q": {"name": "影袭", "cost": 55.0, "cooldown": 4.2, "range": 4.5, "damage": 170.0, "kind": "charge"},
		"w": {"name": "毒牙", "cost": 50.0, "cooldown": 6.0, "range": 3.4, "damage": 150.0, "kind": "burst"},
		"e": {"name": "匿踪", "cost": 45.0, "cooldown": 9.0, "range": 0.0, "damage": 0.0, "kind": "evade", "duration": 2.5, "immune": 1.2},
		"r": {"name": "绝影处决", "cost": 100.0, "cooldown": 26.0, "range": 6.0, "damage": 400.0, "kind": "leap_slam"},
	},
}

static func get_hero(hero_type: String) -> Dictionary:
	return HEROES.get(hero_type, HEROES["blade"])

static func is_valid(hero_type: String) -> bool:
	return HEROES.has(hero_type)

# 五大职业的顺序（选人界面、名册文档都按它排）。
static func roles() -> Array:
	var out: Array = []
	for hero_type in HEROES:
		var role := str(HEROES[hero_type].get("role", ""))
		if not out.has(role):
			out.append(role)
	return out

# 普攻射程（地面范围指示器用）。
static func attack_range(hero_type: String) -> float:
	return float(get_hero(hero_type).get("attack_range", 0.0))

# 技能射程。自身增益类技能（护盾/加速）没有射程，返回 0。
static func skill_range(hero_type: String, slot: String) -> float:
	var skill: Variant = get_hero(hero_type).get(slot, {})
	if not (skill is Dictionary):
		return 0.0
	return float((skill as Dictionary).get("range", 0.0))
