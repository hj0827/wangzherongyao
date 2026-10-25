extends RefCounted
class_name BushField

## 草丛表现。**只影响画面，不参与模拟。**
##
## 旧实现是每个草丛 7 个压扁的球体：没有叶片轮廓、没有层次，俯视只能读成
## 「几个绿色气球」。这里改成程序化叶簇：
## - 每丛一千多片小叶片填充成扁球体，外沿一直铺到玩法半径；
## - 叶片是真实几何轮廓，双面渲染 + 背光透光，不依赖贴图与 billboard；
## - 叶簇内部还有一团暗色实体，挡住水面透光，否则俯视能看到「空心的鸟窝」；
## - 顶点色逐叶抖动明暗与黄绿色相，风摆只作用于叶尖；
## - 地面用径向淡出的柔和暗斑替代原来的方形半透明色块。
##
## 6 个草丛共用 2 份网格 + 1 份材质，总三角面约 3.5 万，对帧率没有可见影响。

const LEAF_SHADER_PATH := "res://shaders/bush_leaf.gdshader"
const FLOOR_SHADER_PATH := "res://shaders/bush_floor.gdshader"

const VARIANTS := 2
## 叶片小而多：草丛看起来像「一丛叶子」，而不是几十片大三角。
const LEAF_COUNT := 1800
## 单位草丛（半径 1）的叶簇分布参数。实际尺寸由摆放时的 scale 决定。
const DOME_RADIUS := 0.82
const DOME_HEIGHT := 0.22
const LEAF_LENGTH_MIN := 0.058
const LEAF_LENGTH_MAX := 0.105
## 叶簇高度的下限（世界单位）。按半径等比缩放时，最小的河边草丛只有 1.0 米高，
## 连英雄的小腿都盖不住；太高又会挡住头顶血条，所以只补到刚好过腰。
const MIN_VISUAL_HEIGHT := 1.6
const LEAF_WIDTH_MIN := 0.030
const LEAF_WIDTH_MAX := 0.050
## 叶簇下方的一团暗色实体：挡住水面 / 地面透光，让草丛读起来有体积。
## 半径比叶簇小一圈，免得在根部露出一圈低多边形的硬边。
const CORE_RADIUS := 0.70
const CORE_HEIGHT := 0.12
## 贴地叶裙的比例：把灌木和地面的交界打散，不然根部像扣了个碗。
const FLOOR_LEAF_SHARE := 0.16
## 地面暗斑比叶簇外沿略大，保证草丛边缘不会出现一圈生硬的断口。
const FLOOR_SCALE := 2.1

static var _meshes: Dictionary = {}
static var _leaf_material: ShaderMaterial = null
static var _floor_material: ShaderMaterial = null

static func leaf_material() -> ShaderMaterial:
	if _leaf_material == null:
		_leaf_material = ShaderMaterial.new()
		_leaf_material.shader = load(LEAF_SHADER_PATH)
		_leaf_material.set_shader_parameter("leaf_dark", Color(0.055, 0.105, 0.035))
		_leaf_material.set_shader_parameter("leaf_light", Color(0.21, 0.35, 0.11))
		_leaf_material.set_shader_parameter("sway_amount", 0.020)
		_leaf_material.set_shader_parameter("sway_speed", 1.25)
	return _leaf_material

static func floor_material() -> ShaderMaterial:
	if _floor_material == null:
		_floor_material = ShaderMaterial.new()
		_floor_material.shader = load(FLOOR_SHADER_PATH)
		_floor_material.set_shader_parameter("floor_color", Color(0.03, 0.07, 0.026))
		_floor_material.set_shader_parameter("opacity", 0.52)
		_floor_material.set_shader_parameter("softness", 0.38)
	return _floor_material

## 两份不同随机种子的网格，避免 6 个草丛看出复制粘贴。
## 网格是单位尺寸（半径约 1、高约 0.4），摆放时用 scale 放大到玩法半径。
static func leaf_mesh(variant: int) -> ArrayMesh:
	var key := variant % VARIANTS
	if _meshes.has(key):
		return _meshes[key]
	var rng := RandomNumberGenerator.new()
	rng.seed = 9031 + key * 7717
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1)
	_add_core(st, rng)
	var clump_phase := rng.randf() * TAU
	for i in LEAF_COUNT:
		_add_leaf(st, rng, clump_phase)
	st.generate_normals()
	var mesh := st.commit()
	_meshes[key] = mesh
	return mesh

## 叶簇内部的暗色穹顶。没有它时，从上方能透过叶片间隙看到水面，
## 草丛读起来是空心的；有了它，缝隙里是深色阴影，才像一丛有厚度的灌木。
static func _add_core(st: SurfaceTool, rng: RandomNumberGenerator) -> void:
	var rings := 5
	var segments := 28
	var wobble := rng.randf() * TAU
	var shade := 0.5
	for ring in rings:
		var t0 := float(ring) / rings
		var t1 := float(ring + 1) / rings
		var y0 := CORE_HEIGHT * t0
		var y1 := CORE_HEIGHT * t1
		var r0 := CORE_RADIUS * sqrt(maxf(0.0, 1.0 - t0 * t0))
		var r1 := CORE_RADIUS * sqrt(maxf(0.0, 1.0 - t1 * t1))
		for seg in segments:
			var a0 := TAU * float(seg) / segments
			var a1 := TAU * float(seg + 1) / segments
			var b0 := 1.0 + sin(a0 * 3.0 + wobble) * 0.06 + sin(a0 * 7.0 - wobble) * 0.03
			var b1 := 1.0 + sin(a1 * 3.0 + wobble) * 0.06 + sin(a1 * 7.0 - wobble) * 0.03
			var p00 := Vector3(cos(a0) * r0 * b0, y0, sin(a0) * r0 * b0)
			var p01 := Vector3(cos(a1) * r0 * b1, y0, sin(a1) * r0 * b1)
			var p10 := Vector3(cos(a0) * r1 * b0, y1, sin(a0) * r1 * b0)
			var p11 := Vector3(cos(a1) * r1 * b1, y1, sin(a1) * r1 * b1)
			var c := Color(shade, shade, shade)
			_tri(st, p00, p10, p11, 0.0, 0.0, 0.0, 0.2, 1.0, 0.2, c)
			_tri(st, p00, p11, p01, 0.0, 0.0, 1.0, 0.2, 1.0, 0.0, c)

## 摆放缩放：横向按玩法半径铺满，纵向保证最低高度。
static func visual_scale(variant: int, radius: float, rng: RandomNumberGenerator) -> Vector3:
	var x := radius * rng.randf_range(0.96, 1.06)
	var z := radius * rng.randf_range(0.96, 1.06)
	var y := radius * rng.randf_range(0.92, 1.02)
	var unit_height := maxf(leaf_mesh(variant).get_aabb().size.y, 0.001)
	y = maxf(y, MIN_VISUAL_HEIGHT / unit_height)
	return Vector3(x, y, z)

static func _add_leaf(st: SurfaceTool, rng: RandomNumberGenerator, clump_phase: float) -> void:
	var radial := sqrt(rng.randf()) * DOME_RADIUS
	var angle := rng.randf() * TAU
	# 低频起伏：几处鼓包/凹陷，让轮廓不是一颗完美的圆馒头。
	var lump := 1.0 + sin(angle * 3.0 + clump_phase) * 0.14 + sin(angle * 5.0 - clump_phase) * 0.07
	var base_y := 0.0
	var yaw := 0.0
	var tilt := 0.0
	if rng.randf() < FLOOR_LEAF_SHARE:
		# 贴地叶裙：一圈低矮、朝外摊开的叶子，把根部轮廓打散。
		radial = rng.randf_range(0.42, DOME_RADIUS)
		base_y = rng.randf_range(0.0, 0.06)
		yaw = angle + rng.randf_range(-0.8, 0.8)
		tilt = rng.randf_range(0.05, 0.30)
	else:
		# 填充扁球体的**体积**而不是只铺球壳：只铺壳时中心会露出一个空洞，
		# 俯视看像花环 / 鸟窝，而不是一丛灌木。
		var t := radial / DOME_RADIUS
		var roof := sqrt(maxf(0.0, 1.0 - t * t)) * DOME_HEIGHT * lump
		base_y = rng.randf_range(0.03, roof + 0.05)
		# 叶面以「朝上」为主：相机是 51° 俯视，纯竖直的叶片只会缩成一条线。
		# yaw 完全随机，避免所有叶片朝外排成放射状花环。
		yaw = rng.randf() * TAU
		tilt = rng.randf_range(0.22, 0.85)

	var base := Vector3(cos(angle) * radial, base_y, sin(angle) * radial)
	var flat := sqrt(maxf(0.0, 1.0 - tilt * tilt))
	var forward := Vector3(cos(yaw) * flat, tilt, sin(yaw) * flat).normalized()
	var side := Vector3(-sin(yaw), 0.0, cos(yaw))
	side = side.normalized().rotated(forward, rng.randf_range(-0.45, 0.45))

	var length := rng.randf_range(LEAF_LENGTH_MIN, LEAF_LENGTH_MAX)
	var width := rng.randf_range(LEAF_WIDTH_MIN, LEAF_WIDTH_MAX)
	_add_leaf_card(st, base, forward, side, length, width, _leaf_color(rng, base_y))

static func _leaf_color(rng: RandomNumberGenerator, base_y: float) -> Color:
	# 越高越亮（受光更多），再叠一点黄绿/青绿色相漂移。
	var height_t := clampf(base_y / maxf(DOME_HEIGHT, 0.001), 0.0, 1.0)
	var shade := lerpf(0.62, 1.0, height_t) * rng.randf_range(0.92, 1.08)
	var hue := rng.randf_range(-0.07, 0.07)
	return Color(
		clampf(shade * (1.0 - hue * 0.55), 0.0, 1.2),
		clampf(shade, 0.0, 1.2),
		clampf(shade * (1.0 + hue * 0.85), 0.0, 1.2)
	)

## 一片叶子 = 3 个三角形（根部 → 中段 → 尖），带轻微上翘的弧度。
## UV.y 从根 0 到尖 1，shader 用它做颜色渐变与风摆权重。
static func _add_leaf_card(
	st: SurfaceTool,
	base: Vector3,
	forward: Vector3,
	side: Vector3,
	length: float,
	width: float,
	color: Color
) -> void:
	var normal := side.cross(forward).normalized()
	var curl := normal * width * 0.22
	var bl := base - side * width * 0.5
	var br := base + side * width * 0.5
	var ml := base + forward * length * 0.46 - side * width * 0.52 + curl
	var mr := base + forward * length * 0.46 + side * width * 0.52 + curl
	var tip := base + forward * length + curl * 1.7
	_tri(st, bl, br, mr, 0.0, 0.0, 0.52, 0.0, 1.0, 0.52, color)
	_tri(st, bl, mr, ml, 0.0, 0.0, 1.0, 0.52, 0.0, 0.52, color)
	_tri(st, ml, mr, tip, 0.0, 0.52, 1.0, 0.52, 0.5, 1.0, color)

static func _tri(
	st: SurfaceTool,
	a: Vector3,
	b: Vector3,
	c: Vector3,
	ua: float,
	va: float,
	ub: float,
	vb: float,
	uc: float,
	vc: float,
	color: Color
) -> void:
	_vert(st, a, Vector2(ua, va), color)
	_vert(st, b, Vector2(ub, vb), color)
	_vert(st, c, Vector2(uc, vc), color)

static func _vert(st: SurfaceTool, vertex: Vector3, uv: Vector2, color: Color) -> void:
	st.set_color(color)
	st.set_uv(uv)
	st.add_vertex(vertex)
