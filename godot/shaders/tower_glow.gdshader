shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled;

// 防御塔脚下的暖色光池（参考王者荣耀：塔基一圈发光的能量池）。
//
// 用径向淡出 + 一圈亮环，避免 PlaneMesh 的方形直边露出来；
// 叠一层很慢的呼吸，让塔看起来在「供能」。颜色由阵营色驱动，
// 红塔是橙红光池，蓝塔是同色系的冷光池，形状完全一致。
// 混合模式用 mix 而不是 add：add 叠在明亮草地上会直接烧成白色，
// 整座塔看起来像立在一个白圈里。

uniform vec4 glow_color : source_color = vec4(1.0, 0.36, 0.18, 1.0);
uniform float ring_radius : hint_range(0.0, 1.0) = 0.43;
uniform float strength : hint_range(0.0, 2.0) = 0.95;

void fragment() {
	vec2 p = UV - vec2(0.5);
	float d = distance(UV, vec2(0.5)) * 2.0;
	float pool = (1.0 - smoothstep(0.05, 0.95, d)) * 0.55;
	float ring = smoothstep(0.10, 0.0, abs(d - ring_radius)) * 0.60;
	float pulse = 0.88 + 0.12 * sin(TIME * 1.7);
	float alpha = clamp(pool + ring, 0.0, 1.0) * strength * pulse * glow_color.a;
	// 中心提亮一点，读成「有能量从地底渗出来」。
	ALBEDO = glow_color.rgb * (1.0 + 0.25 * (1.0 - smoothstep(0.0, 0.5, d)));
	ALPHA = alpha;
}
