extends "res://tests/test_base.gd"

## 技能键图标（2026-10-24）。
##
## 现状是「深色圆 + 一个字母」，18 种技能长得一模一样 —— 这是整个 HUD 最廉价的地方。
## 项目里没有技能图标素材，所以图标是矢量画的：按技能族（斩击/爆发/位移/防护/射击）
## 给一个可辨识的图形，键位字母降级成右下角的小角标。
##
## 这里断言的是三条几何契约，而不是「好不好看」：
## 1. 每种技能都能落到一个族（不能有空白键）；
## 2. 图形必须待在圆环内侧（超出就会被圆形遮罩切掉）；
## 3. 尺寸必须跟着按钮缩放（写死像素会在手机上糊成一团）。

const SkillGlyph = preload("res://scripts/ui/skill_glyph.gd")

# hero_defs 里出现过的全部 kind，外加召唤师技能。
const KINDS := [
	"slash", "spin", "dash", "leap_slam",
	"burst", "line", "slow", "meteor_storm",
	"quake", "charge", "shield", "taunt_aura",
	"arrow", "aoe_shot", "haste", "arrow_barrage", "evade",
	"summoner", "",
]

func _points_of(shapes: Array) -> Array:
	var points: Array = []
	for shape in shapes:
		match str(shape.get("type", "")):
			"poly":
				for point in shape.get("points", PackedVector2Array()):
					points.append(point)
			"line":
				points.append(shape.get("a", Vector2.ZERO))
				points.append(shape.get("b", Vector2.ZERO))
	return points

func _bounds_of(shapes: Array) -> Rect2:
	var points := _points_of(shapes)
	if points.is_empty():
		return Rect2()
	var box := Rect2(points[0], Vector2.ZERO)
	for point in points:
		box = box.expand(point)
	return box

func test_every_skill_kind_maps_to_a_known_family() -> void:
	var families := ["strike", "burst", "move", "ward", "shot"]
	for kind in KINDS:
		var family := SkillGlyph.family(kind)
		check(families.has(family), "kind '%s' fell out of the family table: %s" % [kind, family])

func test_related_kinds_share_a_family() -> void:
	# 斩击类不该和箭矢类撞脸，但同一族的必须复用（否则 18 张图各画一遍）。
	eq(SkillGlyph.family("slash"), SkillGlyph.family("spin"), "slash and spin are both bladework")
	eq(SkillGlyph.family("dash"), SkillGlyph.family("charge"), "dash and charge are both movement")
	eq(SkillGlyph.family("shield"), SkillGlyph.family("taunt_aura"), "shield and taunt are both warding")
	check(SkillGlyph.family("burst") != SkillGlyph.family("arrow"), "a nova and an arrow must not look alike")

func test_every_kind_draws_a_real_glyph() -> void:
	for kind in KINDS:
		var shapes := SkillGlyph.shapes(kind, Vector2.ZERO, 35.0)
		check(shapes.size() >= 2, "kind '%s' needs at least two shapes, got %d" % [kind, shapes.size()])
		var box := _bounds_of(shapes)
		gt(box.size.x, 4.0, "kind '%s' draws a glyph with real width" % kind)
		gt(box.size.y, 4.0, "kind '%s' draws a glyph with real height" % kind)

func test_glyph_stays_inside_the_ring() -> void:
	# 圆环半径 35，图形最外点必须落在 0.62R 以内，否则会顶到描边上。
	for kind in KINDS:
		var radius := 35.0
		var shapes := SkillGlyph.shapes(kind, Vector2.ZERO, radius)
		for point in _points_of(shapes):
			lt(Vector2(point).length(), radius * 0.66, "kind '%s' point %s escapes the inner disc" % [kind, point])

func test_key_badge_sits_in_the_lower_right_corner() -> void:
	var center := Vector2(100.0, 100.0)
	var radius := 35.0
	var badge := SkillGlyph.badge_center(center, radius)
	gt(badge.x, center.x, "the key badge leans right")
	gt(badge.y, center.y, "the key badge leans down")
	var distance := center.distance_to(badge)
	gt(distance, radius * 0.62, "the badge must clear the glyph")
	lt(distance, radius * 0.92, "the badge must stay on the button")
	lt(SkillGlyph.badge_radius(radius), radius * 0.34, "the badge stays a corner tag, not a second button")

func test_glyph_scales_with_the_button() -> void:
	# 半径翻倍，包围盒也要翻倍：写死像素的话，手机上的大按钮里图标会缩成一粒。
	var small := _bounds_of(SkillGlyph.shapes("burst", Vector2.ZERO, 20.0))
	var large := _bounds_of(SkillGlyph.shapes("burst", Vector2.ZERO, 40.0))
	near(large.size.x / small.size.x, 2.0, 0.05, "the glyph must scale linearly with the ring")
	# 同一个图形在不同中心点必须整体平移，不能是绝对坐标画死的。
	var moved := _bounds_of(SkillGlyph.shapes("burst", Vector2(50.0, -20.0), 20.0))
	near(moved.position.x - small.position.x, 50.0, 0.01, "the glyph follows its center")
	near(moved.position.y - small.position.y, -20.0, 0.01, "the glyph follows its center")

func test_unknown_kind_falls_back_to_a_visible_glyph() -> void:
	var shapes := SkillGlyph.shapes("definitely_not_a_skill", Vector2.ZERO, 35.0)
	gt(shapes.size(), 0, "an unknown kind still has to draw something")
