extends SceneTree

const MAIN := preload("res://scenes/main_menu.tscn")

var host: Node
var guest: Node
var failures: Array[String] = []

func _initialize() -> void:
	_run()

func _wait(seconds: float) -> void:
	await create_timer(seconds).timeout

func _check(condition: bool, message: String) -> void:
	if condition:
		print("  OK   ", message)
	else:
		failures.append(message)
		print("  FAIL ", message)

func _run() -> void:
	host = MAIN.instantiate()
	root.add_child(host)
	await process_frame
	host._on_mode_pressed("duel", true)
	host.local_hero = "mage"
	host._on_hero_confirm()
	_check(host.screen == "online", "host reaches online screen")
	host._create_online_room()
	_check(host.screen == "lobby", "host enters lobby")
	_check(host.session.room_code.length() == 5, "room code created")
	var code: String = host.session.room_code
	var port: int = host.session.listen_port

	guest = MAIN.instantiate()
	root.add_child(guest)
	await process_frame
	guest._on_mode_pressed("duel", true)
	guest.local_hero = "archer"
	guest._on_hero_confirm()
	guest._join("127.0.0.1", port, code)
	await _wait(1.6)
	_check(guest.screen == "lobby", "guest enters lobby after join")
	_check(host.session.room_state.get("players", []).size() == 2, "host sees two players")

	host._choose_lobby_hero("tank")
	guest._choose_lobby_hero("archer")
	await _wait(0.8)
	var host_players: Array = host.session.room_state.get("players", [])
	var heroes := {}
	for player in host_players:
		heroes[str(player.id)] = str(player.hero_type)
	_check(heroes.get("1", "") == "tank", "host hero change synced")
	var guest_id := str(guest.session.local_peer_id)
	_check(heroes.get(guest_id, "") == "archer", "guest hero change synced")

	host._start_online_match()
	await _wait(1.2)
	_check(host.screen == "game", "host enters match")
	_check(guest.screen == "game", "guest enters match")
	_check(host._arena != null and host._arena.sim != null, "host runs authoritative sim")
	_check(guest._arena != null and guest._arena.sim == null, "guest runs remote view")

	await _wait(1.2)
	var guest_snapshot: Dictionary = guest._arena.current_snapshot
	_check(not guest_snapshot.is_empty(), "guest receives snapshots")
	var guest_hero: Dictionary = guest._arena._find_entity_by_owner(guest._arena.local_owner)
	_check(not guest_hero.is_empty(), "guest finds own hero in snapshot")
	_check(str(guest_hero.get("hero_type", "")) == "archer", "guest snapshot hero type correct")
	var host_hero: Dictionary = host._arena._find_entity_by_owner("1")
	_check(str(host_hero.get("hero_type", "")) == "tank", "host snapshot hero type correct")

	var guest_count: int = host._arena.sim.snapshot().get("entities", []).size()
	_check(guest_count > 0, "host snapshot has entities")

	guest._leave_game()
	await _wait(2.6)
	_check(host.screen == "game", "host stays in match after guest leaves")
	var bot_takeover := false
	for entity in host._arena.sim.snapshot().get("entities", []):
		if str(entity.get("owner_id", "")) == guest_id:
			print("    guest entity controller=", str(entity.get("controller", "?")), " alive=", str(entity.get("alive", "?")))
			if str(entity.get("controller", "")) == "bot":
				bot_takeover = true
	_check(bot_takeover, "host hands guest hero to AI")

	host._leave_game()
	await _wait(0.4)
	_check(host.screen == "menu", "host returns to menu")

	var host2: Node = MAIN.instantiate()
	root.add_child(host2)
	await process_frame
	host2._on_mode_pressed("team", true)
	host2.local_hero = "tank"
	host2._on_hero_confirm()
	host2._create_online_room()
	_check(host2.screen == "lobby", "second host enters lobby")
	var guest2: Node = MAIN.instantiate()
	root.add_child(guest2)
	await process_frame
	guest2._on_mode_pressed("team", true)
	guest2._on_hero_confirm()
	guest2._join("127.0.0.1", host2.session.listen_port, host2.session.room_code)
	await _wait(1.8)
	_check(guest2.screen == "lobby", "second guest reaches lobby")
	host2._leave_online()
	await _wait(4.0)
	_check(guest2.screen == "online", "guest returns to online screen after host leaves lobby")
	guest2._leave_online()
	host2.queue_free()
	guest2.queue_free()

	if failures.is_empty():
		print("UI_FLOW: ALL CHECKS PASSED")
		quit(0)
	else:
		print("UI_FLOW: %d FAILURES" % failures.size())
		quit(1)
