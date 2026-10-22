extends "res://tests/test_base.gd"

const NetProtocol = preload("res://net/net_protocol.gd")

func test_message_roundtrip_preserves_vectors_and_flags() -> void:
	var payload := {
		"name": "苍刃",
		"move": Vector2(0.5, -1.0),
		"aim": Vector2(12.25, -3.5),
		"skill_q": true,
		"skill_e": false,
	}
	var bytes: PackedByteArray = NetProtocol.encode("hello", payload)
	gt(float(bytes.size()), 0.0, "encoded bytes not empty")
	lt(float(bytes.size()), 512.0, "hello stays in one small packet")
	var decoded: Dictionary = NetProtocol.decode(bytes)
	check(decoded.ok, "valid packet decodes")
	eq(decoded.type, "hello", "type survives roundtrip")
	eq(decoded.payload.name, "苍刃", "string survives roundtrip")
	near(decoded.payload.move.x, 0.5, 0.001, "vector x survives")
	near(decoded.payload.aim.y, -3.5, 0.001, "vector y survives")
	eq(decoded.payload.skill_q, true, "true flag survives")
	eq(decoded.payload.skill_e, false, "false flag survives")

func test_decode_rejects_malformed_or_hostile_packets() -> void:
	eq(NetProtocol.decode(PackedByteArray()).error, "empty", "empty packet rejected")
	eq(NetProtocol.decode(PackedByteArray([1, 2, 3, 4])).error, "decode_failed", "garbage rejected")
	var wrong_magic: Dictionary = NetProtocol._envelope("ping", {})
	wrong_magic.magic = 123
	eq(NetProtocol.decode(var_to_bytes(wrong_magic)).error, "bad_magic", "bad magic rejected")
	var wrong_version: Dictionary = NetProtocol._envelope("ping", {})
	wrong_version.version = NetProtocol.VERSION + 1
	eq(NetProtocol.decode(var_to_bytes(wrong_version)).error, "version_mismatch", "version mismatch rejected")
	var unknown: Dictionary = NetProtocol._envelope("nuke", {})
	eq(NetProtocol.decode(var_to_bytes(unknown)).error, "unknown_type", "unknown type rejected")
	var bad_payload: Dictionary = NetProtocol._envelope("input", "oops")
	eq(NetProtocol.decode(var_to_bytes(bad_payload)).error, "bad_payload", "non-dictionary payload rejected")
	var huge := PackedByteArray()
	huge.resize(NetProtocol.MAX_PACKET + 1)
	eq(NetProtocol.decode(huge).error, "too_large", "oversized packet rejected")
	eq(NetProtocol.decode(var_to_bytes([1, 2, 3])).error, "decode_failed", "non-envelope rejected")

func test_input_sanitizer_clamps_and_scrubs() -> void:
	var clean: Dictionary = NetProtocol.sanitize_input({
		"move": Vector2(10.0, 0.0),
		"aim": Vector2(9999.0, -9999.0),
		"attack": true,
		"skill_q": 1,
		"seq": 7,
	})
	near(clean.move.length(), 1.0, 0.001, "movement clamped to unit circle")
	near(clean.aim.x, 58.0, 0.001, "aim clamped to map bounds")
	near(clean.aim.y, -58.0, 0.001, "aim clamped negative side")
	eq(clean.attack, true, "attack flag kept")
	eq(clean.skill_q, false, "non-bool skill flag scrubbed")
	var junk: Dictionary = NetProtocol.sanitize_input({
		"move": "north",
		"aim": Vector2(NAN, INF),
		"attack": "yes",
	})
	eq(junk.move, Vector2.ZERO, "non-vector movement becomes zero")
	eq(junk.aim, Vector2.ZERO, "non-finite aim becomes zero")
	eq(junk.attack, false, "truthy string is not a bool")
	eq(junk.skill_e, false, "missing skill defaults false")

func test_name_sanitizer_trims_and_caps() -> void:
	eq(NetProtocol.sanitize_name("  Alice  "), "Alice", "name trimmed")
	eq(NetProtocol.sanitize_name(""), "玩家", "empty name falls back")
	eq(NetProtocol.sanitize_name("   "), "玩家", "blank name falls back")
	eq(NetProtocol.sanitize_name(42), "玩家", "non-string name falls back")
	var long_name: String = NetProtocol.sanitize_name("ABCDEFGHIJKLMNOPQRSTUVWXYZ")
	eq(long_name.length(), NetProtocol.MAX_NAME_LENGTH, "name capped")
	var control: String = NetProtocol.sanitize_name("A\nB\tC")
	check(not control.contains("\n") and not control.contains("\t"), "control characters removed")

func test_hello_clamps_hero_and_mode() -> void:
	var hello: Dictionary = NetProtocol.sanitize_hello({
		"name": "  星璃玩家  ",
		"hero_type": "dragon",
		"mode": "solo",
	})
	eq(hello.name, "星璃玩家", "hello keeps trimmed name")
	eq(hello.hero_type, "blade", "unknown hero becomes blade")
	eq(hello.mode, "duel", "unknown mode becomes duel")
	var valid: Dictionary = NetProtocol.sanitize_hello({"name": "Bob", "hero_type": "mage", "mode": "team"})
	eq(valid.hero_type, "mage", "valid hero kept")
	eq(valid.mode, "team", "valid mode kept")

func test_room_state_whitelists_fields_and_caps_players() -> void:
	var players: Array = []
	for i in 14:
		players.append({
			"id": i + 1,
			"name": "P%d" % i,
			"team": "blue",
			"hero_type": "mage",
			"ready": true,
			"secret": "do-not-share",
		})
	var state: Dictionary = NetProtocol.make_room_state({
		"code": "ab12c",
		"mode": "team",
		"host_id": 1,
		"started": false,
		"players": players,
		"internal_token": "hidden",
	})
	eq(state.code, "AB12C", "room code upper-cased")
	eq(state.mode, "team", "mode kept")
	eq(state.capacity, 10, "team capacity exposed")
	eq(state.players.size(), 10, "player list capped at capacity")
	check(not state.has("internal_token"), "private room fields stripped")
	check(not state.players[0].has("secret"), "private player fields stripped")
	eq(state.players[0].name, "P0", "player name kept")
	eq(state.players[0].hero_type, "mage", "player hero kept")
	var duel: Dictionary = NetProtocol.make_room_state({"code": "ZZZZZ", "mode": "duel", "players": players})
	eq(duel.players.size(), 2, "duel state capped at two")
	eq(duel.capacity, 2, "duel capacity exposed")

func test_snapshot_sanitizer_drops_junk_and_caps_entities() -> void:
	var entities: Array = []
	for i in 400:
		entities.append({
			"id": i,
			"type": "minion",
			"team": "blue",
			"x": float(i),
			"y": 0.0,
			"hp": 10.0,
			"max_hp": 10.0,
			"alive": true,
		})
	entities.append({"id": 900, "type": "dragon", "x": 0.0, "y": 0.0})
	entities.append({"id": "no", "type": "hero", "x": 0.0, "y": 0.0})
	entities.append("garbage")
	var result: Dictionary = NetProtocol.sanitize_snapshot({
		"time": 12.5,
		"mode": "duel",
		"bounds": 58.0,
		"entities": entities,
		"events": [{"type": "skill"}],
		"winner": "",
		"ended": false,
		"wave": 3,
		"scores": {"blue": 1, "red": 0},
	})
	check(result.ok, "snapshot accepted")
	var snapshot: Dictionary = result.snapshot
	eq(snapshot.entities.size(), NetProtocol.MAX_ENTITIES, "entity list capped")
	eq(snapshot.time, 12.5, "snapshot time kept")
	eq(snapshot.mode, "duel", "snapshot mode kept")
	eq(snapshot.bounds, 58.0, "snapshot bounds kept")
	eq(snapshot.events.size(), 1, "events kept")
	check(snapshot.scores.has("blue"), "scores kept")
	for entity in snapshot.entities:
		check(entity.type in NetProtocol.ENTITY_TYPES, "only known entity types survive")
		check(entity.has("id") and entity.has("x"), "entity keeps id and position")

func test_snapshot_sanitizer_requires_core_fields() -> void:
	eq(NetProtocol.sanitize_snapshot({}).ok, false, "empty snapshot rejected")
	eq(NetProtocol.sanitize_snapshot({"entities": []}).ok, false, "snapshot without bounds rejected")
	var ok: Dictionary = NetProtocol.sanitize_snapshot({"time": 0.0, "mode": "duel", "bounds": 58.0, "entities": []})
	check(ok.ok, "minimal snapshot accepted")
	eq(ok.snapshot.entities.size(), 0, "empty entity list accepted")

func test_room_code_sanitizer_accepts_short_codes_only() -> void:
	eq(NetProtocol.sanitize_room_code(" ab12c "), "AB12C", "code normalized")
	eq(NetProtocol.sanitize_room_code("AB-12C!"), "AB12C", "code strips punctuation")
	eq(NetProtocol.sanitize_room_code("ABCDEFG"), "ABCDE", "code capped at five")
	eq(NetProtocol.sanitize_room_code(""), "", "empty code stays empty")
	eq(NetProtocol.sanitize_room_code(12), "", "non-string code rejected")
