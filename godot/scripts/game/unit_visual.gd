extends Node3D
class_name UnitVisual

const ModelUtils = preload("res://scripts/game/model_utils.gd")
const BushEye = preload("res://scripts/game/bush_eye.gd")
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
		"weapon_scale": 0.26,
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
		"weapon_scale": 0.26,
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
		"weapon_scale": 0.31,
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
		"weapon_scale": 0.26,
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
		"weapon_scale": 0.20,
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
	pit_id: String = ""
) -> void:
	kind = unit_kind
	team = unit_team
	hero_type = type_id
	is_objective = objective
	objective_id = pit_id
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
	_equip_weapon(setup_data)
	_add_ring(0.9)
	if is_local:
		local_ring = _make_ring(1.15, GOLD, 0.55)
		local_ring.position.y = 0.02
		add_child(local_ring)
	_add_health_bar(HERO_HEIGHT + 0.30)
	idle_anim = str(setup_data.get("idle", "Idle"))
	_set_anim(idle_anim, true)
	process_priority = 10
	# 单位数量多、始终处于镜头附近，阴影 pass 的收益远低于开销；
	# 建筑与环境保留阴影，单位用脚下队伍环提供接地感。
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
	_add_ring(0.44)
	_add_health_bar(MINION_HEIGHT + 0.16, 0.62)
	_set_anim("Idle", true)
	ModelUtils.enable_shadows(self, false)

func _build_monster() -> void:
	if monster_type == "spirit":
		_build_river_spirit()
		return
	var scene: PackedScene
	var target_height := 1.5
	var bar_width := 0.9
	if is_objective:
		scene = preload("res://assets/characters/Orc.glb")
		target_height = OVERLORD_HEIGHT if objective_id == "overlord" else TYRANT_HEIGHT
		bar_width = OBJECTIVE_BAR_WIDTH
	elif monster_type == "orc":
		scene = preload("res://assets/characters/Orc.glb")
		target_height = 2.4
	else:
		scene = preload("res://assets/characters/Wolf.glb")
		target_height = 1.4
	var fitted := ModelUtils.fit_scene(scene, target_height)
	fitted.name = "Model"
	model_root = fitted
	add_child(model_root)
	for node in model_root.find_children("*", "AnimationPlayer", true, false):
		var player := node as AnimationPlayer
		if player:
			animation_players.append(player)
			player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_IDLE
	if is_objective:
		# 脚下环贴着碰撞半径画（暴君 2.6 / 主宰 2.8），
		# 让玩家在选中首领前就能读出它的实际体积。
		_add_ring(2.4 if objective_id == "tyrant" else 2.6)
		_add_health_bar(target_height + 0.55, bar_width)
	else:
		_add_ring(0.6)
		_add_health_bar(target_height + 0.25, bar_width)
	_set_anim("Idle", true)
	ModelUtils.enable_shadows(self, false)

func _build_river_spirit() -> void:
	var root := Node3D.new()
	root.name = "Model"
	model_root = root
	add_child(root)
	var body := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.62
	sphere.height = 1.24
	sphere.radial_segments = 20
	sphere.rings = 12
	body.mesh = sphere
	var body_material := StandardMaterial3D.new()
	body_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	body_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	body_material.albedo_color = Color(0.4, 0.86, 0.95, 0.88)
	body_material.emission_enabled = true
	body_material.emission = Color(0.38, 0.82, 0.96)
	body_material.emission_energy_multiplier = 1.8
	body.material_override = body_material
	body.position.y = 1.0
	body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(body)
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
	_set_anim("Idle", true)
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
		death_timer = 2.4
		_set_anim("Death01" if kind == "hero" else "Death_A", false)
		action_timer = 0.0
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
	if action_timer <= 0.0:
		play_action("Hit_Chest" if kind == "hero" else "Hit_A")

func process_visual(delta: float) -> void:
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
		if death_timer <= 0.0:
			for player in animation_players:
				if player:
					player.pause()
		if kind == "minion" and death_timer < -1.2:
			visible = false
		return
	if action_timer <= 0.0:
		_update_locomotion()
	if local_ring:
		local_ring.rotation.y += delta * 0.8

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
