extends "res://tests/test_base.gd"

const RoomManager = preload("res://net/room_manager.gd")

func _manager() -> Object:
	return RoomManager.new()

func test_create_and_join_duel_room() -> void:
	var rooms := _manager()
	var created: Dictionary = rooms.create_room(1, "Alice", "duel")
	check(created.ok, "create succeeds")
	eq(created.room.code.length(), 5, "room code has five characters")
	eq(created.room.mode, "duel", "room mode stored")
	eq(created.room.host_id, 1, "creator is host")
	eq(created.player.team, "blue", "first player is blue")
	var joined: Dictionary = rooms.join_room(2, "Bob", created.room.code)
	check(joined.ok, "second player joins")
	eq(joined.player.team, "red", "second player is red")
	eq(joined.room.players.size(), 2, "room has two players")
	var info: Dictionary = rooms.get_room_info(created.room.code)
	eq(info.players.size(), 2, "room info lists players")

func test_room_rejects_bad_input_and_third_duel_player() -> void:
	var rooms := _manager()
	var created: Dictionary = rooms.create_room(1, "Alice", "duel")
	eq(rooms.join_room(2, "Bob", "ZZZZZ").error, "room_not_found", "unknown room rejected")
	eq(rooms.join_room(2, "Bob", created.room.code).ok, true, "second joins")
	var third: Dictionary = rooms.join_room(3, "Carol", created.room.code)
	eq(third.ok, false, "duel rejects third player")
	eq(third.error, "room_full", "duel full error")

func test_only_host_can_start_and_join_after_start_is_rejected() -> void:
	var rooms := _manager()
	var created: Dictionary = rooms.create_room(1, "Alice", "duel")
	rooms.join_room(2, "Bob", created.room.code)
	var guest_start: Dictionary = rooms.start_match(2, created.room.code)
	eq(guest_start.ok, false, "guest cannot start")
	eq(guest_start.error, "not_host", "guest start error")
	var host_start: Dictionary = rooms.start_match(1, created.room.code)
	check(host_start.ok, "host starts match")
	check(host_start.room.started, "room marked started")
	var late: Dictionary = rooms.join_room(3, "Carol", created.room.code)
	eq(late.ok, false, "late join rejected")
	eq(late.error, "already_started", "late join error")

func test_team_room_balances_ten_players_and_fills_teams() -> void:
	var rooms := _manager()
	var created: Dictionary = rooms.create_room(1, "P0", "team")
	var code: String = created.room.code
	for i in range(2, 11):
		var joined: Dictionary = rooms.join_room(i, "P%d" % (i - 1), code)
		check(joined.ok, "player %d joins 5v5" % (i - 1))
	eq(created.room.players.size(), 10, "room holds ten players")
	var blue: Array = created.room.players.filter(func(player): return player.team == "blue")
	var red: Array = created.room.players.filter(func(player): return player.team == "red")
	eq(blue.size(), 5, "five blue players")
	eq(red.size(), 5, "five red players")
	var extra: Dictionary = rooms.join_room(11, "P10", code)
	eq(extra.error, "room_full", "eleventh player rejected")

func test_room_codes_are_unique() -> void:
	var rooms := _manager()
	var codes := {}
	for i in 20:
		var created: Dictionary = rooms.create_room(i + 1, "P%d" % i, "duel")
		check(created.ok, "create unique room")
		codes[created.room.code] = true
	eq(codes.size(), 20, "all room codes unique")

func test_hero_selection_and_leave_transfer_host() -> void:
	var rooms := _manager()
	var created: Dictionary = rooms.create_room(1, "Alice", "team")
	var code: String = created.room.code
	rooms.join_room(2, "Bob", code)
	var selected: Dictionary = rooms.set_hero(2, code, "mage")
	check(selected.ok, "hero selection updated")
	eq(selected.room.players.filter(func(player): return player.id == 2)[0].hero_type, "mage", "mage selected")
	var invalid: Dictionary = rooms.set_hero(2, code, "dragon")
	eq(invalid.ok, false, "invalid hero rejected")
	eq(invalid.error, "invalid_hero", "invalid hero error")
	var left: Dictionary = rooms.leave_room(1)
	check(left.ok, "host leaves")
	eq(left.room.host_id, 2, "host transfers to next player")
	var updated: Dictionary = rooms.get_room_info(code)
	eq(updated.players.size(), 1, "one player remains")

func test_start_returns_match_config_with_bot_fill() -> void:
	var rooms := _manager()
	var created: Dictionary = rooms.create_room(1, "Alice", "team")
	var code: String = created.room.code
	rooms.join_room(2, "Bob", code)
	rooms.set_hero(1, code, "tank")
	var started: Dictionary = rooms.start_match(1, code)
	check(started.ok, "match starts")
	eq(started.config.mode, "team", "config carries mode")
	eq(started.config.humans.size(), 2, "config carries humans")
	check(started.config.bot_fill, "match config fills bots")
	var hero_types: Array = started.config.humans.map(func(human): return human.hero_type)
	check(hero_types.has("tank"), "chosen hero in config")
