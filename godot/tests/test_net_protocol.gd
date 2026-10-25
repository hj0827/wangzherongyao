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

func test_input_sanitizer_carries_skills_targeting_and_purchases() -> void:
	var clean: Dictionary = NetProtocol.sanitize_input({
		"skill_w": true,
		"skill_r": true,
		"summoner": true,
		"attack_mode": "tower",
		"locked_target": 42,
		"buy_item": "iron_sword",
		"sell_slot": 3,
		"seq": 12,
	})
	eq(clean.skill_w, true, "skill W flag kept")
	eq(clean.skill_r, true, "skill R flag kept")
	eq(clean.summoner, true, "summoner flag kept")
	eq(clean.attack_mode, "tower", "valid attack mode kept")
	eq(clean.locked_target, 42, "locked target kept")
	eq(clean.buy_item, "iron_sword", "buy item kept")
	eq(clean.sell_slot, 3, "sell slot kept")
	eq(clean.seq, 12, "sequence kept")
	
	var hostile: Dictionary = NetProtocol.sanitize_input({
		"attack_mode": "base",
		"locked_target": -99,
		"sell_slot": 99,
		"buy_item": "x".repeat(99),
		"seq": -5,
	})
	eq(hostile.attack_mode, "default", "unknown attack mode falls back")
	eq(hostile.locked_target, -1, "negative lock clamped")
	eq(hostile.sell_slot, 5, "sell slot clamped to last inventory slot")
	eq(hostile.buy_item.length(), 32, "buy item id capped")
	eq(hostile.seq, 0, "negative sequence clamped")

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

func test_snapshot_hero_carries_skills_gold_and_inventory() -> void:
	var result: Dictionary = NetProtocol.sanitize_snapshot({
		"time": 1.0,
		"mode": "duel",
		"bounds": 58.0,
		"entities": [{
			"id": 1,
			"type": "hero",
			"team": "blue",
			"x": 0.0,
			"y": 0.0,
			"hp": 100.0,
			"max_hp": 100.0,
			"alive": true,
			"owner_id": "p1",
			"hero_type": "blade",
			"skill_w_cd": 2.5,
			"skill_r_cd": 30.0,
			"summoner_spell": "flash",
			"summoner_cd": 12.0,
			"gold": 321,
			"inventory": ["iron_sword", "boots", "not_an_item"],
			"ability_power": 40.0,
			"crit_rate": 0.2,
			"revealed_timer": 1.2,
			"last_input_seq": 17,
		}],
	})
	check(result.ok, "hero snapshot accepted")
	var hero: Dictionary = result.snapshot.entities[0]
	eq(hero.skill_w_cd, 2.5, "skill W cooldown survives")
	eq(hero.skill_r_cd, 30.0, "skill R cooldown survives")
	eq(hero.summoner_spell, "flash", "summoner spell survives")
	eq(hero.summoner_cd, 12.0, "summoner cooldown survives")
	eq(hero.gold, 321, "gold survives")
	eq(hero.inventory.size(), 2, "unknown item ids are dropped")
	eq(hero.inventory[0], "iron_sword", "first item survives")
	eq(hero.ability_power, 40.0, "ability power survives")
	eq(hero.crit_rate, 0.2, "crit rate survives")
	eq(hero.revealed_timer, 1.2, "reveal timer survives for bush combat")
	eq(hero.last_input_seq, 17, "acked input sequence survives for reconciliation")

func _big_snapshot_payload(count: int) -> Dictionary:
	var entities: Array = []
	for i in count:
		entities.append({
			"id": i + 1,
			"type": "minion",
			"team": "blue" if i % 2 == 0 else "red",
			"x": float(i) * 0.5,
			"y": -float(i) * 0.25,
			"hp": 320.0,
			"max_hp": 320.0,
			"alive": true,
			"lane": "mid",
			"minion_type": "melee",
			"moving": true,
			"speed": 4.2,
			"radius": 0.5,
		})
	return {
		"time": 512.5,
		"mode": "team",
		"bounds": 58.0,
		"ended": false,
		"winner": "",
		"wave": 7,
		"scores": {"blue": {"kills": 3}, "red": {"kills": 2}},
		"entities": entities,
	}

# 33KB 的整快照如果原样下发，就是 22 个 IP 分片 + 10Hz = 325KB/s 每客户端。
# 压缩是「丢包代价」的前置条件：包越小，分片越少，坏一个分片整包作废的概率越低。
func test_large_snapshot_packet_is_compressed() -> void:
	var payload := _big_snapshot_payload(200)
	var raw_size: int = var_to_bytes(NetProtocol._envelope("snapshot", payload)).size()
	gt(float(raw_size), 8000.0, "测试数据本身要够大，否则压缩无从谈起")
	var bytes: PackedByteArray = NetProtocol.encode("snapshot", payload)
	check(NetProtocol.is_compressed_frame(bytes), "大快照走压缩帧")
	lt(float(bytes.size()), float(raw_size) / 3.0, "大快照必须压到原体积 1/3 以下")
	var decoded: Dictionary = NetProtocol.decode(bytes)
	check(decoded.ok, "压缩包能解开")
	eq(decoded.type, "snapshot", "压缩后类型不变")
	eq(decoded.payload.entities.size(), 200, "压缩后实体一个不少")
	near(float(decoded.payload.entities[199].x), 99.5, 0.001, "压缩后数值不变")
	eq(decoded.payload.entities[1].team, "red", "压缩后字符串不变")

func test_small_control_packets_skip_compression() -> void:
	var bytes: PackedByteArray = NetProtocol.encode("ping", {})
	check(not NetProtocol.is_compressed_frame(bytes), "小包不压缩，保持原始 var_to_bytes 格式")
	var decoded: Dictionary = NetProtocol.decode(bytes)
	check(decoded.ok, "未压缩包照旧能解")
	eq(decoded.type, "ping", "未压缩包类型正确")

func test_corrupt_or_lying_compressed_frames_are_rejected() -> void:
	var bytes: PackedByteArray = NetProtocol.encode("snapshot", _big_snapshot_payload(200))
	var lying: PackedByteArray = bytes.duplicate()
	# 原始长度字段被改成超大值：不能按这个值去分配/解压（防放大攻击）。
	lying.encode_u32(1, NetProtocol.MAX_PACKET * 4)
	check(not bool(NetProtocol.decode(lying).get("ok", false)), "谎报原始长度的包必须拒绝")
	var truncated: PackedByteArray = bytes.slice(0, 12)
	check(not bool(NetProtocol.decode(truncated).get("ok", false)), "被截断的压缩包必须拒绝")
	var header_only := PackedByteArray([1, 0, 0, 0, 0])
	check(not bool(NetProtocol.decode(header_only).get("ok", false)), "只有帧头的包必须拒绝")

func test_event_packet_sanitizer_keeps_whitelisted_fields_only() -> void:
	var clean: Dictionary = NetProtocol.sanitize_events({
		"time": 33.0,
		"events": [
			{"type": "skill_cast", "hero_type": "blade", "slot": "w", "x": 1.0, "y": 2.0, "aim_x": 3.0, "aim_y": 4.0, "secret": "nope"},
			"garbage",
			{"type": "match_end", "winner": "blue"},
		],
	})
	near(clean.time, 33.0, 0.001, "事件包带时间戳")
	eq(clean.events.size(), 2, "非字典事件被丢弃")
	check(not clean.events[0].has("secret"), "白名单外字段被剥掉")
	eq(clean.events[0].type, "skill_cast", "类型保留")
	near(float(clean.events[0].aim_x), 3.0, 0.001, "落点保留")
	eq(clean.events[1].winner, "blue", "结算事件保留")

	var many: Array = []
	for i in 80:
		many.append({"type": "hit", "damage": 1.0})
	var capped: Dictionary = NetProtocol.sanitize_events({"time": 1.0, "events": many})
	eq(capped.events.size(), NetProtocol.MAX_EVENTS, "事件数按 MAX_EVENTS 截断")

func test_event_packet_rejects_junk_payload() -> void:
	eq(NetProtocol.sanitize_events({}).events.size(), 0, "缺 events 字段给空数组")
	eq(NetProtocol.sanitize_events({"events": "nope"}).events.size(), 0, "非数组事件给空数组")

func test_room_code_sanitizer_accepts_short_codes_only() -> void:
	eq(NetProtocol.sanitize_room_code(" ab12c "), "AB12C", "code normalized")
	eq(NetProtocol.sanitize_room_code("AB-12C!"), "AB12C", "code strips punctuation")
	eq(NetProtocol.sanitize_room_code("ABCDEFG"), "ABCDE", "code capped at five")
	eq(NetProtocol.sanitize_room_code(""), "", "empty code stays empty")
	eq(NetProtocol.sanitize_room_code(12), "", "non-string code rejected")
