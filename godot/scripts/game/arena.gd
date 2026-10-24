extends Node3D

signal exit_requested
# 分帧构建进度：0..1 与阶段说明，交给外层加载遮罩显示。
signal build_progress(value: float, text: String)
signal ready_for_battle

const MatchSim = preload("res://sim/match_sim.gd")
const MapData = preload("res://sim/map_data.gd")
const HeroDefs = preload("res://sim/hero_defs.gd")
const ModelUtils = preload("res://scripts/game/model_utils.gd")
const TerrainBuilder = preload("res://scripts/game/terrain_builder.gd")
const GrassField = preload("res://scripts/game/grass_field.gd")
const UnitVisual = preload("res://scripts/game/unit_visual.gd")
const GameHUD = preload("res://scripts/ui/game_hud.gd")
const GameTheme = preload("res://scripts/ui/game_theme.gd")
const InputAssist = preload("res://scripts/game/input_assist.gd")
const MatchMenu = preload("res://scripts/game/match_menu.gd")
const MapView = preload("res://scripts/game/map_view.gd")
const BushFeedback = preload("res://scripts/game/bush_feedback.gd")
const ChannelFeedback = preload("res://scripts/game/channel_feedback.gd")
const ChannelFx = preload("res://scripts/game/channel_fx.gd")
const AudioCues = preload("res://scripts/game/audio_cues.gd")
const AudioDirector = preload("res://scripts/game/audio_director.gd")
const HitStopManager = preload("res://scripts/view/hit_stop_manager.gd")
const CameraFocus = preload("res://scripts/game/camera_focus.gd")
const ClientPrediction = preload("res://net/client_prediction.gd")
const BAR_SHADER := preload("res://shaders/billboard_bar.gdshader")

const ENV_DIR := "res://assets/environment/"
const TICK := 1.0 / 30.0
const BASE_FOV := 42.0
# 焦段过渡速率（度/秒）。进出草丛只差约 3.4°，0.15s 左右走完。
const FOV_GLIDE_SPEED := 24.0
# 相机缩放的滑行速率（zoom 单位/秒）。滚轮一次 ±2，约 0.14s 走完，匀速不突兀。
const ZOOM_GLIDE_SPEED := 14.0
# 小地图定位时注视点的滑行速率（世界单位/秒）。要跟得上手指拖动，
# 所以比相机缩放快得多：跨半张图（约 58m）0.3s 走完。
const CAMERA_FOCUS_GLIDE_SPEED := 200.0
# 松手归位的速率。比观察更快 —— 「不按了立刻回到自己的画面」，
# 跨整张图（116m）0.36s，体感是「唰一下回来」而不是「慢慢飘回去」。
const CAMERA_FOCUS_RETURN_SPEED := 320.0
# 客机渲染相对服务端的固定延迟。要略大于一个快照周期（服务端 10Hz ≈ 0.1s），
# 否则缓冲里凑不齐两格；取 0.16 给网络抖动留余量。
const NET_RENDER_DELAY := 0.16
# 快照缓冲深度上限（约 1.6s）。只做兜底，正常情况远不会填满。
const NET_BUFFER_LIMIT := 16
# 地面射程环的高度。要略高于路面（0.022）与河水（0.012），避免被 z-fighting 吃掉。
const RANGE_RING_Y := 0.06
const BLUE := Color(0.22, 0.6, 1.0)
const RED := Color(1.0, 0.32, 0.26)
const GOLD := Color(1.0, 0.8, 0.38)
# 点击移动的到达判定（世界单位）。英雄碰撞半径 0.5~0.65，取 0.3 让「站到那个点」自然收住，
# 又不会因为步长（speed*TICK ≈ 0.2）越过目标而在点上来回抽搐。
const MOVE_ARRIVE_EPS := 0.3
# 绿色移动指示环的呼吸幅度 / 频率
const MOVE_MARKER_PULSE := 0.06
const MOVE_MARKER_PULSE_HZ := 7.0
const KILL_ANNOUNCEMENTS := {
	"first_blood": "第一滴血",
	"double_kill": "双杀",
	"triple_kill": "三杀",
	"quadra_kill": "四杀",
	"penta_kill": "五杀",
	"shutdown": "终结",
}
const STREAK_TITLES := {
	"killing_spree": "大杀特杀",
	"rampage": "暴走",
	"godlike": "横扫千军",
	"legendary": "天下无双",
}

var config: Dictionary = {}
var mode := "duel"
var authoritative := true
var local_owner := "p1"
var local_team := "blue"
var local_hero_type := "blade"
var local_name := "你"
var session = null
var sim: Object = null

var current_snapshot: Dictionary = {}
var _views: Dictionary = {}
var _structure_views: Dictionary = {}
var _units_root: Node3D
var _structures_root: Node3D
var _effects_root: Node3D
var _props_root: Node3D
# 地形实例：布景（山 / 树 / 石头）要靠它取实际地面高度，
# 否则摆件会悬在坡上或陷进土里。
var _terrain = null
var camera: Camera3D
var hud: GameHUD
var aim_marker: Node3D
var aim_material: StandardMaterial3D
# 本地英雄脚下的普攻范围环（常驻）。技能范围环是按需生成的临时节点。
var attack_range_ring: MeshInstance3D
var lock_ring: MeshInstance3D
var _attack_mode := "default"
var _locked_target := -1
var zoom := 21.0
# 渲染用的平滑缩放值。相机位置必须刚性跟随角色（否则与 look_at 产生相位差而抖动），
# 但 zoom 突变会让整台相机瞬移，所以单独对 zoom 这个标量做插值。
var _zoom_current := 21.0
# 小地图定位（点 / 拖）时的相机注视点。常态下它返回英雄位置（刚性跟随），
# 只有观察态才滑行到别处，所以移动稳定性不受影响。
var _camera_focus = CameraFocus.new()
# 上一帧是否有操作意图。只在「从无到有」时收回镜头，避免持续按住移动时
# 把拖地图的操作打断掉。
var _last_intent := false
var _cam_initialized := false
var _accumulator := 0.0
# 渲染插值系数：0 = 上一 tick 的位置，1 = 当前 tick 的位置。
# 由模拟侧的时间余量或网络快照间隔驱动，保证渲染帧与 30Hz 模拟解耦。
var _render_alpha := 1.0
# --- 客机 jitter buffer ---
# 不依赖快照到达的节奏：收到的快照按时间戳入队，渲染时刻固定回退
# NET_RENDER_DELAY，在队列里找该时刻所在的两格做插值。网络抖动只影响
# 缓冲深度，不影响插值区间长度，所以对手移动是匀速的。
var _snapshot_buffer: Array[Dictionary] = []
var _render_snapshot: Dictionary = {}
var _render_prev_positions: Dictionary = {}
var _hud_timer := 0.0
var _snapshot_timer := 0.0
var _input_timer := 0.0
var _pending_events: Array = []
var _paused := false
var _local_id := -1
var _local_entity_id := -1
var _hit_stop := HitStopManager.new()
var _camera_shake := 0.0
# 客机本地预测：立即响应移动输入，再用服务端 last_input_seq 校正。
var _prediction = ClientPrediction.new()
var _prediction_ready := false
var _prediction_entity_id := -1
# 草丛进出：状态机 → HUD 隐匿提示 + 焦段目标 + 合成音效。
var _bush_feedback = BushFeedback.new()
var _bush_hidden := false
var _camera_fov_target := BASE_FOV
var _bush_audio: AudioStreamPlayer
# 回城 / 传送：每个英雄一套引导状态机与地面法阵，按需创建，引导结束自动淡出。
var _channel_feedback: Dictionary = {}
var _channel_fx: Dictionary = {}
var _channel_audio: AudioStreamPlayer
# 音频导演：BGM + 战斗音效。由 main.gd 传入（与菜单共用一个播放器），
# 单独跑 arena 的工具/截图场景会自建一个。
var _audio: Node = null
var _shared_audio: Node = null
var touch_mode := false
var _mouse_ground := Vector2.ZERO
var _mouse_valid := false
# 点击移动的目标点。每次左键点击都整份覆盖 —— 「以最后一次点击为准」就是靠这里，
# 不存在排队或叠加，点十次只有最后一个生效。
var _move_target := Vector2.ZERO
var _move_target_valid := false
var move_marker: Node3D
var move_material: StandardMaterial3D
var _move_marker_pulse := 0.0
var _touch_move := Vector2.ZERO
var _touch_attack := false
var _touch_aim := Vector2.ZERO
var _touch_aim_valid := false
var _touch_aim_timer := 0.0
var _touch_last_aim := Vector2.ZERO
var _auto_aim := Vector2.ZERO
var _auto_aim_valid := false
var _touch_points: Dictionary = {}
var _pinch_distance := -1.0
var _prev_q := false
var _prev_w := false
var _prev_e := false
var _prev_r := false
var _prev_summoner := false
var _queued_q := false
var _queued_w := false
var _queued_e := false
var _queued_r := false
var _queued_summoner := false
var _queued_recall := false
var _queued_teleport := false
var _pending_purchases: Array[Dictionary] = []
var _input_seq := 0
var _local_input := {
	"move": Vector2.ZERO,
	"aim": Vector2.ZERO,
	"skill_q": false,
	"skill_w": false,
	"skill_e": false,
	"skill_r": false,
	"summoner": false,
	"attack": false,
	"attack_mode": "default",
	"locked_target": -1,
	"recall": false,
	"teleport": false,
	"buy_item": "",
	"sell_slot": -1,
	"seq": 0,
}
var _started_announcement := false

# --- 高性能对象池与复用（解决高频分配造成的对战卡顿与 GC 抖动） ---
const FONT_SC := preload("res://assets/fonts/NotoSansSC.ttf")
# 首波每方 9 个小兵；预热两波左右，保证前几波刷新不再单帧实例化模型。
const MINION_PREWARM_PER_TEAM := 18
const MINION_POOL_LIMIT := 40
var _minion_pool_blue: Array[UnitVisual] = []
var _minion_pool_red: Array[UnitVisual] = []
var _damage_labels_pool: Array[Label3D] = []
var _hit_particles_pool: Array[GPUParticles3D] = []
var build_complete := false

func configure(options: Dictionary) -> void:
	config = options.get("config", {}).duplicate(true)
	authoritative = bool(options.get("authoritative", true))
	local_owner = str(options.get("local_owner", "p1"))
	session = options.get("session", null)
	mode = str(config.get("mode", "duel"))
	for entry in config.get("humans", []):
		if str(entry.get("id", "")) == local_owner:
			local_team = str(entry.get("team", "blue"))
			local_hero_type = str(entry.get("hero_type", "blade"))
			local_name = str(entry.get("name", "你"))
			break
	if authoritative:
		sim = MatchSim.new(config)

func _ready() -> void:
	touch_mode = InputAssist.wants_touch_controls(config, OS.has_feature("mobile"), DisplayServer.is_touchscreen_available())
	_build_staged()

# 战场构建拆成多帧：进场时加载遮罩保持可见，每帧只做一小段，
# 避免一次性实例化近千个节点造成数秒冻结与着色器编译尖峰。
func _build_staged() -> void:
	_emit_build(0.02, "架起天空与光照")
	_build_environment()
	_props_root = Node3D.new()
	_props_root.name = "Map"
	add_child(_props_root)
	await _next_frame()

	_emit_build(0.08, "铺设峡谷地面")
	_build_ground()
	await _next_frame()

	_emit_build(0.16, "铺开三路兵线")
	await _build_lanes()
	_build_river()
	await _next_frame()

	_emit_build(0.28, "种下峡谷植被")
	await _build_scenery()
	_build_grass_tufts()
	_build_map_features()
	await _next_frame()

	_emit_build(0.42, "摆放战场设施")
	_units_root = Node3D.new()
	_units_root.name = "Units"
	add_child(_units_root)
	_structures_root = Node3D.new()
	_structures_root.name = "Structures"
	add_child(_structures_root)
	_effects_root = Node3D.new()
	_effects_root.name = "Effects"
	add_child(_effects_root)
	# 合成战斗配乐要跑几十万次采样（约 0.3~0.6s），必须摊在加载遮罩下面做，
	# 否则会变成进场瞬间的一次卡顿。
	_emit_build(0.46, "调音：合成战斗配乐")
	_build_audio()
	await _next_frame()
	_init_vfx_pools()
	_build_camera()
	_build_bush_audio()
	_build_channel_audio()
	_build_aim_marker()
	_build_move_marker()
	_build_range_indicators()
	_build_ambient_particles()
	await _next_frame()

	_emit_build(0.5, "点亮英雄与防御塔")
	if sim != null:
		# 主机/单机也走战争迷雾：本地玩家只能看到本队视野内的单位。
		current_snapshot = sim.snapshot_for(local_team)
		_sync_structures(current_snapshot, true)
		await _next_frame()
		await _create_initial_views_staged(current_snapshot)

	_emit_build(0.72, "装配战斗界面")
	_build_hud()
	_update_camera(1.0, true)
	if current_snapshot.is_empty():
		hud.update_snapshot({})
	else:
		hud.update_snapshot(current_snapshot)
	await _next_frame()

	_emit_build(0.82, "预热战场单位")
	await _prewarm_minion_pool()

	if session != null and session.has_method("is_online") and session.is_online():
		_local_id = int(local_owner) if local_owner.is_valid_int() else -1

	build_complete = true
	_emit_build(1.0, "进入峡谷")
	ready_for_battle.emit()
	await get_tree().create_timer(0.45).timeout
	if is_inside_tree():
		hud.announce("对 决 开 始", GameTheme.GOLD_LIGHT, 1.5)
		_started_announcement = true

func _next_frame() -> void:
	await get_tree().process_frame

func _emit_build(value: float, text: String) -> void:
	build_progress.emit(clampf(value, 0.0, 1.0), text)

# 初始单位逐个入场：每个英雄/小兵建好后再让出一帧，确保加载界面持续响应。
func _create_initial_views_staged(snapshot: Dictionary) -> void:
	var created := 0
	for entity in snapshot.get("entities", []):
		var entity_type := str(entity.get("type", ""))
		if entity_type != "hero" and entity_type != "minion" and entity_type != "monster":
			continue
		if entity_type != "hero" and not bool(entity.get("alive", false)):
			continue
		var entity_id := int(entity.get("id", -1))
		if _views.has(entity_id):
			continue
		var view := _create_unit_view(entity)
		_views[entity_id] = view
		created += 1
		if created % 2 == 0:
			await _next_frame()
	_sync_units(snapshot, 0.0)

# 预热小兵模型（不进入 _views）：第一波刷新只做对象复用，不再实例化骨骼与动画。
func _prewarm_minion_pool() -> void:
	for team in ["blue", "red"]:
		var pool := _minion_pool_blue if team == "blue" else _minion_pool_red
		var made := 0
		while pool.size() < MINION_PREWARM_PER_TEAM:
			var view := UnitVisual.new()
			view.setup("minion", team, "minion", "", false, local_team)
			_units_root.add_child(view)
			view.visible = false
			view.recycle()
			pool.append(view)
			made += 1
			if made % 2 == 0:
				await _next_frame()

func _build_hud() -> void:
	var layer := CanvasLayer.new()
	layer.name = "HUD"
	layer.layer = 10
	add_child(layer)
	hud = GameHUD.new()
	hud.setup(local_owner, local_team, local_hero_type, local_name, touch_mode, session != null)
	hud.skill_pressed.connect(_on_skill_button)
	hud.attack_mode_changed.connect(_on_attack_mode_changed)
	hud.lock_changed.connect(_on_lock_changed)
	hud.buy_item_requested.connect(_on_buy_item_requested)
	hud.sell_item_requested.connect(_on_sell_item_requested)
	hud.skill_aim_released.connect(_on_skill_aim_released)
	hud.set_targeting_state(_attack_mode, _locked_target)
	hud.leave_requested.connect(_on_leave_requested)
	hud.resume_requested.connect(_on_resume_requested)
	hud.move_changed.connect(_on_touch_move)
	hud.attack_changed.connect(_on_touch_attack)
	hud.pause_requested.connect(_toggle_pause)
	hud.map_focus_requested.connect(focus_world_point)
	hud.map_focus_released.connect(release_camera_focus)
	layer.add_child(hud)

func _on_skill_button(slot: String) -> void:
	# 按了但放不出来（CD / 蓝不够）必须有声音反馈：手机上玩家看不到 CD 数字时，
	# 「按了没反应」是最容易让人以为游戏卡住的状态。
	if _skill_blocked(slot):
		if _audio != null:
			_audio.play_cue(AudioCues.CUE_DENIED)
		return
	if slot == "q":
		_queued_q = true
	elif slot == "w":
		_queued_w = true
	elif slot == "e":
		_queued_e = true
	elif slot == "r":
		_queued_r = true
	elif slot == "summoner":
		_queued_summoner = true
	elif slot == "recall":
		_queued_recall = true
	elif slot == "teleport":
		_queued_teleport = true

func _on_attack_mode_changed(mode: String) -> void:
	_attack_mode = mode
	_local_input.attack_mode = mode

func _on_lock_changed(target_id: int) -> void:
	_locked_target = target_id
	_local_input.locked_target = target_id

func _on_buy_item_requested(item_id: String) -> void:
	if item_id != "":
		_pending_purchases.append({"buy_item": item_id})

func _on_sell_item_requested(slot_index: int) -> void:
	if slot_index >= 0:
		_pending_purchases.append({"sell_slot": slot_index})

# 触摸技能是「按下开始瞄准、松手施放」：松手位置投到地面作为本次施法方向；
# 拖进取消区则整次施法作废。
func _on_skill_aim_released(slot: String, screen_pos: Vector2, cancelled: bool) -> void:
	if cancelled:
		return
	if _project_ground(screen_pos):
		_touch_aim = _mouse_ground
		_touch_aim_valid = true
		_touch_aim_timer = 3.0
	_on_skill_button(slot)

func _on_touch_move(value: Vector2) -> void:
	_touch_move = value

func _on_touch_attack(value: bool) -> void:
	_touch_attack = value

func _on_leave_requested() -> void:
	_exit_game()

func _on_resume_requested() -> void:
	_close_pause()

func _exit_game() -> void:
	if session != null and session.has_method("close"):
		session.close()
	exit_requested.emit()

func _unhandled_input(event: InputEvent) -> void:
	if not build_complete:
		return
	if touch_mode and _handle_touch_event(event):
		return
	if event is InputEventMouseButton:
		var mouse := event as InputEventMouseButton
		if mouse.pressed and mouse.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom = maxf(14.0, zoom - 2.0)
		elif mouse.pressed and mouse.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom = minf(34.0, zoom + 2.0)
		elif mouse.pressed and not touch_mode and mouse.button_index == MOUSE_BUTTON_LEFT:
			# 左键点地 = 走到那个点。用事件自带的坐标而不是缓存的 _mouse_ground，
			# 否则「先点、鼠标同一帧还在上一帧位置」时点偏一点点。
			if _project_ground(mouse.position):
				_set_move_target(_mouse_ground)
	if event is InputEventKey:
		var key := event as InputEventKey
		if key.pressed and not key.echo and key.keycode == KEY_ESCAPE:
			_toggle_pause()

func _handle_touch_event(event: InputEvent) -> bool:
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed:
			_touch_points[touch.index] = touch.position
			if _touch_points.size() >= 2:
				_pinch_distance = _touch_pair_distance()
			else:
				_set_touch_aim(touch.position)
		else:
			_touch_points.erase(touch.index)
			if _touch_points.size() < 2:
				_pinch_distance = -1.0
		return true
	if event is InputEventScreenDrag:
		var drag := event as InputEventScreenDrag
		if not _touch_points.has(drag.index):
			return false
		_touch_points[drag.index] = drag.position
		if _touch_points.size() >= 2:
			var distance := _touch_pair_distance()
			if _pinch_distance > 0.0:
				zoom = clampf(zoom - (distance - _pinch_distance) * 0.018, 14.0, 34.0)
			_pinch_distance = distance
		else:
			_set_touch_aim(drag.position)
		return true
	return false

func _touch_pair_distance() -> float:
	var points: Array = _touch_points.values()
	if points.size() < 2:
		return -1.0
	var first: Vector2 = points[0]
	var second: Vector2 = points[1]
	return first.distance_to(second)

func _set_touch_aim(screen_pos: Vector2) -> void:
	if camera == null:
		return
	var origin := camera.project_ray_origin(screen_pos)
	var direction := camera.project_ray_normal(screen_pos)
	var hit: Variant = Plane(Vector3.UP, 0.0).intersects_ray(origin, direction)
	if hit != null:
		var point: Vector3 = hit
		_touch_aim = Vector2(point.x, point.z)
		_touch_last_aim = _touch_aim
		_touch_aim_valid = true
		_touch_aim_timer = 3.0

func _notification(what: int) -> void:
	if what != NOTIFICATION_WM_GO_BACK_REQUEST:
		return
	if hud == null:
		return
	var action := MatchMenu.back_action(session != null, hud.paused, hud.result_shown)
	if action == MatchMenu.BACK_LEAVE:
		_exit_game()
	elif action == MatchMenu.BACK_CLOSE:
		_close_pause()
	else:
		_open_pause()

func _toggle_pause() -> void:
	if hud == null or hud.result_shown:
		return
	if hud.paused:
		_close_pause()
	else:
		_open_pause()

func _open_pause() -> void:
	var online := session != null
	if _audio != null:
		# 暂停时音乐压低而不是停播：回来时不需要重新起拍，也不会和战斗节奏错位。
		_audio.set_paused(true)
	if MatchMenu.freezes_simulation(online):
		_paused = true
		_touch_points.clear()
		_pinch_distance = -1.0
	_touch_move = Vector2.ZERO
	_touch_attack = false
	_move_target_valid = false
	_local_input.move = Vector2.ZERO
	_local_input.attack = false
	hud.show_pause(true, online)

func _close_pause() -> void:
	if hud == null:
		return
	_paused = false
	if _audio != null:
		_audio.set_paused(false)
	hud.show_pause(false, session != null)

func _process(delta: float) -> void:
	if not build_complete:
		return
	if session != null and session.has_method("poll"):
		session.poll()
	if _audio != null:
		# 音频的距离衰减 / 残血心跳 / 强度层都读这份上下文。
		_refresh_audio_context()
		_audio.set_context(_audio_ctx)
	if _paused:
		return
	_hit_stop.tick(delta)
	if _hit_stop.is_frozen():
		# 击杀/破塔的短促顿帧只冻结表现层：模拟与网络照常推进，避免联机卡顿。
		_update_camera(delta, false)
		return
	if touch_mode:
		if _touch_aim_valid:
			if _touch_points.is_empty():
				_touch_aim_timer = maxf(0.0, _touch_aim_timer - delta)
				if _touch_aim_timer <= 0.0:
					_touch_aim_valid = false
			else:
				_touch_aim_timer = 3.0
	else:
		_update_mouse_ground()
	if authoritative and sim != null:
		_gather_input()
		if not sim.ended:
			sim.set_input(local_owner, _local_input)
		var ticked := false
		_accumulator += minf(delta, 0.1)
		var guard := 0
		while _accumulator >= TICK and guard < 5:
			sim.tick(TICK)
			_accumulator -= TICK
			guard += 1
			ticked = true
		if ticked:
			current_snapshot = sim.snapshot_for(local_team)
			_process_events(current_snapshot.events)
			# 输入只在真正被模拟消费后清空；否则高帧率下会吞掉刚按下的技能。
			_consume_skill_queue()
			if session != null and session.has_method("is_online") and session.is_online():
				# 广播用原始事件，按队伍过滤交给 snapshot_for；本地视角的过滤不能影响下发。
				_pending_events.append_array(sim.state.events)
		elif current_snapshot.is_empty():
			current_snapshot = sim.snapshot_for(local_team)
		_render_alpha = clampf(_accumulator / TICK, 0.0, 1.0)
		if session != null and session.has_method("is_online") and session.is_online():
			_snapshot_timer += delta
			if _snapshot_timer >= 0.1:
				_snapshot_timer = 0.0
				var outgoing_events: Array = _pending_events.duplicate()
				_pending_events.clear()
				# 视野过滤必须按队伍分别下发，否则客机能看到全图敌人。
				session.broadcast_team_snapshots(func(team: String) -> Dictionary:
					return sim.snapshot_for(team, outgoing_events)
				)
	elif session != null:
		_gather_input()
		_update_local_prediction(delta)
		_input_timer += delta
		if _input_timer >= 0.05 or _local_input.skill_q or _local_input.skill_w or _local_input.skill_e or _local_input.skill_r or _local_input.summoner or _local_input.recall or _local_input.teleport or _local_input.buy_item != "" or _local_input.sell_slot >= 0:
			_input_timer = 0.0
			session.submit_input(_local_input.duplicate())
			# 每个发出的输入都占一个序列号，服务端逐条确认，预测记录用同一个号。
			_input_seq = maxi(_input_seq, int(_local_input.seq) + 1)
			_consume_skill_queue(false)
		# 客机没有本地模拟，位置由 jitter buffer 回放驱动。
		_select_render_snapshot()
	else:
		_gather_input()
		_consume_skill_queue()

	if authoritative:
		_sync_units(current_snapshot, delta)
	else:
		# 客机：视觉用缓冲里回放出的那一格，HUD / 准星仍用最新快照。
		_sync_units(_render_snapshot, delta)
		_apply_predicted_visual()
	_sync_structures(current_snapshot, false)
	_update_bush_feedback()
	_update_channel_feedback(delta)
	var intent := _has_local_intent()
	if intent and not _last_intent and _camera_focus.is_active():
		# 玩家开始操作英雄就立刻收回镜头：否则人已经打起来了，画面还停在地图另一头。
		_camera_focus.release()
	_last_intent = intent
	_update_camera(delta, false)
	_update_aim_marker()
	_update_range_indicators()
	_update_move_marker(delta)
	_hud_timer += delta
	if _hud_timer >= 0.05 and hud != null:
		_hud_timer = 0.0
		_validate_lock_target()
		hud.update_snapshot(current_snapshot)
		hud.set_camera_view(camera_view_rect())

func _gather_input() -> void:
	if touch_mode:
		_gather_touch_input()
		return
	var keys := Vector2.ZERO
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		keys += Vector2(0, -1)
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		keys += Vector2(0, 1)
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		keys += Vector2(-1, 0)
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		keys += Vector2(1, 0)
	keys = InputAssist.camera_relative_move(keys, _camera_forward_2d())
	var move := Vector2.ZERO
	if keys.length() > 0.01:
		# 键盘一动就把点击目标作废，否则两套输入会互相拉扯（人往前、点在后）。
		_move_target_valid = false
		move = keys
	else:
		move = _click_move_vector()
	var q_down := Input.is_key_pressed(KEY_Q)
	var w_down := Input.is_key_pressed(KEY_1)
	var e_down := Input.is_key_pressed(KEY_E)
	var r_down := Input.is_key_pressed(KEY_R)
	var summoner_down := Input.is_key_pressed(KEY_F)
	if (q_down and not _prev_q) or _queued_q:
		_local_input.skill_q = true
		_flash_skill_range("q")
	if (w_down and not _prev_w) or _queued_w:
		_local_input.skill_w = true
		_flash_skill_range("w")
	if (e_down and not _prev_e) or _queued_e:
		_local_input.skill_e = true
		_flash_skill_range("e")
	if (r_down and not _prev_r) or _queued_r:
		_local_input.skill_r = true
		_flash_skill_range("r")
	if (summoner_down and not _prev_summoner) or _queued_summoner:
		_local_input.summoner = true
	_prev_q = q_down
	_prev_w = w_down
	_prev_e = e_down
	_prev_r = r_down
	_prev_summoner = summoner_down
	_local_input.move = move
	if _mouse_valid:
		_local_input.aim = _mouse_ground
	# 左键已经让给「走到那」，普攻改到右键 / 空格。
	_local_input.attack = Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT) or Input.is_key_pressed(KEY_SPACE)
	_local_input.recall = Input.is_key_pressed(KEY_B) or _queued_recall
	_local_input.teleport = Input.is_key_pressed(KEY_T) or _queued_teleport
	_local_input.attack_mode = _attack_mode
	_local_input.locked_target = _locked_target
	_apply_pending_purchase()

# 点击移动：算出本 tick 该走的向量。
# 返回值长度可能小于 1（模拟侧只在 >1 时才归一化），一步能走完时按剩余距离缩短。
# 注意：真正让英雄收住的是 MOVE_ARRIVE_EPS，不是这个分支 —— 输入读的是上一 tick
# 的快照（滞后约 speed*TICK ≈ 0.21m），所以 eps 刻意大于一帧步长，这样即使位置
# 滞后一帧也不会越过目标点。只有在速度足够高（step > eps）时这个分支才生效。
func _click_move_vector() -> Vector2:
	if not _move_target_valid:
		return Vector2.ZERO
	var local := _snapshot_local_hero()
	if local.is_empty() or not bool(local.get("alive", true)):
		_move_target_valid = false
		return Vector2.ZERO
	var from := InputAssist.entity_position(local)
	var to_target := _move_target - from
	var distance := to_target.length()
	if distance <= MOVE_ARRIVE_EPS:
		_move_target_valid = false
		return Vector2.ZERO
	var step := _effective_speed(local) * TICK
	if distance <= step:
		return to_target / step
	return to_target / distance

# 复刻模拟侧的移速修正（疾跑 / 减速），用来算「最后一步走多远」。
# 直接用基础速度会在加速时把最后一步估短，导致在目标点上来回跨。
func _effective_speed(local: Dictionary) -> float:
	var speed := maxf(float(local.get("speed", 6.0)), 0.1)
	if float(local.get("haste_timer", 0.0)) > 0.0:
		speed *= 1.4
	if float(local.get("slow_timer", 0.0)) > 0.0:
		speed *= 0.65
	return speed

func _set_move_target(point: Vector2) -> void:
	# 边界必须与 match_sim._clamp_position 用同一条（BOUNDS - radius）。
	# 之前用固定 0.2 的魔法数：目标能停在 57.80，而英雄最多走到 57.45（radius 0.55），
	# 差 0.35 > MOVE_ARRIVE_EPS(0.30) → 永远进不了到达判定，目标永不失效，
	# 人物贴着边界原地踏步、走路动画一直播。
	var limit := maxf(MapData.BOUNDS - _move_edge_radius(), 0.0)
	_move_target = Vector2(clampf(point.x, -limit, limit), clampf(point.y, -limit, limit))
	_move_target_valid = true
	_move_marker_pulse = 0.0
	if move_marker != null:
		move_marker.position = Vector3(_move_target.x, 0.09, _move_target.y)

# 算可走边界时用的半径。取快照里的真实值，但夹在 [0.65, 1.5]：
#  - 下限 0.65 是 hero_defs 里最大的英雄半径，兜住「客机快照 radius 缺失 / 被清洗成 0」
#    的情况（否则目标落到 57.8，客机一直发 move 输入，host 侧贴边原地踏步）；
#  - 上限 1.5 兜住被恶意放大的 radius，否则目标会被钳到地图中央。
# 比真实半径保守的那 0.1m 在 58m 的地图上肉眼无感，代价远小于「永远到不了」。
func _move_edge_radius() -> float:
	var local := _snapshot_local_hero()
	if local.is_empty():
		return 0.65
	return clampf(float(local.get("radius", 0.0)), 0.65, 1.5)

func _gather_touch_input() -> void:
	if _queued_q:
		_local_input.skill_q = true
		_flash_skill_range("q")
	if _queued_w:
		_local_input.skill_w = true
		_flash_skill_range("w")
	if _queued_e:
		_local_input.skill_e = true
		_flash_skill_range("e")
	if _queued_r:
		_local_input.skill_r = true
		_flash_skill_range("r")
	if _queued_summoner:
		_local_input.summoner = true
	if _queued_recall:
		_local_input.recall = true
	if _queued_teleport:
		_local_input.teleport = true
	_local_input.move = InputAssist.camera_relative_move(_touch_move, _camera_forward_2d())
	_local_input.aim = _resolve_touch_aim()
	_local_input.attack = _touch_attack
	_local_input.attack_mode = _attack_mode
	_local_input.locked_target = _locked_target
	_apply_pending_purchase()

func _apply_pending_purchase() -> void:
	if _pending_purchases.is_empty():
		_local_input.buy_item = ""
		_local_input.sell_slot = -1
		_local_input.seq = _input_seq
		return
	var front: Dictionary = _pending_purchases[0]
	_local_input.buy_item = str(front.get("buy_item", ""))
	_local_input.sell_slot = int(front.get("sell_slot", -1))
	_local_input.seq = _input_seq + 1

func _resolve_touch_aim() -> Vector2:
	var local := _snapshot_local_hero()
	var origin := _touch_last_aim
	if not local.is_empty():
		origin = InputAssist.entity_position(local)
	var result: Dictionary = InputAssist.aim_point(_touch_aim, _touch_aim_valid, current_snapshot.get("entities", []), local_team, origin, InputAssist.AUTO_AIM_RANGE, true)
	var source := str(result.get("source", "none"))
	_auto_aim_valid = source == "auto"
	if source == "auto":
		_auto_aim = result.get("aim", origin)
		return _auto_aim
	if source == "manual":
		_touch_last_aim = result.get("aim", origin)
	return _touch_last_aim

func _snapshot_local_hero() -> Dictionary:
	for entity in current_snapshot.get("entities", []):
		if str(entity.get("type", "")) == "hero" and str(entity.get("owner_id", "")) == local_owner:
			return entity
	return {}

# 音频导演每帧要的三件事：我是谁（判「自己的」事件）、我在哪（距离衰减）、我剩多少血（心跳）。
# 复用同一个字典原地更新：这是每帧都要跑的路径，不在这里分配新对象。
var _audio_ctx := {"local": -1, "x": 0.0, "y": 0.0, "team": "blue", "hp_ratio": 1.0}

func _refresh_audio_context() -> void:
	var hero := _snapshot_local_hero()
	if hero.is_empty():
		_audio_ctx["local"] = -1
		return
	var max_hp := maxf(float(hero.get("max_hp", 1.0)), 1.0)
	_audio_ctx["local"] = int(hero.get("id", -1))
	_audio_ctx["x"] = float(hero.get("x", 0.0))
	_audio_ctx["y"] = float(hero.get("y", 0.0))
	_audio_ctx["team"] = str(hero.get("team", local_team))
	_audio_ctx["hp_ratio"] = clampf(float(hero.get("hp", max_hp)) / max_hp, 0.0, 1.0)

# 技能是否放不出来。只判 CD 与蓝量 —— 距离/目标由模拟侧决定，
# 这里判错了也只是多一声「不行」，不会影响真实施法。
func _skill_blocked(slot: String) -> bool:
	if slot != "q" and slot != "w" and slot != "e" and slot != "r":
		return false
	var hero := _snapshot_local_hero()
	if hero.is_empty():
		return false
	if float(hero.get("skill_" + slot + "_cd", 0.0)) > 0.0:
		return true
	var data: Dictionary = HeroDefs.get_hero(str(hero.get("hero_type", local_hero_type)))
	var skill: Dictionary = data.get(slot, {})
	if skill.is_empty():
		return false
	return float(hero.get("mp", 0.0)) < float(skill.get("cost", 0.0))

func _consume_skill_queue(advance_seq: bool = true) -> void:
	_local_input.skill_q = false
	_local_input.skill_w = false
	_local_input.skill_e = false
	_local_input.skill_r = false
	_local_input.summoner = false
	_local_input.recall = false
	_local_input.teleport = false
	_queued_q = false
	_queued_w = false
	_queued_e = false
	_queued_r = false
	_queued_summoner = false
	_queued_recall = false
	_queued_teleport = false
	if _local_input.buy_item != "" or _local_input.sell_slot >= 0:
		if not _pending_purchases.is_empty():
			_pending_purchases.pop_front()
		if advance_seq:
			_input_seq = maxi(_input_seq, int(_local_input.seq) + 1)
	_local_input.buy_item = ""
	_local_input.sell_slot = -1
	_local_input.seq = _input_seq

# 客机本地预测：用本帧输入立即推进英雄位置，服务端确认后再校正。
# 记录按「下一次要发的输入序列号」归档，receive_snapshot 用 last_input_seq 对账。
func _update_local_prediction(delta: float) -> void:
	var hero := _snapshot_local_hero()
	if hero.is_empty():
		return
	var server_pos := Vector2(float(hero.get("x", 0.0)), float(hero.get("y", 0.0)))
	var hero_id := int(hero.get("id", -1))
	if not _prediction_ready or hero_id != _prediction_entity_id:
		_prediction_ready = true
		_prediction_entity_id = hero_id
		_prediction.reset(server_pos)
	# 死亡/回城/传送期间位置由服务端流程接管，客户端不要自作主张。
	if not bool(hero.get("alive", false)) or bool(hero.get("recalling", false)) or bool(hero.get("teleporting", false)):
		_prediction.reset(server_pos)
		return
	_prediction.predict_at(_local_input.move, float(hero.get("speed", 6.0)), delta, int(_local_input.seq))
	_prediction.update_decay(delta)

func _reconcile_local_prediction() -> void:
	var hero := _find_entity_by_owner(local_owner)
	if hero.is_empty():
		return
	var server_pos := Vector2(float(hero.get("x", 0.0)), float(hero.get("y", 0.0)))
	if not _prediction_ready:
		_prediction_ready = true
		_prediction_entity_id = int(hero.get("id", -1))
		_prediction.reset(server_pos)
		return
	if not bool(hero.get("alive", false)):
		_prediction.reset(server_pos)
		return
	_prediction.reconcile(int(hero.get("last_input_seq", -1)), server_pos)

func _apply_predicted_visual() -> void:
	if not _prediction_ready or _local_entity_id < 0:
		return
	var view: UnitVisual = _views.get(_local_entity_id)
	if view == null or view.dead:
		return
	var predicted := _prediction.get_render_pos()
	view.position = Vector3(predicted.x, 0.0, predicted.y)

func _update_mouse_ground() -> void:
	_project_ground(get_viewport().get_mouse_position())

# 把屏幕坐标投到地面平面（y = 0），成功则刷新 _mouse_ground / _mouse_valid。
# 触摸瞄准、鼠标悬停、左键点地都走这一条，避免三处各写一遍射线求交。
func _project_ground(screen_pos: Vector2) -> bool:
	if camera == null:
		return false
	var origin := camera.project_ray_origin(screen_pos)
	var direction := camera.project_ray_normal(screen_pos)
	var hit: Variant = Plane(Vector3.UP, 0.0).intersects_ray(origin, direction)
	if hit == null:
		return false
	var point: Vector3 = hit
	_mouse_ground = Vector2(point.x, point.z)
	_mouse_valid = true
	return true

func receive_snapshot(data: Dictionary) -> void:
	current_snapshot = data
	# 入队供 jitter buffer 回放。深拷贝是必要的：同一份 Dictionary 后续会被复用。
	_snapshot_buffer.append({
		"at": float(Time.get_ticks_msec()) / 1000.0,
		"st": float(data.get("time", 0.0)),
		"snapshot": data.duplicate(true),
	})
	while _snapshot_buffer.size() > NET_BUFFER_LIMIT:
		_snapshot_buffer.pop_front()
	if not authoritative:
		_reconcile_local_prediction()
	if not build_complete:
		return
	_process_events(data.get("events", []))
	_sync_structures(current_snapshot, false)
	if hud:
		hud.update_snapshot(current_snapshot)

# 在缓冲里挑出「渲染时刻」所在的两格，并算出插值进度。
func _select_render_snapshot() -> void:
	if _snapshot_buffer.is_empty():
		return
	# 服务端当前时刻用最新快照的时间戳近似（快照自带 "time"）。
	# 用服务端时钟而不是本地到达时钟，区间长度才恒等于服务端的推送间隔，
	# 网络抖动只改变缓冲深度，不改变插值速度。
	var latest: Dictionary = _snapshot_buffer[_snapshot_buffer.size() - 1]
	var render_st := float(latest.get("st", 0.0)) - NET_RENDER_DELAY
	var cur_index := -1
	for i in _snapshot_buffer.size():
		if float(_snapshot_buffer[i].get("st", 0.0)) >= render_st:
			cur_index = i
			break
	if cur_index < 0:
		# 缓冲里全是旧快照（刚开局/严重延迟）：用最新的，不插值。
		_render_snapshot = latest.get("snapshot", {})
		_render_prev_positions.clear()
		_render_alpha = 1.0
		return
	if cur_index == 0:
		# 只有一格可用，先用它自己（位置稳定，等下一格到了再开始插值）。
		var first: Dictionary = _snapshot_buffer[0]
		_render_snapshot = first.get("snapshot", {})
		_render_prev_positions.clear()
		_render_alpha = 1.0
		return
	var prev_entry: Dictionary = _snapshot_buffer[cur_index - 1]
	var cur_entry: Dictionary = _snapshot_buffer[cur_index]
	_render_snapshot = cur_entry.get("snapshot", {})
	_render_prev_positions.clear()
	for e in prev_entry.get("snapshot", {}).get("entities", []):
		_render_prev_positions[int(e.get("id", -1))] = Vector2(
			float(e.get("x", 0.0)), float(e.get("y", 0.0))
		)
	var prev_st := float(prev_entry.get("st", 0.0))
	var cur_st := float(cur_entry.get("st", 0.0))
	_render_alpha = clampf((render_st - prev_st) / maxf(cur_st - prev_st, 0.0001), 0.0, 1.0)

func apply_remote_input(peer_id: int, input: Dictionary) -> void:
	if sim != null:
		sim.set_input(str(peer_id), input)

func on_peer_left(peer_id: int) -> void:
	if sim != null:
		sim.set_player_controller(str(peer_id), "bot")
	if hud:
		hud.add_feed("玩家 %d 已离线，英雄交由 AI 接管" % peer_id, GameTheme.MUTED)

func _find_entity_by_owner(owner_id: String) -> Dictionary:
	for entity in current_snapshot.get("entities", []):
		if entity.get("type") == "hero" and str(entity.get("owner_id", "")) == owner_id:
			return entity
	return {}

func _local_world_position() -> Vector3:
	# 优先取渲染用的插值位置。相机若跟随未插值的快照坐标，会与角色的视觉位置
	# 产生相位差（快照 30Hz、渲染 60Hz+），叠加相机自身的平滑后就是持续抖动。
	if _local_entity_id >= 0:
		var view: UnitVisual = _views.get(_local_entity_id)
		if view != null:
			return view.position
	var local := _find_entity_by_owner(local_owner)
	if local.is_empty():
		var base := MapData.BLUE_BASE if local_team == "blue" else MapData.RED_BASE
		return Vector3(base.x, 0.0, base.y)
	return Vector3(float(local.x), 0.0, float(local.y))

func _camera_forward() -> Vector3:
	var dir := MapData.RED_BASE - MapData.BLUE_BASE
	if local_team == "red":
		dir = -dir
	return Vector3(dir.x, 0.0, dir.y).normalized()

func _camera_forward_2d() -> Vector2:
	var forward := _camera_forward()
	return Vector2(forward.x, forward.z)

func _camera_desired(target: Vector3) -> Vector3:
	return target + Vector3.UP * _zoom_current * 0.94 - _camera_forward() * _zoom_current * 0.76

func _update_camera(delta: float, instant: bool) -> void:
	if camera == null:
		return
	var hero := _local_world_position()
	# 注视点唯一真身：常态刚性跟英雄，小地图观察态才滑行（见 camera_focus.gd）。
	# 注意相机位置与 look_at 必须吃同一个 target，否则又是相位差 = 抖。
	var target := hero
	if instant:
		_camera_focus.reset()
	else:
		target = _camera_focus.update(delta, hero, CAMERA_FOCUS_GLIDE_SPEED, CAMERA_FOCUS_RETURN_SPEED)
	# 缩放单独平滑：位置跟随必须刚性（否则与 look_at 产生相位差而抖动），
	# 但 zoom 一步变 2.0 会让相机整体瞬移，观感上同样是「跳」。
	# 用恒定速率而非指数衰减——指数衰减「前快后慢」，首帧就会走掉一大截。
	if instant or not _cam_initialized:
		_zoom_current = zoom
		camera.fov = _camera_fov_target
	else:
		_zoom_current = move_toward(_zoom_current, zoom, delta * ZOOM_GLIDE_SPEED)
		camera.fov = move_toward(camera.fov, _camera_fov_target, delta * FOV_GLIDE_SPEED)
	var desired := _camera_desired(target)
	# 目标位置本身已是逐帧插值后的平滑轨迹，相机再叠一层 lerp 只会引入滞后；
	# 而 look_at 用的是即时 target，两者相位不一致正是移动时画面抖动的主因。
	# 改为刚性锁定：角色在屏幕上保持稳定，背景匀速滚动（MOBA 的标准手感）。
	camera.position = desired
	_cam_initialized = true
	if _camera_shake > 0.0:
		_camera_shake = maxf(0.0, _camera_shake - delta * 1.8)
		camera.position += Vector3(randf_range(-_camera_shake, _camera_shake), randf_range(-_camera_shake, _camera_shake) * 0.4, 0.0)
	var stop_shake := _hit_stop.get_shake_offset()
	if stop_shake.length_squared() > 0.0:
		camera.position += Vector3(stop_shake.x, stop_shake.y * 0.4, 0.0)
	camera.look_at(target + Vector3(0.0, 0.55, 0.0), Vector3.UP)

# --- 小地图定位 -----------------------------------------------------------
# 按住小地图 = 把镜头移到那个世界坐标；松手立刻回到英雄。
# 玩家一旦开始操作英雄（移动/技能/普攻）也会立刻收回。

func focus_world_point(world: Vector2) -> void:
	if not build_complete:
		return
	_camera_focus.request(world, _local_world_position())

func release_camera_focus() -> void:
	_camera_focus.release()

func is_camera_focusing_map() -> bool:
	return _camera_focus.is_active()

# 相机在地面上的可视范围。返回四角点（世界 XZ 顺序：左上、右上、右下、左下），
# 用多边形而不是 AABB —— 透视下地面可视区是梯形，AABB 的中心会往远处偏，
# 画在小地图上会明显偏离真实视线。
func camera_view_rect() -> Dictionary:
	if camera == null or not camera.is_inside_tree():
		return {"valid": false}
	var viewport := get_viewport()
	if viewport == null:
		return {"valid": false}
	var screen := viewport.get_visible_rect().size
	if screen.x <= 0.0 or screen.y <= 0.0:
		return {"valid": false}
	var ground := Plane(Vector3.UP, 0.0)
	var points := PackedVector2Array()
	for corner in [Vector2.ZERO, Vector2(screen.x, 0.0), screen, Vector2(0.0, screen.y)]:
		var origin := camera.project_ray_origin(corner)
		var direction := camera.project_ray_normal(corner)
		var hit: Variant = ground.intersects_ray(origin, direction)
		if hit == null:
			return {"valid": false}
		var point: Vector3 = hit
		points.append(Vector2(point.x, point.z))
	var center := Vector2.ZERO
	for point in points:
		center += point
	center /= float(points.size())
	var low := points[0]
	var high := points[0]
	for point in points:
		low = Vector2(minf(low.x, point.x), minf(low.y, point.y))
		high = Vector2(maxf(high.x, point.x), maxf(high.y, point.y))
	return {"valid": true, "points": points, "center": center, "half": (high - low) * 0.5}

# 玩家是否在操作英雄（用于观察态下自动收回镜头）。
func _has_local_intent() -> bool:
	if _local_input.move.length_squared() > 0.0004:
		return true
	return (
		_local_input.attack
		or _local_input.skill_q
		or _local_input.skill_w
		or _local_input.skill_e
		or _local_input.skill_r
		or _local_input.summoner
		or _local_input.recall
		or _local_input.teleport
	)

func _build_camera() -> void:
	camera = Camera3D.new()
	camera.name = "Camera"
	camera.fov = BASE_FOV
	camera.near = 0.2
	camera.far = 320.0
	camera.current = true
	add_child(camera)
	var base := MapData.BLUE_BASE if local_team == "blue" else MapData.RED_BASE
	var target := Vector3(base.x, 0.0, base.y)
	camera.position = _camera_desired(target)
	camera.look_at(target + Vector3(0.0, 0.55, 0.0), Vector3.UP)

func _build_bush_audio() -> void:
	_bush_audio = AudioStreamPlayer.new()
	_bush_audio.name = "BushAudio"
	_bush_audio.volume_db = -6.0
	add_child(_bush_audio)

# 音频导演进场：优先复用主壳传进来的那个（菜单音乐与战斗音乐共用一个播放器，
# 切曲时是淡入淡出而不是两个播放器叠着响）；没有就自建一个。
func _build_audio() -> void:
	if _shared_audio != null and is_instance_valid(_shared_audio):
		_audio = _shared_audio
	else:
		_audio = AudioDirector.new()
		_audio.name = "Audio"
		add_child(_audio)
	if _audio == null:
		return
	_audio.set_paused(false)
	_audio.play_music(AudioDirector.MUSIC_BATTLE)

func _build_channel_audio() -> void:
	_channel_audio = AudioStreamPlayer.new()
	_channel_audio.name = "ChannelAudio"
	# 引导音是铺底，压得比打击音低一档，避免盖住普攻与技能的落点反馈。
	_channel_audio.volume_db = -8.0
	add_child(_channel_audio)

# 回城 / 传送的引导表现。每帧读快照里的引导标记交给状态机判起手与结束；
# 瞬时爆发与音效走事件 —— 只有事件知道这次是完成还是被打断。
func _update_channel_feedback(delta: float) -> void:
	var snapshot: Dictionary = current_snapshot if authoritative else _render_snapshot
	if snapshot.is_empty():
		return
	var seen := {}
	for entity in snapshot.get("entities", []):
		if str(entity.get("type", "")) != "hero":
			continue
		var entity_id := int(entity.get("id", -1))
		seen[entity_id] = true
		var feedback: ChannelFeedback = _channel_feedback.get(entity_id)
		if feedback == null:
			feedback = ChannelFeedback.new()
			_channel_feedback[entity_id] = feedback
		var transition: String = feedback.update(entity)
		if transition != "none":
			_on_channel_transition(entity_id, transition, entity)
		var view: UnitVisual = _views.get(entity_id)
		var fx := _channel_fx.get(entity_id) as ChannelFx
		if feedback.kind() != "" and view != null and view.visible:
			# 懒创建：没引导过的英雄不该占一套法阵节点（10 个英雄 × 10 个 Mesh 就是白烧）。
			if fx == null or not is_instance_valid(fx):
				fx = _channel_fx_for(entity_id)
			fx.position = Vector3(view.position.x, 0.0, view.position.z)
			fx.set_channel(feedback.kind(), feedback.progress())
		elif fx != null and is_instance_valid(fx):
			fx.release()
	# 英雄离开视野或阵亡时把法阵收掉，否则会留在原地空转。
	for entity_id in _channel_feedback.keys():
		if seen.has(entity_id):
			continue
		var feedback: ChannelFeedback = _channel_feedback[entity_id]
		feedback.reset()
		var fx := _channel_fx.get(entity_id) as ChannelFx
		if fx != null:
			fx.release()

func _channel_fx_for(entity_id: int) -> ChannelFx:
	var fx: ChannelFx = _channel_fx.get(entity_id)
	if fx != null and is_instance_valid(fx):
		return fx
	fx = ChannelFx.new()
	fx.name = "ChannelFx%d" % entity_id
	_effects_root.add_child(fx)
	_channel_fx[entity_id] = fx
	return fx

func _on_channel_transition(entity_id: int, transition: String, entity: Dictionary) -> void:
	var is_local := entity_id == _local_entity_id
	var fx := _channel_fx_for(entity_id)
	if transition == "recall_start":
		fx.position = Vector3(float(entity.get("x", 0.0)), 0.0, float(entity.get("y", 0.0)))
		if is_local:
			_play_channel_cue(AudioCues.recall_channel())
	elif transition == "teleport_start":
		fx.position = Vector3(float(entity.get("x", 0.0)), 0.0, float(entity.get("y", 0.0)))
		if is_local:
			_play_channel_cue(AudioCues.teleport_channel())
	# *_stop 只收尾，不发声：完成与打断的瞬时反馈由事件负责，这里再响一次会重音。

func _play_channel_cue(stream: AudioStreamWAV) -> void:
	if stream == null or _channel_audio == null:
		return
	_channel_audio.stream = stream
	_channel_audio.play()

func _update_bush_feedback() -> void:
	var local := _find_entity_by_owner(local_owner)
	if local.is_empty() or not bool(local.get("alive", false)):
		_clear_bush_feedback()
		return
	_bush_feedback_step(Vector2(float(local.get("x", 0.0)), float(local.get("y", 0.0))))

func _bush_feedback_step(point: Vector2) -> String:
	var transition: String = _bush_feedback.update(point)
	if transition == "none":
		return "none"
	_bush_hidden = bool(_bush_feedback.in_bush)
	_camera_fov_target = _bush_feedback.target_fov(BASE_FOV)
	if hud != null:
		hud.set_bush_hidden(_bush_hidden)
	if _bush_audio != null:
		var cue := _bush_cue_for(transition)
		if cue != null:
			_bush_audio.stream = cue
			_bush_audio.play()
	return transition

func _bush_cue_for(transition: String) -> AudioStreamWAV:
	if transition == "enter":
		return AudioCues.enter_bush()
	if transition == "exit":
		return AudioCues.exit_bush()
	return null

# 死亡时清空隐匿态，避免 HUD 与焦段停在草丛里；重生点不在草里，不需要补 exit。
func _clear_bush_feedback() -> void:
	if not _bush_hidden and not _bush_feedback.in_bush:
		return
	_bush_feedback.reset()
	_bush_hidden = false
	_camera_fov_target = BASE_FOV
	if hud != null:
		hud.set_bush_hidden(false)

func _update_aim_marker() -> void:
	if aim_marker == null:
		return
	if touch_mode:
		var show_auto := not _touch_aim_valid and _auto_aim_valid and _touch_attack
		aim_marker.visible = _touch_aim_valid or show_auto
		if aim_marker.visible:
			var point := _touch_aim if _touch_aim_valid else _auto_aim
			aim_marker.position = Vector3(point.x, 0.08, point.y)
			aim_marker.rotation.y += 0.02
			if aim_material != null:
				var tint := Color(1.0, 0.82, 0.4) if _touch_aim_valid else Color(1.0, 0.34, 0.28)
				aim_material.albedo_color = Color(tint.r, tint.g, tint.b, 0.75)
				aim_material.emission = tint
		return
	aim_marker.visible = _mouse_valid
	if _mouse_valid:
		aim_marker.position = Vector3(_mouse_ground.x, 0.08, _mouse_ground.y)
		aim_marker.rotation.y += 0.02

func _build_aim_marker() -> void:
	aim_marker = Node3D.new()
	aim_marker.name = "AimMarker"
	add_child(aim_marker)
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.42
	torus.outer_radius = 0.49
	torus.rings = 32
	torus.ring_segments = 6
	ring.mesh = torus
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(1.0, 0.82, 0.4, 0.75)
	material.emission_enabled = true
	material.emission = Color(1.0, 0.75, 0.3)
	material.emission_energy_multiplier = 1.4
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	aim_material = material
	ring.material_override = material
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	aim_marker.add_child(ring)
	var dot := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.06
	sphere.height = 0.12
	dot.mesh = sphere
	dot.material_override = material
	dot.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	aim_marker.add_child(dot)

# ---------- 射程指示器 ----------
# 普攻范围常驻在本地英雄脚下；技能范围在按下 Q/E 时闪一下，
# 让玩家知道这一下能覆盖多远。半径写进 TorusMesh 而不是靠 scale 缩放，
# 否则线宽会跟着半径一起被放大，远射程英雄的环会粗成一圈光带。

func _build_range_indicators() -> void:
	var radius := maxf(0.5, HeroDefs.attack_range(local_hero_type))
	attack_range_ring = _make_ground_ring(radius, GOLD, 0.30, 0.10)
	attack_range_ring.visible = false
	add_child(attack_range_ring)
	lock_ring = _make_ground_ring(0.88, RED, 0.85, 0.09)
	lock_ring.visible = false
	add_child(lock_ring)

func _validate_lock_target() -> void:
	if _locked_target <= 0:
		return
	var local := _snapshot_local_hero()
	if local.is_empty() or not bool(local.get("alive", true)):
		_clear_locked_target()
		return
	var from := Vector2(float(local.get("x", 0.0)), float(local.get("y", 0.0)))
	for entity in current_snapshot.get("entities", []):
		if int(entity.get("id", -1)) != _locked_target:
			continue
		if not bool(entity.get("alive", false)):
			break
		var to := Vector2(float(entity.get("x", 0.0)), float(entity.get("y", 0.0)))
		if from.distance_to(to) > 14.0:
			break
		return
	_clear_locked_target()

func _clear_locked_target() -> void:
	_locked_target = -1
	_local_input.locked_target = -1
	if hud != null:
		hud.set_targeting_state(_attack_mode, -1)

func _update_lock_ring() -> void:
	if lock_ring == null:
		return
	var view: UnitVisual = _views.get(_locked_target) if _locked_target > 0 else null
	var show := view != null and not view.dead and view.visible
	lock_ring.visible = show
	if show:
		lock_ring.position = Vector3(view.position.x, RANGE_RING_Y + 0.005, view.position.z)

func _update_range_indicators() -> void:
	_update_lock_ring()
	if attack_range_ring == null:
		return
	var view: UnitVisual = _views.get(_local_entity_id)
	if view == null or view.dead or not view.visible:
		attack_range_ring.visible = false
		return
	attack_range_ring.visible = true
	attack_range_ring.position = Vector3(view.position.x, RANGE_RING_Y, view.position.z)

func _flash_skill_range(slot: String) -> void:
	var view: UnitVisual = _views.get(_local_entity_id)
	if view == null:
		return
	_make_skill_range_ring(local_hero_type, slot, view.position)

# 贴地圆环。返回的节点未挂载，由调用方决定 add_child 还是只做几何检查。
func _make_ground_ring(radius: float, color: Color, alpha: float, width: float) -> MeshInstance3D:
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = maxf(0.02, radius - width * 0.5)
	torus.outer_radius = radius + width * 0.5
	torus.rings = 64
	torus.ring_segments = 6
	ring.mesh = torus
	ring.position.y = RANGE_RING_Y
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(color.r, color.g, color.b, alpha)
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = 1.2
	ring.material_override = material
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return ring

# 技能范围环：施放瞬间在英雄脚下闪一下再淡出。
# 返回 null 表示该技能没有射程（护盾 / 加速这类自身增益）。
func _make_skill_range_ring(hero_type: String, slot: String, center: Vector3) -> MeshInstance3D:
	var radius := HeroDefs.skill_range(hero_type, slot)
	if radius <= 0.2:
		return null
	var ring := _make_ground_ring(radius, GOLD, 0.55, 0.12)
	ring.position = Vector3(center.x, RANGE_RING_Y + 0.01, center.z)
	if _effects_root == null:
		# 未进树（单元测试直接调）：只返回节点，让调用方检查几何。
		return ring
	_effects_root.add_child(ring)
	var material: StandardMaterial3D = ring.material_override
	var tween := create_tween()
	tween.tween_property(material, "albedo_color:a", 0.0, 0.55)
	tween.tween_callback(ring.queue_free)
	return ring

# 点击移动的落点指示：绿色呼吸环。
# 只做「我要走到这儿」的反馈，颜色刻意跟金色准星（攻击/瞄准）区分开。
func _build_move_marker() -> void:
	move_marker = Node3D.new()
	move_marker.name = "MoveMarker"
	move_marker.visible = false
	add_child(move_marker)
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.5
	torus.outer_radius = 0.6
	torus.rings = 36
	torus.ring_segments = 6
	ring.mesh = torus
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	# 不用 ADD：草地是亮色的，加色叠加会把绿色洗成白色，指示环就没了辨识度。
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.albedo_color = Color(0.24, 0.95, 0.42, 0.85)
	material.emission_enabled = true
	material.emission = Color(0.2, 0.95, 0.4)
	material.emission_energy_multiplier = 2.0
	move_material = material
	ring.material_override = material
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	move_marker.add_child(ring)
	# 中心小十字：远看是一个点，近看能认出环心在哪
	for i in 2:
		var tick := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.34, 0.02, 0.06) if i == 0 else Vector3(0.06, 0.02, 0.34)
		tick.mesh = box
		tick.material_override = material
		tick.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		move_marker.add_child(tick)

func _update_move_marker(delta: float) -> void:
	if move_marker == null:
		return
	var show := _move_target_valid and not touch_mode
	move_marker.visible = show
	if not show:
		return
	move_marker.position = Vector3(_move_target.x, 0.09, _move_target.y)
	_move_marker_pulse += delta
	var pulse := 1.0 + sin(_move_marker_pulse * TAU * MOVE_MARKER_PULSE_HZ) * MOVE_MARKER_PULSE
	move_marker.scale = Vector3(pulse, 1.0, pulse)

func _build_environment() -> void:
	var world := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color(0.09, 0.17, 0.3)
	sky_material.sky_horizon_color = Color(0.62, 0.68, 0.7)
	sky_material.sky_curve = 0.18
	sky_material.ground_bottom_color = Color(0.08, 0.1, 0.09)
	sky_material.ground_horizon_color = Color(0.5, 0.52, 0.48)
	sky_material.sun_angle_max = 22.0
	sky_material.sun_curve = 0.12
	sky.sky_material = sky_material
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	environment.ambient_light_energy = 0.68
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.tonemap_exposure = 1.05
	environment.fog_enabled = true
	# 雾调浓一点：外围丘陵和山需要「被空气隔开」的层次，
	# 太清透会让远山像贴在地图边上的一排道具。
	environment.fog_light_color = Color(0.46, 0.56, 0.66)
	environment.fog_light_energy = 0.72
	environment.fog_density = 0.0052
	environment.fog_sky_affect = 0.22
	environment.fog_aerial_perspective = 0.45
	environment.adjustment_enabled = true
	environment.adjustment_contrast = 1.06
	environment.adjustment_saturation = 1.1
	environment.adjustment_brightness = 1.0
	world.environment = environment
	add_child(world)

	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-48.0, -38.0, 0.0)
	sun.light_color = Color(1.0, 0.9, 0.76)
	sun.light_energy = 1.5
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.directional_shadow_max_distance = 48.0
	sun.shadow_bias = 0.035
	sun.shadow_normal_bias = 1.2
	add_child(sun)

func _build_ground() -> void:
	# 地形由 TerrainBuilder 生成：可玩区（±58）严格平坦，往外抬成丘陵，
	# 河道真正下陷成河床。高度纯粹是视觉的，不参与碰撞/寻路。
	var terrain := TerrainBuilder.new()
	_terrain = terrain
	var ground := MeshInstance3D.new()
	ground.name = "Terrain"
	ground.mesh = terrain.build_mesh()
	ground.material_override = TerrainBuilder.build_material()
	ground.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_props_root.add_child(ground)

func _build_lanes() -> void:
	var outer_material := StandardMaterial3D.new()
	outer_material.albedo_texture = load("res://assets/textures/grass_path_2_Diffuse.jpg")
	outer_material.albedo_color = Color(0.62, 0.56, 0.45)
	outer_material.roughness = 1.0
	outer_material.uv1_scale = Vector3(1, 1, 1)
	var inner_material := StandardMaterial3D.new()
	inner_material.albedo_texture = load("res://assets/textures/grass_path_2_Diffuse.jpg")
	inner_material.albedo_color = Color(0.92, 0.88, 0.78)
	inner_material.roughness = 0.97
	inner_material.uv1_scale = Vector3(1, 1, 1)
	var edge_material := StandardMaterial3D.new()
	edge_material.albedo_color = Color(0.16, 0.14, 0.11)
	edge_material.roughness = 1.0
	for lane in MapData.LANE_ORDER:
		var path: Array = MapView.lane_path(lane)
		_props_root.add_child(_lane_ribbon(path, 7.5, 0.008, edge_material))
		_props_root.add_child(_lane_ribbon(path, 7.0, 0.012, outer_material))
		_props_root.add_child(_lane_ribbon(path, 5.2, 0.022, inner_material))
		await _next_frame()

	var plaza_material := StandardMaterial3D.new()
	plaza_material.albedo_texture = load("res://assets/textures/cliff_side_Diffuse.jpg")
	plaza_material.albedo_color = Color(0.7, 0.68, 0.62)
	plaza_material.roughness = 1.0
	plaza_material.uv1_scale = Vector3(6, 6, 1)
	for base in [MapData.BLUE_BASE, MapData.RED_BASE]:
		var plaza := MeshInstance3D.new()
		var cylinder := CylinderMesh.new()
		cylinder.top_radius = 8.4
		cylinder.bottom_radius = 8.6
		cylinder.height = 0.08
		cylinder.radial_segments = 48
		cylinder.rings = 1
		plaza.mesh = cylinder
		plaza.material_override = plaza_material
		plaza.position = Vector3(base.x, 0.04, base.y)
		plaza.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_props_root.add_child(plaza)

func _lane_ribbon(path: Array, width: float, height: float, material: Material) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var total := 0.0
	for index in range(path.size() - 1):
		var a: Vector2 = path[index]
		var b: Vector2 = path[index + 1]
		var segment := b - a
		var length := segment.length()
		if length < 0.01:
			continue
		var dir := segment / length
		var side := Vector2(-dir.y, dir.x) * width * 0.5
		var a_left := Vector3(a.x - side.x, height, a.y - side.y)
		var a_right := Vector3(a.x + side.x, height, a.y + side.y)
		var b_left := Vector3(b.x - side.x, height, b.y - side.y)
		var b_right := Vector3(b.x + side.x, height, b.y + side.y)
		var v0 := total * 0.14
		var v1 := (total + length) * 0.14
		_add_vertex(st, a_left, Vector2(0, v0))
		_add_vertex(st, a_right, Vector2(1, v0))
		_add_vertex(st, b_left, Vector2(0, v1))
		_add_vertex(st, a_right, Vector2(1, v0))
		_add_vertex(st, b_right, Vector2(1, v1))
		_add_vertex(st, b_left, Vector2(0, v1))
		total += length
	var mesh := st.commit()
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return instance

func _add_vertex(st: SurfaceTool, vertex: Vector3, uv: Vector2) -> void:
	st.set_normal(Vector3.UP)
	st.set_uv(uv)
	st.add_vertex(vertex)

func _build_river() -> void:
	# 河床由地形承担（TerrainBuilder 把河道下陷到 -1.45），这里只放水面。
	# 以前在河道两侧贴了一条 22m 宽的 cliff 贴图当「岸」，
	# 结果是一块棕色地毯压在草地上、把地形坡完全盖住 —— 直接去掉。
	var river := MeshInstance3D.new()
	river.name = "River"
	var plane := PlaneMesh.new()
	# 长度远超地图，两端沉进雾里，看不到水面尽头
	plane.size = Vector2(320.0, 17.4)
	river.mesh = plane
	river.rotation.y = PI * 0.25
	river.position.y = -0.42
	var shader := Shader.new()
	shader.code = """
shader_type spatial;
render_mode blend_mix, cull_disabled, depth_draw_opaque, specular_schlick_ggx;

uniform vec4 deep_color : source_color = vec4(0.06, 0.22, 0.26, 1.0);
uniform vec4 shallow_color : source_color = vec4(0.20, 0.44, 0.42, 1.0);
uniform float river_half = 9.0;

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	// 到河道中心线的距离决定深浅：河心深蓝、岸边浅青
	float d = abs(wpos.x + wpos.z) * 0.70710678;
	float t = clamp(d / river_half, 0.0, 1.0);

	// 两层不同频率、不同方向的水波，避免规则条纹
	float w1 = sin(wpos.x * 1.15 + TIME * 0.85) * cos(wpos.z * 0.95 - TIME * 0.62);
	float w2 = sin((wpos.x + wpos.z) * 2.1 - TIME * 1.35);
	float w3 = sin(wpos.x * 3.6 - wpos.z * 2.9 + TIME * 1.8);
	float ripple = w1 * 0.55 + w2 * 0.33 + w3 * 0.12;

	vec3 col = mix(deep_color.rgb, shallow_color.rgb, t * 0.72 + ripple * 0.04);

	// 岸边浅滩泡沫：只在水陆交界一条窄带
	float foam = smoothstep(0.93, 1.0, t + ripple * 0.03);
	col = mix(col, vec3(0.74, 0.82, 0.80), foam * 0.4);

	ALBEDO = col;
	ALPHA = mix(0.93, 0.80, t);
	ROUGHNESS = 0.13;
	SPECULAR = 0.42;
	METALLIC = 0.0;
	// 用波纹扰动法线做假高光，GL Compatibility 下没有 SSR，这是最划算的一招
	NORMAL = normalize(vec3(ripple * 0.06, 1.0, ripple * 0.045));
}
"""
	var material := ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("river_half", MapData.RIVER_HALF_WIDTH)
	# 必须从 GDScript 传 Color：直接写 shader 里的 uniform 默认值会被当成线性色，
	# 输出时再转 sRGB 就整体提亮 —— 深蓝河水会渲染成亮青绿。
	material.set_shader_parameter("deep_color", Color(0.018, 0.095, 0.135))
	material.set_shader_parameter("shallow_color", Color(0.075, 0.21, 0.20))
	river.material_override = material
	river.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_props_root.add_child(river)

	_build_bridge()

func _build_bridge() -> void:
	# 桥体向下延伸进河床，顶面在 0.02（单位走在 y=0 上，不会陷进去）。
	var bridge := MeshInstance3D.new()
	bridge.name = "Bridge"
	var box := BoxMesh.new()
	box.size = Vector3(9.0, 1.7, 26.0)
	bridge.mesh = box
	bridge.rotation.y = PI * 0.25
	bridge.position = Vector3(0.0, -0.83, 0.0)
	# cliff_side_Diffuse 平均色是 (123,82,49) 的棕色岩 —— 直接用它当桥面，
	# 桥看起来就是一块木板。改用同套的 AO 图（灰度）做 albedo，再上灰石色。
	var deck := StandardMaterial3D.new()
	deck.albedo_texture = load("res://assets/textures/cliff_side_AO.jpg")
	deck.albedo_color = Color(0.58, 0.60, 0.62)
	deck.normal_enabled = true
	deck.normal_texture = load("res://assets/textures/cliff_side_nor_gl.jpg")
	deck.normal_scale = 1.4
	deck.roughness = 0.95
	deck.uv1_scale = Vector3(5, 2, 12)
	bridge.material_override = deck
	ModelUtils.enable_shadows(bridge, true)
	_props_root.add_child(bridge)

	# 沿河道方向 / 垂直河道方向的单位向量（桥旋转了 45°）
	var along := Vector3(0.70710678, 0.0, 0.70710678)
	var across := Vector3(0.70710678, 0.0, -0.70710678)

	var stone := StandardMaterial3D.new()
	stone.albedo_texture = load("res://assets/textures/cliff_side_AO.jpg")
	stone.albedo_color = Color(0.54, 0.56, 0.58)
	stone.normal_enabled = true
	stone.normal_texture = load("res://assets/textures/cliff_side_nor_gl.jpg")
	stone.normal_scale = 1.2
	stone.roughness = 1.0
	stone.uv1_scale = Vector3(2, 2, 2)

	# 桥墩：从河床顶到桥底
	for i in 2:
		for side in 2:
			var pier := MeshInstance3D.new()
			var cylinder := CylinderMesh.new()
			cylinder.top_radius = 0.52
			cylinder.bottom_radius = 0.66
			cylinder.height = 1.9
			cylinder.radial_segments = 12
			pier.mesh = cylinder
			pier.material_override = stone
			var t := -1.0 if i == 0 else 1.0
			var s := -1.0 if side == 0 else 1.0
			pier.position = along * (t * 6.0) + across * (s * 3.8) + Vector3(0.0, -0.55, 0.0)
			ModelUtils.enable_shadows(pier, true)
			_props_root.add_child(pier)

	# 低矮石栏：高 0.42，只做两侧边缘，不挡镜头看桥面
	for side in 2:
		var rail := MeshInstance3D.new()
		var rail_box := BoxMesh.new()
		rail_box.size = Vector3(0.34, 0.42, 26.0)
		rail.mesh = rail_box
		rail.rotation.y = PI * 0.25
		var s := -1.0 if side == 0 else 1.0
		rail.position = across * (s * 4.25) + Vector3(0.0, 0.23, 0.0)
		rail.material_override = stone
		ModelUtils.enable_shadows(rail, true)
		_props_root.add_child(rail)

# 地图机制的可视化：墙体、草丛、野区营地与首领坑都从 MapLayout 取坐标，
# 与碰撞/视野/野怪刷新点严格同源，避免「看得见走不过去」或「打到空气墙」。
func _build_map_features() -> void:
	var marks := MapView.map_marks()
	var rng := RandomNumberGenerator.new()
	rng.seed = 90210
	var rock_scene: PackedScene = load(ENV_DIR + "Rock.glb")
	var stone := StandardMaterial3D.new()
	stone.albedo_texture = load("res://assets/textures/cliff_side_Diffuse.jpg")
	stone.albedo_color = Color(0.52, 0.5, 0.46)
	stone.roughness = 1.0
	stone.uv1_scale = Vector3(2, 2, 1)

	for wall in marks.walls:
		var a: Vector2 = wall.a
		var b: Vector2 = wall.b
		var center := (a + b) * 0.5
		var length := a.distance_to(b)
		var dir := (b - a) / maxf(length, 0.001)
		var barrier := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(length, 1.7, 1.3)
		barrier.mesh = box
		barrier.material_override = stone
		barrier.position = Vector3(center.x, 0.85, center.y)
		barrier.rotation.y = -atan2(dir.y, dir.x)
		ModelUtils.enable_shadows(barrier, true)
		_props_root.add_child(barrier)
		for i in 3:
			var p := a.lerp(b, (float(i) + 0.5) / 3.0)
			var rock := ModelUtils.fit_scene(rock_scene, rng.randf_range(1.5, 2.2), rng.randf_range(1.8, 2.8))
			rock.position = Vector3(p.x + rng.randf_range(-0.8, 0.8), 0.0, p.y + rng.randf_range(-0.8, 0.8))
			rock.rotation.y = rng.randf_range(0.0, TAU)
			ModelUtils.enable_shadows(rock, false)
			_props_root.add_child(rock)

	var bush_mat := StandardMaterial3D.new()
	bush_mat.albedo_color = Color(0.12, 0.31, 0.14)
	bush_mat.roughness = 1.0
	for bush in marks.bushes:
		var disc_mat := StandardMaterial3D.new()
		disc_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		disc_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		disc_mat.albedo_color = Color(0.09, 0.24, 0.11, 0.42)
		var disc := MeshInstance3D.new()
		var plane := PlaneMesh.new()
		plane.size = Vector2(float(bush.radius) * 2.0, float(bush.radius) * 2.0)
		disc.mesh = plane
		disc.material_override = disc_mat
		disc.position = Vector3(bush.pos.x, 0.035, bush.pos.y)
		disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_props_root.add_child(disc)
		for i in 7:
			var angle := TAU * float(i) / 7.0
			var offset := Vector2(cos(angle), sin(angle)) * float(bush.radius) * rng.randf_range(0.25, 0.62)
			var clump := MeshInstance3D.new()
			var sphere := SphereMesh.new()
			sphere.radius = rng.randf_range(0.55, 0.95)
			sphere.height = sphere.radius * 2.0
			clump.mesh = sphere
			clump.material_override = bush_mat
			clump.scale = Vector3(1.0, 0.72, 1.0)
			clump.position = Vector3(bush.pos.x + offset.x, 0.42, bush.pos.y + offset.y)
			clump.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			_props_root.add_child(clump)

	for camp in marks.camps:
		var buff := str(camp.get("buff", ""))
		var color := Color(0.95, 0.62, 0.22) if buff == "red" else Color(0.34, 0.58, 0.98)
		_add_map_disc(camp.pos, 3.4, Color(color.r, color.g, color.b, 0.2), color)
		_add_map_totem(camp.pos + Vector2(0.0, -2.0), 2.2, color)

	for pit in marks.objectives:
		_add_map_disc(pit.pos, 5.6, Color(0.35, 0.2, 0.5, 0.26), Color(0.72, 0.5, 0.92))
		for i in 4:
			var angle := TAU * float(i) / 4.0 + PI * 0.25
			var pillar_pos: Vector2 = pit.pos + Vector2(cos(angle), sin(angle)) * 5.0
			_add_map_totem(pillar_pos, 3.0, Color(0.62, 0.5, 0.82))

	for pad in marks.teleports:
		var pad_color := Color(0.4, 0.82, 0.92)
		_add_map_disc(pad.pos, 3.0, Color(pad_color.r, pad_color.g, pad_color.b, 0.2), pad_color)
		_add_map_totem(pad.pos + Vector2(0.0, -2.8), 2.6, pad_color)

func _add_map_disc(pos: Vector2, radius: float, fill: Color, edge: Color) -> void:
	var disc_material := StandardMaterial3D.new()
	disc_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	disc_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	disc_material.albedo_color = fill
	var disc := MeshInstance3D.new()
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = radius
	cylinder.bottom_radius = radius
	cylinder.height = 0.03
	cylinder.radial_segments = 40
	disc.mesh = cylinder
	disc.material_override = disc_material
	disc.position = Vector3(pos.x, 0.04, pos.y)
	disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_props_root.add_child(disc)
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = radius - 0.14
	torus.outer_radius = radius
	torus.rings = 40
	ring.mesh = torus
	var ring_material := StandardMaterial3D.new()
	ring_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring_material.albedo_color = edge
	ring_material.emission_enabled = true
	ring_material.emission = edge
	ring_material.emission_energy_multiplier = 0.9
	ring.material_override = ring_material
	ring.position = Vector3(pos.x, 0.07, pos.y)
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_props_root.add_child(ring)

func _add_map_totem(pos: Vector2, height: float, color: Color) -> void:
	var pole := MeshInstance3D.new()
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = 0.16
	cylinder.bottom_radius = 0.26
	cylinder.height = height
	cylinder.radial_segments = 8
	pole.mesh = cylinder
	var stone := StandardMaterial3D.new()
	stone.albedo_color = Color(0.32, 0.3, 0.28)
	stone.roughness = 1.0
	pole.material_override = stone
	pole.position = Vector3(pos.x, height * 0.5, pos.y)
	ModelUtils.enable_shadows(pole, true)
	_props_root.add_child(pole)
	var gem := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.26
	sphere.height = 0.52
	gem.mesh = sphere
	var glow := StandardMaterial3D.new()
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow.albedo_color = color
	glow.emission_enabled = true
	glow.emission = color
	glow.emission_energy_multiplier = 1.8
	gem.material_override = glow
	gem.position = Vector3(pos.x, height + 0.15, pos.y)
	gem.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_props_root.add_child(gem)

# 布景取地形高度。地形是可玩区外才抬升的，所以可玩区里恒为 0，
# 布景摆放不会因为地形改动而漂移。
func _terrain_height(x: float, z: float) -> float:
	if _terrain == null:
		return 0.0
	return float(_terrain.height_at(x, z))

# --- 草簇散布 ---
# 只长在草地上：路面、河道、基地广场和草丛（玩法区域）都要排除，
# 否则会出现「草长在路中间」「草盖住草丛」这种一眼假的情况。
var _grass_bushes: Array = []
# 用噪声控制草甸密度：均匀撒满会像一层绿色毛刺，
# 有疏有密才像自然长出来的草地。
var _grass_noise := FastNoiseLite.new()

func _can_grow_grass(point: Vector2) -> bool:
	if _grass_noise.get_noise_2d(point.x, point.y) < -0.18:
		return false
	if _lane_distance(point) < 4.2:
		return false
	if _river_distance(point) < 12.5:
		return false
	if _base_distance(point) < 11.5:
		return false
	for bush in _grass_bushes:
		if point.distance_to(bush.pos) < float(bush.radius) + 0.7:
			return false
	return true

func _build_grass_tufts() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 5150
	_grass_noise.seed = 991
	_grass_noise.frequency = 0.045
	_grass_noise.fractal_octaves = 2
	_grass_bushes = MapView.map_marks().bushes
	var tufts := GrassField.scatter(12000, _can_grow_grass, _terrain_height, rng)
	_props_root.add_child(tufts)

func _build_scenery() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261022
	var pine: PackedScene = load(ENV_DIR + "Resource_PineTree_Group.glb")
	var broadleaf: PackedScene = load(ENV_DIR + "Resource_Tree_Group.glb")
	var single_tree: PackedScene = load(ENV_DIR + "Resource_Tree1.glb")
	var rock_group: PackedScene = load(ENV_DIR + "Rock_Group.glb")
	var rock_single: PackedScene = load(ENV_DIR + "Rock.glb")
	var mountains: Array[PackedScene] = [
		load(ENV_DIR + "Mountain_Group_1.glb"),
		load(ENV_DIR + "Mountain_Group_2.glb"),
	]

	for i in 52:
		var angle := rng.randf_range(0.0, TAU)
		var radius := rng.randf_range(25.0, 68.0)
		var pos := Vector2(cos(angle), sin(angle)) * radius
		if _lane_distance(pos) < 9.0 or _base_distance(pos) < 24.0 or _river_distance(pos) < 10.0:
			continue
		if not _feature_clear(pos, 2.0):
			continue
		var scene: PackedScene = pine if i % 3 != 1 else broadleaf
		var height := rng.randf_range(7.0, 12.5)
		var tree := ModelUtils.fit_scene(scene, height, height * 1.1)
		tree.position = Vector3(pos.x, _terrain_height(pos.x, pos.y) - 0.15, pos.y)
		tree.rotation.y = rng.randf_range(0.0, TAU)
		ModelUtils.tint(tree, Color(0.16, 0.28, 0.14), 0.45)
		ModelUtils.enable_shadows(tree, false)
		_props_root.add_child(tree)
		if i % 8 == 7:
			await _next_frame()

	for i in 18:
		var angle := rng.randf_range(0.0, TAU)
		var radius := rng.randf_range(24.0, 58.0)
		var pos := Vector2(cos(angle), sin(angle)) * radius
		if _lane_distance(pos) < 8.0 or _base_distance(pos) < 22.0 or _river_distance(pos) < 8.0:
			continue
		if not _feature_clear(pos, 2.0):
			continue
		var height := rng.randf_range(5.0, 8.0)
		var tree := ModelUtils.fit_scene(single_tree, height, height * 0.8)
		tree.position = Vector3(pos.x, _terrain_height(pos.x, pos.y) - 0.15, pos.y)
		tree.rotation.y = rng.randf_range(0.0, TAU)
		ModelUtils.tint(tree, Color(0.18, 0.30, 0.15), 0.45)
		ModelUtils.enable_shadows(tree, false)
		_props_root.add_child(tree)
		if i % 6 == 5:
			await _next_frame()

	for i in 16:
		var angle := rng.randf_range(0.0, TAU)
		var radius := rng.randf_range(18.0, 62.0)
		var pos := Vector2(cos(angle), sin(angle)) * radius
		if _lane_distance(pos) < 7.0 or _base_distance(pos) < 18.0:
			continue
		if not _feature_clear(pos, 1.5):
			continue
		if _river_distance(pos) > 16.0 and i % 2 == 0:
			continue
		var height := rng.randf_range(1.2, 2.8)
		var rock := ModelUtils.fit_scene(rock_group if i % 3 == 0 else rock_single, height, height * 2.2)
		rock.position = Vector3(pos.x, _terrain_height(pos.x, pos.y) - 0.25, pos.y)
		rock.rotation.y = rng.randf_range(0.0, TAU)
		ModelUtils.enable_shadows(rock, false)
		_props_root.add_child(rock)
		if i % 6 == 5:
			await _next_frame()

	for i in 12:
		var angle := TAU * float(i) / 12.0 + 0.16
		var radius := rng.randf_range(86.0, 104.0)
		var pos := Vector2(cos(angle), sin(angle)) * radius
		if _base_distance(pos) < 44.0:
			continue
		var mountain := ModelUtils.fit_scene(mountains[i % 2], rng.randf_range(22.0, 34.0), rng.randf_range(40.0, 58.0))
		# 山脚埋进地形 2m：模型底边是平的，不埋就会在坡上悬空
		mountain.position = Vector3(pos.x, _terrain_height(pos.x, pos.y) - 2.0, pos.y)
		mountain.rotation.y = rng.randf_range(0.0, TAU)
		# 原始山体是纯白的低模，和草地拼在一起像贴纸。往岩石青灰拉，
		# 再用远景雾把它压向天空色，才有「远处的山」的层次。
		ModelUtils.tint(mountain, Color(0.20, 0.25, 0.31), 0.80)
		ModelUtils.enable_shadows(mountain, false)
		_props_root.add_child(mountain)
		if i % 4 == 3:
			await _next_frame()

	_build_base_decor(MapData.BLUE_BASE, "blue", rng)
	await _next_frame()
	_build_base_decor(MapData.RED_BASE, "red", rng)
	await _next_frame()

func _build_base_decor(base: Vector2, team: String, rng: RandomNumberGenerator) -> void:
	var toward := (Vector2.ZERO - base).normalized()
	var side := Vector2(-toward.y, toward.x)
	var team_color := BLUE if team == "blue" else RED
	var facing := atan2(toward.x, toward.y)
	var temple := ModelUtils.fit_scene(load(ENV_DIR + ("Temple_FirstAge_Level3.glb" if team == "blue" else "TownCenter_SecondAge_Level3.glb")), 8.5, 12.5)
	temple.position = Vector3(base.x + side.x * 14.0 - toward.x * 2.0, 0.0, base.y + side.y * 14.0 - toward.y * 2.0)
	temple.rotation.y = facing + PI * 0.5
	ModelUtils.tint(temple, team_color, 0.08)
	ModelUtils.enable_shadows(temple, true)
	_props_root.add_child(temple)
	var market := ModelUtils.fit_scene(load(ENV_DIR + "Market_FirstAge_Level3.glb"), 5.4, 9.0)
	market.position = Vector3(base.x + side.x * 9.5 + toward.x * 8.0, 0.0, base.y + side.y * 9.5 + toward.y * 8.0)
	market.rotation.y = facing + PI * 0.5
	ModelUtils.tint(market, team_color, 0.08)
	ModelUtils.enable_shadows(market, true)
	_props_root.add_child(market)
	var barracks := ModelUtils.fit_scene(load(ENV_DIR + "Barracks_FirstAge_Level3.glb"), 5.0, 8.0)
	barracks.position = Vector3(base.x - side.x * 9.5 + toward.x * 8.0, 0.0, base.y - side.y * 9.5 + toward.y * 8.0)
	barracks.rotation.y = facing + PI * 0.5
	ModelUtils.tint(barracks, team_color, 0.08)
	ModelUtils.enable_shadows(barracks, true)
	_props_root.add_child(barracks)
	var wall := ModelUtils.fit_scene(load(ENV_DIR + "Wall_FirstAge.glb"), 2.8, 8.0)
	wall.position = Vector3(base.x + toward.x * 11.0 + side.x * 8.0, 0.0, base.y + toward.y * 11.0 + side.y * 8.0)
	wall.rotation.y = facing
	ModelUtils.enable_shadows(wall, true)
	_props_root.add_child(wall)
	var wall_b := ModelUtils.fit_scene(load(ENV_DIR + "Wall_FirstAge.glb"), 2.8, 8.0)
	wall_b.position = Vector3(base.x + toward.x * 11.0 - side.x * 8.0, 0.0, base.y + toward.y * 11.0 - side.y * 8.0)
	wall_b.rotation.y = facing
	ModelUtils.enable_shadows(wall_b, true)
	_props_root.add_child(wall_b)
	for i in 4:
		var prop_scene: PackedScene = load(ENV_DIR + ("Crate.glb" if i % 2 == 0 else "Barrel.glb"))
		var prop := ModelUtils.fit_scene(prop_scene, rng.randf_range(0.8, 1.2))
		var offset := side * rng.randf_range(3.5, 6.0) + toward * rng.randf_range(4.0, 7.0)
		prop.position = Vector3(base.x + offset.x, 0.0, base.y + offset.y)
		prop.rotation.y = rng.randf_range(0.0, TAU)
		ModelUtils.enable_shadows(prop, false)
		_props_root.add_child(prop)

func _lane_distance(point: Vector2) -> float:
	var best := INF
	for lane in MapData.LANE_ORDER:
		var path: Array = MapData.lane_path(lane)
		for i in range(path.size() - 1):
			var a: Vector2 = path[i]
			var b: Vector2 = path[i + 1]
			var ab := b - a
			var length_sq := ab.length_squared()
			if length_sq < 0.0001:
				continue
			var t := clampf((point - a).dot(ab) / length_sq, 0.0, 1.0)
			best = minf(best, point.distance_to(a + ab * t))
	return best

func _base_distance(point: Vector2) -> float:
	return minf(point.distance_to(MapData.BLUE_BASE), point.distance_to(MapData.RED_BASE))

func _river_distance(point: Vector2) -> float:
	return absf(point.x + point.y) * 0.70710678

# 墙体/草丛/营地/首领坑周围留白，避免随机植被长进可交互区域。
func _feature_clear(point: Vector2, margin: float) -> bool:
	var marks := MapView.map_marks()
	for wall in marks.walls:
		if _segment_distance(point, wall.a, wall.b) < 1.5 + margin:
			return false
	for bush in marks.bushes:
		if point.distance_to(bush.pos) < float(bush.radius) + margin:
			return false
	for camp in marks.camps:
		if point.distance_to(camp.pos) < 3.4 + margin:
			return false
	for pit in marks.objectives:
		if point.distance_to(pit.pos) < 5.6 + margin:
			return false
	return true

func _segment_distance(point: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var length_sq := ab.length_squared()
	if length_sq < 0.0001:
		return point.distance_to(a)
	var t := clampf((point - a).dot(ab) / length_sq, 0.0, 1.0)
	return point.distance_to(a + ab * t)

func _sync_units(snapshot: Dictionary, delta: float) -> void:
	if snapshot.is_empty():
		return
	_local_entity_id = -1
	var seen_ids := {}
	for entity in snapshot.get("entities", []):
		var entity_type := str(entity.get("type", ""))
		if entity_type != "hero" and entity_type != "minion" and entity_type != "monster":
			continue
		var entity_id := int(entity.get("id", -1))
		seen_ids[entity_id] = true
		if entity_type == "hero" and str(entity.get("owner_id", "")) == local_owner:
			_local_entity_id = entity_id
		var alive := bool(entity.get("alive", false))
		var view: UnitVisual = _views.get(entity_id)
		if view == null:
			if entity_type != "hero" and not alive:
				continue
			view = _acquire_unit_view(entity)
			_views[entity_id] = view
		if view == null:
			continue
		if entity_type == "hero" and not view.visible:
			# 重新进入视野：直接落位，别从旧位置滑过来（那会出卖敌人的来路）。
			view.visible = true
			view.set_snapshot(entity, delta, 1.0, Vector2(float(entity.get("x", 0.0)), float(entity.get("y", 0.0))))
		# jitter buffer 模式下调用方显式给出上一格位置（可能跳过多格）。
		var prev_xy: Vector2 = _render_prev_positions.get(entity_id, Vector2(INF, INF))
		view.set_snapshot(entity, delta, _render_alpha, prev_xy)
		view.process_visual(delta)

	# 敌人离开视野：英雄不回收（等级/装备信息仍要在重新出现时立刻可用），但必须从画面消失。
	for eid in _views:
		var hidden_view: UnitVisual = _views[eid]
		if hidden_view != null and hidden_view.kind == "hero" and not seen_ids.has(eid):
			hidden_view.visible = false

	# 回收死亡完成或在快照中移除的小兵/野怪，杜绝泄漏与每帧遍历浪费。
	var to_recycle: Array[int] = []
	for eid in _views:
		var view: UnitVisual = _views[eid]
		if view == null:
			continue
		if view.kind == "minion" and (view.can_recycle() or not seen_ids.has(eid)):
			to_recycle.append(eid)
		elif view.kind == "monster" and not seen_ids.has(eid):
			to_recycle.append(eid)
	for eid in to_recycle:
		var view: UnitVisual = _views[eid]
		_views.erase(eid)
		if view == null:
			continue
		if view.kind == "minion":
			view.recycle()
			var pool := _minion_pool_blue if view.team == "blue" else _minion_pool_red
			if pool.size() < MINION_POOL_LIMIT:
				pool.append(view)
			else:
				view.queue_free()
		else:
			view.queue_free()

func _acquire_unit_view(entity: Dictionary) -> UnitVisual:
	var entity_type := str(entity.get("type", "hero"))
	var team := str(entity.get("team", "blue"))
	var pos := Vector3(float(entity.get("x", 0.0)), 0.0, float(entity.get("y", 0.0)))
	if entity_type == "minion":
		var pool := _minion_pool_blue if team == "blue" else _minion_pool_red
		if not pool.is_empty():
			var view: UnitVisual = pool.pop_back()
			view.reset_minion(team, pos)
			view.set_snapshot(entity, 1.0)
			return view
	return _create_unit_view(entity)

func _create_unit_view(entity: Dictionary) -> UnitVisual:
	var view := UnitVisual.new()
	var entity_type := str(entity.get("type", "hero"))
	var team := str(entity.get("team", "blue"))
	var entity_id := int(entity.get("id", -1))
	var is_local := entity_type == "hero" and str(entity.get("owner_id", "")) == local_owner
	if entity_type == "hero":
		view.setup("hero", team, str(entity.get("hero_type", "blade")), str(entity.get("name", "英雄")), is_local, local_team)
	elif entity_type == "monster":
		view.setup("monster", "neutral", str(entity.get("monster_type", "wolf")), str(entity.get("name", "野怪")), false, local_team)
	else:
		view.setup("minion", team, "minion", "", false, local_team)
	_units_root.add_child(view)
	view.position = Vector3(float(entity.get("x", 0.0)), 0.0, float(entity.get("y", 0.0)))
	view.set_snapshot(entity, 1.0)
	return view

func _sync_structures(snapshot: Dictionary, initial: bool) -> void:
	if snapshot.is_empty():
		return
	for entity in snapshot.get("entities", []):
		var entity_type := str(entity.get("type", ""))
		if entity_type != "tower" and entity_type != "guard" and entity_type != "base":
			continue
		var entity_id := int(entity.get("id", -1))
		var record: Dictionary = _structure_views.get(entity_id, {})
		if record.is_empty():
			record = _create_structure_view(entity)
			_structure_views[entity_id] = record
		var alive := bool(entity.get("alive", false))
		var root: Node3D = record.get("root")
		root.visible = alive
		if not alive:
			continue
		var spin: Node3D = record.get("spin")
		if spin:
			spin.rotation.y = float(Time.get_ticks_msec()) * 0.0006
		var shield: Node3D = record.get("shield")
		if shield:
			shield.visible = MapView.structure_locked(entity)
		if entity_type == "base":
			var crystal_shield: Node3D = record.get("crystal_shield")
			if crystal_shield:
				crystal_shield.visible = float(entity.get("shield", 0.0)) > 0.0
		var hp := float(entity.get("hp", 0.0))
		var max_hp := maxf(1.0, float(entity.get("max_hp", 1.0)))
		var ratio := clampf(hp / max_hp, 0.0, 1.0)
		var bar_mat: ShaderMaterial = record.get("bar_mat")
		if bar_mat and not is_equal_approx(float(record.get("ratio", -1.0)), ratio):
			record["ratio"] = ratio
			bar_mat.set_shader_parameter("ratio", ratio)

func _create_structure_view(entity: Dictionary) -> Dictionary:
	var team := str(entity.get("team", "blue"))
	var team_color := BLUE if team == "blue" else RED
	var entity_type := str(entity.get("type", "tower"))
	var tier := str(entity.get("tier", "outer"))
	var visual_scale := MapView.tower_scale(tier) if (entity_type == "tower" or entity_type == "guard") else 1.0
	var root := Node3D.new()
	var pos := Vector3(float(entity.get("x", 0.0)), 0.0, float(entity.get("y", 0.0)))
	root.position = pos
	root.rotation.y = atan2(-pos.x, -pos.z)
	_structures_root.add_child(root)
	var model: Node3D
	var bar_height: float
	var bar_width: float
	var ring_radius: float
	var spin_node: Node3D = null
	var crystal_shield: Node3D = null
	if entity_type == "base":
		var stone := StandardMaterial3D.new()
		stone.albedo_texture = load("res://assets/textures/cliff_side_Diffuse.jpg")
		stone.albedo_color = Color(0.62, 0.6, 0.54)
		stone.roughness = 1.0
		stone.uv1_scale = Vector3(3, 3, 3)
		var base_group := Node3D.new()
		var dais := MeshInstance3D.new()
		var dais_mesh := CylinderMesh.new()
		dais_mesh.top_radius = 4.4
		dais_mesh.bottom_radius = 4.8
		dais_mesh.height = 0.35
		dais_mesh.radial_segments = 32
		dais.mesh = dais_mesh
		dais.material_override = stone
		dais.position.y = 0.18
		base_group.add_child(dais)
		var pedestal := MeshInstance3D.new()
		var pedestal_mesh := CylinderMesh.new()
		pedestal_mesh.top_radius = 1.3
		pedestal_mesh.bottom_radius = 1.8
		pedestal_mesh.height = 1.2
		pedestal_mesh.radial_segments = 8
		pedestal.mesh = pedestal_mesh
		pedestal.material_override = stone
		pedestal.position.y = 0.95
		base_group.add_child(pedestal)
		spin_node = Node3D.new()
		spin_node.position.y = 3.55
		var gem := MeshInstance3D.new()
		var gem_mesh := SphereMesh.new()
		gem_mesh.radius = 1.05
		gem_mesh.height = 2.1
		gem_mesh.radial_segments = 6
		gem_mesh.rings = 3
		gem.mesh = gem_mesh
		gem.scale = Vector3(1.0, 1.55, 1.0)
		var gem_material := StandardMaterial3D.new()
		gem_material.albedo_color = team_color
		gem_material.emission_enabled = true
		gem_material.emission = team_color
		gem_material.emission_energy_multiplier = 2.6
		gem_material.roughness = 0.15
		gem.material_override = gem_material
		spin_node.add_child(gem)
		var halo := MeshInstance3D.new()
		var halo_torus := TorusMesh.new()
		halo_torus.inner_radius = 1.9
		halo_torus.outer_radius = 2.05
		halo_torus.rings = 40
		halo_torus.ring_segments = 6
		halo.mesh = halo_torus
		halo.rotation.x = -PI * 0.35
		var halo_material := StandardMaterial3D.new()
		halo_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		halo_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		halo_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		halo_material.albedo_color = Color(team_color.r, team_color.g, team_color.b, 0.5)
		halo_material.emission_enabled = true
		halo_material.emission = team_color
		halo_material.emission_energy_multiplier = 1.4
		halo.material_override = halo_material
		halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		spin_node.add_child(halo)
		base_group.add_child(spin_node)
		model = base_group
		bar_height = 7.4
		bar_width = 6.0
		# 基地脚下的圈就是泉水范围，和 match_sim 的恢复判定共用同一个半径。
		ring_radius = MapData.FOUNTAIN_RADIUS
		var light := OmniLight3D.new()
		light.light_color = team_color
		light.light_energy = 1.6
		light.omni_range = 22.0
		light.position = Vector3(0, 4.0, 0)
		light.shadow_enabled = false
		root.add_child(light)
		var beam := MeshInstance3D.new()
		var beam_mesh := CylinderMesh.new()
		beam_mesh.top_radius = 0.5
		beam_mesh.bottom_radius = 0.15
		beam_mesh.height = 26.0
		beam_mesh.radial_segments = 12
		beam.mesh = beam_mesh
		var beam_material := StandardMaterial3D.new()
		beam_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		beam_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		beam_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		beam_material.albedo_color = Color(team_color.r, team_color.g, team_color.b, 0.1)
		beam_material.emission_enabled = true
		beam_material.emission = team_color
		beam_material.emission_energy_multiplier = 0.7
		beam.material_override = beam_material
		beam.position = Vector3(0, 13.0, 0)
		beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(beam)
		# 水晶护盾：双塔存活且基地已暴露时罩住整座水晶，破碎后直接消失。
		var bubble := MeshInstance3D.new()
		var bubble_mesh := SphereMesh.new()
		bubble_mesh.radius = 4.6
		bubble_mesh.height = 9.2
		bubble_mesh.radial_segments = 32
		bubble_mesh.rings = 16
		bubble.mesh = bubble_mesh
		var bubble_material := StandardMaterial3D.new()
		bubble_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		bubble_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		bubble_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		bubble_material.albedo_color = Color(0.56, 0.82, 1.0, 0.14)
		bubble_material.emission_enabled = true
		bubble_material.emission = Color(0.5, 0.78, 1.0)
		bubble_material.emission_energy_multiplier = 0.8
		bubble.material_override = bubble_material
		bubble.position.y = 3.0
		bubble.visible = float(entity.get("shield", 0.0)) > 0.0
		bubble.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(bubble)
		crystal_shield = bubble
	else:
		model = ModelUtils.fit_scene(load(ENV_DIR + "WatchTower_SecondAge_Level3.glb"), 7.3 * visual_scale, 3.8 * visual_scale)
		bar_height = 8.5 * visual_scale
		bar_width = 2.7 * visual_scale
		ring_radius = 2.5 * visual_scale
		var crystal := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = 0.32
		sphere.height = 0.9
		crystal.mesh = sphere
		var crystal_material := StandardMaterial3D.new()
		crystal_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		crystal_material.albedo_color = team_color
		crystal_material.emission_enabled = true
		crystal_material.emission = team_color
		crystal_material.emission_energy_multiplier = 2.2
		crystal.material_override = crystal_material
		crystal.position = Vector3(0, 7.0 * visual_scale, 0)
		crystal.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(crystal)
	ModelUtils.tint(model, team_color, 0.08)
	ModelUtils.enable_shadows(model, true)
	root.add_child(model)
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = ring_radius
	torus.outer_radius = ring_radius + 0.22
	torus.rings = 40
	torus.ring_segments = 6
	ring.mesh = torus
	ring.position.y = 0.08
	var ring_material := StandardMaterial3D.new()
	ring_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring_material.albedo_color = Color(team_color.r, team_color.g, team_color.b, 0.55)
	ring_material.emission_enabled = true
	ring_material.emission = team_color
	ring_material.emission_energy_multiplier = 1.1
	ring_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring.material_override = ring_material
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(ring)
	# 未解锁的塔/主堡罩一层光环，提示「现在打不动」。
	var shield := MeshInstance3D.new()
	var shield_torus := TorusMesh.new()
	shield_torus.inner_radius = ring_radius + 1.1
	shield_torus.outer_radius = ring_radius + 1.28
	shield_torus.rings = 40
	shield_torus.ring_segments = 6
	shield.mesh = shield_torus
	shield.position.y = 0.12
	var shield_material := StandardMaterial3D.new()
	shield_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	shield_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	shield_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	shield_material.albedo_color = Color(0.62, 0.78, 0.9, 0.42)
	shield_material.emission_enabled = true
	shield_material.emission = Color(0.55, 0.72, 0.9)
	shield_material.emission_energy_multiplier = 1.2
	shield.material_override = shield_material
	shield.visible = MapView.structure_locked(entity)
	shield.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(shield)
	var fill := _add_structure_bar(root, bar_height, bar_width, team_color)
	return {
		"root": root,
		"bar": fill[0],
		"bar_mat": fill[1],
		"bar_width": bar_width,
		"spin": spin_node,
		"shield": shield,
		"crystal_shield": crystal_shield,
		"scale": visual_scale,
		"tier": tier,
		"team_color": team_color,
	}

func _add_structure_bar(root: Node3D, height: float, width: float, color: Color) -> Array:
	var holder := Node3D.new()
	holder.position.y = height
	root.add_child(holder)
	# 单 quad + 自定义 billboard 着色器：BILLBOARD_ENABLED 会丢弃节点缩放，
	# 旧的 scale.x 填充方式在 billboard 下完全失效。
	var quad := QuadMesh.new()
	quad.size = Vector2(width + 0.12, 0.2)
	var bar := MeshInstance3D.new()
	bar.mesh = quad
	bar.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := ShaderMaterial.new()
	mat.shader = BAR_SHADER
	mat.set_shader_parameter("fill_color", color)
	mat.set_shader_parameter("padding", 0.06 / (width + 0.12))
	mat.set_shader_parameter("ratio", 1.0)
	bar.material_override = mat
	holder.add_child(bar)
	return [bar, mat]

func _process_events(events: Array) -> void:
	# 音效与表现共用同一批事件：模拟侧算一次，主机/客机听到的是同一场战斗。
	if _audio != null:
		_audio.handle_events(events, TICK)
	for event in events:
		if not (event is Dictionary):
			continue
		var banner := MapView.event_banner(event)
		if not banner.is_empty() and hud != null:
			var banner_color: Color = banner.get("color", GameTheme.GOLD_LIGHT)
			if bool(banner.get("announce", false)):
				hud.announce(str(banner.get("text", "")), banner_color, float(banner.get("duration", 1.6)))
			hud.add_feed(str(banner.get("feed", "")), banner_color)
		match str(event.get("type", "")):
			"attack":
				var attacker: UnitVisual = _views.get(int(event.get("hero", -1)))
				if attacker:
					attacker.play_attack()
				if bool(event.get("crit", false)):
					_hit_stop.trigger_hit_stop(0.045, 0.18)
			"skill":
				_handle_skill_event(event)
			"hit":
				_handle_hit_event(event)
			"death":
				_handle_death_event(event)
			"tower_destroyed":
				var pos := Vector3(float(event.get("x", 0.0)), 1.0, float(event.get("y", 0.0)))
				_explosion(pos, RED if str(event.get("team", "red")) == "red" else BLUE, 32)
				_hit_stop.trigger_hit_stop(0.06, 0.22)
			"guard_destroyed":
				var guard_pos := Vector3(float(event.get("x", 0.0)), 1.0, float(event.get("y", 0.0)))
				_explosion(guard_pos, RED if str(event.get("team", "red")) == "red" else BLUE, 30)
				_camera_shake = maxf(_camera_shake, 0.14)
			"crystal_shield_broken":
				var crystal_pos := Vector3(float(event.get("x", 0.0)), 2.0, float(event.get("y", 0.0)))
				_spawn_ring(crystal_pos, Color(0.55, 0.84, 1.0), 1.0, 8.0, 1.0)
				_spawn_particles(crystal_pos + Vector3(0, 2.0, 0), Color(0.62, 0.86, 1.0), 30, 6.0)
				_camera_shake = maxf(_camera_shake, 0.22)
				_hit_stop.trigger_hit_stop(0.1, 0.3)
			"teleport":
				var from_pos := Vector3(float(event.get("x", 0.0)), 0.2, float(event.get("y", 0.0)))
				var to_pos := Vector3(float(event.get("to_x", 0.0)), 0.2, float(event.get("to_y", 0.0)))
				_handle_channel_departure(int(event.get("hero", -1)), "teleport", from_pos, to_pos)
			"teleport_interrupt":
				var break_pos := Vector3(float(event.get("x", 0.0)), 0.2, float(event.get("y", 0.0)))
				_handle_channel_break(int(event.get("hero", -1)), "teleport", break_pos)
			"recall":
				var leave_pos := Vector3(float(event.get("x", 0.0)), 0.2, float(event.get("y", 0.0)))
				var home_pos := Vector3(float(event.get("to_x", 0.0)), 0.2, float(event.get("to_y", 0.0)))
				_handle_channel_departure(int(event.get("hero", -1)), "recall", leave_pos, home_pos)
			"recall_interrupt":
				var cancel_pos := Vector3(float(event.get("x", 0.0)), 0.2, float(event.get("y", 0.0)))
				_handle_channel_break(int(event.get("hero", -1)), "recall", cancel_pos)
			"river_spirit_killed":
				var spirit_pos := Vector3(float(event.get("x", 0.0)), 0.5, float(event.get("y", 0.0)))
				_spawn_ring(spirit_pos, Color(0.46, 0.86, 0.94), 0.6, 4.0, 0.8)
			"objective_killed":
				var boss_pos := Vector3(float(event.get("x", 0.0)), 1.0, float(event.get("y", 0.0)))
				_explosion(boss_pos, GOLD, 40)
				_spawn_ring(Vector3(boss_pos.x, 0.1, boss_pos.z), GOLD, 1.0, 6.0, 0.9)
				_camera_shake = maxf(_camera_shake, 0.2)
			"buff_taken":
				var buff_pos := Vector3(float(event.get("x", 0.0)), 0.2, float(event.get("y", 0.0)))
				var buff_color := BLUE if str(event.get("buff", "")) == "blue" else RED
				_spawn_ring(buff_pos, buff_color, 0.6, 3.0, 0.7)
				_spawn_particles(buff_pos + Vector3(0, 0.8, 0), buff_color, 16, 3.0)
			"base_exposed":
				_camera_shake = maxf(_camera_shake, 0.16)
			"level_up":
				var hero: UnitVisual = _views.get(int(event.get("hero", -1)))
				if hero:
					_spawn_ring(hero.position, GOLD, 0.3, 2.2, 0.6)
					_spawn_particles(hero.position + Vector3(0, 1.0, 0), GOLD, 20, 4.0)
			"wave":
				var wave := int(event.get("wave", 1))
				if wave == 1 or wave % 3 == 0:
					hud.announce("第 %d 波兵线出发" % wave, Color(0.93, 0.82, 0.6), 1.4)
				hud.add_feed("第 %d 波兵线出发" % wave, GameTheme.MUTED)
			"structure_attack":
				var from := Vector3(float(event.get("x", 0.0)), 7.0, float(event.get("y", 0.0)))
				var to := Vector3(float(event.get("target_x", 0.0)), 1.1, float(event.get("target_y", 0.0)))
				_spawn_beam(from, to, BLUE if str(event.get("team", "blue")) == "blue" else RED, 0.14)
			"respawn":
				var pos := Vector3(float(event.get("x", 0.0)), 0.1, float(event.get("y", 0.0)))
				_spawn_ring(pos, GOLD, 0.4, 2.0, 0.6)
			"match_end":
				hud.announce("主堡陷落", GameTheme.GOLD_LIGHT, 2.0)
				_hit_stop.trigger_hit_stop(0.16, 0.45)
				# 结算曲按本地队伍判：赢了上行号角，输了下行钟声。
				# 这两个是一次性音（不循环），所以不走 play_cue 的声道池。
				if _audio != null:
					var winner := str(event.get("winner", ""))
					if winner == local_team:
						_audio.play_music(AudioDirector.MUSIC_VICTORY)
					else:
						_audio.play_music(AudioDirector.MUSIC_DEFEAT)

# 引导完成（回城落地 / 传送抵达）：起点法阵炸开、终点成形、模型直接落位。
# 必须显式 snap_to：位置跳变不足 14 米时（从自家野区回城就是这种）插值会让人滑过整片野区。
func _handle_channel_departure(entity_id: int, kind: String, from_pos: Vector3, to_pos: Vector3) -> void:
	var color := ChannelFx.color_for(kind)
	var fx := _channel_fx.get(entity_id) as ChannelFx
	if fx != null and is_instance_valid(fx):
		fx.burst(color)
		fx.release()
	# 起点余波：人已经走了，只留一圈正在消散的光。
	_spawn_ring(from_pos, color, 1.7, 5.4, 0.55)
	_spawn_particles(from_pos + Vector3(0, 0.9, 0), color, 18, 4.0)
	# 落点成形：英雄凭空出现，必须有「到了」的实感。两层错开的冲击环比单环更像落地。
	_spawn_ring(to_pos, color, 0.6, 4.6, 0.62, 0.9)
	_spawn_ring(to_pos, Color(1.0, 1.0, 1.0).lerp(color, 0.35), 0.35, 2.4, 0.34, 0.95)
	_spawn_particles(to_pos + Vector3(0, 1.0, 0), color, 26, 5.5)
	var view: UnitVisual = _views.get(entity_id)
	if view != null:
		view.snap_to(Vector3(to_pos.x, 0.0, to_pos.z))
	# 客机的插值区间由 jitter buffer 的上一格位置驱动，不清掉会从旧位置滑过来。
	_render_prev_positions.erase(entity_id)
	if entity_id == _local_entity_id:
		_play_channel_cue(AudioCues.recall_done() if kind == "recall" else AudioCues.teleport_done())
		# 回城落地后旧的点击目标已经失效，不清会让英雄立刻往回走。
		_move_target_valid = false
		_prediction.reset(Vector2(to_pos.x, to_pos.z))

# 引导被打断：法阵内爆，不给「成」的音色。
func _handle_channel_break(entity_id: int, kind: String, pos: Vector3) -> void:
	var color := ChannelFx.color_for(kind)
	var fx := _channel_fx.get(entity_id) as ChannelFx
	if fx != null and is_instance_valid(fx):
		fx.shatter(color)
	var dimmed := color.lerp(RED, 0.35)
	_spawn_ring(pos, dimmed, 0.6, 3.4, 0.34, 0.85)
	_spawn_particles(pos + Vector3(0, 0.8, 0), dimmed, 14, 3.2, 0.1, 0.45)
	if entity_id == _local_entity_id:
		_play_channel_cue(AudioCues.recall_break() if kind == "recall" else AudioCues.teleport_break())

func _handle_skill_event(event: Dictionary) -> void:
	var entity_id := int(event.get("hero", -1))
	var view: UnitVisual = _views.get(entity_id)
	if view == null:
		return
	var slot := str(event.get("slot", "q"))
	view.play_skill(slot)
	var hero_type := str(event.get("hero_type", "blade"))
	var color := _hero_vfx_color(hero_type)
	var from := Vector3(float(event.get("x", 0.0)), 1.0, float(event.get("y", 0.0)))
	var aim := Vector3(float(event.get("aim_x", 0.0)), 0.0, float(event.get("aim_y", 0.0)))
	if slot == "e":
		_spawn_ring(view.position, color, 0.4, 2.2, 0.5)
		_spawn_particles(view.position + Vector3(0, 1.0, 0), color, 14, 3.0)
		return
	match hero_type:
		"blade":
			_spawn_ring(aim, color, 0.5, 2.6, 0.32)
			_spawn_particles(aim + Vector3(0, 0.6, 0), color, 22, 5.0)
		"tank":
			_spawn_ring(aim, color, 0.6, 4.2, 0.55)
			_explosion(aim + Vector3(0, 0.4, 0), color, 16)
			_camera_shake = maxf(_camera_shake, 0.18)
		"mage":
			_spawn_projectile(from, aim + Vector3(0, 0.8, 0), color, 0.18)
		"archer":
			_spawn_projectile(from, aim + Vector3(0, 1.0, 0), color, 0.12)
		"assassin":
			# 刺客是贴脸斩击：短促的紫色刀环 + 少量高速碎屑，不做抛射物。
			_spawn_ring(aim, color, 0.38, 2.2, 0.2)
			_spawn_particles(aim + Vector3(0, 0.9, 0), color, 16, 6.0, 0.16, 0.5)
			_camera_shake = maxf(_camera_shake, 0.1)

func _handle_hit_event(event: Dictionary) -> void:
	var pos := Vector3(float(event.get("x", 0.0)), 0.0, float(event.get("y", 0.0)))
	var amount := float(event.get("amount", 0.0))
	var target_id := int(event.get("target", -1))
	var target_type := str(event.get("target_type", ""))
	var color := Color(1.0, 0.92, 0.72) if amount >= 150.0 else Color(0.95, 0.96, 1.0)
	_spawn_damage_number(pos + Vector3(0, 1.7 if target_type == "hero" else 1.0, 0), amount, color)
	if target_type == "hero":
		var view: UnitVisual = _views.get(target_id)
		if view:
			view.play_hit()
		_spawn_particles(pos + Vector3(0, 1.0, 0), Color(1.0, 0.72, 0.4), 10, 3.0)
		if target_id == _local_entity_id:
			_camera_shake = maxf(_camera_shake, 0.12)
	else:
		_spawn_particles(pos + Vector3(0, 0.55, 0), Color(0.9, 0.72, 0.4), 4, 1.8, 0.05, 0.3)

func _handle_death_event(event: Dictionary) -> void:
	var pos := Vector3(float(event.get("x", 0.0)), 0.4, float(event.get("y", 0.0)))
	var entity_type := str(event.get("entity_type", "minion"))
	var team := str(event.get("team", "blue"))
	if entity_type == "hero":
		_explosion(pos + Vector3(0, 0.8, 0), Color(0.85, 0.5, 0.3), 24)
		var hero_id := int(event.get("hero", -1))
		var view: UnitVisual = _views.get(hero_id)
		var victim := str(event.get("victim_name", view.display_name if view else "英雄"))
		var killer_id := int(event.get("killer", -1))
		var killer_name := str(event.get("killer_name", ""))
		var killer_type := str(event.get("killer_type", ""))
		var killer_team := str(event.get("killer_team", ""))
		if killer_name == "" and killer_id >= 0:
			var kview: UnitVisual = _views.get(killer_id)
			if kview:
				killer_name = kview.display_name
		if killer_name == "":
			killer_name = "防御塔" if killer_type == "tower" else ("小兵" if killer_type == "minion" else "战场机关")

		var is_local_victim := (hero_id == _local_entity_id)
		var is_local_killer := (killer_id == _local_entity_id)
		var local_involved := is_local_victim or is_local_killer
		_hit_stop.trigger_hit_stop(0.09 if local_involved else 0.05, 0.34 if local_involved else 0.16)

		# 多杀 / 一血 / 终结由模拟侧统一判定，联机两端看到的是同一份结果。
		var announce_code := str(event.get("announcement", ""))
		var streak_code := str(event.get("streak_title", ""))
		if KILL_ANNOUNCEMENTS.has(announce_code):
			hud.announce(str(KILL_ANNOUNCEMENTS[announce_code]), GameTheme.GOLD_LIGHT, 2.0)
		elif STREAK_TITLES.has(streak_code):
			hud.announce("%s · %s" % [killer_name, STREAK_TITLES[streak_code]], GameTheme.GOLD_LIGHT, 1.8)
		elif is_local_killer:
			hud.announce("你击败了敌方英雄！", GameTheme.GOLD_LIGHT, 1.8)
		elif is_local_victim:
			hud.announce("你被 %s 击败！" % killer_name, RED, 2.0)
		elif killer_team == local_team and team != local_team:
			hud.announce("%s 击败了 %s" % [killer_name, victim], BLUE, 1.6)
		elif killer_team != local_team and team == local_team:
			hud.announce("友方 %s 被击败" % victim, RED, 1.6)

		var feed_color := GameTheme.GOLD_LIGHT if is_local_killer else (RED if is_local_victim else (BLUE if killer_team == local_team else RED))
		if killer_type == "hero":
			hud.add_feed("%s 击败了 %s" % [killer_name, victim], feed_color)
		else:
			hud.add_feed("%s 被 %s 击败" % [victim, killer_name], feed_color)
	elif entity_type == "minion":
		_spawn_particles(pos, Color(0.75, 0.7, 0.6), 5, 2.0, 0.05, 0.4)
	elif entity_type == "monster":
		var boss := str(event.get("name", "")).contains("暴君") or str(event.get("name", "")).contains("主宰")
		_spawn_particles(pos + Vector3(0, 0.8, 0), GOLD if boss else Color(0.7, 0.8, 0.52), 18 if boss else 8, 3.0, 0.1, 0.5)

func _init_vfx_pools() -> void:
	if _effects_root == null:
		return
	# 预热飘字 Label3D 池（24个），杜绝每次受击 new / load 字体 / queue_free
	for i in 24:
		var label := Label3D.new()
		label.font = FONT_SC
		label.font_size = 64
		label.pixel_size = 0.005
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.no_depth_test = true
		label.outline_size = 12
		label.outline_modulate = Color(0.0, 0.0, 0.0, 0.9)
		label.visible = false
		_effects_root.add_child(label)
		_damage_labels_pool.append(label)

	# 预热打击粒子池（12个 GPUParticles3D），预先进入渲染树并预热着色器
	for i in 12:
		var p := GPUParticles3D.new()
		p.amount = 14
		p.lifetime = 0.55
		p.one_shot = true
		p.explosiveness = 0.95
		var process := ParticleProcessMaterial.new()
		process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
		process.emission_sphere_radius = 0.16
		process.direction = Vector3(0, 1, 0)
		process.spread = 180.0
		process.initial_velocity_min = 1.5
		process.initial_velocity_max = 3.5
		process.gravity = Vector3(0, -7.5, 0)
		process.scale_min = 0.55
		process.scale_max = 1.25
		p.process_material = process
		var quad := QuadMesh.new()
		quad.size = Vector2(0.12, 0.12)
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		material.vertex_color_use_as_albedo = true
		quad.material = material
		p.draw_pass_1 = quad
		p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		p.emitting = false
		_effects_root.add_child(p)
		_hit_particles_pool.append(p)

func _spawn_damage_number(pos: Vector3, amount: float, color: Color) -> void:
	if _effects_root == null:
		return
	var label: Label3D
	if not _damage_labels_pool.is_empty():
		label = _damage_labels_pool.pop_back()
	else:
		label = Label3D.new()
		label.font = FONT_SC
		label.font_size = 64
		label.pixel_size = 0.005
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.no_depth_test = true
		label.outline_size = 12
		label.outline_modulate = Color(0.0, 0.0, 0.0, 0.9)
		_effects_root.add_child(label)
	label.text = str(int(round(amount)))
	label.modulate = color
	label.position = pos + Vector3(randf_range(-0.25, 0.25), 0.0, randf_range(-0.25, 0.25))
	label.visible = true
	var start_y := label.position.y
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(label, "position:y", start_y + 0.9, 0.65)
	tween.tween_property(label, "modulate:a", 0.0, 0.65)
	tween.chain().tween_callback(func():
		if is_instance_valid(label):
			label.visible = false
			label.modulate.a = 1.0
			_damage_labels_pool.append(label)
	)

func _spawn_ring(pos: Vector3, color: Color, from_scale: float, to_scale: float, duration: float, alpha := 0.65) -> void:
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.62
	torus.outer_radius = 0.78
	torus.rings = 24
	torus.ring_segments = 5
	ring.mesh = torus
	ring.position = Vector3(pos.x, 0.1, pos.z)
	ring.scale = Vector3.ONE * from_scale
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.albedo_color = Color(color.r, color.g, color.b, alpha)
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = 1.6
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	ring.material_override = material
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_effects_root.add_child(ring)
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(ring, "scale", Vector3.ONE * to_scale, duration)
	tween.tween_property(material, "albedo_color:a", 0.0, duration)
	tween.chain().tween_callback(ring.queue_free)

func _spawn_particles(pos: Vector3, color: Color, amount := 14, speed := 3.5, size := 0.12, lifetime := 0.55) -> void:
	if _effects_root == null:
		return
	var p: GPUParticles3D
	if not _hit_particles_pool.is_empty():
		p = _hit_particles_pool.pop_back()
	else:
		return
	p.position = pos
	p.amount = amount
	p.lifetime = lifetime
	var mat := p.process_material as ParticleProcessMaterial
	if mat:
		mat.color = color
		mat.initial_velocity_min = speed * 0.45
		mat.initial_velocity_max = speed
	p.restart()
	p.emitting = true
	get_tree().create_timer(lifetime + 0.1).timeout.connect(func():
		if is_instance_valid(p):
			p.emitting = false
			_hit_particles_pool.append(p)
	)

func _spawn_projectile(from: Vector3, to: Vector3, color: Color, duration: float) -> void:
	var orb := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.16
	sphere.height = 0.32
	orb.mesh = sphere
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = 2.4
	orb.material_override = material
	orb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	orb.position = from
	_effects_root.add_child(orb)
	orb.scale = Vector3.ONE * 2.2
	var tween := create_tween()
	tween.tween_property(orb, "position", to, duration)
	tween.parallel().tween_property(orb, "scale", Vector3.ONE, duration)
	tween.tween_callback(func():
		_spawn_particles(to, color, 20, 4.5)
		_spawn_ring(Vector3(to.x, 0.1, to.z), color, 0.35, 1.8, 0.3)
		orb.queue_free()
	)

func _spawn_beam(from: Vector3, to: Vector3, color: Color, duration: float) -> void:
	var orb := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.12
	sphere.height = 0.24
	orb.mesh = sphere
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = 2.0
	orb.material_override = material
	orb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	orb.position = from
	_effects_root.add_child(orb)
	var tween := create_tween()
	tween.tween_property(orb, "position", to, duration)
	tween.tween_callback(func():
		_spawn_particles(to, color, 6, 2.5, 0.1, 0.35)
		orb.queue_free()
	)

func _explosion(pos: Vector3, color: Color, amount: int) -> void:
	_spawn_particles(pos, color, amount, 6.0, 0.16, 0.7)
	_spawn_particles(pos, Color(1.0, 0.85, 0.55), int(amount * 0.5), 4.0, 0.1, 0.5)
	_spawn_ring(Vector3(pos.x, 0.12, pos.z), color, 0.6, 4.5, 0.55)

func _hero_vfx_color(hero_type: String) -> Color:
	match hero_type:
		"blade":
			return Color(1.0, 0.72, 0.3)
		"mage":
			return Color(0.62, 0.5, 1.0)
		"tank":
			return Color(0.4, 0.85, 0.8)
		"archer":
			return Color(0.55, 0.95, 0.5)
		"assassin":
			return Color(0.88, 0.42, 0.72)
	return GOLD

func _build_ambient_particles() -> void:
	var particles := GPUParticles3D.new()
	particles.amount = 36
	particles.lifetime = 14.0
	particles.visibility_aabb = AABB(Vector3(-70, -2, -70), Vector3(140, 18, 140))
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process.emission_box_extents = Vector3(62, 5, 62)
	process.direction = Vector3(0, 1, 0)
	process.spread = 35.0
	process.initial_velocity_min = 0.08
	process.initial_velocity_max = 0.35
	process.gravity = Vector3(0, 0.015, 0)
	process.color = Color(1.0, 0.88, 0.6, 0.45)
	particles.process_material = process
	var quad := QuadMesh.new()
	quad.size = Vector2(0.05, 0.05)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	material.vertex_color_use_as_albedo = true
	quad.material = material
	particles.draw_pass_1 = quad
	particles.position = Vector3(0, 5.0, 0)
	particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_effects_root.add_child(particles)
	particles.emitting = true
