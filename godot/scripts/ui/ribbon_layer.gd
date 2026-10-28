extends Control
## 主菜单的透明丝绸飘带层。
##
## 现在只有**一条**：贴着画面上缘、从上方入画、在右上角出画的淡弧。它只负责「空气在动」。
##
## 为什么砍到只剩一条（2026-10-26）：上一版有三条 —— 一条横穿下半屏的宽主带、一条斜穿
## 画面并绕过面板的细带、加上这条远景弧。三者在屏幕上读成「几根绳在上下抖」，
## 反复调振幅仍然不对：问题不在参数，在**数量**。带子一多，任何一条的摆动都会被读成
## 整体在晃；只留最上面那条最细最淡的，动作就退回到背景里去了。
##
## 走位有一条硬约束：**不许穿过左栏文字块**（见 TEXT_BLOCK / HINT_BLOCK），
## 也不许压到战场面板 —— 这条弧始终在面板上方掠过，面板矩形由 main 回填（set_focus_rect）。
##
## 为什么不是贴图：丝带要跟着画布缩放、跟着面板让路。窗口一改尺寸，贴图就得重新对位；
## 而这里的走位是**按设计稿坐标算、按画布缩放**出来的。
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

## 波形振幅**上限**（设计稿像素）。14 是「绸子被空气托了一下」的上限。
## 上一版取 20，一条带在 13 秒里上下摆掉将近两个来回，读起来是「一根被拽着的绳」。
const WAVE_AMPLITUDE := 14.0

## 振幅下限（设计稿像素）。细到只剩 2px 的线头也得留一点呼吸 ——
## 完全静止的话，整条弧会读成一张贴死的图，而不是飘在空气里的绸子。
const WAVE_AMPLITUDE_MIN := 5.0

## **振幅 = 这条带自己的宽度 × 这个系数**（再夹到上面两个值之间）。
##
## 这是「丝线动得难看」的真正修法：同一条 20px 振幅发给三种宽度完全不同的带，
## 84px 宽的绸面被推 20px 是「一块布在起伏」，17px 宽的细线被推 20px 就是
## 「一根线在抽筋」。位移必须和它自己的尺度成比例，细线才只是轻轻荡一下。
## 0.22 ≈ 带宽的 22%，是一条带「托起来」而「不折断」的比例。
const WAVE_AMPLITUDE_PER_WIDTH := 0.22

## 沿整条带传播的波数。0.8 波 = **整条带最多一个隆起**，中间没有反曲点。
## 上一版 1.35 波：一条带跨屏能数出两三个波峰，那是绳子的形状，不是绸子的 ——
## 屏幕上会读成「这条线在上下抖」，而不是「绸子在流」。
const WAVE_COUNT := 0.8

## 宽度起伏深度：±6%。上一版 ±14%，在细线上表现为「一阵变粗一阵变细」，
## 像信号不良的电视线。宽度起伏只该是位移的陪衬，不该自己成为一条节奏。
const WAVE_DEPTH := 0.06

## 一次「生长」循环的长度。**必须是波形周期（PERIOD）的整数倍**：
## 两者同时闭合，绸子重来的那一刻波形相位也在起点上，画面不会出现两套节奏互相错拍。
## 取 3 倍（39s）：只剩一条带之后，「停留」必须占掉绝大部分时间 —— 这条弧是背景，
## 老在长/老在抽，读者的眼睛就会被它带走。39s 里只有约 12s 在动。
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

## 所有文字禁入区。丝带走位必须从两块之间的空档（y ≈ 660 ~ 890）横穿过去 ——
## 这条约束是上一版主带留下的，现在这条弧全程在画面上方，本来就碰不到；留在这里是因为
## 「绸子不许压字」是这个模块最重要的性质，将来加带子时它得先在。
const KEEP_OUT := [TEXT_BLOCK, HINT_BLOCK]

## 这条弧的最低点（设计稿像素）。它决定了弧「探进来多深」，也是挤压保险的基准：
## 可用纵向空间不足 ARC_REACH 时，按比例压扁，弧始终待在面板上方。
const ARC_REACH := 92.0

## 这条弧的最低点必须比面板顶再高这么多（设计稿像素）。见 base_layout 里的 strip。
const PANEL_CLEARANCE := 60.0

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

## 这条带的走位与宽度（设计稿坐标 / 设计稿像素）。
##
## 只剩一条，`RIBBON_SPECS` 仍然保留成数组：走位、截面、生长循环都是按「一组带」写的，
## 将来真要加第二条（比如重新做一次缝合），只在这里加一项、在 paths 里补一条曲线即可，
## 绘制端（一次三角带）一行都不用动。
##
## alpha 0.55：远景带该有的存在感 —— 看得见，但读不出边界。再高就会开始抢面板。
const RIBBON_SPECS := [
	{
		"key": "accent",
		"alpha": 0.55,
		"phase": 30.0,
		"stops": [[0.0, 2.0], [0.30, 17.0], [0.70, 13.0], [1.0, 3.0]],
	},
]

## phase = 这条带生长循环的起点偏移（秒）。只剩一条之后它仍然要紧：
## 必须让「菜单刚打开」落在**停留段**里。否则一进菜单是一片空背景，绸子要等十几秒
## 才从画外探进来 —— 那是「漏了」，不是「在动」。
##
## 现值 30.0（39s 一个循环）：开场整条 → 4.5s 开始被抽走 → 8s 抽完 → 9s 起从画外重新长回来
## → 17s 长满，之后一直停在画面上。菜单停在主界面的时候，看到的绝大多数时间是「静止的一条淡弧」。

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

	# 走位：从画面**上缘**探进来 → 贴着上缘向右滑 → 在右上角出画。
	# 全程 y ≤ 92（设计稿），离面板顶（314）还有 220px 的余量 —— 这是「不压面板」的来源。
	#
	# 下面那几行不是排版手段，而是**保险**：面板一旦被改到更靠上的位置，
	# 这条弧会被压进「画面上缘 ~ 面板顶」那条窄带里（同比例压扁），
	# 而不是从面板上横穿过去、也不是被推出画面外消失。
	var accent_path := PackedVector2Array([
		Vector2(960.0, -120.0),
		Vector2(1280.0, 30.0),
		Vector2(1620.0, 92.0),
		Vector2(1960.0, 42.0),
		Vector2(2140.0, -40.0),
	])
	var strip := f.position.y - PANEL_CLEARANCE
	if strip < ARC_REACH:
		var squeeze := clampf(strip / ARC_REACH, 0.0, 1.0)
		for index in accent_path.size():
			accent_path[index].y *= squeeze

	var paths := {"accent": accent_path}

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
			"amplitude": _amplitude_for(stops, scale),
			"depth": WAVE_DEPTH,
			"mesh_indices": topology["indices"],
			"mesh_colors": topology["colors"],
		})
	return result

## 这条带的波形振幅：**跟它自己的最宽处成比例**，再夹在上下限之间。
##
## stops 里的宽度已经是屏幕像素（base_layout 里乘过 scale），所以上下限也先乘 scale。
## 现值：最宽 17px × 0.22 ≈ 3.7，落到下限 5 —— 屏幕上只是「轻轻荡一下」。
## 比例而不是常数，是上一版「一条线在抽筋」的修法：位移必须和带子自己的尺度成比例。
static func _amplitude_for(stops: Array, scale: float) -> float:
	var widest := 0.0
	for stop in stops:
		widest = maxf(widest, float((stop as Array)[1]))
	return clampf(
		widest * WAVE_AMPLITUDE_PER_WIDTH,
		WAVE_AMPLITUDE_MIN * scale,
		WAVE_AMPLITUDE * scale
	)

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
