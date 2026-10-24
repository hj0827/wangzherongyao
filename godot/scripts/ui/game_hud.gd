extends Control
class_name GameHUD

signal skill_pressed(slot: String)
signal skill_aim_released(slot: String, screen_pos: Vector2, cancelled: bool)
signal attack_mode_changed(mode: String)
signal lock_changed(target_id: int)
signal buy_item_requested(item_id: String)
signal sell_item_requested(slot_index: int)
signal leave_requested
signal resume_requested
signal move_changed(value: Vector2)
signal attack_changed(held: bool)
signal pause_requested
# 按住小地图 → 请求把镜头移到该世界坐标；松手 → 立刻回到英雄。
signal map_focus_requested(world: Vector2)
signal map_focus_released

const GameTheme = preload("res://scripts/ui/game_theme.gd")
const HeroDefs = preload("res://sim/hero_defs.gd")
const SkillSystem = preload("res://sim/skill_system.gd")
const MatchMenu = preload("res://scripts/game/match_menu.gd")
const Minimap = preload("res://scripts/ui/minimap.gd")
const SkillButton = preload("res://scripts/ui/skill_button.gd")
const SkillIndicator = preload("res://scripts/ui/skill_indicator.gd")
const CancelCastZone = preload("res://scripts/ui/cancel_cast_zone.gd")
const AttackCluster = preload("res://scripts/ui/attack_cluster.gd")
const ShopPanel = preload("res://scripts/ui/shop_panel.gd")
const Scoreboard = preload("res://scripts/ui/scoreboard.gd")
const TouchJoystick = preload("res://scripts/ui/touch_joystick.gd")
const TouchActionButton = preload("res://scripts/ui/touch_action_button.gd")
const TouchLayout = preload("res://scripts/ui/touch_layout.gd")
const HudLayout = preload("res://scripts/ui/hud_layout.gd")

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
var _recall_button: TouchActionButton
var _teleport_button: TouchActionButton

var _score_blue: Label
var _score_red: Label
var _timer_label: Label
var _wave_label: Label
var _objective_label: Label
var _score_panel: PanelContainer
var _econ_panel: PanelContainer
var _econ_label: Label
var _econ_sub: Label
var _scoreboard: Control
var _minimap_panel: PanelContainer
var _hero_panel: PanelContainer
var _hint_box: Label
# 分区表：视口一变就重算，所有常驻面板都从这里取矩形，不再各写锚点。
var _layout: Dictionary = {}
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
var _skill_w: SkillButton
var _skill_e: SkillButton
var _skill_r: SkillButton
var _summoner_button: SkillButton
var _attack_cluster: AttackCluster
var _skill_aim_layer: Control
var _aim_slot := ""
var _aim_from := Vector2.ZERO
var _aim_touch := Vector2.ZERO
var _cancel_state: Dictionary = CancelCastZone.create_state()
var _cancel_center := Vector2.ZERO
const CANCEL_ZONE_RADIUS := 66.0
# 键位提示只当新手引导：进场显示 HINT_SECONDS 秒后淡出，之后在 Esc 菜单里可查。
const KEY_HINTS := "左键 移动   ·   右键 / 空格 普攻   ·   Q / 1 / E / R 技能   ·   F 召唤师   ·   B 回城   ·   T 传送   ·   滚轮 缩放"
const HINT_SECONDS := 14.0
var _shop_panel: ShopPanel
var _shop_button: Button
var _gold_label: Label
var _minimap: Minimap
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
var _bush_label: Label

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
	_build_econ_strip()
	_build_bush_indicator()
	_build_minimap()
	_build_feed()
	_build_announcement()
	_build_bottom_panel()
	_build_attack_cluster()
	_build_hints()
	if touch_mode:
		_build_touch_controls()
		_build_skill_aim_layer()
	_build_death_overlay()
	_build_pause_overlay()
	_build_result_overlay()
	_build_loading_overlay()
	_build_shop()
	_build_scoreboard()
	_apply_layout()
	resized.connect(_apply_layout)
	set_process_unhandled_key_input(true)

# 按当前视口重算所有常驻面板的位置。窗口拉伸、旋转屏、改分辨率都走这里。
func _apply_layout() -> void:
	var viewport := size
	if viewport.x < 1.0 or viewport.y < 1.0:
		# 还没进场景树（无头测试）时按设计基准算，保证取值确定、不依赖节点尺寸。
		viewport = Vector2(1600.0, 900.0)
	_layout = HudLayout.zones(viewport, touch_mode)
	_place_zone(_score_panel, _layout["score"])
	# 经济条贴在比分板右侧；窗口太窄时分区宽度会被压到 0，这时整条隐藏，
	# 而不是让它压在商店按钮上。
	var econ_rect: Rect2 = _layout.get("econ", Rect2())
	_econ_panel.visible = econ_rect.size.x >= 100.0
	_place_zone(_econ_panel, econ_rect)
	_place_zone(_minimap_panel, _layout["minimap"])
	_place_zone(_feed_box, _layout["feed"])
	_place_zone(_bush_label, _layout["bush"])
	_place_zone(_hero_panel, _layout["hero"])
	_place_zone(_shop_button, _layout["shop"])
	_place_zone(_hint_box, _layout["hints"])
	if touch_mode:
		_place_zone(_joystick, _layout["joystick"])
	else:
		# 键鼠：技能条贴右下，攻击模式条压在它上面（低频率控件不进战场正中）。
		_place_zone(_attack_cluster, _layout["mode"])
		var slots := ["q", "w", "e", "r", "summoner"]
		for i in slots.size():
			_place_zone(_skill_button_for(slots[i]), HudLayout.skill_rect(_layout["skills"], i))

func _place_zone(node: Control, rect: Rect2) -> void:
	if node == null:
		return
	node.anchor_left = 0.0
	node.anchor_top = 0.0
	node.anchor_right = 0.0
	node.anchor_bottom = 0.0
	node.offset_left = rect.position.x
	node.offset_top = rect.position.y
	node.offset_right = rect.end.x
	node.offset_bottom = rect.end.y

func _build_top_bar() -> void:
	_score_panel = PanelContainer.new()
	_score_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_score_panel.add_theme_stylebox_override("panel", GameTheme.style(Color(0.02, 0.035, 0.05, 0.9), Color(0.55, 0.44, 0.24, 0.65), 1, 9))
	add_child(_score_panel)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 28)
	_score_panel.add_child(row)
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

# 顶栏常驻的经济差：只回答「现在哪边钱多、多多少」。
# 明细（每人的等级 / KDA / 装备）在 Tab 计分板里，不占常驻视野。
func _build_econ_strip() -> void:
	_econ_panel = PanelContainer.new()
	_econ_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_econ_panel.add_theme_stylebox_override("panel", GameTheme.style(Color(0.02, 0.035, 0.05, 0.9), Color(0.55, 0.44, 0.24, 0.5), 1, 9))
	add_child(_econ_panel)
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 1)
	_econ_panel.add_child(box)
	# 主行说「谁领先多少」，副行给两队总额。
	# 只写差值时，落后方为 0 会和差值撞成同一个数字（1.5k · 1.5k），读起来像重复。
	_econ_label = _make_label("经济 ——", 15, GameTheme.MUTED)
	_econ_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_econ_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	box.add_child(_econ_label)
	_econ_sub = _make_label("蓝 —— · 红 ——", 12, GameTheme.MUTED)
	_econ_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_econ_sub.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	box.add_child(_econ_sub)

func _build_scoreboard() -> void:
	_scoreboard = Scoreboard.new()
	_scoreboard.setup(touch_mode)
	add_child(_scoreboard)

# 只在计分板打开时刷新它：关着的时候没人看，没必要每帧重排文字。
func _refresh_economy(board: Dictionary, local_owner: String) -> void:
	var totals: Dictionary = board.get("net_worth", {})
	var blue := int(totals.get("blue", 0))
	var red := int(totals.get("red", 0))
	var diff := blue - red
	if _econ_label != null:
		if absi(diff) < 50:
			_econ_label.text = "经济持平"
			_econ_label.add_theme_color_override("font_color", GameTheme.MUTED)
		elif diff > 0:
			_econ_label.text = "蓝方领先 %s" % _short_gold(diff)
			_econ_label.add_theme_color_override("font_color", GameTheme.BLUE)
		else:
			_econ_label.text = "红方领先 %s" % _short_gold(-diff)
			_econ_label.add_theme_color_override("font_color", GameTheme.RED)
	if _econ_sub != null:
		_econ_sub.text = "蓝 %s · 红 %s" % [_short_gold(blue), _short_gold(red)]
	if _scoreboard != null and _scoreboard.is_open():
		_scoreboard.set_state(board, local_owner)

func _short_gold(value: int) -> String:
	if value >= 1000:
		return "%.1fk" % (float(value) / 1000.0)
	return str(value)

func _build_bush_indicator() -> void:
	_bush_label = _make_label("草丛隐匿 · 敌方无法直接看到你", 15, Color(0.62, 0.92, 0.66))
	_bush_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_bush_label.add_theme_color_override("font_outline_color", Color(0.0, 0.08, 0.03, 0.85))
	_bush_label.add_theme_constant_override("outline_size", 4)
	_bush_label.visible = false
	add_child(_bush_label)

func set_bush_hidden(value: bool) -> void:
	if _bush_label == null:
		return
	_bush_label.visible = value

func _build_minimap() -> void:
	_minimap_panel = PanelContainer.new()
	_minimap_panel.add_theme_stylebox_override("panel", GameTheme.style(Color(0.02, 0.035, 0.05, 0.82), Color(0.55, 0.44, 0.24, 0.65), 1, 9))
	add_child(_minimap_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	_minimap_panel.add_child(box)
	_minimap = Minimap.new()
	_minimap.custom_minimum_size = Minimap.DISPLAY_SIZE
	_minimap.location_clicked.connect(_on_minimap_location_clicked)
	_minimap.location_dragged.connect(_on_minimap_location_dragged)
	_minimap.drag_finished.connect(_on_minimap_drag_finished)
	box.add_child(_minimap)
	_objective_label = _make_label("防御塔 蓝 0 : 0 红", 12, GameTheme.MUTED)
	_objective_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# 操作说明不再常驻两行（长期压着左侧视野），改成悬停提示。
	_minimap.tooltip_text = "按住地图拖动查看其他区域，松手回到自己"
	box.add_child(_objective_label)

func _on_minimap_location_clicked(world: Vector2) -> void:
	map_focus_requested.emit(world)

# 按住拖动时持续改目标，相机就跟着手指走。
func _on_minimap_location_dragged(world: Vector2) -> void:
	map_focus_requested.emit(world)

# 松手立刻回位，不再停留。
func _on_minimap_drag_finished(_world: Vector2) -> void:
	map_focus_released.emit()

# 相机视野框同步给小地图；valid=false 时清掉。
func set_camera_view(view: Dictionary) -> void:
	if _minimap == null:
		return
	_minimap.set_camera_view(view)

func _build_feed() -> void:
	_feed_box = VBoxContainer.new()
	_feed_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
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
	_hero_panel = PanelContainer.new()
	_hero_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hero_panel.add_theme_stylebox_override("panel", GameTheme.style(Color(0.02, 0.04, 0.055, 0.92), Color(0.55, 0.44, 0.24, 0.7), 1, 12))
	add_child(_hero_panel)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	_hero_panel.add_child(row)

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
	# 击杀/阵亡和金币并成一行：状态卡少一行就矮 18px，压住战场的面积直接少一截。
	var meta_row := HBoxContainer.new()
	meta_row.add_theme_constant_override("separation", 8)
	info.add_child(meta_row)
	_kd_label = _make_label("击杀 0 / 阵亡 0", 13, GameTheme.MUTED)
	_kd_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	meta_row.add_child(_kd_label)
	_gold_label = _make_label("金币 0", 13, GameTheme.GOLD)
	meta_row.add_child(_gold_label)

	if not touch_mode:
		# 技能从状态卡里搬出来，单独贴右下角：状态卡只回答「我是谁 / 我还剩多少血」。
		_skill_q = _create_skill("q", "Q", GameTheme.GOLD)
		add_child(_skill_q)
		# 键盘 W 已用于走位，第二技能改绑数字键 1，HUD 直接标注实际键位。
		_skill_w = _create_skill("w", "1", Color(0.68, 0.86, 0.58))
		add_child(_skill_w)
		_skill_e = _create_skill("e", "E", Color(0.55, 0.75, 1.0))
		add_child(_skill_e)
		_skill_r = _create_skill("r", "R", Color(0.95, 0.62, 0.45))
		add_child(_skill_r)
		_summoner_button = _create_skill("summoner", "F", Color(0.5, 0.86, 0.76), _summoner_name())
		add_child(_summoner_button)
	var hero_def: Dictionary = HeroDefs.get_hero(hero_type)
	_role_label.text = "%s · %s" % [hero_def.role, hero_def.title]

func _create_skill(slot: String, key: String, accent: Color, display_name := "") -> SkillButton:
	var button := SkillButton.new()
	button.slot = slot
	button.key_text = key
	button.accent = accent
	button.touch_mode = touch_mode
	if display_name == "":
		display_name = str(HeroDefs.get_hero(hero_type).get(slot, {}).get("name", "技能"))
	button.skill_name = display_name
	if touch_mode:
		button.drag_started.connect(_on_skill_drag_started)
		button.drag_updated.connect(_on_skill_drag_updated)
		button.drag_released.connect(_on_skill_drag_released)
	else:
		button.pressed.connect(func(): skill_pressed.emit(slot))
	return button

func _build_skill_aim_layer() -> void:
	_skill_aim_layer = Control.new()
	_skill_aim_layer.name = "SkillAimLayer"
	_skill_aim_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_skill_aim_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_skill_aim_layer.visible = false
	_skill_aim_layer.draw.connect(func(): _draw_skill_aim(_skill_aim_layer))
	add_child(_skill_aim_layer)

func _skill_button_for(slot: String) -> SkillButton:
	match slot:
		"q":
			return _skill_q
		"w":
			return _skill_w
		"e":
			return _skill_e
		"r":
			return _skill_r
		"summoner":
			return _summoner_button
	return null

func _cancel_zone_position() -> Vector2:
	return Vector2(size.x * 0.5, 150.0)

func _on_skill_drag_started(slot: String, screen_pos: Vector2) -> void:
	if _skill_aim_layer == null:
		return
	var button := _skill_button_for(slot)
	if button == null:
		return
	_aim_slot = slot
	_aim_from = button.get_global_rect().get_center()
	_aim_touch = screen_pos
	_cancel_center = _cancel_zone_position()
	CancelCastZone.update_state(_cancel_state, screen_pos, _cancel_center, CANCEL_ZONE_RADIUS)
	_skill_aim_layer.visible = true
	_skill_aim_layer.queue_redraw()

func _on_skill_drag_updated(slot: String, screen_pos: Vector2) -> void:
	if slot != _aim_slot or _skill_aim_layer == null:
		return
	_aim_touch = screen_pos
	CancelCastZone.update_state(_cancel_state, screen_pos, _cancel_center, CANCEL_ZONE_RADIUS)
	_skill_aim_layer.queue_redraw()

func _on_skill_drag_released(slot: String, screen_pos: Vector2) -> void:
	if slot != _aim_slot:
		return
	_aim_touch = screen_pos
	var cancelled := CancelCastZone.is_inside(screen_pos, _cancel_center, CANCEL_ZONE_RADIUS)
	_aim_slot = ""
	if _skill_aim_layer != null:
		_skill_aim_layer.visible = false
	skill_aim_released.emit(slot, screen_pos, cancelled)

func _draw_skill_aim(layer: Control) -> void:
	if _aim_slot == "":
		return
	var cancelling := bool(_cancel_state.get("cancelling", false))
	var color := CancelCastZone.get_indicator_color(cancelling)
	var to_touch := _aim_touch - _aim_from
	var length := to_touch.length()
	if length > 4.0:
		var quad := SkillIndicator.generate_line_points(_aim_from, to_touch / length, minf(length, 560.0), 26.0)
		var fill := color
		fill.a = 0.16
		layer.draw_colored_polygon(quad, fill)
		layer.draw_polyline(PackedVector2Array([_aim_from, _aim_touch]), color, 2.0)
	var ring_points := SkillIndicator.generate_circle_points(30.0, 24)
	var ring := PackedVector2Array()
	for point in ring_points:
		ring.append(_aim_touch + point)
	layer.draw_polyline(ring, color, 2.5)
	layer.draw_circle(_cancel_center, CANCEL_ZONE_RADIUS, Color(color.r, color.g, color.b, 0.14))
	layer.draw_arc(_cancel_center, CANCEL_ZONE_RADIUS, 0.0, TAU, 48, color, 3.0, true)
	layer.draw_string(
		GameTheme.FONT_REGULAR,
		_cancel_center + Vector2(-CANCEL_ZONE_RADIUS, 6.0),
		"拖到这里取消",
		HORIZONTAL_ALIGNMENT_CENTER,
		CANCEL_ZONE_RADIUS * 2.0,
		14,
		color
	)

func _summoner_name() -> String:
	return str(SkillSystem.get_summoner_spell("flash").get("name", "召唤"))

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

func _build_attack_cluster() -> void:
	_attack_cluster = AttackCluster.new()
	_attack_cluster.setup(touch_mode)
	_attack_cluster.mode_changed.connect(func(mode: String): attack_mode_changed.emit(mode))
	_attack_cluster.lock_changed.connect(func(target_id: int): lock_changed.emit(target_id))
	# 位置统一由 _apply_layout 从分区表取；这里只建节点。
	add_child(_attack_cluster)

func set_targeting_state(mode: String, target_id: int) -> void:
	if _attack_cluster != null:
		_attack_cluster.set_targeting_state(mode, target_id)

func _build_hints() -> void:
	# 手机端不铺常驻键位提示（触屏控件自己会说话）。
	# 键鼠端也只当新手引导：进场显示十几秒后淡出，之后按 Esc 还能在菜单里查到。
	if touch_mode:
		return
	_hint_box = _make_label(KEY_HINTS, 15, Color(0.86, 0.9, 0.94, 0.95))
	_hint_box.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	# 这行会压在草地、水面、桥面上，背景亮度差得远，描边必须够重才读得清。
	_hint_box.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.95))
	_hint_box.add_theme_constant_override("outline_size", 5)
	# 窄窗口下区域会变窄：宁可省略号收尾，也不要溢出到右下角操作簇底下。
	_hint_box.clip_text = true
	_hint_box.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	add_child(_hint_box)
	if is_inside_tree():
		_fade_hints_after(HINT_SECONDS)

func _fade_hints_after(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout
	if _hint_box == null or not is_instance_valid(_hint_box):
		return
	var tween := create_tween()
	tween.tween_property(_hint_box, "modulate:a", 0.0, 1.2)
	tween.tween_callback(func():
		if _hint_box != null and is_instance_valid(_hint_box):
			_hint_box.visible = false
	)

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
	_skill_w = _create_skill("w", "1", Color(0.68, 0.86, 0.58))
	add_child(_skill_w)
	_place_touch_skill(_skill_w, 1)
	_skill_e = _create_skill("e", "E", Color(0.55, 0.75, 1.0))
	add_child(_skill_e)
	_place_touch_skill(_skill_e, 2)
	_skill_r = _create_skill("r", "R", Color(0.95, 0.62, 0.45))
	add_child(_skill_r)
	_place_touch_skill(_skill_r, 3)
	_summoner_button = _create_skill("summoner", "F", Color(0.5, 0.86, 0.76), _summoner_name())
	add_child(_summoner_button)
	_place_utility_button(_summoner_button, TouchLayout.UTILITY_SUMMONER_RECT)

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

	_recall_button = TouchActionButton.new()
	_recall_button.touch_mode = true
	_recall_button.label = "回城"
	_recall_button.hint = "B"
	_recall_button.accent = Color(0.45, 0.78, 0.62)
	_recall_button.pressed.connect(func(): skill_pressed.emit("recall"))
	add_child(_recall_button)
	_place_utility_button(_recall_button, TouchLayout.UTILITY_RECALL_RECT)

	_teleport_button = TouchActionButton.new()
	_teleport_button.touch_mode = true
	_teleport_button.label = "传送"
	_teleport_button.hint = "T"
	_teleport_button.accent = Color(0.42, 0.8, 0.9)
	_teleport_button.pressed.connect(func(): skill_pressed.emit("teleport"))
	add_child(_teleport_button)
	_place_utility_button(_teleport_button, TouchLayout.UTILITY_TELEPORT_RECT)

func _place_utility_button(button: Control, offsets: Rect2) -> void:
	button.anchor_left = 1.0
	button.anchor_top = 1.0
	button.anchor_right = 1.0
	button.anchor_bottom = 1.0
	button.offset_left = offsets.position.x
	button.offset_top = offsets.position.y
	button.offset_right = offsets.end.x
	button.offset_bottom = offsets.end.y

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

func _build_shop() -> void:
	_shop_button = Button.new()
	_shop_button.text = "商店 (P)"
	_shop_button.focus_mode = Control.FOCUS_NONE
	_shop_button.pressed.connect(toggle_shop)
	add_child(_shop_button)

	_shop_panel = ShopPanel.new()
	_shop_panel.setup(hero_type, touch_mode)
	_shop_panel.buy_requested.connect(func(item_id: String): buy_item_requested.emit(item_id))
	_shop_panel.sell_requested.connect(func(slot: int): sell_item_requested.emit(slot))
	_shop_panel.quick_buy_requested.connect(func(item_id: String): buy_item_requested.emit(item_id))
	_shop_panel.close_requested.connect(close_shop)
	add_child(_shop_panel)

func toggle_shop() -> void:
	if _shop_panel == null:
		return
	_shop_panel.visible = not _shop_panel.visible
	if _shop_panel.visible and _shop_button != null:
		_shop_button.text = "关闭商店"
	elif _shop_button != null:
		_shop_button.text = "商店 (P)"

func close_shop() -> void:
	if _shop_panel != null:
		_shop_panel.visible = false
	if _shop_button != null:
		_shop_button.text = "商店 (P)"

func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey):
		return
	var key := event as InputEventKey
	if key.pressed and not key.echo and key.keycode == KEY_TAB:
		# Tab 是「看一眼就关」的临时面板，和商店一样属于 UI 层，不进 sim 输入。
		if _scoreboard != null:
			_scoreboard.toggle()
		accept_event()
		return
	if key.pressed and not key.echo and key.keycode == KEY_P:
		toggle_shop()
		accept_event()

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
	var board: Dictionary = data.get("board", {})
	_refresh_economy(board, str(local.get("owner_id", "")))
	_timer_label.text = _format_time(float(data.get("time", 0.0)))
	_wave_label.text = "第 %d 波" % int(data.get("wave", 1))
	var objectives: Dictionary = data.get("objectives", {})
	var spawn_timer := float(objectives.get("spawn_timer", 0.0))
	if spawn_timer > 0.0:
		_objective_label.text = "暴君/主宰 %s" % _format_time(spawn_timer)
	else:
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
	var gold := int(local.get("gold", 0))
	if _gold_label != null:
		_gold_label.text = "金币 %d" % gold
	if _shop_panel != null:
		_shop_panel.set_state(gold, local.get("inventory", []), str(local.get("hero_type", hero_type)))
	var hero_def: Dictionary = HeroDefs.get_hero(str(local.get("hero_type", hero_type)))
	var role_text := "%s · %s" % [hero_def.role, hero_def.title]
	if float(local.get("buff_blue_timer", 0.0)) > 0.0:
		role_text += " [蓝BUFF %.0fs]" % float(local.get("buff_blue_timer", 0.0))
	if float(local.get("buff_red_timer", 0.0)) > 0.0:
		role_text += " [红BUFF %.0fs]" % float(local.get("buff_red_timer", 0.0))
	if bool(local.get("recalling", false)):
		role_text += " [回城中...]"
	if bool(local.get("teleporting", false)):
		role_text += " [传送中...]"
	_role_label.text = role_text
	var alive := bool(local.get("alive", true))
	_apply_skill_state(_skill_q, local, hero_def.q, "skill_q_cd", mp, not alive)
	_apply_skill_state(_skill_w, local, hero_def.w, "skill_w_cd", mp, not alive)
	_apply_skill_state(_skill_e, local, hero_def.e, "skill_e_cd", mp, not alive)
	_apply_skill_state(_skill_r, local, hero_def.r, "skill_r_cd", mp, not alive)
	if _summoner_button != null:
		var spell := SkillSystem.get_summoner_spell(str(local.get("summoner_spell", "flash")))
		_summoner_button.set_state(
			float(local.get("summoner_cd", 0.0)),
			float(spell.get("cooldown", 90.0)),
			str(spell.get("name", "召唤")),
			true,
			not alive
		)

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

	if _attack_cluster != null:
		_attack_cluster.refresh_enemies(data.get("entities", []), local_team)
	_minimap.set_snapshot(data, local_owner, local_team)
	if ended and not result_shown:
		show_result(str(data.get("winner", "")), local)

func _apply_skill_state(button: SkillButton, local: Dictionary, skill_def: Dictionary, cd_key: String, mp: float, dead: bool) -> void:
	if button == null:
		return
	button.set_state(
		float(local.get(cd_key, 0.0)),
		float(skill_def.get("cooldown", 1.0)),
		str(skill_def.get("name", "技能")),
		mp >= float(skill_def.get("cost", 0.0)),
		dead
	)

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
	while _feed_box.get_child_count() > 5:
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
		# 键位表从战场常驻位置上撤走了，这里补一份，随时按键可查。
		var hint := MatchMenu.hint(online_mode)
		if not touch_mode:
			hint += "\n" + KEY_HINTS
		_pause_hint.text = hint
	if _pause_button != null:
		_pause_button.label = MatchMenu.pause_label(online_mode)
	if value:
		_reset_touch_controls()
		close_shop()
	_pause_overlay.visible = value

func _reset_touch_controls() -> void:
	if _joystick:
		_joystick.reset()
	if _attack_button:
		_attack_button.reset()
	for button in [_skill_q, _skill_w, _skill_e, _skill_r, _summoner_button]:
		if button != null:
			button.cancel_drag()
	_aim_slot = ""
	if _skill_aim_layer != null:
		_skill_aim_layer.visible = false

func is_modal() -> bool:
	return _pause_overlay.visible or _result_overlay.visible

func show_result(winner: String, local: Dictionary) -> void:
	result_shown = true
	close_shop()
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
