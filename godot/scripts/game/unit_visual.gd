extends Node3D
class_name UnitVisual

const ModelUtils = preload("res://scripts/game/model_utils.gd")
const BAR_SHADER := preload("res://shaders/billboard_bar.gdshader")

const BLUE := Color(0.22, 0.6, 1.0)
const RED := Color(1.0, 0.32, 0.26)
const GOLD := Color(1.0, 0.78, 0.32)
const MANA := Color(0.28, 0.56, 1.0)
const FONT_PATH := "res://assets/fonts/NotoSansSC.ttf"
const HERO_HEIGHT := 2.4
const MINION_HEIGHT := 1.35

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
}

const LOOPING_CLIPS := ["Idle", "Jog_Fwd", "Sprint", "Sword_Idle", "Spell_Simple_Idle", "Idle_Shield"]

const ANIM_ATTACK := {
	"blade": "Sword_Regular_A",
	"mage": "Spell_Simple_Shoot",
	"tank": "Sword_Regular_B",
	"archer": "Spell_Simple_Shoot",
}
const ANIM_Q := {
	"blade": "Sword_Regular_C",
	"mage": "Spell_Simple_Shoot",
	"tank": "Shield_Dash_RM",
	"archer": "Spell_Simple_Shoot",
}
const ANIM_E := {
	"blade": "Slide",
	"mage": "Spell_Simple_Shoot",
	"tank": "Shield_Dash_RM",
	"archer": "Roll",
}

static var _source_animations: Dictionary = {}
static var _library_cache: Dictionary = {}
static var _font: Font = null

var kind := "hero"
var team := "blue"
var hero_type := "blade"
var display_name := ""
var is_local := false

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
var idle_anim := "Idle"
var _target_position := Vector3.ZERO
var _initialized := false
var _last_target := Vector3.ZERO
# 实体插值用：_prev_pos/_cur_pos 是相邻两个模拟 tick 的位置，
# 渲染帧按 alpha 在两者之间线性插值，得到匀速平滑的轨迹（指数平滑会一顿一顿）。
var _prev_pos := Vector3.ZERO
var _cur_pos := Vector3.ZERO
var _has_pos := false

var bar_root: Node3D
var bar_mesh: MeshInstance3D
var bar_material: ShaderMaterial
var mp_mesh: MeshInstance3D
var mp_material: ShaderMaterial
var mp_ratio := 0.0
var name_label: Label3D
var level_label: Label3D
var team_ring: MeshInstance3D
var local_ring: MeshInstance3D
var cast_light: OmniLight3D

func setup(unit_kind: String, unit_team: String, type_id: String, label: String, local: bool) -> void:
	kind = unit_kind
	team = unit_team
	hero_type = type_id
	display_name = label
	is_local = local
	if kind == "hero":
		_build_hero()
	else:
		_build_minion()

static func scale_for_height(measured_height: float, target_height: float) -> float:
	if measured_height <= 0.001 or target_height <= 0.0:
		return 1.0
	return target_height / measured_height

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
	_add_health_bar(HERO_HEIGHT + 0.25)
	idle_anim = str(setup_data.get("idle", "Idle"))
	_set_anim(idle_anim, true)
	process_priority = 10

func _build_minion() -> void:
	var scene: PackedScene
	if team == "blue":
		scene = preload("res://assets/characters/Skeleton_Warrior.glb")
	else:
		scene = preload("res://assets/characters/Skeleton_Rogue.glb")
	var fitted := ModelUtils.fit_scene(scene, MINION_HEIGHT)
	fitted.name = "Model"
	model_root = fitted
	add_child(model_root)
	for node in model_root.find_children("*", "AnimationPlayer", true, false):
		var player := node as AnimationPlayer
		if player:
			animation_players.append(player)
			player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_IDLE
	_add_ring(0.5)
	_add_health_bar(MINION_HEIGHT + 0.18, 0.8)
	_set_anim("Idle", true)

func _add_ring(radius: float) -> void:
	team_ring = _make_ring(radius, BLUE if team == "blue" else RED, 0.8)
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
	var hp_bar := _make_bar(Vector2(1.24 * width_scale, 0.14 * width_scale), BLUE if team == "blue" else RED)
	bar_mesh = hp_bar[0]
	bar_material = hp_bar[1]
	bar_root.add_child(bar_mesh)

	if kind == "hero":
		# 英雄头顶蓝条，位于血条正下方
		var mp_bar := _make_bar(Vector2(1.24 * width_scale, 0.07 * width_scale), MANA)
		mp_mesh = mp_bar[0]
		mp_material = mp_bar[1]
		mp_mesh.position.y = -0.12 * width_scale
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
		name_label.position.y = 0.22
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
		level_label.position = Vector3(0.82, 0.22, 0.0)
		bar_root.add_child(level_label)

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

func set_snapshot(data: Dictionary, delta: float, alpha: float = 1.0, prev_xy: Vector2 = Vector2(INF, INF)) -> void:
	var target := Vector3(float(data.get("x", 0.0)), 0.0, float(data.get("y", 0.0)))
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
		position = _prev_pos.lerp(_cur_pos, clampf(alpha, 0.0, 1.0))
	if target.distance_to(_last_target) > 0.004:
		moving = bool(data.get("moving", true))
	else:
		moving = false
	_last_target = target

	var facing: Vector2 = Vector2(float(data.get("facing_x", 0.0)), float(data.get("facing_y", 1.0)))
	if facing.length() > 0.1 and not dead:
		var desired := atan2(facing.x, facing.y)
		rotation.y = lerp_angle(rotation.y, desired, clampf(delta * 16.0, 0.0, 1.0))

	hp_ratio = clampf(float(data.get("hp", 0.0)) / maxf(1.0, float(data.get("max_hp", 1.0))), 0.0, 1.0)
	shield_ratio = clampf(float(data.get("shield", 0.0)) / maxf(1.0, float(data.get("max_hp", 1.0))), 0.0, 1.0)
	mp_ratio = clampf(float(data.get("mp", 0.0)) / maxf(1.0, float(data.get("max_mp", 1.0))), 0.0, 1.0)
	_update_health_bar()
	level = int(data.get("level", 1))
	if level_label:
		level_label.text = "Lv.%d" % level
	haste = float(data.get("haste_timer", 0.0)) > 0.0
	_update_dead_state(bool(data.get("alive", true)))

func _update_health_bar() -> void:
	if bar_material == null:
		return
	bar_material.set_shader_parameter("ratio", hp_ratio)
	bar_material.set_shader_parameter("shield_ratio", shield_ratio)
	if bar_mesh:
		bar_mesh.visible = not dead or hp_ratio > 0.0
	if mp_material:
		mp_material.set_shader_parameter("ratio", mp_ratio)
	if mp_mesh:
		mp_mesh.visible = not dead
	if level_label:
		level_label.visible = not dead

func _update_dead_state(alive: bool) -> void:
	if alive and dead:
		dead = false
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
	elif not alive and not dead:
		dead = true
		death_timer = 2.4
		_set_anim("Death01" if kind == "hero" else "Death_A", false)
		action_timer = 0.0
		if bar_material:
			bar_material.set_shader_parameter("ratio", 0.0)
		if team_ring:
			team_ring.visible = false
		if local_ring:
			local_ring.visible = false
		if name_label:
			name_label.visible = false

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
	if kind != "hero":
		return
	play_action(str(ANIM_ATTACK.get(hero_type, "Sword_Regular_A")))

func play_skill(slot: String) -> void:
	if kind != "hero":
		return
	if slot == "q":
		play_action(str(ANIM_Q.get(hero_type, "Sword_Regular_A")))
		_pulse_cast_light()
	else:
		play_action(str(ANIM_E.get(hero_type, "Roll")))

func play_hit() -> void:
	if dead:
		return
	if action_timer <= 0.0:
		play_action("Hit_Chest" if kind == "hero" else "Hit_A")

func process_visual(delta: float) -> void:
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

func _set_anim(anim_name: String, loop: bool) -> void:
	if anim_name == current_animation:
		return
	current_animation = anim_name
	for player in animation_players:
		if player == null:
			continue
		if kind == "minion" and player == null:
			continue
		if player.has_animation(anim_name):
			player.play(anim_name, 0.16)
			if player.get_animation(anim_name).loop_mode != Animation.LOOP_LINEAR:
				# one-shots are held by the action timer, not by looping
				pass
			if not loop:
				player.speed_scale = 1.0
		else:
			if kind == "minion":
				var fallback := _minion_fallback(anim_name)
				if fallback != "" and player.has_animation(fallback):
					player.play(fallback, 0.16)

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
