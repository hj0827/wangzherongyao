extends "res://tests/test_base.gd"

# 点击小地图查看区域情报的行为契约：
# 1. 地图位置 → 区域分类（泉水 / 河道 / 三路 / 野区）必须确定且可无头验证。
# 2. 情报只统计半径内「存活、非自己」的单位，按距离排序并限条数。
# 3. 小地图点击坐标必须能反投影回世界坐标，边框点击不触发。
# 4. 情报面板已移除：HUD 侧只负责把点击转成相机定位（见 test_minimap_camera_focus）。

const MapIntel = preload("res://sim/map_intel.gd")
const MapData = preload("res://sim/map_data.gd")
const Minimap = preload("res://scripts/ui/minimap.gd")

func _entity(type: String, team: String, pos: Vector2, hp := 100.0, alive := true, extra := {}) -> Dictionary:
	var data := {
		"type": type,
		"team": team,
		"x": pos.x,
		"y": pos.y,
		"hp": hp,
		"max_hp": hp,
		"alive": alive,
	}
	data.merge(extra, true)
	return data

func _snapshot() -> Dictionary:
	return {
		"time": 12.0,
		"ended": false,
		"entities": [
			_entity("hero", "blue", Vector2.ZERO, 1080.0, true, {
				"id": 1, "owner_id": "p1", "name": "你", "hero_type": "blade", "level": 3,
			}),
			_entity("hero", "blue", Vector2(6.0, 0.0), 700.0, true, {
				"id": 2, "owner_id": "p2", "name": "星璃", "hero_type": "mage", "level": 4,
				"max_hp": 840.0,
			}),
			_entity("hero", "red", Vector2(-8.0, 0.0), 1000.0, true, {
				"id": 3, "owner_id": "p9", "name": "铁壁", "hero_type": "tank", "level": 5,
				"max_hp": 1450.0,
			}),
			_entity("tower", "red", Vector2(12.0, 0.0), 2000.0, true, {
				"id": 4, "lane": "mid", "max_hp": 3500.0,
			}),
			_entity("hero", "blue", Vector2(2.0, 0.0), 0.0, false, {
				"id": 5, "owner_id": "p3", "name": "阵亡者", "hero_type": "archer", "level": 2,
			}),
			_entity("minion", "red", Vector2(0.0, 20.0), 120.0, true, {"id": 6, "lane": "mid"}),
		],
	}

# ---------------------------------------------------------------- 区域分类

func test_map_regions_are_classified_by_geometry() -> void:
	eq(str(MapIntel.region_at(MapData.BLUE_BASE).name), "蓝方泉水", "基地中心是蓝方泉水")
	eq(str(MapIntel.region_at(MapData.RED_BASE).name), "红方泉水", "红方基地中心是红方泉水")
	eq(str(MapIntel.region_at(Vector2(0.0, 0.0)).name), "河道", "地图中心的桥面属于河道")
	eq(str(MapIntel.region_at(Vector2(24.0, 24.0)).name), "中路", "中路兵线应识别为中路")
	eq(str(MapIntel.region_at(Vector2(-40.0, 8.0)).name), "上路", "上路航点应识别为上路")
	eq(str(MapIntel.region_at(Vector2(-20.0, -46.0)).name), "下路", "下路航点应识别为下路")
	eq(str(MapIntel.region_at(Vector2(-5.0, 25.0)).name), "野区", "远离兵线与河道的区域是野区")

func test_region_names_are_stable_for_team_fountains() -> void:
	eq(str(MapIntel.region_at(MapData.BLUE_BASE).kind), "fountain", "泉水必须有独立的 kind")
	eq(str(MapIntel.region_at(Vector2(-5.0, 25.0)).kind), "jungle", "野区必须有独立的 kind")
	check(str(MapIntel.region_at(Vector2(24.0, 24.0)).note).length() > 0, "区域应带一句可展示的说明")

# ---------------------------------------------------------------- 附近单位情报

func test_inspect_lists_only_alive_units_inside_radius() -> void:
	var report := MapIntel.inspect(_snapshot(), Vector2.ZERO, "p1", "blue")
	eq(str(report.region.name), "河道", "情报应带上区域名")
	eq(int(report.total), 3, "半径内只统计存活单位：自己、尸体与半径外小兵都不算")
	eq(int(report.counts.blue), 1, "蓝方存活单位计数")
	eq(int(report.counts.red), 2, "红方存活单位计数")
	near(float(report.hero_distance), 0.0, 0.001, "点击点与自己重合时距离为 0")
	check(bool(report.hero_found), "应能定位本地英雄")

func test_inspect_sorts_by_distance_and_labels_entity_types() -> void:
	var report := MapIntel.inspect(_snapshot(), Vector2.ZERO, "p1", "blue")
	var units: Array = report.units
	eq(int(units.size()), 3, "情报条目数量")
	eq(str(units[0].label), "星璃", "最近的单位排在最前")
	eq(str(units[1].label), "铁壁", "按距离排序")
	eq(str(units[2].label), "防御塔", "防御塔使用类型名作为标题")
	near(float(units[0].distance), 6.0, 0.001, "第一条距离")
	near(float(units[1].distance), 8.0, 0.001, "第二条距离")
	near(float(units[2].distance), 12.0, 0.001, "第三条距离")
	eq(str(units[2].kind), "tower", "条目保留实体类型")

func test_inspect_caps_rows_but_keeps_full_counts() -> void:
	var entities: Array = []
	for i in 7:
		entities.append(_entity("minion", "red", Vector2(float(i + 1), 0.0), 100.0, true, {"id": 100 + i}))
	var report := MapIntel.inspect({"entities": entities}, Vector2.ZERO, "p1", "blue")
	eq(int(report.total), 7, "total 统计完整数量")
	eq(int(report.units.size()), MapIntel.MAX_UNITS, "列表只展示前 MAX_UNITS 条")
	eq(int(report.counts.red), 7, "计数不受展示条数限制")
	check(not bool(report.hero_found), "快照里没有本地英雄时应明确标记")
	lt(float(report.hero_distance), 0.0, "找不到本地英雄时距离用负数表示未知")

# ---------------------------------------------------------------- 小地图点击 → 世界坐标

func test_minimap_click_emits_world_position() -> void:
	var minimap := Minimap.new()
	minimap.size = Vector2(206.0, 206.0)
	var hits: Array[Vector2] = []
	minimap.location_clicked.connect(func(point: Vector2) -> void: hits.append(point))
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = Vector2(103.0, 103.0)
	minimap._gui_input(click)
	eq(hits.size(), 1, "点击小地图应发出一次位置信号")
	near(hits[0].length(), 0.0, 0.01, "小地图中心对应世界原点")
	minimap.free()

func test_minimap_ignores_clicks_on_the_border() -> void:
	var minimap := Minimap.new()
	minimap.size = Vector2(206.0, 206.0)
	var hits: Array[Vector2] = []
	minimap.location_clicked.connect(func(point: Vector2) -> void: hits.append(point))
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = Vector2(3.0, 3.0)
	minimap._gui_input(click)
	eq(hits.size(), 0, "点在边框 / 面板留白上不应触发情报")
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	release.position = Vector2(103.0, 103.0)
	minimap._gui_input(release)
	eq(hits.size(), 0, "鼠标松开不应重复触发情报")
	minimap.free()

func test_minimap_projection_round_trip() -> void:
	var minimap := Minimap.new()
	minimap.size = Vector2(206.0, 206.0)
	var corners := [
		Vector2(13.0, 13.0),
		Vector2(192.0, 192.0),
		Vector2(103.0, 60.0),
	]
	for screen in corners:
		var world: Variant = minimap.screen_to_world(screen)
		check(world != null, "可点击区域内必须能反投影：%s" % str(screen))
		if world != null:
			var back := minimap.world_to_screen(world)
			near(back.distance_to(screen), 0.0, 0.01, "世界坐标往返投影必须还原")
	check(minimap.screen_to_world(Vector2(0.0, 0.0)) == null, "面板留白不允许被投影成世界坐标")
	minimap.free()

func test_minimap_touch_tap_also_inspects() -> void:
	var minimap := Minimap.new()
	minimap.size = Vector2(206.0, 206.0)
	var hits: Array[Vector2] = []
	minimap.location_clicked.connect(func(point: Vector2) -> void: hits.append(point))
	var tap := InputEventScreenTouch.new()
	tap.pressed = true
	tap.position = Vector2(140.0, 103.0)
	minimap._gui_input(tap)
	eq(hits.size(), 1, "移动端点按小地图同样应发出定位")
	gt(hits[0].x, 0.0, "点击右侧应对应世界 x 正方向")
	minimap.free()
