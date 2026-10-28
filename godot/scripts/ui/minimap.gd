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
const Jungle = preload("res://sim/map/jungle.gd")
const Objectives = preload("res://sim/map/objectives.gd")

const MARGIN := 13.0
const DISPLAY_SIZE := Vector2(206, 206)

# 视野圈的分段数。180px 的地图上半径约 25~40px，36 段每段不到 4°，看不出折线；
# 再往上加只是让每帧多几个顶点，视觉收益为零。
const VISION_CIRCLE_SEGMENTS := 36

# 英雄头像：原始立绘是 1024²，小地图上只占十几像素。统一缩到 64² 再裁圆并缓存，
# 地图每帧重绘，绝不能每帧去解码 2MB 的原图。
const AVATAR_TEXTURE_SIZE := 64
# 立绘是半身像，整张压成 14px 只能看到一团衣服。裁到头部再缩，脸才认得出来。
const HERO_FACE_CROP := Rect2(0.28, 0.02, 0.44, 0.44)
const HERO_MARK_RADIUS := 7.0
const FACING_TAB_LENGTH := 4.5
const FACING_TAB_WIDTH := 3.2

static var _avatar_cache: Dictionary = {}

# 静态地图要素（墙体/草丛/营地/首领坑）供 _draw 消费；
# 单独抽成纯函数，无头测试可以直接验证「小地图确实画了这些要素」。
static func feature_shapes() -> Array:
	var shapes: Array = []
	for wall in MapLayout.WALLS:
		shapes.append({
			"kind": "wall",
			"a": wall.a,
			"b": wall.b,
			"width": 2.6,
			# 墙原来是近黑色：在深底上会读成「地面上破了个洞」，而不是「这里有段墙」。
			# 改成偏暖的石色，才和地形的语汇一致。
			"color": Color(0.34, 0.30, 0.23, 0.85),
		})
	for bush in MapLayout.BUSHES:
		shapes.append({
			"kind": "bush",
			"pos": bush.pos,
			"radius": float(bush.radius),
			# 原来的亮绿实心圆在深底上比英雄还抢眼，会被误读成单位。
			# 草丛在缩略图上只需要「那里有一片暗影」，不需要被看见。
			"color": Color(0.16, 0.26, 0.17, 0.5),
		})
	for camp in MapLayout.CAMPS:
		var buff := str(camp.get("buff", ""))
		var camp_color := Color(0.93, 0.6, 0.24, 0.85) if buff == "red" else Color(0.32, 0.56, 0.98, 0.9)
		if buff == "":
			camp_color = Color(0.5, 0.72, 0.38, 0.85)
		shapes.append({
			"kind": "camp",
			"id": str(camp.id),
			"pos": camp.pos,
			"radius": 2.8 if buff != "" else 2.0,
			"color": camp_color,
		})
	for pit in MapLayout.OBJECTIVE_PITS:
		shapes.append({
			"kind": "objective",
			"id": str(pit.id),
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

# 营地 / 首领坑的死亡倒计时标记。
#
# 快照里死亡野怪仍然带 camp_id / objective_id / respawn_timer（只要它在视野内），
# 小地图据此把静态营地圆点压暗，再画一圈「快转满 = 快刷新」的弧。
# 不用文字：小地图只有 180px，营地名 + 秒数会糊成一团，弧线在余光里就能读。
static func camp_timer_marks(entities: Array) -> Array:
	var marks: Array = []
	for entity in entities:
		if not (entity is Dictionary) or str(entity.get("type", "")) != "monster":
			continue
		if bool(entity.get("alive", false)):
			continue
		var timer := float(entity.get("respawn_timer", 0.0))
		if timer <= 0.0:
			continue
		var camp_id := str(entity.get("camp_id", ""))
		var objective_id := str(entity.get("objective_id", ""))
		if camp_id == "" and objective_id == "":
			continue
		var region: Dictionary = {}
		var total := Jungle.RESPAWN_TIME
		var color := Color(0.55, 0.72, 0.98, 0.9)
		if camp_id != "":
			for camp in MapLayout.CAMPS:
				if str(camp.id) != camp_id:
					continue
				region = camp
				var buff := str(camp.get("buff", ""))
				if buff == "red":
					color = Color(0.93, 0.6, 0.24, 0.9)
				elif buff == "blue":
					color = Color(0.4, 0.66, 1.0, 0.95)
				else:
					color = Color(0.56, 0.76, 0.42, 0.9)
				total = float(camp.get("respawn_time", Jungle.RESPAWN_TIME))
				break
		else:
			for pit in MapLayout.OBJECTIVE_PITS:
				if str(pit.id) != objective_id:
					continue
				region = pit
				total = Objectives.RESPAWN
				color = Color(0.78, 0.56, 1.0, 0.95)
				break
		if region.is_empty():
			continue
		marks.append({
			"id": camp_id if camp_id != "" else objective_id,
			"kind": "camp" if camp_id != "" else "objective",
			"pos": region.pos,
			"timer": timer,
			"total": total,
			"color": color,
		})
	return marks

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
			return {"kind": "hero", "color": color, "radius": HERO_MARK_RADIUS, "locked": false}
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

## 英雄在小地图上的颜色，按**与本地玩家的关系**取：自己绿 / 友军蓝 / 敌军红。
##
## 这和头顶血条是同一条语义（UnitVisual.bar_color），但**不能直接复用那三个常量**：
## 它们是为了抵消 3D 的 FILMIC 色调映射反解出来的，搬到 2D 上会偏暗发闷。
## 这里用 UI 侧的等价色（GameTheme），保证小地图和左下角血条是同一个绿。
##
## 为什么不能按绝对阵营：红方玩家眼里的队友是红队，按阵营画就是满屏红点，
## 屏幕上读出来是「我被一群敌人围住了」。关系色永远只有三种含义。
static func hero_mark_color(is_local: bool, team: String, viewer_team: String) -> Color:
	if is_local:
		return GameTheme.GREEN
	if viewer_team != "" and team == viewer_team:
		return GameTheme.BLUE
	return GameTheme.RED

## 世界坐标 ⇄ 小地图坐标的朝向变换。
##
## 相机 yaw 决定屏幕轴（见 arena._camera_forward）：蓝方朝世界 +Y 看，屏幕右是 -X；
## 红方朝 -Y 看，屏幕右是 +X。小地图必须按同一套轴折过去，否则蓝方玩家会看到
## 自家基地在右上、敌方在左下，而且左右方向和画面相反。红方的世界轴本来就对得上，
## 蓝方需要整张图转 180°——转完两家都是「自家基地左下、敌方基地右上」。
## 180° 旋转是自逆的，所以正反两个方向共用这一个函数。
static func oriented(world: Vector2, team: String) -> Vector2:
	return world if team == "red" else -world

## 英雄在小地图上的朝向箭头（屏幕坐标）。
## 原来英雄只是一个圆点：混战时分不清谁在往哪走，敌方从哪边压过来只能靠猜。
## facing 为 (0,0) 时（出生、传送落地那一瞬）回落到朝上，不能画出零面积图形。
static func hero_arrow(pos: Vector2, facing: Vector2, radius: float) -> PackedVector2Array:
	var dir := facing
	if dir.length_squared() < 0.0001:
		dir = Vector2.UP
	dir = dir.normalized()
	var side := Vector2(-dir.y, dir.x)
	return PackedVector2Array([
		pos + dir * radius,
		pos - dir * radius * 0.55 + side * radius * 0.62,
		pos - dir * radius * 0.22,
		pos - dir * radius * 0.55 - side * radius * 0.62,
	])

## 英雄头像：小地图上是一枚圆形徽章，方形贴图会盖住地块、也读不出「这是个人」。
## 缺图（未知 hero_type、旧快照）返回 null，调用方回落到队伍色圆点。
static func hero_avatar(hero_type: String) -> Texture2D:
	if _avatar_cache.has(hero_type):
		return _avatar_cache[hero_type]
	var tex: Texture2D = null
	if hero_type != "":
		var path := GameTheme.portrait_path(hero_type)
		if ResourceLoader.exists(path):
			var loaded := load(path)
			if loaded is Texture2D:
				var img: Image = (loaded as Texture2D).get_image()
				if img != null and not img.is_empty():
					if img.is_compressed():
						img.decompress()
					var w := img.get_width()
					var h := img.get_height()
					img = img.get_region(Rect2i(
						int(HERO_FACE_CROP.position.x * w),
						int(HERO_FACE_CROP.position.y * h),
						int(HERO_FACE_CROP.size.x * w),
						int(HERO_FACE_CROP.size.y * h)
					))
					img.resize(AVATAR_TEXTURE_SIZE, AVATAR_TEXTURE_SIZE, Image.INTERPOLATE_LANCZOS)
					# 立绘是方图、没有 alpha；不转 RGBA 的话圆形遮罩会被格式直接丢掉。
					if img.get_format() != Image.FORMAT_RGBA8:
						img.convert(Image.FORMAT_RGBA8)
					_mask_avatar_circle(img)
					tex = ImageTexture.create_from_image(img)
	# 缺图也缓存 null：敌方英雄每帧都会走一次查表，不能重复付 ResourceLoader 的成本。
	_avatar_cache[hero_type] = tex
	return tex

# 圆形裁切 + 1px 软边（缩到十几像素时硬边会出锯齿），只改 alpha 不动像素内容。
static func _mask_avatar_circle(img: Image) -> void:
	var size := img.get_width()
	var radius := float(size) * 0.5
	var center := Vector2(size, size) * 0.5
	for y in size:
		for x in size:
			var edge := radius - (Vector2(x + 0.5, y + 0.5) - center).length()
			if edge >= 1.0:
				continue
			var color := img.get_pixel(x, y)
			if edge <= 0.0:
				img.set_pixel(x, y, Color(0.0, 0.0, 0.0, 0.0))
				continue
			color.a *= edge
			img.set_pixel(x, y, color)

## 贴着头像外沿的朝向小三角（屏幕坐标）。
## 头像本身没有方向，去掉朝向会让「敌人在往哪压」重新变成猜。
## facing 为 (0,0)（出生、传送落地）时回落到朝上，不能画出零面积三角形。
static func hero_facing_tab(pos: Vector2, facing: Vector2, radius: float) -> PackedVector2Array:
	var dir := facing
	if dir.length_squared() < 0.0001:
		dir = Vector2.UP
	dir = dir.normalized()
	var side := Vector2(-dir.y, dir.x)
	var base := pos + dir * radius
	return PackedVector2Array([
		pos + dir * (radius + FACING_TAB_LENGTH),
		base + side * FACING_TAB_WIDTH,
		base - side * FACING_TAB_WIDTH,
	])

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
	# 底色不再是一块死板的深绿：外层压暗 + 中心极淡提亮，读起来像一张地形图而不是点阵图。
	draw_rect(Rect2(origin, Vector2(inner, inner)), Color(0.05, 0.075, 0.065, 0.96))
	draw_circle(origin + Vector2(inner, inner) * 0.5, inner * 0.58, Color(1.0, 0.97, 0.88, 0.035))

	var frame := map_frame()
	# 河道中心线：x = y。蓝方视角整张图转了 180°，这条线仍是同一条对角线。
	var river_a := world_to_screen(Vector2(-MapData.BOUNDS, -MapData.BOUNDS))
	var river_b := world_to_screen(Vector2(MapData.BOUNDS, MapData.BOUNDS))
	draw_line(river_a, river_b, Color(0.09, 0.29, 0.37, 0.5), 13.0, true)
	draw_line(river_a, river_b, Color(0.18, 0.44, 0.54, 0.3), 6.0, true)

	for lane in MapData.LANE_ORDER:
		var path: Array = MapView.lane_path(lane)
		var points := PackedVector2Array()
		for point in path:
			points.append(world_to_screen(point))
		draw_polyline(points, Color(0.66, 0.56, 0.38, 0.58), 3.6, true)

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

	# 营地刷新倒计时：盖在静态营地圆点上，画暗底 + 顺时针生长的弧。
	for camp_mark in camp_timer_marks(snapshot.get("entities", [])):
		var camp_pos := world_to_screen(camp_mark.pos)
		var mark_radius := 3.2 if str(camp_mark.kind) == "camp" else 5.0
		draw_circle(camp_pos, mark_radius, Color(0.06, 0.07, 0.08, 0.88))
		var progress := 1.0 - clampf(float(camp_mark.timer) / maxf(1.0, float(camp_mark.total)), 0.0, 1.0)
		if progress > 0.01:
			draw_arc(
				camp_pos,
				mark_radius + 2.2,
				-PI * 0.5,
				-PI * 0.5 + TAU * progress,
				20,
				camp_mark.color,
				1.6,
				true
			)

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
				# 颜色按「与本地玩家的关系」走，不是队伍色：自己绿 / 友军蓝 / 敌军红。
				var hero_color := hero_mark_color(is_local, str(entity.get("team", "")), local_team)
				var facing := oriented(Vector2(
					float(entity.get("facing_x", 0.0)),
					float(entity.get("facing_y", 0.0))
				), local_team)
				if is_local:
					# 自己那一圈光晕也用同一个绿：金圈 + 绿环会读成两个不同的标记。
					draw_circle(pos, radius * 2.0, Color(hero_color.r, hero_color.g, hero_color.b, 0.22))
				var avatar := hero_avatar(str(entity.get("hero_type", "")))
				if avatar != null:
					_draw_hero_avatar(pos, facing, radius, hero_color, avatar, is_local)
				else:
					# 未知英雄（缺失 hero_type 的快照）：别画空图，回落到关系色箭头。
					var arrow := hero_arrow(pos, facing, radius * 1.2)
					var outline := arrow.duplicate()
					outline.append(arrow[0])
					# 先描深色边再填色：箭头压在地形/敌方红点上时不会糊成一团。
					draw_polyline(outline, Color(0.02, 0.03, 0.04, 0.9), 2.6, true)
					draw_colored_polygon(arrow, hero_color)
					if is_local:
						draw_arc(pos, radius * 1.6, 0, TAU, 20, hero_color, 1.3, true)
			"monster":
				draw_circle(pos, radius, Color(team_color.r, team_color.g, team_color.b, 0.9))
				draw_arc(pos, radius + 1.0, 0, TAU, 16, Color(0.06, 0.08, 0.06, 0.85), 1.0, true)
			"spirit":
				draw_circle(pos, radius * 1.5, Color(team_color.r, team_color.g, team_color.b, 0.25))
				draw_circle(pos, radius, team_color)
				draw_arc(pos, radius + 1.4, 0, TAU, 16, Color(0.8, 0.97, 1.0, 0.9), 1.0, true)

	# 视野圈先画、墙后画：镜头贴边时圆的轮廓会被夹成贴着内框的直边，
	# 让墙压在上面才像「视野被地图边界截住」，而不是一条浮在边框外的金线。
	if _camera_view_valid:
		_draw_camera_view()
	# 边界墙：模拟层走到 ±BOUNDS 就停，小地图必须把这条线画成「墙」而不是细网格。
	# 内框只有 180px 左右，1~2px 的描边会被抗锯齿吃干净 —— 用实心带回字形才看得出。
	var band := maxf(3.0, frame.size.x * 0.024)
	var wall_color := Color(0.22, 0.19, 0.13, 0.92)
	draw_rect(Rect2(frame.position, Vector2(frame.size.x, band)), wall_color)
	draw_rect(Rect2(frame.position + Vector2(0.0, frame.size.y - band), Vector2(frame.size.x, band)), wall_color)
	draw_rect(Rect2(frame.position, Vector2(band, frame.size.y)), wall_color)
	draw_rect(Rect2(frame.position + Vector2(frame.size.x - band, 0.0), Vector2(band, frame.size.y)), wall_color)
	# 内沿一条亮线：墙有「一定厚度 + 一道顶面」两层读感，不会看成纯色边框。
	draw_rect(frame.grow(-band), Color(0.72, 0.61, 0.38, 0.88), false, 1.2)
	# 「北」字去掉了：对局里没有罗盘，玩家要的是「我在哪 / 敌人在哪」，
	# 而不是东南西北。蓝红双方基地本身就是最可靠的方向锚点。

# 头像 + 关系色底圈 + 朝向三角。底圈用「实心圆」而不是细描边：
# 14px 的圆上 1px 弧线会被抗锯齿吃掉，实心边才保证绿/蓝/红一眼可分。
# team_color 传进来的是 hero_mark_color() 的关系色，不是队伍色。
func _draw_hero_avatar(pos: Vector2, facing: Vector2, radius: float, team_color: Color, avatar: Texture2D, is_local: bool) -> void:
	var rim := radius + 1.4
	draw_circle(pos, rim, team_color)
	draw_texture_rect(avatar, Rect2(pos - Vector2(radius, radius), Vector2(radius, radius) * 2.0), false)
	# 深色外描边：头像压在河道/兵线/塔上时仍然有清晰轮廓。
	draw_arc(pos, rim, 0.0, TAU, 28, Color(0.02, 0.03, 0.04, 0.9), 1.6, true)
	if is_local:
		# 自己再套一道同色的细环：在几个友军蓝点里一眼找得到「我」。
		draw_arc(pos, rim + 2.4, 0.0, TAU, 28, team_color, 1.3, true)
	var tab := hero_facing_tab(pos, facing, rim)
	var tab_outline := tab.duplicate()
	tab_outline.append(tab[0])
	draw_polyline(tab_outline, Color(0.02, 0.03, 0.04, 0.9), 2.0, true)
	draw_colored_polygon(tab, team_color)

func _draw_camera_view() -> void:
	var outline := camera_view_outline()
	if outline.size() < 3:
		return
	draw_colored_polygon(outline, Color(GameTheme.GOLD.r, GameTheme.GOLD.g, GameTheme.GOLD.b, 0.10))
	var closed := outline.duplicate()
	closed.append(outline[0])
	draw_polyline(closed, Color(GameTheme.GOLD_LIGHT.r, GameTheme.GOLD_LIGHT.g, GameTheme.GOLD_LIGHT.b, 0.85), 1.3, true)

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

# 相机视野圈（屏幕坐标）：{center, radius}，无效时返回空字典。
#
# 为什么是圆而不是四边形：180px 的缩略图上，梯形只剩下四个尖点，一眼读不出
# 「这是镜头看到的范围」；圆是一个整体形状，扫一眼就知道自己在看哪一片。
#
# 半径取**和视野矩形等面积**的那个圆：外接圆按 4:3 的长边算，屏幕上会比真正看到的
# 范围大一圈（上下多出一大块）；内切圆又反过来少报。等面积是唯一不谎报视野大小的取法。
# 圆心取四个角点的形心，不直接信调用方传的 center —— 圆心必须和半径来自同一份数据。
func camera_view_circle() -> Dictionary:
	if not has_camera_view():
		return {}
	var low := _camera_view_points[0]
	var high := _camera_view_points[0]
	var sum := Vector2.ZERO
	for point in _camera_view_points:
		low = Vector2(minf(low.x, point.x), minf(low.y, point.y))
		high = Vector2(maxf(high.x, point.x), maxf(high.y, point.y))
		sum += point
	var half := (high - low) * 0.5
	var radius := sqrt(maxf(half.x * half.y, 0.0)) * _world_scale()
	if radius <= 0.5:
		return {}
	var center := world_to_screen(sum / float(_camera_view_points.size()))
	return {"center": center, "radius": radius}

# 视野圈的轮廓点（屏幕坐标，已夹进地图内框）。
# 夹边而不是整体缩小：镜头贴到地图边缘时圆会超出内框，画出去会压在边框和面板底色上。
# 夹出来的直边由墙体带盖住（视野圈画在墙体之前），看起来像「视野被地图边界截住」。
func camera_view_outline() -> PackedVector2Array:
	var out := PackedVector2Array()
	var circle := camera_view_circle()
	if circle.is_empty():
		return out
	var inner := Rect2(_inner_origin(), Vector2(_inner_size(), _inner_size()))
	var center: Vector2 = circle["center"]
	var radius := float(circle["radius"])
	for index in VISION_CIRCLE_SEGMENTS:
		var angle := TAU * float(index) / float(VISION_CIRCLE_SEGMENTS)
		out.append((center + Vector2(cos(angle), sin(angle)) * radius).clamp(inner.position, inner.end))
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
	var shown := oriented(world, local_team)
	return _inner_origin() + Vector2(shown.x + MapData.BOUNDS, shown.y + MapData.BOUNDS) * _world_scale()

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
	return oriented((local - origin) / scale - Vector2(MapData.BOUNDS, MapData.BOUNDS), local_team)

# 拖拽专用：越界不返回 null，而是夹到地图边缘。
func screen_to_world_clamped(local: Vector2) -> Vector2:
	var inner := _inner_size()
	var scale := _world_scale()
	if inner <= 0.0 or scale <= 0.0:
		return Vector2.ZERO
	var origin := _inner_origin()
	var relative := (local - origin).clamp(Vector2.ZERO, Vector2(inner, inner))
	return oriented(relative / scale - Vector2(MapData.BOUNDS, MapData.BOUNDS), local_team)

# 地图内框（屏幕坐标）。绘制与测试共用：朝向翻转后不能再拿两个世界角点算矩形，
# 那两个点会互换位置，围出来的矩形是负尺寸。
func map_frame() -> Rect2:
	return Rect2(_inner_origin(), Vector2(_inner_size(), _inner_size()))
