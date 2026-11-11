extends SceneTree

const GameSession = preload("res://net/game_session.gd")

func _pump(sessions: Array, seconds := 2.0) -> void:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < deadline:
		for session in sessions:
			if session != null:
				session.poll()
		OS.delay_msec(5)

func _initialize() -> void:
	var host: Object = GameSession.new()
	print("host: ", host.host_game(0, "Alice", "blade", "duel").ok)
	var client: Object = GameSession.new()
	print("join: ", client.join_game("127.0.0.1", int(host.listen_port), "Bob", "mage", "").ok)
	_pump([host, client])
	print("start: ", host.start_match().ok)
	_pump([host, client])
	print("client id=", client.local_peer_id, " state=", client.state, " token_len=", client._reconnect_token.length())
	client.reconnect_window_ms = 8000
	client.peer.close()
	_pump([host], 3.5)
	print("after host-only 3.5s: host players=", host.room_state.players.size(),
		" disconnected=", host._disconnected_at, " tokens=", host._peer_tokens, " raw=", host._raw_peer)
	var errors: Array = []
	client.error_received.connect(func(code): errors.append(code))
	var returned: Array = []
	host.peer_returned.connect(func(id): returned.append(id))
	var deadline := Time.get_ticks_msec() + 6000
	var next_log := 0
	while Time.get_ticks_msec() < deadline:
		host.poll()
		client.poll()
		OS.delay_msec(5)
		if Time.get_ticks_msec() >= next_log:
			next_log = Time.get_ticks_msec() + 500
			var status := -99
			if client.peer != null:
				status = client.peer.get_connection_status()
			print("[t] state=", client.state, " peer=", client.peer != null, " status=", status,
				" addr=", client._address, ":", client._port, " retry_at=", client._reconnect_retry_at,
				" now=", Time.get_ticks_msec())
	print("after reconnect pump: client state=", client.state, " id=", client.local_peer_id,
		" errors=", errors, " last_error=", client.last_error,
		" returned=", returned,
		" host players=", host.room_state.players.size(),
		" disconnected=", host._disconnected_at,
		" aliases=", host._peer_aliases, " raw=", host._raw_peer)
	host.close()
	quit(0)
