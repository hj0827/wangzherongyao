extends "res://tests/test_base.gd"

# 相机贴边内推的回归守卫。
#
# 起因：注视点刚性跟英雄，英雄贴到边界墙时相机跟着贴过去 ——
# 左右两侧墙外草地能占到三分之一屏，上下还因为透视压缩看起来完全不一样。
#
# 契约：注视点靠近可走边界时往地图中心推，**只动相机不动可走边界**。
# 可走边界是联机同步的（clamp_bounds 在模拟层），相机朝向每个客户端不同
# （蓝方朝 +z、红方朝 -z），一旦把边距做成跟方向相关就会不同步。

const CameraEdge = preload("res://scripts/game/camera_edge.gd")
const MapData = preload("res://sim/map_data.gd")

const BLUE_FORWARD := Vector3(0.0, 0.0, 1.0)
const RED_FORWARD := Vector3(0.0, 0.0, -1.0)

func _limit() -> float:
	return MapData.BOUNDS - MapData.CAMERA_WALL_MARGIN

func test_far_side_gets_full_inset() -> void:
	# 蓝方朝 +z 看，+z 那面墙是远侧（画面上方）：推满。
	var point := Vector3(0.0, 0.0, _limit())
	var out := CameraEdge.inset(point, 21.0, BLUE_FORWARD)
	near(out.z, _limit() - CameraEdge.EDGE_INSET_RATIO * 21.0, 0.001, "远侧贴墙必须内推满量")
	near(out.x, 0.0, 0.001, "没贴边的那一轴不能动")
	near(out.y, 0.0, 0.001, "高度不参与内推")

func test_near_side_is_left_alone() -> void:
	# 近侧（相机后方那面墙）露出来的是墙自己，内推只会把英雄从墙边拽开。
	var point := Vector3(0.0, 0.0, -_limit())
	var out := CameraEdge.inset(point, 21.0, BLUE_FORWARD)
	near(out.z, -_limit(), 0.001, "近侧不该内推")
	# 换红方（朝 -z）之后，近侧变成 +z：同一面墙的角色互换，这是对的。
	var flipped := CameraEdge.inset(Vector3(0.0, 0.0, _limit()), 21.0, RED_FORWARD)
	near(flipped.z, _limit(), 0.001, "红方的近侧是 +z，同样不内推")

func test_side_walls_get_full_inset() -> void:
	# 左右两侧与相机朝向无关，两个队伍都推满。
	for forward in [BLUE_FORWARD, RED_FORWARD]:
		var out := CameraEdge.inset(Vector3(_limit(), 0.0, 0.0), 21.0, forward)
		near(out.x, _limit() - CameraEdge.EDGE_INSET_RATIO * 21.0, 0.001, "左右贴墙必须内推满量")

func test_walking_the_lane_does_not_move_the_camera() -> void:
	# 边路中心在 |pos| = 50，可走极限 53.65。过渡带一旦宽到十几米，
	# 沿边路正常走路时画面会一直往内偏 —— 那比贴墙时露出墙外更难受。
	var point := Vector3(50.0, 0.0, 0.0)
	var out := CameraEdge.inset(point, 21.0, BLUE_FORWARD)
	lt(absf(out.x - 50.0), 0.2, "边路上走路时镜头偏移必须小于 0.2 米")
	# 而真正贴到墙根时必须推满 —— 否则过渡带只是把问题推迟了几米。
	var at_wall := CameraEdge.inset(Vector3(_limit(), 0.0, 0.0), 21.0, BLUE_FORWARD)
	near(at_wall.x, _limit() - CameraEdge.EDGE_INSET_RATIO * 21.0, 0.001, "贴到墙根必须推满")

func test_inset_is_monotonic_and_has_no_jump() -> void:
	# 内推量随贴边程度单调不降，且相邻采样之间没有跳变。
	var previous := 0.0
	var steps := 100
	for i in steps + 1:
		var value := 40.0 + (_limit() - 40.0) * float(i) / float(steps)
		var out := CameraEdge.inset(Vector3(value, 0.0, 0.0), 21.0, BLUE_FORWARD)
		var inset := value - out.x
		check(inset >= -0.001, "内推量不能为负：%.2f" % value)
		check(inset >= previous - 0.001, "内推量必须单调不降：%.2f 处回退了" % value)
		lt(inset - previous, 0.4, "相邻采样之间不能跳变：%.2f 处跳了 %.3f" % [value, inset - previous])
		previous = inset

func test_inset_never_pulls_the_focus_across_the_center() -> void:
	# 极端情况：注视点本来就在中心附近，内推不能把它推到另一侧。
	for value in [0.0, 0.5, 2.0, -0.5]:
		var out := CameraEdge.inset(Vector3(value, 0.0, 0.0), 21.0, BLUE_FORWARD)
		near(out.x, value, 0.001, "中心附近不该有内推：%.2f" % value)

func test_inset_scales_with_zoom() -> void:
	# 视野越宽（zoom 越大），同样的贴边要推得越多，否则墙外露出的绝对面积更大。
	var point := Vector3(_limit(), 0.0, 0.0)
	var near_zoom := CameraEdge.inset(point, 14.0, BLUE_FORWARD)
	var far_zoom := CameraEdge.inset(point, 34.0, BLUE_FORWARD)
	gt(_limit() - far_zoom.x, _limit() - near_zoom.x, "zoom 越大内推越多")

func test_arena_camera_actually_uses_the_inset() -> void:
	# "模块在 + 测试绿" ≠ "生产真的调了"。_update_camera 里必须接上。
	#
	# 注意不能直接 contains("CameraEdge.inset(")：把调用**注释掉**之后字符串还在，
	# 守卫会假绿（这条被变异验证抓过一次）。必须逐行看，跳过注释行。
	var source := FileAccess.get_file_as_string("res://scripts/game/arena.gd")
	check(source.contains("const CameraEdge = preload("), "arena 必须 preload camera_edge.gd")
	check(has_live_line(source, "CameraEdge.inset("), "相机的注视点必须真的经过 CameraEdge.inset（不是写在注释里）")
