shader_type spatial;
// 基地水晶的双塔护盾。
//
// 旧版是一颗加色球（StandardMaterial3D, alpha 0.14）：
// 俯视下就是一团均匀的蓝雾，既没有「罩住」的边缘，也看不出是一层护盾。
// 这一版只做三件事，但每件都在 21 米机位下可见：
//   ① Fresnel 边缘：球的正中间几乎透明，轮廓才亮 —— 一眼读出「有一层壳」；
//   ② 蜂窝纹：低频网格，近看有材质，远看只是轻微噪点，不会糊成白球；
//   ③ 从下往上扫的扫描线：护盾是「活的」，不是一块静态玻璃。
//
// 不用 blend_add：加色叠在过曝的水晶上会把整个基地烧白。
// blend_mix + 低 alpha 才能在保留水晶本体的同时看到护盾。
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled;

uniform vec4 shield_color : source_color = vec4(0.58, 0.82, 1.0, 1.0);
uniform vec4 edge_color : source_color = vec4(0.88, 0.96, 1.0, 1.0);
uniform float intensity : hint_range(0.0, 2.0) = 1.0;
// 护盾量 0..1：破了会变薄，不要直接消失得毫无过程。
uniform float strength : hint_range(0.0, 1.0) = 1.0;
// 受击脉冲由 GDScript 推（0 = 无），持续 0.2s 左右。
uniform float pulse : hint_range(0.0, 1.0) = 0.0;

// 扁平化的蜂窝近似：交错行 + 每格内取到边界的距离。
// 不追求数学上的正六边形 —— 在球面上没有人能分辨，读出来是「有肌理的壳」就够了。
float cell_lines(vec2 uv) {
	vec2 q = uv * vec2(16.0, 8.0);
	q.x += mod(floor(q.y), 2.0) * 0.5;
	vec2 f = abs(fract(q) - 0.5);
	float d = min(f.x, f.y);
	// 收窄线宽：首版 0.024~0.062 在 21 米机位糊成一层均匀磨砂，读不出六边形。
	return 1.0 - smoothstep(0.018, 0.045, d);
}

void fragment() {
	float rim = pow(1.0 - abs(dot(normalize(NORMAL), normalize(VIEW))), 2.1);
	float grid = cell_lines(UV) * 0.55;
	// 自下而上的扫描带：护盾的能量在流动。
	float scan = smoothstep(0.94, 1.0, sin(UV.y * 17.0 - TIME * 1.9));
	float breathe = 0.88 + 0.12 * sin(TIME * 1.5);

	// 中心几乎全透、轮廓才亮：首版球心 0.012 + 泛白 edge_color，
	// 实拍是一颗灰白磨砂罩，把红方水晶整个洗掉色。
	float alpha = (0.004 + rim * 0.46 + grid * 0.13 + scan * 0.055) * breathe;
	// 顶部能量汇聚环：护盾不是一顶玻璃罩，能量在顶点收口。
	alpha += (1.0 - smoothstep(0.02, 0.13, abs(UV.y - 0.93))) * 0.20;
	alpha *= (0.35 + 0.65 * clamp(strength, 0.0, 1.0));
	alpha *= 1.0 + pulse * 0.9;
	// 球底压暗一档：贴地的部分如果也亮，会像一圈发光的围栏。
	alpha *= smoothstep(0.0, 0.16, UV.y);

	// 边缘只掺 20% 白，阵营色在护盾上仍然读得出来。
	vec3 body = mix(shield_color.rgb, edge_color.rgb, clamp(rim * 0.85 + pulse * 0.5, 0.0, 1.0));
	ALBEDO = body;
	ALPHA = clamp(alpha * intensity * shield_color.a, 0.0, 0.62);
}
