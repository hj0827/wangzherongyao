shader_type spatial;
render_mode unshaded, shadows_disabled;

// 自定义 billboard 血条/蓝条：
// Godot 4 的 BaseMaterial3D.BILLBOARD_ENABLED 会丢弃节点缩放，
// 导致用 scale.x 控制血条填充完全失效。这里在顶点着色器中手动实现
// billboard（只保留模型平移，旋转对齐相机），网格尺寸 / UV 不受影响，
// 填充比例通过 UV.x 与 ratio 比较在片元着色器中完成。

uniform vec4 fill_color : source_color = vec4(0.22, 0.6, 1.0, 1.0);
uniform vec4 back_color : source_color = vec4(0.015, 0.022, 0.03, 0.88);
uniform vec4 shield_color : source_color = vec4(0.93, 0.96, 1.0, 0.95);
uniform float ratio : hint_range(0.0, 1.0) = 1.0;
uniform float shield_ratio : hint_range(0.0, 1.0) = 0.0;
uniform float padding : hint_range(0.0, 0.2) = 0.032;
uniform float glow : hint_range(0.0, 2.0) = 0.4;

void vertex() {
	// 只保留平移（MODEL_MATRIX 第 4 列），旋转基取自相机，
	// 缩放由 QuadMesh 自身尺寸携带，不会被丢弃。
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
		INV_VIEW_MATRIX[0],
		INV_VIEW_MATRIX[1],
		INV_VIEW_MATRIX[2],
		MODEL_MATRIX[3]
	);
}

void fragment() {
	float x = UV.x;
	float left = padding;
	float right = 1.0 - padding;
	vec4 col = back_color;
	float is_fill = 0.0;
	if (x > left && x < right) {
		float t = (x - left) / (right - left);
		float cap = min(1.0, ratio + shield_ratio);
		if (t < ratio) {
			col = vec4(fill_color.rgb, 1.0);
			is_fill = 1.0;
		} else if (t < cap && shield_ratio > 0.0) {
			col = shield_color;
		}
	}
	ALBEDO = col.rgb;
	ALPHA = col.a;
	EMISSION = fill_color.rgb * glow * is_fill;
}
