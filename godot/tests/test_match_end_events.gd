extends "res://tests/test_base.gd"

# 对局结束后的事件派发契约。
#
# 症状：结算界面（战败 / 胜利）出现后整屏一直在抖。
# 根因：match_end 是一次性事件，但 tick() 在 ended 后直接 return，不再清空 state.events；
# 而快照每次都从 state.events 复制事件，于是每个 tick 都会重放一次 match_end——
# 表现层每帧重新触发顿帧 + 震屏（随机偏移 ±0.45）+ 结算音乐，画面就成了持续抖动。
#
# 契约：事件是消费型的。谁取走谁清空，取走之后同一个 tick 内不会再被派发第二次。

const MatchSim = preload("res://sim/match_sim.gd")
const Crystal = preload("res://sim/map/crystal.gd")

func _sim() -> Object:
	return MatchSim.new({
		"mode": "duel",
		"humans": [{"id": "p1", "name": "Tester", "team": "blue", "hero_type": "blade"}],
		"bot_fill": true,
		"bot_ai": false,
	})

func _find(sim: Object, type: String, team: String, predicate := Callable()) -> Array:
	var result: Array = []
	for entity in sim.state.entities:
		if str(entity.type) != type or str(entity.team) != team:
			continue
		if predicate.is_valid() and not bool(predicate.call(entity)):
			continue
		result.append(entity)
	return result

func _has_event(events: Array, type: String) -> bool:
	for event in events:
		if event is Dictionary and str(event.get("type", "")) == type:
			return true
	return false

# 走真实路径把红方基地打掉：拆三路塔 → 破双子塔护盾 → 水晶掉血致死。
func _end_match(sim: Object) -> void:
	for tier in ["outer", "inner", "high"]:
		for tower in _find(sim, "tower", "red", func(entity): return str(entity.get("tier", "")) == tier):
			sim.apply_damage(int(tower.id), 999999.0)
	sim.tick(1.0 / 30.0)
	for guard in _find(sim, "guard", "red"):
		sim.apply_damage(int(guard.id), 999999.0)
	Crystal.tick(sim.state, 0.0)
	var base := _find(sim, "base", "red")
	sim.apply_damage(int(base[0].id), 999999.0)

func test_match_end_survives_the_frozen_tick_until_consumed() -> void:
	var sim := _sim()
	_end_match(sim)
	check(sim.ended, "基地被摧毁后对局结束")
	check(_has_event(sim.state.events, "match_end"), "结束这一帧必须产生 match_end")

	# 结束后 tick 不再推进模拟。此时事件必须仍然留着：结算表现（顿帧 / 震屏 / 音乐）
	# 就靠这一份 match_end 触发，tick 在这里顺手清空会让结算表现静默丢失。
	sim.tick(1.0 / 30.0)
	check(_has_event(sim.consume_events(), "match_end"), "结束后第一次消费仍能拿到 match_end")

	# 取走之后就不能再有。结算界面活在这段稳态里，任何重复派发都是持续抖动。
	var replays := 0
	for i in 20:
		sim.tick(1.0 / 30.0)
		if _has_event(sim.consume_events(), "match_end"):
			replays += 1
	eq(replays, 0, "消费过之后 match_end 不能每个 tick 重放")

func test_snapshot_events_stop_carrying_match_end_after_consumption() -> void:
	var sim := _sim()
	_end_match(sim)
	check(_has_event(sim.snapshot().events, "match_end"), "结束那一帧的快照带上 match_end")
	sim.consume_events()
	for i in 10:
		sim.tick(1.0 / 30.0)
		check(
			not _has_event(sim.snapshot().events, "match_end"),
			"快照每帧都从 state.events 复制，取走之后不能还带着 match_end"
		)
		sim.consume_events()

func test_consume_events_drains_the_batch() -> void:
	var sim := _sim()
	_end_match(sim)
	check(_has_event(sim.consume_events(), "match_end"), "consume_events 取走本批事件")
	eq(sim.state.events.size(), 0, "取走之后 state.events 必须清空")
	eq(sim.consume_events().size(), 0, "同一批事件不能被取走两次")

# 表现层契约：arena 必须在模拟循环内部逐 tick 取走事件。
# 只在循环外读一次快照的事件有两个后果：
#   ① 一帧补跑多个 tick 时，前面 tick 的击杀 / 结算事件被后面的 tick 覆盖 → 表现静默丢失；
#   ② 结束后 tick 不再推进，事件不会被清空 → match_end 每帧重放 → 结算界面持续抖。
func test_arena_consumes_events_inside_the_tick_loop() -> void:
	var src := FileAccess.get_file_as_string("res://scripts/game/arena.gd")
	check(
		src.contains("frame_events.append_array(sim.consume_events())"),
		"arena 必须在 tick 循环内逐 tick 取走事件"
	)
	check(src.contains("_process_events(frame_events)"), "表现层处理本帧累积的事件，而不是最后一次快照的事件")
