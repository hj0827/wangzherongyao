extends RefCounted
## 战场「观感层」的唯一真身：所有调色 / 大气 / 光照参数都在这里，arena 只负责套上去。
##
## 为什么要抽出来：这些参数散在 _build_environment 里时，没有任何测试能证明
## 「bloom 真的开了」「饱和度真的降下来了」「蓝红半场真的有色差」。
## 抽成纯函数 + 常量后，测试可以直接建一个 Environment 传进来断言。

## 饱和度。> 1.0 会把手绘贴图推成塑料色（2026-10-24 之前是 1.1）。
## 0.96 而不是 0.90：再低草地会变成灰绿色，和「去塑料感」不是一回事。
const SATURATION := 0.96
const CONTRAST := 1.08
const BRIGHTNESS := 1.0

## 环境光压低、主光提亮：让形体真的分出亮面和暗面，而不是一片均匀打亮。
const AMBIENT_ENERGY := 0.52
const SUN_ENERGY := 1.68
const SUN_WARM := Color(1.0, 0.88, 0.72)
## 雾。地形边缘要「被空气隔开」，但 0.0052 在俯瞰机位上已经把整张图糊成一张白纱。
const FOG_DENSITY := 0.0044

## Bloom：技能、水晶、塔的发光必须有溢出，否则「发光」只是「浅色块」。
const GLOW_INTENSITY := 0.85
const GLOW_STRENGTH := 1.05
const GLOW_BLOOM := 0.10
const GLOW_HDR_THRESHOLD := 0.95

## SSAO 只有 Forward+ / Mobile 渲染器支持。本项目跑 GL Compatibility，
## 硬开不会报错也不会有效果 —— 所以这里如实写 false，另用「地形自投影」补接触阴影。
const SSAO_ENABLED := false
const SSAO_INTENSITY := 1.6
const SSAO_RADIUS := 1.4

## 地形自投影：山体/丘陵不投影时，远山看起来是一排贴在边上的道具。
const TERRAIN_SHADOW := GeometryInstance3D.SHADOW_CASTING_SETTING_ON

## 阵营色偏：蓝方半场偏冷、红方偏暖。不是审美问题——玩家靠它判断自己在哪半边。
## 强度刻意压在 ±6% 以内，再高草地就变成蓝/红地毯了。
const WARM_TINT := Vector3(1.05, 0.99, 0.94)
const COOL_TINT := Vector3(0.94, 0.98, 1.06)
## 从河心到「完全染色」的世界距离。26m 大约半个半场，过渡够长，看不出接缝。
const FACTION_SPAN := 26.0

## 草地贴图的乘数。原来的 (0.28, 0.60, 0.25) 是过饱和的根源；
## 但绿色压得太狠会变成灰绿，所以绿通道只降到 0.50。
const GRASS_GAIN := Vector3(0.34, 0.50, 0.32)

# ---------------- 墙外远景 -------------------------------------------------
#
# 边界墙（±58）外面还有 70 米草地 + 丘陵 + 山体，它是「背景」不是「玩法区」。
# 但它铺满了画面上缘和两侧，玩家贴墙时墙外占掉三分之一屏，反而比墙内抢眼。
#
# 做法：从墙内表面往外，在 FADE 米内逐渐压暗、去饱和、混冷灰，
# 让墙外退成远景。**不砍地形、不动相机** —— 贴墙时英雄仍在画面正中，
# 只是墙外的草地不再是画面主体。
#
# 用切比雪夫距离（max(|x|,|z|)）而不是欧氏距离：城墙是方的、clamp_bounds 也是方的，
# 用圆形衰减会让四个角比四条边晚暗一大圈，角上露出一块亮斑。
## 过渡宽度（米）。18 米在 21 米机位上是「墙根往外一屏半」的距离，够慢，看不出接缝。
const OUTSIDE_FADE := 18.0
## 紧贴墙根处的压暗比例。不能从 0 开始渐变：画面里看到的墙外恰恰是墙脚下最近那一圈，
## 从 0 起意味着「离玩家最近、最该退后的那块」是全场最亮的。
const OUTSIDE_BASE := 0.55
## 完全进入远景后的亮度乘数。0.34 让墙外明显退后，但还看得出是草地/山，不是黑洞。
const OUTSIDE_DARKEN := 0.34
## 远景混色。偏冷偏灰：暖色会把墙外的草地拉回前景。
const OUTSIDE_TINT := Vector3(0.20, 0.25, 0.26)
## 远景色占比。0.42 是「去饱和但不发灰」的位置 —— 再高草地会变成水泥地。
const OUTSIDE_TINT_MIX := 0.42

## 墙外渐隐的 GLSL 片段。
##
## 地形（terrain_builder.gd）和水面（arena.gd::_build_river）都要用：
## 地形暗了水面不暗，就会在墙外留一条亮青色的河 —— 比不压暗更扎眼。
## 公式只能有一份，两份写必然有一天改一处漏一处，所以在这里拼接。
##
## 占位符写法：shader 源码里写 __OUTSIDE_UNIFORMS__ / __OUTSIDE_APPLY__，
## 由 `apply_outside_fade()` 替换。uniform 必须落在函数外，apply 必须落在 fragment 内，
## 所以拆成两段而不是一段。
const OUTSIDE_UNIFORMS := """
uniform float play_half = 58.0;
uniform float outside_fade = 18.0;
uniform float outside_base = 0.55;
uniform float outside_darken = 0.34;
uniform vec3 outside_tint = vec3(0.20, 0.25, 0.26);
uniform float outside_tint_mix = 0.42;
"""

const OUTSIDE_APPLY := """
	// 墙外退成远景。切比雪夫距离 = 方形城墙的口径（与 clamp_bounds 同源）；
	// 用欧氏距离会在四角留下一块比四边晚暗的亮斑。
	// at_wall 在墙线两侧 0.6 米内完成跳变 —— 接缝被墙身（厚 1.8m）压住，看不见。
	float edge = max(abs(wpos.x), abs(wpos.z));
	float at_wall = smoothstep(play_half - 0.6, play_half + 0.6, edge);
	float far_away = smoothstep(play_half, play_half + outside_fade, edge);
	float outside = mix(at_wall * outside_base, 1.0, far_away);
	col = mix(col, mix(col * outside_darken, outside_tint, outside_tint_mix), outside);
"""

## 把上面两段塞进 shader 源码。两个 shader 都走这里，公式不会分叉。
static func apply_outside_fade(code: String) -> String:
	return code.replace("__OUTSIDE_UNIFORMS__", OUTSIDE_UNIFORMS).replace("__OUTSIDE_APPLY__", OUTSIDE_APPLY)

## 往材质里灌墙外渐隐的参数。和 apply_outside_fade 配套，别只做一半。
static func bind_outside_fade(material: ShaderMaterial, play_half: float) -> void:
	material.set_shader_parameter("play_half", play_half)
	material.set_shader_parameter("outside_fade", OUTSIDE_FADE)
	material.set_shader_parameter("outside_base", OUTSIDE_BASE)
	material.set_shader_parameter("outside_darken", OUTSIDE_DARKEN)
	material.set_shader_parameter("outside_tint", OUTSIDE_TINT)
	material.set_shader_parameter("outside_tint_mix", OUTSIDE_TINT_MIX)

# ---------------- 石壁（野区墙体 + 边界墙）---------------------------------
#
# 参数单独留在这里而不是写死在 arena 里，原因和上面一样：观感要能被断言。
# 贴图的坑见 shaders/rock_wall.gdshader 顶部注释（BoxMesh 的 0..1 UV 把岩层拉成木纹）。
const ROCK_SHADER_PATH := "res://shaders/rock_wall.gdshader"
const ROCK_ALBEDO_PATH := "res://assets/textures/cliff_side_Diffuse.jpg"
const ROCK_NORMAL_PATH := "res://assets/textures/cliff_side_nor_gl.jpg"
const ROCK_ROUGH_PATH := "res://assets/textures/cliff_side_Rough.jpg"
const ROCK_AO_PATH := "res://assets/textures/cliff_side_AO.jpg"

## 一格贴图铺多少米。3.4 米 = 一块「岩壁块面」，站在 21 米机位上看是一层石壁，
## 而不是一整片被拉长的纹理。
const WALL_TILE_METRES := 3.4
## 赭黄砂岩的色相是「木头感」的直接来源，拉到中性灰再补亮度。
const WALL_DESATURATE := 0.84
const WALL_GAIN := 1.74
## 偏冷的灰：蓝分量略高于红，压掉砂岩的暖调。
const WALL_ROCK_TINT := Color(0.58, 0.61, 0.63)
## 顶面草。俯视机位下顶面最常被看见，没有这道绿，墙就只是一块石头墩子。
## 但**不能盖满**：0.8 那版顶面是一整块绿毯子，石头一点不露，比平顶更假。
## 0.45 配合 shader 里的斑块遮罩，才是「石头上长了几片草」。
const WALL_MOSS_AMOUNT := 0.45
const WALL_MOSS_COLOR := Color(0.21, 0.31, 0.16)
## 脊顶压暗。朝上的面受光最足，不压的话一条十几米长的亮头顶边
## 读起来是「墙顶铺好了一条走道」，而不是长着土和草的山脊。
const WALL_CREST_DARKEN := 0.70
## 砌石砖缝。这组数决定「一堵墙」还是「一根灰色原木」：
## 层高 0.52 米 ≈ 一层条石，砖长 1.15 米 ≈ 一块条石两倍高，正好是城墙的比例。
## 缝宽 0.035 米在 20 米机位下大约半个像素到一像素 —— 再宽就成格子布了。
const WALL_BRICK_COURSE := 0.52
const WALL_BRICK_LENGTH := 1.15
const WALL_MORTAR_WIDTH := 0.028
const WALL_MORTAR_DARKEN := 0.74
const WALL_BRICK_TINT := 0.07

## 石壁材质。全图（野区墙体 + 边界墙）共用一份实例，避免一处石头一处木板，
## 也省掉几十个 material 的重复编译。
static func rock_wall_material() -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = load(ROCK_SHADER_PATH)
	material.set_shader_parameter("albedo_tex", load(ROCK_ALBEDO_PATH))
	material.set_shader_parameter("normal_tex", load(ROCK_NORMAL_PATH))
	material.set_shader_parameter("roughness_tex", load(ROCK_ROUGH_PATH))
	material.set_shader_parameter("ao_tex", load(ROCK_AO_PATH))
	material.set_shader_parameter("tile_size", WALL_TILE_METRES)
	material.set_shader_parameter("desaturate", WALL_DESATURATE)
	material.set_shader_parameter("rock_gain", WALL_GAIN)
	material.set_shader_parameter("rock_tint", WALL_ROCK_TINT)
	material.set_shader_parameter("moss_amount", WALL_MOSS_AMOUNT)
	material.set_shader_parameter("moss_color", WALL_MOSS_COLOR)
	material.set_shader_parameter("crest_darken", WALL_CREST_DARKEN)
	material.set_shader_parameter("brick_course", WALL_BRICK_COURSE)
	material.set_shader_parameter("brick_length", WALL_BRICK_LENGTH)
	material.set_shader_parameter("mortar_width", WALL_MORTAR_WIDTH)
	material.set_shader_parameter("mortar_darken", WALL_MORTAR_DARKEN)
	material.set_shader_parameter("brick_tint", WALL_BRICK_TINT)
	return material

static func apply_environment(environment: Environment) -> void:
	environment.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color(0.09, 0.17, 0.3)
	sky_material.sky_horizon_color = Color(0.62, 0.68, 0.7)
	sky_material.sky_curve = 0.18
	sky_material.ground_bottom_color = Color(0.08, 0.1, 0.09)
	sky_material.ground_horizon_color = Color(0.5, 0.52, 0.48)
	sky_material.sun_angle_max = 22.0
	sky_material.sun_curve = 0.12
	sky.sky_material = sky_material
	environment.sky = sky

	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	environment.ambient_light_energy = AMBIENT_ENERGY
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.tonemap_exposure = 1.05

	environment.fog_enabled = true
	# 雾调浓一点：外围丘陵和山需要「被空气隔开」的层次，
	# 太清透会让远山像贴在地图边上的一排道具。
	environment.fog_light_color = Color(0.46, 0.56, 0.66)
	environment.fog_light_energy = 0.72
	environment.fog_density = FOG_DENSITY
	environment.fog_sky_affect = 0.22
	environment.fog_aerial_perspective = 0.45

	environment.glow_enabled = true
	environment.glow_intensity = GLOW_INTENSITY
	environment.glow_strength = GLOW_STRENGTH
	environment.glow_bloom = GLOW_BLOOM
	environment.glow_hdr_threshold = GLOW_HDR_THRESHOLD
	environment.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE

	environment.ssao_enabled = SSAO_ENABLED
	environment.ssao_intensity = SSAO_INTENSITY
	environment.ssao_radius = SSAO_RADIUS

	environment.adjustment_enabled = true
	environment.adjustment_contrast = CONTRAST
	environment.adjustment_saturation = SATURATION
	environment.adjustment_brightness = BRIGHTNESS

static func apply_sun(sun: DirectionalLight3D) -> void:
	sun.rotation_degrees = Vector3(-48.0, -38.0, 0.0)
	sun.light_color = SUN_WARM
	sun.light_energy = SUN_ENERGY
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	# 手机端把阴影范围从 48 收到 36 米：镜头附近的石壁/塔仍有影子，
	# 远处阴影本来就被雾和墙外渐隐盖住，却要占满 shadow map 的采样预算。
	sun.directional_shadow_max_distance = 36.0 if OS.has_feature("mobile") else 48.0
	sun.shadow_bias = 0.035
	sun.shadow_normal_bias = 1.2

## 蓝方半场返回偏冷的乘数，红方半场返回偏暖的，河心返回接近 1 的中性色。
## 参数是世界坐标（地形 shader 里同样是 (x - z) 这条轴，别改成 x + z）。
static func faction_tint(x: float, z: float) -> Color:
	var side := (x - z) * 0.70710678
	var t := smoothstep(-FACTION_SPAN, FACTION_SPAN, side)
	var mixed := WARM_TINT.lerp(COOL_TINT, t)
	return Color(mixed.x, mixed.y, mixed.z)
