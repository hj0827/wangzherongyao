shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;

// 草丛叶片。几何本身就是叶片轮廓（不是 alpha 贴图），
// 所以从任何角度看都有厚度，不会出现 billboard 转身的「纸片感」。
//
// 顶点色携带逐叶明暗 + 黄绿/青绿色相偏移；UV.y 是叶片从根到尖的高度权重。
// 风摆只作用于叶尖（UV.y²），根部必须钉死，否则整丛草会像贴纸一样整体平移。

uniform vec4 leaf_dark : source_color = vec4(0.055, 0.105, 0.035, 1.0);
uniform vec4 leaf_light : source_color = vec4(0.21, 0.35, 0.11, 1.0);
uniform float sway_amount : hint_range(0.0, 0.2) = 0.020;
uniform float sway_speed : hint_range(0.0, 4.0) = 1.25;

void vertex() {
	float weight = UV.y * UV.y;
	vec3 world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	// 用世界坐标做相位：相邻叶片不会整齐划一地摆，整丛才有「活的」感觉。
	float phase = world.x * 0.65 + world.z * 0.85;
	float sway = sin(TIME * sway_speed + phase) * 0.62
		+ sin(TIME * sway_speed * 1.73 + phase * 1.31) * 0.38;
	VERTEX.x += sway * sway_amount * weight;
	VERTEX.z += sway * sway_amount * 0.72 * weight;
}

void fragment() {
	vec3 leaf = mix(leaf_dark.rgb, leaf_light.rgb, UV.y);
	vec3 albedo = leaf * COLOR.rgb;
	ALBEDO = albedo;
	ROUGHNESS = 0.92;
	SPECULAR = 0.1;
	// 双面渲染时背面默认发黑；给一点透光，逆光下的叶丛才不是一团死黑。
	BACKLIGHT = albedo * 0.35;
}
