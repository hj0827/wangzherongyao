extends RefCounted

class_name GameTheme

const FONT_REGULAR = preload("res://assets/fonts/NotoSansSC.ttf")
const FONT_DISPLAY = preload("res://assets/fonts/MaShanZheng.ttf")

const GOLD := Color(0.84, 0.66, 0.34)
const GOLD_LIGHT := Color(1.0, 0.86, 0.55)
const INK := Color(0.035, 0.055, 0.075)
const PANEL := Color(0.035, 0.06, 0.085, 0.92)
const PANEL_LIGHT := Color(0.06, 0.095, 0.125, 0.92)
const BLUE := Color(0.24, 0.62, 1.0)
const RED := Color(1.0, 0.36, 0.3)
const GREEN := Color(0.32, 0.8, 0.46)
const MANA := Color(0.28, 0.56, 1.0)
const TEXT := Color(0.9, 0.93, 0.96)
const MUTED := Color(0.58, 0.66, 0.72)

static var _theme: Theme

static func theme() -> Theme:
	if _theme != null:
		return _theme
	var result := Theme.new()
	result.default_font = FONT_REGULAR
	result.default_font_size = 17

	var button_normal := style(PANEL_LIGHT, Color(0.5, 0.4, 0.22, 0.55), 1, 10, 9, 0.45)
	button_normal.shadow_offset = Vector2(0, 6)
	button_normal.content_margin_left = 24
	button_normal.content_margin_right = 24
	button_normal.content_margin_top = 12
	button_normal.content_margin_bottom = 12
	# 悬停：底色提亮 + 金边点亮 + 投影拉长，读起来像被“抬离”了面板
	var button_hover := style(Color(0.11, 0.16, 0.2, 0.97), GOLD, 1, 10, 18, 0.6)
	button_hover.shadow_offset = Vector2(0, 10)
	button_hover.content_margin_left = 24
	button_hover.content_margin_right = 24
	button_hover.content_margin_top = 12
	button_hover.content_margin_bottom = 12
	# 按下：投影收短 + 文字下沉 2px，形成被压回去的手感
	var button_pressed := style(Color(0.15, 0.12, 0.06, 0.98), GOLD_LIGHT, 2, 10, 5, 0.5)
	button_pressed.shadow_offset = Vector2(0, 2)
	button_pressed.content_margin_left = 24
	button_pressed.content_margin_right = 24
	button_pressed.content_margin_top = 14
	button_pressed.content_margin_bottom = 10
	var button_disabled := style(Color(0.05, 0.06, 0.07, 0.7), Color(0.25, 0.27, 0.3, 0.6), 1, 10, 4, 0.3)
	button_disabled.content_margin_left = 24
	button_disabled.content_margin_right = 24
	button_disabled.content_margin_top = 12
	button_disabled.content_margin_bottom = 12
	result.set_stylebox("normal", "Button", button_normal)
	result.set_stylebox("hover", "Button", button_hover)
	result.set_stylebox("pressed", "Button", button_pressed)
	result.set_stylebox("disabled", "Button", button_disabled)
	result.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	result.set_color("font_color", "Button", TEXT)
	result.set_color("font_hover_color", "Button", GOLD_LIGHT)
	result.set_color("font_pressed_color", "Button", GOLD_LIGHT)
	result.set_color("font_disabled_color", "Button", MUTED)
	result.set_font("font", "Button", FONT_REGULAR)
	result.set_font_size("font_size", "Button", 19)

	result.set_color("font_color", "Label", TEXT)
	result.set_font("font", "Label", FONT_REGULAR)
	result.set_font_size("font_size", "Label", 17)

	result.set_stylebox("panel", "Panel", style(PANEL, Color(0.5, 0.4, 0.22, 0.5), 1, 12, 18, 0.5))
	result.set_stylebox("panel", "PanelContainer", style(PANEL, Color(0.5, 0.4, 0.22, 0.5), 1, 12, 18, 0.5))

	result.set_type_variation("TitleLabel", "Label")
	result.set_font("font", "TitleLabel", FONT_DISPLAY)
	result.set_font_size("font_size", "TitleLabel", 64)
	result.set_color("font_color", "TitleLabel", GOLD_LIGHT)

	result.set_type_variation("SubLabel", "Label")
	result.set_color("font_color", "SubLabel", MUTED)
	result.set_font_size("font_size", "SubLabel", 14)

	result.set_type_variation("MonoLabel", "Label")
	result.set_font_size("font_size", "MonoLabel", 16)
	result.set_color("font_color", "MonoLabel", TEXT)

	var line_normal := style(Color(0.02, 0.035, 0.05, 0.95), Color(0.4, 0.34, 0.2, 0.6), 1, 6)
	line_normal.content_margin_left = 16
	line_normal.content_margin_right = 16
	line_normal.content_margin_top = 10
	line_normal.content_margin_bottom = 10
	var line_focus := style(Color(0.025, 0.04, 0.055, 0.98), GOLD, 1, 6)
	line_focus.content_margin_left = 16
	line_focus.content_margin_right = 16
	line_focus.content_margin_top = 10
	line_focus.content_margin_bottom = 10
	result.set_stylebox("normal", "LineEdit", line_normal)
	result.set_stylebox("focus", "LineEdit", line_focus)
	result.set_color("font_color", "LineEdit", TEXT)
	result.set_color("font_placeholder_color", "LineEdit", Color(0.45, 0.52, 0.58))
	result.set_font("font", "LineEdit", FONT_REGULAR)
	result.set_font_size("font_size", "LineEdit", 18)

	_theme = result
	return result

static func style(
	bg: Color,
	border: Color,
	border_width: int,
	radius: int,
	shadow_size: int = 8,
	shadow_alpha: float = 0.45
) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = bg
	box.border_color = border
	box.set_border_width_all(border_width)
	box.set_corner_radius_all(radius)
	box.corner_detail = 10
	box.content_margin_left = 14
	box.content_margin_right = 14
	box.content_margin_top = 10
	box.content_margin_bottom = 10
	box.anti_aliasing = true
	# 统一的落影：所有面板/按钮都从背景里浮起来，而不是贴在画面上
	box.shadow_color = Color(0.0, 0.0, 0.0, shadow_alpha)
	box.shadow_size = shadow_size
	box.shadow_offset = Vector2(0, float(shadow_size) * 0.7)
	return box

static func portrait_path(hero_type: String) -> String:
	return "res://assets/ui/portraits/%s.png" % hero_type

# 立绘是 1024×1024 的半身像，脸在画面上方中间。整张缩到 44px 之后脸只剩几个像素，
# 所以先裁出头肩再降采样。框取 (350,95) 起 320×320：
# 五张立绘的脸中心分别是 blade(500,240) / mage(505,265) / tank(575,205) /
# archer(490,280) / assassin(510,280)，脸宽约 170px —— 320 的框正好让脸占一半，
# 缩到 44px 后五官还认得出来。框再放大就会带进半个身子，脸反而更糊。
const AVATAR_REGION_X := 350
const AVATAR_REGION_Y := 95
const AVATAR_REGION_SIZE := 320

# 和 item_icon 同样的做法：裁好 + 缩到目标尺寸后缓存。
# 原图 2MB/张，每次刷新都重新裁一遍会明显掉帧。
static var _avatar_cache: Dictionary = {}

static func hero_avatar(hero_type: String, size: int) -> Texture2D:
	var key := "%s@%d" % [hero_type, size]
	if _avatar_cache.has(key):
		return _avatar_cache[key]
	var tex: Texture2D = null
	var path := portrait_path(hero_type)
	if ResourceLoader.exists(path):
		var loaded := load(path)
		if loaded is Texture2D:
			var source := loaded as Texture2D
			var img := source.get_image()
			if img != null and not img.is_empty():
				if img.is_compressed():
					img.decompress()
				var region := img.get_region(Rect2i(AVATAR_REGION_X, AVATAR_REGION_Y, AVATAR_REGION_SIZE, AVATAR_REGION_SIZE))
				region.resize(size, size, Image.INTERPOLATE_LANCZOS)
				tex = ImageTexture.create_from_image(region)
			else:
				# get_image 拿不到（压缩纹理）时退回 AtlasTexture，至少能显示。
				var atlas := AtlasTexture.new()
				atlas.atlas = source
				atlas.region = Rect2(AVATAR_REGION_X, AVATAR_REGION_Y, AVATAR_REGION_SIZE, AVATAR_REGION_SIZE)
				tex = atlas
	# 缺图也缓存 null，避免每帧重复走 ResourceLoader.exists。
	_avatar_cache[key] = tex
	return tex

# 装备图标：一件一张，缺图时调用方回落到占位色块，不要在这里造默认图。
static func item_icon_path(item_id: String) -> String:
	return "res://assets/ui/items/%s.png" % item_id

# 已按边长降采样过的图标缓存。原图是 256×256，直接塞进 26px 的格子里既浪费
# 显存又会被逐帧缩放；这里一次性缩到目标尺寸再复用。
static var _icon_cache: Dictionary = {}

static func item_icon(item_id: String, size: int) -> Texture2D:
	var key := "%s@%d" % [item_id, size]
	if _icon_cache.has(key):
		return _icon_cache[key]
	var tex: Texture2D = null
	var path := item_icon_path(item_id)
	if ResourceLoader.exists(path):
		var loaded := load(path)
		if loaded is Texture2D:
			tex = loaded as Texture2D
			var img := tex.get_image()
			if img != null and not img.is_empty():
				if img.is_compressed():
					img.decompress()
				img.resize(size, size, Image.INTERPOLATE_LANCZOS)
				tex = ImageTexture.create_from_image(img)
	# 缺图也缓存 null，避免每帧重复走 ResourceLoader.exists。
	_icon_cache[key] = tex
	return tex

static func has_item_icon(item_id: String) -> bool:
	return ResourceLoader.exists(item_icon_path(item_id))
