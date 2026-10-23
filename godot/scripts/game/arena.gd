extends Node3D

signal exit_requested
# 分帧构建进度：0..1 与阶段说明，交给外层加载遮罩显示。
signal build_progress(value: float, text: String)
signal ready_for_battle

const MatchSim = preload("res://sim/match_sim.gd")
const MapData = preload("res://sim/map_data.gd")
const HeroDefs = preload("res://sim/hero_defs.gd")
const ModelUtils = preload("res://scripts/game/model_utils.gd")
const UnitVisual = preload("res://scripts/game/unit_visual.gd")
const GameHUD = preload("res://scripts/ui/game_hud.gd")
const GameTheme = preload("res://scripts/ui/game_theme.gd")
const InputAssist = preload("res://scripts/game/input_assist.gd")
const MatchMenu = preload("res://scripts/game/match_menu.gd")
const BAR_SHADER := preload("res://shaders/billboard_bar.gdshader")

const ENV_DIR := "res://assets/environment/"
const TICK := 1.0 / 30.0
# 相机缩放的滑行速率（zoom 单位/秒）。滚轮一次 ±2，约 0.14s 走完，匀速不突兀。
const ZOOM_GLIDE_SPEED := 14.0
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
var camera: Camera3D
var hud: GameHUD
var aim_marker: Node3D
var aim_material: StandardMaterial3D
# 本地英雄脚下的普攻范围环（常驻）。技能范围环是按需生成的临时节点。
var attack_range_ring: MeshInstance3D
var zoom := 21.0
# 渲染用的平滑缩放值。相机位置必须刚性跟随角色（否则与 look_at 产生相位差而抖动），
# 但 zoom 突变会让整台相机瞬移，所以单独对 zoom 这个标量做插值。
var _zoom_current := 21.0
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
var _first_blood := false
var _camera_shake := 0.0
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
var _prev_e := false
var _queued_q := false
var _queued_e := false
var _local_input := {
	"move": Vector2.ZERO,
	"aim": Vector2.ZERO,
	"skill_q": false,
	"skill_e": false,
	"attack": false,
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
	_init_vfx_pools()
	_build_camera()
	_build_aim_marker()
	_build_move_marker()
	_build_range_indicators()
	_build_ambient_particles()
	await _next_frame()

	_emit_build(0.5, "点亮英雄与防御塔")
	if sim != null:
		current_snapshot = sim.snapshot()
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
		if entity_type != "hero" and entity_type != "minion":
			continue
		if entity_type == "minion" and not bool(entity.get("alive", false)):
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
			view.setup("minion", team, "minion", "", false)
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
	hud.leave_requested.connect(_on_leave_requested)
	hud.resume_requested.connect(_on_resume_requested)
	hud.move_changed.connect(_on_touch_move)
	hud.attack_changed.connect(_on_touch_attack)
	hud.pause_requested.connect(_toggle_pause)
	layer.add_child(hud)

func _on_skill_button(slot: String) -> void:
	if slot == "q":
		_queued_q = true
	else:
		_queued_e = true

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
	hud.show_pause(false, session != null)

func _process(delta: float) -> void:
	if not build_complete:
		return
	if session != null and session.has_method("poll"):
		session.poll()
	if _paused:
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
			current_snapshot = sim.snapshot()
			_process_events(current_snapshot.events)
			if session != null and session.has_method("is_online") and session.is_online():
				_pending_events.append_array(current_snapshot.events)
		elif current_snapshot.is_empty():
			current_snapshot = sim.snapshot()
		_render_alpha = clampf(_accumulator / TICK, 0.0, 1.0)
		_consume_skill_queue()
		if session != null and session.has_method("is_online") and session.is_online():
			_snapshot_timer += delta
			if _snapshot_timer >= 0.1:
				_snapshot_timer = 0.0
				var outgoing := current_snapshot.duplicate()
				outgoing["events"] = _pending_events.duplicate()
				_pending_events.clear()
				session.broadcast_snapshot(outgoing)
	elif session != null:
		_gather_input()
		_input_timer += delta
		if _input_timer >= 0.05 or _local_input.skill_q or _local_input.skill_e:
			_input_timer = 0.0
			session.submit_input(_local_input.duplicate())
			_consume_skill_queue()
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
	_sync_structures(current_snapshot, false)
	_update_camera(delta, false)
	_update_aim_marker()
	_update_range_indicators()
	_update_move_marker(delta)
	_hud_timer += delta
	if _hud_timer >= 0.05 and hud != null:
		_hud_timer = 0.0
		hud.update_snapshot(current_snapshot)

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
	var e_down := Input.is_key_pressed(KEY_E)
	if (q_down and not _prev_q) or _queued_q:
		_local_input.skill_q = true
		_flash_skill_range("q")
	if (e_down and not _prev_e) or _queued_e:
		_local_input.skill_e = true
		_flash_skill_range("e")
	_prev_q = q_down
	_prev_e = e_down
	_local_input.move = move
	if _mouse_valid:
		_local_input.aim = _mouse_ground
	# 左键已经让给「走到那」，普攻改到右键 / 空格。
	_local_input.attack = Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT) or Input.is_key_pressed(KEY_SPACE)

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
	if _queued_e:
		_local_input.skill_e = true
		_flash_skill_range("e")
	_local_input.move = InputAssist.camera_relative_move(_touch_move, _camera_forward_2d())
	_local_input.aim = _resolve_touch_aim()
	_local_input.attack = _touch_attack

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

func _consume_skill_queue() -> void:
	_local_input.skill_q = false
	_local_input.skill_e = false
	_queued_q = false
	_queued_e = false

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
	var target := _local_world_position()
	# 缩放单独平滑：位置跟随必须刚性（否则与 look_at 产生相位差而抖动），
	# 但 zoom 一步变 2.0 会让相机整体瞬移，观感上同样是「跳」。
	# 用恒定速率而非指数衰减——指数衰减「前快后慢」，首帧就会走掉一大截。
	if instant or not _cam_initialized:
		_zoom_current = zoom
	else:
		_zoom_current = move_toward(_zoom_current, zoom, delta * ZOOM_GLIDE_SPEED)
	var desired := _camera_desired(target)
	# 目标位置本身已是逐帧插值后的平滑轨迹，相机再叠一层 lerp 只会引入滞后；
	# 而 look_at 用的是即时 target，两者相位不一致正是移动时画面抖动的主因。
	# 改为刚性锁定：角色在屏幕上保持稳定，背景匀速滚动（MOBA 的标准手感）。
	camera.position = desired
	_cam_initialized = true
	if _camera_shake > 0.0:
		_camera_shake = maxf(0.0, _camera_shake - delta * 1.8)
		camera.position += Vector3(randf_range(-_camera_shake, _camera_shake), randf_range(-_camera_shake, _camera_shake) * 0.4, 0.0)
	camera.look_at(target + Vector3(0.0, 0.55, 0.0), Vector3.UP)

func _build_camera() -> void:
	camera = Camera3D.new()
	camera.name = "Camera"
	camera.fov = 42.0
	camera.near = 0.2
	camera.far = 320.0
	camera.current = true
	add_child(camera)
	var base := MapData.BLUE_BASE if local_team == "blue" else MapData.RED_BASE
	var target := Vector3(base.x, 0.0, base.y)
	camera.position = _camera_desired(target)
	camera.look_at(target + Vector3(0.0, 0.55, 0.0), Vector3.UP)

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

func _update_range_indicators() -> void:
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
	environment.fog_light_color = Color(0.5, 0.6, 0.62)
	environment.fog_light_energy = 0.7
	environment.fog_density = 0.0038
	environment.fog_sky_affect = 0.25
	environment.fog_aerial_perspective = 0.35
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
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(160.0, 160.0)
	ground.mesh = plane
	var shader := Shader.new()
	shader.code = """
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
uniform sampler2D grass_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D dirt_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
varying vec3 world_pos;
void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
void fragment() {
	vec2 uv = world_pos.xz * 0.12;
	vec3 broad = texture(grass_tex, world_pos.xz * 0.014).rgb;
	vec3 grass = texture(grass_tex, uv).rgb * vec3(0.5, 0.66, 0.4);
	vec3 dirt = texture(dirt_tex, uv * 0.72).rgb * vec3(0.95, 0.84, 0.66);
	vec3 color = mix(grass, dirt, smoothstep(0.32, 0.68, broad.r) * 0.3);
	color *= 0.9 + broad.g * 0.16;
	ALBEDO = color;
	ROUGHNESS = 0.94;
	SPECULAR = 0.16;
}
"""
	var material := ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("grass_tex", load("res://assets/textures/leafy_grass_Diffuse.jpg"))
	material.set_shader_parameter("dirt_tex", load("res://assets/textures/grass_path_2_Diffuse.jpg"))
	ground.material_override = material
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
		var path: Array = MapData.lane_path(lane)
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
	var river := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(176.0, 18.0)
	river.mesh = plane
	river.rotation.y = PI * 0.25
	river.position.y = 0.012
	var shader := Shader.new()
	shader.code = """
shader_type spatial;
render_mode blend_mix, cull_disabled, specular_schlick_ggx;
uniform vec4 deep_color : source_color = vec4(0.025, 0.12, 0.15, 0.92);
uniform vec4 shallow_color : source_color = vec4(0.09, 0.32, 0.34, 0.86);
void fragment() {
	vec2 uv = UV;
	float ripple = sin(uv.x * 92.0 + uv.y * 38.0 + TIME * 1.25) * 0.5 + 0.5;
	ALBEDO = mix(deep_color.rgb, shallow_color.rgb, ripple * 0.42);
	ALPHA = mix(0.8, 0.92, ripple);
	ROUGHNESS = 0.08;
	SPECULAR = 0.8;
	EMISSION = shallow_color.rgb * 0.04;
}
"""
	var material := ShaderMaterial.new()
	material.shader = shader
	river.material_override = material
	river.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_props_root.add_child(river)

	var bank := MeshInstance3D.new()
	var bank_plane := PlaneMesh.new()
	bank_plane.size = Vector2(178.0, 22.0)
	bank.mesh = bank_plane
	bank.rotation.y = PI * 0.25
	bank.position.y = 0.006
	var bank_material := StandardMaterial3D.new()
	bank_material.albedo_texture = load("res://assets/textures/cliff_side_Diffuse.jpg")
	bank_material.albedo_color = Color(0.5, 0.48, 0.42)
	bank_material.roughness = 1.0
	bank_material.uv1_scale = Vector3(18, 3, 1)
	bank.material_override = bank_material
	bank.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_props_root.add_child(bank)

	var bridge := MeshInstance3D.new()
	var bridge_box := BoxMesh.new()
	bridge_box.size = Vector3(9.0, 0.05, 24.0)
	bridge.mesh = bridge_box
	bridge.rotation.y = PI * 0.25
	bridge.position = Vector3(0, 0.055, 0)
	var bridge_material := StandardMaterial3D.new()
	bridge_material.albedo_texture = load("res://assets/textures/cliff_side_Diffuse.jpg")
	bridge_material.albedo_color = Color(0.72, 0.68, 0.6)
	bridge_material.roughness = 0.9
	bridge.material_override = bridge_material
	_props_root.add_child(bridge)

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
		var scene: PackedScene = pine if i % 3 != 1 else broadleaf
		var height := rng.randf_range(7.0, 12.5)
		var tree := ModelUtils.fit_scene(scene, height, height * 1.1)
		tree.position = Vector3(pos.x, 0.0, pos.y)
		tree.rotation.y = rng.randf_range(0.0, TAU)
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
		var height := rng.randf_range(5.0, 8.0)
		var tree := ModelUtils.fit_scene(single_tree, height, height * 0.8)
		tree.position = Vector3(pos.x, 0.0, pos.y)
		tree.rotation.y = rng.randf_range(0.0, TAU)
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
		if _river_distance(pos) > 16.0 and i % 2 == 0:
			continue
		var height := rng.randf_range(1.2, 2.8)
		var rock := ModelUtils.fit_scene(rock_group if i % 3 == 0 else rock_single, height, height * 2.2)
		rock.position = Vector3(pos.x, 0.0, pos.y)
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
		mountain.position = Vector3(pos.x, 0.0, pos.y)
		mountain.rotation.y = rng.randf_range(0.0, TAU)
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

func _sync_units(snapshot: Dictionary, delta: float) -> void:
	if snapshot.is_empty():
		return
	_local_entity_id = -1
	var seen_ids := {}
	for entity in snapshot.get("entities", []):
		var entity_type := str(entity.get("type", ""))
		if entity_type != "hero" and entity_type != "minion":
			continue
		var entity_id := int(entity.get("id", -1))
		seen_ids[entity_id] = true
		if entity_type == "hero" and str(entity.get("owner_id", "")) == local_owner:
			_local_entity_id = entity_id
		var alive := bool(entity.get("alive", false))
		var view: UnitVisual = _views.get(entity_id)
		if view == null:
			if entity_type == "minion" and not alive:
				continue
			if entity_type == "hero" or alive:
				view = _acquire_unit_view(entity)
				_views[entity_id] = view
		if view == null:
			continue
		# jitter buffer 模式下调用方显式给出上一格位置（可能跳过多格）。
		var prev_xy: Vector2 = _render_prev_positions.get(entity_id, Vector2(INF, INF))
		view.set_snapshot(entity, delta, _render_alpha, prev_xy)
		view.process_visual(delta)

	# 回收死亡完成或在快照中移除的小兵，杜绝死兵泄漏与每帧遍历浪费
	var to_recycle: Array[int] = []
	for eid in _views:
		var view: UnitVisual = _views[eid]
		if view != null and view.kind == "minion":
			if view.can_recycle() or not seen_ids.has(eid):
				to_recycle.append(eid)
	for eid in to_recycle:
		var view: UnitVisual = _views[eid]
		_views.erase(eid)
		if view:
			view.recycle()
			var pool := _minion_pool_blue if view.team == "blue" else _minion_pool_red
			if pool.size() < MINION_POOL_LIMIT:
				pool.append(view)
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
		view.setup("hero", team, str(entity.get("hero_type", "blade")), str(entity.get("name", "英雄")), is_local)
	else:
		view.setup("minion", team, "minion", "", false)
	_units_root.add_child(view)
	view.position = Vector3(float(entity.get("x", 0.0)), 0.0, float(entity.get("y", 0.0)))
	view.set_snapshot(entity, 1.0)
	return view

func _sync_structures(snapshot: Dictionary, initial: bool) -> void:
	if snapshot.is_empty():
		return
	for entity in snapshot.get("entities", []):
		var entity_type := str(entity.get("type", ""))
		if entity_type != "tower" and entity_type != "base":
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
	else:
		model = ModelUtils.fit_scene(load(ENV_DIR + "WatchTower_SecondAge_Level3.glb"), 7.3, 3.8)
		bar_height = 8.5
		bar_width = 2.7
		ring_radius = 2.5
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
		crystal.position = Vector3(0, 7.0, 0)
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
	var fill := _add_structure_bar(root, bar_height, bar_width, team_color)
	return {"root": root, "bar": fill[0], "bar_mat": fill[1], "bar_width": bar_width, "spin": spin_node}

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
	for event in events:
		if not (event is Dictionary):
			continue
		match str(event.get("type", "")):
			"attack":
				var attacker: UnitVisual = _views.get(int(event.get("hero", -1)))
				if attacker:
					attacker.play_attack()
			"skill":
				_handle_skill_event(event)
			"hit":
				_handle_hit_event(event)
			"death":
				_handle_death_event(event)
			"tower_destroyed":
				var pos := Vector3(float(event.get("x", 0.0)), 1.0, float(event.get("y", 0.0)))
				_explosion(pos, RED if str(event.get("team", "red")) == "red" else BLUE, 32)
				hud.add_feed("防御塔被摧毁", GameTheme.GOLD_LIGHT)
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

		if not _first_blood:
			_first_blood = true
			hud.announce("第一滴血", GameTheme.GOLD_LIGHT, 2.0)
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

func _spawn_ring(pos: Vector3, color: Color, from_scale: float, to_scale: float, duration: float) -> void:
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
	material.albedo_color = Color(color.r, color.g, color.b, 0.65)
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
