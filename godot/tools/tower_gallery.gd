extends SceneTree

# 防御塔画廊（验收工具，入库）：把四种层级 + 低血 + 开火 + 倒塌拼成一张对照图。
#
# 为什么单独做：塔的升级是"观感"改动，测试只能钉住数值契约（肋数、亮度、倾斜角），
# 钉不住"21m 机位下能不能一眼分出这是高地塔"。必须有一张和游戏同光照的实拍图。
#
# 环境与主光直接吃 ArenaLook（和 monster_gallery.gd 同一条口径）：
# 自己另写一套光照 / 不开 bloom，图上看到的亮度和游戏里不是一回事，
# 「核心到底够不够亮」就判断不了。

const Arena = preload("res://scripts/game/arena.gd")
const ArenaLook = preload("res://scripts/game/arena_look.gd")
const TowerVisual = preload("res://scripts/game/tower_visual.gd")

const TEAM := Color(1.0, 0.32, 0.26)
const TIERS := ["outer", "inner", "high", "twin"]

var stage: Node3D
var viewport: SubViewport

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
	plane.size = Vector2(80.0, 80.0)
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

func _place_tier(tier: String, x: float) -> Node3D:
	var built := TowerVisual.build(TEAM, tier)
	var node: Node3D = built.get("node")
	node.position = Vector3(x, 0.0, 0.0)
	stage.add_child(node)
	# 光池与花瓣和 arena 一样挂在塔根上（不进 model 的 AABB）。
	var glow: Node3D = built.get("glow")
	stage.add_child(glow)
	glow.position = Vector3(x, 0.0, 0.0)
	var petals: Node3D = built.get("petals")
	stage.add_child(petals)
	petals.position = Vector3(x, 0.0, 0.0)
	return node

func _aim(camera: Camera3D, eye: Vector3, target: Vector3) -> void:
	# 必须用 look_at_from_position：scene 构建阶段相机还没进树时 look_at() 会静默失败，
	# 相机停在默认朝向上，拍到的是天空和塔顶——很容易被误读成"塔没建出来"。
	camera.look_at_from_position(eye, target, Vector3.UP)

func _run(camera: Camera3D) -> void:
	# 四座塔横排：21m 机位下能不能分出层级，一眼就知道。
	for i in TIERS.size():
		_place_tier(str(TIERS[i]), -9.0 + 6.0 * float(i))
	_aim(camera, Vector3(0.0, 12.5, 20.0), Vector3(0.0, 4.2, 0.0))
	await create_timer(0.7).timeout
	await _shot("tower_tiers_field")

	# 特写：塔冠（肋数 / 宝珠 / 金箍的差别全在这一块）。
	_aim(camera, Vector3(-9.0, 9.6, 5.6), Vector3(-9.0, 7.6, 0.0))
	await create_timer(0.5).timeout
	await _shot("tower_crown_outer")
	_aim(camera, Vector3(-3.0, 9.6, 5.6), Vector3(-3.0, 7.6, 0.0))
	await create_timer(0.5).timeout
	await _shot("tower_crown_inner")
	_aim(camera, Vector3(3.0, 9.6, 5.6), Vector3(3.0, 7.6, 0.0))
	await create_timer(0.5).timeout
	await _shot("tower_crown_high")

	# 残破：把外塔按满血 / 残血各拍一张，看变暗与裂纹。
	_aim(camera, Vector3(-9.0, 7.0, 9.0), Vector3(-9.0, 3.6, 0.0))
	var outer := stage.get_child(0) as Node3D
	var cracks: MeshInstance3D = TowerVisual.build_cracks(7)
	outer.add_child(cracks)
	cracks.visible = false
	var stone := outer.get_node_or_null("Stone") as MeshInstance3D
	var stone_mat: StandardMaterial3D = null
	if stone != null:
		stone_mat = stone.material_override as StandardMaterial3D
	await create_timer(0.4).timeout
	await _shot("tower_health_full")
	if stone_mat != null:
		stone_mat.albedo_color = Color(1.0, 0.97, 0.93).lerp(Color(0.52, 0.49, 0.47), 0.85)
	cracks.visible = true
	await create_timer(0.3).timeout
	await _shot("tower_health_low")
	quit()
