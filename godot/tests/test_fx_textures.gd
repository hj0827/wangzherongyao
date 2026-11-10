extends "res://tests/test_base.gd"

# 程序化 VFX 贴图（P0 视觉升级）。
#
# 项目里没有 VFX 贴图资产；粒子从"纯色方片"升级成"中心亮、边缘透明的柔光圆"。
# 这里钉住：生成一次并缓存、尺寸固定、径向渐变、边缘 alpha 为 0。

const FxTextures = preload("res://scripts/game/fx_textures.gd")

func test_soft_glow_is_a_cached_radial_gradient() -> void:
	var first := FxTextures.soft_glow()
	check(first != null, "柔光贴图必须能生成")
	if first == null:
		return
	eq(first.get_width(), 64, "贴图宽度固定 64")
	eq(first.get_height(), 64, "贴图高度固定 64")
	check(FxTextures.soft_glow() == first, "重复调用必须复用同一张纹理")
	var gradient_texture := first as GradientTexture2D
	check(gradient_texture != null, "必须是 GradientTexture2D")
	if gradient_texture == null:
		return
	eq(gradient_texture.fill, GradientTexture2D.FILL_RADIAL, "必须是径向渐变")
	eq(gradient_texture.fill_from, Vector2(0.5, 0.5), "渐变从中心开始")
	near(gradient_texture.gradient.get_color(0).a, 1.0, 0.001, "中心不透明")
	near(gradient_texture.gradient.get_color(1).a, 0.0, 0.001, "边缘完全透明")
