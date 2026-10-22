extends Control
class_name Minimap

const MapData = preload("res://sim/map_data.gd")
const GameTheme = preload("res://scripts/ui/game_theme.gd")

var snapshot: Dictionary = {}
var local_owner := ""
var local_team := "blue"
var _panel_style: StyleBoxFlat

func _ready() -> void:
	custom_minimum_size = Vector2(220, 220)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_panel_style = GameTheme.style(Color(0.015, 0.03, 0.042, 0.9), Color(0.55, 0.44, 0.24, 0.8), 1, 8)

func set_snapshot(data: Dictionary, owner: String, team: String) -> void:
	snapshot = data
	local_owner = owner
	local_team = team
	queue_redraw()

func _draw() -> void:
	draw_style_box(_panel_style, Rect2(Vector2.ZERO, size))
	var margin := 13.0
	var inner := minf(size.x, size.y) - margin * 2.0
	var origin := Vector2((size.x - inner) * 0.5, (size.y - inner) * 0.5)
	var world_size := MapData.BOUNDS * 2.0
	var scale := inner / world_size
	draw_rect(Rect2(origin, Vector2(inner, inner)), Color(0.035, 0.07, 0.05, 0.9))

	var top_left := _project(Vector2(-MapData.BOUNDS, -MapData.BOUNDS), origin, scale)
	var bottom_right := _project(Vector2(MapData.BOUNDS, MapData.BOUNDS), origin, scale)
	var river_a := _project(Vector2(-MapData.BOUNDS, MapData.BOUNDS), origin, scale)
	var river_b := _project(Vector2(MapData.BOUNDS, -MapData.BOUNDS), origin, scale)
	draw_line(river_a, river_b, Color(0.1, 0.36, 0.48, 0.55), 13.0, true)
	draw_line(river_a, river_b, Color(0.24, 0.6, 0.72, 0.35), 6.0, true)

	for lane in MapData.LANE_ORDER:
		var path: Array = MapData.lane_path(lane)
		var points := PackedVector2Array()
		for point in path:
			points.append(_project(point, origin, scale))
		draw_polyline(points, Color(0.48, 0.4, 0.26, 0.6), 4.0, true)

	var entities: Array = snapshot.get("entities", [])
	for entity in entities:
		if not entity.get("alive", false):
			continue
		var pos := _project(Vector2(float(entity.x), float(entity.y)), origin, scale)
		var team_color := GameTheme.BLUE if entity.team == "blue" else GameTheme.RED
		match str(entity.type):
			"minion":
				draw_circle(pos, 1.6, Color(team_color.r, team_color.g, team_color.b, 0.7))
			"tower":
				var rect := Rect2(pos - Vector2(3, 3), Vector2(6, 6))
				draw_rect(rect, team_color, true)
				draw_rect(rect, Color(0.02, 0.03, 0.04, 0.8), false, 1.0)
			"base":
				draw_circle(pos, 8.0, Color(team_color.r, team_color.g, team_color.b, 0.28))
				draw_circle(pos, 5.0, team_color)
				draw_arc(pos, 8.0, 0, TAU, 20, Color(team_color.r, team_color.g, team_color.b, 0.8), 1.0, true)
			"hero":
				var is_local := str(entity.get("owner_id", "")) == local_owner
				if is_local:
					draw_circle(pos, 8.0, Color(GameTheme.GOLD.r, GameTheme.GOLD.g, GameTheme.GOLD.b, 0.35))
				draw_circle(pos, 4.2, team_color)
				draw_arc(pos, 4.8, 0, TAU, 16, Color(0.02, 0.03, 0.04, 0.9), 1.0, true)
				if is_local:
					draw_arc(pos, 7.0, 0, TAU, 20, GameTheme.GOLD_LIGHT, 1.4, true)

	draw_line(top_left, Vector2(bottom_right.x, top_left.y), Color(0.54, 0.44, 0.25, 0.25), 1.0)
	draw_line(Vector2(top_left.x, bottom_right.y), bottom_right, Color(0.54, 0.44, 0.25, 0.25), 1.0)
	var font := GameTheme.FONT_REGULAR
	draw_string(font, Vector2(size.x * 0.5 - 8.0, 12.0), "北", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.7, 0.76, 0.8, 0.7))

func _project(world: Vector2, origin: Vector2, scale: float) -> Vector2:
	return origin + Vector2(world.x + MapData.BOUNDS, world.y + MapData.BOUNDS) * scale
