shader_type spatial;
// 主晶的能量外壳（2026-11-12 二轮）。
//
// 为什么需要这一层：gem 用的是 StandardMaterial3D + 顶点色切面，平面法线做对了，
// 但它在实拍图里仍然读成「实心蓝塑料」—— 切面只有静态明暗，内部没有东西在动，
// 边缘也没有 fresnel 亮边。王者荣耀的水晶是「能量核」：边缘亮、内部有流光上涌、
// 晶尖有呼吸，远看是一团被封在晶体里的光。
//
// 这里复用 gem 的同一份网格、放大 1.03 再画一遍加法混合的薄壳：
//   - 不新建网格、不新建几何；
//   - 主体 StandardMaterial3D 的淡化 / 残破契约一个字都不用改；
//   - 壳本身是加色薄光，不写深度、不投影，不会挡住走进泉水的英雄。
//
// 三个状态量都由 GDScript 推进，不藏在 TIME 里：
//   phase（累计时间）/ damage（残血撕裂）/ fade_alpha（跟随 OcclusionFade）。
// 这样无头测试能断言「残血真的暗了」「贴近时壳跟着淡了」，静态截图也可复现。
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;

uniform vec4 energy_color : source_color = vec4(0.22, 0.58, 1.0, 1.0);
uniform vec4 hot_color : source_color = vec4(0.80, 0.95, 1.0, 1.0);
// 累计时间（弧度制近似），由 CrystalVisual.apply_state 推。
uniform float phase = 0.0;
uniform float intensity : hint_range(0.0, 2.0) = 1.0;
uniform float damage : hint_range(0.0, 1.0) = 0.0;
uniform float fade_alpha : hint_range(0.0, 1.0) = 1.0;

varying vec3 v_local;
varying float v_rim;

void vertex() {
	v_local = VERTEX;
	vec4 mv = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	vec3 view_dir = normalize(-mv.xyz);
	vec3 view_normal = normalize((MODELVIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	// abs()：薄壳是双面渲染的，背面也要有同样的轮廓光。
	v_rim = pow(1.0 - abs(dot(view_normal, view_dir)), 2.0);
}

void fragment() {
	// gem 网格的本地高度约 -0.36 ~ 4.35；归一到 0..1 再驱动竖向流动。
	float h = clamp((v_local.y + 0.40) / 4.90, 0.0, 1.0);
	float radial = atan(v_local.z, v_local.x);

	// 两股不同速度的能量沿晶面向上涌。频率不成整数倍，避免读出「百叶窗」。
	float wave_a = sin(h * 17.0 - phase * 2.6 + radial * 1.3);
	float wave_b = sin(h * 6.5 - phase * 1.3 - radial * 2.1);
	float veins = pow(max(wave_a * 0.5 + 0.5, 0.0), 7.0) * 0.62
			+ pow(max(wave_b * 0.5 + 0.5, 0.0), 11.0) * 0.38;
	// 切面朝向差异：让每个棱面的流光强度不同，读成内部折射而不是一层均匀贴膜。
	float facet = 0.62 + 0.38 * abs(sin(radial * 3.0 + h * 0.8));
	// 晶尖的缓慢核心脉冲，把视线收回顶端。
	float crown = pow(h, 4.0) * (0.55 + 0.45 * sin(phase * 1.7));
	float breathe = 0.88 + 0.12 * sin(phase * 1.35);
	// 残血按角度撕裂式熄灭（sin² 保证非负），和地面法阵同一套语言。
	float tear = sin(radial * 7.0 + phase * 9.0);
	float flicker = 1.0 - damage * (0.34 + 0.30 * tear * tear);

	float a = (v_rim * 0.40 + veins * facet * 0.20 + crown * 0.10 + 0.012)
			* breathe * flicker * fade_alpha * intensity;
	vec3 col = mix(energy_color.rgb, hot_color.rgb,
			clamp(v_rim * 0.72 + veins * 0.30 + crown * 0.25, 0.0, 1.0));
	ALBEDO = col;
	ALPHA = clamp(a, 0.0, 0.68);
}
