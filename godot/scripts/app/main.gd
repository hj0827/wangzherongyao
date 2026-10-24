extends Node

const Arena = preload("res://scripts/game/arena.gd")
const GameSession = preload("res://net/game_session.gd")
const LanDiscovery = preload("res://net/lan_discovery.gd")
const HeroDefs = preload("res://sim/hero_defs.gd")
const GameTheme = preload("res://scripts/ui/game_theme.gd")
const InputAssist = preload("res://scripts/game/input_assist.gd")
const TouchLayout = preload("res://scripts/ui/touch_layout.gd")
const HudLayout = preload("res://scripts/ui/hud_layout.gd")
const CinematicBackground = preload("res://scripts/ui/cinematic_background.gd")
const AudioDirector = preload("res://scripts/game/audio_director.gd")
const AudioCues = preload("res://scripts/game/audio_cues.gd")
const DepthCard = preload("res://scripts/ui/depth_card.gd")
const UnitVisual = preload("res://scripts/game/unit_visual.gd")

# 选人界面按五大职业排列：坦克 / 战士 / 刺客 / 法师 / 射手
const HERO_ORDER := ["tank", "blade", "assassin", "mage", "archer"]
const GAME_PORT := 24680

const MODE_NAMES := {
	"duel": "双人 · 1V1",
	"team": "军团 · 5V5",
}

const SKILL_KINDS := {
	"slash": "剑气横扫",
	"burst": "星陨轰击",
	"dash": "疾风突进",
	"quake": "震地击飞",
	"shield": "守护壁垒",
	"slow": "星界禁锢",
	"arrow": "穿云箭矢",
	"haste": "鹰眼疾行",
}

const ERROR_TEXT := {
	"bind_failed": "端口被占用，无法创建房间",
	"connect_failed": "无法连接到房间",
	"connect_timeout": "连接超时，请检查局域网",
	"bad_room_code": "房间码不匹配",
	"room_full": "房间已满",
	"already_started": "对局已经开始",
	"host_disconnected": "与房主断开连接",
}

var session: Object = null
var discovery: Object = null

var screen := "menu"
var local_hero := "blade"
var player_name := "无名客"
var _pending_online := false
var _pending_mode := "duel"
var _arena: Node3D = null

var _ui: CanvasLayer
var _screen_root: Control
var _background: Control
# 音频导演挂在应用壳上（菜单 / 选人 / 大厅 / 战斗共用一套声道）：
# 进战斗时是把同一台混音台换曲，不会出现菜单音乐和战斗音乐叠着响。
var _audio: Node = null

var _hero_cards := {}
var _hero_marks := {}
var _hero_videos := {}
var _hero_confirm: Button
var _quote_banner: PanelContainer = null
var _quote_label: Label = null
var _loading_screen: Control = null
var _loading_layer: CanvasLayer = null
var _loading_progress: ProgressBar = null
var _loading_status: Label = null

var _online_status: Label
var _name_input: LineEdit
var _offer_box: VBoxContainer
var _offer_signature := ""
var _discovery_hosting := false
var touch_mode := false

var _lobby_signature := ""
var _lobby_status: Label
var _next_refresh := 0

func _ready() -> void:
	touch_mode = InputAssist.wants_touch_controls({}, OS.has_feature("mobile"), DisplayServer.is_touchscreen_available())
	# HUD 是按 1600x900 排的，窗口再小就会整体缩到 0.7 以下、字先糊掉。
	# 桌面端直接给窗口一个下限，别让玩家把界面拉成看不清的形状。
	if not OS.has_feature("mobile"):
		get_window().min_size = Vector2i(HudLayout.MIN_VIEWPORT)
	session = GameSession.new()
	discovery = LanDiscovery.new()
	_connect_session()
	_audio = AudioDirector.new()
	_audio.name = "Audio"
	add_child(_audio)
	_build_shell()
	_show_menu()
	UnitVisual.warmup()

func _notification(what: int) -> void:
	if what != NOTIFICATION_WM_GO_BACK_REQUEST:
		return
	if screen == "game":
		return
	if screen == "lobby":
		_leave_online()
	elif screen == "hero_select" or screen == "online":
		_show_menu()
	else:
		get_tree().quit()

func _process(_delta: float) -> void:
	if session != null and screen != "game":
		session.poll()
	if discovery != null:
		discovery.poll()
	var now := Time.get_ticks_msec()
	if screen == "online" and now >= _next_refresh:
		_next_refresh = now + 400
		_refresh_offers()
	elif screen == "lobby" and now >= _next_refresh:
		_next_refresh = now + 250
		_show_lobby()

func _connect_session() -> void:
	session.state_changed.connect(_on_session_state)
	session.room_updated.connect(_on_room_updated)
	session.match_started.connect(_on_match_started)
	session.snapshot_received.connect(_on_network_snapshot)
	session.input_received.connect(_on_network_input)
	session.peer_left.connect(_on_network_peer_left)
	session.error_received.connect(_on_session_error)

func _build_shell() -> void:
	_ui = CanvasLayer.new()
	_ui.layer = 5
	add_child(_ui)

	var root := Control.new()
	root.name = "UIRoot"
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.theme = GameTheme.theme()
	_ui.add_child(root)

	# 动态背景：原画缓推 + 冷暖辉光 + 三层流动雾 + 上升火星 + 暗角，自带鼠标视差
	_background = CinematicBackground.new()
	_background.name = "CinematicBackground"
	_background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_background)

	_screen_root = Control.new()
	_screen_root.name = "Screen"
	_screen_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(_screen_root)

func _show_menu() -> void:
	screen = "menu"
	_ui.visible = true
	if _background != null:
		_background.set_audio_enabled(true)
	if _audio != null:
		# 从战斗回来时这里会把曲目切回菜单主题（淡入淡出），不用手动停战斗曲。
		_audio.play_music(AudioDirector.MUSIC_MENU)
	_clear_screen()
	discovery.stop()
	_discovery_hosting = false
	if session != null and session.state not in ["idle", "match"]:
		session.close()

	var margin := _full_margin(86, 62)
	_screen_root.add_child(margin)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 48)
	margin.add_child(row)

	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_theme_constant_override("separation", 12)
	row.add_child(left)

	var kicker := _make_label("O R I G I N A L   C A N Y O N   M O B A", 15, GameTheme.GOLD)
	left.add_child(kicker)
	var title := _make_label("烽 火 峡 谷", 112, GameTheme.GOLD_LIGHT)
	title.add_theme_font_override("font", GameTheme.FONT_DISPLAY)
	title.add_theme_color_override("font_outline_color", Color(0.02, 0.02, 0.015, 0.95))
	title.add_theme_constant_override("outline_size", 10)
	title.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.65))
	title.add_theme_constant_override("shadow_offset_x", 4)
	title.add_theme_constant_override("shadow_offset_y", 6)
	left.add_child(title)

	var subtitle := _make_label("原创峡谷竞技 · 单机试炼 · 双人联机 · 五人军团", 19, GameTheme.TEXT)
	left.add_child(subtitle)
	var blurb := _make_label(
		"操控四位原创英雄，沿三路兵线推进，\n摧毁敌方外塔与主堡。所有空位由 AI 补足。",
		15,
		GameTheme.MUTED
	)
	blurb.add_theme_constant_override("line_spacing", 8)
	left.add_child(blurb)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(spacer)

	var chips := HBoxContainer.new()
	chips.add_theme_constant_override("separation", 10)
	left.add_child(chips)
	for text in ["30 HZ 权威模拟", "4 位原创英雄", "AI 智能补位"]:
		chips.add_child(_chip(text))

	var hint_text := "左键 点击移动   ·   右键 / 空格 普攻   ·   Q / E 技能"
	if touch_mode:
		hint_text = "左侧摇杆移动   ·   按住攻击   ·   技能自动索敌   ·   双指缩放"
	var hint := _make_label(hint_text, 15 if touch_mode else 13, Color(0.62, 0.7, 0.76, 0.85))
	left.add_child(hint)

	var right := VBoxContainer.new()
	right.custom_minimum_size = Vector2(430, 0)
	right.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.alignment = BoxContainer.ALIGNMENT_CENTER
	right.add_theme_constant_override("separation", 22)
	row.add_child(right)

	var panel: PanelContainer = DepthCard.build(
		Color(0.018, 0.036, 0.052, 0.93), Color(0.55, 0.43, 0.24, 0.62), 14, 22, 30
	)
	right.add_child(panel)
	var box: VBoxContainer = panel.get_meta("box")
	box.add_theme_constant_override("separation", 10)

	box.add_child(_make_label("选 择 战 场", 22, GameTheme.GOLD_LIGHT))
	box.add_child(_divider())
	var modes := [
		{"text": "单人试炼    ·    1 V 1", "mode": "duel", "online": false},
		{"text": "人机军团    ·    5 V 5", "mode": "team", "online": false},
		{"text": "双人联机    ·    1 V 1", "mode": "duel", "online": true},
		{"text": "五人联机    ·    5 V 5", "mode": "team", "online": true},
	]
	var mode_buttons: Array[Control] = []
	for entry in modes:
		var button := _menu_button(entry.text)
		if bool(entry.online):
			button.add_theme_color_override("font_color", GameTheme.GOLD_LIGHT)
		button.pressed.connect(_on_mode_pressed.bind(entry.mode, entry.online))
		box.add_child(button)
		mode_buttons.append(button)
	box.add_child(_make_label("联机模式通过局域网自动发现房间，无需服务器。", 12, GameTheme.MUTED))

	var footer := _make_label("原型版本 0.9   ·   Godot 4.7   ·   本地权威模拟", 12, Color(0.62, 0.7, 0.76, 0.88))
	right.add_child(footer)

	# 入场：文字先亮起，卡片随后浮出，按钮逐个落下
	_fade_in([left], 0.0)
	_fade_in([panel], 0.08)
	_fade_in(mode_buttons, 0.16, 0.05)
	_fade_in([footer], 0.32)

func _on_mode_pressed(mode: String, online: bool) -> void:
	_pending_mode = mode
	_pending_online = online
	_show_hero_select()

func _show_hero_select() -> void:
	screen = "hero_select"
	if _background != null:
		_background.set_audio_enabled(false)
	_clear_screen()
	discovery.stop()
	_hero_cards.clear()
	_hero_marks.clear()
	_hero_videos.clear()

	var margin := _full_margin(64, 48)
	_screen_root.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 18)
	margin.add_child(column)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 18)
	column.add_child(header)
	var back := _small_button("‹  返回")
	back.custom_minimum_size = Vector2(150, _tap_height(46))
	back.pressed.connect(_show_menu)
	header.add_child(back)
	var titles := VBoxContainer.new()
	titles.add_theme_constant_override("separation", 2)
	header.add_child(titles)
	titles.add_child(_make_label("选择你的英雄", 42, GameTheme.GOLD_LIGHT))
	var context := "单人试炼" if not _pending_online else "联机对战"
	titles.add_child(_make_label("%s  ·  %s  ·  确认后进入战场" % [context, MODE_NAMES[_pending_mode]], 14, GameTheme.MUTED))
	var header_spacer := Control.new()
	header_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(header_spacer)
	var tip := _make_label("每位英雄拥有独立普攻、Q 与 E 技能", 13, GameTheme.MUTED)
	header.add_child(tip)

	var cards := HBoxContainer.new()
	cards.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cards.add_theme_constant_override("separation", 16)
	column.add_child(cards)
	for hero_type in HERO_ORDER:
		cards.add_child(_make_hero_card(hero_type))

	# 英雄台词展示横幅（殿堂级金色边框 + 发光台词）
	_quote_banner = PanelContainer.new()
	var banner_style := GameTheme.style(Color(0.04, 0.07, 0.1, 0.92), GameTheme.GOLD, 1, 10)
	banner_style.content_margin_left = 28
	banner_style.content_margin_right = 28
	banner_style.content_margin_top = 8
	banner_style.content_margin_bottom = 8
	_quote_banner.add_theme_stylebox_override("panel", banner_style)
	_quote_banner.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	column.add_child(_quote_banner)
	_quote_label = _make_label("", 16, GameTheme.GOLD_LIGHT)
	_quote_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_quote_banner.add_child(_quote_label)

	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 18)
	column.add_child(footer)
	var selected := _make_label("", 16, GameTheme.TEXT)
	selected.name = "SelectedHint"
	footer.add_child(selected)
	var footer_spacer := Control.new()
	footer_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(footer_spacer)
	_hero_confirm = _menu_button("确 认 出 战")
	_hero_confirm.custom_minimum_size = Vector2(300, _tap_height(62))
	_hero_confirm.pressed.connect(_on_hero_confirm)
	footer.add_child(_hero_confirm)
	_refresh_hero_selection()

func _make_hero_card(hero_type: String) -> PanelContainer:
	var definition: Dictionary = HeroDefs.get_hero(hero_type)
	var card: PanelContainer = DepthCard.build(
		Color(0.025, 0.045, 0.06, 0.9), Color(0.32, 0.3, 0.23, 0.55), 12, 12, 18
	)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	card.gui_input.connect(_on_hero_card_input.bind(hero_type))
	_hero_cards[hero_type] = card

	var box: VBoxContainer = card.get_meta("box")
	box.add_theme_constant_override("separation", 7)

	# 英雄立绘与专属动态视频容器
	var preview_box := Control.new()
	preview_box.custom_minimum_size = Vector2(0, 236)
	preview_box.clip_contents = true
	box.add_child(preview_box)

	var portrait := TextureRect.new()
	portrait.texture = load(GameTheme.portrait_path(hero_type))
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	portrait.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	preview_box.add_child(portrait)

	var video_path: String = str(definition.get("video_path", ""))
	if video_path != "" and ResourceLoader.exists(video_path):
		var video_holder := Control.new()
		video_holder.clip_contents = true
		video_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
		video_holder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		preview_box.add_child(video_holder)

		var video_player := VideoStreamPlayer.new()
		# 视频流延迟到真正选中该英雄时再加载，避免进入选人界面时同时解码四路视频。
		video_player.expand = true
		video_player.loop = true
		video_player.visible = false
		video_holder.add_child(video_player)
		_hero_videos[hero_type] = video_player
		# 16:9 素材按「cover」裁切：超宽屏也不会把人物横向拉扁。
		preview_box.resized.connect(_fit_hero_video.bind(preview_box, video_player))
		_fit_hero_video(preview_box, video_player)

	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 10)
	box.add_child(name_row)
	var hero_name := _make_label(str(definition.name), 30, GameTheme.GOLD_LIGHT)
	name_row.add_child(hero_name)
	var role := _make_label(str(definition.role), 14, GameTheme.TEXT)
	role.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	name_row.add_child(role)
	var mark := _make_label("◆ 已选择", 12, GameTheme.GOLD_LIGHT)
	mark.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	mark.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mark.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	name_row.add_child(mark)
	_hero_marks[hero_type] = mark

	box.add_child(_make_label(str(definition.title), 14, GameTheme.MUTED))
	box.add_child(_divider())

	var stats := _make_label(
		"生命 %d      攻击 %d      移速 %.1f" % [
			int(definition.max_hp),
			int(definition.attack_damage),
			float(definition.speed),
		],
		13,
		GameTheme.MUTED
	)
	box.add_child(stats)

	var q: Dictionary = definition.q
	var e: Dictionary = definition.e
	box.add_child(_skill_line("Q", str(q.name), q))
	box.add_child(_skill_line("E", str(e.name), e))

	var filler := Control.new()
	filler.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(filler)
	_ignore_mouse_children(card)
	return card

func _fit_hero_video(box: Control, video: VideoStreamPlayer) -> void:
	var area := box.size
	if area.x <= 0.0 or area.y <= 0.0:
		return
	# 展示视频统一为 16:9。按 cover 放大再居中裁切，超宽屏也不会变形。
	var video_size := Vector2(area.x, area.x * 9.0 / 16.0)
	if video_size.y < area.y:
		video_size = Vector2(area.y * 16.0 / 9.0, area.y)
	video.size = video_size
	video.position = (area - video_size) * 0.5

func _skill_line(slot: String, skill_name: String, data: Dictionary) -> Label:
	var detail := ""
	if float(data.get("damage", 0.0)) > 0.0:
		detail = "%d 伤害" % int(data.damage)
	else:
		detail = str(SKILL_KINDS.get(str(data.get("kind", "")), "战术技能"))
	var text := "%s  %s   ·   %s   ·   %.1fs" % [slot, skill_name, detail, float(data.get("cooldown", 0.0))]
	var label := _make_label(text, 12, GameTheme.TEXT)
	label.add_theme_color_override("font_color", Color(0.82, 0.86, 0.9))
	return label

func _on_hero_card_input(event: InputEvent, hero_type: String) -> void:
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed:
			local_hero = hero_type
			_refresh_hero_selection()
		return
	if event is InputEventMouseButton:
		var mouse := event as InputEventMouseButton
		if mouse.pressed and mouse.button_index == MOUSE_BUTTON_LEFT:
			local_hero = hero_type
			_refresh_hero_selection()

func _refresh_hero_selection() -> void:
	for hero_type in _hero_cards:
		var selected: bool = str(hero_type) == local_hero
		var card: PanelContainer = _hero_cards[hero_type]
		var style := GameTheme.style(
			Color(0.06, 0.09, 0.11, 0.96) if selected else Color(0.025, 0.045, 0.06, 0.9),
			GameTheme.GOLD if selected else Color(0.32, 0.3, 0.23, 0.55),
			2 if selected else 1,
			12
		)
		style.content_margin_left = 6
		style.content_margin_right = 6
		style.content_margin_top = 6
		style.content_margin_bottom = 6
		card.add_theme_stylebox_override("panel", style)
		_hero_marks[hero_type].visible = selected

		# 控制对应英雄视频播放（选中时才加载视频流）
		var video: VideoStreamPlayer = _hero_videos.get(hero_type)
		if video != null:
			if selected:
				if video.stream == null:
					var video_path: String = str(HeroDefs.get_hero(hero_type).get("video_path", ""))
					if video_path != "" and ResourceLoader.exists(video_path):
						video.stream = load(video_path)
				video.visible = video.stream != null
				if video.visible and is_inside_tree() and not video.is_playing():
					video.play()
			else:
				video.visible = false
				if is_inside_tree() and video.is_playing():
					video.stop()

	if _hero_confirm != null:
		_hero_confirm.text = "确 认 出 战   ·   %s" % str(HeroDefs.get_hero(local_hero).name)

	var definition: Dictionary = HeroDefs.get_hero(local_hero)
	var quote: String = str(definition.get("quote", definition.title))

	# 英雄台词展示横幅更新
	if _quote_label != null:
		_quote_label.text = "【%s】「%s」" % [definition.name, quote]
		if _quote_banner != null and is_inside_tree():
			_quote_banner.visible = true
			_quote_banner.modulate.a = 0.0
			var tween := create_tween()
			if tween:
				tween.tween_property(_quote_banner, "modulate:a", 1.0, 0.25)

	var hint := _screen_root.find_child("SelectedHint", true, false) as Label
	if hint != null:
		hint.text = "%s · %s     「%s」" % [definition.name, definition.role, quote]
		hint.add_theme_color_override("font_color", GameTheme.GOLD_LIGHT)

func _show_loading_transition(hero_type: String) -> void:
	if _loading_layer != null and is_instance_valid(_loading_layer):
		_loading_layer.queue_free()
	_loading_layer = CanvasLayer.new()
	_loading_layer.name = "LoadingLayer"
	# 独立顶层：主菜单 UI 隐藏后加载遮罩仍能覆盖战场与 HUD，直到构建完成。
	_loading_layer.layer = 20
	add_child(_loading_layer)

	_loading_screen = Control.new()
	_loading_screen.name = "LoadingScreen"
	_loading_screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_loading_screen.theme = GameTheme.theme()
	_loading_layer.add_child(_loading_screen)

	var bg := ColorRect.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.015, 0.025, 0.04, 0.98)
	_loading_screen.add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_loading_screen.add_child(center)

	var column := VBoxContainer.new()
	column.custom_minimum_size = Vector2(560, 0)
	column.add_theme_constant_override("separation", 14)
	center.add_child(column)

	var def := HeroDefs.get_hero(hero_type)
	var kicker := _make_label("E N T E R I N G   T H E   C A N Y O N", 13, GameTheme.GOLD)
	kicker.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(kicker)
	var title := _make_label("正在进入峡谷战场", 38, GameTheme.GOLD_LIGHT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(title)

	var sub := _make_label("%s  ·  %s     「%s」" % [def.name, def.role, def.get("quote", def.title)], 17, GameTheme.TEXT)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(sub)

	_loading_status = _make_label("正在构筑峡谷战场…   0%", 13, GameTheme.MUTED)
	_loading_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_loading_status)

	_loading_progress = ProgressBar.new()
	_loading_progress.custom_minimum_size = Vector2(0, 8)
	_loading_progress.show_percentage = false
	var style_bg := StyleBoxFlat.new()
	style_bg.bg_color = Color(0.08, 0.12, 0.16)
	style_bg.set_corner_radius_all(4)
	var style_fg := StyleBoxFlat.new()
	style_fg.bg_color = GameTheme.GOLD
	style_fg.set_corner_radius_all(4)
	_loading_progress.add_theme_stylebox_override("background", style_bg)
	_loading_progress.add_theme_stylebox_override("fill", style_fg)
	_loading_progress.value = 0.0
	column.add_child(_loading_progress)

func _on_arena_build_progress(value: float, text: String) -> void:
	if _loading_progress != null:
		_loading_progress.value = clampf(value, 0.0, 1.0) * 100.0
	if _loading_status != null:
		_loading_status.text = "%s   %d%%" % [text, int(round(clampf(value, 0.0, 1.0) * 100.0))]

func _hide_loading_transition() -> void:
	if _loading_layer == null or not is_instance_valid(_loading_layer):
		return
	var layer := _loading_layer
	var screen := _loading_screen
	_loading_layer = null
	_loading_screen = null
	_loading_progress = null
	_loading_status = null
	if screen != null and is_instance_valid(screen):
		var tween := create_tween()
		tween.tween_property(screen, "modulate:a", 0.0, 0.28)
		tween.chain().tween_callback(func():
			if is_instance_valid(layer):
				layer.queue_free()
		)
	else:
		layer.queue_free()

func _on_hero_confirm() -> void:
	if _pending_online:
		_show_online()
	else:
		_start_offline()

func _start_offline() -> void:
	var config := {
		"mode": _pending_mode,
		"humans": [{"id": "p1", "name": "你", "team": "blue", "hero_type": local_hero}],
		"bot_fill": true,
		"bot_ai": true,
	}
	_enter_match(config, null, true, "p1")

func _show_online() -> void:
	screen = "online"
	_clear_screen()
	_offer_signature = ""
	if not _discovery_hosting:
		discovery.start_browsing()

	var margin := _full_margin(70, 46)
	_screen_root.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 16)
	margin.add_child(column)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 16)
	column.add_child(header)
	var back := _small_button("‹  返回")
	back.custom_minimum_size = Vector2(150, _tap_height(46))
	back.pressed.connect(_show_hero_select)
	header.add_child(back)
	var titles := VBoxContainer.new()
	titles.add_theme_constant_override("separation", 2)
	header.add_child(titles)
	titles.add_child(_make_label("联机对战", 42, GameTheme.GOLD_LIGHT))
	titles.add_child(_make_label("%s  ·  局域网房间自动发现" % MODE_NAMES[_pending_mode], 14, GameTheme.MUTED))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)
	var name_label := _make_label("你的称号", 13, GameTheme.MUTED)
	name_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header.add_child(name_label)
	_name_input = LineEdit.new()
	_name_input.text = player_name
	_name_input.max_length = 12
	_name_input.custom_minimum_size = Vector2(230, _tap_height(46))
	_name_input.text_changed.connect(func(value): player_name = value if value.strip_edges() != "" else "无名客")
	header.add_child(_name_input)

	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 18)
	column.add_child(body)

	var create_panel := _section_panel("创建房间", "把房间码告诉好友，或让好友在局域网列表中找到你。")
	create_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(create_panel)
	var create_box: VBoxContainer = create_panel.get_meta("box")
	var hero_line := _make_label(
		"出战英雄   %s   ·   %s" % [HeroDefs.get_hero(local_hero).name, MODE_NAMES[_pending_mode]],
		16,
		GameTheme.GOLD_LIGHT
	)
	create_box.add_child(hero_line)
	var create_note := _make_label(
		"房间会以当前英雄开局。\n空余位置由 AI 自动补足。\n对局采用房主权威模拟，延迟低、无服务器依赖。",
		14,
		GameTheme.MUTED
	)
	create_note.add_theme_constant_override("line_spacing", 6)
	create_box.add_child(create_note)
	var filler := Control.new()
	filler.size_flags_vertical = Control.SIZE_EXPAND_FILL
	create_box.add_child(filler)
	var create_button := _menu_button("创 建 房 间")
	create_button.custom_minimum_size = Vector2(0, _tap_height(62))
	create_button.pressed.connect(_create_online_room)
	create_box.add_child(create_button)

	var join_panel := _section_panel("加入房间", "选择局域网房间，或输入房间码 / 直连地址。")
	join_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(join_panel)
	var join_box: VBoxContainer = join_panel.get_meta("box")

	var list_header := HBoxContainer.new()
	join_box.add_child(list_header)
	var list_title := _make_label("局域网房间", 16, GameTheme.TEXT)
	list_header.add_child(list_title)
	var list_spacer := Control.new()
	list_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_header.add_child(list_spacer)
	var refresh := _small_button("刷新")
	refresh.custom_minimum_size = Vector2(120, _tap_height(34))
	refresh.pressed.connect(_refresh_offers.bind(true))
	list_header.add_child(refresh)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 120 if touch_mode else 198)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	join_box.add_child(scroll)
	_offer_box = VBoxContainer.new()
	_offer_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_offer_box.add_theme_constant_override("separation", 8)
	scroll.add_child(_offer_box)
	_refresh_offers(true)

	join_box.add_child(_divider())
	var code_row := HBoxContainer.new()
	code_row.add_theme_constant_override("separation", 8)
	join_box.add_child(code_row)
	var code_input := LineEdit.new()
	code_input.name = "CodeInput"
	code_input.placeholder_text = "房间码"
	code_input.max_length = 5
	code_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	code_input.custom_minimum_size = Vector2(0, _tap_height(46))
	code_row.add_child(code_input)
	var code_button := _small_button("按码加入")
	code_button.custom_minimum_size = Vector2(130, _tap_height(46))
	code_button.pressed.connect(_join_by_code.bind(code_input))
	code_row.add_child(code_button)

	var ip_row := HBoxContainer.new()
	ip_row.add_theme_constant_override("separation", 8)
	join_box.add_child(ip_row)
	var ip_input := LineEdit.new()
	ip_input.name = "IpInput"
	ip_input.placeholder_text = "直连 IP，例如 192.168.1.8"
	ip_input.text = "127.0.0.1"
	ip_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ip_input.custom_minimum_size = Vector2(0, _tap_height(46))
	ip_row.add_child(ip_input)
	var ip_button := _small_button("直连加入")
	ip_button.custom_minimum_size = Vector2(130, _tap_height(46))
	ip_button.pressed.connect(_join_direct.bind(ip_input, code_input))
	ip_row.add_child(ip_button)

	_online_status = _make_label("", 13, GameTheme.MUTED)
	join_box.add_child(_online_status)

func _create_online_room() -> void:
	_sync_name()
	var result: Dictionary = session.host_game(GAME_PORT, player_name, local_hero, _pending_mode)
	if not bool(result.get("ok", false)):
		_set_online_status(_error_text(str(result.get("error", "bind_failed"))), true)
		return
	discovery.stop()
	var advert: Dictionary = discovery.start_advertising({
		"code": str(result.code),
		"name": player_name,
		"port": int(result.port),
		"mode": _pending_mode,
		"players": 1,
	}, LanDiscovery.DEFAULT_PORT)
	_discovery_hosting = bool(advert.get("ok", false))
	_show_lobby()

func _join_by_code(code_input: LineEdit) -> void:
	var code := code_input.text.strip_edges().to_upper()
	if code.is_empty():
		_set_online_status("请输入房间码", true)
		return
	for offer in discovery.offers:
		if str(offer.code) == code:
			_join_offer(offer)
			return
	_set_online_status("局域网中未找到该房间，可尝试使用直连 IP", true)

func _join_direct(ip_input: LineEdit, code_input: LineEdit) -> void:
	var address := ip_input.text.strip_edges()
	if address.is_empty():
		_set_online_status("请输入直连 IP", true)
		return
	_join(address, GAME_PORT, code_input.text.strip_edges().to_upper())

func _join_offer(offer: Dictionary) -> void:
	_join(str(offer.ip), int(offer.port), str(offer.code))

func _join(address: String, port: int, code: String) -> void:
	_sync_name()
	var result: Dictionary = session.join_game(address, port, player_name, local_hero, code)
	if not bool(result.get("ok", false)):
		_set_online_status(_error_text(str(result.get("error", "connect_failed"))), true)
		return
	discovery.stop()
	if _online_status != null:
		_online_status.text = "正在连接 %s:%d …" % [address, port]
		_online_status.add_theme_color_override("font_color", GameTheme.GOLD_LIGHT)

func _refresh_offers(force := false) -> void:
	if _offer_box == null or discovery == null:
		return
	var signature := ""
	for offer in discovery.offers:
		signature += "%s:%s:%s:%s;" % [offer.code, offer.ip, offer.port, offer.players]
	if signature == _offer_signature and not force:
		return
	_offer_signature = signature
	for child in _offer_box.get_children():
		child.queue_free()
	if discovery.offers.is_empty():
		var empty := _make_label("正在搜索局域网房间…\n确认双方处于同一网络，或使用直连 IP。", 13, GameTheme.MUTED)
		empty.add_theme_constant_override("line_spacing", 5)
		_offer_box.add_child(empty)
		return
	for offer in discovery.offers:
		var button := Button.new()
		button.text = "房间 %s   ·   %s   ·   %d / %d   ·   %s" % [
			offer.code,
			offer.name,
			int(offer.players),
			int(offer.capacity),
			MODE_NAMES.get(str(offer.mode), "1V1"),
		]
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.custom_minimum_size = Vector2(0, _tap_height(48))
		button.add_theme_font_size_override("font_size", 15)
		button.pressed.connect(_join_offer.bind(offer))
		_offer_box.add_child(button)

func _show_lobby() -> void:
	if session == null or session.room_state.is_empty():
		return
	var signature: String = JSON.stringify(session.room_state)
	if screen == "lobby" and signature == _lobby_signature:
		return
	_lobby_signature = signature
	screen = "lobby"
	_clear_screen()

	if session.is_server and _discovery_hosting:
		discovery.update_advertising({
			"code": session.room_code,
			"name": player_name,
			"port": session.listen_port,
			"mode": _pending_mode,
			"players": session.room_state.players.size(),
		})

	var margin := _full_margin(64, 44)
	_screen_root.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 14)
	margin.add_child(column)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 16)
	column.add_child(header)
	var back := _small_button("‹  离开房间")
	back.custom_minimum_size = Vector2(170, _tap_height(46))
	back.pressed.connect(_leave_online)
	header.add_child(back)
	var titles := VBoxContainer.new()
	titles.add_theme_constant_override("separation", 2)
	header.add_child(titles)
	titles.add_child(_make_label("房 间  %s" % session.room_code, 40, GameTheme.GOLD_LIGHT))
	titles.add_child(_make_label("%s  ·  %s  ·  %d / %d 名玩家" % [
		MODE_NAMES.get(str(session.room_state.get("mode", "duel")), "1V1"),
		"房主" if session.is_server else "已加入",
		session.room_state.players.size(),
		int(session.room_state.get("capacity", 2)),
	], 14, GameTheme.MUTED))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)
	var copy := _small_button("复制房间码")
	copy.custom_minimum_size = Vector2(170, _tap_height(46))
	copy.pressed.connect(func():
		DisplayServer.clipboard_set(session.room_code)
		_set_lobby_status("房间码已复制", false)
	)
	header.add_child(copy)

	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 18)
	column.add_child(body)

	var capacity := int(session.room_state.get("capacity", 2))
	var players: Array = session.room_state.get("players", [])
	var blue_players: Array = players.filter(func(player): return str(player.team) == "blue")
	var red_players: Array = players.filter(func(player): return str(player.team) == "red")

	var blue := _team_panel("蓝 方", "TEAM BLUE", GameTheme.BLUE, blue_players, 5 if capacity > 2 else 1, "blue")
	blue.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(blue)

	var center := VBoxContainer.new()
	center.custom_minimum_size = Vector2(260, 0)
	center.add_theme_constant_override("separation", 10)
	body.add_child(center)
	var vs := _make_label("VS", 68, GameTheme.GOLD)
	vs.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	center.add_child(vs)
	var center_tip := _make_label(
		"空位由 AI 补位\n所有玩家可在开局前更换英雄",
		13,
		GameTheme.MUTED
	)
	center_tip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	center.add_child(center_tip)
	var center_filler := Control.new()
	center_filler.size_flags_vertical = Control.SIZE_EXPAND_FILL
	center.add_child(center_filler)
	if session.is_server:
		var start := _menu_button("开 始 对 局")
		start.custom_minimum_size = Vector2(0, _tap_height(64))
		start.pressed.connect(_start_online_match)
		center.add_child(start)
	else:
		var waiting := _make_label("等待房主开始对局…", 15, GameTheme.MUTED)
		waiting.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		center.add_child(waiting)
	_lobby_status = _make_label("", 13, GameTheme.MUTED)
	_lobby_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	center.add_child(_lobby_status)

	var red := _team_panel("红 方", "TEAM RED", GameTheme.RED, red_players, 5 if capacity > 2 else 1, "red")
	red.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(red)

	var picker := HBoxContainer.new()
	picker.add_theme_constant_override("separation", 10)
	column.add_child(picker)
	picker.add_child(_make_label("出战英雄", 14, GameTheme.MUTED))
	for hero_type in HERO_ORDER:
		var hero_def: Dictionary = HeroDefs.get_hero(hero_type)
		var button := _small_button(str(hero_def.name))
		button.custom_minimum_size = Vector2(130, _tap_height(42))
		button.add_theme_font_size_override("font_size", 15)
		if hero_type == local_hero:
			button.add_theme_color_override("font_color", GameTheme.GOLD_LIGHT)
		button.pressed.connect(_choose_lobby_hero.bind(hero_type))
		picker.add_child(button)
	var picker_spacer := Control.new()
	picker_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	picker.add_child(picker_spacer)
	picker.add_child(_make_label("局域网房间码可被同网好友直接发现", 12, GameTheme.MUTED))

func _team_panel(
	title: String,
	subtitle: String,
	color: Color,
	players: Array,
	slots: int,
	team: String
) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", GameTheme.style(Color(0.02, 0.045, 0.06, 0.9), Color(color.r, color.g, color.b, 0.5), 1, 12))
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 18)
	margin.add_theme_constant_override("margin_right", 18)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_bottom", 16)
	panel.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	margin.add_child(box)
	var title_label := _make_label(title, 26, color)
	box.add_child(title_label)
	box.add_child(_make_label(subtitle, 11, Color(color.r, color.g, color.b, 0.7)))
	box.add_child(_divider())
	for index in slots:
		var player: Variant = players[index] if index < players.size() else null
		box.add_child(_player_slot(player, team))
	return panel

func _player_slot(player: Variant, team: String) -> PanelContainer:
	var slot := PanelContainer.new()
	slot.add_theme_stylebox_override("panel", GameTheme.style(Color(0.035, 0.06, 0.08, 0.85), Color(0.28, 0.27, 0.2, 0.4), 1, 8))
	slot.custom_minimum_size = Vector2(0, 68)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	slot.add_child(row)
	var color := GameTheme.BLUE if team == "blue" else GameTheme.RED
	if player == null:
		var empty := _make_label("空位   ·   AI 补位", 15, GameTheme.MUTED)
		empty.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(empty)
		return slot

	var hero_type := str(player.get("hero_type", "blade"))
	var portrait := TextureRect.new()
	portrait.texture = load(GameTheme.portrait_path(hero_type))
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	portrait.custom_minimum_size = Vector2(52, 52)
	row.add_child(portrait)
	var info := VBoxContainer.new()
	info.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	info.add_theme_constant_override("separation", 0)
	row.add_child(info)
	var name_line := HBoxContainer.new()
	name_line.add_theme_constant_override("separation", 8)
	info.add_child(name_line)
	name_line.add_child(_make_label(str(player.name), 17, GameTheme.TEXT))
	if int(player.id) == int(session.room_state.get("host_id", 0)):
		name_line.add_child(_make_label("房主", 11, GameTheme.GOLD))
	var hero_def: Dictionary = HeroDefs.get_hero(hero_type)
	var hero_line := _make_label("%s · %s" % [hero_def.name, hero_def.role], 12, color)
	info.add_child(hero_line)
	if int(player.id) == _local_peer_id():
		slot.add_theme_stylebox_override("panel", GameTheme.style(Color(0.07, 0.1, 0.12, 0.95), GameTheme.GOLD, 1, 8))
	return slot

func _choose_lobby_hero(hero_type: String) -> void:
	local_hero = hero_type
	session.choose_hero(hero_type)
	_lobby_signature = ""
	_show_lobby()

func _start_online_match() -> void:
	var result: Dictionary = session.start_match()
	if not bool(result.get("ok", false)):
		_set_lobby_status(_error_text(str(result.get("error", "start_failed"))), true)

func _leave_online() -> void:
	session.close()
	discovery.stop()
	_discovery_hosting = false
	_show_online()

func _enter_match(config: Dictionary, active_session: Object, authoritative: bool, owner: String) -> void:
	screen = "game"
	discovery.stop()
	_lobby_signature = ""

	for vid in _hero_videos.values():
		if is_instance_valid(vid) and vid is VideoStreamPlayer:
			vid.stop()

	_show_loading_transition(local_hero)
	_ui.visible = false
	await get_tree().process_frame

	_arena = Arena.new()
	_arena.name = "Arena"
	_arena.configure({
		"config": config,
		"authoritative": authoritative,
		"local_owner": owner,
		"session": active_session,
	})
	_arena.build_progress.connect(_on_arena_build_progress)
	add_child(_arena)
	_arena.exit_requested.connect(_leave_game)

	# 遮罩下分帧构建：构建完成后再多渲染两帧，让首批材质/着色器在
	# 遮罩后面完成首次编译，避免揭幕瞬间一次卡死。
	while is_instance_valid(_arena) and not _arena.build_complete:
		await get_tree().process_frame
	if not is_instance_valid(_arena) or screen != "game":
		_hide_loading_transition()
		return
	await get_tree().process_frame
	await get_tree().process_frame
	_hide_loading_transition()

func _leave_game() -> void:
	if session != null:
		session.close()
	discovery.stop()
	_discovery_hosting = false
	_hide_loading_transition()
	if is_instance_valid(_arena):
		_arena.queue_free()
	_arena = null
	if _audio != null:
		# 可能是在暂停菜单里直接退出的：不复位的话菜单音乐会一直是被压低的状态。
		_audio.set_paused(false)
	_ui.visible = true
	_show_menu()

func _on_network_snapshot(snapshot: Dictionary) -> void:
	if screen == "game" and is_instance_valid(_arena):
		_arena.receive_snapshot(snapshot)

func _on_network_input(peer_id: int, input: Dictionary) -> void:
	if screen == "game" and is_instance_valid(_arena):
		_arena.apply_remote_input(peer_id, input)

func _on_network_peer_left(peer_id: int) -> void:
	if screen == "game" and is_instance_valid(_arena):
		_arena.on_peer_left(peer_id)

func _on_session_state(value: String) -> void:
	if value == "lobby":
		if screen in ["online", "joining"]:
			_show_lobby()
	elif value == "rejected":
		if screen == "game":
			return
		_show_online()
		_set_online_status(_error_text(session.last_error), true)
	elif value == "disconnected":
		if screen == "game":
			_on_session_error("host_disconnected")
		elif screen in ["online", "joining"]:
			_show_online()
			_set_online_status(_error_text(session.last_error), true)
		elif screen == "lobby":
			_show_online()
			_set_online_status(_error_text(session.last_error), true)

func _on_room_updated(_state: Dictionary) -> void:
	if screen == "lobby":
		_show_lobby()

func _on_match_started(config: Dictionary) -> void:
	if screen == "game" or session == null:
		return
	var owner := "1"
	if not session.is_server:
		owner = str(session.local_peer_id)
	_enter_match(config, session, session.is_server, owner)

func _on_session_error(code: String) -> void:
	_play_ui_error()
	if screen == "game":
		if is_instance_valid(_arena) and _arena.hud != null:
			_arena.hud.add_feed(_error_text(code), GameTheme.RED)
			_arena.hud.announce("连接中断", GameTheme.RED, 2.0)
		if code == "host_disconnected":
			await get_tree().create_timer(2.4).timeout
			if screen == "game":
				_leave_game()
		return
	if screen in ["online", "joining"]:
		_set_online_status(_error_text(code), true)
	elif screen == "lobby":
		_set_lobby_status(_error_text(code), true)

func _local_peer_id() -> int:
	if session == null:
		return 0
	return int(session.local_peer_id)

func _sync_name() -> void:
	if _name_input != null:
		var value := _name_input.text.strip_edges()
		player_name = value if not value.is_empty() else "无名客"
	if player_name.strip_edges().is_empty():
		player_name = "无名客"

func _set_online_status(text: String, error: bool) -> void:
	if _online_status == null:
		return
	_online_status.text = text
	_online_status.add_theme_color_override("font_color", GameTheme.RED if error else GameTheme.GOLD_LIGHT)

func _set_lobby_status(text: String, error: bool) -> void:
	if _lobby_status == null:
		return
	_lobby_status.text = text
	_lobby_status.add_theme_color_override("font_color", GameTheme.RED if error else GameTheme.MUTED)

func _error_text(code: String) -> String:
	return str(ERROR_TEXT.get(code, "网络错误：%s" % code))

func _full_margin(horizontal: int, vertical: int) -> MarginContainer:
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", horizontal)
	margin.add_theme_constant_override("margin_right", horizontal)
	margin.add_theme_constant_override("margin_top", vertical)
	margin.add_theme_constant_override("margin_bottom", vertical)
	return margin

func _clear_screen() -> void:
	if _screen_root == null:
		return
	for child in _screen_root.get_children():
		_screen_root.remove_child(child)
		_queue_free_tree(child)
	_hero_cards.clear()
	_hero_marks.clear()
	_hero_videos.clear()
	_hero_confirm = null
	_quote_banner = null
	_quote_label = null
	_online_status = null
	_name_input = null
	_offer_box = null
	_lobby_status = null

func _queue_free_tree(node: Node) -> void:
	# 逐节点标记：只 queue_free 根节点时，子树各节点在帧末前都不会处于
	# 「已排队删除」状态，视频/模型资源会多驻留一整个切换帧。
	for child in node.get_children():
		_queue_free_tree(child)
	node.queue_free()

func _menu_button(text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(0, TouchLayout.BUTTON_HEIGHT if touch_mode else 58)
	button.add_theme_font_size_override("font_size", 20)
	_polish_button(button, 1.02)
	return button

func _small_button(text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(0, TouchLayout.BUTTON_HEIGHT if touch_mode else 0)
	button.add_theme_font_size_override("font_size", 15)
	_polish_button(button, 1.035)
	return button

## 悬停时轻微放大 + 主题里更长的投影 = 按钮离开面板浮到前景
func _polish_button(button: Button, lift: float) -> void:
	button.resized.connect(func() -> void: button.pivot_offset = button.size * 0.5)
	button.mouse_entered.connect(_animate_lift.bind(button, lift))
	button.mouse_exited.connect(_animate_lift.bind(button, 1.0))
	# 点击音统一挂在这里：菜单、选人、大厅所有按钮一次覆盖，不用逐个接线。
	button.pressed.connect(_play_ui_click)

func _play_ui_click() -> void:
	if _audio != null:
		_audio.play_cue(AudioCues.CUE_UI_CLICK)

func _play_ui_confirm() -> void:
	if _audio != null:
		_audio.play_cue(AudioCues.CUE_UI_CONFIRM)

func _play_ui_error() -> void:
	if _audio != null:
		_audio.play_cue(AudioCues.CUE_UI_ERROR)

func _animate_lift(button: Button, target_scale: float) -> void:
	if not is_instance_valid(button) or not button.is_inside_tree():
		return
	button.pivot_offset = button.size * 0.5
	if button.has_meta("lift_tween"):
		var previous: Variant = button.get_meta("lift_tween")
		if previous is Tween and (previous as Tween).is_valid():
			(previous as Tween).kill()
	var tween := button.create_tween()
	tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(button, "scale", Vector2.ONE * target_scale, 0.14)
	button.set_meta("lift_tween", tween)

## 入场：整体淡入，可选逐个错峰
func _fade_in(nodes: Array, delay: float, step: float = 0.0) -> void:
	var cursor := delay
	for node in nodes:
		var item := node as CanvasItem
		if item == null or not item.is_inside_tree():
			continue
		item.modulate.a = 0.0
		var tween := item.create_tween()
		tween.tween_interval(cursor)
		tween.tween_property(item, "modulate:a", 1.0, 0.3).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		cursor += step

func _tap_height(desktop: float) -> float:
	return TouchLayout.button_height(touch_mode, desktop)

func _make_label(text: String, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.autowrap_mode = TextServer.AUTOWRAP_OFF
	return label

func _chip(text: String) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", GameTheme.style(Color(0.03, 0.06, 0.08, 0.72), Color(0.45, 0.37, 0.22, 0.55), 1, 20))
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_top", 7)
	margin.add_theme_constant_override("margin_bottom", 7)
	panel.add_child(margin)
	margin.add_child(_make_label(text, 12, Color(0.8, 0.82, 0.78)))
	return panel

func _divider() -> ColorRect:
	var line := ColorRect.new()
	line.color = Color(0.55, 0.45, 0.26, 0.32)
	line.custom_minimum_size = Vector2(0, 1)
	return line

func _section_panel(title: String, subtitle: String) -> PanelContainer:
	var panel: PanelContainer = DepthCard.build(
		Color(0.018, 0.036, 0.052, 0.92), Color(0.45, 0.36, 0.2, 0.5), 12, 20, 22
	)
	var box: VBoxContainer = panel.get_meta("box")
	box.add_theme_constant_override("separation", 9)
	box.add_child(_make_label(title, 25, GameTheme.GOLD_LIGHT))
	box.add_child(_make_label(subtitle, 12, GameTheme.MUTED))
	box.add_child(_divider())
	return panel

func _ignore_mouse_children(node: Node) -> void:
	for child in node.get_children():
		if child is Control:
			(child as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
		_ignore_mouse_children(child)
