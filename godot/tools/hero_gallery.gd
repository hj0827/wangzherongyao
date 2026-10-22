extends SceneTree

const UnitVisual = preload("res://scripts/game/unit_visual.gd")

var viewport: SubViewport
var views: Array = []

func _initialize() -> void:
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	DisplayServer.window_set_position(Vector2i(5200, 3200))
	Engine.max_fps = 15
	viewport = SubViewport.new()
	viewport.size = Vector2i(1600, 900)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)

	var world := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.05, 0.065, 0.09)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.55, 0.65, 0.8)
	environment.ambient_light_energy = 0.8
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	world.environment = environment
	viewport.add_child(world)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-38, -28, 0)
	sun.light_color = Color(1.0, 0.92, 0.8)
	sun.light_energy = 1.7
	sun.shadow_enabled = true
	viewport.add_child(sun)

	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-18, 150, 0)
	rim.light_color = Color(0.45, 0.62, 1.0)
	rim.light_energy = 0.7
	viewport.add_child(rim)

	var floor := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(30, 18)
	floor.mesh = plane
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.11, 0.12, 0.11)
	material.roughness = 0.92
	floor.material_override = material
	viewport.add_child(floor)

	var backdrop := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(30, 9, 0.4)
	backdrop.mesh = box
	backdrop.position = Vector3(0, 4.5, -3.2)
	var backdrop_material := StandardMaterial3D.new()
	backdrop_material.albedo_color = Color(0.07, 0.085, 0.1)
	backdrop_material.roughness = 1.0
	backdrop.material_override = backdrop_material
	viewport.add_child(backdrop)

	var camera := Camera3D.new()
	camera.position = Vector3(0, 2.2, 8.6)
	camera.fov = 45
	viewport.add_child(camera)
	camera.look_at_from_position(camera.position, Vector3(0, 1.0, 0), Vector3.UP)
	camera.current = true

	var types := ["blade", "mage", "tank", "archer"]
	var names := ["苍刃", "星璃", "铁壁", "翎羽"]
	for i in 4:
		var view := UnitVisual.new()
		var x := (float(i) - 1.5) * 2.75
		view.setup("hero", "blue", types[i], names[i], i == 0)
		view.set_snapshot({"x": x, "y": 0.0, "hp": 1000.0, "max_hp": 1000.0, "level": 3, "alive": true, "facing_x": 0.0, "facing_y": 1.0}, 1.0)
		view.position = Vector3(x, 0.0, 0.0)
		viewport.add_child(view)
		views.append(view)

	_run()

func _shot(file_name: String) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = viewport.get_texture().get_image()
	img.save_png(ProjectSettings.globalize_path("res://shots/%s.png" % file_name))
	print("SHOT ", file_name, " ", img.get_size())

func _run() -> void:
	await create_timer(0.8).timeout
	await _shot("gallery_idle")
	for view in views:
		view.play_attack()
	await create_timer(0.32).timeout
	await _shot("gallery_attack")
	quit()
