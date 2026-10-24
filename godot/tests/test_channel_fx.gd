extends "res://tests/test_base.gd"

# 回城 / 传送的表现契约。
#
# 这三层必须一起成立，否则会出现「机制能跑但玩家看不见/听不见」：
# 1) 模拟层：完成与打断都要发事件，且事件自带起止坐标 —— 客户端才知道在哪儿炸、给谁放音效；
# 2) 表现层：引导由快照状态机驱动，起手/结束各只触发一次（不能每帧重播，否则音效叠成一团）；
# 3) 音效层：项目没有音频资源，全部靠合成 PCM，必须有真实波形而不是一段静音。

const MatchSim = preload("res://sim/match_sim.gd")
const MapData = preload("res://sim/map_data.gd")
const MapLayout = preload("res://sim/map/map_layout.gd")
const RecallRules = preload("res://sim/map/recall.gd")
const Teleport = preload("res://sim/map/teleport.gd")
const AudioCues = preload("res://scripts/game/audio_cues.gd")
const ChannelFeedback = preload("res://scripts/game/channel_feedback.gd")
const ChannelFx = preload("res://scripts/game/channel_fx.gd")

const TICK := 1.0 / 30.0

func _sim(mode := "duel") -> Object:
	return MatchSim.new({
		"mode": mode,
		"humans": [{"id": "p1", "name": "Tester", "team": "blue", "hero_type": "blade"}],
		"bot_fill": true,
		"bot_ai": false,
	})

# state.events 每个 tick 都会被清空，必须边推进边收集。
func _run(sim: Object, ticks: int, stop_when: Callable = Callable()) -> Array:
	var collected: Array = []
	for i in ticks:
		sim.tick(TICK)
		collected.append_array(sim.state.events)
		if stop_when.is_valid() and bool(stop_when.call()):
			break
	return collected

func _events_of(events: Array, type_id: String) -> Array:
	return events.filter(func(event): return str(event.get("type", "")) == type_id)

func test_recall_completion_emits_event_with_both_ends() -> void:
	var sim := _sim()
	var hero: Dictionary = sim.get_hero_by_player("p1")
	# 出生点就在泉水里，而泉水内禁止回城，先走出去。
	hero.pos = Vector2(-20.0, -20.0)
	sim.set_input("p1", {"recall": true})
	sim.tick(TICK)
	check(bool(hero.get("recalling", false)), "离开泉水后可以开始回城")
	sim.set_input("p1", {})
	var events := _run(sim, 200, func(): return not bool(hero.get("recalling", false)))
	check(not bool(hero.get("recalling", false)), "4 秒引导后回城结束")
	var done := _events_of(events, "recall")
	eq(done.size(), 1, "回城完成发一条 recall 事件")
	if not done.is_empty():
		var event: Dictionary = done[0]
		near(float(event.get("x", 0.0)), -20.0, 0.01, "事件带起手坐标 x")
		near(float(event.get("y", 0.0)), -20.0, 0.01, "事件带起手坐标 y")
		var landing := Vector2(float(event.get("to_x", 0.0)), float(event.get("to_y", 0.0)))
		check(landing.distance_to(RecallRules.spawn_point(hero)) < 0.01, "事件带落点 = 出生点")
		check(landing.distance_to(MapData.BLUE_BASE) <= MapData.FOUNTAIN_RADIUS, "落点在己方泉水范围内")
		eq(str(event.get("team", "")), "blue", "事件带阵营，客户端据此选特效配色")
		check(event.has("hero"), "事件带英雄 id，客户端可定位模型")
	eq(_events_of(events, "recall_interrupt").size(), 0, "正常完成不应再发打断事件")

func test_recall_interrupt_emits_event_and_no_completion() -> void:
	var sim := _sim()
	var hero: Dictionary = sim.get_hero_by_player("p1")
	hero.pos = Vector2(-20.0, -20.0)
	sim.set_input("p1", {"recall": true})
	sim.tick(TICK)
	check(bool(hero.get("recalling", false)), "引导已开始")
	sim.set_input("p1", {"move": Vector2(1.0, 0.0)})
	var events := _run(sim, 2)
	check(not bool(hero.get("recalling", false)), "移动打断回城")
	eq(_events_of(events, "recall_interrupt").size(), 1, "打断发一条 recall_interrupt 事件")
	eq(_events_of(events, "recall").size(), 0, "被打断不算完成")

func test_interrupt_returns_whether_channel_was_active() -> void:
	# 打断是幂等的：重复调用不能刷出一串事件。
	var hero := {"alive": true, "team": "blue", "pos": Vector2.ZERO}
	eq(RecallRules.interrupt(hero), false, "没在引导时打断返回 false")
	check(RecallRules.start(hero), "可以开始回城")
	eq(RecallRules.interrupt(hero), true, "在引导时打断返回 true")
	eq(RecallRules.interrupt(hero), false, "重复打断返回 false")
	var tp := {"alive": true, "team": "blue", "pos": MapLayout.TELEPORT_PADS[0].pos}
	eq(Teleport.interrupt(tp), false, "没在传送引导时打断返回 false")
	check(Teleport.start(tp), "可以开始传送")
	eq(Teleport.interrupt(tp), true, "在传送引导时打断返回 true")

func test_teleport_interrupt_emits_event() -> void:
	var sim := _sim()
	var hero: Dictionary = sim.get_hero_by_player("p1")
	hero.pos = MapLayout.TELEPORT_PADS[0].pos
	sim.set_input("p1", {"teleport": true})
	sim.tick(TICK)
	check(bool(hero.get("teleporting", false)), "传送引导已开始")
	sim.apply_damage(int(hero.id), 10.0)
	# apply_damage 不在 tick 内，事件会留在 state.events 里；下一个 tick 开头会清空。
	var events: Array = sim.state.events.duplicate()
	check(not bool(hero.get("teleporting", false)), "受击打断传送")
	eq(_events_of(events, "teleport_interrupt").size(), 1, "打断发一条 teleport_interrupt 事件")
	var done := _events_of(events, "teleport")
	eq(done.size(), 0, "被打断不算传送完成")

func test_channel_feedback_reports_start_progress_and_stop() -> void:
	var feedback := ChannelFeedback.new()
	eq(feedback.update({"recalling": false}), "none", "未引导时无转换")
	eq(feedback.kind(), "", "未引导时 kind 为空")
	eq(feedback.update({"recalling": true, "recall_timer": 4.0, "recall_total": 4.0}), "recall_start", "回城起手只触发一次")
	near(feedback.progress(), 0.0, 0.001, "起手进度为 0")
	eq(feedback.update({"recalling": true, "recall_timer": 3.0, "recall_total": 4.0}), "none", "引导中不重复触发")
	near(feedback.progress(), 0.25, 0.001, "进度按剩余时间推进")
	eq(feedback.update({"recalling": true, "recall_timer": 1.0, "recall_total": 4.0}), "none", "进度推进不产生转换")
	near(feedback.progress(), 0.75, 0.001, "进度连续")
	eq(feedback.update({"recalling": false}), "recall_stop", "引导结束触发 stop")
	eq(feedback.kind(), "", "结束后 kind 清空")
	eq(feedback.update({"recalling": false}), "none", "结束后不再重复 stop")

func test_channel_feedback_prefers_teleport_and_handles_handover() -> void:
	var feedback := ChannelFeedback.new()
	eq(feedback.update({"teleporting": true, "teleport_timer": 2.5, "teleport_total": 2.5}), "teleport_start", "传送起手")
	near(feedback.progress(), 0.0, 0.001, "传送起手进度 0")
	eq(feedback.update({"teleporting": true, "teleport_timer": 1.25, "teleport_total": 2.5}), "none", "传送中不重复触发")
	near(feedback.progress(), 0.5, 0.001, "传送进度过半")
	# 同一帧两个标记都为真时传送优先：模拟层里传送会打断回城。
	eq(
		feedback.update({"teleporting": true, "teleport_timer": 1.0, "teleport_total": 2.5, "recalling": true, "recall_timer": 2.0, "recall_total": 4.0}),
		"none",
		"传送进行中不会被回城标记抢走"
	)
	eq(feedback.kind(), "teleport", "kind 仍是传送")
	# 回城切到传送：先 stop 再 start，保证法阵配色和音效跟着换。
	eq(feedback.update({"teleporting": false, "recalling": true, "recall_timer": 4.0, "recall_total": 4.0}), "recall_start", "传送结束后回城接棒")
	eq(feedback.kind(), "recall", "kind 切到回城")
	eq(feedback.update({"recalling": false, "teleporting": true, "teleport_timer": 2.5, "teleport_total": 2.5}), "teleport_start", "回城切到传送")
	eq(feedback.kind(), "teleport", "kind 切回传送")

func test_channel_feedback_ignores_broken_timers() -> void:
	var feedback := ChannelFeedback.new()
	# total 为 0 或缺失时不能除零，进度退回 0。
	eq(feedback.update({"recalling": true}), "recall_start", "缺 timer 字段也能起手")
	near(feedback.progress(), 0.0, 0.001, "缺 total 时进度为 0，不产生 NaN")
	eq(feedback.update({"recalling": true, "recall_timer": -3.0, "recall_total": 4.0}), "none", "负剩余时间不产生转换")
	near(feedback.progress(), 1.0, 0.001, "进度被夹在 1")

func test_channel_audio_cues_have_audible_waveforms() -> void:
	var cues := {
		"recall_channel": AudioCues.recall_channel(),
		"recall_done": AudioCues.recall_done(),
		"recall_break": AudioCues.recall_break(),
		"teleport_channel": AudioCues.teleport_channel(),
		"teleport_done": AudioCues.teleport_done(),
		"teleport_break": AudioCues.teleport_break(),
	}
	for name in cues:
		var stream: AudioStreamWAV = cues[name]
		check(stream != null, "%s 返回音频流" % name)
		if stream == null:
			continue
		check(stream.data.size() > 1000, "%s 有足够的采样数据" % name)
		check(stream.mix_rate > 0, "%s 采样率有效" % name)
		var peak := 0.0
		var energy := 0.0
		var count := stream.data.size() / 2
		for i in count:
			var value := absf(float(stream.data.decode_s16(i * 2)) / 32767.0)
			peak = maxf(peak, value)
			energy += value
		gt(peak, 0.05, "%s 有实际波形（不是静音）" % name)
		lt(peak, 1.001, "%s 没有削波溢出" % name)
		gt(energy / maxf(float(count), 1.0), 0.001, "%s 平均能量非零" % name)
	# 完成音必须比引导音短促：引导是铺底，完成是打击点，反过来会糊在一起。
	lt(_duration(AudioCues.recall_done()), _duration(AudioCues.recall_channel()), "回城完成音比引导音短")
	lt(_duration(AudioCues.teleport_done()), _duration(AudioCues.teleport_channel()), "传送完成音比引导音短")

func _duration(stream: AudioStreamWAV) -> float:
	if stream == null:
		return 0.0
	return float(stream.data.size() / 2) / maxf(1.0, float(stream.mix_rate))

func test_channel_fx_progress_drives_visual_parameters() -> void:
	# 法阵随进度收拢、旋转加速、光柱升高 —— 进度必须真的改变外观，否则「引导」看不出来。
	var color_recall := ChannelFx.color_for("recall")
	var color_teleport := ChannelFx.color_for("teleport")
	check(color_recall != color_teleport, "回城与传送配色不同")
	gt(ChannelFx.spin_speed("recall", 1.0), ChannelFx.spin_speed("recall", 0.0), "引导越久法阵转得越快")
	lt(ChannelFx.ring_radius("recall", 1.0), ChannelFx.ring_radius("recall", 0.0), "法阵随进度收拢")
	gt(ChannelFx.beam_height("recall", 1.0), ChannelFx.beam_height("recall", 0.0), "光柱随进度升高")
	gt(ChannelFx.particle_rate("recall", 1.0), ChannelFx.particle_rate("recall", 0.0), "粒子随进度变密")
	gt(ChannelFx.spin_speed("teleport", 0.0), ChannelFx.spin_speed("recall", 0.0), "传送法阵比回城更急促")
	for kind in ["recall", "teleport"]:
		near(ChannelFx.progress_clamped(-2.0), 0.0, 0.001, "负进度夹到 0")
		near(ChannelFx.progress_clamped(3.0), 1.0, 0.001, "超界进度夹到 1")
		gt(ChannelFx.spin_speed(kind, 0.5), 0.0, "%s 法阵始终在转" % kind)
