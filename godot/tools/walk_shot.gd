extends SceneTree

# 走路姿态连拍：模拟按住 W 前进，近景抓 3 帧，
# 用来肉眼确认腿在迈步（不是站立滑行）。

const Arena = preload("res://scripts/game/arena.gd")

var arena: Node3D
var viewport: SubViewport

func _initialize() -> void:
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, true)
	DisplayServer.window_set_position(Vector2i(5200, 3200))
	DisplayServer.window_set_size(Vector2i(1, 1))
	viewport = SubViewport.new()
	viewport.size = Vector2i(1280, 720)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.gui_disable_input = true
	root.add_child(viewport)
	arena = Arena.new()
	arena.configure({
		"config": {
			"mode": "duel",
			"humans": [{"id": "p1", "name": "苍刃", "team": "blue", "hero_type": "blade"}],
			"bot_fill": true,
			"bot_ai": true,
		},
		"authoritative": true,
		"local_owner": "p1",
	})
	viewport.add_child(arena)
	_run()

func _shot(file_name: String) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = viewport.get_texture().get_image()
	img.save_png(ProjectSettings.globalize_path("res://shots/%s.png" % file_name))
	print("SHOT ", file_name)

func _run() -> void:
	while not arena.build_complete:
		await process_frame
	await create_timer(0.4).timeout
	arena.hud.visible = false
	arena._mouse_valid = false
	var hero: Dictionary = arena.sim.get_hero_by_player("p1")
	hero.pos = Vector2(0.0, 0.0)
	arena.zoom = 6.0
	arena._update_camera(1.0, true)
	var ev := InputEventKey.new()
	ev.keycode = KEY_W
	ev.physical_keycode = KEY_W
	ev.pressed = true
	Input.parse_input_event(ev)
	await create_timer(0.8).timeout
	for i in 3:
		await _shot("walk_%d" % i)
		await create_timer(0.11).timeout
	var up := InputEventKey.new()
	up.keycode = KEY_W
	up.physical_keycode = KEY_W
	up.pressed = false
	Input.parse_input_event(up)
	quit()
