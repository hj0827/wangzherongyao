extends RefCounted

# 程序化 BGM：这个项目没有任何音频资源文件，背景音乐也现场合成。
#
# 为什么不用 .ogg 素材：
#   - 仓库里一个音频文件都没有，加二进制资产会让 clone 体积和授权来源都变复杂；
#   - 合成曲可以按 BPM 精确算出小节长度，循环点能对齐到采样，不需要「差不多对齐」。
#
# 结构：
#   谱面（_battle_theme / _menu_theme …）用「第几拍」写，全部走 _add() 混进同一条
#   PackedFloat32Array。渲染完后把尾巴折回开头（_fold），再归一化到 0.85 FS。
#   折尾这一步是循环无缝的关键：不折的话，每圈都会在接缝处「哒」一下。
#
# 三条曲子对得上：
#   TRACK_BATTLE 与 TRACK_BATTLE_STEM 同 BPM、同小节数、同样点开始 —— 叠着播就是
#   「同一首曲子多一层」，所以战斗强度可以只调 STEM 的音量，不用换曲（换曲会破节奏）。

const RATE := 16000

const TRACK_MENU := "menu"
const TRACK_BATTLE := "battle"
const TRACK_BATTLE_STEM := "battle_stem"
const TRACK_VICTORY := "victory"
const TRACK_DEFEAT := "defeat"

const BPM_MENU := 76.0
const BPM_BATTLE := 100.0
# 4/4 × 4 小节。循环曲都按这个长度写，战斗曲与强度层才能逐拍对齐。
const BEATS := 16

# A 小调五声音阶（宫商角徵羽的听感），战争题材用这个调最省事：
# 怎么排都不刺耳，还能靠鼓点做出推进感。
const A4 := 440.0
const C5 := 523.25
const D5 := 587.33
const E5 := 659.25
const G5 := 783.99
const A5 := 880.0
const F4 := 349.23
const G4 := 392.0
const B4 := 493.88
const CS5 := 554.37

static var _cache: Dictionary = {}

static func track(track_name: String) -> AudioStreamWAV:
	if _cache.has(track_name):
		return _cache[track_name]
	var stream: AudioStreamWAV = null
	match track_name:
		TRACK_MENU:
			stream = _menu_theme()
		TRACK_BATTLE:
			stream = _battle_theme()
		TRACK_BATTLE_STEM:
			stream = _battle_stem()
		TRACK_VICTORY:
			stream = _victory_sting()
		TRACK_DEFEAT:
			stream = _defeat_sting()
	_cache[track_name] = stream
	return stream

static func loop_seconds(track_name: String) -> float:
	match track_name:
		TRACK_MENU:
			return float(BEATS) * 60.0 / BPM_MENU
		TRACK_BATTLE, TRACK_BATTLE_STEM:
			return float(BEATS) * 60.0 / BPM_BATTLE
	return 0.0

# ---------------------------------------------------------------- 谱面

static func _battle_theme() -> AudioStreamWAV:
	var beat := 60.0 / BPM_BATTLE
	var bar := beat * 4.0
	var seconds := loop_seconds(TRACK_BATTLE)
	var track_data := _new_track(seconds, 0.6)
	# Am - F - C - G：最稳的战争进行，每小节换一次，鼓点不用跟着变。
	var roots := [110.0, 87.31, 130.81, 98.0]
	var chords := [
		[220.0, 261.63, 329.63],
		[174.61, 220.0, 261.63],
		[261.63, 329.63, 392.0],
		[196.0, 246.94, 293.66],
	]
	var riff := [A4, C5, E5, D5, C5, E5, G5, E5]
	for b in 4:
		var at := bar * float(b)
		# 低音：八分音符不停顿，是「一直在推进」的来源。
		# 音量刻意压住：低频太满会把中高频（riff 与踩镲）埋掉，听起来就是「糊」。
		for i in 8:
			_add(track_data, at + beat * 0.5 * float(i), 0.22, {
				"freq": roots[b], "harm": [1.0, 0.35], "decay": 2.4, "gain": 0.30, "seed": 900 + b * 8 + i,
			})
		# 和声垫：一小节一个和弦，弱奏，只负责把低频与旋律黏起来。
		for freq in chords[b]:
			_add(track_data, at, bar * 0.98, {
				"freq": freq, "harm": [1.0, 0.22], "attack": 0.18, "decay": 1.0,
				"sustain": 0.55, "gain": 0.075, "detune": 0.004, "seed": 401 + int(freq),
			})
		# 主奏：固定八分音符 riff，重复本身产生记忆点。这是战斗曲的「主线」，
		# 音量必须压过低频，否则整首只剩鼓和嗡。
		for i in riff.size():
			_add(track_data, at + beat * 0.5 * float(i), 0.22, {
				"freq": riff[i], "harm": [1.0, 0.35], "attack": 0.004, "decay": 3.2,
				"gain": 0.30, "seed": 700 + i,
			})
		# 战鼓：正拍重、反拍轻，第 4 拍后半加一记花，避免机械。
		for hit in [[0.0, 0.38], [1.0, 0.22], [2.0, 0.30], [3.0, 0.22], [3.5, 0.15]]:
			_add(track_data, at + beat * float(hit[0]), 0.32, {
				"from": 68.0, "to": 42.0, "curve": 1.6, "harm": [1.0, 0.5],
				"noise": 0.34, "noise_decay": 30.0, "decay": 3.4, "gain": float(hit[1]), "seed": 1200 + b,
			})
		# 踩镲：战斗曲「亮」的来源。太轻就整首发闷，太重会盖住 riff。
		for i in 8:
			_add(track_data, at + beat * 0.5 * float(i), 0.06, {
				"harm": [], "noise": 0.9, "noise_decay": 90.0, "decay": 6.0,
				"gain": 0.17 if i % 2 == 0 else 0.10, "seed": 1500 + i,
			})
	# 镲片：每两小节一次，标记段落。
	for b in [0, 2]:
		_add(track_data, bar * float(b), 1.3, {
			"harm": [], "noise": 0.55, "noise_decay": 2.2, "attack": 0.002,
			"decay": 3.0, "gain": 0.15, "seed": 1900 + b,
		})
	return _finish(track_data, true, 0.15)

static func _battle_stem() -> AudioStreamWAV:
	var beat := 60.0 / BPM_BATTLE
	var bar := beat * 4.0
	var track_data := _new_track(loop_seconds(TRACK_BATTLE_STEM), 0.6)
	var chords := [
		[880.0, 659.25],
		[698.46, 523.25],
		[783.99, 659.25],
		[783.99, 587.33],
	]
	for b in 4:
		var at := bar * float(b)
		# 高音弦乐：只在强度层出现。音量从 -46dB 推到 -12dB 时，
		# 听感是「音乐突然紧张起来」，而不是换了一首歌。
		for freq in chords[b]:
			_add(track_data, at, bar * 0.98, {
				"freq": freq, "harm": [1.0, 0.3, 0.12], "attack": 0.3, "decay": 0.8,
				"sustain": 0.7, "gain": 0.11, "trem": 6.5, "trem_depth": 0.45,
				"detune": 0.005, "seed": 2100 + int(freq),
			})
		# 十六分沙锤：把密度再抬一档，团战时能听出「打起来了」。
		for i in 16:
			_add(track_data, at + beat * 0.25 * float(i), 0.05, {
				"harm": [], "noise": 0.8, "noise_decay": 70.0, "decay": 5.0,
				"gain": 0.055 if i % 4 == 0 else 0.032, "seed": 2400 + i,
			})
	return _finish(track_data, true, 0.11)

static func _menu_theme() -> AudioStreamWAV:
	var beat := 60.0 / BPM_MENU
	var bar := beat * 4.0
	var seconds := loop_seconds(TRACK_MENU)
	var track_data := _new_track(seconds, 1.2)
	var roots := [110.0, 87.31, 130.81, 98.0]
	var chords := [
		[220.0, 261.63, 329.63],
		[174.61, 220.0, 261.63],
		[261.63, 329.63, 392.0],
		[196.0, 246.94, 293.66],
	]
	var melody := [
		[A4, C5, E5],
		[F4, A4, C5],
		[C5, E5, G5],
		[G4, B4, D5],
	]
	for b in 4:
		var at := bar * float(b)
		# 低音铺底：一小节一口气，慢起慢落，不做节奏。
		_add(track_data, at, bar * 0.99, {
			"freq": roots[b], "harm": [1.0, 0.4], "attack": 0.55, "decay": 0.9,
			"sustain": 0.62, "gain": 0.26, "seed": 300 + b,
		})
		for freq in chords[b]:
			_add(track_data, at, bar * 0.99, {
				"freq": freq, "harm": [1.0, 0.2], "attack": 0.85, "decay": 1.1,
				"sustain": 0.5, "gain": 0.075, "detune": 0.006, "seed": 500 + int(freq),
			})
		# 稀疏拨弦：一拍半一个音，留白比音符重要。
		for i in melody[b].size():
			_add(track_data, at + beat * 1.15 * float(i), 0.85, {
				"freq": melody[b][i], "harm": [1.0, 0.3, 0.1], "attack": 0.005,
				"decay": 2.8, "gain": 0.20, "seed": 800 + i,
			})
	# 风声：整段铺满，极轻，慢速起伏。没有它，安静的小节会显得「掉线了」。
	_add(track_data, 0.0, seconds, {
		"harm": [], "noise": 0.5, "noise_decay": 0.05, "attack": 1.8,
		"decay": 0.4, "sustain": 0.9, "gain": 0.05, "trem": 0.55,
		"trem_depth": 0.55, "seed": 660,
	})
	return _finish(track_data, true, 0.11)

static func _victory_sting() -> AudioStreamWAV:
	var track_data := _new_track(4.4, 0.0)
	# 上行号角 + 大调收束：A 大三和弦，听感是「赢了」。
	for hit in [[0.0, 0.55], [0.45, 0.4], [0.9, 0.5]]:
		_add(track_data, float(hit[0]), 0.4, {
			"from": 74.0, "to": 46.0, "curve": 1.6, "harm": [1.0, 0.5],
			"noise": 0.3, "noise_decay": 26.0, "decay": 3.0, "gain": float(hit[1]), "seed": 3100,
		})
	var bells := [[0.0, A4], [0.33, CS5], [0.66, E5], [0.99, A5]]
	for bell in bells:
		_add(track_data, float(bell[0]), 1.2, {
			"freq": float(bell[1]), "harm": [1.0, 0.5, 0.28, 0.14], "attack": 0.004,
			"decay": 2.6, "gain": 0.26, "seed": 3200 + int(float(bell[1])),
		})
	for freq in [220.0, 277.18, 329.63, 440.0]:
		_add(track_data, 1.15, 3.2, {
			"freq": freq, "harm": [1.0, 0.25], "attack": 0.12, "decay": 1.2,
			"sustain": 0.45, "gain": 0.13, "detune": 0.004, "seed": 3400 + int(freq),
		})
	return _finish(track_data, false)

static func _defeat_sting() -> AudioStreamWAV:
	var track_data := _new_track(4.8, 0.0)
	# 低频闷响 + 下行三音：不解释，听就知道输了。
	_add(track_data, 0.0, 1.6, {
		"from": 58.0, "to": 38.0, "curve": 1.4, "harm": [1.0, 0.45],
		"noise": 0.3, "noise_decay": 18.0, "decay": 2.6, "gain": 0.5, "seed": 4100,
	})
	for i in 4:
		_add(track_data, 0.15, 2.6, {
			"freq": 55.0, "harm": [1.0, 0.3], "attack": 0.4, "decay": 0.9,
			"sustain": 0.5, "gain": 0.1, "seed": 4200 + i,
		})
	var bells := [[0.2, A4], [1.0, G4], [1.8, E5 * 0.5], [2.6, D5 * 0.5]]
	for bell in bells:
		_add(track_data, float(bell[0]), 1.8, {
			"freq": float(bell[1]), "harm": [1.0, 0.4, 0.2], "attack": 0.01,
			"decay": 2.2, "gain": 0.2, "seed": 4400 + int(float(bell[1])),
		})
	return _finish(track_data, false, 0.12)

# ---------------------------------------------------------------- 合成底层

static func _new_track(seconds: float, tail: float) -> Dictionary:
	var loop_len := maxi(int(round(seconds * RATE)), 2)
	var total := loop_len + int(tail * RATE)
	var buf := PackedFloat32Array()
	buf.resize(total)
	return {"buf": buf, "loop": loop_len, "total": total}

# 往 track 里叠加一个音符。spec 见各谱面的调用处：
#   freq/from/to  音高（from/to 不同即为滑音），curve 是滑音曲线
#   harm          谐波振幅数组，[] 表示纯噪声
#   noise         噪声量与衰减速率
#   attack/decay/sustain  包络
#   detune        第二个振荡器的失谐比例（做「合奏」的厚度）
#   trem/trem_depth      颤音（弦乐、风声用）
static func _add(track_data: Dictionary, at: float, duration: float, spec: Dictionary) -> void:
	var buf: PackedFloat32Array = track_data.buf
	var total := buf.size()
	var start := int(round(at * RATE))
	var count := maxi(int(duration * RATE), 1)
	var f0 := float(spec.get("freq", spec.get("from", 440.0)))
	var f1 := float(spec.get("to", f0))
	var curve := float(spec.get("curve", 1.0))
	var harm: Array = spec.get("harm", [1.0])
	var noise_amount := float(spec.get("noise", 0.0))
	var noise_decay := float(spec.get("noise_decay", 10.0))
	var attack := maxf(float(spec.get("attack", 0.005)), 0.0008)
	var decay := float(spec.get("decay", 2.0))
	var sustain := float(spec.get("sustain", 0.0))
	var gain := float(spec.get("gain", 0.3))
	var detune := float(spec.get("detune", 0.0))
	var trem := float(spec.get("trem", 0.0))
	var trem_depth := float(spec.get("trem_depth", 0.0))
	var rng := RandomNumberGenerator.new()
	rng.seed = int(spec.get("seed", 1234)) * 31 + start
	var phase := 0.0
	var phase2 := 0.0
	var last := float(maxi(count - 1, 1))
	for i in count:
		var index := start + i
		if index >= total:
			break
		var t := float(i) / last
		var freq := lerpf(f0, f1, pow(t, curve))
		var tone := 0.0
		phase += TAU * freq / RATE
		for h in harm.size():
			tone += sin(phase * float(h + 1)) * float(harm[h])
		if detune > 0.0:
			phase2 += TAU * freq * (1.0 + detune) / RATE
			tone += sin(phase2) * 0.45
		var envelope := minf(t * duration / attack, 1.0) * (sustain + (1.0 - sustain) * pow(1.0 - t, decay))
		if trem > 0.0:
			envelope *= 1.0 - trem_depth * 0.5 * (1.0 - sin(TAU * trem * t * duration))
		var sample := tone
		if noise_amount > 0.0:
			sample += rng.randf_range(-1.0, 1.0) * noise_amount * exp(-t * duration * noise_decay)
		buf[index] += sample * envelope * gain

# 把尾巴折回开头：循环点两侧就接上了，不会每圈「哒」一下。
# 响度按 **RMS** 归一，不按峰值：曲子是长音铺底 + 鼓点瞬态，按峰值归一会让
# 鼓点密的曲子整体偏轻 —— 从菜单切进战斗时听着像「音量被调小了」。
# 归一后再夹一道峰值上限，保证不和音效抢动态。
static func _finish(track_data: Dictionary, looping: bool, target_rms := 0.14) -> AudioStreamWAV:
	var buf: PackedFloat32Array = track_data.buf
	var loop_len: int = track_data.loop
	var total: int = track_data.total
	if looping:
		var tail := total - loop_len
		for i in range(0, mini(tail, loop_len)):
			buf[i] += buf[loop_len + i]
		buf.resize(loop_len)
	var peak := 0.0
	var energy := 0.0
	for value in buf:
		peak = maxf(peak, absf(value))
		energy += value * value
	var rms := sqrt(energy / maxf(float(buf.size()), 1.0))
	var scale := target_rms / maxf(rms, 0.0001)
	scale = minf(scale, 0.90 / maxf(peak, 0.0001))
	var data := PackedByteArray()
	data.resize(buf.size() * 2)
	for i in buf.size():
		data.encode_s16(i * 2, int(clampf(buf[i] * scale, -1.0, 1.0) * 32767.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = RATE
	stream.stereo = false
	stream.data = data
	if looping:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_begin = 0
		stream.loop_end = buf.size()
	return stream
