extends RefCounted

# 进草后的「不可见」标记：一只被斜线划掉的眼睛。
#
# 为什么要程序化画而不是找图标：这个标记要和血条一样在任何分辨率下都清楚，
# 外部 PNG 会跟着 DPI 缩放变糊；而它的形状只有 5 个部件（眼形 / 瞳孔 / 斜线 /
# 描边 / 外发光），用 96×96 的 RGBA 逐像素算一次、缓存成 ImageTexture 就够了。
#
# 颜色选薄荷绿而不是白色：草丛本身是深绿，白眼睛在叶簇上会读成「一个洞」；
# 薄荷绿既能在深绿上跳出来，又和 HUD 的草丛提示同色系。

const TEXTURE_SIZE := 96

static var _texture: ImageTexture = null

static func texture() -> Texture2D:
	if _texture != null:
		return _texture
	var image := Image.create(TEXTURE_SIZE, TEXTURE_SIZE, false, Image.FORMAT_RGBA8)
	var half := float(TEXTURE_SIZE) * 0.5
	for y in TEXTURE_SIZE:
		for x in TEXTURE_SIZE:
			var nx := (float(x) + 0.5 - half) / half
			var ny := (float(y) + 0.5 - half) / half
			var color := _pixel(nx, ny)
			if color.a > 0.002:
				image.set_pixel(x, y, color)
	_texture = ImageTexture.create_from_image(image)
	return _texture

static func _pixel(nx: float, ny: float) -> Color:
	var color := Color(0.0, 0.0, 0.0, 0.0)
	var radius := sqrt(nx * nx + ny * ny)

	# 外发光：让标记从草丛叶簇里「透」出来，而不是贴上去的一块塑料片。
	var glow := 1.0 - smoothstep(0.34, 0.58, radius)
	color = _over(color, Color(0.42, 1.0, 0.62, glow * 0.22))

	var ex := absf(nx)
	if ex >= 1.0:
		return color
	# 杏仁形：上下边界随 |x| 收窄；0.03 的柔边避免缩到 40px 时出现锯齿。
	var half_height := 0.52 * sqrt(maxf(0.0, 1.0 - ex * ex))
	var distance_to_edge := absf(ny) - half_height
	var body := 1.0 - smoothstep(-0.03, 0.035, distance_to_edge)
	if body <= 0.0:
		return color
	color = _over(color, Color(0.012, 0.045, 0.032, body * 0.88))

	# 眼白内圈：贴着轮廓的一道亮边，远看先认出「眼睛」再认出斜线。
	var rim := body * (1.0 - smoothstep(0.0, 0.11, half_height - absf(ny)))
	color = _over(color, Color(0.58, 1.0, 0.76, rim * 0.95))

	var pupil := 1.0 - smoothstep(0.0, 0.035, Vector2(nx, ny).length() - 0.17)
	color = _over(color, Color(0.0, 0.02, 0.015, pupil))

	# 斜线方向 y = -x：先铺一条深色宽线，再压一条亮线，任何底色上都能读清。
	var slash_distance := absf(nx + ny) * 0.70710678
	var slash_dark := 1.0 - smoothstep(0.085, 0.12, slash_distance)
	color = _over(color, Color(0.0, 0.03, 0.02, slash_dark * 0.9))
	var slash_light := 1.0 - smoothstep(0.035, 0.055, slash_distance)
	color = _over(color, Color(0.84, 1.0, 0.92, slash_light))
	return color

# 标准 source-over 合成（top 盖在 base 上）。
static func _over(base: Color, top: Color) -> Color:
	var alpha := top.a + base.a * (1.0 - top.a)
	if alpha <= 0.0001:
		return Color(0.0, 0.0, 0.0, 0.0)
	var r := (top.r * top.a + base.r * base.a * (1.0 - top.a)) / alpha
	var g := (top.g * top.a + base.g * base.a * (1.0 - top.a)) / alpha
	var b := (top.b * top.a + base.b * base.a * (1.0 - top.a)) / alpha
	return Color(r, g, b, alpha)
