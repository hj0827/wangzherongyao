extends "res://tests/test_base.gd"

# 项 1：战斗属性系统（差距文档 §3.1 / 验收表 1.1–1.6）。
# 伤害按 物理/法术/真实 分型，物理过护甲、法术过魔抗、真实免减伤：
#   有效伤害 = raw * K / (K + resist)，K = MatchSim.MATCH_MITIGATION_K（resist=K 减半）。
#
# 两头都要守住：
#  1. 字段存在 == 字段参与计算 —— 每条都把 resist 拉成非零，逼公式真的生效；
#  2. resist=0 时必须与旧"直接减法"逐位相同 —— 否则 survivability/net 里
#     锚死的 near(100*PVE_SCALE) 会被静默改掉（04-combat-chain 的静默失效教训）。
#
# 时序污染必须隔离，否则精确断言全是假失败：
#  - 出生点贴着自己基地（射程 9 米），tick 一次基地就替玩家打了一发 180；
#  - 脱战回血在 _apply_human_inputs 之前跑，会先给目标 +1.1 血再挨打；
#  - 首波兵 1 秒后才刷。
# _duel() 把两名英雄搬到场心并清零受击时刻，一次 tick 内三者都不介入。

const MatchSim = preload("res://sim/match_sim.gd")
const ItemShop = preload("res://sim/item_shop.gd")
const NetProtocol = preload("res://net/net_protocol.gd")
const SkillSystem = preload("res://sim/skill_system.gd")
const GameTheme = preload("res://scripts/ui/game_theme.gd")
const ShopPanel = preload("res://scripts/ui/shop_panel.gd")
const TICK := 1.0 / 30.0

func _K() -> float:
	return float(MatchSim.MATCH_MITIGATION_K)

func _match(humans: Array) -> Object:
	return MatchSim.new({"mode": "duel", "humans": humans})

func _human(id: String, team: String, hero_type := "blade") -> Dictionary:
	return {"id": id, "name": id, "team": team, "hero_type": hero_type}

func _hero(sim: Object, id: String) -> Dictionary:
	return sim.get_hero_by_player(id)

# 场心对峙：离两座基地 65 米（基地射程 9），离最近外塔 18 米（塔射程 8）。
func _duel(attacker_type: String, victim_type: String) -> Dictionary:
	var sim := _match([_human("p1", "blue", attacker_type), _human("p2", "red", victim_type)])
	var a: Dictionary = _hero(sim, "p1")
	var b: Dictionary = _hero(sim, "p2")
	a.pos = Vector2.ZERO
	b.pos = Vector2(3.0, 0)
	a.last_damage_time = 0.0
	b.last_damage_time = 0.0
	return {"sim": sim, "a": a, "b": b}

# 项 3.3：技能有前摇（0.15–0.25 秒），伤害在起手后若干 tick 才结算。
# 这些用例关心的是"减伤后的数值"，所以统一越过前摇窗口再读血量。
func _tick_past_windup(sim: Object) -> void:
	for i in 15:
		sim.tick(TICK)

# 不在实体列表里的临时受害者：只用于直调 _damage。
func _victim(team := "red", hp := 1000.0) -> Dictionary:
	return {"id": 999, "type": "hero", "team": team, "alive": true,
		"pos": Vector2(30.0, 30.0), "hp": hp, "max_hp": hp, "radius": 0.5,
		"armor": 0.0, "magic_resist": 0.0}

# ---------------------------------------------------------------- 1.1 + 1.2 分型减伤

func test_physical_damage_is_mitigated_by_armor() -> void:
	var sim := _match([_human("p1", "blue"), _human("p2", "red")])
	var victim := _victim()
	victim.armor = _K()
	var before := float(victim.hp)
	sim._damage(victim, 200.0, _hero(sim, "p1"), "physical")
	eq(before - float(victim.hp), 100.0, "护甲=K 时 200 点物理伤害结算成 100")

func test_magic_damage_is_mitigated_by_magic_resist_only() -> void:
	var sim := _match([_human("p1", "blue"), _human("p2", "red")])
	var victim := _victim()
	victim.armor = _K()          # 护甲对法术无效
	victim.magic_resist = _K()   # 魔抗减半
	var before := float(victim.hp)
	sim._damage(victim, 200.0, _hero(sim, "p1"), "magic")
	eq(before - float(victim.hp), 100.0, "魔抗=K 时 200 点法术伤害结算成 100，护甲不参与")

func test_true_damage_ignores_both_resistances() -> void:
	var sim := _match([_human("p1", "blue"), _human("p2", "red")])
	var victim := _victim()
	victim.armor = _K() * 10.0
	victim.magic_resist = _K() * 10.0
	var before := float(victim.hp)
	sim._damage(victim, 200.0, _hero(sim, "p1"), "true")
	eq(before - float(victim.hp), 200.0, "真实伤害不吃任何减伤")

func test_zero_resistance_reproduces_the_legacy_subtraction() -> void:
	# 回归护栏：resist=0 → 乘子恒等 1.0 → 与旧减法逐位相同。
	var sim := _match([_human("p1", "blue"), _human("p2", "red")])
	var victim := _victim()
	var before := float(victim.hp)
	sim._damage(victim, 137.0, _hero(sim, "p1"), "physical")
	eq(before - float(victim.hp), 137.0, "resist=0 时物理伤害原样")

func test_armor_stacks_on_top_of_the_pve_scale() -> void:
	# 小兵对英雄：先 PVE 缩放、再护甲减伤，两段相乘都要在。
	var sim := _match([_human("p1", "blue"), _human("p2", "red")])
	var minion := {"id": 98, "type": "minion", "team": "red", "pos": Vector2(30, 30)}
	var victim := _victim()
	victim.armor = _K()
	var before := float(victim.hp)
	sim._damage(victim, 100.0, minion, "physical")
	near(before - float(victim.hp), 100.0 * float(MatchSim.PVE_HERO_DAMAGE_SCALE) * 0.5, 0.01,
		"小兵伤害 = 原值 * PVE缩放 * 护甲乘子")

func test_non_hero_units_take_unmitigated_damage() -> void:
	# 小兵/塔/野怪没有抗性字段：兵线互殴数值必须原样（否则整条推塔节奏被连带动）。
	var sim := _match([_human("p1", "blue"), _human("p2", "red")])
	var minion := {"id": 97, "type": "minion", "team": "red", "alive": true,
		"pos": Vector2(30, 30), "hp": 300.0, "max_hp": 300.0, "radius": 0.4}
	var before := float(minion.hp)
	sim._damage(minion, 100.0, _hero(sim, "p1"), "magic")
	eq(before - float(minion.hp), 100.0, "小兵没有魔抗概念：法术伤害原样扣")

# ---------------------------------------------------------------- 1.2 技能分型接通实战路径

func test_mage_skill_damage_is_reduced_by_magic_resist() -> void:
	# 同一个法师同一发 Q，打在魔抗 K 的坦克上必须恰好减半 → 证明分型链路接通。
	var ctx := _duel("mage", "tank")
	var sim: Object = ctx.sim
	var mage: Dictionary = ctx.a
	var tank: Dictionary = ctx.b
	tank.magic_resist = _K()
	var hp0 := float(tank.hp)
	sim.set_input("p1", {"seq": 1, "aim": tank.pos, "skill_q": true})
	_tick_past_windup(sim)
	var mitigated := hp0 - float(tank.hp)
	check(mitigated > 0.0, "q still hits with resist")

	var ctx2 := _duel("mage", "tank")
	var sim2: Object = ctx2.sim
	var tank2: Dictionary = ctx2.b
	var hp1 := float(tank2.hp)
	sim2.set_input("p1", {"seq": 1, "aim": tank2.pos, "skill_q": true})
	_tick_past_windup(sim2)
	var raw := hp1 - float(tank2.hp)
	near(mitigated, raw * 0.5, 0.01, "魔抗=K 使法师 Q 恰好减半")

func test_blade_skill_damage_is_reduced_by_armor_not_mr() -> void:
	var ctx := _duel("blade", "tank")
	var sim: Object = ctx.sim
	var tank: Dictionary = ctx.b
	tank.magic_resist = _K() * 4.0   # 堆魔抗对物理毫无意义
	var hp0 := float(tank.hp)
	sim.set_input("p1", {"seq": 1, "aim": tank.pos, "skill_q": true})
	_tick_past_windup(sim)
	gt(hp0 - float(tank.hp), 100.0, "苍刃 Q 是物理伤害：目标堆再多魔抗也要掉够血")

# ---------------------------------------------------------------- 1.3 CDR

func test_cooldown_reduction_shortens_skill_cooldown() -> void:
	var ctx := _duel("blade", "tank")
	var blue: Dictionary = ctx.a
	var red: Dictionary = ctx.b
	blue.cooldown_reduction = 0.4
	ctx.sim._cast_q(blue, red.pos)
	var base_cd := float(MatchSim.HeroDefs.get_hero("blade").q.cooldown)
	near(float(blue.skill_q_cd), base_cd * 0.6, 0.001, "CDR 40% → CD 变 60%")

func test_cooldown_reduction_is_capped_at_40_percent() -> void:
	var ctx := _duel("blade", "tank")
	var blue: Dictionary = ctx.a
	var red: Dictionary = ctx.b
	blue.cooldown_reduction = 0.9   # 装备凑爆了也只用 0.4
	ctx.sim._cast_q(blue, red.pos)
	var base_cd := float(MatchSim.HeroDefs.get_hero("blade").q.cooldown)
	near(float(blue.skill_q_cd), base_cd * (1.0 - MatchSim.CDR_CAP), 0.001, "CDR 封顶后按封顶算")
	eq(MatchSim.CDR_CAP, 0.4, "上限 40%（对标王者口径）")

func test_blue_buff_and_cdr_multiply() -> void:
	# 蓝 buff（×0.8）与 CDR 0.4 叠乘：最终 CD = base * 0.8 * 0.6。
	var ctx := _duel("blade", "tank")
	var blue: Dictionary = ctx.a
	var red: Dictionary = ctx.b
	blue.cooldown_reduction = 0.4
	blue.buff_blue_timer = 30.0
	ctx.sim._cast_q(blue, red.pos)
	var base_cd := float(MatchSim.HeroDefs.get_hero("blade").q.cooldown)
	near(float(blue.skill_q_cd), base_cd * 0.8 * 0.6, 0.001, "蓝buff×0.8 与 CDR×0.6 叠乘")

func test_cast_skill_path_also_applies_cdr() -> void:
	# W 走 skill_system.cast_skill，必须与 _cast_q 用同一个系数真身。
	# （项 2 之后 R 出生未学习，改用同样走这条路径、且出生即 1 级的 W。）
	var ctx := _duel("blade", "tank")
	var blue: Dictionary = ctx.a
	var red: Dictionary = ctx.b
	blue.cooldown_reduction = 0.4
	SkillSystem.cast_skill(blue, "w", red.pos, ctx.sim)
	var base_cd := float(MatchSim.HeroDefs.get_hero("blade").w.cooldown)
	near(float(blue.skill_w_cd), base_cd * 0.6, 0.001, "skill_system 路径也吃 CDR")

# ---------------------------------------------------------------- 1.4 攻速可成长

func test_attack_speed_shortens_effective_attack_interval() -> void:
	var base := float(MatchSim.HeroDefs.get_hero("archer").attack_interval)
	var unit := {"attack_interval": base, "attack_speed": 0.5}
	near(MatchSim.hero_attack_interval(unit), base / 1.5, 0.0001, "攻速+50% → 间隔缩到 2/3")

func test_hero_attack_interval_is_identity_without_bonus() -> void:
	# 恒等护栏：没有攻速字段/为 0 的单位（小兵、塔、旧实体）间隔必须原样。
	eq(MatchSim.hero_attack_interval({"attack_interval": 1.1}), 1.1, "缺字段=恒等")
	eq(MatchSim.hero_attack_interval({"attack_interval": 0.88, "attack_speed": 0.0}), 0.88, "0 加成=恒等")

func test_try_attack_uses_the_attack_speed_gated_interval() -> void:
	# 普攻后的攻击冷却必须由「有效间隔」决定，而不是裸 attack_interval。
	var ctx := _duel("archer", "tank")
	var archer: Dictionary = ctx.a
	var tank: Dictionary = ctx.b
	tank.pos = archer.pos + Vector2(1.5, 0)
	archer.attack_cd = 0.0
	archer.attack_speed = 1.0   # 攻速翻倍
	ctx.sim._try_attack(archer)
	var base := float(MatchSim.HeroDefs.get_hero("archer").attack_interval)
	check(float(archer.attack_cd) < base - 0.01, "攻速加成必须真的缩短普攻间隔（旧写法在这红）")
	# 顺序钉死：attack_cd 在被动结算**之前**取值，所以这一刀只算装备攻速；
	# 被动给下一刀提速。写反了这里会红。
	near(float(archer.attack_cd), base / 2.0, 0.0001, "本刀间隔 = 基础/2（装备攻速）")
	check(MatchSim.hero_attack_interval(archer) < base / 2.0 - 0.01, "被动攻速对下一刀继续提速")

# ---------------------------------------------------------------- 1.4b 翎羽被动：文案与实现同源

func test_archer_passive_actually_grants_attack_speed() -> void:
	# 差距文档 §5.1：被动写「提升移速与攻速」但实现只有移速。本用例钉死实现侧。
	var ctx := _duel("archer", "tank")
	var sim: Object = ctx.sim
	var archer: Dictionary = ctx.a
	var tank: Dictionary = ctx.b
	var base := float(archer.attack_interval)
	SkillSystem.on_hero_attack_hit(archer, tank, sim)
	check(MatchSim.hero_attack_interval(archer) < base, "普攻命中英雄后有效攻击间隔必须真的变短")
	gt(float(archer.get("passive_as_bonus", 0.0)), 0.0, "被动写进攻速加成字段")
	# 窗口过期后必须清零，否则被动变成永久增益（计时器在、没人收账的那类坑）。
	archer.passive_as_timer = 0.0001
	sim._update_hero_timers(TICK * 2)
	eq(float(archer.passive_as_bonus), 0.0, "窗口结束后加成清零")

# ---------------------------------------------------------------- 1.5 暴伤字段化

func test_crit_damage_is_a_field_not_the_hardcoded_150_percent() -> void:
	var ctx := _duel("blade", "tank")
	var sim: Object = ctx.sim
	var blue: Dictionary = ctx.a
	var red := _victim("red", 1000.0)
	red.pos = blue.pos + Vector2(1.5, 0)
	sim.state.entities.append(red)
	blue.crit_rate = 1.0        # 必暴
	blue.crit_damage = 3.0      # 300% 暴伤
	blue.attack_cd = 0.0
	var hp0 := float(red.hp)
	sim._try_attack(blue)
	# 第一击只到 1 层被动（3 层才追加），所以是纯净的 普攻 * 暴伤倍率。
	eq(hp0 - float(red.hp), float(blue.attack_damage) * 3.0, "暴击倍率读 crit_damage（写死 1.5 必红）")

func test_crit_damage_defaults_to_150_percent() -> void:
	var ctx := _duel("blade", "tank")
	eq(float(ctx.a.crit_damage), 1.5, "出生默认暴伤 150%，与旧常量口径连续")

# ---------------------------------------------------------------- 1.6 回复属性化

func test_hp_regen_stat_adds_to_out_of_combat_regen() -> void:
	var ctx := _duel("blade", "tank")
	var blue: Dictionary = ctx.a
	# _duel 已把英雄搬出场心，泉水（半径10）与基地火力（射程9）都够不到。
	blue.hp = 500.0
	blue.last_damage_time = -999.0
	blue.hp_regen = 50.0
	var hp0 := float(blue.hp)
	ctx.sim._update_hero_timers(TICK)
	var expected := hp0 + (float(blue.max_hp) * float(MatchSim.FIELD_HP_REGEN) + 50.0) * TICK
	near(float(blue.hp), expected, 0.001, "脱战回血 = 基础% + hp_regen 属性")

func test_mana_regen_stat_adds_to_base_ticking() -> void:
	var ctx := _duel("blade", "tank")
	var blue: Dictionary = ctx.a
	blue.mp = 100.0
	blue.mana_regen = 24.0
	var mp0 := float(blue.mp)
	ctx.sim._update_hero_timers(TICK)
	near(float(blue.mp), mp0 + (float(MatchSim.FIELD_MP_REGEN) + 24.0) * TICK, 0.001,
		"回蓝 = 基础 + mana_regen 属性")

# ---------------------------------------------------------------- 装备 → 属性聚合

func test_defense_items_grant_real_resistance() -> void:
	# 「布甲=护甲15」不是愿望，是这条断言。防御装从此改变减伤，而不是只堆血。
	var ctx := _duel("blade", "tank")
	var hero: Dictionary = ctx.a
	hero.gold = 5000
	check(ItemShop.buy_item(hero, "cloth_armor"), "buy cloth armor")
	near(float(hero.armor), 15.0, 0.001, "布甲给 15 护甲")
	check(ItemShop.buy_item(hero, "resistance_boots"), "buy resistance boots")
	near(float(hero.magic_resist), 25.0, 0.001, "抵抗之靴给 25 魔抗")
	# 卖装后必须回落，否则"买了退不掉"会变成隐性永久增益。
	check(ItemShop.sell_item(hero, 0), "sell cloth armor")
	eq(float(hero.armor), 0.0, "卖甲后护甲清零")

func test_hit_event_amount_is_the_mitigated_number() -> void:
	# 链路 5 的数据侧：飘字读 hit 事件的 amount（arena._handle_hit_event）。
	# 如果事件发的是减伤前的数，玩家会看到「飘了 200、血只掉 100」——
	# 护甲在数值上生效、在视觉上仍然是坏的。
	var sim := _match([_human("p1", "blue"), _human("p2", "red")])
	var victim := _victim()
	victim.armor = _K()
	sim._damage(victim, 200.0, _hero(sim, "p1"), "physical")
	var hit: Dictionary = {}
	for event in sim.consume_events():
		if str(event.get("type", "")) == "hit" and int(event.get("target", -1)) == int(victim.id):
			hit = event
			break
	check(not hit.is_empty(), "hit event emitted")
	if not hit.is_empty():
		eq(float(hit.get("amount", -1.0)), 100.0, "hit 事件带的是减伤后的数")

func _board(touch: bool) -> Object:
	# setup() 会 _build()，进而实测 _stats_avail（桌面 561 / 触屏 531）。
	# 不走 setup 的用例拿到的是兜底 520，那测出来的不是真实面板的行为。
	var Scoreboard = preload("res://scripts/ui/scoreboard.gd")
	var sb = Scoreboard.new()
	sb.setup(touch)
	return sb

# 真实后期坦克：数值取自 pacing_report 的 15 分钟量级（不是把所有位数拉满）。
const LATE_TANK := {
	"cs": 60, "attack_damage": 180.0, "max_hp": 4600.0, "speed": 6.6,
	"armor": 55.0, "magic_resist": 25.0,
	"damage_dealt": 12000.0, "damage_taken": 20000.0, "tower_kills": 2,
}

func test_stats_avail_is_measured_not_fallback() -> void:
	# _stats_avail 只有在"节点层级取不到"时才回落到兜底值。若将来布局改名/换层
	# 让 _measure_stats_avail 静默走 fallback 分支，桌面会把预算从 561 收到 520、
	# 白白少显示字段，而且不报错 —— 典型的「测量断了但测试还绿」。
	# 判据用结构不变量而不是"等于某个数"：兜底路径对两种模式返回**同一个常数**，
	# 真实测量则必须 桌面 > 触屏（桌面面板 1240 宽、触屏 1180）。
	var measured := {}
	for touch in [false, true]:
		var sb := _board(touch)
		measured[touch] = float(sb._stats_avail)
		sb.free()
	var desk := float(measured[false])
	var touch_avail := float(measured[true])
	check(desk > 0.0 and touch_avail > 0.0, "可用宽必须是正数（desk=%.1f touch=%.1f）" % [desk, touch_avail])
	check(desk > touch_avail,
		"桌面可用宽必须大于触屏（实测 desk=%.1f touch=%.1f；相等说明量到的是兜底常数，不是真实层级）" % [desk, touch_avail])

func test_scoreboard_shows_defense_on_the_real_panel() -> void:
	# 面板消费：属性进了快照但没人显示 = 玩家永远看不到（04-combat-chain 链路 6）。
	for touch in [false, true]:
		var sb := _board(touch)
		var text: String = sb._stats_text(LATE_TANK)
		sb.free()
		check(text.contains("护甲 55"), "%s 面板显示护甲：%s" % [str(touch), text])
		check(text.contains("魔抗 25"), "%s 面板显示魔抗：%s" % [str(touch), text])

func test_scoreboard_hides_zero_resistances() -> void:
	# 零值不占宽度（与"法师不看『法强 0』"同一套语言）。
	var sb := _board(false)
	var text: String = sb._stats_text({"cs": 1, "attack_damage": 70.0, "max_hp": 1000.0,
		"speed": 6.0, "armor": 0.0, "magic_resist": 0.0, "cooldown_reduction": 0.0})
	sb.free()
	check(not text.contains("护甲"), "0 护甲不进面板：%s" % text)
	check(not text.contains("魔抗"), "0 魔抗不进面板：%s" % text)

func test_stats_line_never_clips_the_decision_fields() -> void:
	# 这一行开着 clip_text=true：超宽不是换行，而是从右侧**静默裁掉**，
	# 而字符串断言查不出来（内容还在，只是看不见）——本仓库最典型的「测试绿、界面坏」。
	# 实测可用宽只有 561/531，而全字段拉满要 678：所以低优先级字段必须能整段放弃，
	# 换 输出/承伤/推塔 这三个决策字段永不消失。
	for touch in [false, true]:
		var sb := _board(touch)
		var absurd := {"cs": 999, "attack_damage": 999.0, "ability_power": 999.0,
			"max_hp": 99999.0, "speed": 99.0, "crit_rate": 0.99,
			"armor": 999.0, "magic_resist": 999.0, "cooldown_reduction": 0.99,
			"damage_dealt": 999000.0, "damage_taken": 999000.0, "tower_kills": 99}
		var text: String = sb._stats_text(absurd)
		var need := GameTheme.FONT_REGULAR.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
		check(need <= float(sb._stats_avail) + 0.5,
			"%s 最坏属性行 %.0fpx 超过可用 %.0fpx，尾部会被裁" % [str(touch), need, float(sb._stats_avail)])
		check(text.contains("输出"), "%s 决策字段 输出 必须在：%s" % [str(touch), text])
		check(text.contains("承伤"), "%s 决策字段 承伤 必须在：%s" % [str(touch), text])
		check(text.contains("推塔"), "%s 决策字段 推塔 必须在：%s" % [str(touch), text])
		sb.free()

func test_shop_describes_defensive_stats() -> void:
	# 商店必须说清"布甲是减伤"，不然玩家看到的仍是"+220 生命"那一套旧描述。
	var panel := ShopPanel.new()
	var armor_text: String = panel._describe(ItemShop.get_item("cloth_armor"))
	var boots_text: String = panel._describe(ItemShop.get_item("resistance_boots"))
	panel.free()
	check(armor_text.contains("+15 护甲"), "商店描述护甲：%s" % armor_text)
	check(boots_text.contains("+25 魔抗"), "商店描述魔抗：%s" % boots_text)

func test_new_stats_reach_the_snapshot() -> void:
	# 链路 3：_snapshot_entity 漏一个键 = HUD/详情永远读到默认值且不报错。
	var ctx := _duel("blade", "tank")
	var hero: Dictionary = ctx.a
	hero.armor = 40.0
	hero.magic_resist = 25.0
	hero.cooldown_reduction = 0.2
	hero.attack_speed = 0.15
	hero.crit_damage = 1.8
	hero.hp_regen = 12.0
	hero.mana_regen = 8.0
	var shot: Dictionary = ctx.sim._snapshot_entity(hero)
	eq(float(shot.get("armor", -1.0)), 40.0, "snapshot.armor")
	eq(float(shot.get("magic_resist", -1.0)), 25.0, "snapshot.magic_resist")
	eq(float(shot.get("cooldown_reduction", -1.0)), 0.2, "snapshot.cooldown_reduction")
	eq(float(shot.get("attack_speed", -1.0)), 0.15, "snapshot.attack_speed")
	eq(float(shot.get("crit_damage", -1.0)), 1.8, "snapshot.crit_damage")
	eq(float(shot.get("hp_regen", -1.0)), 12.0, "snapshot.hp_regen")
	eq(float(shot.get("mana_regen", -1.0)), 8.0, "snapshot.mana_regen")

func _wire_hero(overrides: Dictionary) -> Dictionary:
	var hero := {
		"id": 3, "type": "hero", "team": "blue", "alive": true,
		"x": 1.0, "y": 2.0, "hp": 100.0, "max_hp": 200.0, "radius": 0.5,
		"owner_id": "p1", "name": "n", "hero_type": "blade", "controller": "human",
		"lane": "mid", "level": 1, "xp": 0.0, "mp": 10.0, "max_mp": 20.0,
		"kills": 0, "deaths": 0, "speed": 6.0, "shield": 0.0,
	}
	for key in overrides:
		hero[key] = overrides[key]
	return hero

func test_new_stats_survive_the_net_whitelist() -> void:
	# 链路 4：漏白名单 = 单机一切正常、联机静默丢（00-hard-rules 第 6 条原样复刻）。
	var clean: Dictionary = NetProtocol._sanitize_entity(_wire_hero({
		"armor": 40.0, "magic_resist": 25.0, "cooldown_reduction": 0.2,
		"attack_speed": 0.15, "crit_damage": 1.8, "hp_regen": 12.0, "mana_regen": 8.0,
	}), 58.0)
	eq(float(clean.get("armor", -1.0)), 40.0, "wire.armor")
	eq(float(clean.get("magic_resist", -1.0)), 25.0, "wire.magic_resist")
	eq(float(clean.get("cooldown_reduction", -1.0)), 0.2, "wire.cooldown_reduction")
	eq(float(clean.get("attack_speed", -1.0)), 0.15, "wire.attack_speed")
	eq(float(clean.get("crit_damage", -1.0)), 1.8, "wire.crit_damage")
	eq(float(clean.get("hp_regen", -1.0)), 12.0, "wire.hp_regen")
	eq(float(clean.get("mana_regen", -1.0)), 8.0, "wire.mana_regen")

func test_whitelist_clamps_hostile_resistance_values() -> void:
	var clean: Dictionary = NetProtocol._sanitize_entity(_wire_hero({
		"armor": -50.0, "magic_resist": 999999.0, "cooldown_reduction": 5.0,
		"attack_speed": -1.0, "crit_damage": -3.0, "hp_regen": -9.0, "mana_regen": 1e9,
	}), 58.0)
	eq(float(clean.get("armor", -999.0)), 0.0, "负护甲钳到 0")
	eq(float(clean.get("magic_resist", -999.0)), NetProtocol.MAX_RESISTANCE, "魔抗封顶")
	eq(float(clean.get("cooldown_reduction", -999.0)), NetProtocol.MAX_CDR, "CDR 钳到上限口径")
	eq(float(clean.get("attack_speed", -999.0)), 0.0, "负攻速钳到 0")
	eq(float(clean.get("crit_damage", -999.0)), 0.0, "负暴伤钳到 0")
	eq(float(clean.get("hp_regen", -999.0)), 0.0, "负回血钳到 0")
	eq(float(clean.get("mana_regen", -999.0)), NetProtocol.MAX_REGEN, "回蓝封顶")

func test_board_exposes_defensive_stats() -> void:
	# 计分板/详情面板要能拿到抗性：进 board 行（Vision 之外的公开战报）。
	var ctx := _duel("blade", "tank")
	var hero: Dictionary = ctx.a
	hero.armor = 40.0
	hero.magic_resist = 25.0
	var board: Dictionary = ctx.sim._snapshot_board()
	var row: Dictionary = (board.blue as Array)[0]
	eq(float(row.get("armor", -1.0)), 40.0, "board.armor")
	eq(float(row.get("magic_resist", -1.0)), 25.0, "board.magic_resist")

func test_board_stats_survive_the_wire() -> void:
	# 链路 4 的另一条路径：board 走的是 sanitize_snapshot 里**单独一份**逐字段清单，
	# 加了 _snapshot_board 却忘加这里 = 客机计分板读 0 且不报错。
	# （历史上 8 个模块栽的就是这种"两条路径只接了一条"。）
	var ctx := _duel("blade", "tank")
	var hero: Dictionary = ctx.a
	hero.armor = 40.0
	hero.magic_resist = 25.0
	hero.cooldown_reduction = 0.2
	hero.attack_speed = 0.15
	hero.crit_damage = 1.8
	hero.crit_rate = 3.0
	var shot: Dictionary = ctx.sim.snapshot()
	var wire: Dictionary = NetProtocol.sanitize_snapshot(shot)
	check(bool(wire.get("ok", false)), "snapshot must pass the sanitizer")
	var board: Dictionary = wire.snapshot.get("board", {})
	var rows: Array = board.get("blue", [])
	check(rows.size() > 0, "board keeps the blue row")
	if rows.size() > 0:
		var row: Dictionary = rows[0]
		eq(float(row.get("armor", -1.0)), 40.0, "wire.board.armor")
		eq(float(row.get("magic_resist", -1.0)), 25.0, "wire.board.magic_resist")
		eq(float(row.get("cooldown_reduction", -1.0)), 0.2, "wire.board.cooldown_reduction")
		eq(float(row.get("attack_speed", -1.0)), 0.15, "wire.board.attack_speed")
		eq(float(row.get("crit_damage", -1.0)), 1.8, "wire.board.crit_damage")
		eq(float(row.get("crit_rate", -1.0)), 1.0, "wire.board.crit_rate matches entity clamp")

# ---------------------------------------------------------------- 数据完整性守卫

func test_recalculate_stats_is_idempotent_for_new_attributes() -> void:
	# 买/卖装备每次都重跑 recalculate_stats。若"基础值"取自被写回过的字段，
	# 加成会在每次重算时再叠一遍（买一件攻速装、再买一件别的，攻速就翻倍）。
	# 所以这里反复重算，要求七个属性全部稳定不动。
	var ctx := _duel("blade", "tank")
	var hero: Dictionary = ctx.a
	hero.gold = 9000
	ItemShop.buy_item(hero, "cloth_armor")
	ItemShop.buy_item(hero, "resistance_boots")
	ItemShop.recalculate_stats(hero)
	var snap := {}
	for key in ["armor", "magic_resist", "hp_regen", "mana_regen", "cooldown_reduction", "attack_speed", "crit_damage"]:
		snap[key] = float(hero.get(key, 0.0))
	for i in 5:
		ItemShop.recalculate_stats(hero)
	for key in snap:
		eq(float(hero.get(key, 0.0)), float(snap[key]), "重算 5 次后 %s 必须不变（基础值取自 base_*）" % key)

func test_every_damage_skill_declares_its_damage_type() -> void:
	# 分型减伤最怕的静默失效：新增/改动技能时漏写 damage_type，
	# 代码会默认按 physical 结算 —— 法师的技能于是走护甲、不吃魔抗，
	# 数值不报错、测试不红，只是打出来的数和玩家预期完全不同。
	# 所以这里要求每个**会造成伤害**的技能都必须显式声明合法分型。
	var legal := {"physical": true, "magic": true, "true": true}
	var missing: Array[String] = []
	var illegal: Array[String] = []
	for hero_type in MatchSim.HeroDefs.HEROES:
		var def: Dictionary = MatchSim.HeroDefs.HEROES[hero_type]
		for slot in ["q", "w", "e", "r"]:
			var skill: Variant = def.get(slot, null)
			if not (skill is Dictionary):
				continue
			if float((skill as Dictionary).get("damage", 0.0)) <= 0.0:
				continue   # 纯位移/护盾/加速技能没有伤害，不需要分型
			var dtype := str((skill as Dictionary).get("damage_type", ""))
			if dtype == "":
				missing.append("%s.%s(%s)" % [hero_type, slot, str((skill as Dictionary).get("name", ""))])
			elif not legal.has(dtype):
				illegal.append("%s.%s=%s" % [hero_type, slot, dtype])
	check(missing.is_empty(), "伤害技能漏标 damage_type（会静默按物理结算）：%s" % ", ".join(missing))
	check(illegal.is_empty(), "damage_type 取值非法：%s" % ", ".join(illegal))

func test_mage_skills_are_magic_type() -> void:
	# 当前职业契约：法师星璃的每个伤害技能都必须是 magic。
	# 这条不是审美——它保证"堆魔抗能克制法师"这件事在数据层就成立。
	var def: Dictionary = MatchSim.HeroDefs.get_hero("mage")
	for slot in ["q", "w", "e", "r"]:
		var skill: Dictionary = def[slot]
		if float(skill.get("damage", 0.0)) > 0.0:
			eq(str(skill.get("damage_type", "")), "magic", "法师 %s 必须是 magic 伤害" % slot)
