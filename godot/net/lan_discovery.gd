extends RefCounted

signal offers_changed(offers: Array)

const NetProtocol = preload("res://net/net_protocol.gd")

const MAGIC := "CANYON_CLASH_V1"
const DEFAULT_PORT := 24681
const QUERY_INTERVAL_MS := 900
const OFFER_TTL_MS := 3500
const CLEANUP_INTERVAL_MS := 500

var offers: Array = []

var _udp: PacketPeerUDP = null
var _role := "off"
var _advert: Dictionary = {}
var _discovery_port := DEFAULT_PORT
var _query_address := "255.255.255.255"
var _last_query := 0
var _last_cleanup := 0

static func make_offer_bytes(data: Dictionary) -> PackedByteArray:
	var mode := str(data.get("mode", "duel"))
	if not NetProtocol.MODES.has(mode):
		mode = "duel"
	var message := {
		"magic": MAGIC,
		"query": false,
		"code": NetProtocol.sanitize_room_code(data.get("code", "")),
		"name": NetProtocol.sanitize_name(data.get("name", "")),
		"port": int(data.get("port", 0)),
		"mode": mode,
		"players": clampi(int(data.get("players", 1)), 0, 10),
	}
	return JSON.stringify(message).to_utf8_buffer()

static func parse_offer(bytes: PackedByteArray, ip: String) -> Dictionary:
	if bytes.is_empty():
		return {"ok": false, "error": "empty"}
	var parsed: Variant = JSON.parse_string(bytes.get_string_from_utf8())
	if not (parsed is Dictionary):
		return {"ok": false, "error": "bad_json"}
	if str(parsed.get("magic", "")) != MAGIC:
		return {"ok": false, "error": "bad_magic"}
	if bool(parsed.get("query", false)):
		return {"ok": false, "error": "is_query"}
	var code := NetProtocol.sanitize_room_code(parsed.get("code", ""))
	if code.is_empty():
		return {"ok": false, "error": "bad_code"}
	var port := int(parsed.get("port", 0))
	if port <= 0 or port > 65535:
		return {"ok": false, "error": "bad_port"}
	var mode := str(parsed.get("mode", "duel"))
	if not NetProtocol.MODES.has(mode):
		mode = "duel"
	var capacity := 10 if mode == "team" else 2
	var players := clampi(int(parsed.get("players", 1)), 0, capacity)
	return {
		"ok": true,
		"offer": {
			"code": code,
			"name": NetProtocol.sanitize_name(parsed.get("name", "")),
			"ip": ip,
			"port": port,
			"mode": mode,
			"capacity": capacity,
			"players": players,
		},
	}

func start_advertising(room: Dictionary, discovery_port := DEFAULT_PORT) -> Dictionary:
	stop()
	var parsed: Dictionary = parse_offer(make_offer_bytes(room), "")
	if not bool(parsed.get("ok", false)):
		return {"ok": false, "error": str(parsed.get("error", "bad_offer"))}
	var udp := PacketPeerUDP.new()
	var err := udp.bind(discovery_port, "0.0.0.0")
	if err != OK:
		return {"ok": false, "error": "bind_failed"}
	_udp = udp
	_role = "hosting"
	_advert = parsed.offer
	_discovery_port = discovery_port
	return {"ok": true}

func update_advertising(room: Dictionary) -> Dictionary:
	if _role != "hosting":
		return {"ok": false, "error": "not_hosting"}
	var parsed: Dictionary = parse_offer(make_offer_bytes(room), "")
	if not bool(parsed.get("ok", false)):
		return {"ok": false, "error": str(parsed.get("error", "bad_offer"))}
	_advert = parsed.offer
	return {"ok": true}

func start_browsing(discovery_port := DEFAULT_PORT, address := "255.255.255.255") -> Dictionary:
	stop()
	var udp := PacketPeerUDP.new()
	var err := udp.bind(0, "0.0.0.0")
	if err != OK:
		return {"ok": false, "error": "bind_failed"}
	udp.set_broadcast_enabled(true)
	_udp = udp
	_role = "browsing"
	_discovery_port = discovery_port
	_query_address = address
	_last_query = 0
	_last_cleanup = 0
	offers.clear()
	_send_query()
	return {"ok": true}

func poll() -> Array:
	if _udp == null:
		return offers
	var now := Time.get_ticks_msec()
	while _udp.get_available_packet_count() > 0:
		var packet := _udp.get_packet()
		var ip := _udp.get_packet_ip()
		var sender_port := _udp.get_packet_port()
		if _role == "hosting":
			if _is_query(packet):
				_udp.set_dest_address(ip, sender_port)
				_udp.put_packet(make_offer_bytes(_advert))
		elif _role == "browsing":
			var result: Dictionary = parse_offer(packet, ip)
			if bool(result.get("ok", false)):
				_merge_offer(result.offer, now)
	if _role == "browsing":
		if now - _last_query >= QUERY_INTERVAL_MS:
			_last_query = now
			_send_query()
		if now - _last_cleanup >= CLEANUP_INTERVAL_MS:
			_last_cleanup = now
			_remove_stale(now)
	return offers

func stop() -> void:
	if _udp != null:
		_udp.close()
		_udp = null
	_role = "off"
	_advert = {}
	offers.clear()

func _send_query() -> void:
	if _udp == null:
		return
	_udp.set_dest_address(_query_address, _discovery_port)
	_udp.put_packet(JSON.stringify({"magic": MAGIC, "query": true}).to_utf8_buffer())

func _is_query(packet: PackedByteArray) -> bool:
	var parsed: Variant = JSON.parse_string(packet.get_string_from_utf8())
	if not (parsed is Dictionary):
		return false
	return str(parsed.get("magic", "")) == MAGIC and bool(parsed.get("query", false))

func _merge_offer(offer: Dictionary, now: int) -> void:
	for i in offers.size():
		if offers[i].code == offer.code:
			offer["last_seen"] = now
			offers[i] = offer
			offers_changed.emit(offers.duplicate())
			return
	offer["last_seen"] = now
	offers.append(offer)
	offers_changed.emit(offers.duplicate())

func _remove_stale(now: int) -> void:
	var kept: Array = []
	for offer in offers:
		if now - int(offer.get("last_seen", 0)) <= OFFER_TTL_MS:
			kept.append(offer)
	if kept.size() != offers.size():
		offers = kept
		offers_changed.emit(offers.duplicate())
