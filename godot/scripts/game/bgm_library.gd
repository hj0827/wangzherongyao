extends RefCounted

# BGM 曲库：成品音频优先，缺失则回落到程序化合成。
#
# 为什么要有这一层
# ----------------
# 1. 5 首曲子不可能一次全部到位（生成额度、挑版本都要时间）。
#    任何一首缺失时游戏必须照常出声 —— 静音比「音色不统一」严重得多。
# 2. 播放器不应该关心「这轨是 OGG 还是合成 WAV」。
#    `AudioStreamOggVorbis` 没有 `loop_mode`（那是 `AudioStreamWAV` 独有），
#    把子类差异收在本文件，调用点就不会踩到「属性不存在」的运行时错误。
# 3. 每次 `load()` 都会把整首重新解码（3 分钟 ≈ 17MB PCM），
#    切场景反复加载会卡顿，必须缓存。
#
# 成品文件的来源与加工
# --------------------
# `godot/assets/audio/bgm/<track>.ogg`，48kHz 立体声 OGG Vorbis。
# 首尾已做 4 秒交叉淡化，循环接缝实测跳变 0.02%（menu）/ 1.9%（battle），
# 都低于曲内相邻样本的正常步进，听不出断点。

const BgmSynth = preload("res://scripts/game/bgm_synth.gd")

const BGM_DIR := "res://assets/audio/bgm"

# 需要循环播放的轨道。victory / defeat 是一次性结算 sting，不能标循环。
const LOOPING_TRACKS := ["menu", "battle", "battle_stem"]

# battle_stem 是「同一首曲子更紧张」的叠加层：
# 原设计与 battle 同 BPM 同调、逐采样对齐，所以叠播成立。
# 一旦 battle 换成外部成品曲，合成 stem 的 BPM/调性必然对不上，
# 两首不同曲子同时播是噪音而不是紧张感 —— 此时必须停用 stem。
const STEM_TRACK := "battle_stem"
const STEM_HOST := "battle"

static var _cache := {}
static var _source := {}

# 取一轨音频。找不到文件就回落合成；两者都没有则返回 null（调用方应静默跳过）。
static func track(track_name: String) -> AudioStream:
	if track_name == "":
		return null
	if _cache.has(track_name):
		return _cache[track_name]

	var stream: AudioStream = null
	var origin := ""

	var file_path := file_path_for(track_name)
	if ResourceLoader.exists(file_path):
		stream = load(file_path)
		if stream != null:
			if LOOPING_TRACKS.has(track_name):
				_set_loop(stream, true)
			origin = "file"

	if stream == null:
		stream = _synth_fallback(track_name)
		if stream != null:
			origin = "synth"

	_cache[track_name] = stream
	_source[track_name] = origin
	return stream

# 这一轨当前的实际来源："file" / "synth" / ""（不可用）。
# 探针与测试用；也用于判断 battle 是否已经把 stem 顶掉。
static func source_of(track_name: String) -> String:
	if not _source.has(track_name):
		track(track_name)
	return str(_source.get(track_name, ""))

# 该轨道是否循环播放。
# 子类属性名不同，这里统一判定，调用点不要再自己摸 loop_mode。
static func is_looping(stream: AudioStream) -> bool:
	if stream is AudioStreamWAV:
		return stream.loop_mode == AudioStreamWAV.LOOP_FORWARD
	if stream is AudioStreamOggVorbis:
		return stream.loop
	if stream is AudioStreamMP3:
		return stream.loop
	return false

static func file_path_for(track_name: String) -> String:
	return "%s/%s.ogg" % [BGM_DIR, track_name]

# 清空缓存。切换曲库/测试隔离用。
static func clear_cache() -> void:
	_cache.clear()
	_source.clear()

# ---------------------------------------------------------------- 内部

static func _synth_fallback(track_name: String) -> AudioStream:
	if track_name == STEM_TRACK and source_of(STEM_HOST) == "file":
		# battle 已有成品曲：合成 stem 直接让位，避免两首曲子叠播。
		return null
	return BgmSynth.track(track_name)

static func _set_loop(stream: AudioStream, enabled: bool) -> void:
	if stream is AudioStreamOggVorbis:
		stream.loop = enabled
	elif stream is AudioStreamMP3:
		stream.loop = enabled
