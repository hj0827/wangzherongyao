extends RefCounted
class_name GrassField

## 地表草簇。**只影响画面，不参与模拟。**
##
## 为什么需要它：地形只有贴图时，近距离就是一张糊掉的绿色地毯 ——
## 相机 zoom 到 21 时地面占满屏幕，任何纹理细节都会被放大成色斑。
## 真实感靠的是「有高度的东西」：草叶、碎石。这里用 MultiMesh 一次画几千簇，
## 成本是一个 draw call + 每簇 6 个三角形。

const BLADES_PER_TUFT := 4
const TUFT_HEIGHT := 0.26

const MapData = preload("res://sim/map_data.gd")

## 草簇网格：3 片交叉的草叶，每片 2 个三角形。
## UV.y 携带「沿叶片的相对高度」（0 = 根部，1 = 叶尖），
## 着色器用它做根深尖浅的渐变和随风摆动 —— 根部必须不动，否则整片草会整体平移。
static func build_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for b in BLADES_PER_TUFT:
		var angle := TAU * float(b) / float(BLADES_PER_TUFT) + 0.4
		var dir := Vector3(cos(angle), 0.0, sin(angle))
		var side := Vector3(-dir.z, 0.0, dir.x)
		var half_w := 0.058
		var h := TUFT_HEIGHT
		# 叶片略微外倾，避免所有草都笔直戳在地上
		var lean := dir * 0.07
		var base_l := side * -half_w
		var base_r := side * half_w
		var mid_l := side * -half_w * 0.55 + Vector3(0.0, h * 0.55, 0.0) + lean * 0.45
		var mid_r := side * half_w * 0.55 + Vector3(0.0, h * 0.55, 0.0) + lean * 0.45
		var tip := Vector3(0.0, h, 0.0) + lean
		_add_quad(st, base_l, base_r, mid_r, mid_l, 0.0, 0.55)
		_add_quad(st, mid_l, mid_r, tip, tip, 0.55, 1.0)
	st.generate_normals()
	return st.commit()

static func _add_quad(st: SurfaceTool, bl: Vector3, br: Vector3, tr: Vector3, tl: Vector3, v0: float, v1: float) -> void:
	# 正面（顺时针）
	st.set_uv(Vector2(0.0, v0))
	st.add_vertex(bl)
	st.set_uv(Vector2(1.0, v0))
	st.add_vertex(br)
	st.set_uv(Vector2(1.0, v1))
	st.add_vertex(tr)
	st.set_uv(Vector2(0.0, v0))
	st.add_vertex(bl)
	st.set_uv(Vector2(1.0, v1))
	st.add_vertex(tr)
	st.set_uv(Vector2(0.0, v1))
	st.add_vertex(tl)

static func build_material() -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = """
shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;

uniform vec4 base_color : source_color = vec4(0.10, 0.22, 0.07, 1.0);
uniform vec4 tip_color : source_color = vec4(0.40, 0.62, 0.22, 1.0);

void vertex() {
	// UV.y 是沿叶片的高度权重。用平方让它只在叶尖附近摆，
	// 根部固定在地上 —— 线性权重会让整簇草左右平移，看起来像贴纸在滑动。
	float weight = UV.y * UV.y;
	float phase = VERTEX.x * 2.3 + VERTEX.z * 1.7;
	float sway = sin(TIME * 1.35 + phase) * 0.5 + sin(TIME * 2.1 + phase * 1.7) * 0.5;
	VERTEX.x += sway * 0.055 * weight;
	VERTEX.z += sway * 0.042 * weight;
}

void fragment() {
	ALBEDO = mix(base_color.rgb, tip_color.rgb, UV.y);
	ROUGHNESS = 0.95;
	SPECULAR = 0.08;
	// 双面渲染：背面用同一套光照，避免草叶背光面变成死黑
	BACKLIGHT = ALBEDO * 0.35;
}
"""
	var material := ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("base_color", Color(0.07, 0.16, 0.05))
	material.set_shader_parameter("tip_color", Color(0.21, 0.37, 0.12))
	return material

## 散布草簇。accept 是一个 Callable(Vector2) -> bool，由调用方决定哪里能长草
## （路面、河道、建筑基座要排除）。height_at 取地形高度，让草贴着坡面。
static func scatter(count: int, accept: Callable, height_at: Callable, rng: RandomNumberGenerator) -> MultiMeshInstance3D:
	var mesh := build_mesh()
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = mesh
	multimesh.instance_count = count

	var placed := 0
	var attempts := 0
	while placed < count and attempts < count * 4:
		attempts += 1
		var x := rng.randf_range(-MapData.BOUNDS, MapData.BOUNDS)
		var z := rng.randf_range(-MapData.BOUNDS, MapData.BOUNDS)
		var point := Vector2(x, z)
		if not accept.call(point):
			continue
		var scale := rng.randf_range(0.72, 1.45)
		var basis := Basis(Vector3.UP, rng.randf_range(0.0, TAU)).scaled(Vector3(scale, scale * rng.randf_range(0.85, 1.25), scale))
		var origin := Vector3(x, float(height_at.call(x, z)) - 0.02, z)
		multimesh.set_instance_transform(placed, Transform3D(basis, origin))
		placed += 1
	# 没铺满就裁掉多余实例，避免 count 个实例全堆在原点
	if placed < count:
		multimesh.instance_count = placed
		multimesh.visible_instance_count = placed

	var node := MultiMeshInstance3D.new()
	node.name = "GrassTufts"
	node.multimesh = multimesh
	node.material_override = build_material()
	# 几千簇草不投影：阴影 pass 的开销远大于收益，而且草影会很脏
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return node
