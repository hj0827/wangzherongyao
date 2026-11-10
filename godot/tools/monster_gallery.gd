extends SceneTree

# 野怪画廊（入库工具）：把每一种野怪形象**单独放大**拍一张，再拼成一张对照图，
# 外加一张实战取景图（51° 俯角 / zoom 21 / FOV 42，和平常打游戏看到的一样）。
#
# 为什么需要它：野怪在实战里是「20 米机位下的一小块剪影」，看单帧战斗截图根本判断不了
# 「蜥蜴和野猪是不是长得一样」「蓝石像和红石像能不能一眼分开」。同框放大 + 实战取景
# 两个视角一起看，才谈得上「形象好不好」。
#
# 用法：godot --path godot --script res://tools/monster_gallery.gd
# 产物：godot/shots/monster_sheet.png（4×2 对照图）、monster_field.png（实战取景）
#      （shots/ 已忽略，不入库）

const UnitVisual = preload("res://scripts/game/unit_visual.gd")
const ModelUtils = preload("res://scripts/game/model_utils.gd")
const MonsterForms = preload("res://scripts/game/monster_forms.gd")
const MonsterKit = preload("res://scripts/game/monster_kit.gd")
const ArenaLook = preload("res://scripts/game/arena_look.gd")

# zoom 21 下的机位，与 arena.CAMERA_PITCH_UP / CAMERA_PITCH_BACK 同源。
const FIELD_ZOOM := 21.0
const FIELD_PITCH_UP := 0.94
const FIELD_PITCH_BACK := 0.76
const FIELD_FOV := 42.0

const CELL := Vector2i(400, 450)
const COLUMNS := 4

# 一行一个形态：type / name 都按 MapLayout.CAMPS 与 OBJECTIVE_PITS 的真实数据写。
const SHEET_UNITS := [
	{"type": "wolf", "name": "双狼"},
	{"type": "lizard", "name": "蜥蜴"},
	{"type": "boar", "name": "三猪"},
	{"type": "bird", "name": "红鸟"},
	{"type": "blue_sentinel", "name": "霜狼", "buff": "blue"},
	{"type": "red_sentinel", "name": "赤狼", "buff": "red"},
	{"type": "tyrant", "name": "暴君", "objective": true, "pit": "tyrant"},
	{"type": "overlord", "name": "主宰", "objective": true, "pit": "overlord"},
]

var viewport: SubViewport
var camera: Camera3D
var field_camera: Camera3D
var field_root: Node3D
var sheet_units_root: Node3D

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
	# 环境与主光直接吃 arena 的观感层：画廊里挑的颜色必须就是实战里看到的颜色。
	# 自己另写一套光照（尤其是不开 bloom）时，「晶体是不是发光」根本判断不了。
	var world := WorldEnvironment.new()
	var environment := Environment.new()
	ArenaLook.apply_environment(environment)
	world.environment = environment
	viewport.add_child(world)

	var sun := DirectionalLight3D.new()
	ArenaLook.apply_sun(sun)
	viewport.add_child(sun)

	var floor := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(60, 40)
	floor.mesh = plane
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.3, 0.42, 0.24)
	material.roughness = 0.95
	floor.material_override = material
	viewport.add_child(floor)

	camera = Camera3D.new()
	camera.fov = 40.0
	camera.current = true
	viewport.add_child(camera)

	sheet_units_root = Node3D.new()
	viewport.add_child(sheet_units_root)

	field_root = Node3D.new()
	field_root.visible = false
	viewport.add_child(field_root)

	field_camera = Camera3D.new()
	field_camera.fov = FIELD_FOV
	field_camera.position = Vector3(0.0, FIELD_ZOOM * FIELD_PITCH_UP, -FIELD_ZOOM * FIELD_PITCH_BACK)
	field_camera.look_at_from_position(field_camera.position, Vector3(0.0, 0.8, 6.0), Vector3.UP)
	field_camera.current = false
	viewport.add_child(field_camera)

func _spawn(unit: Dictionary, parent: Node, pos: Vector3) -> UnitVisual:
	var view := UnitVisual.new()
	var is_objective := bool(unit.get("objective", false))
	view.setup(
		"monster",
		"neutral",
		str(unit.get("type", "wolf")),
		str(unit.get("name", "野怪")),
		false,
		"blue",
		is_objective,
		str(unit.get("pit", ""))
	)
	view.set_monster_badge(str(unit.get("buff", "")), is_objective)
	view.set_snapshot({
		"x": pos.x, "y": pos.z,
		"hp": 720.0, "max_hp": 720.0, "alive": true,
		"facing_x": 0.0, "facing_y": 1.0, "moving": false,
	}, 1.0)
	view.position = pos
	parent.add_child(view)
	return view

func _clear(parent: Node) -> void:
	for child in parent.get_children():
		child.queue_free()

func _shot(file_name: String) -> Image:
	await RenderingServer.frame_post_draw
	var img: Image = viewport.get_texture().get_image()
	if file_name != "":
		img.save_png(ProjectSettings.globalize_path("res://shots/%s.png" % file_name))
		print("SHOT ", file_name, " ", img.get_size())
	return img

# 单只野怪特写：相机按它在**画面上实际占多大**退到「刚好装下 + 一点余量」。
#
# 不能直接拿包围盒的长边当尺子：长条形的怪（蜥蜴 3 米、首领 5 米）长度是纵深，
# 屏幕上并不占宽。按长度退会让它在格子里缩成一小坨，看不出版型。
func _frame_form(view: UnitVisual) -> void:
	var box := ModelUtils.relative_aabb(view.model_root)
	var aspect := float(CELL.x) / float(CELL.y)
	var half := tan(deg_to_rad(camera.fov * 0.5))
	# 纵深按 0.45 折算成屏幕宽度（俯角约 12°，长度只有一部分投影到横向）。
	var projected_width := maxf(box.size.x, box.size.z * 0.45)
	var distance := maxf(box.size.y / (2.0 * half), projected_width / (2.0 * half * aspect)) * 1.62
	var centre := Vector3(0.0, box.size.y * 0.46, 0.0)
	camera.position = centre + Vector3(0.0, box.size.y * 0.3 + distance * 0.22, distance)
	camera.look_at_from_position(camera.position, centre, Vector3.UP)

func _run() -> void:
	await create_timer(0.9).timeout
	var sheet := Image.create_empty(CELL.x * COLUMNS, CELL.y * int(ceil(float(SHEET_UNITS.size()) / float(COLUMNS))), false, Image.FORMAT_RGBA8)
	for i in SHEET_UNITS.size():
		_clear(sheet_units_root)
		await create_timer(0.12).timeout
		var view := _spawn(SHEET_UNITS[i], sheet_units_root, Vector3.ZERO)
		_frame_form(view)
		var box := ModelUtils.relative_aabb(view.model_root)
		print("SHEET %-16s h=%.2f w=%.2f d=%.2f 网格=%d 材质=%d" % [
			str(SHEET_UNITS[i]["type"]),
			box.size.y,
			box.size.x,
			box.size.z,
			_count_meshes(view.model_root),
			MonsterKit.material_count(),
		])
		await create_timer(0.16).timeout
		var cell := await _shot("")
		var column := i % COLUMNS
		var row := i / COLUMNS
		sheet.blit_rect(cell, Rect2i(Vector2i.ZERO, CELL), Vector2i(column * CELL.x, row * CELL.y))
	sheet.save_png(ProjectSettings.globalize_path("res://shots/monster_sheet.png"))
	print("SHOT monster_sheet ", sheet.get_size())

	# 实战取景：主角英雄 + 各类野怪，51° 俯角、zoom 21，判断「俯视下还认不认得出」。
	_clear(sheet_units_root)
	field_root.visible = true
	viewport.size = Vector2i(1600, 900)
	var hero := UnitVisual.new()
	hero.setup("hero", "blue", "blade", "苍刃", true, "blue")
	hero.position = Vector3(-3.4, 0.0, 3.2)
	hero.set_snapshot({
		"x": -3.4, "y": 3.2, "hp": 2000.0, "max_hp": 2000.0, "mp": 400.0, "max_mp": 400.0,
		"level": 6, "alive": true, "facing_x": 0.0, "facing_y": 1.0,
	}, 1.0)
	field_root.add_child(hero)
	var field_units := [
		{"spec": {"type": "blue_sentinel", "name": "霜狼", "buff": "blue"}, "pos": Vector3(-4.8, 0.0, 0.4)},
		{"spec": {"type": "red_sentinel", "name": "赤狼", "buff": "red"}, "pos": Vector3(4.8, 0.0, 1.2)},
		{"spec": {"type": "lizard", "name": "蜥蜴"}, "pos": Vector3(-0.9, 0.0, 6.6)},
		{"spec": {"type": "bird", "name": "红鸟"}, "pos": Vector3(2.6, 0.0, 7.4)},
		{"spec": {"type": "wolf", "name": "双狼"}, "pos": Vector3(-6.6, 0.0, -3.4)},
		{"spec": {"type": "boar", "name": "三猪"}, "pos": Vector3(6.6, 0.0, 9.0)},
		{"spec": {"type": "tyrant", "name": "暴君", "objective": true, "pit": "tyrant"}, "pos": Vector3(-9.5, 0.0, 12.0)},
	]
	for entry in field_units:
		var view := _spawn(entry["spec"], field_root, entry["pos"])
		view.rotation.y = PI
		view.set_snapshot({
			"x": entry["pos"].x, "y": entry["pos"].z,
			"hp": 720.0, "max_hp": 720.0, "alive": true,
			"facing_x": 0.0, "facing_y": -1.0,
		}, 1.0)
	field_camera.current = true
	camera.current = false
	await create_timer(0.4).timeout
	await _shot("monster_field")
	quit()

func _count_meshes(root: Node) -> int:
	return root.find_children("*", "MeshInstance3D", true, false).size()
