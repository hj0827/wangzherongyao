shader_type spatial;
// 基地广场的贴地法阵（水晶脚下的「泉水晶盘」）。
//
// 旧版直接复用营地符阵 camp_sigil：两条环 + 六根刻线。
// 它挂在水晶脚下时太单薄 —— 那是一个营地的标记，不是一座基地的底座。
//
// 这一版是三层语言叠出来的：
//   ① 外圈：双环 + 48 根密齿 + 三道差速旋转弧（读成「一台还在运转的装置」）；
//   ② 内阵：12 根长刻线 + 6 道辐条 + 六芒星（读成「这是主堡，不是野点」）；
//   ③ 阵心：光池 + 护盾状态环（有护盾时多一道亮环，破盾后消失）。
//
// 所有动画量都能被 GDScript 覆盖（spin / active / damage / shield），
// 不把状态藏在 TIME 里 —— 否则无头测试无法断言「破盾后阵纹真的暗了」。
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;

uniform vec4 sigil_color : source_color = vec4(0.32, 0.64, 1.0, 0.78);
uniform vec4 hot_color : source_color = vec4(0.78, 0.94, 1.0, 1.0);
// 累计自转弧度（由 GDScript 推进），不是角速度。
uniform float spin = 0.0;
// 差速旋转的角速度；测试按这个键名读，别改名。
uniform float spin_speed = 0.35;
uniform float active : hint_range(0.0, 1.0) = 1.0;
uniform float intensity : hint_range(0.0, 2.0) = 1.0;
// 残血 0..1：阵纹抖动、局部熄灭，读成「供能不稳」。
uniform float damage : hint_range(0.0, 1.0) = 0.0;
// 有护盾 0..1：多一道外环，颜色偏白。
uniform float shield : hint_range(0.0, 1.0) = 0.0;
uniform float band_gain : hint_range(0.0, 1.0) = 0.62;

float band(float r, float target, float width) {
	return 1.0 - smoothstep(width, width * 2.0, abs(r - target));
}

float teeth(float angle, float r, float inner, float outer, float count, float rot, float duty) {
	float gated = step(inner, r) * step(r, outer);
	float a = fract((angle + rot) / TAU * count);
	return gated * smoothstep(0.0, 0.055, a) * (1.0 - smoothstep(duty, duty + 0.055, a));
}

void fragment() {
	vec2 uv = UV * 2.0 - 1.0;
	float r = length(uv);
	if (r > 1.0) {
		discard;
	}
	float angle = atan(uv.y, uv.x);
	float t = TIME * spin_speed + spin;
	float breathe = 0.90 + 0.10 * sin(TIME * 1.35);

	// --- ① 外圈 -----------------------------------------------------------
	float rings = band(r, 0.975, 0.009) * 0.95;
	rings += band(r, 0.925, 0.004) * 0.42;
	rings += band(r, 0.790, 0.006) * 0.72;
	rings += band(r, 0.600, 0.004) * 0.44;
	rings += band(r, 0.315, 0.006) * 0.68;

	float ticks = teeth(angle, r, 0.800, 0.918, 48.0, t * 0.62, 0.30) * 0.50;
	ticks = max(ticks, teeth(angle, r, 0.610, 0.775, 12.0, -t * 0.37, 0.11) * 0.56);
	// 三道断续弧：差速旋转最直观的证据。只靠同心圆是看不出在转的。
	ticks = max(ticks, teeth(angle, r, 0.930, 0.968, 3.0, t * 0.85, 0.42) * 0.44);
	ticks = max(ticks, teeth(angle, r, 0.548, 0.594, 5.0, -t * 0.55, 0.30) * 0.36);

	// --- ② 内阵 -----------------------------------------------------------
	float spokes = teeth(angle, r, 0.322, 0.592, 6.0, t * 0.16, 0.018) * 0.34;
	// 六芒星：6 瓣角向高次幂，夹在 0.20~0.44 的两道环之间。
	float star = pow(abs(cos(angle * 3.0 - t * 0.10)), 22.0);
	star *= smoothstep(0.18, 0.23, r) * (1.0 - smoothstep(0.43, 0.52, r)) * 0.82;

	// --- ③ 阵心 + 护盾环 ---------------------------------------------------
	float core = (1.0 - smoothstep(0.015, 0.255, r)) * (0.78 + 0.12 * sin(TIME * 2.1));
	float shield_ring = band(r, 0.708 + 0.010 * sin(TIME * 2.4), 0.011) * shield * 1.70;

	// 残血：整圈按角度撕裂式熄灭，而不是整体均匀变暗（后者读不出「坏了」）。
	float flicker = 1.0 - damage * (0.30 + 0.32 * smoothstep(0.2, 0.9, sin(angle * 7.0 + TIME * 15.0)));
	float mask = rings + ticks + spokes + star + core + shield_ring;

	// 方形 PlaneMesh 的边角淡出，避免看到四角。
	float edge = 1.0 - smoothstep(0.955, 1.0, r);
	vec3 body = mix(sigil_color.rgb, hot_color.rgb, clamp(shield * 0.55 + damage * 0.10, 0.0, 1.0));
	ALBEDO = body;
	ALPHA = clamp(mask * active * intensity * breathe * flicker * edge * band_gain * sigil_color.a, 0.0, 1.0);
}
