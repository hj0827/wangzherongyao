class_name GameSettings
extends RefCounted

## 玩家设置：音量、画质、自动加点。
## 只落盘到 user://settings.cfg；桌面上任何一项都不会改变键鼠操作。

const PATH := "user://settings.cfg"
const CONFIG_VERSION := 1

const QUALITY_LOW := "low"
const QUALITY_MEDIUM := "medium"
const QUALITY_HIGH := "high"
const QUALITY_ULTRA := "ultra"
const QUALITY_KEYS := [QUALITY_LOW, QUALITY_MEDIUM, QUALITY_HIGH, QUALITY_ULTRA]
const QUALITY_NAMES := {
	QUALITY_LOW: "低",
	QUALITY_MEDIUM: "中",
	QUALITY_HIGH: "高",
	QUALITY_ULTRA: "极致",
}
const QUALITY_SCALES := {
	QUALITY_LOW: 0.60,
	QUALITY_MEDIUM: 0.72,
	QUALITY_HIGH: 0.85,
	QUALITY_ULTRA: 1.0,
}

static var master_volume := 0.8
static var music_volume := 0.7
static var sfx_volume := 1.0
static var quality := ""
static var auto_skill_points := true
static var loaded := false

static func default_quality() -> String:
	return QUALITY_MEDIUM if OS.has_feature("mobile") else QUALITY_ULTRA

static func reset_defaults() -> void:
	master_volume = 0.8
	music_volume = 0.7
	sfx_volume = 1.0
	quality = default_quality()
	auto_skill_points = true
	loaded = false

static func load_from(path := PATH) -> void:
	reset_defaults()
	var cfg := ConfigFile.new()
	if cfg.load(path) != OK:
		loaded = true
		return
	master_volume = clampf(float(cfg.get_value("audio", "master", master_volume)), 0.0, 1.0)
	music_volume = clampf(float(cfg.get_value("audio", "music", music_volume)), 0.0, 1.0)
	sfx_volume = clampf(float(cfg.get_value("audio", "sfx", sfx_volume)), 0.0, 1.0)
	var saved_quality := str(cfg.get_value("video", "quality", quality))
	quality = saved_quality if QUALITY_KEYS.has(saved_quality) else default_quality()
	auto_skill_points = bool(cfg.get_value("gameplay", "auto_skill_points", auto_skill_points))
	loaded = true

static func save_to(path := PATH) -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("meta", "version", CONFIG_VERSION)
	cfg.set_value("audio", "master", master_volume)
	cfg.set_value("audio", "music", music_volume)
	cfg.set_value("audio", "sfx", sfx_volume)
	cfg.set_value("video", "quality", quality if QUALITY_KEYS.has(quality) else default_quality())
	cfg.set_value("gameplay", "auto_skill_points", auto_skill_points)
	cfg.save(path)

## 总线在首次应用时按需创建，项目里不需要额外的 bus layout 资源。
static func ensure_buses() -> void:
	for bus_name in ["Music", "SFX"]:
		if AudioServer.get_bus_index(bus_name) >= 0:
			continue
		AudioServer.add_bus()
		var index := AudioServer.bus_count - 1
		AudioServer.set_bus_name(index, bus_name)
		AudioServer.set_bus_send(index, "Master")

static func apply_audio() -> void:
	ensure_buses()
	_set_bus_volume("Master", master_volume)
	_set_bus_volume("Music", music_volume)
	_set_bus_volume("SFX", sfx_volume)

static func quality_scale() -> float:
	var key := quality if QUALITY_SCALES.has(quality) else default_quality()
	return float(QUALITY_SCALES.get(key, 1.0))

## 只改当前视口的 3D 缩放；UI 仍按原生分辨率绘制，文字不会变糊。
static func apply_quality(viewport: Viewport) -> void:
	if viewport == null:
		return
	viewport.scaling_3d_scale = quality_scale()

static func quality_name() -> String:
	return str(QUALITY_NAMES.get(quality, QUALITY_NAMES[default_quality()]))

static func _set_bus_volume(bus_name: String, value: float) -> void:
	var index := AudioServer.get_bus_index(bus_name)
	if index < 0:
		return
	var linear := clampf(value, 0.0, 1.0)
	AudioServer.set_bus_mute(index, linear <= 0.001)
	AudioServer.set_bus_volume_db(index, linear_to_db(maxf(linear, 0.001)))
