extends SceneTree

const UnitVisual = preload("res://scripts/game/unit_visual.gd")
const ModelUtils = preload("res://scripts/game/model_utils.gd")

var viewport: SubViewport

func _initialize() -> void:
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, true)
	DisplayServer.window_set_position(Vector2i(5200, 3200))
	DisplayServer.window_set_size(Vector2i(1, 1))
	Engine.max_fps = 15
	viewport = SubViewport.new()
	viewport.size = Vector2i(1200, 700)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	_build_stage()
	_run()

func _build_stage() -> void:
	var world := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.12, 0.18, 0.2)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.65, 0.7, 0.8)
	environment.ambient_light_energy = 0.7
	world.environment = environment
	viewport.add_child(world)

	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-52.0, -32.0, 0.0)
	light.light_energy = 1.25
	light.shadow_enabled = true
	viewport.add_child(light)

	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(24.0, 24.0)
	ground.mesh = plane
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.32, 0.42, 0.28)
	ground.material_override = material
	viewport.add_child(ground)

	var camera := Camera3D.new()
	camera.position = Vector3(0.0, 2.4, 6.4)
	camera.look_at_from_position(camera.position, Vector3(0.0, 1.2, 0.0))
	camera.fov = 46.0
	viewport.add_child(camera)

	var hero: UnitVisual = UnitVisual.new()
	viewport.add_child(hero)
	hero.setup("hero", "blue", "blade", "英雄", true)
	hero.position = Vector3(-1.5, 0.0, 0.0)

	for i in 2:
		var minion: UnitVisual = UnitVisual.new()
		viewport.add_child(minion)
		minion.setup("minion", "red" if i == 0 else "blue", "minion", "", false)
		minion.position = Vector3(0.85 + float(i) * 0.95, 0.0, 0.15 - float(i) * 0.25)
		minion.rotation.y = -0.4 + float(i) * 0.8

func _run() -> void:
	await create_timer(1.0).timeout
	var heights := {}
	for node in viewport.find_children("*", "Node3D", true, false):
		if node is UnitVisual:
			var visual := node as UnitVisual
			heights["%s_%d" % [visual.kind, heights.size()]] = ModelUtils.relative_aabb(visual.model_root).size.y
	print("UNIT SCALE HEIGHTS ", heights)
	await RenderingServer.frame_post_draw
	var img := viewport.get_texture().get_image()
	img.save_png(ProjectSettings.globalize_path("res://shots/unit_scale.png"))
	print("SHOT unit_scale ", img.get_size())
	quit()
