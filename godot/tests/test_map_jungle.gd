extends "res://tests/test_base.gd"

# 野区契约：四座镜像营地、可争夺的中立野怪、击杀后的红/蓝增益与刷新时间。
# 野区让打野位有经验与增益来源，也让地图不再只有三条兵线。

const Jungle = preload("res://sim/map/jungle.gd")
const MapLayout = preload("res://sim/map/map_layout.gd")
const MapData = preload("res://sim/map_data.gd")
const MatchSim = preload("res://sim/match_sim.gd")

func _sim() -> Object:
	return MatchSim.new({
		"mode": "duel",
		"humans": [{"id": "p1", "name": "T", "team": "blue", "hero_type": "blade"}],
		"bot_fill": false,
		"bot_ai": false,
	})

func _first_monster(sim: Object) -> Dictionary:
	for entity in sim.state.entities:
		if str(entity.type) == "monster" and not bool(entity.get("objective", false)):
			return entity
	return {}

func _hero() -> Dictionary:
	return {
		"type": "hero",
		"team": "blue",
		"alive": true,
		"buff_red_timer": 0.0,
		"buff_blue_timer": 0.0,
	}

func test_four_mirrored_camps_with_two_buff_types() -> void:
	eq(Jungle.CAMPS.size(), 4, "野区有四座营地")
	var buffs := {}
	for camp in Jungle.CAMPS:
		buffs[str(camp.buff)] = true
		check(MapLayout.bush_at(camp.pos).is_empty(), "营地本身不是草丛")
	eq(buffs.size(), 2, "红蓝两种增益都有")
	eq(Jungle.RESPAWN_TIME, 70.0, "野怪 70 秒刷新")

func test_every_half_gets_one_red_and_one_blue_camp() -> void:
	# 上一版的四个营地是按 y=-x 镜像配对的，而 mirror 不换半场（a = x-y 不变），
	# 结果是「蓝方半场两个蓝 buff、红方半场两个红 buff」——
	# 任何一队在自己野区里都见不到另一种增益，只能入侵才拿得到。
	var per_half := {"blue": {}, "red": {}}
	for camp in Jungle.CAMPS:
		var side := "blue" if camp.pos.x - camp.pos.y > 0.0 else "red"
		per_half[side][str(camp.buff)] = true
	for side in per_half:
		var buffs: Dictionary = per_half[side]
		check(buffs.has("blue"), "%s 半场必须有蓝 buff 营地" % side)
		check(buffs.has("red"), "%s 半场必须有红 buff 营地" % side)

func test_camps_stand_on_land_not_in_the_river() -> void:
	# 旧数据里两座蓝 buff 营地 |a| = 10 → 离河心只有 7.07 米，
	# 比河道半宽 9 米还小：整只野怪泡在水里，俯视一眼就假。
	for camp in Jungle.CAMPS:
		var offset: float = absf(camp.pos.x - camp.pos.y) * 0.70710678
		var dry: float = offset - MapData.RIVER_HALF_WIDTH - float(camp.radius)
		gt(dry, 0.5, "营地必须整只站在岸上：%s（离水面 %.2f 米）" % [str(camp.id), dry])

func test_camps_do_not_overlap_each_other() -> void:
	for i in Jungle.CAMPS.size():
		for j in range(i + 1, Jungle.CAMPS.size()):
			var first: Dictionary = Jungle.CAMPS[i]
			var second: Dictionary = Jungle.CAMPS[j]
			var need: float = float(first.radius) + float(second.radius) + 6.0
			gt((first.pos as Vector2).distance_to(second.pos), need, "营地之间要留出走位空间：%s × %s" % [str(first.id), str(second.id)])

func test_monster_stats_are_scaled_per_camp() -> void:
	for camp in Jungle.CAMPS:
		var stats: Dictionary = Jungle.monster_stats(camp)
		eq(str(stats.type), "monster", "野怪实体类型")
		eq(str(stats.team), "neutral", "野怪中立")
		gt(float(stats.hp), 500.0, "野怪血量要有争夺价值")
		gt(float(stats.attack_damage), 0.0, "野怪会反击")
		eq(str(stats.camp_id), str(camp.id), "野怪记住所属营地")
		eq(str(stats.buff_type), str(camp.buff), "野怪携带对应增益")

func test_blue_buff_shortens_cooldowns_and_red_buff_adds_damage() -> void:
	var hero := _hero()
	Jungle.apply_buff(hero, "blue")
	gt(float(hero.buff_blue_timer), 0.0, "蓝增益计时开始")
	near(Jungle.cooldown_scale(hero), Jungle.BLUE_COOLDOWN_SCALE, 0.001, "蓝增益缩减技能冷却")
	near(Jungle.damage_scale(hero), 1.0, 0.001, "蓝增益不加伤害")
	hero.buff_blue_timer = 0.0
	Jungle.apply_buff(hero, "red")
	gt(float(hero.buff_red_timer), 0.0, "红增益计时开始")
	near(Jungle.damage_scale(hero), Jungle.RED_DAMAGE_SCALE, 0.001, "红增益提升普攻伤害")
	near(Jungle.cooldown_scale(hero), 1.0, 0.001, "红增益不缩减冷却")

func _hero_entity(sim: Object) -> Dictionary:
	for entity in sim.state.entities:
		if str(entity.get("type", "")) == "hero":
			return entity
	return {}

func test_monster_stays_passive_when_hero_stands_next_to_it() -> void:
	var sim := _sim()
	var monster := _first_monster(sim)
	var hero := _hero_entity(sim)
	check(not monster.is_empty(), "野区里有可打的野怪")
	check(not hero.is_empty(), "模拟里有英雄")
	if monster.is_empty() or hero.is_empty():
		return
	# 站在野怪鼻子底下（已经进了它的普攻距离）：以前这里会立刻掉头扑上来。
	hero.pos = monster.pos + Vector2(1.5, 0.0)
	var start: Vector2 = monster.pos
	var hero_hp := float(hero.hp)
	for i in 30:
		sim.tick(1.0 / 30.0)
	near(monster.pos.distance_to(start), 0.0, 0.01, "没被打的野怪不该挪窝")
	near(float(hero.hp), hero_hp, 0.01, "没被打的野怪不该主动攻击英雄")

func test_monster_retaliates_after_taking_damage() -> void:
	var sim := _sim()
	var monster := _first_monster(sim)
	var hero := _hero_entity(sim)
	check(not monster.is_empty() and not hero.is_empty(), "野怪与英雄都在场")
	if monster.is_empty() or hero.is_empty():
		return
	hero.pos = monster.pos + Vector2(2.0, 0.0)
	var hero_hp := float(hero.hp)
	sim.apply_damage(int(monster.id), 50.0, int(hero.id))
	check(float(monster.hp) < float(monster.max_hp), "野怪确实掉了血")
	for i in 90:
		sim.tick(1.0 / 30.0)
	lt(float(hero.hp), hero_hp, "受到伤害后野怪要反击")

func test_monster_gives_up_when_attacker_leaves_leash() -> void:
	var sim := _sim()
	var monster := _first_monster(sim)
	var hero := _hero_entity(sim)
	if monster.is_empty() or hero.is_empty():
		check(false, "野怪与英雄都在场")
		return
	hero.pos = monster.pos + Vector2(2.0, 0.0)
	sim.apply_damage(int(monster.id), 50.0, int(hero.id))
	# 英雄跑出栓绳范围：野怪必须放弃并回窝，不能一路追到线上。
	hero.pos = monster.pos + Vector2(float(monster.get("leash_range", 11.0)) + 6.0, 0.0)
	for i in 120:
		sim.tick(1.0 / 30.0)
	var home: Vector2 = monster.get("home_pos", monster.pos)
	near(monster.pos.distance_to(home), 0.0, 0.6, "脱战后的野怪回到营地")
	# 追丢就该彻底忘掉：英雄再贴上来时它必须回到「没被打就不动」的状态，
	# 否则会出现「从窝里冲出来主动咬人」的远程索敌。
	hero.pos = monster.pos + Vector2(1.5, 0.0)
	var hero_hp := float(hero.hp)
	for i in 30:
		sim.tick(1.0 / 30.0)
	near(float(hero.hp), hero_hp, 0.01, "追丢之后不该隔空再次主动攻击")

func test_expired_buffs_fall_back_to_neutral_values() -> void:
	var hero := _hero()
	Jungle.apply_buff(hero, "red")
	Jungle.apply_buff(hero, "blue")
	hero.buff_red_timer = 0.0
	hero.buff_blue_timer = 0.0
	near(Jungle.damage_scale(hero), 1.0, 0.001, "红增益过期后伤害回落")
	near(Jungle.cooldown_scale(hero), 1.0, 0.001, "蓝增益过期后冷却回落")
