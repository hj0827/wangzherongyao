extends RefCounted

# 技能特效的唯一真身。
#
# 这里只做两件纯逻辑的事，不碰任何节点：
#   ① recipe(kind)       —— 技能「长什么样」的配方（环 / 粒子 / 抛射物 / 拖尾 / 震屏）
#   ② requests(events)   —— 把模拟层的事件翻成渲染请求（唯一取口）
#
# 为什么按 kind 而不是按 hero_type：Q 和 W 是同一个英雄的两个技能，按英雄出效果
# 必然撞车。kind 才是技能形态（斩击 / 旋风 / 冲锋 / 陨石…），不同英雄复用同一形态
# 本来就该长得一样。
#
# 为什么要有 requests()：W/R 走 SkillSystem.cast_skill()，事件名是 skill_cast；
# Q/E 走 match_sim._cast_q/_cast_e，事件名是 skill。渲染层曾经只认后者，
# 于是大招放出去毫无表现、也不报错。现在两种事件在同一个入口归一，事件名不再是契约。

const HeroDefs = preload("res://sim/hero_defs.gd")

# 兜底：新加的 kind 忘了写配方时，至少还有一圈光和一把碎屑，不会「放了没反应」。
const DEFAULT_RECIPE := {
	"rings": [{"at": "aim", "from": 0.4, "to": 2.4, "dur": 0.3, "alpha": 0.55}],
	"particles": [{"at": "aim", "count": 12, "speed": 3.0, "height": 0.5, "life": 0.45, "size": 0.12}],
	"projectile": 0.0,
	"trail": 0,
	"beam": 0,
	"shake": 0.0,
	"hit_stop": 0.0,
}

const SUMMONER_COLORS := {
	"flash": Color(0.78, 0.92, 1.0),
	"execute": Color(1.0, 0.4, 0.36),
	"cleanse": Color(0.55, 0.95, 0.9),
	"heal": Color(0.45, 0.95, 0.6),
}

static func recipe(kind: String) -> Dictionary:
	match kind:
		"slash":
			# 苍刃 Q 裂空斩：贴地一道短斩环 + 前冲碎屑。
			return _make(
				[_ring("aim", 0.5, 2.6, 0.32, 0.65)],
				[_burst("aim", 22, 5.0, 0.6, 0.55)]
			)
		"spin":
			# 苍刃 W 旋风斩：脚下双环外扩，碎屑绕身散开。
			return _make(
				[_ring("self", 0.4, 3.4, 0.42, 0.55), _ring("self", 0.3, 2.0, 0.3, 0.5)],
				[_burst("self", 26, 4.2, 0.9, 0.5)],
				0.0, 0, 0, 0.08
			)
		"dash":
			# 苍刃 E 疾风步：起步环 + 路径残影，不做抛射物。
			return _make(
				[_ring("self", 0.4, 1.6, 0.26, 0.5)],
				[_burst("self", 8, 2.4, 0.5, 0.35)],
				0.0, 3
			)
		"leap_slam":
			# 苍刃 / 墨鸦 R：跳斩落点大环 + 双爆 + 震屏，必须比 Q 重。
			return _make(
				[_ring("aim", 0.8, 5.0, 0.5, 0.7), _ring("aim", 0.4, 2.4, 0.3, 0.6)],
				[_burst("aim", 30, 6.0, 0.8, 0.6), _burst("aim", 12, 2.6, 0.3, 0.4, 0.16)],
				0.0, 0, 0, 0.26, 0.06
			)
		"burst":
			# 星璃 Q / 墨鸦 W：法球飞到落点再炸开。
			return _make(
				[_ring("aim", 0.5, 2.8, 0.3, 0.6)],
				[_burst("aim", 20, 4.6, 0.6, 0.5)],
				0.22
			)
		"line":
			# 星璃 W 虚空织流：一道光带贯穿，沿线补残影环。
			return _make(
				[_ring("aim", 0.4, 2.2, 0.28, 0.55)],
				[_burst("aim", 14, 3.2, 0.5, 0.45)],
				0.0, 3, 1
			)
		"slow":
			# 星璃 E 星界禁锢：落点压一个缓慢扩张的禁锢环。
			return _make(
				[_ring("aim", 0.4, 3.0, 0.5, 0.55)],
				[_burst("aim", 16, 2.6, 0.7, 0.5)]
			)
		"meteor_storm":
			# 星璃 R 星河天倾：最大的一发，三层环 + 长震屏。
			return _make(
				[_ring("aim", 1.0, 6.0, 0.6, 0.7), _ring("aim", 0.5, 3.2, 0.45, 0.6)],
				[_burst("aim", 36, 7.0, 1.0, 0.7), _burst("aim", 16, 3.0, 0.4, 0.5, 0.15)],
				0.0, 0, 0, 0.3, 0.08
			)
		"quake":
			# 铁壁 Q 震地：自身为圆心的地面冲击环。
			return _make(
				[_ring("self", 0.5, 4.2, 0.5, 0.65)],
				[_burst("self", 20, 3.6, 0.4, 0.45)],
				0.0, 0, 0, 0.18
			)
		"charge":
			# 铁壁 W / 墨鸦 Q：冲锋，路径上留一串残影。
			return _make(
				[_ring("aim", 0.4, 2.2, 0.3, 0.55)],
				[_burst("aim", 14, 3.4, 0.5, 0.45)],
				0.0, 4, 0, 0.14
			)
		"shield":
			# 铁壁 E 守护壁垒：贴身收拢的光罩。
			return _make(
				[_ring("self", 0.5, 2.6, 0.45, 0.6)],
				[_burst("self", 18, 2.0, 1.2, 0.6)]
			)
		"taunt_aura":
			# 铁壁 R 不破要塞：以自身为中心向外推两圈。
			return _make(
				[_ring("self", 0.6, 5.0, 0.55, 0.65), _ring("self", 0.4, 3.0, 0.4, 0.55)],
				[_burst("self", 24, 3.0, 1.1, 0.6)],
				0.0, 0, 0, 0.2
			)
		"arrow":
			# 翎羽 Q 穿云箭：一支高速箭矢。
			return _make(
				[],
				[_burst("aim", 8, 2.2, 0.4, 0.35)],
				0.12
			)
		"aoe_shot":
			# 翎羽 W 爆裂疾射：箭矢 + 落点炸开。
			return _make(
				[_ring("aim", 0.5, 3.0, 0.32, 0.6)],
				[_burst("aim", 18, 4.0, 0.6, 0.5)],
				0.18
			)
		"haste":
			# 翎羽 E 鹰眼：脚下上浮的光点。
			return _make(
				[_ring("self", 0.4, 2.2, 0.4, 0.55)],
				[_burst("self", 14, 2.4, 1.4, 0.55)]
			)
		"arrow_barrage":
			# 翎羽 R 万箭归宗：落点连片箭雨。
			return _make(
				[_ring("aim", 0.8, 5.2, 0.5, 0.65), _ring("aim", 0.4, 2.6, 0.3, 0.55)],
				[_burst("aim", 34, 6.5, 0.9, 0.6)],
				0.0, 0, 0, 0.16
			)
		"evade":
			# 墨鸦 E 匿踪：淡出，刻意最轻。
			return _make(
				[_ring("self", 0.3, 1.8, 0.3, 0.45)],
				[_burst("self", 12, 1.8, 0.6, 0.4)]
			)
	return DEFAULT_RECIPE.duplicate(true)

static func summoner_recipe(spell: String) -> Dictionary:
	match spell:
		"flash":
			# 闪现：起点和落点各一圈，中间补残影，才读得出「瞬移」。
			return _make(
				[_ring("self", 0.3, 1.4, 0.22, 0.5), _ring("aim", 0.3, 1.4, 0.22, 0.5)],
				[_burst("self", 10, 2.0, 0.5, 0.4)],
				0.0, 2
			)
		"execute":
			# 终结：目标身上炸一发。
			return _make(
				[_ring("aim", 0.5, 2.6, 0.3, 0.7)],
				[_burst("aim", 20, 5.0, 0.7, 0.5)],
				0.0, 0, 0, 0.12
			)
		"cleanse":
			# 净化：脚下向上扫一圈。
			return _make(
				[_ring("self", 0.4, 2.2, 0.45, 0.6)],
				[_burst("self", 16, 2.2, 1.3, 0.55)]
			)
		"heal":
			# 治疗：绿色上浮光点。
			return _make(
				[_ring("self", 0.4, 2.8, 0.5, 0.6)],
				[_burst("self", 20, 2.0, 1.5, 0.6)]
			)
	return DEFAULT_RECIPE.duplicate(true)

static func summoner_color(spell: String) -> Color:
	return SUMMONER_COLORS.get(spell, Color(0.9, 0.92, 1.0))

# 老事件没有 kind 字段时，按 hero_type + slot 反查技能定义。
static func kind_for(hero_type: String, slot: String) -> String:
	if hero_type == "" or slot == "":
		return ""
	var def: Dictionary = HeroDefs.get_hero(hero_type)
	var skill: Dictionary = def.get(slot, {})
	return str(skill.get("kind", ""))

# 事件 → 渲染请求。Q/E 的 skill、W/R 的 skill_cast、召唤师技能的 summoner_cast
# 全部在这里归一，渲染层不再关心事件名。
static func requests(events: Array) -> Array:
	var out: Array = []
	for item in events:
		if not (item is Dictionary):
			continue
		var event: Dictionary = item
		var type := str(event.get("type", ""))
		if type == "skill" or type == "skill_cast":
			var slot := str(event.get("slot", "q"))
			var hero_type := str(event.get("hero_type", ""))
			var kind := str(event.get("kind", ""))
			if kind == "":
				kind = kind_for(hero_type, slot)
			out.append({
				"hero_id": int(event.get("hero", event.get("caster_id", -1))),
				"slot": slot,
				"hero_type": hero_type,
				"kind": kind,
				"summoner": "",
				"from": _point(event, "start_x", "start_y", "x", "y"),
				"aim": _point(event, "aim_x", "aim_y", "x", "y"),
				"recipe": recipe(kind),
			})
		elif type == "summoner_cast":
			var spell := str(event.get("spell_id", "flash"))
			out.append({
				"hero_id": int(event.get("caster_id", -1)),
				"slot": "",
				"hero_type": str(event.get("hero_type", "")),
				"kind": "summoner_" + spell,
				"summoner": spell,
				"from": _point(event, "start_x", "start_y", "x", "y"),
				"aim": _point(event, "aim_x", "aim_y", "x", "y"),
				"recipe": summoner_recipe(spell),
			})
	return out

static func _make(rings: Array, particles: Array, projectile := 0.0, trail := 0, beam := 0, shake := 0.0, hit_stop := 0.0) -> Dictionary:
	return {
		"rings": rings,
		"particles": particles,
		"projectile": projectile,
		"trail": trail,
		"beam": beam,
		"shake": shake,
		"hit_stop": hit_stop,
	}

static func _ring(at: String, from: float, to: float, dur: float, alpha: float) -> Dictionary:
	return {"at": at, "from": from, "to": to, "dur": dur, "alpha": alpha}

static func _burst(at: String, count: int, speed: float, height: float, life: float, size := 0.12) -> Dictionary:
	return {"at": at, "count": count, "speed": speed, "height": height, "life": life, "size": size}

static func _point(event: Dictionary, kx1: String, ky1: String, kx2: String, ky2: String) -> Vector2:
	if event.has(kx1) and event.has(ky1):
		return Vector2(float(event.get(kx1, 0.0)), float(event.get(ky1, 0.0)))
	return Vector2(float(event.get(kx2, 0.0)), float(event.get(ky2, 0.0)))
