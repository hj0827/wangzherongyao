extends SceneTree

# 血条配色的像素级验证工具（入库）。
#
# 为什么需要它：血条色常量对，不等于屏幕上的颜色对。
# arena 用 TONE_MAPPER_FILMIC + exposure 1.05，FILMIC 的肩部会把中间调提亮，
# 绿色和蓝色的 G 通道被抬得最狠 —— 直接写纯色的话，友军蓝渲染出来是青白色。
# 这个工具复刻 arena 的 environment，把三种关系的血条各渲一格，
# 采样中心像素，打印「设定色 -> 实际渲染色」，改色前先跑它。
#
# 用法：godot --path godot --script res://tools/bar_color_shot.gd
# 产物：godot/shots/bar_colors.png（不入库）

const BAR_SHADER := preload("res://shaders/billboard_bar.gdshader")
const UnitVisual = preload("res://scripts/game/unit_visual.gd")

const CELL := 120
# 顺序与 bar_color() 的三种结果一一对应
const CASES := [
	["self_green ", "自己"],
	["ally_blue  ", "友军"],
	["enemy_red  ", "敌军"],
]

var viewport: SubViewport

func _initialize() -> void:
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, true)
	DisplayServer.window_set_position(Vector2i(5200, 3200))
	Engine.max_fps = 15
	viewport = SubViewport.new()
	viewport.size = Vector2i(CELL * CASES.size(), CELL)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	_build()
	_run()

# 与 arena.gd::_build_environment 保持一致，否则测出来的不是线上观感。
func _build() -> void:
	var world := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0, 0, 0)
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.05
	world.environment = env
	viewport.add_child(world)

	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 3.0
	cam.position = Vector3(0.0, 0.0, 4.0)
	viewport.add_child(cam)

	var colors := [
		UnitVisual.bar_color(true, "blue", "blue"),
		UnitVisual.bar_color(false, "blue", "blue"),
		UnitVisual.bar_color(false, "red", "blue"),
	]
	for i in colors.size():
		var quad := QuadMesh.new()
		quad.size = Vector2(0.9, 0.9)
		var mi := MeshInstance3D.new()
		mi.mesh = quad
		var mat := ShaderMaterial.new()
		mat.shader = BAR_SHADER
		mat.set_shader_parameter("fill_color", colors[i])
		mat.set_shader_parameter("padding", 0.0)
		mat.set_shader_parameter("ratio", 1.0)
		mi.material_override = mat
		mi.position = Vector3((float(i) - 1.0) * 3.0, 0.0, 0.0)
		viewport.add_child(mi)

func _run() -> void:
	await create_timer(0.4).timeout
	await RenderingServer.frame_post_draw
	var img: Image = viewport.get_texture().get_image()
	img.save_png(ProjectSettings.globalize_path("res://shots/bar_colors.png"))
	var colors := [
		UnitVisual.HP_SELF,
		UnitVisual.HP_ALLY,
		UnitVisual.HP_ENEMY,
	]
	for i in colors.size():
		var c := img.get_pixel(CELL * i + CELL / 2, CELL / 2)
		var s: Color = colors[i]
		print("BAR %s 设定=(%.2f,%.2f,%.2f) 渲染=(%.2f,%.2f,%.2f)" % [
			CASES[i][0], s.r, s.g, s.b, c.r, c.g, c.b])
	print("SHOT bar_colors ", img.get_size())
	quit()
