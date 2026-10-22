extends Node3D

const HERO := preload("res://assets/characters/hero_warrior.glb")
const MAGE := preload("res://assets/characters/hero_mage.glb")
const OUTFIT_M := preload("res://assets/characters/outfit_ranger_m.glb")
const OUTFIT_F := preload("res://assets/characters/outfit_ranger_f.glb")
const HAIR_BUZZ := preload("res://assets/characters/hair_buzzed.glb")
const HAIR_LONG := preload("res://assets/characters/hair_long.glb")
const UAL1 := preload("res://assets/animations/ual1.glb")
const UAL2 := preload("res://assets/animations/ual2.glb")
const CLAYMORE := preload("res://assets/weapons/Claymore.glb")
const SCYTHE := preload("res://assets/weapons/Scythe.glb")

var merged_animations: Dictionary = {}

func _ready() -> void:
	_build_world()
	_collect_animations()
	var warrior := _build_hero(HERO, OUTFIT_M, HAIR_BUZZ, Vector3(-1.05, 0, 0))
	_equip(warrior, CLAYMORE, Vector3(0, 0, 0), 1.0)
	var mage := _build_hero(MAGE, OUTFIT_F, HAIR_LONG, Vector3(1.05, 0, 0))
	_equip(mage, SCYTHE, Vector3(0, 0, 0), 0.75)
	_play(warrior, "Sword_Regular_A")
	_play(mage, "Spell_Simple_Shoot")
	await get_tree().create_timer(0.6).timeout
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(ProjectSettings.globalize_path("res://preview.png"))
	print("SAVED preview.png ", img.get_size())
	get_tree().quit()

func _build_world() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.055, 0.075, 0.11)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.55, 0.68, 0.9)
	e.ambient_light_energy = 0.7
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment = e
	add_child(env)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-42, -35, 0)
	sun.light_color = Color(1.0, 0.91, 0.78)
	sun.light_energy = 1.8
	sun.shadow_enabled = true
	add_child(sun)

	var cam := Camera3D.new()
	cam.position = Vector3(0, 1.45, 4.4)
	cam.rotation_degrees = Vector3(-7, 0, 0)
	cam.fov = 42
	add_child(cam)

	var floor := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(30, 30)
	floor.mesh = plane
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.16, 0.18, 0.16)
	mat.roughness = 0.9
	floor.material_override = mat
	add_child(floor)

func _collect_animations() -> void:
	for scene in [UAL1, UAL2]:
		var source: Node = scene.instantiate()
		add_child(source)
		var src_player: AnimationPlayer = null
		for node in source.find_children("*", "AnimationPlayer", true, false):
			src_player = node
			break
		if src_player:
			for lib_name in src_player.get_animation_library_list():
				var lib := src_player.get_animation_library(lib_name)
				for anim_name in lib.get_animation_list():
					merged_animations[anim_name] = lib.get_animation(anim_name)
		source.queue_free()
	print("MERGED ANIMATIONS: ", merged_animations.size())

func _build_hero(body_scene: PackedScene, outfit_scene: PackedScene, hair_scene: PackedScene, pos: Vector3) -> Node3D:
	var root := Node3D.new()
	root.position = pos
	add_child(root)
	var bodies: Array[Node3D] = []
	for scene in [body_scene, outfit_scene, hair_scene]:
		var model: Node3D = scene.instantiate()
		root.add_child(model)
		bodies.append(model)
		_attach_player(model)
	return root

func _attach_player(model: Node3D) -> void:
	var skeleton: Skeleton3D = null
	for node in model.find_children("*", "Skeleton3D", true, false):
		skeleton = node
		break
	if skeleton == null:
		return
	var player := AnimationPlayer.new()
	player.name = "RigAnim"
	model.add_child(player)
	player.add_animation_library("", AnimationLibrary.new())
	var lib := player.get_animation_library("")
	var prefix := model.get_path_to(skeleton)
	for anim_name in merged_animations:
		var anim: Animation = merged_animations[anim_name].duplicate()
		var valid_tracks := 0
		for i in range(anim.get_track_count() - 1, -1, -1):
			var bone := anim.track_get_path(i).get_concatenated_subnames()
			if bone == "" or skeleton.find_bone(bone) < 0:
				anim.remove_track(i)
			else:
				anim.track_set_path(i, NodePath(str(prefix) + ":" + bone))
				valid_tracks += 1
		if valid_tracks > 0:
			lib.add_animation(anim_name, anim)

func _play(hero: Node3D, anim_name: String) -> void:
	for player in hero.find_children("*", "AnimationPlayer", true, false):
		var ap := player as AnimationPlayer
		if ap.has_animation(anim_name):
			ap.play(anim_name)

func _equip(hero: Node3D, weapon_scene: PackedScene, rotation: Vector3, scale_factor: float) -> void:
	var skeleton: Skeleton3D = null
	for node in hero.find_children("*", "Skeleton3D", true, false):
		skeleton = node
		break
	if skeleton == null:
		return
	var attachment := BoneAttachment3D.new()
	attachment.bone_name = "hand_r"
	skeleton.add_child(attachment)
	var weapon: Node3D = weapon_scene.instantiate()
	weapon.rotation_degrees = rotation
	weapon.scale = Vector3.ONE * scale_factor
	attachment.add_child(weapon)
