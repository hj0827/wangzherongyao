extends Node

# 音频导演：把「事件 / 状态」翻译成实际播放的声道。
#
# 分工（重要，别合并）：
#   - `audio_plan.gd` 是纯逻辑：事件 → cue 名 + 增益，含距离衰减、冷却、单帧上限。
#     它不碰节点，所以能在 headless 测试里被断言。
#   - `audio_cues.gd` / `bgm_synth.gd` 只负责合成波形。
#   - 本文件只做三件事：持有一小组复用的 AudioStreamPlayer、跑淡入淡出、把两边接起来。
#
# 为什么是固定声道池而不是每次 new：
#   规则 4「战斗中禁止 .new()」。一次团战每秒几十次命中，每次 new 一个播放器
#   在真机上会直接掉帧。这里启动时建好 VOICE_COUNT 个，之后只换 stream 重播。
#
# 为什么 BGM 有两层：
#   TRACK_BATTLE 常驻，TRACK_BATTLE_STEM 一直播但音量从 -48dB 起。
#   打起来时推 STEM 的音量，就是「同一首曲子更紧张」，不会破拍也不会断层。

const AudioCues = preload("res://scripts/game/audio_cues.gd")
const BgmSynth = preload("res://scripts/game/bgm_synth.gd")
const AudioPlan = preload("res://scripts/game/audio_plan.gd")

const MUSIC_MENU := "menu"
const MUSIC_BATTLE := "battle"
const MUSIC_STEM := "battle_stem"
const MUSIC_VICTORY := "victory"
const MUSIC_DEFEAT := "defeat"

# 同时可发声的声道数。团战时同一帧最多 6 个（AudioPlan 的单帧上限），
# 留 10 个是为了让上一条尾音自然衰减完，不被新音硬切。
const VOICE_COUNT := 10
# 音乐常态音量。比音效低约 10dB —— BGM 是背景，不能盖住打击反馈。
const MUSIC_DB := -10.0
const STEM_DB := -13.0
# 静音电平。-48dB 在手机上等同无声，但保留淡入淡出的连续曲线。
const SILENT_DB := -48.0
# 淡入淡出速率（dB/秒）。26dB/s 走完 38dB 约 1.5 秒，进场不突兀。
const FADE_DB_PER_SEC := 26.0
# 打开暂停菜单时音乐让位（不是停播，是压低），回来立刻恢复。
const PAUSE_DUCK_DB := -8.0

var _voices: Array[AudioStreamPlayer] = []
var _music: AudioStreamPlayer
var _stem: AudioStreamPlayer
var _plan = AudioPlan.new()
var _context := {"local": -1, "x": 0.0, "y": 0.0, "team": "blue", "hp_ratio": 1.0}
var _track := ""
var _music_target := SILENT_DB
var _stem_target := SILENT_DB
var _next_voice := 0
var _paused := false
var _built := false

func _ready() -> void:
	_ensure_built()

# 首次使用时建声道池。不放在 _ready 里是因为工具/测试可能先调 play_* 再进树，
# 那种顺序下 _ready 还没跑，直接访问 _music 会空引用。
func _ensure_built() -> void:
	if _built:
		return
	_built = true
	_music = AudioStreamPlayer.new()
	_music.name = "Music"
	_music.volume_db = SILENT_DB
	add_child(_music)
	_stem = AudioStreamPlayer.new()
	_stem.name = "MusicStem"
	_stem.volume_db = SILENT_DB
	add_child(_stem)
	for i in VOICE_COUNT:
		var voice := AudioStreamPlayer.new()
		voice.name = "Voice%02d" % i
		voice.volume_db = 0.0
		add_child(voice)
		_voices.append(voice)

# ---------------------------------------------------------------- 对外接口

# 本地英雄的位置与血量。距离衰减、残血心跳、热度都靠它。
func set_context(ctx: Dictionary) -> void:
	for key in ctx:
		_context[key] = ctx[key]

# 每批事件调用一次。delta 用于推进节流时钟与热度衰减。
# 返回本批实际放出来的 cue 名（探针/日志用，正常游戏不需要）。
func handle_events(events: Array, delta: float) -> Array:
	_ensure_built()
	var played := []
	if int(_context.get("local", -1)) < 0:
		# 本地英雄还没进快照（开局第一帧）：只推进时钟，不判距离/心跳，
		# 否则所有事件都会因为坐标是 (0,0) 而被判成「很近」或「很远」。
		_plan.begin_frame(delta, {})
		return played
	var pending := _plan.begin_frame(delta, _context)
	for event in events:
		if event is Dictionary:
			pending.append_array(_plan.cues_for(event, _context))
	for item in pending:
		play_cue(str(item.get("cue", "")), float(item.get("gain_db", 0.0)))
		played.append(item.get("cue"))
	set_combat_heat(_plan.heat())
	return played

# 播一条音效。gain_db 由 AudioPlan 算好（含距离衰减）。
func play_cue(cue_name: String, gain_db := 0.0, pitch := 1.0) -> void:
	_ensure_built()
	if cue_name == "":
		return
	var stream := AudioCues.cue(cue_name)
	if stream == null:
		return
	var voice := _acquire_voice()
	voice.stream = stream
	voice.pitch_scale = pitch
	voice.volume_db = clampf(gain_db, SILENT_DB, 8.0)
	voice.play()

func play_music(track_name: String) -> void:
	_ensure_built()
	if track_name == "" or _track == track_name:
		return
	_track = track_name
	var stream := BgmSynth.track(track_name)
	if stream == null:
		return
	_music.stream = stream
	_music.volume_db = SILENT_DB
	if stream.loop_mode == AudioStreamWAV.LOOP_FORWARD:
		_music.play()
	else:
		# 结算音（胜利/失败）是一次性的：播完就停，不留空转。
		_music.play()
	_music_target = MUSIC_DB
	_start_stem(track_name == MUSIC_BATTLE)

func stop_music() -> void:
	_music_target = SILENT_DB
	_stem_target = SILENT_DB
	_track = ""

# 战斗热度 0..1：把强度层的音量推上去。由 AudioPlan.heat() 驱动。
func set_combat_heat(value: float) -> void:
	var heat := clampf(value, 0.0, 1.0)
	_stem_target = lerpf(SILENT_DB, STEM_DB, heat)

func set_paused(paused: bool) -> void:
	_paused = paused

func current_track() -> String:
	return _track

# ---------------------------------------------------------------- 内部

func _process(delta: float) -> void:
	if not _built:
		return
	var step := FADE_DB_PER_SEC * delta
	var music_target := _music_target
	if _paused:
		music_target = minf(_music_target, MUSIC_DB + PAUSE_DUCK_DB)
	_music.volume_db = move_toward(_music.volume_db, music_target, step)
	if _music.volume_db <= SILENT_DB + 0.2 and _music_target <= SILENT_DB and _music.playing:
		_music.stop()
	if _stem.playing:
		_stem.volume_db = move_toward(_stem.volume_db, _stem_target, step)

func _start_stem(enabled: bool) -> void:
	if not enabled:
		_stem_target = SILENT_DB
		if _stem.playing:
			_stem.stop()
		return
	var stream := BgmSynth.track(MUSIC_STEM)
	if stream == null:
		return
	_stem.stream = stream
	_stem.volume_db = SILENT_DB
	_stem.play()
	_stem_target = SILENT_DB

# 优先用空闲声道；都在响就用轮转的下一个（切掉最老的一条）。
func _acquire_voice() -> AudioStreamPlayer:
	for i in VOICE_COUNT:
		var index := (_next_voice + i) % VOICE_COUNT
		if not _voices[index].playing:
			_next_voice = (index + 1) % VOICE_COUNT
			return _voices[index]
	var fallback := _voices[_next_voice]
	_next_voice = (_next_voice + 1) % VOICE_COUNT
	return fallback
