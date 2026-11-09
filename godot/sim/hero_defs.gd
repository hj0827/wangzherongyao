extends RefCounted

# 一队五人的默认职业配置：五大职业各一人。
const BOT_TYPES := ["blade", "tank", "assassin", "mage", "archer"]

# --- 技能等级规则（项 2，差距文档 §3.2）-----------------------------------
# 这些是"英雄技能的数据规则"，真身放这里：sim 与 net_protocol 都 preload 本文件，
# 两边引用同一组常量，避免 crit_rate 那种"两条路径各写一个上限"的口径漂移。
const MAX_LEVEL := 15                    # 英雄等级上限
const SKILL_SLOTS := ["q", "w", "e", "r"]
const MAX_SKILL_LEVEL_NORMAL := 6        # Q/W/E 上限
const MAX_SKILL_LEVEL_ULT := 3           # R 上限
const ULT_UNLOCK_LEVELS := [4, 7, 10]    # R 升到 1/2/3 级需要的英雄等级
const MAX_SKILL_POINTS := MAX_LEVEL - 1  # 攒点的物理上限（升到满级的总点数）

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
		"q": {"name": "裂空斩", "cost": 60.0, "cooldown": 4.5, "range": 5.5, "damage": 190.0, "damage_grow": 55.0, "kind": "slash", "damage_type": "physical"},
		"w": {"name": "旋风斩", "cost": 50.0, "cooldown": 6.0, "range": 3.8, "damage": 160.0, "damage_grow": 45.0, "kind": "spin", "damage_type": "physical"},
		"e": {"name": "疾风步", "cost": 40.0, "cooldown": 8.0, "range": 6.5, "damage": 0.0, "kind": "dash", "damage_type": "physical"},
		"r": {"name": "裂地崩山", "cost": 100.0, "cooldown": 28.0, "range": 7.0, "damage": 380.0, "damage_grow": 110.0, "kind": "leap_slam", "damage_type": "physical"},
		"skill_plan": ["q", "w", "r", "e", "q", "r", "w", "e", "r", "q", "w", "e", "q", "w"],
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
		"q": {"name": "星陨", "cost": 80.0, "cooldown": 5.5, "range": 8.0, "damage": 215.0, "damage_grow": 60.0, "kind": "burst", "damage_type": "magic"},
		"w": {"name": "虚空织流", "cost": 65.0, "cooldown": 7.5, "range": 7.2, "damage": 140.0, "damage_grow": 40.0, "kind": "line", "damage_type": "magic"},
		"e": {"name": "星界禁锢", "cost": 70.0, "cooldown": 10.0, "range": 6.5, "damage": 80.0, "damage_grow": 25.0, "kind": "slow", "damage_type": "magic"},
		"r": {"name": "星河天倾", "cost": 130.0, "cooldown": 32.0, "range": 8.5, "damage": 420.0, "damage_grow": 130.0, "kind": "meteor_storm", "damage_type": "magic"},
		"skill_plan": ["q", "w", "r", "e", "q", "r", "w", "e", "r", "q", "w", "e", "q", "w"],
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
		"q": {"name": "震地", "cost": 55.0, "cooldown": 6.0, "range": 4.5, "damage": 145.0, "damage_grow": 40.0, "kind": "quake", "damage_type": "physical"},
		"w": {"name": "野蛮冲撞", "cost": 50.0, "cooldown": 8.0, "range": 5.5, "damage": 120.0, "damage_grow": 35.0, "kind": "charge", "damage_type": "physical"},
		"e": {"name": "守护壁垒", "cost": 65.0, "cooldown": 12.0, "range": 0.0, "damage": 0.0, "kind": "shield"},
		"r": {"name": "不破要塞", "cost": 90.0, "cooldown": 30.0, "range": 5.0, "damage": 220.0, "damage_grow": 70.0, "kind": "taunt_aura", "damage_type": "magic"},
		"skill_plan": ["q", "w", "r", "e", "q", "r", "w", "e", "r", "q", "w", "e", "q", "w"],
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
		"q": {"name": "穿云箭", "cost": 55.0, "cooldown": 4.8, "range": 9.0, "damage": 185.0, "damage_grow": 48.0, "kind": "arrow", "damage_type": "physical"},
		"w": {"name": "爆裂疾射", "cost": 60.0, "cooldown": 7.0, "range": 7.5, "damage": 150.0, "damage_grow": 40.0, "kind": "aoe_shot", "damage_type": "physical"},
		"e": {"name": "鹰眼", "cost": 50.0, "cooldown": 10.0, "range": 0.0, "damage": 0.0, "kind": "haste", "duration": 3.0},
		"r": {"name": "万箭归宗", "cost": 110.0, "cooldown": 26.0, "range": 9.5, "damage": 390.0, "damage_grow": 105.0, "kind": "arrow_barrage", "damage_type": "physical"},
		"skill_plan": ["q", "w", "r", "e", "q", "r", "w", "e", "r", "q", "w", "e", "q", "w"],
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
		"q": {"name": "影袭", "cost": 55.0, "cooldown": 4.2, "range": 4.5, "damage": 170.0, "damage_grow": 50.0, "kind": "charge", "damage_type": "physical"},
		"w": {"name": "毒牙", "cost": 50.0, "cooldown": 6.0, "range": 3.4, "damage": 150.0, "damage_grow": 42.0, "kind": "burst", "damage_type": "physical"},
		"e": {"name": "匿踪", "cost": 45.0, "cooldown": 9.0, "range": 0.0, "damage": 0.0, "kind": "evade", "duration": 2.5, "immune": 1.2},
		"r": {"name": "绝影处决", "cost": 100.0, "cooldown": 26.0, "range": 6.0, "damage": 400.0, "damage_grow": 120.0, "kind": "leap_slam", "damage_type": "physical"},
		"skill_plan": ["q", "w", "r", "e", "q", "r", "w", "e", "r", "q", "w", "e", "q", "w"],
	},
}

static func get_hero(hero_type: String) -> Dictionary:
	return HEROES.get(hero_type, HEROES["blade"])

# --- 技能等级化（项 2）-----------------------------------------------------
# 读某英雄某槽位的技能等级。缺键（小兵/野怪/旧构造字典）一律按 1 级，
# 只有 r 缺键按 0（未学习）—— 与出生值口径一致。
static func skill_level(hero: Dictionary, slot: String) -> int:
	var key := "skill_%s_level" % slot
	if not hero.has(key):
		return 0 if slot == "r" else 1
	return int(hero.get(key, 1))

# 技能伤害 = 表内 damage + damage_grow * (技能等级 - 1)。
# 两条施法路径（match_sim 的 Q/E、skill_system 的 W/R）都调这一个函数，
# 保证「成长只写在一处」—— 否则会出现只有一半技能会升级还不报错。
static func scaled_damage(hero: Dictionary, slot: String) -> float:
	var skill: Dictionary = get_hero(str(hero.get("hero_type", "blade"))).get(slot, {})
	if not (skill is Dictionary):
		return 0.0
	var base := float(skill.get("damage", 0.0))
	var grow := float(skill.get("damage_grow", 0.0))
	var lv := skill_level(hero, slot)
	if lv <= 1:
		return base
	return base + grow * float(lv - 1)

## 技能为什么放不出来（项 2）。空串 = 可以放 / 不该由本函数否决。
## 做成 static 且只读"快照里就有的字段"（mp / skill_*_cd / skill_*_level），
## 是为了让 sim、主机 arena、客机 HUD 用**同一个函数**判：
##  - 客机没有 sim，调不到 MatchSim 的实例方法；
##  - 各写一份的话，"按了没反应"的原因就会在一边说冷却、另一边说没蓝。
## 空 hero 与非技能槽都返回 ""：快照还没就绪、或这根本不是技能（回城/传送/召唤师），
## 本函数无权否决 —— 返回"没有这个技能"会让 arena 把回城键一起吞掉（旧实现靠
## 槽位白名单挡住这件事，收进一个函数后必须由函数自己保证）。
static func skill_block_reason(hero: Dictionary, slot: String) -> String:
	if hero.is_empty() or not SKILL_SLOTS.has(slot):
		return ""
	var lv := skill_level(hero, slot)
	if slot == "r" and lv <= 0:
		return "需要 %d 级解锁大招" % int(ULT_UNLOCK_LEVELS[0])
	if float(hero.get("skill_%s_cd" % slot, 0.0)) > 0.0:
		return "冷却中"
	var skill: Variant = get_hero(str(hero.get("hero_type", "blade"))).get(slot, {})
	if skill is Dictionary and float(hero.get("mp", 0.0)) < float((skill as Dictionary).get("cost", 0.0)):
		return "法力不足"
	return ""

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
