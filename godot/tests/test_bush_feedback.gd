extends "res://tests/test_base.gd"

# 草丛进出反馈契约：
# 进/出草丛要有可测试的状态迁移、镜头焦段变化与合成音效；
# HUD 显示隐匿提示，Arena 负责把三者串起来。

const MapLayout = preload("res://sim/map/map_layout.gd")
const BushFeedback = preload("res://scripts/game/bush_feedback.gd")
const AudioCues = preload("res://scripts/game/audio_cues.gd")
const Arena = preload("res://scripts/game/arena.gd")
const GameHUD = preload("res://scripts/ui/game_hud.gd")

func _outside_point() -> Vector2:
	var bush: Dictionary = MapLayout.BUSHES[0]
	return (bush.pos as Vector2) + Vector2(float(bush.radius) + 2.5, 0.0)

func test_bush_feedback_detects_enter_stay_and_exit() -> void:
	var feedback = BushFeedback.new()
	var bush_pos: Vector2 = MapLayout.BUSHES[0].pos
	eq(feedback.update(_outside_point()), "none", "草丛外没有状态迁移")
	eq(feedback.update(bush_pos), "enter", "走进草丛触发进入")
	check(feedback.in_bush, "记录在草丛内的状态")
	eq(feedback.update(bush_pos + Vector2(0.4, -0.3)), "none", "待在草丛内不重复触发")
	eq(feedback.update(_outside_point()), "exit", "离开草丛触发退出")
	check(not feedback.in_bush, "退出后状态复位")
	eq(feedback.update(_outside_point()), "none", "在草丛外继续移动不重复触发")

func test_bush_feedback_changes_camera_fov_target() -> void:
	var feedback = BushFeedback.new()
	feedback.update(MapLayout.BUSHES[0].pos)
	var inside := feedback.target_fov(42.0)
	lt(inside, 42.0, "草丛内镜头轻微拉近")
	gt(inside, 42.0 * 0.8, "拉近幅度保持轻微，不产生鱼眼感")
	feedback.update(_outside_point())
	near(feedback.target_fov(42.0), 42.0, 0.001, "草丛外恢复默认焦段")

func test_audio_cues_are_synthesized_and_distinct() -> void:
	var enter: AudioStreamWAV = AudioCues.enter_bush()
	var exit: AudioStreamWAV = AudioCues.exit_bush()
	check(enter != null and exit != null, "进出草丛各有音效")
	if enter and exit:
		eq(enter.format, AudioStreamWAV.FORMAT_16_BITS, "进入音效为 16-bit PCM")
		gt(float(enter.data.size()), 2000.0, "进入音效有实际采样数据")
		gt(float(exit.data.size()), 2000.0, "退出音效有实际采样数据")
		check(enter.data != exit.data, "进入与退出音效不同")
		eq(enter.mix_rate, AudioCues.SAMPLE_RATE, "采样率与合成配置一致")

func test_hud_shows_bush_hidden_indicator() -> void:
	var hud := GameHUD.new()
	hud.setup("p1", "blue", "blade", "你", false, false)
	hud._ready()
	check(hud._bush_label != null, "HUD 有草丛隐匿提示")
	if hud._bush_label:
		check(not hud._bush_label.visible, "默认不显示隐匿提示")
		hud.set_bush_hidden(true)
		check(hud._bush_label.visible, "进入草丛显示隐匿提示")
		check(str(hud._bush_label.text).contains("草丛"), "提示文案说明草丛")
		hud.set_bush_hidden(false)
		check(not hud._bush_label.visible, "离开草丛隐藏提示")
	hud.free()

func test_arena_bush_step_drives_camera_and_cue() -> void:
	var arena: Node3D = Arena.new()
	var cam := Camera3D.new()
	cam.fov = Arena.BASE_FOV
	arena.add_child(cam)
	arena.camera = cam
	var bush_pos: Vector2 = MapLayout.BUSHES[1].pos
	eq(arena._bush_feedback_step(bush_pos), "enter", "Arena 检测到进入草丛")
	check(arena._bush_hidden, "Arena 记录隐匿状态")
	lt(arena._camera_fov_target, Arena.BASE_FOV, "镜头目标焦段拉近")
	gt(arena._camera_fov_target, Arena.BASE_FOV * 0.8, "镜头拉近幅度保持轻微")
	check(arena._bush_cue_for("enter") != null, "进入草丛有音效")
	eq(arena._bush_feedback_step(bush_pos), "none", "草丛内停留不重复反馈")
	eq(arena._bush_feedback_step(_outside_point()), "exit", "Arena 检测到离开草丛")
	check(not arena._bush_hidden, "退出后隐匿状态复位")
	near(arena._camera_fov_target, Arena.BASE_FOV, 0.001, "镜头目标焦段恢复")
	check(arena._bush_cue_for("exit") != null, "退出草丛有音效")
	arena.free()
