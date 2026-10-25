extends "res://tests/test_base.gd"

# 小地图「按住看别处」的行为契约：
# 1. 点 / 拖小地图 → 相机滑到那个世界坐标（不是瞬移）。
# 2. 松手立刻回位（不再停留 N 秒）；但轻点一下至少展示 MIN_SHOW，否则什么也看不见。
# 3. 回位必须滑行，归位完成后恢复刚性跟随（否则会破坏移动时的稳定性）。
# 4. 小地图上要画出当前相机视野框，否则「点过去」看不出自己在看哪。
# 5. 情报面板已移除，点地图只移动镜头。
#
# CameraFocus 是纯逻辑（RefCounted），所有断言都不需要真实场景。

const CameraFocus = preload("res://scripts/game/camera_focus.gd")
const MapData = preload("res://sim/map_data.gd")
const Minimap = preload("res://scripts/ui/minimap.gd")
const GameHUD = preload("res://scripts/ui/game_hud.gd")

# ---------------------------------------------------------------- CameraFocus

func test_focus_follows_hero_rigidly_by_default() -> void:
	var focus := CameraFocus.new()
	var hero := Vector3(3.0, 0.0, -4.0)
	for i in 5:
		var point := focus.update(0.016, hero, 60.0)
		eq(point, hero, "没有观察请求时相机必须刚性跟随英雄，不能有滞后")
	check(not focus.is_active(), "默认不处于观察态")

func test_focus_glides_toward_requested_point() -> void:
	var focus := CameraFocus.new()
	var hero := Vector3.ZERO
	focus.request(Vector2(100.0, 0.0), hero)
	check(focus.is_active(), "请求后进入观察态")
	var first := focus.update(0.1, hero, 60.0)
	near(first.x, 6.0, 0.01, "第一帧只走 速度×delta 的距离（不能瞬移）")
	lt(first.x, 100.0, "不能一步跳到目标")
	for i in 60:
		focus.update(0.1, hero, 60.0)
	var settled := focus.update(0.1, hero, 60.0)
	near(settled.x, 100.0, 0.01, "滑行最终停在目标点（x）")
	near(settled.z, 0.0, 0.01, "世界 y 映射到焦点的 z")

func test_focus_release_after_long_look_returns_immediately() -> void:
	var focus := CameraFocus.new()
	var hero := Vector3.ZERO
	focus.request(Vector2(100.0, 0.0), hero)
	for i in 20:
		focus.update(0.1, hero, 60.0)
	check(focus.is_active(), "按住期间保持观察态")
	focus.release()
	check(not focus.is_active(), "松手立刻退出观察态，不再停留")
	var first := focus.update(0.05, hero, 60.0)
	lt(first.x, 100.0, "松手当帧就开始往回走")
	gt(first.x, 0.0, "回位是滑行，不是瞬移")
	for i in 200:
		focus.update(0.1, hero, 60.0)
	eq(focus.update(0.016, hero, 60.0), hero, "归位完成后必须恢复刚性跟随")

func test_focus_quick_tap_still_shows_the_spot() -> void:
	var focus := CameraFocus.new()
	var hero := Vector3.ZERO
	focus.request(Vector2(100.0, 0.0), hero)
	focus.update(0.05, hero, 200.0)
	focus.release()
	check(not focus.is_active(), "轻点松手后不再算按住")
	var shown := focus.update(0.1, hero, 200.0)
	gt(shown.x, 0.0, "轻点一下也要能看到那块画面，不能一闪而过")
	for i in 6:
		focus.update(0.1, hero, 200.0)
	var back := focus.update(0.1, hero, 200.0)
	lt(back.x, shown.x, "补足最小展示时间后自动归位")

func test_focus_drag_updates_target() -> void:
	var focus := CameraFocus.new()
	var hero := Vector3.ZERO
	focus.request(Vector2(10.0, 0.0), hero)
	for i in 3:
		focus.update(0.1, hero, 60.0)
	focus.request(Vector2(-30.0, 8.0), hero)
	for i in 4:
		focus.update(0.1, hero, 200.0)
	var point := focus.update(0.016, hero, 200.0)
	near(point.x, -30.0, 0.01, "拖拽会把焦点改到新位置（x）")
	near(point.z, 8.0, 0.01, "拖拽会把焦点改到新位置（z）")
	check(focus.is_active(), "拖拽期间始终保持观察态")

func test_focus_never_gets_stuck_without_release() -> void:
	var focus := CameraFocus.new()
	var hero := Vector3.ZERO
	focus.request(Vector2(100.0, 0.0), hero)
	for i in 100:
		focus.update(0.1, hero, 60.0)
	check(not focus.is_active(), "长时间收不到松手信号也要自动退出（兜底）")

# ---------------------------------------------------------------- 小地图拖拽

func _minimap() -> Minimap:
	var minimap := Minimap.new()
	minimap.size = Vector2(206.0, 206.0)
	return minimap

func _press(minimap: Minimap, local: Vector2) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	event.position = local
	minimap._gui_input(event)

func test_minimap_drag_emits_continuous_positions() -> void:
	var minimap := _minimap()
	var pressed: Array[Vector2] = []
	var dragged: Array[Vector2] = []
	var finished: Array[Vector2] = []
	minimap.location_clicked.connect(func(point: Vector2) -> void: pressed.append(point))
	minimap.location_dragged.connect(func(point: Vector2) -> void: dragged.append(point))
	minimap.drag_finished.connect(func(point: Vector2) -> void: finished.append(point))

	_press(minimap, Vector2(103.0, 103.0))
	eq(pressed.size(), 1, "按下即请求一次定位")
	minimap._drag_to(Vector2(160.0, 160.0))
	eq(dragged.size(), 1, "拖拽过程要持续发出位置")
	# 小地图按本队朝向翻转后，不能再假设「屏幕右下 = 世界正坐标」：
	# 断言改成「拖到哪里，该世界点就显示在哪里」。
	near(minimap.world_to_screen(dragged[0]).distance_to(Vector2(160.0, 160.0)), 0.0, 0.01,
		"拖到的位置必须和该世界点在图上显示的位置一致")
	minimap._end_drag()
	eq(finished.size(), 1, "松手发一次结束信号")
	check(not minimap._dragging, "松手后不再处于拖拽态")
	minimap.free()

func test_minimap_drag_clamps_outside_the_panel() -> void:
	var minimap := _minimap()
	var dragged: Array[Vector2] = []
	minimap.location_dragged.connect(func(point: Vector2) -> void: dragged.append(point))
	_press(minimap, Vector2(103.0, 103.0))
	minimap._drag_to(Vector2(600.0, -200.0))
	eq(dragged.size(), 1, "拖出面板边界仍要继续跟随，不能中断")
	# 拖出右上角 = 小地图右上角对应的世界角点；默认蓝方视角下是 (-X, +Y)。
	var corner := Minimap.oriented(Vector2(MapData.BOUNDS, -MapData.BOUNDS), "blue")
	near(dragged[0].x, corner.x, 0.01, "横向越界夹到小地图右边界")
	near(dragged[0].y, corner.y, 0.01, "纵向越界夹到小地图上边界")
	minimap._end_drag()
	minimap.free()

func test_minimap_ignores_drag_without_press() -> void:
	var minimap := _minimap()
	var dragged: Array[Vector2] = []
	minimap.location_dragged.connect(func(point: Vector2) -> void: dragged.append(point))
	minimap._drag_to(Vector2(160.0, 160.0))
	eq(dragged.size(), 0, "没按下时移动鼠标不该移动镜头")
	minimap.free()

func test_minimap_release_outside_still_ends_drag() -> void:
	var minimap := _minimap()
	var finished: Array[Vector2] = []
	minimap.drag_finished.connect(func(point: Vector2) -> void: finished.append(point))
	_press(minimap, Vector2(103.0, 103.0))
	minimap._drag_to(Vector2(400.0, 400.0))
	minimap._end_drag()
	eq(finished.size(), 1, "在面板外松手也要结束拖拽")
	minimap.free()

# 移动端是主目标平台，触摸拖拽必须独立走通（不能只依赖鼠标轮询）。
func test_minimap_touch_drag_keeps_following() -> void:
	var minimap := _minimap()
	var dragged: Array[Vector2] = []
	var finished := [0]
	minimap.location_dragged.connect(func(point: Vector2) -> void: dragged.append(point))
	minimap.drag_finished.connect(func(_point: Vector2) -> void: finished[0] += 1)

	var touch := InputEventScreenTouch.new()
	touch.pressed = true
	touch.position = Vector2(103.0, 103.0)
	minimap._gui_input(touch)
	check(minimap._dragging, "触摸按下进入拖拽态")
	check(minimap._drag_touch, "触摸拖拽必须标记为触摸，避免被鼠标轮询打断")

	var drag := InputEventScreenDrag.new()
	drag.position = Vector2(150.0, 150.0)
	minimap._gui_input(drag)
	eq(dragged.size(), 1, "触摸拖动要持续发出位置")
	near(minimap.world_to_screen(dragged[0]).distance_to(Vector2(150.0, 150.0)), 0.0, 0.01,
		"触摸拖到的位置必须和该世界点在图上显示的位置一致")

	var release := InputEventScreenTouch.new()
	release.pressed = false
	release.position = Vector2(150.0, 150.0)
	minimap._gui_input(release)
	eq(finished[0], 1, "触摸松手要发结束信号")
	check(not minimap._dragging, "触摸松手后退出拖拽态")
	minimap.free()

# ---------------------------------------------------------------- 视野圈

func test_minimap_vision_is_a_round_circle_not_a_polygon() -> void:
	# 视野范围在小地图上是一个**圆**，不是梯形：180px 的缩略图上，梯形的四个角只是
	# 四个尖点，一眼读不出「这就是镜头看到的范围」。
	# 半径取「和视野矩形等面积」的那个圆 —— 外接圆按 4:3 的长边算，屏幕上会比真正
	# 看到的范围大一圈；内切圆又反过来少报。等面积是唯一不谎报视野大小的取法。
	var minimap := _minimap()
	check(not minimap.has_camera_view(), "默认没有视野圈")
	var corners := PackedVector2Array([
		Vector2(-10.0, -17.0), Vector2(30.0, -17.0), Vector2(30.0, 7.0), Vector2(-10.0, 7.0),
	])
	minimap.set_camera_view({
		"valid": true,
		"points": corners,
		"center": Vector2(10.0, -5.0),
		"half": Vector2(20.0, 12.0),
	})
	check(minimap.has_camera_view(), "设置后视野圈可用")
	var circle := minimap.camera_view_circle()
	check(not circle.is_empty(), "视野圈必须给出圆心和半径")
	var center: Vector2 = circle["center"]
	near(center.distance_to(minimap.world_to_screen(Vector2(10.0, -5.0))), 0.0, 0.01,
		"圆心必须落在视野中心")
	var expected := sqrt(20.0 * 12.0) * minimap._world_scale()
	near(float(circle["radius"]), expected, 0.01,
		"半径必须按「与视野矩形等面积」取（当前 %.2f / 期望 %.2f）" % [float(circle["radius"]), expected])
	var outline := minimap.camera_view_outline()
	gt(float(outline.size()), 16.0, "圆至少要 16 段，少了会看出折线")
	for point in outline:
		near(point.distance_to(center), expected, 0.02,
			"轮廓上每一点到圆心的距离必须相等 —— 不等就还是多边形")
	minimap.free()

func test_minimap_vision_circle_clamps_to_inner_square() -> void:
	# 镜头贴到地图边缘时圆会超出内框：画出去会压在边框和面板底色上，
	# 所以轮廓点要夹进内框（夹出来的直边由墙体带盖住）。
	var minimap := _minimap()
	var inner := Rect2(minimap._inner_origin(), Vector2(minimap._inner_size(), minimap._inner_size()))
	minimap.set_camera_view({
		"valid": true,
		"points": PackedVector2Array([
			Vector2(-400.0, -400.0), Vector2(400.0, -400.0), Vector2(400.0, 400.0), Vector2(-400.0, 400.0),
		]),
		"center": Vector2.ZERO,
		"half": Vector2(400.0, 400.0),
	})
	var outline := minimap.camera_view_outline()
	gt(float(outline.size()), 16.0, "越界后仍然是完整的一圈轮廓")
	for point in outline:
		check(
			point.x >= inner.position.x - 0.01 and point.x <= inner.end.x + 0.01
			and point.y >= inner.position.y - 0.01 and point.y <= inner.end.y + 0.01,
			"视野圈不能画到地图内框之外",
		)
	minimap.free()

func test_minimap_vision_circle_disappears_when_the_view_is_invalid() -> void:
	# 镜头不在场景里（切场景/首帧）时 arena 会给 valid=false：这时必须什么都不画，
	# 而不是留一个上一次的圆停在原地。
	var minimap := _minimap()
	minimap.set_camera_view({"valid": true, "points": PackedVector2Array([
		Vector2(-10.0, -17.0), Vector2(30.0, -17.0), Vector2(30.0, 7.0), Vector2(-10.0, 7.0),
	])})
	check(not minimap.camera_view_circle().is_empty(), "有效视野必须有圆")
	minimap.set_camera_view({"valid": false})
	check(minimap.camera_view_circle().is_empty(), "视野失效后不能再画圆")
	eq(minimap.camera_view_outline().size(), 0, "视野失效后轮廓必须是空的")
	minimap.free()

# ---------------------------------------------------------------- HUD 转发

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
			_entity("hero", "red", Vector2(-8.0, 0.0), 1000.0, true, {
				"id": 3, "owner_id": "p9", "name": "铁壁", "hero_type": "tank", "level": 5,
			}),
		],
	}

func _hud() -> GameHUD:
	var hud := GameHUD.new()
	hud.setup("p1", "blue", "blade", "你", false, false)
	hud._ready()
	hud.update_snapshot(_snapshot())
	# 测试里 HUD 不在场景树中，容器不排版，手动给地图真实尺寸。
	hud._minimap.size = Vector2(206.0, 206.0)
	return hud

func test_hud_requests_camera_focus_on_minimap_click() -> void:
	var hud := _hud()
	var requests: Array[Vector2] = []
	var releases := [0]
	hud.map_focus_requested.connect(func(world: Vector2) -> void: requests.append(world))
	hud.map_focus_released.connect(func() -> void: releases[0] += 1)
	_press(hud._minimap, Vector2(103.0, 103.0))
	eq(requests.size(), 1, "按下即请求相机移动到该位置")
	hud._minimap._end_drag()
	eq(releases[0], 1, "松手要通知相机立刻回位")
	hud.free()

func test_hud_drag_keeps_camera_following() -> void:
	var hud := _hud()
	var requests: Array[Vector2] = []
	hud.map_focus_requested.connect(func(world: Vector2) -> void: requests.append(world))
	_press(hud._minimap, Vector2(103.0, 103.0))
	hud._minimap._drag_to(Vector2(170.0, 40.0))
	eq(requests.size(), 2, "拖拽要持续请求相机跟随")
	# 小地图按本队朝向翻转后，屏幕右/上对应的世界方向由 Minimap.oriented 决定。
	var delta := requests[1] - requests[0]
	var screen_right := Minimap.oriented(Vector2(1.0, 0.0), "blue")
	var screen_up := Minimap.oriented(Vector2(0.0, -1.0), "blue")
	gt(delta.dot(screen_right), 0.0, "拖到右边，相机要往画面上右边对应的世界方向走")
	gt(delta.dot(screen_up), 0.0, "拖到上边，相机要往画面上边对应的世界方向走")
	hud.free()

func test_hud_pushes_camera_view_box_to_minimap() -> void:
	var hud := _hud()
	var points := PackedVector2Array([
		Vector2(-4.0, -6.0), Vector2(16.0, -6.0), Vector2(16.0, 10.0), Vector2(-4.0, 10.0),
	])
	hud.set_camera_view({"valid": true, "points": points, "center": Vector2(6.0, 2.0), "half": Vector2(10.0, 8.0)})
	check(hud._minimap.has_camera_view(), "HUD 要把相机视野同步给小地图")
	hud.set_camera_view({"valid": false})
	check(not hud._minimap.has_camera_view(), "视野无效时要清掉框")
	hud.free()

# ---------------------------------------------------------------- 生产接线守卫

# 本仓库踩过「文件在、测试绿、生产引用为 0」的坑，这里钉住 arena 的真实接线。
func test_arena_wires_camera_focus_into_update_camera() -> void:
	var source := FileAccess.get_file_as_string("res://scripts/game/arena.gd")
	check(source.contains("CameraFocus"), "arena 必须 preload CameraFocus")
	check(source.contains("target = _camera_focus.update("), "相机每帧的注视点必须来自 CameraFocus 的结果")
	check(source.contains("func focus_world_point("), "arena 必须暴露 focus_world_point 给 HUD 调用")
	check(source.contains("hud.map_focus_requested.connect("), "HUD 的聚焦请求必须被 arena 接上")
	check(source.contains("hud.map_focus_released.connect("), "松手回位信号必须被 arena 接上")

# 情报面板已按需求移除，别让它悄悄回来。
func test_hud_no_longer_builds_map_intel_panel() -> void:
	var source := FileAccess.get_file_as_string("res://scripts/ui/game_hud.gd")
	check(not source.contains("_build_map_intel"), "情报面板已移除，不要再建")
	check(not source.contains("_intel_panel"), "情报面板控件已移除")

# 情报标记（十字）也一并移除：视野框已经表达了「镜头在哪」，
# 松手回位后十字还留在原地会误导。
func test_minimap_no_longer_draws_intel_marker() -> void:
	var source := FileAccess.get_file_as_string("res://scripts/ui/minimap.gd")
	check(not source.contains("_draw_inspect_marker"), "情报标记已移除")
	check(not source.contains("set_inspect_point"), "情报标记接口已移除")
