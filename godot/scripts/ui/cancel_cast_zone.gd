extends RefCounted

const COLOR_NORMAL := Color(0.2, 0.65, 1.0, 0.7)
const COLOR_CANCEL := Color(0.95, 0.22, 0.2, 0.85)

static func create_state() -> Dictionary:
	return {
		"cancelling": false,
		"touch_pos": Vector2.ZERO,
	}

static func is_inside(touch_pos: Vector2, zone_center: Vector2, radius: float) -> bool:
	return touch_pos.distance_to(zone_center) <= radius

static func get_indicator_color(is_cancelling: bool) -> Color:
	return COLOR_CANCEL if is_cancelling else COLOR_NORMAL

static func update_state(state: Dictionary, touch_pos: Vector2, zone_center: Vector2, radius: float) -> bool:
	var in_zone := is_inside(touch_pos, zone_center, radius)
	state["cancelling"] = in_zone
	state["touch_pos"] = touch_pos
	return in_zone
