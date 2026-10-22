extends SceneTree
## 主菜单单屏渲染：连拍三帧，用于确认动态背景真的在动（雾、辉光、火星、原画缓推）

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
	await create_timer(1.2).timeout
	await _shot("menu_t0")
	await create_timer(2.0).timeout
	await _shot("menu_t2")
	await create_timer(3.0).timeout
	await _shot("menu_t5")
	quit()
