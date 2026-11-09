extends "res://tests/test_base.gd"

# BGM 曲库守卫：成品音频优先、缺失回落合成、循环标记正确。
#
# 为什么需要这一层，而不是让 audio_director 直接读文件：
#   1. 5 首曲子不可能一次全部到位（生成额度、挑版本都要时间）。
#      任何一首缺失时游戏必须照常出声 —— 静音比「音色不统一」严重得多。
#   2. 交付物是 OGG，而 `AudioStreamOggVorbis` **没有** `loop_mode` 属性
#      （那是 `AudioStreamWAV` 独有）。原来 `audio_director.gd` 里那行
#      `stream.loop_mode == AudioStreamWAV.LOOP_FORWARD` 一换成 OGG 就会抛错。
#      把「这轨怎么循环」收进一个函数，子类差异才不会漏到调用点。
#   3. 每个 `load()` 都会把整首重新解码（3 分钟 ≈ 17MB PCM），
#      切场景反复加载会卡顿，必须缓存。

const LIB_PATH := "res://scripts/game/bgm_library.gd"
const DIRECTOR_PATH := "res://scripts/game/audio_director.gd"
# battle_stem 是强度叠加层，不是独立一首，单独测（见下）。
const STANDALONE_TRACKS := ["menu", "battle", "victory", "defeat"]

func _lib():
	var script = load(LIB_PATH)
	check(script != null, "bgm_library.gd 必须存在")
	return script

# ---------------------------------------------------------------- 正常路径

func test_every_standalone_track_yields_a_playable_stream() -> void:
	var Lib = _lib()
	if Lib == null:
		return
	for track_name in STANDALONE_TRACKS:
		var stream = Lib.track(track_name)
		check(stream != null, "轨道 %s 必须能返回音频流（文件或合成）" % track_name)
		if stream != null:
			check(stream.get_length() > 1.0, "轨道 %s 的音频长度应大于 1 秒，实际 %.3f" % [track_name, stream.get_length()])

func test_menu_and_battle_prefer_the_downloaded_files() -> void:
	var Lib = _lib()
	if Lib == null:
		return
	# 这两个是已经下载并转码进 assets/audio/bgm 的成品。
	# 若它们跑回合成曲，说明 ①未 --import，或 ②路径写错，两种情况都要立刻暴露。
	eq(Lib.source_of("menu"), "file", "menu 应使用下载的 OGG 成品")
	eq(Lib.source_of("battle"), "file", "battle 应使用下载的 OGG 成品")

func test_file_backed_tracks_are_marked_looping() -> void:
	var Lib = _lib()
	if Lib == null:
		return
	for track_name in ["menu", "battle"]:
		var stream = Lib.track(track_name)
		if stream == null:
			continue
		check(Lib.is_looping(stream), "轨道 %s 的成品必须标记为循环播放" % track_name)

# ---------------------------------------------------------------- 边界退化

func test_unknown_track_returns_null_instead_of_crashing() -> void:
	var Lib = _lib()
	if Lib == null:
		return
	eq(Lib.track("no_such_track"), null, "未知轨道应返回 null")
	eq(Lib.source_of("no_such_track"), "", "未知轨道不应谎报来源")

# battle 一旦换成成品曲，强度层就不能再混合成曲：
#   两首不同 BPM、不同调性的曲子叠在一起是噪音，不是「更紧张」。
func test_stem_yields_to_file_backed_battle() -> void:
	var Lib = _lib()
	if Lib == null:
		return
	eq(Lib.source_of("battle"), "file", "前置条件：battle 必须来自成品文件")
	eq(Lib.track("battle_stem"), null, "battle 用成品曲时，合成强度层必须停用，避免两首曲子叠播")

# 合成曲的胜利/失败是一次性 sting（不循环），不能被标成循环。
func test_one_shot_stings_are_not_marked_looping() -> void:
	var Lib = _lib()
	if Lib == null:
		return
	for track_name in ["victory", "defeat"]:
		var stream = Lib.track(track_name)
		if stream == null:
			continue
		check(not Lib.is_looping(stream), "轨道 %s 是一次性结算音，不应标记循环" % track_name)

# ---------------------------------------------------------------- 缓存

func test_track_is_cached_between_calls() -> void:
	var Lib = _lib()
	if Lib == null:
		return
	var first = Lib.track("menu")
	var second = Lib.track("menu")
	check(first != null and second != null, "前置条件：menu 必须可用")
	if first != null and second != null:
		check(first == second, "同一轨道重复取用必须命中缓存，否则每次切场景都重新解码")

# ---------------------------------------------------------------- 接线守卫

func test_director_routes_music_through_the_library() -> void:
	var source := FileAccess.get_file_as_string(DIRECTOR_PATH)
	check(has_live_line(source, "BgmLibrary.track("), "audio_director 必须通过 BgmLibrary 取曲，不能直接调 BgmSynth")
	check(has_live_line(source, "BgmLibrary.track(MUSIC_STEM)"), "强度层也必须走 BgmLibrary，否则成品曲会和合成 stem 叠播")

func test_director_never_reads_wav_only_properties() -> void:
	var source := FileAccess.get_file_as_string(DIRECTOR_PATH)
	# loop_mode / loop_begin 都是 AudioStreamWAV 独有；OGG 上访问即抛错。
	check(not has_live_line(source, "loop_mode"), "audio_director 不得读取 loop_mode —— AudioStreamOggVorbis 没有这个属性")
	check(not has_live_line(source, "loop_begin"), "audio_director 不得读取 loop_begin —— 同上")
