extends "res://tests/test_base.gd"

# 项 4：硬控（眩晕 / 击飞 / 沉默 / 定身）。
#
# 这一组守的是一张**行动矩阵**，而不是"字段存在"：
#   kind      禁移动  禁施法  禁普攻  附加
#   stun        ✓       ✓      ✓
#   knockup     ✓       ✓      ✓     强制位移
#   silence     ✗       ✓      ✗
#   root        ✓       ✗      ✗     仍可转向
#
# 改造前 sim 里只有 slow/haste/shield/cc_immune 四种状态，**没有任何硬控**，
# 而且 `cc_immune_timer` 只被赋值、从不被读取 —— 也就是"免疫"完全是装饰，
# 玩家开了净化照样被减速粘住。本套件同时钉住这两件事。

const MatchSim = preload("res://sim/match_sim.gd")
const ControlRules = preload("res://sim/control_rules.gd")
const HeroDefs = preload("res://sim/hero_defs.gd")
const NetProtocol = preload("res://net/net_protocol.gd")
const SkillSystemRef = preload("res://sim/skill_system.gd")

func _duel(blue_hero := "blade", red_hero := "tank", bot_ai := false) -> Object:
	return MatchSim.new({
		"mode": "duel",
		"humans": [
			{"id": "p1", "team": "blue", "hero_type": blue_hero},
			{"id": "p2", "team": "red", "hero_type": red_hero},
		],
		"bot_fill": false,
		"bot_ai": bot_ai,
	})

func _hero(sim: Object, player: String) -> Dictionary:
	return sim.get_hero_by_player(player)

func _clear_cc(hero: Dictionary) -> void:
	for kind in ControlRules.KINDS:
		hero[ControlRules.timer_field(kind)] = 0.0
	hero["slow_timer"] = 0.0
	hero["cc_immune_timer"] = 0.0

# ---------------------------------------------------------------- 行动矩阵（4.1）

func test_stun_blocks_move_cast_and_attack() -> void:
	var sim := _duel()
	var hero := _hero(sim, "p1")
	_clear_cc(hero)
	eq(ControlRules.apply(hero, ControlRules.STUN, 1.0), true, "眩晕必须能施加")
	eq(ControlRules.can_move(hero), false, "眩晕禁移动")
	eq(ControlRules.can_cast(hero), false, "眩晕禁施法")
	eq(ControlRules.can_attack(hero), false, "眩晕禁普攻")
	eq(ControlRules.dominant_status(hero), ControlRules.STUN, "状态码应为 stun")

func test_knockup_blocks_everything_and_displaces() -> void:
	var sim := _duel()
	var hero := _hero(sim, "p1")
	_clear_cc(hero)
	hero["pos"] = Vector2(0.0, 0.0)
	var before: Vector2 = hero["pos"]
	eq(ControlRules.apply(hero, ControlRules.KNOCKUP, 0.6, Vector2(-3.0, 0.0)), true, "击飞必须能施加")
	eq(ControlRules.can_move(hero), false, "击飞禁移动")
	eq(ControlRules.can_cast(hero), false, "击飞禁施法")
	eq(ControlRules.can_attack(hero), false, "击飞禁普攻")
	# 强制位移：朝远离施法者的方向，距离约等于 KNOCKUP_DISTANCE。
	var moved := (hero["pos"] as Vector2).distance_to(before)
	gt(moved, 1.0, "击飞必须把目标推开（实测 %.2f）" % moved)
	gt((hero["pos"] as Vector2).x, 0.0, "施法者在左，目标应被推向右侧")

func test_silence_blocks_skills_but_not_move_or_attack() -> void:
	var sim := _duel()
	var hero := _hero(sim, "p1")
	_clear_cc(hero)
	ControlRules.apply(hero, ControlRules.SILENCE, 1.0)
	eq(ControlRules.can_cast(hero), false, "沉默禁技能")
	eq(ControlRules.can_move(hero), true, "沉默不禁移动")
	eq(ControlRules.can_attack(hero), true, "沉默不禁普攻")

func test_root_blocks_move_but_not_cast_or_attack() -> void:
	var sim := _duel()
	var hero := _hero(sim, "p1")
	_clear_cc(hero)
	ControlRules.apply(hero, ControlRules.ROOT, 1.0)
	eq(ControlRules.can_move(hero), false, "定身禁移动")
	eq(ControlRules.can_cast(hero), true, "定身不禁施法")
	eq(ControlRules.can_attack(hero), true, "定身不禁普攻")

# ---------------------------------------------------------------- 免疫（4.1 的真身）

func test_immunity_actually_blocks_every_control_kind() -> void:
	# 这条守的是那个**死字段**：改造前 cc_immune_timer 只被赋值、从不被读取，
	# 免疫形同虚设。这里逐个 kind 验证"免疫时施加必须返回 false 且不写计时"。
	var sim := _duel()
	var hero := _hero(sim, "p1")
	for kind in ControlRules.KINDS:
		_clear_cc(hero)
		hero["cc_immune_timer"] = 2.0
		eq(ControlRules.apply(hero, kind, 1.0), false, "%s 必须被免疫挡下" % kind)
		near(ControlRules.remaining(hero, kind), 0.0, 0.001, "%s 被免疫时不该写入计时" % kind)

func test_immunity_also_blocks_slow() -> void:
	# 软控也要吃免疫：开了净化还被减速粘住，观感上和没开一样。
	var sim := _duel()
	var hero := _hero(sim, "p1")
	_clear_cc(hero)
	hero["cc_immune_timer"] = 2.0
	eq(ControlRules.apply_slow(hero, 2.5), false, "免疫时减速必须被挡下")
	near(float(hero.get("slow_timer", 0.0)), 0.0, 0.001, "免疫时不该写入减速")
	# 对照：没有免疫时必须正常生效，否则上面的断言可能是"永远不生效"造成的假绿。
	_clear_cc(hero)
	eq(ControlRules.apply_slow(hero, 2.5), true, "无免疫时减速必须生效")
	gt(float(hero.get("slow_timer", 0.0)), 2.0, "无免疫时减速时长应写入")

# ---------------------------------------------------------------- 计时（不能永久眩晕）

func test_control_expires_and_does_not_become_permanent() -> void:
	var sim := _duel()
	var hero := _hero(sim, "p1")
	_clear_cc(hero)
	ControlRules.apply(hero, ControlRules.STUN, 0.2)
	eq(ControlRules.can_move(hero), false, "前置条件：先被眩晕")
	var dt := 1.0 / MatchSim.TICK_RATE
	for i in 20:
		sim.tick(dt)
		sim.consume_events()
	near(ControlRules.remaining(hero, ControlRules.STUN), 0.0, 0.05, "眩晕计时必须走完")
	eq(ControlRules.can_move(hero), true, "控制结束后必须恢复行动（不能永久眩晕）")

func test_stronger_control_overrides_weaker_but_does_not_stack_infinitely() -> void:
	var sim := _duel()
	var hero := _hero(sim, "p1")
	_clear_cc(hero)
	ControlRules.apply(hero, ControlRules.STUN, 1.0)
	ControlRules.apply(hero, ControlRules.STUN, 0.3)
	near(ControlRules.remaining(hero, ControlRules.STUN), 1.0, 0.01, "更短的控制不该缩短已有效果")
	ControlRules.apply(hero, ControlRules.STUN, 3.0)
	near(ControlRules.remaining(hero, ControlRules.STUN), 3.0, 0.01, "更长的控制应覆盖旧的")

# ---------------------------------------------------------------- 真 sim 集成

func test_stunned_hero_cannot_move_in_real_sim() -> void:
	var sim := _duel()
	var hero := _hero(sim, "p1")
	_clear_cc(hero)
	var start: Vector2 = hero["pos"]
	ControlRules.apply(hero, ControlRules.STUN, 3.0)
	var dt := 1.0 / MatchSim.TICK_RATE
	for i in 12:
		sim.set_input("p1", {"move": Vector2(1.0, 0.0)})
		sim.tick(dt)
		sim.consume_events()
	lt((hero["pos"] as Vector2).distance_to(start), 0.05, "眩晕期间按移动键不该位移")

func test_unstunned_hero_does_move_in_real_sim() -> void:
	# 对照组：同样是 12 tick 的移动输入，不带控时必须真的走起来。
	# 没有这条，"不能移动"可能只是因为移动输入根本没生效（假绿）。
	var sim := _duel()
	var hero := _hero(sim, "p1")
	_clear_cc(hero)
	var start: Vector2 = hero["pos"]
	var dt := 1.0 / MatchSim.TICK_RATE
	for i in 12:
		sim.set_input("p1", {"move": Vector2(1.0, 0.0)})
		sim.tick(dt)
		sim.consume_events()
	gt((hero["pos"] as Vector2).distance_to(start), 0.2, "无控时必须能移动（对照）")

func test_silenced_hero_cannot_cast_but_still_moves() -> void:
	var sim := _duel("mage", "tank")
	var hero := _hero(sim, "p1")
	_clear_cc(hero)
	hero["skill_q_cd"] = 0.0
	hero["mp"] = 999.0
	var hp_before := float(_hero(sim, "p2").hp)
	ControlRules.apply(hero, ControlRules.SILENCE, 3.0)
	var start: Vector2 = hero["pos"]
	var dt := 1.0 / MatchSim.TICK_RATE
	for i in 12:
		sim.set_input("p1", {"move": Vector2(1.0, 0.0), "aim": _hero(sim, "p2").pos, "skill_q": true})
		sim.tick(dt)
		sim.consume_events()
	near(float(_hero(sim, "p2").hp), hp_before, 0.01, "沉默期间技能不该生效")
	gt((hero["pos"] as Vector2).distance_to(start), 0.2, "沉默不禁移动")

func test_stun_interrupts_a_channel() -> void:
	# 回城是脱离手段。被控还能安然读条回家，硬控在防守端的价值就没了。
	var sim := _duel()
	var hero := _hero(sim, "p1")
	_clear_cc(hero)
	# 必须先把英雄挪出泉水：泉水内是禁止回城的（RecallRules 的前置条件），
	# 出生点就在泉水里，不放出来这条测试会卡在"根本没开始回城"。
	hero["pos"] = Vector2(0.0, 0.0)
	sim.set_input("p1", {"recall": true})
	sim.tick(1.0 / MatchSim.TICK_RATE)
	sim.consume_events()
	eq(bool(hero.get("recalling", false)), true, "前置条件：应已开始回城")
	ControlRules.apply(hero, ControlRules.STUN, 1.0)
	sim.tick(1.0 / MatchSim.TICK_RATE)
	sim.consume_events()
	eq(bool(hero.get("recalling", false)), false, "眩晕必须打断回城引导")

# ---------------------------------------------------------------- bot（4.2）

func test_bots_respect_hard_control() -> void:
	# AI 读不到控就是白控：玩家把控制交出去，bot 照样走位放技能，
	# 那这套硬控只是"给玩家看的动画"。
	var sim := MatchSim.new({
		"mode": "team", "humans": [], "bot_fill": true, "bot_ai": true,
	})
	var bot: Dictionary = {}
	for entity in sim.state.entities:
		if str(entity.get("type", "")) == "hero" and str(entity.get("controller", "")) == "bot":
			bot = entity
			break
	check(not bot.is_empty(), "前置条件：必须有 bot 英雄")
	_clear_cc(bot)
	var bot_id := int(bot["id"])
	var start: Vector2 = bot["pos"]
	var dt := 1.0 / MatchSim.TICK_RATE
	ControlRules.apply(bot, ControlRules.STUN, 5.0)
	var cast_seen := 0
	for i in 20:
		sim.tick(dt)
		for ev in sim.consume_events():
			if str(ev.get("type", "")) == "skill_cast" and int(ev.get("caster_id", -1)) == bot_id:
				cast_seen += 1
	lt((bot["pos"] as Vector2).distance_to(start), 0.05, "被眩晕的 bot 不该移动")
	eq(cast_seen, 0, "被眩晕的 bot 不该施法")

func test_assassin_ultimate_actually_stuns() -> void:
	# 行为测试，不是文本守卫。变异验证里"删掉某个分支的 control 传参"曾被
	# has_live_line 放行（另一个分支还留着同样的字符串），所以必须真放一次技能。
	var sim := _duel("assassin", "tank")
	var me := _hero(sim, "p1")
	var foe := _hero(sim, "p2")
	_clear_cc(me)
	_clear_cc(foe)
	me["skill_r_level"] = 1
	me["skill_r_cd"] = 0.0
	me["mp"] = 999.0
	# 贴身释放：跃击的落点就是 aim，AoE 半径 3.2 内必中。
	foe["pos"] = (me["pos"] as Vector2) + Vector2(2.0, 0.0)
	SkillSystemRef.cast_skill(me, "r", foe["pos"], sim)
	gt(ControlRules.remaining(foe, ControlRules.STUN), 0.0,
		"刺客大招命中后目标必须处于眩晕（实测 %.2f 秒）" % ControlRules.remaining(foe, ControlRules.STUN))
	eq(ControlRules.can_move(foe), false, "被大招眩晕的目标不能移动")

func test_tank_charge_actually_knocks_up() -> void:
	var sim := _duel("tank", "blade")
	var me := _hero(sim, "p1")
	var foe := _hero(sim, "p2")
	_clear_cc(me)
	_clear_cc(foe)
	me["skill_w_cd"] = 0.0
	me["mp"] = 999.0
	var foe_start: Vector2 = (me["pos"] as Vector2) + Vector2(3.0, 0.0)
	foe["pos"] = foe_start
	SkillSystemRef.cast_skill(me, "w", foe["pos"], sim)
	gt(ControlRules.remaining(foe, ControlRules.KNOCKUP), 0.0,
		"坦克冲锋命中后目标必须处于击飞（实测 %.2f 秒）" % ControlRules.remaining(foe, ControlRules.KNOCKUP))
	gt((foe["pos"] as Vector2).distance_to(foe_start), 0.5,
		"击飞必须真的把目标推开（位移 %.2f）" % (foe["pos"] as Vector2).distance_to(foe_start))

func test_cleanse_actually_removes_every_control() -> void:
	# 净化描述写的是"解除所有控制与负面状态"。只清减速的话，
	# 玩家交了净化还被眩晕按在地上 —— 这张牌就是假的。
	var sim := _duel()
	var hero := _hero(sim, "p1")
	_clear_cc(hero)
	for kind in ControlRules.KINDS:
		hero[ControlRules.timer_field(kind)] = 1.0
	hero["slow_timer"] = 1.0
	hero["summoner_spell"] = "cleanse"
	hero["summoner_cd"] = 0.0
	eq(SkillSystemRef.cast_summoner_spell(hero, "cleanse", hero["pos"], sim), true, "净化必须能施放")
	for kind in ControlRules.KINDS:
		near(ControlRules.remaining(hero, kind), 0.0, 0.001, "净化必须清掉 %s" % kind)
	near(float(hero.get("slow_timer", 0.0)), 0.0, 0.001, "净化必须清掉减速")
	gt(float(hero.get("cc_immune_timer", 0.0)), 0.0, "净化必须给一段免控窗口")

func test_controlled_bot_still_uses_cleanse_to_break_out() -> void:
	# 净化只有在被控时才有意义。若 bot 一被控就完全不作为，
	# 它手里那张净化永远不会被打出来 —— 等于没有。
	var sim := MatchSim.new({
		"mode": "team", "humans": [], "bot_fill": true, "bot_ai": true,
	})
	var bot: Dictionary = {}
	for entity in sim.state.entities:
		if str(entity.get("type", "")) == "hero" and str(entity.get("controller", "")) == "bot":
			bot = entity
			break
	check(not bot.is_empty(), "前置条件：必须有 bot 英雄")
	_clear_cc(bot)
	bot["summoner_spell"] = "cleanse"
	bot["summoner_cd"] = 0.0
	ControlRules.apply(bot, ControlRules.STUN, 1.0)
	sim.tick(1.0 / MatchSim.TICK_RATE)
	sim.consume_events()
	gt(float(bot.get("summoner_cd", 0.0)), 0.0, "被控的 bot 必须交出净化解除控制")
	near(ControlRules.remaining(bot, ControlRules.STUN), 0.0, 0.001, "净化后眩晕必须被清掉")

# ---------------------------------------------------------------- 快照与协议（4.3）

func test_control_state_survives_the_wire() -> void:
	var sim := _duel()
	var hero := _hero(sim, "p1")
	_clear_cc(hero)
	ControlRules.apply(hero, ControlRules.STUN, 1.5)
	var snapshot: Dictionary = sim.snapshot()
	var raw_entity: Dictionary = _find_snapshot_entity(snapshot, int(hero["id"]))
	check(not raw_entity.is_empty(), "前置条件：快照里必须有该英雄")
	gt(float(raw_entity.get("stun_timer", 0.0)), 0.0, "快照必须带硬控计时")
	eq(str(raw_entity.get("cc_status", "")), ControlRules.STUN, "快照必须带聚合状态码")
	var wire: Dictionary = NetProtocol.sanitize_snapshot(snapshot)
	eq(bool(wire.get("ok", false)), true, "前置条件：快照必须通过协议校验")
	var wire_entity: Dictionary = _find_snapshot_entity(wire.get("snapshot", {}), int(hero["id"]))
	check(not wire_entity.is_empty(), "客机必须收到该英雄")
	gt(float(wire_entity.get("stun_timer", 0.0)), 0.0, "硬控计时必须过白名单")
	eq(str(wire_entity.get("cc_status", "")), ControlRules.STUN, "状态码必须过白名单")

func test_wire_rejects_a_forged_control_status() -> void:
	# 客机不能把任意字符串塞进 UI 层（比如伪造一个不存在的状态码）。
	var raw := {
		"bounds": 64.0, "mode": "duel", "time": 1.0, "ended": false, "events": [],
		"entities": [{
			"id": 1, "type": "hero", "team": "blue", "x": 0.0, "y": 0.0,
			"radius": 0.55, "hp": 100.0, "max_hp": 100.0, "alive": true,
			"stun_timer": 999.0, "cc_status": "PERMANENT_FREEZE",
		}],
	}
	var wire: Dictionary = NetProtocol.sanitize_snapshot(raw)
	eq(bool(wire.get("ok", false)), true, "前置条件：快照必须通过协议校验")
	var entity: Dictionary = _find_snapshot_entity(wire.get("snapshot", {}), 1)
	check(not entity.is_empty(), "前置条件：实体必须保留")
	eq(str(entity.get("cc_status", "")), "", "非法状态码必须被清成空串")
	near(float(entity.get("stun_timer", 0.0)), 10.0, 0.01, "异常时长必须被钳到上限")

func _find_snapshot_entity(snapshot: Dictionary, entity_id: int) -> Dictionary:
	for e in snapshot.get("entities", []):
		if int(e.get("id", -1)) == entity_id:
			return e
	return {}

# ---------------------------------------------------------------- 英雄与文案（4.4）

func test_at_least_two_heroes_have_hard_control() -> void:
	# 4.4 要求至少 2 个现有英雄获得硬控。
	var with_control: Array = []
	for hero_type in HeroDefs.HEROES:
		var def: Dictionary = HeroDefs.get_hero(str(hero_type))
		for slot in ["q", "w", "e", "r"]:
			var skill: Variant = def.get(slot, null)
			if not (skill is Dictionary):
				continue
			var control: Variant = (skill as Dictionary).get("control", null)
			if control is Dictionary and not (control as Dictionary).is_empty():
				with_control.append("%s.%s" % [hero_type, slot])
	gt(with_control.size(), 1, "至少要有 2 个英雄带硬控，实际 %s" % str(with_control))
	# 两个指定的英雄必须真的有控（刺客大招眩晕 / 坦克冲锋击飞）。
	var assassin_r: Dictionary = HeroDefs.get_hero("assassin")["r"]
	eq(str((assassin_r.get("control", {}) as Dictionary).get("kind", "")), ControlRules.STUN,
		"刺客大招应附带眩晕")
	var tank_w: Dictionary = HeroDefs.get_hero("tank")["w"]
	eq(str((tank_w.get("control", {}) as Dictionary).get("kind", "")), ControlRules.KNOCKUP,
		"坦克冲锋应附带击飞")

func test_skill_text_is_generated_from_the_same_table() -> void:
	# 4.4：文案与数据同源。手写第二份描述迟早与表里的 control 脱节
	# （"描述说眩晕、实际只减速"是玩家立刻能发现的不一致）。
	var assassin_r: Dictionary = HeroDefs.get_hero("assassin")["r"]
	check(HeroDefs.skill_summary(assassin_r).contains("眩晕"),
		"刺客大招文案必须由 control 数据生成出'眩晕'：%s" % HeroDefs.skill_summary(assassin_r))
	var tank_w: Dictionary = HeroDefs.get_hero("tank")["w"]
	check(HeroDefs.skill_summary(tank_w).contains("击飞"),
		"坦克冲锋文案必须由 control 数据生成出'击飞'：%s" % HeroDefs.skill_summary(tank_w))
	# 不带控的技能不该凭空出现控制字样。
	var blade_q: Dictionary = HeroDefs.get_hero("blade")["q"]
	check(not HeroDefs.skill_summary(blade_q).contains("眩晕"), "无控技能文案不该出现控制字样")
	eq(HeroDefs.control_label({}), "", "空 control 不产生文案")

func test_local_player_is_told_when_controlled() -> void:
	# 4.3 的另一面：**本地玩家**也要知道自己被控住了。
	# 手机上没有 CD 数字可看，"按了没反应"最容易被误判成游戏卡死。
	var GameHUDRef = preload("res://scripts/ui/game_hud.gd")
	eq(GameHUDRef.control_status_caption({}), "", "未被控时不该有提示（不占文案位）")
	var caption: String = GameHUDRef.control_status_caption({"stun_timer": 0.8})
	check(caption.contains("眩晕"), "被眩晕的提示必须说明原因：%s" % caption)
	check(caption.contains("0.8"), "提示应带剩余时间：%s" % caption)
	# 沉默与眩晕同时存在时两个都要说出来（玩家需要知道是哪种）。
	var both: String = GameHUDRef.control_status_caption({"stun_timer": 0.5, "silence_timer": 1.2})
	check(both.contains("眩晕") and both.contains("沉默"), "多种控制必须都列出：%s" % both)

func test_hud_actually_calls_the_control_caption() -> void:
	# C16 教训：只测 control_status_caption 这个静态函数是不够的 ——
	# 函数算得再对，只要 role_text 不调用它，玩家就永远看不到被控提示。
	# 这类"函数在、测试绿、生产引用 0"正是仓库反复警告的形态。
	var src := FileAccess.get_file_as_string("res://scripts/ui/game_hud.gd")
	check(has_live_line(src, "control_status_caption(local)"),
		"HUD 必须真的调用 control_status_caption，而不只是定义它")
	# 反向守卫：那句 if 不能被改成恒假（变异 C16 就是这么逃逸的）。
	check(has_live_line(src, 'if cc_text != "":'),
		"被控提示的显示条件必须真的判断非空")

func test_control_status_is_rendered_on_the_unit_visual() -> void:
	# 4.3 的"客机头顶状态表现正确"：数据层通了还不够，没人画就等于没有。
	# 这里查的是**生产代码真的接线**，而不是"字段在快照里"。
	var src := FileAccess.get_file_as_string("res://scripts/game/unit_visual.gd")
	check(has_live_line(src, "CC_RING_SPECS"), "必须有硬控环的规格表")
	check(has_live_line(src, "cc_rings"), "必须持有硬控环实例")
	# 环的显隐必须读**计时字段**：只读 cc_status 的话，同时中两种控时只会亮一个。
	check(has_live_line(src, '_timer" % kind'), "硬控环显隐必须读各控的计时字段")
	# 四种控都要有环，一种都不能少。
	for kind in ControlRules.KINDS:
		check(src.contains('"%s"' % kind), "缺少 %s 的状态环" % kind)

func test_minion_vs_minion_hits_do_not_flood_the_wire() -> void:
	# 项 3.5：小兵互殴的 hit 事件曾占全场 65% 的大头，而玩家不会去数
	# 小兵互相打了多少下 —— 这类事件纯属挤占 32 条/批的网络预算。
	# 现在小兵打小兵不发 hit，但**伤害照常结算**（这一点必须分开验，
	# 否则"省事件"可能变成"不打伤害"）。
	#
	# 采样要点：mid 路全长约 130m，双方小兵速度约 4.4 m/s，各走 65m 需要约 15 秒
	# **纯移动**，加上绕塔/被塔打/停下来互殴，实际首次交战接近 25~30 秒。
	#
	# 这里不跑满 60 秒（会让整个回归套件慢到不可用），而是**把两个小兵直接摆到一起**：
	# 判断"小兵打小兵是否静音 hit"只需要它们真的在互相攻击，不需要复现整条兵线。
	var sim := MatchSim.new({"mode": "duel", "humans": [], "bot_fill": false})
	var dt := 1.0 / MatchSim.TICK_RATE
	var blue := {
		"id": 9001, "type": "minion", "team": "blue", "lane": "mid",
		"pos": Vector2(0.0, 0.0), "radius": 0.5, "hp": 500.0, "max_hp": 500.0, "alive": true,
		"speed": 4.4, "attack_damage": 20.0, "attack_range": 2.5, "attack_interval": 1.0,
		"attack_cd": 0.0, "minion_type": "melee", "path": [Vector2(0.0, 0.0)], "path_index": 0,
		"path_dir": 1,
	}
	var red := blue.duplicate(true)
	red["id"] = 9002
	red["team"] = "red"
	red["pos"] = Vector2(1.2, 0.0)
	sim.state.entities.append(blue)
	sim.state.entities.append(red)
	var minion_to_minion := 0
	var ever_damaged := false
	for i in 120:
		sim.tick(dt)
		for ev in sim.consume_events():
			if str(ev.get("type", "")) != "hit":
				continue
			if str(ev.get("target_type", "")) == "minion" and str(ev.get("source_type", "")) == "minion":
				minion_to_minion += 1
		if float(blue.get("hp", 500.0)) < 499.5 or float(red.get("hp", 500.0)) < 499.5:
			ever_damaged = true
	eq(minion_to_minion, 0, "小兵打小兵不应广播 hit（伤害仍要照常结算）")
	eq(ever_damaged, true, "静音事件不代表静音伤害：小兵必须真的在掉血")

func test_hero_involved_hits_are_never_suppressed() -> void:
	# 反向守卫：过滤只针对"小兵打小兵"。
	# 英雄打小兵、小兵打英雄、打塔、打野怪的 hit 都必须照常广播，
	# 否则玩家看不到自己的伤害数字（那是核心反馈，不是噪声）。
	var src := FileAccess.get_file_as_string("res://sim/match_sim.gd")
	check(has_live_line(src, 'str(target.type) == "minion" and not source.is_empty()'),
		"过滤条件必须严格要求目标是小兵")
	check(has_live_line(src, 'and str(source.get("type", "")) == "minion"'),
		"过滤条件必须严格要求来源是小兵（缺了这一半，英雄打小兵就没数字了）")

func test_control_execution_is_wired_into_the_skill_path() -> void:
	# G3：control 字段有数据、有文案，还要证明**施法路径真的读它**。
	# 否则就是"字段在、文案对、打上去没控"。
	var src := FileAccess.get_file_as_string("res://sim/skill_system.gd")
	check(has_live_line(src, '_apply_control(e, control, hero)'),
		"AOE 结算必须真的调用 _apply_control")
	check(has_live_line(src, 'skill.get("control", {})'),
		"技能分支必须从技能表读 control，而不是写死")
	# 免疫的唯一读取点：证明 cc_immune_timer 不再是死字段。
	var rules := FileAccess.get_file_as_string("res://sim/control_rules.gd")
	check(has_live_line(rules, 'entity.get("cc_immune_timer", 0.0)'),
		"免疫判定必须真的读取 cc_immune_timer")
