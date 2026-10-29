extends Node3D

signal exit_requested
# 分帧构建进度：0..1 与阶段说明，交给外层加载遮罩显示。
signal build_progress(value: float, text: String)
signal ready_for_battle

const MatchSim = preload("res://sim/match_sim.gd")
const MapData = preload("res://sim/map_data.gd")
const MapLayout = preload("res://sim/map/map_layout.gd")
const HeroDefs = preload("res://sim/hero_defs.gd")
const ModelUtils = preload("res://scripts/game/model_utils.gd")
const TowerVisual = preload("res://scripts/game/tower_visual.gd")
const TerrainBuilder = preload("res://scripts/game/terrain_builder.gd")
const ArenaLook = preload("res://scripts/game/arena_look.gd")
const GrassField = preload("res://scripts/game/grass_field.gd")
const BushField = preload("res://scripts/game/bush_field.gd")
const UnitVisual = preload("res://scripts/game/unit_visual.gd")
const GameHUD = preload("res://scripts/ui/game_hud.gd")
const GameTheme = preload("res://scripts/ui/game_theme.gd")
const InputAssist = preload("res://scripts/game/input_assist.gd")
const MatchMenu = preload("res://scripts/game/match_menu.gd")
const MapView = preload("res://scripts/game/map_view.gd")
const LaneRoad = preload("res://scripts/game/lane_road.gd")
const BushFeedback = preload("res://scripts/game/bush_feedback.gd")
const ChannelFeedback = preload("res://scripts/game/channel_feedback.gd")
const ChannelFx = preload("res://scripts/game/channel_fx.gd")
const SkillFx = preload("res://scripts/game/skill_fx.gd")
const AudioCues = preload("res://scripts/game/audio_cues.gd")
const AudioDirector = preload("res://scripts/game/audio_director.gd")
const HitStopManager = preload("res://scripts/view/hit_stop_manager.gd")
const CameraFocus = preload("res://scripts/game/camera_focus.gd")
const CameraEdge = preload("res://scripts/game/camera_edge.gd")
const ClientPrediction = preload("res://net/client_prediction.gd")
const BushEye = preload("res://scripts/game/bush_eye.gd")
const DebugPanelScript = preload("res://scripts/ui/debug_panel.gd")
const BAR_SHADER := preload("res://shaders/billboard_bar.gdshader")
const CAMP_SIGIL_SHADER := "res://shaders/camp_sigil.gdshader"

const ENV_DIR := "res://assets/environment/"
# 桥体尺寸。三路各一座：中路在河心（地图中心），上下路各在自己 L 形的拐角处跨河。
# 桥面是**兵线路径截出来的一段连续带**，不是一块旋转 45° 的直板 ——
# 边路的跨河点正好压在上路的圆角上，直板会把桥端斜着切进路面，护栏从路中间断开。
const BRIDGE_WIDTH := 10.6
const BRIDGE_SPAN_MID := 26.0
const BRIDGE_SPAN_EDGE := 20.0
# 桥面高出路面 2cm：路面最上层 0.055，桥面 0.075。压低会被路面盖住，
# 抬高就会在桥头出现一道台阶。
const BRIDGE_DECK_Y := 0.075
# 桥头接坡：把桥面从 10.6m 收到路肩 9.75m，高度压到 0.05（低于路面 0.055 的一半），
# 接坡尾端直接沉进路面，接缝只有一条材质线，没有台阶。
const BRIDGE_APPROACH := 1.6
const BRIDGE_APPROACH_Y := 0.05
# 护栏：0.42m 高的矮栏，沿路缘弯过去；两端各一根门柱收口。
# 偏移 4.6 贴着桥面外沿（半宽 5.3）留 0.7m 走边，同时避开路面石墩（4.31）。
const BRIDGE_RAIL_OFFSET := 4.6
const BRIDGE_RAIL_WIDTH := 0.34
const BRIDGE_RAIL_HEIGHT := 0.42
const BRIDGE_RAIL_STEP := 1.7
const BRIDGE_RAIL_INSET := 0.9
const BRIDGE_POST_SIZE := 0.56
const BRIDGE_POST_HEIGHT := 0.95
const BRIDGE_POST_CAP := 0.74
const BRIDGE_POST_CAP_HEIGHT := 0.16
# 桥墩顶面必须低于桥面：旧版顶面在 0.4m，俯视就是桥面上多了几个圆饼。
const BRIDGE_PIER_HEIGHT := 2.2
const BRIDGE_PIER_TOP := 0.0
# 桥侧裙板落到水面（-0.42）以下，斜俯视时桥缘才不会露出水缝。
const BRIDGE_SKIRT_BOTTOM := -0.65
const TICK := 1.0 / 30.0
const BASE_FOV := 42.0
# 焦段过渡速率（度/秒）。进出草丛只差约 3.4°，0.15s 左右走完。
const FOV_GLIDE_SPEED := 24.0

# 相机机位：注视点上方 0.94×zoom、朝自家基地反向退 0.76×zoom。
# 俯角 = atan(0.94 / 0.76) = 51.04°，地面上的位移沿纵深方向被压 sin(51°) = 0.778 ——
# 这就是「小地图上 45° 的路在主视角里只有 38°」的唯一来源，属于透视本身的性质。
const CAMERA_PITCH_UP := 0.94
const CAMERA_PITCH_BACK := 0.76
# 镜头对准的是地面上方 0.55 的高度（英雄的上半身），所以机位虽然在地面之上，
# 视线并不是垂直下压 —— 少了这 0.55，英雄会贴在画面的最下沿。
const CAMERA_LOOK_HEIGHT := 0.55
# 相机缩放的滑行速率（zoom 单位/秒）。滚轮一次 ±2，约 0.14s 走完，匀速不突兀。
const ZOOM_GLIDE_SPEED := 14.0
# 小地图定位时注视点的滑行速率（世界单位/秒）。要跟得上手指拖动，
# 所以比相机缩放快得多：跨半张图（约 58m）0.3s 走完。
const CAMERA_FOCUS_GLIDE_SPEED := 200.0
# 松手归位的速率。比观察更快 —— 「不按了立刻回到自己的画面」，
# 跨整张图（116m）0.36s，体感是「唰一下回来」而不是「慢慢飘回去」。
const CAMERA_FOCUS_RETURN_SPEED := 320.0
# 远山挡视野：相机贴到地图边界时（尤其拉远镜头）会钻进山体，半个屏幕被岩壁糊住。
# 远山只是布景 —— 相机进入或贴近某座山的包围盒时整座隐藏，离远后恢复。
const BACKDROP_HIDE_MARGIN := 20.0
# 客机渲染相对服务端的固定延迟。要略大于一个快照周期（服务端 10Hz ≈ 0.1s），
# 否则缓冲里凑不齐两格；取 0.16 给网络抖动留余量。
const NET_RENDER_DELAY := 0.16
# 快照缓冲深度上限（约 1.6s）。只做兜底，正常情况远不会填满。
const NET_BUFFER_LIMIT := 16
# 地面射程环的高度。要略高于路面（0.022）与河水（0.012），避免被 z-fighting 吃掉。
const RANGE_RING_Y := 0.06
# 防御塔攻击范围圈：默认**不画**。整张图十几座塔同时铺满射程圈就是一片蓝雾，
# 只有敌方小兵/英雄真的踏进射程（塔马上要开火）时才亮起；
# 本地英雄在敌方塔下时整圈转红，这才是「危险」的那一瞬。
const TOWER_RING_IDLE_ALPHA := 0.16
const TOWER_RING_ACTIVE_ALPHA := 0.36
const TOWER_RING_WARN_ALPHA := 0.55
const TOWER_RING_WARN_COLOR := Color(1.0, 0.2, 0.16)
# --- 英雄普攻表现（2026-10-28）---------------------------------------------
# 症状：按普攻只有一次骨骼动作，目标身上四颗小火星，打起来「看不出谁在出手」。
# 现在近战英雄挥出一片新月刀光（走池，见 _slash_pool），远程英雄打一条弹道。
# 三种近战（苍刃 2.0 / 铁壁 2.1 / 墨鸦 2.0）与两种远程（星璃 5.6 / 翎羽 6.4）
# 用 HERO_RANGED_REACH 分档，取的是 hero_defs 的 attack_range，不另写一份数值。
const HERO_RANGED_REACH := 4.0
const HERO_SLASH_ARC_DEG := 118.0
# 内沿半径（相对外沿）：1.0 = 实心扇形。0.62 太厚，2 米半径下是一片白饼；
# 0.78 才读成「一道月牙刀光」。
const HERO_SLASH_INNER := 0.78
# 刀光高度取胸口（英雄身高 2.7，剑是举在肩上的）。0.95 那一版在 51° 俯角下
# 正好压在脚面上，看着像「地上铺了张纸」。
const HERO_SLASH_HEIGHT := 1.35
# 刀光半径只吃到攻击距离的 92%：吃到 112% 时它比英雄还宽，
# 画面里是一把「比自己还大的刀」。
const HERO_SLASH_REACH_RATIO := 0.92
const HERO_SLASH_GROW := 1.1
const HERO_SLASH_DURATION := 0.18
const HERO_SHOT_DURATION := 0.16
const HERO_SHOT_HEIGHT := 1.15
const HERO_SHOT_RADIUS := 0.16
# 塔的视觉体型：51° 俯角下塔越宽，站在塔后（相机远侧）的英雄被盖得越狠。
# 程序化石塔（TowerVisual）本身就按「细而尖」建模：最高 8.95m、最宽 2.76m，
# 宽高比 ≈ 3.2。宽高比契约见 tests/test_map_presentation.gd::test_tower_model_is_slim_and_tall。
# 塔冠核心高度同时是塔光束的枪口高度，两边不能各写一个数。
const TOWER_CRYSTAL_HEIGHT := 8.2
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
# 主机每 tick 构建的完整世界快照。10Hz 广播直接复用它再按队伍过滤，
# 不再为广播单独重建一份（30Hz 本地 + 10Hz 广播 = 每秒 40 次全量构建）。
var _last_world_shot: Dictionary = {}
var _views: Dictionary = {}
var _structure_views: Dictionary = {}
var _units_root: Node3D
var _structures_root: Node3D
var _effects_root: Node3D
# 本局一共消费过多少次技能特效请求。用于测试「事件有没有接到表现层」，
# 也方便排查「技能放出去没画面」这类静默失效。
var skill_fx_count := 0
# 粒子池空了导致「这一簇粒子没放出来」的次数。池是固定大小的，
# 团战同时开几个大就会静默丢掉后面几簇 —— 计数器让这件事可测，而不是靠肉眼发现。
var particle_bursts := 0
# 池空时抢占旧簇的次数（抢占是有意的：掐掉快消失的那簇，保住刚放的那簇）。
var particle_steals := 0
var _props_root: Node3D
# 营地/首领坑地面的符阵材质，按 camp / pit id 索引；野怪死亡时把它们调暗。
var _sigil_shader: Shader = null
var _camp_sigils: Dictionary = {}
var _camp_sigil_active: Dictionary = {}
# 营地地面重生牌：野怪死亡后显示「名称 + 剩余秒数」，活着时隐藏。
var _camp_labels: Dictionary = {}
# 全图石壁共用的一份材质（野区墙 + 边界墙 + 压顶石）。懒建，因为
# 「建场景」和「渲染」都可能在无材质需求时被单独调用（测试里就是这样）。
var _stone_material: ShaderMaterial = null
# 墙石批处理：几百块 Rock.glb 如果逐个节点画，移动端光是 draw call 和
# 阴影 pass 就会把帧率吃掉。这里先收集实例数据，最后合成 1~2 个 MultiMesh。
var _rock_batch_specs: Array[Dictionary] = []
var _rock_mesh_cache: Dictionary = {}
# 地形实例：布景（山 / 树 / 石头）要靠它取实际地面高度，
# 否则摆件会悬在坡上或陷进土里。
var _terrain = null
# 远山布景及其世界包围盒：相机靠近时整座隐藏，避免山体挡住英雄（见 backdrop_hidden）。
var _backdrop_mountains: Array[Dictionary] = []
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
# 开发者调试（F3）。时间倍率只作用于主机模拟，表现层仍按真实时间走。
var _debug_panel = null
var _debug_time_scale := 1.0
var _debug_paused := false
var _debug_reveal := false
var _debug_no_hit_stop := false
var _debug_no_shake := false
var _debug_tick_ms := 0.0
var _debug_snapshot_ms := 0.0
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
# 普攻也要锁存：联机输入 20Hz 上报，一次 30ms 的点击可能整段落在两次上报之间，
# 只按「当前是否按住」采样就会静默吞掉这一下（技能早已是锁存语义）。
var _queued_attack := false
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
# 正在飘的伤害数字，队首最老 —— 池空时抢占，绝不在战斗中 new Label3D。
var _damage_labels_active: Array[Label3D] = []
var _hit_particles_pool: Array[GPUParticles3D] = []
# 正在播放的粒子节点，队首最老 —— 池空时从这头抢。
var _hit_particles_active: Array[GPUParticles3D] = []
# 普攻弹道（小兵弹丸 / 近战刀光）与塔的光束都走池：
# 三路兵线同时交火时每秒十几次攻击，不能每次 new + queue_free。
var _tracer_pool: Array[MeshInstance3D] = []
var _tracer_active: Array[MeshInstance3D] = []
var _lance_pool: Array[MeshInstance3D] = []
var _lance_active: Array[MeshInstance3D] = []
# 命中/技能范围环：以前每次 new TorusMesh + StandardMaterial3D + queue_free，
# 团战里一秒十几次就是十几次材质创建。池化后只改颜色和缩放。
var _ring_pool: Array[MeshInstance3D] = []
var _ring_active: Array[MeshInstance3D] = []
# 英雄普攻刀光：12 片新月。5v5 同时开打时每秒十几次普攻，
# 每次 new SurfaceTool 提交网格 + 新建材质就等于把硬规则 4 重新破掉。
var _slash_pool: Array[MeshInstance3D] = []
var _slash_active: Array[MeshInstance3D] = []
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
	_build_lanes()
	_build_river()
	await _next_frame()

	_emit_build(0.28, "种下峡谷植被")
	await _build_scenery()
	_build_grass_tufts()
	_build_map_features()
	_build_boundary_walls()
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
	_build_debug_panel()
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

func _debug_enabled() -> bool:
	# 正式包默认不开；调试构建、`--dev` 启动参数、或配置显式打开时才有 F3。
	if OS.is_debug_build():
		return true
	if OS.get_cmdline_args().has("--dev"):
		return true
	return bool(config.get("debug_panel", false))

func _build_debug_panel() -> void:
	if not _debug_enabled():
		return
	_debug_panel = DebugPanelScript.new()
	_debug_panel.name = "DebugPanel"
	add_child(_debug_panel)
	_debug_panel.setup(self)

# --- 调试面板接口 -----------------------------------------------------------
# 面板只负责发命令，所有校验都在这里：客机没有 sim，一律静默忽略。

func debug_metrics() -> Dictionary:
	var online: bool = session != null and session.has_method("is_online") and session.is_online()
	var mode_text := "单机"
	if online:
		mode_text = "主机" if authoritative else "客机"
	var entities: Array = current_snapshot.get("entities", [])
	return {
		"mode": mode_text,
		"time": float(current_snapshot.get("time", 0.0)),
		"fps": Engine.get_frames_per_second(),
		"entities": entities.size(),
		"tick_ms": _debug_tick_ms,
		"snapshot_ms": _debug_snapshot_ms,
		"network": "在线" if online else "本地",
		"buffer": _snapshot_buffer.size(),
		"authoritative": authoritative,
		"time_scale": _debug_time_scale,
		"paused": _paused or _debug_paused,
	}

func debug_set_time_scale(value: float) -> void:
	_debug_time_scale = clampf(value, 0.1, 8.0)

func debug_set_paused(value: bool) -> void:
	_debug_paused = value
	if value:
		_accumulator = 0.0

func debug_step() -> void:
	if not authoritative or sim == null or sim.ended:
		return
	var events: Array = []
	sim.tick(TICK)
	events.append_array(sim.consume_events())
	_accumulator = 0.0
	_last_world_shot = sim.snapshot()
	current_snapshot = _last_world_shot if _debug_reveal else sim.snapshot_for(local_team, null, _last_world_shot)
	_process_events(events)
	if session != null and session.has_method("is_online") and session.is_online():
		_pending_events.append_array(events)

func debug_set_god(value: bool) -> void:
	_debug_set_local_flag("debug_god", value)

func debug_set_infinite_mana(value: bool) -> void:
	_debug_set_local_flag("debug_infinite_mana", value)

func debug_set_no_cooldown(value: bool) -> void:
	_debug_set_local_flag("debug_no_cooldown", value)

func debug_add_gold(amount: int) -> void:
	if sim != null and authoritative:
		sim.debug_add_gold(local_owner, amount)

func debug_level_up() -> void:
	if sim != null and authoritative:
		sim.debug_level_up(local_owner)

func debug_heal() -> void:
	if sim != null and authoritative:
		sim.debug_heal(local_owner)

func debug_teleport_to_cursor() -> void:
	if sim == null or not authoritative:
		return
	var target := _touch_aim if touch_mode and _touch_aim_valid else _mouse_ground
	if not touch_mode and not _mouse_valid:
		return
	sim.debug_teleport_hero(local_owner, target)

func debug_clear_minions() -> void:
	if sim != null and authoritative:
		sim.debug_clear_minions()

func debug_respawn_camps() -> void:
	if sim != null and authoritative:
		sim.debug_respawn_monsters()

func debug_set_reveal(value: bool) -> void:
	if sim == null or not authoritative:
		_debug_reveal = false
		return
	_debug_reveal = value
	if value:
		if _last_world_shot.is_empty():
			_last_world_shot = sim.snapshot()
		current_snapshot = _last_world_shot
	else:
		current_snapshot = sim.snapshot_for(local_team, null, _last_world_shot if not _last_world_shot.is_empty() else null)

func debug_set_no_hit_stop(value: bool) -> void:
	_debug_no_hit_stop = value

func debug_set_no_shake(value: bool) -> void:
	_debug_no_shake = value

func _debug_local_hero() -> Dictionary:
	if not authoritative or sim == null:
		return {}
	return sim.get_hero_by_player(local_owner)

func _debug_set_local_flag(key: String, value: bool) -> void:
	var hero := _debug_local_hero()
	if hero.is_empty():
		return
	hero[key] = value

# 所有顿帧都从这里走：关闭顿帧时连触发都不该发生，否则冻结计时器仍会拦下一帧的视觉同步。
func _trigger_hit_stop(freeze_duration: float, shake_strength: float = 0.3) -> void:
	if _debug_no_hit_stop:
		return
	_hit_stop.trigger_hit_stop(freeze_duration, shake_strength)

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
	if value:
		_queued_attack = true

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
		elif mouse.pressed and mouse.button_index == MOUSE_BUTTON_RIGHT:
			# 右键按下即锁存一次普攻：即使松手发生在下一次 20Hz 上报之前也不丢。
			_queued_attack = true
		elif mouse.pressed and not touch_mode and mouse.button_index == MOUSE_BUTTON_LEFT:
			# 左键点地 = 走到那个点。用事件自带的坐标而不是缓存的 _mouse_ground，
			# 否则「先点、鼠标同一帧还在上一帧位置」时点偏一点点。
			if _project_ground(mouse.position):
				_set_move_target(_mouse_ground)
	if event is InputEventKey:
		var key := event as InputEventKey
		if key.pressed and not key.echo and key.keycode == KEY_F3:
			if _debug_panel != null:
				_debug_panel.toggle()
				get_viewport().set_input_as_handled()
		elif key.pressed and not key.echo and key.keycode == KEY_ESCAPE:
			_toggle_pause()
		elif key.pressed and not key.echo and key.keycode == KEY_SPACE:
			_queued_attack = true

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
	# 顿帧只冻结表现层。以前这里直接 return，把 sim.tick 和 10Hz 快照广播一起停掉：
	# 一次击杀 90ms 的顿帧刚好抽掉一格快照，客机 jitter buffer 欠载就会「回拉」。
	# 现在还照常推进模拟、消费输入、发送网络包，只在最后跳过视觉同步。
	var frozen := _hit_stop.is_frozen()
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
		# 事件必须逐 tick 取走。两个理由：
		# ① 一帧可能补跑多个 tick（卡顿后追帧），只在循环外读一次快照会漏掉前面 tick 的
		#    击杀 / 结算事件，表现静默丢失；
		# ② 对局结束后 tick 不再推进、也不再清空 state.events，不取走的话 match_end 会留在
		#    那里被每帧重放（顿帧常驻 + 震屏每帧重算），结算界面就一直在抖。
		var frame_events: Array = []
		# 调试暂停只停模拟，不改输入采集与网络收发：单步之后立即能看到下一 tick 的画面。
		if not _debug_paused:
			_accumulator += minf(delta, 0.1) * _debug_time_scale
		var guard := 0
		var tick_count := 0
		var tick_started := Time.get_ticks_usec()
		while _accumulator >= TICK and guard < 5:
			sim.tick(TICK)
			frame_events.append_array(sim.consume_events())
			_accumulator -= TICK
			guard += 1
			tick_count += 1
		if tick_count > 0:
			_debug_tick_ms = float(Time.get_ticks_usec() - tick_started) / 1000.0 / float(tick_count)
			var snapshot_started := Time.get_ticks_usec()
			_last_world_shot = sim.snapshot()
			# 全图视野是纯本机作弊：只换本地这份快照，广播仍按队伍过滤。
			if _debug_reveal:
				current_snapshot = _last_world_shot
			else:
				current_snapshot = sim.snapshot_for(local_team, null, _last_world_shot)
			_debug_snapshot_ms = float(Time.get_ticks_usec() - snapshot_started) / 1000.0
			_process_events(frame_events)
			# 输入只在真正被模拟消费后清空；否则高帧率下会吞掉刚按下的技能。
			_consume_skill_queue()
			if session != null and session.has_method("is_online") and session.is_online():
				# 广播用原始事件；按队伍过滤在广播时由 events_for 逐队做，
				# 本地视角已经消化过的事件不影响下发给客机的副本。
				_pending_events.append_array(frame_events)
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
				# 状态与事件分两路：状态走不可靠（丢了下一格覆盖），
				# 事件走可靠（丢了就永远没有播报/结算曲/特效）。
				# 世界快照只构建一次，两个队伍复用同一份再各自过滤：5v5 下这是每 10Hz
				# 最大的一笔分配，按队伍重建等于白跑一遍全实体 + 经济面板 + 河道。
				var world_shot: Dictionary = _last_world_shot if not _last_world_shot.is_empty() else sim.snapshot()
				session.broadcast_team_snapshots(func(team: String) -> Dictionary:
					return sim.snapshot_for(team, null, world_shot)
				)
				session.broadcast_team_events(
					func(team: String) -> Array:
						return sim.events_for(team, outgoing_events),
					float(sim.state.get("time", 0.0))
				)
	elif session != null:
		_gather_input()
		_update_local_prediction(delta)
		_input_timer += delta
		if _input_timer >= 0.05 or _local_input.skill_q or _local_input.skill_w or _local_input.skill_e or _local_input.skill_r or _local_input.summoner or _local_input.attack or _local_input.recall or _local_input.teleport or _local_input.buy_item != "" or _local_input.sell_slot >= 0:
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

	if frozen:
		# 模拟、输入与网络包已经在本帧推进，这里只冻结画面（位置/动画/HUD）。
		_update_camera(delta, false)
		return

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
		# 屏幕坐标必须先送：锁定条要按这一帧的机位画线，
		# 晚一步就会看到线头领先目标一帧（镜头跟随时尤其明显）。
		hud.set_enemy_screens(_enemy_screen_positions())
		hud.update_snapshot(current_snapshot)
		hud.set_camera_view(camera_view_rect())

## 敌方英雄的屏幕投影。只有真机需要（锁定条的连线要落到人身上）。
##
## 相机背后的点会让 unproject_position 翻到屏幕另一侧，所以先用 is_position_behind
## 剔掉 —— 否则锁定一个人跑到身后，屏幕上会出现一根横穿整个画面的线。
func _enemy_screen_positions() -> Dictionary:
	var out := {}
	if camera == null or not touch_mode:
		return out
	for entity in current_snapshot.get("entities", []):
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
		# 抬到胸口：脚底点落在地面上，靠近地形边缘时线会指到脚下的地砖。
		var world := Vector3(pos.x, 1.6, pos.y)
		if camera.is_position_behind(world):
			continue
		out[entity_id] = camera.unproject_position(world)
	return out

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
	_local_input.attack = Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT) or Input.is_key_pressed(KEY_SPACE) or _queued_attack
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
	_local_input.attack = _touch_attack or _queued_attack
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
	_queued_attack = false
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
	# 入队供 jitter buffer 回放。data 是 NetProtocol.decode + sanitize 现场构出来的新字典，
	# 没有任何地方改写它，这里不再整份深拷贝 —— 5v5 每 100ms 一次，纯属白烧 CPU。
	_snapshot_buffer.append({
		"at": float(Time.get_ticks_msec()) / 1000.0,
		"st": float(data.get("time", 0.0)),
		"snapshot": data,
	})
	while _snapshot_buffer.size() > NET_BUFFER_LIMIT:
		_snapshot_buffer.pop_front()
	if not authoritative:
		_reconcile_local_prediction()
	if not build_complete:
		return
	_sync_structures(current_snapshot, false)
	if hud:
		hud.update_snapshot(current_snapshot)

# 离散事件走独立的可靠包，不和状态快照绑在一起（快照丢了下一格覆盖，
# 事件丢一次就是永久缺失）。进场构建期间到达的事件直接丢弃——场地还没建好，播不了。
func receive_events(events: Array) -> void:
	if not build_complete or events.is_empty():
		return
	_process_events(events)

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
	# 相机 yaw 必须和地图坐标轴对齐，屏幕才和小地图「同向」。
	#
	# 这里以前返回的是「蓝方基地 → 红方基地」那条对角线。后果是整张地图相对小地图
	# 被拧了 45°：小地图上是「横 / 斜 / 竖」三条路，进战场变成「45° 斜 / 正竖 / 45° 斜」——
	# 沿世界 X 轴铺的路在屏幕上成了 45° 斜线，而中路（世界 45°）反倒成了正竖线。
	#
	# 改成沿世界 Y 轴看：世界 +X 只落在屏幕水平方向、世界 +Y 只落在屏幕垂直方向。
	# 相机永远从自家基地往敌方半场看，所以蓝方朝 +Y、红方朝 -Y。
	# 真实 MOBA 也是这个口径（自家基地在画面下方，沿一条边往对面推）。
	return Vector3(0.0, 0.0, 1.0) if local_team == "blue" else Vector3(0.0, 0.0, -1.0)

func _camera_forward_2d() -> Vector2:
	var forward := _camera_forward()
	return Vector2(forward.x, forward.z)

# 机位（唯一的真身）。_build_camera 与 _update_camera 都走这里，
# 测试也直接调它来量「屏幕上这段路是多少度」。
static func camera_eye(target: Vector3, forward: Vector3, zoom: float) -> Vector3:
	return target + Vector3.UP * zoom * CAMERA_PITCH_UP - forward * zoom * CAMERA_PITCH_BACK

static func camera_placement(target: Vector3, forward: Vector3, zoom: float) -> Transform3D:
	var eye := camera_eye(target, forward, zoom)
	var look := target + Vector3(0.0, CAMERA_LOOK_HEIGHT, 0.0)
	return Transform3D(Basis.looking_at((look - eye).normalized(), Vector3.UP), eye)

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
	# 贴到边界墙时把注视点往地图中心推（见 camera_edge.gd）：
	# 不然相机跟着英雄越过城墙，近侧墙占掉小半屏、墙外草地也露一大块。
	# 这一步是纯几何映射（连续、无滞后），不会和 look_at 产生相位差。
	target = CameraEdge.inset(target, _zoom_current if _cam_initialized else zoom, _camera_forward())
	# 缩放单独平滑：位置跟随必须刚性（否则与 look_at 产生相位差而抖动），
	# 但 zoom 一步变 2.0 会让相机整体瞬移，观感上同样是「跳」。
	# 用恒定速率而非指数衰减——指数衰减「前快后慢」，首帧就会走掉一大截。
	if instant or not _cam_initialized:
		_zoom_current = zoom
		camera.fov = _camera_fov_target
	else:
		_zoom_current = move_toward(_zoom_current, zoom, delta * ZOOM_GLIDE_SPEED)
		camera.fov = move_toward(camera.fov, _camera_fov_target, delta * FOV_GLIDE_SPEED)
	var placement := camera_placement(target, _camera_forward(), _zoom_current)
	# 目标位置本身已是逐帧插值后的平滑轨迹，相机再叠一层 lerp 只会引入滞后；
	# 而朝向用的是即时 target，两者相位不一致正是移动时画面抖动的主因。
	# 改为刚性锁定：角色在屏幕上保持稳定，背景匀速滚动（MOBA 的标准手感）。
	# 抖动只加在机位上、不改朝向 —— 否则震屏会连带把地平线拧歪。
	var eye := placement.origin
	_cam_initialized = true
	if _debug_no_shake:
		# 关掉震屏时把存量也清干净：否则重新打开会先抖一下残留的旧震幅。
		_camera_shake = 0.0
	else:
		if _camera_shake > 0.0:
			_camera_shake = maxf(0.0, _camera_shake - delta * 1.8)
			eye += Vector3(randf_range(-_camera_shake, _camera_shake), randf_range(-_camera_shake, _camera_shake) * 0.4, 0.0)
		var stop_shake := _hit_stop.get_shake_offset()
		if stop_shake.length_squared() > 0.0:
			eye += Vector3(stop_shake.x, stop_shake.y * 0.4, 0.0)
	camera.transform = Transform3D(placement.basis, eye)
	_update_backdrop_visibility(camera.global_position)

# 相机是否已经进入（或贴近）某座远山的包围盒。
# 用包围盒最近点而不是中心点：山体很大，中心还在几十米外时近面已经贴到镜头。
static func backdrop_hidden(camera_pos: Vector3, box: AABB) -> bool:
	return box.grow(BACKDROP_HIDE_MARGIN).has_point(camera_pos)

# 贴边拉远时相机会钻进远山，半屏岩壁把英雄糊掉。远山只是布景：
# 相机靠近哪座就把哪座隐藏，离开后自动恢复；山体本身不动，远景轮廓保留。
func _update_backdrop_visibility(eye: Vector3) -> void:
	for entry in _backdrop_mountains:
		var node: Node3D = entry.node
		node.visible = not backdrop_hidden(eye, entry.box)

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
	camera.transform = camera_placement(target, _camera_forward(), _zoom_current)

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
	_set_local_bush_eye(_bush_hidden)
	if transition == "enter":
		_play_bush_enter_ring()
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
	_set_local_bush_eye(false)

# 头顶斜划眼只属于本地英雄：敌人进草不该在本地画面里冒标记（那就成透视了）。
func _set_local_bush_eye(value: bool) -> void:
	if _local_entity_id < 0:
		return
	var view: UnitVisual = _views.get(_local_entity_id)
	if view != null and view.kind == "hero":
		view.set_bush_hidden(value)

# 进草瞬间在草丛中心放一圈绿色扩散环：HUD 的文字在屏幕下方，
# 玩家视线还在人身上，这一圈是「你确实进草了」的第一反馈。
func _play_bush_enter_ring() -> void:
	var bush_id := str(_bush_feedback.bush_id)
	for bush in MapLayout.BUSHES:
		if str(bush.id) != bush_id:
			continue
		var radius := float(bush.radius)
		_spawn_ring(
			Vector3(float(bush.pos.x), 0.0, float(bush.pos.y)),
			Color(0.42, 0.96, 0.58),
			radius * 0.9,
			radius * 2.0,
			0.55,
			0.5
		)
		break

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
	# 大气 / 调色 / bloom 全部收在 arena_look.gd，这里只负责挂上去。
	# 参数散在函数里时没人能证明「bloom 真的开着」，抽出去才有测试能断言。
	ArenaLook.apply_environment(environment)
	world.environment = environment
	add_child(world)

	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	ArenaLook.apply_sun(sun)
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
	# 地形必须投影：关掉时山体和丘陵不会落到地面上，远山就是一排贴纸。
	# 手机端例外：地形是整张 5 万三角形的大网格，移动时把它塞进 shadow pass
	# 的代价远高于山体阴影带来的收益，移动端改由光照明暗表现起伏。
	ground.cast_shadow = (
		ArenaLook.TERRAIN_SHADOW
		if not OS.has_feature("mobile")
		else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	)
	_props_root.add_child(ground)

func _build_lanes() -> void:
	# 三层铺装都是由 LaneRoad 生成的连续带（绕序 / 宽度 / 拐角斜接都在那边保证）。
	# 这里只负责「哪三层、什么颜色」。宽度不写死：路宽的唯一来源是 MapData.LANE_HALF_WIDTH，
	# 这样「看到的路面」和「判定为兵线的范围」永远是同一条。
	var materials := _lane_materials()
	var half_widths: Array = LaneRoad.layer_half_widths()
	var heights: Array = LaneRoad.layer_heights()
	for lane in MapData.LANE_ORDER:
		var path: Array = MapView.lane_path(lane)
		for layer in range(half_widths.size()):
			var ribbon := _lane_ribbon(path, float(half_widths[layer]) * 2.0, float(heights[layer]), materials[layer])
			ribbon.name = "lane_%s_%s" % [str(lane), str(LaneRoad.LAYER_NAMES[layer])]
			_props_root.add_child(ribbon)
	_build_lane_edges()

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
		# 压在最上层铺装（0.055）之上，否则基地广场会被路面盖住一半。
		plaza.position = Vector3(base.x, 0.08, base.y)
		plaza.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_props_root.add_child(plaza)

func _lane_materials() -> Array:
	# 路肩 / 路面 / 中央走道，三层同一张贴图、由暗到亮。
	# 只靠亮度差就能在草地上读出「这是一条路」，不需要额外贴花。
	var tones := [
		Color(0.32, 0.28, 0.22),
		Color(0.70, 0.62, 0.47),
		Color(0.95, 0.90, 0.77),
	]
	var materials: Array = []
	for tone in tones:
		var material := StandardMaterial3D.new()
		material.albedo_texture = load("res://assets/textures/grass_path_2_Diffuse.jpg")
		material.albedo_color = tone
		material.roughness = 1.0
		materials.append(material)
	return materials

# 路缘石：一条路上每 5.5m 一对，贴着路缘落地。
# 用 MultiMesh：三路加起来一百多个石墩，逐个 MeshInstance3D 就是一百多个 draw call。
func _build_lane_edges() -> void:
	var stones: Array = []
	var width := LaneRoad.surface_half_width() * 2.0
	for lane in MapData.LANE_ORDER:
		var path: Array = MapView.lane_path(lane)
		var windows := _bridge_arc_windows(str(lane), path)
		for stone in LaneRoad.edge_stones(path, width):
			# 桥上有自己的护栏。路缘石继续铺过去会和护栏叠成两条边，
			# 俯视看就是桥面镶了一圈牙 —— 桥段的路缘石必须让位。
			if _inside_bridge_window(float(stone.get("arc", 0.0)), windows):
				continue
			# 角落广场同理：广场面（0.075）压在路缘石顶（0.18）之下，
			# 石头会从石面里冒出半截 —— 广场里的路缘石一律不铺。
			if MapLayout.inside_corner_plaza(stone.pos):
				continue
			stones.append(stone)
	if stones.is_empty():
		return
	# 路缘石也走石壁材质：原来直接用赭黄砂岩贴图 + 高亮 albedo，
	# 一排 2 米长的暖褐色石块俯视看过去就是「一圈木栅栏」，和环境里的石壁对不上。
	var stone := _wall_stone_material()
	var box := BoxMesh.new()
	box.size = Vector3(2.05, 0.20, 0.42)
	var instance := MultiMeshInstance3D.new()
	instance.name = "road_edges"
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = box
	multimesh.instance_count = stones.size()
	for index in stones.size():
		var stone_data: Dictionary = stones[index]
		var pos: Vector2 = stone_data.pos
		var basis := Basis(Vector3.UP, float(stone_data.get("yaw", 0.0)))
		multimesh.set_instance_transform(index, Transform3D(basis, Vector3(pos.x, 0.08, pos.y)))
	instance.multimesh = multimesh
	instance.material_override = stone
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_props_root.add_child(instance)

# 路缘石要给谁让位：中路的桥面（桥有自己的护栏）。
# 边路 2026-10-28 起没有桥了 —— 角落改由广场铺石，广场里的路缘石在
# _build_lane_edges 里按 inside_corner_plaza 单独剔除。
# 以前这里也给边路跨河点开窗口，拆桥之后那个窗口会把广场外 5 米的路缘石一起剃掉，
# 留下一条没有石沿的路。
func _bridge_arc_windows(lane: String, path: Array) -> Array:
	var entries: Array = []
	if lane == "mid":
		entries.append({"center": Vector2.ZERO, "half": BRIDGE_SPAN_MID * 0.5})
	var windows: Array = []
	var total := LaneRoad.path_length(path)
	for entry in entries:
		var center := LaneRoad.nearest_arc(path, entry.center)
		var half := float(entry.half) + BRIDGE_APPROACH + 0.5
		windows.append(Vector2(maxf(center - half, 0.0), minf(center + half, total)))
	return windows

func _inside_bridge_window(arc: float, windows: Array) -> bool:
	for window in windows:
		if arc >= window.x and arc <= window.y:
			return true
	return false

func _lane_ribbon(path: Array, width: float, height: float, material: Material) -> MeshInstance3D:
	var data := LaneRoad.ribbon(path, width, height)
	var points: PackedVector3Array = data.points
	var uvs: PackedVector2Array = data.uvs
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for index in points.size():
		st.set_normal(Vector3.UP)
		st.set_uv(uvs[index])
		st.add_vertex(points[index])
	var instance := MeshInstance3D.new()
	instance.mesh = st.commit()
	instance.material_override = material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return instance

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
	# 长边要贴着河道中心线（y = x）：局部 +X 经 -45° 旋转后指向 (1,0,1)。
	river.rotation.y = -PI * 0.25
	river.position.y = -0.42
	var shader := Shader.new()
	shader.code = """
shader_type spatial;
render_mode blend_mix, cull_disabled, depth_draw_opaque, specular_schlick_ggx;

uniform vec4 deep_color : source_color = vec4(0.06, 0.22, 0.26, 1.0);
uniform vec4 shallow_color : source_color = vec4(0.20, 0.44, 0.42, 1.0);
uniform float river_half = 9.0;
__OUTSIDE_UNIFORMS__

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	// 到河道中心线的距离决定深浅：河心深蓝、岸边浅青
	float d = abs(wpos.x - wpos.z) * 0.70710678;
	float t = clamp(d / river_half, 0.0, 1.0);

	// 两层不同频率、不同方向的水波，避免规则条纹
	float w1 = sin(wpos.x * 1.15 + TIME * 0.85) * cos(wpos.z * 0.95 - TIME * 0.62);
	float w2 = sin((wpos.x - wpos.z) * 2.1 - TIME * 1.35);
	float w3 = sin(wpos.x * 3.6 - wpos.z * 2.9 + TIME * 1.8);
	float ripple = w1 * 0.55 + w2 * 0.33 + w3 * 0.12;

	vec3 col = mix(deep_color.rgb, shallow_color.rgb, t * 0.72 + ripple * 0.04);

	// 岸边浅滩泡沫：只在水陆交界一条窄带
	float foam = smoothstep(0.93, 1.0, t + ripple * 0.03);
	col = mix(col, vec3(0.74, 0.82, 0.80), foam * 0.4);

	// 墙外那段河跟着地形一起退成远景：地形暗了水面不暗，
	// 会在墙外留一条亮青色的河，比不压暗更扎眼。
__OUTSIDE_APPLY__

	ALBEDO = col;
	// 提高不透明度：河床在阴影里是暗的，透出来会把整条河压成墨绿，
	// 同一个水色在不同角度看深浅差一大截。宁可少一点"见底"，也要颜色稳定。
	ALPHA = mix(0.97, 0.88, t);
	ROUGHNESS = 0.13;
	SPECULAR = 0.42;
	METALLIC = 0.0;
	// 用波纹扰动法线做假高光，GL Compatibility 下没有 SSR，这是最划算的一招
	NORMAL = normalize(vec3(ripple * 0.06, 1.0, ripple * 0.045));
}
"""
	var material := ShaderMaterial.new()
	shader.code = ArenaLook.apply_outside_fade(shader.code)
	material.shader = shader
	material.set_shader_parameter("river_half", MapData.RIVER_HALF_WIDTH)
	# 必须从 GDScript 传 Color：直接写 shader 里的 uniform 默认值会被当成线性色，
	# 输出时再转 sRGB 就整体提亮 —— 深蓝河水会渲染成亮青绿。
	# 原来的 (0.018, 0.095, 0.135) 在斜俯视全景里几乎是一片黑 —— 河道读成了一条深灰柏油路，
	# 和小地图上那条亮青色的河完全对不上。实测渲染像素只有 (20,50,55)，
	# 所以按比例提到 (45~60, 130~150, 140~160) 这一档，和小地图同色系。
	material.set_shader_parameter("deep_color", Color(0.110, 0.400, 0.470))
	material.set_shader_parameter("shallow_color", Color(0.260, 0.600, 0.600))
	# 和地形共用同一份墙外渐隐参数：水面伸到墙外的那一段必须一起退后。
	ArenaLook.bind_outside_fade(material, MapData.BOUNDS)
	river.material_override = material
	river.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_props_root.add_child(river)

	# 2026-10-28：边路的两个跨河角落改成**整块铺石**（玩家：「把这个角落全部铺上……
	# 不需要那个桥」）。角落桥不再建 —— 广场已经把跨河段整段盖住，
	# 桥的护栏/桥墩/接坡留在广场底下反而会露出半截。
	_build_bridge("mid", Vector2.ZERO, BRIDGE_SPAN_MID)
	_build_corner_plazas()

# 角落广场：两个空角落整块铺石（数据在 MapLayout.corner_plazas()）。
#
# 为什么广场面比路面高 2cm（0.075 对 0.055）：广场要盖住路面和河面，
# 只有压在路面之上才读得出「路从石台上过」；和桥面用同一个高度，
# 于是传送阵的抬升量（BRIDGE_DECK_Y + 0.02）两边通用。
#
# 为什么要裙板：广场内沿跨在水面上，没有裙板就是「一块悬空石板」——
# 和桥裙板同一个 bug、同一套口径（沉到 BRIDGE_SKIRT_BOTTOM，水面 -0.42 以下）。
#
# 材质关掉背面剔除：广场只有 6 个面片，省下的三角形远不如「绕序写反 → 整块看不见」
# 的风险值钱（桥面是几百段连续带，才必须逐面较真绕序）。
func _build_corner_plazas() -> void:
	var plazas: Array = MapLayout.corner_plazas()
	if plazas.is_empty():
		return
	var material := _bridge_deck_material()
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.uv1_scale = Vector3(1, 1, 1)
	for index in plazas.size():
		var plaza: Dictionary = plazas[index]
		var low: Vector2 = plaza.min
		var high: Vector2 = plaza.max
		var deck := MeshInstance3D.new()
		# 名字即接口：测试靠 CornerPlaza* 数广场、验「跨河点落在广场上」「广场够到墙脚」。
		deck.name = "CornerPlaza_%d" % index
		deck.mesh = _plaza_deck_mesh(low, high)
		deck.material_override = material
		ModelUtils.enable_shadows(deck, true)
		deck.set_meta("corner", plaza.corner)
		_props_root.add_child(deck)
		var skirt := MeshInstance3D.new()
		skirt.name = "corner_plaza_skirt_%d" % index
		skirt.mesh = _plaza_skirt_mesh(low, high)
		skirt.material_override = material
		ModelUtils.enable_shadows(skirt, true)
		_props_root.add_child(skirt)

func _plaza_deck_mesh(low: Vector2, high: Vector2) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# 与 lane_road.ribbon 同一套绕序约定：相机在上方，几何法线朝下 = 正面。
	var corners := [
		Vector3(low.x, BRIDGE_DECK_Y, low.y),
		Vector3(high.x, BRIDGE_DECK_Y, low.y),
		Vector3(high.x, BRIDGE_DECK_Y, high.y),
		Vector3(low.x, BRIDGE_DECK_Y, high.y),
	]
	var span := high - low
	# 每 4 米重复一次 cliff 贴图：uv1_scale 是 1，靠 UV 自己控制密度。
	var uvs := [
		Vector2(0.0, 0.0),
		Vector2(span.x * 0.25, 0.0),
		Vector2(span.x * 0.25, span.y * 0.25),
		Vector2(0.0, span.y * 0.25),
	]
	for triangle in [[0, 1, 2], [0, 2, 3]]:
		for corner in triangle:
			st.set_normal(Vector3.UP)
			st.set_uv(uvs[corner])
			st.add_vertex(corners[corner])
	return st.commit()

func _plaza_skirt_mesh(low: Vector2, high: Vector2) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var corners := [low, Vector2(high.x, low.y), high, Vector2(low.x, high.y)]
	for index in 4:
		var a: Vector2 = corners[index]
		var b: Vector2 = corners[(index + 1) % 4]
		var segment := a.distance_to(b)
		if segment < 0.0001:
			continue
		var direction := (b - a) / segment
		var outward := Vector2(direction.y, -direction.x)
		var normal := Vector3(outward.x, 0.0, outward.y)
		var quad := [
			Vector3(a.x, BRIDGE_DECK_Y, a.y),
			Vector3(b.x, BRIDGE_DECK_Y, b.y),
			Vector3(a.x, BRIDGE_SKIRT_BOTTOM, a.y),
			Vector3(b.x, BRIDGE_SKIRT_BOTTOM, b.y),
		]
		var quad_uv := [Vector2(0, 1), Vector2(1, 1), Vector2(0, 0), Vector2(1, 0)]
		for corner in [0, 1, 2, 1, 3, 2]:
			st.set_normal(normal)
			st.set_uv(Vector2(quad_uv[corner].x * segment * LaneRoad.UV_PER_METER, quad_uv[corner].y))
			st.add_vertex(quad[corner])
	return st.commit()

func _build_bridge(label: String, center: Vector2, span: float) -> void:
	# 桥面沿**看得见的那条兵线**走：边路的跨河点正好压在上路的圆角上，
	# 旧版三座桥都是同一块旋转 -45° 的直板 —— 桥端斜着切穿路面、护栏从路中间断开、
	# 桥角戳进草地。截一段兵线路径做连续带之后，桥端垂直于路面，接缝才读得通。
	var path: Array = LaneRoad.slice_around(MapView.lane_path(label), center, span * 0.5)
	if path.size() < 2:
		return
	var deck_material := _bridge_deck_material()
	var rail_material := _bridge_rail_material()

	var deck := MeshInstance3D.new()
	# 名字即接口：测试靠 Bridge* 数桥、验「跨河点真的落在桥面上」。
	deck.name = "Bridge" if label == "mid" else "Bridge_" + label
	deck.mesh = _bridge_deck_mesh(path)
	deck.material_override = deck_material
	ModelUtils.enable_shadows(deck, true)
	_props_root.add_child(deck)

	_build_bridge_skirt(label, path, deck_material)
	_build_bridge_approaches(label, path, deck_material)
	_build_bridge_rails(label, path, rail_material)
	_build_bridge_piers(label, path, rail_material)

func _bridge_deck_material() -> StandardMaterial3D:
	# 与石壁同一套 cliff AO：桥面和野区墙必须是同一种石头。
	var material := StandardMaterial3D.new()
	material.albedo_texture = load("res://assets/textures/cliff_side_AO.jpg")
	material.albedo_color = Color(0.48, 0.49, 0.50)
	material.normal_enabled = true
	material.normal_texture = load("res://assets/textures/cliff_side_nor_gl.jpg")
	material.normal_scale = 1.3
	material.roughness = 0.95
	# 连续带的 UV：横向 0..1 铺满桥宽，纵向按弧长（LaneRoad.UV_PER_METER）。
	# 这里按「接近方形」补比例，否则 AO 贴图会被拉成一条条。
	material.uv1_scale = Vector3(4.0, 3.0, 1.0)
	return material

func _bridge_rail_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_texture = load("res://assets/textures/cliff_side_AO.jpg")
	material.albedo_color = Color(0.56, 0.57, 0.58)
	material.normal_enabled = true
	material.normal_texture = load("res://assets/textures/cliff_side_nor_gl.jpg")
	material.normal_scale = 1.1
	material.roughness = 1.0
	material.uv1_scale = Vector3(2, 2, 2)
	return material

func _bridge_deck_mesh(path: Array) -> ArrayMesh:
	var data := LaneRoad.ribbon(path, BRIDGE_WIDTH, BRIDGE_DECK_Y)
	var points: PackedVector3Array = data.points
	var uvs: PackedVector2Array = data.uvs
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for index in points.size():
		st.set_normal(Vector3.UP)
		st.set_uv(uvs[index])
		st.add_vertex(points[index])
	return st.commit()

# 桥侧裙板：桥面是一条没有厚度的连续带，斜俯视能直接从边缘看进水缝里，
# 读成「一块飘在河上的石板」。两侧沿桥缘落一道到水面以下的石壁，桥才有截面。
func _build_bridge_skirt(label: String, path: Array, material: Material) -> void:
	var skirt := MeshInstance3D.new()
	skirt.name = "bridge_skirt_" + label
	skirt.mesh = _bridge_skirt_mesh(path)
	skirt.material_override = material
	ModelUtils.enable_shadows(skirt, true)
	_props_root.add_child(skirt)

func _bridge_skirt_mesh(path: Array) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var half := BRIDGE_WIDTH * 0.5
	for side in [-1.0, 1.0]:
		var edge: Array = LaneRoad.offset_path(path, side * half)
		for index in edge.size() - 1:
			var a: Vector2 = edge[index]
			var b: Vector2 = edge[index + 1]
			var segment := a.distance_to(b)
			if segment < 0.0001:
				continue
			var direction := (b - a) / segment
			# 左缘的外法线是 (-dy, dx)，右缘反过来。
			var outward: Vector2 = Vector2(-direction.y, direction.x) * float(side)
			var normal := Vector3(outward.x, 0.0, outward.y)
			var quad := [
				Vector3(a.x, BRIDGE_DECK_Y, a.y),
				Vector3(b.x, BRIDGE_DECK_Y, b.y),
				Vector3(a.x, BRIDGE_SKIRT_BOTTOM, a.y),
				Vector3(b.x, BRIDGE_SKIRT_BOTTOM, b.y),
			]
			var quad_uv := [Vector2(0, 1), Vector2(1, 1), Vector2(0, 0), Vector2(1, 0)]
			# 与 lane_road.ribbon 同一套绕序：桥外侧看到的面，右手定则法线朝桥内。左右缘相反。
			var order := [0, 1, 2, 1, 3, 2] if side > 0.0 else [0, 2, 1, 1, 2, 3]
			for corner in order:
				st.set_normal(normal)
				st.set_uv(Vector2(quad_uv[corner].x * segment * LaneRoad.UV_PER_METER, quad_uv[corner].y))
				st.add_vertex(quad[corner])
	return st.commit()

# 桥头接坡：桥面 10.6 宽收成路肩 9.75 宽，高度从 0.075 压到 0.05（沉进路面）。
# 没有这一块，桥面就是在路上被刀切出来的一块板。
func _build_bridge_approaches(label: String, path: Array, material: Material) -> void:
	var deck_half := BRIDGE_WIDTH * 0.5
	var road_half := float(LaneRoad.layer_half_widths()[0])
	for end in 2:
		var index := 0 if end == 0 else path.size() - 1
		var neighbor := 1 if end == 0 else path.size() - 2
		var center: Vector2 = path[index]
		var direction := (center - (path[neighbor] as Vector2)).normalized()
		var normal := Vector2(-direction.y, direction.x)
		var outer := center + direction * BRIDGE_APPROACH
		var ramp := MeshInstance3D.new()
		ramp.name = "ramp_%s_%d" % [label, end]
		ramp.mesh = _ramp_mesh(
			center + normal * deck_half,
			center - normal * deck_half,
			outer + normal * road_half,
			outer - normal * road_half
		)
		ramp.material_override = material
		ramp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_props_root.add_child(ramp)

func _ramp_mesh(inner_left: Vector2, inner_right: Vector2, outer_left: Vector2, outer_right: Vector2) -> ArrayMesh:
	var a_l := Vector3(inner_left.x, BRIDGE_DECK_Y, inner_left.y)
	var a_r := Vector3(inner_right.x, BRIDGE_DECK_Y, inner_right.y)
	var b_l := Vector3(outer_left.x, BRIDGE_APPROACH_Y, outer_left.y)
	var b_r := Vector3(outer_right.x, BRIDGE_APPROACH_Y, outer_right.y)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# 与 lane_road.ribbon 同一绕序：相机在上方，几何法线朝下 = 正面。
	# 但着色法线必须朝上 —— 用几何法线（朝下）会被当成背光面，整块接坡烤成黑的。
	for triangle in [[a_l, a_r, b_l], [a_r, b_r, b_l]]:
		var uv := 0.0
		for vertex in triangle:
			st.set_normal(Vector3.UP)
			st.set_uv(Vector2(uv, 0.0))
			st.add_vertex(vertex)
			uv += 1.0
	return st.commit()

# 护栏：沿路缘弯过去的一排矮栏，两端各一根门柱 + 石帽收口。
# 全部塞进一个 MultiMesh：三座桥一百多段，逐个 MeshInstance3D 就是一百多个 draw call。
func _build_bridge_rails(label: String, path: Array, material: Material) -> void:
	var transforms: Array[Transform3D] = []
	for side in [-1.0, 1.0]:
		var rail_path := LaneRoad.offset_path(path, side * BRIDGE_RAIL_OFFSET)
		var total := LaneRoad.path_length(rail_path)
		var start := BRIDGE_RAIL_INSET
		var finish := total - BRIDGE_RAIL_INSET
		if finish - start < 1.0:
			continue
		var steps := maxi(int(ceil((finish - start) / BRIDGE_RAIL_STEP)), 1)
		var step := (finish - start) / float(steps)
		for index in steps:
			var station := LaneRoad.sample(rail_path, start + step * (float(index) + 0.5))
			transforms.append(_box_transform(
				station.pos, station.dir,
				Vector3(BRIDGE_RAIL_WIDTH, BRIDGE_RAIL_HEIGHT, step + 0.06),
				BRIDGE_DECK_Y + BRIDGE_RAIL_HEIGHT * 0.5
			))
		for arc in [start, finish]:
			var station := LaneRoad.sample(rail_path, arc)
			transforms.append(_box_transform(
				station.pos, station.dir,
				Vector3(BRIDGE_POST_SIZE, BRIDGE_POST_HEIGHT, BRIDGE_POST_SIZE),
				BRIDGE_DECK_Y + BRIDGE_POST_HEIGHT * 0.5
			))
			transforms.append(_box_transform(
				station.pos, station.dir,
				Vector3(BRIDGE_POST_CAP, BRIDGE_POST_CAP_HEIGHT, BRIDGE_POST_CAP),
				BRIDGE_DECK_Y + BRIDGE_POST_HEIGHT + BRIDGE_POST_CAP_HEIGHT * 0.5
			))
	if transforms.is_empty():
		return
	var box := BoxMesh.new()
	box.size = Vector3.ONE
	var instance := MultiMeshInstance3D.new()
	instance.name = "bridge_rails_" + label
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = box
	multimesh.instance_count = transforms.size()
	for index in transforms.size():
		multimesh.set_instance_transform(index, transforms[index])
	instance.multimesh = multimesh
	# headless 的 dummy 渲染器读不回 MultiMesh 实例变换，测试只能靠这份记录量护栏走向。
	instance.set_meta("rail_transforms", transforms)
	instance.material_override = material
	ModelUtils.enable_shadows(instance, true)
	_props_root.add_child(instance)

# 单位盒 + 朝向 dir 的长轴（局部 +Z）。缩放写进基里，MultiMesh 才能共用一个盒子。
func _box_transform(pos: Vector2, heading: Vector2, size: Vector3, center_y: float) -> Transform3D:
	var yaw := atan2(heading.x, heading.y)
	var basis := Basis(Vector3.UP, yaw) * Basis.from_scale(size)
	return Transform3D(basis, Vector3(pos.x, center_y, pos.y))

func _build_bridge_piers(label: String, path: Array, material: Material) -> void:
	# 桥墩只做水下的支撑：顶面压到桥面以下，俯视时才不会在桥面上多出几个圆饼。
	var total := LaneRoad.path_length(path)
	var center := total * 0.5
	var index := 0
	for along in [-1.0, 1.0]:
		var station := LaneRoad.sample(path, center + along * total * 0.23)
		var normal := Vector2(-station.dir.y, station.dir.x)
		for side in [-1.0, 1.0]:
			var pos: Vector2 = station.pos + normal * 3.8 * side
			var pier := MeshInstance3D.new()
			pier.name = "bridge_pier_%s_%d" % [label, index]
			var cylinder := CylinderMesh.new()
			cylinder.top_radius = 0.52
			cylinder.bottom_radius = 0.66
			cylinder.height = BRIDGE_PIER_HEIGHT
			cylinder.radial_segments = 12
			pier.mesh = cylinder
			pier.material_override = material
			pier.position = Vector3(pos.x, BRIDGE_PIER_TOP - BRIDGE_PIER_HEIGHT * 0.5, pos.y)
			ModelUtils.enable_shadows(pier, true)
			_props_root.add_child(pier)
			index += 1

# 石壁材质只建一次。理由有两个：观感必须全图一致（一处石头一处木板是最刺眼的不一致），
# 以及几十段墙各建一个 ShaderMaterial 会让每个材质都要单独编译一次。
func _wall_stone_material() -> ShaderMaterial:
	if _stone_material == null:
		_stone_material = ArenaLook.rock_wall_material()
	return _stone_material

# 地图机制的可视化：墙体、草丛、野区营地与首领坑都从 MapLayout 取坐标，
# 与碰撞/视野/野怪刷新点严格同源，避免「看得见走不过去」或「打到空气墙」。
func _build_map_features() -> void:
	var marks := MapView.map_marks()
	var rng := RandomNumberGenerator.new()
	rng.seed = 90210
	var rock_scene: PackedScene = load(ENV_DIR + "Rock.glb")
	var stone := _wall_stone_material()

	_begin_rock_batch()
	for wall_index in marks.walls.size():
		var wall: Dictionary = marks.walls[wall_index]
		var a: Vector2 = wall.a
		var b: Vector2 = wall.b
		var center := (a + b) * 0.5
		var length := a.distance_to(b)
		var dir := (b - a) / maxf(length, 0.001)
		var perp := Vector2(-dir.y, dir.x)
		var yaw := -atan2(dir.y, dir.x)
		var wall_id := str(wall.get("id", "jungle"))
		# 每段墙一个相位：相邻墙的岩脊不会像复制粘贴一样同向摆。
		var phase := float(wall_index) * 1.63
		# 尺寸全部取自 sim 层：视觉厚度与碰撞厚度必须一致，否则会出现
		# 「看着贴得过去、身体却被挡住」的错位（薄渲染 / 厚碰撞）。
		# 现在这一层只是**基座**：直墙的方盒轮廓会被上面的岩脊打碎，
		# 但碰撞线仍然由它来封住。
		var barrier := MeshInstance3D.new()
		# 名字即接口：遮挡逻辑与测试都靠 wall_<id> 找到某一段石壁。
		barrier.name = "wall_" + wall_id
		var box := BoxMesh.new()
		box.size = Vector3(length, MapLayout.WALL_CORE_HEIGHT, MapLayout.WALL_THICKNESS)
		barrier.mesh = box
		barrier.material_override = stone
		barrier.position = Vector3(center.x, MapLayout.WALL_CORE_HEIGHT * 0.5, center.y)
		barrier.rotation.y = yaw
		ModelUtils.enable_shadows(barrier, true)
		_props_root.add_child(barrier)

		# 岩脊：沿墙铺一串高度/宽度/朝向都不同的 Rock.glb。基座顶边是直的，
		# 俯视一眼就读成方盒；岩脊把它压成一条起伏的山脊线。
		# 低石左右摆出 S 形、高石仍贴中线：墙面轮廓因此不是一条直线，
		# 但高石不会伸到英雄贴墙的位置。
		var ridge_count := maxi(3, int(round(length / MapLayout.WALL_ROCK_SPACING)))
		for i in ridge_count:
			var t := (float(i) + 0.5) / float(ridge_count)
			t = clampf(t + rng.randf_range(-0.22, 0.22) / float(ridge_count), 0.0, 1.0)
			var p := a.lerp(b, t)
			var wave := sin(t * PI * 2.4 + phase) * 0.26
			if i % 2 == 1:
				wave *= 0.2
			var lateral := perp * (wave + rng.randf_range(-0.05, 0.05))
			# 高低交替 + 随机带内抖动：纯随机在只有三块石头的短墙上会抽成一样高，
			# 俯视又变回一条直顶边。
			var band := rng.randf_range(0.05, 0.30) if i % 2 == 0 else rng.randf_range(0.70, 0.95)
			_queue_rock(
				p + lateral,
				lerpf(MapLayout.WALL_ROCK_MIN_HEIGHT, MapLayout.WALL_ROCK_MAX_HEIGHT, band),
				rng.randf_range(MapLayout.WALL_ROCK_WIDTH_MIN, MapLayout.WALL_ROCK_WIDTH_MAX),
				rng.randf_range(0.0, TAU),
				{"wall_id": wall_id, "kind": "ridge", "along": length * t}
			)
		# 墙脚乱石：比旧版更密（每 2 米一块），左右两侧交替、位置带抖动。
		# 这层是**低矮**的 0.8~1.4 米石块，不参与碰撞；它负责把墙脚那条
		# 数学直线啃成参差的石根，俯视时墙不会像一条摆正的盒子边。
		var rocks := maxi(4, int(round(length / 2.0)))
		for i in rocks:
			var p := a.lerp(b, (float(i) + 0.5) / float(rocks))
			var side := 1.0 if i % 2 == 0 else -1.0
			var out := perp * side * rng.randf_range(MapLayout.WALL_THICKNESS * 0.5 + 0.15, MapLayout.WALL_THICKNESS * 0.5 + 0.75)
			_queue_rock(
				Vector2(p.x + out.x + rng.randf_range(-0.45, 0.45), p.y + out.y + rng.randf_range(-0.45, 0.45)),
				rng.randf_range(0.8, 1.4),
				1.0,
				rng.randf_range(0.0, TAU),
				{"wall_id": wall_id, "kind": "footrock", "along": length * (float(i) + 0.5) / float(rocks)}
			)

	# 野区墙石：一批 MultiMesh，阴影关闭。高石/墙脚石都由基座与墙端石提供接地阴影，
	# 这一批数量最大，单独开阴影会让移动端的 shadow pass 翻倍。
	_flush_rock_batch("wall_rocks", rock_scene, stone, false)
	# 墙端露头：BoxMesh 的端面是绝对平的，一段墙看着像被刀切过。
	# 王者的野区石壁是「山体在两端露头」，所以每个墙端压一块**高过墙顶**的岩体，
	# 把平整端面吞进石头里。相邻两段墙靠得近时，两块露头自然合成一个山口。
	# 尺寸由 sim 层按「离兵线 / 营地还剩多少」算好，这里只负责摆。
	var wall_ends := MapLayout.wall_ends()
	for end_index in wall_ends.size():
		var entry: Dictionary = wall_ends[end_index]
		var end_radius: float = float(entry["radius"])
		# 空间不够就不放：一颗压不住截面的碎石只会露在墙角旁边碍事。
		if end_radius < MapLayout.END_MIN_RADIUS:
			continue
		# 高度必须**低于墙顶**：野区墙没有可走边界兜底，英雄能贴着墙根站，
		# 任何高过 2.2 米的部件都会把他整条盖住。露头石的职责是收断面，不是加高。
		# 按序号错开 0 / 0.08 / 0.16 米：半径被余量压成同一个值时，
		# 一排等高石头俯视是条锯齿完全相同的花边，比等高墙还假。
		var end_height := 1.55 + (end_radius - MapLayout.END_MIN_RADIUS) * 0.85
		end_height += float(end_index % 3) * 0.08
		var cap := ModelUtils.fit_scene(rock_scene, end_height, end_radius * 2.0)
		cap.name = "wall_end_%s_%s" % [str(entry["wall"]), str(entry["end"])]
		var end_pos: Vector2 = entry["pos"]
		# 往墙里推 0.15 米：让石头吃掉端面，而不是在端面外侧贴一颗。
		var inward: Vector2 = -(entry["outward"] as Vector2) * 0.15
		cap.position = Vector3(end_pos.x + inward.x, 0.0, end_pos.y + inward.y)
		cap.rotation.y = rng.randf_range(0.0, TAU)
		# 半径与高度记到 meta：测试靠它验算「没伸进路面」和「确实高过墙」。
		cap.set_meta("end_radius", end_radius)
		cap.set_meta("end_height", end_height)
		ModelUtils.override_material(cap, stone)
		ModelUtils.enable_shadows(cap, true)
		_props_root.add_child(cap)

	# 草丛：叶簇网格 + 径向柔边的地面暗斑，几何与材质见 bush_field.gd。
	# 旧版是 7 个压扁球 + 一块半透明绿色矩形，俯视只能读成绿色气球和绿玻璃。
	var leaf_material := BushField.leaf_material()
	var floor_material := BushField.floor_material()
	var bush_rng := RandomNumberGenerator.new()
	bush_rng.seed = 41277
	for i in marks.bushes.size():
		var bush: Dictionary = marks.bushes[i]
		var center: Vector2 = bush.pos
		var radius := float(bush.radius)

		var floor_node := MeshInstance3D.new()
		floor_node.name = str(bush.id) + "_floor"
		var plane := PlaneMesh.new()
		plane.size = Vector2(radius * BushField.FLOOR_SCALE, radius * BushField.FLOOR_SCALE)
		floor_node.mesh = plane
		floor_node.material_override = floor_material
		floor_node.position = Vector3(center.x, 0.04, center.y)
		floor_node.rotation.y = bush_rng.randf_range(0.0, TAU)
		floor_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_props_root.add_child(floor_node)

		var bush_node := MeshInstance3D.new()
		bush_node.name = str(bush.id)
		bush_node.mesh = BushField.leaf_mesh(i)
		bush_node.material_override = leaf_material
		bush_node.position = Vector3(center.x, 0.0, center.y)
		bush_node.rotation.y = bush_rng.randf_range(0.0, TAU)
		# 横向铺满玩法半径，纵向有最低高度：藏得住下半身，又不盖住头顶血条。
		bush_node.scale = BushField.visual_scale(i, radius, bush_rng)
		bush_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_props_root.add_child(bush_node)

	for camp in marks.camps:
		var buff := str(camp.get("buff", ""))
		var color := Color(0.95, 0.62, 0.22) if buff == "red" else Color(0.34, 0.58, 0.98)
		if buff == "":
			# 小野点用草绿，和红/蓝 buff 一眼分开；它们没有增益可争夺。
			color = Color(0.58, 0.78, 0.42)
		var disc_radius := float(camp.get("disc_radius", MapLayout.CAMP_DISC_RADIUS))
		_add_map_disc(camp.pos, disc_radius, Color(color.r, color.g, color.b, 0.2), color)
		_add_camp_sigil("camp_%s" % str(camp.id), camp.pos, disc_radius, color)
		# 小野点不立图腾柱：12 个野点全立会变成一排彩色柱子，压过野怪本身。
		if buff != "":
			_add_map_totem(camp.pos + Vector2(0.0, -2.0), 2.2, color)
		_add_camp_label(camp, color)

	for pit in marks.objectives:
		_add_map_disc(pit.pos, MapLayout.PIT_DISC_RADIUS, Color(0.35, 0.2, 0.5, 0.26), Color(0.72, 0.5, 0.92))
		_add_camp_sigil("pit_%s" % str(pit.id), pit.pos, MapLayout.PIT_DISC_RADIUS, Color(0.72, 0.5, 0.92))
		for i in 4:
			var angle := TAU * float(i) / 4.0 + PI * 0.25
			var pillar_pos: Vector2 = pit.pos + Vector2(cos(angle), sin(angle)) * 5.0
			_add_map_totem(pillar_pos, 3.0, Color(0.62, 0.5, 0.82))
		_add_camp_label(pit, Color(0.8, 0.58, 1.0), true)

	for pad in marks.teleports:
		var pad_color := Color(0.4, 0.82, 0.92)
		# 盘半径走 MapLayout 的唯一真身：传送判定用的是同一个数，
		# 画大 / 画小都会变成「看着在阵里、按了没反应」。
		# 高度必须压在广场面**之上**：阵落在角落广场里，广场面 y = BRIDGE_DECK_Y(0.075)，
		# 沿用野区那套 0.04 会被广场整个盖住 —— 阵还在，画面上什么都没有。
		_add_map_disc(
			pad.pos, MapLayout.PAD_DISC_RADIUS,
			Color(pad_color.r, pad_color.g, pad_color.b, 0.2), pad_color,
			BRIDGE_DECK_Y + 0.02
		)
		# 图腾柱朝角落里立（离阵心 4.2 米，在阵盘 3.0 之外）：
		# 站在广场上、不压阵眼，也不立在路面正中挡小兵。
		_add_map_totem(pad.pos + Vector2(pad.get("totem", Vector2(0.0, -2.8))), 2.6, pad_color)

# 岩脊单块：fit_scene 先把高度对齐，再在水平方向拉伸成更宽的岩块。
# 不能直接给 fit_scene 传 max_width：Rock.glb 本身高瘦，按宽度封顶会把它压矮。
# meta 里带 wall_id / side / kind / along，测试靠它分组、量间距、找岩脊；
# 不要改成解析节点名：墙 id 自己就带下划线（wall_top_west），拆字符串必崩。
func _begin_rock_batch() -> void:
	_rock_batch_specs.clear()

func _queue_rock(point: Vector2, height: float, width_scale: float, yaw: float, meta: Dictionary) -> void:
	_rock_batch_specs.append({
		"pos": point,
		"height": height,
		"width_scale": width_scale,
		"yaw": yaw,
		"meta": meta,
	})

# Rock.glb 只实例化一次，取出网格与「把原始模型归一化到高 1 米、脚底 y=0」的
# 基变换。之后每个实例只需要自己的缩放/旋转/位移，不再各自 new 一个场景。
func _rock_mesh_data(rock_scene: PackedScene) -> Dictionary:
	var key := rock_scene.resource_path
	if _rock_mesh_cache.has(key):
		return _rock_mesh_cache[key]
	var model: Node3D = rock_scene.instantiate()
	var mesh_instance: MeshInstance3D = null
	for node in model.find_children("*", "MeshInstance3D", true, false):
		var candidate := node as MeshInstance3D
		if candidate.mesh != null:
			mesh_instance = candidate
			break
	if mesh_instance == null:
		model.free()
		return {}
	var local := Transform3D.IDENTITY
	var current: Node = mesh_instance
	while current != null and current != model:
		if current is Node3D:
			local = (current as Node3D).transform * local
		current = current.get_parent()
	# glb 根节点也可能带变换；fit_scene 的包围盒包含了它，这里必须一起带上。
	local = model.transform * local
	var box := ModelUtils.relative_aabb(model)
	var raw_height := maxf(box.size.y, 0.001)
	var factor := 1.0 / raw_height
	var center := box.get_center()
	var fit := Transform3D(
		Basis.from_scale(Vector3.ONE * factor),
		Vector3(-center.x * factor, -box.position.y * factor, -center.z * factor)
	)
	var data := {"mesh": mesh_instance.mesh, "base": fit * local}
	model.free()
	_rock_mesh_cache[key] = data
	return data

# 把本批岩块合成一个 MultiMeshInstance3D：几百块石头只占 1 个 draw call，
# 阴影 pass 也只画一次。每块石头的 height/width/yaw/pos 和元数据仍写进
# rock_specs，测试与调试可以逐块核对。
func _flush_rock_batch(node_name: String, rock_scene: PackedScene, stone: Material, shadows: bool) -> MultiMeshInstance3D:
	if _rock_batch_specs.is_empty():
		return null
	var data := _rock_mesh_data(rock_scene)
	if data.is_empty():
		_rock_batch_specs.clear()
		return null
	var mesh: Mesh = data.mesh
	var base: Transform3D = data.base
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = mesh
	multimesh.instance_count = _rock_batch_specs.size()
	var bounds := AABB()
	var has_bounds := false
	for i in _rock_batch_specs.size():
		var spec: Dictionary = _rock_batch_specs[i]
		var point: Vector2 = spec.pos
		var height := float(spec.height)
		var width_scale := float(spec.width_scale)
		var basis := Basis(Vector3.UP, float(spec.yaw)) \
			* Basis.from_scale(Vector3(width_scale * height, height, width_scale * height))
		var xform := Transform3D(basis, Vector3(point.x, 0.0, point.y)) * base
		multimesh.set_instance_transform(i, xform)
		spec["transform"] = xform
		var extra: Dictionary = spec.meta
		for extra_key in extra:
			spec[extra_key] = extra[extra_key]
		var instance_box: AABB = xform * mesh.get_aabb()
		bounds = instance_box if not has_bounds else bounds.merge(instance_box)
		has_bounds = true
	var node := MultiMeshInstance3D.new()
	node.name = node_name
	node.multimesh = multimesh
	node.material_override = stone
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# MultiMesh 的默认 AABB 只按单块网格算；不显式给全图包围盒，镜头一动
	# 整批石头会被错误剔除，表现为「墙突然消失」。
	node.custom_aabb = bounds
	node.set_meta("rock_specs", _rock_batch_specs.duplicate(true))
	_props_root.add_child(node)
	_rock_batch_specs = []
	return node

# 边界：一圈看得见的岩壁。
# 模拟层靠 collision.clamp_bounds 拦住人，但那是隐形墙 —— 玩家看见草地一直铺到
# 远处的山，撞上去才知道到边了。这里的墙内表面与 MapData.BOUNDS 重合，
# 所以「看到的墙」和「走不过去的线」是同一条。
#
# 2026-10-28 重做：旧版是「直方盒墙身 + 外挑压顶 + 等距壁柱」，俯视是一圈
# 规整的城墙，四个直角非常明显。王者峡谷的边界是自然山体，岩面有进有退。
# 现在保留 2 米高的砌石基座封住边界，上面铺一条前后错落、高度不一的岩脊；
# 四个角再压一簇更大的岩体，把直角吞掉。岩脊可以往非走区探 1.2 米，
# 但前缘始终留在玩家身体之外（可走极限 54.2，岩体前缘 ≥ 55）。
func _build_boundary_walls() -> void:
	# 边界墙与野区墙是同一块石头：两套材质会出现「远处木板、近处石壁」的割裂，
	# 而且玩家读不出这两者是同一种地形。
	var stone := _wall_stone_material()
	var rng := RandomNumberGenerator.new()
	rng.seed = 20481
	var rock_scene: PackedScene = load(ENV_DIR + "Rock.glb")
	_begin_rock_batch()

	for wall in MapLayout.boundary_walls():
		var a: Vector2 = wall.a
		var b: Vector2 = wall.b
		var center := (a + b) * 0.5
		var length := a.distance_to(b)
		var dir := (b - a) / maxf(length, 0.001)
		var perp := Vector2(-dir.y, dir.x)
		var yaw := -atan2(dir.y, dir.x)
		var side := str(wall.get("id", "boundary")).trim_prefix("boundary_")
		var inward := perp * (1.0 if center.dot(perp) < 0.0 else -1.0)
		var barrier := MeshInstance3D.new()
		barrier.name = str(wall.get("id", "boundary"))
		var box := BoxMesh.new()
		box.size = Vector3(length, MapLayout.BOUNDARY_CORE_HEIGHT, MapLayout.BOUNDARY_THICK)
		barrier.mesh = box
		barrier.material_override = stone
		barrier.position = Vector3(center.x, MapLayout.BOUNDARY_CORE_HEIGHT * 0.5, center.y)
		barrier.rotation.y = yaw
		ModelUtils.enable_shadows(barrier, true)
		_props_root.add_child(barrier)

		# 岩脊：每块石头的进深、高度、水平拉伸都不同，连续的直顶线被打散成山脊。
		var ridge_count := maxi(6, int(round(length / MapLayout.BOUNDARY_ROCK_SPACING)))
		for i in ridge_count:
			var t := (float(i) + 0.5) / float(ridge_count)
			t = clampf(t + rng.randf_range(-0.2, 0.2) / float(ridge_count), 0.0, 1.0)
			var p := a.lerp(b, t)
			# 负值往外退、正值往可玩区探：同一侧墙的岩面因此有进有退。
			p += inward * rng.randf_range(-MapLayout.BOUNDARY_ROCK_OUTWARD, MapLayout.BOUNDARY_ROCK_INTRUDE)
			var band := rng.randf_range(0.05, 0.35) if i % 2 == 0 else rng.randf_range(0.65, 0.95)
			_queue_rock(
				p,
				lerpf(MapLayout.BOUNDARY_ROCK_MIN_HEIGHT, MapLayout.BOUNDARY_ROCK_MAX_HEIGHT, band),
				rng.randf_range(MapLayout.BOUNDARY_ROCK_WIDTH_MIN, MapLayout.BOUNDARY_ROCK_WIDTH_MAX),
				rng.randf_range(0.0, TAU),
				{"side": side, "kind": "ridge", "along": length * t}
			)

		# 墙脚碎石：让墙和草地之间不是一条数学直线。
		# 只撒在**内侧**（朝可玩区那一面），因为外侧贴着地形抬升，本来就被山体挡住。
		var rubble := maxi(2, int(round(length / 6.5)))
		for i in rubble:
			var p := a.lerp(b, (float(i) + 0.5) / float(rubble) + rng.randf_range(-0.2, 0.2) / maxf(length, 0.001))
			var out := inward * rng.randf_range(MapLayout.BOUNDARY_THICK * 0.5 + 0.1, MapLayout.BOUNDARY_THICK * 0.5 + 0.9)
			_queue_rock(
				Vector2(p.x + out.x, p.y + out.y),
				rng.randf_range(0.35, 0.65),
				1.0,
				rng.randf_range(0.0, TAU),
				{"side": side, "kind": "rubble", "along": length * (float(i) + 0.5) / float(rubble)}
			)

	# 四角岩簇：两段直墙在角点硬碰硬，是最明显的「方盒子」信号。
	# 每个角压三块大岩，前两块往外包、第三块往内收，把直角吞进山体里。
	var c := MapLayout.BOUNDARY_CENTER
	var corners := [Vector2(-c, -c), Vector2(c, -c), Vector2(c, c), Vector2(-c, c)]
	for ci in corners.size():
		var corner: Vector2 = corners[ci]
		var outward := corner.normalized()
		for j in 3:
			var p := corner + outward * rng.randf_range(0.5, 1.8)
			if j == 2:
				p = corner - outward * rng.randf_range(0.1, 0.4)
			p += Vector2(rng.randf_range(-0.6, 0.6), rng.randf_range(-0.6, 0.6))
			_queue_rock(
				p,
				rng.randf_range(3.05, 3.6),
				rng.randf_range(1.5, 1.75),
				rng.randf_range(0.0, TAU),
				{"side": "corner", "kind": "ridge", "corner": ci}
			)

	# 边界岩脊与角岩合成一批：桌面保留阴影（边界轮廓更立体）；
	# 移动端关掉，边界基座和墙端石仍会投影，足够接地。
	_flush_rock_batch("boundary_rocks", rock_scene, stone, not OS.has_feature("mobile"))

# 贴地圆盘（营地 / 首领坑 / 传送阵）。base_y 默认压在草地上（草地 0.0、路面 0.022）；
# 传送阵现在坐在角落桥上（桥面 y = BRIDGE_DECK_Y），必须显式抬高，否则整块被桥面盖住。
func _add_map_disc(pos: Vector2, radius: float, fill: Color, edge: Color, base_y := 0.04) -> void:
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
	disc.position = Vector3(pos.x, base_y, pos.y)
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
	ring.position = Vector3(pos.x, base_y + 0.03, pos.y)
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_props_root.add_child(ring)
	# 内环：一道边环的实心圆片读成「地上的一滩水」，两道同心环才读成「法阵」。
	# 半径 0.62 是俯视下能同时看见两环、又不把阵心填满的位置。
	var inner := MeshInstance3D.new()
	var inner_torus := TorusMesh.new()
	inner_torus.inner_radius = radius * 0.62 - 0.06
	inner_torus.outer_radius = radius * 0.62
	inner_torus.rings = 40
	inner.mesh = inner_torus
	var inner_material := StandardMaterial3D.new()
	inner_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	inner_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	inner_material.albedo_color = Color(edge.r, edge.g, edge.b, 0.55)
	inner_material.emission_enabled = true
	inner_material.emission = edge
	inner_material.emission_energy_multiplier = 0.5
	inner.material_override = inner_material
	inner.position = Vector3(pos.x, base_y + 0.025, pos.y)
	inner.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_props_root.add_child(inner)

# 营地 / 首领坑的贴地符阵：圆盘上的旋转刻线，野怪死亡时整块暗下去。
# 与圆盘分开放，是为了让「熄灭」只影响符阵，不把石盘和边缘环一起吞掉。
func _add_camp_sigil(key: String, pos: Vector2, radius: float, color: Color) -> void:
	if _sigil_shader == null:
		_sigil_shader = load(CAMP_SIGIL_SHADER)
	if _sigil_shader == null:
		return
	var material := ShaderMaterial.new()
	material.shader = _sigil_shader
	material.set_shader_parameter("sigil_color", Color(color.r, color.g, color.b, 0.72))
	material.set_shader_parameter("active", 1.0)
	var node := MeshInstance3D.new()
	node.name = "camp_sigil_" + key
	var plane := PlaneMesh.new()
	plane.size = Vector2(radius * 1.72, radius * 1.72)
	node.mesh = plane
	node.material_override = material
	# 压在圆盘上沿（圆盘 0.04 / 内环 0.065），再高会被图腾柱底部吃掉。
	node.position = Vector3(pos.x, 0.085, pos.y)
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_props_root.add_child(node)
	_camp_sigils[key] = material
	_camp_sigil_active[key] = true

func _set_camp_sigil_active(key: String, active: bool) -> void:
	var material: ShaderMaterial = _camp_sigils.get(key, null)
	if material == null:
		return
	if bool(_camp_sigil_active.get(key, true)) == active:
		return
	_camp_sigil_active[key] = active
	material.set_shader_parameter("active", 1.0 if active else 0.0)

# 营地重生牌：怪物活着时隐藏，死亡后原地显示「名称 + 剩余秒数」。
# 不用 UnitVisual 的头顶名牌，因为怪物死亡后视图会被回收，而倒计时必须留在营地上。
func _add_camp_label(region: Dictionary, color: Color, pit := false) -> void:
	var label := Label3D.new()
	var region_id := str(region.get("id", ""))
	label.name = "camp_timer_" + region_id
	label.text = ""
	label.font = FONT_SC
	label.font_size = 40
	label.pixel_size = 0.004
	label.outline_size = 10
	label.outline_modulate = Color(0.01, 0.02, 0.03, 0.95)
	label.modulate = color
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = false
	# 首领坑的怪高 2.4 米，牌要抬到头顶之上；小营地/小野点 2.1 米就够。
	# 不能再用「buff 为空」判断首领：小野点的 buff 也是空的。
	label.position = Vector3(float(region.pos.x), 3.4 if pit else 2.2, float(region.pos.y))
	label.visible = false
	label.set_meta("region_id", region_id)
	label.set_meta("display_name", str(region.get("name", "野怪")))
	_props_root.add_child(label)
	_camp_labels[region_id] = label

func _add_map_totem(pos: Vector2, height: float, color: Color) -> void:
	var pole := MeshInstance3D.new()
	var cylinder := CylinderMesh.new()
	# 上细下粗的方尖碑：0.16/0.26 那版在 20 米机位下就是一根灰铅笔，
	# 顶上再点一颗小珠子，整体读成「路牌」而不是「遗迹法柱」。
	# 四方截面（radial_segments = 4）而不是六/八边的圆管：
	# 圆截面的细杆在任何角度都是同一条灰影，读成「塑料管」；方的才有棱、有面。
	cylinder.top_radius = 0.26
	cylinder.bottom_radius = 0.34
	cylinder.height = height
	cylinder.radial_segments = 4
	pole.mesh = cylinder
	var stone := StandardMaterial3D.new()
	stone.albedo_color = Color(0.32, 0.3, 0.28)
	stone.roughness = 1.0
	pole.material_override = stone
	pole.position = Vector3(pos.x, height * 0.5, pos.y)
	ModelUtils.enable_shadows(pole, true)
	_props_root.add_child(pole)
	# 石箍：柱身上套两圈。只有一根光杆时，不管加多粗都读成「塑料管」；
	# 有箍才有「分段的遗迹石柱」——这也是参考图里那些高柱的共同特征。
	for t in [0.42, 0.72]:
		var collar := MeshInstance3D.new()
		var collar_mesh := CylinderMesh.new()
		collar_mesh.top_radius = 0.34
		collar_mesh.bottom_radius = 0.34
		collar_mesh.height = 0.16
		collar_mesh.radial_segments = 4
		collar.mesh = collar_mesh
		collar.material_override = stone
		collar.position = Vector3(pos.x, height * float(t), pos.y)
		ModelUtils.enable_shadows(collar, true)
		_props_root.add_child(collar)
	var gem := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	# 顶上是一颗**发光晶石**。之前试过四面菱形（想显得"有棱"），
	# 但在 20 米机位下低分段的球就是一个方疙瘩，比圆球更像贴纸。
	# 圆柱身 + 石箍已经在做"石柱"这件事，头部就交给光。
	sphere.radial_segments = 16
	sphere.rings = 8
	sphere.radius = 0.30
	sphere.height = 0.66
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
	if _lane_distance(point) < 4.6:
		return false
	if _river_distance(point) < 12.5:
		return false
	if _base_distance(point) < 11.5:
		return false
	# 地表草也要避开贴地圆盘：草丛是按草根撒的，草根长在石盘上就是
	# 「绿点从法阵里冒出来」。留 0.3 米让草丛边缘自然收口，不要一圈秃边。
	if MapLayout.on_ground_mark(point, 0.3):
		return false
	for bush in _grass_bushes:
		# 留在草丛外沿 0.45m 处的草可以长进来，让叶簇和地表草自然衔接；
		# 全部排除会留出一圈生硬的秃边。
		if point.distance_to(bush.pos) < float(bush.radius) - 0.45:
			return false
	return true

func _build_grass_tufts() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 5150
	_grass_noise.seed = 991
	_grass_noise.frequency = 0.045
	_grass_noise.fractal_octaves = 2
	_grass_bushes = MapView.map_marks().bushes
	# 手机端把草簇从 12000 降到 6000：草是半透明小片的 fill-rate 大头，
	# 镜头移动时满屏草叶的 overdraw 会直接吃掉帧率；密度减半后远看仍是草甸。
	var tuft_count := 6000 if OS.has_feature("mobile") else 12000
	var tufts := GrassField.scatter(tuft_count, _can_grow_grass, _terrain_height, rng)
	_props_root.add_child(tufts)

func _build_scenery() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261022
	# 玩家要求地图内不放树：树只是布景，却会把兵线、野区和草丛挡得看不清。
	# 岩石与远山保留，地形轮廓仍然成立。
	var rock_group: PackedScene = load(ENV_DIR + "Rock_Group.glb")
	var rock_single: PackedScene = load(ENV_DIR + "Rock.glb")
	var mountains: Array[PackedScene] = [
		load(ENV_DIR + "Mountain_Group_1.glb"),
		load(ENV_DIR + "Mountain_Group_2.glb"),
	]

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
		# 登记包围盒：相机钻进山体时由 _update_backdrop_visibility 整座隐藏。
		_backdrop_mountains.append({"node": mountain, "box": ModelUtils.relative_aabb(mountain)})
		if i % 4 == 3:
			await _next_frame()

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
	# 与 TerrainBuilder.river_distance / MapIntel 同源：河道中心线是 x - y = 0。
	return absf(point.x - point.y) * 0.70710678

# 墙体/草丛/营地/首领坑/传送阵/角落广场/边界墙周围留白，避免随机植被长进可交互区域。
func _feature_clear(point: Vector2, margin: float) -> bool:
	if MapLayout.near_boundary(point, 2.5 + margin):
		return false
	# 角落广场是整块石面：树长在石板上比长在阵盘上更离谱。
	# 广场外沿本来就吃掉了边界留白，这里按内沿外扩 margin 判。
	if MapLayout.inside_corner_plaza(point, margin):
		return false
	var marks := MapView.map_marks()
	for wall in marks.walls:
		if _segment_distance(point, wall.a, wall.b) < 1.5 + margin:
			return false
	for bush in marks.bushes:
		if point.distance_to(bush.pos) < float(bush.radius) + margin:
			return false
	# 贴地圆盘（营地 / 首领坑 / 传送阵）的占位只有 MapLayout.on_ground_mark 一份。
	# 曾经在这里手抄过一遍半径，传送阵是后加的、清单没跟上，树就长到了阵盘正中。
	if MapLayout.on_ground_mark(point, margin):
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
	_sync_camp_states(snapshot)

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

# 野怪状态 → 营地地面牌 + 符阵亮度。
# 快照里出现怪 = 这个营地当前在视野内；没出现就保持隐藏，避免隔墙读倒计时。
func _sync_camp_states(snapshot: Dictionary) -> void:
	for label in _camp_labels.values():
		if label != null:
			label.visible = false
	for entity in snapshot.get("entities", []):
		if str(entity.get("type", "")) != "monster":
			continue
		var camp_id := str(entity.get("camp_id", ""))
		var objective_id := str(entity.get("objective_id", ""))
		var region_id := camp_id if camp_id != "" else objective_id
		if region_id == "":
			continue
		var alive := bool(entity.get("alive", false))
		var sigil_key := ("camp_" if camp_id != "" else "pit_") + region_id
		_set_camp_sigil_active(sigil_key, alive)
		var label: Label3D = _camp_labels.get(region_id, null)
		if label == null:
			continue
		if alive:
			continue
		var timer := float(entity.get("respawn_timer", 0.0))
		if timer <= 0.0:
			continue
		label.visible = true
		var seconds := int(ceil(timer))
		var text := "%s  %ds" % [str(label.get_meta("display_name", "野怪")), seconds]
		if str(label.get_meta("timer_text", "")) != text:
			label.set_meta("timer_text", text)
			label.text = text

func _acquire_unit_view(entity: Dictionary) -> UnitVisual:
	var entity_type := str(entity.get("type", "hero"))
	var team := str(entity.get("team", "blue"))
	var pos := Vector3(float(entity.get("x", 0.0)), 0.0, float(entity.get("y", 0.0)))
	if entity_type == "minion":
		var pool := _minion_pool_blue if team == "blue" else _minion_pool_red
		if not pool.is_empty():
			var view: UnitVisual = pool.pop_back()
			view.reset_minion(team, pos, str(entity.get("minion_type", "melee")))
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
		var objective := bool(entity.get("objective", false))
		view.setup(
			"monster",
			"neutral",
			str(entity.get("monster_type", "wolf")),
			str(entity.get("name", "野怪")),
			false,
			local_team,
			objective,
			str(entity.get("objective_id", ""))
		)
		view.set_monster_badge(str(entity.get("buff_type", "")), objective)
	else:
		view.setup("minion", team, str(entity.get("minion_type", "melee")), "", false, local_team)
	_units_root.add_child(view)
	view.position = Vector3(float(entity.get("x", 0.0)), 0.0, float(entity.get("y", 0.0)))
	view.set_snapshot(entity, 1.0)
	return view

func _sync_structures(snapshot: Dictionary, initial: bool) -> void:
	if snapshot.is_empty():
		return
	# 本地英雄每帧查一次：塔范围圈的红/蓝只取决于它站在哪儿。
	# _sync_units 先于本函数执行，所以 _local_entity_id 已经是本帧的值。
	var viewer: Dictionary = {}
	if _local_entity_id >= 0:
		for candidate in snapshot.get("entities", []):
			if int(candidate.get("id", -1)) == _local_entity_id:
				viewer = candidate
				break
	# 范围圈只在敌方可攻击单位进圈时亮：先筛一遍，十几座结构复用同一份列表。
	var ring_targets: Array = []
	for unit in snapshot.get("entities", []):
		var unit_type := str(unit.get("type", ""))
		if unit_type == "minion" or unit_type == "hero":
			ring_targets.append(unit)
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
		# 圈默认隐藏：敌方小兵/英雄进圈才亮，本地英雄在敌方塔下时转红。
		var ring_state := range_ring_state(entity, record.get("team_color", BLUE), viewer, ring_targets)
		var range_ring: MeshInstance3D = record.get("range_ring")
		var range_band: MeshInstance3D = record.get("range_band")
		var ring_visible := bool(ring_state.visible)
		if range_ring != null:
			range_ring.visible = ring_visible
		if range_band != null:
			range_band.visible = ring_visible
		# 材质只在「隐藏/亮起/报警」切换时改。以前每帧无条件写 albedo/emission：
		# 5v5 有 12 座建筑，每帧 12 次材质属性写会逼渲染端重建 uniform。
		var tone := 2 if bool(ring_state.warned) else (1 if ring_visible else 0)
		if int(record.get("ring_tone", -1)) != tone:
			record["ring_tone"] = tone
			var range_mat: StandardMaterial3D = record.get("range_mat")
			var band_mat: StandardMaterial3D = record.get("range_band_mat")
			if range_mat != null:
				range_mat.albedo_color = ring_state.color
				range_mat.emission = ring_state.glow
			if band_mat != null:
				band_mat.albedo_color = Color(ring_state.glow.r, ring_state.glow.g, ring_state.glow.b, float(ring_state.color.a) * 0.45)
				band_mat.emission = ring_state.glow

# 塔的范围圈只在「真的有可攻击目标」时显示：敌方小兵/英雄进入射程。
# 口径与 TowerRules.select_target 一致 —— 自家单位和野怪（neutral）都不算，
# 否则一圈蓝雾会因为自家兵线或路过一只野怪亮起来。
static func range_ring_revealed(entity: Dictionary, entities: Array) -> bool:
	var team := str(entity.get("team", ""))
	var reach := float(entity.get("range", 8.0))
	var structure_pos := Vector2(float(entity.get("x", 0.0)), float(entity.get("y", 0.0)))
	for unit in entities:
		var unit_type := str(unit.get("type", ""))
		if unit_type != "minion" and unit_type != "hero":
			continue
		if not bool(unit.get("alive", false)):
			continue
		var unit_team := str(unit.get("team", ""))
		if unit_team == team or unit_team == "neutral":
			continue
		var unit_pos := Vector2(float(unit.get("x", 0.0)), float(unit.get("y", 0.0)))
		if structure_pos.distance_to(unit_pos) <= reach:
			return true
	return false

# 防御塔范围圈的唯一判定入口。抽成纯函数是为了能被 headless 测到：
# 半径必须取实体自己的 range（塔 8 / 双生塔 7 / 主堡 9），
# 只有**敌方**塔在本地英雄踏入时才转红；没有敌方单位进圈时整圈隐藏。
static func range_ring_state(entity: Dictionary, team_color: Color, viewer: Dictionary, entities: Array = []) -> Dictionary:
	var attack_range := float(entity.get("range", 8.0))
	var warned := false
	if not viewer.is_empty() and bool(viewer.get("alive", false)):
		if str(viewer.get("team", "")) != str(entity.get("team", "")):
			var structure_pos := Vector2(float(entity.get("x", 0.0)), float(entity.get("y", 0.0)))
			var viewer_pos := Vector2(float(viewer.get("x", 0.0)), float(viewer.get("y", 0.0)))
			# 边界算在内：和塔的命中判定（中心距 <= range）保持一致，
			# 否则会出现「圈还是蓝的，人已经在挨打」。
			warned = structure_pos.distance_to(viewer_pos) <= attack_range
	var revealed := warned or range_ring_revealed(entity, entities)
	var glow: Color = TOWER_RING_WARN_COLOR if warned else team_color
	var alpha := TOWER_RING_WARN_ALPHA if warned else (TOWER_RING_ACTIVE_ALPHA if revealed else TOWER_RING_IDLE_ALPHA)
	return {
		"radius": attack_range,
		"warned": warned,
		"visible": revealed,
		"glow": glow,
		"color": Color(glow.r, glow.g, glow.b, alpha),
	}

# 普攻表现配方。抽成静态纯函数，headless 才能断言
# 「近战刀光 / 远程弹丸 / 炮车大弹丸 / 塔的光束」确实长得不一样。
# mode：melee = 瞬时刀光，projectile = 飞行弹丸，lance = 塔的持续光束。
static func attack_fx_plan(event: Dictionary) -> Dictionary:
	if str(event.get("type", "")) == "structure_attack":
		var source_type := str(event.get("source_type", "tower"))
		var scale_y := MapView.tower_scale(str(event.get("tier", "outer")))
		return {
			"mode": "lance",
			"radius": 0.26 if source_type == "base" else 0.2,
			# 主堡水晶在 3.55m，塔的水晶在 8.2m；枪口必须贴着模型顶部，
			# 否则光束会从半空中凭空出现。
			"from_height": 4.6 if source_type == "base" else 8.2 * scale_y,
			"to_height": 1.1,
			"duration": 0.18,
		}
	match str(event.get("minion_type", "melee")):
		"ranged":
			return {"mode": "projectile", "radius": 0.11, "from_height": 0.85, "to_height": 0.85, "duration": 0.22}
		"cannon":
			return {"mode": "projectile", "radius": 0.18, "from_height": 0.95, "to_height": 0.9, "duration": 0.26}
		"super":
			return {"mode": "melee", "radius": 0.14, "from_height": 0.95, "to_height": 0.85, "duration": 0.1}
	return {"mode": "melee", "radius": 0.09, "from_height": 0.75, "to_height": 0.8, "duration": 0.07}

# 英雄普攻表现配方（纯数据、无节点）。抽成静态纯函数，headless 才能断言
# 「近战英雄挥刀光 / 远程英雄打弹道」「暴击只是同一刀更狠，不是另一个形态」。
# 形态由 hero_defs 的 attack_range 分档，不另抄一份「谁是远程」的名单：
# 改数值表时表现自动跟着走，不会出现「数值说她是射手、画出刀光」。
static func hero_attack_fx_plan(hero_type: String, crit := false) -> Dictionary:
	var reach := maxf(HeroDefs.attack_range(hero_type), 1.6)
	var color := _hero_vfx_color(hero_type)
	if crit:
		# 暴击偏白偏亮：同一片刀光里，玩家要能一眼分出这一下更重。
		color = color.lerp(Color(1.0, 0.97, 0.9), 0.45)
	if reach < HERO_RANGED_REACH:
		return {
			"mode": "slash",
			"color": color,
			"reach": reach,
			"arc": HERO_SLASH_ARC_DEG,
			"height": HERO_SLASH_HEIGHT,
			# 刀光半径是**比例**（×reach），弹道半径是**绝对米数** ——
			# 两个键分开命名：同一个 "radius" 有两种量纲，下一个人一定会乘错。
			"reach_ratio": HERO_SLASH_REACH_RATIO,
			"duration": HERO_SLASH_DURATION,
			"impact": 8 if crit else 5,
			"shake": 0.06 if crit else 0.0,
		}
	return {
		"mode": "shot",
		"color": color,
		"reach": reach,
		"arc": 0.0,
		"height": HERO_SHOT_HEIGHT,
		"radius": HERO_SHOT_RADIUS,
		"duration": HERO_SHOT_DURATION,
		"impact": 4 if crit else 0,
		"shake": 0.05 if crit else 0.0,
	}

# 刀光的几何：一片朝局部 +X 张开的新月带。外沿半径 1，内沿从 1 收到
# HERO_SLASH_INNER，两端收成尖 —— 平口两端会读成「被切了一块扇形」。
# 只建一次、12 个池节点共用；每个实例只改颜色 / 朝向 / 缩放。
static func slash_mesh(segments := 18) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	var half := deg_to_rad(HERO_SLASH_ARC_DEG * 0.5)
	var steps := maxi(segments, 2)
	for index in steps + 1:
		var t := float(index) / float(steps)
		var angle := -half + 2.0 * half * t
		var pinch := sin(PI * t)
		var inner := lerpf(1.0, HERO_SLASH_INNER, pow(pinch, 0.55))
		var dir := Vector2(cos(angle), sin(angle))
		st.set_normal(Vector3.UP)
		st.set_uv(Vector2(t, 0.0))
		st.add_vertex(Vector3(dir.x, 0.0, dir.y))
		st.set_normal(Vector3.UP)
		st.set_uv(Vector2(t, 1.0))
		st.add_vertex(Vector3(dir.x * inner, 0.0, dir.y * inner))
	return st.commit()

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
	var core_node: MeshInstance3D = null
	var halo_node: MeshInstance3D = null
	var glow_node: MeshInstance3D = null
	var no_shadow_parts: Array = []
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
		# 参考图里的塔：米黄石雕裙摆 + 收分塔柱 + 笼状塔冠 + 发光核心 + 塔脚光池。
		# 石构件由 TowerVisual 一次拼好（一个网格），光效拆成独立节点方便每帧调色。
		var tower := TowerVisual.build(team_color)
		model = tower.node
		model.scale = Vector3.ONE * visual_scale
		core_node = tower.core
		halo_node = tower.halo
		glow_node = tower.glow
		glow_node.scale = Vector3.ONE * visual_scale
		var petals: Node3D = tower.petals
		petals.scale = Vector3.ONE * visual_scale
		root.add_child(glow_node)
		root.add_child(petals)
		spin_node = petals
		# 血条要压过塔顶石顶（含塔冠），同时给一点余量。
		bar_height = (TowerVisual.TOP_HEIGHT + 0.7) * visual_scale
		bar_width = 2.4 * visual_scale
		ring_radius = 2.0 * visual_scale
		# 核心和光晕都不投阴影：自发光体在地面上留一块实心黑影非常出戏。
		no_shadow_parts = [core_node, halo_node]
	ModelUtils.tint(model, team_color, 0.08 if entity_type == "base" else 0.04)
	ModelUtils.enable_shadows(model, true)
	for part in no_shadow_parts:
		(part as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
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
	# 攻击范围圈：贴地细环，半径就是这座塔真正的攻击距离。
	var ring_state := range_ring_state(entity, team_color, {})
	var range_ring := MeshInstance3D.new()
	var range_torus := TorusMesh.new()
	range_torus.inner_radius = maxf(0.6, float(ring_state.radius) - 0.16)
	range_torus.outer_radius = float(ring_state.radius) + 0.16
	range_torus.rings = 96
	range_torus.ring_segments = 6
	range_ring.mesh = range_torus
	range_ring.position.y = RANGE_RING_Y
	var range_mat := StandardMaterial3D.new()
	range_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	range_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	range_mat.albedo_color = ring_state.color
	range_mat.emission_enabled = true
	range_mat.emission = ring_state.glow
	range_mat.emission_energy_multiplier = 1.0
	# 贴地环从任何角度都要能看见，双面渲染省得背面被剔除掉半圈。
	range_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	range_ring.material_override = range_mat
	range_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# 默认隐藏：等 _sync_structures 判定「有敌方小兵/英雄进圈」才亮。
	range_ring.visible = false
	root.add_child(range_ring)
	# 参考图里的射程是一条又宽又柔的暖色光带，细环只负责把边界钉死。
	var range_band := MeshInstance3D.new()
	var band_torus := TorusMesh.new()
	band_torus.inner_radius = maxf(1.0, float(ring_state.radius) - 0.42)
	band_torus.outer_radius = float(ring_state.radius) + 0.42
	band_torus.rings = 96
	band_torus.ring_segments = 6
	range_band.mesh = band_torus
	range_band.position.y = RANGE_RING_Y - 0.01
	var band_mat := StandardMaterial3D.new()
	band_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	band_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	# 用普通 alpha 混合而不是加法：加法叠在亮草地上会整片烧白，警戒色就没了。
	band_mat.albedo_color = Color(ring_state.glow.r, ring_state.glow.g, ring_state.glow.b, float(ring_state.color.a) * 0.45)
	band_mat.emission_enabled = true
	band_mat.emission = ring_state.glow
	band_mat.emission_energy_multiplier = 0.35
	band_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	range_band.material_override = band_mat
	range_band.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	range_band.visible = false
	root.add_child(range_band)
	var fill := _add_structure_bar(root, bar_height, bar_width, team_color)
	return {
		"root": root,
		"model": model,
		"bar_height": bar_height,
		"bar": fill[0],
		"bar_mat": fill[1],
		"bar_width": bar_width,
		"spin": spin_node,
		"shield": shield,
		"crystal_shield": crystal_shield,
		"range_ring": range_ring,
		"range_mat": range_mat,
		"range_band": range_band,
		"range_band_mat": band_mat,
		"core": core_node,
		"glow": glow_node,
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
	# 技能表现统一从 SkillFx.requests() 取：Q/E 的 skill、W/R 的 skill_cast、
	# 召唤师技能的 summoner_cast 在这里归一。以前只认 skill，W/R 放出去毫无表现。
	for request in SkillFx.requests(events):
		_spawn_skill_fx(request)
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
				_handle_hero_attack(event)
			"hit":
				_handle_hit_event(event)
			"death":
				_handle_death_event(event)
			"tower_destroyed":
				var pos := Vector3(float(event.get("x", 0.0)), 1.0, float(event.get("y", 0.0)))
				_explosion(pos, RED if str(event.get("team", "red")) == "red" else BLUE, 32)
				_trigger_hit_stop(0.06, 0.22)
			"guard_destroyed":
				var guard_pos := Vector3(float(event.get("x", 0.0)), 1.0, float(event.get("y", 0.0)))
				_explosion(guard_pos, RED if str(event.get("team", "red")) == "red" else BLUE, 30)
				_camera_shake = maxf(_camera_shake, 0.14)
			"crystal_shield_broken":
				var crystal_pos := Vector3(float(event.get("x", 0.0)), 2.0, float(event.get("y", 0.0)))
				_spawn_ring(crystal_pos, Color(0.55, 0.84, 1.0), 1.0, 8.0, 1.0)
				_spawn_particles(crystal_pos + Vector3(0, 2.0, 0), Color(0.62, 0.86, 1.0), 30, 6.0)
				_camera_shake = maxf(_camera_shake, 0.22)
				_trigger_hit_stop(0.1, 0.3)
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
			"minion_attack":
				_handle_minion_attack(event)
			"structure_attack":
				_handle_structure_attack(event)
			"respawn":
				var pos := Vector3(float(event.get("x", 0.0)), 0.1, float(event.get("y", 0.0)))
				_spawn_ring(pos, GOLD, 0.4, 2.0, 0.6)
			"match_end":
				hud.announce("主堡陷落", GameTheme.GOLD_LIGHT, 2.0)
				_trigger_hit_stop(0.16, 0.45)
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

# 技能表现：照着 SkillFx 的配方放环 / 粒子 / 抛射物 / 光带 / 震屏。
# 不看「_views 里有没有这个英雄」——事件自带坐标，镜头外或刚进视野的施法也该有表现，
# 否则会出现「听得到音效、看不到画面」。view 只用来播施法动作。
func _spawn_skill_fx(request: Dictionary) -> void:
	# 计数放在最前面：即使特效根节点还没建好（进场分帧构建期间），
	# 也能证明「这条事件确实被技能表现链路消费了」，便于排查静默失效。
	skill_fx_count += 1
	if _effects_root == null:
		return
	var slot := str(request.get("slot", "q"))
	var spell := str(request.get("summoner", ""))
	var view: UnitVisual = _views.get(int(request.get("hero_id", -1)))
	if view != null and spell == "":
		view.play_skill(slot)
	var color: Color = SkillFx.summoner_color(spell) if spell != "" else _hero_vfx_color(str(request.get("hero_type", "blade")))
	var from_point: Vector2 = request.get("from", Vector2.ZERO)
	var aim_point: Vector2 = request.get("aim", Vector2.ZERO)
	var from := Vector3(from_point.x, 1.0, from_point.y)
	var aim := Vector3(aim_point.x, 0.1, aim_point.y)
	var recipe: Dictionary = request.get("recipe", {})
	# 位移技能的残影：起点 → 落点之间补几圈，才读得出「冲过去了」。
	var trail := int(recipe.get("trail", 0))
	for index in trail:
		var ratio := float(index + 1) / float(trail + 1)
		var point := from.lerp(aim, ratio)
		_spawn_ring(Vector3(point.x, 0.1, point.z), color, 0.35, 2.0, 0.38, 0.45)
	for ring in recipe.get("rings", []):
		var ring_base: Vector3 = from if str(ring.get("at", "aim")) == "self" else aim
		_spawn_ring(
			Vector3(ring_base.x, 0.1, ring_base.z), color,
			float(ring.get("from", 0.4)), float(ring.get("to", 2.4)),
			float(ring.get("dur", 0.3)), float(ring.get("alpha", 0.6))
		)
	for burst in recipe.get("particles", []):
		var burst_base: Vector3 = from if str(burst.get("at", "aim")) == "self" else aim
		_spawn_particles(
			Vector3(burst_base.x, float(burst.get("height", 0.6)), burst_base.z), color,
			int(burst.get("count", 12)), float(burst.get("speed", 3.0)),
			float(burst.get("size", 0.12)), float(burst.get("life", 0.45))
		)
	var projectile := float(recipe.get("projectile", 0.0))
	if projectile > 0.0:
		_spawn_projectile(from, Vector3(aim.x, 0.8, aim.z), color, projectile)
	if int(recipe.get("beam", 0)) > 0:
		_spawn_beam(from, Vector3(aim.x, 0.4, aim.z), color, 0.16)
	_camera_shake = maxf(_camera_shake, float(recipe.get("shake", 0.0)))
	var hit_stop := float(recipe.get("hit_stop", 0.0))
	if hit_stop > 0.0:
		_trigger_hit_stop(hit_stop, 0.3)

# 英雄普攻：出手动作 + 刀光 / 弹道 + 命中火星。
#
# 三条必须写在这里的理由：
# ① 事件自带起点与目标点，镜头外（或刚进视野）的普攻也照样有表现，
#    不能挂在 _views 上，否则「看得见的才出手」；
# ② 表现配方来自纯函数 hero_attack_fx_plan()，headless 能断言近战与远程不一样；
# ③ 刀光从 _slash_pool 借，绝不在普攻路径上 new 网格/材质（硬规则 4）。
func _handle_hero_attack(event: Dictionary) -> void:
	var view: UnitVisual = _views.get(int(event.get("hero", -1)))
	if view != null:
		view.play_attack()
	var crit := bool(event.get("crit", false))
	# 顿帧必须排在「特效根节点还没建好」的早退之前：进场分帧构建期间
	# 也会收到 attack 事件，手感不该因为没画完场景就丢掉。
	if crit:
		_trigger_hit_stop(0.045, 0.18)
	if _effects_root == null:
		return
	# hero_type 由模拟层随事件下发（联机白名单里也有）：客机即使这一帧还没建好
	# 英雄视图，也能按同一套配方画刀光。
	var hero_type := str(event.get("hero_type", ""))
	if hero_type == "" and view != null:
		hero_type = view.hero_type
	var plan := hero_attack_fx_plan(hero_type, crit)
	var from_point := Vector2(float(event.get("x", 0.0)), float(event.get("y", 0.0)))
	var aim_point := Vector2(float(event.get("aim_x", from_point.x)), float(event.get("aim_y", from_point.y)))
	var direction := aim_point - from_point
	# 贴脸出手时方向会退化（目标就压在自己身上）：退到 -Y，
	# 避免画出一片朝零向量张开的刀光。
	if direction.length() < 0.05:
		direction = Vector2(0.0, -1.0)
	direction = direction.normalized()
	var color: Color = plan.get("color", GOLD)
	var target := Vector3(aim_point.x, 0.85, aim_point.y)
	if str(plan.get("mode", "slash")) == "slash":
		_spawn_slash(
			Vector3(from_point.x, float(plan.get("height", HERO_SLASH_HEIGHT)), from_point.y),
			direction, color,
			float(plan.get("reach", 2.0)) * float(plan.get("reach_ratio", HERO_SLASH_REACH_RATIO)),
			float(plan.get("arc", HERO_SLASH_ARC_DEG)),
			float(plan.get("duration", HERO_SLASH_DURATION))
		)
	else:
		# 远程：从手部抛出、落点抬到胸口，箭矢/法球才不是贴着地面飞。
		var hand := Vector3(from_point.x, float(plan.get("height", HERO_SHOT_HEIGHT)), from_point.y) \
			+ Vector3(direction.x, 0.0, direction.y) * 0.55
		_spawn_tracer(hand, target, color, float(plan.get("radius", HERO_SHOT_RADIUS)), float(plan.get("duration", HERO_SHOT_DURATION)))
		# 枪口一圈小闪 + 四颗火星：只有一颗飞过去的小球时，玩家要靠「血掉了」
		# 才反推自己出过手；小兵弹丸也是这么补的。
		_spawn_ring(hand, color, 0.14, 0.55, 0.16, 0.7)
		_spawn_particles(hand, color, 4, 1.6, 0.06, 0.16)
	var impact := int(plan.get("impact", 0))
	if impact > 0:
		_spawn_particles(target, color.lerp(Color(1.0, 1.0, 1.0), 0.35), impact, 2.6, 0.07, 0.24)
	var shake := float(plan.get("shake", 0.0))
	if shake > 0.0:
		_camera_shake = maxf(_camera_shake, shake)

# 小兵普攻：先播出手动作，再画刀光/弹丸。事件自带坐标，镜头外也照样有表现。
func _handle_minion_attack(event: Dictionary) -> void:
	var view: UnitVisual = _views.get(int(event.get("source", -1)))
	if view != null:
		view.play_attack()
	if _effects_root == null:
		return
	var plan := attack_fx_plan(event)
	var color := BLUE if str(event.get("team", "blue")) == "blue" else RED
	var from := Vector3(float(event.get("x", 0.0)), float(plan.get("from_height", 0.8)), float(event.get("y", 0.0)))
	var to := Vector3(float(event.get("target_x", 0.0)), float(plan.get("to_height", 0.8)), float(event.get("target_y", 0.0)))
	var radius := float(plan.get("radius", 0.1))
	var duration := float(plan.get("duration", 0.1))
	if str(plan.get("mode", "melee")) == "projectile":
		_spawn_tracer(from, to, color, radius, duration)
	else:
		# 刀光用队伍色偏白，和受击的四颗火星区分开。
		_spawn_tracer(from, to, color.lerp(Color(1.0, 0.96, 0.86), 0.5), radius, duration)
		_spawn_particles(to + Vector3(0, 0.15, 0), color.lerp(Color(1.0, 0.95, 0.82), 0.55), 3, 1.8, 0.06, 0.22)

# 防御塔开火：枪口闪光 + 一道淡出的光束 + 命中点火星。
# 旧实现只有一颗飞过的小球，玩家反馈「塔打了没感觉」。
func _handle_structure_attack(event: Dictionary) -> void:
	if _effects_root == null:
		return
	var plan := attack_fx_plan(event)
	var color := BLUE if str(event.get("team", "blue")) == "blue" else RED
	var from := Vector3(float(event.get("x", 0.0)), float(plan.get("from_height", 7.0)), float(event.get("y", 0.0)))
	var to := Vector3(float(event.get("target_x", 0.0)), float(plan.get("to_height", 1.1)), float(event.get("target_y", 0.0)))
	_spawn_lance(from, to, color, float(plan.get("radius", 0.2)), float(plan.get("duration", 0.18)))
	_spawn_particles(from, color, 8, 2.6, 0.1, 0.3)
	_spawn_particles(to, color.lerp(Color(1.0, 0.95, 0.8), 0.45), 6, 2.6, 0.09, 0.32)

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
		_trigger_hit_stop(0.09 if local_involved else 0.05, 0.34 if local_involved else 0.16)

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

	# 预热打击粒子池（24 个 GPUParticles3D），预先进入渲染树并预热着色器。
	# 12 个不够用：5v5 团战里 Q/W/R 一起放时实测有 26% 的簇因为池空被静默丢弃
	# （`tools/probe_particle_pool.gd` 量的）。现在池空时会抢占最老的一簇，不再丢。
	for i in 24:
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

	# 弹道光点池：小兵远程弹丸 / 近战刀光共用。
	# 24 个够覆盖三路同时交火；池空时和粒子一样抢占最老的那个。
	var tracer_mesh := SphereMesh.new()
	tracer_mesh.radius = 0.5
	tracer_mesh.height = 1.0
	tracer_mesh.radial_segments = 10
	tracer_mesh.rings = 6
	for i in 24:
		var orb := MeshInstance3D.new()
		orb.mesh = tracer_mesh
		# 普通混合保留阵营色：叠加混合会让蓝/红弹丸在亮色地面上都变成白点。
		orb.material_override = _make_fx_material(BaseMaterial3D.BLEND_MODE_MIX)
		orb.visible = false
		orb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_effects_root.add_child(orb)
		_tracer_pool.append(orb)

	# 塔的光束：一根会淡出的细圆柱，比飞过的小球更像「塔在开火」。
	var lance_mesh := CylinderMesh.new()
	lance_mesh.top_radius = 0.5
	lance_mesh.bottom_radius = 0.5
	lance_mesh.height = 1.0
	lance_mesh.radial_segments = 8
	lance_mesh.rings = 1
	for i in 8:
		var lance := MeshInstance3D.new()
		lance.mesh = lance_mesh
		# 光束用普通混合：叠加混合在亮色石板路上会被抬成纯白，阵营色就丢了。
		lance.material_override = _make_fx_material(BaseMaterial3D.BLEND_MODE_MIX)
		lance.visible = false
		lance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_effects_root.add_child(lance)
		_lance_pool.append(lance)

	# 范围环池：16 个足够覆盖 5v5 同时爆点，池空时抢占最老的那个。
	var ring_mesh := TorusMesh.new()
	ring_mesh.inner_radius = 0.62
	ring_mesh.outer_radius = 0.78
	ring_mesh.rings = 24
	ring_mesh.ring_segments = 5
	for i in 16:
		var ring := MeshInstance3D.new()
		ring.mesh = ring_mesh
		var ring_mat := _make_fx_material(BaseMaterial3D.BLEND_MODE_ADD)
		ring_mat.emission_energy_multiplier = 1.6
		ring.material_override = ring_mat
		ring.visible = false
		ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_effects_root.add_child(ring)
		_ring_pool.append(ring)

	# 英雄普攻刀光：12 片新月，5v5 同一秒十几次普攻也够；池空时抢占最老的。
	# 网格只提交一次（slash_mesh），材质每个节点一份 —— 挥击要独立改透明度。
	# 用普通混合（和塔光束/弹丸同一条理由）：叠加混合在亮石板、桥面上会被抬成纯白，
	# 英雄谱系色（苍刃橙 / 墨鸦粉）就没了 —— 第一版实测就是一片白。
	var slash_shape := slash_mesh()
	for i in 12:
		var slash := MeshInstance3D.new()
		slash.mesh = slash_shape
		var slash_mat := _make_fx_material(BaseMaterial3D.BLEND_MODE_MIX)
		slash_mat.emission_energy_multiplier = 1.4
		slash.material_override = slash_mat
		slash.visible = false
		slash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_effects_root.add_child(slash)
		_slash_pool.append(slash)

func _make_fx_material(blend := BaseMaterial3D.BLEND_MODE_ADD) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = blend
	material.emission_enabled = true
	material.emission_energy_multiplier = 2.2
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return material

func _spawn_damage_number(pos: Vector3, amount: float, color: Color) -> void:
	if _effects_root == null:
		return
	var slot: Dictionary = take_particle_slot(_damage_labels_pool, _damage_labels_active)
	if slot.is_empty():
		return
	var label: Label3D = slot.get("node")
	if bool(slot.get("stolen", false)):
		# 池空时抢最老的那个：它已经在屏幕上方淡出，掐掉它比新数字不显示划算。
		var old_tween: Variant = label.get_meta("tween", null)
		if old_tween is Tween and (old_tween as Tween).is_valid():
			(old_tween as Tween).kill()
	# 代际号：被抢占的节点，上一次的归还回调必须作废，避免同一个节点被放回池两次。
	var generation := int(label.get_meta("generation", 0)) + 1
	label.set_meta("generation", generation)
	label.text = str(int(round(amount)))
	label.modulate = color
	label.position = pos + Vector3(randf_range(-0.25, 0.25), 0.0, randf_range(-0.25, 0.25))
	label.visible = true
	_damage_labels_active.append(label)
	var start_y := label.position.y
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(label, "position:y", start_y + 0.9, 0.65)
	tween.tween_property(label, "modulate:a", 0.0, 0.65)
	tween.chain().tween_callback(func():
		if not is_instance_valid(label):
			return
		if int(label.get_meta("generation", 0)) != generation:
			return
		label.visible = false
		label.modulate.a = 1.0
		_damage_labels_active.erase(label)
		_damage_labels_pool.append(label)
	)
	label.set_meta("tween", tween)

func _spawn_ring(pos: Vector3, color: Color, from_scale: float, to_scale: float, duration: float, alpha := 0.65) -> void:
	if _effects_root == null:
		return
	var slot: Dictionary = take_particle_slot(_ring_pool, _ring_active)
	if slot.is_empty():
		return
	var ring: MeshInstance3D = slot.get("node")
	if bool(slot.get("stolen", false)):
		var old_tween: Variant = ring.get_meta("tween", null)
		if old_tween is Tween and (old_tween as Tween).is_valid():
			(old_tween as Tween).kill()
	var generation := int(ring.get_meta("generation", 0)) + 1
	ring.set_meta("generation", generation)
	var material := ring.material_override as StandardMaterial3D
	if material == null:
		material = _make_fx_material(BaseMaterial3D.BLEND_MODE_ADD)
		material.emission_energy_multiplier = 1.6
		ring.material_override = material
	material.albedo_color = Color(color.r, color.g, color.b, alpha)
	material.emission = color
	ring.position = Vector3(pos.x, 0.1, pos.z)
	ring.scale = Vector3.ONE * from_scale
	ring.visible = true
	_ring_active.append(ring)
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(ring, "scale", Vector3.ONE * to_scale, duration)
	tween.tween_property(material, "albedo_color:a", 0.0, duration)
	tween.chain().tween_callback(func():
		if not is_instance_valid(ring):
			return
		if int(ring.get_meta("generation", 0)) != generation:
			return
		ring.visible = false
		_ring_active.erase(ring)
		_ring_pool.append(ring)
	)
	ring.set_meta("tween", tween)

# 从池里取一个粒子节点：优先空闲池，其次抢占最老的活动节点。
# 抽成静态函数是为了能在无头环境里断言「不会把同一个节点借两次」——
# 真机上它只由 _spawn_particles 调用，两个数组会被就地修改（pop）。
static func take_particle_slot(pool: Array, active: Array) -> Dictionary:
	if not pool.is_empty():
		return {"node": pool.pop_back(), "stolen": false}
	if not active.is_empty():
		return {"node": active.pop_front(), "stolen": true}
	return {}

func _spawn_particles(pos: Vector3, color: Color, amount := 14, speed := 3.5, size := 0.12, lifetime := 0.55) -> void:
	if _effects_root == null:
		return
	particle_bursts += 1
	var slot: Dictionary = take_particle_slot(_hit_particles_pool, _hit_particles_active)
	if slot.is_empty():
		return
	var p: GPUParticles3D = slot.get("node")
	if bool(slot.get("stolen", false)):
		# 池空时抢占最老的一簇：它已经在尾焰里、肉眼快看不见了，
		# 掐掉它比掐掉玩家刚放出来的这一簇划算得多。
		particle_steals += 1
	# 代际号：被抢占的节点，它上一次的归还回调必须作废，
	# 否则会把正在使用中的节点又塞回池里，造成同一节点被借两次。
	var generation := int(p.get_meta("generation", 0)) + 1
	p.set_meta("generation", generation)
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
	_hit_particles_active.append(p)
	get_tree().create_timer(lifetime + 0.1).timeout.connect(func():
		if not is_instance_valid(p):
			return
		if int(p.get_meta("generation", 0)) != generation:
			return
		p.emitting = false
		_hit_particles_active.erase(p)
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

# 英雄普攻刀光：从池里借一片新月，按英雄朝向张开，边扫边淡出。
#
# 四个取舍：
# ① 朝向：网格朝局部 +X 张开，绕 Y 转 yaw = atan2(-dir.y, dir.x) 才对准 `direction`
#    （绕 Y 转 θ 后局部 +X 指向世界 (cosθ, 0, -sinθ)）；
# ② 挥击感：把旋转从 yaw 扫到 yaw + arc*0.22，同时略放大 —— 静止一片弧读成「贴图」；
# ③ 高度：放在胸口，不贴地：51° 俯角下贴地会被路面和血迹吃掉；
# ④ 混合模式用 MIX 而不是 ADD：叠加混合在石板路 / 桥面上会被抬成一片白，
#    和塔光束、小兵弹丸是同一个坑（见 _init_vfx_pools 里那两处注释）。
func _spawn_slash(center: Vector3, direction: Vector2, color: Color, reach: float, arc_deg: float, duration: float) -> void:
	if _effects_root == null:
		return
	var slot: Dictionary = take_particle_slot(_slash_pool, _slash_active)
	if slot.is_empty():
		return
	var slash: MeshInstance3D = slot.get("node")
	if bool(slot.get("stolen", false)):
		var old_tween: Variant = slash.get_meta("tween", null)
		if old_tween is Tween and (old_tween as Tween).is_valid():
			(old_tween as Tween).kill()
	var generation := int(slash.get_meta("generation", 0)) + 1
	slash.set_meta("generation", generation)
	var material := slash.material_override as StandardMaterial3D
	material.albedo_color = Color(color.r, color.g, color.b, 0.95)
	material.emission = color
	var size := maxf(reach, 0.6)
	var yaw := atan2(-direction.y, direction.x)
	slash.position = center
	slash.rotation = Vector3(0.0, yaw, 0.0)
	slash.scale = Vector3.ONE * size
	slash.visible = true
	_slash_active.append(slash)
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(slash, "rotation:y", yaw + deg_to_rad(maxf(arc_deg, 0.0) * 0.22), duration)
	tween.tween_property(slash, "scale", Vector3.ONE * size * HERO_SLASH_GROW, duration)
	tween.tween_property(material, "albedo_color:a", 0.0, duration)
	tween.chain().tween_callback(func():
		if not is_instance_valid(slash):
			return
		if int(slash.get_meta("generation", 0)) != generation:
			return
		slash.visible = false
		_slash_active.erase(slash)
		_slash_pool.append(slash)
	)
	slash.set_meta("tween", tween)

# 小兵普攻弹道 / 近战刀光：从池里借一颗发光球飞向目标。
# 近战用极短 duration（0.06~0.1s），看上去就是一道瞬时刀光。
func _spawn_tracer(from: Vector3, to: Vector3, color: Color, radius: float, duration: float) -> void:
	if _effects_root == null:
		return
	var slot: Dictionary = take_particle_slot(_tracer_pool, _tracer_active)
	if slot.is_empty():
		return
	var orb: MeshInstance3D = slot.get("node")
	var generation := int(orb.get_meta("generation", 0)) + 1
	orb.set_meta("generation", generation)
	var previous: Variant = orb.get_meta("tween") if orb.has_meta("tween") else null
	if previous is Tween and (previous as Tween).is_valid():
		(previous as Tween).kill()
	var material := orb.material_override as StandardMaterial3D
	material.albedo_color = Color(color.r, color.g, color.b, 0.95)
	material.emission = color
	material.emission_energy_multiplier = 1.6
	orb.visible = true
	orb.position = from
	orb.scale = Vector3.ONE * maxf(0.05, radius * 2.0)
	_tracer_active.append(orb)
	var tween := create_tween()
	tween.tween_property(orb, "position", to, maxf(0.03, duration))
	tween.tween_callback(func():
		if not is_instance_valid(orb) or int(orb.get_meta("generation", 0)) != generation:
			return
		orb.visible = false
		_tracer_active.erase(orb)
		_tracer_pool.append(orb)
	)
	orb.set_meta("tween", tween)

# 塔光束的几何：一根底面半径 0.5、高 1 的圆柱，缩放并旋转成 from→to。
# 必须用 scaled_local —— Basis.scaled 是按世界轴缩放，旋转后的光束会被压成竖直的。
static func lance_transform(from: Vector3, to: Vector3, radius: float) -> Transform3D:
	var delta := to - from
	var length := delta.length()
	var width := maxf(0.02, radius * 2.0)
	var basis := Basis(Quaternion(Vector3.UP, delta / maxf(length, 0.0001))).scaled_local(Vector3(width, length, width))
	return Transform3D(basis, (from + to) * 0.5)

# 防御塔光束：一根从水晶枪口指向目标的细圆柱，短暂淡出。
# 旧实现只有一颗飞过的小球，远看几乎看不见「塔开火了」。
func _spawn_lance(from: Vector3, to: Vector3, color: Color, radius: float, duration: float) -> void:
	if _effects_root == null:
		return
	if (to - from).length() < 0.05:
		return
	var slot: Dictionary = take_particle_slot(_lance_pool, _lance_active)
	if slot.is_empty():
		return
	var lance: MeshInstance3D = slot.get("node")
	var generation := int(lance.get_meta("generation", 0)) + 1
	lance.set_meta("generation", generation)
	var previous: Variant = lance.get_meta("tween") if lance.has_meta("tween") else null
	if previous is Tween and (previous as Tween).is_valid():
		(previous as Tween).kill()
	var material := lance.material_override as StandardMaterial3D
	material.albedo_color = Color(color.r, color.g, color.b, 0.85)
	material.emission = color
	material.emission_energy_multiplier = 0.8
	lance.transform = lance_transform(from, to, radius)
	lance.visible = true
	_lance_active.append(lance)
	var tween := create_tween()
	tween.tween_property(material, "albedo_color:a", 0.0, duration)
	tween.tween_callback(func():
		if not is_instance_valid(lance) or int(lance.get_meta("generation", 0)) != generation:
			return
		lance.visible = false
		_lance_active.erase(lance)
		_lance_pool.append(lance)
	)
	lance.set_meta("tween", tween)

func _explosion(pos: Vector3, color: Color, amount: int) -> void:
	_spawn_particles(pos, color, amount, 6.0, 0.16, 0.7)
	_spawn_particles(pos, Color(1.0, 0.85, 0.55), int(amount * 0.5), 4.0, 0.1, 0.5)
	_spawn_ring(Vector3(pos.x, 0.12, pos.z), color, 0.6, 4.5, 0.55)

# 英雄特效色：谱系色只认这几个英雄。static 是为了让纯函数
# hero_attack_fx_plan() 也能取到同一份颜色（测试要断言「不同英雄颜色不同」）。
static func _hero_vfx_color(hero_type: String) -> Color:
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
