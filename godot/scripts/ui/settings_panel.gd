class_name SettingsPanel
extends Control

## 大厅与暂停菜单共用的设置面板。改一项立即生效，关闭时落盘。

signal closed

const GameSettings = preload("res://scripts/app/settings.gd")
const GameTheme = preload("res://scripts/ui/game_theme.gd")

var _quality_keys: Array = GameSettings.QUALITY_KEYS

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	theme = GameTheme.theme()

	var dim := ColorRect.new()
	dim.color = Color(0.004, 0.009, 0.014, 0.78)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)

	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.offset_left = -260.0
	panel.offset_right = 260.0
	panel.offset_top = -285.0
	panel.offset_bottom = 285.0
	panel.add_theme_stylebox_override(
		"panel",
		GameTheme.style(GameTheme.PANEL, Color(0.72, 0.56, 0.28, 0.95), 2, 14)
	)
	add_child(panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 16)
	panel.add_child(box)

	var title := _label("设  置", 32, GameTheme.GOLD_LIGHT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)

	box.add_child(_slider_row("主音量", GameSettings.master_volume, func(value: float):
		GameSettings.master_volume = value
		GameSettings.apply_audio()
	))
	box.add_child(_slider_row("音乐", GameSettings.music_volume, func(value: float):
		GameSettings.music_volume = value
		GameSettings.apply_audio()
	))
	box.add_child(_slider_row("音效", GameSettings.sfx_volume, func(value: float):
		GameSettings.sfx_volume = value
		GameSettings.apply_audio()
	))
	# FX-09：只缩放装饰粒子与震屏，技能主环/飘字不受影响，所以调低也能读技能。
	box.add_child(_slider_row("特效强度", GameSettings.fx_intensity, func(value: float):
		GameSettings.fx_intensity = clampf(value, 0.0, 1.0)
	))

	box.add_child(_quality_row())
	box.add_child(_auto_points_row())

	var close := Button.new()
	close.text = "完成"
	close.custom_minimum_size = Vector2(0, 54)
	close.pressed.connect(close_panel)
	box.add_child(close)

func close_panel() -> void:
	GameSettings.save_to()
	GameSettings.apply_audio()
	GameSettings.apply_quality(get_viewport())
	closed.emit()
	queue_free()

func _slider_row(label_text: String, value: float, on_change: Callable) -> Control:
	var row := VBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	row.add_child(head)
	var label := _label(label_text, 18, GameTheme.TEXT)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(label)
	var readout := _label("%d%%" % int(round(value * 100.0)), 16, GameTheme.MUTED)
	head.add_child(readout)
	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.05
	slider.value = value
	slider.custom_minimum_size = Vector2(0, 32)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.value_changed.connect(func(next: float):
		readout.text = "%d%%" % int(round(next * 100.0))
		on_change.call(next)
	)
	row.add_child(slider)
	return row

func _quality_row() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	var label := _label("画质", 18, GameTheme.TEXT)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	var options := OptionButton.new()
	options.custom_minimum_size = Vector2(180, 44)
	for key in _quality_keys:
		options.add_item(str(GameSettings.QUALITY_NAMES[key]))
	var current := _quality_keys.find(GameSettings.quality)
	options.select(maxi(0, current))
	options.item_selected.connect(func(index: int):
		GameSettings.quality = str(_quality_keys[index])
		GameSettings.apply_quality(get_viewport())
	)
	row.add_child(options)
	return row

func _auto_points_row() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	var label := _label("自动加点", 18, GameTheme.TEXT)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	var toggle := CheckButton.new()
	toggle.button_pressed = GameSettings.auto_skill_points
	toggle.custom_minimum_size = Vector2(72, 44)
	toggle.toggled.connect(func(pressed: bool):
		GameSettings.auto_skill_points = pressed
	)
	row.add_child(toggle)
	return row

func _label(text: String, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	return label
