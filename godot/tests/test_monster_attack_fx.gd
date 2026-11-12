extends "res://tests/test_base.gd"

# 野怪 / 小兵攻击表现升级（2026-11-11）。
#
# 起因：三处「看不见」的具体症状。
#   ① **野怪根本没有攻击事件**：`_update_monsters()` 只结算伤害，表现层只能从 `hit` 的
#      `source` 反推「有东西打了我」，于是打野时野怪一动不动、没有爪光、没有音效，
#      玩家读不出「它在还手」；
#   ② 小兵虽然早就有 `minion_attack`（`test_unit_attack_fx`），但**近战兵画的是
#      一颗飞过去的小球**，远程/炮车/超级兵除了球大一点之外长得完全一样；
#   ③ 配方里的 `smoke` 贴图在生产代码里 0 引用（差距文档 §3 D5），野怪扬尘只能用火星凑。
#
# 本轮契约（全部可机读）：
#   ① sim 每次野怪出手都发 `monster_attack`，带 `monster_type / buff_type / objective`；
#   ② 这些键必须过 `net_protocol` 白名单，否则客机看到「血在掉、怪没动」；
#   ③ 配方仍由纯函数 `Arena.attack_fx_plan()` 给，且野怪/小兵/炮车/首领两两不同
#      （形状 + 残留 + 震屏，不是只换颜色）；
#   ④ 渲染层真的消费 `shape / arc_deg / arc_count / decal / shake`，且不新开节点。

const Arena = preload("res://scripts/game/arena.gd")
const MatchSim = preload("res://sim/match_sim.gd")
const NetProtocol = preload("res://net/net_protocol.gd")
const UnitVisual = preload("res://scripts/game/unit_visual.gd")
const AudioPlan = preload("res://scripts/game/audio_plan.gd")
const AudioCues = preload("res://scripts/game/audio_cues.gd")

func _sim() -> Object:
	return MatchSim.new({
		"mode": "duel",
		"humans": [{"id": "p1", "team": "blue", "hero_type": "blade"}],
		"bot_fill": false,
		"bot_ai": false,
	})

# 第一个野区营地（非首领）：用真实数据，证明「12 个野点的常态」而不是手搭的假实体。
func _camp_monster(sim: Object) -> Dictionary:
	for entity in sim.state.entities:
		if str(entity.get("type", "")) != "monster" or bool(entity.get("objective", false)):
			continue
		if str(entity.get("monster_type", "")) == "spirit":
			continue
		return entity
	return {}

# 首领在 120s 才刷：测试不等两分钟，手搭一只同结构的实体（照 test_unit_attack_fx 的写法）。
func _boss(id: int, pos: Vector2) -> Dictionary:
	return {
		"id": id,
		"type": "monster",
		"team": "neutral",
		"monster_type": "orc",
		"name": "暴君",
		"objective": true,
		"objective_id": "tyrant",
		"pos": pos,
		"x": pos.x,
		"y": pos.y,
		"radius": 2.6,
		"hp": 6800.0,
		"max_hp": 6800.0,
		"attack_damage": 1.0,
		"attack_range": 3.4,
		"attack_interval": 1.4,
		"attack_cd": 0.0,
		"leash_range": 14.0,
		"move_speed": 0.0,
		"alive": true,
		"respawn_timer": 0.0,
		"last_attacker_id": -1,
		"last_attacker_time": -999.0,
	}

func _monster_attacks(sim: Object, source_id: int) -> Array:
	var out: Array = []
	for event in sim.consume_events():
		if str(event.get("type", "")) != "monster_attack":
			continue
		if int(event.get("source", -1)) != source_id:
			continue
		out.append(event)
	return out

func _cue_names(list: Array) -> Array:
	var out := []
	for item in list:
		out.append(str(item.get("cue", "")))
	return out

# 配方指纹：只看「形状 / 节奏 / 残留 / 力度」，不看颜色。
# 颜色撞车是允许的（那只是同一族换色），形状撞车才是「升级没做」。
static func _plan_signature(plan: Dictionary) -> String:
	var parts: Array[String] = [
		str(plan.get("shape", "")),
		"%.1f" % float(plan.get("arc_deg", 0.0)),
		"%d" % int(plan.get("arc_count", 1)),
		str(plan.get("decal", "")),
		str(plan.get("dust", "")),
		"%d" % int(plan.get("impact", 0)),
		"%.2f" % float(plan.get("shake", 0.0)),
	]
	return "|".join(parts)

# 取出一个函数的函数体（到下一个顶格 func 为止）。守卫用：攻击链路里不许再 new / queue_free。
static func _function_body(source: String, signature: String) -> String:
	var lines := source.split("\n")
	var body := ""
	var inside := false
	for line in lines:
		if not inside:
			if line.begins_with(signature):
				inside = true
			continue
		if line.begins_with("func ") or line.begins_with("static func "):
			break
		body += line + "\n"
	return body

# ---------------------------------------------------------------------------
# ① sim：野怪出手必须发事件（以前只有伤害，没有表现）
# ---------------------------------------------------------------------------

func test_jungle_monster_emits_an_attack_event() -> void:
	var sim := _sim()
	var hero: Dictionary = sim.get_hero_by_player("p1")
	var monster := _camp_monster(sim)
	check(not monster.is_empty(), "duel 里必须有野区营地")
	if monster.is_empty() or hero.is_empty():
		return
	var monster_id := int(monster.get("id", -1))
	hero["pos"] = (monster["pos"] as Vector2) + Vector2(1.4, 0.0)
	hero["hp"] = 99999.0
	hero["max_hp"] = 99999.0
	sim.consume_events()
	# 野怪是「纯反击」（见 _monster_target）：必须先留下仇恨，它才会还手。
	sim.apply_damage(monster_id, 8.0, int(hero.get("id", -1)))
	var attacks: Array = []
	# 1.33s < 攻击间隔 1.4s：这段时间内最多一刀，多出来的就是事件刷屏。
	for i in 40:
		sim.tick(1.0 / 30.0)
		attacks.append_array(_monster_attacks(sim, monster_id))
	eq(attacks.size(), 1, "野怪出手必须发 monster_attack（以前只结算伤害，画面里怪不动）")
	if attacks.is_empty():
		return
	var event: Dictionary = attacks[0]
	eq(str(event.get("monster_type", "")), str(monster.get("monster_type", "")), "事件要带物种：爪光样式由它决定")
	eq(int(event.get("target", -1)), int(hero.get("id", -1)), "事件要带被打的人")
	check(event.has("target_x") and event.has("target_y"), "事件要带落点：爪光朝向靠它")
	check(event.has("x") and event.has("y"), "事件要带出手坐标")
	eq(str(event.get("buff_type", "")), str(monster.get("buff_type", "")), "红/蓝BUFF 怪的出手色由 buff_type 决定")
	check(not bool(event.get("objective", false)), "小野点不是首领")

func test_objective_attack_carries_boss_flags() -> void:
	var sim := _sim()
	var hero: Dictionary = sim.get_hero_by_player("p1")
	var boss := _boss(9001, Vector2(6.0, 6.0))
	sim.state.entities.append(boss)
	hero["pos"] = Vector2(7.6, 6.0)
	hero["hp"] = 99999.0
	hero["max_hp"] = 99999.0
	sim.consume_events()
	sim.apply_damage(9001, 8.0, int(hero.get("id", -1)))
	var attacks: Array = []
	for i in 40:
		sim.tick(1.0 / 30.0)
		attacks.append_array(_monster_attacks(sim, 9001))
	eq(attacks.size(), 1, "首领出手同样要发事件")
	if attacks.is_empty():
		return
	check(bool(attacks[0].get("objective", false)), "首领攻击必须带 objective：表现层靠它放大砸地")
	eq(str(attacks[0].get("objective_id", "")), "tyrant", "首领 id 也要带上，两只首领的演出不同")

# ---------------------------------------------------------------------------
# ② 联机白名单（06-net-sync §4）：漏键 = 客机看到「血在掉、怪没动」
# ---------------------------------------------------------------------------

func test_net_whitelist_keeps_monster_attack_fields() -> void:
	var result: Dictionary = NetProtocol.sanitize_snapshot({
		"time": 1.0,
		"mode": "duel",
		"bounds": 58.0,
		"entities": [],
		"events": [{
			"type": "monster_attack",
			"source": 9,
			"team": "neutral",
			"monster_type": "boar",
			"camp_id": "red_pig_blue_side",
			"buff_type": "red",
			"objective": false,
			"objective_id": "",
			"target": 3,
			"target_type": "hero",
			"x": 1.0,
			"y": 2.0,
			"target_x": 3.0,
			"target_y": 4.0,
		}],
	})
	check(bool(result.get("ok", false)), "快照要被接受")
	var events: Array = result.get("snapshot", {}).get("events", [])
	eq(events.size(), 1, "野怪攻击事件要保留到客机")
	if events.is_empty():
		return
	var kept: Dictionary = events[0]
	eq(str(kept.get("monster_type", "")), "boar", "客机要靠物种选爪光（白名单漏了就是全员狼爪）")
	eq(str(kept.get("buff_type", "")), "red", "客机要靠 buff 选出手色")
	eq(str(kept.get("camp_id", "")), "red_pig_blue_side", "客机要靠营地点位对齐样式")
	check(kept.has("objective"), "objective 也要过白名单：漏了首领在客机上只是普通爪光")

# ---------------------------------------------------------------------------
# ③ 配方：形状 / 残留 / 震屏 两两不同
# ---------------------------------------------------------------------------

func test_monster_attack_plans_differ_by_species() -> void:
	var wolf: Dictionary = Arena.attack_fx_plan({"type": "monster_attack", "monster_type": "wolf"})
	var boar: Dictionary = Arena.attack_fx_plan({"type": "monster_attack", "monster_type": "boar"})
	var buff: Dictionary = Arena.attack_fx_plan({
		"type": "monster_attack", "monster_type": "wolf",
		"buff_type": "blue", "camp_id": "blue_buff_blue_side",
	})
	var boss: Dictionary = Arena.attack_fx_plan({
		"type": "monster_attack", "monster_type": "orc", "objective": true, "objective_id": "tyrant",
	})
	var spirit: Dictionary = Arena.attack_fx_plan({"type": "monster_attack", "monster_type": "spirit"})
	var seen := {}
	for pair in [["wolf", wolf], ["boar", boar], ["buff", buff], ["boss", boss], ["spirit", spirit]]:
		var sig := _plan_signature(pair[1])
		check(not seen.has(sig), "%s 的野怪攻击配方和 %s 撞了（只换了颜色）" % [str(pair[0]), str(seen.get(sig, ""))])
		seen[sig] = pair[0]
	eq(seen.size(), 5, "五种野怪的出手必须都能分辨")
	eq(str(wolf.get("shape", "")), "arc", "普通野怪是挥爪")
	gt(float(wolf.get("arc_count", 1)), 1.0, "狼是双爪：两片弧交错才读得出爪痕")
	eq(str(boar.get("dust", "")), "smoke", "野猪扬起的是土（烟），不是火星")
	gt(float(buff.get("impact", 0)), float(wolf.get("impact", 0)), "BUFF 怪一击比小野点重")
	gt(float(boss.get("impact", 0)), float(wolf.get("impact", 0)) * 2.0, "首领一击要比小野点重得多")
	gt(float(boss.get("shake", 0.0)), 0.1, "首领砸地要有震屏")
	eq(str(boss.get("decal", "")), "shock", "首领砸地要留地裂")
	eq(str(spirit.get("shape", "")), "splash", "河道之灵是一圈水花，不是爪光")

func test_minion_attack_shapes_are_distinct_and_heavier_ones_land() -> void:
	var melee: Dictionary = Arena.attack_fx_plan({"type": "minion_attack", "minion_type": "melee"})
	var ranged: Dictionary = Arena.attack_fx_plan({"type": "minion_attack", "minion_type": "ranged"})
	var cannon: Dictionary = Arena.attack_fx_plan({"type": "minion_attack", "minion_type": "cannon"})
	var super_minion: Dictionary = Arena.attack_fx_plan({"type": "minion_attack", "minion_type": "super"})
	eq(str(melee.get("shape", "")), "arc", "近战兵是刀光，不是飞过去的小球")
	gt(float(melee.get("arc_deg", 0.0)), 60.0, "刀光要有弧度")
	eq(str(ranged.get("shape", "")), "orb", "远程兵是弹丸")
	check(bool(ranged.get("muzzle", false)), "远程兵出手要有枪口闪光：只有一颗小球看不出是谁放的")
	eq(str(cannon.get("shape", "")), "orb", "炮车也是弹丸")
	gt(float(cannon.get("impact", 0)), float(ranged.get("impact", 0)), "炮车命中火星更多")
	eq(str(cannon.get("decal", "")), "shock", "炮车落点要留冲击痕迹")
	gt(float(cannon.get("shake", 0.0)), 0.0, "炮车落地要有一点点震")
	gt(float(super_minion.get("arc_deg", 0.0)), float(melee.get("arc_deg", 0.0)), "超级兵刀光更宽")
	eq(str(melee.get("dust", "")), "smoke", "近战兵脚下要扬尘（smoke 贴图从此有生产引用）")

func test_arc_reach_follows_the_real_distance() -> void:
	var near: Dictionary = Arena.attack_fx_plan({
		"type": "minion_attack", "minion_type": "melee",
		"x": 0.0, "y": 0.0, "target_x": 1.2, "target_y": 0.0,
	})
	var far: Dictionary = Arena.attack_fx_plan({
		"type": "minion_attack", "minion_type": "melee",
		"x": 0.0, "y": 0.0, "target_x": 2.4, "target_y": 0.0,
	})
	gt(float(far.get("reach", 0.0)), float(near.get("reach", 0.0)), "刀光要够到目标：距离越远弧越长")
	lt(float(near.get("reach", 0.0)), 1.8, "近身时刀光不能夸张地长（会把整条兵线糊成一片）")

func test_every_texture_named_by_the_new_plans_exists() -> void:
	# 贴图名写错时 file_texture() 返回 null、粒子静默变白方片，不报错。
	var FxTextures = load("res://scripts/game/fx_textures.gd")
	var events: Array = [
		{"type": "minion_attack", "minion_type": "melee"},
		{"type": "minion_attack", "minion_type": "ranged"},
		{"type": "minion_attack", "minion_type": "cannon"},
		{"type": "minion_attack", "minion_type": "super"},
		{"type": "monster_attack", "monster_type": "wolf"},
		{"type": "monster_attack", "monster_type": "boar"},
		{"type": "monster_attack", "monster_type": "bird"},
		{"type": "monster_attack", "monster_type": "lizard"},
		{"type": "monster_attack", "monster_type": "spirit"},
		{"type": "monster_attack", "monster_type": "wolf", "buff_type": "red"},
		{"type": "monster_attack", "monster_type": "orc", "objective": true},
		{"type": "structure_attack", "source_type": "tower", "tier": "outer"},
	]
	for event in events:
		var plan: Dictionary = Arena.attack_fx_plan(event)
		for key in ["dust", "decal", "texture"]:
			var name := str(plan.get(key, ""))
			if name == "":
				continue
			check(
				FxTextures.file_texture(name) != null,
				"%s 的 %s 贴图 '%s' 不存在" % [str(event.get("type", "")), key, name]
			)

# ---------------------------------------------------------------------------
# ④ 渲染层：接线 + 消费 + 战斗期零分配
# ---------------------------------------------------------------------------

func test_arena_routes_monster_attacks_and_uses_pools() -> void:
	# 分发在 event_router.gd（C17），生成逻辑仍在 arena：两份源码都要看。
	var source := FileAccess.get_file_as_string("res://scripts/game/arena.gd") \
		+ FileAccess.get_file_as_string("res://scripts/game/event_router.gd")
	check(has_live_line(source, '"monster_attack":'), "monster_attack 必须接进 _process_events 的分发")
	check(has_live_line(source, "_handle_monster_attack(event)"), "要接到 _handle_monster_attack")
	check(has_live_line(source, "attack_fx_plan("), "野怪与小兵共用同一份纯函数配方")
	check(has_live_line(source, "_spawn_slash("), "近战爪光/刀光必须走池化的新月")
	check(has_live_line(source, 'str(plan.get("shape", "orb"))'), "渲染层必须真的按 shape 分支")
	check(has_live_line(source, 'str(plan.get("decal", ""))'), "命中残留必须真的吃掉配方")
	check(has_live_line(source, "take_particle_slot(_slash_pool"), "爪光必须从池里取（硬规则 4）")

func test_attack_handlers_never_allocate_in_combat() -> void:
	# 硬规则 4：小兵/野怪的攻击是**每秒十几次**的频率，这里 new 一次就是真机掉帧。
	# 用函数体扫描而不是全文件扫描：arena 别处（装配期）允许 new。
	var source := FileAccess.get_file_as_string("res://scripts/game/arena.gd")
	for signature in [
		"func _handle_minion_attack(",
		"func _handle_monster_attack(",
		"func _play_unit_attack_fx(",
	]:
		var body := _function_body(source, signature)
		check(body != "", "%s 必须存在（否则这条守卫是假绿）" % signature)
		check(not body.contains(".new("), "%s 里不许在战斗期 new 节点/网格/材质" % signature)
		check(not body.contains("queue_free("), "%s 里不许 queue_free（高频对象要走池）" % signature)

func test_monster_attack_plays_a_body_reaction() -> void:
	# 狼有骨骼的 Attack 动作；程序化拼的野怪没有骨骼，靠前冲读「这一下打出去了」。
	var wolf := UnitVisual.new()
	wolf.setup("monster", "neutral", "wolf", "双狼", false, "blue")
	wolf.play_attack()
	gt(float(wolf.action_timer), 0.0, "狼有自己的扑咬动作，必须播出来")
	wolf.free()
	var boar := UnitVisual.new()
	boar.setup("monster", "neutral", "boar", "三猪", false, "blue")
	boar.play_attack()
	gt(float(boar._attack_lunge_timer), 0.0, "程序化形态没有骨骼，靠前冲读出手")
	gt(float(boar._attack_lunge_strength), 1.0, "野怪的前冲要比小兵更狠（体型差一圈）")
	boar.free()

func test_a_followup_hit_does_not_shrink_the_monster_lunge() -> void:
	# 同一次出手会先后到达两条事件：monster_attack（野怪力度）与 hit（默认 1.0）。
	# 若后到的 hit 把力度压回基准，扑咬会退化成「原地抖一下」——而且不报错。
	var view := UnitVisual.new()
	view.setup("monster", "neutral", "boar", "三猪", false, "blue")
	view.play_attack()
	var strong := float(view._attack_lunge_strength)
	gt(strong, 1.0, "先到的 monster_attack 抬高了力度")
	view.play_attack_reaction()
	near(float(view._attack_lunge_strength), strong, 0.001, "后到的 hit 不许把力度压回去")
	# 计时走完之后才允许回到基准：下一次真的挨打仍然是小兵力度。
	view.process_visual(0.3)
	view.play_attack_reaction()
	near(float(view._attack_lunge_strength), 1.0, 0.001, "出手结束后的受击要回到基准力度")
	view.free()

func test_arc_count_reaches_the_renderer_as_that_many_slashes() -> void:
	# 配方写「双爪」只证明数据对；狼在画面上真的挥出两片弧才算做完。
	# 这条用真实的池来数：arc_count 被渲染层忽略时它只会静默地挥一片。
	var arena: Node3D = Arena.new()
	arena._effects_root = Node3D.new()
	arena.add_child(arena._effects_root)
	arena._init_vfx_pools()
	arena._process_events([{
		"type": "monster_attack", "source": 501, "team": "neutral", "monster_type": "wolf",
		"x": 0.0, "y": 0.0, "target": 7, "target_type": "hero", "target_x": 1.2, "target_y": 0.0,
	}])
	eq(arena._slash_active.size(), 2, "狼是双爪：一片弧等于「只挥了一下」")
	# 单爪的物种只能出 1 片：否则「双爪」这个轴就不是区分度，而是全员双爪。
	for entry in [arena._slash_active, arena._ring_active, arena._decal_active]:
		for item in entry:
			var node: Variant = item.get("node") if item is Dictionary else item
			if is_instance_valid(node):
				node.visible = false
		entry.clear()
	arena._process_events([{
		"type": "monster_attack", "source": 502, "team": "neutral", "monster_type": "boar",
		"x": 0.0, "y": 0.0, "target": 7, "target_type": "hero", "target_x": 1.2, "target_y": 0.0,
	}])
	eq(arena._slash_active.size(), 1, "野猪是单爪上挑，不能也画两片")
	# 首领走 slam：一片弧 + 一枚贴地冲击环（砸地感来自那枚环，不是多画几片弧）。
	for entry in [arena._slash_active, arena._ring_active, arena._decal_active]:
		for item in entry:
			var node: Variant = item.get("node") if item is Dictionary else item
			if is_instance_valid(node):
				node.visible = false
		entry.clear()
	arena._process_events([{
		"type": "monster_attack", "source": 503, "team": "neutral", "monster_type": "orc",
		"objective": true, "objective_id": "tyrant",
		"x": 0.0, "y": 0.0, "target": 7, "target_type": "hero", "target_x": 1.6, "target_y": 0.0,
	}])
	eq(arena._slash_active.size(), 1, "首领砸地是一片宽弧")
	gt(float(arena._ring_active.size()), 0.0, "砸地必须有贴地冲击环：只挥一片弧读不出「重」")
	eq(arena._decal_active.size(), 1, "首领砸过的地方要留地裂")
	arena.free()

func test_ranged_minions_get_a_muzzle_flash_and_melee_ones_do_not() -> void:
	# 枪口闪光只有远程兵才有。近战兵也闪的话，兵线对拼时每一下都有一圈光，
	# 和「刀光挥出去了」互相抵消，反而看不出谁在砍谁。
	var arena: Node3D = Arena.new()
	arena._effects_root = Node3D.new()
	arena.add_child(arena._effects_root)
	arena._init_vfx_pools()
	arena._process_events([{
		"type": "minion_attack", "source": 601, "team": "blue", "minion_type": "ranged",
		"x": 0.0, "y": 0.0, "target": 7, "target_type": "hero", "target_x": 3.0, "target_y": 0.0,
	}])
	gt(float(arena._tracer_active.size()), 0.0, "远程兵要打弹丸")
	gt(float(arena._ring_active.size()), 0.0, "远程兵出手要有枪口闪光")
	eq(arena._slash_active.size(), 0, "远程兵不该画刀光")
	# 清空上一阶段的借出记录：池节点是复用的，不清会把远程兵的弹丸算到近战兵头上。
	for entry in [arena._ring_active, arena._slash_active, arena._tracer_active]:
		for node in entry:
			if is_instance_valid(node):
				node.visible = false
		entry.clear()
	arena._process_events([{
		"type": "minion_attack", "source": 602, "team": "blue", "minion_type": "melee",
		"x": 0.0, "y": 0.0, "target": 7, "target_type": "hero", "target_x": 1.0, "target_y": 0.0,
	}])
	gt(float(arena._slash_active.size()), 0.0, "近战兵要挥刀光（旧版是一颗飞过去的小球）")
	eq(arena._tracer_active.size(), 0, "近战兵不该再飞小球")
	eq(arena._ring_active.size(), 0, "近战兵没有枪口闪光")
	arena.free()

# ---------------------------------------------------------------------------
# ⑤ 音频：野怪出手不能是哑的
# ---------------------------------------------------------------------------

func test_monster_attacks_have_their_own_sound() -> void:
	var plan := AudioPlan.new()
	var ctx := {"local": 7, "x": 0.0, "y": 0.0, "team": "blue", "hp_ratio": 1.0}
	plan.begin_frame(1.0 / 30.0, ctx)
	eq(_cue_names(plan.cues_for({"type": "monster_attack", "monster_type": "wolf", "x": 1.0, "y": 0.0}, ctx)), ["monster_swipe"], "野怪挥爪要有专属音色")
	plan.reset()
	plan.begin_frame(1.0 / 30.0, ctx)
	eq(
		_cue_names(plan.cues_for({"type": "monster_attack", "monster_type": "orc", "objective": true, "x": 1.0, "y": 0.0}, ctx)),
		["monster_slam"],
		"首领砸地必须是另一个更重的音"
	)
	plan.reset()
	plan.begin_frame(1.0 / 30.0, ctx)
	eq(
		_cue_names(plan.cues_for({"type": "monster_attack", "monster_type": "wolf", "x": 200.0, "y": 0.0}, ctx)),
		[],
		"40 米外的野怪出手不该占声道"
	)
	for name in ["monster_swipe", "monster_slam"]:
		check(AudioPlan.CUES.has(str(name)), "%s 必须进 AudioPlan.CUES 注册表" % str(name))
		check(AudioCues.cue(str(name)) != null, "%s 必须有合成波形（漏了就是「事件来了没声音」）" % str(name))
	check(
		AudioCues.cue("monster_slam").data.size() > AudioCues.cue("monster_swipe").data.size(),
		"首领砸地要比挥爪长（更重的打击感）"
	)
