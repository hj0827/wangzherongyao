extends "res://tests/test_base.gd"
## 选人卡面的展示视频是 loop 的：那句台词每 7 秒会重念一次，很吵。
## 规则：一次选中里只念一遍 —— 第一遍带原声，之后每次循环静音；重新选中即恢复。

const Cycle = preload("res://scripts/ui/video_line_cycle.gd")

func test_first_pass_plays_the_line() -> void:
	var cycle = Cycle.new()
	eq(cycle.volume_db(), Cycle.VOICE_DB, "第一遍必须带原声")
	check(cycle.wants_voice(), "第一遍应判定为带台词")
	eq(cycle.passes(), 0, "还没走完任何一轮")

func test_second_loop_is_muted() -> void:
	var cycle = Cycle.new()
	cycle.sample(0.0)
	cycle.sample(6.9)
	var wrapped: bool = cycle.sample(0.05)
	check(wrapped, "播放位置回卷应当被识别为进入下一轮")
	eq(cycle.volume_db(), Cycle.MUTED_DB, "第二遍循环必须静音")
	eq(cycle.passes(), 1, "只过了一轮")

func test_small_backwards_jitter_is_not_a_new_pass() -> void:
	# 解码/取整会让 stream_position 偶尔回退一两帧。
	# 把它当成换轮的话，台词会在第一遍中途被静音 —— 也就是「念到一半没声了」。
	var cycle = Cycle.new()
	cycle.sample(3.00)
	cycle.sample(2.96)
	eq(cycle.passes(), 0, "0.04s 的回退不算换轮")
	eq(cycle.volume_db(), Cycle.VOICE_DB, "抖动之后仍应带原声")

func test_jitter_right_after_wrap_does_not_double_count() -> void:
	var cycle = Cycle.new()
	cycle.sample(6.90)
	cycle.sample(0.05)
	cycle.sample(0.01)
	eq(cycle.passes(), 1, "换轮后紧跟的一次回退不能重复计数")

func test_monotonic_playback_never_ends_a_pass() -> void:
	var cycle = Cycle.new()
	var position := 0.0
	for index in 300:
		position += 1.0 / 24.0
		cycle.sample(position)
	eq(cycle.passes(), 0, "一路向前播不该产生换轮")
	eq(cycle.volume_db(), Cycle.VOICE_DB, "仍在第一遍，应带原声")

func test_stays_muted_across_many_loops() -> void:
	var cycle = Cycle.new()
	cycle.sample(0.0)
	for loop_index in 5:
		cycle.sample(6.90)
		cycle.sample(0.02)
		eq(cycle.volume_db(), Cycle.MUTED_DB, "第 %d 遍循环也必须静音" % (loop_index + 2))
	eq(cycle.passes(), 5, "五遍循环应当记满五轮")

func test_reselect_restores_the_line() -> void:
	var cycle = Cycle.new()
	cycle.sample(6.90)
	cycle.sample(0.05)
	eq(cycle.volume_db(), Cycle.MUTED_DB, "先确认已经静音")
	cycle.reset()
	eq(cycle.volume_db(), Cycle.VOICE_DB, "重新选中后必须恢复原声")
	eq(cycle.passes(), 0, "轮数归零")
	check(cycle.wants_voice(), "重新选中应判定为带台词")

func test_zero_position_never_counts_as_a_wrap() -> void:
	# 视频还没真正开播时 position 恒为 0，不能判成换轮
	var cycle = Cycle.new()
	for index in 60:
		cycle.sample(0.0)
	eq(cycle.passes(), 0, "position 不动不算换轮")
	eq(cycle.volume_db(), Cycle.VOICE_DB, "仍应带原声")

func test_muted_level_is_inaudible_but_keeps_the_stream() -> void:
	# 用 -80dB 而不是停止播放：画面要一直动，只是别出声
	lt(Cycle.MUTED_DB, -60.0, "静音档必须低于 -60dB，否则还能听见")
	eq(Cycle.VOICE_DB, 0.0, "带台词时用原始音量")
