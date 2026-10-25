extends RefCounted

# 三路路面的几何生成器。
#
# 为什么单独抽一个模块：路面原来在 arena.gd 里用一个 `_lane_ribbon` 现拼三角形，
# 结果**绕序反了** —— Godot 的 CULL_BACK 把「右手定则法线朝向相机」的三角形当背面剔掉，
# 于是网格一直在、屏幕上却一根路都没有（战场里只剩一整片草地，
# 和小地图上清清楚楚的三条路完全对不上）。绕序是纯几何问题，必须能用断言守住，
# 不能靠在战场里瞪着眼睛找。抽出来之后 test_lane_road.gd 就能直接算三角形法线。
#
# 宽度契约：**画出来的路面宽度 = 模拟层的路宽**（MapData.LANE_HALF_WIDTH × 2）。
# 路肩只是视觉过渡，铺在路面底下、比路面各宽出 0.6m；
# 中央走道只是提亮，比路面窄。这两层都不能改「路面」的宽度定义，
# 否则会出现「看着站在路上，判定却在野区」。

const MapData = preload("res://sim/map_data.gd")

# 三层铺装高度（米）。必须递增且不共面：共面的两层在远处会 z-fighting，
# 表现为路面闪烁成一片斑；抬太高又会变成一块悬空的板。
const SURFACE_Y := 0.045
const LAYER_HEIGHTS := [0.035, 0.045, 0.055]
# 各层相对「路面半宽」的倍率：路肩 1.30（外扩 1.1m）/ 路面 1.0 / 中央走道 0.78。
const LAYER_WIDTH_SCALE := [1.30, 1.0, 0.78]
const LAYER_NAMES := ["shoulder", "surface", "center"]

# 路缘石贴着路缘再向外 0.35m 落地，间隔 2.2m、每块 2.05m 长 —— 几乎连成一条矮石沿。
# 之前试过 5.5m 一墩，画面里是散落的方块，读不出「路沿」，反而像路上的杂物。
const EDGE_STONE_INSET := 0.35
const EDGE_STONE_SPACING := 2.2
# 两端各留 9m 不放路缘石：基地广场半径 8.6，石墩会压在广场上。
const EDGE_STONE_MARGIN := 9.0

const UV_PER_METER := 0.14

static func surface_half_width() -> float:
	return float(MapData.LANE_HALF_WIDTH)

static func layer_heights() -> Array:
	return LAYER_HEIGHTS.duplicate()

static func layer_half_widths() -> Array:
	var half := surface_half_width()
	var widths: Array = []
	for scale in LAYER_WIDTH_SCALE:
		widths.append(half * float(scale))
	return widths

# 路径上每个点的左 / 右边缘偏移。
# 拐角用斜接（miter）：把相邻两段的法线加起来归一化，再按 1/cos(θ/2) 拉长，
# 这样拐角处路面宽度不变、外侧的楔形缺口也不会漏出草地。
# 纯三角形拼的四边形带子做不到这一点，拐角外侧会透出一条草地缝。
static func _edges(path: Array) -> Dictionary:
	var count := path.size()
	var left: Array = []
	var right: Array = []
	for index in count:
		var prev: Vector2 = path[maxi(index - 1, 0)]
		var next: Vector2 = path[mini(index + 1, count - 1)]
		var dir := next - prev
		if dir.length_squared() < 0.000001:
			dir = Vector2(1.0, 0.0)
		dir = dir.normalized()
		var normal := Vector2(-dir.y, dir.x)
		var scale := 1.0
		if index > 0 and index < count - 1:
			var d0: Vector2 = ((path[index] as Vector2) - (path[index - 1] as Vector2))
			var d1: Vector2 = ((path[index + 1] as Vector2) - (path[index] as Vector2))
			if d0.length_squared() > 0.000001 and d1.length_squared() > 0.000001:
				var n0 := Vector2(-d0.normalized().y, d0.normalized().x)
				var n1 := Vector2(-d1.normalized().y, d1.normalized().x)
				var miter := n0 + n1
				if miter.length_squared() > 0.000001:
					miter = miter.normalized()
					# 尖角（接近 180° 折返）不要把斜接拉到天上，夹到 2.86 倍。
					scale = 1.0 / clampf(miter.dot(n0), 0.35, 1.0)
					normal = miter
		left.append(normal * scale)
		right.append(-normal * scale)
	return {"left": left, "right": right}

# 连续带（每个路点只出一对顶点，相邻路点共用），返回顶点与 UV。
# 连续带是「拐角不漏缝」的前提：按段各生成一个四边形，段与段之间必然留缝。
static func ribbon(path: Array, width: float, height: float) -> Dictionary:
	var points := PackedVector3Array()
	var uvs := PackedVector2Array()
	if path.size() < 2:
		return {"points": points, "uvs": uvs}
	var half := width * 0.5
	var edges := _edges(path)
	var left: Array = edges.left
	var right: Array = edges.right

	var station_left: Array = []
	var station_right: Array = []
	var station_v: Array = []
	var travelled := 0.0
	for index in path.size():
		if index > 0:
			travelled += (path[index] as Vector2).distance_to(path[index - 1])
		var center: Vector2 = path[index]
		station_left.append(Vector3(center.x + (left[index] as Vector2).x * half, height,
			center.y + (left[index] as Vector2).y * half))
		station_right.append(Vector3(center.x + (right[index] as Vector2).x * half, height,
			center.y + (right[index] as Vector2).y * half))
		station_v.append(travelled * UV_PER_METER)

	for index in path.size() - 1:
		var a_l: Vector3 = station_left[index]
		var a_r: Vector3 = station_right[index]
		var b_l: Vector3 = station_left[index + 1]
		var b_r: Vector3 = station_right[index + 1]
		var a_v := float(station_v[index])
		var b_v := float(station_v[index + 1])
		# 绕序：Godot 的正面 = 右手定则法线**背对**相机。
		# 相机在上方，所以路面三角形的法线必须朝下（-Y），
		# 和 terrain_builder 的地形网格同一个方向。写反了整片路会被背面剔除。
		points.append(a_l)
		points.append(a_r)
		points.append(b_l)
		uvs.append(Vector2(0.0, a_v))
		uvs.append(Vector2(1.0, a_v))
		uvs.append(Vector2(0.0, b_v))

		points.append(a_r)
		points.append(b_r)
		points.append(b_l)
		uvs.append(Vector2(1.0, a_v))
		uvs.append(Vector2(1.0, b_v))
		uvs.append(Vector2(0.0, b_v))
	return {"points": points, "uvs": uvs}

static func ribbon_triangles(path: Array, width: float, height: float) -> PackedVector3Array:
	return ribbon(path, width, height).points as PackedVector3Array

# 路径上离 point 最近的位置，返回它到起点的弧长。
# 桥心必须压在跨河点上，而跨河点是按**原始折线**算的；路面用的是平滑后的路径，
# 两者在拐角处差一米多。先投影到可见路面上，桥才不会整座偏到路肩外。
static func nearest_arc(path: Array, point: Vector2) -> float:
	var best_distance := INF
	var best_arc := 0.0
	var travelled := 0.0
	for index in path.size() - 1:
		var a: Vector2 = path[index]
		var b: Vector2 = path[index + 1]
		var ab := b - a
		var length_sq := ab.length_squared()
		if length_sq <= 0.000001:
			continue
		var t := clampf((point - a).dot(ab) / length_sq, 0.0, 1.0)
		var distance := point.distance_squared_to(a + ab * t)
		if distance < best_distance:
			best_distance = distance
			best_arc = travelled + ab.length() * t
		travelled += ab.length()
	return best_arc

# 以 point 的投影为心截取一段折线（前后各 half_span 米）。
# 端点插值到精确弧长上，所以截出来的带子首尾都垂直于路面 —— 桥端才不是斜口。
static func slice_around(path: Array, point: Vector2, half_span: float) -> Array:
	if path.size() < 2:
		return path.duplicate()
	var center := nearest_arc(path, point)
	var total := path_length(path)
	return section(path, maxf(center - half_span, 0.0), minf(center + half_span, total))

static func section(path: Array, start: float, end: float) -> Array:
	var out: Array = []
	if path.size() < 2 or end - start <= 0.0001:
		return out
	var travelled := 0.0
	var started := false
	for index in path.size() - 1:
		var a: Vector2 = path[index]
		var b: Vector2 = path[index + 1]
		var segment := a.distance_to(b)
		if segment <= 0.000001:
			continue
		var segment_start := travelled
		var segment_end := travelled + segment
		travelled = segment_end
		if segment_end < start:
			continue
		if segment_start > end:
			break
		if not started:
			var t_start := clampf((start - segment_start) / segment, 0.0, 1.0)
			out.append(a.lerp(b, t_start))
			started = true
		var t_end := clampf((end - segment_start) / segment, 0.0, 1.0)
		if t_end < 1.0:
			out.append(a.lerp(b, t_end))
			break
		if (out[out.size() - 1] as Vector2).distance_to(b) > 0.0001:
			out.append(b)
	return out

# 平行于路径、偏移 offset 米（正数往左法线方向）。斜接量与 ribbon 完全一致，
# 所以桥护栏和桥面边缘在任何拐角上都是同一条曲率。
static func offset_path(path: Array, offset: float) -> Array:
	var out: Array = []
	if path.size() < 2:
		return path.duplicate()
	var edges := _edges(path)
	var left: Array = edges.left
	for index in path.size():
		out.append((path[index] as Vector2) + (left[index] as Vector2) * offset)
	return out

# 沿路径按弧长等距取点（不受路点疏密影响，石墩间隔才是均匀的）。
static func sample(path: Array, distance: float) -> Dictionary:
	var travelled := 0.0
	for index in path.size() - 1:
		var a: Vector2 = path[index]
		var b: Vector2 = path[index + 1]
		var segment := a.distance_to(b)
		if segment < 0.0001:
			continue
		if travelled + segment >= distance or index == path.size() - 2:
			var t := clampf((distance - travelled) / segment, 0.0, 1.0)
			var dir := (b - a) / segment
			return {"pos": a.lerp(b, t), "dir": dir}
		travelled += segment
	var last: Vector2 = path[path.size() - 2]
	return {"pos": path[path.size() - 1], "dir": (path[path.size() - 1] - last).normalized()}

static func path_length(path: Array) -> float:
	var total := 0.0
	for index in path.size() - 1:
		total += (path[index + 1] as Vector2).distance_to(path[index])
	return total

# 路缘石：两侧成对，贴着路缘向外 0.35m。
# 返回 [{pos: Vector2, offset: float（带符号，负=左侧）, yaw: float}]。
static func edge_stones(path: Array, width: float, spacing := EDGE_STONE_SPACING) -> Array:
	var stones: Array = []
	if path.size() < 2:
		return stones
	var half := width * 0.5
	var total := path_length(path)
	if total <= EDGE_STONE_MARGIN * 2.0 + spacing:
		return stones
	var reach := half + EDGE_STONE_INSET
	var step := maxf(spacing, 1.0)
	var travelled := EDGE_STONE_MARGIN
	while travelled <= total - EDGE_STONE_MARGIN:
		var station := sample(path, travelled)
		var dir: Vector2 = station.dir
		var normal := Vector2(-dir.y, dir.x)
		var pos: Vector2 = station.pos
		var yaw := -atan2(dir.y, dir.x)
		# arc 让上层能按桥的弧长窗口把桥面上的石墩剔掉（桥有自己的护栏）。
		stones.append({"pos": pos + normal * reach, "offset": reach, "yaw": yaw, "arc": travelled})
		stones.append({"pos": pos - normal * reach, "offset": -reach, "yaw": yaw, "arc": travelled})
		travelled += step
	return stones
