extends RefCounted

const BOT_TYPES := ["blade", "mage", "tank", "archer", "mage"]

const HEROES := {
	"blade": {
		"name": "苍刃",
		"role": "战士",
		"title": "裂空之刃",
		"quote": "剑气破长空，唯我立苍穹！",
		"video_path": "res://assets/ui/hero_videos/hero_blade.ogv",
		"max_hp": 1080.0,
		"max_mp": 420.0,
		"hp_growth": 95.0,
		"mp_growth": 24.0,
		"damage_growth": 7.5,
		"speed": 6.4,
		"radius": 0.55,
		"attack_damage": 78.0,
		"attack_range": 2.0,
		"attack_interval": 0.88,
		"q": {"name": "裂空斩", "cost": 60.0, "cooldown": 4.5, "range": 5.5, "damage": 190.0, "kind": "slash"},
		"e": {"name": "疾风步", "cost": 40.0, "cooldown": 8.0, "range": 6.5, "damage": 0.0, "kind": "dash"},
	},
	"mage": {
		"name": "星璃",
		"role": "法师",
		"title": "星辰织者",
		"quote": "星辰流转，万象皆入我织网！",
		"video_path": "res://assets/ui/hero_videos/hero_mage.ogv",
		"max_hp": 840.0,
		"max_mp": 560.0,
		"hp_growth": 74.0,
		"mp_growth": 38.0,
		"damage_growth": 6.0,
		"speed": 5.9,
		"radius": 0.50,
		"attack_damage": 55.0,
		"attack_range": 5.6,
		"attack_interval": 1.0,
		"q": {"name": "星陨", "cost": 80.0, "cooldown": 5.5, "range": 8.0, "damage": 215.0, "kind": "burst"},
		"e": {"name": "星界禁锢", "cost": 70.0, "cooldown": 10.0, "range": 6.5, "damage": 80.0, "kind": "slow"},
	},
	"tank": {
		"name": "铁壁",
		"role": "坦克",
		"title": "不破之盾",
		"quote": "山岳不动，吾身即是不破之城！",
		"video_path": "res://assets/ui/hero_videos/hero_tank.ogv",
		"max_hp": 1450.0,
		"max_mp": 380.0,
		"hp_growth": 130.0,
		"mp_growth": 20.0,
		"damage_growth": 6.0,
		"speed": 5.5,
		"radius": 0.65,
		"attack_damage": 62.0,
		"attack_range": 2.1,
		"attack_interval": 1.0,
		"q": {"name": "震地", "cost": 55.0, "cooldown": 6.0, "range": 4.5, "damage": 145.0, "kind": "quake"},
		"e": {"name": "守护壁垒", "cost": 65.0, "cooldown": 12.0, "range": 0.0, "damage": 0.0, "kind": "shield"},
	},
	"archer": {
		"name": "翎羽",
		"role": "射手",
		"title": "逐风之矢",
		"quote": "箭出无回，疾风所至破千军！",
		"video_path": "res://assets/ui/hero_videos/hero_archer.ogv",
		"max_hp": 880.0,
		"max_mp": 440.0,
		"hp_growth": 78.0,
		"mp_growth": 28.0,
		"damage_growth": 8.0,
		"speed": 6.1,
		"radius": 0.50,
		"attack_damage": 66.0,
		"attack_range": 6.4,
		"attack_interval": 0.82,
		"q": {"name": "穿云箭", "cost": 55.0, "cooldown": 4.8, "range": 9.0, "damage": 185.0, "kind": "arrow"},
		"e": {"name": "鹰眼", "cost": 50.0, "cooldown": 10.0, "range": 0.0, "damage": 0.0, "kind": "haste"},
	},
}

static func get_hero(hero_type: String) -> Dictionary:
	return HEROES.get(hero_type, HEROES["blade"])

static func is_valid(hero_type: String) -> bool:
	return HEROES.has(hero_type)

# 普攻射程（地面范围指示器用）。
static func attack_range(hero_type: String) -> float:
	return float(get_hero(hero_type).get("attack_range", 0.0))

# 技能射程。自身增益类技能（护盾/加速）没有射程，返回 0。
static func skill_range(hero_type: String, slot: String) -> float:
	var skill: Variant = get_hero(hero_type).get(slot, {})
	if not (skill is Dictionary):
		return 0.0
	return float((skill as Dictionary).get("range", 0.0))
