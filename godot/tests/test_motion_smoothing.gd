extends "res://tests/test_base.gd"

# 移动抖动的回归测试。
#
# 背景：模拟以 30Hz 推进，渲染 60Hz+。若视觉位置用「指数平滑」
# (position.lerp(target, delta * rate)) 去追每 tick 跳变的目标，
# 速度会呈现「加速→衰减」的锯齿，肉眼就是人物一顿一顿地颤抖；
# 若相机再叠一层平滑、却用未插值的离散坐标做 look_at，
# 两者相位不一致会让整个画面持续抖动。
#
# 正确做法是实体插值：记录相邻两 tick 的位置，渲染帧按 alpha 线性插值，
# 相机刚性锁定插值后的位置。下面的断言钉住这两条。

const UnitVisual = preload("res://scripts/game/unit_visual.gd")

const TICK := 1.0 / 30.0
const FRAME := 1.0 / 60.0
const SPEED := 6.0

func _snap(pos: Vector2) -> Dictionary:
	return {
		"x": pos.x,
		"y": pos.y,
		"hp": 100.0,
		"max_hp": 100.0,
		"level": 1,
		"alive": true,
		"facing_x": 1.0,
		"facing_y": 0.0,
	}

# 驱动一个匀速前进的实体，返回每渲染帧的位移量。
func _frame_steps(frames: int) -> Array:
	var view = UnitVisual.new()
	var step_vec := Vector2(SPEED * TICK, 0.0)
	var pos := Vector2.ZERO
	# 预热：先落位，再推进一个 tick，建立 prev->cur 的插值区间。
	# 不预热的话头两帧 prev == cur，位移为 0，会被误算成抖动。
	view.set_snapshot(_snap(pos), FRAME, 1.0)
	pos += step_vec
	view.set_snapshot(_snap(pos), FRAME, 0.0)
	var alpha := 0.0
	var last: Vector3 = view.position
	var steps: Array = []
	for i in frames:
		alpha += FRAME / TICK
		if alpha >= 1.0:
			alpha -= 1.0
			pos += step_vec
		view.set_snapshot(_snap(pos), FRAME, clampf(alpha, 0.0, 1.0))
		steps.append(view.position.distance_to(last))
		last = view.position
	view.free()
	return steps

func test_interpolated_motion_has_uniform_step() -> void:
	var steps := _frame_steps(40)
	check(steps.size() >= 30, "expected enough frames, got %d" % steps.size())
	if steps.size() < 2:
		return
	var min_step: float = steps[0]
	var max_step: float = steps[0]
	var total := 0.0
	for step in steps:
		min_step = minf(min_step, step)
		max_step = maxf(max_step, step)
		total += step
	var avg := total / steps.size()
	gt(avg, 0.0, "entity should actually move")
	# 匀速插值下每帧位移应完全相等；指数平滑会产生从大到小衰减的序列。
	lt(max_step - min_step, 0.002, "frame step must stay uniform (jitter check)")
	lt(absf(avg - SPEED * FRAME), 0.002, "average speed must match simulation speed")

func test_same_tick_repeats_do_not_advance_interpolation() -> void:
	# 同一 tick 内 _sync_units 每帧都会调用 set_snapshot，
	# 若每次都推进 prev/cur，插值区间会被重置成一帧一跳（就是抖动的原始症状）。
	var view = UnitVisual.new()
	view.set_snapshot(_snap(Vector2.ZERO), FRAME, 1.0)
	view.set_snapshot(_snap(Vector2(SPEED * TICK, 0.0)), FRAME, 0.0)
	near(view.position.x, 0.0, 0.0001, "alpha=0 shows previous tick position")
	for i in 4:
		view.set_snapshot(_snap(Vector2(SPEED * TICK, 0.0)), FRAME, 0.25 * (i + 1))
	var expected: float = SPEED * TICK
	near(view.position.x, expected, 0.0001, "alpha=1 reaches current tick position")
	view.free()

func test_static_entity_does_not_drift() -> void:
	var view = UnitVisual.new()
	var pos := Vector2(3.0, -2.0)
	for i in 20:
		view.set_snapshot(_snap(pos), FRAME, float(i % 4) * 0.25)
	near(view.position.x, 3.0, 0.0001, "static x must not drift")
	near(view.position.z, -2.0, 0.0001, "static z must not drift")
	view.free()

func test_teleport_snaps_without_sliding() -> void:
	var view = UnitVisual.new()
	view.set_snapshot(_snap(Vector2.ZERO), FRAME, 1.0)
	# 超过 14 单位视为传送/复活，应直接落位而不是慢慢滑过去
	view.set_snapshot(_snap(Vector2(40.0, 0.0)), FRAME, 0.0)
	near(view.position.x, 40.0, 0.0001, "teleport must snap to destination")
	view.free()

# --- 走路动画（「拖着走」的回归守卫）---
#
# 症状：人物在走，但腿完全不动，像被拖着平移；同时整个游戏掉到 27fps 并抖动。
# 根因：moving 原先靠「本帧 target 是否变化」推断，而 target 只在模拟 tick
# 时变，同一 tick 内的后续渲染帧距离恒为 0，moving 于是在 30Hz 上反复翻转。
# _update_locomotion 每帧在 Jog / Idle 之间切一次，player.play() 每次从头
# 开始，腿永远停在第一帧；每帧对全部单位重播动画还把帧率拖垮。

func test_moving_flag_survives_same_tick_repeats() -> void:
	var view = UnitVisual.new()
	var snap := _snap(Vector2.ZERO)
	snap["moving"] = true
	view.set_snapshot(snap, FRAME, 0.0)
	check(view.moving, "snapshot moving=true must apply on the first frame")
	view.set_snapshot(snap, FRAME, 0.5)
	check(view.moving, "same-tick repeat must not flip moving to false")
	view.set_snapshot(snap, FRAME, 0.9)
	check(view.moving, "same-tick repeat must not flip moving to false (3rd)")
	var stop := _snap(Vector2.ZERO)
	stop["moving"] = false
	view.set_snapshot(stop, FRAME, 1.0)
	check(not view.moving, "moving=false from snapshot must apply immediately")
	view.free()

func test_locomotion_clip_does_not_flip_between_frames() -> void:
	var view = UnitVisual.new()
	var snap := _snap(Vector2.ZERO)
	snap["moving"] = true
	snap["speed"] = 6.4
	view.set_snapshot(snap, FRAME, 0.0)
	view.process_visual(FRAME)
	var clip: String = view.current_animation
	eq(clip, "Jog_Fwd", "moving snapshot should select the jog clip")
	for i in 6:
		view.set_snapshot(snap, FRAME, 0.1 * float(i + 1))
		view.process_visual(FRAME)
		eq(view.current_animation, clip, "locomotion clip must not flip between frames")
	view.free()

func test_locomotion_rate_scales_with_unit_speed() -> void:
	# 动画倍速跟随真实速度，否则速度快的单位会脚底打滑（拖行感）。
	var slow = UnitVisual.new()
	slow.unit_speed = 3.2
	var fast = UnitVisual.new()
	fast.unit_speed = 6.4
	var crawl = UnitVisual.new()
	crawl.unit_speed = 0.4
	near(slow.locomotion_rate_for(true), 1.0, 0.001, "reference speed plays at 1.0x")
	near(fast.locomotion_rate_for(true), 2.0, 0.001, "double speed plays at 2.0x")
	near(crawl.locomotion_rate_for(true), 1.0, 0.001, "very slow units clamp to 1.0x")
	near(fast.locomotion_rate_for(false), 1.0, 0.001, "idle always plays at 1.0x")
	slow.free()
	fast.free()
	crawl.free()

func test_stopped_entity_does_not_oscillate() -> void:
	# 症状：人一停下，整个画面开始抖（相机刚性跟随，所以人物抖 = 画面抖）。
	# 根因：停下后 target 不再前进，但 _prev_pos 还停在停步前那一格，
	# 而 alpha 每帧照旧在 0→1 回绕，位置就在这两点之间来回扫，
	# 幅度正好等于最后一格的位移 —— 60fps 下约 6 个像素，非常明显。
	var view = UnitVisual.new()
	var pos := Vector2(3.0, -2.0)
	# 走到 pos：先给出前一格，再给 pos，建立 prev->cur 区间
	view.set_snapshot(_snap(pos - Vector2(SPEED * TICK, 0.0)), FRAME, 0.0)
	view.set_snapshot(_snap(pos), FRAME, 0.0)
	view.set_snapshot(_snap(pos), FRAME, 0.5)
	# 之后模拟位置不再变，但 alpha 继续回绕
	var samples: Array = []
	for i in 24:
		view.set_snapshot(_snap(pos), FRAME, float(i % 4) * 0.25)
		samples.append(view.position.x)
	var mn: float = samples[0]
	var mx: float = samples[0]
	for v in samples:
		mn = minf(mn, float(v))
		mx = maxf(mx, float(v))
	lt(mx - mn, 0.0005, "stopped entity must not oscillate between prev and cur")
	near(view.position.x, pos.x, 0.0005, "stopped entity must settle on the sim position")
	view.free()

func test_oscillation_guard_is_not_vacuous() -> void:
	# 变异验证：用旧实现（不收敛插值区间）跑同一段输入，必然出现往复。
	var view = UnitVisual.new()
	var pos := Vector2(3.0, -2.0)
	var prev := pos - Vector2(SPEED * TICK, 0.0)
	view.set_snapshot(_snap(prev), FRAME, 0.0)
	view.set_snapshot(_snap(pos), FRAME, 0.0)
	var mn := 1.0e9
	var mx := -1.0e9
	for i in 24:
		var alpha := float(i % 4) * 0.25
		# 旧实现：无条件 lerp(prev, cur, alpha)，区间从不收拢
		view.position = Vector3(prev.x, 0.0, prev.y).lerp(Vector3(pos.x, 0.0, pos.y), alpha)
		mn = minf(mn, view.position.x)
		mx = maxf(mx, view.position.x)
	gt(mx - mn, 0.05, "legacy interpolation must visibly oscillate after stopping")
	view.free()

# 对照实验（变异验证）：证明 test_interpolated_motion_has_uniform_step 不是恒真。# 这里手写旧实现的指数平滑 position.lerp(target, delta*rate)，
# 它在同样的输入下必然产生「加速→衰减」的锯齿位移，即用户看到的颤抖。
func test_exponential_smoothing_is_measurably_jittery() -> void:
	var pos := Vector3.ZERO
	var target := Vector3.ZERO
	var last := Vector3.ZERO
	var steps: Array = []
	for i in 40:
		if i % 2 == 0:
			target.x += SPEED * TICK
		pos = pos.lerp(target, clampf(FRAME * 22.0, 0.0, 1.0))
		if i > 4:
			steps.append(pos.distance_to(last))
		last = pos
	var min_step: float = steps[0]
	var max_step: float = steps[0]
	for step in steps:
		min_step = minf(min_step, step)
		max_step = maxf(max_step, step)
	gt(max_step - min_step, 0.005, "legacy exponential smoothing must be visibly non-uniform")

# --- jitter buffer（客机联机）---

const Arena = preload("res://scripts/game/arena.gd")

func _push(arena: Object, st: float, x: float, at: float = -1.0) -> void:
	# st = 服务端时间戳（决定插值区间），at = 本地到达时刻（只用于兜底/裁剪）。
	var local_at := st
	if at >= 0.0:
		local_at = at
	arena._snapshot_buffer.append({
		"at": local_at,
		"st": st,
		"snapshot": {"time": st, "entities": [{"id": 7, "type": "hero", "owner_id": "2", "x": x, "y": 0.0}]},
	})

func test_render_snapshot_picks_pair_around_fixed_delay() -> void:
	var arena = Arena.new()
	_push(arena, 0.00, 0.0)
	_push(arena, 0.10, 1.0)
	_push(arena, 0.20, 2.0)
	_push(arena, 0.30, 3.0)

	# render_st = 最新服务端时间 - 0.16。最新 st=0.30 → render_st=0.14，
	# 落在服务端区间 [0.10, 0.20] 内，alpha 只由服务端时钟决定，与网络无关。
	arena._select_render_snapshot()
	near(arena._render_alpha, 0.4, 0.001, "alpha derived from server clock")
	eq(arena._render_prev_positions.get(7, Vector2.ONE), Vector2(1.0, 0.0), "prev entity from server segment")
	arena.free()

func test_render_snapshot_ignores_arrival_jitter() -> void:
	# 同样的服务端快照序列，本地到达间隔被抖动打乱，插值结果必须完全一致。
	var straight = Arena.new()
	_push(straight, 0.00, 0.0)
	_push(straight, 0.10, 1.0)
	_push(straight, 0.20, 2.0)
	_push(straight, 0.30, 3.0)
	straight._select_render_snapshot()
	var clean_alpha: float = straight._render_alpha

	var jittered = Arena.new()
	# 服务端时间戳完全一致，只有本地到达间隔被打乱。
	_push(jittered, 0.00, 0.0, 0.00)
	_push(jittered, 0.10, 1.0, 0.07)
	_push(jittered, 0.20, 2.0, 0.19)
	_push(jittered, 0.30, 3.0, 0.30)
	jittered._select_render_snapshot()
	near(jittered._render_alpha, clean_alpha, 0.0001, "arrival jitter must not change interpolation")
	straight.free()
	jittered.free()

func test_render_snapshot_falls_back_when_buffer_is_stale() -> void:
	var arena = Arena.new()
	_push(arena, 0.00, 0.0)
	_push(arena, 0.10, 1.0)
	# 只有一格可用（第二格还没到）：先用它自己，不插值，位置稳定
	arena._select_render_snapshot()
	near(arena._render_alpha, 1.0, 0.001, "single entry needs no interpolation")
	arena.free()


# 回城 / 传送落地：位置跳变可能只有十几米（从自家野区回城就是这种），
# 单靠 set_snapshot 里「距离 > 14 米才直接落位」的阈值兜不住 ——
# 那种情况会退化成横穿整片野区的滑行。snap_to 必须把插值区间收拢到落点。
func test_snap_to_lands_immediately_after_short_teleport() -> void:
	var landing := Vector3(-28.0, 0.0, -28.0)
	var view = UnitVisual.new()
	view.set_snapshot(_snap(Vector2(-20.0, -20.0)), FRAME, 1.0)
	view.snap_to(landing)
	view.set_snapshot(_snap(Vector2(-28.0, -28.0)), FRAME, 0.5)
	lt(view.position.distance_to(landing), 0.01, "落地当帧就在落点，不插值滑行")
	view.free()

	# 对照组：同样的跳变不调 snap_to 会停在半路 —— 证明上面那条不是恒真。
	var sliding = UnitVisual.new()
	sliding.set_snapshot(_snap(Vector2(-20.0, -20.0)), FRAME, 1.0)
	sliding.set_snapshot(_snap(Vector2(-28.0, -28.0)), FRAME, 0.5)
	gt(sliding.position.distance_to(landing), 1.0, "未落位时仍在插值中")
	sliding.free()
