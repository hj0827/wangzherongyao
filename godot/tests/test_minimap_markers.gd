extends "res://tests/test_base.gd"

## 小地图英雄朝向标记（2026-10-24）。
##
## 原来每个英雄就是一个圆点：打起来分不清「谁在往哪走」，敌方从哪边压过来只能靠猜。
## 王者荣耀的小地图英雄是带朝向的箭头，这条把朝向变成可断言的几何。

const Minimap = preload("res://scripts/ui/minimap.gd")

func _shoelace(poly: PackedVector2Array) -> float:
	var total := 0.0
	for i in poly.size():
		var a := poly[i]
		var b := poly[(i + 1) % poly.size()]
		total += a.x * b.y - b.x * a.y
	return absf(total) * 0.5

func test_arrow_tip_points_along_facing() -> void:
	for facing in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1), Vector2(0.7071, 0.7071)]:
		var poly := Minimap.hero_arrow(Vector2.ZERO, facing, 6.0)
		check(poly.size() >= 3, "the marker needs at least a triangle for %s" % facing)
		var tip := poly[0]
		gt(tip.normalized().dot(facing.normalized()), 0.98, "the tip must sit on the facing axis (%s)" % facing)
		gt(tip.length(), 5.0, "the tip must reach the marker radius (%s)" % facing)
		lt(tip.length(), 7.0, "the tip must not overshoot the marker radius (%s)" % facing)

func test_arrow_has_area_and_is_not_a_line() -> void:
	var poly := Minimap.hero_arrow(Vector2.ZERO, Vector2(1, 0), 6.0)
	gt(_shoelace(poly), 8.0, "the marker must be a filled arrow, not a degenerate sliver")
	# 朝向变化必须真的改变形状，不能永远是同一块。
	var rotated := Minimap.hero_arrow(Vector2.ZERO, Vector2(0, 1), 6.0)
	gt(poly[1].distance_to(rotated[1]), 3.0, "rotating the facing must rotate the wings")

func test_arrow_is_symmetric_around_the_facing_axis() -> void:
	var radius := 6.0
	var poly := Minimap.hero_arrow(Vector2.ZERO, Vector2(1, 0), radius)
	# 左右翼到朝向轴的垂直距离必须相等，否则箭头看起来是歪的。
	var axis := Vector2(1, 0)
	var left := poly[1] - axis * poly[1].dot(axis)
	var right := poly[poly.size() - 1] - axis * poly[poly.size() - 1].dot(axis)
	near(absf(left.y), absf(right.y), 0.01, "the wings must mirror each other")
	gt(absf(left.y), radius * 0.4, "the wings must actually spread")

func test_arrow_scales_with_the_marker() -> void:
	var small := Minimap.hero_arrow(Vector2.ZERO, Vector2(1, 0), 4.0)
	var large := Minimap.hero_arrow(Vector2.ZERO, Vector2(1, 0), 8.0)
	near(large[0].length() / small[0].length(), 2.0, 0.05, "the arrow scales with the marker radius")
	near(large[1].y / small[1].y, 2.0, 0.05, "the wings scale too")

func test_zero_facing_falls_back_instead_of_collapsing() -> void:
	# 出生瞬间 / 传送落地时 facing 可能是 (0,0)。不能画出 NaN 或零面积。
	var poly := Minimap.hero_arrow(Vector2.ZERO, Vector2.ZERO, 6.0)
	check(poly.size() >= 3, "a zero facing must still produce a polygon")
	gt(_shoelace(poly), 8.0, "a zero facing must fall back to a real arrow")
	for point in poly:
		check(not is_nan(point.x) and not is_nan(point.y), "the marker must not contain NaN")
