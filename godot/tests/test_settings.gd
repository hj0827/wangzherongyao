extends "res://tests/test_base.gd"

## 设置系统（A4）：音量 / 画质 / 自动加点。
##
## 只测三件会静默坏掉的事：
## 1. 落盘往返丢值（ConfigFile 的键名写错不会报错，只会悄悄回默认）；
## 2. 非法存档值不钳制（手改 cfg 后音量 300% 直接炸耳膜）；
## 3. 总线没建出来（设置面板看起来能拖，实际什么都没发生）。

const GameSettings = preload("res://scripts/app/settings.gd")
const SettingsPanel = preload("res://scripts/ui/settings_panel.gd")

const TEST_PATH := "user://test_settings.cfg"

func _cleanup() -> void:
	var absolute := ProjectSettings.globalize_path(TEST_PATH)
	if FileAccess.file_exists(TEST_PATH):
		DirAccess.remove_absolute(absolute)
	GameSettings.reset_defaults()

func test_defaults_are_playable() -> void:
	_cleanup()
	GameSettings.reset_defaults()
	eq(GameSettings.master_volume, 0.8, "默认主音量")
	eq(GameSettings.music_volume, 0.7, "默认音乐音量")
	eq(GameSettings.sfx_volume, 1.0, "默认音效音量")
	eq(GameSettings.auto_skill_points, true, "默认自动加点（移动端不能逐次手点）")
	eq(GameSettings.quality, GameSettings.default_quality(), "没有存档时用平台默认画质")
	check(GameSettings.QUALITY_KEYS.has(GameSettings.quality), "默认画质必须是四档之一")

func test_quality_scales_are_ordered_and_bounded() -> void:
	eq(GameSettings.QUALITY_KEYS.size(), 4, "四档画质")
	var previous := 0.0
	for key in GameSettings.QUALITY_KEYS:
		var scale := float(GameSettings.QUALITY_SCALES[key])
		gt(scale, previous, "画质档位 %s 必须高于上一档" % key)
		check(scale > 0.0 and scale <= 1.0, "画质缩放 %s 必须在 (0, 1] 内" % key)
		previous = scale
	near(float(GameSettings.QUALITY_SCALES[GameSettings.QUALITY_ULTRA]), 1.0, 0.001, "极致档不降分辨率")

func test_save_and_load_roundtrip() -> void:
	_cleanup()
	GameSettings.master_volume = 0.35
	GameSettings.music_volume = 0.15
	GameSettings.sfx_volume = 0.90
	GameSettings.quality = GameSettings.QUALITY_HIGH
	GameSettings.auto_skill_points = false
	GameSettings.save_to(TEST_PATH)
	check(FileAccess.file_exists(TEST_PATH), "存档必须真的写到 user://")

	# 先破坏内存态，确认 load 真的读了盘，而不是碰巧保留旧值。
	GameSettings.reset_defaults()
	GameSettings.load_from(TEST_PATH)
	near(GameSettings.master_volume, 0.35, 0.001, "主音量往返")
	near(GameSettings.music_volume, 0.15, 0.001, "音乐往返")
	near(GameSettings.sfx_volume, 0.90, 0.001, "音效往返")
	eq(GameSettings.quality, GameSettings.QUALITY_HIGH, "画质往返")
	eq(GameSettings.auto_skill_points, false, "自动加点开关往返")
	_cleanup()

func test_missing_file_falls_back_to_defaults() -> void:
	_cleanup()
	GameSettings.load_from("user://definitely_not_here_%d.cfg" % Time.get_ticks_usec())
	eq(GameSettings.master_volume, 0.8, "没有存档时主音量回默认")
	eq(GameSettings.quality, GameSettings.default_quality(), "没有存档时画质回默认")
	eq(GameSettings.auto_skill_points, true, "没有存档时自动加点回默认")
	check(GameSettings.loaded, "读取失败也要标记 loaded，避免每帧重读盘")

func test_hand_edited_values_are_clamped() -> void:
	_cleanup()
	var cfg := ConfigFile.new()
	cfg.set_value("audio", "master", 3.0)
	cfg.set_value("audio", "music", -2.0)
	cfg.set_value("audio", "sfx", 0.5)
	cfg.set_value("video", "quality", "banana")
	cfg.save(TEST_PATH)

	GameSettings.load_from(TEST_PATH)
	eq(GameSettings.master_volume, 1.0, "超过 1 的音量钳到 1")
	eq(GameSettings.music_volume, 0.0, "负音量钳到 0")
	eq(GameSettings.sfx_volume, 0.5, "合法值保留")
	eq(GameSettings.quality, GameSettings.default_quality(), "未知画质档位回退到平台默认")
	_cleanup()

func test_audio_buses_are_created_and_feed_master() -> void:
	_cleanup()
	GameSettings.ensure_buses()
	for bus_name in ["Music", "SFX"]:
		var index := AudioServer.get_bus_index(bus_name)
		check(index > 0, "总线 %s 必须存在且不是 Master" % bus_name)
		if index > 0:
			eq(AudioServer.get_bus_send(index), "Master", "总线 %s 必须汇入 Master" % bus_name)
	# 幂等：重复调用不许越建越多。
	var before := AudioServer.bus_count
	GameSettings.ensure_buses()
	eq(AudioServer.bus_count, before, "重复 ensure_buses 不新增总线")

func test_apply_audio_updates_bus_volumes() -> void:
	_cleanup()
	GameSettings.master_volume = 1.0
	GameSettings.music_volume = 0.0
	GameSettings.sfx_volume = 0.5
	GameSettings.apply_audio()
	var master := AudioServer.get_bus_index("Master")
	var music := AudioServer.get_bus_index("Music")
	var sfx := AudioServer.get_bus_index("SFX")
	check(not AudioServer.is_bus_mute(master), "主音量 100% 不能静音")
	check(AudioServer.is_bus_mute(music), "音量 0 必须静音而不是 -inf dB")
	check(not AudioServer.is_bus_mute(sfx), "音效 50% 不应静音")
	near(AudioServer.get_bus_volume_db(sfx), linear_to_db(0.5), 0.01, "音效总线按线性值换算 dB")
	_cleanup()
	GameSettings.apply_audio()

func test_settings_panel_builds_without_a_tree() -> void:
	# 面板是大厅/暂停菜单共用的入口；构建期崩掉的话玩家根本看不到设置。
	_cleanup()
	var panel: Control = SettingsPanel.new()
	panel._ready()
	check(panel.get_child_count() >= 2, "设置面板必须有遮罩与内容面板")
	panel.free()
	_cleanup()

func test_apply_quality_only_touches_3d_scale() -> void:
	_cleanup()
	var viewport := SubViewport.new()
	GameSettings.quality = GameSettings.QUALITY_LOW
	GameSettings.apply_quality(viewport)
	near(viewport.scaling_3d_scale, 0.60, 0.001, "低画质把 3D 渲染缩放降到 0.6")
	GameSettings.quality = GameSettings.QUALITY_ULTRA
	GameSettings.apply_quality(viewport)
	near(viewport.scaling_3d_scale, 1.0, 0.001, "极致画质恢复原生分辨率")
	GameSettings.apply_quality(null)  # 不许崩：启动早期视口可能还没就绪
	viewport.free()
	_cleanup()
