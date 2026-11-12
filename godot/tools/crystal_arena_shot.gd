extends SceneTree

## 临时验收：把英雄放到基地旁边，用真实对局相机看水晶。
## 画廊（crystal_gallery）只有纯色地面，验证不了「水晶和地形/城墙/角色同框」。

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
		"bot_ai": false,
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

func _run() -> void:
	while not arena.build_complete:
		await process_frame
	await create_timer(0.8).timeout
	arena.hud.visible = false
	arena._mouse_valid = false
	var hero: Dictionary = arena.sim.get_hero_by_player("p1")

	# 蓝方基地在 (46,-46)。英雄站在基地斜前方，镜头越过英雄看向水晶。
	hero.pos = Vector2(42.0, -42.0)
	hero.facing = Vector2(0.7071, -0.7071)
	arena.zoom = 15.0
	arena._update_camera(1.0, true)
	await create_timer(0.8).timeout
	await _shot("crystal_arena_blue")

	# 红方基地在 (-46,46)。
	hero.pos = Vector2(-42.0, 42.0)
	hero.facing = Vector2(-0.7071, 0.7071)
	arena.zoom = 15.0
	arena._update_camera(1.0, true)
	await create_timer(0.8).timeout
	await _shot("crystal_arena_red")

	# 默认对局焦距：看 21 米机位下两个阵营还能不能分辨。
	hero.pos = Vector2(46.0, -38.0)
	hero.facing = Vector2(0.0, -1.0)
	arena.zoom = 21.0
	arena._update_camera(1.0, true)
	await create_timer(0.8).timeout
	await _shot("crystal_arena_zoom21")

	quit()
