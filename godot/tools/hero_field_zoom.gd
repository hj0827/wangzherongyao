extends SceneTree

# 实战机位逐英雄验收图（入库工具）：把 5 个英雄轮流放到同一个地面位置，
# 用 arena 自己的相机（zoom 21 / 51° 俯角）拍整帧，再裁出英雄附近放大。
#
# 为什么必须单独一个工具：
#   `hero_gallery.gd` 是「近景好看」的验收，`arena_shot.gd` 只拍苍刃一个人。
#   而「血条压头 / 剑握在手腕 / 披风糊成一块黑板」这三类问题**只在 21 米机位下**
#   才看得出来，而且每个英雄的暴露点不同（铁壁是战旗、翎羽是弓、墨鸦是蹲姿）。
#   这就是「逐个英雄」的验收手段。
#
# 用法（必须走隐藏桌面，见 AGENTS.md 环境硬约束）：
#   powershell -ExecutionPolicy Bypass -File godot\tools\shot_offscreen.ps1 tools\hero_field_zoom.gd
# 产物：godot/shots/hero_field_zoom.png（5 行 × 2 列：整帧缩略 + 英雄放大）
#      godot/shots/hero_field_<hero>.png（整帧原图，未裁）

const Arena = preload("res://scripts/game/arena.gd")

const HEROES := ["blade", "mage", "tank", "archer", "assassin"]
# 中路靠近河道的直段草地：平整、没有墙/草丛/野怪，技能与人物不被场景抢读。
const SPOT := Vector2(-2.0, 8.0)
const FRAME := Vector2i(1600, 900)
# 放大后的裁切边长（正方形）。英雄在 21 米机位下约 60×70 像素，
# 裁 180 像素见方再放大 3 倍，正好把「血条 + 全身」都框进来。
const CROP := 240
const SCALE := 4
const CELL := Vector2i(CROP * SCALE, CROP * SCALE)

var arena: Node3D
var viewport: SubViewport
var _hero: Dictionary = {}

func _initialize() -> void:
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	DisplayServer.window_set_position(Vector2i(5200, 3200))
	Engine.max_fps = 15
	viewport = SubViewport.new()
	viewport.size = FRAME
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	_run()

func _run() -> void:
	arena = Arena.new()
	arena.configure({
		"config": {
			"mode": "duel",
			"humans": [{"id": "p1", "name": "观察者", "team": "blue", "hero_type": "blade"}],
			"bot_fill": false,
			"bot_ai": false,
		},
		"authoritative": true,
		"local_owner": "p1",
	})
	viewport.add_child(arena)
	while not arena.build_complete:
		await process_frame
	await create_timer(0.4).timeout
	if arena.hud != null:
		arena.hud.visible = false
	_hero = arena.sim.get_hero_by_player("p1")
	if _hero.is_empty():
		printerr("找不到本地英雄")
		quit(1)
		return
	arena.set_process(false)
	var sheet := Image.create_empty(CELL.x * 2, CELL.y * HEROES.size(), false, Image.FORMAT_RGBA8)
	sheet.fill(Color(0.05, 0.06, 0.08, 1.0))
	for row in HEROES.size():
		var hero_type := str(HEROES[row])
		# 换英雄类型：直接改 sim 里的 hero_type，再让 Arena 重建视图。
		_hero["hero_type"] = hero_type
		_hero["pos"] = SPOT
		_hero["moving"] = false
		_hero["hp"] = float(_hero.get("max_hp", 1000.0))
		_rebuild_view()
		# 等建立 + 量身高 + 装武器（分帧构建），再让相机跟上。
		await create_timer(0.35).timeout
		await _follow_camera()
		var frame := await _capture()
		frame.save_png(ProjectSettings.globalize_path(
			"res://shots/hero_field_%s.png" % hero_type))
		var screen: Vector2 = Vector2(800.0, 450.0)
		if arena.camera != null:
			screen = arena.camera.unproject_position(Vector3(SPOT.x, 1.0, SPOT.y))
		var zoomed := _crop_zoom(frame, Vector2i(int(screen.x), int(screen.y) - 30))
		var thumb := frame.duplicate() as Image
		thumb.resize(CELL.x, CELL.y, Image.INTERPOLATE_BILINEAR)
		sheet.blit_rect(thumb, Rect2i(Vector2i.ZERO, CELL), Vector2i(0, row * CELL.y))
		sheet.blit_rect(zoomed, Rect2i(Vector2i.ZERO, CELL),
			Vector2i(CELL.x, row * CELL.y))
		var bar_y := _health_bar_height()
		print("FIELD %-9s 血条y=%.2f  屏幕=%s" % [hero_type, bar_y, str(screen)])
	sheet.save_png(ProjectSettings.globalize_path("res://shots/hero_field_zoom.png"))
	print("FIELD sheet ", sheet.get_size())
	# 收尾：把 arena 的 process 还回去，避免退出时报泄漏。
	arena.set_process(true)
	quit(0)

## 换 hero_type 后**直接重建**视图。
##
## 不能只删掉 `_views` 里的条目等下一帧重建：`_sync_units` 只在「快照里出现了
## 新 id」时才创建视图，而这里 id 没变 —— 删掉之后英雄就再也不画了。
## 第一版就是这么拍出五张空地图的。
func _rebuild_view() -> void:
	var local_id := int(arena._local_entity_id)
	if local_id < 0:
		return
	var old_view: Node = arena._views.get(local_id)
	if old_view != null:
		arena._views.erase(local_id)
		(_units_parent() as Node).remove_child(old_view)
		old_view.queue_free()
	# 用 sim 里的真实实体重建一份，字段（owner_id / hero_type）都从 sim 拿。
	var entity: Dictionary = {}
	for item in arena.sim.snapshot().get("entities", []):
		if int(item.get("id", -1)) == local_id:
			entity = item
			break
	if entity.is_empty():
		return
	var view = arena._create_unit_view(entity)
	view.set_snapshot(entity, 0.016, 1.0,
		Vector2(float(entity.get("x", 0.0)), float(entity.get("y", 0.0))))
	arena._views[local_id] = view

func _units_parent() -> Node:
	var holder: Node = arena._views.values()[0].get_parent() if not arena._views.is_empty() else null
	return holder if holder != null else arena

func _follow_camera() -> void:
	# 相机由 arena 的 _update_camera() 驱动，但它被 set_process(false) 停掉了。
	# 这里手动推一帧：直接算好机位，避免整局跑起来。
	if arena.camera == null:
		return
	arena._update_camera(0.016, 1.0)
	await process_frame

func _capture() -> Image:
	await RenderingServer.frame_post_draw
	return viewport.get_texture().get_image()

func _crop_zoom(frame: Image, centre: Vector2i) -> Image:
	var half := CROP / 2
	var origin := Vector2i(centre.x - half, centre.y - half)
	origin.x = clampi(origin.x, 0, FRAME.x - CROP)
	origin.y = clampi(origin.y, 0, FRAME.y - CROP)
	var crop := frame.get_region(Rect2i(origin, Vector2i(CROP, CROP)))
	crop.resize(CELL.x, CELL.y, Image.INTERPOLATE_NEAREST)
	return crop

## 血条根节点的世界 y —— 用来核对「血条有没有压头」。
func _health_bar_height() -> float:
	var local_id := int(arena._local_entity_id)
	var view: Node = arena._views.get(local_id)
	if view == null:
		return -1.0
	var bar: Node3D = view.get("bar_root")
	if bar == null:
		return -1.0
	return bar.position.y
