extends "res://tests/test_base.gd"

# 快捷信号（验收项 11.1）的链路守卫。
# 这条链路有四个必须同时成立的环节，少一个就变成「单机能用、联机静默失效」：
#  1. 输入白名单收 ping_kind/ping_x/ping_y（客机发得出去）；
#  2. 模拟侧权威冷却 + 坐标钳制（防刷屏、防越界）；
#  3. 事件只发给同队（标点不能借敌方视野泄漏位置）；
#  4. HUD 能显示并按时过期（倒计时图标不会永远挂着）。

const MatchSim = preload("res://sim/match_sim.gd")
const NetProtocol = preload("res://net/net_protocol.gd")
const PingRules = preload("res://sim/ping_rules.gd")
const GameHUD = preload("res://scripts/ui/game_hud.gd")

func _duel() -> Dictionary:
	var sim := MatchSim.new({
		"mode": "duel",
		"humans": [
			{"id": "p1", "name": "小明", "team": "blue", "hero_type": "blade"},
			{"id": "p2", "name": "小红", "team": "red", "hero_type": "tank"},
		],
		"bot_fill": false,
	})
	return {"sim": sim, "a": sim.get_hero_by_player("p1")}

func _base_input() -> Dictionary:
	var input: Dictionary = NetProtocol.EMPTY_INPUT.duplicate()
	input["move_x"] = 0.0
	input["move_y"] = 0.0
	return input

func _pings(events: Array) -> Array:
	var out: Array = []
	for event in events:
		if event is Dictionary and str(event.get("type", "")) == "ping_mark":
			out.append(event)
	return out

# ---------------------------------------------------------------- 枚举与协议

func test_ping_kinds_have_labels_and_colors() -> void:
	eq(PingRules.KINDS.size(), 4, "四类快捷信号")
	for kind in PingRules.KINDS:
		check(PingRules.is_valid(kind), "%s 是合法信号" % kind)
		check(PingRules.label(kind) != "信号", "%s 有专属文案" % kind)
		check(PingRules.glyph(kind) != "", "%s 有小地图标记" % kind)
	check(not PingRules.is_valid("attack_now"), "自由文本不是合法信号")

func test_sanitize_input_keeps_ping_and_clamps_coordinates() -> void:
	var clean: Dictionary = NetProtocol.sanitize_input({
		"ping_kind": "attack", "ping_x": 999.0, "ping_y": -999.0,
	})
	eq(str(clean.get("ping_kind", "")), "attack", "合法信号保留")
	eq(float(clean.get("ping_x", 0.0)), NetProtocol.MAX_PING_COORD, "x 钳到地图上限")
	eq(float(clean.get("ping_y", 0.0)), -NetProtocol.MAX_PING_COORD, "y 钳到地图下限")
	var bad: Dictionary = NetProtocol.sanitize_input({"ping_kind": "free chat", "ping_x": 3.0})
	eq(str(bad.get("ping_kind", "x")), "", "非法信号被清空，不回落成默认类型")

func test_event_packet_keeps_ping_fields() -> void:
	var packet: Dictionary = NetProtocol.sanitize_events({"time": 1.0, "events": [{
		"type": "ping_mark", "team": "blue", "hero": 1, "name": "小明",
		"kind": "help", "x": 12.5, "y": -3.5,
	}]})
	var events: Array = packet.get("events", [])
	eq(events.size(), 1, "ping_mark 通过事件白名单")
	if events.size() == 1:
		eq(str(events[0].get("kind", "")), "help", "kind 透传")
		eq(str(events[0].get("name", "")), "小明", "发送者透传")
		eq(float(events[0].get("x", 0.0)), 12.5, "坐标透传")

# ---------------------------------------------------------------- 模拟侧

func test_ping_emits_team_event_with_sender_and_cooldown() -> void:
	var ctx := _duel()
	var sim: MatchSim = ctx["sim"]
	var input := _base_input()
	input["ping_kind"] = "attack"
	input["ping_x"] = 7.0
	input["ping_y"] = -3.0
	sim.set_input("p1", input)
	sim.tick(1.0 / 30.0)
	var first := _pings(sim.consume_events())
	eq(first.size(), 1, "第一次信号产生一条 ping_mark")
	if first.size() == 1:
		eq(str(first[0].get("team", "")), "blue", "带队伍，用于可见性过滤")
		eq(str(first[0].get("kind", "")), "attack", "带信号类型")
		eq(str(first[0].get("name", "")), "小明", "带发送者")
		eq(float(first[0].get("x", 0.0)), 7.0, "带落点 x")
		eq(float(first[0].get("y", 0.0)), -3.0, "带落点 y")

	# 冷却内再发：模拟侧必须去重，否则客户端 20Hz 输入会刷满地图。
	var again := _base_input()
	again["ping_kind"] = "retreat"
	again["ping_x"] = 1.0
	again["ping_y"] = 1.0
	sim.set_input("p1", again)
	sim.tick(1.0 / 30.0)
	eq(_pings(sim.consume_events()).size(), 0, "冷却内的第二条信号被权威丢弃")

	# 越过冷却后恢复。
	sim.state.time = float(sim.state.time) + MatchSim.PING_COOLDOWN + 0.1
	var third := _base_input()
	third["ping_kind"] = "missing"
	third["ping_x"] = 2.0
	third["ping_y"] = 2.0
	sim.set_input("p1", third)
	sim.tick(1.0 / 30.0)
	eq(_pings(sim.consume_events()).size(), 1, "冷却结束后可以再发")

func test_ping_is_invisible_to_enemy_even_when_point_is_visible() -> void:
	var ctx := _duel()
	var sim: MatchSim = ctx["sim"]
	var blue: Dictionary = ctx["a"]
	var red: Dictionary = sim.get_hero_by_player("p2")
	# 把标点放在红方英雄脚下：位置对红方完全可见，但信号仍不能下发。
	var event := {
		"type": "ping_mark", "team": "blue", "hero": int(blue.id), "name": "小明",
		"kind": "attack", "x": float(red.pos.x), "y": float(red.pos.y),
	}
	eq(sim.events_for("red", [event]).size(), 0, "敌方收不到标点（即使标点就在他脚下）")
	eq(sim.events_for("blue", [event]).size(), 1, "同队能收到标点")

# ---------------------------------------------------------------- HUD

func test_hud_builds_ping_entry_and_expires_markers() -> void:
	var hud := GameHUD.new()
	hud.setup("p1", "blue", "blade", "你", false, false)
	hud._ready()
	check(hud._ping_button != null, "HUD 有快捷信号入口")
	check(hud._ping_panel != null, "HUD 有四选一浮层")
	if hud._ping_panel != null:
		check(not hud._ping_panel.visible, "浮层默认收起")
		hud._show_ping_panel(true)
		check(hud._ping_panel.visible, "打开后可见")
		hud._show_ping_panel(false)
	var chosen: Array = []
	hud.ping_requested.connect(func(kind: String): chosen.append(kind))
	hud._on_ping_choice("help")
	eq(chosen, ["help"], "选择信号类型后向外发请求")
	hud.show_ping({"kind": "attack", "x": 1.0, "y": 2.0, "name": "小明"})
	eq(hud._pings.size(), 1, "收到标点后展示一条")
	hud._process(GameHUD.PING_LIFETIME + 0.1)
	eq(hud._pings.size(), 0, "超过生命周期后自动过期，不残留图标")
	hud.free()
