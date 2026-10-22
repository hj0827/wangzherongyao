extends PanelContainer
## 有厚度感的卡片容器
## 除了面板本身的落影，内部还叠了两层“光”：
##   顶部一条金色高光（顶光打在倒角上）
##   底部一层暗部渐变（面板自身的厚度衰减）
## 两者都画在内容之下，不会盖住文字。
## 内容容器通过 meta "box" 取回。

const SELF_PATH := "res://scripts/ui/depth_card.gd"
const LAYER_PATH := "res://scripts/ui/depth_layer.gd"

static func build(
	bg: Color,
	border: Color,
	radius: int,
	padding: int,
	shadow_size: int = 20
) -> PanelContainer:
	var card := (load(SELF_PATH) as Script).new() as PanelContainer

	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(radius)
	style.corner_detail = 10
	style.anti_aliasing = true
	style.content_margin_left = 0
	style.content_margin_right = 0
	style.content_margin_top = 0
	style.content_margin_bottom = 0
	style.shadow_color = Color(0.0, 0.0, 0.0, 0.55)
	style.shadow_size = shadow_size
	style.shadow_offset = Vector2(0, float(shadow_size) * 0.58)
	card.add_theme_stylebox_override("panel", style)

	var layer := (load(LAYER_PATH) as Script).new() as Control
	layer.name = "Depth"
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	card.add_child(layer)

	var shade := _vertical_fade(Color(0, 0, 0, 0.0), Color(0, 0, 0, 0.34))
	shade.name = "InnerShade"
	shade.anchor_left = 0.0
	shade.anchor_right = 1.0
	shade.anchor_top = 0.3
	shade.anchor_bottom = 1.0
	shade.offset_left = float(radius)
	shade.offset_right = -float(radius)
	shade.offset_top = 0.0
	shade.offset_bottom = 0.0
	layer.add_child(shade)

	var sheen := _vertical_fade(Color(1.0, 0.87, 0.58, 0.42), Color(1.0, 0.87, 0.58, 0.0))
	sheen.name = "TopSheen"
	sheen.anchor_left = 0.0
	sheen.anchor_right = 1.0
	sheen.anchor_top = 0.0
	sheen.anchor_bottom = 0.0
	sheen.offset_left = float(radius) + 6.0
	sheen.offset_right = -float(radius) - 6.0
	sheen.offset_top = 1.0
	sheen.offset_bottom = 3.0
	layer.add_child(sheen)

	var margin := MarginContainer.new()
	margin.name = "Content"
	margin.mouse_filter = Control.MOUSE_FILTER_PASS
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", padding)
	margin.add_theme_constant_override("margin_right", padding)
	margin.add_theme_constant_override("margin_top", padding)
	margin.add_theme_constant_override("margin_bottom", padding)
	layer.add_child(margin)

	var content := VBoxContainer.new()
	content.name = "Box"
	content.mouse_filter = Control.MOUSE_FILTER_PASS
	content.add_theme_constant_override("separation", 10)
	margin.add_child(content)

	layer.set("content", margin)
	card.set_meta("box", content)
	return card

static func _vertical_fade(top: Color, bottom: Color) -> TextureRect:
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 1.0])
	gradient.colors = PackedColorArray([top, bottom])
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.width = 1
	texture.height = 128
	texture.fill_from = Vector2(0, 0)
	texture.fill_to = Vector2(0, 1)
	var rect := TextureRect.new()
	rect.texture = texture
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_SCALE
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rect
