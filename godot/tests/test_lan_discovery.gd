extends "res://tests/test_base.gd"

const LanDiscovery = preload("res://net/lan_discovery.gd")

func _free_udp_port() -> int:
	var probe := PacketPeerUDP.new()
	probe.bind(0, "127.0.0.1")
	var port := probe.get_local_port()
	probe.close()
	return port

func _pump(discovery: Array, seconds := 2.0) -> void:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < deadline:
		for node in discovery:
			node.poll()
		OS.delay_msec(5)

func test_offer_parser_accepts_valid_offer() -> void:
	var packet: PackedByteArray = LanDiscovery.make_offer_bytes({
		"code": "ab12c",
		"name": "  Alice  ",
		"port": 24680,
		"mode": "team",
		"players": 3,
	})
	var result: Dictionary = LanDiscovery.parse_offer(packet, "192.168.1.9")
	check(result.ok, "valid offer parsed")
	eq(result.offer.code, "AB12C", "offer code normalized")
	eq(result.offer.name, "Alice", "offer name sanitized")
	eq(result.offer.ip, "192.168.1.9", "offer uses packet source ip")
	eq(result.offer.port, 24680, "offer game port kept")
	eq(result.offer.mode, "team", "offer mode kept")
	eq(result.offer.capacity, 10, "team capacity derived")
	eq(result.offer.players, 3, "player count kept")

func test_offer_parser_rejects_junk_and_unknown_magic() -> void:
	eq(LanDiscovery.parse_offer(PackedByteArray(), "127.0.0.1").ok, false, "empty offer rejected")
	eq(LanDiscovery.parse_offer("{not json".to_utf8_buffer(), "127.0.0.1").ok, false, "bad json rejected")
	eq(LanDiscovery.parse_offer("{\"magic\":\"OTHER\",\"code\":\"AB12C\"}".to_utf8_buffer(), "127.0.0.1").ok, false, "wrong magic rejected")
	eq(LanDiscovery.parse_offer(LanDiscovery.make_offer_bytes({"code": "", "port": 1}), "127.0.0.1").ok, false, "empty code rejected")
	eq(LanDiscovery.parse_offer(LanDiscovery.make_offer_bytes({"code": "AB12C", "port": 0}), "127.0.0.1").ok, false, "zero port rejected")
	eq(LanDiscovery.parse_offer(LanDiscovery.make_offer_bytes({"code": "AB12C", "port": 70000}), "127.0.0.1").ok, false, "oversized port rejected")

func test_lan_broadcast_discovers_host_offer() -> void:
	var port := _free_udp_port()
	var host := LanDiscovery.new()
	var browser := LanDiscovery.new()
	var hosting: Dictionary = host.start_advertising({
		"code": "Q7W2M",
		"name": "Alice",
		"port": 24680,
		"mode": "duel",
		"players": 1,
	}, port)
	check(hosting.ok, "host advertises")
	var browsing: Dictionary = browser.start_browsing(port, "127.0.0.1")
	check(browsing.ok, "browser starts")
	_pump([host, browser])
	eq(browser.offers.size(), 1, "browser found one host")
	if browser.offers.size() == 1:
		eq(browser.offers[0].code, "Q7W2M", "offer code shown")
		eq(browser.offers[0].name, "Alice", "offer host name shown")
		eq(browser.offers[0].port, 24680, "offer connect port")
		eq(browser.offers[0].mode, "duel", "offer mode")
	host.stop()
	browser.stop()

func test_update_advertising_refreshes_offer() -> void:
	var port := _free_udp_port()
	var host := LanDiscovery.new()
	var browser := LanDiscovery.new()
	host.start_advertising({"code": "AB12C", "name": "Alice", "port": 24680, "mode": "team", "players": 1}, port)
	var updated: Dictionary = host.update_advertising({
		"code": "AB12C",
		"name": "Alice",
		"port": 24680,
		"mode": "team",
		"players": 4,
	})
	check(updated.ok, "advertising offer can be updated")
	browser.start_browsing(port, "127.0.0.1")
	_pump([host, browser], 1.0)
	eq(browser.offers.size(), 1, "updated offer discovered")
	if browser.offers.size() == 1:
		eq(browser.offers[0].players, 4, "updated player count advertised")
	host.stop()
	browser.stop()

func test_stale_offers_expire() -> void:
	var port := _free_udp_port()
	var host := LanDiscovery.new()
	var browser := LanDiscovery.new()
	host.start_advertising({"code": "AB12C", "name": "Alice", "port": 24680, "mode": "duel", "players": 1}, port)
	browser.start_browsing(port, "127.0.0.1")
	_pump([host, browser], 1.0)
	eq(browser.offers.size(), 1, "offer discovered")
	host.stop()
	_pump([browser], 5.0)
	eq(browser.offers.size(), 0, "offer expires after host stops")
	browser.stop()
