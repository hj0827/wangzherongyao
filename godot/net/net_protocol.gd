extends RefCounted

const HeroDefs = preload("res://sim/hero_defs.gd")

const MAGIC := 0x4D4F4241
const VERSION := 1
const MAX_PACKET := 65536
const MAX_NAME_LENGTH := 12
const MAX_ENTITIES := 256
const MAX_EVENTS := 32
const MAX_STRING := 48
const MAX_AIM := 58.0
const MODES := ["duel", "team"]
const ENTITY_TYPES := ["hero", "minion", "tower", "base"]
const TYPES := [
	"hello",
	"welcome",
	"room_state",
	"set_hero",
	"start_match",
	"input",
	"snapshot",
	"peer_joined",
	"leave",
	"peer_left",
	"ping",
	"pong",
	"error",
]

const EMPTY_INPUT := {
	"move": Vector2.ZERO,
	"aim": Vector2.ZERO,
	"attack": false,
	"skill_q": false,
	"skill_e": false,
}

static func is_valid_type(type: String) -> bool:
	return TYPES.has(type)

static func _envelope(type: String, payload: Variant) -> Dictionary:
	return {
		"magic": MAGIC,
		"version": VERSION,
		"type": type,
		"payload": payload,
	}

static func encode(type: String, payload: Dictionary) -> PackedByteArray:
	if not is_valid_type(type):
		return PackedByteArray()
	return var_to_bytes(_envelope(type, payload))

static func decode(bytes: PackedByteArray) -> Dictionary:
	if bytes.is_empty():
		return {"ok": false, "error": "empty"}
	if bytes.size() > MAX_PACKET:
		return {"ok": false, "error": "too_large"}
	var value: Variant = bytes_to_var(bytes)
	if not (value is Dictionary):
		return {"ok": false, "error": "decode_failed"}
	var envelope: Dictionary = value
	if int(envelope.get("magic", 0)) != MAGIC:
		return {"ok": false, "error": "bad_magic"}
	if int(envelope.get("version", 0)) != VERSION:
		return {"ok": false, "error": "version_mismatch"}
	var type := str(envelope.get("type", ""))
	if not is_valid_type(type):
		return {"ok": false, "error": "unknown_type"}
	var payload: Variant = envelope.get("payload", null)
	if not (payload is Dictionary):
		return {"ok": false, "error": "bad_payload"}
	return {"ok": true, "type": type, "payload": payload}

static func sanitize_name(value: Variant) -> String:
	if not (value is String):
		return "玩家"
	var text := str(value).strip_edges()
	var cleaned := ""
	for i in text.length():
		var code := text.unicode_at(i)
		if code >= 32 and code != 127:
			cleaned += text[i]
	cleaned = cleaned.strip_edges()
	if cleaned.is_empty():
		return "玩家"
	if cleaned.length() > MAX_NAME_LENGTH:
		cleaned = cleaned.substr(0, MAX_NAME_LENGTH).strip_edges()
	return cleaned

static func sanitize_input(raw: Dictionary) -> Dictionary:
	var input := EMPTY_INPUT.duplicate()
	var raw_move: Variant = raw.get("move", Vector2.ZERO)
	if raw_move is Vector2 and (raw_move as Vector2).is_finite():
		input.move = (raw_move as Vector2).limit_length(1.0)
	var raw_aim: Variant = raw.get("aim", Vector2.ZERO)
	if raw_aim is Vector2 and (raw_aim as Vector2).is_finite():
		input.aim = (raw_aim as Vector2).clamp(Vector2(-MAX_AIM, -MAX_AIM), Vector2(MAX_AIM, MAX_AIM))
	input.attack = _flag(raw.get("attack", false))
	input.skill_q = _flag(raw.get("skill_q", false))
	input.skill_e = _flag(raw.get("skill_e", false))
	return input

static func sanitize_hello(raw: Dictionary) -> Dictionary:
	var hero_type := str(raw.get("hero_type", "blade"))
	if not HeroDefs.is_valid(hero_type):
		hero_type = "blade"
	var mode := str(raw.get("mode", "duel"))
	if not MODES.has(mode):
		mode = "duel"
	return {
		"name": sanitize_name(raw.get("name", "")),
		"hero_type": hero_type,
		"mode": mode,
	}

static func make_room_state(room: Dictionary) -> Dictionary:
	var mode := str(room.get("mode", "duel"))
	if not MODES.has(mode):
		mode = "duel"
	var capacity := 10 if mode == "team" else 2
	var players: Array = []
	var source: Variant = room.get("players", [])
	if source is Array:
		for item in source:
			if players.size() >= capacity:
				break
			if not (item is Dictionary):
				continue
			var player: Dictionary = item
			var hero_type := str(player.get("hero_type", "blade"))
			if not HeroDefs.is_valid(hero_type):
				hero_type = "blade"
			players.append({
				"id": int(player.get("id", 0)),
				"name": sanitize_name(player.get("name", "")),
				"team": "red" if str(player.get("team", "blue")) == "red" else "blue",
				"hero_type": hero_type,
				"ready": _flag(player.get("ready", false)),
			})
	return {
		"code": _sanitize_code(room.get("code", "")),
		"mode": mode,
		"capacity": capacity,
		"host_id": int(room.get("host_id", 0)),
		"started": _flag(room.get("started", false)),
		"players": players,
	}

static func sanitize_snapshot(raw: Variant) -> Dictionary:
	if not (raw is Dictionary):
		return {"ok": false, "error": "bad_snapshot"}
	var data: Dictionary = raw
	var bounds_value: Variant = data.get("bounds", null)
	if not _is_number(bounds_value):
		return {"ok": false, "error": "missing_bounds"}
	var bounds := clampf(float(bounds_value), 1.0, 512.0)
	var entities: Array = []
	var source: Variant = data.get("entities", [])
	if source is Array:
		for item in source:
			if entities.size() >= MAX_ENTITIES:
				break
			var entity := _sanitize_entity(item, bounds)
			if not entity.is_empty():
				entities.append(entity)
	var events: Array = []
	var raw_events: Variant = data.get("events", [])
	if raw_events is Array:
		for item in raw_events:
			if events.size() >= MAX_EVENTS:
				break
			var event := _sanitize_event(item)
			if not event.is_empty():
				events.append(event)
	var mode := str(data.get("mode", "duel"))
	if not MODES.has(mode):
		mode = "duel"
	return {
		"ok": true,
		"snapshot": {
			"time": clampf(_number(data.get("time", 0.0)), 0.0, 86400.0),
			"winner": _short_string(str(data.get("winner", "")), 16),
			"mode": mode,
			"bounds": bounds,
			"ended": _flag(data.get("ended", false)),
			"entities": entities,
			"scores": _sanitize_scores(data.get("scores", {})),
			"events": events,
			"wave": clampi(int(_number(data.get("wave", 1))), 0, 9999),
		},
	}

static func _sanitize_entity(raw: Variant, bounds: float) -> Dictionary:
	if not (raw is Dictionary):
		return {}
	var source: Dictionary = raw
	var type := str(source.get("type", ""))
	if not ENTITY_TYPES.has(type):
		return {}
	var id_value: Variant = source.get("id", null)
	if not _is_number(id_value):
		return {}
	var team := str(source.get("team", "neutral"))
	if team != "blue" and team != "red":
		team = "neutral"
	var entity := {
		"id": int(id_value),
		"type": type,
		"team": team,
		"x": clampf(_number(source.get("x", 0.0)), -bounds, bounds),
		"y": clampf(_number(source.get("y", 0.0)), -bounds, bounds),
		"radius": clampf(_number(source.get("radius", 0.0)), 0.0, 16.0),
		"hp": clampf(_number(source.get("hp", 0.0)), 0.0, 1000000.0),
		"max_hp": clampf(_number(source.get("max_hp", 0.0)), 0.0, 1000000.0),
		"alive": _flag(source.get("alive", false)),
	}
	if type == "hero":
		var hero_type := str(source.get("hero_type", "blade"))
		if not HeroDefs.is_valid(hero_type):
			hero_type = "blade"
		var lane := str(source.get("lane", "mid"))
		if lane != "top" and lane != "bottom":
			lane = "mid"
		entity["owner_id"] = _short_string(str(source.get("owner_id", "")), 32)
		entity["name"] = sanitize_name(source.get("name", ""))
		entity["hero_type"] = hero_type
		entity["controller"] = "bot" if str(source.get("controller", "human")) == "bot" else "human"
		entity["lane"] = lane
		entity["level"] = clampi(int(_number(source.get("level", 1))), 1, 30)
		entity["xp"] = clampf(_number(source.get("xp", 0.0)), 0.0, 1000000.0)
		entity["mp"] = clampf(_number(source.get("mp", 0.0)), 0.0, 1000000.0)
		entity["max_mp"] = clampf(_number(source.get("max_mp", 0.0)), 0.0, 1000000.0)
		entity["kills"] = clampi(int(_number(source.get("kills", 0))), 0, 9999)
		entity["deaths"] = clampi(int(_number(source.get("deaths", 0))), 0, 9999)
		entity["respawn_timer"] = clampf(_number(source.get("respawn_timer", 0.0)), 0.0, 600.0)
		entity["skill_q_cd"] = clampf(_number(source.get("skill_q_cd", 0.0)), 0.0, 600.0)
		entity["skill_e_cd"] = clampf(_number(source.get("skill_e_cd", 0.0)), 0.0, 600.0)
		entity["speed"] = clampf(_number(source.get("speed", 0.0)), 0.0, 64.0)
		entity["shield"] = clampf(_number(source.get("shield", 0.0)), 0.0, 1000000.0)
		entity["facing_x"] = clampf(_number(source.get("facing_x", 1.0)), -1.0, 1.0)
		entity["facing_y"] = clampf(_number(source.get("facing_y", 0.0)), -1.0, 1.0)
		entity["attack_cd"] = clampf(_number(source.get("attack_cd", 0.0)), 0.0, 60.0)
		entity["haste_timer"] = clampf(_number(source.get("haste_timer", 0.0)), 0.0, 60.0)
		entity["slow_timer"] = clampf(_number(source.get("slow_timer", 0.0)), 0.0, 60.0)
		entity["moving"] = _flag(source.get("moving", false))
	elif type == "minion":
		var lane := str(source.get("lane", "mid"))
		if lane != "top" and lane != "bottom":
			lane = "mid"
		entity["lane"] = lane
		entity["speed"] = clampf(_number(source.get("speed", 0.0)), 0.0, 64.0)
		entity["moving"] = _flag(source.get("moving", false))
	elif type == "tower":
		var lane := str(source.get("lane", "mid"))
		if lane != "top" and lane != "bottom":
			lane = "mid"
		entity["lane"] = lane
		entity["range"] = clampf(_number(source.get("range", 0.0)), 0.0, 64.0)
	return entity

static func _sanitize_event(raw: Variant) -> Dictionary:
	if not (raw is Dictionary):
		return {}
	var source: Dictionary = raw
	var event := {}
	for key in [
		"type", "hero", "source", "target", "slot", "hero_type", "team",
		"x", "y", "aim_x", "aim_y", "target_x", "target_y", "value",
		"damage", "wave", "level", "winner",
	]:
		if not source.has(key):
			continue
		var value: Variant = source[key]
		if value is String:
			event[key] = _short_string(value, MAX_STRING)
		elif value is bool or value is int or value is float:
			event[key] = value
	return event

static func _sanitize_scores(raw: Variant) -> Dictionary:
	var scores := {
		"blue": {"kills": 0, "towers": 0},
		"red": {"kills": 0, "towers": 0},
	}
	if not (raw is Dictionary):
		return scores
	for team in ["blue", "red"]:
		var source: Variant = raw.get(team, null)
		if source is Dictionary:
			scores[team].kills = clampi(int(_number(source.get("kills", 0))), 0, 9999)
			scores[team].towers = clampi(int(_number(source.get("towers", 0))), 0, 99)
	return scores

static func sanitize_room_code(value: Variant) -> String:
	return _sanitize_code(value)

static func _sanitize_code(value: Variant) -> String:
	if not (value is String):
		return ""
	var text := str(value).strip_edges().to_upper()
	var cleaned := ""
	for i in text.length():
		var character := text[i]
		if (character >= "A" and character <= "Z") or (character >= "0" and character <= "9"):
			cleaned += character
	if cleaned.length() > 5:
		cleaned = cleaned.substr(0, 5)
	return cleaned

static func _short_string(value: String, limit: int) -> String:
	var cleaned := ""
	for i in value.length():
		if cleaned.length() >= limit:
			break
		var code := value.unicode_at(i)
		if code >= 32 and code != 127:
			cleaned += value[i]
	return cleaned

static func _flag(value: Variant) -> bool:
	return value is bool and value

static func _is_number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))

static func _number(value: Variant) -> float:
	if not _is_number(value):
		return 0.0
	return float(value)
