extends "res://tests/test_base.gd"

const MatchSim = preload("res://sim/match_sim.gd")

func _human(id: String, team: String, hero_type := "blade") -> Dictionary:
	return {"id": id, "name": id, "team": team, "hero_type": hero_type}

func _match(options := {}) -> Object:
	var config := {
		"mode": "duel",
		"humans": [],
		"bot_fill": false,
		"bot_ai": false,
	}
	for key in options:
		config[key] = options[key]
	return MatchSim.new(config)

func _hero(sim: Object, owner_id: String) -> Dictionary:
	var hero = sim.get_hero_by_player(owner_id)
	check(hero != null, "hero exists for " + owner_id)
	return hero if hero != null else {}

func _tick_for(sim: Object, seconds: float) -> void:
	var steps := int(ceil(seconds * MatchSim.TICK_RATE))
	for i in steps:
		sim.tick(1.0 / MatchSim.TICK_RATE)

# 死亡不是时间暂停：复活等待期间冷却照样走，否则死一次等于白送一个大招 CD。
func test_cooldowns_keep_ticking_while_dead() -> void:
	var sim := _match({"humans": [_human("p1", "blue"), _human("p2", "red")]})
	var blue := _hero(sim, "p1")
	var red := _hero(sim, "p2")
	blue["skill_r_cd"] = 60.0
	blue["summoner_cd"] = 90.0
	blue["attack_cd"] = 1.0
	sim.apply_damage(int(blue.id), 99999.0, int(red.id))
	check(not bool(blue.alive), "blue is dead")
	_tick_for(sim, 2.0)
	lt(float(blue.skill_r_cd), 59.0, "ultimate cooldown keeps ticking while dead")
	lt(float(blue.summoner_cd), 89.0, "summoner cooldown keeps ticking while dead")
	lt(float(blue.attack_cd), 1.0, "attack cooldown keeps ticking while dead")
	check(float(blue.skill_r_cd) >= 0.0, "cooldown never goes negative")
	check(not bool(blue.alive), "hero stays dead during the respawn timer")

# 护盾吃掉的那部分伤害同样是「交手」：必须记战斗计时与伤害来源，
# 否则会漏掉脱战回血重置、击杀归属和助攻。
func test_fully_absorbed_damage_still_counts_as_combat() -> void:
	var sim := _match({"humans": [_human("p1", "blue"), _human("p2", "red")]})
	var blue := _hero(sim, "p1")
	var red := _hero(sim, "p2")
	blue["shield"] = 500.0
	blue["shield_timer"] = 10.0
	var hp_before := float(blue.hp)
	sim._damage(blue, 100.0, red)
	near(float(blue.hp), hp_before, 0.001, "shield fully absorbs the hit")
	eq(float(blue.shield), 400.0, "shield is consumed")
	near(float(blue.last_damage_time), float(sim.state.time), 0.001, "absorbed hit refreshes combat timer")
	check(blue.get("hero_damagers", {}).has(int(red.id)), "absorbed hit records the attacker for assists")
	eq(int(blue.get("last_hero_attacker_id", -1)), int(red.id), "absorbed hit records last hero attacker")

# 打盾不等于没输出：之后被塔收掉，击杀仍应记在压血线的英雄头上。
func test_shield_pressure_earns_kill_credit() -> void:
	var sim := _match({"humans": [_human("p1", "blue"), _human("p2", "red")]})
	var blue := _hero(sim, "p1")
	var red := _hero(sim, "p2")
	var tower: Dictionary = sim.state.entities.filter(func(e): return e.type == "tower" and e.team == "red")[0]
	blue["shield"] = 500.0
	blue["shield_timer"] = 10.0
	sim._damage(blue, 100.0, red)
	sim.apply_damage(int(blue.id), 99999.0, int(tower.id))
	check(not bool(blue.alive), "blue dies to the tower")
	eq(sim.get_last_kill().killer_id, int(red.id), "hero who drained the shield gets kill credit")

# 助攻要覆盖「只打了护盾」的队友。
func test_shield_pressure_awards_assist() -> void:
	var sim := _match({
		"mode": "team",
		"humans": [_human("p1", "blue"), _human("p2", "red"), _human("p3", "red", "archer")],
	})
	var blue := _hero(sim, "p1")
	var red_one := _hero(sim, "p2")
	var red_two := _hero(sim, "p3")
	blue["shield"] = 500.0
	blue["shield_timer"] = 10.0
	sim._damage(blue, 100.0, red_one)
	sim._damage(blue, 99999.0, red_two)
	check(not bool(blue.alive), "blue dies to the second attacker")
	eq(int(red_two.kills), 1, "killing blow is credited")
	eq(int(red_one.assists), 1, "shield-only damage still awards an assist")

# 主机广播要复用同一份世界快照按队伍过滤：内容必须与逐队重建一致，且不能改坏基础快照。
func test_snapshot_for_reuses_prebuilt_base() -> void:
	var sim := _match({"humans": [_human("p1", "blue"), _human("p2", "red")]})
	var base: Dictionary = sim.snapshot()
	var full_count: int = base.entities.size()
	var with_base: Dictionary = sim.snapshot_for("blue", null, base)
	var rebuilt: Dictionary = sim.snapshot_for("blue")
	eq(base.entities.size(), full_count, "base snapshot must not be mutated by filtering")
	eq(with_base.entities.size(), rebuilt.entities.size(), "filtering a shared base keeps the same entity set")
	near(float(with_base.time), float(rebuilt.time), 0.0001, "shared base keeps the same time")
	lt(float(with_base.entities.size()), float(full_count) + 1.0, "filtered view cannot exceed the full world")
