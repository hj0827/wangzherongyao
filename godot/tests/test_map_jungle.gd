extends "res://tests/test_base.gd"

# 野区契约：四座镜像营地、可争夺的中立野怪、击杀后的红/蓝增益与刷新时间。
# 野区让打野位有经验与增益来源，也让地图不再只有三条兵线。

const Jungle = preload("res://sim/map/jungle.gd")
const MapLayout = preload("res://sim/map/map_layout.gd")

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

func test_expired_buffs_fall_back_to_neutral_values() -> void:
	var hero := _hero()
	Jungle.apply_buff(hero, "red")
	Jungle.apply_buff(hero, "blue")
	hero.buff_red_timer = 0.0
	hero.buff_blue_timer = 0.0
	near(Jungle.damage_scale(hero), 1.0, 0.001, "红增益过期后伤害回落")
	near(Jungle.cooldown_scale(hero), 1.0, 0.001, "蓝增益过期后冷却回落")
