extends "res://tests/test_base.gd"

# 英雄普攻表现契约（2026-10-28）。
#
# 起因：玩家反馈「英雄在进行普攻时没有什么明显的效果」。
# 查下来普攻只播一次骨骼动作，画面里没有任何「挥出去」的东西 ——
# 小兵的每一次攻击反而都有刀光/弹丸（见 test_unit_attack_fx），
# 英雄这个最该有打击感的主体成了唯一没有表现的。
#
# 契约：
# ① 形态由 hero_defs 的 attack_range 决定，不另写一份「谁是远程」的名单；
# ② 近战 = 一片新月刀光（有弧度、贴胸口），远程 = 一条弹道（无弧、从手部出）；
# ③ 暴击只放大、不改形态 —— 同一刀更狠，不是另一个技能；
# ④ 事件必须自带英雄类型与目标点，客机才画得出同一片刀光；
# ⑤ 刀光必须走池、必须真的接在 _process_events 的 "attack" 分支上（接线守卫）。

const Arena = preload("res://scripts/game/arena.gd")
const HeroDefs = preload("res://sim/hero_defs.gd")
const MatchSim = preload("res://sim/match_sim.gd")
const NetProtocol = preload("res://net/net_protocol.gd")
const WaveRules = preload("res://sim/map/wave_rules.gd")

const HERO_TYPES := ["blade", "mage", "tank", "archer", "assassin"]
# 近战 / 远程的**期望名单**写死在这里，不从 Arena 的阈值反推：
# 用 `reach < Arena.HERO_RANGED_REACH` 反推等于自己证明自己 ——
# 把阈值改成 0（所有人都变远程）测试照样绿，那就不是断言。
const MELEE_HEROES := ["blade", "tank", "assassin"]
const RANGED_HEROES := ["mage", "archer"]
# 分界阈值。数值表一侧必须真的跨过它，否则「谁是远程」只是巧合。
const RANGED_REACH_THRESHOLD := 4.0

func test_melee_heroes_swing_and_ranged_heroes_shoot() -> void:
	for hero_type in MELEE_HEROES:
		var reach := HeroDefs.attack_range(str(hero_type))
		var plan: Dictionary = Arena.hero_attack_fx_plan(str(hero_type))
		eq(str(plan.get("mode", "")), "slash", "%s 是近战，必须挥刀光" % str(hero_type))
		lt(reach, RANGED_REACH_THRESHOLD, "%s 的攻击距离要真的落在近战一侧" % str(hero_type))
		near(float(plan.get("reach", 0.0)), maxf(reach, 1.6), 0.001,
			"%s 的刀光长度必须等于攻击距离（远了看着在打空气）" % str(hero_type))
		gt(float(plan.get("arc", 0.0)), 90.0, "%s 的近战刀光必须有明显弧度" % str(hero_type))
		gt(float(plan.get("reach_ratio", 0.0)), 0.8, "%s 的刀光半径不能缩到看不见" % str(hero_type))
		lt(float(plan.get("reach_ratio", 9.0)), 1.0, "%s 的刀光不能比攻击距离还宽" % str(hero_type))
	for hero_type in RANGED_HEROES:
		var reach := HeroDefs.attack_range(str(hero_type))
		var plan: Dictionary = Arena.hero_attack_fx_plan(str(hero_type))
		eq(str(plan.get("mode", "")), "shot", "%s 是远程，必须打弹道" % str(hero_type))
		gt(reach, RANGED_REACH_THRESHOLD, "%s 的攻击距离要真的落在远程一侧" % str(hero_type))
		near(float(plan.get("arc", -1.0)), 0.0, 0.001, "%s 的远程普攻不该画弧" % str(hero_type))
		gt(float(plan.get("radius", 0.0)), 0.05, "%s 的弹道要有体积" % str(hero_type))
	for hero_type in HERO_TYPES:
		var plan: Dictionary = Arena.hero_attack_fx_plan(str(hero_type))
		near(float(plan.get("reach", 0.0)), maxf(HeroDefs.attack_range(str(hero_type)), 1.6), 0.001,
			"%s 的表现射程必须跟数值表同源" % str(hero_type))
		gt(float(plan.get("duration", 0.0)), 0.0, "%s 的普攻表现必须有持续时间" % str(hero_type))

func test_every_hero_has_its_own_color_and_height() -> void:
	var seen := {}
	for hero_type in HERO_TYPES:
		var plan: Dictionary = Arena.hero_attack_fx_plan(str(hero_type))
		var color: Color = plan.get("color", Color.BLACK)
		check(not seen.has(color.to_html()), "%s 的普攻颜色和别的英雄撞了" % str(hero_type))
		seen[color.to_html()] = true
		# 普攻和技能共用一个谱系色：同一场战斗里「我的颜色」只有一种。
		eq(color, Arena._hero_vfx_color(str(hero_type)), "%s 的普攻颜色必须和技能特效同源" % str(hero_type))
	# 刀光和弹道的出手高度必须不同：一个是挥在胸口的弧，一个是从手部抛出的点。
	check(
		not is_equal_approx(
			float(Arena.hero_attack_fx_plan("blade").get("height", 0.0)),
			float(Arena.hero_attack_fx_plan("archer").get("height", 0.0))
		),
		"刀光与弹道的出手高度必须不同"
	)

func test_crit_keeps_the_shape_but_hits_harder() -> void:
	for hero_type in HERO_TYPES:
		var normal: Dictionary = Arena.hero_attack_fx_plan(str(hero_type), false)
		var crit: Dictionary = Arena.hero_attack_fx_plan(str(hero_type), true)
		eq(str(crit.get("mode", "")), str(normal.get("mode", "")), "%s 暴击不能换形态" % str(hero_type))
		near(float(crit.get("reach", 0.0)), float(normal.get("reach", 0.0)), 0.001, "%s 暴击不能改射程" % str(hero_type))
		gt(float(crit.get("impact", 0)), float(normal.get("impact", 0)), "%s 暴击的命中火星要更多" % str(hero_type))
		gt(float(crit.get("shake", 0.0)), 0.0, "%s 暴击要带一点震屏" % str(hero_type))
		var normal_color: Color = normal.get("color", Color.BLACK)
		var crit_color: Color = crit.get("color", Color.BLACK)
		# 用**亮度**而不是 Color.v：谱系色本身已经是满值（v = 1.0），
		# 暴击是把三通道一起往白里拉，只有亮度会变。
		gt(_luma(crit_color), _luma(normal_color), "%s 暴击刀光要更亮" % str(hero_type))


static func _luma(color: Color) -> float:
	return color.r * 0.299 + color.g * 0.587 + color.b * 0.114

func test_slash_mesh_is_a_pointed_crescent_at_unit_radius() -> void:
	# 网格只建一次、12 个池节点共用，所以它的尺寸必须是「单位半径 + 靠缩放」：
	# 外沿 1.0（渲染时乘 attack_range），内沿最深处 HERO_SLASH_INNER。
	var mesh: ArrayMesh = Arena.slash_mesh()
	eq(mesh.get_surface_count(), 1, "刀光必须只有一个面")
	var arrays := mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	gt(float(vertices.size()), 8.0, "新月要有足够分段，否则两端是折线")
	var farthest := 0.0
	var nearest := INF
	var aimed := 0
	for point in vertices:
		near(point.y, 0.0, 0.0001, "刀光是水平面片，不能有高度差")
		var radius := Vector2(point.x, point.z).length()
		farthest = maxf(farthest, radius)
		nearest = minf(nearest, radius)
		if point.x > 0.9:
			aimed += 1
	near(farthest, 1.0, 0.001, "外沿半径必须是 1：实例靠缩放对准攻击距离")
	# 内沿写成一个**区间**而不是 HERO_SLASH_INNER 本身：
	# 拿常量当期望值的话，把常量改成 1.0（实心扇形）测试照样绿。
	# 0.70~0.88 = 既有厚度（俯视能看见弧形），又不是一块饼。
	gt(nearest, 0.70, "刀光内沿太靠外：一片弧会薄成一根线")
	lt(nearest, 0.88, "刀光内沿太靠内：会变成实心扇形（一块白饼）")
	gt(float(aimed), 0.0, "刀光必须朝局部 +X 张开（渲染层按这个朝向旋转）")
	# 两端收成尖：首两个顶点必须重合（内沿 = 外沿）。
	# 平口两端在俯视下读成「被切了一块的披萨」，不是刀光。
	var first_outer := Vector2(vertices[0].x, vertices[0].z)
	var first_inner := Vector2(vertices[1].x, vertices[1].z)
	lt(first_outer.distance_to(first_inner), 0.001, "刀光一端必须是尖的")
	var last_outer := Vector2(vertices[vertices.size() - 2].x, vertices[vertices.size() - 2].z)
	var last_inner := Vector2(vertices[vertices.size() - 1].x, vertices[vertices.size() - 1].z)
	lt(last_outer.distance_to(last_inner), 0.001, "刀光另一端也必须是尖的")

func test_attack_event_carries_hero_type_and_target() -> void:
	# 表现层不看 _views：客机这一帧没建好英雄视图时，事件里的 hero_type 就是唯一来源。
	var sim := MatchSim.new({
		"mode": "duel",
		"humans": [{"id": "p1", "team": "blue", "hero_type": "archer"}],
		"bot_fill": false,
		"bot_ai": false,
	})
	var hero: Dictionary = sim.get_hero_by_player("p1")
	var stats: Dictionary = WaveRules.stats("melee", 1)
	var spot: Vector2 = (hero.get("pos", Vector2.ZERO) as Vector2) + Vector2(1.5, 0.0)
	sim.state.entities.append({
		"id": 9001,
		"type": "minion",
		"team": "red",
		"lane": "mid",
		"minion_type": "melee",
		"pos": spot,
		"radius": float(stats.radius),
		"hp": 9000.0,
		"max_hp": 9000.0,
		"alive": true,
		"speed": 0.0,
		"attack_damage": 1.0,
		"attack_range": float(stats.attack_range),
		"attack_interval": 1.0,
		"attack_cd": 0.0,
		"path": [spot, spot],
		"path_index": 0,
		"path_dir": 1,
	})
	sim.consume_events()
	sim.set_input("p1", {"attack": true})
	sim.tick(0.05)
	var attacks: Array = sim.consume_events().filter(
		func(event): return str(event.get("type", "")) == "attack"
	)
	eq(attacks.size(), 1, "按住普攻必须发出一条 attack 事件")
	if attacks.is_empty():
		return
	var event: Dictionary = attacks[0]
	eq(str(event.get("hero_type", "")), "archer", "事件要带英雄类型：客机靠它选刀光/弹道")
	eq(int(event.get("hero", -1)), int(hero.get("id", -2)), "事件要带出手者")
	check(event.has("aim_x") and event.has("aim_y"), "事件要带目标点，刀光才知道朝哪挥")
	check(event.has("crit"), "事件要带暴击标记")
	near(float(event.get("aim_x", 0.0)), spot.x, 0.001, "目标点的 x 必须是被打单位的位置")

func test_net_snapshot_keeps_the_attack_fields() -> void:
	var result: Dictionary = NetProtocol.sanitize_snapshot({
		"time": 1.0,
		"mode": "duel",
		"bounds": 58.0,
		"entities": [],
		"events": [{
			"type": "attack",
			"hero": 7,
			"hero_type": "archer",
			"x": 1.0,
			"y": 2.0,
			"aim_x": 3.0,
			"aim_y": 4.0,
			"crit": true,
		}],
	})
	check(bool(result.get("ok", false)), "快照要被接受")
	var events: Array = result.get("snapshot", {}).get("events", [])
	eq(events.size(), 1, "attack 事件要保留到客机")
	if events.is_empty():
		return
	var kept: Dictionary = events[0]
	eq(str(kept.get("hero_type", "")), "archer", "客机要靠英雄类型选刀光/弹道")
	near(float(kept.get("aim_x", 0.0)), 3.0, 0.001, "客机要靠目标点定朝向")
	check(bool(kept.get("crit", false)), "客机也要知道这一下是暴击")

func test_the_attack_branch_actually_draws_it() -> void:
	# 接线守卫（00-hard-rules 第 9 条）：文件在 + 测试绿 ≠ 功能在跑。
	# 用 has_live_line 而不是 contains —— 把调用注释掉之后字符串还在，守卫会假绿。
	var source := FileAccess.get_file_as_string("res://scripts/game/arena.gd")
	check(has_live_line(source, "_handle_hero_attack(event)"), "attack 事件必须接到 _handle_hero_attack")
	check(has_live_line(source, "_spawn_slash("), "近战普攻必须真的生成刀光")
	check(has_live_line(source, "take_particle_slot(_slash_pool"), "刀光必须从池里取（硬规则 4）")
	check(has_live_line(source, "hero_attack_fx_plan("), "表现必须走纯函数配方")
	var sim_source := FileAccess.get_file_as_string("res://sim/match_sim.gd")
	check(has_live_line(sim_source, "\"hero_type\": str(hero.hero_type)"), "模拟层的 attack 事件必须带英雄类型")
