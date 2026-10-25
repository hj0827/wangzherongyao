extends RefCounted

# 地形碰撞：圆 vs 胶囊墙体。移动采用分步 + 切向滑行，
# 避免单位在墙角停死，也避免高速位移直接穿过墙。

const MapLayout = preload("res://sim/map/map_layout.gd")
const MapData = preload("res://sim/map_data.gd")

const PUSH_ITERATIONS := 4
const MIN_STEP := 0.35

static func is_blocked(point: Vector2, radius: float) -> bool:
	for wall in MapLayout.WALLS:
		var distance := MapLayout.point_to_segment_distance(point, wall.a, wall.b)
		if distance < MapLayout.WALL_THICKNESS * 0.5 + radius:
			return true
	return false

static func resolve_circle(point: Vector2, radius: float) -> Vector2:
	var resolved := clamp_bounds(point, radius)
	for _iteration in PUSH_ITERATIONS:
		var moved := false
		for wall in MapLayout.WALLS:
			var closest := _closest_point(resolved, wall.a, wall.b)
			var delta: Vector2 = resolved - closest
			var min_distance := MapLayout.WALL_THICKNESS * 0.5 + radius
			if delta.length() >= min_distance:
				continue
			var normal := _wall_normal(wall, resolved)
			if delta.length() > 0.0001 and delta.dot(normal) < 0.0:
				normal = -normal
			resolved = closest + normal * (min_distance + 0.01)
			resolved = clamp_bounds(resolved, radius)
			moved = true
		if not moved:
			break
	return resolved

# 从 from 走到 to，遇到墙时保留切向分量，返回最终可站立位置。
static func move(from: Vector2, to: Vector2, radius: float) -> Vector2:
	var current := resolve_circle(from, radius)
	var desired: Vector2 = to - current
	var distance := desired.length()
	if distance < 0.0001:
		return current
	var steps := clampi(int(ceil(distance / maxf(radius * 0.8, MIN_STEP))), 1, 48)
	var step := desired / float(steps)
	for _index in steps:
		var candidate: Vector2 = current + step
		if not is_blocked(candidate, radius):
			current = clamp_bounds(candidate, radius)
			continue
		var wall := _blocking_wall(candidate, radius)
		var normal := _wall_normal(wall, candidate)
		if (current - _closest_point(current, wall.a, wall.b)).dot(normal) < 0.0:
			normal = -normal
		var slide: Vector2 = step - normal * step.dot(normal)
		var slid: Vector2 = current + slide
		if not is_blocked(slid, radius):
			current = clamp_bounds(slid, radius)
		else:
			# 贴墙蠕动时至少把被墙吃掉的法向分量去掉，保留原地而不是穿过去。
			current = resolve_circle(current + step, radius)
	return current

# 视线遮挡：两段线段的最短距离小于墙体半厚（外加可选宽度）即视为被墙挡住。
static func segment_blocked(from: Vector2, to: Vector2, width := 0.0) -> bool:
	for wall in MapLayout.WALLS:
		var limit := MapLayout.WALL_THICKNESS * 0.5 + width
		if Geometry2D.segment_intersects_segment(from, to, wall.a, wall.b):
			return true
		var closest := minf(
			minf(MapLayout.point_to_segment_distance(from, wall.a, wall.b), MapLayout.point_to_segment_distance(to, wall.a, wall.b)),
			minf(MapLayout.point_to_segment_distance(wall.a, from, to), MapLayout.point_to_segment_distance(wall.b, from, to))
		)
		if closest <= limit:
			return true
	return false

static func nearest_free(point: Vector2, radius: float, max_search := 6.0) -> Vector2:
	var clamped := clamp_bounds(point, radius)
	if not is_blocked(clamped, radius):
		return clamped
	var ring := 0.5
	while ring <= max_search:
		var samples := maxi(8, int(ceil(ring * 8.0)))
		for index in samples:
			var angle := TAU * float(index) / float(samples)
			var candidate: Vector2 = clamped + Vector2(cos(angle), sin(angle)) * ring
			candidate = clamp_bounds(candidate, radius)
			if not is_blocked(candidate, radius):
				return candidate
		ring += 0.5
	return resolve_circle(clamped, radius)

static func clamp_bounds(point: Vector2, radius: float) -> Vector2:
	# 除了半径，还要让出相机安全边距：贴到墙根时镜头已经越过边界墙，
	# 墙会把英雄整条盖住（见 MapData.CAMERA_WALL_MARGIN）。
	var limit: float = maxf(MapData.BOUNDS - radius - MapData.CAMERA_WALL_MARGIN, 0.0)
	return Vector2(clampf(point.x, -limit, limit), clampf(point.y, -limit, limit))

static func _closest_point(point: Vector2, a: Vector2, b: Vector2) -> Vector2:
	var ab := b - a
	var length_sq := ab.length_squared()
	if length_sq < 0.0001:
		return a
	var t := clampf((point - a).dot(ab) / length_sq, 0.0, 1.0)
	return a + ab * t

static func _blocking_wall(point: Vector2, radius: float) -> Dictionary:
	var best := {}
	var best_distance := INF
	for wall in MapLayout.WALLS:
		var distance := MapLayout.point_to_segment_distance(point, wall.a, wall.b)
		if distance < MapLayout.WALL_THICKNESS * 0.5 + radius and distance < best_distance:
			best_distance = distance
			best = wall
	return best

static func _wall_normal(wall: Dictionary, point: Vector2) -> Vector2:
	if wall.is_empty():
		return Vector2.UP
	var segment: Vector2 = wall.b - wall.a
	var normal := Vector2(-segment.y, segment.x).normalized()
	if normal.length() < 0.01:
		return Vector2.UP
	if (point - _closest_point(point, wall.a, wall.b)).dot(normal) < 0.0:
		return -normal
	return normal
