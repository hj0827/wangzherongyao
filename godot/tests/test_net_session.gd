extends "res://tests/test_base.gd"

const GameSession = preload("res://net/game_session.gd")

func _pump(sessions: Array, seconds := 2.0) -> void:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < deadline:
		for session in sessions:
			if session != null:
				session.poll()
		OS.delay_msec(5)

func _host(hero := "blade", mode := "duel", name := "Alice") -> Object:
	var host: Object = GameSession.new()
	var result: Dictionary = host.host_game(0, name, hero, mode)
	check(result.ok, "host starts listening")
	return host

func _join(host: Object, name := "Bob", hero := "mage", code := "") -> Object:
	var client: Object = GameSession.new()
	var result: Dictionary = client.join_game("127.0.0.1", int(host.listen_port), name, hero, code)
	check(result.ok, "client connection initiated")
	return client

func test_host_creates_room_with_code() -> void:
	var host := _host("tank", "team")
	eq(host.state, "lobby", "host enters lobby")
	eq(host.room_code.length(), 5, "host room code generated")
	eq(host.room_state.mode, "team", "room state carries mode")
	eq(host.room_state.players.size(), 1, "host alone in room")
	eq(host.room_state.players[0].hero_type, "tank", "host hero recorded")
	gt(float(host.listen_port), 0.0, "host advertises a real port")
	host.close()

func test_two_players_sync_room_state() -> void:
	var host := _host()
	var client := _join(host)
	_pump([host, client])
	eq(client.state, "lobby", "client reaches lobby")
	eq(host.room_state.players.size(), 2, "host sees two players")
	eq(client.room_state.players.size(), 2, "client sees two players")
	eq(client.local_peer_id, int(client.room_state.players[1].id), "client id matches room entry")
	eq(client.room_state.players[1].team, "red", "second player assigned red")
	eq(client.room_state.host_id, 1, "host id is one")
	host.close()
	client.close()

func test_guest_joining_with_wrong_code_is_rejected() -> void:
	var host := _host()
	var client := _join(host, "Bob", "mage", "ZZZZZ")
	_pump([host, client])
	eq(host.room_state.players.size(), 1, "wrong code does not join room")
	eq(client.state, "rejected", "client rejected")
	check(client.last_error == "bad_room_code", "bad code error surfaced")
	host.close()
	client.close()

func test_hero_selection_propagates_both_ways() -> void:
	var host := _host()
	var client := _join(host)
	_pump([host, client])
	client.choose_hero("archer")
	host.choose_hero("tank")
	_pump([host, client])
	var client_entry: Dictionary = host.room_state.players.filter(func(player): return int(player.id) == client.local_peer_id)[0]
	var host_entry: Dictionary = client.room_state.players.filter(func(player): return int(player.id) == 1)[0]
	eq(client_entry.hero_type, "archer", "host sees guest hero change")
	eq(host_entry.hero_type, "tank", "guest sees host hero change")
	host.close()
	client.close()

func test_start_match_broadcasts_config_and_inputs_reach_host() -> void:
	var host := _host()
	var client := _join(host)
	_pump([host, client])
	var started_configs: Array = []
	client.match_started.connect(func(config): started_configs.append(config))
	var inputs: Array = []
	host.input_received.connect(func(peer_id, input): inputs.append({"peer_id": peer_id, "input": input}))
	var started: Dictionary = host.start_match()
	check(started.ok, "host starts match")
	_pump([host, client])
	eq(client.state, "match", "client enters match")
	eq(started_configs.size(), 1, "client got start signal")
	eq(started_configs[0].mode, "duel", "config mode broadcast")
	eq(started_configs[0].humans.size(), 2, "config lists both humans")
	client.submit_input({
		"move": Vector2(6.0, 0.0),
		"aim": Vector2(400.0, -3.0),
		"attack": true,
		"skill_q": true,
		"skill_e": false,
	})
	_pump([host, client], 1.0)
	eq(inputs.size(), 1, "host received input")
	if inputs.size() == 1:
		eq(inputs[0].peer_id, client.local_peer_id, "input tagged by sender")
		near(inputs[0].input.move.length(), 1.0, 0.001, "input movement clamped")
		near(inputs[0].input.aim.x, 58.0, 0.001, "input aim clamped")
		eq(inputs[0].input.skill_q, true, "input skill kept")
	host.close()
	client.close()

func test_snapshot_reaches_client_sanitized() -> void:
	var host := _host()
	var client := _join(host)
	_pump([host, client])
	host.start_match()
	_pump([host, client])
	var snapshots: Array = []
	client.snapshot_received.connect(func(snapshot): snapshots.append(snapshot))
	host.broadcast_team_snapshots(func(_team: String) -> Dictionary:
		return {
			"time": 4.25,
			"mode": "duel",
			"bounds": 58.0,
			"ended": false,
			"winner": "",
			"wave": 2,
			"scores": {"blue": {"kills": 1, "towers": 0}, "red": {"kills": 0, "towers": 0}},
			"entities": [
				{"id": 1, "type": "hero", "team": "blue", "x": 2.0, "y": -3.0, "hp": 800.0, "max_hp": 1000.0, "alive": true, "hero_type": "blade", "owner_id": "1", "name": "Alice"},
				{"id": 99, "type": "dragon", "x": 0.0, "y": 0.0},
			],
		}
	)
	_pump([host, client], 1.0)
	eq(snapshots.size(), 1, "client received snapshot")
	if snapshots.size() == 1:
		eq(snapshots[0].time, 4.25, "snapshot time kept")
		eq(snapshots[0].entities.size(), 1, "unknown entity dropped")
		eq(snapshots[0].entities[0].hero_type, "blade", "hero payload kept")
	host.close()
	client.close()

func test_disconnect_drops_guest_and_notifies_host() -> void:
	var host := _host()
	var client := _join(host)
	_pump([host, client])
	host.start_match()
	_pump([host, client])
	var left: Array = []
	host.peer_left.connect(func(peer_id): left.append(peer_id))
	var peer_id: int = client.local_peer_id
	client.close()
	_pump([host], 4.0)
	eq(host.room_state.players.size(), 1, "guest removed from room")
	eq(left.size(), 1, "host notified once")
	if left.size() == 1:
		eq(left[0], peer_id, "notified with departing peer id")
	host.close()

func test_host_loss_is_reported_to_guest() -> void:
	var host := _host()
	var client := _join(host)
	_pump([host, client])
	var errors: Array = []
	client.error_received.connect(func(code): errors.append(code))
	host.close()
	_pump([client], 3.0)
	eq(client.state, "disconnected", "guest notices host loss")
	check(errors.has("host_disconnected"), "host loss error surfaced")
	client.close()

# 状态快照丢了下一格就覆盖，走不可靠通道；击杀/结算/特效这类离散事件丢一次
# 就是永久缺失（客机不会播胜利曲、不会弹播报），必须走可靠通道。
func test_state_snapshot_and_events_use_separate_channels() -> void:
	var host := _host()
	var client := _join(host)
	_pump([host, client])
	host.start_match()
	_pump([host, client])
	var snapshots: Array = []
	var events: Array = []
	client.snapshot_received.connect(func(snapshot): snapshots.append(snapshot))
	client.events_received.connect(func(list): events.append_array(list))

	host.broadcast_team_snapshots(func(_team: String) -> Dictionary:
		return {
			"time": 6.0, "mode": "duel", "bounds": 58.0, "ended": false, "winner": "",
			"wave": 2, "scores": {},
			"entities": [{
				"id": 1, "type": "hero", "team": "blue", "x": 0.0, "y": 0.0,
				"hp": 100.0, "max_hp": 100.0, "alive": true,
				"owner_id": "1", "hero_type": "blade", "name": "Alice",
			}],
		}
	)
	eq(host.last_send_mode, "unreliable", "状态快照必须走不可靠通道")
	host.broadcast_team_events(func(_team: String) -> Array:
		return [{"type": "wave", "wave": 2}, {"type": "match_end", "winner": "blue"}]
	)
	eq(host.last_send_mode, "reliable", "离散事件必须走可靠通道")

	_pump([host, client], 1.0)
	eq(snapshots.size(), 1, "客机收到状态快照")
	if snapshots.size() == 1:
		eq(snapshots[0].time, 6.0, "快照时间保留")
		eq(snapshots[0].events.size(), 0, "状态快照不再夹带事件")
	eq(events.size(), 2, "事件走独立包到达")
	if events.size() == 2:
		eq(events[0].type, "wave", "兵线事件")
		eq(events[1].type, "match_end", "结算事件")
		eq(events[1].winner, "blue", "结算方保留")
	host.close()
	client.close()

func test_team_snapshot_broadcast_filters_each_team() -> void:
	var host := _host()
	var client := _join(host)
	_pump([host, client])
	host.start_match()
	_pump([host, client])
	var received: Array = []
	var built_teams: Array = []
	client.snapshot_received.connect(func(snapshot): received.append(snapshot))
	host.broadcast_team_snapshots(func(team: String) -> Dictionary:
		built_teams.append(team)
		return {
			"time": 2.0,
			"mode": "duel",
			"bounds": 58.0,
			"ended": false,
			"winner": "",
			"wave": 1,
			"objectives": {},
			"scores": {},
			"entities": [{
				"id": 1, "type": "hero", "team": team, "x": 0.0, "y": 0.0,
				"hp": 100.0, "max_hp": 100.0, "alive": true,
				"owner_id": "1", "hero_type": "blade", "name": "Alice",
			}],
			"events": [],
		}
	)
	_pump([host, client], 1.0)
	eq(received.size(), 1, "guest received one team snapshot")
	if received.size() == 1:
		eq(received[0].entities.size(), 1, "team snapshot kept one hero")
		eq(str(received[0].entities[0].team), "red", "guest receives only its own team snapshot")
	eq(built_teams, ["red"], "host builds one snapshot for the guest team only")
	host.close()
	client.close()
