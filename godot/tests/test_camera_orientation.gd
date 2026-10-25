extends "res://tests/test_base.gd"

# 主视角的朝向 ↔ 小地图的朝向。
#
# 起因：小地图上清清楚楚「上边横着一条、中间一条斜的、右边竖着一条」，
# 进战场却变成「45° 斜 / 正竖 / 45° 斜」—— 整张地图相对小地图被拧了 45°。
#
# 根因不在路本身（两边吃的是同一份 lane_path），在相机 yaw：
# `_camera_forward()` 跟着「蓝方基地 → 红方基地」那条对角线走。
# 于是「世界 X 轴」被拍成了屏幕上的 45° 斜线，而中路（世界 45°）反而被拍成正竖线。
# 小地图是「正北朝上、坐标轴对齐」的正方形投影，两者自然差 45°。
#
# 这里的契约（改之前全都红）：
#   1. 相机 yaw 必须和地图坐标轴对齐 —— 朝向不能带横向分量，也不能 roll；
#   2. 世界 +X 的位移只能落在屏幕水平方向，世界 +Y 只能落在屏幕垂直方向；
#   3. 站在路上看，每一段路的「屏幕倾角」都必须贴近它在小地图上的倾角，
#      只允许俯角透视带来的压缩（当前 51° 俯角 ≈ 7° 以内），不允许整体旋转。

const Arena = preload("res://scripts/game/arena.gd")
const MapData = preload("res://sim/map_data.gd")

const ZOOM := 21.0
# 相机 pitch = atan(0.94 / 0.76) = 51.04°，地面位移沿纵深方向被压 sin(51°) = 0.7776。
# 45° 的路在屏幕上会变成 atan(0.7776 × tan45°) = 37.9°，即最多差 7.1°。
const MAX_TILT_ERROR := 8.5

func _forward_for(team: String) -> Vector3:
	var arena = Arena.new()
	arena.local_team = team
	var forward: Vector3 = arena._camera_forward()
	arena.free()
	return forward

# 平面透视投影：返回以画面中心为原点、Y 向上的屏幕坐标。
func _project(xform: Transform3D, world: Vector2) -> Vector2:
	var local: Vector3 = xform.affine_inverse() * Vector3(world.x, 0.05, world.y)
	var depth := -local.z
	if depth <= 0.01:
		return Vector2(INF, INF)
	return Vector2(local.x / depth, local.y / depth)

func _screen_angle(a: Vector2, b: Vector2) -> float:
	var angle := rad_to_deg(atan2(b.y - a.y, b.x - a.x))
	return fposmod(angle, 180.0)

# 小地图是 x 向右、y 向下（正方形、等比，没有压缩），
# 所以「小地图上的倾角」就是把世界方向换成 Y 向上之后的 atan2。
func _minimap_angle(a: Vector2, b: Vector2) -> float:
	return fposmod(rad_to_deg(atan2(-(b.y - a.y), b.x - a.x)), 180.0)

func test_camera_yaw_follows_the_map_axes_not_the_base_diagonal() -> void:
	# 相机 yaw 一旦跟着基地对角线走，世界里沿坐标轴铺出来的路在屏幕上就全是 45° 斜线。
	for team in ["blue", "red"]:
		var forward := _forward_for(team)
		near(forward.x, 0.0, 0.001,
			"%s 方相机朝向不能带 X 分量（否则整张地图相对小地图被转 45°）" % team)
		near(forward.y, 0.0, 0.001,
			"%s 方相机朝向必须贴着地面（不能抬头低头）" % team)
		near(absf(forward.z), 1.0, 0.001,
			"%s 方相机必须沿世界 Y 轴看（世界 X → 屏幕水平，世界 Y → 屏幕垂直）" % team)

func test_camera_looks_from_own_base_into_the_enemy_half() -> void:
	# 对齐坐标轴之后仍然要「从自家基地往敌方看」，否则会对着身后那道墙。
	for team in ["blue", "red"]:
		var forward := _forward_for(team)
		var own: Vector2 = MapData.BLUE_BASE if team == "blue" else MapData.RED_BASE
		var enemy: Vector2 = MapData.RED_BASE if team == "blue" else MapData.BLUE_BASE
		var to_enemy := (enemy - own).normalized()
		var flat := Vector2(forward.x, forward.z).normalized()
		gt(flat.dot(to_enemy), 0.6,
			"%s 方相机的朝向必须指向敌方半场（当前点积 %.2f）" % [team, flat.dot(to_enemy)])

func test_camera_has_no_roll() -> void:
	# 有 roll 的话地平线是歪的，路的倾角也会跟着歪。
	for team in ["blue", "red"]:
		var xform: Transform3D = Arena.camera_placement(Vector3.ZERO, _forward_for(team), ZOOM)
		near(xform.basis.y.x, 0.0, 0.0001, "%s 方相机不能有侧倾（roll）" % team)

func test_world_x_projects_to_the_screen_horizontal() -> void:
	# 纯 X 位移上所有点的景深相同 —— 所以这一条是精确断言，不是近似。
	var xform: Transform3D = Arena.camera_placement(Vector3.ZERO, _forward_for("blue"), ZOOM)
	var left := _project(xform, Vector2(-8.0, 0.0))
	var right := _project(xform, Vector2(8.0, 0.0))
	near(right.y - left.y, 0.0, 0.0005, "沿世界 X 走的位移必须严格落在屏幕水平方向")
	gt(absf(right.x - left.x), 0.05, "沿世界 X 走的位移必须有可见的横向位移")

func test_world_y_projects_to_the_screen_vertical() -> void:
	var xform: Transform3D = Arena.camera_placement(Vector3.ZERO, _forward_for("blue"), ZOOM)
	var near_point := _project(xform, Vector2(0.0, -8.0))
	var far_point := _project(xform, Vector2(0.0, 8.0))
	near(far_point.x - near_point.x, 0.0, 0.0005, "沿世界 Y 走的位移必须严格落在屏幕垂直方向")
	gt(absf(far_point.y - near_point.y), 0.02, "沿世界 Y 走的位移必须有可见的纵向位移")

func test_mid_lane_is_a_diagonal_like_the_minimap_not_a_vertical_line() -> void:
	# 中路是唯一一条「斜」的路：小地图上 45°，屏幕上应该还是斜的（俯角压到 ~38°）。
	# 修之前它是 90°（正竖线）—— 这就是玩家一眼看出来的那股别扭。
	for team in ["blue", "red"]:
		var xform: Transform3D = Arena.camera_placement(Vector3.ZERO, _forward_for(team), ZOOM)
		var path: Array = MapData.lane_path("mid")
		# 取最靠近地图中心的一段（画面中心附近没有边缘透视畸变）
		var best_index := 0
		var best_distance := INF
		for index in range(path.size() - 1):
			var mid: Vector2 = (path[index] + path[index + 1]) * 0.5
			if mid.length() < best_distance:
				best_distance = mid.length()
				best_index = index
		var a: Vector2 = path[best_index]
		var b: Vector2 = path[best_index + 1]
		var screen_angle := _screen_angle(_project(xform, a), _project(xform, b))
		var map_angle := _minimap_angle(a, b)
		near(map_angle, 45.0, 0.5, "小地图上中路是 45° 斜线（正方形投影，不压缩）")
		var delta := absf(screen_angle - map_angle)
		if delta > 90.0:
			delta = 180.0 - delta
		lt(delta, MAX_TILT_ERROR,
			"%s 方视角里中路的屏幕倾角必须贴近小地图的 45°（屏幕 %.1f° / 小地图 %.1f°）"
			% [team, screen_angle, map_angle])
		gt(absf(screen_angle - 90.0), 20.0,
			"%s 方视角里中路不能是正竖线（屏幕 %.1f°）" % [team, screen_angle])

func test_every_lane_segment_keeps_the_minimap_tilt_on_screen() -> void:
	# 站在某一段路上时（相机就悬在它头顶），这一段在屏幕上的倾角必须和小地图一致，
	# 只允许俯角压缩（≤ ~7°）。这是「三条路的倾斜角度和小地图一样」的量化版本。
	for team in ["blue", "red"]:
		var forward := _forward_for(team)
		var worst := 0.0
		var worst_lane := ""
		var worst_screen := 0.0
		var worst_map := 0.0
		for lane in MapData.LANE_ORDER:
			var path: Array = MapData.lane_path(str(lane))
			for index in range(path.size() - 1):
				var a: Vector2 = path[index]
				var b: Vector2 = path[index + 1]
				var mid := (a + b) * 0.5
				var xform: Transform3D = Arena.camera_placement(
					Vector3(mid.x, 0.0, mid.y), forward, ZOOM)
				var screen_angle := _screen_angle(_project(xform, a), _project(xform, b))
				var map_angle := _minimap_angle(a, b)
				var delta := absf(screen_angle - map_angle)
				if delta > 90.0:
					delta = 180.0 - delta
				if delta > worst:
					worst = delta
					worst_lane = str(lane)
					worst_screen = screen_angle
					worst_map = map_angle
		lt(worst, MAX_TILT_ERROR,
			"%s 方：最差的一段是 %s 路（屏幕 %.1f° / 小地图 %.1f°，差 %.1f°）"
			% [team, worst_lane, worst_screen, worst_map, worst])

func test_side_lanes_stay_axis_aligned_on_screen() -> void:
	# 上下路贴着地图外圈走，两段主干分别沿世界 -X（横）和世界 +Y（竖）。
	# 小地图上它们是「横」和「竖」，屏幕上必须同样是「横」和「竖」。
	# 取**最长的轴向段**而不是「出基地那一段」：基地出口是一段 18° 的斜线
	# （4 米内转 90° 会让路面自交，见 MapData.LANES 的注释），
	# 拿它验「水平」验的是错的东西。
	var forward := _forward_for("blue")
	for lane in ["top", "bottom"]:
		var horizontal := _longest_axis_segment(MapData.lane_path(lane), true)
		var vertical := _longest_axis_segment(MapData.lane_path(lane), false)
		gt(float(horizontal.size()), 0.0, "%s 路必须有一段沿世界 X 轴走的主干" % lane)
		gt(float(vertical.size()), 0.0, "%s 路必须有一段沿世界 Y 轴走的主干" % lane)
		var h_mid: Vector2 = ((horizontal[0] as Vector2) + (horizontal[1] as Vector2)) * 0.5
		var h_xform: Transform3D = Arena.camera_placement(Vector3(h_mid.x, 0.0, h_mid.y), forward, ZOOM)
		near(_screen_angle(_project(h_xform, horizontal[0]), _project(h_xform, horizontal[1])), 0.0, 0.6,
			"%s 路沿世界 X 轴的主干在屏幕上必须是水平的" % lane)
		var v_mid: Vector2 = ((vertical[0] as Vector2) + (vertical[1] as Vector2)) * 0.5
		var v_xform: Transform3D = Arena.camera_placement(Vector3(v_mid.x, 0.0, v_mid.y), forward, ZOOM)
		near(_screen_angle(_project(v_xform, vertical[0]), _project(v_xform, vertical[1])), 90.0, 0.6,
			"%s 路沿世界 Y 轴的主干在屏幕上必须是竖直的" % lane)

# 找一条路上最长的「纯水平 / 纯竖直」线段，返回 [a, b]。
func _longest_axis_segment(path: Array, horizontal: bool) -> Array:
	var best: Array = []
	var best_span := 0.0
	for index in range(path.size() - 1):
		var a: Vector2 = path[index]
		var b: Vector2 = path[index + 1]
		var span := a.distance_to(b)
		if span <= best_span:
			continue
		if horizontal and absf(a.y - b.y) > 0.01:
			continue
		if not horizontal and absf(a.x - b.x) > 0.01:
			continue
		best = [a, b]
		best_span = span
	return best
