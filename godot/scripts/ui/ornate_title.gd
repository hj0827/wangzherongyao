extends Control
## 鎏金浮雕主标题 + 匾额花边。
##
## 原来的标题是一层 Label：金色字 + 黑描边 + 投影。信息没错，但读起来像排版工整的
## 说明文字 —— 单层描边在深色底上永远浮不起来。
##
## 这里换成**多层 Label 由深到浅往下错位堆叠**：最底一层是放大的黑色描边（当硬投影），
## 往上每层收紧 outline、抬高一点点、颜色亮一档，最上面是一层亮金。层与层之间
## 露出的深色边缘就成了「字的厚度」，这正是老游戏标题（金属浮雕字）的做法。
##
## 花边全部由 ornament.gd 生成，在 _draw 里画在文字**下面**（Control 先画自己再画子节点），
## 所以花纹永远不会糊住笔画。

const SELF_PATH := "res://scripts/ui/ornate_title.gd"
const Ornament = preload("res://scripts/ui/ornament.gd")
const GameTheme = preload("res://scripts/ui/game_theme.gd")

## 花边要占的地方。
## 注意：**只有右侧和上下留白，左侧不留** —— 标题必须和下面的副标题左对齐，
## 一旦在控件内居中，整块标题会往右缩进半个留白，看起来像误操作。
## 左边那株花枝画在负坐标里（Control 不裁剪自身绘制），溢到外边距的空白处。
const PAD_RIGHT := 50.0
const PAD_TOP := 42.0
const PAD_BOTTOM := 32.0

## 浮雕层定义（从深到浅）。
## offset 是相对文字基位的偏移，**只能往下增**：往上错位会让描边露在字的上沿，
## 变成「字上盖了层黑边」，看起来很脏。
static func layers(font_size: float) -> Array:
	var scale := font_size / 112.0
	return [
		{
			"offset": Vector2(0.0, 10.0 * scale),
			"color": Color(0.0, 0.0, 0.0, 0.42),
			"outline": int(round(22.0 * scale)),
			"outline_color": Color(0.01, 0.01, 0.008, 0.6),
		},
		{
			"offset": Vector2(0.0, 5.5 * scale),
			"color": Color(0.20, 0.095, 0.02, 1.0),
			"outline": int(round(15.0 * scale)),
			"outline_color": Color(0.13, 0.055, 0.01, 0.98),
		},
		{
			"offset": Vector2(0.0, 3.0 * scale),
			"color": Color(0.52, 0.26, 0.045, 1.0),
			"outline": int(round(8.0 * scale)),
			"outline_color": Color(0.24, 0.11, 0.015, 1.0),
		},
		{
			"offset": Vector2(0.0, 1.2 * scale),
			"color": Color(0.80, 0.50, 0.13, 1.0),
			"outline": int(round(4.0 * scale)),
			"outline_color": Color(0.33, 0.17, 0.03, 1.0),
		},
		{
			"offset": Vector2.ZERO,
			"color": Color(1.0, 0.88, 0.58, 1.0),
			"outline": int(round(2.0 * scale)),
			"outline_color": Color(0.46, 0.26, 0.06, 1.0),
		},
	]

static func build(text: String, font_size: int = 112) -> Control:
	var title := (load(SELF_PATH) as Script).new() as Control
	title.name = "OrnateTitle"

	var font: Font = GameTheme.FONT_DISPLAY
	var glyph := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size)
	var text_size := Vector2(glyph.x, maxf(glyph.y, font.get_height(font_size)))
	title.set_meta("text_size", text_size)
	title.custom_minimum_size = Vector2(
		text_size.x + PAD_RIGHT,
		text_size.y + PAD_TOP + PAD_BOTTOM
	)

	var definitions := layers(float(font_size))
	for index in definitions.size():
		var definition: Dictionary = definitions[index]
		var label := Label.new()
		label.name = "Layer%d" % index
		label.text = text
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		label.autowrap_mode = TextServer.AUTOWRAP_OFF
		label.add_theme_font_override("font", font)
		label.add_theme_font_size_override("font_size", font_size)
		label.add_theme_color_override("font_color", definition.color)
		var outline: int = definition.outline
		if outline > 0:
			label.add_theme_constant_override("outline_size", outline)
			label.add_theme_color_override("font_outline_color", definition.outline_color)
		label.set_meta("layer_offset", definition.offset)
		title.add_child(label)
	return title

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_layout_layers()
		queue_redraw()

## 让每一层都对齐到同一块文字基位，只差各自的浮雕偏移。
## 文字左对齐到 x = 0：标题是左侧那一栏的视觉起点，必须和 kicker / 副标题同一根竖线。
func _layout_layers() -> void:
	var text_size: Vector2 = get_meta("text_size", Vector2.ZERO)
	var origin := Vector2(0.0, PAD_TOP)
	for child in get_children():
		var label := child as Label
		if label == null:
			continue
		var offset: Vector2 = label.get_meta("layer_offset", Vector2.ZERO)
		label.position = origin + offset
		label.size = text_size

func _draw() -> void:
	var text_size: Vector2 = get_meta("text_size", Vector2.ZERO)
	if text_size.x <= 0.0:
		return
	# 花边一律按**文字实测宽**算，不用控件宽：控件会被 VBox 拉满整栏，
	# 按控件宽画出来的中轴线会横穿到右侧的战场面板下面去。
	var left := 0.0
	var right := text_size.x
	var top := PAD_TOP
	var bottom := PAD_TOP + text_size.y
	var gold := GameTheme.GOLD_LIGHT

	# 上轴：压在标题上沿当「匾额横档」。取字宽的 86% —— 收窄到 58% 时它只悬在
	# 中间两个字上方，两头空得莫名其妙；齐平又会读成一条把画面切断的横杠。
	var upper_width := text_size.x * 0.86
	Ornament.paint(self, Ornament.center_rule(upper_width, top - 17.0, 1.3),
		Color(gold.r, gold.g, gold.b, 0.42), 1.5,
		Vector2((text_size.x - upper_width) * 0.5, 0.0))
	# 下轴：比标题略宽，收住整行字
	Ornament.paint(self, Ornament.center_rule(text_size.x + 14.0, bottom + 15.0, 1.5),
		Color(gold.r, gold.g, gold.b, 0.50), 1.6, Vector2(-7.0, 0.0))

	# 左右花枝：朝外的那一株向外伸展，朝内的一端扎进字旁。
	# 标题尺寸下不要起笔的叶子 —— 它会垂到字的下半截旁边，变成一撮看不清的金点。
	# inset 是给字体自身左侧留白（side bearing）的补偿：text_size 包含这段空白，
	# 按字宽摆花枝会让它离笔画差出几十像素。
	var wing_height := text_size.y * 0.56
	var wing_y := top + text_size.y * 0.56
	var inset := text_size.x * 0.05
	Ornament.paint(self,
		Ornament.wing(Vector2(left + inset, wing_y), 40.0, wing_height, -1.0, false),
		Color(gold.r, gold.g, gold.b, 0.72), 1.6)
	Ornament.paint(self,
		Ornament.wing(Vector2(right - inset, wing_y), 40.0, wing_height, 1.0, false),
		Color(gold.r, gold.g, gold.b, 0.72), 1.6)
