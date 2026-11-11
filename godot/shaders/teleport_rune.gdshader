shader_type spatial;
// 传送阵的贴地符文轮。
//
// 这是传送阵「活着」的唯一证据。石台、石柱、晶核在 51° 俯视下都只是静态剪影，
// 真正让人一眼认出「这里能传送、现在正在读条」的，是地面上这圈会转、会呼吸、
// 会随引导抽亮的符文。
//
// 为什么整块符文用 shader 画，而不是拼一堆 TorusMesh：
//   1. 圆环是**各向同性**的，转起来在画面上完全看不出在动（见 docs/ai/05-ui-and-feel.md §4.1）。
//      要有齿状刻线、六芒星这种非各向同性图形，才读得出「在转」；
//   2. 两座阵各多 6~8 个环就是十几个 draw call，而 shader 只占 1 个；
//   3. 刻线宽度按半径百分比给，缩到任何机位都清晰，不会像几何环那样忽粗忽细。
//
// 亮度口径（量过像素，别凭手感改）：阵纹峰值必须停在 lumin 180~215 这一档。
// 推到 255 就是在 bloom 里烧成一坨白饼 —— 那时外环、齿、六芒星、读数弧全部糊在一起，
// 玩家反而读不出「读到哪了」。所以：
//   - 底色（台面）压到 DECK_STONE 那种深蓝灰，由石料负责，不在这里减；
//   - 这里的 alpha 统一乘 `BAND_GAIN`，加色叠上去只抬到「清楚可见」就到顶；
//   - 引导进度带来的变化放在**形状**（线变粗、扫过的弧）与**对比**上，
//     而不是继续堆亮度 —— 堆亮度到后面几格就没有视觉差异了。
//
// spin / charge / pulse / flash 全部由 GDScript 每帧写入，**不在 shader 里累加 TIME**：
// 无头测试才能断言「读了 50% 时 charge 真的是 0.5」，否则一切观感都不可测。
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;

uniform vec4 rune_color : source_color = vec4(0.34, 0.84, 0.98, 1.0);
uniform vec4 hot_color : source_color = vec4(0.88, 0.99, 1.0, 1.0);
// 引导进度 0..1：外圈读数扫过、六芒星变粗、中心抽亮。
uniform float charge : hint_range(0.0, 1.0) = 0.0;
// 累计旋转弧度。由 GDScript 推进，速度随 charge 变快。
uniform float spin = 0.0;
// 呼吸相位 0..1。让静止的阵也有「供能」的节奏。
uniform float pulse : hint_range(0.0, 1.0) = 0.5;
// 落地/抵达的一次性闪光 0..1，衰减由 GDScript 控制。
uniform float flash : hint_range(0.0, 1.0) = 0.0;
// 被打断：整圈被撕成条纹并抖一下。颜色语义（转红）交给 Arena 的环，这里只管「裂」。
uniform float shatter : hint_range(0.0, 1.0) = 0.0;
uniform float intensity : hint_range(0.0, 2.0) = 1.0;
// 整体增益。见文件头「亮度口径」：这是把峰值锁在 180~215 的那一档。
uniform float band_gain : hint_range(0.0, 1.0) = 0.60;

// TAU / PI 是 Godot 着色器内置常量，**不能重新声明** —— 重定义会直接编译失败，
// 而失败的表现是「材质回落到纯白」，看起来像石台被刷了一层白漆（踩过）。

// 一圈亮环：宽度按半径的百分比给，任何机位下都不会糊成一条带。
float band(float r, float target, float width) {
	return 1.0 - smoothstep(width, width * 2.0, abs(r - target));
}

// 极坐标齿：把一圈切成 count 格，每格前 duty 比例是亮的。
// 齿是「在转」的视觉证据 —— 圆环转与不转在画面上完全一样。
float teeth(float angle, float r, float inner, float outer, float count, float rot, float duty) {
	float gated = step(inner, r) * step(r, outer);
	float a = fract((angle + rot) / TAU * count);
	return gated * smoothstep(0.0, 0.06, a) * (1.0 - smoothstep(duty, duty + 0.06, a));
}

// 直线的距离场遮罩：六芒星由两组互成 60° 的三条线拼出来。
float line_mask(vec2 p, float normal_angle, float dist, float width) {
	vec2 n = vec2(cos(normal_angle), sin(normal_angle));
	return 1.0 - smoothstep(width, width * 2.0, abs(dot(p, n) - dist));
}

vec2 rot2(vec2 p, float a) {
	float c = cos(a);
	float s = sin(a);
	return vec2(p.x * c - p.y * s, p.x * s + p.y * c);
}

void fragment() {
	vec2 uv = UV * 2.0 - 1.0;
	float r = length(uv);
	if (r > 1.0) {
		discard;
	}
	float ang = atan(uv.y, uv.x);
	float hot = clamp(charge, 0.0, 1.0);
	float breathe = 0.86 + 0.14 * clamp(pulse, 0.0, 1.0);

	// --- 环骨架：三道主环 + 两道细环 -------------------------------------
	// 0.96 是外沿（压在石台内沿上），0.70 / 0.33 是内阵的边界。
	float rings = band(r, 0.960, 0.012) * 1.00;
	rings += band(r, 0.888, 0.005) * 0.50;
	rings += band(r, 0.700, 0.008) * 0.85;
	rings += band(r, 0.520, 0.006) * 0.70;
	rings += band(r, 0.330, 0.004) * 0.55;

	// --- 刻线：外圈密齿顺转、中圈长齿倒转、六根辐条慢转 -------------------
	// 三层转速不同，才能读出「整座阵在做差速旋转」而不是一整块贴图在转。
	float ticks = teeth(ang, r, 0.892, 0.956, 48.0, spin * 0.85, 0.34) * 0.62;
	ticks = max(ticks, teeth(ang, r, 0.524, 0.696, 12.0, -spin * 0.50, 0.15) * 0.58);
	ticks = max(ticks, teeth(ang, r, 0.336, 0.694, 6.0, spin * 0.22, 0.028) * 0.52);

	// --- 内阵六芒星：两组互成 60° 的三线 ---------------------------------
	// 两组线相交成六角星，是本阵最强的记忆点；线宽随引导变粗（能量被灌进内阵）。
	float width = 0.009 + 0.009 * hot;
	vec2 p = rot2(uv, -spin * 0.32);
	float star = 0.0;
	star = max(star, line_mask(p, PI * 0.5, 0.30, width));
	star = max(star, line_mask(p, PI * 7.0 / 6.0, 0.30, width));
	star = max(star, line_mask(p, PI * 11.0 / 6.0, 0.30, width));
	star = max(star, line_mask(p, PI / 6.0, 0.30, width));
	star = max(star, line_mask(p, PI * 5.0 / 6.0, 0.30, width));
	star = max(star, line_mask(p, PI * 1.5, 0.30, width));

	// --- 阵心：光池 + 一颗亮核 -------------------------------------------
	float core = (1.0 - smoothstep(0.05, 0.30, r)) * (0.30 + 0.22 * hot);
	float spark = 1.0 - smoothstep(0.0, 0.070, r);

	// --- 读数：12 点方向起顺时针扫过 -------------------------------------
	// 夹在 0.72~0.86 两道环之间，扫过的部分点亮，笔头是一个更亮的点。
	// 这是「读了多久」最直观的一根指针 —— 光靠整体变亮，到最后两秒几乎看不出差别
	// （实测：drive start→late 的台面亮度只差 0~15 个 luminance 单位，靠亮度根本数不出来）。
	// 不 charge 时不画：常驻一个亮点会被当成贴图瑕疵。
	float t = fract(atan(uv.x, uv.y) / TAU + 1.0);
	float sweep_band = step(0.715, r) * step(r, 0.865);
	float active = step(0.02, hot);
	float swept = step(t, hot) * sweep_band * active;
	// 笔头要**比扫过的那条带明显更亮**才能当指针用：0.030 时它只是弧末端稍亮一点，
	// 实战里 21 米机位下完全看不见。加宽到 0.045 并抬到 1.8 倍才读得出「读到这儿了」。
	float head = (1.0 - smoothstep(0.0, 0.045, abs(t - hot))) * sweep_band * active;

	float mask = rings + ticks + star * 1.00 + core + spark * 1.20;
	mask += swept * 0.75 + head * 1.80;

	// --- 打断：整圈被撕成条纹 -------------------------------------------
	// 乘法叠加而不是直接乘 0：条纹随角度闪动，读成「阵纹断了」而不是「阵变暗了」。
	float ripped = 1.0 - shatter * (0.50 + 0.35 * sin(ang * 33.0 + spin * 2.0));

	// 颜色：常态是饱和的宝石青，读条时向更亮的青白过渡，但不走到纯白。
	// 走满纯白会在大面积加色下变成一块白斑，把「青色的传送阵」这个身份丢掉。
	vec3 base = mix(rune_color.rgb, hot_color.rgb, clamp(hot * 0.50 + flash * 0.65, 0.0, 1.0));
	float alpha = mask * (0.55 + 0.30 * hot) * breathe * ripped * band_gain;
	// 闪光从阵心向外铺满整块石台，边界柔和。
	alpha += flash * 0.30 * (1.0 - smoothstep(0.0, 0.90, r));
	alpha *= intensity * rune_color.a;
	// 边缘再淡出一次：PlaneMesh 是方的，不留这一道会在四角看到直边。
	alpha *= 1.0 - smoothstep(0.96, 1.0, r);

	ALBEDO = base;
	ALPHA = clamp(alpha, 0.0, 1.0);
}
