shader_type spatial;
// 营地 / 首领坑地面的旋转符阵。
// 贴地平面 + 加色混合：不参与光照、不写深度，只负责让石盘在俯视下「活着」。
// 状态由 active 控制：野怪存活 = 亮，击杀等待刷新 = 熄灭（只留一圈暗环）。
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;

uniform vec4 sigil_color : source_color = vec4(0.35, 0.62, 1.0, 0.8);
uniform float active : hint_range(0.0, 1.0) = 1.0;
uniform float pulse_speed = 1.6;
uniform float spin_speed = 0.35;
uniform float intensity = 1.0;

float ring_mask(float radius, float target, float width) {
	return 1.0 - smoothstep(width, width * 2.0, abs(radius - target));
}

void fragment() {
	vec2 uv = UV * 2.0 - 1.0;
	float radius = length(uv);
	if (radius > 1.0) {
		discard;
	}
	float angle = atan(uv.y, uv.x);

	// 双环：外环是边界，内环是阵眼；宽度按半径的百分比给，缩到任何尺寸都清晰。
	float outer_ring = ring_mask(radius, 0.78, 0.022);
	float inner_ring = ring_mask(radius, 0.48, 0.018);
	// 六道旋转刻线：只落在两环之间，读起来像符文而不是车轮。
	float spokes = smoothstep(0.93, 1.0, abs(cos(angle * 3.0 + TIME * spin_speed)));
	spokes *= smoothstep(0.44, 0.5, radius) * (1.0 - smoothstep(0.72, 0.8, radius));
	// 阵心呼吸：击杀后 active 归零，这里随之彻底暗掉。
	float core = (1.0 - smoothstep(0.0, 0.32, radius)) * (0.35 + 0.25 * sin(TIME * pulse_speed));
	float mask = outer_ring + inner_ring * 0.8 + spokes * 0.65 + core * 0.5;

	// 圆盘边缘再淡出一次，避免 PlaneMesh 的方角露出来。
	float edge = 1.0 - smoothstep(0.82, 1.0, radius);
	ALBEDO = sigil_color.rgb;
	ALPHA = clamp(mask * edge * sigil_color.a * intensity * active, 0.0, 1.0);
}
