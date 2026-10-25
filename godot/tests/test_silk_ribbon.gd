extends "res://tests/test_base.gd"

# 透明丝带几何的回归守卫。
#
# 起因：主菜单左右两栏（标题 / 战场面板）在视觉上互不相干，中间只隔着一片背景。
# 想用「丝绸从面板底下穿过去」把两块缝合起来 —— 但丝带这种东西在屏幕上极难验：
# 高光偏了 3px、宽度在拐弯处塌了、末端没收成尖，肉眼都只会觉得「有点怪」。
#
# 所以几何被抽成 scripts/ui/silk_ribbon.gd 的纯函数，用可量化的性质来守：
#
#   · 样条必须真的穿过给定的每个控制点（否则丝带会从面板旁边绕过去）
#   · 重采样必须按弧长等距（否则拐弯处点会挤在一起，描边粗细不匀）
#   · 带宽必须等于要求的宽度，且拐弯处不许塌边
#   · 高光面 / 暗面必须落在主体轮廓**里面**（飘出去就是丝带边上浮着一条断线）
#   · 上下两条沿边线必须贴在主体边缘的两侧（这是「透明丝绸」的厚度来源）
#   · 退化输入（重复点 / 单点）不许产出 NaN

const SilkRibbon = preload("res://scripts/ui/silk_ribbon.gd")

const EPS := 0.01

# 一条从画面左侧抬起、横穿中部、再收向右下的主带（设计稿里的走位）
var _main_path := PackedVector2Array([
	Vector2(-140.0, 980.0),
	Vector2(260.0, 940.0),
	Vector2(1166.0, 754.0),
	Vector2(1566.0, 714.0),
	Vector2(1806.0, 824.0),
	Vector2(2100.0, 904.0),
])

const TAPER := [[0.0, 130.0], [0.35, 100.0], [0.62, 104.0], [1.0, 44.0]]

func _all_finite(points: PackedVector2Array) -> bool:
	for point in points:
		if not (is_finite(point.x) and is_finite(point.y)):
			return false
	return true

# ---------- 样条：必须穿过控制点 ----------

func test_spline_passes_through_every_control_point() -> void:
	var curve := SilkRibbon.spline(_main_path, 400)
	gt(float(curve.size()), 300.0, "采样点数不能少于要求")
	for target in _main_path:
		var nearest := INF
		for point in curve:
			nearest = minf(nearest, point.distance_to(target))
		lt(nearest, 4.0, "样条没有穿过控制点 (%.1f, %.1f)，最近处还差 %.2f" % [target.x, target.y, nearest])

func test_spline_keeps_the_ends_exactly() -> void:
	# 两端必须落在起点/终点上：丝带要「入画」和「出画」，端点被内缩一截会露出断头。
	var curve := SilkRibbon.spline(_main_path, 200)
	lt(curve[0].distance_to(_main_path[0]), 0.01, "起点必须精确落在第一个控制点")
	lt(curve[curve.size() - 1].distance_to(_main_path[_main_path.size() - 1]), 0.01, "终点必须精确落在最后一个控制点")

func test_spline_resamples_evenly_by_arc_length() -> void:
	# 不按弧长重采样的话，弯道内侧的点会挤成一撮 —— 描边在那里会变粗、发黑。
	var curve := SilkRibbon.spline(_main_path, 240)
	var shortest := INF
	var longest := 0.0
	for index in range(1, curve.size()):
		var step := curve[index].distance_to(curve[index - 1])
		shortest = minf(shortest, step)
		longest = maxf(longest, step)
	lt(longest / maxf(shortest, 0.0001), 1.12, "相邻点间距差得太多（最长 %.3f / 最短 %.3f），不是弧长等距" % [longest, shortest])

# ---------- 法线：单位且与切线垂直 ----------

func test_normals_are_unit_and_perpendicular() -> void:
	var curve := SilkRibbon.spline(_main_path, 80)
	var normals := SilkRibbon.normals(curve)
	eq(normals.size(), curve.size(), "每个点都要有一条法线")
	for index in range(1, curve.size() - 1):
		near(normals[index].length(), 1.0, 0.001, "法线必须是单位向量（第 %d 点）" % index)
		var tangent := (curve[index + 1] - curve[index - 1]).normalized()
		near(normals[index].dot(tangent), 0.0, 0.01, "法线必须垂直于切线（第 %d 点）" % index)

# ---------- 宽度：线性插值 + 越界钳制 ----------

func test_width_stops_interpolate_linearly() -> void:
	var stops := [[0.0, 100.0], [0.5, 60.0], [1.0, 20.0]]
	near(SilkRibbon.width_at(stops, 0.25), 80.0, EPS, "两档之间必须是线性插值")
	near(SilkRibbon.width_at(stops, 0.75), 40.0, EPS, "两档之间必须是线性插值（后半段）")
	near(SilkRibbon.width_at(stops, -0.4), 100.0, EPS, "越界必须钳到首档宽度")
	near(SilkRibbon.width_at(stops, 1.6), 20.0, EPS, "越界必须钳到末档宽度")

# ---------- 带：宽度就是宽度 ----------

func test_constant_width_band_keeps_its_width() -> void:
	var curve := SilkRibbon.spline(_main_path, 120)
	var normals := SilkRibbon.normals(curve)
	var band := SilkRibbon.band(curve, normals, [[0.0, 80.0], [1.0, 80.0]], -0.5, 0.5)
	var n := curve.size()
	eq(band.size(), n * 2, "带轮廓 = 去程 n 点 + 回程 n 点")
	for index in n:
		var width := band[index].distance_to(band[band.size() - 1 - index])
		near(width, 80.0, 0.02, "第 %d 点的带宽必须等于 80（拐弯处也不许塌）" % index)

func test_band_tapers_along_the_curve() -> void:
	var curve := SilkRibbon.spline(_main_path, 200)
	var normals := SilkRibbon.normals(curve)
	var band := SilkRibbon.band(curve, normals, TAPER, -0.5, 0.5)
	var n := curve.size()
	var first := band[0].distance_to(band[band.size() - 1])
	var middle := band[n / 2].distance_to(band[band.size() - 1 - n / 2])
	var last := band[n - 1].distance_to(band[n])
	near(first, 130.0, 0.05, "起笔宽度必须等于首档")
	near(last, 44.0, 0.05, "收笔宽度必须等于末档")
	check(middle < first and middle > last, "中段宽度必须落在首末之间：%.2f（起 %.2f / 收 %.2f）" % [middle, first, last])
	lt(last, first * 0.5, "末端必须明显收细，否则读不出「飘带」")

# ---------- 分层：高光/暗面必须落在主体里面 ----------

func test_sheen_and_shade_stay_inside_the_body() -> void:
	# 高光飘到轮廓外面，屏幕上就是丝带边缘浮着一条断开的高亮线 —— 比不画还糟。
	var ribbon := SilkRibbon.ribbon(_main_path, TAPER, 180)
	var body: PackedVector2Array = ribbon["body"]
	gt(float(body.size()), 10.0, "主体轮廓不能是空的")
	for key in ["sheen", "shade"]:
		var shape: PackedVector2Array = ribbon[key]
		gt(float(shape.size()), 10.0, "%s 必须是闭合多边形" % key)
		for point in shape:
			check(Geometry2D.is_point_in_polygon(point, body),
				"%s 有点跑到了主体轮廓外面：(%.2f, %.2f)" % [key, point.x, point.y])

func test_rims_sit_on_opposite_edges_of_the_body() -> void:
	# 「透明丝绸」的厚度全靠这两条沿边线：面是透的、边是亮的。
	# 它们必须各贴一侧，贴到同一侧就退化成一根线，丝带立刻变成「描边色块」。
	var ribbon := SilkRibbon.ribbon(_main_path, TAPER, 160)
	var spine: PackedVector2Array = ribbon["spine"]
	var light: PackedVector2Array = ribbon["rim_light"]
	var dark: PackedVector2Array = ribbon["rim_dark"]
	eq(light.size(), spine.size(), "亮边线点数必须跟脊线一致")
	eq(dark.size(), spine.size(), "暗边线点数必须跟脊线一致")
	for index in spine.size():
		var half := SilkRibbon.width_at(TAPER, float(index) / float(spine.size() - 1)) * 0.5
		near(light[index].distance_to(spine[index]), half, 0.02, "亮边必须正好贴在边缘上（第 %d 点）" % index)
		near(dark[index].distance_to(spine[index]), half, 0.02, "暗边必须正好贴在另一侧边缘上（第 %d 点）" % index)
		var cross := (light[index] - spine[index]).dot(dark[index] - spine[index])
		lt(cross, 0.0, "亮边与暗边必须在脊线的两侧（点积必须为负，第 %d 点）" % index)

func test_ribbon_returns_every_layer() -> void:
	var ribbon := SilkRibbon.ribbon(_main_path, TAPER, 100)
	for key in ["spine", "body", "sheen", "shade", "rim_light", "rim_dark"]:
		check(ribbon.has(key), "丝带必须包含 %s 这一层" % key)
		check((ribbon[key] as PackedVector2Array).size() > 1, "%s 不能是空层" % key)

# ---------- 退化输入：不许产出 NaN ----------

func test_duplicate_points_do_not_produce_nan() -> void:
	# 端点重合时切线长度为 0，normalized() 会给出零向量/NaN —— 整条丝带直接消失。
	var degenerate := PackedVector2Array([Vector2(40.0, 40.0), Vector2(40.0, 40.0), Vector2(40.0, 40.0)])
	var curve := SilkRibbon.spline(degenerate, 24)
	check(_all_finite(curve), "全重合的输入也必须是有限坐标")
	var ribbon := SilkRibbon.ribbon(degenerate, [[0.0, 60.0], [1.0, 10.0]], 24)
	check(_all_finite(ribbon["body"] as PackedVector2Array), "退化输入的带轮廓不能出现 NaN")
	check(_all_finite(ribbon["rim_light"] as PackedVector2Array), "退化输入的边线不能出现 NaN")

func test_single_point_does_not_crash() -> void:
	var single := PackedVector2Array([Vector2(12.0, 34.0)])
	var curve := SilkRibbon.spline(single, 16)
	check(curve.size() >= 1, "单点输入至少要原样返回一个点")
	check(_all_finite(curve), "单点输入的坐标必须是有限的")

func test_zero_width_is_finite() -> void:
	var curve := SilkRibbon.spline(_main_path, 60)
	var normals := SilkRibbon.normals(curve)
	var band := SilkRibbon.band(curve, normals, [[0.0, 0.0], [1.0, 0.0]], -0.5, 0.5)
	eq(band.size(), curve.size() * 2, "零宽带仍然是完整轮廓（交给渲染端决定画不画）")
	check(_all_finite(band), "零宽带不能出现 NaN")

# ---------- 顺滑：不许出现折点 ----------

func test_curve_never_kinks_harder_than_a_gentle_arc() -> void:
	# 「丝带不够顺」在屏幕上就是能数出来的折角。逐段量转角：
	# 一段 320 点的曲线里，任意相邻两段的转角超过几度，边缘就会在缩略图上显形。
	var curve := SilkRibbon.spline(_main_path, 320)
	var worst := 0.0
	var worst_at := 0
	for index in range(1, curve.size() - 1):
		var before := (curve[index] - curve[index - 1]).normalized()
		var after := (curve[index + 1] - curve[index]).normalized()
		var angle := rad_to_deg(absf(before.angle_to(after)))
		if angle > worst:
			worst = angle
			worst_at = index
	lt(worst, 4.0, "第 %d 点出现 %.2f° 的折角，曲线不够顺（阈值 4°）" % [worst_at, worst])

func test_curve_travels_left_to_right_without_folding_back() -> void:
	# 丝带「看着扭了」几乎都是自交或回折：曲线在 x 上倒退一段，就会和上一段叠在一起，
	# 屏幕上表现为绸子打了个结。走位是单调向右的，曲线也必须单调向右。
	var curve := SilkRibbon.spline(_main_path, 400)
	var worst := 0.0
	for index in range(1, curve.size()):
		worst = minf(worst, curve[index].x - curve[index - 1].x)
	check(worst >= -0.05, "曲线在第 %d 点向后折了 %.2f px" % [0, -worst])
	var span := curve[curve.size() - 1].x - curve[0].x
	near(span, _main_path[_main_path.size() - 1].x - _main_path[0].x, 0.5,
		"曲线两端必须落在首末控制点上")

# ---------- 流动：端点钉住、振幅有界、周期闭合 ----------

func test_wave_pins_both_ends_for_a_seamless_loop() -> void:
	# 循环动画最容易露馅的地方是接缝：位移在首尾不为零，每轮重放都会「弹」一下。
	var curve := SilkRibbon.spline(_main_path, 120)
	var normals := SilkRibbon.normals(curve)
	for time in [0.0, 1.7, 5.4, 9.9]:
		var waved := SilkRibbon.wave(curve, normals, time, 20.0, 11.0, 1.35)
		near(waved[0].distance_to(curve[0]), 0.0, 0.001, "t=%.1f 时起点被推动了，循环会看到接缝" % time)
		near(waved[waved.size() - 1].distance_to(curve[curve.size() - 1]), 0.0, 0.001,
			"t=%.1f 时终点被推动了，循环会看到接缝" % time)

func test_wave_is_bounded_and_perpendicular() -> void:
	var curve := SilkRibbon.spline(_main_path, 120)
	var normals := SilkRibbon.normals(curve)
	var amplitude := 20.0
	var waved := SilkRibbon.wave(curve, normals, 3.2, amplitude, 11.0, 1.35)
	var moved := 0
	for index in curve.size():
		var offset := waved[index] - curve[index]
		lt(offset.length(), amplitude * 1.4, "第 %d 点位移超过振幅包络" % index)
		# 位移必须垂直于脊线：沿切线推等于把丝带「拉长」，看着像在滑动而不是在飘。
		var tangent := (curve[mini(index + 1, curve.size() - 1)] - curve[maxi(index - 1, 0)]).normalized()
		near(offset.dot(tangent), 0.0, 0.02, "第 %d 点的位移必须垂直于脊线" % index)
		if offset.length() > 0.5:
			moved += 1
	gt(float(moved), 20.0, "波形必须真的动起来（只有 %d 个点有位移）" % moved)

func test_wave_closes_its_loop_after_one_period() -> void:
	# 周期一到必须回到同一帧，否则动画每轮重启都会跳一下。
	var curve := SilkRibbon.spline(_main_path, 120)
	var normals := SilkRibbon.normals(curve)
	var period := 11.0
	var at_zero := SilkRibbon.wave(curve, normals, 0.0, 18.0, period, 1.35)
	var at_period := SilkRibbon.wave(curve, normals, period, 18.0, period, 1.35)
	var mid := SilkRibbon.wave(curve, normals, period * 0.5, 18.0, period, 1.35)
	for index in curve.size():
		near(at_period[index].distance_to(at_zero[index]), 0.0, 0.01,
			"第 %d 点在一个周期后没有回到原位（循环会跳）" % index)
	var shifted := 0.0
	for index in curve.size():
		shifted = maxf(shifted, mid[index].distance_to(at_zero[index]))
	gt(shifted, 2.0, "半个周期时波形必须已经明显移动（当前最大位移 %.2f）" % shifted)

# ---------- 流动的宽度：绸子被拧，而不是光带在平移 ----------

func test_flow_widths_are_bounded_and_actually_move() -> void:
	# 只沿法线推位移的话，两条边是「平行移动的橡皮筋」—— 屏幕上读起来像一道光在滑。
	# 宽度必须跟着流，而且只能在 ±depth 的量级里流，否则带子会一阵鼓一阵缩。
	var widths := SilkRibbon.widths(TAPER, 120)
	var depth := 0.14
	var flowed := SilkRibbon.flow_widths(widths, 3.4, 13.0, 1.35, depth)
	eq(flowed.size(), widths.size(), "宽度数组长度不能变")
	var widest_delta := 0.0
	var changed := 0
	for index in widths.size():
		var delta := absf(flowed[index] - widths[index]) / maxf(widths[index], 0.001)
		widest_delta = maxf(widest_delta, delta)
		if delta > 0.01:
			changed += 1
	lt(widest_delta, depth * 1.4, "宽度起伏超出包络（最大 %.3f）" % widest_delta)
	gt(float(changed), 40.0, "宽度几乎没动，读不出「布在扭」（只有 %d 个点变了）" % changed)

func test_flow_widths_pin_both_ends_and_close_the_loop() -> void:
	# 两端必须保持原宽：末端本来就收成尖，再乘一个起伏会在画外露出粗细不均的断头。
	var widths := SilkRibbon.widths(TAPER, 100)
	var at_zero := SilkRibbon.flow_widths(widths, 0.0, 13.0)
	var at_period := SilkRibbon.flow_widths(widths, 13.0, 13.0)
	near(at_zero[0], widths[0], 0.001, "起点宽度被改了，出画处会露断头")
	near(at_zero[widths.size() - 1], widths[widths.size() - 1], 0.001, "终点宽度被改了")
	for index in widths.size():
		near(at_period[index], at_zero[index], 0.001,
			"第 %d 点在一个周期后没有回到原宽（循环会跳）" % index)

func test_flow_widths_never_collapse_or_balloon() -> void:
	# 负宽度会让带子翻面（轮廓自交，屏幕上是一块黑洞）；涨太多会盖过相邻的层。
	var widths := SilkRibbon.widths(TAPER, 160)
	for time in [0.0, 1.1, 4.7, 8.3, 12.9]:
		var flowed := SilkRibbon.flow_widths(widths, time, 13.0, 1.35, 0.20)
		for index in flowed.size():
			gt(flowed[index], 0.0, "t=%.1f 时第 %d 点宽度 <= 0（轮廓会翻面）" % [time, index])
			lt(flowed[index], widths[index] * 1.5, "t=%.1f 时第 %d 点宽度涨过头" % [time, index])
