extends Control
## 按钮花边覆盖层。
##
## 按钮本体还是普通的 Button（主题里的 StyleBoxFlat 负责底、边、投影、悬停抬升），
## 这里只往上贴一层**不响应鼠标**的装饰：文字左右各一株卷须。悬停时卷须点亮
## （glow 0 → 1），按下时跟着按钮缩放一起动。
##
## 为什么不做成 StyleBoxTexture / 九宫格贴图：贴图在按钮被拉宽时会把卷尾一起拉扁，
## 而花边恰恰是靠「卷」立住的。程序化画就不会变形。

const SELF_PATH := "res://scripts/ui/ornate_frame.gd"
const Ornament = preload("res://scripts/ui/ornament.gd")
const GameTheme = preload("res://scripts/ui/game_theme.gd")

## 0 = 静息亮度，1 = 全亮。由 hover 驱动，_process 里缓动逼近目标值。
var glow: float = 0.0
var _target_glow: float = 0.0
## 被装饰的按钮。卷须要贴着文字放，所以得回头问它要文字实测宽度。
var _host: Control = null

static func attach(target: Control, row_height: float = 58.0) -> Control:
	var overlay := (load(SELF_PATH) as Script).new() as Control
	overlay.name = "Ornament"
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.set_meta("row_height", row_height)
	overlay.set("_host", target)
	overlay.anchor_left = 0.0
	overlay.anchor_top = 0.0
	overlay.anchor_right = 1.0
	overlay.anchor_bottom = 1.0
	overlay.offset_left = 0.0
	overlay.offset_top = 0.0
	overlay.offset_right = 0.0
	overlay.offset_bottom = 0.0
	target.add_child(overlay)
	target.resized.connect(Callable(overlay, "refresh"))
	target.mouse_entered.connect(Callable(overlay, "set_glow").bind(1.0))
	target.mouse_exited.connect(Callable(overlay, "set_glow").bind(0.0))
	overlay.call("refresh")
	return overlay

func refresh() -> void:
	queue_redraw()

func set_glow(value: float) -> void:
	_target_glow = clampf(value, 0.0, 1.0)
	set_process(true)

func _process(delta: float) -> void:
	glow = move_toward(glow, _target_glow, delta * 5.5)
	queue_redraw()
	if is_equal_approx(glow, _target_glow):
		glow = _target_glow
		set_process(false)

func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, size)
	if rect.size.x < 120.0 or rect.size.y < 26.0:
		return
	var row_height: float = get_meta("row_height", rect.size.y)
	var alpha := 0.48 + 0.45 * glow
	var gold := Color(GameTheme.GOLD.r, GameTheme.GOLD.g, GameTheme.GOLD.b + 0.12, alpha)
	var line_width := 1.4 + 0.4 * glow

	# 左右各一株小卷草，**夹着文字**放。
	# 为什么不是四角内嵌 L 线：上下两个角的竖边在按钮两侧会连成一条虚线，
	# 视觉上把一颗按钮切成三段 —— 试过，比不画还糟。
	# 为什么不是贴在按钮两端：按钮宽 386、文字只有 150，贴边放会变成两边各挂一个
	# 孤立的小挂件；贴着文字才读成「❧ 单人试炼 · 1 V 1 ❧」这一整行。
	var half := _text_width() * 0.5
	var centre := rect.size.x * 0.5
	var gap := 14.0
	var room := centre - half - gap - 10.0
	if room < 14.0:
		return
	var mid_y := rect.size.y * 0.5
	var height := minf(minf(rect.size.y, row_height) * 0.42, 22.0)
	var span := minf(room * 0.62, 30.0)
	Ornament.paint(self, Ornament.tendril(Vector2(centre - half - gap, mid_y), span, height, -1.0), gold, line_width)
	Ornament.paint(self, Ornament.tendril(Vector2(centre + half + gap, mid_y), span, height, 1.0), gold, line_width)

func _text_width() -> float:
	if _host == null or not is_instance_valid(_host):
		return 0.0
	var font: Font = _host.get_theme_font("font")
	if font == null:
		return 0.0
	var font_size: int = _host.get_theme_font_size("font_size")
	var text := str(_host.get("text"))
	return font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size).x
