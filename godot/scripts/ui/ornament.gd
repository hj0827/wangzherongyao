extends RefCounted
class_name Ornament

## 东方风装饰纹样的**纯几何**生成器。
##
## 只吐顶点（PackedVector2Array），不建节点、不读主题、不画东西。这样纹样可以被
## 量化断言：螺线是不是真的往里收、中轴是不是真的左右对称、角饰有没有跑到对角去。
## 渲染端（ornate_title / ornate_frame）只负责把顶点喂给 draw_polyline /
## draw_colored_polygon，一个问题只在一处发生。
##
## 统一返回格式：
##   {"strokes": Array[PackedVector2Array],  需要描边的开放折线
##    "fills":   Array[PackedVector2Array]}  需要填充的闭合多边形
##
## 角度一律用弧度，x 向右、y 向下（和 Control 的坐标系一致）。

## 新建一个空纹样包
static func parts() -> Dictionary:
	return {"strokes": [], "fills": []}

static func add_stroke(target: Dictionary, points: PackedVector2Array) -> Dictionary:
	(target["strokes"] as Array).append(points)
	return target

static func add_fill(target: Dictionary, points: PackedVector2Array) -> Dictionary:
	(target["fills"] as Array).append(points)
	return target

## 把纹样包里所有顶点摊平成一个数组，方便测试整体范围 / 对称性
static func points_of(target: Dictionary) -> PackedVector2Array:
	var result := PackedVector2Array()
	for stroke in (target.get("strokes", []) as Array):
		result.append_array(stroke as PackedVector2Array)
	for fill in (target.get("fills", []) as Array):
		result.append_array(fill as PackedVector2Array)
	return result

# ---------- 基本笔画 ----------

## 卷草：阿基米德螺线。半径从 start_radius 线性收到 end_radius，
## 同时绕 start_angle 扫过 sweep 弧度 —— 一条真正的「卷」，而不是一段圆弧。
static func curl(
	origin: Vector2,
	start_radius: float,
	end_radius: float,
	start_angle: float,
	sweep: float,
	segments: int = 24
) -> PackedVector2Array:
	var points := PackedVector2Array()
	var steps := maxi(segments, 1)
	for index in steps + 1:
		var t := float(index) / float(steps)
		var radius := lerpf(start_radius, end_radius, t)
		var angle := start_angle + sweep * t
		points.append(origin + Vector2(cos(angle), sin(angle)) * radius)
	return points

## 渐细带：一条（可弯的）中心线，两端各有宽度，宽端到窄端自然收成笔锋。
## 返回的是**闭合轮廓**，可以直接 draw_colored_polygon。
## 每一点的法线取当前切线方向，所以花枝拐弯处宽度不会塌掉。
static func taper(
	from: Vector2,
	to: Vector2,
	start_width: float,
	end_width: float,
	curve: float = 0.0,
	segments: int = 12
) -> PackedVector2Array:
	var steps := maxi(segments, 1)
	var axis := (to - from)
	var normal := Vector2(-axis.y, axis.x)
	if normal.length() < 0.0001:
		normal = Vector2(0.0, 1.0)
	else:
		normal = normal.normalized()
	var control := (from + to) * 0.5 + normal * curve
	var left := PackedVector2Array()
	var right := PackedVector2Array()
	for index in steps + 1:
		var t := float(index) / float(steps)
		var centre := _quad(from, control, to, t)
		var tangent := _quad_tangent(from, control, to, t)
		var side := normal
		if tangent.length() > 0.0001:
			var unit := tangent.normalized()
			side = Vector2(-unit.y, unit.x)
		var half := lerpf(start_width, end_width, t) * 0.5
		left.append(centre + side * half)
		right.append(centre - side * half)
	var shape := PackedVector2Array()
	shape.append_array(left)
	for index in range(right.size() - 1, -1, -1):
		shape.append(right[index])
	return shape

## 宝珠：四角菱形，四个顶点到中心等距
static func diamond(centre: Vector2, radius: float) -> PackedVector2Array:
	return PackedVector2Array([
		centre + Vector2(0.0, -radius),
		centre + Vector2(radius, 0.0),
		centre + Vector2(0.0, radius),
		centre + Vector2(-radius, 0.0),
	])

# ---------- 组合纹样 ----------

## 中轴花边：中央一枚宝珠 + 两侧各一条中间粗两端尖的梭形横线 + 外端小钩。
## 整组关于 width/2 精确镜像。
static func center_rule(width: float, y: float, thickness: float = 1.6) -> Dictionary:
	var result := parts()
	var centre := Vector2(width * 0.5, y)
	var bead := maxf(thickness * 3.2, 4.0)
	# 梭形横线：从外端（宽 0）向宝珠一侧长粗，两端都是笔锋
	add_fill(result, taper(Vector2(0.0, y), centre - Vector2(bead, 0.0), 0.0, thickness * 2.0, 0.0, 14))
	add_fill(result, taper(Vector2(width, y), centre + Vector2(bead, 0.0), 0.0, thickness * 2.0, 0.0, 14))
	# 中央宝珠 + 左右两粒碎珠，给中轴一点节奏
	add_fill(result, diamond(centre, bead))
	add_fill(result, diamond(centre - Vector2(bead * 2.5, 0.0), bead * 0.32))
	add_fill(result, diamond(centre + Vector2(bead * 2.5, 0.0), bead * 0.32))
	# 刻意不在两端加卷钩：梭形线本身就收到尖，再加两笔小卷会在尖端外侧悬成
	# 两个孤立的小逗号，远看像句读而不是纹样。留白比加笔更难，但这里应该留白。
	return result

## 角饰：一个角上的内嵌 L 形折线 + 拐角内侧一枚宝珠。
## anchor 指明是矩形的哪一个角：(0,0) 左上、(1,0) 右上、(0,1) 左下、(1,1) 右下。
## 所有点保证落在该角 arm × arm 的方框内 —— 越界就会压在按钮边框上。
static func corner(
	rect: Rect2,
	arm: float,
	thickness: float,
	anchor: Vector2i = Vector2i(0, 0),
	inset: float = 4.0
) -> Dictionary:
	var result := parts()
	var sx := 1.0 if anchor.x == 0 else -1.0
	var sy := 1.0 if anchor.y == 0 else -1.0
	var origin := Vector2(
		rect.position.x if anchor.x == 0 else rect.end.x,
		rect.position.y if anchor.y == 0 else rect.end.y
	)
	var edge := minf(inset, arm * 0.35)
	add_stroke(result, PackedVector2Array([
		origin + Vector2(sx * arm, sy * edge),
		origin + Vector2(sx * edge, sy * edge),
		origin + Vector2(sx * edge, sy * arm),
	]))
	add_fill(result, diamond(origin + Vector2(sx * arm * 0.44, sy * arm * 0.44), thickness * 1.4))
	return result

## 单侧花枝：主枝向外伸展并在末端卷起来，三分之一处再挑一朵小花，
## 起笔处长一片叶子（否则花枝像从空气里凭空冒出来）。
## facing = 1 朝右，-1 朝左 —— 只镜像 x，其余完全一致。
## with_leaf = false 时去掉起笔的叶子：大尺寸花枝上叶子是点睛，
## 小尺寸（按钮里）叶子会碎成一撮噪点。
##
## 几何一律在「根部 = 原点」的局部空间里生成，最后才平移到 origin。
## 这一步不能省：镜像只绕 x = 0 成立，如果带着 origin 一起镜像，根部不在原点的
## 花枝会被整株甩到轴的另一侧 —— 标题左边的花枝会扑到字上，按钮左边的会飞出画外。
static func wing(
	origin: Vector2,
	width: float,
	height: float,
	facing: float,
	with_leaf: bool = true
) -> Dictionary:
	var result := parts()
	var root := Vector2.ZERO
	var tip := root + Vector2(width * 0.72, -height * 0.08)
	add_fill(result, taper(root, tip, height * 0.14, height * 0.05, height * 0.30, 18))
	add_stroke(result, curl(
		tip + Vector2(width * 0.04, -height * 0.02),
		height * 0.18, height * 0.04, PI * 0.75, TAU * 0.78, 24
	))
	var stem := root + Vector2(width * 0.30, -height * 0.05)
	var bud := stem + Vector2(width * 0.06, -height * 0.36)
	add_fill(result, taper(stem, bud, height * 0.08, height * 0.035, -height * 0.12, 12))
	add_stroke(result, curl(bud, height * 0.11, height * 0.025, -PI * 0.5, TAU * 0.7, 18))
	if with_leaf:
		add_fill(result, taper(
			root, root + Vector2(height * 0.30, height * 0.34), height * 0.10, 0.0, height * 0.10, 10
		))
	if facing < 0.0:
		_mirror_x(result)
	_translate(result, origin)
	return result

## 细须：一条渐细的曲线，末端卷起来。完整花枝（wing）的副枝和叶子在 20px 级别的
## 尺寸下会糊成一撮，按钮那一排只留主枝 + 卷尾才认得出是花边。
## 镜像规则与 wing 完全一致：局部空间生成 → 绕根部镜像 → 平移。
static func tendril(origin: Vector2, width: float, height: float, facing: float) -> Dictionary:
	var result := parts()
	var root := Vector2.ZERO
	var tip := root + Vector2(width * 0.72, -height * 0.06)
	# 主枝要细、弯要小：20px 级别的尺寸下，粗枝会因为抗锯齿糊成一条毛毛虫，
	# 弯度稍大又会读成波浪线而不是花边。
	add_fill(result, taper(root, tip, height * 0.13, height * 0.04, height * 0.24, 16))
	add_stroke(result, curl(
		tip + Vector2(width * 0.05, -height * 0.01),
		height * 0.22, height * 0.04, PI * 0.82, TAU * 0.88, 22
	))
	if facing < 0.0:
		_mirror_x(result)
	_translate(result, origin)
	return result

## 把纹样包里所有顶点按 x = -x 镜像。左右对称靠这一处统一处理，
## 而不是在 wing() 里给每个坐标手写两次符号。
static func _mirror_x(target: Dictionary) -> void:
	_apply(target, func(point: Vector2) -> Vector2: return Vector2(-point.x, point.y))

static func _translate(target: Dictionary, offset: Vector2) -> void:
	if offset == Vector2.ZERO:
		return
	_apply(target, func(point: Vector2) -> Vector2: return point + offset)

static func _apply(target: Dictionary, transform: Callable) -> void:
	for key in ["strokes", "fills"]:
		var shapes: Array = target[key]
		for index in shapes.size():
			var points: PackedVector2Array = shapes[index]
			for point_index in points.size():
				points[point_index] = transform.call(points[point_index]) as Vector2
			shapes[index] = points

## 把纹样画到 canvas 上。渲染端只需要这一句 —— strokes / fills 的循环只写一份，
## 免得两个装饰类各抄一遍、各错一处。
static func paint(
	canvas: CanvasItem,
	target: Dictionary,
	colour: Color,
	width: float = 1.6,
	offset: Vector2 = Vector2.ZERO
) -> void:
	for fill in (target.get("fills", []) as Array):
		var shape := _shifted(fill as PackedVector2Array, offset)
		if shape.size() >= 3:
			canvas.draw_colored_polygon(shape, colour)
	for stroke in (target.get("strokes", []) as Array):
		var line := _shifted(stroke as PackedVector2Array, offset)
		if line.size() >= 2:
			canvas.draw_polyline(line, colour, width, true)

static func _shifted(points: PackedVector2Array, offset: Vector2) -> PackedVector2Array:
	if offset == Vector2.ZERO:
		return points
	var result := PackedVector2Array()
	result.resize(points.size())
	for index in points.size():
		result[index] = points[index] + offset
	return result

static func _quad(a: Vector2, control: Vector2, b: Vector2, t: float) -> Vector2:
	var mt := 1.0 - t
	return a * (mt * mt) + control * (2.0 * mt * t) + b * (t * t)

static func _quad_tangent(a: Vector2, control: Vector2, b: Vector2, t: float) -> Vector2:
	var mt := 1.0 - t
	return (control - a) * (2.0 * mt) + (b - control) * (2.0 * t)
