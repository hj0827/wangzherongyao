extends RefCounted
class_name TerrainBuilder

const ArenaLook = preload("res://scripts/game/arena_look.gd")
const MapData = preload("res://sim/map_data.gd")

## 视觉地形。**只影响画面，不参与模拟。**
##
## 模拟层的碰撞 / 寻路 / 视野全部跑在 MapData 的 2D 平面上（BOUNDS = ±58），
## 所以这里的高度必须在可玩区内严格为 0 —— 抬升只允许出现在边界之外。
## 之前的地图是一整块 160×160 的平板，山像纸片一样立在上面、河岸是贴纸，
## 「不真实」的根源就是没有任何高度变化。

const SIZE := 260.0          # 地形边长（米）
const CELLS := 128           # 每边格数 → 2.03m 一格
const RIVER_HALF := 9.0      # 河道半宽，与 MapData.RIVER_HALF_WIDTH 同源
const RIVER_BED := -1.45     # 河床相对高度（水面在 -0.42，水深约 1m）
const RIVER_SLOPE := 4.5     # 河岸过渡宽度
const PLAY_HALF := 60.0      # 抬升起点。必须 > MapData.BOUNDS(58)：
                             # 单位最远能走到 58，地形提前抬升会把人埋进坡里。
const HILL_FULL := 92.0      # 到这里达到完整丘陵高度
const MOUNT_FULL := 134.0    # 再往外进入山体高度

var _hill := FastNoiseLite.new()
var _detail := FastNoiseLite.new()
var _ridge := FastNoiseLite.new()

func _init() -> void:
	_hill.seed = 20261023
	_hill.frequency = 0.011
	_hill.fractal_octaves = 3
	_detail.seed = 4471
	_detail.frequency = 0.055
	_detail.fractal_octaves = 2
	_ridge.seed = 90210
	_ridge.frequency = 0.028
	_ridge.fractal_octaves = 2

## 到河道中心线（x - z = 0，即 y = x）的垂直距离，与 collision.gd 的判定同源。
func river_distance(x: float, z: float) -> float:
	return absf(x - z) * 0.70710678

func height_at(x: float, z: float) -> float:
	var river_d := river_distance(x, z)

	# 河床：河心最深，到岸线附近平滑回到 0，形成真实的河岸坡
	var bed := 1.0 - smoothstep(RIVER_HALF - 2.0, RIVER_HALF + RIVER_SLOPE, river_d)
	var h := RIVER_BED * bed

	# 丘陵：只在可玩区外抬升；边界线用噪声扰动，避免方盒子感
	var edge := maxf(absf(x), absf(z)) + _ridge.get_noise_2d(x, z) * 5.5
	var rise := smoothstep(PLAY_HALF, HILL_FULL, edge)
	if rise > 0.0:
		# 河道走廊内不抬升 —— 山丘被河谷切开，而不是河从山肚子里穿过去
		var corridor := 1.0 - smoothstep(11.0, 27.0, river_d)
		# 基准 9m 起步：4.5m 的丘陵在 100m 视野里几乎看不出来，
		# 地图外围仍然像一块平板。再叠一层低频噪声做山脊，避免馒头状。
		var hill := 11.0 + _hill.get_noise_2d(x, z) * 5.0 + _detail.get_noise_2d(x, z) * 2.0
		var far := smoothstep(HILL_FULL, MOUNT_FULL, edge)
		hill += far * (22.0 + _hill.get_noise_2d(x * 0.7, z * 0.7) * 14.0)
		h += rise * hill * (1.0 - corridor)
	return h

## 建出地形网格。顶点按 1.625m 网格排布，索引共享，约 5.1 万三角形 / 1 个 draw call。
func build_mesh() -> ArrayMesh:
	var step := SIZE / float(CELLS)
	var half := SIZE * 0.5
	var row := CELLS + 1
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for iz in row:
		for ix in row:
			var x := -half + float(ix) * step
			var z := -half + float(iz) * step
			st.set_uv(Vector2(x, z))
			st.add_vertex(Vector3(x, height_at(x, z), z))
	for iz in CELLS:
		for ix in CELLS:
			var a := iz * row + ix
			var b := a + 1
			var c := a + row
			var d := c + 1
			# Godot 默认 CULL_BACK，正面是顺时针（从上方看）。
			# 写成 a→c→b 会是逆时针，整块地形会被当成背面剔掉 —— 画面上只剩天空。
			st.add_index(a)
			st.add_index(b)
			st.add_index(c)
			st.add_index(b)
			st.add_index(d)
			st.add_index(c)
	st.generate_normals()
	st.generate_tangents()
	return st.commit()

## 地表材质：草 / 泥 / 沙 / 岩 按坡度与河岸距离混合，并接上法线贴图。
## 贴图只喂 diffuse 是之前「像塑料板」的直接原因 —— 法线 + 粗糙度让表面真的有凹凸。
static func build_material(mobile_override: Variant = null) -> ShaderMaterial:
	var mobile: bool = OS.has_feature("mobile") if mobile_override == null else bool(mobile_override)
	var shader := Shader.new()
	shader.code = """
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
uniform sampler2D grass_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D grass_nor : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D dirt_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D dirt_nor : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float river_half = 9.0;
// 观感参数全部由 arena_look.gd 注入，shader 里不写死颜色：
// 一处调色，地形 / 阵营色偏 / 去饱和不会各跑各的。
uniform vec3 grass_gain = vec3(0.34, 0.46, 0.31);
uniform vec3 faction_warm = vec3(1.05, 0.99, 0.94);
uniform vec3 faction_cool = vec3(0.94, 0.98, 1.06);
uniform float faction_span = 26.0;
uniform float faction_sat = 0.94;
__OUTSIDE_UNIFORMS__

varying vec3 wpos;
varying vec3 wnorm;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnorm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec2 p = wpos.xz;
	float slope = 1.0 - clamp(wnorm.y, 0.0, 1.0);
	float river_d = abs(wpos.x - wpos.z) * 0.70710678;

	// 采样预算很紧：集显（Intel UHD 730）跑 1600x900 时，
	// 每多一次纹理采样就掉几帧。三层草贴图 + 1 泥土 + 1 岩石 + 1 法线 = 6 次，
	// 低频变化直接复用 g3.r / g2.g，不再单独采样。
	vec3 g1 = texture(grass_tex, p * 0.46).rgb;
	vec3 g3 = __TERRAIN_GRASS_3__;
	vec3 d1 = texture(dirt_tex, p * 0.24).rgb;

	// 两层草贴图（周期 2.2m / 16m）已经足够破掉重复感；
	// 加第三层在集显上换不来肉眼可辨的提升，只换来 7 帧。
	vec3 grass = mix(g1, g3, 0.34) * grass_gain;
	vec3 dirt  = d1 * vec3(0.70, 0.66, 0.54);
	vec3 sand  = d1 * vec3(1.04, 0.96, 0.80);
	vec3 rock  = d1 * vec3(0.62, 0.63, 0.66);

	float bank = smoothstep(river_half + 5.0, river_half - 2.0, river_d);
	float rocky = smoothstep(0.30, 0.62, slope);

	vec3 col = mix(grass, dirt, smoothstep(0.40, 0.62, g3.r) * 0.52 + smoothstep(0.62, 0.88, g1.g) * 0.22);
	col = mix(col, sand, bank * 0.82);
	col = mix(col, rock, rocky);
	col *= 0.90 + g3.r * 0.16;

	// 去饱和在前、阵营染色在后：反过来的话染色会被去饱和拉回中性，色偏就白做了。
	float luma = dot(col, vec3(0.2126, 0.7152, 0.0722));
	col = mix(vec3(luma), col, faction_sat);
	float side = (wpos.x - wpos.z) * 0.70710678;
	float faction = smoothstep(-faction_span, faction_span, side);
	col *= mix(faction_warm, faction_cool, faction);

	// 墙外退成远景。切比雪夫距离 = 方形城墙的口径（与 clamp_bounds 同源），
	// 用欧氏距离会在四角留下一块比四边晚暗的亮斑。
	// 放在阵营染色之后：远景不该还带着半场的暖/冷色偏。
__OUTSIDE_APPLY__

	ALBEDO = col;
	NORMAL_MAP = __TERRAIN_NORMAL__;
	NORMAL_MAP_DEPTH = 1.5;
	ROUGHNESS = 0.85;
	SPECULAR = 0.16;
}
"""
	var material := ShaderMaterial.new()
	# 手机端地表只保留 1 层草 + 1 层泥土，跳过高频草贴图与法线采样：
	# 这两次采样铺满整屏，是移动端移动镜头时最大的 fill-rate 开销。
	shader.code = shader.code.replace(
		"__TERRAIN_GRASS_3__",
		"g1" if mobile else "texture(grass_tex, p * 0.061 + vec2(0.71, 0.23)).rgb"
	)
	shader.code = shader.code.replace(
		"__TERRAIN_NORMAL__",
		"vec3(0.5, 0.5, 1.0)" if mobile else "texture(grass_nor, p * 0.46).rgb"
	)
	shader.code = ArenaLook.apply_outside_fade(shader.code)
	material.shader = shader
	material.set_shader_parameter("grass_tex", load("res://assets/textures/leafy_grass_Diffuse.jpg"))
	material.set_shader_parameter("grass_nor", load("res://assets/textures/leafy_grass_nor_gl.jpg"))
	material.set_shader_parameter("dirt_tex", load("res://assets/textures/grass_path_2_Diffuse.jpg"))
	material.set_shader_parameter("dirt_nor", load("res://assets/textures/grass_path_2_nor_gl.jpg"))
	material.set_shader_parameter("river_half", RIVER_HALF)
	material.set_shader_parameter("grass_gain", ArenaLook.GRASS_GAIN)
	material.set_shader_parameter("faction_warm", ArenaLook.WARM_TINT)
	material.set_shader_parameter("faction_cool", ArenaLook.COOL_TINT)
	material.set_shader_parameter("faction_span", ArenaLook.FACTION_SPAN)
	material.set_shader_parameter("faction_sat", ArenaLook.SATURATION)
	# 墙外远景。边界取 MapData.BOUNDS（= 城墙内表面），不另写一个数：
	# 城墙挪了、可走边界挪了，渐隐起点自动跟着走。
	ArenaLook.bind_outside_fade(material, MapData.BOUNDS)
	return material
