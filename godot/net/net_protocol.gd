extends RefCounted

const HeroDefs = preload("res://sim/hero_defs.gd")
const ItemShop = preload("res://sim/item_shop.gd")

const MAGIC := 0x4D4F4241
const VERSION := 1
const MAX_PACKET := 65536
const MAX_NAME_LENGTH := 12
const MAX_ENTITIES := 256
const MAX_EVENTS := 32
const MAX_STRING := 48
const MAX_AIM := 58.0
const MODES := ["duel", "team"]
const ATTACK_MODES := ["default", "minion", "tower"]
const SUMMONER_SPELLS := ["flash", "execute", "cleanse", "heal"]
const ENTITY_TYPES := ["hero", "minion", "tower", "guard", "base", "monster"]
# 压缩帧：1 字节编解码标记 + 4 字节原始长度 + ZSTD 数据。
# 不压缩的包保持 var_to_bytes 原样，首字节是 Variant 类型号（Dictionary = 27），
# 与压缩标记 1 天然不冲突，所以两种格式在线上共存、不会误判。
# ZSTD 是三种内建算法里唯一双向都便宜的：33KB 快照压 0.35ms、解 0.04ms，
# 而 FASTLZ 解压要 11ms、DEFLATE 压缩要 8.6ms，都会在 30Hz 的主循环里露出毛刺。
const CODEC_ZSTD := 1
const CODEC_HEADER := 5
# 小于这个体积不压：控制包只有几十字节，压了反而多 5 字节帧头。
const COMPRESS_MIN_BYTES := 512
const TYPES := [
	"hello",
	"welcome",
	"room_state",
	"set_hero",
	"start_match",
	"input",
	"snapshot",
	"events",
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
	"skill_w": false,
	"skill_e": false,
	"skill_r": false,
	"summoner": false,
	"recall": false,
	"teleport": false,
	"attack_mode": "default",
	"locked_target": -1,
	"buy_item": "",
	"sell_slot": -1,
	"seq": 0,
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
	var raw: PackedByteArray = var_to_bytes(_envelope(type, payload))
	if raw.size() < COMPRESS_MIN_BYTES:
		return raw
	var packed: PackedByteArray = raw.compress(FileAccess.COMPRESSION_ZSTD)
	if packed.is_empty() or packed.size() + CODEC_HEADER >= raw.size():
		return raw
	var frame := PackedByteArray()
	frame.resize(CODEC_HEADER)
	frame[0] = CODEC_ZSTD
	frame.encode_u32(1, raw.size())
	frame.append_array(packed)
	return frame

static func is_compressed_frame(bytes: PackedByteArray) -> bool:
	return not bytes.is_empty() and int(bytes[0]) == CODEC_ZSTD

static func decode(bytes: PackedByteArray) -> Dictionary:
	if bytes.is_empty():
		return {"ok": false, "error": "empty"}
	if bytes.size() > MAX_PACKET:
		return {"ok": false, "error": "too_large"}
	var raw := bytes
	if is_compressed_frame(bytes):
		if bytes.size() <= CODEC_HEADER:
			return {"ok": false, "error": "decode_failed"}
		var original_size := int(bytes.decode_u32(1))
		# 谎报长度会直接变成一次大分配，超过上限一律当坏包。
		if original_size <= 0 or original_size > MAX_PACKET:
			return {"ok": false, "error": "decode_failed"}
		raw = bytes.slice(CODEC_HEADER).decompress(original_size, FileAccess.COMPRESSION_ZSTD)
		if raw.size() != original_size:
			return {"ok": false, "error": "decode_failed"}
	var value: Variant = bytes_to_var(raw)
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
	input.skill_w = _flag(raw.get("skill_w", false))
	input.skill_e = _flag(raw.get("skill_e", false))
	input.skill_r = _flag(raw.get("skill_r", false))
	input.summoner = _flag(raw.get("summoner", false))
	input.recall = _flag(raw.get("recall", false))
	input.teleport = _flag(raw.get("teleport", false))
	var attack_mode := str(raw.get("attack_mode", "default"))
	input.attack_mode = attack_mode if ATTACK_MODES.has(attack_mode) else "default"
	input.locked_target = clampi(int(_number(raw.get("locked_target", -1))), -1, 1000000)
	input.buy_item = _short_string(str(raw.get("buy_item", "")), 32) if raw.get("buy_item") is String else ""
	input.sell_slot = clampi(int(_number(raw.get("sell_slot", -1))), -1, 5)
	input.seq = maxi(0, int(_number(raw.get("seq", 0))))
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
			"objectives": _sanitize_objectives(data.get("objectives", {})),
			"river": _sanitize_river(data.get("river", {})),
			"board": _sanitize_board(data.get("board", {})),
		},
	}

# 离散事件包：与状态快照分开走可靠通道。
# 状态快照丢了下一格就覆盖，事件丢一次就是永久缺失（客机不会播胜利曲、不会弹播报）。
# 字段白名单复用 _sanitize_event，避免同一事件在两条路径里解析出不同结果。
static func sanitize_events(raw: Variant) -> Dictionary:
	var payload: Dictionary = raw if raw is Dictionary else {}
	var events: Array = []
	var source: Variant = payload.get("events", [])
	if source is Array:
		for item in source:
			if events.size() >= MAX_EVENTS:
				break
			var event := _sanitize_event(item)
			if not event.is_empty():
				events.append(event)
	return {
		"time": clampf(_number(payload.get("time", 0.0)), 0.0, 86400.0),
		"events": events,
	}

# 计分板账本：只放公开统计，不放坐标。
# 总量在这里按行重算，不采信对端上报的 net_worth 合计。
static func _sanitize_board(raw: Variant) -> Dictionary:
	var board := {"blue": [], "red": [], "net_worth": {"blue": 0, "red": 0}, "time": 0.0}
	if not (raw is Dictionary):
		return board
	var source: Dictionary = raw
	board["time"] = clampf(_number(source.get("time", 0.0)), 0.0, 100000.0)
	for side in ["blue", "red"]:
		var rows: Array = []
		var raw_rows: Variant = source.get(side, [])
		if raw_rows is Array:
			for item in raw_rows:
				if rows.size() >= 5:
					break
				if not (item is Dictionary):
					continue
				var row: Dictionary = item
				var hero_type := str(row.get("hero_type", "blade"))
				if not HeroDefs.is_valid(hero_type):
					hero_type = "blade"
				var inventory: Array = []
				var raw_inventory: Variant = row.get("inventory", [])
				if raw_inventory is Array:
					for item_id in raw_inventory:
						if inventory.size() >= 6:
							break
						if item_id is String and ItemShop.CATALOGUE.has(item_id):
							inventory.append(item_id)
				var gold := clampi(int(_number(row.get("gold", 0))), 0, 1000000)
				var item_value := 0
				for item_id in inventory:
					item_value += int(ItemShop.get_item(str(item_id)).get("cost", 0))
				rows.append({
					"id": clampi(int(_number(row.get("id", 0))), 0, 100000000),
					"owner_id": _short_string(str(row.get("owner_id", "")), 32),
					"name": sanitize_name(row.get("name", "")),
					"team": side,
					"hero_type": hero_type,
					"role": _short_string(str(row.get("role", "")), 12),
					"lane": _short_string(str(row.get("lane", "mid")), 12),
					"controller": _short_string(str(row.get("controller", "")), 12),
					"level": clampi(int(_number(row.get("level", 1))), 1, 30),
					"kills": clampi(int(_number(row.get("kills", 0))), 0, 9999),
					"deaths": clampi(int(_number(row.get("deaths", 0))), 0, 9999),
					"assists": clampi(int(_number(row.get("assists", 0))), 0, 9999),
					"cs": clampi(int(_number(row.get("cs", 0))), 0, 100000),
					"gold": gold,
					"net_worth": clampi(gold + item_value, 0, 2000000),
					# 经济面板的明细字段。少一项就是「客机面板永远显示 0」，
					# 而且不报错 —— 加字段时务必和 _snapshot_board 一一对齐。
					"item_value": clampi(item_value, 0, 2000000),
					"damage_dealt": clampf(_number(row.get("damage_dealt", 0.0)), 0.0, 100000000.0),
					"damage_taken": clampf(_number(row.get("damage_taken", 0.0)), 0.0, 100000000.0),
					"tower_kills": clampi(int(_number(row.get("tower_kills", 0))), 0, 99),
					"attack_damage": clampf(_number(row.get("attack_damage", 0.0)), 0.0, 100000.0),
					"ability_power": clampf(_number(row.get("ability_power", 0.0)), 0.0, 100000.0),
					"max_hp": clampf(_number(row.get("max_hp", 0.0)), 0.0, 1000000.0),
					"speed": clampf(_number(row.get("speed", 0.0)), 0.0, 100.0),
					"crit_rate": clampf(_number(row.get("crit_rate", 0.0)), 0.0, 5.0),
					"alive": _flag(row.get("alive", true)),
					"respawn_timer": clampf(_number(row.get("respawn_timer", 0.0)), 0.0, 600.0),
					"inventory": inventory,
				})
		var total := 0
		for row in rows:
			total += int(row.net_worth)
		board[side] = rows
		board.net_worth[side] = total
	return board

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
		entity["skill_w_cd"] = clampf(_number(source.get("skill_w_cd", 0.0)), 0.0, 600.0)
		entity["skill_e_cd"] = clampf(_number(source.get("skill_e_cd", 0.0)), 0.0, 600.0)
		entity["skill_r_cd"] = clampf(_number(source.get("skill_r_cd", 0.0)), 0.0, 600.0)
		var summoner_spell := str(source.get("summoner_spell", "flash"))
		if not SUMMONER_SPELLS.has(summoner_spell):
			summoner_spell = "flash"
		entity["summoner_spell"] = summoner_spell
		entity["summoner_cd"] = clampf(_number(source.get("summoner_cd", 0.0)), 0.0, 600.0)
		entity["gold"] = clampi(int(_number(source.get("gold", 0))), 0, 1000000)
		entity["cs"] = clampi(int(_number(source.get("cs", 0))), 0, 100000)
		var inventory: Array = []
		var raw_inventory: Variant = source.get("inventory", [])
		if raw_inventory is Array:
			for item in raw_inventory:
				if inventory.size() >= 6:
					break
				if item is String and ItemShop.CATALOGUE.has(item):
					inventory.append(item)
		entity["inventory"] = inventory
		entity["ability_power"] = clampf(_number(source.get("ability_power", 0.0)), 0.0, 100000.0)
		entity["crit_rate"] = clampf(_number(source.get("crit_rate", 0.0)), 0.0, 1.0)
		entity["speed"] = clampf(_number(source.get("speed", 0.0)), 0.0, 64.0)
		entity["shield"] = clampf(_number(source.get("shield", 0.0)), 0.0, 1000000.0)
		entity["facing_x"] = clampf(_number(source.get("facing_x", 1.0)), -1.0, 1.0)
		entity["facing_y"] = clampf(_number(source.get("facing_y", 0.0)), -1.0, 1.0)
		entity["attack_cd"] = clampf(_number(source.get("attack_cd", 0.0)), 0.0, 60.0)
		entity["haste_timer"] = clampf(_number(source.get("haste_timer", 0.0)), 0.0, 60.0)
		entity["slow_timer"] = clampf(_number(source.get("slow_timer", 0.0)), 0.0, 60.0)
		entity["moving"] = _flag(source.get("moving", false))
		entity["last_killer_name"] = _short_string(str(source.get("last_killer_name", "")), 32)
		entity["recalling"] = _flag(source.get("recalling", false))
		entity["recall_timer"] = clampf(_number(source.get("recall_timer", 0.0)), 0.0, 60.0)
		entity["recall_total"] = clampf(_number(source.get("recall_total", 0.0)), 0.0, 60.0)
		entity["teleporting"] = _flag(source.get("teleporting", false))
		entity["teleport_timer"] = clampf(_number(source.get("teleport_timer", 0.0)), 0.0, 60.0)
		entity["teleport_total"] = clampf(_number(source.get("teleport_total", 0.0)), 0.0, 60.0)
		entity["teleport_cd"] = clampf(_number(source.get("teleport_cd", 0.0)), 0.0, 600.0)
		entity["buff_red_timer"] = clampf(_number(source.get("buff_red_timer", 0.0)), 0.0, 600.0)
		entity["buff_blue_timer"] = clampf(_number(source.get("buff_blue_timer", 0.0)), 0.0, 600.0)
		entity["revealed_timer"] = clampf(_number(source.get("revealed_timer", 0.0)), 0.0, 60.0)
		entity["last_input_seq"] = clampi(int(_number(source.get("last_input_seq", -1))), -1, 1000000000)
	elif type == "minion":
		var lane := str(source.get("lane", "mid"))
		if lane != "top" and lane != "bottom":
			lane = "mid"
		entity["lane"] = lane
		var minion_type := str(source.get("minion_type", "melee"))
		if not ["melee", "ranged", "cannon", "super"].has(minion_type):
			minion_type = "melee"
		entity["minion_type"] = minion_type
		entity["speed"] = clampf(_number(source.get("speed", 0.0)), 0.0, 64.0)
		entity["moving"] = _flag(source.get("moving", false))
	elif type == "tower":
		var lane := str(source.get("lane", "mid"))
		if lane != "top" and lane != "bottom":
			lane = "mid"
		entity["lane"] = lane
		var tier := str(source.get("tier", "outer"))
		if not ["outer", "inner", "high"].has(tier):
			tier = "outer"
		entity["tier"] = tier
		entity["vulnerable"] = _flag(source.get("vulnerable", true))
		entity["range"] = clampf(_number(source.get("range", 0.0)), 0.0, 64.0)
	elif type == "guard":
		var guard_tier := str(source.get("tier", "twin"))
		if not ["outer", "inner", "high", "twin"].has(guard_tier):
			guard_tier = "twin"
		entity["tier"] = guard_tier
		var side := str(source.get("side", "left"))
		entity["side"] = side if side == "left" or side == "right" else "left"
		entity["vulnerable"] = _flag(source.get("vulnerable", true))
		entity["range"] = clampf(_number(source.get("range", 0.0)), 0.0, 64.0)
	elif type == "base":
		entity["vulnerable"] = _flag(source.get("vulnerable", true))
		entity["shield"] = clampf(_number(source.get("shield", 0.0)), 0.0, 1000000.0)
		entity["shield_max"] = clampf(_number(source.get("shield_max", 0.0)), 0.0, 1000000.0)
		entity["guards_alive"] = clampi(int(_number(source.get("guards_alive", 0))), 0, 2)
		# 主堡射程（9 米）：范围圈在客机上是按这个值画的，白名单漏了就会画成塔的 8 米。
		entity["range"] = clampf(_number(source.get("range", 0.0)), 0.0, 64.0)
	elif type == "monster":
		entity["monster_type"] = _short_string(str(source.get("monster_type", "wolf")), 24)
		entity["camp_id"] = _short_string(str(source.get("camp_id", "")), 32)
		var buff_type := str(source.get("buff_type", ""))
		if buff_type != "blue" and buff_type != "red":
			buff_type = ""
		entity["buff_type"] = buff_type
		entity["objective"] = _flag(source.get("objective", false))
		entity["objective_id"] = _short_string(str(source.get("objective_id", "")), 32)
		entity["name"] = sanitize_name(source.get("name", "野怪"))
		entity["respawn_timer"] = clampf(_number(source.get("respawn_timer", 0.0)), 0.0, 600.0)
	return entity

static func _sanitize_event(raw: Variant) -> Dictionary:
	if not (raw is Dictionary):
		return {}
	var source: Dictionary = raw
	var event := {}
	for key in [
		"type", "hero", "source", "target", "slot", "hero_type", "team",
		"x", "y", "aim_x", "aim_y", "target_x", "target_y", "value",
		"damage", "wave", "level", "winner", "entity_type",
		"killer", "killer_type", "killer_name", "killer_hero_type", "killer_team",
		"victim_name", "victim_hero_type", "victim_team",
		"tier", "side", "guards_left", "buff", "objective_id", "name",
		"pad", "to_x", "to_y", "spell_id", "caster_id",
		"killer_id", "victim_id", "amount", "minion_type", "source_type", "target_type",
		"announcement", "streak_title", "buy_item", "sell_slot", "crit",
	]:
		if not source.has(key):
			continue
		var value: Variant = source[key]
		if value is String:
			event[key] = _short_string(value, MAX_STRING)
		elif value is bool or value is int or value is float:
			event[key] = value
	return event

static func _sanitize_objectives(raw: Variant) -> Dictionary:
	var objectives := {"spawn_timer": 0.0, "blue_buff": 0.0, "red_buff": 0.0}
	if not (raw is Dictionary):
		return objectives
	objectives.spawn_timer = clampf(_number(raw.get("spawn_timer", 0.0)), 0.0, 3600.0)
	objectives.blue_buff = clampf(_number(raw.get("blue_buff", 0.0)), 0.0, 600.0)
	objectives.red_buff = clampf(_number(raw.get("red_buff", 0.0)), 0.0, 600.0)
	return objectives

static func _sanitize_river(raw: Variant) -> Dictionary:
	var river := {
		"spawn_timer": 0.0,
		"reveals": {"blue": [], "red": []},
	}
	if not (raw is Dictionary):
		return river
	river.spawn_timer = clampf(_number(raw.get("spawn_timer", 0.0)), 0.0, 3600.0)
	var reveals: Variant = raw.get("reveals", null)
	if not (reveals is Dictionary):
		return river
	for team in ["blue", "red"]:
		var source: Variant = reveals.get(team, [])
		if not (source is Array):
			continue
		for item in source:
			if river.reveals[team].size() >= 8:
				break
			if not (item is Dictionary):
				continue
			river.reveals[team].append({
				"x": clampf(_number(item.get("x", 0.0)), -512.0, 512.0),
				"y": clampf(_number(item.get("y", 0.0)), -512.0, 512.0),
				"radius": clampf(_number(item.get("radius", 0.0)), 0.0, 64.0),
				"timer": clampf(_number(item.get("timer", 0.0)), 0.0, 600.0),
			})
	return river

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
