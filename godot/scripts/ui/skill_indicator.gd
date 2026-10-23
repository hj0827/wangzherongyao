extends RefCounted

static func generate_circle_points(radius: float, resolution: int = 24) -> PackedVector2Array:
	var points := PackedVector2Array()
	var step := (PI * 2.0) / float(maxi(3, resolution))
	for i in resolution:
		var theta := float(i) * step
		points.append(Vector2(cos(theta), sin(theta)) * radius)
	return points

static func is_inside_circle(point: Vector2, center: Vector2, radius: float) -> bool:
	return point.distance_to(center) <= radius

static func generate_line_points(start: Vector2, direction: Vector2, length: float, width: float) -> PackedVector2Array:
	var dir := direction.normalized()
	if dir == Vector2.ZERO:
		dir = Vector2.UP
	var side := Vector2(-dir.y, dir.x) * (width * 0.5)
	var end := start + dir * length
	var corners := PackedVector2Array()
	corners.append(start + side)
	corners.append(start - side)
	corners.append(end - side)
	corners.append(end + side)
	return corners

static func is_inside_line(point: Vector2, start: Vector2, direction: Vector2, length: float, width: float) -> bool:
	var dir := direction.normalized()
	if dir == Vector2.ZERO:
		dir = Vector2.UP
	var to_p := point - start
	var proj := to_p.dot(dir)
	if proj < 0.0 or proj > length:
		return false
	var side_dist := (to_p - dir * proj).length()
	return side_dist <= (width * 0.5)

static func generate_cone_points(origin: Vector2, direction: Vector2, range_val: float, angle_deg: float, resolution: int = 12) -> PackedVector2Array:
	var points := PackedVector2Array()
	points.append(origin)
	var dir := direction.normalized()
	if dir == Vector2.ZERO:
		dir = Vector2.UP
	var base_angle := dir.angle()
	var half_angle_rad := deg_to_rad(angle_deg * 0.5)
	var count := maxi(2, resolution)
	for i in (count + 1):
		var t := float(i) / float(count)
		var angle := base_angle - half_angle_rad + t * (half_angle_rad * 2.0)
		points.append(origin + Vector2(cos(angle), sin(angle)) * range_val)
	return points

static func is_inside_cone(point: Vector2, origin: Vector2, direction: Vector2, range_val: float, angle_deg: float) -> bool:
	var to_p := point - origin
	var dist := to_p.length()
	if dist > range_val or dist <= 0.001:
		return false
	var dir := direction.normalized()
	if dir == Vector2.ZERO:
		dir = Vector2.UP
	var cos_threshold := cos(deg_to_rad(angle_deg * 0.5))
	return dir.dot(to_p.normalized()) >= cos_threshold
