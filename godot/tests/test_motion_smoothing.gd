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

# 对照实验（变异验证）：证明 test_interpolated_motion_has_uniform_step 不是恒真。
# 这里手写旧实现的指数平滑 position.lerp(target, delta*rate)，
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

func _push(arena: Object, at: float, x: float) -> void:
	arena._snapshot_buffer.append({
		"at": at,
		"snapshot": {"entities": [{"id": 7, "type": "hero", "owner_id": "2", "x": x, "y": 0.0}]},
	})

func test_render_snapshot_picks_pair_around_fixed_delay() -> void:
	var arena = Arena.new()
	_push(arena, 0.00, 0.0)
	_push(arena, 0.10, 1.0)
	_push(arena, 0.20, 2.0)
	_push(arena, 0.30, 3.0)

	# render_time = now - 0.16。区间取「render_time 之后的第一个快照」与它前一格，
	# 所以 render_time 落在 [prev_at, cur_at] 内，alpha 是该区间内的比例。
	# now=0.21 → render_time=0.05 → 区间 [0.00,0.10] 中点
	arena._select_render_snapshot(0.21)
	near(arena._render_alpha, 0.5, 0.001, "render_time mid first segment")
	eq(arena._render_prev_positions.get(7, Vector2.ONE), Vector2(0.0, 0.0), "prev entity is segment start")

	# now=0.26 → render_time=0.10 → 仍是 [0.00,0.10] 的末端
	arena._select_render_snapshot(0.26)
	near(arena._render_alpha, 1.0, 0.001, "render_time at first segment end")

	# now=0.31 → render_time=0.15 → 已跨入 [0.10,0.20]
	arena._select_render_snapshot(0.31)
	near(arena._render_alpha, 0.5, 0.001, "render_time mid second segment")
	eq(arena._render_prev_positions.get(7, Vector2.ONE), Vector2(1.0, 0.0), "prev entity advanced")

	# now=0.36 → render_time=0.20 → [0.10,0.20] 末端
	arena._select_render_snapshot(0.36)
	near(arena._render_alpha, 1.0, 0.001, "render_time at second segment end")
	eq(arena._render_prev_positions.get(7, Vector2.ONE), Vector2(1.0, 0.0), "prev entity still segment start")
	arena.free()

func test_render_snapshot_survives_jittery_arrivals() -> void:
	# 快照到达不均匀（0.08 / 0.13 / 0.08 / 0.11），渲染仍按固定延迟取格。
	var arena = Arena.new()
	_push(arena, 0.00, 0.0)
	_push(arena, 0.08, 0.8)
	_push(arena, 0.21, 2.1)
	_push(arena, 0.29, 2.9)
	_push(arena, 0.40, 4.0)

	# now=0.50 → render_time=0.34，落在 [0.29, 0.40]
	arena._select_render_snapshot(0.50)
	near(arena._render_alpha, (0.34 - 0.29) / 0.11, 0.001, "alpha uses real segment span")
	eq(arena._render_prev_positions.get(7, Vector2.ONE), Vector2(2.9, 0.0), "prev from earlier arrival")

	# 渲染时刻还没攒够两格时，退回最新一格且不插值（位置稳定）
	var arena2 = Arena.new()
	_push(arena2, 0.00, 0.0)
	arena2._select_render_snapshot(0.05)
	near(arena2._render_alpha, 1.0, 0.001, "single entry needs no interpolation")
	arena.free()
	arena2.free()

func test_render_snapshot_falls_back_when_buffer_is_stale() -> void:
	var arena = Arena.new()
	_push(arena, 0.00, 0.0)
	_push(arena, 0.10, 1.0)
	# now 远超缓冲范围：用最新格，不插值，避免角色倒退
	arena._select_render_snapshot(5.0)
	near(arena._render_alpha, 1.0, 0.001, "stale buffer renders latest")
	arena.free()


