extends SceneTree

# 基地水晶画廊（验收工具，入库）：双方阵营 + 满血/残血/护盾 + 俯视/特写。
#
# 为什么单独做：测试能钉住「节点在、alpha 对了、曲线单调」，钉不住
# 「21 米机位下两个阵营能不能一眼分开」「晶簇是不是一坨发白的球」。
# 这些只能出一张和游戏同光照的实拍图来看。
#
# 环境与主光直接吃 ArenaLook（和 tower_gallery.gd 同一条口径）；
# 自己另写一套光照，图上看到的亮度就和游戏里不是一回事。

const Arena = preload("res://scripts/game/arena.gd")
const ArenaLook = preload("res://scripts/game/arena_look.gd")
const CrystalVisual = preload("res://scripts/game/crystal_visual.gd")
const ModelUtils = preload("res://scripts/game/model_utils.gd")

const BLUE_X := -8.0
const RED_X := 8.0

var stage: Node3D
var viewport: SubViewport
var blue: Dictionary
var red: Dictionary

func _initialize() -> void:
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	DisplayServer.window_set_position(Vector2i(5200, 3200))
	viewport = SubViewport.new()
	viewport.size = Vector2i(1600, 900)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var world := Node3D.new()
	viewport.add_child(world)
	var env := Environment.new()
	ArenaLook.apply_environment(env)
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	world.add_child(world_env)
	var sun := DirectionalLight3D.new()
	ArenaLook.apply_sun(sun)
	world.add_child(sun)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(90.0, 90.0)
	ground.mesh = plane
	var grass := StandardMaterial3D.new()
	grass.albedo_color = Color(0.22, 0.32, 0.18)
	grass.roughness = 1.0
	ground.material_override = grass
	world.add_child(ground)
	var camera := Camera3D.new()
	camera.fov = 42.0
	camera.current = true
	world.add_child(camera)
	stage = Node3D.new()
	world.add_child(stage)
	_run(camera)

func _shot(file_name: String) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = viewport.get_texture().get_image()
	img.save_png(ProjectSettings.globalize_path("res://shots/%s.png" % file_name))
	print("SHOT ", file_name, " ", img.get_size())

func _place(x: float, team: String, color: Color) -> Dictionary:
	var state := CrystalVisual.build(color, team)
	var node: Node3D = state.node
	node.position = Vector3(x, 0.0, 0.0)
	stage.add_child(node)
	# 把静态帧摆到一个「碎片分开、金环错位」的相位，避免六块碎片刚好排成一条线。
	CrystalVisual.apply_state(state, 6.0)
	var box := ModelUtils.relative_aabb(node)
	print("BUILD %s meshes=%d aabb=%.2f x %.2f x %.2f" % [team, node.find_children("*", "MeshInstance3D", true, false).size(), box.size.x, box.size.y, box.size.z])
	return state

func _aim(camera: Camera3D, eye: Vector3, target: Vector3) -> void:
	camera.look_at_from_position(eye, target, Vector3.UP)

func _run(camera: Camera3D) -> void:
	blue = _place(BLUE_X, "blue", Arena.BLUE)
	red = _place(RED_X, "red", Arena.RED)

	# ① 对局机位远看：两座基地同框，只比剪影和阵营色。
	_aim(camera, Vector3(0.0, 20.0, 25.0), Vector3(0.0, 3.4, 0.0))
	await create_timer(0.9).timeout
	await _shot("crystal_bases_field")

	# ② 俯视：台阶、金环、法阵、六块碎片必须读得出来。
	_aim(camera, Vector3(BLUE_X, 17.5, 2.4), Vector3(BLUE_X, 0.0, 0.0))
	await create_timer(0.5).timeout
	await _shot("crystal_blue_top")

	# ③ 蓝方 3/4 特写：看晶簇切面、柱座花瓣、金环厚度。
	# 机位比旧版更高更远：旧版 13.5m 处把台基前沿切出画面，台基看起来像一块白板。
	_aim(camera, Vector3(BLUE_X + 7.2, 11.2, 13.0), Vector3(BLUE_X, 3.9, 0.0))
	await create_timer(0.5).timeout
	await _shot("crystal_blue_closeup")

	# ④ 红方 3/4 特写：同一机位，检查暖石材 + 赤金是否成立。
	_aim(camera, Vector3(RED_X - 7.2, 11.2, 13.0), Vector3(RED_X, 3.9, 0.0))
	await create_timer(0.5).timeout
	await _shot("crystal_red_closeup")

	# ⑤ 护盾：只罩红方，检查「边缘亮、中心透」而不是一团蓝雾。
	CrystalVisual.apply_shield(red, 2400.0, 2400.0)
	CrystalVisual.apply_state(red, 0.0)
	_aim(camera, Vector3(RED_X - 3.0, 12.5, 15.5), Vector3(RED_X, 3.6, 0.0))
	await create_timer(0.5).timeout
	await _shot("crystal_red_shield")

	# ⑥ 残血：蓝方压到 15%，检查裂纹、变暗、光柱衰减。
	CrystalVisual.apply_damage(blue, 0.15)
	CrystalVisual.apply_state(blue, 0.0)
	_aim(camera, Vector3(BLUE_X + 7.2, 11.2, 13.0), Vector3(BLUE_X, 3.9, 0.0))
	await create_timer(0.5).timeout
	await _shot("crystal_blue_damaged")

	# ⑦ 残血 + 贴脸：OcclusionFade 把柱身/晶簇淡到 0.16，dais 保持不透明。
	const Occlusion = preload("res://scripts/game/occlusion_fade.gd")
	Occlusion.apply({"crystal_fade_parts": blue.fade_parts}, 0.0)
	_aim(camera, Vector3(BLUE_X + 5.2, 6.8, 6.4), Vector3(BLUE_X, 2.6, 0.0))
	await create_timer(0.4).timeout
	await _shot("crystal_blue_faded")

	quit()
