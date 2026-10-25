extends "res://tests/test_base.gd"

# 边界墙的回归守卫。
#
# 起因：底盘是 ±58 的正方形，拦住人的是 collision.clamp_bounds —— 一堵**隐形**的墙。
# 玩家视野里草地一直铺到远处的山，撞上去才知道到边了；从主视角看根本分不清
# 「这里能走」和「这里不能走」。
#
# 契约：边界处有一圈**看得见的**石墙，墙内表面 = 可走边界 + 相机安全边距。
# 只加视觉不加碰撞（或反过来）都会退化成「看得见走不过去」/「走到空气里被绊住」。
#
# 为什么要留那段边距：镜头在英雄身后 0.76×zoom、俯角 51°，人贴到墙根时相机
# 已经越过边界墙，墙会把英雄整条盖住。宁可墙前留一条走不进去的窄带，
# 也不能让玩家看不见自己（见 MapData.CAMERA_WALL_MARGIN）。

const MapData = preload("res://sim/map_data.gd")
const MapLayout = preload("res://sim/map/map_layout.gd")
const Collision = preload("res://sim/map/collision.gd")
const Arena = preload("res://scripts/game/arena.gd")

const EPS := 0.01
const MAX_HERO_RADIUS := 0.65

func _key(point: Vector2) -> String:
	return "%d_%d" % [int(round(point.x)), int(round(point.y))]

func test_boundary_is_four_walls_in_a_closed_frame() -> void:
	var walls := MapLayout.boundary_walls()
	eq(walls.size(), 4, "四面墙")
	var corners := {}
	for wall in walls:
		corners[_key(wall.a)] = true
		corners[_key(wall.b)] = true
	eq(corners.size(), 4, "四面墙必须共用 4 个角点，围成闭合方框")
	# 每条墙横跨两个角点：长度 = 2 × 墙心线距离。
	var expected: float = MapLayout.BOUNDARY_CENTER * 2.0
	for wall in walls:
		near((wall.a as Vector2).distance_to(wall.b), expected, EPS, "边界墙必须从一角连到另一角：%s" % str(wall.id))

func test_wall_inner_surface_is_the_walkable_edge() -> void:
	# 墙内表面 = 底盘边界；实际能走到的是底盘边界再往里让出相机安全边距。
	near(MapLayout.boundary_inner(), MapData.BOUNDS, EPS, "墙内表面必须与底盘边界重合")
	gt(MapLayout.BOUNDARY_CENTER, MapData.BOUNDS, "墙心在可走边界之外，不能把墙修在地图里")
	gt(float(MapLayout.BOUNDARY_THICK), 0.0, "墙必须有厚度，否则侧面看是一条纸片")
	gt(float(MapLayout.BOUNDARY_HEIGHT), 1.6, "墙要明显高于角色视线里的地面起伏")

func test_walkable_area_never_reaches_into_the_wall() -> void:
	# 人能走到的极限是 BOUNDS - radius - 相机安全边距；必须还在墙内侧。
	var farthest: float = MapData.BOUNDS - MAX_HERO_RADIUS - MapData.CAMERA_WALL_MARGIN
	lt(farthest, MapLayout.boundary_inner(), "可走极限必须在墙内侧")
	# 反过来：空隙只能来自相机安全边距，不能多让 —— 多让就是白丢可走面积。
	near(
		MapLayout.boundary_inner() - farthest,
		MAX_HERO_RADIUS + MapData.CAMERA_WALL_MARGIN,
		EPS,
		"墙前空隙必须恰好等于相机安全边距"
	)

func test_visual_wall_is_not_in_the_collision_list() -> void:
	# 边界墙刻意不进 Collision.WALLS：拦人是 clamp_bounds 的职责。
	# 两者叠在一起会让贴边的人被反复推挤（夹取 → 推离 → 再夹取），表现为原地抖动。
	for wall in MapLayout.WALLS:
		check(
			not str(wall.get("id", "")).begins_with("boundary_"),
			"内部墙体列表里不能混进边界墙：%s" % str(wall.get("id", ""))
		)
	# 而且真的走不过去：可走区内的点不被阻挡，区外的点会被夹回来。
	check(not Collision.is_blocked(Vector2(0.0, 0.0), MAX_HERO_RADIUS), "地图中央不该被挡")
	var limit := MapData.BOUNDS - MAX_HERO_RADIUS - MapData.CAMERA_WALL_MARGIN
	var clamped := Collision.clamp_bounds(Vector2(200.0, 200.0), MAX_HERO_RADIUS)
	near(clamped.x, limit, EPS, "越界点必须被夹回可走极限 x")
	near(clamped.y, limit, EPS, "越界点必须被夹回可走极限 y")

func test_boundary_wall_is_masonry_with_rising_buttress_caps() -> void:
	# 旧版每 9 米立一根 5.2 米等距方柱 + 浅色柱帽，俯视就是一圈**城垛**。
	# 中间那版改成墙顶撒随机岩脊，那是「塌方」的语言，而参考图是一道**砌筑**的城墙。
	# 契约（对照参考图）：压顶石外挑 + 内侧等距壁柱 + 柱帽越出压顶一起伏线。
	var data_source := FileAccess.get_file_as_string("res://sim/map/map_layout.gd")
	check(not data_source.contains("BOUNDARY_POST_SPACING"), "边界墙不该再有等距塔柱的间距常量")
	check(not data_source.contains("BOUNDARY_POST_HEIGHT"), "边界墙不该再有塔柱高度常量")
	check(not data_source.contains("BOUNDARY_CREST_"), "边界墙不该再靠随机岩脊破平顶，改用壁柱帽")
	var build_source := FileAccess.get_file_as_string("res://scripts/game/arena.gd")
	check(not build_source.contains("post_cap"), "柱帽那套部件应当整段删掉")

	# 压顶石必须**外挑**：参考图里顶面比墙面探出一条，那是城墙最清楚的横向线。
	gt(float(MapLayout.BOUNDARY_COPING_OVERHANG), 0.05, "压顶石要探出墙面，齐平就只是一块厚板")
	lt(float(MapLayout.BOUNDARY_COPING_OVERHANG), 0.6, "压顶探出太多会变成一条檐廊")

	var arena: Node3D = Arena.new()
	arena._props_root = Node3D.new()
	arena.add_child(arena._props_root)
	arena.call("_build_boundary_walls")
	var sides := {}
	var tops := {}
	for child in arena._props_root.get_children():
		if not str(child.name).begins_with("buttress_boundary_"):
			continue
		var side := str((child as Node).get_meta("side", ""))
		if side == "":
			continue
		sides[side] = int(sides.get(side, 0)) + 1
		if str((child as Node).get_meta("kind", "")) != "body":
			continue
		var box: BoxMesh = ((child as MeshInstance3D).mesh) as BoxMesh
		if box == null:
			continue
		gt(box.size.z, MapLayout.BOUNDARY_THICK + 0.1, "边界壁柱要外挑出墙面：%s" % str(child.name))
		if not tops.has(side):
			tops[side] = []
		(tops[side] as Array).append((child as Node3D).position.y + box.size.y * 0.5)
	arena.free()
	eq(sides.size(), 4, "四面墙都要有壁柱，只做一面等于没做")
	for side in sides:
		gt(float(sides[side]), 5.0, "%s 这面墙的壁柱太少（%d 根），节奏断了" % [side, int(sides[side])])
	# 最高点必须留在 BOUNDARY_TOP 预算内：相机的安全边距是按它反解的。
	for side in tops:
		var list: Array = tops[side]
		if list.is_empty():
			continue
		lt(float(list.max()), MapLayout.BOUNDARY_TOP + 0.001, "%s 的壁柱高出了遮挡预算" % side)

func test_boundary_wall_has_real_depth() -> void:
	# 1 米厚在 51° 俯视下只剩一条石板边；加厚之后墙顶才有进深。
	gt(float(MapLayout.BOUNDARY_THICK), 1.4, "边界墙要够厚，才读得出是一道墙而不是栅栏")
	near(MapLayout.boundary_inner(), MapData.BOUNDS, EPS, "加厚不能把内表面推进可走区")

func test_vegetation_keeps_clear_of_the_boundary() -> void:
	check(MapLayout.near_boundary(Vector2(58.0, 0.0)), "贴墙的点要判为接近边界")
	check(MapLayout.near_boundary(Vector2(0.0, -58.0)), "贴墙的点要判为接近边界")
	check(MapLayout.near_boundary(Vector2(-57.0, 30.0)), "墙内侧 1m 也要判为接近边界")
	check(not MapLayout.near_boundary(Vector2(0.0, 0.0)), "地图中央不该被判为接近边界")
	check(not MapLayout.near_boundary(Vector2(46.0, -46.0)), "基地不算贴边界（要留出活动空间）")

func test_walking_into_the_wall_stops_cleanly() -> void:
	# 墙是视觉的、拦人的是 clamp —— 两者如果对不齐，贴边的人会「原地踏步」：
	# 目标点在墙外、人永远到不了，走路动画一直播。
	var radius := MAX_HERO_RADIUS
	var limit := MapData.BOUNDS - radius - MapData.CAMERA_WALL_MARGIN
	var stopped := Collision.move(Vector2(50.0, 0.0), Vector2(70.0, 0.0), radius)
	near(stopped.x, limit, 0.05, "走向边界必须停在可走极限")
	near(stopped.y, 0.0, 0.05, "贴边不该把人横向推开")
	# 再发一次同样的指令，位置必须纹丝不动。
	var again := Collision.move(stopped, Vector2(70.0, 0.0), radius)
	near(again.distance_to(stopped), 0.0, 0.001, "贴墙后重复移动指令不能来回抖动")
	# 角落也是一样：两个方向同时到边不能互相顶。
	var corner := Collision.move(Vector2(50.0, 50.0), Vector2(70.0, 70.0), radius)
	near(corner.x, limit, 0.05, "角落 x 停在可走极限")
	near(corner.y, limit, 0.05, "角落 y 停在可走极限")

func test_arena_actually_builds_the_boundary() -> void:
	# "文件在 + 数据对" ≠ "墙真的建出来了"。真跑一次构建函数，数节点。
	var arena = Arena.new()
	arena._props_root = Node3D.new()
	arena.add_child(arena._props_root)
	arena.call("_build_boundary_walls")
	var named := 0
	for child in arena._props_root.get_children():
		if str(child.name).begins_with("boundary_"):
			named += 1
	eq(named, 4, "四面边界墙必须各自作为独立节点建出来")
	# 墙 + 压顶 + 塔柱 + 柱帽，总量应该远超四面墙本身。
	gt(float(arena._props_root.get_child_count()), 30.0, "边界墙除了墙体还应该有压顶与塔柱")
	arena.free()

func test_minimap_draws_the_boundary_frame() -> void:
	# 小地图原来只画了左边和上边两条淡线，玩家看不出这是一圈墙。
	var source := FileAccess.get_file_as_string("res://scripts/ui/minimap.gd")
	check(source.contains("draw_rect(frame"), "小地图必须把边界画成闭合方框")
	check(source.contains("MapData.BOUNDS"), "小地图的边界尺寸必须来自 MapData.BOUNDS，不能写死")
