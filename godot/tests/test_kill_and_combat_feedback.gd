extends "res://tests/test_base.gd"

const CombatAnnouncer = preload("res://sim/combat_announcer.gd")
const HitStopManager = preload("res://scripts/view/hit_stop_manager.gd")
const MatchSim = preload("res://sim/match_sim.gd")

func test_first_blood_and_multi_kill_detection() -> void:
	var announcer := CombatAnnouncer.new()
	
	# 1st kill in match: First Blood
	var event1: Dictionary = announcer.record_kill(1, "blade", "blue", 10, "tank", "red", 12.0)
	check(event1.has("announcement"), "kill produces announcement")
	eq(str(event1.announcement), "first_blood", "first hero kill in match is First Blood")
	
	# Same killer gets another kill within multi-kill window (e.g. 5 seconds later)
	var event2: Dictionary = announcer.record_kill(1, "blade", "blue", 11, "mage", "red", 17.0)
	eq(str(event2.announcement), "double_kill", "second kill within window triggers double kill")
	
	# Third kill
	var event3: Dictionary = announcer.record_kill(1, "blade", "blue", 12, "archer", "red", 20.0)
	eq(str(event3.announcement), "triple_kill", "third kill within window triggers triple kill")

func test_kill_streak_and_shutdown() -> void:
	var announcer := CombatAnnouncer.new()
	# Simulate 1 getting 3 kills
	announcer.record_kill(1, "blade", "blue", 10, "tank", "red", 10.0)
	announcer.record_kill(1, "blade", "blue", 11, "tank", "red", 35.0) # >10s, streak continues
	var streak3: Dictionary = announcer.record_kill(1, "blade", "blue", 12, "tank", "red", 60.0)
	eq(str(streak3.streak_title), "killing_spree", "3 kills in one life is killing spree")
	
	# Now red player 2 kills blue player 1 (Shutdown!)
	var shutdown_event: Dictionary = announcer.record_kill(2, "archer", "red", 1, "blade", "blue", 70.0)
	eq(str(shutdown_event.announcement), "shutdown", "killing a hero on a streak triggers shutdown")

func test_ace_announcement_when_team_wiped() -> void:
	var announcer := CombatAnnouncer.new()
	var red_team := [
		{"id": 10, "type": "hero", "team": "red", "alive": false},
		{"id": 11, "type": "hero", "team": "red", "alive": false},
	]
	
	var is_ace: bool = announcer.check_ace("red", red_team)
	check(is_ace, "all enemies dead triggers Ace")
	
	red_team[0].alive = true
	check(not announcer.check_ace("red", red_team), "if any enemy is alive, no Ace")
	
	var duel_team := [{"id": 12, "type": "hero", "team": "red", "alive": false}]
	check(not announcer.check_ace("red", duel_team), "a lone dead hero in 1v1 is not an Ace")

func test_non_hero_death_claims_first_blood_and_resets_streak() -> void:
	var announcer := CombatAnnouncer.new()
	var first: Dictionary = announcer.record_death(10)
	eq(str(first.announcement), "first_blood", "non-hero first death still claims first blood")
	var second: Dictionary = announcer.record_death(10)
	eq(str(second.announcement), "", "first blood is claimed only once")

func test_match_sim_emits_announcements_and_ace() -> void:
	var sim := MatchSim.new({
		"mode": "team",
		"humans": [
			{"id": "p1", "team": "blue", "hero_type": "blade"},
			{"id": "p2", "team": "red", "hero_type": "tank"},
			{"id": "p3", "team": "red", "hero_type": "mage"},
		],
		"bot_fill": false,
	})
	var blue: Dictionary = sim.get_hero_by_player("p1")
	var red_one: Dictionary = sim.get_hero_by_player("p2")
	var red_two: Dictionary = sim.get_hero_by_player("p3")
	check(not blue.is_empty() and not red_one.is_empty() and not red_two.is_empty(), "team heroes spawned")
	
	sim._kill_entity(red_one, blue)
	var first_death := _find_event(sim.state.events, "death")
	eq(str(first_death.get("announcement", "")), "first_blood", "sim tags first blood")
	check(not _has_event(sim.state.events, "ace"), "one teammate still alive means no ace")
	
	sim._kill_entity(red_two, blue)
	check(_has_event(sim.state.events, "ace"), "wiping the team emits ace")
	var second_death := _latest_event(sim.state.events, "death")
	eq(str(second_death.get("announcement", "")), "double_kill", "second quick kill is a double kill")
	eq(str(second_death.get("streak_title", "")), "", "two kills is not a streak title yet")

func _find_event(events: Array, type: String) -> Dictionary:
	for event in events:
		if str(event.get("type", "")) == type:
			return event
	return {}

func _latest_event(events: Array, type: String) -> Dictionary:
	for i in range(events.size() - 1, -1, -1):
		var event: Variant = events[i]
		if event is Dictionary and str(event.get("type", "")) == type:
			return event
	return {}

func _has_event(events: Array, type: String) -> bool:
	return not _find_event(events, type).is_empty()

func test_hit_stop_manager_freezes_and_decays() -> void:
	var manager := HitStopManager.new()
	eq(manager.is_frozen(), false, "initially not frozen")
	
	manager.trigger_hit_stop(0.08, 0.4) # 80ms freeze, 0.4 shake
	eq(manager.is_frozen(), true, "hit stop is active")
	gt(manager.get_shake_offset().length(), 0.0, "screen shake offset generated")
	
	# Advance time past freeze duration
	manager.tick(0.09)
	eq(manager.is_frozen(), false, "freeze ends after duration")
	
	# Shake decays
	var initial_shake := manager.get_shake_offset()
	manager.tick(0.2)
	lt(manager.get_shake_offset().length(), initial_shake.length(), "shake decays toward zero")
