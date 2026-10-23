extends "res://tests/test_base.gd"

const SkillIndicator = preload("res://scripts/ui/skill_indicator.gd")
const CancelCastZone = preload("res://scripts/ui/cancel_cast_zone.gd")

func test_circle_indicator_geometry_and_containment() -> void:
	var points: PackedVector2Array = SkillIndicator.generate_circle_points(6.0, 16)
	eq(points.size(), 16, "circle indicator generates requested resolution")
	check(SkillIndicator.is_inside_circle(Vector2(2.0, 3.0), Vector2.ZERO, 6.0), "point within radius is inside")
	check(not SkillIndicator.is_inside_circle(Vector2(7.0, 0.0), Vector2.ZERO, 6.0), "point beyond radius is outside")

func test_line_indicator_geometry_and_containment() -> void:
	var start := Vector2.ZERO
	var dir := Vector2(1.0, 0.0) # Right
	var length := 8.0
	var width := 2.0 # Half-width 1.0
	
	var quad: PackedVector2Array = SkillIndicator.generate_line_points(start, dir, length, width)
	eq(quad.size(), 4, "line indicator generates 4 quad corners")
	
	check(SkillIndicator.is_inside_line(Vector2(4.0, 0.5), start, dir, length, width), "point inside line corridor")
	check(not SkillIndicator.is_inside_line(Vector2(4.0, 2.5), start, dir, length, width), "point outside lateral width")
	check(not SkillIndicator.is_inside_line(Vector2(9.0, 0.0), start, dir, length, width), "point beyond longitudinal length")

func test_cone_indicator_geometry_and_containment() -> void:
	var origin := Vector2.ZERO
	var dir := Vector2(0.0, -1.0) # Forward (Up)
	var range_val := 7.0
	var angle_deg := 60.0
	
	var arc: PackedVector2Array = SkillIndicator.generate_cone_points(origin, dir, range_val, angle_deg, 8)
	gt(arc.size(), 8, "cone indicator includes origin and arc points")
	
	check(SkillIndicator.is_inside_cone(Vector2(0.5, -4.0), origin, dir, range_val, angle_deg), "point in forward cone arc")
	check(not SkillIndicator.is_inside_cone(Vector2(4.0, 0.0), origin, dir, range_val, angle_deg), "point perpendicular to cone")
	check(not SkillIndicator.is_inside_cone(Vector2(0.0, 2.0), origin, dir, range_val, angle_deg), "point behind cone")

func test_cancel_zone_detection_and_indicator_styling() -> void:
	var zone_center := Vector2(800.0, 100.0)
	var zone_radius := 60.0
	
	check(CancelCastZone.is_inside(Vector2(810.0, 110.0), zone_center, zone_radius), "touch inside cancel circle")
	check(not CancelCastZone.is_inside(Vector2(600.0, 400.0), zone_center, zone_radius), "touch outside cancel circle")
	
	# Color state check
	var normal_color: Color = CancelCastZone.get_indicator_color(false)
	var cancel_color: Color = CancelCastZone.get_indicator_color(true)
	check(normal_color != cancel_color, "normal and cancel indicator colors must differ")
	check(cancel_color.r > cancel_color.g and cancel_color.r > cancel_color.b, "cancel indicator should be red alert")

func test_cancel_zone_state_transitions() -> void:
	var state := CancelCastZone.create_state()
	eq(bool(state.cancelling), false, "initial state is not cancelling")
	
	CancelCastZone.update_state(state, Vector2(800.0, 100.0), Vector2(800.0, 100.0), 60.0)
	eq(bool(state.cancelling), true, "dragged into cancel zone")
	
	CancelCastZone.update_state(state, Vector2(200.0, 200.0), Vector2(800.0, 100.0), 60.0)
	eq(bool(state.cancelling), false, "dragged back out restores casting")
