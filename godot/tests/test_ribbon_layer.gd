extends "res://tests/test_base.gd"

# 丝带层的走位守卫。
#
# 丝带不是装饰，是**缝合线**：它必须从左侧标题栏横穿到右侧战场面板，并且真的钻到
# 面板底下再出来。走位偏一点，丝带就从面板旁边绕过去 —— 屏幕上看着还是一张挺好看
# 的图，但左右两块仍然是孤岛，改版就白做了。
#
# 这里守的都是「读不出来的失败」：
#   · 有没有真的穿过面板矩形（test_main_ribbon_crosses_the_panel）
#   · 三条丝带是不是都还活着（层被删掉一条，画面只是变稀，不会报错）
#   · 有没有跑出画面上下边界（跑出去会突然截断在视口边）
#   · 缩放后走位是否还贴着面板（窗口改了尺寸，丝带留在原地）

const RibbonLayer = preload("res://scripts/ui/ribbon_layer.gd")

const CANVAS := Vector2(1600.0, 900.0)
const PANEL := Rect2(1172.0, 262.0, 358.0, 392.0)

func _all_finite(points: PackedVector2Array) -> bool:
	for point in points:
		if not (is_finite(point.x) and is_finite(point.y)):
			return false
	return true

func _bounds(points: PackedVector2Array) -> Rect2:
	var min_point := Vector2(INF, INF)
	var max_point := Vector2(-INF, -INF)
	for point in points:
		min_point.x = minf(min_point.x, point.x)
		min_point.y = minf(min_point.y, point.y)
		max_point.x = maxf(max_point.x, point.x)
		max_point.y = maxf(max_point.y, point.y)
	return Rect2(min_point, max_point - min_point)

func _ribbon(layout: Array, key: String) -> Dictionary:
	for item in layout:
		if str((item as Dictionary).get("key")) == key:
			return item
	return {}

func test_every_ribbon_layer_is_present() -> void:
	var layout := RibbonLayer.layout(CANVAS, PANEL)
	eq(layout.size(), 3, "三条丝带：主带 / 从面板左缘吐出的细带 / 上方远景带")
	var keys: Array = []
	for item in layout:
		keys.append(str((item as Dictionary).get("key")))
	for key in ["main", "thin", "accent"]:
		check(keys.has(key), "缺少丝带层：%s" % key)

func test_every_ribbon_has_all_its_layers() -> void:
	# 「透明丝绸」= 整带底 + 截面细带 + 上下两条沿边线。少掉截面那层，
	# 丝带就退回成一块半透明的色块 —— 屏幕上看不出错，只是不再像丝绸。
	for item in RibbonLayer.layout(CANVAS, PANEL):
		var ribbon: Dictionary = item
		for key in ["spine", "body", "rim_light", "rim_dark"]:
			check(ribbon.has(key), "丝带 %s 缺少 %s 层" % [str(ribbon.get("key")), key])
			var points: PackedVector2Array = ribbon[key]
			gt(float(points.size()), 8.0, "丝带 %s 的 %s 层点太少" % [str(ribbon.get("key")), key])
			check(_all_finite(points), "丝带 %s 的 %s 层出现 NaN" % [str(ribbon.get("key")), key])

func test_section_tiles_cover_the_band_without_gaps_or_overlap() -> void:
	# 截面是「互不重叠地铺满整条带」。留缝会看到背景透出一条黑线；
	# 重叠会让相邻两条的透明度叠起来，带宽中间冒出一条比两边更亮的横杠。
	var tiles: Array = RibbonLayer.SECTION_TILES
	gt(float(tiles.size()), 3.0, "截面至少要 4 条，否则渐变是台阶")
	near(float((tiles[0] as Array)[0]), -0.5, 0.001, "截面必须从 -0.5 开始（贴住上沿）")
	near(float((tiles[tiles.size() - 1] as Array)[1]), 0.5, 0.001, "截面必须到 +0.5 结束（贴住下沿）")
	for index in range(1, tiles.size()):
		near(float((tiles[index] as Array)[0]), float((tiles[index - 1] as Array)[1]), 0.001,
			"第 %d 条截面与上一条之间有缝/重叠" % index)

func test_sections_are_lit_on_one_side_and_shadowed_on_the_other() -> void:
	# 上沿亮、下沿暗 —— 这是丝绸「柱面受光」的方向。反过来（下亮上暗）屏幕上就是
	# 一条倒扣的管子，看着说不上哪里错但就是不对。
	var tiles: Array = RibbonLayer.SECTION_TILES
	var top: Color = (tiles[0] as Array)[2]
	var bottom: Color = (tiles[tiles.size() - 1] as Array)[2]
	gt(top.get_luminance(), bottom.get_luminance() * 2.0,
		"上沿必须明显比下沿亮（上 %.2f / 下 %.2f）" % [top.get_luminance(), bottom.get_luminance()])
	gt(float((tiles[0] as Array)[3]), float((tiles[tiles.size() - 1] as Array)[3]) * 0.8,
		"上沿高光的透明度不能比下沿暗面低太多，否则亮边看不见")

func test_sections_are_drawn_inside_the_band() -> void:
	# 截面是沿脊线切出来的，必须全部落在整带轮廓内 —— 飘出去就是带子边上浮着一条彩色断线。
	for item in RibbonLayer.layout(CANVAS, PANEL):
		var ribbon: Dictionary = item
		var body: PackedVector2Array = ribbon["body"]
		var body_bounds := _bounds(body)
		for section in ribbon["sections"]:
			var points: PackedVector2Array = section
			check(_all_finite(points), "截面出现 NaN")
			var bounds := _bounds(points)
			check(bounds.position.x >= body_bounds.position.x - 0.5
				and bounds.position.y >= body_bounds.position.y - 0.5
				and bounds.end.x <= body_bounds.end.x + 0.5
				and bounds.end.y <= body_bounds.end.y + 0.5,
				"丝带 %s 有一条截面跑出了整带轮廓" % str(ribbon.get("key")))

func test_main_ribbon_crosses_the_panel() -> void:
	# 只擦到面板的角不算穿过：必须有一段落在面板内部，并且明显地从左边进、右边出。
	var ribbon := _ribbon(RibbonLayer.layout(CANVAS, PANEL), "main")
	var spine: PackedVector2Array = ribbon.get("spine", PackedVector2Array())
	var inside := 0
	var left_of := 0
	var right_of := 0
	for point in spine:
		if PANEL.has_point(point):
			inside += 1
		if point.x < PANEL.position.x:
			left_of += 1
		if point.x > PANEL.end.x and point.y > PANEL.position.y:
			right_of += 1
	gt(float(inside), 6.0, "主带必须从面板底下穿过（内部采样点只有 %d 个）" % inside)
	gt(float(left_of), 20.0, "主带必须从面板左侧一路过来")
	gt(float(right_of), 10.0, "主带必须从面板右侧/下方再钻出来，否则收势断在面板后面")

func test_thin_ribbon_exits_from_the_panel_left_edge() -> void:
	# 设计里细带的「妙处」是从面板左缘吐出来 —— 这一笔决定面板像不像浮在绸子上面。
	var ribbon := _ribbon(RibbonLayer.layout(CANVAS, PANEL), "thin")
	var spine: PackedVector2Array = ribbon.get("spine", PackedVector2Array())
	var inside := 0
	var below_left := 0
	for point in spine:
		if PANEL.has_point(point):
			inside += 1
		if point.x < PANEL.position.x and point.y > PANEL.position.y:
			below_left += 1
	gt(float(inside), 4.0, "细带必须擦过面板（内部采样点只有 %d 个）" % inside)
	gt(float(below_left), 20.0, "细带必须从面板左侧拖出去，而不是停在面板里")

func test_ribbons_stay_inside_the_vertical_frame() -> void:
	# 上下跑出画面会在视口边缘出现一条突然截断的宽带，像贴图错位。
	for item in RibbonLayer.layout(CANVAS, PANEL):
		var body: PackedVector2Array = (item as Dictionary)["body"]
		var bounds := _bounds(body)
		gt(bounds.position.y, -CANVAS.y * 0.25, "丝带 %s 向上跑出画面太多" % str((item as Dictionary).get("key")))
		lt(bounds.end.y, CANVAS.y * 1.30, "丝带 %s 向下跑出画面太多" % str((item as Dictionary).get("key")))

func test_main_ribbon_enters_and_leaves_the_frame() -> void:
	# 两端必须在画面外：起于画外、收于画外，才读得出「绸子从别处飘过这里」。
	var spine: PackedVector2Array = _ribbon(RibbonLayer.layout(CANVAS, PANEL), "main").get("spine", PackedVector2Array())
	var bounds := _bounds(spine)
	lt(bounds.position.x, 0.0, "主带必须从画面左外侧入画")
	gt(bounds.end.x, CANVAS.x, "主带必须收到画面右外侧出画")

func test_main_ribbon_is_much_wider_than_the_thin_one() -> void:
	# 两条带的关系必须一眼分得清：主带是「面」，细带是「线」。宽度接近就没有层次。
	var main_body: PackedVector2Array = _ribbon(RibbonLayer.layout(CANVAS, PANEL), "main")["body"]
	var thin_body: PackedVector2Array = _ribbon(RibbonLayer.layout(CANVAS, PANEL), "thin")["body"]
	gt(_widest(main_body), _widest(thin_body) * 1.6, "主带最宽处必须明显宽于细带")

func _widest(body: PackedVector2Array) -> float:
	var widest := 0.0
	var count := body.size() / 2
	for index in count:
		widest = maxf(widest, body[index].distance_to(body[body.size() - 1 - index]))
	return widest

func test_layout_falls_back_when_no_panel_rect_is_known() -> void:
	# 菜单刚建起来时控件还没排版，拿不到面板矩形 —— 这时不能画出空丝带。
	var layout := RibbonLayer.layout(CANVAS, Rect2())
	eq(layout.size(), 3, "没有面板矩形时仍要给出三条丝带（走位退回设计稿坐标）")
	var fallback := RibbonLayer.default_focus(CANVAS)
	for item in layout:
		check(_all_finite((item as Dictionary)["body"] as PackedVector2Array),
			"回落走位不能出现 NaN")
	var inside := 0
	for point in _ribbon(layout, "main").get("spine", PackedVector2Array()):
		if fallback.has_point(point):
			inside += 1
	gt(float(inside), 4.0, "回落的走位也必须穿过回落面板矩形（否则首次打开就没有缝合效果）")

func test_layout_scales_with_the_canvas() -> void:
	# 窗口从 1600×900 换到 3200×1800，丝带必须整体放大一倍。
	var small: PackedVector2Array = _ribbon(RibbonLayer.layout(CANVAS, PANEL), "main")["body"]
	var big_canvas := CANVAS * 2.0
	var big_panel := Rect2(PANEL.position * 2.0, PANEL.size * 2.0)
	var big: PackedVector2Array = _ribbon(RibbonLayer.layout(big_canvas, big_panel), "main")["body"]
	var small_bounds := _bounds(small)
	var big_bounds := _bounds(big)
	near(big_bounds.size.x / small_bounds.size.x, 2.0, 0.08, "横向必须按画布等比放大")
	near(big_bounds.size.y / small_bounds.size.y, 2.0, 0.08, "纵向必须按画布等比放大")

# ---------- 动画：会动、但不许在接缝上跳 ----------

func test_animated_frames_close_their_loop() -> void:
	# 循环动画的两条硬指标：一个周期后必须回到同一帧（不跳），
	# 半周期时必须已经明显不同（不是一帧静止画面）。
	# 这里量的是**波形**：生长（reveal）另有一组测试，所以关掉它单独看波。
	var base := RibbonLayer.base_layout(CANVAS, PANEL, 120)
	var start: Array = RibbonLayer.frame_geometry(base, 0.0, true, false)
	var looped: Array = RibbonLayer.frame_geometry(base, RibbonLayer.PERIOD, true, false)
	var middle: Array = RibbonLayer.frame_geometry(base, RibbonLayer.PERIOD * 0.5, true, false)
	var start_body: PackedVector2Array = start[0]["body"]
	var looped_body: PackedVector2Array = looped[0]["body"]
	var middle_body: PackedVector2Array = middle[0]["body"]
	eq(looped_body.size(), start_body.size(), "一个周期后顶点数不能变")
	var moved := 0.0
	for index in start_body.size():
		near(looped_body[index].distance_to(start_body[index]), 0.0, 0.02,
			"第 %d 点在一个周期后没有回到原位（循环会跳）" % index)
		moved = maxf(moved, middle_body[index].distance_to(start_body[index]))
	gt(moved, 1.0, "半个周期时丝带必须已经移动（当前最大位移 %.2f）" % moved)

func test_animation_pins_the_ribbon_ends() -> void:
	# 丝带的两端落在画面外。端点如果跟着波形动，画面边缘会看到绸子在原地抽搐。
	# 生长会主动改可见长度，所以这里关掉 reveal，只量波形对端点的处理。
	var base := RibbonLayer.base_layout(CANVAS, PANEL, 90)
	var start: Array = RibbonLayer.frame_geometry(base, 0.0, true, false)
	var later: Array = RibbonLayer.frame_geometry(base, 4.3, true, false)
	for index in start.size():
		var before: PackedVector2Array = start[index]["spine"]
		var after: PackedVector2Array = later[index]["spine"]
		near(before[0].distance_to(after[0]), 0.0, 0.02,
			"丝带 %s 的起点被推动了" % str(start[index]["key"]))
		near(before[before.size() - 1].distance_to(after[after.size() - 1]), 0.0, 0.02,
			"丝带 %s 的终点被推动了" % str(start[index]["key"]))

# ---------- 走位：不许穿过左栏文字块 ----------

func _text_block_screen() -> Rect2:
	var scale := minf(CANVAS.x / 1920.0, CANVAS.y / 1080.0)
	var origin := (CANVAS - Vector2(1920.0, 1080.0) * scale) * 0.5
	return Rect2(origin + RibbonLayer.TEXT_BLOCK.position * scale, RibbonLayer.TEXT_BLOCK.size * scale)

func _keep_out_screen() -> Array:
	# 左栏有两块字：上方标题/说明块，下方特性标签 + 操作提示行。两块之间是空的 ——
	# 那才是绸子可以横穿过去的通道。只挡上面一块的话，丝带会从「左键 点击移动…」
	# 那一行字上划过去，而屏幕上只会觉得「这行字有点花」。
	var scale := minf(CANVAS.x / 1920.0, CANVAS.y / 1080.0)
	var origin := (CANVAS - Vector2(1920.0, 1080.0) * scale) * 0.5
	var result: Array = []
	for rect in RibbonLayer.KEEP_OUT:
		var design: Rect2 = rect
		result.append(Rect2(origin + design.position * scale, design.size * scale))
	return result

func test_ribbons_never_cross_any_text_block() -> void:
	# 上一版只挡了标题块，结果主带正好压在底部那行操作提示上 —— 这是真实发生过的缺陷。
	var blocks := _keep_out_screen()
	gt(float(blocks.size()), 1.0, "左栏有两块字，只挡一块会漏掉底部提示行")
	for item in RibbonLayer.layout(CANVAS, PANEL):
		var ribbon: Dictionary = item
		var spine: PackedVector2Array = ribbon.get("spine", PackedVector2Array())
		for block in blocks:
			var hits := 0
			for point in spine:
				if (block as Rect2).has_point(point):
					hits += 1
			eq(hits, 0, "丝带 %s 有 %d 个采样点落在文字块 %s 里" % [str(ribbon.get("key")), hits, str(block)])
		var body: PackedVector2Array = ribbon.get("body", PackedVector2Array())
		for block in blocks:
			var body_hits := 0
			for point in body:
				if (block as Rect2).has_point(point):
					body_hits += 1
			eq(body_hits, 0, "丝带 %s 的轮廓有 %d 个顶点压在文字块 %s 上"
				% [str(ribbon.get("key")), body_hits, str(block)])

# ---------- 视觉：读起来是丝绸，不是一条灰纸带 ----------

func test_section_colors_stay_warm_and_never_sink_to_shadow() -> void:
	# 深色原画上，「下沿暗面」用近黑色是最容易犯的错：整条带会被读成一道阴影/污渍，
	# 而不是一块会透光的绸子。暗面的下限是「暖棕」，不是「黑」。
	for tile in RibbonLayer.SECTION_TILES:
		var color: Color = (tile as Array)[2]
		check(color.r > color.g and color.g > color.b,
			"截面颜色必须偏暖（r>g>b），当前 %s 读起来是灰的" % str(color))
		gt(color.get_luminance(), 0.18,
			"截面颜色太暗（亮度 %.2f），会读成阴影而不是丝绸" % color.get_luminance())

func test_rim_highlight_dominates_the_dark_edge() -> void:
	# 「硬边纸带」的成因之一：下沿暗面压过了上沿丝光，两条边一样重，带子就变成一块带轮廓的纸。
	# 边现在已经不是折线，而是截面自己的首末两档 —— 所以这条量的是那两档的权重差：
	# 上沿必须更亮、也更实；下沿只是把轮廓收住。
	var boundaries: Array = RibbonLayer.mesh_boundaries()
	var top: Array = boundaries[1]
	var bottom: Array = boundaries[boundaries.size() - 2]
	var top_light: float = (top[1] as Color).get_luminance()
	var bottom_light: float = (bottom[1] as Color).get_luminance()
	gt(top_light, bottom_light * 2.0,
		"上沿必须明显比下沿亮（上 %.2f / 下 %.2f）" % [top_light, bottom_light])
	gt(float(top[2]), float(bottom[2]) * 1.8,
		"上沿丝光不能和下沿暗面一样实（亮 %.3f / 暗 %.3f）" % [float(top[2]), float(bottom[2])])

func test_the_band_edge_fades_out_instead_of_being_cut() -> void:
	# 只有一条 1px 实线 = 「抠出来」的硬边，放大就露馅。现在让截面自己向外淡出：
	# 判据是「带宽边界那一档和带外那一档之间有明显落差」—— 有落差才有那道丝光的收束，
	# 落差太小就成了模糊的一条渐隐带，看着发虚。
	var boundaries: Array = RibbonLayer.mesh_boundaries()
	var last := boundaries.size() - 1
	var top_inside: float = float((boundaries[1] as Array)[2])
	var top_outside: float = float((boundaries[0] as Array)[2])
	var bottom_inside: float = float((boundaries[last - 1] as Array)[2])
	var bottom_outside: float = float((boundaries[last] as Array)[2])
	near(top_outside, 0.0, 0.001, "上沿带外那一档必须完全透明，否则带子上方会多一条灰边")
	near(bottom_outside, 0.0, 0.001, "下沿带外那一档必须完全透明")
	gt(top_inside, 0.05, "上沿丝光太淡（%.3f），淡出段读不出一条边" % top_inside)
	gt(top_inside - top_outside, 0.05,
		"上沿内外落差太小（%.3f），看起来是一条模糊渐隐带而不是丝光" % (top_inside - top_outside))
	gt(bottom_inside, 0.0, "下沿暗面完全透明的话，带子下缘会直接切在背景上")

func test_ribbons_never_dip_out_of_frame_and_come_back() -> void:
	# 之前主带在 x≈780 处掉到画布下方 (y=1122) 再折回 y=922 —— 带子被视口底边切掉一截
	# 又突然接回来，屏幕上就是左边缘那个「凿出来的直角」。
	#
	# 允许：进画（从画外飘进来）+ 出画（收出去），各一次。
	# 禁止：已经进过画之后又跑出去、再折回来 —— 那才是挖坑。
	for item in RibbonLayer.layout(CANVAS, PANEL):
		var spine: PackedVector2Array = (item as Dictionary)["spine"]
		var key := str((item as Dictionary).get("key"))
		var entered := false
		var left_side := 0
		for index in spine.size():
			var inside := spine[index].y <= CANVAS.y and spine[index].y >= 0.0
			if inside:
				eq(left_side, 0, "丝带 %s 在第 %d 点出界后（%s）又折回来了，会看到硬切口"
					% [key, index, "下沿" if left_side > 0 else "上沿"])
				entered = true
			elif entered and left_side == 0:
				left_side = 1 if spine[index].y > CANVAS.y else -1

func test_ribbon_curves_have_no_visible_kink() -> void:
	# 走位的控制点如果挤在一起，向心样条会在那里拧出一个尖。屏幕上只在亮边上多一个
	# 「V」形小折，说不清哪里错但就是觉得硬。
	for item in RibbonLayer.layout(CANVAS, PANEL):
		var spine: PackedVector2Array = (item as Dictionary)["spine"]
		var worst := 0.0
		var worst_at := 0
		for index in range(2, spine.size() - 2):
			var before := (spine[index] - spine[index - 1]).normalized()
			var after := (spine[index + 1] - spine[index]).normalized()
			var angle := rad_to_deg(absf(before.angle_to(after)))
			if angle > worst:
				worst = angle
				worst_at = index
		lt(worst, 4.0, "丝带 %s 在第 %d 点有 %.2f° 的折角"
			% [str((item as Dictionary).get("key")), worst_at, worst])

func test_ribbons_never_cross_the_title_block() -> void:
	# 绸子划过书法或说明文字，字就废了。这是本改版最容易被「顺手调一下走位」破坏的性质：
	# 走位偏 100px，屏幕上还只是一张挺好看的图，只是标题上多了一道斜光 —— 没人会当成 bug 报。
	var block := _text_block_screen()
	for item in RibbonLayer.layout(CANVAS, PANEL):
		var ribbon: Dictionary = item
		var spine: PackedVector2Array = ribbon.get("spine", PackedVector2Array())
		var hits := 0
		for point in spine:
			if block.has_point(point):
				hits += 1
		eq(hits, 0, "丝带 %s 有 %d 个采样点落在左栏文字块里（会压住标题/说明）"
			% [str(ribbon.get("key")), hits])

func test_ribbon_bodies_stay_out_of_the_title_block_too() -> void:
	# 只看脊线不够：一条 108px 宽的带子脊线擦着边过，半边照样压在字上。
	# 轮廓比脊线宽，所以这里量的是「轮廓的外接框有没有和文字块相交」之外的更强条件：
	# 轮廓上不许有点落进文字块。
	var block := _text_block_screen()
	for item in RibbonLayer.layout(CANVAS, PANEL):
		var ribbon: Dictionary = item
		var body: PackedVector2Array = ribbon.get("body", PackedVector2Array())
		var hits := 0
		for point in body:
			if block.has_point(point):
				hits += 1
		eq(hits, 0, "丝带 %s 的轮廓有 %d 个顶点压在文字块上"
			% [str(ribbon.get("key")), hits])

func test_the_two_stitching_ribbons_enter_the_panel_from_opposite_sides() -> void:
	# 面板被绸子「扎」在画面里，靠的是两条带各钻一次板底、并且从**不同**两侧进出。
	# 两条都从左进右出的话，面板只是被两条平行线穿过，缝合感没有了。
	var layout := RibbonLayer.layout(CANVAS, PANEL)
	var main_spine: PackedVector2Array = _ribbon(layout, "main").get("spine", PackedVector2Array())
	var thin_spine: PackedVector2Array = _ribbon(layout, "thin").get("spine", PackedVector2Array())
	var main_entry := _first_inside(main_spine)
	var thin_entry := _first_inside(thin_spine)
	gt(main_entry.y, PANEL.position.y + PANEL.size.y * 0.45,
		"主带必须从面板下半部钻进去（当前入点在 y=%.0f）" % main_entry.y)
	lt(thin_entry.y, PANEL.position.y + PANEL.size.y * 0.45,
		"细带必须从面板上半部钻进去（当前入点在 y=%.0f）" % thin_entry.y)

func _first_inside(spine: PackedVector2Array) -> Vector2:
	for point in spine:
		if PANEL.has_point(point):
			return point
	return Vector2(-1.0, -1.0)

# ---------- 绘制路径：一次三角带，而不是每帧三角化 ----------

func test_mesh_boundaries_cover_the_band_and_bleed_outward() -> void:
	# 三角带要一次画完「背景 → 丝光 → 暗面 → 背景」的整个过渡。
	# 起点必须落在 -0.5 之外（否则带上沿是一条突然开始的硬边），终点同理；
	# 中间必须严格递增且首尾相接（留缝会露出背景色的一条细线）。
	var boundaries: Array = RibbonLayer.mesh_boundaries()
	gt(float(boundaries.size()), 5.0, "截面边界太少")
	lt(float((boundaries[0] as Array)[0]), -0.5, "三角带没有从上沿外开始淡入")
	gt(float((boundaries[boundaries.size() - 1] as Array)[0]), 0.5, "三角带没有在下沿外淡出")
	near(float((boundaries[0] as Array)[2]), 0.0, 0.001, "带外那一档必须完全透明")
	near(float((boundaries[boundaries.size() - 1] as Array)[2]), 0.0, 0.001, "带外那一档必须完全透明")
	for index in range(1, boundaries.size()):
		gt(float((boundaries[index] as Array)[0]), float((boundaries[index - 1] as Array)[0]),
			"第 %d 条边界没有比上一条更靠下，三角带会翻面" % index)

func test_mesh_topology_matches_its_vertex_count() -> void:
	# 索引越界在 Godot 里不报错，只画出一片乱三角 —— 屏幕上看着像丝带被撕开了。
	var count := 96
	var topology := RibbonLayer.mesh_topology(count)
	var vertices := (topology["indices"] as PackedInt32Array).size()
	eq((topology["colors"] as PackedColorArray).size(), RibbonLayer.mesh_boundaries().size() * count,
		"顶点色数量和「边界数 × 采样点」对不上")
	eq(vertices % 6, 0, "索引数必须是完整的三角形（6 的倍数）")
	for index in topology["indices"]:
		check(index >= 0 and index < RibbonLayer.mesh_boundaries().size() * count,
			"索引 %d 越界（顶点只有 %d 个）" % [index, RibbonLayer.mesh_boundaries().size() * count])

func test_mesh_colors_are_static_across_time() -> void:
	# 顶点色和索引只跟采样点数有关。要是每帧重算，动画就白优化了 ——
	# 这条守的是「它们被缓存进 base_layout」这件事本身。
	var base := RibbonLayer.base_layout(CANVAS, PANEL, 80)
	for item in base:
		var ribbon: Dictionary = item
		check(ribbon.has("mesh_indices"), "base 里没有缓存索引")
		check(ribbon.has("mesh_colors"), "base 里没有缓存顶点色")
		var expected := RibbonLayer.mesh_topology(80, float(ribbon["alpha"]))
		eq((ribbon["mesh_indices"] as PackedInt32Array).size(),
			(expected["indices"] as PackedInt32Array).size(), "索引长度和采样点数对不上")

func test_draw_path_does_not_build_polygons() -> void:
	# 主循环走 include_polygons = false。这条守的是**性能契约**：
	# 谁要是为了「顺手」在绘制路径里又把整带 / 截面拼出来，每帧就多一次顶点拼装，
	# 屏幕上什么都看不出来，只是又开始掉帧。
	var base := RibbonLayer.base_layout(CANVAS, PANEL, 80)
	var lightweight: Array = RibbonLayer.frame_geometry(base, 2.5, false)
	for item in lightweight:
		var ribbon: Dictionary = item
		check(not ribbon.has("sections"), "绘制路径不该拼截面多边形")
		check(not ribbon.has("body"), "绘制路径不该拼整带多边形")
		check(not ribbon.has("rim_dark"), "绘制路径不该拼暗边折线")
		check(ribbon.has("mesh_vertices"), "绘制路径必须给出三角带顶点")
		check(ribbon.has("rim_light"), "绘制路径必须给出亮边折线")
		eq((ribbon["mesh_vertices"] as PackedVector2Array).size(),
			(ribbon["mesh_colors"] as PackedColorArray).size(),
			"三角带顶点数和顶点色数必须相等，否则绘制会错位")

func test_mesh_vertices_stay_finite_for_every_frame() -> void:
	# 顶点带 NaN 时 Godot 不报错，整层直接消失 —— 主菜单上就是「丝带突然没了」。
	var base := RibbonLayer.base_layout(CANVAS, PANEL, 64)
	for step in 7:
		var frame: Array = RibbonLayer.frame_geometry(base, RibbonLayer.PERIOD * float(step) / 7.0, false)
		for item in frame:
			check(_all_finite((item as Dictionary)["mesh_vertices"] as PackedVector2Array),
				"t=%.2f 时三角带顶点出现 NaN" % (RibbonLayer.PERIOD * float(step) / 7.0))

# ---------- 流畅度：每帧小位移，半周期大位移，接缝处不跳 ----------

func _max_point_move(first: Array, second: Array) -> float:
	var worst := 0.0
	for index in first.size():
		var a: PackedVector2Array = (first[index] as Dictionary)["mesh_vertices"]
		var b: PackedVector2Array = (second[index] as Dictionary)["mesh_vertices"]
		for point in a.size():
			worst = maxf(worst, a[point].distance_to(b[point]))
	return worst

func test_motion_is_slow_per_frame_but_visible_over_half_a_period() -> void:
	# 「流畅」和「看得见在动」是一对互相拉扯的指标，必须同时量：
	#   每帧位移太大 → 60fps 下也像在抽搐；
	#   半周期总位移太小 → 整条丝带静止，动画白做。
	# 实测基线（1600×900）：单帧 0.164px，半周期 41.15px。
	# 生长（头部推进）本来就走得比波快，那是另一组测试；这里只量波形本身。
	var base := RibbonLayer.base_layout(CANVAS, PANEL, 96)
	var step := 1.0 / 60.0
	var start: Array = RibbonLayer.frame_geometry(base, 0.0, false, false)
	var next_frame: Array = RibbonLayer.frame_geometry(base, step, false, false)
	var half: Array = RibbonLayer.frame_geometry(base, RibbonLayer.PERIOD * 0.5, false, false)
	var per_frame := _max_point_move(start, next_frame)
	var per_half := _max_point_move(start, half)
	lt(per_frame, 2.0, "单帧位移 %.3fpx 太大，60fps 下会看成抽搐" % per_frame)
	gt(per_half, 8.0, "半周期只移动了 %.2fpx，丝带看起来是静止的" % per_half)

func test_the_loop_seam_cannot_be_told_apart_from_any_other_frame() -> void:
	# 循环最容易露馅的地方：跨过周期那一刻的位移和别处不一样，屏幕上就是「弹一下」。
	# 量的是「最后一帧 → 第一帧」这一步是否和整段的最大单帧位移同量级。
	# 只比较位置相等（上一组测试）抓不到这个 —— 位置可以相等而速度不连续。
	var base := RibbonLayer.base_layout(CANVAS, PANEL, 96)
	var step := 1.0 / 60.0
	var last: Array = RibbonLayer.frame_geometry(base, RibbonLayer.PERIOD - step, false, false)
	var wrapped: Array = RibbonLayer.frame_geometry(base, 0.0, false, false)
	var seam := _max_point_move(last, wrapped)
	var typical := _max_point_move(
		RibbonLayer.frame_geometry(base, RibbonLayer.PERIOD * 0.25, false, false),
		RibbonLayer.frame_geometry(base, RibbonLayer.PERIOD * 0.25 + step, false, false)
	)
	lt(absf(seam - typical), maxf(typical * 0.35, 0.02),
		"接缝那一步位移 %.4fpx 和普通帧 %.4fpx 差太多，循环会跳" % [seam, typical])

# ---------- 生长：从画外一点点长出来，而不是整条一起动 ----------
#
# 上一版的「流动」是**整条同时起伏**：波形一推，从头到尾一起晃。屏幕上看不到「来处」，
# 绸子像一张已经铺好的贴纸在原地抖。改成「从画外长出来」之后，能看见的是**头部在推进** ——
# 这些断言守的就是这件事：
#   · 周期起点长度必须是 0（不是整条突然出现）
#   · 生长单调、每帧推进量可见但不抽搐
#   · 还没长出来的那段必须真的没有宽度（否则是一条被齐口切断的带子）
#   · 头部要收成尖（线头），不是断口
#   · 三条带不许同时长（那又变回「一起动」）

func _body_widths(body: PackedVector2Array) -> PackedFloat32Array:
	# 带轮廓 = 去程 n 点 + 回程 n 点，所以第 i 点的带宽就是首尾对称两点的距离。
	var count := body.size() / 2
	var widths := PackedFloat32Array()
	widths.resize(count)
	for index in count:
		widths[index] = body[index].distance_to(body[body.size() - 1 - index])
	return widths

func _phase_of(key: String) -> float:
	for item in RibbonLayer.RIBBON_SPECS:
		if str((item as Dictionary).get("key")) == key:
			return float((item as Dictionary).get("phase", 0.0))
	return 0.0

func _one_frame(key: String, local_time: float, samples: int = 120) -> Dictionary:
	# 参数是**这条带自己循环里的时刻**（0 = 它刚开始长），内部再减去它的相位。
	# 用绝对时间写的话，改一次相位所有断言都得跟着改，而且会悄悄变成「其实在量另一个阶段」。
	var base := RibbonLayer.base_layout(CANVAS, PANEL, samples)
	for item in base:
		if str((item as Dictionary).get("key")) == key:
			var frame: Array = RibbonLayer.frame_geometry([item], local_time - _phase_of(key))
			if frame.size() > 0:
				return frame[0]
	return {}

func _tip_of(ribbon: Dictionary) -> Vector2:
	# 可见部分的末端：没长出来的点全部叠在头部尖端上，所以最后一个采样点就是线头。
	var spine: PackedVector2Array = ribbon.get("spine", PackedVector2Array())
	if spine.size() == 0:
		return Vector2.ZERO
	return spine[spine.size() - 1]

func test_a_ribbon_starts_from_nothing_and_grows_to_full_length() -> void:
	# 「从边边慢慢出现延长」的硬指标：起点长度为零，生长到一半露出一段，
	# 长满后整条都在。上一版一上来就是整条，这条会直接红。
	var empty := RibbonLayer.reveal_span(0.0, 0.0)
	near(empty.y - empty.x, 0.0, 0.001, "周期起点必须是零长度（丝带要从画外一点点长出来）")
	var half := RibbonLayer.reveal_span(RibbonLayer.GROW_TIME * 0.5, 0.0)
	gt(half.y, 0.2, "生长过半时必须已经露出一段（当前 %.2f）" % half.y)
	lt(half.y, 0.9, "生长过半时不该已经长满（当前 %.2f）" % half.y)
	near(half.x, 0.0, 0.001, "生长阶段尾部必须钉在画外边缘，不能从中间冒出来")
	var full := RibbonLayer.reveal_span(RibbonLayer.GROW_TIME + RibbonLayer.HOLD_TIME * 0.5, 0.0)
	near(full.x, 0.0, 0.001, "停留阶段尾部仍钉在画外")
	near(full.y, 1.0, 0.001, "停留阶段必须整条都在")

func test_growth_never_jumps_backwards() -> void:
	var previous := -1.0
	for step in 41:
		var time := RibbonLayer.GROW_TIME * float(step) / 40.0
		var span := RibbonLayer.reveal_span(time, 0.0)
		check(span.y >= previous - 0.0001,
			"t=%.2f 时长度倒退了（%.3f < %.3f），屏幕上会看到绸子往回缩" % [time, span.y, previous])
		previous = span.y
	near(previous, 1.0, 0.01, "生长结束时必须已经长满")

func test_the_ribbon_is_drawn_away_before_the_next_cycle() -> void:
	# 长满之后不能「啪」地消失：尾部追上来把绸子抽走，抽完之后留一小段空档再从头长。
	var slide_start := RibbonLayer.GROW_TIME + RibbonLayer.HOLD_TIME
	var sliding := RibbonLayer.reveal_span(slide_start + RibbonLayer.SLIDE_TIME * 0.5, 0.0)
	gt(sliding.x, 0.1, "抽走阶段尾部必须已经离开画外边缘（当前 %.2f）" % sliding.x)
	near(sliding.y, 1.0, 0.001, "抽走阶段头部必须保持在终点，不能跟着往回缩")
	var gap := RibbonLayer.reveal_span(slide_start + RibbonLayer.SLIDE_TIME + 0.01, 0.0)
	near(gap.y - gap.x, 0.0, 0.001, "抽完之后必须有一段空档，再从头长出来")

func test_the_growth_cycle_closes_and_lines_up_with_the_wave() -> void:
	# 生长循环必须是波形周期的整数倍：否则「绸子重来」的那一刻波形相位停在半路，
	# 两套节奏互相错拍 —— 屏幕上说不出哪里怪，但就是不安定。
	var ratio := RibbonLayer.CYCLE / RibbonLayer.PERIOD
	near(ratio, round(ratio), 0.001,
		"生长循环 %.1fs 不是波形周期 %.1fs 的整数倍" % [RibbonLayer.CYCLE, RibbonLayer.PERIOD])
	var gap := RibbonLayer.CYCLE - (RibbonLayer.GROW_TIME + RibbonLayer.HOLD_TIME + RibbonLayer.SLIDE_TIME)
	gt(gap, 0.05, "四段之和正好等于循环长度，抽走之后会立刻又长出来，没有空档")
	lt(gap, 2.0, "空档有 %.1fs，画面上会明显空掉一块" % gap)
	for time in [0.0, 1.3, 4.7, 8.2, 25.5]:
		var before := RibbonLayer.reveal_span(time, 0.7)
		var after := RibbonLayer.reveal_span(time + RibbonLayer.CYCLE, 0.7)
		near(before.x, after.x, 0.0001, "t=%.1f 尾部在一个循环后没回到原处" % time)
		near(before.y, after.y, 0.0001, "t=%.1f 头部在一个循环后没回到原处" % time)

func test_the_three_ribbons_do_not_grow_together() -> void:
	# 「一起动」的另一半：三条带必须错开长。三条同时长/同时满，画面就是一次整体的呼吸，
	# 依然读不出「从边边来」。
	var base := RibbonLayer.base_layout(CANVAS, PANEL, 60)
	var widest := 0.0
	var busiest := 0
	for step in 131:
		var time := RibbonLayer.CYCLE * float(step) / 130.0
		var shortest := 1.0
		var longest := 0.0
		var growing := 0
		for item in base:
			var span := RibbonLayer.reveal_span(time, float((item as Dictionary).get("phase", 0.0)))
			var length := span.y - span.x
			shortest = minf(shortest, length)
			longest = maxf(longest, length)
			# 尾部钉在画外、长度介于 0 和 1 之间 = 这一条正在长
			if span.x < 0.001 and length > 0.001 and length < 0.999:
				growing += 1
		widest = maxf(widest, longest - shortest)
		busiest = maxi(busiest, growing)
	gt(widest, 0.35, "三条丝带的生长进度最多只差 %.2f —— 读起来还是整条一起动" % widest)
	eq(busiest, 1, "同一时刻有 %d 条丝带在一起长 —— 那就又变成「一起动」了" % busiest)

func test_at_least_one_ribbon_keeps_the_panel_stitched_at_all_times() -> void:
	# 丝带不是装饰：它把左栏和右面板缝在一起。生长循环里允许「这一条没了」，
	# 但不允许「两条都没了」—— 那几秒里面板重新变成一座孤岛，而截图上只会被读成
	# 「这张图有点空」，没人会把它报成 bug。远景带在画面上方，不参与缝合。
	var base := RibbonLayer.base_layout(CANVAS, PANEL, 60)
	var worst := 1.0
	var worst_at := 0.0
	for step in 131:
		var time := RibbonLayer.CYCLE * float(step) / 130.0
		var best := 0.0
		for item in base:
			if str((item as Dictionary).get("key")) == "accent":
				continue
			var span := RibbonLayer.reveal_span(time, float((item as Dictionary).get("phase", 0.0)))
			best = maxf(best, span.y - span.x)
		if best < worst:
			worst = best
			worst_at = time
	gt(worst, 0.5, "t=%.1fs 时主带和细带都不足一半 —— 面板会在这几秒里变成孤岛" % worst_at)

func test_the_menu_opens_with_the_panel_stitched_and_one_ribbon_still_growing() -> void:
	# 开场那一秒不能是「什么都没有」：丝带是左栏和右面板之间的缝合线，
	# 菜单一打开就得有一整条在，否则面板先当几秒钟孤岛，再被绸子慢慢补上。
	# 同时必须**还有一条没长完** —— 那是「从边边慢慢出现」的第一印象，
	# 一打开就三条齐满的话，生长要等十几秒才轮到，用户看不到他要的那个动法。
	var base := RibbonLayer.base_layout(CANVAS, PANEL, 60)
	var full_at_open := 0
	var coming_in := 0
	for item in base:
		var span := RibbonLayer.reveal_span(0.0, float((item as Dictionary).get("phase", 0.0)))
		var length := span.y - span.x
		if length > 0.99:
			full_at_open += 1
		elif length < 0.5:
			coming_in += 1
	gt(float(full_at_open), 1.0, "开场时必须至少有一条丝带是整条的（当前 %d 条）" % full_at_open)
	gt(float(coming_in), 0.0, "开场时三条都已经长满了 —— 用户要等十几秒才看得到生长")

func test_the_part_that_has_not_grown_yet_draws_nothing() -> void:
	# 没长出来的那段必须真的「没有」：宽度归零、点全部叠在头部尖端。
	# 否则屏幕上是一条从画外伸到半路、末端齐刷刷切断的带子 —— 比不长还难看。
	var time := RibbonLayer.GROW_TIME * 0.5
	var ribbon := _one_frame("main", time)
	check(not ribbon.is_empty(), "生长中段必须还能拿到主带的几何")
	check(bool(ribbon.get("revealed", true)), "生长中段必须判定为可见")
	var widths := _body_widths(ribbon["body"] as PackedVector2Array)
	var count := widths.size()
	var span: Vector2 = ribbon["reveal"]
	var head := int(round(span.y * float(count - 1)))
	gt(widths[head / 2], 8.0, "已经长出来的中段必须有正常宽度（%.2f）" % widths[head / 2])
	var body: PackedVector2Array = ribbon["body"]
	for index in range(head + 4, count):
		lt(widths[index], 0.2, "第 %d 点还没长出来，宽度却是 %.2f（会看到被切断的带子）" % [index, widths[index]])
		lt(body[index].distance_to(body[head]), 1.0,
			"第 %d 点没叠到头部尖端上，屏幕上会露出一截" % index)

func test_the_growing_tip_comes_to_a_point() -> void:
	# 头部必须是「线头」，不是断口：宽度在最后十几个采样点内收零。
	# 齐口的样子很像贴图被裁掉一截 —— 说不清哪里错，但就是假。
	var ribbon := _one_frame("main", RibbonLayer.GROW_TIME * 0.55)
	var widths := _body_widths(ribbon["body"] as PackedVector2Array)
	var count := widths.size()
	var span: Vector2 = ribbon["reveal"]
	var head := int(round(span.y * float(count - 1)))
	lt(widths[head], 1.0, "头部宽度 %.2f，没有收成尖" % widths[head])
	var behind := maxi(head - int(RibbonLayer.TIP_SAMPLES * 2.0), 1)
	gt(widths[behind], widths[head] + 4.0,
		"头部尖端必须比后面明显细（尖 %.2f / 后 %.2f）" % [widths[head], widths[behind]])

func test_growth_moves_at_a_steady_visible_speed() -> void:
	# 头部每帧推进：太小看着没在长，太大会一顿一顿。上限按「一眼能看出在走」定。
	var step := 1.0 / 60.0
	var previous := _one_frame("main", 0.0)
	var worst := 0.0
	var travelled := 0.0
	var time := step
	while time < RibbonLayer.GROW_TIME:
		var current := _one_frame("main", time)
		var delta := _tip_of(previous).distance_to(_tip_of(current))
		worst = maxf(worst, delta)
		travelled += delta
		previous = current
		time += step
	lt(worst, 12.0, "生长最快的一帧推进了 %.2fpx，会看成抽搐" % worst)
	gt(travelled, 400.0, "整段生长只推进了 %.0fpx，看起来是静止的" % travelled)

func test_the_ribbon_really_vanishes_between_cycles() -> void:
	# 空档里必须「什么都没有」。零宽度的退化三角带虽然看不见，但每帧照样提交几千个顶点；
	# 更要紧的是：判据错了会画出一条宽度乱跳的残带。
	var gap_time := RibbonLayer.GROW_TIME + RibbonLayer.HOLD_TIME + RibbonLayer.SLIDE_TIME + 0.1
	var ribbon := _one_frame("main", gap_time)
	check(not ribbon.is_empty(), "空档里也要给出几何（绘制端靠 revealed 标记跳过）")
	check(not bool(ribbon.get("revealed", true)), "空档里必须判定为不可见")
	var widths := _body_widths(ribbon["body"] as PackedVector2Array)
	var widest := 0.0
	for value in widths:
		widest = maxf(widest, value)
	lt(widest, 0.2, "空档里还有 %.2fpx 宽的残带" % widest)
