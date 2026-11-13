extends SceneTree

# 英雄画廊（入库工具）：给 5 个英雄各拍三张——正面特写 / 3-4 侧面 / 21 米实战机位，
# 再拼成一张对照大图。判断标准不是「单看某个英雄挺帅」，而是三件事：
#   1. 五个人并排时剪影能不能两两分开；
#   2. 主色/发光色是不是一眼能对上立绘（苍刃墨绿、星璃靛紫、铁壁铁橙、翎羽青白、墨鸦紫黑）；
#   3. 21 米俯视（玩家 90% 时间看到的距离）下还认不认得出。
#
# 环境与主光直接吃 ArenaLook：画廊里看到的颜色必须就是游戏里的颜色。
# 自己另写一套光照（尤其不开 bloom）时，「星环到底亮不亮」「金边是不是脏」判断不了。
#
# 用法（必须走隐藏桌面，见 AGENTS.md 的环境硬约束）：
#   powershell -ExecutionPolicy Bypass -File godot\tools\shot_offscreen.ps1 tools\hero_gallery.gd
# 产物：godot/shots/hero_sheet.png（5×3 对照图）
#      godot/shots/hero_<type>.png（单英雄三联：正面 / 侧面 / 实战）
#      godot/shots/hero_field.png（五人在 21 米机位同框）

const UnitVisual = preload("res://scripts/game/unit_visual.gd")
const ModelUtils = preload("res://scripts/game/model_utils.gd")
const ArenaLook = preload("res://scripts/game/arena_look.gd")
const HeroLook = preload("res://scripts/game/hero_look.gd")
const HeroCostume = preload("res://scripts/game/hero_costume.gd")

const HEROES := [
	{"type": "blade", "name": "苍刃"},
	{"type": "mage", "name": "星璃"},
	{"type": "tank", "name": "铁壁"},
	{"type": "archer", "name": "翎羽"},
	{"type": "assassin", "name": "墨鸦"},
]

const CELL := Vector2i(360, 520)
const FOV := 34.0
# 实战机位：与 arena.CAMERA_PITCH_UP / CAMERA_PITCH_BACK 同源（zoom 21 / 51° 俯角）。
const FIELD_ZOOM := 21.0
const FIELD_PITCH_UP := 0.94
const FIELD_PITCH_BACK := 0.76
const FIELD_FOV := 42.0

var viewport: SubViewport
var camera: Camera3D
var stage: Node3D
var views: Array[UnitVisual] = []

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

	# 舞台地面：深色石台 + 一圈英雄主色环，人物边缘能读出来。
	var floor := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(14, 14)
	floor.mesh = plane
	var floor_material := StandardMaterial3D.new()
	floor_material.albedo_color = Color(0.14, 0.15, 0.14)
	floor_material.roughness = 0.9
	floor.material_override = floor_material
	floor.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	viewport.add_child(floor)

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
	view.position = Vector3.ZERO
	stage.add_child(view)
	return view

func _clear() -> void:
	for child in stage.get_children():
		child.queue_free()
	views.clear()

func _shot(file_name: String) -> Image:
	await RenderingServer.frame_post_draw
	var image: Image = viewport.get_texture().get_image()
	if file_name != "":
		image.save_png(ProjectSettings.globalize_path("res://shots/%s.png" % file_name))
		print("SHOT ", file_name, " ", image.get_size())
	return image

## 框住一个英雄：按包围盒（排除武器与配件之外的溢出）退到刚好装下。
func _frame_hero(view: UnitVisual, yaw_deg: float) -> void:
	camera.fov = FOV
	var box := ModelUtils.relative_aabb(view.model_root)
	var height := maxf(box.size.y, 2.4)
	var half := tan(deg_to_rad(camera.fov * 0.5))
	var distance := height / (2.0 * half) * 1.30
	var centre := Vector3(0.0, height * 0.52, 0.0)
	var yaw := deg_to_rad(yaw_deg)
	camera.position = centre + Vector3(sin(yaw) * distance, height * 0.10, cos(yaw) * distance)
	camera.look_at_from_position(camera.position, centre, Vector3.UP)

func _count_meshes(root: Node) -> int:
	return root.find_children("*", "MeshInstance3D", true, false).size()

func _run() -> void:
	await create_timer(0.8).timeout
	# 四列：正面 / 侧面 / 头肩特写 / 21 米实战机位。
	# 最后一列不能省：前三列都是「拉近看细节」，而玩家 90% 时间看到的是那一格，
	# 判断「认不认得出这个人」只能靠它。
	var sheet := Image.create_empty(CELL.x * 4, CELL.y * HEROES.size(), false, Image.FORMAT_RGBA8)
	for row in HEROES.size():
		var spec: Dictionary = HEROES[row]
		var hero_type := str(spec["type"])
		_clear()
		await create_timer(0.08).timeout
		var view := _spawn(hero_type, str(spec["name"]))
		await create_timer(0.12).timeout
		# 正面：相机稍微偏一点，纯正面会读成证件照，看不出肩甲/披风的厚度。
		var shots := [["front", -18.0], ["side", -88.0], ["bust", -28.0]]
		var images: Array[Image] = []
		for entry in shots:
			view.rotation.y = 0.0
			if str(entry[0]) == "bust":
				_frame_bust(view)
			else:
				_frame_hero(view, float(entry[1]))
			await create_timer(0.08).timeout
			var image := await _shot("")
			images.append(image)
			if str(entry[0]) == "front":
				image.save_png(
					ProjectSettings.globalize_path("res://shots/hero_%s_front.png" % hero_type))
		images.append(await _field_cell(view))
		var costume: Dictionary = view._costume
		print("HERO %-8s 网格=%3d 材质缓存=%d 件=%2d 摆动组=%d 身高=%.2f" % [
			hero_type, _count_meshes(view.model_root),
			HeroCostume.material_count(), (costume.get("parts", []) as Array).size(),
			(costume.get("sway", {}) as Dictionary).size(),
			ModelUtils.relative_aabb(view.model_root).size.y])
		for column in images.size():
			sheet.blit_rect(images[column], Rect2i(Vector2i.ZERO, CELL),
				Vector2i(column * CELL.x, row * CELL.y))
	sheet.save_png(ProjectSettings.globalize_path("res://shots/hero_sheet.png"))
	print("SHOT hero_sheet ", sheet.get_size())

	# 五人同框的实战机位：判断「并排时剪影能不能分开」。
	_clear()
	viewport.size = Vector2i(1600, 900)
	camera.current = false
	var field_camera := Camera3D.new()
	field_camera.fov = FIELD_FOV
	field_camera.position = Vector3(0.0, FIELD_ZOOM * FIELD_PITCH_UP, -FIELD_ZOOM * FIELD_PITCH_BACK)
	field_camera.look_at_from_position(field_camera.position, Vector3(0.0, 0.8, 6.0), Vector3.UP)
	field_camera.current = true
	viewport.add_child(field_camera)
	var floor_size := 40
	for i in HEROES.size():
		var spec: Dictionary = HEROES[i]
		var view := _spawn(str(spec["type"]), str(spec["name"]))
		view.position = Vector3((float(i) - 2.0) * 2.4, 0.0, 2.0)
		view.rotation.y = 0.0
	await create_timer(0.3).timeout
	await _shot("hero_field")
	quit()

## 头肩特写：21 米机位下看不清脸，但近景能判断「像不像那个角色」。
##
## ★ 中心必须按**身体**包围盒算，不能含武器与配件。
##   待机姿势换过之后（HERO-07），苍刃抱臂时剑尖举过头顶、铁壁战旗比头还高，
##   用整棵树算「顶点」会把镜头对到剑尖上 —— 实拍是一张只剩额头的图。
##   排除口径与 `test_hero_silhouette` 一致：摘掉 WeaponSlot 与 HeroCostume_* 挂点。
func _frame_bust(view: UnitVisual) -> void:
	var top := _body_top(view)
	var centre := Vector3(0.0, top - 0.30, 0.0)
	var yaw := deg_to_rad(-28.0)
	var distance := 2.35
	camera.fov = 34.0
	camera.position = centre + Vector3(sin(yaw) * distance, 0.08, cos(yaw) * distance)
	camera.look_at_from_position(camera.position, centre, Vector3.UP)

## 身体最高点（模型坐标，不含武器与配件）。
func _body_top(view: UnitVisual) -> float:
	var saved_weapon: Node = null
	var weapon := view.model_root.find_child("WeaponSlot", true, false)
	if weapon != null and weapon.get_parent() != null:
		saved_weapon = weapon
		saved_weapon.get_parent().remove_child(saved_weapon)
	var anchors: Array[Node] = []
	var anchor_parent: Node = null
	for node in view.model_root.find_children("*", "BoneAttachment3D", true, false):
		anchor_parent = node.get_parent()
		break
	if anchor_parent != null:
		for anchor in anchor_parent.find_children("HeroCostume_*", "BoneAttachment3D", true, false):
			anchors.append(anchor)
			anchor_parent.remove_child(anchor)
	var box := ModelUtils.relative_aabb(view.model_root)
	var top := box.position.y + box.size.y
	if anchor_parent != null:
		for anchor in anchors:
			anchor_parent.add_child(anchor)
	if saved_weapon != null:
		view.model_root.add_child(saved_weapon)
	return top

## 单人在 21 米俯视机位下的一格：用来对照「远看还剩什么」。
##
## 取景是**真实实战机位**（zoom 21 / 51° 俯角 / FOV 42），但把中央一半裁出来
## 再放大 2 倍贴进格子 —— 360×520 的画幅里英雄只有约 50 像素高，不放大在拼图上
## 根本判读不了「认不认得出」。实际屏占比看 `hero_field.png`（那张是未裁的原帧）。
func _field_cell(view: UnitVisual) -> Image:
	var cell := Image.create_empty(CELL.x, CELL.y, false, Image.FORMAT_RGBA8)
	cell.fill(Color(0.12, 0.14, 0.12))
	var saved := camera.global_transform
	camera.fov = FIELD_FOV
	var target := Vector3(0.0, 0.9, 0.0)
	camera.position = target + Vector3(0.0, FIELD_ZOOM * FIELD_PITCH_UP, FIELD_ZOOM * FIELD_PITCH_BACK)
	camera.look_at_from_position(camera.position, target, Vector3.UP)
	await create_timer(0.06).timeout
	await RenderingServer.frame_post_draw
	var frame: Image = viewport.get_texture().get_image()
	# 只裁掉四边各 15%：保留「周围有多空」这个尺感，同时让人物占满画面中间。
	# 裁得太狠（1/3）会读成「实战里英雄很大」，和真实观感相反。
	var inset := Vector2i(int(CELL.x * 0.15), int(CELL.y * 0.15))
	var crop := frame.get_region(Rect2i(inset, CELL - inset * 2))
	crop.resize(CELL.x, CELL.y, Image.INTERPOLATE_BILINEAR)
	cell.blit_rect(crop, Rect2i(Vector2i.ZERO, CELL), Vector2i.ZERO)
	camera.global_transform = saved
	camera.fov = FOV
	return cell
