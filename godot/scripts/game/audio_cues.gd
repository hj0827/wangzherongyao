extends RefCounted

# 项目没有音效资源，草丛反馈用合成 PCM 生成：
# 进入是上滑的气流声，退出是下滑的轻响，短促、不抢战斗音。

const SAMPLE_RATE := 22050

static func enter_bush() -> AudioStreamWAV:
	return _sweep(0.22, 260.0, 880.0, 0.34, 0.3, 1701)

static func exit_bush() -> AudioStreamWAV:
	return _sweep(0.18, 760.0, 250.0, 0.24, 0.22, 9027)

static func _sweep(duration: float, from_hz: float, to_hz: float, noise_amount: float, gain: float, seed_value: int) -> AudioStreamWAV:
	var count := int(duration * SAMPLE_RATE)
	var data := PackedByteArray()
	data.resize(count * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var phase := 0.0
	for i in count:
		var t := float(i) / maxf(float(count - 1), 1.0)
		var frequency := lerpf(from_hz, to_hz, t)
		phase += TAU * frequency / SAMPLE_RATE
		var attack := minf(t * 14.0, 1.0)
		var envelope := attack * pow(1.0 - t, 1.5)
		var noise := rng.randf_range(-1.0, 1.0) * noise_amount
		var sample := (sin(phase) + noise) * envelope * gain
		data.encode_s16(i * 2, int(clampf(sample, -1.0, 1.0) * 32767.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = SAMPLE_RATE
	stream.stereo = false
	stream.data = data
	return stream
