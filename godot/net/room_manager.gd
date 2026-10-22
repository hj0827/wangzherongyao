extends RefCounted

const HeroDefs = preload("res://sim/hero_defs.gd")

const CODE_CHARS := "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
const CODE_LENGTH := 5
const MAX_PLAYERS := {"duel": 2, "team": 10}

var rooms: Dictionary = {}
var _rng := RandomNumberGenerator.new()

func _init() -> void:
	_rng.randomize()

func create_room(peer_id: int, display_name: String, mode: String) -> Dictionary:
	if not MAX_PLAYERS.has(mode):
		return {"ok": false, "error": "invalid_mode"}
	var code := _generate_code()
	var player := _new_player(peer_id, display_name, "blue")
	var room := {
		"code": code,
		"mode": mode,
		"host_id": peer_id,
		"started": false,
		"players": [player],
	}
	rooms[code] = room
	return {"ok": true, "room": room, "player": player}

func join_room(peer_id: int, display_name: String, code: String) -> Dictionary:
	code = code.strip_edges().to_upper()
	if not rooms.has(code):
		return {"ok": false, "error": "room_not_found"}
	var room: Dictionary = rooms[code]
	if bool(room.started):
		return {"ok": false, "error": "already_started"}
	for player in room.players:
		if int(player.id) == peer_id:
			return {"ok": true, "room": room, "player": player}
	var capacity: int = int(MAX_PLAYERS[room.mode])
	if room.players.size() >= capacity:
		return {"ok": false, "error": "room_full"}
	var player := _new_player(peer_id, display_name, _next_team(room))
	room.players.append(player)
	return {"ok": true, "room": room, "player": player}

func start_match(peer_id: int, code: String) -> Dictionary:
	code = code.strip_edges().to_upper()
	if not rooms.has(code):
		return {"ok": false, "error": "room_not_found"}
	var room: Dictionary = rooms[code]
	if int(room.host_id) != peer_id:
		return {"ok": false, "error": "not_host"}
	room.started = true
	var humans: Array = []
	for player in room.players:
		humans.append({
			"id": player.id,
			"name": player.name,
			"team": player.team,
			"hero_type": player.hero_type,
		})
	var match_config := {
		"mode": room.mode,
		"humans": humans,
		"bot_fill": true,
		"bot_ai": true,
	}
	return {"ok": true, "room": room, "config": match_config}

func set_hero(peer_id: int, code: String, hero_type: String) -> Dictionary:
	code = code.strip_edges().to_upper()
	if not rooms.has(code):
		return {"ok": false, "error": "room_not_found"}
	if not HeroDefs.is_valid(hero_type):
		return {"ok": false, "error": "invalid_hero"}
	var room: Dictionary = rooms[code]
	for player in room.players:
		if int(player.id) == peer_id:
			player.hero_type = hero_type
			return {"ok": true, "room": room, "player": player}
	return {"ok": false, "error": "not_in_room"}

func leave_room(peer_id: int) -> Dictionary:
	for code in rooms.keys():
		var room: Dictionary = rooms[code]
		var player_index := -1
		for i in room.players.size():
			if int(room.players[i].id) == peer_id:
				player_index = i
				break
		if player_index < 0:
			continue
		room.players.remove_at(player_index)
		if room.players.is_empty():
			rooms.erase(code)
			return {"ok": true, "room": room}
		if int(room.host_id) == peer_id:
			room.host_id = int(room.players[0].id)
		return {"ok": true, "room": room}
	return {"ok": false, "error": "not_in_room"}

func get_room_info(code: String) -> Dictionary:
	code = code.strip_edges().to_upper()
	return rooms.get(code, {})

func _new_player(peer_id: int, display_name: String, team: String) -> Dictionary:
	return {
		"id": peer_id,
		"name": display_name.strip_edges() if display_name.strip_edges() != "" else "玩家%d" % peer_id,
		"team": team,
		"hero_type": "blade",
		"ready": false,
	}

func _next_team(room: Dictionary) -> String:
	var blue := 0
	var red := 0
	for player in room.players:
		if player.team == "blue":
			blue += 1
		else:
			red += 1
	return "blue" if blue <= red else "red"

func _generate_code() -> String:
	for attempt in 512:
		var code := ""
		for i in CODE_LENGTH:
			code += CODE_CHARS[_rng.randi_range(0, CODE_CHARS.length() - 1)]
		if not rooms.has(code):
			return code
	# Deterministic fallback keeps codes unique even if the RNG stalls
	var index := rooms.size() + 1
	while true:
		var fallback := "R%04d" % (index % 10000)
		if not rooms.has(fallback):
			return fallback
		index += 1
	return "R0000"
