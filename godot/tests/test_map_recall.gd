extends "res://tests/test_base.gd"

# 回城契约：4 秒引导、移动/施法/受击打断、完成后回到出生点。
# 回城让「残血带线 → 回家补给 → 再出门」成为地图节奏的一部分。

const RecallRules = preload("res://sim/map/recall.gd")
const MatchSim = preload("res://sim/match_sim.gd")

func _hero() -> Dictionary:
	return {
		"type": "hero",
		"team": "blue",
		"alive": true,
		"pos": Vector2(10.0, 10.0),
		"spawn_pos": Vector2(46.0, -46.0),
		"recalling": false,
		"recall_timer": 0.0,
		"recall_total": 0.0,
	}

func _input(overrides := {}) -> Dictionary:
	var result := {
		"move": Vector2.ZERO,
		"aim": Vector2.ZERO,
		"attack": false,
		"skill_q": false,
		"skill_e": false,
		"recall": false,
	}
	for key in overrides:
		result[key] = overrides[key]
	return result

func test_recall_channels_for_four_seconds_then_teleports_home() -> void:
	var hero := _hero()
	RecallRules.start(hero)
	check(bool(hero.recalling), "回城引导开始")
	near(float(hero.recall_timer), RecallRules.CHANNEL_TIME, 0.001, "引导时长四秒")
	eq(RecallRules.tick(hero, _input(), 2.0), false, "两秒时尚未完成")
	near(float(hero.recall_timer), 2.0, 0.001, "倒计时正确递减")
	eq(RecallRules.tick(hero, _input(), 2.01), true, "四秒后回城完成")
	check(not bool(hero.recalling), "完成后退出引导状态")
	near((hero.pos as Vector2).distance_to(hero.spawn_pos), 0.0, 0.001, "回城落点是出生点")

func test_moving_or_casting_cancels_recall() -> void:
	var hero := _hero()
	RecallRules.start(hero)
	RecallRules.tick(hero, _input({"move": Vector2(1.0, 0.0)}), 0.5)
	check(not bool(hero.recalling), "移动打断回城")
	RecallRules.start(hero)
	RecallRules.tick(hero, _input({"skill_q": true}), 0.5)
	check(not bool(hero.recalling), "施法打断回城")
	RecallRules.start(hero)
	RecallRules.tick(hero, _input({"attack": true}), 0.5)
	check(not bool(hero.recalling), "普攻打断回城")

func test_damage_interrupts_recall() -> void:
	var hero := _hero()
	RecallRules.start(hero)
	RecallRules.interrupt(hero)
	check(not bool(hero.recalling), "受击立即打断回城")
	near(float(hero.recall_timer), 0.0, 0.001, "打断后清空倒计时")

func test_dead_hero_cannot_start_recall() -> void:
	var hero := _hero()
	hero.alive = false
	RecallRules.start(hero)
	check(not bool(hero.recalling), "阵亡英雄不能回城")

func test_simulation_integrates_recall_input_and_damage_cancel() -> void:
	var sim := MatchSim.new({
		"mode": "duel",
		"humans": [{"id": "p1", "name": "回城者", "team": "blue", "hero_type": "blade"}],
		"bot_fill": true,
		"bot_ai": false,
	})
	var hero: Dictionary = sim.get_hero_by_player("p1")
	hero.pos = Vector2(5.0, 5.0)
	sim.set_input("p1", _input({"recall": true}))
	sim.tick(1.0 / MatchSim.TICK_RATE)
	check(bool(hero.recalling), "模拟层识别回城输入并开始引导")
	var frame := 1.0 / MatchSim.TICK_RATE
	for i in int(RecallRules.CHANNEL_TIME * MatchSim.TICK_RATE) + 2:
		sim.tick(frame)
	check(not bool(hero.recalling), "引导结束")
	near((hero.pos as Vector2).distance_to(hero.spawn_pos), 0.0, 0.01, "模拟层回城后落位出生点")

	hero.pos = Vector2(5.0, 5.0)
	sim.set_input("p1", _input({"recall": true}))
	sim.tick(frame)
	check(bool(hero.recalling), "再次开始回城")
	sim.apply_damage(int(hero.id), 30.0)
	check(not bool(hero.recalling), "受到伤害立即打断回城")
