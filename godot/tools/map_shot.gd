extends SceneTree

# 地图观感截图工具（入库）。改地形 / 水面 / 植被 / 光照后用它看真实效果。
#
# 用法：godot --path godot --script res://tools/map_shot.gd
# 产物：godot/shots/map_overview.png / map_river.png / map_jungle.png / map_base.png（不入库）

const Arena = preload("res://scripts/game/arena.gd")
const MapData = preload("res://sim/map_data.gd")
const MapLayout = preload("res://sim/map/map_layout.gd")

var arena: Node3D
var viewport: SubViewport

func _initialize() -> void:
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, true)
	DisplayServer.window_set_position(Vector2i(5200, 3200))
	Engine.max_fps = 15
	viewport = SubViewport.new()
	viewport.size = Vector2i(1600, 900)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var config := {
		"mode": "team",
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
	print("SHOT ", file_name)

# 摆一个固定机位。arena 自己的 _update_camera 每帧都会覆盖相机，
# 所以先关掉它的 _process。
func _place(eye: Vector3, target: Vector3, fov: float = 55.0) -> void:
	arena.camera.fov = fov
	arena.camera.position = eye
	arena.camera.look_at(target, Vector3.UP)

func _run() -> void:
	while not arena.build_complete:
		await process_frame
	await create_timer(0.6).timeout
	arena.set_process(false)
	arena.hud.visible = false

	# 1. 高空斜俯视：看整张图的地形、河道、三条路
	_place(Vector3(-92.0, 96.0, -92.0), Vector3(0.0, 0.0, 0.0), 52.0)
	await create_timer(0.5).timeout
	await _shot("map_overview")

	# 2. 河道近景：看水面与岸线
	_place(Vector3(-16.0, 9.0, 16.0), Vector3(0.0, 0.0, 0.0), 46.0)
	await create_timer(0.4).timeout
	await _shot("map_river")

	# 3. 野区近景：看植被与岩石。机位跟着**当前**的营地走 ——
	# 营地挪过一次，写死旧坐标的结果是「拍到的空地上什么都没有」，
	# 上一轮就是靠这张图误判过。这里直接取 MapLayout 的第一座营地。
	var camp: Vector2 = MapLayout.CAMPS[0].pos
	_place(Vector3(camp.x + 10.0, 13.0, camp.y + 12.0), Vector3(camp.x, 0.0, camp.y), 50.0)
	await create_timer(0.4).timeout
	await _shot("map_jungle")

	# 4. 基地：看建筑与广场
	var base := MapData.BLUE_BASE
	_place(Vector3(base.x - 6.0, 13.0, base.y - 20.0), Vector3(base.x, 2.0, base.y), 50.0)
	await create_timer(0.4).timeout
	await _shot("map_base")

	# 5. 首领坑：看坑盘与四根石柱是否整圈落在岸上
	var pit: Vector2 = MapLayout.OBJECTIVE_PITS[0].pos
	_place(Vector3(pit.x + 11.0, 12.0, pit.y + 13.0), Vector3(pit.x, 0.0, pit.y), 46.0)
	await create_timer(0.4).timeout
	await _shot("map_pit")

	# 6. 传送阵：看阵盘离水多远 —— 这张是「法阵漂在水里」最直接的证据图
	var pad: Vector2 = MapLayout.TELEPORT_PADS[0].pos
	_place(Vector3(pad.x + 10.0, 11.0, pad.y + 12.0), Vector3(pad.x, 0.0, pad.y), 46.0)
	await create_timer(0.4).timeout
	await _shot("map_pad")

	quit()
