extends "res://tests/test_base.gd"

const GameSession = preload("res://net/game_session.gd")
const MatchSim = preload("res://sim/match_sim.gd")

const HEROES := ["blade", "mage", "tank", "archer"]

func _pump_until(sessions: Array, condition: Callable, seconds := 10.0) -> void:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < deadline:
		for session in sessions:
			if session != null:
				session.poll()
		if bool(condition.call()):
			return
		OS.delay_msec(5)

func test_full_team_room_accepts_ten_and_rejects_overflow() -> void:
	var host: Object = GameSession.new()
	var hosted: Dictionary = host.host_game(0, "Host", "blade", "team")
	check(hosted.ok, "host starts team room")
	var clients: Array = []
	for i in 9:
		var client: Object = GameSession.new()
		client.join_game("127.0.0.1", int(host.listen_port), "P%d" % (i + 1), HEROES[i % HEROES.size()])
		clients.append(client)
	var all: Array = [host] + clients

	_pump_until(all, func(): return host.room_state.get("players", []).size() == 10)
	eq(host.room_state.players.size(), 10, "ten players fill the 5v5 room")
	eq(int(host.room_state.get("capacity", 0)), 10, "team room capacity is ten")
	eq(host.room_state.players.filter(func(player): return str(player.team) == "blue").size(), 5, "five blue players")
	eq(host.room_state.players.filter(func(player): return str(player.team) == "red").size(), 5, "five red players")
	var all_in_lobby := true
	for client in clients:
		if client.state != "lobby":
			all_in_lobby = false
	check(all_in_lobby, "all nine guests reach the lobby")

	var extra: Object = GameSession.new()
	extra.join_game("127.0.0.1", int(host.listen_port), "Overflow", "mage")
	_pump_until([host, extra], func(): return extra.state == "rejected", 4.0)
	eq(extra.state, "rejected", "eleventh player is rejected")
	eq(extra.last_error, "room_full", "overflow reports room full")
	extra.close()

	var started: Dictionary = host.start_match()
	check(started.ok, "host starts the ten-player match")
	_pump_until(all, func():
		for client in clients:
			if client.state != "match":
				return false
		return true
	, 4.0)
	eq(started.config.humans.size(), 10, "match config carries ten humans")
	eq(started.config.mode, "team", "match config is 5v5")
	for client in clients:
		eq(client.state, "match", "guest entered the match")

	var sim := MatchSim.new(started.config)
	var snapshot: Dictionary = sim.snapshot()
	var heroes: Array = snapshot.entities.filter(func(entity): return entity.type == "hero")
	var humans: Array = heroes.filter(func(entity): return entity.controller == "human")
	eq(heroes.size(), 10, "sim spawns ten heroes")
	eq(humans.size(), 10, "all ten heroes are human-controlled")
	eq(heroes.filter(func(entity): return entity.team == "blue").size(), 5, "sim fields five blue heroes")
	eq(heroes.filter(func(entity): return entity.team == "red").size(), 5, "sim fields five red heroes")

	host.close()
	for client in clients:
		client.close()
