extends RefCounted

signal state_changed(state: String)
signal room_updated(room_state: Dictionary)
signal match_started(config: Dictionary)
signal snapshot_received(snapshot: Dictionary)
signal input_received(peer_id: int, input: Dictionary)
signal peer_left(peer_id: int)
signal error_received(code: String)

const NetProtocol = preload("res://net/net_protocol.gd")
const RoomManager = preload("res://net/room_manager.gd")
const HeroDefs = preload("res://sim/hero_defs.gd")

const MAX_CLIENTS := 12
const CONNECT_TIMEOUT_MS := 6000
const PEER_TIMEOUT_MS := 2500
const HEARTBEAT_MS := 500

var state := "idle"
var is_server := false
var local_peer_id := 1
var local_name := "玩家"
var local_hero := "blade"
var room_manager: Object = null
var room_code := ""
var room_state: Dictionary = {}
var match_config: Dictionary = {}
var listen_port := 0
var last_error := ""
var peer: ENetMultiplayerPeer = null

var _clients := {}
var _mode := "duel"
var _desired_code := ""
var _connect_deadline := 0
var _last_heartbeat := 0

func host_game(port: int, display_name: String, hero_type: String, mode: String) -> Dictionary:
	close()
	local_name = NetProtocol.sanitize_name(display_name)
	local_hero = hero_type if HeroDefs.is_valid(hero_type) else "blade"
	_mode = mode if NetProtocol.MODES.has(mode) else "duel"
	var new_peer := ENetMultiplayerPeer.new()
	var err := new_peer.create_server(port, MAX_CLIENTS)
	if err != OK:
		last_error = "bind_failed"
		return {"ok": false, "error": last_error}
	peer = new_peer
	is_server = true
	local_peer_id = 1
	listen_port = int(peer.get_host().get_local_port())
	room_manager = RoomManager.new()
	var created: Dictionary = room_manager.create_room(1, local_name, _mode)
	if not bool(created.get("ok", false)):
		close()
		last_error = "room_create_failed"
		return {"ok": false, "error": last_error}
	room_code = str(created.room.code)
	room_manager.set_hero(1, room_code, local_hero)
	room_state = NetProtocol.make_room_state(room_manager.get_room_info(room_code))
	_set_state("lobby")
	room_updated.emit(room_state)
	return {"ok": true, "code": room_code, "port": listen_port, "room_state": room_state}

func join_game(address: String, port: int, display_name: String, hero_type: String, code := "") -> Dictionary:
	close()
	local_name = NetProtocol.sanitize_name(display_name)
	local_hero = hero_type if HeroDefs.is_valid(hero_type) else "blade"
	_desired_code = NetProtocol.make_room_state({"code": code}).code
	var new_peer := ENetMultiplayerPeer.new()
	var err := new_peer.create_client(address, port)
	if err != OK:
		last_error = "connect_failed"
		return {"ok": false, "error": last_error}
	peer = new_peer
	is_server = false
	listen_port = port
	_connect_deadline = Time.get_ticks_msec() + CONNECT_TIMEOUT_MS
	_set_state("connecting")
	return {"ok": true}

func poll() -> void:
	var net := peer
	if net == null:
		return
	net.poll()
	var now := Time.get_ticks_msec()
	while net.get_available_packet_count() > 0:
		var sender := net.get_packet_peer()
		var packet := net.get_packet()
		_handle_packet(sender, packet, now)
		if peer != net:
			break
	if peer != net:
		return
	if is_server:
		_maintain_server(now)
	else:
		_poll_client(now)

func choose_hero(hero_type: String) -> void:
	if not HeroDefs.is_valid(hero_type):
		return
	local_hero = hero_type
	if is_server:
		if room_manager != null and room_code != "" and state == "lobby":
			room_manager.set_hero(1, room_code, hero_type)
			_publish_room_state()
	elif peer != null and state in ["connected", "lobby"]:
		_send_to(1, "set_hero", {"hero_type": hero_type})

func start_match() -> Dictionary:
	if not is_server:
		return {"ok": false, "error": "not_host"}
	if room_manager == null or room_code == "":
		return {"ok": false, "error": "no_room"}
	var started: Dictionary = room_manager.start_match(1, room_code)
	if not bool(started.get("ok", false)):
		return {"ok": false, "error": str(started.get("error", "start_failed"))}
	match_config = _sanitize_config(started.config)
	room_state = NetProtocol.make_room_state(room_manager.get_room_info(room_code))
	_set_state("match")
	_send_to(0, "start_match", {"config": match_config})
	match_started.emit(match_config)
	return {"ok": true, "config": match_config}

func submit_input(input: Dictionary) -> void:
	if is_server or peer == null:
		return
	var clean := NetProtocol.sanitize_input(input)
	var bytes := NetProtocol.encode("input", clean)
	# 购买/出售是离散且不可重放的操作，丢失一次就永远不生效，必须走可靠通道。
	var reliable := str(clean.get("buy_item", "")) != "" or int(clean.get("sell_slot", -1)) >= 0
	_send_bytes(1, bytes, reliable)

func broadcast_snapshot(snapshot: Dictionary) -> void:
	if not is_server or peer == null:
		return
	var bytes := NetProtocol.encode("snapshot", snapshot)
	_send_bytes(0, bytes, true)

# 按队伍分别构建并下发快照（视野过滤）。同一队伍的多个客户端共用一份编码结果。
func broadcast_team_snapshots(build: Callable) -> void:
	if not is_server or peer == null or not build.is_valid():
		return
	var players: Array = []
	if room_manager != null and room_code != "":
		var info: Dictionary = room_manager.get_room_info(room_code)
		players = info.get("players", [])
	if players.is_empty():
		players = match_config.get("humans", [])
	var packets := {}
	for player in players:
		var peer_id := int(player.get("id", player.get("peer_id", 0)))
		if peer_id <= 1:
			continue
		var team := str(player.get("team", "blue"))
		if not packets.has(team):
			var snapshot: Variant = build.call(team)
			if not (snapshot is Dictionary) or (snapshot as Dictionary).is_empty():
				continue
			packets[team] = NetProtocol.encode("snapshot", snapshot)
		_send_bytes(peer_id, packets[team], true)

func is_online() -> bool:
	return peer != null and state in ["lobby", "match"]

func close() -> void:
	if peer != null:
		if not is_server and peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
			_send_to(1, "leave", {}, true)
			peer.poll()
		peer.close()
		peer = null
	_clients.clear()
	room_manager = null
	room_state = {}
	match_config = {}
	room_code = ""
	listen_port = 0
	_connect_deadline = 0
	_last_heartbeat = 0
	is_server = false
	local_peer_id = 1
	last_error = ""
	state = "idle"

func _set_state(value: String) -> void:
	if state == value:
		return
	state = value
	state_changed.emit(state)

func _poll_client(now: int) -> void:
	var status := peer.get_connection_status()
	if state == "connecting":
		if status == MultiplayerPeer.CONNECTION_CONNECTED:
			local_peer_id = peer.get_unique_id()
			_set_state("connected")
			_send_to(1, "hello", {
				"name": local_name,
				"hero_type": local_hero,
				"code": _desired_code,
			})
		elif now >= _connect_deadline:
			last_error = "connect_timeout"
			_set_state("disconnected")
			error_received.emit(last_error)
			_shutdown_peer()
		return
	if state in ["connected", "lobby", "match"]:
		if status == MultiplayerPeer.CONNECTION_DISCONNECTED:
			last_error = "host_disconnected"
			_set_state("disconnected")
			error_received.emit(last_error)
			_shutdown_peer()
			return
		if now - _last_heartbeat >= HEARTBEAT_MS:
			_last_heartbeat = now
			_send_to(1, "ping", {}, false)

func _maintain_server(now: int) -> void:
	for client_id in _clients.keys():
		var id := int(client_id)
		if now - int(_clients[client_id]) > PEER_TIMEOUT_MS:
			_drop_peer(id, now)

func _drop_peer(peer_id: int, _now: int) -> void:
	if not _clients.has(peer_id):
		return
	_clients.erase(peer_id)
	if room_manager != null and room_code != "":
		room_manager.leave_room(peer_id)
		var info: Dictionary = room_manager.get_room_info(room_code)
		if not info.is_empty():
			room_state = NetProtocol.make_room_state(info)
			_broadcast_room_state()
	if state == "match":
		_send_to(0, "peer_left", {"peer_id": peer_id})
	peer_left.emit(peer_id)

func _handle_packet(sender: int, packet: PackedByteArray, now: int) -> void:
	var message := NetProtocol.decode(packet)
	if not bool(message.get("ok", false)):
		return
	var type := str(message.type)
	var payload: Dictionary = message.payload
	if is_server:
		_clients[sender] = now
		match type:
			"hello":
				_on_hello(sender, payload)
			"set_hero":
				if state == "lobby" and room_manager != null and room_code != "":
					var hero := str(payload.get("hero_type", "blade"))
					if HeroDefs.is_valid(hero):
						room_manager.set_hero(sender, room_code, hero)
						_publish_room_state()
			"input":
				if state == "match":
					input_received.emit(sender, NetProtocol.sanitize_input(payload))
			"ping":
				_send_to(sender, "pong", {}, false)
			"leave":
				_drop_peer(sender, now)
	else:
		match type:
			"welcome":
				local_peer_id = int(payload.get("peer_id", local_peer_id))
				room_code = str(payload.get("code", ""))
				_mode = str(payload.get("mode", _mode))
				var incoming: Variant = payload.get("room_state", {})
				room_state = incoming if incoming is Dictionary else {}
				_set_state("lobby")
				room_updated.emit(room_state)
			"room_state":
				var incoming: Variant = payload.get("room_state", {})
				if incoming is Dictionary:
					room_state = incoming
					room_updated.emit(room_state)
			"start_match":
				var config := _sanitize_config(payload.get("config", {}))
				if not config.is_empty():
					match_config = config
					_set_state("match")
					match_started.emit(match_config)
			"snapshot":
				var result := NetProtocol.sanitize_snapshot(payload)
				if bool(result.get("ok", false)):
					snapshot_received.emit(result.snapshot)
			"peer_left":
				peer_left.emit(int(payload.get("peer_id", 0)))
			"error":
				var code := str(payload.get("code", "network_error"))
				last_error = code
				_set_state("rejected")
				error_received.emit(code)
				_shutdown_peer()

func _on_hello(sender: int, payload: Dictionary) -> void:
	if not is_server or room_manager == null:
		return
	if state != "lobby":
		_send_to(sender, "error", {"code": "already_started"})
		return
	var requested: String = str(NetProtocol.make_room_state({"code": payload.get("code", "")}).code)
	if requested != "" and requested != room_code:
		_send_to(sender, "error", {"code": "bad_room_code"})
		return
	var joined: Dictionary = room_manager.join_room(
		sender,
		NetProtocol.sanitize_name(payload.get("name", "")),
		room_code
	)
	if not bool(joined.get("ok", false)):
		_send_to(sender, "error", {"code": str(joined.get("error", "join_failed"))})
		return
	var hero := str(payload.get("hero_type", "blade"))
	if HeroDefs.is_valid(hero):
		room_manager.set_hero(sender, room_code, hero)
	room_state = NetProtocol.make_room_state(room_manager.get_room_info(room_code))
	_send_to(sender, "welcome", {
		"peer_id": sender,
		"code": room_code,
		"mode": _mode,
		"room_state": room_state,
	})
	_broadcast_room_state()

func _publish_room_state() -> void:
	if room_manager == null or room_code == "":
		return
	var info: Dictionary = room_manager.get_room_info(room_code)
	if info.is_empty():
		return
	room_state = NetProtocol.make_room_state(info)
	room_updated.emit(room_state)
	_broadcast_room_state()

func _broadcast_room_state() -> void:
	_send_to(0, "room_state", {"room_state": room_state})

func _send_to(target: int, type: String, payload: Dictionary, reliable := true) -> void:
	_send_bytes(target, NetProtocol.encode(type, payload), reliable)

func _send_bytes(target: int, bytes: PackedByteArray, reliable: bool) -> void:
	if peer == null or bytes.is_empty():
		return
	peer.set_target_peer(target)
	peer.set_transfer_mode(
		MultiplayerPeer.TRANSFER_MODE_RELIABLE if reliable else MultiplayerPeer.TRANSFER_MODE_UNRELIABLE_ORDERED
	)
	peer.put_packet(bytes)

func _shutdown_peer() -> void:
	if peer != null:
		peer.close()
		peer = null

func _sanitize_config(raw: Variant) -> Dictionary:
	if not (raw is Dictionary):
		return {}
	var mode := str(raw.get("mode", "duel"))
	if not NetProtocol.MODES.has(mode):
		mode = "duel"
	var humans: Array = []
	var source: Variant = raw.get("humans", [])
	if source is Array:
		for item in source:
			if humans.size() >= 10:
				break
			if not (item is Dictionary):
				continue
			var hero_type := str(item.get("hero_type", "blade"))
			if not HeroDefs.is_valid(hero_type):
				hero_type = "blade"
			humans.append({
				"id": str(item.get("id", "")),
				"name": NetProtocol.sanitize_name(item.get("name", "")),
				"team": "red" if str(item.get("team", "blue")) == "red" else "blue",
				"hero_type": hero_type,
			})
	return {
		"mode": mode,
		"humans": humans,
		"bot_fill": true,
		"bot_ai": true,
	}
