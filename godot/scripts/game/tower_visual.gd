extends RefCounted
class_name TowerVisual

# 防御塔的 3D 模型（纯程序化）。
#
# 参考图：王者荣耀的塔 —— 米黄石雕、外扩的花瓣裙摆、竖棱收分的塔柱、
# 笼状塔冠里一颗发光核心，塔脚一圈暖色光池。
# 旧实现是直接 load 一个贴图瞭望塔 glb，和程序化地形不是一套材质，
# 而且塔身粗、形状平。这里用 SurfaceTool 拼出石构件：
#   1. 石料全部走**一个**网格 + 顶点色 —— 一座塔只占一个不透明 draw call；
#   2. 光效（核心 / 光池 / 花瓣）单独拆出来，方便每帧只改颜色，不重建网格；
#   3. 光池和花瓣不放进 model，避免撑大 AABB 破坏「细高不挡英雄」的契约。

const CORE_HEIGHT := 8.2
const TOP_HEIGHT := 8.95
const GROUND_GLOW_Y := 0.07

const BASE_RADIUS := 1.34
const SHAFT_BOTTOM_RADIUS := 0.86
const SHAFT_TOP_RADIUS := 0.49
const SHAFT_TOP_Y := 6.52

const PETAL_COUNT := 8
const FLOATING_PETAL_COUNT := 6

const STONE_LIGHT := Color(0.74, 0.65, 0.50)
const STONE_MID := Color(0.57, 0.48, 0.35)
const STONE_SHADOW := Color(0.32, 0.26, 0.19)
const TRIM := Color(0.66, 0.48, 0.22)

const GLOW_SHADER := preload("res://shaders/tower_glow.gdshader")

static func build(team_color: Color) -> Dictionary:
	var node := Node3D.new()
	node.name = "TowerStone"

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_add_plinth(st)
	_add_shaft(st)
	_add_shaft_bands(st)
	_add_skirt(st)
	_add_collar(st)
	_add_crown(st)
	var stone := MeshInstance3D.new()
	stone.name = "Stone"
	stone.mesh = st.commit()
	var stone_mat := StandardMaterial3D.new()
	stone_mat.vertex_color_use_as_albedo = true
	stone_mat.albedo_color = Color.WHITE
	stone_mat.roughness = 0.86
	stone_mat.metallic_specular = 0.3
	# 花瓣和塔冠是单面片，双面渲染才不会有「半片花瓣消失」。
	stone_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	stone.material_override = stone_mat
	node.add_child(stone)

	var core := _make_core(team_color)
	node.add_child(core)
	var halo := _make_halo(team_color)
	node.add_child(halo)

	var glow := _make_ground_glow(team_color)
	var petals := _make_floating_petals()

	return {
		"node": node,
		"core": core,
		"halo": halo,
		"glow": glow,
		"petals": petals,
		"height": TOP_HEIGHT,
		"base_width": BASE_RADIUS * 2.0,
		"stone_material": stone_mat,
	}

# ---------- 石构件 ----------

static func _add_plinth(st: SurfaceTool) -> void:
	# 两阶梯石台：底层外扩，上层收回来承托裙摆。
	var profile := [
		Vector2(0.0, 0.0), Vector2(1.34, 0.0), Vector2(1.38, 0.09),
		Vector2(1.24, 0.26), Vector2(1.06, 0.34), Vector2(1.06, 0.46),
		Vector2(0.0, 0.46),
	]
	var colors := [STONE_SHADOW, STONE_SHADOW, STONE_MID, STONE_LIGHT, STONE_LIGHT, STONE_MID, STONE_MID]
	_revolve(st, profile, colors, 28)

static func _add_shaft(st: SurfaceTool) -> void:
	# 向上收分的塔柱 + 12 道竖棱。棱槽用顶点色压暗，读成凿出来的石槽。
	var rings := 10
	var profile: Array = []
	var colors: Array = []
	for i in rings + 1:
		var t := float(i) / float(rings)
		var y := lerpf(0.42, SHAFT_TOP_Y, t)
		var radius := _shaft_radius(t)
		profile.append(Vector2(radius, y))
		var shade := 0.10 + 0.34 * smoothstep(0.0, 1.0, absf(t - 0.42) * 1.6)
		colors.append(STONE_LIGHT.lerp(STONE_MID, shade))
	# 12 道棱至少每道 3 个分段，否则棱槽会被顶点插值抹平。
	_revolve(st, profile, colors, 36, 12, 0.045)

static func _shaft_radius(t: float) -> float:
	return lerpf(SHAFT_BOTTOM_RADIUS, SHAFT_TOP_RADIUS, pow(clampf(t, 0.0, 1.0), 0.62))

static func _add_shaft_bands(st: SurfaceTool) -> void:
	# 三道石箍把长柱分段，读起来像砌起来的石构件，而不是一根白柱子。
	for entry in [[2.35, 0.055], [4.05, 0.05], [5.45, 0.045]]:
		var y := float(entry[0])
		var t := (y - 0.42) / (SHAFT_TOP_Y - 0.42)
		var radius := _shaft_radius(t) + float(entry[1])
		var profile := [
			Vector2(0.0, y - 0.11), Vector2(radius + 0.06, y - 0.05),
			Vector2(radius + 0.06, y + 0.05), Vector2(radius - 0.02, y + 0.10),
			Vector2(0.0, y + 0.10),
		]
		var colors := [STONE_SHADOW, STONE_MID, STONE_LIGHT, STONE_MID, STONE_SHADOW]
		_revolve(st, profile, colors, 24)

static func _add_skirt(st: SurfaceTool) -> void:
	# 两层花瓣裙摆：外层大瓣从石台铺到塔柱，内层小瓣错半个角度补缝。
	# 相邻花瓣换一个明度，边界才看得出是「一片一片」而不是一根喇叭口。
	for i in PETAL_COUNT:
		var tone := STONE_LIGHT if i % 2 == 0 else STONE_LIGHT.lerp(STONE_MID, 0.45)
		_add_petal(st, TAU * float(i) / PETAL_COUNT, 1.30, 0.72, 2.30, 0.42, tone, STONE_SHADOW)
	for i in PETAL_COUNT:
		_add_petal(st, TAU * (float(i) + 0.5) / PETAL_COUNT, 1.04, 0.64, 1.68, 0.30, STONE_MID.lerp(STONE_SHADOW, 0.25), STONE_SHADOW)

static func _add_petal(st: SurfaceTool, angle: float, base_r: float, tip_r: float, top_y: float, span: float, light: Color, dark: Color) -> void:
	var cols := 3
	var rows := 4
	var grid: Array = []
	var color_grid: Array = []
	for row in rows + 1:
		var v := float(row) / float(rows)
		var half_width := span * sin(PI * clampf(0.22 + 0.78 * v, 0.0, 1.0))
		var center_r := _petal_radius(base_r, tip_r, v)
		var y := 0.10 + (top_y - 0.10) * pow(v, 0.92)
		var row_points: Array = []
		var row_colors: Array = []
		for col in cols + 1:
			var u := float(col) / float(cols)
			var a := angle + (u - 0.5) * 2.0 * half_width
			# 边缘略向内收：单面片也能读出一片有厚度的花瓣。
			var r := center_r - 0.05 * (1.0 - pow(2.0 * u - 1.0, 2.0)) * (1.0 - v)
			row_points.append(Vector3(cos(a) * r, y + 0.035 * sin(u * PI) * (1.0 - v), sin(a) * r))
			var edge := absf(u - 0.5) * 2.0
			row_colors.append(light.lerp(dark, 0.18 + 0.62 * edge + 0.24 * (1.0 - v)))
		grid.append(row_points)
		color_grid.append(row_colors)
	for row in rows:
		for col in cols:
			var p0: Vector3 = grid[row][col]
			var p1: Vector3 = grid[row][col + 1]
			var p2: Vector3 = grid[row + 1][col + 1]
			var p3: Vector3 = grid[row + 1][col]
			var mid := (p0 + p1 + p2 + p3) * 0.25
			_quad(
				st, p0, p1, p2, p3,
				color_grid[row][col], color_grid[row][col + 1],
				color_grid[row + 1][col + 1], color_grid[row + 1][col],
				Vector3(mid.x, 0.35, mid.z)
			)

static func _petal_radius(base_r: float, tip_r: float, v: float) -> float:
	return lerpf(base_r, tip_r, pow(v, 0.7)) - 0.10 * sin(v * PI)

static func _add_collar(st: SurfaceTool) -> void:
	# 塔柱顶部的束腰 + 一圈金箍，再向外翻成承托塔冠的托盘。
	var profile := [
		Vector2(0.0, 6.34), Vector2(0.48, 6.34), Vector2(0.56, 6.40),
		Vector2(0.56, 6.50), Vector2(0.46, 6.56), Vector2(0.72, 6.64),
		Vector2(0.90, 6.74), Vector2(0.66, 6.88), Vector2(0.50, 6.96),
		Vector2(0.0, 6.96),
	]
	var colors := [
		STONE_MID, STONE_MID, TRIM, TRIM, TRIM,
		STONE_LIGHT, STONE_LIGHT, STONE_MID, STONE_MID, STONE_MID,
	]
	_revolve(st, profile, colors, 28)

static func _add_crown(st: SurfaceTool) -> void:
	# 笼状塔冠：6 根向外鼓起的石肋，在核心上方收拢，盖一个石顶。
	for i in 6:
		var a := TAU * float(i) / 6.0
		var points: Array = []
		for k in 7:
			var t := float(k) / 6.0
			var r := _bezier(0.50, 1.12, 0.32, t)
			var y := _bezier(6.94, 7.96, 8.60, t)
			points.append(Vector3(cos(a) * r, y, sin(a) * r))
		_add_tube(st, points, 0.105, 0.065, STONE_LIGHT, STONE_MID, 5)
	# 灯笼腰箍：夹在核心上下，读成「核心被石架托住」。
	var rim := [
		Vector2(0.0, 8.24), Vector2(0.58, 8.24), Vector2(0.62, 8.30),
		Vector2(0.62, 8.40), Vector2(0.56, 8.44), Vector2(0.0, 8.44),
	]
	_revolve(st, rim, [STONE_MID, TRIM, TRIM, TRIM, STONE_MID, STONE_MID], 20)
	var dome := [
		Vector2(0.0, 8.56), Vector2(0.38, 8.56), Vector2(0.40, 8.64),
		Vector2(0.24, 8.82), Vector2(0.0, TOP_HEIGHT),
	]
	_revolve(st, dome, [TRIM, TRIM, STONE_LIGHT, STONE_LIGHT, STONE_LIGHT], 20)

# ---------- 光效 ----------

static func _make_core(team_color: Color) -> MeshInstance3D:
	var core := MeshInstance3D.new()
	core.name = "Core"
	var sphere := SphereMesh.new()
	sphere.radius = 0.32
	sphere.height = 0.64
	sphere.radial_segments = 16
	sphere.rings = 8
	core.mesh = sphere
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = team_color
	mat.emission_enabled = true
	mat.emission = team_color
	mat.emission_energy_multiplier = 4.2
	core.material_override = mat
	core.position.y = CORE_HEIGHT
	core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return core

static func _make_halo(team_color: Color) -> MeshInstance3D:
	var halo := MeshInstance3D.new()
	halo.name = "CoreHalo"
	var sphere := SphereMesh.new()
	sphere.radius = 0.62
	sphere.height = 1.24
	sphere.radial_segments = 16
	sphere.rings = 8
	halo.mesh = sphere
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.albedo_color = Color(team_color.r, team_color.g, team_color.b, 0.20)
	mat.emission_enabled = true
	mat.emission = team_color
	mat.emission_energy_multiplier = 1.3
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	halo.material_override = mat
	halo.position.y = CORE_HEIGHT
	halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return halo

static func _make_ground_glow(team_color: Color) -> MeshInstance3D:
	var glow := MeshInstance3D.new()
	glow.name = "GroundGlow"
	var plane := PlaneMesh.new()
	plane.size = Vector2(6.4, 6.4)
	glow.mesh = plane
	glow.position.y = GROUND_GLOW_Y
	var mat := ShaderMaterial.new()
	mat.shader = GLOW_SHADER
	mat.set_shader_parameter("glow_color", Color(team_color.r, team_color.g, team_color.b, 0.85))
	# 亮环落在石台外沿（1.38m / 3.2m 半宽）。
	mat.set_shader_parameter("ring_radius", 0.43)
	glow.material_override = mat
	glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return glow

static func _make_floating_petals() -> Node3D:
	var group := Node3D.new()
	group.name = "FloatingPetals"
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in FLOATING_PETAL_COUNT:
		var a := TAU * float(i) / FLOATING_PETAL_COUNT + 0.35
		var radius := 1.28 + 0.18 * sin(float(i) * 2.1)
		var y := 6.65 + 0.30 * float(i)
		var center := Vector3(cos(a) * radius, y, sin(a) * radius)
		var tangent := Vector3(-sin(a), 0.0, cos(a))
		var radial := Vector3(cos(a), 0.0, sin(a))
		var half_w := 0.13
		var half_h := 0.19
		var curl := 0.06
		var p0 := center - tangent * half_w - Vector3.UP * half_h
		var p1 := center + tangent * half_w - Vector3.UP * half_h
		var p2 := center + tangent * half_w + Vector3.UP * half_h + radial * curl
		var p3 := center - tangent * half_w + Vector3.UP * half_h + radial * curl
		var tint := Color(1.0, 0.80, 0.88, 0.95) if i % 2 == 0 else Color(1.0, 0.80, 0.44, 0.95)
		_quad(st, p0, p1, p2, p3, tint, tint, tint, tint, radial)
	var mesh := MeshInstance3D.new()
	mesh.name = "PetalMesh"
	mesh.mesh = st.commit()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.albedo_color = Color.WHITE
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh.material_override = mat
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	group.add_child(mesh)
	return group

# ---------- 网格工具 ----------

# 旋转体：profile 是 (半径, 高度) 序列，法线取该段轮廓的二维外法线。
# flutes > 0 时在半径上叠一圈余弦棱，顶点色同步压暗棱槽。
static func _revolve(st: SurfaceTool, profile: Array, colors: Array, segments: int, flutes := 0, flute_depth := 0.0) -> void:
	for i in profile.size() - 1:
		var lo: Vector2 = profile[i]
		var hi: Vector2 = profile[i + 1]
		var dr := hi.x - lo.x
		var dy := hi.y - lo.y
		var n2 := Vector2(dy, -dr)
		if n2.length_squared() < 0.000001:
			continue
		n2 = n2.normalized()
		var c_lo: Color = colors[i]
		var c_hi: Color = colors[i + 1]
		for s in segments:
			var a0 := TAU * float(s) / float(segments)
			var a1 := TAU * float(s + 1) / float(segments)
			var r0 := lo.x
			var r1 := lo.x
			var r2 := hi.x
			var r3 := hi.x
			if flutes > 0:
				r0 *= 1.0 + cos(float(flutes) * a0) * flute_depth
				r1 *= 1.0 + cos(float(flutes) * a1) * flute_depth
				r2 *= 1.0 + cos(float(flutes) * a1) * flute_depth
				r3 *= 1.0 + cos(float(flutes) * a0) * flute_depth
			var p0 := Vector3(cos(a0) * r0, lo.y, sin(a0) * r0)
			var p1 := Vector3(cos(a1) * r1, lo.y, sin(a1) * r1)
			var p2 := Vector3(cos(a1) * r2, hi.y, sin(a1) * r2)
			var p3 := Vector3(cos(a0) * r3, hi.y, sin(a0) * r3)
			var mid_a := (a0 + a1) * 0.5
			var hint := Vector3(cos(mid_a) * n2.x, n2.y, sin(mid_a) * n2.x)
			_quad(
				st, p0, p1, p2, p3,
				_groove(c_lo, a0, flutes), _groove(c_lo, a1, flutes),
				_groove(c_hi, a1, flutes), _groove(c_hi, a0, flutes),
				hint
			)

static func _groove(base: Color, angle: float, flutes: int) -> Color:
	if flutes <= 0:
		return base
	return base.lerp(STONE_SHADOW, 0.34 * clampf(-cos(float(flutes) * angle), 0.0, 1.0))

static func _add_tube(st: SurfaceTool, points: Array, radius_start: float, radius_end: float, color_start: Color, color_end: Color, sides: int) -> void:
	var rings: Array = []
	for i in points.size():
		var p: Vector3 = points[i]
		var prev: Vector3 = points[maxi(i - 1, 0)]
		var next: Vector3 = points[mini(i + 1, points.size() - 1)]
		var tangent := (next - prev).normalized()
		var radial := Vector3(p.x, 0.0, p.z)
		radial = radial.normalized() if radial.length() > 0.0001 else Vector3.RIGHT
		var side := tangent.cross(radial).normalized()
		if side.length_squared() < 0.000001:
			side = Vector3.RIGHT
		var up := side.cross(tangent).normalized()
		var t := float(i) / float(maxi(points.size() - 1, 1))
		var radius := lerpf(radius_start, radius_end, t)
		var ring: Array = []
		for s in sides:
			var a := TAU * float(s) / float(sides)
			ring.append(p + side * cos(a) * radius + up * sin(a) * radius)
		rings.append(ring)
	for i in points.size() - 1:
		var center_a: Vector3 = (points[i] + points[i + 1]) * 0.5
		var t := float(i) / float(maxi(points.size() - 2, 1))
		var c0 := color_start.lerp(color_end, t)
		var c1 := color_start.lerp(color_end, minf(t + 0.2, 1.0))
		for s in sides:
			var s2 := (s + 1) % sides
			var p0: Vector3 = rings[i][s]
			var p1: Vector3 = rings[i][s2]
			var p2: Vector3 = rings[i + 1][s2]
			var p3: Vector3 = rings[i + 1][s]
			var mid := (p0 + p1 + p2 + p3) * 0.25
			_quad(st, p0, p1, p2, p3, c0, c0, c1, c1, mid - center_a)

static func _quad(st: SurfaceTool, p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, c0: Color, c1: Color, c2: Color, c3: Color, hint: Vector3) -> void:
	var normal := (p1 - p0).cross(p2 - p0)
	if normal.length_squared() < 0.0000000001:
		normal = (p2 - p0).cross(p3 - p0)
	if normal.length_squared() < 0.0000000001:
		return
	normal = normal.normalized()
	if normal.dot(hint) < 0.0:
		normal = -normal
	_put(st, p0, normal, c0)
	_put(st, p1, normal, c1)
	_put(st, p2, normal, c2)
	_put(st, p0, normal, c0)
	_put(st, p2, normal, c2)
	_put(st, p3, normal, c3)

static func _put(st: SurfaceTool, vertex: Vector3, normal: Vector3, color: Color) -> void:
	st.set_normal(normal)
	st.set_color(color)
	st.add_vertex(vertex)

static func _bezier(a: float, b: float, c: float, t: float) -> float:
	var u := 1.0 - t
	return u * u * a + 2.0 * u * t * b + t * t * c
