extends RefCounted

const BOUNDS := 58.0
const BASE_RADIUS := 7.0
const TOWER_RADIUS := 2.0
const BLUE_BASE := Vector2(-46.0, -46.0)
const RED_BASE := Vector2(46.0, 46.0)

const LANE_ORDER := ["mid", "top", "bottom"]

const LANES := {
	"mid": [
		Vector2(-46.0, -46.0),
		Vector2(-32.0, -32.0),
		Vector2(-18.0, -18.0),
		Vector2(0.0, 0.0),
		Vector2(18.0, 18.0),
		Vector2(32.0, 32.0),
		Vector2(46.0, 46.0),
	],
	"top": [
		Vector2(-46.0, -46.0),
		Vector2(-46.0, -20.0),
		Vector2(-40.0, 8.0),
		Vector2(-24.0, 30.0),
		Vector2(0.0, 42.0),
		Vector2(28.0, 44.0),
		Vector2(46.0, 46.0),
	],
	"bottom": [
		Vector2(-46.0, -46.0),
		Vector2(-20.0, -46.0),
		Vector2(8.0, -40.0),
		Vector2(30.0, -24.0),
		Vector2(42.0, 0.0),
		Vector2(44.0, 28.0),
		Vector2(46.0, 46.0),
	],
}

const TOWER_OUTER_INDEX := 2
const TOWER_INNER_INDEX := 1
const TOWER_RED_OUTER_INDEX := 4
const TOWER_RED_INNER_INDEX := 5

static func lane_path(lane: String) -> Array:
	return LANES.get(lane, LANES["mid"])
