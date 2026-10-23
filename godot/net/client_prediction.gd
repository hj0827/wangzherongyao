extends RefCounted

const SNAP_THRESHOLD := 4.0
const DRIFT_EPSILON := 0.02
const DECAY_RATE := 12.0 # 每秒指数衰减系数

var _current_pos := Vector2.ZERO
var _smooth_offset := Vector2.ZERO
var _next_seq := 1
var _pending_inputs: Array[Dictionary] = []

func reset(initial_pos: Vector2) -> void:
	_current_pos = initial_pos
	_smooth_offset = Vector2.ZERO
	_next_seq = 1
	_pending_inputs.clear()

func predict_input(input_data: Dictionary, dt: float) -> Vector2:
	var move: Vector2 = input_data.get("move", Vector2.ZERO)
	if move.length() > 1.0:
		move = move.normalized()
	var speed: float = float(input_data.get("speed", 6.0))
	var step := move * speed * dt
	_current_pos += step

	var record := {
		"seq": _next_seq,
		"move": move,
		"speed": speed,
		"dt": dt,
		"predicted_pos": _current_pos,
	}
	_pending_inputs.append(record)
	_next_seq += 1
	return _current_pos

func reconcile(acked_seq: int, server_pos: Vector2) -> void:
	var match_index := -1
	for i in _pending_inputs.size():
		if int(_pending_inputs[i].seq) == acked_seq:
			match_index = i
			break

	if match_index < 0:
		# 没有匹配的待决历史，直接采用权威
		if _pending_inputs.is_empty():
			var diff := server_pos - _current_pos
			if diff.length() > SNAP_THRESHOLD:
				_current_pos = server_pos
				_smooth_offset = Vector2.ZERO
			elif diff.length() > DRIFT_EPSILON:
				_smooth_offset -= diff
				_current_pos = server_pos
		return

	var historical_pred: Vector2 = _pending_inputs[match_index].predicted_pos
	var error: Vector2 = server_pos - historical_pred

	# 移除所有 <= acked_seq 的输入记录
	_pending_inputs = _pending_inputs.slice(match_index + 1)

	if error.length() > SNAP_THRESHOLD:
		# 大误差（硬控位移、瞬移）：瞬移贴齐，重放剩余输入
		_current_pos = server_pos
		_smooth_offset = Vector2.ZERO
		for item in _pending_inputs:
			_current_pos += (item.move as Vector2) * float(item.speed) * float(item.dt)
			item["predicted_pos"] = _current_pos
	elif error.length() > DRIFT_EPSILON:
		# 微小阻挡/减速误差：将误差叠加进平滑偏移，消除视觉瞬移拉扯
		_smooth_offset -= error
		_current_pos = server_pos
		for item in _pending_inputs:
			_current_pos += (item.move as Vector2) * float(item.speed) * float(item.dt)
			item["predicted_pos"] = _current_pos

func update_decay(dt: float) -> void:
	if _smooth_offset.length() > 0.001:
		_smooth_offset = _smooth_offset.lerp(Vector2.ZERO, clampf(dt * DECAY_RATE, 0.0, 1.0))
	else:
		_smooth_offset = Vector2.ZERO

func get_render_pos() -> Vector2:
	return _current_pos + _smooth_offset

func get_smooth_offset() -> Vector2:
	return _smooth_offset

func get_pending_count() -> int:
	return _pending_inputs.size()
