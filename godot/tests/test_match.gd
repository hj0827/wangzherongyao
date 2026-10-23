extends "res://tests/test_base.gd"

const MatchSim = preload("res://sim/match_sim.gd")

const EMPTY_INPUT := {
	"move": Vector2.ZERO,
	"aim": Vector2.ZERO,
	"skill_q": false,
	"skill_e": false,
}

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

func _entities(sim: Object, type: String) -> Array:
	return sim.state.entities.filter(func(entity): return entity.type == type)

func _hero(sim: Object, owner_id: String) -> Dictionary:
	var hero = sim.get_hero_by_player(owner_id)
	check(hero != null, "hero exists for " + owner_id)
	return hero if hero != null else {}

func _input(overrides := {}) -> Dictionary:
	var result := EMPTY_INPUT.duplicate()
	for key in overrides:
		result[key] = overrides[key]
	return result

func _tick_for(sim: Object, seconds: float) -> void:
	var steps := int(ceil(seconds * MatchSim.TICK_RATE))
	for i in steps:
		sim.tick(1.0 / MatchSim.TICK_RATE)

func _distance(a: Vector2, b: Vector2) -> float:
	return a.distance_to(b)

func test_duel_creates_one_human_and_one_bot() -> void:
	var sim := _match({"humans": [_human("p1", "blue")], "bot_fill": true})
	var heroes := _entities(sim, "hero")
	var bases := _entities(sim, "base")
	var towers := _entities(sim, "tower")
	eq(heroes.size(), 2, "duel has two heroes")
	eq(heroes.filter(func(hero): return hero.controller == "human").size(), 1, "one human")
	eq(heroes.filter(func(hero): return hero.controller == "bot").size(), 1, "one bot")
	eq(bases.size(), 2, "two bases")
	gt(towers.size(), 0, "towers exist")
	var player := _hero(sim, "p1")
	eq(player.team, "blue", "human keeps team")

func test_team_mode_creates_ten_humans_and_full_tower_map() -> void:
	var humans: Array = []
	for i in 10:
		humans.append(_human("p%d" % i, "blue" if i < 5 else "red", "blade"))
	var sim := _match({"mode": "team", "humans": humans})
	eq(_entities(sim, "hero").size(), 10, "5v5 has ten heroes")
	eq(_entities(sim, "tower").size(), 18, "three tiers of towers per lane per team")
	eq(_entities(sim, "base").size(), 2, "two bases")

func test_team_mode_fills_empty_slots_with_bots() -> void:
	var sim := _match({
		"mode": "team",
		"humans": [_human("p1", "blue")],
		"bot_fill": true,
	})
	var heroes := _entities(sim, "hero")
	eq(heroes.size(), 10, "5v5 fills to ten heroes")
	eq(heroes.filter(func(hero): return hero.controller == "bot").size(), 9, "nine bots")
	eq(heroes.filter(func(hero): return hero.team == "blue").size(), 5, "blue has five")
	eq(heroes.filter(func(hero): return hero.team == "red").size(), 5, "red has five")

func test_heroes_spawn_clear_of_their_base() -> void:
	var sim := _match({
		"mode": "team",
		"humans": [],
		"bot_fill": true,
	})
	var bases := _entities(sim, "base")
	for hero in _entities(sim, "hero"):
		var own_base: Dictionary = bases.filter(func(base): return base.team == hero.team)[0]
		gt(_distance(hero.pos, own_base.pos), own_base.radius + hero.radius, "spawn clear of base")

func test_movement_and_map_clamp() -> void:
	var sim := _match({"humans": [_human("p1", "blue")]})
	var hero := _hero(sim, "p1")
	var start: Vector2 = hero.pos
	sim.set_input("p1", _input({"move": Vector2(1, 0), "aim": start + Vector2(5, 0)}))
	_tick_for(sim, 0.5)
	gt(hero.pos.x - start.x, 2.0, "hero moves with input")
	var bounds: float = sim.state.bounds
	hero.pos = Vector2(bounds - hero.radius - 0.2, 0)
	sim.set_input("p1", _input({"move": Vector2(1, 0), "aim": hero.pos + Vector2(5, 0)}))
	_tick_for(sim, 2.0)
	check(hero.pos.x <= bounds - hero.radius + 0.001, "hero clamped to map bounds")

func test_diagonal_movement_is_normalized() -> void:
	var sim := _match({"humans": [_human("p1", "blue")]})
	var hero := _hero(sim, "p1")
	var start: Vector2 = hero.pos
	sim.set_input("p1", _input({"move": Vector2.ONE, "aim": start + Vector2(5, 5)}))
	_tick_for(sim, 0.5)
	var moved: float = hero.pos.distance_to(start)
	near(moved, hero.speed * 0.5, 0.6, "diagonal speed matches base speed")

func test_q_skill_spends_mana_deals_damage_and_starts_cooldown() -> void:
	var sim := _match({
		"humans": [_human("p1", "blue", "blade"), _human("p2", "red", "mage")],
	})
	var blue := _hero(sim, "p1")
	var red := _hero(sim, "p2")
	red.pos = blue.pos + Vector2(4.2, 0)
	var red_hp: float = red.hp
	var mana: float = blue.mp
	sim.set_input("p1", _input({"aim": red.pos, "skill_q": true}))
	sim.tick(1.0 / MatchSim.TICK_RATE)
	lt(red.hp, red_hp, "q damages enemy hero")
	lt(blue.mp, mana, "q spends mana")
	gt(blue.skill_q_cd, 0.0, "q cooldown starts")
	var hp_after: float = red.hp
	sim.set_input("p1", _input({"aim": red.pos, "skill_q": true}))
	sim.tick(1.0 / MatchSim.TICK_RATE)
	near(red.hp, hp_after, 0.01, "q cannot be cast during cooldown")

func test_skill_without_mana_does_not_fire() -> void:
	var sim := _match({
		"humans": [_human("p1", "blue", "mage"), _human("p2", "red", "blade")],
	})
	var blue := _hero(sim, "p1")
	var red := _hero(sim, "p2")
	blue.mp = 0.0
	red.pos = blue.pos + Vector2(5.0, 0)
	var red_hp: float = red.hp
	sim.set_input("p1", _input({"aim": red.pos, "skill_q": true}))
	sim.tick(1.0 / MatchSim.TICK_RATE)
	near(red.hp, red_hp, 0.01, "no mana means no skill damage")
	eq(blue.skill_q_cd, 0.0, "no cooldown without mana")

func test_minions_spawn_and_advance_towards_enemy_base() -> void:
	var sim := _match()
	_tick_for(sim, 6.0)
	var minions := _entities(sim, "minion")
	gt(minions.size(), 0, "first wave spawned")
	var minion: Dictionary = minions[0]
	var start: Vector2 = minion.pos
	_tick_for(sim, 1.0)
	gt(minion.pos.distance_to(start), 0.5, "minion advances along lane")

func test_team_mode_spawns_three_lanes_of_minions() -> void:
	var sim := _match({"mode": "team"})
	_tick_for(sim, 6.0)
	var lanes := {}
	for minion in _entities(sim, "minion"):
		lanes[minion.lane] = true
	eq(lanes.size(), 3, "minions spawn in three lanes")

func test_tower_attacks_enemy_hero_in_range() -> void:
	var sim := _match({
		"humans": [_human("p1", "blue"), _human("p2", "red")],
	})
	var blue := _hero(sim, "p1")
	var red_tower: Dictionary = _entities(sim, "tower").filter(func(tower): return tower.team == "red")[0]
	blue.pos = red_tower.pos + Vector2(4.0, 0)
	var hp: float = blue.hp
	_tick_for(sim, 2.0)
	lt(blue.hp, hp, "tower hits hero")

func test_hero_death_respawn_and_kill_credit() -> void:
	var sim := _match({
		"humans": [_human("p1", "blue"), _human("p2", "red")],
	})
	var blue := _hero(sim, "p1")
	var red := _hero(sim, "p2")
	sim.apply_damage(blue.id, 99999.0, red.id)
	check(not blue.alive, "hero dies")
	eq(blue.deaths, 1, "death counted")
	eq(red.kills, 1, "kill credited")
	gt(red.xp, 0.0, "killer gains xp")
	_tick_for(sim, 12.0)
	check(blue.alive, "hero respawns")
	eq(blue.hp, blue.max_hp, "hero respawns at full health")
	gt(_distance(blue.pos, _entities(sim, "base").filter(func(base): return base.team == "blue")[0].pos), 5.0, "respawn at base")

func test_minion_kill_grants_xp() -> void:
	var sim := _match({
		"humans": [_human("p1", "blue")],
		"bot_fill": true,
	})
	_tick_for(sim, 6.0)
	var blue := _hero(sim, "p1")
	var enemy_minion: Dictionary = _entities(sim, "minion").filter(func(minion): return minion.team == "red")[0]
	sim.apply_damage(enemy_minion.id, 99999.0, blue.id)
	gt(blue.xp, 0.0, "minion kill grants xp")

func test_destroying_base_ends_match() -> void:
	var sim := _match({
		"humans": [_human("p1", "blue"), _human("p2", "red")],
	})
	var blue := _hero(sim, "p1")
	for tier in ["outer", "inner", "high"]:
		var tower: Dictionary = _entities(sim, "tower").filter(
			func(t): return t.team == "red" and t.lane == "mid" and t.tier == tier
		)[0]
		sim.apply_damage(tower.id, 99999.0, blue.id)
	var red_base: Dictionary = _entities(sim, "base").filter(func(base): return base.team == "red")[0]
	sim.apply_damage(red_base.id, 99999.0, blue.id)
	eq(sim.state.winner, "blue", "blue wins")
	check(sim.ended, "match ended")
	var snapshot: Dictionary = sim.snapshot()
	eq(snapshot.winner, "blue", "snapshot carries winner")
	var time_before: float = sim.state.time
	_tick_for(sim, 1.0)
	near(sim.state.time, time_before, 0.0001, "tick ignored after match end")

func test_snapshot_is_serializable_and_contains_hero_details() -> void:
	var sim := _match({
		"humans": [_human("p1", "blue")],
		"bot_fill": true,
	})
	_tick_for(sim, 0.2)
	var snapshot: Dictionary = sim.snapshot()
	check(snapshot.has("entities"), "snapshot has entities")
	check(snapshot.has("scores"), "snapshot has scores")
	check(snapshot.has("events"), "snapshot has events")
	var hero_data: Dictionary = snapshot.entities.filter(func(entity): return entity.type == "hero" and entity.owner_id == "p1")[0]
	eq(hero_data.hero_type, "blade", "hero type present")
	eq(hero_data.controller, "human", "controller present")
	check(hero_data.has("max_hp"), "max hp present")
	check(hero_data.has("mp"), "mana present")
	check(hero_data.has("respawn_timer"), "respawn timer present")
	for entity in snapshot.entities:
		check(typeof(entity.x) == TYPE_FLOAT, "snapshot x is float")
		check(typeof(entity.y) == TYPE_FLOAT, "snapshot y is float")
		check(not (entity.x is Vector2), "snapshot has no Vector2 payload")

func test_bots_move_and_fight_after_spawn() -> void:
	var sim := _match({
		"humans": [_human("p1", "blue")],
		"bot_fill": true,
		"bot_ai": true,
	})
	var bot: Dictionary = _entities(sim, "hero").filter(func(hero): return hero.controller == "bot")[0]
	var start: Vector2 = bot.pos
	_tick_for(sim, 3.0)
	gt(bot.pos.distance_to(start), 1.0, "bot leaves spawn")

func test_kill_attribution_direct_hero() -> void:
	var sim := _match({
		"humans": [_human("p1", "blue"), _human("p2", "red")],
	})
	var blue := _hero(sim, "p1")
	var red := _hero(sim, "p2")
	sim.apply_damage(red.id, 99999.0, blue.id)
	check(not red.alive, "red dies")
	eq(blue.kills, 1, "blue hero credited with kill")
	var last_kill: Dictionary = sim.get_last_kill()
	eq(last_kill.victim_id, red.id, "last kill victim matches")
	eq(last_kill.killer_id, blue.id, "last kill killer matches")
	eq(last_kill.killer_type, "hero", "killer type is hero")
	eq(sim.get_killer_of(red.id).killer_id, blue.id, "get_killer_of matches")

func test_kill_attribution_tower_with_recent_hero_damage() -> void:
	var sim := _match({
		"humans": [_human("p1", "blue"), _human("p2", "red")],
	})
	var blue := _hero(sim, "p1")
	var red := _hero(sim, "p2")
	var tower: Dictionary = _entities(sim, "tower").filter(func(t): return t.team == "blue")[0]
	sim.apply_damage(red.id, 50.0, blue.id)
	sim.apply_damage(red.id, 99999.0, tower.id)
	check(not red.alive, "red dies")
	eq(blue.kills, 1, "blue hero credited with kill due to recent damage")
	var last_kill: Dictionary = sim.get_last_kill()
	eq(last_kill.killer_id, blue.id, "killer credited to blue hero")
	eq(last_kill.killer_name, blue.name, "killer name matches blue hero")

func test_kill_attribution_pure_tower() -> void:
	var sim := _match({
		"humans": [_human("p1", "blue"), _human("p2", "red")],
	})
	var red := _hero(sim, "p2")
	var tower: Dictionary = _entities(sim, "tower").filter(func(t): return t.team == "blue")[0]
	sim.apply_damage(red.id, 99999.0, tower.id)
	check(not red.alive, "red dies")
	var last_kill: Dictionary = sim.get_last_kill()
	eq(last_kill.killer_type, "tower", "killer type is tower")
	eq(last_kill.killer_name, "防御塔", "killer name is 防御塔")

func test_in_place_attack_keeps_root_at_origin() -> void:
	var unit_visual_script := preload("res://scripts/game/unit_visual.gd")
	unit_visual_script._library_cache.clear()
	var uv: Node = unit_visual_script.new()
	uv.setup("hero", "blue", "blade", "你", true)
	var sk: Skeleton3D = null
	for node in uv.model_root.find_children("*", "Skeleton3D", true, false):
		sk = node
		break
	check(sk != null, "skeleton found")
	eq(sk.get_bone_pose_position(0), Vector3.ZERO, "initial root bone is at origin")
	uv.play_attack()
	for ap in uv.animation_players:
		ap.advance(0.2)
	eq(sk.get_bone_pose_position(0), Vector3.ZERO, "mid-attack root bone stays at origin")
	for ap in uv.animation_players:
		ap.advance(0.3)
	uv.process_visual(0.7)
	eq(sk.get_bone_pose_position(0), Vector3.ZERO, "post-attack root bone stays at origin")
	uv.free()
