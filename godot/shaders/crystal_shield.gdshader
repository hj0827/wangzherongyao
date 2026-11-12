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
	return 1.0 - smoothstep(0.024, 0.062, d);
}

void fragment() {
	float rim = pow(1.0 - abs(dot(normalize(NORMAL), normalize(VIEW))), 2.1);
	float grid = cell_lines(UV) * 0.55;
	// 自下而上的扫描带：护盾的能量在流动。
	float scan = smoothstep(0.94, 1.0, sin(UV.y * 17.0 - TIME * 1.9));
	float breathe = 0.88 + 0.12 * sin(TIME * 1.5);

	// 0.46 的边缘上限：旧版 0.62 叠在已经过曝的水晶上，整座基地变成一颗粉白玻璃球。
	float alpha = (0.012 + rim * 0.36 + grid * 0.08 + scan * 0.045) * breathe;
	alpha *= (0.35 + 0.65 * clamp(strength, 0.0, 1.0));
	alpha *= 1.0 + pulse * 0.9;
	// 球底压暗一档：贴地的部分如果也亮，会像一圈发光的围栏。
	alpha *= smoothstep(0.0, 0.16, UV.y);

	vec3 body = mix(shield_color.rgb, edge_color.rgb, clamp(rim + pulse * 0.5, 0.0, 1.0));
	ALBEDO = body;
	ALPHA = clamp(alpha * intensity * shield_color.a, 0.0, 0.55);
}
