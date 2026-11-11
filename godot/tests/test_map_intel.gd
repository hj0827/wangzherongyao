extends "res://tests/test_base.gd"

# 地图区域语义与小地图点击的行为契约：
# 1. 地图位置 → 区域分类（泉水 / 河道 / 三路 / 野区）必须确定且可无头验证。
# 2. 小地图点击坐标必须能反投影回世界坐标，边框点击不触发。
# 3. 情报面板已移除：HUD 侧只负责把点击转成相机定位（见 test_minimap_camera_focus）。

const MapIntel = preload("res://sim/map_intel.gd")
const MapData = preload("res://sim/map_data.gd")
const Minimap = preload("res://scripts/ui/minimap.gd")

# ---------------------------------------------------------------- 区域分类

func test_map_regions_are_classified_by_geometry() -> void:
	eq(str(MapIntel.region_at(MapData.BLUE_BASE).name), "蓝方泉水", "基地中心是蓝方泉水")
	eq(str(MapIntel.region_at(MapData.RED_BASE).name), "红方泉水", "红方基地中心是红方泉水")
	eq(str(MapIntel.region_at(Vector2(0.0, 0.0)).name), "河道", "地图中心的桥面属于河道")
	eq(str(MapIntel.region_at(Vector2(24.0, -24.0)).name), "中路", "中路兵线应识别为中路")
	eq(str(MapIntel.region_at(Vector2(-14.0, -50.0)).name), "上路", "上路航点应识别为上路")
	eq(str(MapIntel.region_at(Vector2(50.0, -18.0)).name), "下路", "下路航点应识别为下路")
	eq(str(MapIntel.region_at(Vector2(-5.0, 25.0)).name), "野区", "远离兵线与河道的区域是野区")

func test_region_names_are_stable_for_team_fountains() -> void:
	eq(str(MapIntel.region_at(MapData.BLUE_BASE).kind), "fountain", "泉水必须有独立的 kind")
	eq(str(MapIntel.region_at(Vector2(-5.0, 25.0)).kind), "jungle", "野区必须有独立的 kind")
	check(str(MapIntel.region_at(Vector2(24.0, -24.0)).note).length() > 0, "区域应带一句可展示的说明")

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
	# 小地图按本队朝向翻转，点按位置要按同一套变换反算并显示回原处。
	near(minimap.world_to_screen(hits[0]).distance_to(Vector2(140.0, 103.0)), 0.0, 0.01,
		"点按的位置必须和该世界点在图上显示的位置一致")
	minimap.free()
