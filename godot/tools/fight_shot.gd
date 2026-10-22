extends SceneTree

const Arena = preload("res://scripts/game/arena.gd")

var arena: Node3D
var viewport: SubViewport

func _initialize() -> void:
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	DisplayServer.window_set_position(Vector2i(5200, 3200))
	Engine.max_fps = 15
	viewport = SubViewport.new()
	viewport.size = Vector2i(1600, 900)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var config := {
		"mode": "duel",
		"humans": [{"id": "p1", "name": "苍刃", "team": "blue", "hero_type": "blade"}],
		"bot_fill": true,
		"bot_ai": true,
	}
	arena = Arena.new()
	arena.configure({"config": config, "authoritative": true, "local_owner": "p1"})
	viewport.add_child(arena)
	_run()

func _shot(file_name: String) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = viewport.get_texture().get_image()
	img.save_png(ProjectSettings.globalize_path("res://shots/%s.png" % file_name))
	print("SHOT ", file_name, " ", img.get_size())

func _fast_forward(seconds: float) -> void:
	for i in int(seconds * 30.0):
		arena.sim.tick(1.0 / 30.0)
		var hero: Dictionary = arena.sim.get_hero_by_player("p1")
		if not hero.is_empty():
			hero.hp = hero.max_hp
			hero.mp = hero.max_mp
	arena.current_snapshot = arena.sim.snapshot()
	arena._sync_structures(arena.current_snapshot, true)
	arena._sync_units(arena.current_snapshot, 1.0)
	arena.hud.update_snapshot(arena.current_snapshot)

func _run() -> void:
	await create_timer(1.2).timeout
	var hero: Dictionary = arena.sim.get_hero_by_player("p1")
	hero.pos = Vector2(0.0, 3.0)
	_fast_forward(18.0)
	arena.zoom = 20.0
	arena._update_camera(1.0, true)
	await create_timer(0.8).timeout
	await _shot("fight_center")

	arena._on_skill_button("q")
	await create_timer(0.28).timeout
	await _shot("fight_skill")

	arena.zoom = 11.0
	arena._update_camera(1.0, true)
	await create_timer(0.5).timeout
	await _shot("fight_close")

	quit()
