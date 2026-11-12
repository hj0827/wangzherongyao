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
# 快捷信号（项 11.1）：轮盘打开时 arena 记下当前指向；选择某一类后由 arena 解析落点。
# 长按小地图会带上明确的落点（Vector2.INF = 没有指定，让 arena 用准星/英雄脚下）。
signal ping_wheel_opened(target: Vector2)
signal ping_requested(kind: String)
# 手动加点（项 2 链路 6 / B7）：触屏没有 Ctrl+技能，必须给一个可点的入口。
signal upgrade_requested(slot: String)

const GameTheme = preload("res://scripts/ui/game_theme.gd")
const HeroDefs = preload("res://sim/hero_defs.gd")
const ControlRules = preload("res://sim/control_rules.gd")
const SkillSystem = preload("res://sim/skill_system.gd")
const MatchMenu = preload("res://scripts/game/match_menu.gd")
const Minimap = preload("res://scripts/ui/minimap.gd")
const SkillButton = preload("res://scripts/ui/skill_button.gd")
const SkillIndicator = preload("res://scripts/ui/skill_indicator.gd")
const CancelCastZone = preload("res://scripts/ui/cancel_cast_zone.gd")
const AttackCluster = preload("res://scripts/ui/attack_cluster.gd")
const AttackModeButton = preload("res://scripts/ui/attack_mode_button.gd")
const LockBar = preload("res://scripts/ui/lock_bar.gd")
const ShopPanel = preload("res://scripts/ui/shop_panel.gd")
const SettingsPanel = preload("res://scripts/ui/settings_panel.gd")
const Scoreboard = preload("res://scripts/ui/scoreboard.gd")
const TouchJoystick = preload("res://scripts/ui/touch_joystick.gd")
const TouchActionButton = preload("res://scripts/ui/touch_action_button.gd")
const TouchLayout = preload("res://scripts/ui/touch_layout.gd")
const HudLayout = preload("res://scripts/ui/hud_layout.gd")
const RecallBar = preload("res://scripts/ui/recall_bar.gd")
const PingRules = preload("res://sim/ping_rules.gd")

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
var _recall_bar: RecallBar
var _recall_button: TouchActionButton
var _teleport_button: TouchActionButton

var _score_blue: Label
var _score_red: Label
var _timer_label: Label
var _wave_label: Label
## 手机端把两队比分折进一行（「0  vs  0」），桌面上是左右两块队伍名，这个节点为空。
var _score_line: Label
## 小地图下方那行左边的金币。手机端没有横着的状态卡，钱要在左上角一眼看到。
var _map_gold_label: Label
## 客机延迟读数：紧挨金币行右侧，主机不显示（自己到自己的 RTT 没有意义）。
var _rtt_label: Label
var _shown_rtt := -2
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
# 手动 _ready() 后再进树时，引擎会再调一次 _ready；没有这道闸就会整份 HUD 建两遍。
var _built := false
var _hp_bar: ProgressBar
var _hp_text: Label
var _hp_style: StyleBoxFlat
var _equip_icons: Array[TextureRect] = []
var _status_pips: Array[PanelContainer] = []
var _status_icons: Array[TextureRect] = []
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
# 触屏端的攻击模式是贴在攻击键旁的三颗圆按钮（桌面端仍是 AttackCluster 横条）。
var _mode_buttons: Array[Control] = []
var _lock_bar: LockBar
# arena 每 20Hz 送一次「敌人 id → 屏幕坐标」，锁定条的连线靠它定位。
var _enemy_screens: Dictionary = {}
var _attack_mode_local := "default"
var _locked_target_local := -1
var _skill_aim_layer: Control
var _aim_slot := ""
var _aim_from := Vector2.ZERO
var _aim_touch := Vector2.ZERO
var _cancel_state: Dictionary = CancelCastZone.create_state()
var _cancel_center := Vector2.ZERO
const CANCEL_ZONE_RADIUS := 66.0
# 键位提示只当新手引导：进场显示 HINT_SECONDS 秒后淡出，之后在 Esc 菜单里可查。
# 原来是一行 76 个字硬塞进 840px（15px 字 + 5px 黑描边），实机直接裁成一串碎片。
# 现在分成两行、每行只放 4~5 组键位，并且垫一层底板，水面上也读得出来。
const KEY_HINT_LINES := [
	"左键 移动   ·   右键 / 空格 普攻   ·   Q / 1 / E / R 技能   ·   F 召唤师",
	"B 回城   ·   T 传送   ·   G 快捷信号   ·   Ctrl+技能 升级   ·   滚轮 缩放视角   ·   Tab 计分板   ·   Esc 暂停",
]
const KEY_HINTS := "左键 移动   ·   右键 / 空格 普攻   ·   Q / 1 / E / R 技能   ·   F 召唤师   ·   B 回城   ·   T 传送   ·   Ctrl+技能 升级   ·   滚轮 缩放视角   ·   Tab 计分板   ·   Esc 暂停"

## 触屏端攻击模式的三个圆按钮。id 与 AttackCluster.MODES 是同一套 attack_mode 值
## （sim 只认 id），label 缩短到两个字：76px 的圆里三个字会挤成一条。
const TOUCH_MODE_ENTRIES := [
	{"id": "default", "label": "普攻"},
	{"id": "minion", "label": "补刀"},
	{"id": "tower", "label": "推塔"},
]
const HINT_SECONDS := 14.0
# 小地图那行金币的字号。比旁边的塔数（13）大一档，读起来是「钱」不是「附注」。
const GOLD_READOUT_SIZE := 18
var _shop_panel: ShopPanel
var _shop_button: Button
var _gold_label: Label
var _minimap: Minimap
var _portrait: TextureRect
var _feed_box: VBoxContainer
var _announce_panel: PanelContainer
var _announce_label: Label
var _announce_tween: Tween
# 击杀横幅（UI-04）：640×160，与 kill_banner.png 的 4:1 同比例，不被拉伸。
var _kill_banner: Control
var _kill_banner_bg: TextureRect
var _kill_banner_killer: TextureRect
var _kill_banner_victim: TextureRect
var _kill_banner_killer_frame: PanelContainer
var _kill_banner_victim_frame: PanelContainer
var _kill_banner_text: Label
var _kill_banner_emblem: TextureRect
var _kill_banner_tween: Tween
var _death_overlay: Control
var _death_countdown: Label
var _death_killer_label: Label
var _result_overlay: Control
var _result_title: Label
var _result_badge: Label
var _result_avatar: TextureRect
var _result_bg: TextureRect
var _result_medal: TextureRect
var _result_sub: Label
var _result_stats: Label
# UI-06 结算数据条：输出 / 承伤 / 参团。数值取快照里本队英雄的相对峰值。
var _result_bars: Dictionary = {}
var _like_button: Button
var _likes := 0
const RESULT_BAR_ROWS := [
	{"key": "dealt", "label": "输出"},
	{"key": "taken", "label": "承伤"},
	{"key": "join", "label": "参团"},
]
var _pause_overlay: Control
var _pause_title: Label
var _pause_hint: Label
var _loading_overlay: Control
var _bush_label: Label
# 快捷信号：一颗常驻入口 + 四选一浮层；标点本身由 arena 广播、这里只管显示。
var _ping_button: Button
var _ping_panel: PanelContainer
var _pings: Array = []
const PING_LIFETIME := 4.0
# FX-11 低血红晕：全屏径向渐变，只在血量低于 30% 时按缺失比例淡入。
var _low_health: TextureRect
# 手动加点：有剩余点数时才出现的「加点」按钮 + 四技能浮层（仅触屏）。
var _level_button: Button
var _level_panel: PanelContainer
var _level_buttons: Dictionary = {}

func setup(owner_id: String, team: String, type_id: String, display: String, mobile := false, online := false) -> void:
	local_owner = owner_id
	local_team = team
	hero_type = type_id
	player_name = display
	touch_mode = mobile
	online_mode = online

func _ready() -> void:
	if _built:
		return
	_built = true
	theme = GameTheme.theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# 红晕必须最先加、压在最底层：晚加会盖住血条和技能键。
	_build_low_health()
	_build_top_bar()
	_build_econ_strip()
	_build_bush_indicator()
	_build_minimap()
	_build_ping_ui()
	_build_level_ui()
	_build_feed()
	_build_announcement()
	_build_kill_banner()
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
	# 标点有生命周期（4 秒倒计时），必须每帧推进；没有标点时 _process 直接返回。
	set_process(true)

# 按当前视口重算所有常驻面板的位置。窗口拉伸、旋转屏、改分辨率都走这里。
func _apply_layout() -> void:
	var viewport := size
	if viewport.x < 1.0 or viewport.y < 1.0:
		# 还没进场景树（无头测试）时按设计基准算，保证取值确定、不依赖节点尺寸。
		viewport = Vector2(1600.0, 900.0)
	var insets := _safe_insets(viewport)
	_layout = HudLayout.zones(viewport, touch_mode, insets)
	if _low_health != null:
		_low_health.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_place_zone(_score_panel, _layout["score"])
	# 经济条贴在比分板右侧；窗口太窄时分区宽度会被压到 0，这时整条隐藏，
	# 而不是让它压在商店按钮上。
	var econ_rect: Rect2 = _layout.get("econ", Rect2())
	_econ_panel.visible = econ_rect.size.x >= 100.0
	_place_zone(_econ_panel, econ_rect)
	_place_zone(_minimap_panel, _layout["minimap"])
	# 快捷信号入口贴在小地图右侧，浮层在底部中间弹出。
	var mini: Rect2 = _layout["minimap"]
	_place_zone(_ping_button, Rect2(mini.end.x + 8.0, mini.position.y, 104.0, 56.0))
	if _ping_panel != null:
		_place_zone(_ping_panel, Rect2(
			(viewport.x - 440.0) * 0.5,
			viewport.y - (300.0 if touch_mode else 240.0),
			440.0,
			108.0
		))
	# 加点入口贴在技能条左上角；桌面隐藏，浮层在技能条上方弹出。
	if _level_button != null:
		var skills: Rect2 = _layout["skills"]
		_place_zone(_level_button, Rect2(skills.position.x - 104.0, skills.end.y - 48.0, 96.0, 44.0))
	if _level_panel != null:
		_place_zone(_level_panel, Rect2(
			(viewport.x - 440.0) * 0.5,
			viewport.y - (370.0 if touch_mode else 310.0),
			440.0,
			108.0
		))
	_place_zone(_feed_box, _layout["feed"])
	_place_zone(_bush_label, _layout["bush"])
	_place_zone(_hero_panel, _layout["hero"])
	_place_zone(_shop_button, _layout["shop"])
	_place_zone(_hint_box, _layout["hints"])
	if touch_mode:
		_place_zone(_joystick, _layout["joystick"])
		_place_zone(_pause_button, _layout["pause"])
		_place_zone(_recall_bar, _layout["recall"])
		_place_touch_skills(viewport, insets)
		_place_mode_buttons(viewport, insets)
		_place_utility_buttons(viewport, insets)
		_place_attack_button(insets)
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

## 引擎安全区换算。只在 mobile 上生效；桌面端返回 0，窗口移动不会推动 HUD。
func _safe_insets(viewport: Vector2) -> Rect2i:
	return HudLayout.safe_insets(
		Vector2(DisplayServer.window_get_size()),
		DisplayServer.get_display_safe_area(),
		OS.has_feature("mobile"),
		viewport
	)

## 拇指控件都锚在右下角；只用右/下 inset 收缩可用视口，左/上由分区表处理。
func _touch_viewport(viewport: Vector2, insets: Rect2i) -> Vector2:
	return viewport - Vector2(float(insets.size.x), float(insets.size.y))

## 触屏端的攻击模式圆按钮：位置全从 TouchLayout 取，跟攻击键、技能弧共享同一套几何。
func _place_mode_buttons(viewport: Vector2, insets := Rect2i()) -> void:
	var safe := _touch_viewport(viewport, insets)
	var rects := TouchLayout.mode_button_rects(safe)
	for i in _mode_buttons.size():
		if i < rects.size():
			_place_zone(_mode_buttons[i], rects[i])
	if _lock_bar != null:
		_lock_bar.set_viewport_size(safe)

## 回城 / 传送 / 召唤师：底部横排，紧贴技能弧左侧（详见 TouchLayout.utility_button_rects）。
## 顺序从远到近是 回城 → 传送 → 召唤师，召唤师离技能最近。
func _place_utility_buttons(viewport: Vector2, insets := Rect2i()) -> void:
	var rects := TouchLayout.utility_button_rects(_touch_viewport(viewport, insets))
	var nodes := [_recall_button, _teleport_button, _summoner_button]
	for i in nodes.size():
		if i < rects.size():
			_place_zone(nodes[i], rects[i])
	# 召唤师键是 SkillButton（要显示冷却环），它的 custom_minimum_size 是 128x148，
	# 摆进 96 的格子里会被最小尺寸顶大 40px。这里按格子收一次。
	if _summoner_button != null and rects.size() > 0:
		_summoner_button.custom_minimum_size = rects[rects.size() - 1].size

func _build_top_bar() -> void:
	_score_panel = PanelContainer.new()
	_score_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_score_panel.add_theme_stylebox_override("panel", GameTheme.style(Color(0.02, 0.035, 0.05, 0.9), Color(0.55, 0.44, 0.24, 0.65), 1, 9))
	add_child(_score_panel)
	if touch_mode:
		# 手机端照王者那条比分：一列「时间 / 0 vs 0」，不再左右各摆一个
		# 「蓝方 0」「0 红方」的大字 —— 手机屏幕本来就窄，左右两块队伍名会把中间的
		# 时间挤成一条缝，而队伍归属靠颜色（蓝 / 红）已经说清楚了。
		# 波次不进来：80px 高的条装不下三行，硬塞会把「0 vs 0」压成一团糊字。
		var column := VBoxContainer.new()
		column.alignment = BoxContainer.ALIGNMENT_CENTER
		column.add_theme_constant_override("separation", 0)
		_score_panel.add_child(column)
		# 字号卡在 20 / 17：Noto 的实际行高比字号大（26 号字占到 36px），
		# 26+22 两行加 20px 内边距是 87 > SCORE_H(80)，第二行会被 PanelContainer 裁掉。
		# 20+17 两行约 52px，留得下。
		_timer_label = _make_label("00:00", 20, GameTheme.TEXT)
		_timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		column.add_child(_timer_label)
		_score_line = _make_label("0  vs  0", 17, GameTheme.TEXT)
		_score_line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		column.add_child(_score_line)
		return
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
# 明细（每人的等级 / KDA / 装备 / 攻防属性）在 Tab 计分板里。
# 这条本身就是面板的入口 —— 玩家看见「红方领先 658」的第一反应就是想看明细，
# 让他再去找 Tab 键是多余的。点击即开/关，鼠标和触摸都走 gui_input。
func _build_econ_strip() -> void:
	_econ_panel = PanelContainer.new()
	_econ_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_econ_panel.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_econ_panel.tooltip_text = "点击查看双方经济与装备"
	_econ_panel.add_theme_stylebox_override("panel", GameTheme.style(Color(0.02, 0.035, 0.05, 0.9), Color(0.55, 0.44, 0.24, 0.5), 1, 9))
	_econ_panel.gui_input.connect(_on_econ_strip_input)
	_econ_panel.mouse_entered.connect(_on_econ_strip_hover.bind(true))
	_econ_panel.mouse_exited.connect(_on_econ_strip_hover.bind(false))
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

func _on_econ_strip_input(event: InputEvent) -> void:
	if _scoreboard == null:
		return
	# 只认「按下」：松开时再触发一次会立刻把刚打开的面板关掉。
	if event is InputEventMouseButton:
		var click := event as InputEventMouseButton
		if click.button_index == MOUSE_BUTTON_LEFT and click.pressed:
			_scoreboard.toggle()
			accept_event()
	elif event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed:
			_scoreboard.toggle()
			accept_event()

func _on_econ_strip_hover(hovered: bool) -> void:
	if _econ_panel == null:
		return
	var border := Color(0.95, 0.78, 0.38, 0.95) if hovered else Color(0.55, 0.44, 0.24, 0.5)
	_econ_panel.add_theme_stylebox_override("panel", GameTheme.style(Color(0.02, 0.035, 0.05, 0.9), border, 1, 9))

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

## 客机延迟读数。负数 = 不显示（单机/主机/还没测到）。
## 阈值：<80 绿、<160 黄、>=160 红 —— 红不是禁止玩，是提示走位要多留提前量。
func set_rtt(ms: int) -> void:
	if _rtt_label == null or ms == _shown_rtt:
		return
	_shown_rtt = ms
	if ms < 0:
		_rtt_label.text = ""
		return
	_rtt_label.text = "%dms" % ms
	var color := GameTheme.GREEN
	if ms >= 160:
		color = GameTheme.RED
	elif ms >= 80:
		color = Color(0.95, 0.78, 0.3)
	_rtt_label.add_theme_color_override("font_color", color)

func _build_minimap() -> void:
	_minimap_panel = PanelContainer.new()
	_minimap_panel.add_theme_stylebox_override("panel", GameTheme.minimap_frame())
	add_child(_minimap_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	_minimap_panel.add_child(box)
	_minimap = Minimap.new()
	_minimap.custom_minimum_size = Minimap.DISPLAY_SIZE
	_minimap.location_clicked.connect(_on_minimap_location_clicked)
	_minimap.location_dragged.connect(_on_minimap_location_dragged)
	_minimap.drag_finished.connect(_on_minimap_drag_finished)
	_minimap.long_pressed.connect(_on_minimap_long_pressed)
	box.add_child(_minimap)
	_objective_label = _make_label("防御塔 蓝 0 : 0 红", 13, Color(0.78, 0.72, 0.56))
	_objective_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# 操作说明不再常驻两行（长期压着左侧视野），改成悬停提示。
	_minimap.tooltip_text = "按住地图拖动查看其他区域，松手回到自己"
	if touch_mode:
		# 王者的左上角是「小地图 + 一条钱」：手机没有横着的状态卡，
		# 金币必须在这儿露出来，否则玩家得点开商店才知道自己有多少钱。
		# 塔数的字更小，靠右；金币靠左、金色、字号大一档，扫一眼就能读到。
		_map_gold_label = _make_label("71", GOLD_READOUT_SIZE, GameTheme.GOLD_LIGHT)
		_map_gold_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		_map_gold_label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.85))
		_map_gold_label.add_theme_constant_override("outline_size", 4)
		var meta_row := HBoxContainer.new()
		meta_row.add_theme_constant_override("separation", 8)
		box.add_child(meta_row)
		meta_row.add_child(_map_gold_label)
		# 延迟紧跟金币右侧：这是同一行里玩家最常扫的位置。
		_rtt_label = _make_label("", 12, GameTheme.GREEN)
		_rtt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		meta_row.add_child(_rtt_label)
		_objective_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		_objective_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		meta_row.add_child(_objective_label)
	else:
		box.add_child(_objective_label)
		_rtt_label = _make_label("", 12, GameTheme.GREEN)
		_rtt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		box.add_child(_rtt_label)

func _on_minimap_location_clicked(world: Vector2) -> void:
	map_focus_requested.emit(world)

# --- FX-11 低血红晕 ----------------------------------------------------------

func _build_low_health() -> void:
	# 用径向渐变而不是纯色矩形：纯红会整体染色，连小地图都看不清。
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.58, 1.0])
	gradient.colors = PackedColorArray([
		Color(0.0, 0.0, 0.0, 0.0),
		Color(0.72, 0.02, 0.02, 0.0),
		Color(0.92, 0.05, 0.03, 0.6),
	])
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	texture.width = 256
	texture.height = 256
	_low_health = TextureRect.new()
	_low_health.texture = texture
	_low_health.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_low_health.stretch_mode = TextureRect.STRETCH_SCALE
	_low_health.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_low_health.visible = false
	add_child(_low_health)

# 比例来自本机英雄快照；死亡时调用方传 1.0 关掉红晕（复活后再按血量恢复）。
func set_low_health(ratio: float) -> void:
	if _low_health == null:
		return
	var missing := clampf((0.3 - ratio) / 0.3, 0.0, 1.0)
	_low_health.visible = missing > 0.01
	_low_health.modulate.a = missing

# --- 快捷信号（项 11.1）-----------------------------------------------------
# 入口放在小地图右侧：标点是「地图上的事」，挨着地图最符合直觉；
# 四类信号收在一个浮层里，避免再往拇指区塞四颗常驻按钮。

func _build_ping_ui() -> void:
	_ping_button = Button.new()
	_ping_button.text = "信号 (G)"
	_ping_button.focus_mode = Control.FOCUS_NONE
	_ping_button.pressed.connect(_toggle_ping_panel)
	add_child(_ping_button)

	_ping_panel = PanelContainer.new()
	_ping_panel.add_theme_stylebox_override("panel", GameTheme.style(
		Color(0.02, 0.035, 0.05, 0.96), Color(0.55, 0.44, 0.24, 0.8), 1, 10
	))
	_ping_panel.visible = false
	add_child(_ping_panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	_ping_panel.add_child(column)
	var hint := _make_label("发送快捷信号", 13, GameTheme.MUTED)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(hint)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	column.add_child(row)
	for kind in PingRules.KINDS:
		var button := Button.new()
		button.text = PingRules.label(kind)
		button.focus_mode = Control.FOCUS_NONE
		button.custom_minimum_size = Vector2(92, 56)
		button.pressed.connect(_on_ping_choice.bind(kind))
		row.add_child(button)

func _toggle_ping_panel() -> void:
	_show_ping_panel(_ping_panel != null and not _ping_panel.visible)

# target 只在手势入口（长按小地图）传入；按钮/G 键仍走「让 arena 自己解析准星」。
func _show_ping_panel(value: bool, target := Vector2.INF) -> void:
	if _ping_panel == null:
		return
	_ping_panel.visible = value
	if value:
		ping_wheel_opened.emit(target)

func _on_minimap_long_pressed(world: Vector2) -> void:
	_show_ping_panel(true, world)

func _on_ping_choice(kind: String) -> void:
	_show_ping_panel(false)
	ping_requested.emit(kind)

# 收到一条标点（本机或队友）：小地图图标 + 播报条，发送者名来自事件。
func show_ping(event: Dictionary) -> void:
	var kind := str(event.get("kind", ""))
	if not PingRules.is_valid(kind):
		return
	_pings.append({
		"kind": kind,
		"x": float(event.get("x", 0.0)),
		"y": float(event.get("y", 0.0)),
		"duration": PING_LIFETIME,
		"remaining": PING_LIFETIME,
	})
	if _minimap != null:
		_minimap.set_pings(_pings)
	var text := PingRules.feed_text(kind, str(event.get("name", "")))
	# 播报条依赖 Tween，只有进树后才能创建；纯数据测试里 HUD 是游离节点。
	if is_inside_tree():
		add_feed(text, PingRules.color(kind))
		announce(text, PingRules.color(kind), 1.4)

func _process(delta: float) -> void:
	if _pings.is_empty():
		return
	var alive: Array = []
	for ping in _pings:
		ping["remaining"] = float(ping.get("remaining", 0.0)) - delta
		if float(ping["remaining"]) > 0.0:
			alive.append(ping)
	_pings = alive
	if _minimap != null:
		_minimap.set_pings(_pings)

# --- 手动加点（B7）-----------------------------------------------------------
# 只有触屏需要：桌面已有 Ctrl+技能。按钮仅在 skill_points > 0 时出现，
# 点开后再选具体技能，避免把四个「+」常驻压在技能键上误触。

func _build_level_ui() -> void:
	_level_button = Button.new()
	_level_button.text = "加点"
	_level_button.focus_mode = Control.FOCUS_NONE
	_level_button.visible = false
	_level_button.pressed.connect(_toggle_level_panel)
	add_child(_level_button)

	_level_panel = PanelContainer.new()
	_level_panel.add_theme_stylebox_override("panel", GameTheme.style(
		Color(0.02, 0.035, 0.05, 0.96), Color(0.55, 0.44, 0.24, 0.8), 1, 10
	))
	_level_panel.visible = false
	add_child(_level_panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	_level_panel.add_child(column)
	var hint := _make_label("升级哪个技能？", 13, GameTheme.MUTED)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(hint)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	column.add_child(row)
	for slot in ["q", "w", "e", "r"]:
		var button := Button.new()
		button.focus_mode = Control.FOCUS_NONE
		button.custom_minimum_size = Vector2(92, 56)
		button.pressed.connect(_on_level_choice.bind(slot))
		row.add_child(button)
		_level_buttons[slot] = button

func _toggle_level_panel() -> void:
	if _level_panel == null:
		return
	_level_panel.visible = not _level_panel.visible

func _on_level_choice(slot: String) -> void:
	_level_panel.visible = false
	upgrade_requested.emit(slot)

# 每次快照刷新：点数决定按钮显隐，等级决定浮层按钮文案与可用性。
func _sync_level_ui(local: Dictionary) -> void:
	if _level_button == null:
		return
	var points := int(local.get("skill_points", 0))
	_level_button.visible = touch_mode and points > 0
	if points <= 0 and _level_panel != null:
		_level_panel.visible = false
	for slot in _level_buttons.keys():
		var button: Button = _level_buttons[slot]
		var level_key := "skill_%s_level" % slot
		var level := int(local.get(level_key, 0))
		var max_level := HeroDefs.MAX_SKILL_LEVEL_ULT if slot == "r" else HeroDefs.MAX_SKILL_LEVEL_NORMAL
		button.text = "%s Lv%d" % [slot.to_upper(), level]
		button.disabled = level >= max_level or points <= 0

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

# 击杀横幅：底图 + 双方头像 + 中央文字 +（连杀时）上方纹章。
# 位置固定在画面上部中央（横幅不进 hud_layout 分区表：它是瞬时反馈，不是常驻控件）。
func _build_kill_banner() -> void:
	_kill_banner = Control.new()
	_kill_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_kill_banner.anchor_left = 0.5
	_kill_banner.anchor_right = 0.5
	_kill_banner.offset_left = -320.0
	_kill_banner.offset_right = 320.0
	_kill_banner.offset_top = 200.0
	_kill_banner.offset_bottom = 360.0
	_kill_banner.visible = false
	add_child(_kill_banner)

	_kill_banner_bg = TextureRect.new()
	_kill_banner_bg.texture = GameTheme.kill_banner()
	_kill_banner_bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_kill_banner_bg.stretch_mode = TextureRect.STRETCH_SCALE
	_kill_banner_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_kill_banner_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_kill_banner.add_child(_kill_banner_bg)

	_kill_banner_killer_frame = _make_banner_avatar_slot()
	_kill_banner_killer_frame.anchor_top = 0.0
	_kill_banner_killer_frame.anchor_bottom = 0.0
	_kill_banner_killer_frame.offset_left = 14.0
	_kill_banner_killer_frame.offset_right = 94.0
	_kill_banner_killer_frame.offset_top = 40.0
	_kill_banner_killer_frame.offset_bottom = 120.0
	_kill_banner.add_child(_kill_banner_killer_frame)
	_kill_banner_killer = _kill_banner_killer_frame.get_meta("avatar")

	_kill_banner_victim_frame = _make_banner_avatar_slot()
	_kill_banner_victim_frame.anchor_left = 1.0
	_kill_banner_victim_frame.anchor_right = 1.0
	_kill_banner_victim_frame.anchor_top = 0.0
	_kill_banner_victim_frame.anchor_bottom = 0.0
	_kill_banner_victim_frame.offset_left = -94.0
	_kill_banner_victim_frame.offset_right = -14.0
	_kill_banner_victim_frame.offset_top = 40.0
	_kill_banner_victim_frame.offset_bottom = 120.0
	_kill_banner.add_child(_kill_banner_victim_frame)
	_kill_banner_victim = _kill_banner_victim_frame.get_meta("avatar")

	_kill_banner_text = _make_label("", 30, GameTheme.GOLD_LIGHT)
	_kill_banner_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_kill_banner_text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_kill_banner_text.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_kill_banner_text.offset_left = 96.0
	_kill_banner_text.offset_right = -96.0
	_kill_banner_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_kill_banner_text.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_kill_banner_text.add_theme_constant_override("outline_size", 6)
	_kill_banner.add_child(_kill_banner_text)

	_kill_banner_emblem = TextureRect.new()
	_kill_banner_emblem.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_kill_banner_emblem.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_kill_banner_emblem.anchor_left = 0.5
	_kill_banner_emblem.anchor_right = 0.5
	_kill_banner_emblem.anchor_top = 0.0
	_kill_banner_emblem.anchor_bottom = 0.0
	_kill_banner_emblem.offset_left = -56.0
	_kill_banner_emblem.offset_right = 56.0
	_kill_banner_emblem.offset_top = -92.0
	_kill_banner_emblem.offset_bottom = 20.0
	_kill_banner_emblem.visible = false
	_kill_banner_emblem.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_kill_banner.add_child(_kill_banner_emblem)

func _make_banner_avatar() -> TextureRect:
	var avatar := TextureRect.new()
	avatar.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	avatar.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	avatar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return avatar

# 头像位 = 金边方框 + 内嵌头像。框和头像必须一起显隐：
# 被塔/小兵击杀时左边没有击杀者，留下一个空金环会像"图丢了"。
func _make_banner_avatar_slot() -> PanelContainer:
	var frame := PanelContainer.new()
	frame.custom_minimum_size = Vector2(80.0, 80.0)
	var style := GameTheme.style(Color(0.02, 0.03, 0.045, 0.95), Color(0.92, 0.78, 0.45, 0.9), 2, 6, 0, 0.0)
	style.content_margin_left = 4
	style.content_margin_right = 4
	style.content_margin_top = 4
	style.content_margin_bottom = 4
	frame.add_theme_stylebox_override("panel", style)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var avatar := _make_banner_avatar()
	frame.add_child(avatar)
	frame.set_meta("avatar", avatar)
	return frame

# streak：1=第一滴血 … 5=五杀，0=不显示纹章。
# killer_is_hero=false 时（被塔/小兵击杀）只显示受害者头像。
func show_kill_banner(
	killer_name: String,
	killer_hero_type: String,
	victim_name: String,
	victim_hero_type: String,
	streak := 0,
	killer_is_hero := true
) -> void:
	if _kill_banner == null:
		return
	_kill_banner.visible = true
	if _kill_banner_bg != null and _kill_banner_bg.texture == null:
		_kill_banner_bg.texture = GameTheme.kill_banner()
	if _kill_banner_killer != null:
		_kill_banner_killer.texture = GameTheme.hero_avatar(killer_hero_type, 72) if (killer_is_hero and killer_hero_type != "") else null
		_kill_banner_killer.visible = _kill_banner_killer.texture != null
		if _kill_banner_killer_frame != null:
			_kill_banner_killer_frame.visible = _kill_banner_killer.texture != null
	if _kill_banner_victim != null:
		_kill_banner_victim.texture = GameTheme.hero_avatar(victim_hero_type, 72) if victim_hero_type != "" else null
		_kill_banner_victim.visible = _kill_banner_victim.texture != null
		if _kill_banner_victim_frame != null:
			_kill_banner_victim_frame.visible = _kill_banner_victim.texture != null
	if _kill_banner_text != null:
		_kill_banner_text.text = "%s  击败  %s" % [killer_name, victim_name] if killer_is_hero else "%s  被 %s 击败" % [victim_name, killer_name]
	if _kill_banner_emblem != null:
		var emblem := GameTheme.streak_emblem(streak)
		_kill_banner_emblem.texture = emblem
		_kill_banner_emblem.visible = emblem != null
	if _kill_banner_tween != null and _kill_banner_tween.is_valid():
		_kill_banner_tween.kill()
	_kill_banner.modulate = Color(1, 1, 1, 0)
	_kill_banner.scale = Vector2(0.92, 0.92)
	_kill_banner.pivot_offset = _kill_banner.size * 0.5
	_kill_banner_tween = create_tween()
	_kill_banner_tween.set_parallel(true)
	_kill_banner_tween.tween_property(_kill_banner, "modulate:a", 1.0, 0.12)
	_kill_banner_tween.tween_property(_kill_banner, "scale", Vector2.ONE, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_kill_banner_tween.set_parallel(false)
	_kill_banner_tween.tween_interval(1.7)
	_kill_banner_tween.tween_property(_kill_banner, "modulate:a", 0.0, 0.3)
	_kill_banner_tween.tween_callback(func(): _kill_banner.visible = false)

func _build_bottom_panel() -> void:
	_hero_panel = PanelContainer.new()
	_hero_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# 手机端这根柱子只有小地图那么宽（234），内边距和落影都得收着：
	# 按桌面那套 14px 内边距 + 8px 落影，内容区会被挤到 190 以下，头像和血条并排放不下。
	var panel_style := GameTheme.style(
		Color(0.02, 0.04, 0.055, 0.92),
		Color(0.55, 0.44, 0.24, 0.7),
		1,
		12,
		0 if touch_mode else 8,
		0.0 if touch_mode else 0.45
	)
	if touch_mode:
		panel_style.content_margin_left = 6
		panel_style.content_margin_right = 6
		panel_style.content_margin_top = 6
		panel_style.content_margin_bottom = 6
	_hero_panel.add_theme_stylebox_override("panel", panel_style)
	add_child(_hero_panel)
	var portrait_size := 56.0 if touch_mode else 104.0
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8 if touch_mode else 16)
	_hero_panel.add_child(row)

	var portrait_frame := PanelContainer.new()
	portrait_frame.custom_minimum_size = Vector2(portrait_size, portrait_size)
	portrait_frame.add_theme_stylebox_override("panel", GameTheme.style(Color(0.02, 0.03, 0.045, 1.0), Color(0.72, 0.56, 0.3, 0.8), 2, 8, 0, 0.0))
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
	info.add_theme_constant_override("separation", 4 if touch_mode else 5)
	row.add_child(info)
	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 6 if touch_mode else 10)
	info.add_child(name_row)
	_name_label = _make_label(player_name, 15 if touch_mode else 22, GameTheme.TEXT)
	_name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name_label.clip_text = touch_mode
	_name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_row.add_child(_name_label)
	_level_label = _make_label("Lv.1", 13 if touch_mode else 18, GameTheme.GOLD_LIGHT)
	name_row.add_child(_level_label)
	# 英雄定位并进名字行：单开一行会占掉装备格需要的 ~20px，状态卡高度就会被顶破。
	# 手机端不挂这行副标题（234 宽会被省略成半句话）；桌面端超长时用省略号。
	_role_label = _make_label("", 11 if not touch_mode else 13, GameTheme.MUTED)
	_role_label.visible = not touch_mode
	_role_label.clip_text = true
	_role_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_row.add_child(_role_label)
	var hp_root := _make_stat_bar(GameTheme.GREEN, 14.0 if touch_mode else 20.0)
	_hp_bar = hp_root.get_meta("bar")
	_hp_text = hp_root.get_meta("label")
	_hp_style = _hp_bar.get_theme_stylebox("fill") as StyleBoxFlat
	# 14px 高的条里塞 11 号数字会裁成半截；血量比例看条，精确值在计分板里。
	_hp_text.visible = not touch_mode
	info.add_child(hp_root)
	var mp_root := _make_stat_bar(GameTheme.MANA, 10.0 if touch_mode else 16.0)
	_mp_bar = mp_root.get_meta("bar")
	_mp_text = mp_root.get_meta("label")
	_mp_text.visible = not touch_mode
	info.add_child(mp_root)
	# 击杀/阵亡和金币并成一行：状态卡少一行就矮 18px，压住战场的面积直接少一截。
	var meta_row := HBoxContainer.new()
	meta_row.add_theme_constant_override("separation", 6 if touch_mode else 8)
	info.add_child(meta_row)
	_kd_label = _make_label("击杀 0 / 阵亡 0", 10 if touch_mode else 13, GameTheme.MUTED)
	_kd_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	meta_row.add_child(_kd_label)
	_gold_label = _make_label("金币 0", 11 if touch_mode else 13, GameTheme.GOLD)
	meta_row.add_child(_gold_label)

	# 装备格：复用商店的 256² 图标，缩到 16/20px。没有装备就留空槽，
	# 不再让状态卡只回答"我是谁、我还剩多少血"，却看不出出了什么装。
	var equip_row := HBoxContainer.new()
	equip_row.add_theme_constant_override("separation", 3)
	info.add_child(equip_row)
	var equip_size := 14.0 if touch_mode else 20.0
	for i in 6:
		var frame := PanelContainer.new()
		frame.custom_minimum_size = Vector2(equip_size, equip_size)
		frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var frame_style := GameTheme.style(Color(0.02, 0.03, 0.04, 0.9), Color(0.32, 0.28, 0.20, 0.8), 1, 3, 0, 0.0)
		frame_style.content_margin_left = 0
		frame_style.content_margin_right = 0
		frame_style.content_margin_top = 0
		frame_style.content_margin_bottom = 0
		frame.add_theme_stylebox_override("panel", frame_style)
		var icon := TextureRect.new()
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		frame.add_child(icon)
		equip_row.add_child(frame)
		_equip_icons.append(icon)
	# Buff/Debuff 小色标：红/蓝 BUFF、加速、减速。没有图标资产时用纯色标，
	# 至少让玩家在状态卡上看到"身上有东西"，而不是只能看角色脚下的光环。
	var pip_size := 12.0 if touch_mode else 16.0
	for entry in [
		["红BUFF", Color(0.95, 0.32, 0.18)],
		["蓝BUFF", Color(0.30, 0.60, 1.0)],
		["加速", Color(0.42, 0.90, 0.48)],
		["减速", Color(0.48, 0.80, 1.0)],
	]:
		var pip := PanelContainer.new()
		pip.custom_minimum_size = Vector2(pip_size, pip_size)
		pip.tooltip_text = str(entry[0])
		pip.visible = false
		var pip_style := GameTheme.style(Color(entry[1]), Color(0.95, 0.92, 0.82, 0.8), 1, 3, 0, 0.0)
		pip_style.content_margin_left = 0
		pip_style.content_margin_right = 0
		pip_style.content_margin_top = 0
		pip_style.content_margin_bottom = 0
		pip.add_theme_stylebox_override("panel", pip_style)
		var status_icon := TextureRect.new()
		status_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		status_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		status_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pip.add_child(status_icon)
		equip_row.add_child(pip)
		_status_pips.append(pip)
		_status_icons.append(status_icon)

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
	if slot == "summoner":
		button.skill_kind = "summoner"
	else:
		var skill_def: Dictionary = HeroDefs.get_hero(hero_type).get(slot, {})
		button.skill_kind = str(skill_def.get("kind", ""))
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
	# 300 是桌面横卡里血条的占位；手机端的状态柱只有 234 宽，按 300 要最小尺寸
	# 会把整根柱子顶出分区（PanelContainer 只会被内容撑大，不会自己缩）。
	root.custom_minimum_size = Vector2(120.0 if touch_mode else 300.0, height)
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
	# 触屏端不要把键鼠那条 460x176 的横面板搬上来：真机上它被挤到摇杆正上方，
	# 跟攻击键隔着半个屏幕，玩家点「补刀」得先横跨整个拇指区。
	# 触屏改成「攻击键旁三颗圆 + 右上角头像锁定」，见 _build_mode_buttons / _build_lock_bar。
	if touch_mode:
		_build_mode_buttons()
		_build_lock_bar()
		return
	_attack_cluster = AttackCluster.new()
	_attack_cluster.setup(touch_mode)
	_attack_cluster.mode_changed.connect(func(mode: String): attack_mode_changed.emit(mode))
	_attack_cluster.lock_changed.connect(func(target_id: int): lock_changed.emit(target_id))
	# 位置统一由 _apply_layout 从分区表取；这里只建节点。
	add_child(_attack_cluster)

func _build_mode_buttons() -> void:
	if not _mode_buttons.is_empty():
		return
	for entry in TOUCH_MODE_ENTRIES:
		var button: Control = AttackModeButton.new()
		button.name = "AttackMode_%s" % str(entry.id)
		button.setup(true)
		button.label = str(entry.label)
		button.accent = GameTheme.GOLD
		button.pressed.connect(_on_mode_button_pressed.bind(str(entry.id)))
		add_child(button)
		_mode_buttons.append(button)
	_sync_mode_buttons(_attack_mode_local)

func _build_lock_bar() -> void:
	if _lock_bar != null:
		return
	_lock_bar = LockBar.new()
	_lock_bar.name = "LockBar"
	_lock_bar.setup(touch_mode)
	_lock_bar.lock_changed.connect(_on_lock_bar_changed)
	add_child(_lock_bar)

func _on_mode_button_pressed(mode: String) -> void:
	_attack_mode_local = mode
	_sync_mode_buttons(mode)
	attack_mode_changed.emit(mode)

func _sync_mode_buttons(mode: String) -> void:
	for i in _mode_buttons.size():
		var entry: Dictionary = TOUCH_MODE_ENTRIES[i]
		_mode_buttons[i].set_active(str(entry.id) == mode)

func _on_lock_bar_changed(target_id: int) -> void:
	_locked_target_local = target_id
	lock_changed.emit(target_id)

func set_targeting_state(mode: String, target_id: int) -> void:
	_attack_mode_local = mode
	_locked_target_local = target_id
	if _attack_cluster != null:
		_attack_cluster.set_targeting_state(mode, target_id)
	_sync_mode_buttons(mode)
	if _lock_bar != null:
		_lock_bar.set_locked(target_id)

## arena 每 20Hz 送一次「敌人 id → 屏幕坐标」。锁定条的线靠它落到人身上。
func set_enemy_screens(screens: Dictionary) -> void:
	_enemy_screens = screens

## 把快照里的敌方英雄整理成锁定条要的形状：算距离、带上屏幕坐标。
## 距离过滤和排序在 LockBar 里做（那是可测的纯逻辑），这里只管取数。
## 注意快照里的坐标是扁平的 x / y（net_protocol 序列化成那样），不是 sim 内部的 Vector2 pos。
func _lock_targets(data: Dictionary) -> Array:
	var hero := _find_local_hero(data)
	if hero.is_empty():
		return []
	var origin := Vector2(float(hero.get("x", 0.0)), float(hero.get("y", 0.0)))
	var targets: Array = []
	for entity in data.get("entities", []):
		if str(entity.get("type", "")) != "hero":
			continue
		if str(entity.get("team", "")) == local_team:
			continue
		if not bool(entity.get("alive", true)):
			continue
		var entity_id := int(entity.get("id", -1))
		if entity_id <= 0:
			continue
		var pos := Vector2(float(entity.get("x", 0.0)), float(entity.get("y", 0.0)))
		targets.append({
			"id": entity_id,
			"hero_type": str(entity.get("hero_type", "blade")),
			"name": str(entity.get("name", "")),
			"dist": origin.distance_to(pos),
			"screen": _enemy_screens.get(entity_id, Vector2(-1.0, -1.0)),
		})
	return targets

func _build_hints() -> void:
	# 手机端不铺常驻键位提示（触屏控件自己会说话）。
	# 键鼠端也只当新手引导：进场显示十几秒后淡出，之后按 Esc 还能在菜单里查到。
	if touch_mode:
		return
	_hint_box = _make_label("\n".join(KEY_HINT_LINES), 14, Color(0.90, 0.93, 0.96, 0.96))
	_hint_box.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	# 底板替代「粗描边」：描边只能救单字，救不了一行压在亮水面上的小字。
	# 有底板之后文字可以正常字重，不会糊成一团黑边。
	# 底板不要投影：投影会往上下各溢出 6px，正好把「和状态卡之间的 16px 间隙」填满，
	# 两块就又看起来粘在一起了。提示条是贴地的说明，不需要浮起来。
	# 上下内边距也必须压到 2px：46px 高的框扣掉默认 10+10 只剩 26px，两行字会被裁成碎片。
	var hint_style := GameTheme.style(Color(0.015, 0.028, 0.04, 0.84), Color(0.42, 0.36, 0.20, 0.34), 1, 8, 0, 0.0)
	hint_style.content_margin_left = 10
	hint_style.content_margin_right = 10
	hint_style.content_margin_top = 2
	hint_style.content_margin_bottom = 2
	_hint_box.add_theme_stylebox_override("normal", hint_style)
	_hint_box.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.65))
	_hint_box.add_theme_constant_override("outline_size", 2)
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
	# 手游的普攻键不写字：一把剑 + 金环就够了，键面上放字会把圆挤小。
	# 用 `attack`（剑）而不是 `slash`（45° 平行四边形）：后者放大到 130px 会把
	# 整个圆糊成一块褐色方块，看起来像个色卡而不是按键。
	_attack_button.icon_kind = "attack"
	_attack_button.label = "攻击"
	_attack_button.hint = "按住连击"
	# 淡金而不是橘褐：王者的普攻键是「银白剑 + 金环」，橘褐色在绿草地上
	# 会读成一块土黄的色块，和旁边金环技能键撞车。
	_attack_button.accent = Color(0.96, 0.82, 0.54)
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
	_skill_w = _create_skill("w", "1", Color(0.68, 0.86, 0.58))
	add_child(_skill_w)
	_skill_e = _create_skill("e", "E", Color(0.55, 0.75, 1.0))
	add_child(_skill_e)
	_skill_r = _create_skill("r", "R", Color(0.95, 0.62, 0.45))
	add_child(_skill_r)
	# 位置不在这里定：弧半径和角间距都跟视口有关（见 TouchLayout.skill_arc_radius），
	# 由 _apply_layout 每次按当前视口重排。
	_summoner_button = _create_skill("summoner", "F", Color(0.5, 0.86, 0.76), _summoner_name())
	add_child(_summoner_button)

	_pause_button = TouchActionButton.new()
	_pause_button.touch_mode = true
	_pause_button.label = MatchMenu.pause_label(online_mode)
	_pause_button.accent = Color(0.58, 0.66, 0.72)
	# 位置由 _apply_layout 从分区表取（触屏在小地图正下方）。
	# 这里曾经写死过 (1854, 276)，正好被锁定头像条的第三格压住 —— 别写回来。
	_pause_button.pressed.connect(func(): pause_requested.emit())
	add_child(_pause_button)

	_recall_button = TouchActionButton.new()
	_recall_button.touch_mode = true
	_recall_button.label = "回城"
	_recall_button.hint = "B"
	_recall_button.accent = Color(0.45, 0.78, 0.62)
	_recall_button.pressed.connect(func(): skill_pressed.emit("recall"))
	add_child(_recall_button)

	_teleport_button = TouchActionButton.new()
	_teleport_button.touch_mode = true
	_teleport_button.label = "传送"
	_teleport_button.hint = "T"
	_teleport_button.accent = Color(0.42, 0.8, 0.9)
	_teleport_button.pressed.connect(func(): skill_pressed.emit("teleport"))
	add_child(_teleport_button)

	# 回城条：位置由分区表给（底部正中）。默认隐藏，只有 recall_timer > 0 才出现。
	_recall_bar = RecallBar.new()
	add_child(_recall_bar)

## 普攻键用锚点贴右下；inset 只能在这里补，否则它仍会压进手势条。
func _place_attack_button(insets := Rect2i()) -> void:
	if _attack_button == null:
		return
	var right := float(insets.size.x)
	var bottom := float(insets.size.y)
	_attack_button.offset_left = -right - TouchLayout.ATTACK_MARGIN.x - TouchLayout.ATTACK_BUTTON_SIZE
	_attack_button.offset_top = -bottom - TouchLayout.ATTACK_MARGIN.y - TouchLayout.ATTACK_BUTTON_SIZE
	_attack_button.offset_right = -right - TouchLayout.ATTACK_MARGIN.x
	_attack_button.offset_bottom = -bottom - TouchLayout.ATTACK_MARGIN.y

func _place_touch_skills(viewport: Vector2, insets := Rect2i()) -> void:
	var nodes := [_skill_q, _skill_w, _skill_e, _skill_r]
	var centers := TouchLayout.skill_arc_centers(_touch_viewport(viewport, insets))
	var half := TouchLayout.SKILL_TOUCH_SIZE * 0.5
	for i in nodes.size():
		if i >= centers.size():
			break
		_place_zone(nodes[i], Rect2(centers[i] - half, TouchLayout.SKILL_TOUCH_SIZE))

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
	var pause_frame := GameTheme.panel_frame()
	if pause_frame.texture != null:
		panel.add_theme_stylebox_override("panel", pause_frame)
	else:
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
	var settings := Button.new()
	settings.text = "设置"
	settings.custom_minimum_size = Vector2(0, button_height)
	settings.pressed.connect(_open_settings_from_pause)
	box.add_child(settings)
	var leave := Button.new()
	leave.text = "离开对局"
	leave.custom_minimum_size = Vector2(0, button_height)
	leave.pressed.connect(func(): leave_requested.emit())
	box.add_child(leave)
	_pause_hint = _make_label(MatchMenu.hint(online_mode), 12, GameTheme.MUTED)
	_pause_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_pause_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_pause_hint)

func _open_settings_from_pause() -> void:
	var panel := SettingsPanel.new()
	panel.name = "SettingsPanel"
	add_child(panel)

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
	panel.offset_top = -260.0
	panel.offset_bottom = 260.0
	var ornate := GameTheme.ornate_panel()
	if ornate.texture != null:
		panel.add_theme_stylebox_override("panel", ornate)
	else:
		panel.add_theme_stylebox_override("panel", GameTheme.style(Color(0.025, 0.045, 0.06, 0.97), Color(0.7, 0.55, 0.28, 0.95), 2, 14))
	_result_overlay.add_child(panel)
	# 结算页背景：压在内容之下，随面板内容区缩放（768×512 与 660×440 同为 1.5:1）。
	_result_bg = TextureRect.new()
	_result_bg.texture = GameTheme.mvp_background()
	_result_bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_result_bg.stretch_mode = TextureRect.STRETCH_SCALE
	_result_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(_result_bg)
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 16)
	panel.add_child(box)
	var head_row := HBoxContainer.new()
	head_row.alignment = BoxContainer.ALIGNMENT_CENTER
	head_row.add_theme_constant_override("separation", 16)
	box.add_child(head_row)
	# 勋章：MVP / 参战两枚，show_result 里按 KDA 切换。
	_result_medal = TextureRect.new()
	_result_medal.custom_minimum_size = Vector2(72.0, 72.0)
	_result_medal.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_result_medal.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_result_medal.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head_row.add_child(_result_medal)
	var avatar_frame := PanelContainer.new()
	avatar_frame.custom_minimum_size = Vector2(96.0, 96.0)
	avatar_frame.add_theme_stylebox_override("panel", GameTheme.style(Color(0.02, 0.03, 0.045, 1.0), Color(0.72, 0.56, 0.30, 0.85), 2, 8, 0, 0.0))
	head_row.add_child(avatar_frame)
	_result_avatar = TextureRect.new()
	_result_avatar.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_result_avatar.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_result_avatar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	avatar_frame.add_child(_result_avatar)
	var title_box := VBoxContainer.new()
	title_box.add_theme_constant_override("separation", 2)
	head_row.add_child(title_box)
	_result_title = _make_label("胜  利", 64, GameTheme.GOLD_LIGHT, "TitleLabel")
	_result_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_box.add_child(_result_title)
	_result_badge = _make_label("MVP", 18, GameTheme.GOLD_LIGHT)
	_result_badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_box.add_child(_result_badge)
	_result_sub = _make_label("", 20, GameTheme.TEXT)
	_result_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_result_sub)
	_result_stats = _make_label("", 16, GameTheme.MUTED)
	_result_stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_result_stats)
	# 数据条：三条相对本队峰值的横条。只读同队英雄，敌方数值不参与归一化。
	var bars := VBoxContainer.new()
	bars.add_theme_constant_override("separation", 5)
	box.add_child(bars)
	for spec in RESULT_BAR_ROWS:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		bars.add_child(row)
		var title := _make_label(str(spec.label), 14, GameTheme.MUTED)
		title.custom_minimum_size = Vector2(44.0, 0.0)
		row.add_child(title)
		var bar := ProgressBar.new()
		bar.min_value = 0.0
		bar.max_value = 1.0
		bar.value = 0.0
		bar.show_percentage = false
		bar.custom_minimum_size = Vector2(300.0, 14.0)
		bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bar.add_theme_stylebox_override("background", GameTheme.style(
			Color(0.06, 0.08, 0.10, 0.92), Color(0.18, 0.22, 0.26, 0.9), 1, 4, 0, 0.0
		))
		bar.add_theme_stylebox_override("fill", GameTheme.style(
			Color(0.78, 0.60, 0.32, 0.95), Color(0.0, 0.0, 0.0, 0.0), 0, 4, 0, 0.0
		))
		row.add_child(bar)
		var readout := _make_label("", 13, GameTheme.TEXT)
		readout.custom_minimum_size = Vector2(84.0, 0.0)
		readout.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(readout)
		_result_bars[str(spec.key)] = {"bar": bar, "value": readout}
	# 点赞：按视觉文档的口径只做 UI，不接后端；同一局只能点一次。
	_like_button = Button.new()
	_like_button.text = "点赞"
	_like_button.focus_mode = Control.FOCUS_NONE
	_like_button.custom_minimum_size = Vector2(132.0, 40.0)
	_like_button.pressed.connect(_on_result_like)
	box.add_child(_like_button)
	var leave := Button.new()
	leave.text = "返回主菜单"
	leave.custom_minimum_size = TouchLayout.RESULT_BUTTON_SIZE if touch_mode else Vector2(220, 52)
	var leave_frame := GameTheme.button_frame()
	if leave_frame.texture != null:
		leave.add_theme_stylebox_override("normal", leave_frame)
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
	if key.pressed and not key.echo and key.keycode == KEY_G:
		# G = 快捷信号轮盘：和小地图旁的「信号」按钮同一个入口。
		_toggle_ping_panel()
		accept_event()
		return
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
	# 手机端没有左右两块队伍名，比分折进中间那一行；桌面端仍是左右分立。
	if _score_line != null:
		_score_line.text = "%d  vs  %d" % [blue_kills, red_kills]
	if _score_blue != null:
		_score_blue.text = "蓝方  %d" % blue_kills
	if _score_red != null:
		_score_red.text = "%d  红方" % red_kills
	var board: Dictionary = data.get("board", {})
	_refresh_economy(board, str(local.get("owner_id", "")))
	_timer_label.text = _format_time(float(data.get("time", 0.0)))
	# 手机端没有「第 N 波」这一行（80px 的比分条只放得下时间和比分），判空而不是硬写。
	if _wave_label != null:
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
	if not _equip_icons.is_empty():
		var inventory: Array = local.get("inventory", [])
		var icon_size := 16 if touch_mode else 20
		for i in _equip_icons.size():
			_equip_icons[i].texture = (
				GameTheme.item_icon(str(inventory[i]), icon_size)
				if i < inventory.size()
				else null
			)
	if _status_pips.size() >= 4:
		# 每帧直接写 4 个 bool，不建临时数组：状态卡是常驻 HUD，能少一次分配就少一次。
		_status_pips[0].visible = float(local.get("buff_red_timer", 0.0)) > 0.0
		_status_pips[1].visible = float(local.get("buff_blue_timer", 0.0)) > 0.0
		_status_pips[2].visible = float(local.get("haste_timer", 0.0)) > 0.0
		_status_pips[3].visible = float(local.get("slow_timer", 0.0)) > 0.0
		var icon_size := 12 if touch_mode else 16
		if _status_icons.size() >= 4:
			_status_icons[0].texture = GameTheme.status_icon("buff_red", icon_size)
			_status_icons[1].texture = GameTheme.status_icon("buff_blue", icon_size)
			_status_icons[2].texture = GameTheme.status_icon("haste", icon_size)
			_status_icons[3].texture = GameTheme.status_icon("slow", icon_size)
	# 左上角那行金币：写得短，钱多了折成 15.4k，否则会把塔数挤出去。
	if _map_gold_label != null:
		_map_gold_label.text = _short_gold(gold)
	# 回城引导：手机端的状态柱放不下「[回城中...]」这行字，进度改由底部那条进度条来说。
	if _recall_bar != null:
		_recall_bar.set_state(float(local.get("recall_timer", 0.0)), float(local.get("recall_total", 0.0)))
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
	# 项 4：被控时必须告诉玩家**为什么动不了**。
	# 手机上没有 CD 数字可看，玩家被眩晕后只看到"按了没反应"，
	# 最容易误判成游戏卡死。这条提示走既有的状态行，不新增 UI 元素。
	var cc_text := control_status_caption(local)
	if cc_text != "":
		role_text += " [%s]" % cc_text
	# 项 2：剩余技能点。0 点时 caption 是空串，不会常驻一句"技能点 0"。
	var points_caption := skill_points_caption(local)
	if points_caption != "":
		role_text += " [%s]" % points_caption
	_role_label.text = role_text
	var alive := bool(local.get("alive", true))
	_apply_skill_state(_skill_q, local, hero_def.q, "skill_q_cd", mp, not alive)
	_apply_skill_state(_skill_w, local, hero_def.w, "skill_w_cd", mp, not alive)
	_apply_skill_state(_skill_e, local, hero_def.e, "skill_e_cd", mp, not alive)
	_apply_skill_state(_skill_r, local, hero_def.r, "skill_r_cd", mp, not alive)
	_sync_level_ui(local)
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
	if _lock_bar != null:
		_lock_bar.set_targets(_lock_targets(data))
	_minimap.set_snapshot(data, local_owner, local_team)
	if ended and not result_shown:
		show_result(str(data.get("winner", "")), local)

func _apply_skill_state(button: SkillButton, local: Dictionary, skill_def: Dictionary, cd_key: String, mp: float, dead: bool) -> void:
	if button == null:
		return
	# 项 2：等级从快照读（skill_<slot>_level），漏传就会显示不出成长。
	# slot 用 cd_key 反推（"skill_q_cd" -> "q"），避免调用方再传一遍、两处可能不一致。
	var slot := str(cd_key).trim_prefix("skill_").trim_suffix("_cd")
	button.set_state(
		float(local.get(cd_key, 0.0)),
		float(skill_def.get("cooldown", 1.0)),
		str(skill_def.get("name", "技能")),
		mp >= float(skill_def.get("cost", 0.0)),
		dead,
		int(local.get("skill_%s_level" % slot, 1))
	)

## 剩余技能点读数（项 2，链路 6）。静态函数便于宽度/内容守卫直接调用。
## 0 点返回空串：不占文案位，否则状态卡上常驻一句"技能点 0"是纯噪声。
static func skill_points_caption(local: Dictionary) -> String:
	var points := int(local.get("skill_points", 0))
	if points <= 0:
		return ""
	return "技能点 %d" % points

## 被控提示（项 4，链路 6）。静态函数便于内容守卫直接调用。
## 手机上没有 CD 数字可看，玩家被眩晕后只看到"按了没反应"，
## 最容易误判成游戏卡死 —— 所以必须有一句明说"你被控住了"。
## 文案按 ControlRules 的同一套数据生成，不另写一份枚举。
static func control_status_caption(local: Dictionary) -> String:
	var parts: Array = []
	for kind in ControlRules.KINDS:
		var remaining := float(local.get("%s_timer" % kind, 0.0))
		if remaining <= 0.0:
			continue
		parts.append("%s %.1f秒" % [ControlRules.display_name(kind), remaining])
	if parts.is_empty():
		return ""
	return "被" + "、".join(parts)

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
	_trim_feed()
	var tween := create_tween()
	tween.tween_interval(4.5)
	tween.tween_property(label, "modulate:a", 0.0, 0.6)
	tween.tween_callback(label.queue_free)

# 击杀条目：英雄击杀显示"击杀者头像 + 文字 + 受害者头像"，
# 塔/小兵击杀只显示受害者头像。头像复用立绘裁切缓存，不新增 2D 资产。
func add_kill_feed(killer_name: String, killer_hero_type: String, victim_name: String, victim_hero_type: String, color: Color, killer_is_hero := true) -> void:
	if _feed_box == null:
		return
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	row.alignment = BoxContainer.ALIGNMENT_END
	if killer_is_hero and killer_hero_type != "":
		_add_feed_avatar(row, killer_hero_type)
	var text := ""
	if killer_is_hero:
		text = "%s 击败了 %s" % [killer_name, victim_name]
	else:
		text = "%s 被 %s 击败" % [victim_name, killer_name]
	var label := _make_label(text, 14, color)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	label.clip_text = true
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	label.add_theme_constant_override("outline_size", 4)
	row.add_child(label)
	if victim_hero_type != "":
		_add_feed_avatar(row, victim_hero_type)
	_feed_box.add_child(row)
	_trim_feed()
	var tween := create_tween()
	tween.tween_interval(4.5)
	tween.tween_property(row, "modulate:a", 0.0, 0.6)
	tween.tween_callback(row.queue_free)

func _add_feed_avatar(row: HBoxContainer, hero_type: String) -> void:
	var texture := GameTheme.hero_avatar(hero_type, 22)
	if texture == null:
		return
	var frame := PanelContainer.new()
	frame.custom_minimum_size = Vector2(24.0, 24.0)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := GameTheme.style(Color(0.02, 0.03, 0.04, 0.95), Color(0.72, 0.56, 0.30, 0.8), 1, 4, 0, 0.0)
	style.content_margin_left = 0
	style.content_margin_right = 0
	style.content_margin_top = 0
	style.content_margin_bottom = 0
	frame.add_theme_stylebox_override("panel", style)
	var icon := TextureRect.new()
	icon.texture = texture
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(icon)
	row.add_child(frame)

func _trim_feed() -> void:
	while _feed_box.get_child_count() > 5:
		var first := _feed_box.get_child(0)
		_feed_box.remove_child(first)
		first.queue_free()

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
	if _result_avatar:
		_result_avatar.texture = GameTheme.hero_avatar(hero_type, 96)
	var kills := int(local.get("kills", 0))
	var deaths := int(local.get("deaths", 0))
	var is_mvp := kills >= 3 and kills > deaths
	if _result_bg:
		_result_bg.texture = GameTheme.mvp_background()
	if _result_medal:
		_result_medal.texture = GameTheme.mvp_medal(is_mvp)
	if _result_badge:
		_result_badge.text = "MVP" if is_mvp else "参战"
		_result_badge.add_theme_color_override("font_color", GameTheme.GOLD_LIGHT if is_mvp else GameTheme.MUTED)
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
	_update_result_bars(local)
	_likes = 0
	if _like_button != null:
		_like_button.text = "点赞"
		_like_button.disabled = false
	_result_overlay.visible = true
	announce("对局结束", GameTheme.GOLD_LIGHT, 1.5)

func _on_result_like() -> void:
	# 仅 UI：视觉文档明确不接后端，所以这里只做一次性的本地反馈。
	_likes += 1
	if _like_button != null:
		_like_button.text = "已点赞 (%d)" % _likes
		_like_button.disabled = true

# 输出/承伤按本队最高值归一化；参团 = (击杀+助攻) / 本队总击杀。
# 客机快照只含本队实体，敌方数值本来就不该进来参与比较。
func _update_result_bars(local: Dictionary) -> void:
	if _result_bars.is_empty():
		return
	var max_dealt := 1.0
	var max_taken := 1.0
	var team_kills := 0
	for entity in snapshot.get("entities", []):
		if str(entity.get("type", "")) != "hero" or str(entity.get("team", "")) != local_team:
			continue
		max_dealt = maxf(max_dealt, float(entity.get("damage_dealt", 0.0)))
		max_taken = maxf(max_taken, float(entity.get("damage_taken", 0.0)))
		team_kills += int(entity.get("kills", 0))
	var dealt := float(local.get("damage_dealt", 0.0))
	var taken := float(local.get("damage_taken", 0.0))
	var involvement := int(local.get("kills", 0)) + int(local.get("assists", 0))
	var participation := clampf(float(involvement) / float(maxi(1, team_kills)), 0.0, 1.0)
	_set_result_bar("dealt", clampf(dealt / max_dealt, 0.0, 1.0), _format_amount(dealt))
	_set_result_bar("taken", clampf(taken / max_taken, 0.0, 1.0), _format_amount(taken))
	_set_result_bar("join", participation, "%d%%" % roundi(participation * 100.0))

func _set_result_bar(key: String, ratio: float, text: String) -> void:
	var entry: Dictionary = _result_bars.get(key, {})
	if entry.is_empty():
		return
	(entry["bar"] as ProgressBar).value = ratio
	(entry["value"] as Label).text = text

func _format_amount(value: float) -> String:
	if value >= 1000.0:
		return "%.1fk" % (value / 1000.0)
	return "%d" % roundi(maxf(0.0, value))

func _format_time(seconds: float) -> String:
	var total := int(maxf(0.0, seconds))
	return "%02d:%02d" % [total / 60, total % 60]
