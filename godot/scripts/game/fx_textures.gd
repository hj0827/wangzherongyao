extends RefCounted
class_name FxTextures

## 程序化特效贴图。项目里没有 VFX 贴图资产，先用 GradientTexture2D 生成柔光圆，
## 把粒子从"纯色方片"变成"有衰减的光点"。生成一次、静态缓存，战斗路径不 load()。

static var _soft_glow: Texture2D = null

static func soft_glow() -> Texture2D:
	if _soft_glow != null:
		return _soft_glow
	var gradient := Gradient.new()
	gradient.set_color(0, Color(1.0, 1.0, 1.0, 1.0))
	gradient.set_color(1, Color(1.0, 1.0, 1.0, 0.0))
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.width = 64
	texture.height = 64
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	_soft_glow = texture
	return _soft_glow
