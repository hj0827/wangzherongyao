extends "res://tests/test_base.gd"

# 地图布局契约：三塔结构、上下路镜像、平滑兵线、墙体/草丛/野区/首领坑的静态数据。
# 这些数据同时被模拟层（碰撞/视野/塔序）和表现层（地面/小地图）读取，必须唯一可信。

const MapLayout = preload("res://sim/map/map_layout.gd")
const MapData = preload("res://sim/map_data.gd")

func test_each_lane_has_three_towers_per_team() -> void:
	eq(MapLayout.TOWER_TIERS.size(), 3, "每条路每方三座塔：外塔 / 内塔 / 高地塔")
	var slots: Array = MapLayout.tower_slots()
	eq(slots.size(), 18, "三路 × 双方 × 三塔 = 18 座防御塔")
	var seen := {}
	for slot in slots:
		var key := "%s|%s|%s" % [slot.lane, slot.team, slot.tier]
		check(not seen.has(key), "塔位不能重复：" + key)
		seen[key] = true
	eq(seen.size(), 18, "18 个唯一塔位")

func test_tower_tiers_get_closer_to_own_base() -> void:
	for lane in MapData.LANE_ORDER:
		for team in ["blue", "red"]:
			var base := MapData.BLUE_BASE if team == "blue" else MapData.RED_BASE
			var high := MapLayout.tower_anchor(str(lane), team, "high").distance_to(base)
			var inner := MapLayout.tower_anchor(str(lane), team, "inner").distance_to(base)
			var outer := MapLayout.tower_anchor(str(lane), team, "outer").distance_to(base)
			lt(high, inner, "%s/%s 高地塔必须比内塔更靠近己方基地" % [lane, team])
			lt(inner, outer, "%s/%s 内塔必须比外塔更靠近己方基地" % [lane, team])
			gt(outer - high, 15.0, "%s/%s 三塔之间必须有足够纵深，不能挤成一团" % [lane, team])

func test_lane_smoothing_keeps_endpoints_and_stays_in_bounds() -> void:
	for lane in MapData.LANE_ORDER:
		var path: Array = MapData.lane_path(lane)
		var smooth: Array = MapLayout.smoothed_lane(lane, 6)
		gt(smooth.size(), path.size(), "%s 兵线应经过平滑采样" % lane)
		near(smooth[0].distance_to(path[0]), 0.0, 0.001, "%s 平滑线起点必须与航点一致" % lane)
		near(smooth[smooth.size() - 1].distance_to(path[path.size() - 1]), 0.0, 0.001, "%s 平滑线终点必须与航点一致" % lane)
		for point in smooth:
			check(absf(point.x) <= MapData.BOUNDS + 0.001 and absf(point.y) <= MapData.BOUNDS + 0.001, "%s 平滑线不能越出地图" % lane)
		# 切角平滑只该吃掉**尖角**。
		# 边路贴边之后，航点里多了两类「不该被切」的点：直段加密点（转角 0°）
		# 和三点圆角的采样点（转角 22.5°）。一刀切地要求「每个航点都被切圆」
		# 会把直段也判成违规 —— 而直段一旦被切，96 米的长边就会缩成弧，
		# 贴边就白贴了。
		# 切掉多少本身与转角、段长成正比（Chaikin 的极限是二次 B 样条），
		# 所以按转角分档，判的是「有没有被磨」，而不是「必须磨掉多少」：
		#   > 30°   → 明显磨圆（≥ 0.8 米，约等于最短段长 6.4 米的 1/8）
		#   15~30°  → 有磨（≥ 0.3 米）
		#   ≤ 15°   → 保持原处（< 4 米，约等于最长段长的 1/4）
		for index in range(1, path.size() - 1):
			var corner: Vector2 = path[index]
			var turn := absf(
				(corner - (path[index - 1] as Vector2)).normalized().angle_to(
					((path[index + 1] as Vector2) - corner).normalized()
				)
			)
			var nearest := INF
			for point in smooth:
				nearest = minf(nearest, (point as Vector2).distance_to(corner))
			var degrees := rad_to_deg(turn)
			if degrees > 30.0:
				gt(nearest, 0.8, "%s 的尖角应被磨圆（第 %d 点，转角 %.1f°）" % [lane, index, degrees])
			elif degrees > 15.0:
				gt(nearest, 0.3, "%s 的浅转角也该有磨（第 %d 点，转角 %.1f°）" % [lane, index, degrees])
			else:
				lt(nearest, 4.0, "%s 的直段航点不该被平滑拉走（第 %d 点，转角 %.1f°）" % [lane, index, degrees])

func test_walls_bushes_camps_and_pits_are_mirrored() -> void:
	for wall in MapLayout.WALLS:
		var mirrored := MapLayout.mirror(wall.a)
		var found := false
		for other in MapLayout.WALLS:
			if other.a.distance_to(mirrored) < 0.01 or other.b.distance_to(mirrored) < 0.01:
				found = true
				break
		check(found, "墙体必须沿河道镜像：" + str(wall.id))
	for bush in MapLayout.BUSHES:
		check(not MapLayout.bush_at(MapLayout.mirror(bush.pos)).is_empty(), "草丛必须镜像：" + str(bush.id))
	# 营地与首领坑用的是**另一种**对称：绕地图中心 180°（-p），不是 y=-x 镜像。
	# 原因见 map_layout.gd CAMPS 顶部：mirror 保持 a（= 离河道多远）不变，
	# 也就是「同一个半场」，镜像出来的营地跟原营地同队。
	# 营地只要求**近似**对称（8 米容差）：两半场的石壁形状本来就不是同一个图形，
	# 精确旋转会把红方那座推进石头里（实测被压 1.6 米）。
	for camp in MapLayout.CAMPS:
		var turned: Vector2 = -(camp.pos as Vector2)
		var nearest := INF
		for other in MapLayout.CAMPS:
			if str(other.id) == str(camp.id):
				continue
			nearest = minf(nearest, (other.pos as Vector2).distance_to(turned))
		lt(nearest, 8.0, "营地要有 180° 附近的对家，最近的是 %.1f 米：%s" % [nearest, str(camp.id)])
	for pit in MapLayout.OBJECTIVE_PITS:
		lt((MapLayout.objective_at(-(pit.pos as Vector2)).get("pos", Vector2(999.0, 999.0)) as Vector2).distance_to(-(pit.pos as Vector2)), 0.01, "首领坑必须精确 180° 对称：" + str(pit.id))

func test_features_keep_clear_of_lane_centers_and_structures() -> void:
	for wall in MapLayout.WALLS:
		for t in [0.0, 0.25, 0.5, 0.75, 1.0]:
			var point: Vector2 = wall.a.lerp(wall.b, t)
			gt(MapLayout.distance_to_lanes(point), MapData.LANE_HALF_WIDTH + 2.0, "墙体不能压住兵线：" + str(wall.id))
	for camp in MapLayout.CAMPS:
		gt(MapLayout.distance_to_lanes(camp.pos), MapData.LANE_HALF_WIDTH + 2.0, "野区营地不能压在兵线上：" + str(camp.id))
	for pit in MapLayout.OBJECTIVE_PITS:
		gt(MapLayout.distance_to_lanes(pit.pos), MapData.LANE_HALF_WIDTH + 2.0, "首领坑不能压在兵线上：" + str(pit.id))
	for bush in MapLayout.BUSHES:
		gt(bush.pos.distance_to(MapData.BLUE_BASE), MapData.FOUNTAIN_RADIUS + 2.0, "草丛不能侵入蓝方泉水")
		gt(bush.pos.distance_to(MapData.RED_BASE), MapData.FOUNTAIN_RADIUS + 2.0, "草丛不能侵入红方泉水")

func test_bush_and_camp_lookup_by_point() -> void:
	var bush: Dictionary = MapLayout.bush_at(MapLayout.BUSHES[0].pos)
	eq(str(bush.id), str(MapLayout.BUSHES[0].id), "草丛中心必须命中该草丛")
	check(MapLayout.bush_at(Vector2.ZERO).is_empty(), "桥面中心不是草丛")
	var camp: Dictionary = MapLayout.camp_at(MapLayout.CAMPS[0].pos)
	eq(str(camp.id), str(MapLayout.CAMPS[0].id), "营地中心必须命中该营地")
	check(MapLayout.camp_at(Vector2.ZERO).is_empty(), "地图中心不是营地")
	eq(str(MapLayout.objective_at(MapLayout.OBJECTIVE_PITS[0].pos).id), str(MapLayout.OBJECTIVE_PITS[0].id), "首领坑中心必须命中")

func test_ground_marks_claim_their_discs() -> void:
	# 三块贴地圆盘（营地 / 首领坑 / 传送阵）是**实心片**：树根、草根长在盘面上
	# 就是「绿点从石盘里冒出来」。以前避让清单在渲染层手抄一遍、
	# 草丛那边干脆没抄，于是「树避开了、草没避开」。
	# 契约：占位判定只有一份，布景与草丛都读它。
	for camp in MapLayout.CAMPS:
		check(MapLayout.on_ground_mark(camp.pos as Vector2), "营地圆盘要占位：%s" % str(camp.id))
		check(
			not MapLayout.on_ground_mark(
				(camp.pos as Vector2) + Vector2(0.0, MapLayout.CAMP_DISC_RADIUS + 4.0)
			),
			"营地圆盘外面不该占位：%s" % str(camp.id)
		)
	for pit in MapLayout.OBJECTIVE_PITS:
		check(MapLayout.on_ground_mark(pit.pos as Vector2), "首领坑圆盘要占位：%s" % str(pit.id))
	for pad in MapLayout.TELEPORT_PADS:
		check(MapLayout.on_ground_mark(pad.pos as Vector2), "传送阵圆盘要占位：%s" % str(pad.id))
		# 阵盘边缘 1 米仍然算占位（树冠那一圈），这是它和营地不同的一点。
		check(
			MapLayout.on_ground_mark((pad.pos as Vector2) + Vector2(MapLayout.PAD_DISC_RADIUS + 1.0, 0.0)),
			"传送阵的树冠留白也算占位：%s" % str(pad.id)
		)
	check(not MapLayout.on_ground_mark(Vector2(0.0, 0.0)), "地图中心（桥面）不是任何圆盘")
