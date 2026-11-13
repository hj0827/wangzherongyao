extends SceneTree

# 待机姿势对照画廊（入库工具）：把 5 个英雄各拍 3 帧待机（0s / 中段 / 末段），
# 水平并排成一张长图，用来判断两件事：
#   1. 五个人站在一起时，**站姿**能不能两两分开（不是只有武器/颜色不同）；
#   2. 待机是不是真的在循环呼吸，而不是停在一帧上（三帧姿态必须有差别）。
#
# 为什么不能只看测试：`test_hero_idle_poses_are_distinct` 只证明「clip 名不同」，
# 证明不了「看起来不同」—— 两个 clip 也可能是同一个姿势的两种时长。
#
# 用法（必须走隐藏桌面，见 AGENTS.md 环境硬约束）：
#   powershell -ExecutionPolicy Bypass -File godot\tools\shot_offscreen.ps1 tools\hero_idle_shot.gd
# 产物：godot/shots/hero_idle_sheet.png（5 行 × 3 帧）

const UnitVisual = preload("res://scripts/game/unit_visual.gd")
const ModelUtils = preload("res://scripts/game/model_utils.gd")
const ArenaLook = preload("res://scripts/game/arena_look.gd")
const HeroLook = preload("res://scripts/game/hero_look.gd")

const HEROES := [
	{"type": "blade", "name": "苍刃"},
	{"type": "mage", "name": "星璃"},
	{"type": "tank", "name": "铁壁"},
	{"type": "archer", "name": "翎羽"},
	{"type": "assassin", "name": "墨鸦"},
]

const CELL := Vector2i(340, 470)
const FOV := 34.0
const FPS := 30

var viewport: SubViewport
var camera: Camera3D
var stage: Node3D

func _initialize() -> void:
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	DisplayServer.window_set_position(Vector2i(5200, 3200))
	DisplayServer.window_set_size(Vector2i(1, 1))
	Engine.max_fps = 15
	viewport = SubViewport.new()
	viewport.size = CELL
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	_build_stage()
	_run()

func _build_stage() -> void:
	var world := WorldEnvironment.new()
	var environment := Environment.new()
	ArenaLook.apply_environment(environment)
	world.environment = environment
	viewport.add_child(world)
	var sun := DirectionalLight3D.new()
	ArenaLook.apply_sun(sun)
	viewport.add_child(sun)
	var floor_node := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(14, 14)
	floor_node.mesh = plane
	var floor_material := StandardMaterial3D.new()
	floor_material.albedo_color = Color(0.14, 0.15, 0.14)
	floor_material.roughness = 0.9
	floor_node.material_override = floor_material
	floor_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	viewport.add_child(floor_node)
	stage = Node3D.new()
	viewport.add_child(stage)
	camera = Camera3D.new()
	camera.fov = FOV
	camera.near = 0.05
	camera.current = true
	viewport.add_child(camera)

func _spawn(hero_type: String, name: String) -> UnitVisual:
	var view := UnitVisual.new()
	view.setup("hero", "blue", hero_type, name, false, "blue")
	view.set_snapshot({
		"x": 0.0, "y": 0.0, "hp": 2000.0, "max_hp": 2000.0,
		"mp": 400.0, "max_mp": 400.0, "level": 6, "alive": true,
		"facing_x": 0.0, "facing_y": 1.0, "moving": false,
	}, 1.0)
	if view.bar_root != null:
		view.bar_root.visible = false
	if view.team_ring != null:
		view.team_ring.visible = false
	if view.local_ring != null:
		view.local_ring.visible = false
	stage.add_child(view)
	# 待机会自己播（AnimationPlayer 默认 active）；这里关掉 process 手动推进，
	# 让「第几帧」是确定的，否则三张图可能拍到同一个姿态。
	view.set_process(false)
	return view

func _clear() -> void:
	for child in stage.get_children():
		child.queue_free()

## 手动把动画推进固定时间。避免依赖真实帧间隔（截图写盘会拖慢）。
func _advance(view: UnitVisual, seconds: float) -> void:
	var steps := int(seconds * FPS)
	for i in steps:
		for player in view.animation_players:
			if player != null:
				player.advance(1.0 / float(FPS))
		view.process_visual(1.0 / float(FPS))

func _frame(view: UnitVisual) -> void:
	var box := ModelUtils.relative_aabb(view.model_root)
	var height := maxf(box.size.y, 2.4)
	var half := tan(deg_to_rad(camera.fov * 0.5))
	var distance := height / (2.0 * half) * 1.28
	var centre := Vector3(0.0, height * 0.52, 0.0)
	var yaw := deg_to_rad(-24.0)
	camera.position = centre + Vector3(sin(yaw) * distance, height * 0.12, cos(yaw) * distance)
	camera.look_at_from_position(camera.position, centre, Vector3.UP)

func _shot() -> Image:
	await RenderingServer.frame_post_draw
	return viewport.get_texture().get_image()

func _run() -> void:
	await create_timer(0.8).timeout
	var sheet := Image.create_empty(CELL.x * 3, CELL.y * HEROES.size(), false, Image.FORMAT_RGBA8)
	sheet.fill(Color(0.06, 0.07, 0.09, 1.0))
	for row in HEROES.size():
		var spec: Dictionary = HEROES[row]
		var hero_type := str(spec["type"])
		_clear()
		await create_timer(0.08).timeout
		var view := _spawn(hero_type, str(spec["name"]))
		await create_timer(0.12).timeout
		_frame(view)
		# 三帧：0 / 0.55s / 1.1s。待机 clip 都在 1.5~2.9s，两个采样点足以看出
		# 「它到底动没动」；同时第一帧能代表「刚站定的样子」。
		var frames := [0.0, 0.55, 1.10]
		var images: Array[Image] = []
		for index in frames.size():
			if index > 0:
				_advance(view, 0.55)
			await create_timer(0.05).timeout
			images.append(await _shot())
		print("IDLE %-9s clip=%-18s 帧=%d" % [
			hero_type, HeroLook.idle_pose(hero_type), images.size()])
		for column in images.size():
			sheet.blit_rect(images[column], Rect2i(Vector2i.ZERO, CELL),
				Vector2i(column * CELL.x, row * CELL.y))
	sheet.save_png(ProjectSettings.globalize_path("res://shots/hero_idle_sheet.png"))
	print("IDLE sheet ", sheet.get_size())
	quit()
