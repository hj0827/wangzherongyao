extends RefCounted

signal state_changed(state: String)
signal room_updated(room_state: Dictionary)
signal match_started(config: Dictionary)
signal snapshot_received(snapshot: Dictionary)
signal events_received(events: Array)
signal input_received(peer_id: int, input: Dictionary)
signal peer_left(peer_id: int)
signal peer_returned(peer_id: int)
signal rtt_updated(ms: int)
signal error_received(code: String)

const NetProtocol = preload("res://net/net_protocol.gd")
const RoomManager = preload("res://net/room_manager.gd")
const HeroDefs = preload("res://sim/hero_defs.gd")
const SkillSystem = preload("res://sim/skill_system.gd")

const MAX_CLIENTS := 12
const CONNECT_TIMEOUT_MS := 6000
const PEER_TIMEOUT_MS := 2500
const HEARTBEAT_MS := 500
# 掉线后 60 秒内允许凭内存里的凭证回到原槽位；超时才真正清人。
# 这段时间里主机把英雄交给 AI 托管，重连成功后立即交还。
const RECONNECT_WINDOW_MS := 60000
const RECONNECT_RETRY_MS := 1500
# 主动退出时先发 leave，再留一点时间让 ENet 把可靠包刷上链路，然后才真正断开。
const CLOSE_FLUSH_MS := 300

var state := "idle"
var is_server := false
var local_peer_id := 1
# 本地玩家选中的召唤师技能，随 hello / set_summoner 同步到主机。
var local_summoner := "flash"
var local_name := "玩家"
var local_hero := "blade"
var room_manager: Object = null
var room_code := ""
var room_state: Dictionary = {}
var match_config: Dictionary = {}
var listen_port := 0
var last_error := ""
var peer: ENetMultiplayerPeer = null
# 诊断字段：最近一个包的通道类型。状态快照走可靠通道会拖住后面所有快照，
# 这类回归在环回网络上看不出来，只能靠它把「用了哪条通道」变成可断言的事实。
var last_send_mode := ""
# 诊断字段：本局累计被 MAX_EVENTS 截断的事件数。客机「少播一次击杀/团战特效」
# 时先看它，避免把容量问题误判成表现层 bug。
var dropped_events := 0
# 重连窗口（毫秒）。测试会把它调小来验证超时，生产保持 60 秒。
var reconnect_window_ms := RECONNECT_WINDOW_MS
# 客机延迟：last_rtt_ms 是最新采样，rtt_display_ms 每 2 秒才刷新一次，
# 避免数字每帧跳动导致玩家盯着看却读不出趋势。
var last_rtt_ms := -1
var rtt_display_ms := -1
var _ping_sent_at := 0
var _rtt_refresh_at := 0

var _clients := {}
var _mode := "duel"
var _desired_code := ""
var _connect_deadline := 0
var _last_heartbeat := 0
var _closing_until := 0
# 客机重连：地址/端口与凭证只驻留内存，进程退出即失效，绝不落盘。
var _address := ""
var _port := 0
var _reconnect_token := ""
var _reconnect_deadline := 0
var _reconnect_retry_at := 0
var _reconnect_hello_sent := false
var _resume_state := ""
# 主机侧：player_id(槽位身份) → 凭证 / 当前真实网络 id / 掉线时间。
# 身份在整个对局里保持不变，重连只更换「真实 id → 身份」的映射，
# 这样 sim 的 owner_id、match_config 与队伍分配都不用重写。
var _peer_tokens := {}
var _token_owner := {}
var _raw_peer := {}
var _peer_aliases := {}
var _disconnected_at := {}

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
	_address = address
	_port = port
	_reconnect_token = _new_token()
	_connect_deadline = Time.get_ticks_msec() + CONNECT_TIMEOUT_MS
	_set_state("connecting")
	return {"ok": true}

func poll() -> void:
	var net := peer
	var now := Time.get_ticks_msec()
	if net == null:
		# 重连时 peer 已被关掉，仍然要靠 poll 推进「再拨号」的计时。
		if not is_server and state == "reconnecting":
			_poll_reconnect(now)
		return
	net.poll()
	# close() 之后链路只负责把 leave 刷出去，不再接收任何回包改变状态。
	if _closing_until > 0:
		if now >= _closing_until:
			_shutdown_peer()
			_closing_until = 0
		return
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

func choose_summoner(spell_id: String) -> void:
	if not SkillSystem.SUMMONER_SPELLS.has(spell_id):
		return
	local_summoner = spell_id
	if is_server:
		if room_manager != null and room_code != "" and state == "lobby":
			room_manager.set_summoner(1, room_code, spell_id)
			_publish_room_state()
	elif peer != null and state in ["connected", "lobby"]:
		_send_to(1, "set_summoner", {"summoner": spell_id})

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

# 按队伍分别构建并下发状态快照（视野过滤）。同一队伍的多个客户端共用一份编码结果。
# 走不可靠通道：快照是「最新覆盖旧」，丢一格下一格就补上；而可靠通道里丢一个分片会把
# 后面排队的快照全部卡住，表现就是网络一抖人物往回流。
func broadcast_team_snapshots(build: Callable) -> void:
	if not is_server or peer == null or not build.is_valid():
		return
	var packets := {}
	for entry in _remote_peer_teams():
		var team := str(entry.team)
		if not packets.has(team):
			var snapshot: Variant = build.call(team)
			if not (snapshot is Dictionary) or (snapshot as Dictionary).is_empty():
				continue
			packets[team] = NetProtocol.encode("snapshot", snapshot)
		_send_bytes(int(entry.peer_id), packets[team], false)

# 离散事件单独走可靠通道：击杀播报、结算曲、技能特效都只在这一路。
# 跟着快照走不可靠通道的话，丢一次就永远不会补发（客机不会播胜利曲）。
func broadcast_team_events(build: Callable, time: float = 0.0) -> void:
	if not is_server or peer == null or not build.is_valid():
		return
	var packets := {}
	for entry in _remote_peer_teams():
		var team := str(entry.team)
		if not packets.has(team):
			var events: Variant = build.call(team)
			# 空数组也要在 packets 里留位，否则同一队伍的每个客户端都要重算一次过滤。
			if events is Array and not (events as Array).is_empty():
				packets[team] = NetProtocol.encode("events", {"time": time, "events": events})
			else:
				packets[team] = PackedByteArray()
		var packet: PackedByteArray = packets[team]
		if packet.is_empty():
			continue
		_send_bytes(int(entry.peer_id), packet, true)

# 每个远程玩家的 peer_id → 队伍。快照与事件两条路共用，避免各写一遍筛人逻辑。
func _remote_peer_teams() -> Array:
	var players: Array = []
	if room_manager != null and room_code != "":
		var info: Dictionary = room_manager.get_room_info(room_code)
		players = info.get("players", [])
	if players.is_empty():
		players = match_config.get("humans", [])
	var out: Array = []
	for player in players:
		var peer_id := int(player.get("id", player.get("peer_id", 0)))
		if peer_id <= 1:
			continue
		out.append({"peer_id": peer_id, "team": str(player.get("team", "blue"))})
	return out

func is_online() -> bool:
	return peer != null and state in ["lobby", "match"]

func close() -> void:
	# 客机主动退出：先把 leave 塞进可靠通道，再让 poll() 刷 300ms 才真正断开。
	# 立即 close 会把还没上路的包一起丢掉，主机只能等 60 秒超时 —— 就是幽灵玩家。
	# 上一次 close 还在刷包时又要重开：先把它彻底收掉，避免旧 ENet host 泄漏。
	if _closing_until > 0:
		_shutdown_peer()
		_closing_until = 0
	var graceful := peer != null and not is_server \
		and peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED
	if graceful:
		_send_to(1, "leave", {}, true)
		_closing_until = Time.get_ticks_msec() + CLOSE_FLUSH_MS
		_set_state("idle")
	elif peer != null:
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
	# 主动退出（close）不进入重连，凭证也一并作废。
	_address = ""
	_port = 0
	_reconnect_token = ""
	_reconnect_deadline = 0
	_reconnect_retry_at = 0
	_reconnect_hello_sent = false
	_resume_state = ""
	last_rtt_ms = -1
	rtt_display_ms = -1
	_ping_sent_at = 0
	_rtt_refresh_at = 0
	_peer_tokens.clear()
	_token_owner.clear()
	_raw_peer.clear()
	_peer_aliases.clear()
	_disconnected_at.clear()
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
				"token": _reconnect_token,
				"summoner": local_summoner,
			})
		elif now >= _connect_deadline:
			last_error = "connect_timeout"
			_set_state("disconnected")
			error_received.emit(last_error)
			_shutdown_peer()
		return
	if state in ["connected", "lobby", "match"]:
		if status == MultiplayerPeer.CONNECTION_DISCONNECTED:
			_begin_reconnect(now)
			return
		if now - _last_heartbeat >= HEARTBEAT_MS:
			_last_heartbeat = now
			_ping_sent_at = now
			_send_to(1, "ping", {}, false)
	elif state == "reconnecting":
		_poll_reconnect(now)

# 链路断开不等于离开对局：60 秒内持续换新 peer 重拨，凭证还在内存里。
# 超过窗口才真正判定掉线，避免地铁/切后台这种几秒抖动直接把人踢出比赛。
func _begin_reconnect(now: int) -> void:
	if _reconnect_token == "" or _address == "" or _port <= 0:
		_fail_disconnect("host_disconnected")
		return
	_resume_state = state
	_reconnect_deadline = now + reconnect_window_ms
	_reconnect_retry_at = now
	_reconnect_hello_sent = false
	if peer != null:
		peer.close()
		peer = null
	_set_state("reconnecting")
	error_received.emit("reconnecting")

func _poll_reconnect(now: int) -> void:
	if peer != null:
		var status := peer.get_connection_status()
		if status == MultiplayerPeer.CONNECTION_CONNECTED:
			if not _reconnect_hello_sent:
				_reconnect_hello_sent = true
				local_peer_id = peer.get_unique_id()
				_send_to(1, "hello", {
					"name": local_name,
					"hero_type": local_hero,
					"code": _desired_code,
					"token": _reconnect_token,
					"summoner": local_summoner,
				})
			return
		if status == MultiplayerPeer.CONNECTION_DISCONNECTED:
			peer.close()
			peer = null
			_reconnect_hello_sent = false
	if now >= _reconnect_deadline:
		_fail_disconnect("reconnect_timeout")
		return
	if peer == null and now >= _reconnect_retry_at:
		_reconnect_retry_at = now + RECONNECT_RETRY_MS
		var new_peer := ENetMultiplayerPeer.new()
		if new_peer.create_client(_address, _port) == OK:
			peer = new_peer

func _fail_disconnect(code: String) -> void:
	last_error = code
	_set_state("disconnected")
	error_received.emit(code)
	_shutdown_peer()

func _new_token() -> String:
	# 凭证只用于「证明我是刚才那个槽位」，不承载敏感信息；16 字节随机足够防猜。
	var crypto := Crypto.new()
	return crypto.generate_random_bytes(16).hex_encode()

func _maintain_server(now: int) -> void:
	for client_id in _clients.keys():
		var id := int(client_id)
		if now - int(_clients[client_id]) > PEER_TIMEOUT_MS:
			_drop_peer(id, now)
	# 超时且没有回来：这时才真正把玩家从房间里清掉，释放槽位与容量。
	for client_id in _disconnected_at.keys():
		var id := int(client_id)
		if now - int(_disconnected_at[id]) <= reconnect_window_ms:
			continue
		_disconnected_at.erase(id)
		_forget_peer(id)
		if room_manager != null and room_code != "":
			room_manager.leave_room(id)
			var info: Dictionary = room_manager.get_room_info(room_code)
			if not info.is_empty():
				room_state = NetProtocol.make_room_state(info)
				_broadcast_room_state()

func _drop_peer(peer_id: int, now: int, explicit := false) -> void:
	if not _clients.has(peer_id):
		return
	_clients.erase(peer_id)
	var token := str(_peer_tokens.get(peer_id, ""))
	# 掉线（非主动退出）且持有凭证：保留槽位，把英雄交给 AI，等 60 秒。
	if not explicit and token != "":
		_disconnected_at[peer_id] = now
		_peer_aliases.erase(int(_raw_peer.get(peer_id, 0)))
		if state == "match":
			_send_to(0, "peer_left", {"peer_id": peer_id})
		peer_left.emit(peer_id)
		return
	_forget_peer(peer_id)
	if room_manager != null and room_code != "":
		room_manager.leave_room(peer_id)
		var info: Dictionary = room_manager.get_room_info(room_code)
		if not info.is_empty():
			room_state = NetProtocol.make_room_state(info)
			_broadcast_room_state()
	if state == "match":
		_send_to(0, "peer_left", {"peer_id": peer_id})
	peer_left.emit(peer_id)

func _forget_peer(peer_id: int) -> void:
	var token := str(_peer_tokens.get(peer_id, ""))
	if token != "" and int(_token_owner.get(token, -1)) == peer_id:
		_token_owner.erase(token)
	_peer_tokens.erase(peer_id)
	var raw := int(_raw_peer.get(peer_id, peer_id))
	_peer_aliases.erase(raw)
	_raw_peer.erase(peer_id)

func _handle_packet(sender: int, packet: PackedByteArray, now: int) -> void:
	var message := NetProtocol.decode(packet)
	if not bool(message.get("ok", false)):
		return
	var type := str(message.type)
	var payload: Dictionary = message.payload
	if is_server:
		# 重连后真实网络 id 会变，但对局内的「身份」不变：先翻译成槽位 id，
		# 之后的输入、心跳、离开都沿用身份，sim 与 match_config 无需改写。
		var identity := int(_peer_aliases.get(sender, sender))
		_clients[identity] = now
		if identity != sender:
			_clients.erase(sender)
		match type:
			"hello":
				_on_hello(sender, payload, now)
			"set_hero":
				if state == "lobby" and room_manager != null and room_code != "":
					var hero := str(payload.get("hero_type", "blade"))
					if HeroDefs.is_valid(hero):
						room_manager.set_hero(identity, room_code, hero)
						_publish_room_state()
			"set_summoner":
				if state == "lobby" and room_manager != null and room_code != "":
					var spell := str(payload.get("summoner", "flash"))
					if SkillSystem.SUMMONER_SPELLS.has(spell):
						room_manager.set_summoner(identity, room_code, spell)
						_publish_room_state()
			"input":
				if state == "match":
					input_received.emit(identity, NetProtocol.sanitize_input(payload))
			"ping":
				_send_to(identity, "pong", {}, false)
			"leave":
				_drop_peer(identity, now, true)
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
			"pong":
				if _ping_sent_at > 0:
					last_rtt_ms = clampi(now - _ping_sent_at, 0, 9999)
					# 展示值 2 秒才换一次；首包立即显示，不让玩家先看着空白。
					if rtt_display_ms < 0 or now >= _rtt_refresh_at:
						rtt_display_ms = last_rtt_ms
						_rtt_refresh_at = now + 2000
						rtt_updated.emit(rtt_display_ms)
			"resume":
				# 重连回对局：不重建场景，只恢复状态与配置，后续快照会把战场补齐。
				var config := _sanitize_config(payload.get("config", {}))
				if not config.is_empty():
					match_config = config
				_set_state("match")
				match_started.emit(match_config)
			"snapshot":
				var result := NetProtocol.sanitize_snapshot(payload)
				if bool(result.get("ok", false)):
					_note_dropped_events(int(result.snapshot.get("dropped_events", 0)))
					snapshot_received.emit(result.snapshot)
			"events":
				var clean := NetProtocol.sanitize_events(payload)
				_note_dropped_events(int(clean.get("dropped_events", 0)))
				if not (clean.events as Array).is_empty():
					events_received.emit(clean.events)
			"peer_left":
				peer_left.emit(int(payload.get("peer_id", 0)))
			"error":
				var code := str(payload.get("code", "network_error"))
				last_error = code
				_set_state("rejected")
				error_received.emit(code)
				_shutdown_peer()

func _note_dropped_events(count: int) -> void:
	if count <= 0:
		return
	var first_drop := dropped_events == 0
	dropped_events += count
	if first_drop:
		push_warning("event packet exceeded MAX_EVENTS; further drops are counted in GameSession.dropped_events")


func _on_hello(sender: int, payload: Dictionary, now: int) -> void:
	if not is_server or room_manager == null:
		return
	var hello: Dictionary = NetProtocol.sanitize_hello(payload)
	var token := str(hello.token)
	# 先看凭证：掉线 60 秒内的老玩家可以直接回到原槽位，哪怕对局已开始。
	if _reattach(sender, token, hello, now):
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
		str(hello.name),
		room_code
	)
	if not bool(joined.get("ok", false)):
		_send_to(sender, "error", {"code": str(joined.get("error", "join_failed"))})
		return
	var hero := str(hello.hero_type)
	if HeroDefs.is_valid(hero):
		room_manager.set_hero(sender, room_code, hero)
	var spell := str(hello.summoner)
	if SkillSystem.SUMMONER_SPELLS.has(spell):
		room_manager.set_summoner(sender, room_code, spell)
	_raw_peer[sender] = sender
	if token != "":
		_peer_tokens[sender] = token
		_token_owner[token] = sender
	room_state = NetProtocol.make_room_state(room_manager.get_room_info(room_code))
	_send_to(sender, "welcome", {
		"peer_id": sender,
		"code": room_code,
		"mode": _mode,
		"room_state": room_state,
	})
	_broadcast_room_state()

## 凭证有效且槽位仍在掉线保留期内：换上新链路，身份不变。
func _reattach(sender: int, token: String, hello: Dictionary, now: int) -> bool:
	if token == "" or not _token_owner.has(token):
		return false
	var identity := int(_token_owner[token])
	if room_manager == null or room_code == "" or not _room_has_player(identity):
		return false
	# 两种合法情形：主机已判定掉线（_disconnected_at），或旧链路还没超时
	# 就被新链路顶替（几秒内的小抖动）。同一条链路重复 hello 不算重连。
	var old_raw := int(_raw_peer.get(identity, identity))
	if not _disconnected_at.has(identity) and (old_raw == sender or not _clients.has(identity)):
		return false
	if _clients.has(identity):
		_clients.erase(identity)
	_disconnected_at.erase(identity)
	_peer_aliases[sender] = identity
	if old_raw != sender:
		_peer_aliases.erase(old_raw)
	_raw_peer[identity] = sender
	_clients.erase(sender)
	_clients[identity] = now
	var hero := str(hello.hero_type)
	if HeroDefs.is_valid(hero):
		# 客户端断线前选好的英雄继续沿用；若它改过英雄则同步到槽位。
		room_manager.set_hero(identity, room_code, hero)
	var spell := str(hello.summoner)
	if SkillSystem.SUMMONER_SPELLS.has(spell):
		room_manager.set_summoner(identity, room_code, spell)
	room_state = NetProtocol.make_room_state(room_manager.get_room_info(room_code))
	_send_to(identity, "welcome", {
		"peer_id": identity,
		"code": room_code,
		"mode": _mode,
		"room_state": room_state,
	})
	if state == "match":
		_send_to(identity, "resume", {"config": match_config})
	_broadcast_room_state()
	peer_returned.emit(identity)
	return true

func _room_has_player(peer_id: int) -> bool:
	if room_manager == null or room_code == "":
		return false
	var info: Dictionary = room_manager.get_room_info(room_code)
	for player in info.get("players", []):
		if int(player.get("id", 0)) == peer_id:
			return true
	return false

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
	# 目标按「槽位身份」传进来；重连后它对着一条新的真实链路。
	peer.set_target_peer(int(_raw_peer.get(target, target)))
	peer.set_transfer_mode(
		MultiplayerPeer.TRANSFER_MODE_RELIABLE if reliable else MultiplayerPeer.TRANSFER_MODE_UNRELIABLE_ORDERED
	)
	last_send_mode = "reliable" if reliable else "unreliable"
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
			var summoner := str(item.get("summoner_spell", "flash"))
			if not NetProtocol.SUMMONER_SPELLS.has(summoner):
				summoner = "flash"
			humans.append({
				"id": str(item.get("id", "")),
				"name": NetProtocol.sanitize_name(item.get("name", "")),
				"team": "red" if str(item.get("team", "blue")) == "red" else "blue",
				"hero_type": hero_type,
				"summoner_spell": summoner,
			})
	return {
		"mode": mode,
		"humans": humans,
		"bot_fill": true,
		"bot_ai": true,
	}
