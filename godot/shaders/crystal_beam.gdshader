shader_type spatial;
// 基地水晶的光柱。
//
// 为什么不用一根半透明圆柱 + StandardMaterial3D：
//   1. 圆柱 silhouette 是一条硬边，加色后像一根塑料管；
//   2. 静态 alpha 在 21 米机位下读不出「能量在往上涌」；
//   3. 水晶本体每帧只改材质参数，光柱也应该只改 uniform，不能重建节点。
//
// 这里用两层圆柱（内芯 + 外焰）共用同一份 shader：
//   - 内芯窄、偏白、alpha 高，负责「光真的从水晶里射出来」；
//   - 外焰宽、队伍色、alpha 低，负责在 bloom 里晕开一圈。
//
// 轮廓软化靠 NORMAL·VIEW：圆柱正对镜头的那一条最亮，转到边缘自然淡出，
// 不会留下一条直上直下的硬边（这是第一版看起来像「栏杆」的原因）。
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;

uniform vec4 beam_color : source_color = vec4(0.32, 0.66, 1.0, 0.26);
uniform vec4 hot_color : source_color = vec4(0.86, 0.97, 1.0, 0.72);
// 整体亮度闸门。残血 / 护盾 / 摧毁演出都从这里收，不改几何。
uniform float intensity : hint_range(0.0, 2.5) = 1.0;
uniform float flow_speed = 1.35;
uniform float streak_count = 16.0;
// 光柱向上淡出的起点：0.62 之后逐渐收掉，避免顶端戳进天空像一根柱子。
uniform float fade_start : hint_range(0.0, 1.0) = 0.62;

void fragment() {
	float vertical = UV.y;
	// 两端都淡：底部从石台里「渗」出来，顶部散进天空。
	float ends = smoothstep(0.0, 0.075, vertical) * (1.0 - smoothstep(fade_start, 1.0, vertical));
	// 柱面正对镜头处最亮，边缘柔和消失。abs() 让背面（cull_disabled）也有贡献。
	float facing = abs(dot(normalize(NORMAL), normalize(VIEW)));
	float body = smoothstep(0.04, 0.78, facing);

	// 上升的丝状能量：两个不同频率的角向条纹叠加，避免读出重复的「百叶窗」。
	float angle = UV.x * TAU;
	float streak = 0.58 + 0.42 * sin(angle * streak_count + vertical * 38.0 - TIME * flow_speed);
	streak *= 0.72 + 0.28 * sin(angle * (streak_count * 0.37) - vertical * 15.0 + TIME * flow_speed * 0.63);
	// 大尺度的上升脉冲：让整根柱有「呼吸」，不是一张静止的噪声贴图。
	float pulse = 0.80 + 0.20 * sin(vertical * 8.0 - TIME * 1.7);

	float alpha = ends * body * pulse * (0.42 + 0.58 * streak);
	ALBEDO = mix(beam_color.rgb, hot_color.rgb, clamp(body * streak * 0.42, 0.0, 1.0));
	ALPHA = clamp(alpha * intensity * beam_color.a, 0.0, 0.92);
}
