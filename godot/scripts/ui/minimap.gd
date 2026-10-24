extends Control
class_name Minimap

signal location_clicked(world_position: Vector2)
# 拖拽中持续发出（每帧最多一次），相机据此连续跟随。
signal location_dragged(world_position: Vector2)
# 松手结算。情报面板只在这里刷新，拖拽途中不刷屏。
signal drag_finished(world_position: Vector2)

const MapData = preload("res://sim/map_data.gd")
const MapLayout = preload("res://sim/map/map_layout.gd")
const MapView = preload("res://scripts/game/map_view.gd")
const GameTheme = preload("res://scripts/ui/game_theme.gd")

const MARGIN := 13.0
const DISPLAY_SIZE := Vector2(206, 206)

# 静态地图要素（墙体/草丛/营地/首领坑）供 _draw 消费；
# 单独抽成纯函数，无头测试可以直接验证「小地图确实画了这些要素」。
static func feature_shapes() -> Array:
	var shapes: Array = []
	for wall in MapLayout.WALLS:
		shapes.append({
			"kind": "wall",
			"a": wall.a,
			"b": wall.b,
			"width": 3.0,
			"color": Color(0.16, 0.15, 0.13, 0.95),
		})
	for bush in MapLayout.BUSHES:
		shapes.append({
			"kind": "bush",
			"pos": bush.pos,
			"radius": float(bush.radius),
			"color": Color(0.13, 0.3, 0.15, 0.78),
		})
	for camp in MapLayout.CAMPS:
		shapes.append({
			"kind": "camp",
			"pos": camp.pos,
			"radius": 2.8,
			"color": Color(0.93, 0.6, 0.24, 0.85) if str(camp.get("buff", "")) == "red" else Color(0.32, 0.56, 0.98, 0.9),
		})
	for pit in MapLayout.OBJECTIVE_PITS:
		shapes.append({
			"kind": "objective",
			"pos": pit.pos,
			"radius": 4.2,
			"color": Color(0.72, 0.5, 0.92, 0.9),
		})
	for pad in MapLayout.TELEPORT_PADS:
		shapes.append({
			"kind": "teleport",
			"pos": pad.pos,
			"radius": 4.6,
			"color": Color(0.36, 0.78, 0.88, 0.9),
		})
	return shapes

# 动态单位在小地图上的呈现参数；tower 按层级放大，未解锁的塔带 locked 标记。
static func entity_mark(entity: Dictionary) -> Dictionary:
	var kind := str(entity.get("type", ""))
	var team := str(entity.get("team", "blue"))
	var color := GameTheme.BLUE if team == "blue" else GameTheme.RED
	if team == "neutral":
		color = Color(0.86, 0.74, 0.4)
	match kind:
		"tower":
			var radius := 3.0 * MapView.tower_scale(str(entity.get("tier", "outer")))
			return {"kind": "tower", "color": color, "radius": radius, "locked": not bool(entity.get("vulnerable", true))}
		"guard":
			var guard_radius := 2.6 * MapView.tower_scale(str(entity.get("tier", "twin")))
			return {"kind": "guard", "color": color, "radius": guard_radius, "locked": not bool(entity.get("vulnerable", true))}
		"base":
			return {
				"kind": "base",
				"color": color,
				"radius": 5.0,
				"locked": not bool(entity.get("vulnerable", true)),
				"shield": float(entity.get("shield", 0.0)) > 0.0,
			}
		"hero":
			return {"kind": "hero", "color": color, "radius": 4.2, "locked": false}
		"minion":
			return {"kind": "minion", "color": color, "radius": 1.6, "locked": false}
		"monster":
			var boss := bool(entity.get("objective", false))
			if bool(entity.get("river_spirit", false)):
				return {"kind": "spirit", "color": Color(0.44, 0.86, 0.92), "radius": 2.6, "locked": false}
			return {
				"kind": "monster",
				"color": Color(0.95, 0.68, 0.28) if boss else Color(0.6, 0.8, 0.52),
				"radius": 3.4 if boss else 2.2,
				"locked": false,
			}
	return {}

var snapshot: Dictionary = {}
var local_owner := ""
var local_team := "blue"
var _panel_style: StyleBoxFlat
# --- 拖拽定位 ---
# 按住地图拖动 = 连续改变相机注视点。鼠标拖出控件后 _gui_input 收不到事件，
# 所以鼠标侧靠 _process 轮询真实指针位置，触摸侧靠 InputEventScreenDrag（触摸事件
# 会持续派发给按下的那个控件，不受出界影响）。
var _dragging := false
var _drag_touch := false
var _drag_local := Vector2.ZERO
# --- 相机视野框 ---
# 不画这个框，玩家「点过去」之后无法判断镜头落在地图哪一块。
# 存的是四个世界角点：透视下地面可视区是梯形，用 AABB 会明显偏离真实视线。
var _camera_view_valid := false
var _camera_view_points := PackedVector2Array()
var _camera_center := Vector2.ZERO
var _camera_half := Vector2.ZERO

func _ready() -> void:
	custom_minimum_size = DISPLAY_SIZE
	mouse_filter = Control.MOUSE_FILTER_STOP
	_panel_style = GameTheme.style(Color(0.015, 0.03, 0.042, 0.9), Color(0.55, 0.44, 0.24, 0.8), 1, 8)
	set_process(false)

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
		var path: Array = MapView.lane_path(lane)
		var points := PackedVector2Array()
		for point in path:
			points.append(world_to_screen(point))
		draw_polyline(points, Color(0.48, 0.4, 0.26, 0.6), 4.0, true)

	for shape in feature_shapes():
		match str(shape.kind):
			"wall":
				draw_line(world_to_screen(shape.a), world_to_screen(shape.b), shape.color, float(shape.width), true)
			"bush":
				draw_circle(world_to_screen(shape.pos), maxf(2.0, float(shape.radius) * scale), shape.color)
			"camp":
				var camp_pos := world_to_screen(shape.pos)
				draw_circle(camp_pos, 3.2, shape.color)
				draw_arc(camp_pos, 4.6, 0, TAU, 14, shape.color, 1.0, true)
			"objective":
				var pit_pos := world_to_screen(shape.pos)
				draw_circle(pit_pos, 5.0, Color(shape.color.r, shape.color.g, shape.color.b, 0.28))
				draw_arc(pit_pos, 5.4, 0, TAU, 20, shape.color, 1.4, true)
			"teleport":
				var pad_pos := world_to_screen(shape.pos)
				draw_circle(pad_pos, 4.2, Color(shape.color.r, shape.color.g, shape.color.b, 0.22))
				draw_arc(pad_pos, 4.6, 0, TAU, 20, shape.color, 1.2, true)
				draw_arc(pad_pos, 2.4, 0, TAU, 14, Color(shape.color.r, shape.color.g, shape.color.b, 0.7), 1.0, true)

	var entities: Array = snapshot.get("entities", [])
	for entity in entities:
		if not entity.get("alive", false):
			continue
		var mark := entity_mark(entity)
		if mark.is_empty():
			continue
		var pos := world_to_screen(Vector2(float(entity.x), float(entity.y)))
		var team_color: Color = mark.color
		var radius := float(mark.radius)
		match str(mark.kind):
			"minion":
				draw_circle(pos, radius, Color(team_color.r, team_color.g, team_color.b, 0.7))
			"tower":
				var rect := Rect2(pos - Vector2(radius, radius), Vector2(radius, radius) * 2.0)
				draw_rect(rect, team_color, true)
				draw_rect(rect, Color(0.02, 0.03, 0.04, 0.8), false, 1.0)
				if bool(mark.locked):
					draw_arc(pos, radius + 2.0, 0, TAU, 16, Color(0.72, 0.78, 0.84, 0.85), 1.0, true)
			"guard":
				var guard_points := PackedVector2Array([
					pos + Vector2(0.0, -radius),
					pos + Vector2(radius, 0.0),
					pos + Vector2(0.0, radius),
					pos + Vector2(-radius, 0.0),
				])
				draw_colored_polygon(guard_points, team_color)
				guard_points.append(guard_points[0])
				draw_polyline(guard_points, Color(0.02, 0.03, 0.04, 0.85), 1.0, true)
				if bool(mark.locked):
					draw_arc(pos, radius + 2.0, 0, TAU, 16, Color(0.72, 0.78, 0.84, 0.85), 1.0, true)
			"base":
				draw_circle(pos, radius * 1.6, Color(team_color.r, team_color.g, team_color.b, 0.28))
				draw_circle(pos, radius, team_color)
				draw_arc(pos, radius * 1.6, 0, TAU, 20, Color(team_color.r, team_color.g, team_color.b, 0.8), 1.0, true)
				if bool(mark.get("shield", false)):
					draw_arc(pos, radius * 1.95, 0, TAU, 24, Color(0.62, 0.86, 1.0, 0.85), 1.4, true)
			"hero":
				var is_local := str(entity.get("owner_id", "")) == local_owner
				if is_local:
					draw_circle(pos, radius * 1.9, Color(GameTheme.GOLD.r, GameTheme.GOLD.g, GameTheme.GOLD.b, 0.35))
				draw_circle(pos, radius, team_color)
				draw_arc(pos, radius + 0.6, 0, TAU, 16, Color(0.02, 0.03, 0.04, 0.9), 1.0, true)
				if is_local:
					draw_arc(pos, radius + 2.8, 0, TAU, 20, GameTheme.GOLD_LIGHT, 1.4, true)
			"monster":
				draw_circle(pos, radius, Color(team_color.r, team_color.g, team_color.b, 0.9))
				draw_arc(pos, radius + 1.0, 0, TAU, 16, Color(0.06, 0.08, 0.06, 0.85), 1.0, true)
			"spirit":
				draw_circle(pos, radius * 1.5, Color(team_color.r, team_color.g, team_color.b, 0.25))
				draw_circle(pos, radius, team_color)
				draw_arc(pos, radius + 1.4, 0, TAU, 16, Color(0.8, 0.97, 1.0, 0.9), 1.0, true)

	draw_line(top_left, Vector2(bottom_right.x, top_left.y), Color(0.54, 0.44, 0.25, 0.25), 1.0)
	draw_line(Vector2(top_left.x, bottom_right.y), bottom_right, Color(0.54, 0.44, 0.25, 0.25), 1.0)
	if _camera_view_valid:
		_draw_camera_view()
	var font := GameTheme.FONT_REGULAR
	draw_string(font, Vector2(size.x * 0.5 - 8.0, 12.0), "北", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.7, 0.76, 0.8, 0.7))

func _draw_camera_view() -> void:
	var polygon := camera_view_polygon()
	if polygon.size() < 3:
		return
	draw_colored_polygon(polygon, Color(GameTheme.GOLD.r, GameTheme.GOLD.g, GameTheme.GOLD.b, 0.12))
	var outline := polygon.duplicate()
	outline.append(polygon[0])
	draw_polyline(outline, Color(GameTheme.GOLD_LIGHT.r, GameTheme.GOLD_LIGHT.g, GameTheme.GOLD_LIGHT.b, 0.85), 1.3, true)
	# 四角短刻线：叠在地图要素上时纯细边框容易看不清。
	var middle := polygon[0]
	for point in polygon:
		middle += point
	middle /= float(polygon.size())
	for point in polygon:
		var inward := (middle - point).normalized()
		draw_line(point, point + inward * 5.0, GameTheme.GOLD_LIGHT, 1.8, true)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse := event as InputEventMouseButton
		if mouse.button_index != MOUSE_BUTTON_LEFT:
			return
		if mouse.pressed:
			_begin_drag(mouse.position, false)
		else:
			_end_drag()
	elif event is InputEventMouseMotion:
		# 鼠标侧的真实跟手由 _process 轮询保证（移出控件后这里就收不到事件了）。
		if _dragging and not _drag_touch:
			_drag_to((event as InputEventMouseMotion).position)
	elif event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed:
			_begin_drag(touch.position, true)
		else:
			_end_drag()
	elif event is InputEventScreenDrag:
		if _dragging and _drag_touch:
			_drag_to((event as InputEventScreenDrag).position)

func _process(_delta: float) -> void:
	if not _dragging or _drag_touch:
		return
	if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_end_drag()
		return
	_drag_to(get_local_mouse_position())

func _begin_drag(local: Vector2, touch_drag: bool) -> void:
	_dragging = true
	_drag_touch = touch_drag
	_drag_local = local
	set_process(not touch_drag)
	_emit_location(local, false)
	if is_inside_tree():
		accept_event()

func _drag_to(local: Vector2) -> void:
	if not _dragging:
		return
	_drag_local = local
	# 拖拽允许出界：夹到地图边缘继续跟随，比中途断开更像 MOBA 的操作手感。
	_emit_location(local, true)

func _end_drag() -> void:
	if not _dragging:
		return
	_dragging = false
	_drag_touch = false
	set_process(false)
	var world := screen_to_world_clamped(_drag_local)
	drag_finished.emit(world)
	if is_inside_tree():
		accept_event()

func _emit_location(local: Vector2, dragging: bool) -> void:
	var world: Variant = screen_to_world_clamped(local) if dragging else screen_to_world(local)
	if world == null:
		return
	if dragging:
		location_dragged.emit(world)
	else:
		location_clicked.emit(world)
	if is_inside_tree():
		accept_event()

func set_camera_view(view: Dictionary) -> void:
	_camera_view_valid = bool(view.get("valid", false))
	_camera_view_points = view.get("points", PackedVector2Array())
	_camera_center = view.get("center", Vector2.ZERO)
	_camera_half = view.get("half", Vector2.ZERO)
	queue_redraw()

func has_camera_view() -> bool:
	return _camera_view_valid and _camera_view_points.size() >= 3

# 相机视野在地图上的四边形（屏幕坐标，已夹进地图内框）。
func camera_view_polygon() -> PackedVector2Array:
	var out := PackedVector2Array()
	if not has_camera_view():
		return out
	var inner := Rect2(_inner_origin(), Vector2(_inner_size(), _inner_size()))
	for point in _camera_view_points:
		out.append(world_to_screen(point).clamp(inner.position, inner.end))
	return out

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

# 拖拽专用：越界不返回 null，而是夹到地图边缘。
func screen_to_world_clamped(local: Vector2) -> Vector2:
	var inner := _inner_size()
	var scale := _world_scale()
	if inner <= 0.0 or scale <= 0.0:
		return Vector2.ZERO
	var origin := _inner_origin()
	var relative := (local - origin).clamp(Vector2.ZERO, Vector2(inner, inner))
	return relative / scale - Vector2(MapData.BOUNDS, MapData.BOUNDS)
