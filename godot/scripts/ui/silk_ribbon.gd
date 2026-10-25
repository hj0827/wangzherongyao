extends RefCounted
class_name SilkRibbon

## 透明丝绸飘带的**纯几何**生成器。
##
## 丝带在截图里永远是「看着还行」的东西：高光偏 3px、拐弯处宽度塌掉、末端没收成尖，
## 肉眼都只会觉得有点怪，说不上哪里错。所以这里只算顶点，不建节点、不画东西 ——
## 让 tests/test_silk_ribbon.gd 能把每一条都量出来。
##
## 渲染端（ribbon_layer）负责把五层喂给 draw_colored_polygon / draw_polyline：
##
##   spine      脊线（开放折线，调试用，一般不画）
##   body       主体闭合轮廓（半透明金，是「面」）
##   sheen      上侧高光面（贴着上沿的窄条，模拟丝绸受光的那一道）
##   shade      下侧暗面（贴着下沿，给厚度）
##   rim_light  上沿亮线（1~1.5px，面是透的、边是亮的）
##   rim_dark   下沿暗线
##
## 为什么用「多层纯色」而不是渐变：渐变要按路径铺 UV，丝带一拐弯就得重算坐标系；
## 四层纯色叠出来的厚度感在游戏里几乎看不出区别，而改一个颜色只要改一个数。

## 每条样条段内的采样密度。向心 Catmull-Rom 每段最多两个拐点，32 足够平滑；
## 再密只是让按弧长重采样更准一点，收益很小。
const DENSE_PER_SPAN := 32

## 向心参数化的指数。0.5 = centripetal（向心），是「不出现过冲/尖点」的标准取值：
## 控制点间距悬殊时，均匀参数化（alpha = 0）会在拐弯外侧甩出一个鼓包。
const ALPHA := 0.5

## 把一串控制点连成一条**穿过每个点**的平滑曲线，并按弧长等距重采样。
##
## 用向心 Catmull-Rom 而不是三次贝塞尔：贝塞尔不穿过中间控制点，想让它贴着给定的
## 走位就必须自己解控制柄，改一个点要重算三个 —— 调走位时会调到怀疑人生。
## 也不用均匀参数化：控制点一疏一密就会出现肉眼可见的「甩包」。
static func spline(through: PackedVector2Array, samples: int = 220) -> PackedVector2Array:
	var count := through.size()
	if count == 0:
		return PackedVector2Array()
	if count == 1:
		return PackedVector2Array([through[0]])
	var dense := PackedVector2Array()
	for span in count - 1:
		var p1 := through[span]
		var p2 := through[span + 1]
		# 端点缺邻居时**复制端点**，不要镜像出虚拟点。镜像点（p1*2 - p2）会落在真实
		# 控制点的包围盒外面，把曲线末端朝虚拟点方向拽过去 —— 表现为丝带在出画前鼓个包。
		# 复制端点时 A1 恒等于 p1（两点重合），数值上稳定，曲线也不会离开控制多边形。
		var p0 := through[span - 1] if span > 0 else p1
		var p3 := through[span + 2] if span + 2 < count else p2
		var knots := _knots(p0, p1, p2, p3)
		for step in DENSE_PER_SPAN:
			var t := lerpf(knots[1], knots[2], float(step) / float(DENSE_PER_SPAN))
			dense.append(_centripetal(p0, p1, p2, p3, knots, t))
	dense.append(through[count - 1])
	return _resample(dense, maxi(samples, 2))

## 每个点的左手法线（切线逆时针转 90°）。用相邻两点求切线而不是用解析导数，
## 这样任何采样方式得到的曲线都能直接用。
static func normals(curve: PackedVector2Array) -> PackedVector2Array:
	var result := PackedVector2Array()
	var count := curve.size()
	if count == 0:
		return result
	for index in count:
		var before := curve[maxi(index - 1, 0)]
		var after := curve[mini(index + 1, count - 1)]
		var tangent := after - before
		if tangent.length() < 0.0001:
			# 所有点重合（退化输入）：沿用上一条法线，别让 normalized() 吐 NaN。
			result.append(result[result.size() - 1] if result.size() > 0 else Vector2(0.0, -1.0))
		else:
			var unit := tangent.normalized()
			result.append(Vector2(-unit.y, unit.x))
	return result

## 按「宽度档位」取某一位置的宽度。stops 形如 [[0.0, 120.0], [0.55, 90.0], [1.0, 30.0]]，
## 档位之间线性插值，越界钳到首/末档。
static func width_at(stops: Array, t: float) -> float:
	if stops.is_empty():
		return 0.0
	if stops.size() == 1:
		return float((stops[0] as Array)[1])
	if t <= float((stops[0] as Array)[0]):
		return float((stops[0] as Array)[1])
	for index in range(1, stops.size()):
		var previous: Array = stops[index - 1]
		var current: Array = stops[index]
		var from_t := float(previous[0])
		var to_t := float(current[0])
		if t <= to_t:
			var span := to_t - from_t
			if span <= 0.0001:
				return float(current[1])
			return lerpf(float(previous[1]), float(current[1]), (t - from_t) / span)
	return float((stops[stops.size() - 1] as Array)[1])

## 把宽度档位展开成「每个采样点一条宽度」。逐帧动画时脊线每帧都在变，
## 但宽度档位不变 —— 先算一次存下来，动画里就只剩位移与拼边。
static func widths(stops: Array, count: int) -> PackedFloat32Array:
	var result := PackedFloat32Array()
	result.resize(count)
	for index in count:
		result[index] = width_at(stops, float(index) / float(maxi(count - 1, 1)))
	return result

## 沿曲线切一条**闭合**的带：外沿取 from_frac × 宽度，内沿取 to_frac × 宽度。
## from_frac / to_frac 是宽度的比例（-0.5 ~ 0.5 正好是整条带），方便做分层：
## 主体 (-0.5, 0.5)、上高光 (-0.46, -0.12)、下暗面 (0.12, 0.46)。
static func band(
	curve: PackedVector2Array,
	curve_normals: PackedVector2Array,
	stops: Array,
	from_frac: float,
	to_frac: float
) -> PackedVector2Array:
	return band_of(curve, curve_normals, widths(stops, curve.size()), from_frac, to_frac)

## 同上，但直接吃已经展开好的宽度数组（动画帧用这个，省掉每帧的档位插值）。
static func band_of(
	curve: PackedVector2Array,
	curve_normals: PackedVector2Array,
	width_values: PackedFloat32Array,
	from_frac: float,
	to_frac: float
) -> PackedVector2Array:
	var count := curve.size()
	if count == 0 or curve_normals.size() != count or width_values.size() != count:
		return PackedVector2Array()
	var forward := PackedVector2Array()
	var backward := PackedVector2Array()
	for index in count:
		var width := width_values[index]
		var normal := curve_normals[index]
		forward.append(curve[index] + normal * (width * from_frac))
		backward.append(curve[index] + normal * (width * to_frac))
	var shape := forward
	for index in range(count - 1, -1, -1):
		shape.append(backward[index])
	return shape

## 沿曲线的一条**开放**偏移线（沿边线的亮/暗描边用）。
static func edge(
	curve: PackedVector2Array,
	curve_normals: PackedVector2Array,
	stops: Array,
	frac: float
) -> PackedVector2Array:
	return edge_of(curve, curve_normals, widths(stops, curve.size()), frac)

static func edge_of(
	curve: PackedVector2Array,
	curve_normals: PackedVector2Array,
	width_values: PackedFloat32Array,
	frac: float
) -> PackedVector2Array:
	var count := curve.size()
	var result := PackedVector2Array()
	if count == 0 or curve_normals.size() != count or width_values.size() != count:
		return result
	for index in count:
		result.append(curve[index] + curve_normals[index] * (width_values[index] * frac))
	return result

## 沿法线传播的周期波：丝带的「流动」。
##
## 三个必须满足的性质（tests/test_silk_ribbon.gd 逐条守着）：
##   1. 两端位移恒为 0（sin(πt) 包络）—— 否则循环每轮重启都会在画面边缘弹一下
##   2. 位移只沿法线 —— 沿切线推等于把丝带「拉长」，看着像在滑动而不是在飘
##   3. 周期严格闭合 —— 谐波频率取整数倍，time += period 时相位正好转一圈
static func wave(
	curve: PackedVector2Array,
	curve_normals: PackedVector2Array,
	time: float,
	amplitude: float,
	period: float,
	waves: float = 1.35
) -> PackedVector2Array:
	var count := curve.size()
	var result := PackedVector2Array()
	if count == 0:
		return result
	result.resize(count)
	if count == 1 or curve_normals.size() != count:
		for index in count:
			result[index] = curve[index]
		return result
	var cycle := TAU / maxf(period, 0.001)
	for index in count:
		var t := float(index) / float(count - 1)
		var envelope := sin(PI * t)
		var phase := t * TAU * waves - time * cycle
		# 第二谐波让波形不那么「正弦」：纯单频看着像被机器推开，
		# 叠一层二倍频才有一点绸子在风里的不规则感（周期仍然严格闭合）。
		var value := sin(phase) + 0.32 * sin(phase * 2.0 + time * cycle)
		result[index] = curve[index] + curve_normals[index] * (value * amplitude * envelope)
	return result

## 沿脊线传播的**宽度起伏**：绸子被风托起时，带子会一边收窄一边鼓起。
##
## 只做法线位移的话，两条边像两根被同时推开的橡皮筋 —— 平行移动，读起来是「光带在滑」。
## 叠一层宽度起伏，边缘一宽一窄，才有布被拧了一下的感觉。
##
## 与 wave 同样的三条性质：两端钉住（包络）、有界、周期闭合。
static func flow_widths(
	width_values: PackedFloat32Array,
	time: float,
	period: float,
	waves: float = 1.35,
	depth: float = 0.14
) -> PackedFloat32Array:
	var count := width_values.size()
	var result := PackedFloat32Array()
	result.resize(count)
	if count == 0:
		return result
	var cycle := TAU / maxf(period, 0.001)
	for index in count:
		var t := float(index) / float(maxi(count - 1, 1))
		var envelope := sin(PI * t)
		# 相位比 wave 偏 0.9 rad：位移最大的地方宽度不是最宽，看着才像布在扭，
		# 而不是一个气球在胀缩。
		var phase := t * TAU * waves - time * cycle + 0.9
		var value := sin(phase) + 0.28 * sin(phase * 2.0 - time * cycle)
		result[index] = width_values[index] * (1.0 + value * depth * envelope)
	return result

## 一条完整丝带的所有层。
static func ribbon(through: PackedVector2Array, stops: Array, samples: int = 220) -> Dictionary:
	var curve := spline(through, samples)
	var curve_normals := normals(curve)
	return {
		"spine": curve,
		"body": band(curve, curve_normals, stops, -0.5, 0.5),
		"core": band(curve, curve_normals, stops, -0.30, -0.04),
		"sheen": band(curve, curve_normals, stops, -0.46, -0.12),
		"shade": band(curve, curve_normals, stops, 0.10, 0.50),
		"rim_light": edge(curve, curve_normals, stops, -0.5),
		"rim_dark": edge(curve, curve_normals, stops, 0.5),
	}

# ---------- 内部 ----------

## 向心参数化的结点序列：t(i+1) = t(i) + |p(i+1) - p(i)|^alpha。
## 距离悬殊时结点间隔也跟着悬殊，正是这样才把过冲压掉。
static func _knots(p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2) -> PackedFloat32Array:
	var knots := PackedFloat32Array()
	knots.resize(4)
	knots[0] = 0.0
	knots[1] = knots[0] + pow(maxf(p1.distance_to(p0), 0.0001), ALPHA)
	knots[2] = knots[1] + pow(maxf(p2.distance_to(p1), 0.0001), ALPHA)
	knots[3] = knots[2] + pow(maxf(p3.distance_to(p2), 0.0001), ALPHA)
	return knots

## 在 [t1, t2] 上做三次向心插值（Barry–Goldman 金字塔）。
## 所有权重都是正数 ⇒ 结果一定落在四个控制点的凸包里 ⇒ 不会甩出控制多边形之外。
static func _centripetal(
	p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2, knots: PackedFloat32Array, t: float
) -> Vector2:
	var t0 := knots[0]
	var t1 := knots[1]
	var t2 := knots[2]
	var t3 := knots[3]
	var a1 := _mix(p0, p1, t0, t1, t)
	var a2 := _mix(p1, p2, t1, t2, t)
	var a3 := _mix(p2, p3, t2, t3, t)
	var b1 := _mix(a1, a2, t0, t2, t)
	var b2 := _mix(a2, a3, t1, t3, t)
	return _mix(b1, b2, t1, t2, t)

static func _mix(a: Vector2, b: Vector2, from_t: float, to_t: float, t: float) -> Vector2:
	var span := maxf(to_t - from_t, 0.000001)
	return a * ((to_t - t) / span) + b * ((t - from_t) / span)

## 按弧长重采样。弯道内侧的点如果按参数 t 等分，会挤成一撮 —— 描边在那里又粗又黑。
static func _resample(points: PackedVector2Array, samples: int) -> PackedVector2Array:
	var count := points.size()
	if count == 0:
		return PackedVector2Array()
	if count == 1:
		var single := PackedVector2Array()
		single.resize(samples)
		for index in samples:
			single[index] = points[0]
		return single
	var accumulated := PackedFloat32Array()
	accumulated.resize(count)
	accumulated[0] = 0.0
	for index in range(1, count):
		accumulated[index] = accumulated[index - 1] + points[index].distance_to(points[index - 1])
	var total := accumulated[count - 1]
	var result := PackedVector2Array()
	result.resize(samples)
	if total <= 0.0001:
		for index in samples:
			result[index] = points[0]
		return result
	var cursor := 0
	for index in samples:
		var target := total * float(index) / float(maxi(samples - 1, 1))
		while cursor < count - 2 and accumulated[cursor + 1] < target:
			cursor += 1
		var span := accumulated[cursor + 1] - accumulated[cursor]
		var u := 0.0 if span <= 0.0001 else (target - accumulated[cursor]) / span
		u = clampf(u, 0.0, 1.0)
		result[index] = points[cursor].lerp(points[cursor + 1], u)
	return result
