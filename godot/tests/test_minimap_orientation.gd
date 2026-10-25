extends "res://tests/test_base.gd"

## 小地图朝向（2026-10-25）。
##
## 相机 yaw 决定屏幕轴（arena._camera_forward）：蓝方朝世界 +Y 看、屏幕右是 -X；
## 红方朝 -Y 看、屏幕右是 +X。小地图如果照世界坐标直铺，蓝方玩家会看到自己在右上、
## 敌人在左下，而且左右方向和画面反着走。约定：**本队基地永远在左下角，敌方在右上角**。

const Minimap = preload("res://scripts/ui/minimap.gd")
const MapData = preload("res://sim/map_data.gd")

func _minimap(team: String) -> Minimap:
	var minimap := Minimap.new()
	minimap.size = Vector2(206.0, 206.0)
	minimap.set_snapshot({}, "p1", team)
	return minimap

# 与 arena._camera_forward() 同一口径：[forward, right]，都是世界平面坐标。
func _camera_axes(team: String) -> Array:
	return [Vector2(0.0, 1.0), Vector2(-1.0, 0.0)] if team == "blue" else [Vector2(0.0, -1.0), Vector2(1.0, 0.0)]

func test_own_base_sits_bottom_left_for_every_team() -> void:
	for team in ["blue", "red"]:
		var minimap := _minimap(team)
		var own := MapData.BLUE_BASE if team == "blue" else MapData.RED_BASE
		var enemy := MapData.RED_BASE if team == "blue" else MapData.BLUE_BASE
		var own_screen := minimap.world_to_screen(own)
		var enemy_screen := minimap.world_to_screen(enemy)
		lt(own_screen.x, minimap.size.x * 0.5, "%s 的自方基地必须在小地图左半边" % team)
		gt(own_screen.y, minimap.size.y * 0.5, "%s 的自方基地必须在小地图下半边" % team)
		gt(enemy_screen.x, minimap.size.x * 0.5, "%s 的敌方基地必须在小地图右半边" % team)
		lt(enemy_screen.y, minimap.size.y * 0.5, "%s 的敌方基地必须在小地图上半边" % team)
		minimap.free()

func test_minimap_axes_match_the_camera_for_every_team() -> void:
	# 只把基地摆对还不够：小地图的上下左右必须和 3D 画面的方向一致，
	# 否则玩家按「小地图上敌人往右压」去拦截，实际会跑到另一边。
	for team in ["blue", "red"]:
		var minimap := _minimap(team)
		var axes := _camera_axes(team)
		var forward: Vector2 = axes[0]
		var right: Vector2 = axes[1]
		var base := minimap.world_to_screen(Vector2.ZERO)
		var ahead := minimap.world_to_screen(forward * 10.0)
		var side := minimap.world_to_screen(right * 10.0)
		lt(ahead.y, base.y - 1.0, "%s: 相机前方必须是小地图上方" % team)
		gt(side.x, base.x + 1.0, "%s: 相机右方必须是小地图右方" % team)
		minimap.free()

func test_facing_arrows_follow_the_map_orientation() -> void:
	# 英雄朝向是**世界方向**，画到小地图上必须先过同一次翻转，
	# 否则蓝方玩家的箭头会指向自己实际行进的反方向。
	# 「推进方向」取相机前方：蓝方 +Y、红方 -Y，两家都是朝敌方半场。
	for team in ["blue", "red"]:
		var advance: Vector2 = _camera_axes(team)[0]
		var shown := Minimap.oriented(advance, team)
		gt(shown.dot(Vector2(0.0, -1.0)), 0.99, "%s: 朝敌方半场走的箭头必须指向小地图上方" % team)
		# 静态换算与实例换算必须一致。
		var minimap := _minimap(team)
		var base := minimap.world_to_screen(Vector2.ZERO)
		var moved := minimap.world_to_screen(advance * 10.0)
		near((moved - base).normalized().dot(Vector2(0.0, -1.0)), 1.0, 0.001,
			"%s: 世界朝向必须和位置使用同一套朝向变换" % team)
		minimap.free()

func test_clicking_the_map_lands_where_the_marker_is_shown() -> void:
	# 小地图变了朝向，点击/拖拽必须按同一套变换反算回世界坐标。
	for team in ["blue", "red"]:
		var minimap := _minimap(team)
		for world in [Vector2(30.0, -20.0), Vector2(-10.0, 35.0), Vector2.ZERO]:
			var screen := minimap.world_to_screen(world)
			var back: Variant = minimap.screen_to_world(screen)
			check(back != null, "%s: 内框内的点必须能反算" % team)
			near((back as Vector2).distance_to(world), 0.0, 0.01,
				"%s: 点击反算必须回到原世界坐标" % team)
			var clamped := minimap.screen_to_world_clamped(screen)
			near(clamped.distance_to(world), 0.0, 0.01,
				"%s: 拖拽反算同样要回到原坐标" % team)
		minimap.free()

func test_map_frame_stays_positive_under_flipped_orientation() -> void:
	# 边框以前用「世界左上角 / 右下角」两个点算矩形；朝向翻转后这两个点会互换，
	# 得到负尺寸，整条墙带都画不出来。
	for team in ["blue", "red"]:
		var minimap := _minimap(team)
		var frame := minimap.map_frame()
		gt(frame.size.x, 0.0, "%s: 地图边框宽度必须为正" % team)
		gt(frame.size.y, 0.0, "%s: 地图边框高度必须为正" % team)
		near(frame.size.x, minimap._inner_size(), 0.01, "%s: 边框必须等于内框" % team)
		# 四个世界角点必须落在边框的四条边上（顺序可以变，集合不变）。
		var corners := [
			minimap.world_to_screen(Vector2(-MapData.BOUNDS, -MapData.BOUNDS)),
			minimap.world_to_screen(Vector2(MapData.BOUNDS, -MapData.BOUNDS)),
			minimap.world_to_screen(Vector2(MapData.BOUNDS, MapData.BOUNDS)),
			minimap.world_to_screen(Vector2(-MapData.BOUNDS, MapData.BOUNDS)),
		]
		for corner in corners:
			check(frame.grow(0.01).has_point(corner), "%s: 世界角点必须落在小地图边框上" % team)
		minimap.free()
