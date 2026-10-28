extends CanvasLayer

# 开发者调试面板。
#
# 原则：**只改本地主机**。客机没有 sim，所有作弊按钮在客机上直接禁用，
# 面板仍可打开看 FPS / 实体数 / 缓冲深度 —— 排查网络卡顿时这些数字比作弊有用。
#
# 入口：F3。构建条件见 Arena._debug_enabled()（debug build / --dev / config.debug_panel）。
# 面板不参与游戏输入分发：控件自己吃掉鼠标事件，键盘只认 F3。

const GameTheme = preload("res://scripts/ui/game_theme.gd")

const TIME_SCALES := [0.25, 0.5, 1.0, 2.0, 4.0]

var arena: Object = null
var root: PanelContainer
var _status: Label
var _network: Label
var _refresh := 0.0
var _cheat_controls: Array[Control] = []

func setup(target: Object) -> void:
	arena = target
	layer = 20
	visible = false
	_build()
	_refresh = 0.0

func toggle() -> void:
	set_open(not visible)

func set_open(value: bool) -> void:
	visible = value
	if value:
		_refresh = 0.0
		_refresh_status()

func _build() -> void:
	root = PanelContainer.new()
	root.name = "DebugRoot"
	# 贴右上、上下留 18px：面板本身随窗口高度伸缩，ScrollContainer 兜住小窗口。
	root.anchor_left = 1.0
	root.anchor_right = 1.0
	root.anchor_top = 0.0
	root.anchor_bottom = 1.0
	root.offset_left = -404.0
	root.offset_right = -18.0
	root.offset_top = 18.0
	root.offset_bottom = -18.0
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_theme_stylebox_override(
		"panel",
		GameTheme.style(Color(0.018, 0.035, 0.05, 0.96), Color(0.84, 0.66, 0.34, 0.75), 1, 12, 14, 0.55)
	)
	# CanvasLayer 不是 Control：给它一个全屏宿主，面板才能按屏幕锚点定位。
	var host := Control.new()
	host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(host)
	host.add_child(root)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	root.add_child(column)

	var title_row := HBoxContainer.new()
	column.add_child(title_row)
	title_row.add_child(_make_label("开发者调试", 21, GameTheme.GOLD_LIGHT))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(spacer)
	title_row.add_child(_make_label("F3 关闭", 12, GameTheme.MUTED))

	_status = _make_label("", 13, GameTheme.TEXT)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_status)
	column.add_child(_make_label("作弊仅主机可用 · 客机只看状态", 11, GameTheme.MUTED))
	column.add_child(HSeparator.new())

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 5)
	scroll.add_child(body)

	_build_sim_group(body)
	_build_hero_group(body)
	_build_world_group(body)
	_build_feel_group(body)
	_build_network_group(body)

func _build_sim_group(body: VBoxContainer) -> void:
	body.add_child(_section("模拟"))
	var scale_row := HBoxContainer.new()
	scale_row.add_child(_make_label("时间倍率", 13, GameTheme.MUTED))
	scale_row.add_child(Control.new())
	var scale_option := OptionButton.new()
	scale_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for value in TIME_SCALES:
		scale_option.add_item("%sx" % str(value))
	scale_option.select(TIME_SCALES.find(1.0))
	scale_option.item_selected.connect(func(index: int) -> void:
		_call("debug_set_time_scale", [float(TIME_SCALES[index])])
	)
	scale_row.add_child(scale_option)
	body.add_child(scale_row)
	_track_cheat(scale_option)

	var pause_toggle := _check("暂停模拟", false, func(value: bool) -> void:
		_call("debug_set_paused", [value])
	)
	body.add_child(pause_toggle)
	var step := _make_button("单步 1 tick", func() -> void:
		_call("debug_step", [])
	)
	body.add_child(step)

func _build_hero_group(body: VBoxContainer) -> void:
	body.add_child(_section("英雄"))
	body.add_child(_check("无敌", false, func(value: bool) -> void:
		_call("debug_set_god", [value])
	))
	body.add_child(_check("无限法力", false, func(value: bool) -> void:
		_call("debug_set_infinite_mana", [value])
	))
	body.add_child(_check("无冷却", false, func(value: bool) -> void:
		_call("debug_set_no_cooldown", [value])
	))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 4)
	body.add_child(grid)
	grid.add_child(_make_button("+1000 金币", func() -> void: _call("debug_add_gold", [1000])))
	grid.add_child(_make_button("等级 +1", func() -> void: _call("debug_level_up", [])))
	grid.add_child(_make_button("回满血蓝", func() -> void: _call("debug_heal", [])))
	grid.add_child(_make_button("传到鼠标", func() -> void: _call("debug_teleport_to_cursor", [])))

func _build_world_group(body: VBoxContainer) -> void:
	body.add_child(_section("世界"))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 4)
	body.add_child(grid)
	grid.add_child(_make_button("清空小兵", func() -> void: _call("debug_clear_minions", [])))
	grid.add_child(_make_button("刷新野怪", func() -> void: _call("debug_respawn_camps", [])))
	var reveal := _check("全图视野", false, func(value: bool) -> void:
		_call("debug_set_reveal", [value])
	)
	body.add_child(reveal)

func _build_feel_group(body: VBoxContainer) -> void:
	body.add_child(_section("表现"))
	body.add_child(_check("关闭顿帧", false, func(value: bool) -> void:
		_call("debug_set_no_hit_stop", [value])
	))
	body.add_child(_check("关闭震屏", false, func(value: bool) -> void:
		_call("debug_set_no_shake", [value])
	))

func _build_network_group(body: VBoxContainer) -> void:
	body.add_child(_section("网络"))
	_network = _make_label("", 12, GameTheme.MUTED)
	body.add_child(_network)

func _section(text: String) -> Label:
	var label := _make_label(text, 15, GameTheme.GOLD)
	label.add_theme_constant_override("outline_size", 0)
	return label

func _make_label(text: String, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	return label

func _make_button(text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(0, 36)
	button.add_theme_font_size_override("font_size", 14)
	button.pressed.connect(action)
	_track_cheat(button)
	return button

func _check(text: String, value: bool, action: Callable) -> CheckButton:
	var button := CheckButton.new()
	button.text = text
	button.button_pressed = value
	button.add_theme_font_size_override("font_size", 14)
	button.toggled.connect(action)
	_track_cheat(button)
	return button

func _track_cheat(control: Control) -> void:
	_cheat_controls.append(control)

func _call(method: String, args: Array) -> void:
	if arena == null or not is_instance_valid(arena) or not arena.has_method(method):
		return
	arena.callv(method, args)

func _process(delta: float) -> void:
	if not visible:
		return
	_refresh -= delta
	if _refresh > 0.0:
		return
	_refresh = 0.25
	_refresh_status()

func _refresh_status() -> void:
	if arena == null or not is_instance_valid(arena):
		return
	var metrics: Dictionary = {}
	if arena.has_method("debug_metrics"):
		metrics = arena.debug_metrics()
	var can_cheat := bool(metrics.get("authoritative", false))
	for control in _cheat_controls:
		if is_instance_valid(control):
			control.disabled = not can_cheat
	_status.text = "模式 %s · 时间 %s\nFPS %d · 单位 %d\ntick %.2fms · 快照 %.2fms" % [
		str(metrics.get("mode", "?")),
		_format_time(float(metrics.get("time", 0.0))),
		int(metrics.get("fps", 0)),
		int(metrics.get("entities", 0)),
		float(metrics.get("tick_ms", 0.0)),
		float(metrics.get("snapshot_ms", 0.0)),
	]
	_network.text = "连接 %s · 缓冲 %d 格 · %s" % [
		str(metrics.get("network", "本地")),
		int(metrics.get("buffer", 0)),
		"主机权威" if can_cheat else "客机只读",
	]

func _format_time(seconds: float) -> String:
	var total := maxi(0, int(seconds))
	return "%02d:%02d" % [total / 60, total % 60]
