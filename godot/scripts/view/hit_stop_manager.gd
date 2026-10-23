extends RefCounted

var _freeze_timer := 0.0
var _shake_timer := 0.0
var _shake_amplitude := 0.0
var _shake_offset := Vector2.ZERO

func trigger_hit_stop(freeze_duration: float, shake_strength: float = 0.3) -> void:
	_freeze_timer = maxf(_freeze_timer, freeze_duration)
	_shake_amplitude = maxf(_shake_amplitude, shake_strength)
	_shake_timer = 0.25 # 震屏持续约 250ms
	_generate_shake()

func tick(dt: float) -> void:
	if _freeze_timer > 0.0:
		_freeze_timer = maxf(0.0, _freeze_timer - dt)
	if _shake_timer > 0.0:
		_shake_timer = maxf(0.0, _shake_timer - dt)
		_shake_amplitude = lerpf(_shake_amplitude, 0.0, clampf(dt * 10.0, 0.0, 1.0))
		_generate_shake()
	else:
		_shake_offset = Vector2.ZERO
		_shake_amplitude = 0.0

func _generate_shake() -> void:
	if _shake_amplitude > 0.001:
		var angle := randf() * TAU
		_shake_offset = Vector2(cos(angle), sin(angle)) * _shake_amplitude
	else:
		_shake_offset = Vector2.ZERO

func is_frozen() -> bool:
	return _freeze_timer > 0.0

func get_shake_offset() -> Vector2:
	return _shake_offset
