extends Control
## 主菜单的透明丝绸飘带层。
##
## 它解决的是**构图问题**，不是装饰问题：左栏（标题）和右栏（战场面板）原本是两块
## 互不相干的岛，中间只有一片空背景。两条丝带从两侧钻进面板底下、再从另两边钻出来，
## 面板于是被绸子「扎」在画面里 —— 它不再是贴在背景上的一张卡片，而是浮在绸子上的一层玻璃。
##
## 为什么不是贴图：丝带要跟着面板走。窗口一改尺寸，面板换了位置，贴图就得重新对位；
## 而这里的走位是**按面板矩形算出来的** —— 面板在哪，丝带就从哪穿过。
##
## 走位有一条硬约束：**不许穿过左栏文字块**（见 TEXT_BLOCK）。绸子划过书法或说明文字，
## 字就废了 —— 这比「丝带不够好看」严重得多，所以它是测试守的第一条。
##
## 画法（「透明丝绸」）在 silk_ribbon.gd 里：主体极淡 + 上侧高光核 + 下侧暗面 + 亮/暗沿边线。
## 面是透的、边是亮的，厚度感就出来了；全靠多层纯色，不写渐变，改色也只改一个数。
##
## 动画 = **一次几何缓存 + 每帧只推波形**：
##   base_layout 只在尺寸 / 面板矩形变化时算一次（曲线、法线、宽度都存下来），
##   每帧只做 wave() 的法线位移、flow_widths() 的宽度起伏和拼边。
## 循环靠时间取模：波形是 sin(t)、谐波是 2 倍频，time += PERIOD 时相位正好转一圈，
## 所以循环点是数学上闭合的，看不到接缝。

const SilkRibbon = preload("res://scripts/ui/silk_ribbon.gd")
const GameTheme = preload("res://scripts/ui/game_theme.gd")

## 走位坐标全部按 1920×1080 的设计稿写，运行时按画布等比缩放。
const DESIGN := Vector2(1920.0, 1080.0)
## 采样点数。320 在 1600 宽的画面里约每 8px 一个点，沿边线看不出折角；
## 再往上加只会让每帧的顶点数变多，视觉收益接近于零。
const SAMPLES := 320

## 一次完整流动的周期（秒）。取 13 秒：比呼吸慢、比心跳远，看着不催人。
const PERIOD := 13.0
## 波形振幅（设计稿像素）。只做「绸子在空气里被托了一下」的程度，不能大。
const WAVE_AMPLITUDE := 20.0
## 沿整条带传播的波数。1.35 波：一头抬起时另一头还在下沉，读起来是流动。
const WAVE_COUNT := 1.35
## 宽度起伏深度：±14%。再大就成了「被反复拉扯的橡皮带」。
const WAVE_DEPTH := 0.14

## 一次「生长」循环的长度。**必须是波形周期（PERIOD）的整数倍**：
## 两者同时闭合，绸子重来的那一刻波形相位也在起点上，画面不会出现两套节奏互相错拍。
## 取 2 倍而不是 1 倍，是因为下面四段里「停留」必须够长 —— 丝带不是装饰，
## 它把左栏和右面板缝在一起；循环太短的话，面板隔一会儿就重新变成一座孤岛。
const CYCLE := PERIOD * 3.0

## 一个循环里的四段（秒）：
##   GROW  头部从画外走进画外 —— 这就是「从边边慢慢出现延长」
##   HOLD  整条都在，只剩波形在流（占掉一半以上的时间）
##   SLIDE 尾部追上来，绸子被抽走（不能「啪」地消失）
##   GAP   什么都不画
## 四段之和必须等于 CYCLE，`test_the_growth_cycle_closes_and_lines_up_with_the_wave` 守着。
const GROW_TIME := 8.0
const HOLD_TIME := 26.5
const SLIDE_TIME := 3.5

## 头部（以及抽走时的尾部）收成尖所用的长度，单位是**采样点数**。
## 采样是弧长等距的，所以 12 点 ≈ 全长的 4% ≈ 屏幕上 80px —— 一个线头的长度。
## 不能改成「占可见长度的比例」：那样长满之后两端也会跟着收细，而两端本该是齐宽的。
const TIP_SAMPLES := 12.0

## 左栏文字块（设计稿坐标）：英文眉标 / 主标题 / 副标 / 说明都在里面。
## 丝带**绝不允许**穿过这块 —— 绸子划过书法，字就废了。
const TEXT_BLOCK := Rect2(30.0, 30.0, 730.0, 620.0)

## 左栏底部那块字：特性标签（chip）+ 操作提示行。很容易被忘掉的一块 ——
## 只挡上面的标题块时，丝带会从「左键 点击移动…」上划过去，屏幕上只觉得那行字花了。
const HINT_BLOCK := Rect2(30.0, 900.0, 730.0, 140.0)

## 所有文字禁入区。丝带走位必须从两块之间的空档（y ≈ 660 ~ 890）横穿过去。
const KEEP_OUT := [TEXT_BLOCK, HINT_BLOCK]

## 截面：把带宽切成若干条互不重叠的细带，每条一个颜色，用纯色分层近似「柱面受光」。
##
## 为什么不用一条平带 + 一条亮边：那是**光带**的画法。丝绸之所以像丝绸，是因为横截面上
## 有一条连续从亮到暗的渐变（上沿迎着光、中间半透、下沿是背光的暗部）。切成 6 条之后，
## 屏幕上就是一条会「转」的带子，而不是一张半透明的贴纸。
##
## ⚠️ 深色原画上最容易犯的错：下沿暗面用近黑色。整条带会被读成一道**阴影 / 污渍**
## （上一版真实出现过），而不是一块会透光的绸子。所以最暗的一档停在暖棕，不下潜到黑 ——
## 「暗」靠的是相对上沿更暗，不是绝对亮度低。
##
## 每项：[起点比例, 终点比例, 颜色, 透明度]。比例是带宽的比例，-0.5 ~ 0.5 是整条。
const SECTION_TILES := [
	[-0.50, -0.34, Color(1.00, 0.97, 0.90), 0.20],
	[-0.34, -0.14, Color(1.00, 0.90, 0.70), 0.12],
	[-0.14, 0.06, Color(0.93, 0.78, 0.52), 0.075],
	[0.06, 0.22, Color(0.74, 0.56, 0.32), 0.055],
	[0.22, 0.36, Color(0.52, 0.36, 0.18), 0.050],
	[0.36, 0.50, Color(0.34, 0.22, 0.10), 0.055],
]

## 沿边线。上沿是丝绸绷紧的那道「丝光」，下沿只是让轮廓收住 ——
## 两者的重量必须差得开，否则带子变成一块有描边的纸。
const RIM_LIGHT := Color(1.0, 0.97, 0.90)
const RIM_LIGHT_ALPHA := 0.34

## 截面之外再往两侧各溢出一段，透明度淡到 0。
##
## 这一段是**1px 硬描边的替代品**。原先边上是三层抗锯齿折线（9px 淡 + 4px 中 + 1.1px 实），
## 放大看确实像丝光，但代价是每条带 5 条 AA 折线 × 320 段 —— 实测丝带整层要吃掉
## 30ms/帧（1600×900，Intel UHD 730）。现在把「光晕」改成截面自己向外淡出：
## 顶点数只多两排，而且和主体共用一次三角带绘制。
const SECTION_GLOW := [-0.62, 0.62]

## 拿不到面板矩形时（首帧排版前）用的回落位置，按设计稿比例给。
const FALLBACK_FOCUS_FRAC := Rect2(0.675, 0.235, 0.245, 0.40)

## 三条带的走位与宽度（设计稿坐标 / 设计稿像素）。
## 主带与细带里出现 f.position / f.end 的项是**跟着面板算的**，不是硬编码：
## 面板换位置时丝带会跟着改道，不会从旁边绕过去。
##
## phase 是这条带的生长循环**起点偏移（秒）**。三条必须错开：
## 同时长、同时满的话，整屏还是一次整体的呼吸 —— 依然读不出「从边边来」。
##
## 现值的效果（39s 一个循环）：
##   开场   主带整条、细带刚长到 20%、远景带整条 —— 面板已被缝住，同时看得见「正在延长」
##   9~17s  远景带从画外长出来
##   14.5s  主带被抽走 → 19s 重新长回来
##   32.5s  细带被抽走 → 37s 重新长回来
## 三条的生长窗口互不重叠（`test_the_three_ribbons_do_not_grow_together` 守着），
## 所以任何时刻最多只有一条在延长 —— 那才是「一条一条来」，而不是「一起动」。
const RIBBON_SPECS := [
	{
		"key": "main",
		"alpha": 1.0,
		"phase": 20.0,
		"stops": [[0.0, 84.0], [0.20, 76.0], [0.44, 64.0], [0.60, 56.0], [0.78, 62.0], [1.0, 30.0]],
	},
	{
		"key": "thin",
		"alpha": 0.9,
		"phase": 2.0,
		"stops": [[0.0, 3.0], [0.10, 22.0], [0.34, 28.0], [0.58, 24.0], [0.80, 17.0], [1.0, 2.0]],
	},
	{
		"key": "accent",
		"alpha": 0.55,
		"phase": 30.0,
		"stops": [[0.0, 2.0], [0.30, 17.0], [0.70, 13.0], [1.0, 3.0]],
	},
]

var _focus := Rect2()
var _focus_dirty := true
var _base: Array = []
var _base_size := Vector2(-1.0, -1.0)
var _time := 0.0
var _pointer := Vector2.ZERO
var _pointer_target := Vector2.ZERO

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	resized.connect(_invalidate)
	_invalidate()

## 由 main 在面板排版之后回填（屏幕坐标系，和本控件同一坐标系）。
## 只在一帧之内变化超过半个像素时才重建 —— 布局每帧都在挪 0.3px 的话，
## 重建几千个顶点会变成隐形的掉帧源。
func set_focus_rect(rect: Rect2) -> void:
	if rect.size.x < 8.0 or rect.size.y < 8.0:
		return
	if _focus.position.distance_to(rect.position) < 0.5 and _focus.size.distance_to(rect.size) < 0.5:
		return
	_focus = rect
	_invalidate()

func _invalidate() -> void:
	_focus_dirty = true
	_base = []
	_base_size = Vector2(-1.0, -1.0)
	queue_redraw()

func _process(delta: float) -> void:
	# 时间是累加的绝对时间，不是「每帧加一个固定步长」：
	# 掉一帧只会让波形跳过一次采样，不会让整条丝带和帧率绑死（那才是真卡顿）。
	_time = fmod(_time + delta, PERIOD * 1024.0)
	if is_inside_tree() and size.x > 1.0 and size.y > 1.0:
		var mouse: Vector2 = get_viewport().get_mouse_position() - global_position
		var centered := (mouse / size - Vector2(0.5, 0.5)) * 2.0
		_pointer_target = centered.clamp(Vector2(-1.0, -1.0), Vector2(1.0, 1.0)) * -7.0
	_pointer = _pointer.lerp(_pointer_target, clampf(delta * 1.6, 0.0, 1.0))
	queue_redraw()

func _ensure_base() -> void:
	if size.x < 8.0 or size.y < 8.0:
		_base = []
		return
	if _base.is_empty() or _base_size != size or _focus_dirty:
		_base = base_layout(size, _focus, SAMPLES)
		_base_size = size
		_focus_dirty = false

func _draw() -> void:
	_ensure_base()
	if _base.is_empty():
		return
	# 只留一点点指针视差：丝带是「远处飘过来」的东西，跟着鼠标大幅平移会立刻穿帮。
	# draw_set_transform 改的是本 canvas item 的变换，后面直接走 RenderingServer 的
	# 三角带绘制同样吃这个变换，不用逐点加偏移。
	draw_set_transform(_pointer, 0.0, Vector2.ONE)
	var canvas_item := get_canvas_item()
	for item in frame_geometry(_base, _time, false):
		var ribbon: Dictionary = item
		# 生长空档里这一条是零宽度的退化带：顶点全叠在尖端，画了也看不见，
		# 但每帧照样要提交几千个顶点 —— 直接跳过。
		if not bool(ribbon.get("revealed", true)):
			continue
		var strength := float(ribbon.get("alpha", 1.0))
		# 整条带（含两侧淡出）一次三角带画完：索引和顶点色都是缓存好的静态数据，
		# 每帧只换顶点坐标。这是本层从 30ms 掉到 1ms 量级的关键 ——
		# 用 draw_colored_polygon 画 640 点的凹多边形，引擎每帧都要重新三角化一次。
		RenderingServer.canvas_item_add_triangle_array(
			canvas_item,
			ribbon["mesh_indices"] as PackedInt32Array,
			ribbon["mesh_vertices"] as PackedVector2Array,
			ribbon["mesh_colors"] as PackedColorArray
		)
		# 亮边只留一条 1.1px 的抗锯齿实线：丝光要有「一根绷紧的丝」，光靠渐变会显得发虚。
		var rim: PackedVector2Array = ribbon["rim_light"]
		if rim.size() > 1:
			draw_polyline(rim,
				Color(RIM_LIGHT.r, RIM_LIGHT.g, RIM_LIGHT.b, RIM_LIGHT_ALPHA * strength), 1.1, true)
		# 暗边不描线 —— 截面的最后一档已经收在暖棕，再加一条线就成了「描边的纸」。

## 拿不到面板矩形时的回落位置（屏幕坐标）。
static func default_focus(canvas: Vector2) -> Rect2:
	var scale := minf(canvas.x / DESIGN.x, canvas.y / DESIGN.y)
	var origin := (canvas - DESIGN * scale) * 0.5
	var frac := FALLBACK_FOCUS_FRAC
	return Rect2(
		origin + Vector2(frac.position.x * DESIGN.x, frac.position.y * DESIGN.y) * scale,
		frac.size * DESIGN * scale
	)

## 设计稿坐标 → 屏幕坐标的换算（origin + p * scale）。
static func _to_screen(canvas: Vector2, point: Vector2) -> Vector2:
	var scale := minf(canvas.x / DESIGN.x, canvas.y / DESIGN.y)
	if scale <= 0.0001:
		scale = 1.0
	var origin := (canvas - DESIGN * scale) * 0.5
	return origin + point * scale

## 某一时刻这条带**可见的那一段**，用 0~1 的弧长比例给出：[尾部, 头部]。
##
## 这是「从边边慢慢出现延长」的唯一真身。上一版没有它：三条带一上来就是整条，
## 只有波形在推 —— 屏幕上读不出绸子从哪里来，只看到一整条在原地晃。
##
## 返回 (x, x) 表示这一段长度为 0（还没长出来 / 已经抽走 / 在空档里）。
static func reveal_span(time: float, phase: float = 0.0) -> Vector2:
	var local := fposmod(time + phase, CYCLE)
	if local < GROW_TIME:
		return Vector2(0.0, _growth_ease(local / GROW_TIME))
	local -= GROW_TIME
	if local < HOLD_TIME:
		return Vector2(0.0, 1.0)
	local -= HOLD_TIME
	if local < SLIDE_TIME:
		return Vector2(_growth_ease(local / SLIDE_TIME), 1.0)
	return Vector2(1.0, 1.0)

## 生长的缓动：两头慢、中间匀。
##
## 线性推进读起来像「进度条」；缓入让线头刚冒出来时几乎不动（那是它从画外探头的瞬间），
## 缓出让它在画外那一端自然收速。用 smoothstep 而不是更强的曲线 —— 中间那一段要够匀，
## 否则 `test_growth_moves_at_a_steady_visible_speed` 会看到忽快忽慢。
static func _growth_ease(ratio: float) -> float:
	var clamped := clampf(ratio, 0.0, 1.0)
	return clamped * clamped * (3.0 - 2.0 * clamped)

## 把整条曲线**裁剪**到 [tail, head] 这段（单位：采样点序号，可以是小数），
## 并把两端的宽度收成零。
##
## 为什么不是「真的切掉点」：三角带的索引和顶点色是**缓存好的静态数据**
## （见 mesh_topology 与「一次三角带」的性能契约），顶点数一变就得每帧重算拓扑。
## 所以这里保留点数，把看不见的点**全部叠到尖端那一个位置**上 —— 面积为零的三角形
## 什么都不画，代价是 0，而拓扑仍然静态。
##
## 顺带得到「线头」：靠近头部的那 tip 个点宽度按 smoothstep 收零，三角形于是自然收成一个尖。
static func shape_reveal(
	curve: PackedVector2Array,
	width_values: PackedFloat32Array,
	head: float,
	tail: float,
	tip: float = TIP_SAMPLES
) -> Dictionary:
	var count := curve.size()
	var spine_out := PackedVector2Array()
	var widths_out := PackedFloat32Array()
	spine_out.resize(count)
	widths_out.resize(count)
	if count == 0 or width_values.size() != count:
		return {"spine": spine_out, "widths": widths_out}
	var last := float(count - 1)
	var head_at := clampf(head, 0.0, last)
	var tail_at := clampf(tail, 0.0, head_at)
	# 停留阶段（整条都在）占掉一个循环的三分之二。这时裁剪和收尖都是恒等变换 ——
	# 直接原样返回，别让每帧白付 320 次插值和 smoothstep。
	# 两端都在画外，所以「本来会收尖」这件事看不见。
	if head_at >= last - 0.0001 and tail_at <= 0.0001:
		return {"spine": curve, "widths": width_values}
	var taper := maxf(tip, 0.001)
	for index in count:
		var at := clampf(float(index), tail_at, head_at)
		var low := int(floor(at))
		var high := mini(low + 1, count - 1)
		spine_out[index] = curve[low].lerp(curve[high], at - float(low))
		# 头部永远收尖（长出来的是线头，不是断口）。
		# 尾部只在「抽走」阶段收尖 —— 生长和停留时尾部在画外，收了也看不见，
		# 但那一刻它必须是齐宽的，否则长满的瞬间会看到尾部忽然变细。
		var head_taper := smoothstep(0.0, 1.0, clampf((head_at - at) / taper, 0.0, 1.0))
		var tail_taper := 1.0
		if tail_at > 0.001:
			tail_taper = smoothstep(0.0, 1.0, clampf((at - tail_at) / taper, 0.0, 1.0))
		widths_out[index] = width_values[index] * head_taper * tail_taper
	return {"spine": spine_out, "widths": widths_out}

## 静态骨架：曲线、法线、宽度各算一次，动画只在这个骨架上推波形。
## 返回 [{key, alpha, spine, normals, widths, amplitude}]。
static func base_layout(canvas: Vector2, focus: Rect2, samples: int = SAMPLES) -> Array:
	var scale := minf(canvas.x / DESIGN.x, canvas.y / DESIGN.y)
	if scale <= 0.0001:
		scale = 1.0
	var origin := (canvas - DESIGN * scale) * 0.5
	var focus_screen := focus
	if focus_screen.size.x < 8.0 or focus_screen.size.y < 8.0:
		focus_screen = default_focus(canvas)
	# 换回设计空间：走位是按设计稿写的，只有面板矩形是运行时的。
	var f := Rect2((focus_screen.position - origin) / scale, focus_screen.size / scale)

	# 主带：从左边缘的**空档**（标题块 y≤650 与提示行 y≥900 之间）横穿过来 →
	# 抬到面板左下部钻进去 → 从面板右缘出来 → 收向右下画外。
	#
	# 两条硬约束，都是被真实缺陷逼出来的：
	#   1. y 必须落在 660~890 之间。上一版走 y≈1000，正好压在底部那行操作提示上。
	#   2. **不许先掉出画布再折回来**。上一版在 x≈780 处掉到 y=1122（画布外）再折回 922，
	#      带子被视口底边切掉一截又突然接上 —— 屏幕左边那个「凿出来的直角」就是它。
	var main_path := PackedVector2Array([
		Vector2(-180.0, 838.0),
		Vector2(140.0, 802.0),
		Vector2(f.position.x - 880.0, 748.0),
		Vector2(f.position.x - 600.0, 712.0),
		Vector2(f.position.x - 340.0, 748.0),
		Vector2(f.position.x - 140.0, 814.0),
		Vector2(f.position.x + f.size.x * 0.10, f.end.y - 42.0),
		Vector2(f.position.x + f.size.x * 0.55, f.end.y - 96.0),
		Vector2(f.end.x + 30.0, f.end.y - 58.0),
		Vector2(f.end.x + 220.0, f.end.y + 62.0),
		Vector2(f.end.x + 470.0, f.end.y + 196.0),
	])

	# 细带：从右上入画 → 从面板**上缘**钻进去 → 从面板**左缘**吐出来 → 沿两栏之间的
	# 空档垂下去 → 收于下方画外。它是「面板被绸子绕了一圈」的那半圈。
	var thin_path := PackedVector2Array([
		Vector2(2060.0, 88.0),
		Vector2(f.end.x + 120.0, 152.0),
		Vector2(f.position.x + f.size.x * 0.62, f.position.y + 12.0),
		Vector2(f.position.x + f.size.x * 0.32, f.position.y + 192.0),
		Vector2(f.position.x - 42.0, f.position.y + 302.0),
		Vector2(f.position.x - 222.0, f.position.y + 400.0),
		Vector2(f.position.x - 400.0, f.position.y + 540.0),
		Vector2(f.position.x - 470.0, f.position.y + 700.0),
		Vector2(f.position.x - 500.0, f.position.y + 862.0),
	])

	# 远景带：只在右上空域扫一条，负责空气感。全程 y ≤ 100，绝不靠近面板顶（240）。
	var accent_path := PackedVector2Array([
		Vector2(960.0, -120.0),
		Vector2(1280.0, 30.0),
		Vector2(1620.0, 92.0),
		Vector2(1960.0, 42.0),
		Vector2(2140.0, -40.0),
	])

	var paths := {"main": main_path, "thin": thin_path, "accent": accent_path}

	var result: Array = []
	for spec in RIBBON_SPECS:
		var key := str((spec as Dictionary).get("key"))
		var through := PackedVector2Array()
		for point in paths[key]:
			through.append(origin + (point as Vector2) * scale)
		var stops: Array = []
		for stop in (spec as Dictionary).get("stops", []):
			stops.append([float((stop as Array)[0]), float((stop as Array)[1]) * scale])
		var spine := SilkRibbon.spline(through, maxi(samples, 16))
		var alpha := float((spec as Dictionary).get("alpha", 1.0))
		var topology := mesh_topology(spine.size(), alpha)
		result.append({
			"key": key,
			"alpha": alpha,
			"phase": float((spec as Dictionary).get("phase", 0.0)),
			"spine": spine,
			"normals": SilkRibbon.normals(spine),
			"widths": SilkRibbon.widths(stops, spine.size()),
			"amplitude": WAVE_AMPLITUDE * scale,
			"depth": WAVE_DEPTH,
			"mesh_indices": topology["indices"],
			"mesh_colors": topology["colors"],
		})
	return result

## 三角带的**静态**部分：每条截面的顶点色 + 把相邻两条截面缝成条的索引。
##
## 这两样只和采样点数有关，跟时间无关 —— 存进 base_layout 里，动画期间一帧都不用重算。
## 顶点顺序是「一条截面接一条截面」排下来的，所以索引是纯算术：
## 第 s 条截面的第 i 个点编号是 s * count + i，和它下面那条拼成两个三角。
static func mesh_topology(count: int, alpha_scale: float = 1.0) -> Dictionary:
	var boundaries := mesh_boundaries()
	var colors := PackedColorArray()
	colors.resize(boundaries.size() * count)
	for index in boundaries.size():
		var boundary: Array = boundaries[index]
		var color: Color = boundary[1]
		var tinted := Color(color.r, color.g, color.b, float(boundary[2]) * alpha_scale)
		for point in count:
			colors[index * count + point] = tinted
	var indices := PackedInt32Array()
	indices.resize((boundaries.size() - 1) * (count - 1) * 6)
	var cursor := 0
	for band in boundaries.size() - 1:
		var top := band * count
		var bottom := (band + 1) * count
		for point in count - 1:
			indices[cursor] = top + point
			indices[cursor + 1] = top + point + 1
			indices[cursor + 2] = bottom + point
			indices[cursor + 3] = top + point + 1
			indices[cursor + 4] = bottom + point + 1
			indices[cursor + 5] = bottom + point
			cursor += 6
	return {"colors": colors, "indices": indices}

## 截面的边界清单：[带宽比例, 颜色, 透明度]，从 -0.62（带外）到 +0.62（带外）。
## 相邻两条之间由 GPU 插值 —— 所以屏幕上是一条连续的柱面渐变，不是六块硬过渡的色带。
static func mesh_boundaries() -> Array:
	var result: Array = []
	var first: Array = SECTION_TILES[0]
	var last: Array = SECTION_TILES[SECTION_TILES.size() - 1]
	# 上侧淡出：带外透明 → 上沿丝光
	result.append([float(SECTION_GLOW[0]), first[2], 0.0])
	for tile in SECTION_TILES:
		result.append([float((tile as Array)[0]), (tile as Array)[2], float((tile as Array)[3])])
	result.append([float(last[1]), last[2], float(last[3])])
	# 下侧淡出：下沿暗部 → 带外透明
	result.append([float(SECTION_GLOW[1]), last[2], 0.0])
	return result

## 某一时刻的完整几何：骨架 + 波形位移 + 宽度起伏 + **生长裁剪** + 分层拼边。
##
## include_polygons = false 时只产出**绘制要用的那套**（三角带顶点 + 亮边折线），
## 不产出整带 / 截面 / 暗边这些多边形。它们是给测试量几何用的，主循环一个都用不上，
## 而每多算一个 640 点多边形，就是每帧多一次无谓的顶点拼装。
##
## animate_reveal = false 时跳过生长裁剪，整条原样给出。**静态走位测试用它** ——
## 那些断言量的是「绸子走哪儿」（穿面板、避开文字块），跟「长到哪了」无关；
## 让它们跟着时间漂，等于每改一次节奏就得重调一遍断言。
static func frame_geometry(
	base: Array,
	time: float,
	include_polygons: bool = true,
	animate_reveal: bool = true
) -> Array:
	var result: Array = []
	var boundaries := mesh_boundaries()
	for item in base:
		var entry: Dictionary = item
		var spine: PackedVector2Array = entry["spine"]
		var curve_normals: PackedVector2Array = entry["normals"]
		var width_values: PackedFloat32Array = entry["widths"]
		var waved := SilkRibbon.wave(
			spine, curve_normals, time, float(entry.get("amplitude", 0.0)), PERIOD, WAVE_COUNT
		)
		# 宽度也要跟着流动：只推位移的话两条边是平行移动的橡皮筋，读起来像光带在滑。
		var flowed := SilkRibbon.flow_widths(
			width_values, time, PERIOD, WAVE_COUNT, float(entry.get("depth", WAVE_DEPTH))
		)
		var span := Vector2(0.0, 1.0)
		if animate_reveal:
			span = reveal_span(time, float(entry.get("phase", 0.0)))
		var last_index := float(maxi(waved.size() - 1, 0))
		var shaped := shape_reveal(waved, flowed, span.y * last_index, span.x * last_index)
		var shaped_spine: PackedVector2Array = shaped["spine"]
		var shaped_widths: PackedFloat32Array = shaped["widths"]
		var count := shaped_spine.size()
		# 三角带顶点：一条截面接一条截面排下来，顺序必须和 mesh_indices 对齐。
		var vertices := PackedVector2Array()
		vertices.resize(boundaries.size() * count)
		for band in boundaries.size():
			var line := SilkRibbon.edge_of(shaped_spine, curve_normals, shaped_widths, float((boundaries[band] as Array)[0]))
			for point in count:
				vertices[band * count + point] = line[point]
		var ribbon := {
			"key": str(entry.get("key")),
			"alpha": float(entry.get("alpha", 1.0)),
			"reveal": span,
			"revealed": span.y - span.x > 0.0001,
			"spine": shaped_spine,
			"mesh_vertices": vertices,
			"mesh_colors": entry["mesh_colors"],
			"mesh_indices": entry["mesh_indices"],
			"rim_light": _visible_rim(shaped_spine, curve_normals, shaped_widths),
		}
		if include_polygons:
			var sections: Array = []
			for tile in SECTION_TILES:
				sections.append(SilkRibbon.band_of(
					shaped_spine, curve_normals, shaped_widths, float((tile as Array)[0]), float((tile as Array)[1])
				))
			ribbon["body"] = SilkRibbon.band_of(shaped_spine, curve_normals, shaped_widths, -0.5, 0.5)
			ribbon["sections"] = sections
			ribbon["rim_dark"] = SilkRibbon.edge_of(shaped_spine, curve_normals, shaped_widths, 0.5)
		result.append(ribbon)
	return result

## 上沿那道丝光。**只留宽度不为零的那一段**：
## 没长出来的点全叠在尖端上，折线里会多出几百个重合点 —— 画出来是零长度线段，
## 看不见，但抗锯齿那一段会跟着退化，缩小时尖端偶尔冒一个亮点。
static func _visible_rim(
	curve: PackedVector2Array,
	curve_normals: PackedVector2Array,
	width_values: PackedFloat32Array
) -> PackedVector2Array:
	var line := SilkRibbon.edge_of(curve, curve_normals, width_values, -0.5)
	var result := PackedVector2Array()
	for index in line.size():
		if width_values[index] > 0.0:
			result.append(line[index])
	return result

## 静态一帧（整条，不生长）。测试用它量走位，主循环用 base_layout + frame_geometry。
static func layout(canvas: Vector2, focus: Rect2, samples: int = SAMPLES) -> Array:
	return frame_geometry(base_layout(canvas, focus, samples), 0.0, true, false)
