shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled;

// 草丛脚下的柔和暗斑。
//
// 以前直接用 PlaneMesh + 半透明绿色：矩形四条直边在草地上非常刺眼，
// 看起来像一块「绿玻璃」。这里按 UV 到中心的距离径向淡出，
// 边缘再加一点点不规则抖动，读成树丛下的接触阴影而不是 UI 色块。

uniform vec4 floor_color : source_color = vec4(0.035, 0.075, 0.03, 1.0);
uniform float opacity : hint_range(0.0, 1.0) = 0.52;
uniform float softness : hint_range(0.0, 0.9) = 0.38;

void fragment() {
	vec2 p = UV - vec2(0.5);
	float angle = atan(p.y, p.x);
	// 两个不同频率的正弦叠加，边缘不是完美的圆，也不会看出多边形。
	float wobble = sin(angle * 7.0) * 0.035 + sin(angle * 13.0 + 1.7) * 0.018;
	float d = distance(UV, vec2(0.5)) * 2.0 + wobble;
	float alpha = (1.0 - smoothstep(1.0 - softness, 1.0, d)) * opacity;
	ALBEDO = floor_color.rgb * mix(0.86, 1.0, clamp(d, 0.0, 1.0));
	ALPHA = alpha;
}
