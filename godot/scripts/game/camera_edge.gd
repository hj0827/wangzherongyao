extends RefCounted

# 相机注视点的「贴边内推」。
#
# 问题：注视点刚性跟着英雄，英雄贴到边界墙时，相机（在英雄身后 0.76×zoom）会跟着
# 一起贴过去 —— 近侧墙变成「从墙外往里看」，墙占了小半屏，墙外草地也露一大块；
# 左右两侧更糟：横屏的水平视野比垂直宽得多，贴左右墙时墙外草地能占到三分之一屏。
#
# 解法：注视点靠近可走边界时，按接近程度往地图中心推，最多推 EDGE_INSET_RATIO×zoom。
# 这一步只动相机，**不动可走边界** —— 模拟层的 clamp_bounds 是联机同步的，
# 相机朝向每个客户端都不一样（蓝方朝 +z、红方朝 -z），边距一旦跟方向相关就会不同步。
#
# 副作用是英雄贴墙时不在画面正中。这是有意的：贴着墙还要求画面以自己为中心，
# 等价于要求「墙外也要看到一大片」，两件事不能同时成立。
#
# 近侧（相机后方那一侧）要特殊处理：那一侧墙外露出来的**是墙自己**，不是草地 ——
# 压暗对墙不起作用，而内推又会把英雄往画面里拽、反而看起来离墙更远。
# 所以近侧只推一小部分，远侧和左右推满。

const MapData = preload("res://sim/map_data.gd")

## 贴到可走极限时，注视点往地图中心推的距离 = 这个比例 × zoom。
## 0.24 × 21 ≈ 5 米：左右两侧墙外草地基本收干净，英雄偏到画面 60~70% 处。
const EDGE_INSET_RATIO := 0.24
## 近侧的内推倍率。**0 是有意的**：实测内推 1.8 米之后，墙外草地只少了 30px，
## 但墙的立面在屏幕上反而高了一截（相机离墙更远、视线更平，能看到更多立面），
## 而英雄被从墙边拽开 50px —— 三件事全都往坏的方向走。
## 近侧露出来的本来就是墙自己，压暗对它无效，也不该压暗。
const NEAR_INSET_SCALE := 0.0
## 从离可走极限多远开始内推（米）。
## 不能大：边路中心在 |pos| = 50，可走极限 53.65 —— 过渡带一旦宽到十几米，
## 沿边路正常走路时画面就会一直往内偏，玩家会以为镜头坏了。
## 4 米让「边路上走」只偏 0.1 米，真正贴到墙根才推满。
const EDGE_SPAN := 4.0

## 把注视点按贴边程度往地图中心推。
## point 是注视点（世界坐标），zoom 是当前机位缩放，forward 是相机朝向（只用到 z 分量）。
static func inset(point: Vector3, zoom: float, forward: Vector3) -> Vector3:
	var limit := MapData.BOUNDS - MapData.CAMERA_WALL_MARGIN
	var amount := maxf(0.0, EDGE_INSET_RATIO * zoom)
	if amount <= 0.0:
		return point
	# 相机在 +forward 方向看，近侧就是 -forward 那一侧。
	var near_sign := -signf(forward.z)
	var z_amount := amount * (NEAR_INSET_SCALE if signf(point.z) == near_sign else 1.0)
	return Vector3(_axis(point.x, limit, amount), point.y, _axis(point.z, limit, z_amount))

## 单轴内推。用 smoothstep 而不是线性：线性在「刚开始内推」那一点有折角，
## 玩家贴着边界走时会看到画面速度突变。
static func _axis(value: float, limit: float, amount: float) -> float:
	var dist := absf(value)
	var start := limit - EDGE_SPAN
	if dist <= start or amount <= 0.0:
		return value
	var t := clampf((dist - start) / EDGE_SPAN, 0.0, 1.0)
	var eased := t * t * (3.0 - 2.0 * t)
	return value - signf(value) * amount * eased

## 某个坐标的「贴边程度」0..1。测试与探针用它判断内推是否真的生效。
static func edge_factor(value: float) -> float:
	var limit := MapData.BOUNDS - MapData.CAMERA_WALL_MARGIN
	var start := limit - EDGE_SPAN
	if absf(value) <= start:
		return 0.0
	return clampf((absf(value) - start) / EDGE_SPAN, 0.0, 1.0)
