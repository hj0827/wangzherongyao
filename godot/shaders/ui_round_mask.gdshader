shader_type canvas_item;

// 圆形头像遮罩。
//
// 为什么要 shader 而不是拿 StyleBox 裁：Godot 的 Control 没有圆形裁剪，
// 方形立绘塞进圆框之后四角会顶出来，读起来像「一张贴纸掉在圆环上」。
// 这里直接把方形纹理按 UV 半径裁成圆，边缘留 6% 的软过渡做抗锯齿。
//
// 注意：本 shader 会顶掉 TextureRect 内置的 stretch 处理，
// 所以调用方必须保证「纹理是正方形 + 控件是正方形」，让 UV 直接等于纹理坐标。

void fragment() {
	vec4 src = texture(TEXTURE, UV);
	vec2 p = UV * 2.0 - 1.0;
	float d = length(p);
	float mask = 1.0 - smoothstep(0.94, 1.0, d);
	COLOR = vec4(src.rgb, src.a * mask);
}
