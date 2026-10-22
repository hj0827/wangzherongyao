extends RefCounted

const AUTO_AIM_RANGE := 10.0
const HERO_PRIORITY := 1.2
const STRUCTURE_PENALTY := 0.6

static func wants_touch_controls(config: Dictionary, mobile_feature: bool, touchscreen_available: bool) -> bool:
	if config.has("touch_controls"):
		return bool(config.get("touch_controls", false))
	return mobile_feature or touchscreen_available

static func entity_position(entity: Dictionary) -> Vector2:
	if entity.has("pos"):
		var pos: Variant = entity.get("pos")
		if pos is Vector2:
			return pos
	return Vector2(float(entity.get("x", 0.0)), float(entity.get("y", 0.0)))

static func nearest_enemy(entities: Array, team: String, from: Vector2, max_range: float, include_structures := false) -> Dictionary:
	var best: Dictionary = {}
	var best_score := INF
	for entry in entities:
		if not (entry is Dictionary):
			continue
		var entity: Dictionary = entry
		if not bool(entity.get("alive", false)):
			continue
		if str(entity.get("team", "")) == team:
			continue
		var kind := str(entity.get("type", ""))
		var is_hero := kind == "hero"
		var is_unit := kind == "hero" or kind == "minion" or kind == "monster"
		if not is_unit and (not include_structures or (kind != "tower" and kind != "base")):
			continue
		var dist := from.distance_to(entity_position(entity))
		if dist > max_range:
			continue
		var score := dist
		if is_hero:
			score -= HERO_PRIORITY
		elif kind == "tower" or kind == "base":
			score += STRUCTURE_PENALTY
		if score < best_score:
			best_score = score
			best = entity
	return best

static func aim_point(manual_aim: Vector2, has_manual: bool, entities: Array, team: String, from: Vector2, auto_range: float, include_structures := false) -> Dictionary:
	if has_manual:
		return {"aim": manual_aim, "source": "manual"}
	var target: Dictionary = nearest_enemy(entities, team, from, auto_range, include_structures)
	if target.is_empty():
		return {"aim": manual_aim, "source": "none"}
	return {"aim": entity_position(target), "source": "auto"}

static func camera_relative_move(stick: Vector2, camera_forward: Vector2) -> Vector2:
	if camera_forward.length_squared() < 0.0001:
		return stick.limit_length(1.0)
	var forward := camera_forward.normalized()
	var right := Vector2(-forward.y, forward.x)
	return (right * stick.x - forward * stick.y).limit_length(1.0)

