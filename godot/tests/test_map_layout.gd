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
		# 切角平滑后不应再保留原折线的尖角点（起点/终点除外）。
		for index in range(1, path.size() - 1):
			var corner: Vector2 = path[index]
			for point in smooth:
				gt(point.distance_to(corner), 0.5, "%s 的折线尖角应被切圆" % lane)

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
	for camp in MapLayout.CAMPS:
		var mirrored_pos := MapLayout.mirror(camp.pos)
		var mirrored_camp := MapLayout.camp_at(mirrored_pos)
		check(not mirrored_camp.is_empty(), "野区营地必须镜像：" + str(camp.id))
		if not mirrored_camp.is_empty():
			eq(str(mirrored_camp.buff), str(camp.buff), "镜像营地提供同类型增益")
	for pit in MapLayout.OBJECTIVE_PITS:
		check(MapLayout.objective_at(MapLayout.mirror(pit.pos)).size() > 0, "首领坑必须镜像：" + str(pit.id))

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
