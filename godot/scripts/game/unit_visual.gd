extends Node3D
class_name UnitVisual

const ModelUtils = preload("res://scripts/game/model_utils.gd")
const BushEye = preload("res://scripts/game/bush_eye.gd")
const MonsterForms = preload("res://scripts/game/monster_forms.gd")
const HeroModelRegistry = preload("res://scripts/game/hero_model_registry.gd")
const MonsterKit = preload("res://scripts/game/monster_kit.gd")
const BAR_SHADER := preload("res://shaders/billboard_bar.gdshader")

const BLUE := Color(0.22, 0.6, 1.0)
const RED := Color(1.0, 0.32, 0.26)
const GOLD := Color(1.0, 0.78, 0.32)
# 蓝条比友军血条更暗：同一个友军英雄头顶两条蓝叠着，
# 靠亮度 + 血条两倍厚度区分。别把 MANA 调亮到和 HP_ALLY 一样。
const MANA := Color(0.18, 0.30, 0.78)
# 血条按「与本地玩家的关系」着色，而不是绝对阵营：
#   自己 = 绿、友军 = 蓝、敌军 = 红（含中立野怪）。
#
# 这三个值不是「眼睛挑的色」，是按 arena 的渲染管线反解出来的：
# 场景用 TONE_MAPPER_FILMIC + exposure 1.05，FILMIC 的肩部会把中间调整体提亮，
# 绿色和蓝色的 G 通道被抬得最狠。直接写纯色的话，友军蓝渲染到屏幕上会变成
# 青白（实测 (0.34,0.74,1.0) 出来是 (0.45,0.87,1.00)，G 和 B 一起顶到 1.0），
# 自己绿则发白发黄。所以这里刻意压低 G，让**最终像素**落回纯绿 / 纯蓝 / 纯红。
# 实测渲染色（tools/bar_color_shot.gd 采样中心像素）：
#   自己 (0.24,0.72,0.30) -> (0.31,0.85,0.39) 绿
#   友军 (0.20,0.40,0.98) -> (0.25,0.53,1.00) 蓝
#   敌军 (0.82,0.13,0.15) -> (0.92,0.15,0.18) 红
# 改这三个值前先跑那个截图工具，别只看常量。
const HP_SELF := Color(0.24, 0.72, 0.30)
const HP_ALLY := Color(0.20, 0.40, 0.98)
const HP_ENEMY := Color(0.82, 0.13, 0.15)
const FONT_PATH := "res://assets/fonts/NotoSansSC.ttf"
# --- 英雄 / 小兵 的体型 ---
# 王者荣耀官方「王者世界」身高表：男英雄 176–197cm（李白 184、韩信 185、廉颇 190），
# 女英雄 165–180，主流按 180cm 算；普通小兵约 150cm（鲁班 149、李元芳 152 常被形容
# 「和小兵差不多高」）。也就是说**设定身高比只有 1.2 : 1**，远没有很多人以为的 2~3 倍。
# 游戏里之所以一眼分得出，靠的不是身高：小兵体型窄（肩宽约英雄 5 成）、穿统一兵种配色、
# 没有名字与描边；而且王者荣耀镜头很近，英雄约占屏高 1/6。
# 我们的相机 zoom 21 下英雄只占屏高 ~7%，1.2 的身高差在屏幕上不到 10 个像素，
# 再叠加小兵用的是 Q 版大头模型，两者视觉体量几乎一样 —— 这才是「分不出英雄和小兵」的根因。
# 所以按「屏幕可辨识」取值：英雄 2.7 : 小兵 1.15 ≈ 2.35 : 1，并把小兵横向收窄到 0.9，
# 等效于王者荣耀「英雄明显大一号、小兵又瘦又整齐」的观感。
# 想严格照设定身高比（1.2:1）时，把 MINION_HEIGHT 改成 HERO_HEIGHT / 1.2 即可。
const HERO_HEIGHT := 2.7
const MINION_HEIGHT := 1.15
const MINION_GIRTH := 0.9
# 双狼营地的狼：比小兵高一点、比英雄矮一半 —— 俯视下「狼比小兵大、比英雄小」。
const WOLF_HEIGHT := 1.45
# 头顶血条按世界单位定尺寸。英雄条比小兵/野怪更宽更厚：
# 默认镜头下英雄只占屏高 ~7%，1.24×0.14 的细条在手机竖屏上读不出剩余血量。
# 1.9×0.26 是玩家反馈「血条太短太细」后的加宽加粗版；蓝条同宽、厚度约一半，
# 保持 test_hero_readout 的契约（宽 ≥1.4、厚 ≥0.18、蓝条薄于血条且在其下方不重叠）。
# 小兵/野怪仍走 width_scale 等比缩放，见 _add_health_bar。
const HERO_BAR_SIZE := Vector2(1.9, 0.26)
const HERO_MANA_SIZE := Vector2(1.9, 0.13)
const HERO_MANA_GAP := 0.03
const OTHER_BAR_SIZE := Vector2(1.24, 0.14)
# 首领体型：暴君 / 主宰必须比英雄（2.7 m）明显大一圈，否则四个营地共用
# 两种模型时，首领在俯视下只是一只「血多一点的野怪」。
# 3.8 / 4.2 = 英雄的 1.41 / 1.56 倍；Orc 模型按高度等比放大后宽约
# 5.1 / 5.7 m，正好对上模拟层 2.6 / 2.8 的碰撞半径 —— 玩家看到的身板
# 与真实受击范围一致，普攻距离才不会读成「隔空打」。
const TYRANT_HEIGHT := 3.8
const OVERLORD_HEIGHT := 4.2
# 首领血条比普通野怪宽 1.55 倍（≈ 英雄血条宽度），4 米高的身板上
# 1.1 米宽的细条会小到读不出剩余血量。
const OBJECTIVE_BAR_WIDTH := 1.55

const UAL1 := preload("res://assets/animations/ual1.glb")
const UAL2 := preload("res://assets/animations/ual2.glb")

const HERO_SETUPS := {
	"blade": {
		"body": preload("res://assets/characters/hero_warrior.glb"),
		"outfit": preload("res://assets/characters/outfit_ranger_m.glb"),
		"hair": preload("res://assets/characters/hair_buzzed.glb"),
		"weapon": preload("res://assets/weapons/Claymore.glb"),
		"body_scale": Vector3(1.06, 1.0, 1.02),
		"weapon_scale": 0.28,
		"accent": Color(1.0, 0.72, 0.30),
		"weapon_tint_amount": 0.30,
		"weapon_rotation": Vector3(0.0, 0.0, 0.0),
		"weapon_offset": Vector3(0.0, 0.0, 0.0),
		"weapon_bone": "hand_r",
		"idle": "Sword_Idle",
		"outfit_tint": Color(0.33, 0.52, 0.28),
		"tint_amount": 0.1,
	},
	"mage": {
		"body": preload("res://assets/characters/hero_mage.glb"),
		"outfit": preload("res://assets/characters/outfit_ranger_f.glb"),
		"hair": preload("res://assets/characters/hair_long.glb"),
		"weapon": preload("res://assets/weapons/Scythe.glb"),
		"body_scale": Vector3(0.96, 1.0, 0.96),
		"weapon_scale": 0.30,
		"accent": Color(0.62, 0.50, 1.0),
		"weapon_tint_amount": 0.35,
		"weapon_rotation": Vector3(0.0, 0.0, 0.0),
		"weapon_offset": Vector3(0.0, 0.0, 0.0),
		"weapon_bone": "hand_r",
		"idle": "Spell_Simple_Idle",
		"outfit_tint": Color(0.34, 0.3, 0.78),
		"tint_amount": 0.5,
	},
	"tank": {
		"body": preload("res://assets/characters/hero_warrior.glb"),
		"outfit": preload("res://assets/characters/outfit_peasant_m.glb"),
		"hair": preload("res://assets/characters/hair_beard.glb"),
		"weapon": preload("res://assets/weapons/Hammer_Double.glb"),
		"body_scale": Vector3(1.18, 1.0, 1.10),
		"weapon_scale": 0.35,
		"accent": Color(0.40, 0.85, 0.80),
		"weapon_tint_amount": 0.28,
		"weapon_rotation": Vector3(0.0, 0.0, 0.0),
		"weapon_offset": Vector3(0.0, 0.0, 0.0),
		"weapon_bone": "hand_r",
		"idle": "Sword_Idle",
		"outfit_tint": Color(0.6, 0.36, 0.2),
		"tint_amount": 0.45,
	},
	"archer": {
		"body": preload("res://assets/characters/hero_mage.glb"),
		"outfit": preload("res://assets/characters/outfit_ranger_f.glb"),
		"hair": preload("res://assets/characters/hair_buns.glb"),
		"weapon": preload("res://assets/weapons/Bow_Wooden2.glb"),
		"body_scale": Vector3(0.90, 1.0, 0.92),
		"weapon_scale": 0.31,
		"accent": Color(0.55, 0.95, 0.50),
		"weapon_tint_amount": 0.32,
		"weapon_rotation": Vector3(0.0, 0.0, 0.0),
		"weapon_offset": Vector3(0.0, 0.0, 0.0),
		"weapon_bone": "hand_l",
		"idle": "Spell_Simple_Idle",
		"outfit_tint": Color(0.16, 0.5, 0.5),
		"tint_amount": 0.45,
	},
	"assassin": {
		"body": preload("res://assets/characters/hero_mage.glb"),
		"outfit": preload("res://assets/characters/outfit_peasant_f.glb"),
		"hair": preload("res://assets/characters/hair_buns.glb"),
		"weapon": preload("res://assets/weapons/Dagger.glb"),
		"body_scale": Vector3(0.84, 1.0, 0.88),
		"weapon_scale": 0.24,
		"accent": Color(0.88, 0.42, 0.72),
		"weapon_tint_amount": 0.34,
		"weapon_rotation": Vector3(0.0, 0.0, 0.0),
		"weapon_offset": Vector3(0.0, 0.0, 0.0),
		"weapon_bone": "hand_r",
		"idle": "Sword_Idle",
		"outfit_tint": Color(0.32, 0.15, 0.44),
		"tint_amount": 0.6,
	},
}

const LOOPING_CLIPS := ["Idle", "Jog_Fwd", "Sprint", "Sword_Idle", "Spell_Simple_Idle", "Idle_Shield"]

# 移动动画在 1.0 倍速下对应的「地面速度」（m/s）。UAL 的动作是原地循环，
# 本身没有米/秒语义，这个值是观感标定：速度 6.4 的英雄约等于 2 倍速播放，
# 步频落在 4 步/秒上下。低于它就滑步（像被拖着走），高于它就变成鬼畜。
const LOCO_REF_SPEED := 3.2
const LOCO_RATE_MIN := 1.0
const LOCO_RATE_MAX := 2.2
# 程序化倒地用多久倒到位（秒）。快于死亡停留时间，让「倒下 → 躺住」有个过程而不是瞬移。
const DEATH_FALL_SECONDS := 0.9
# 死亡后视图停留多久（秒）。倒地进度是**从这个值往回算**的（见 _update_death_pose）：
# 用「剩余时间」当进度会算反 —— death_timer 从 2.4 递减，进度要拿 2.4 - 剩余。
const DEATH_LINGER_SECONDS := 2.4
# 倒地之后再用 0.6s 沉进地面；重生从 0.25 倍缩放回 1.0。
# 这两个阶段只影响程序化野怪，不改变死亡停留时间与复活逻辑。
const DEATH_SINK_SECONDS := 0.6
const DEATH_SINK_SCALE := 0.18
const SPAWN_SCALE_SECONDS := 0.25
# 受击/攻击反馈的时长。全部是表现层计时，不进快照、不进协议。
const HIT_FLASH_SECONDS := 0.10
const HIT_SQUASH_SECONDS := 0.16
const ATTACK_LUNGE_SECONDS := 0.18
const ATTACK_LUNGE_DISTANCE := 0.16
# 野怪出手的前冲倍数。小兵是 0.16 米，野怪体型大一圈（普通 1.45m / BUFF 石像 2m /
# 首领 3.8~4.2m），照抄 0.16 在 21 米机位下等于没动。倍数由 Arena 按体型给，
# 这里只定义「基准 + 上限」，避免首领前冲把自己甩出脚下环。
const MONSTER_LUNGE_SCALE := 2.2
const MONSTER_LUNGE_MAX := 0.62

const ANIM_ATTACK := {
	"blade": "Sword_Regular_A",
	"mage": "Spell_Simple_Shoot",
	"tank": "Sword_Regular_B",
	"archer": "Spell_Simple_Shoot",
	"assassin": "Sword_Regular_A",
}
const ANIM_Q := {
	"blade": "Sword_Regular_C",
	"mage": "Spell_Simple_Shoot",
	"tank": "Shield_Dash_RM",
	"archer": "Spell_Simple_Shoot",
	"assassin": "Slide",
}
const ANIM_E := {
	"blade": "Slide",
	"mage": "Spell_Simple_Shoot",
	"tank": "Shield_Dash_RM",
	"archer": "Roll",
	"assassin": "Roll",
}
# W 是「中段技能」：连斩 / 蓄力 / 冲撞 / 点射 / 反手斩。
const ANIM_W := {
	"blade": "Sword_Regular_Combo",
	"mage": "Spell_Simple_Enter",
	"tank": "Sword_Dash_RM",
	"archer": "Spell_Simple_Shoot",
	"assassin": "Sword_Regular_B",
}
# R 是大招：跳斩 / 抛掷 / 举盾。以前非 Q 一律播 E 的动作，
# 于是翎羽和墨鸦放大会原地「滚」一下，完全读不出这是大招。
const ANIM_R := {
	"blade": "NinjaJump_Start",
	"mage": "OverhandThrow",
	"tank": "Shield_OneShot",
	"archer": "Spell_Simple_Enter",
	"assassin": "NinjaJump_Start",
}

static var _source_animations: Dictionary = {}
static var _library_cache: Dictionary = {}
static var _font: Font = null
# 小兵配件材质按颜色缓存：池里的几十个小兵不各自 new 一份。
static var _minion_mat_cache: Dictionary = {}

var kind := "hero"
var team := "blue"
var hero_type := "blade"
var display_name := ""
var is_local := false
# 本地玩家所在阵营。血条靠它判断「友军 / 敌军」，
# 留空（预览工具、离线截图）时一律按敌军处理。
var viewer_team := ""
var monster_type := ""
var minion_type := "melee"
# 首领（暴君 / 主宰）走更大体型的独立分支；objective_id 用来区分两座坑。
var is_objective := false
var objective_id := ""
# 野怪形态键（wolf / lizard / boar / bird / blue_sentinel / red_sentinel / tyrant / overlord）。
# 由 camp_id / monster_type 派生，见 _build_monster()：**形象不靠名字猜**，靠快照里已有的字段。
var monster_form := ""
# 野点 id（快照里的 camp_id）。表现层用它查「这个野点该长什么样」，
# 见 MonsterForms.CAMP_FORMS —— 不新增 sim/联机字段。
var monster_camp := ""
# 程序化形态的部件表（腿/翅/尾/轨道/呼吸点）。这类形态没有 AnimationPlayer，
# 走路与倒地都由 process_visual 依据它驱动；空的表示这只怪用的是骨骼模型（狼）。
var _monster_spec: Dictionary = {}
# 装配完成时的静止姿态，倒地动画要在它之上叠加（见 _capture_model_rest_pose）。
var _model_rest_scale := Vector3.ONE
var _model_rest_position := Vector3.ZERO
var _hit_flash_timer := 0.0
var _hit_squash_timer := 0.0
var _attack_lunge_timer := 0.0
# 这一次前冲的力度倍数（1.0 = 小兵基准）。野怪体型比小兵大一圈，同样的 0.16 米
# 在 21 米机位下读不出「它扑了一下」。由 Arena 按体型给，默认 1.0 不改既有行为。
var _attack_lunge_strength := 1.0
var _spawn_scale_timer := 0.0
var _force_shared_hero := false
var flash_mesh: MeshInstance3D = null
var shield_bubble: MeshInstance3D = null
var buff_aura: MeshInstance3D = null
var slow_ring: MeshInstance3D = null
# 硬控状态环（项 4，链路 5）：眩晕/击飞/沉默/定身各有各的环，
# 玩家必须一眼看出"对方是被打晕了"还是"被封了技能"——这两种的应对完全不同。
# 复用 _make_status_ring，不再另造一套几何。
var cc_rings: Dictionary = {}
var _buff_aura_key := ""
var _minion_props: Dictionary = {}
var _minion_base_scale := Vector3.ONE

var model_root: Node3D
var body_root: Node3D
var animation_players: Array[AnimationPlayer] = []
var current_animation := ""
var action_timer := 0.0
var dead := false
var death_timer := 0.0
var hp_ratio := 1.0
var shield_ratio := 0.0
var level := 1
var moving := false
var haste := false
var unit_speed := 0.0
var _locomotion_rate := 1.0
var idle_anim := "Idle"
var _target_position := Vector3.ZERO
var _initialized := false
var _last_target := Vector3.ZERO
# 实体插值用：_prev_pos/_cur_pos 是相邻两个模拟 tick 的位置，
# 渲染帧按 alpha 在两者之间线性插值，得到匀速平滑的轨迹（指数平滑会一顿一顿）。
var _prev_pos := Vector3.ZERO
var _cur_pos := Vector3.ZERO
var _has_pos := false
# 上一帧的插值进度。变小说明进入了新的一格（tick / 快照区间推进），
# 用来识别「这一格位置没变 = 实体已经站住」。
var _last_alpha := 1.0
# 渲染状态缓存：这些值只在变化时写回 Label3D / ShaderMaterial，
# 避免 60fps 下对每个单位重复做字体排版与材质参数刷新。
var _shown_hp := -1.0
var _shown_shield := -1.0
var _shown_mp := -1.0
var _shown_level := -1
var _shown_bar_visible := true

var bar_root: Node3D
var bar_mesh: MeshInstance3D
var bar_material: ShaderMaterial
var mp_mesh: MeshInstance3D
var mp_material: ShaderMaterial
var mp_ratio := 0.0
var name_label: Label3D
var level_label: Label3D
# 进草后的「不可见」眼睛（仅本地英雄）。斜划眼挂在血条上方，
# 用 no_depth_test 保证被草丛叶簇挡住时仍然看得见 —— 它本来就是给玩家看的状态。
var bush_eye: Sprite3D = null
var bush_hidden := false
var _bush_eye_time := 0.0
var team_ring: MeshInstance3D
var local_ring: MeshInstance3D
var cast_light: OmniLight3D

func setup(
	unit_kind: String,
	unit_team: String,
	type_id: String,
	label: String,
	local: bool,
	viewer: String = "",
	objective: bool = false,
	pit_id: String = "",
	camp_id: String = ""
) -> void:
	kind = unit_kind
	team = unit_team
	hero_type = type_id
	is_objective = objective
	objective_id = pit_id
	monster_camp = camp_id
	if kind == "monster":
		monster_type = type_id
	elif kind == "minion":
		minion_type = "melee" if type_id == "" or type_id == "minion" else type_id
	display_name = label
	is_local = local
	viewer_team = viewer
	if kind == "hero":
		_build_hero()
	elif kind == "monster":
		_build_monster()
	else:
		_build_minion()

# 血条配色唯一真身：自己绿、友军蓝、敌军红。
# 传的是「本地玩家阵营」而不是单位阵营 —— 同一支蓝方英雄，
# 从红方玩家眼里看必须是红条。
static func bar_color(local: bool, unit_team: String, viewer_side: String) -> Color:
	if local:
		return HP_SELF
	if viewer_side != "" and unit_team == viewer_side:
		return HP_ALLY
	return HP_ENEMY

static func scale_for_height(measured_height: float, target_height: float) -> float:
	if measured_height <= 0.001 or target_height <= 0.0:
		return 1.0
	return target_height / measured_height

func can_recycle() -> bool:
	return kind == "minion" and dead and death_timer < -1.0

func recycle() -> void:
	visible = false
	dead = true
	for player in animation_players:
		if player:
			player.stop()

func reset_minion(new_team: String, new_pos: Vector3, new_type := "melee") -> void:
	team = new_team
	minion_type = new_type
	dead = false
	death_timer = 0.0
	action_timer = 0.0
	current_animation = ""
	_locomotion_rate = 1.0
	_last_alpha = 1.0
	_shown_hp = -1.0
	_shown_shield = -1.0
	_shown_mp = -1.0
	_shown_level = -1
	_shown_bar_visible = true
	visible = true
	_hit_flash_timer = 0.0
	_hit_squash_timer = 0.0
	_attack_lunge_timer = 0.0
	if flash_mesh:
		flash_mesh.visible = false
	if shield_bubble:
		shield_bubble.visible = false
	if buff_aura:
		buff_aura.visible = false
	if slow_ring:
		slow_ring.visible = false
	for entry in CC_RING_SPECS:
		var cc_ring: MeshInstance3D = cc_rings.get(str(entry[0]), null)
		if cc_ring != null:
			cc_ring.visible = false
	if model_root:
		model_root.position = _model_rest_position
		model_root.rotation = Vector3.ZERO
	_apply_minion_type_look(new_type)
	_spawn_scale_timer = SPAWN_SCALE_SECONDS
	_has_pos = false
	_initialized = false
	position = new_pos
	_prev_pos = new_pos
	_cur_pos = new_pos
	_last_target = new_pos
	rotation.y = 0.0
	if team_ring:
		team_ring.visible = true
		var ring_mat := team_ring.material_override as StandardMaterial3D
		if ring_mat:
			var ring_color := BLUE if team == "blue" else RED
			ring_mat.albedo_color = Color(ring_color.r, ring_color.g, ring_color.b, 0.8)
			ring_mat.emission = ring_color
	if bar_mesh:
		bar_mesh.visible = true
	if bar_material:
		bar_material.set_shader_parameter("ratio", 1.0)
		bar_material.set_shader_parameter("shield_ratio", 0.0)
	if mp_mesh:
		mp_mesh.visible = false
	if level_label:
		level_label.visible = false
	_set_anim("Idle", true)
	_cur_pos = new_pos
	_last_alpha = 1.0
	if team_ring:
		team_ring.visible = true
		var ring_mat := team_ring.material_override as StandardMaterial3D
		if ring_mat:
			var ring_color := BLUE if team == "blue" else RED
			ring_mat.albedo_color = Color(ring_color.r, ring_color.g, ring_color.b, 0.8)
			ring_mat.emission = ring_color
	if bar_material:
		bar_material.set_shader_parameter("ratio", 1.0)
		bar_material.set_shader_parameter("shield_ratio", 0.0)
	if bar_mesh:
		bar_mesh.visible = true
	for player in animation_players:
		if player:
			player.stop()
	current_animation = ""
	_set_anim("Idle", true)

func _build_hero() -> void:
	var setup_data: Dictionary = HERO_SETUPS.get(hero_type, HERO_SETUPS["blade"])
	if not _force_shared_hero and HeroModelRegistry.has_custom_model(hero_type):
		_build_custom_hero(setup_data)
		return
	var team_tint := Color(0.92, 0.25, 0.2) if team == "red" else Color(0.35, 0.55, 1.0)
	var team_tint_amount := 0.24 if team == "red" else 0.05
	model_root = Node3D.new()
	model_root.name = "Model"
	add_child(model_root)
	for slot in ["body", "outfit", "hair"]:
		var scene: PackedScene = setup_data[slot]
		var model: Node3D = scene.instantiate()
		model.name = str(slot).capitalize()
		model_root.add_child(model)
		if slot == "outfit":
			var tint_color: Color = setup_data.get("outfit_tint", Color.WHITE)
			ModelUtils.tint(model, tint_color, float(setup_data.get("tint_amount", 0.0)))
		ModelUtils.tint(model, team_tint, team_tint_amount)
		_attach_retargeted_player(model)
	var measured_height := ModelUtils.relative_aabb(model_root).size.y
	model_root.scale = Vector3.ONE * scale_for_height(measured_height, HERO_HEIGHT)
	# 只压/放横轴：身高仍锚在 HERO_HEIGHT，剪影靠肩宽与武器区分。
	var body_scale: Vector3 = setup_data.get("body_scale", Vector3.ONE)
	model_root.scale = Vector3(model_root.scale.x * body_scale.x, model_root.scale.y, model_root.scale.z * body_scale.z)
	_equip_weapon(setup_data)
	_capture_model_rest_pose()
	_add_ring(0.9)
	if is_local:
		local_ring = _make_ring(1.15, GOLD, 0.55)
		local_ring.position.y = 0.02
		add_child(local_ring)
	_add_health_bar(HERO_HEIGHT + 0.30)
	_build_status_fx(HERO_HEIGHT, 0.62)
	idle_anim = str(setup_data.get("idle", "Idle"))
	_set_anim(idle_anim, true)
	process_priority = 10
	# 单位数量多、始终处于镜头附近，阴影 pass 的收益远低于开销；
	# 建筑与环境保留阴影，单位用脚下队伍环提供接地感。
	ModelUtils.enable_shadows(self, false)

# HERO-04 定制模型：模型自带服装/武器/骨骼/动作，不再拼 body/outfit/hair/weapon。
# 缺失时完全回退现有共享模型，保证没有资产时游戏照常运行。
func _build_custom_hero(setup_data: Dictionary) -> void:
	var scene: PackedScene = load(HeroModelRegistry.model_path(hero_type)) as PackedScene
	if scene == null:
		_force_shared_hero = true
		_build_hero()
		_force_shared_hero = false
		return
	var model := scene.instantiate()
	model.name = "Model"
	model_root = model
	add_child(model_root)
	for node in model_root.find_children("*", "AnimationPlayer", true, false):
		var player := node as AnimationPlayer
		if player:
			animation_players.append(player)
			player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_IDLE
	var team_tint := Color(0.92, 0.25, 0.2) if team == "red" else Color(0.35, 0.55, 1.0)
	ModelUtils.tint(model_root, team_tint, 0.06)
	var measured_height := ModelUtils.relative_aabb(model_root).size.y
	model_root.scale = Vector3.ONE * scale_for_height(measured_height, HERO_HEIGHT)
	_capture_model_rest_pose()
	_add_ring(0.9)
	if is_local:
		local_ring = _make_ring(1.15, GOLD, 0.55)
		local_ring.position.y = 0.02
		add_child(local_ring)
	_add_health_bar(HERO_HEIGHT + 0.30)
	_build_status_fx(HERO_HEIGHT, 0.62)
	idle_anim = str(setup_data.get("idle", "Idle"))
	_set_anim(idle_anim, true)
	process_priority = 10
	ModelUtils.enable_shadows(self, false)

func _build_minion() -> void:
	var scene: PackedScene
	if team == "blue":
		scene = preload("res://assets/characters/Skeleton_Warrior.glb")
	else:
		scene = preload("res://assets/characters/Skeleton_Rogue.glb")
	var fitted := ModelUtils.fit_scene(scene, MINION_HEIGHT)
	fitted.name = "Model"
	model_root = fitted
	# 只压横轴：小兵要瘦，但不改身高（fit_scene 已经把高度对齐到 MINION_HEIGHT）。
	model_root.scale = Vector3(MINION_GIRTH, 1.0, MINION_GIRTH)
	add_child(model_root)
	for node in model_root.find_children("*", "AnimationPlayer", true, false):
		var player := node as AnimationPlayer
		if player:
			animation_players.append(player)
			player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_IDLE
	_minion_base_scale = model_root.scale
	_build_minion_props()
	_apply_minion_type_look(minion_type)
	_capture_model_rest_pose()
	_add_ring(0.44)
	_add_health_bar(MINION_HEIGHT + 0.16, 0.62)
	_build_status_fx(MINION_HEIGHT, 0.40)
	_set_anim("Idle", true)
	_spawn_scale_timer = SPAWN_SCALE_SECONDS
	ModelUtils.enable_shadows(self, false)

func _build_monster() -> void:
	if monster_type == "spirit":
		_build_river_spirit()
		return
	var form := MonsterForms.form_key(monster_type, is_objective, objective_id, monster_camp)
	monster_form = form
	var objective_height := OVERLORD_HEIGHT if objective_id == "overlord" else TYRANT_HEIGHT
	var spec := MonsterForms.build(form, objective_height)
	if not spec.is_empty():
		_build_procedural_monster(spec)
		return
	_build_wolf_monster()

# 程序化野怪：形象由 MonsterForms 拼好，UnitVisual 只管挂上、对齐血条与脚下环。
# 这类形态**没有 AnimationPlayer**，走路/呼吸/死亡全部由 process_visual 里的
# 程序化动画驱动，所以这里必须把 spec 留下来（_monster_spec）。
func _build_procedural_monster(spec: Dictionary) -> void:
	_monster_spec = spec
	model_root = spec.get("root", null)
	if model_root == null:
		# 形态字典里没有 root = 装配失败。退回狼模型，绝不留下「看不见却能被打」的空模型。
		_build_wolf_monster()
		return
	add_child(model_root)
	var target_height := float(spec.get("height", 1.5))
	var bar_width := float(spec.get("bar_width", 0.9))
	monster_form = str(spec.get("form", monster_form))
	_capture_model_rest_pose()
	# 脚下环贴着形态的真实体量：石像比蜥蜴宽一圈，首领占满整个坑。
	_add_ring(MonsterForms.ring_radius(monster_form))
	_build_status_fx(target_height, clampf(target_height * 0.28, 0.45, 2.4))
	if is_objective:
		_add_health_bar(target_height + 0.55, bar_width)
	else:
		_add_health_bar(target_height + 0.25, bar_width)
	_set_anim("Idle", true)
	_spawn_scale_timer = SPAWN_SCALE_SECONDS
	ModelUtils.enable_shadows(self, false)

# 狼：现成模型（双狼营地本来就是狼），只补两处 —— 高度对齐、眼睛点亮。
# 保留 glb 的 Idle/Walk/Gallop/Death 骨骼动作，这是程序化形态没有的东西。
func _build_wolf_monster() -> void:
	_monster_spec = {}
	monster_form = "wolf"
	var fitted := ModelUtils.fit_scene(preload("res://assets/characters/Wolf.glb"), WOLF_HEIGHT)
	fitted.name = "Model"
	model_root = fitted
	add_child(model_root)
	for node in model_root.find_children("*", "AnimationPlayer", true, false):
		var player := node as AnimationPlayer
		if player:
			animation_players.append(player)
			player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_IDLE
	_polish_wolf(model_root)
	_capture_model_rest_pose()
	_add_ring(MonsterForms.ring_radius("wolf"))
	_build_status_fx(WOLF_HEIGHT, 0.52)
	_add_health_bar(WOLF_HEIGHT + 0.25, 0.9)
	_set_anim("Idle", true)
	_spawn_scale_timer = SPAWN_SCALE_SECONDS
	ModelUtils.enable_shadows(self, false)

# 狼原本是一团灰白：在草地上、和石头一个色，玩家要凑近才认得出是活物。
# 把 glb 里那对「黑眼睛」换成自发光琥珀色，20 米机位下那两点亮光就是「它是活的」。
# 材质走 MonsterKit 的静态缓存，重生时不会新建材质（硬规则 4）。
func _polish_wolf(root: Node3D) -> void:
	var eyes := MonsterKit.glow(Color(1.0, 0.72, 0.28), 1.9)
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.mesh == null:
			continue
		for surface in mesh_instance.mesh.get_surface_count():
			var material := mesh_instance.get_active_material(surface)
			if material != null and str(material.resource_name).to_lower().contains("eye"):
				mesh_instance.set_surface_override_material(surface, eyes)

# 记下装配完成时的静止姿态：倒地动画（程序化形态没有骨骼动作）要在这个姿态上叠加，
# 否则会覆盖 fit_height 算出来的缩放与贴地偏移，野怪一死就变大/浮空。
func _capture_model_rest_pose() -> void:
	if model_root == null:
		return
	_model_rest_scale = model_root.scale
	_model_rest_position = model_root.position

# 复活：把倒地姿态收回去。野怪在自己视野内被打死又刷新的情况下视图不会重建，
# 少了这一步它就会带着「趴在地上」的旋转继续站着打人。
func _restore_model_rest_pose() -> void:
	if model_root == null:
		return
	model_root.rotation = Vector3.ZERO
	model_root.scale = _model_rest_scale
	model_root.position = _model_rest_position

# 死亡动作名。三种单位三种命名，不能互相顶替：
#   英雄 ual 动作库叫 Death01；小兵 Skeleton_* 叫 Death_A；狼 glb 叫 Death。
# 程序化形态没有 AnimationPlayer，_set_anim 会静默跳过，倒地交给 _update_death_pose()。
func _death_anim() -> String:
	if kind == "hero":
		return "Death01"
	if kind == "monster" and _monster_spec.is_empty():
		return "Death"
	return "Death_A"

func _build_river_spirit() -> void:
	var root := Node3D.new()
	root.name = "Model"
	model_root = root
	add_child(root)
	_capture_model_rest_pose()

	var body_material := StandardMaterial3D.new()
	body_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	body_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	body_material.albedo_color = Color(0.4, 0.86, 0.95, 0.88)
	body_material.emission_enabled = true
	body_material.emission = Color(0.38, 0.82, 0.96)
	body_material.emission_energy_multiplier = 1.8
	var fin_material := StandardMaterial3D.new()
	fin_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fin_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fin_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	fin_material.albedo_color = Color(0.55, 0.92, 1.0, 0.55)
	fin_material.emission_enabled = true
	fin_material.emission = Color(0.45, 0.88, 1.0)
	fin_material.emission_energy_multiplier = 1.2
	fin_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	var eye_material := StandardMaterial3D.new()
	eye_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	eye_material.albedo_color = Color(0.95, 1.0, 1.0)
	eye_material.emission_enabled = true
	eye_material.emission = Color(0.9, 1.0, 1.0)
	eye_material.emission_energy_multiplier = 2.6

	# 水滴形身体 + 头 + 双眼：俯视先读出一条有朝向的剪影，而不是一颗圆球。
	var body := MeshInstance3D.new()
	body.name = "SpiritBody"
	var body_mesh := SphereMesh.new()
	body_mesh.radius = 0.5
	body_mesh.height = 1.0
	body_mesh.radial_segments = 16
	body_mesh.rings = 8
	body.mesh = body_mesh
	body.material_override = body_material
	body.scale = Vector3(0.88, 1.28, 0.82)
	body.position = Vector3(0.0, 1.05, 0.0)
	body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(body)
	var head := MeshInstance3D.new()
	head.name = "SpiritHead"
	var head_mesh := SphereMesh.new()
	head_mesh.radius = 0.3
	head_mesh.height = 0.6
	head_mesh.radial_segments = 14
	head_mesh.rings = 7
	head.mesh = head_mesh
	head.material_override = body_material
	head.position = Vector3(0.0, 1.58, 0.18)
	head.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(head)
	for side in [-1.0, 1.0]:
		var eye := MeshInstance3D.new()
		eye.name = "SpiritEye" + ("L" if side < 0.0 else "R")
		var eye_mesh := SphereMesh.new()
		eye_mesh.radius = 0.06
		eye_mesh.height = 0.12
		eye_mesh.radial_segments = 8
		eye_mesh.rings = 4
		eye.mesh = eye_mesh
		eye.material_override = eye_material
		eye.position = Vector3(side * 0.12, 1.64, 0.43)
		eye.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(eye)
	# 两侧鳍：扁平的发光片，给俯视剪影一条横向"鱼"的轮廓。
	for side in [-1.0, 1.0]:
		var fin := MeshInstance3D.new()
		fin.name = "SpiritFin" + ("L" if side < 0.0 else "R")
		var fin_mesh := SphereMesh.new()
		fin_mesh.radius = 0.5
		fin_mesh.height = 1.0
		fin_mesh.radial_segments = 8
		fin_mesh.rings = 4
		fin.mesh = fin_mesh
		fin.material_override = fin_material
		fin.scale = Vector3(0.10, 0.30, 0.42)
		fin.position = Vector3(side * 0.52, 1.08, -0.02)
		fin.rotation.z = side * 0.35
		fin.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(fin)
	# 尾：三节递减的水珠 + 尾鳍，往后下方拖。
	var tail := Node3D.new()
	tail.name = "SpiritTail"
	tail.position = Vector3(0.0, 0.98, -0.38)
	root.add_child(tail)
	for i in 3:
		var bead := MeshInstance3D.new()
		var bead_mesh := SphereMesh.new()
		bead_mesh.radius = 0.24 - float(i) * 0.06
		bead_mesh.height = bead_mesh.radius * 2.0
		bead_mesh.radial_segments = 10
		bead_mesh.rings = 5
		bead.mesh = bead_mesh
		bead.material_override = fin_material
		bead.position = Vector3(0.0, -0.04 * float(i), -0.18 - float(i) * 0.26)
		bead.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		tail.add_child(bead)
	var tail_fin := MeshInstance3D.new()
	var tail_fin_mesh := SphereMesh.new()
	tail_fin_mesh.radius = 0.5
	tail_fin_mesh.height = 1.0
	tail_fin_mesh.radial_segments = 8
	tail_fin_mesh.rings = 4
	tail_fin.mesh = tail_fin_mesh
	tail_fin.material_override = fin_material
	tail_fin.scale = Vector3(0.06, 0.26, 0.34)
	tail_fin.position = Vector3(0.0, -0.08, -0.78)
	tail.add_child(tail_fin)
	# 伴游光点：一圈小水珠绕体缓转，静止时也有生命感。
	var orbit := Node3D.new()
	orbit.name = "SpiritOrbit"
	orbit.position = Vector3(0.0, 1.2, 0.0)
	root.add_child(orbit)
	for i in 3:
		var drop := MeshInstance3D.new()
		var drop_mesh := SphereMesh.new()
		drop_mesh.radius = 0.07
		drop_mesh.height = 0.14
		drop_mesh.radial_segments = 8
		drop_mesh.rings = 4
		drop.mesh = drop_mesh
		drop.material_override = eye_material
		var angle := TAU * float(i) / 3.0
		drop.position = Vector3(cos(angle) * 0.72, 0.0, sin(angle) * 0.72)
		drop.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		orbit.add_child(drop)
	var halo := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.86
	torus.outer_radius = 0.94
	torus.rings = 28
	torus.ring_segments = 6
	halo.mesh = torus
	halo.rotation.x = -PI * 0.4
	var halo_material := StandardMaterial3D.new()
	halo_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	halo_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	halo_material.albedo_color = Color(0.8, 0.97, 1.0, 0.55)
	halo_material.emission_enabled = true
	halo_material.emission = Color(0.7, 0.95, 1.0)
	halo_material.emission_energy_multiplier = 1.4
	halo.material_override = halo_material
	halo.position.y = 1.0
	halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(halo)
	_add_ring(0.7)
	_add_health_bar(2.0, 0.9)
	_build_status_fx(2.0, 0.55)
	_set_anim("Idle", true)
	_spawn_scale_timer = SPAWN_SCALE_SECONDS
	ModelUtils.enable_shadows(self, false)

func _add_ring(radius: float) -> void:
	var ring_color := BLUE if team == "blue" else (RED if team == "red" else Color(0.86, 0.74, 0.4))
	team_ring = _make_ring(radius, ring_color, 0.8)
	add_child(team_ring)

func _make_ring(radius: float, color: Color, alpha: float) -> MeshInstance3D:
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = radius
	torus.outer_radius = radius + 0.07
	torus.rings = 32
	torus.ring_segments = 6
	ring.mesh = torus
	ring.position.y = 0.03
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(color.r, color.g, color.b, alpha)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = 1.3
	material.no_depth_test = false
	ring.material_override = material
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return ring

# ---------- 受击 / 攻击 / 状态表现 ----------
#
# 这些节点全部在装配时建好、战斗路径只切 visible 与参数：
# 硬规则 4 不允许在受击帧里 new 网格/材质。

func _build_status_fx(height: float, radius: float) -> void:
	# 受击白闪：加色球挂在 UnitVisual 根上，不参与 model_root 的 AABB，
	# 否则会撑大野怪/小兵的体型契约。
	flash_mesh = MeshInstance3D.new()
	flash_mesh.name = "HitFlash"
	var sphere := SphereMesh.new()
	sphere.radius = 0.5
	sphere.height = 1.0
	sphere.radial_segments = 12
	sphere.rings = 6
	flash_mesh.mesh = sphere
	var flash_mat := StandardMaterial3D.new()
	flash_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	flash_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	flash_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	flash_mat.albedo_color = Color(1.0, 0.95, 0.86, 0.58)
	flash_mat.emission_enabled = true
	flash_mat.emission = Color(1.0, 0.95, 0.86)
	flash_mat.emission_energy_multiplier = 2.0
	flash_mesh.material_override = flash_mat
	flash_mesh.scale = Vector3(maxf(radius * 1.7, 0.45), maxf(height * 0.52, 0.5), maxf(radius * 1.7, 0.45))
	flash_mesh.position = Vector3(0.0, height * 0.5, 0.0)
	flash_mesh.visible = false
	flash_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(flash_mesh)

	# 护盾泡：半透明加色球，只在 shield > 0 时出现。
	shield_bubble = MeshInstance3D.new()
	shield_bubble.name = "ShieldBubble"
	var bubble_mesh := SphereMesh.new()
	bubble_mesh.radius = 0.5
	bubble_mesh.height = 1.0
	bubble_mesh.radial_segments = 16
	bubble_mesh.rings = 8
	shield_bubble.mesh = bubble_mesh
	var bubble_mat := StandardMaterial3D.new()
	bubble_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bubble_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bubble_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	bubble_mat.albedo_color = Color(0.55, 0.82, 1.0, 0.18)
	bubble_mat.emission_enabled = true
	bubble_mat.emission = Color(0.5, 0.8, 1.0)
	bubble_mat.emission_energy_multiplier = 1.1
	bubble_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	shield_bubble.material_override = bubble_mat
	shield_bubble.scale = Vector3(radius * 2.6, height * 0.58, radius * 2.6)
	shield_bubble.position = Vector3(0.0, height * 0.5, 0.0)
	shield_bubble.visible = false
	shield_bubble.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(shield_bubble)

	# 红/蓝 BUFF 光环：贴地双环，颜色在 _update_status_fx 里按快照切换。
	buff_aura = _make_status_ring(maxf(radius * 1.05, 0.55), 0.055, Color(1.0, 0.35, 0.2, 0.65))
	buff_aura.name = "BuffAura"
	buff_aura.position.y = 0.055
	buff_aura.visible = false
	add_child(buff_aura)
	var inner := _make_status_ring(maxf(radius * 0.72, 0.38), 0.035, Color(1.0, 0.35, 0.2, 0.45))
	inner.name = "BuffAuraInner"
	inner.position.y = 0.04
	buff_aura.add_child(inner)

	# 减速环：冰蓝色，单独一层，避免和 BUFF 光环抢颜色。
	slow_ring = _make_status_ring(maxf(radius * 0.9, 0.45), 0.045, Color(0.45, 0.8, 1.0, 0.55))
	slow_ring.name = "SlowRing"
	slow_ring.position.y = 0.07
	slow_ring.visible = false
	add_child(slow_ring)

	# 硬控环：每种控一个环，颜色与控制含义对应。
	# 高度分层：眩晕最内、沉默最外，避免多个控同时存在时完全重叠成一团。
	for entry in CC_RING_SPECS:
		var kind := str(entry[0])
		var ring := _make_status_ring(
			maxf(radius * (0.95 + float(entry[1]) * 0.12), 0.45),
			0.05,
			entry[2]
		)
		ring.name = "CCRing_" + kind
		ring.position.y = 0.09 + float(entry[1]) * 0.05
		ring.visible = false
		add_child(ring)
		cc_rings[kind] = ring

## 硬控状态环规格（项 4）：[kind, 半径档位, 颜色]
## 颜色按玩家应对方式区分，不是按伤害类型：
##   眩晕 = 金（完全动不了，等它结束） 击飞 = 橙（被推开）
##   沉默 = 紫（能走能打但放不出技能） 定身 = 青（能放技能但走不了）
const CC_RING_SPECS := [
	["stun", 0.0, Color(1.0, 0.82, 0.28, 0.75)],
	["knockup", 1.0, Color(1.0, 0.55, 0.25, 0.75)],
	["silence", 2.0, Color(0.76, 0.48, 1.0, 0.72)],
	["root", 3.0, Color(0.35, 0.92, 0.95, 0.72)],
]

func _make_status_ring(radius: float, width: float, color: Color) -> MeshInstance3D:
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = maxf(0.05, radius - width)
	torus.outer_radius = radius
	torus.rings = 40
	torus.ring_segments = 6
	ring.mesh = torus
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = Color(color.r, color.g, color.b)
	material.emission_energy_multiplier = 1.3
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	ring.material_override = material
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return ring

func _update_status_fx(data: Dictionary) -> void:
	if dead:
		if shield_bubble:
			shield_bubble.visible = false
		if buff_aura:
			buff_aura.visible = false
		if slow_ring:
			slow_ring.visible = false
		for entry in CC_RING_SPECS:
			var cc_ring: MeshInstance3D = cc_rings.get(str(entry[0]), null)
			if cc_ring != null:
				cc_ring.visible = false
		return
	if shield_bubble:
		shield_bubble.visible = shield_ratio > 0.001
	if buff_aura:
		var red := float(data.get("buff_red_timer", 0.0))
		var blue := float(data.get("buff_blue_timer", 0.0))
		var key := ""
		if red > 0.0 and red >= blue:
			key = "red"
		elif blue > 0.0:
			key = "blue"
		if key != _buff_aura_key:
			_buff_aura_key = key
			var color := Color(1.0, 0.35, 0.2) if key == "red" else Color(0.28, 0.58, 1.0)
			var material := buff_aura.material_override as StandardMaterial3D
			if material:
				material.albedo_color = Color(color.r, color.g, color.b, 0.62)
				material.emission = color
			var inner := buff_aura.get_node_or_null("BuffAuraInner") as MeshInstance3D
			if inner:
				var inner_mat := inner.material_override as StandardMaterial3D
				if inner_mat:
					inner_mat.albedo_color = Color(color.r, color.g, color.b, 0.42)
					inner_mat.emission = color
		buff_aura.visible = key != ""
	if slow_ring:
		slow_ring.visible = float(data.get("slow_timer", 0.0)) > 0.0
	# 硬控环（项 4）：按各控的剩余时间点亮。
	# 用计时而不是只用 cc_status：cc_status 只给"最重的那一个"，
	# 同时中两种控时另一个也会亮，玩家才能看到完整状态。
	for entry in CC_RING_SPECS:
		var kind := str(entry[0])
		var ring: MeshInstance3D = cc_rings.get(kind, null)
		if ring == null:
			continue
		ring.visible = float(data.get("%s_timer" % kind, 0.0)) > 0.0

func _update_hit_reaction(delta: float) -> void:
	if _hit_flash_timer > 0.0:
		_hit_flash_timer = maxf(0.0, _hit_flash_timer - delta)
		if flash_mesh:
			flash_mesh.visible = _hit_flash_timer > 0.0
	if _hit_squash_timer > 0.0:
		_hit_squash_timer = maxf(0.0, _hit_squash_timer - delta)
	if _attack_lunge_timer > 0.0:
		_attack_lunge_timer = maxf(0.0, _attack_lunge_timer - delta)
	if _spawn_scale_timer > 0.0:
		_spawn_scale_timer = maxf(0.0, _spawn_scale_timer - delta)
	if model_root == null or dead:
		return
	var squash := 1.0
	if _hit_squash_timer > 0.0:
		var t := 1.0 - _hit_squash_timer / HIT_SQUASH_SECONDS
		squash = 1.0 - sin(t * PI) * 0.12
	var lunge := 0.0
	if _attack_lunge_timer > 0.0:
		var t := 1.0 - _attack_lunge_timer / ATTACK_LUNGE_SECONDS
		lunge = sin(t * PI) * ATTACK_LUNGE_DISTANCE * _attack_lunge_strength
	var spawn_scale := 1.0
	if _spawn_scale_timer > 0.0:
		var t := 1.0 - _spawn_scale_timer / SPAWN_SCALE_SECONDS
		spawn_scale = lerpf(0.25, 1.0, t * t)
	if not is_equal_approx(squash, 1.0) or lunge > 0.0001 or spawn_scale < 0.999:
		var side := 1.0 + (1.0 - squash) * 0.55
		model_root.scale = Vector3(
			_model_rest_scale.x * side * spawn_scale,
			_model_rest_scale.y * squash * spawn_scale,
			_model_rest_scale.z * side * spawn_scale
		)
		model_root.position = _model_rest_position + Vector3(0.0, 0.0, lunge)
	else:
		model_root.scale = _model_rest_scale
		model_root.position = _model_rest_position

func _minion_material(key: String, color: Color, metallic := 0.0) -> StandardMaterial3D:
	if _minion_mat_cache.has(key):
		return _minion_mat_cache[key]
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.82
	material.metallic = metallic
	_minion_mat_cache[key] = material
	return material

func _add_prop_box(parent: Node3D, size: Vector3, material: Material, pos: Vector3, rot_deg := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mi.mesh = box
	mi.material_override = material
	mi.position = pos
	mi.rotation_degrees = rot_deg
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi

func _add_prop_cylinder(parent: Node3D, radius: float, height: float, material: Material, pos: Vector3, rot_deg := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = radius
	cylinder.bottom_radius = radius
	cylinder.height = height
	cylinder.radial_segments = 10
	mi.mesh = cylinder
	mi.material_override = material
	mi.position = pos
	mi.rotation_degrees = rot_deg
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi

# 小兵四类型的"一眼可辨"配件：远程举杖/炮车有炮管/超级兵有肩甲与背旗。
# 配件挂在 model_root 上，跟着身体一起播放骨骼动作；不做手部骨骼绑定，
# 因为俯视 21m 下"背后多一根杖/一辆车"的剪影比手指位置更重要。
func _build_minion_props() -> void:
	if model_root == null:
		return
	var wood := _minion_material("minion_wood", Color(0.27, 0.19, 0.11), 0.0)
	var metal := _minion_material("minion_metal", Color(0.42, 0.44, 0.47), 0.55)
	var glow := _minion_material("minion_glow", Color(0.35, 0.8, 1.0), 0.0)
	glow.emission_enabled = true
	glow.emission = Color(0.35, 0.8, 1.0)
	glow.emission_energy_multiplier = 2.0
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	var ranged := Node3D.new()
	ranged.name = "RangedKit"
	model_root.add_child(ranged)
	_add_prop_cylinder(ranged, 0.035, 1.2, wood, Vector3(0.28, 0.62, -0.08), Vector3(0.0, 0.0, -12.0))
	var orb := MeshInstance3D.new()
	var orb_mesh := SphereMesh.new()
	orb_mesh.radius = 0.085
	orb_mesh.height = 0.17
	orb.mesh = orb_mesh
	orb.material_override = glow
	orb.position = Vector3(0.40, 1.23, -0.08)
	orb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ranged.add_child(orb)

	var cannon := Node3D.new()
	cannon.name = "CannonKit"
	model_root.add_child(cannon)
	_add_prop_box(cannon, Vector3(0.56, 0.18, 0.74), wood, Vector3(0.0, 0.18, 0.02))
	for side in [-1.0, 1.0]:
		for front in [-1.0, 1.0]:
			_add_prop_cylinder(cannon, 0.14, 0.08, metal, Vector3(side * 0.3, 0.14, front * 0.22), Vector3(0.0, 0.0, 90.0))
	_add_prop_cylinder(cannon, 0.10, 0.72, metal, Vector3(0.0, 0.52, 0.34), Vector3(90.0, 0.0, 0.0))
	var muzzle := MeshInstance3D.new()
	var muzzle_mesh := SphereMesh.new()
	muzzle_mesh.radius = 0.12
	muzzle_mesh.height = 0.24
	muzzle.mesh = muzzle_mesh
	muzzle.material_override = glow
	muzzle.position = Vector3(0.0, 0.52, 0.70)
	muzzle.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	cannon.add_child(muzzle)

	var super_kit := Node3D.new()
	super_kit.name = "SuperKit"
	model_root.add_child(super_kit)
	for side in [-1.0, 1.0]:
		_add_prop_box(super_kit, Vector3(0.20, 0.12, 0.28), metal, Vector3(side * 0.27, 0.88, 0.0), Vector3(0.0, 0.0, side * 12.0))
	_add_prop_box(super_kit, Vector3(0.05, 0.62, 0.36), _minion_material("minion_banner", Color(0.45, 0.12, 0.10), 0.0), Vector3(0.0, 0.92, -0.22))
	_add_prop_box(super_kit, Vector3(0.04, 0.16, 0.34), metal, Vector3(0.0, 0.70, -0.22))

	_minion_props = {"melee": null, "ranged": ranged, "cannon": cannon, "super": super_kit}
	for key in _minion_props:
		var node: Node3D = _minion_props[key]
		if node:
			node.visible = false

func _apply_minion_type_look(new_type: String) -> void:
	if model_root == null:
		return
	for key in _minion_props:
		var node: Node3D = _minion_props[key]
		if node:
			node.visible = key == new_type
	var scale := _minion_base_scale
	match new_type:
		"cannon":
			scale *= 1.10
		"super":
			scale *= 1.22
		"ranged":
			scale *= 0.98
	model_root.scale = scale
	_model_rest_scale = scale

func _make_bar(size: Vector2, fill_color: Color, padding: float = 0.032) -> Array:
	var quad := QuadMesh.new()
	quad.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = quad
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := ShaderMaterial.new()
	mat.shader = BAR_SHADER
	mat.set_shader_parameter("fill_color", fill_color)
	mat.set_shader_parameter("padding", padding)
	mat.set_shader_parameter("ratio", 1.0)
	mat.set_shader_parameter("shield_ratio", 0.0)
	mi.material_override = mat
	return [mi, mat]

func _add_health_bar(height: float, width_scale: float = 1.0) -> void:
	bar_root = Node3D.new()
	bar_root.position.y = height
	add_child(bar_root)

	# 单 quad 血条：底板 + 填充 + 护盾段都由着色器按 UV 绘制，
	# 避免 BILLBOARD_ENABLED 丢弃节点缩放导致血条无法收缩的问题。
	# 配色按「与本地玩家的关系」走 bar_color()，英雄/小兵/野怪同一套规则。
	var hp_color := bar_color(is_local, team, viewer_team)
	var hp_size := HERO_BAR_SIZE if kind == "hero" else OTHER_BAR_SIZE * width_scale
	var hp_bar := _make_bar(hp_size, hp_color)
	bar_mesh = hp_bar[0]
	bar_material = hp_bar[1]
	bar_root.add_child(bar_mesh)

	if kind == "hero":
		# 英雄头顶蓝条，位于血条正下方；间距按血条厚度推算，加粗后不会压住血条。
		var mp_bar := _make_bar(HERO_MANA_SIZE, MANA)
		mp_mesh = mp_bar[0]
		mp_material = mp_bar[1]
		mp_mesh.position.y = -(HERO_BAR_SIZE.y + HERO_MANA_GAP + HERO_MANA_SIZE.y) * 0.5
		bar_root.add_child(mp_mesh)

	if kind == "hero":
		name_label = Label3D.new()
		name_label.text = display_name
		name_label.font = _get_font()
		name_label.font_size = 42
		name_label.pixel_size = 0.0028
		name_label.outline_size = 10
		name_label.outline_modulate = Color(0.01, 0.02, 0.03, 0.9)
		name_label.modulate = GOLD if is_local else Color(0.92, 0.95, 1.0)
		name_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		name_label.no_depth_test = false
		name_label.position.y = HERO_BAR_SIZE.y * 0.5 + 0.15
		bar_root.add_child(name_label)
		level_label = Label3D.new()
		level_label.text = "Lv.1"
		level_label.font = _get_font()
		level_label.font_size = 28
		level_label.pixel_size = 0.0026
		level_label.outline_size = 8
		level_label.outline_modulate = Color(0.01, 0.02, 0.03, 0.9)
		level_label.modulate = Color(0.86, 0.9, 1.0)
		level_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		level_label.position = Vector3(HERO_BAR_SIZE.x * 0.5 + 0.20, name_label.position.y, 0.0)
		bar_root.add_child(level_label)
		_build_bush_eye()
	elif kind == "monster":
		# 野怪也要有名字：四个营地共用两种模型，没有名牌时玩家分不清
		# 「霜狼 / 赤狼 / 暴君」，更看不出这只会掉蓝 BUFF 还是红 BUFF。
		name_label = Label3D.new()
		name_label.text = display_name
		name_label.font = _get_font()
		# 首领离镜头更远才装得下，名牌也要跟着放大；普通野怪保持紧凑。
		name_label.font_size = 44 if is_objective else 32
		name_label.pixel_size = 0.0032
		name_label.outline_size = 10 if is_objective else 8
		name_label.outline_modulate = Color(0.01, 0.02, 0.03, 0.9)
		name_label.modulate = Color(0.9, 0.95, 1.0)
		name_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		name_label.position.y = hp_size.y * 0.5 + (0.18 if is_objective else 0.12)
		bar_root.add_child(name_label)

func _build_bush_eye() -> void:
	bush_eye = Sprite3D.new()
	bush_eye.name = "BushEye"
	bush_eye.texture = BushEye.texture()
	# 96px 的贴图铺成约 1 米宽：比血条窄一点，不会抢名字的视线。
	bush_eye.pixel_size = 1.0 / float(BushEye.TEXTURE_SIZE)
	bush_eye.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	bush_eye.no_depth_test = true
	bush_eye.render_priority = 10
	bush_eye.position = Vector3(0.0, HERO_HEIGHT + 1.05, 0.0)
	bush_eye.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	bush_eye.visible = false
	add_child(bush_eye)

# 本地英雄进出草时由 Arena 调用；其他单位即使被误调也不会长出眼睛。
func set_bush_hidden(value: bool) -> void:
	if kind != "hero":
		bush_hidden = false
		return
	bush_hidden = value
	if bush_hidden and bush_eye == null:
		_build_bush_eye()
	_refresh_bush_eye()

func _refresh_bush_eye() -> void:
	if bush_eye == null:
		return
	bush_eye.visible = bush_hidden and not dead
	if bush_eye.visible:
		_bush_eye_time = 0.0

# 野怪名牌上带增益信息。颜色和文案都由 Arena 从快照字段读出来，
# UnitVisual 不猜 camp / buff 的语义。
func set_monster_badge(buff_type: String, objective: bool) -> void:
	if kind != "monster" or name_label == null:
		return
	var prefix := ""
	var color := Color(0.9, 0.95, 1.0)
	if objective:
		prefix = "首领 · "
		color = Color(0.86, 0.68, 1.0)
	elif buff_type == "blue":
		prefix = "蓝BUFF · "
		color = Color(0.52, 0.76, 1.0)
	elif buff_type == "red":
		prefix = "红BUFF · "
		color = Color(1.0, 0.66, 0.36)
	name_label.text = prefix + display_name
	name_label.modulate = color

func _get_font() -> Font:
	if _font == null:
		_font = load(FONT_PATH)
	return _font

func _attach_retargeted_player(model: Node3D) -> void:
	var skeleton: Skeleton3D = null
	for node in model.find_children("*", "Skeleton3D", true, false):
		skeleton = node
		break
	if skeleton == null:
		return
	var prefix := str(model.get_path_to(skeleton))
	var key := _skeleton_key(skeleton, prefix)
	var library: AnimationLibrary = _library_cache.get(key)
	if library == null:
		library = _build_library(skeleton, prefix)
		_library_cache[key] = library
	var player := AnimationPlayer.new()
	player.name = "RigAnim"
	model.add_child(player)
	player.add_animation_library("", library)
	player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_IDLE
	animation_players.append(player)

func _skeleton_key(skeleton: Skeleton3D, prefix: String) -> String:
	var names: Array[String] = []
	for i in skeleton.get_bone_count():
		names.append(skeleton.get_bone_name(i))
	return prefix + "|" + "|".join(names)

static func warmup() -> void:
	_get_source_animations()

static func _get_source_animations() -> Dictionary:
	if not _source_animations.is_empty():
		return _source_animations
	for scene in [UAL1, UAL2]:
		var source: Node = scene.instantiate()
		for node in source.find_children("*", "AnimationPlayer", true, false):
			var player := node as AnimationPlayer
			if player == null:
				continue
			for lib_name in player.get_animation_library_list():
				var library := player.get_animation_library(lib_name)
				for anim_name in library.get_animation_list():
					_source_animations[anim_name] = library.get_animation(anim_name)
		source.free()
	return _source_animations

func _build_library(skeleton: Skeleton3D, prefix: String) -> AnimationLibrary:
	var sources := _get_source_animations()
	var library := AnimationLibrary.new()
	for anim_name in sources:
		var animation: Animation = (sources[anim_name] as Animation).duplicate()
		var valid_tracks := 0
		for i in range(animation.get_track_count() - 1, -1, -1):
			var bone := animation.track_get_path(i).get_concatenated_subnames()
			if bone == "" or skeleton.find_bone(bone) < 0:
				animation.remove_track(i)
			elif bone == "root":
				# 动作库部分攻击/技能动画包含 root 骨骼位移（Root Motion）。
				# MOBA 战斗中实体的实际位移由模拟层逻辑控制，模型动画必须保持原地（In-Place），
				# 否则攻击后模型脱离地面的脚底光圈与指示环，且待机动画无 root 轨导致位移无法复原。
				animation.remove_track(i)
			else:
				animation.track_set_path(i, NodePath(prefix + ":" + bone))
				valid_tracks += 1
		if valid_tracks > 0:
			if LOOPING_CLIPS.has(anim_name):
				animation.loop_mode = Animation.LOOP_LINEAR
			library.add_animation(anim_name, animation)
	return library

func _equip_weapon(setup_data: Dictionary) -> void:
	var skeleton: Skeleton3D = null
	for node in model_root.find_children("*", "Skeleton3D", true, false):
		skeleton = node
		break
	if skeleton == null:
		return
	var bone_name := str(setup_data.get("weapon_bone", "hand_r"))
	if skeleton.find_bone(bone_name) < 0:
		return
	var attachment := BoneAttachment3D.new()
	attachment.name = "WeaponSlot"
	attachment.bone_name = bone_name
	skeleton.add_child(attachment)
	var weapon_scene: PackedScene = setup_data.weapon
	var weapon: Node3D = weapon_scene.instantiate()
	weapon.scale = Vector3.ONE * float(setup_data.weapon_scale)
	weapon.rotation_degrees = setup_data.weapon_rotation
	weapon.position = setup_data.weapon_offset
	attachment.add_child(weapon)
	# 武器主色跟英雄谱系色走：立绘/技能/技能图标是同一套色，模型上的武器也要能认出来。
	ModelUtils.tint(weapon, setup_data.get("accent", Color.WHITE), float(setup_data.get("weapon_tint_amount", 0.0)))

func set_snapshot(data: Dictionary, delta: float = 0.016, alpha: float = 1.0, prev_xy: Vector2 = Vector2(INF, INF)) -> void:
	var target := Vector3(float(data.get("x", 0.0)), 0.0, float(data.get("y", 0.0)))
	# alpha 变小 = 进入新的一格（tick / 快照区间推进）。
	var wrapped := alpha + 0.0001 < _last_alpha
	_last_alpha = alpha
	if prev_xy.x < 1.0e9:
		# jitter buffer 模式：上一格位置由调用方显式给出。
		# 回放时可能一次跳过多个快照，「上一次调用的位置」已经不可信。
		_prev_pos = Vector3(prev_xy.x, 0.0, prev_xy.y)
		_cur_pos = target
		_has_pos = true
		_initialized = true
		position = _prev_pos.lerp(_cur_pos, clampf(alpha, 0.0, 1.0))
	elif not _has_pos:
		_prev_pos = target
		_cur_pos = target
		_has_pos = true
		_initialized = true
		position = target
	elif target.distance_to(_cur_pos) > 14.0:
		# 复活 / 传送 / 换线：直接落位，插值会造成长距离滑动
		_prev_pos = target
		_cur_pos = target
		position = target
	else:
		if not target.is_equal_approx(_cur_pos):
			# snapshot 只在模拟 tick 时前进。同一 tick 内 _sync_units 每帧都会调用，
			# 若无条件推进 _prev_pos，插值区间会被每帧重置，轨迹退化成一帧一跳（即抖动）。
			_prev_pos = _cur_pos
			_cur_pos = target
		elif wrapped:
			# 进了新的一格但位置没变 = 实体已经站住。
			# 这时必须把插值区间收拢到 _cur_pos：否则 _prev_pos 会永远停在
			# 停步前那一格，而 alpha 每帧照旧在 0→1 回绕，位置就在这两点之间
			# 来回扫（幅度 = 最后一格的位移），肉眼就是「人一停下场景就开始抖」。
			_prev_pos = _cur_pos
		position = _prev_pos.lerp(_cur_pos, clampf(alpha, 0.0, 1.0))
	# moving 取快照里的权威值。以前用「本帧 target 是否变化」来推断，
	# 但 target 只在模拟 tick 时才变，同一 tick 内的后续渲染帧距离恒为 0，
	# moving 于是在 30Hz 上 true/false 反复翻转：_update_locomotion 每帧
	# 在 Jog 和 Idle 之间切一次，player.play() 每次从头开始 —— 腿永远停在
	# 第一帧，人靠位置平移前进，看起来就是「被拖着走」，而且每帧重播动画
	# 本身也是 CPU 热点。
	if data.has("moving"):
		moving = bool(data["moving"]) and not dead
	else:
		moving = target.distance_to(_last_target) > 0.004
	_last_target = target
	unit_speed = float(data.get("speed", unit_speed))

	var facing: Vector2 = Vector2(float(data.get("facing_x", 0.0)), float(data.get("facing_y", 1.0)))
	if facing.length() > 0.1 and not dead:
		var desired := atan2(facing.x, facing.y)
		rotation.y = lerp_angle(rotation.y, desired, clampf(delta * 16.0, 0.0, 1.0))

	hp_ratio = clampf(float(data.get("hp", 0.0)) / maxf(1.0, float(data.get("max_hp", 1.0))), 0.0, 1.0)
	shield_ratio = clampf(float(data.get("shield", 0.0)) / maxf(1.0, float(data.get("max_hp", 1.0))), 0.0, 1.0)
	mp_ratio = clampf(float(data.get("mp", 0.0)) / maxf(1.0, float(data.get("max_mp", 1.0))), 0.0, 1.0)
	_update_health_bar()
	level = int(data.get("level", 1))
	if level_label and level != _shown_level:
		_shown_level = level
		level_label.text = "Lv.%d" % level
	haste = float(data.get("haste_timer", 0.0)) > 0.0
	_update_dead_state(bool(data.get("alive", true)))
	_update_status_fx(data)

# 回城落地 / 传送抵达：直接落位，把插值区间收拢到落点。
# set_snapshot 里「距离 > 14 米直接落位」兜不住近距离瞬移（从自家野区回城可能只跳十来米），
# 那种情况会退化成滑行 —— 人会横穿整片野区。这里由事件明确告知「这是一次瞬移」。
func snap_to(world_pos: Vector3) -> void:
	_prev_pos = world_pos
	_cur_pos = world_pos
	_last_target = world_pos
	_has_pos = true
	_initialized = true
	position = world_pos
	moving = false

func _update_health_bar() -> void:
	if bar_material == null:
		return
	if not is_equal_approx(hp_ratio, _shown_hp):
		_shown_hp = hp_ratio
		bar_material.set_shader_parameter("ratio", hp_ratio)
	if not is_equal_approx(shield_ratio, _shown_shield):
		_shown_shield = shield_ratio
		bar_material.set_shader_parameter("shield_ratio", shield_ratio)
	var show_bar := not dead or hp_ratio > 0.0
	if bar_mesh and show_bar != _shown_bar_visible:
		_shown_bar_visible = show_bar
		bar_mesh.visible = show_bar
	if mp_material and not is_equal_approx(mp_ratio, _shown_mp):
		_shown_mp = mp_ratio
		mp_material.set_shader_parameter("ratio", mp_ratio)
	if mp_mesh:
		mp_mesh.visible = not dead
	if level_label:
		level_label.visible = not dead

func _update_dead_state(alive: bool) -> void:
	if alive and dead:
		dead = false
		_restore_model_rest_pose()
		_hit_flash_timer = 0.0
		_hit_squash_timer = 0.0
		_attack_lunge_timer = 0.0
		if kind == "monster" or kind == "minion":
			_spawn_scale_timer = SPAWN_SCALE_SECONDS
		if flash_mesh:
			flash_mesh.visible = false
		if shield_bubble:
			shield_bubble.visible = false
		if buff_aura:
			buff_aura.visible = false
		if slow_ring:
			slow_ring.visible = false
		# 硬控环同样要清：复活后若还留着眩晕环，玩家会以为"复活了还是被控着"。
		for entry in CC_RING_SPECS:
			var cc_ring: MeshInstance3D = cc_rings.get(str(entry[0]), null)
			if cc_ring != null:
				cc_ring.visible = false
		_shown_hp = -1.0
		_shown_shield = -1.0
		_shown_mp = -1.0
		_shown_level = -1
		_shown_bar_visible = true
		for player in animation_players:
			if player:
				player.stop()
		current_animation = ""
		_set_anim("Idle", true)
		visible = true
		if team_ring:
			team_ring.visible = true
		if name_label:
			name_label.visible = true
		_refresh_bush_eye()
	elif not alive and not dead:
		dead = true
		death_timer = DEATH_LINGER_SECONDS
		_set_anim(_death_anim(), false)
		action_timer = 0.0
		_hit_flash_timer = 0.0
		_hit_squash_timer = 0.0
		_attack_lunge_timer = 0.0
		if flash_mesh:
			flash_mesh.visible = false
		if shield_bubble:
			shield_bubble.visible = false
		if buff_aura:
			buff_aura.visible = false
		if slow_ring:
			slow_ring.visible = false
		_shown_hp = 0.0
		if bar_material:
			bar_material.set_shader_parameter("ratio", 0.0)
		if team_ring:
			team_ring.visible = false
		if local_ring:
			local_ring.visible = false
		if name_label:
			name_label.visible = false
		_refresh_bush_eye()

func play_action(anim_name: String) -> void:
	if dead or anim_name == "":
		return
	_set_anim(anim_name, false)
	action_timer = 0.0
	for player in animation_players:
		if player and player.has_animation(anim_name):
			action_timer = maxf(action_timer, player.get_animation(anim_name).length * 0.82)
	if action_timer <= 0.0:
		action_timer = 0.35

func play_attack() -> void:
	if kind == "hero":
		play_action(str(ANIM_ATTACK.get(hero_type, "Sword_Regular_A")))
	elif kind == "minion":
		play_action(minion_attack_anim(minion_type))
	elif kind == "monster":
		# 野怪：狼带着骨骼的 Attack 动作（glb 里确实有，见 _build_wolf_monster），
		# 程序化拼的那些形态没有骨骼，play_action 会静默跳过 —— 它们的出手感靠
		# 前冲补上。两者都叠加一次前冲：骨骼动作只有上身，脚下仍然站着不动。
		if _monster_spec.is_empty():
			play_action("Attack")
		play_attack_reaction(monster_lunge_strength())

# 小兵攻击动作：远程兵举杖施法，近战兵/超级兵挥武器。
# 这些名字都直接存在于 Skeleton_Warrior / Skeleton_Rogue 里，不依赖 fallback。
static func minion_attack_anim(unit_minion_type: String) -> String:
	match unit_minion_type:
		"ranged", "cannon":
			return "Spellcast_Shoot"
		"super":
			return "2H_Melee_Attack_Chop"
	return "1H_Melee_Attack_Chop"

# 施法动作按槽位取：Q/W/E/R 各一套，不能互相顶替。
static func cast_anim(slot: String, hero_type: String) -> String:
	match slot:
		"q":
			return str(ANIM_Q.get(hero_type, "Sword_Regular_A"))
		"w":
			return str(ANIM_W.get(hero_type, "Sword_Regular_B"))
		"r":
			return str(ANIM_R.get(hero_type, "Sword_Regular_C"))
	return str(ANIM_E.get(hero_type, "Roll"))

func play_skill(slot: String) -> void:
	if kind != "hero":
		return
	play_action(cast_anim(slot, hero_type))
	# Q 和 R 是"打出去"的技能，补一下手部亮光；W/E 多为自身增益或位移，不加光。
	if slot == "q" or slot == "r":
		_pulse_cast_light()

func play_hit() -> void:
	if dead:
		return
	_hit_flash_timer = HIT_FLASH_SECONDS
	_hit_squash_timer = HIT_SQUASH_SECONDS
	if flash_mesh:
		flash_mesh.visible = true
	if action_timer <= 0.0:
		if kind == "hero":
			play_action("Hit_Chest")
		elif kind == "minion":
			play_action("Hit_A")

# 野怪出手的前冲力度。体型越大扑得越狠：普通野怪 2.2 倍、首领顶到上限。
# 上限 0.62 米是为了不让首领「一头扑出脚下环」（环半径 2.4~2.6），
# 出去之后玩家会以为它位移了。
func monster_lunge_strength() -> float:
	if is_objective:
		return MONSTER_LUNGE_MAX / ATTACK_LUNGE_DISTANCE
	var scale := 1.0
	if not _monster_spec.is_empty():
		scale = clampf(float(_monster_spec.get("height", 1.45)) / WOLF_HEIGHT, 1.0, 2.4)
	return MONSTER_LUNGE_SCALE * scale

# 野怪/小兵出手：没有骨骼攻击动作的形态靠身体前倾读"这一下打出去了"。
# 英雄仍走 attack 事件里的 play_attack()，不会重复触发。
# strength 是前冲力度倍数：野怪体型大一圈，用 1.0 的基准在小地图机位下等于没动。
#
# 只升不降：同一次出手会先到 monster_attack（野怪 2.2 倍），再到 hit（默认 1.0 倍），
# 后到的那次把力度压回基准的话，扑咬就变成「原地抖一下」——而且不报错，
# 只能靠 `_attack_lunge_strength` 的断言抓到（见 test_monster_attack_fx）。
func play_attack_reaction(strength := 1.0) -> void:
	if dead:
		return
	var wanted := clampf(strength, 0.5, 4.0)
	if _attack_lunge_timer > 0.0:
		wanted = maxf(wanted, _attack_lunge_strength)
	_attack_lunge_strength = wanted
	_attack_lunge_timer = ATTACK_LUNGE_SECONDS

func process_visual(delta: float) -> void:
	_update_hit_reaction(delta)
	if bush_eye != null and bush_eye.visible:
		# 轻微呼吸 + 透明度起伏：静止的眼睛会被当成贴图污点。
		_bush_eye_time += delta
		var pulse := 1.0 + sin(_bush_eye_time * 5.0) * 0.07
		bush_eye.scale = Vector3.ONE * pulse
		bush_eye.modulate.a = 0.78 + sin(_bush_eye_time * 5.0) * 0.16
	if action_timer > 0.0:
		action_timer -= delta
		if action_timer <= 0.0 and not dead:
			_update_locomotion()
	if dead:
		death_timer -= delta
		_update_death_pose()
		if death_timer <= 0.0:
			for player in animation_players:
				if player:
					player.pause()
		if kind == "minion" and death_timer < -1.2:
			visible = false
		return
	if action_timer <= 0.0:
		_update_locomotion()
	_animate_monster(delta)
	if local_ring:
		local_ring.rotation.y += delta * 0.8

# 野怪的程序化动画：只有没有骨骼动作的形态才走这里（狼有自己的 Idle/Walk/Death）。
func _animate_monster(delta: float) -> void:
	if _monster_spec.is_empty() or model_root == null:
		return
	MonsterForms.animate(_monster_spec, delta, moving, unit_speed)

# 程序化倒地：没有 Death 动作的形态（石像 / 蜥蜴 / 猪 / 鸟 / 首领）向前倒 + 轻微下沉。
# 没有这一步，被击杀的野怪会保持站姿杵在原地，玩家读成「打不动它」。
# 只在静止姿态之上叠加，不能覆盖 fit_height 的缩放与贴地偏移 —— 否则一死就变大。
func _update_death_pose() -> void:
	if not _monster_spec.is_empty() and animation_players.is_empty() and model_root != null:
		var elapsed := clampf((DEATH_LINGER_SECONDS - death_timer) / DEATH_FALL_SECONDS, 0.0, 1.0)
		var eased := elapsed * elapsed
		# 倒地之后继续下沉/缩小：2.4 秒的停留时间里，尸体不会一直以 0.82 倍
		# 完整地杵在地上，而是在最后 0.6 秒收进地面，给重生留出"空场"。
		var sink_start := DEATH_LINGER_SECONDS - DEATH_FALL_SECONDS
		var sink_t := clampf((sink_start - death_timer) / DEATH_SINK_SECONDS, 0.0, 1.0)
		var sink_eased := sink_t * sink_t
		var fallen_scale := lerpf(1.0, 0.82, eased)
		model_root.rotation.x = -1.42 * eased
		model_root.scale = _model_rest_scale * lerpf(fallen_scale, DEATH_SINK_SCALE, sink_eased)
		model_root.position = _model_rest_position + Vector3(0.0, -0.12 * eased - 0.28 * sink_eased, 0.0)

func _update_locomotion() -> void:
	if dead:
		return
	var target_anim := idle_anim
	if moving:
		target_anim = "Sprint" if haste else "Jog_Fwd"
	_set_anim(target_anim, true)
	_apply_locomotion_rate(moving)

# 移动动画的播放速率跟随真实移动速度：速率固定时，速度越快的单位
# 脚底打滑越严重（模型在冰上滑行 = 用户说的「拖着走」）。
# 上限 2.2 倍，再快腿就会糊成一团。
func locomotion_rate_for(active: bool) -> float:
	if not active:
		return 1.0
	return clampf(unit_speed / LOCO_REF_SPEED, LOCO_RATE_MIN, LOCO_RATE_MAX)

func _apply_locomotion_rate(active: bool) -> void:
	var rate := locomotion_rate_for(active)
	if is_equal_approx(rate, _locomotion_rate):
		return
	_locomotion_rate = rate
	for player in animation_players:
		if player:
			player.speed_scale = rate

func _set_anim(anim_name: String, loop: bool) -> void:
	if anim_name == current_animation:
		return
	current_animation = anim_name
	for player in animation_players:
		if player == null:
			continue
		if player.has_animation(anim_name):
			player.play(anim_name, 0.16)
		else:
			if kind == "minion":
				var fallback := _minion_fallback(anim_name)
				if fallback != "" and player.has_animation(fallback):
					player.play(fallback, 0.16)
		# 一次性动作（攻击/技能/受击）始终按原速播放；
		# 移动动画的倍速由 _apply_locomotion_rate 覆盖。
		player.speed_scale = 1.0
	_locomotion_rate = 1.0

func _minion_fallback(anim_name: String) -> String:
	if anim_name == "Death01":
		return "Death_A"
	if anim_name == "Hit_Chest":
		return "Hit_A"
	if anim_name == "Jog_Fwd" or anim_name == "Sprint":
		return "Running_A"
	if anim_name == "Sword_Regular_A":
		return "1H_Melee_Attack_Chop"
	return ""

func _pulse_cast_light() -> void:
	if cast_light == null:
		cast_light = OmniLight3D.new()
		cast_light.light_color = GOLD
		cast_light.light_energy = 0.0
		cast_light.omni_range = 4.0
		cast_light.position.y = 1.2
		add_child(cast_light)
	var tween := create_tween()
	cast_light.light_energy = 3.2
	tween.tween_property(cast_light, "light_energy", 0.0, 0.35)
