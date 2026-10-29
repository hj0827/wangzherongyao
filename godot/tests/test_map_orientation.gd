extends "res://tests/test_base.gd"

# 地图朝向的回归守卫。
#
# 2026-10-24 把整张图顺时针转了 90°。旋转是在**数据层**做完的（直接改坐标值），
# 不是运行时变换 —— 于是所有下游（渲染 / 碰撞 / 视野 / 小地图）自动跟上，
# 但有两个东西必须同步改，否则会「看得见的河」和「算出来的河」错位：
#   ① 河道判定式：x + y = 0  →  x - y = 0
#   ② 上下路镜像轴：y = x   →  y = -x
#
# 这类错位不会报错。地形会把河床挖在 A 处、水面画在 B 处，草丛判定按 C 处算，
# 玩家只会觉得「走到岸边莫名其妙开始减速」「河里居然能隐身」。

const MapData = preload("res://sim/map_data.gd")
const MapLayout = preload("res://sim/map/map_layout.gd")
const MapIntel = preload("res://sim/map_intel.gd")
const TerrainBuilder = preload("res://scripts/game/terrain_builder.gd")
const Arena = preload("res://scripts/game/arena.gd")

const EPS := 0.01

func test_the_map_is_recorded_as_one_quarter_turn() -> void:
	# 常量本身不参与计算（坐标已经写死在数据里），它的作用是让下一个读代码的人
	# 知道「这些数为什么长这样」，而不是当成随手乱填的魔数。
	eq(int(MapData.ORIENT_QUARTER_TURNS), 1, "地图应当是顺时针转过 1 个 90°")

func test_bases_sit_on_opposite_corners_of_the_rotated_diagonal() -> void:
	# 旋转后：蓝方右上 (46,-46)，红方左下 (-46,46)。
	near(MapData.BLUE_BASE.x, 46.0, EPS, "蓝方基地 x")
	near(MapData.BLUE_BASE.y, -46.0, EPS, "蓝方基地 y")
	near(MapData.RED_BASE.x, -46.0, EPS, "红方基地 x")
	near(MapData.RED_BASE.y, 46.0, EPS, "红方基地 y")
	# 两个基地关于地图中心 180° 对称：这是双方的公平性前提，旋转不能打破。
	near(MapData.BLUE_BASE.x, -MapData.RED_BASE.x, EPS, "两基地 x 关于原点对称")
	near(MapData.BLUE_BASE.y, -MapData.RED_BASE.y, EPS, "两基地 y 关于原点对称")

func test_river_centre_line_is_x_minus_y() -> void:
	# 河心线现在过 (46,46) 和 (-46,-46)，也就是两条边路 L 形拐角的跨河点。
	#
	# 这里原来拿「传送阵在河心线两侧、有向距离异号」当证据 —— 那个契约已经改了：
	# 两座阵 2026-10-28 挪到两个空角落的广场里，阵心 (∓52, ∓52) 正压在河心线上，
	# 有向距离都是 0，异号断言自然不成立。河心线本身改用两条独立证据：
	#   ① 两座阵绕原点 180° 对称 → 中点必然落在原点上；
	#   ② 河道之灵仍在河心线上（a = 0）。
	var pads: Array = MapLayout.TELEPORT_PADS
	eq(pads.size(), 2, "两端各一座传送阵")
	if pads.size() == 2:
		var a: Vector2 = pads[0].pos
		var b: Vector2 = pads[1].pos
		var mid := (a + b) * 0.5
		near(mid.x, 0.0, EPS, "两座传送阵的中点 x")
		near(mid.y, 0.0, EPS, "两座传送阵的中点 y（河心线过原点）")
		# 阵心就在河心线上：两个空角落本来就在河道两端。
		near(a.x - a.y, 0.0, EPS, "东南角阵心在河心线上")
		near(b.x - b.y, 0.0, EPS, "西北角阵心在河心线上")
	for spirit in MapLayout.RIVER_SPIRITS:
		var s: Vector2 = spirit.pos
		near(absf(s.x - s.y), 0.0, EPS, "河道之灵必须在河心线上：%s" % str(spirit.id))
	# 地图中心是河心，也是桥面。
	eq(str(MapIntel.region_at(Vector2.ZERO).name), "河道", "地图中心是河道（桥面）")
	# 反例：旧河心线上的点现在必须不是河道，否则说明判定式没跟着改。
	check(str(MapIntel.region_at(Vector2(20.0, -20.0)).name) != "河道", "旧河心线 y=-x 不再是河道")

func test_mid_lane_and_river_are_perpendicular() -> void:
	# 中路沿 y = -x（连接两个基地），河道沿 y = x。二者垂直，中心交叉成桥。
	var mid: Array = MapData.lane_path("mid")
	var first: Vector2 = mid[0]
	var last: Vector2 = mid[mid.size() - 1]
	near(first.x, MapData.BLUE_BASE.x, EPS, "中路起点是蓝方基地")
	near(first.y, MapData.BLUE_BASE.y, EPS, "中路起点是蓝方基地")
	near(last.x, MapData.RED_BASE.x, EPS, "中路终点是红方基地")
	near(last.y, MapData.RED_BASE.y, EPS, "中路终点是红方基地")
	# 中路方向点乘河道方向 ≈ 0 → 垂直。
	var lane_dir := (last - first).normalized()
	var river_dir := Vector2(1.0, 1.0).normalized()
	near(lane_dir.dot(river_dir), 0.0, 0.001, "中路与河道必须垂直")

func test_every_lane_runs_from_blue_base_to_red_base() -> void:
	for lane in MapData.LANE_ORDER:
		var path: Array = MapData.lane_path(lane)
		var head: Vector2 = path[0]
		var tail: Vector2 = path[path.size() - 1]
		near(head.distance_to(MapData.BLUE_BASE), 0.0, EPS, "%s 路从蓝方基地出发" % lane)
		near(tail.distance_to(MapData.RED_BASE), 0.0, EPS, "%s 路抵达红方基地" % lane)
		# 航点不能越出地图：旋转后端点贴边（±46），比 BOUNDS(58) 小 12。
		for point in path:
			var p: Vector2 = point
			lt(absf(p.x), MapData.BOUNDS, "%s 路航点不能越界 x" % lane)
			lt(absf(p.y), MapData.BOUNDS, "%s 路航点不能越界 y" % lane)

func test_side_lanes_cross_the_river_only_at_their_corner() -> void:
	# 边路贴边以后必然要跨河道：河道沿 y = x 一直通到地图两端，
	# 而 L 形边路的拐角就落在这条线上。这是几何事实，不是瑕疵 ——
	# 王者峡谷的边路也是在河道端头跨过去的。
	# 要守住的是「别把整条边路泡在水里」：
	#   ① 落进河宽内的航点必须连成一段；
	#   ② 这一段不能太长（是一条跨河，不是沿河修路）；
	#   ③ 跨河点必须靠近河道端头，不能在河中央。
	for lane in ["top", "bottom"]:
		var path: Array = MapData.lane_path(lane)
		var wet: Array = []
		var spans := 0
		var previous_wet := false
		for point in path:
			var p: Vector2 = point
			var inside := absf(p.x - p.y) * 0.70710678 <= MapData.RIVER_HALF_WIDTH
			if inside:
				wet.append(p)
				if not previous_wet:
					spans += 1
			previous_wet = inside
		eq(spans, 1, "%s 路只该在拐角处跨河一次" % lane)
		eq(wet.size(), 3, "%s 路的跨河段应该是三点圆角（切入 / 弧中 / 切出）" % lane)
		if wet.is_empty():
			continue
		var span := 0.0
		var middle := Vector2.ZERO
		for p in wet:
			middle += p
		for i in wet.size():
			for j in range(i + 1, wet.size()):
				span = maxf(span, (wet[i] as Vector2).distance_to(wet[j]))
		middle /= float(wet.size())
		lt(span, 30.0, "%s 路的跨河段长 %.1f 米，已经是沿河修路而不是跨河" % [lane, span])
		gt(middle.length(), 40.0, "%s 路的跨河点离地图中心只有 %.1f 米，跑到河中央去了" % [lane, middle.length()])

func test_mirror_axis_is_y_equals_minus_x() -> void:
	# 新对称轴。手算两个点，避免 `MapLayout.mirror` 自己被改成恒等函数却仍然"自洽"。
	var m := MapLayout.mirror(Vector2(3.0, 7.0))
	near(m.x, -7.0, EPS, "mirror 的 x 分量")
	near(m.y, -3.0, EPS, "mirror 的 y 分量")
	# 上下路关于新轴对称：top 的每个航点镜像后都该落在 bottom 的航点上。
	var top: Array = MapData.lane_path("top")
	var bottom: Array = MapData.lane_path("bottom")
	for index in range(1, top.size() - 1):
		var mirrored := MapLayout.mirror(top[index])
		var best := INF
		for candidate in bottom:
			best = minf(best, mirrored.distance_to(candidate))
		near(best, 0.0, EPS, "上路第 %d 个航点关于 y=-x 应该镜像到下路" % index)

func test_the_old_mirror_axis_no_longer_lines_up() -> void:
	# 这条是"防回退"：如果有人把 mirror 改回 Vector2(point.y, point.x)，
	# 上一条仍然会过（因为上下路数据是自洽的），这一条会红 ——
	# 旧轴映射出来的点根本不在下路航点上。
	var top_point: Vector2 = MapData.lane_path("top")[2]      # (2, -50)
	var legacy := Vector2(top_point.y, top_point.x)            # 旧轴 -> (-50, 2)
	var nearest := INF
	for candidate in MapData.lane_path("bottom"):
		nearest = minf(nearest, legacy.distance_to(candidate))
	gt(nearest, 5.0, "旧 y=x 镜像轴映射出来的点已经不落在下路上")
	check(
		MapLayout.mirror(top_point).distance_to(legacy) > 1.0,
		"新 mirror 不能退化成旧的 x/y 交换"
	)

func test_three_modules_agree_on_the_river_distance() -> void:
	# 地形（视觉）、MapIntel（情报面板）、Arena（草地避让）各算各的，
	# 但必须给出同一个数。历史上这三份曾经不一致过。
	var terrain = TerrainBuilder.new()
	var samples := [
		Vector2(0.0, 0.0), Vector2(20.0, 2.0), Vector2(-13.0, 9.0),
		Vector2(40.0, -6.0), Vector2(-30.0, -30.0),
	]
	for sample in samples:
		var point: Vector2 = sample
		var canonical: float = absf(point.x - point.y) * 0.70710678
		near(terrain.river_distance(point.x, point.y), canonical, 0.001, "地形河道距离与公式一致：%s" % str(point))
	# 情报面板：河宽之内必须认成河道，之外必须不是。
	near(MapData.RIVER_HALF_WIDTH, 9.0, 0.001, "河宽常量")
	eq(str(MapIntel.region_at(Vector2(4.0, 4.0)).name), "河道", "河宽之内的点是河道")
	check(str(MapIntel.region_at(Vector2(30.0, 10.0)).name) != "河道", "河宽之外的点不是河道")

func test_arena_river_distance_helper_matches() -> void:
	# Arena 自己那份 _river_distance 是私有的，用反射调用，确保它没被漏改。
	var arena = Arena.new()
	var got: Variant = arena.call("_river_distance", Vector2(20.0, 2.0))
	near(float(got), absf(20.0 - 2.0) * 0.70710678, 0.001, "Arena 的河道距离必须同源")
	arena.free()
