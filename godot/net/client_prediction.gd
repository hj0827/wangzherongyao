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
	return _predict(move, speed, dt, _next_seq, true)

# 联机版本：预测记录按服务端输入序列号归档，同一序列内的多帧合并成一条记录，
# reconcile 时才能用 acked_seq 精确找到历史位置并重放剩余输入。
func predict_at(move_input: Vector2, speed: float, dt: float, seq: int) -> Vector2:
	var move := move_input
	if move.length() > 1.0:
		move = move.normalized()
	return _predict(move, speed, dt, seq, false)

func _predict(move: Vector2, speed: float, dt: float, seq: int, auto_advance: bool) -> Vector2:
	_current_pos += move * speed * dt
	var record := _find_record(seq)
	if record.is_empty():
		_pending_inputs.append({
			"seq": seq,
			"move": move,
			"speed": speed,
			"dt": dt,
			"predicted_pos": _current_pos,
		})
	else:
		record["move"] = move
		record["speed"] = speed
		record["dt"] = float(record.dt) + dt
		record["predicted_pos"] = _current_pos
	if auto_advance:
		_next_seq += 1
	else:
		_next_seq = maxi(_next_seq, seq + 1)
	return _current_pos

func _find_record(seq: int) -> Dictionary:
	for item in _pending_inputs:
		if int(item.seq) == seq:
			return item
	return {}

func reconcile(acked_seq: int, server_pos: Vector2) -> void:
	var match_index := -1
	for i in _pending_inputs.size():
		if int(_pending_inputs[i].seq) == acked_seq:
			match_index = i
			break

	if match_index < 0:
		# 没有匹配的待决历史（刚重置、购买序列跳跃或服务端确认了未预测的输入）：
		# 以服务端位置为基准重放剩余输入，再按新旧渲染位置差补偿，避免视觉跳变。
		var kept: Array[Dictionary] = []
		for item in _pending_inputs:
			if int(item.seq) > acked_seq:
				kept.append(item)
		_pending_inputs = kept
		var old_render := get_render_pos()
		_current_pos = server_pos
		for item in _pending_inputs:
			_current_pos += (item.move as Vector2) * float(item.speed) * float(item.dt)
			item["predicted_pos"] = _current_pos
		var drift := old_render - _current_pos
		if drift.length() > SNAP_THRESHOLD:
			_smooth_offset = Vector2.ZERO
		else:
			_smooth_offset = drift
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
