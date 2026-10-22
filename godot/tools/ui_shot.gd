extends SceneTree

const MAIN := preload("res://scenes/main_menu.tscn")

var OUT_DIR := ProjectSettings.globalize_path("res://shots/")

var main: Node
var viewport: SubViewport

func _initialize() -> void:
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, true)
	DisplayServer.window_set_position(Vector2i(5200, 3200))
	DisplayServer.window_set_size(Vector2i(1, 1))
	Engine.max_fps = 30
	viewport = SubViewport.new()
	viewport.size = Vector2i(1600, 900)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.gui_disable_input = true
	root.add_child(viewport)
	main = MAIN.instantiate()
	viewport.add_child(main)
	_run()

func _shot(file_name: String) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = viewport.get_texture().get_image()
	img.save_png(OUT_DIR + file_name + ".png")
	print("SHOT ", file_name, " ", img.get_size())

func _run() -> void:
	await create_timer(0.9).timeout
	await _shot("ui_menu")

	main._show_hero_select()
	await create_timer(0.5).timeout
	await _shot("ui_hero_select")
	main.local_hero = "archer"
	main._refresh_hero_selection()
	await create_timer(0.3).timeout
	await _shot("ui_hero_select_archer")

	main._pending_online = true
	main._pending_mode = "duel"
	main._show_online()
	await create_timer(0.6).timeout
	await _shot("ui_online")

	main._pending_mode = "team"
	var hosted: Dictionary = main.session.host_game(24690, "苍刃", "mage", "team")
	if bool(hosted.get("ok", false)):
		main.discovery.start_advertising({
			"code": str(hosted.code),
			"name": "苍刃",
			"port": int(hosted.port),
			"mode": "team",
			"players": 1,
		}, 24691)
		main._discovery_hosting = true
		main._show_lobby()
		await create_timer(0.6).timeout
		await _shot("ui_lobby_team")
		main.session.close()
		main.discovery.stop()

	main._ui.visible = true
	main._pending_online = false
	main._pending_mode = "duel"
	main.local_hero = "blade"
	main._start_offline()
	await create_timer(2.4).timeout
	await _shot("ui_match_duel")

	main._leave_game()
	await create_timer(0.5).timeout
	await _shot("ui_back_menu")

	main._pending_online = false
	main._pending_mode = "team"
	main.local_hero = "archer"
	main._start_offline()
	await create_timer(2.8).timeout
	await _shot("ui_match_team")
	var local: Variant = main._arena.sim.get_hero_by_player("p1")
	if local != null:
		local.pos = Vector2(0.0, 0.0)
		for entity in main._arena.sim.state.entities:
			if entity.type == "hero" and entity.team == "red":
				entity.pos = Vector2(2.5, 0.0)
				break
		main._arena._mouse_ground = Vector2(2.5, 0.0)
		main._arena._mouse_valid = true
	await create_timer(0.2).timeout
	main._arena._on_skill_button("q")
	await create_timer(0.12).timeout
	await _shot("ui_match_skill")

	for entity in main._arena.sim.state.entities:
		if entity.type == "base" and entity.team == "red":
			main._arena.sim._damage(entity, 99999.0, {})
			break
	await create_timer(0.6).timeout
	await _shot("ui_result")
	main._leave_game()
	quit()
