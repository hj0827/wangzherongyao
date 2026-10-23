extends Control
class_name GameHUD

signal skill_pressed(slot: String)
signal leave_requested
signal resume_requested
signal move_changed(value: Vector2)
signal attack_changed(held: bool)
signal pause_requested

const GameTheme = preload("res://scripts/ui/game_theme.gd")
const HeroDefs = preload("res://sim/hero_defs.gd")
const MapIntel = preload("res://sim/map_intel.gd")
const MatchMenu = preload("res://scripts/game/match_menu.gd")
const Minimap = preload("res://scripts/ui/minimap.gd")
const SkillButton = preload("res://scripts/ui/skill_button.gd")
const TouchJoystick = preload("res://scripts/ui/touch_joystick.gd")
const TouchActionButton = preload("res://scripts/ui/touch_action_button.gd")
const TouchLayout = preload("res://scripts/ui/touch_layout.gd")

var arena: Node = null
var local_owner := ""
var local_team := "blue"
var hero_type := "blade"
var player_name := "你"
var snapshot: Dictionary = {}
var result_shown := false
var paused := false
var touch_mode := false
var online_mode := false
var _joystick: TouchJoystick
var _attack_button: TouchActionButton
var _pause_button: TouchActionButton

var _score_blue: Label
var _score_red: Label
var _timer_label: Label
var _wave_label: Label
var _objective_label: Label
var _hp_bar: ProgressBar
var _hp_text: Label
var _hp_style: StyleBoxFlat
var _mp_bar: ProgressBar
var _mp_text: Label
var _level_label: Label
var _name_label: Label
var _role_label: Label
var _kd_label: Label
var _skill_q: SkillButton
var _skill_e: SkillButton
var _minimap: Minimap
var _intel_panel: PanelContainer
var _intel_title: Label
var _intel_meta: Label
var _intel_detail: Label
var _intel_summary: Label
var _intel_units: VBoxContainer
var _intel_rows: Array[Label] = []
var _intel_close: Button
var _intel_point := Vector2.ZERO
var _intel_valid := false
var _portrait: TextureRect
var _feed_box: VBoxContainer
var _announce_panel: PanelContainer
var _announce_label: Label
var _announce_tween: Tween
var _death_overlay: Control
var _death_countdown: Label
var _death_killer_label: Label
var _result_overlay: Control
var _result_title: Label
var _result_sub: Label
var _result_stats: Label
var _pause_overlay: Control
var _pause_title: Label
var _pause_hint: Label
var _loading_overlay: Control

func setup(owner_id: String, team: String, type_id: String, display: String, mobile := false, online := false) -> void:
	local_owner = owner_id
	local_team = team
	hero_type = type_id
	player_name = display
	touch_mode = mobile
	online_mode = online

func _ready() -> void:
	theme = GameTheme.theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_top_bar()
	_build_minimap()
	_build_map_intel()
	_build_feed()
	_build_announcement()
	_build_bottom_panel()
	_build_hints()
	if touch_mode:
		_build_touch_controls()
	_build_death_overlay()
	_build_pause_overlay()
	_build_result_overlay()
	_build_loading_overlay()

func _build_top_bar() -> void:
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.offset_left = -246.0
	panel.offset_right = 246.0
	panel.offset_top = 14.0
	panel.offset_bottom = 82.0
	panel.add_theme_stylebox_override("panel", GameTheme.style(Color(0.02, 0.035, 0.05, 0.9), Color(0.55, 0.44, 0.24, 0.65), 1, 9))
	add_child(panel)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 28)
	panel.add_child(row)
	_score_blue = _make_label("蓝方  0", 22, GameTheme.BLUE)
	_score_blue.custom_minimum_size.x = 132
	_score_blue.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(_score_blue)
	var center := VBoxContainer.new()
	center.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_theme_constant_override("separation", 0)
	row.add_child(center)
	_timer_label = _make_label("00:00", 26, GameTheme.TEXT)
	_timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	center.add_child(_timer_label)
	_wave_label = _make_label("第 1 波", 12, GameTheme.MUTED)
	_wave_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	center.add_child(_wave_label)
	_score_red = _make_label("0  红方", 22, GameTheme.RED)
	_score_red.custom_minimum_size.x = 132
	_score_red.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	row.add_child(_score_red)

func _build_minimap() -> void:
	var panel := PanelContainer.new()
	panel.anchor_left = 0.0
	panel.anchor_right = 0.0
	panel.offset_left = 18.0
	panel.offset_right = 252.0
	panel.offset_top = 18.0
	panel.offset_bottom = 286.0
	panel.add_theme_stylebox_override("panel", GameTheme.style(Color(0.02, 0.035, 0.05, 0.82), Color(0.55, 0.44, 0.24, 0.65), 1, 9))
	add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	panel.add_child(box)
	_minimap = Minimap.new()
	_minimap.custom_minimum_size = Minimap.DISPLAY_SIZE
	_minimap.location_clicked.connect(_on_minimap_location_clicked)
	box.add_child(_minimap)
	_objective_label = _make_label("防御塔 蓝 0 : 0 红", 12, GameTheme.MUTED)
	_objective_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_objective_label)
	var hint := _make_label("点击地图查看区域情报", 11, Color(0.6, 0.68, 0.72, 0.8))
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(hint)

func _build_map_intel() -> void:
	_intel_panel = PanelContainer.new()
	_intel_panel.anchor_left = 0.0
	_intel_panel.anchor_top = 0.0
	_intel_panel.anchor_right = 0.0
	_intel_panel.anchor_bottom = 0.0
	_intel_panel.offset_left = 18.0
	_intel_panel.offset_right = 390.0
	_intel_panel.offset_top = 294.0
	_intel_panel.offset_bottom = 502.0
	_intel_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_intel_panel.add_theme_stylebox_override("panel", GameTheme.style(Color(0.02, 0.04, 0.055, 0.94), Color(0.55, 0.44, 0.24, 0.85), 1, 9, 10, 0.5))
	_intel_panel.visible = false
	add_child(_intel_panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 3)
	_intel_panel.add_child(box)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	box.add_child(header)
	_intel_title = _make_label("地图情报", 18, GameTheme.GOLD_LIGHT)
	_intel_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(_intel_title)
	_intel_close = Button.new()
	_intel_close.text = "×"
	_intel_close.flat = true
	_intel_close.focus_mode = Control.FOCUS_NONE
	_intel_close.custom_minimum_size = Vector2(48, 48)
	_intel_close.add_theme_font_size_override("font_size", 20)
	_intel_close.add_theme_color_override("font_color", GameTheme.MUTED)
	_intel_close.add_theme_color_override("font_hover_color", GameTheme.GOLD_LIGHT)
	for state in ["normal", "hover", "pressed"]:
		_intel_close.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	_intel_close.pressed.connect(_close_intel)
	header.add_child(_intel_close)
	_intel_meta = _make_label("", 12, GameTheme.MUTED)
	box.add_child(_intel_meta)
	_intel_detail = _make_label("", 11, Color(0.66, 0.72, 0.76))
	box.add_child(_intel_detail)
	_intel_summary = _make_label("", 12, GameTheme.TEXT)
	box.add_child(_intel_summary)
	_intel_units = VBoxContainer.new()
	_intel_units.add_theme_constant_override("separation", 1)
	box.add_child(_intel_units)
	_intel_rows.clear()
	for i in MapIntel.MAX_UNITS:
		var row := _make_label("", 12, GameTheme.TEXT)
		row.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
		row.add_theme_constant_override("outline_size", 2)
		row.visible = false
		_intel_units.add_child(row)
		_intel_rows.append(row)

func _on_minimap_location_clicked(world: Vector2) -> void:
	_intel_point = world
	_intel_valid = true
	_intel_panel.visible = true
	_refresh_intel()

func _close_intel() -> void:
	_intel_valid = false
	if _intel_panel != null:
		_intel_panel.visible = false
	if _minimap != null:
		_minimap.clear_inspect_point()

func _refresh_intel() -> void:
	if not _intel_valid or _intel_panel == null:
		return
	var report := MapIntel.inspect(snapshot, _intel_point, local_owner, local_team)
	var region: Dictionary = report.region
	_intel_title.text = "地图情报 · %s" % str(region.get("name", "未知"))
	var distance_text := "距你 --"
	if bool(report.get("hero_found", false)):
		distance_text = "距你 %.1f m" % float(report.get("hero_distance", 0.0))
	_intel_meta.text = "坐标 (%.1f, %.1f)   ·   %s" % [_intel_point.x, _intel_point.y, distance_text]
	_intel_detail.text = str(region.get("note", ""))
	var counts: Dictionary = report.get("counts", {})
	var blue_count := int(counts.get("blue", 0))
	var red_count := int(counts.get("red", 0))
	var total := int(report.get("total", 0))
	if total == 0:
		_intel_summary.text = "附近 %d 米内没有可观察单位" % int(round(float(report.get("radius", MapIntel.INSPECT_RADIUS))))
		_intel_summary.add_theme_color_override("font_color", GameTheme.MUTED)
	else:
		_intel_summary.text = "附近单位   蓝方 %d   ·   红方 %d" % [blue_count, red_count]
		_intel_summary.add_theme_color_override("font_color", GameTheme.TEXT)
	var units: Array = report.get("units", [])
	for index in _intel_rows.size():
		var row := _intel_rows[index]
		if index < units.size():
			_apply_intel_row(row, units[index])
		else:
			row.visible = false

func _apply_intel_row(label: Label, unit: Dictionary) -> void:
	var kind := str(unit.get("kind", ""))
	var mark := "●"
	if kind == "tower":
		mark = "■"
	elif kind == "base":
		mark = "◆"
	elif kind == "minion":
		mark = "·"
	var team := str(unit.get("team", "blue"))
	var text := "%s %s（%s" % [mark, str(unit.get("label", "单位")), "蓝方" if team == "blue" else "红方"]
	if int(unit.get("level", 0)) > 0:
		text += " Lv.%d" % int(unit.get("level", 0))
	text += "）  %d/%d   ·   %.1f m" % [
		int(ceil(float(unit.get("hp", 0.0)))),
		int(unit.get("max_hp", 1.0)),
		float(unit.get("distance", 0.0)),
	]
	label.text = text
	label.add_theme_color_override("font_color", GameTheme.BLUE if team == "blue" else GameTheme.RED)
	label.visible = true

func _build_feed() -> void:
	_feed_box = VBoxContainer.new()
	_feed_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_feed_box.anchor_left = 1.0
	_feed_box.anchor_right = 1.0
	_feed_box.offset_left = -430.0
	_feed_box.offset_top = 20.0
	_feed_box.offset_right = -22.0
	_feed_box.offset_bottom = 250.0
	_feed_box.add_theme_constant_override("separation", 4)
	add_child(_feed_box)

func _build_announcement() -> void:
	_announce_panel = PanelContainer.new()
	_announce_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_announce_panel.anchor_left = 0.5
	_announce_panel.anchor_right = 0.5
	_announce_panel.anchor_top = 0.13
	_announce_panel.anchor_bottom = 0.13
	_announce_panel.offset_left = -330.0
	_announce_panel.offset_right = 330.0
	_announce_panel.offset_top = 0.0
	_announce_panel.offset_bottom = 84.0
	_announce_panel.add_theme_stylebox_override("panel", GameTheme.style(Color(0.0, 0.0, 0.0, 0.36), Color(0.55, 0.44, 0.24, 0.25), 1, 8))
	add_child(_announce_panel)
	_announce_label = _make_label("", 38, GameTheme.GOLD_LIGHT, "TitleLabel")
	_announce_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_announce_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_announce_label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.9))
	_announce_label.add_theme_constant_override("outline_size", 8)
	_announce_panel.add_child(_announce_label)
	_announce_panel.visible = false

func _build_bottom_panel() -> void:
	var bottom_inset := 40.0 if touch_mode else 16.0
	var panel_height := TouchLayout.BOTTOM_PANEL_HEIGHT if touch_mode else 160.0
	var panel := PanelContainer.new()
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 1.0
	panel.anchor_bottom = 1.0
	panel.offset_left = -420.0
	panel.offset_right = 420.0
	panel.offset_top = -(bottom_inset + panel_height)
	panel.offset_bottom = -bottom_inset
	panel.add_theme_stylebox_override("panel", GameTheme.style(Color(0.02, 0.04, 0.055, 0.92), Color(0.55, 0.44, 0.24, 0.7), 1, 12))
	add_child(panel)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	panel.add_child(row)

	var portrait_frame := PanelContainer.new()
	portrait_frame.custom_minimum_size = Vector2(104, 104)
	portrait_frame.add_theme_stylebox_override("panel", GameTheme.style(Color(0.02, 0.03, 0.045, 1.0), Color(0.72, 0.56, 0.3, 0.8), 2, 8))
	row.add_child(portrait_frame)
	_portrait = TextureRect.new()
	_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var portrait_path := GameTheme.portrait_path(hero_type)
	if ResourceLoader.exists(portrait_path):
		_portrait.texture = load(portrait_path)
	portrait_frame.add_child(_portrait)

	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 5)
	row.add_child(info)
	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 10)
	info.add_child(name_row)
	_name_label = _make_label(player_name, 22, GameTheme.TEXT)
	_name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_row.add_child(_name_label)
	_level_label = _make_label("Lv.1", 18, GameTheme.GOLD_LIGHT)
	name_row.add_child(_level_label)
	_role_label = _make_label("", 13, GameTheme.MUTED)
	info.add_child(_role_label)
	var hp_root := _make_stat_bar(GameTheme.GREEN, 20)
	_hp_bar = hp_root.get_meta("bar")
	_hp_text = hp_root.get_meta("label")
	_hp_style = _hp_bar.get_theme_stylebox("fill") as StyleBoxFlat
	info.add_child(hp_root)
	var mp_root := _make_stat_bar(GameTheme.MANA, 16)
	_mp_bar = mp_root.get_meta("bar")
	_mp_text = mp_root.get_meta("label")
	info.add_child(mp_root)
	_kd_label = _make_label("击杀 0 / 阵亡 0", 13, GameTheme.MUTED)
	info.add_child(_kd_label)

	if not touch_mode:
		var skills := HBoxContainer.new()
		skills.add_theme_constant_override("separation", 12)
		row.add_child(skills)
		_skill_q = _create_skill("q", "Q", GameTheme.GOLD)
		skills.add_child(_skill_q)
		_skill_e = _create_skill("e", "E", Color(0.55, 0.75, 1.0))
		skills.add_child(_skill_e)
	var hero_def: Dictionary = HeroDefs.get_hero(hero_type)
	_role_label.text = "%s · %s" % [hero_def.role, hero_def.title]

func _create_skill(slot: String, key: String, accent: Color) -> SkillButton:
	var button := SkillButton.new()
	button.slot = slot
	button.key_text = key
	button.accent = accent
	button.touch_mode = touch_mode
	button.skill_name = str(HeroDefs.get_hero(hero_type).get(slot, {}).get("name", "技能"))
	button.pressed.connect(func(): skill_pressed.emit(slot))
	return button

func _make_stat_bar(fill_color: Color, height: float) -> Control:
	var root := Control.new()
	root.custom_minimum_size = Vector2(300, height)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bar := ProgressBar.new()
	bar.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bar.show_percentage = false
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.01, 0.02, 0.03, 0.92)
	bg.set_border_width_all(1)
	bg.border_color = Color(0.15, 0.18, 0.22, 0.9)
	bg.set_corner_radius_all(4)
	var fill := StyleBoxFlat.new()
	fill.bg_color = fill_color
	fill.set_corner_radius_all(4)
	bar.add_theme_stylebox_override("background", bg)
	bar.add_theme_stylebox_override("fill", fill)
	root.add_child(bar)
	var label := _make_label("", 11, Color(1, 1, 1, 0.95))
	label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.95))
	label.add_theme_constant_override("outline_size", 3)
	root.add_child(label)
	root.set_meta("bar", bar)
	root.set_meta("label", label)
	return root

func _build_hints() -> void:
	# 操作提示拆两行：左键改成「移动到点」之后键位变多，单行会顶到英雄信息面板底下。
	var lines: Array[String] = [
		"左键 移动   ·   右键 / 空格 普攻   ·   Q / E 技能",
		"WASD 走位   ·   滚轮 缩放   ·   Esc 菜单",
	]
	var top := -50.0
	var bottom := -12.0
	if touch_mode:
		lines = ["左侧摇杆移动   ·   按住攻击   ·   战场拖动瞄准   ·   双指缩放"]
		top = -332.0
		bottom = -304.0
	var box := VBoxContainer.new()
	box.anchor_left = 0.0
	box.anchor_top = 1.0
	box.anchor_right = 0.0
	box.anchor_bottom = 1.0
	box.offset_left = 22.0
	box.offset_top = top
	box.offset_right = 640.0
	box.offset_bottom = bottom
	box.alignment = BoxContainer.ALIGNMENT_END
	box.add_theme_constant_override("separation", 3)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for line in lines:
		var hint := _make_label(line, 15 if touch_mode else 13, Color(0.66, 0.72, 0.77, 0.9))
		hint.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.75))
		hint.add_theme_constant_override("outline_size", 3)
		hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(hint)
	add_child(box)

func _build_touch_controls() -> void:
	_joystick = TouchJoystick.new()
	_joystick.touch_mode = true
	_joystick.anchor_left = 0.0
	_joystick.anchor_top = 1.0
	_joystick.anchor_right = 0.0
	_joystick.anchor_bottom = 1.0
	_joystick.offset_left = 12.0
	_joystick.offset_top = -300.0
	_joystick.offset_right = 272.0
	_joystick.offset_bottom = -40.0
	_joystick.moved.connect(func(value: Vector2): move_changed.emit(value))
	add_child(_joystick)

	_attack_button = TouchActionButton.new()
	_attack_button.touch_mode = true
	_attack_button.label = "攻击"
	_attack_button.hint = "按住连击"
	_attack_button.accent = Color(0.95, 0.55, 0.3)
	_attack_button.anchor_left = 1.0
	_attack_button.anchor_top = 1.0
	_attack_button.anchor_right = 1.0
	_attack_button.anchor_bottom = 1.0
	_attack_button.offset_left = -TouchLayout.ATTACK_MARGIN.x - TouchLayout.ATTACK_BUTTON_SIZE
	_attack_button.offset_top = -TouchLayout.ATTACK_MARGIN.y - TouchLayout.ATTACK_BUTTON_SIZE
	_attack_button.offset_right = -TouchLayout.ATTACK_MARGIN.x
	_attack_button.offset_bottom = -TouchLayout.ATTACK_MARGIN.y
	_attack_button.pressed.connect(func(): attack_changed.emit(true))
	_attack_button.released.connect(func(): attack_changed.emit(false))
	add_child(_attack_button)

	_skill_q = _create_skill("q", "Q", GameTheme.GOLD)
	add_child(_skill_q)
	_place_touch_skill(_skill_q, 0)
	_skill_e = _create_skill("e", "E", Color(0.55, 0.75, 1.0))
	add_child(_skill_e)
	_place_touch_skill(_skill_e, 1)

	_pause_button = TouchActionButton.new()
	_pause_button.touch_mode = true
	_pause_button.label = MatchMenu.pause_label(online_mode)
	_pause_button.accent = Color(0.58, 0.66, 0.72)
	_pause_button.anchor_left = 1.0
	_pause_button.anchor_top = 0.0
	_pause_button.anchor_right = 1.0
	_pause_button.anchor_bottom = 0.0
	_pause_button.offset_left = -26.0 - TouchLayout.PAUSE_BUTTON_SIZE.x
	_pause_button.offset_top = 276.0
	_pause_button.offset_right = -26.0
	_pause_button.offset_bottom = 276.0 + TouchLayout.PAUSE_BUTTON_SIZE.y
	_pause_button.pressed.connect(func(): pause_requested.emit())
	add_child(_pause_button)

func _place_touch_skill(button: Control, arc_index: int) -> void:
	var angle := deg_to_rad(float(TouchLayout.SKILL_ARC_ANGLES_DEG[arc_index]))
	var attack_center_offset := Vector2(
		-TouchLayout.ATTACK_MARGIN.x - TouchLayout.ATTACK_BUTTON_SIZE * 0.5,
		-TouchLayout.ATTACK_MARGIN.y - TouchLayout.ATTACK_BUTTON_SIZE * 0.5
	)
	var center := attack_center_offset + Vector2(cos(angle), sin(angle)) * TouchLayout.SKILL_ARC_RADIUS
	var half := TouchLayout.SKILL_TOUCH_SIZE * 0.5
	button.anchor_left = 1.0
	button.anchor_top = 1.0
	button.anchor_right = 1.0
	button.anchor_bottom = 1.0
	button.offset_left = center.x - half.x
	button.offset_top = center.y - half.y
	button.offset_right = center.x + half.x
	button.offset_bottom = center.y + half.y

func _build_death_overlay() -> void:
	_death_overlay = ColorRect.new()
	_death_overlay.color = Color(0.08, 0.0, 0.0, 0.48)
	_death_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_death_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_death_overlay.visible = false
	add_child(_death_overlay)
	var center := VBoxContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	center.alignment = BoxContainer.ALIGNMENT_CENTER
	center.offset_left = -220.0
	center.offset_right = 220.0
	center.offset_top = -100.0
	center.offset_bottom = 100.0
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_death_overlay.add_child(center)
	var title := _make_label("阵  亡", 72, Color(0.92, 0.42, 0.35), "TitleLabel")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	center.add_child(title)
	_death_killer_label = _make_label("", 20, Color(1.0, 0.8, 0.4))
	_death_killer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	center.add_child(_death_killer_label)
	_death_countdown = _make_label("复活倒计时 6.0", 20, GameTheme.TEXT)
	_death_countdown.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	center.add_child(_death_countdown)
	var tip := _make_label("等待队友推进 · 观战中", 14, GameTheme.MUTED)
	tip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	center.add_child(tip)

func _build_pause_overlay() -> void:
	var overlay_height := 460.0 if touch_mode else 340.0
	var button_height := TouchLayout.PAUSE_MENU_BUTTON_HEIGHT if touch_mode else 52.0
	_pause_overlay = ColorRect.new()
	_pause_overlay.color = Color(0.005, 0.01, 0.015, 0.72)
	_pause_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_pause_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_pause_overlay.visible = false
	add_child(_pause_overlay)
	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.offset_left = -230.0
	panel.offset_right = 230.0
	panel.offset_top = -overlay_height * 0.5
	panel.offset_bottom = overlay_height * 0.5
	panel.add_theme_stylebox_override("panel", GameTheme.style(GameTheme.PANEL, Color(0.6, 0.48, 0.26, 0.9), 2, 12))
	_pause_overlay.add_child(panel)
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 18)
	panel.add_child(box)
	_pause_title = _make_label(MatchMenu.title(online_mode), 54, GameTheme.GOLD_LIGHT, "TitleLabel")
	_pause_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_pause_title)
	var resume := Button.new()
	resume.text = "继续对局"
	resume.custom_minimum_size = Vector2(0, button_height)
	resume.pressed.connect(func(): resume_requested.emit())
	box.add_child(resume)
	var leave := Button.new()
	leave.text = "离开对局"
	leave.custom_minimum_size = Vector2(0, button_height)
	leave.pressed.connect(func(): leave_requested.emit())
	box.add_child(leave)
	_pause_hint = _make_label(MatchMenu.hint(online_mode), 12, GameTheme.MUTED)
	_pause_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_pause_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_pause_hint)

func _build_result_overlay() -> void:
	_result_overlay = ColorRect.new()
	_result_overlay.color = Color(0.005, 0.01, 0.015, 0.76)
	_result_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_result_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_result_overlay.visible = false
	add_child(_result_overlay)
	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.offset_left = -330.0
	panel.offset_right = 330.0
	panel.offset_top = -220.0
	panel.offset_bottom = 220.0
	panel.add_theme_stylebox_override("panel", GameTheme.style(Color(0.025, 0.045, 0.06, 0.97), Color(0.7, 0.55, 0.28, 0.95), 2, 14))
	_result_overlay.add_child(panel)
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 16)
	panel.add_child(box)
	_result_title = _make_label("胜  利", 76, GameTheme.GOLD_LIGHT, "TitleLabel")
	_result_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_result_title)
	_result_sub = _make_label("", 20, GameTheme.TEXT)
	_result_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_result_sub)
	_result_stats = _make_label("", 16, GameTheme.MUTED)
	_result_stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_result_stats)
	var leave := Button.new()
	leave.text = "返回主菜单"
	leave.custom_minimum_size = TouchLayout.RESULT_BUTTON_SIZE if touch_mode else Vector2(220, 52)
	leave.pressed.connect(func(): leave_requested.emit())
	box.add_child(leave)

func _build_loading_overlay() -> void:
	_loading_overlay = PanelContainer.new()
	_loading_overlay.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_loading_overlay.offset_left = -190.0
	_loading_overlay.offset_right = 190.0
	_loading_overlay.offset_top = -46.0
	_loading_overlay.offset_bottom = 46.0
	_loading_overlay.add_theme_stylebox_override("panel", GameTheme.style(Color(0.02, 0.035, 0.05, 0.94), Color(0.55, 0.44, 0.24, 0.7), 1, 8))
	_loading_overlay.visible = false
	add_child(_loading_overlay)
	var label := _make_label("正在同步战场…", 20, GameTheme.TEXT)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_loading_overlay.add_child(label)

func _make_label(text: String, font_size: int, color: Color, variation := "") -> Label:
	var label := Label.new()
	label.text = text
	if variation != "":
		label.theme_type_variation = variation
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label

func update_snapshot(data: Dictionary) -> void:
	snapshot = data
	var local := _find_local_hero(data)
	if local.is_empty():
		if _loading_overlay:
			_loading_overlay.visible = true
		return
	if _loading_overlay:
		_loading_overlay.visible = false

	var scores: Dictionary = data.get("scores", {})
	var blue_score: Dictionary = scores.get("blue", {})
	var red_score: Dictionary = scores.get("red", {})
	var blue_kills := int(blue_score.get("kills", 0))
	var red_kills := int(red_score.get("kills", 0))
	_score_blue.text = "蓝方  %d" % blue_kills
	_score_red.text = "%d  红方" % red_kills
	_timer_label.text = _format_time(float(data.get("time", 0.0)))
	_wave_label.text = "第 %d 波" % int(data.get("wave", 1))
	_objective_label.text = "防御塔  蓝 %d : %d 红" % [int(blue_score.get("towers", 0)), int(red_score.get("towers", 0))]

	var max_hp := maxf(1.0, float(local.get("max_hp", 1.0)))
	var hp := float(local.get("hp", 0.0))
	var max_mp := maxf(1.0, float(local.get("max_mp", 1.0)))
	var mp := float(local.get("mp", 0.0))
	_hp_bar.max_value = max_hp
	_hp_bar.value = hp
	_hp_text.text = "%d / %d" % [int(ceil(hp)), int(max_hp)]
	_mp_bar.max_value = max_mp
	_mp_bar.value = mp
	_mp_text.text = "%d / %d" % [int(ceil(mp)), int(max_mp)]
	var ratio := hp / max_hp
	var desired_color := GameTheme.GREEN
	if ratio < 0.3:
		desired_color = Color(0.92, 0.28, 0.24)
	elif ratio < 0.6:
		desired_color = Color(0.9, 0.68, 0.27)
	if _hp_style:
		_hp_style.bg_color = desired_color
	_level_label.text = "Lv.%d" % int(local.get("level", 1))
	_kd_label.text = "击杀 %d   /   阵亡 %d" % [int(local.get("kills", 0)), int(local.get("deaths", 0))]
	var hero_def: Dictionary = HeroDefs.get_hero(str(local.get("hero_type", hero_type)))
	_role_label.text = "%s · %s" % [hero_def.role, hero_def.title]
	var alive := bool(local.get("alive", true))
	var q_def: Dictionary = hero_def.q
	var e_def: Dictionary = hero_def.e
	_skill_q.set_state(float(local.get("skill_q_cd", 0.0)), float(q_def.cooldown), str(q_def.name), mp >= float(q_def.cost), not alive)
	_skill_e.set_state(float(local.get("skill_e_cd", 0.0)), float(e_def.cooldown), str(e_def.name), mp >= float(e_def.cost), not alive)

	var ended := bool(data.get("ended", false))
	if not ended and not alive and not _result_overlay.visible:
		_death_overlay.visible = true
		_death_countdown.text = "复活倒计时 %.1f" % float(local.get("respawn_timer", 0.0))
		var killer_name := str(local.get("last_killer_name", ""))
		if killer_name != "":
			_death_killer_label.text = "被 %s 击败" % killer_name
			_death_killer_label.visible = true
		else:
			_death_killer_label.visible = false
	else:
		_death_overlay.visible = false

	_minimap.set_snapshot(data, local_owner, local_team)
	if _intel_valid:
		_refresh_intel()
	if ended and not result_shown:
		show_result(str(data.get("winner", "")), local)

func _find_local_hero(data: Dictionary) -> Dictionary:
	for entity in data.get("entities", []):
		if str(entity.get("type", "")) != "hero":
			continue
		if str(entity.get("owner_id", "")) == local_owner:
			return entity
	return {}

func announce(text: String, color := GameTheme.GOLD_LIGHT, duration := 2.2) -> void:
	if _announce_panel == null:
		return
	if _announce_tween != null and _announce_tween.is_valid():
		_announce_tween.kill()
	_announce_panel.visible = true
	_announce_label.text = text
	_announce_label.add_theme_color_override("font_color", color)
	_announce_label.modulate = Color(1, 1, 1, 0)
	_announce_tween = create_tween()
	_announce_tween.tween_property(_announce_label, "modulate:a", 1.0, 0.18)
	_announce_tween.tween_interval(duration)
	_announce_tween.tween_property(_announce_label, "modulate:a", 0.0, 0.4)
	_announce_tween.tween_callback(func(): _announce_panel.visible = false)

func add_feed(text: String, color := GameTheme.TEXT) -> void:
	if _feed_box == null:
		return
	var label := _make_label(text, 15, color)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	label.add_theme_constant_override("outline_size", 4)
	_feed_box.add_child(label)
	while _feed_box.get_child_count() > 6:
		var first := _feed_box.get_child(0)
		_feed_box.remove_child(first)
		first.queue_free()
	var tween := create_tween()
	tween.tween_interval(4.5)
	tween.tween_property(label, "modulate:a", 0.0, 0.6)
	tween.tween_callback(label.queue_free)

func show_pause(value: bool, online := false) -> void:
	paused = value
	online_mode = online
	if _pause_title != null:
		_pause_title.text = MatchMenu.title(online_mode)
	if _pause_hint != null:
		_pause_hint.text = MatchMenu.hint(online_mode)
	if _pause_button != null:
		_pause_button.label = MatchMenu.pause_label(online_mode)
	if value:
		_reset_touch_controls()
	_pause_overlay.visible = value

func _reset_touch_controls() -> void:
	if _joystick:
		_joystick.reset()
	if _attack_button:
		_attack_button.reset()

func is_modal() -> bool:
	return _pause_overlay.visible or _result_overlay.visible

func show_result(winner: String, local: Dictionary) -> void:
	result_shown = true
	_death_overlay.visible = false
	var victory := winner == local_team
	_result_title.text = "胜  利" if victory else "战  败"
	_result_title.add_theme_color_override("font_color", GameTheme.GOLD_LIGHT if victory else Color(0.9, 0.36, 0.3))
	_result_sub.text = "敌方主堡已被摧毁" if victory else "我方主城已被摧毁"
	var scores: Dictionary = snapshot.get("scores", {})
	var team_score: Dictionary = scores.get(local_team, {})
	_result_stats.text = "击杀 %d   ·   阵亡 %d   ·   推塔 %d   ·   对局时长 %s" % [
		int(local.get("kills", 0)),
		int(local.get("deaths", 0)),
		int(team_score.get("towers", 0)),
		_format_time(float(snapshot.get("time", 0.0))),
	]
	_result_overlay.visible = true
	announce("对局结束", GameTheme.GOLD_LIGHT, 1.5)

func _format_time(seconds: float) -> String:
	var total := int(maxf(0.0, seconds))
	return "%02d:%02d" % [total / 60, total % 60]
