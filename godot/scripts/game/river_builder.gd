extends RefCounted

# 河道水面。C17 拆分第三步：从 arena.gd 抽出水面网格 + 水色 shader，
# 节点名（River）与参数逐位保持原样。
#
# 河床由地形承担（TerrainBuilder 把河道下陷到 -1.45），这里只放水面。
# 以前在河道两侧贴了一条 22m 宽的 cliff 贴图当「岸」，结果是一块棕色地毯
# 压在草地上、把地形坡完全盖住 —— 直接去掉。

const MapData = preload("res://sim/map_data.gd")
const ArenaLook = preload("res://scripts/game/arena_look.gd")

static func build(root: Node3D) -> void:
	var river := MeshInstance3D.new()
	river.name = "River"
	var plane := PlaneMesh.new()
	# 河道长 98 米（两端到 ±49m），在端头河岸下自然收口，不切入边路
	plane.size = Vector2(98.0, 17.4)
	river.mesh = plane
	# 长边要贴着河道中心线（y = x）：局部 +X 经 -45° 旋转后指向 (1,0,1)。
	river.rotation.y = -PI * 0.25
	river.position.y = -0.42
	var shader := Shader.new()
	shader.code = """
shader_type spatial;
render_mode blend_mix, cull_disabled, depth_draw_opaque, specular_schlick_ggx;

uniform vec4 deep_color : source_color = vec4(0.06, 0.22, 0.26, 1.0);
uniform vec4 shallow_color : source_color = vec4(0.20, 0.44, 0.42, 1.0);
uniform float river_half = 9.0;
__OUTSIDE_UNIFORMS__

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	// 到河道中心线的距离决定深浅：河心深蓝、岸边浅青
	float d = abs(wpos.x - wpos.z) * 0.70710678;
	float t = clamp(d / river_half, 0.0, 1.0);

	// 两层不同频率、不同方向的水波，避免规则条纹
	float w1 = sin(wpos.x * 1.15 + TIME * 0.85) * cos(wpos.z * 0.95 - TIME * 0.62);
	float w2 = sin((wpos.x - wpos.z) * 2.1 - TIME * 1.35);
	float w3 = sin(wpos.x * 3.6 - wpos.z * 2.9 + TIME * 1.8);
	float ripple = w1 * 0.55 + w2 * 0.33 + w3 * 0.12;

	vec3 col = mix(deep_color.rgb, shallow_color.rgb, t * 0.72 + ripple * 0.04);

	// 岸边浅滩泡沫：只在水陆交界一条窄带
	float foam = smoothstep(0.93, 1.0, t + ripple * 0.03);
	col = mix(col, vec3(0.74, 0.82, 0.80), foam * 0.4);

	// 墙外那段河跟着地形一起退成远景：地形暗了水面不暗，
	// 会在墙外留一条亮青色的河，比不压暗更扎眼。
__OUTSIDE_APPLY__

	ALBEDO = col;
	// 提高不透明度：河床在阴影里是暗的，透出来会把整条河压成墨绿，
	// 同一个水色在不同角度看深浅差一大截。宁可少一点"见底"，也要颜色稳定。
	ALPHA = mix(0.97, 0.88, t);
	ROUGHNESS = 0.13;
	SPECULAR = 0.42;
	METALLIC = 0.0;
	// 用波纹扰动法线做假高光，GL Compatibility 下没有 SSR，这是最划算的一招
	NORMAL = normalize(vec3(ripple * 0.06, 1.0, ripple * 0.045));
}
"""
	var material := ShaderMaterial.new()
	shader.code = ArenaLook.apply_outside_fade(shader.code)
	material.shader = shader
	material.set_shader_parameter("river_half", MapData.RIVER_HALF_WIDTH)
	# 必须从 GDScript 传 Color：直接写 shader 里的 uniform 默认值会被当成线性色，
	# 输出时再转 sRGB 就整体提亮 —— 深蓝河水会渲染成亮青绿。
	# 原来的 (0.018, 0.095, 0.135) 在斜俯视全景里几乎是一片黑 —— 河道读成了一条深灰柏油路，
	# 和小地图上那条亮青色的河完全对不上。实测渲染像素只有 (20,50,55)，
	# 所以按比例提到 (45~60, 130~150, 140~160) 这一档，和小地图同色系。
	material.set_shader_parameter("deep_color", Color(0.110, 0.400, 0.470))
	material.set_shader_parameter("shallow_color", Color(0.260, 0.600, 0.600))
	# 和地形共用同一份墙外渐隐参数：水面伸到墙外的那一段必须一起退后。
	ArenaLook.bind_outside_fade(material, MapData.BOUNDS)
	river.material_override = material
	river.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(river)
