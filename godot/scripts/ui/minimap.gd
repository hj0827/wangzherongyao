extends Control
class_name Minimap

signal location_clicked(world_position: Vector2)

const MapData = preload("res://sim/map_data.gd")
const MapIntel = preload("res://sim/map_intel.gd")
const GameTheme = preload("res://scripts/ui/game_theme.gd")

const MARGIN := 13.0
const DISPLAY_SIZE := Vector2(206, 206)

var snapshot: Dictionary = {}
var local_owner := ""
var local_team := "blue"
var _panel_style: StyleBoxFlat
var _inspect_point := Vector2.ZERO
var _inspect_valid := false

func _ready() -> void:
	custom_minimum_size = DISPLAY_SIZE
	mouse_filter = Control.MOUSE_FILTER_STOP
	_panel_style = GameTheme.style(Color(0.015, 0.03, 0.042, 0.9), Color(0.55, 0.44, 0.24, 0.8), 1, 8)

func set_snapshot(data: Dictionary, owner: String, team: String) -> void:
	snapshot = data
	local_owner = owner
	local_team = team
	queue_redraw()

func _draw() -> void:
	draw_style_box(_panel_style, Rect2(Vector2.ZERO, size))
	var inner := _inner_size()
	var origin := _inner_origin()
	var scale := _world_scale()
	draw_rect(Rect2(origin, Vector2(inner, inner)), Color(0.035, 0.07, 0.05, 0.9))

	var top_left := world_to_screen(Vector2(-MapData.BOUNDS, -MapData.BOUNDS))
	var bottom_right := world_to_screen(Vector2(MapData.BOUNDS, MapData.BOUNDS))
	var river_a := world_to_screen(Vector2(-MapData.BOUNDS, MapData.BOUNDS))
	var river_b := world_to_screen(Vector2(MapData.BOUNDS, -MapData.BOUNDS))
	draw_line(river_a, river_b, Color(0.1, 0.36, 0.48, 0.55), 13.0, true)
	draw_line(river_a, river_b, Color(0.24, 0.6, 0.72, 0.35), 6.0, true)

	for lane in MapData.LANE_ORDER:
		var path: Array = MapData.lane_path(lane)
		var points := PackedVector2Array()
		for point in path:
			points.append(world_to_screen(point))
		draw_polyline(points, Color(0.48, 0.4, 0.26, 0.6), 4.0, true)

	var entities: Array = snapshot.get("entities", [])
	for entity in entities:
		if not entity.get("alive", false):
			continue
		var pos := world_to_screen(Vector2(float(entity.x), float(entity.y)))
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
	if _inspect_valid:
		_draw_inspect_marker(scale)
	var font := GameTheme.FONT_REGULAR
	draw_string(font, Vector2(size.x * 0.5 - 8.0, 12.0), "北", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.7, 0.76, 0.8, 0.7))

func _draw_inspect_marker(scale: float) -> void:
	var pos := world_to_screen(_inspect_point)
	var radius := maxf(7.0, MapIntel.INSPECT_RADIUS * scale)
	draw_circle(pos, radius, Color(GameTheme.GOLD.r, GameTheme.GOLD.g, GameTheme.GOLD.b, 0.1))
	draw_arc(pos, radius, 0.0, TAU, 40, Color(GameTheme.GOLD.r, GameTheme.GOLD.g, GameTheme.GOLD.b, 0.62), 1.2, true)
	draw_line(pos - Vector2(7.0, 0.0), pos + Vector2(7.0, 0.0), GameTheme.GOLD_LIGHT, 1.6, true)
	draw_line(pos - Vector2(0.0, 7.0), pos + Vector2(0.0, 7.0), GameTheme.GOLD_LIGHT, 1.6, true)
	draw_circle(pos, 2.4, GameTheme.GOLD_LIGHT)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse := event as InputEventMouseButton
		if mouse.pressed and mouse.button_index == MOUSE_BUTTON_LEFT:
			_emit_location(mouse.position)
	elif event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed:
			_emit_location(touch.position)

func _emit_location(local: Vector2) -> void:
	var world: Variant = screen_to_world(local)
	if world == null:
		return
	set_inspect_point(world)
	location_clicked.emit(world)
	if is_inside_tree():
		accept_event()

func set_inspect_point(point: Vector2) -> void:
	_inspect_point = point
	_inspect_valid = true
	queue_redraw()

func clear_inspect_point() -> void:
	_inspect_valid = false
	queue_redraw()

func _inner_size() -> float:
	return maxf(0.0, minf(size.x, size.y) - MARGIN * 2.0)

func _inner_origin() -> Vector2:
	var inner := _inner_size()
	return Vector2((size.x - inner) * 0.5, (size.y - inner) * 0.5)

func _world_scale() -> float:
	var inner := _inner_size()
	var world_size := MapData.BOUNDS * 2.0
	if inner <= 0.0 or world_size <= 0.0:
		return 0.0
	return inner / world_size

func world_to_screen(world: Vector2) -> Vector2:
	return _inner_origin() + Vector2(world.x + MapData.BOUNDS, world.y + MapData.BOUNDS) * _world_scale()

func screen_to_world(local: Vector2) -> Variant:
	var inner := _inner_size()
	var scale := _world_scale()
	if inner <= 0.0 or scale <= 0.0:
		return null
	var origin := _inner_origin()
	if local.x < origin.x or local.y < origin.y:
		return null
	if local.x > origin.x + inner or local.y > origin.y + inner:
		return null
	return (local - origin) / scale - Vector2(MapData.BOUNDS, MapData.BOUNDS)
