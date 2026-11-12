extends "res://tests/test_base.gd"

# 基地装饰（P0 视觉升级，SCENE-01 的第一部分）。
# 每个基地 4 面旗 + 2 盏灯笼，纯程序化几何；不参与碰撞，不落在兵线路面里。

const Arena = preload("res://scripts/game/arena.gd")
const MapData = preload("res://sim/map_data.gd")
const MapGeometry = preload("res://scripts/game/map_geometry.gd")

func _arena_with_props() -> Node3D:
	var arena: Node3D = Arena.new()
	arena._props_root = Node3D.new()
	arena.add_child(arena._props_root)
	arena._build_map_features()
	return arena

func test_each_base_has_banners_and_lanterns() -> void:
	var arena := _arena_with_props()
	for team in ["blue", "red"]:
		var banners := 0
		var lanterns := 0
		for child in arena._props_root.get_children():
			var name := str(child.name)
			if name.begins_with("base_banner_%s_" % team):
				banners += 1
			elif name.begins_with("base_lantern_%s_" % team):
				lanterns += 1
		check(banners >= 2, "%s 基地至少保留 2 面旗" % team)
		check(lanterns >= 1, "%s 基地至少保留 1 盏灯笼" % team)
	arena.free()

func test_base_props_sit_outside_the_plaza_and_off_the_lane() -> void:
	var arena := _arena_with_props()
	var bases := {"blue": MapData.BLUE_BASE, "red": MapData.RED_BASE}
	for child in arena._props_root.get_children():
		var name := str(child.name)
		if not (name.begins_with("base_banner_") or name.begins_with("base_lantern_")):
			continue
		var root := child as Node3D
		var team := "blue" if name.contains("_blue_") else "red"
		var base: Vector2 = bases[team]
		var point := Vector2(root.position.x, root.position.z)
		var distance := point.distance_to(base)
		check(distance > 8.0 and distance < 11.0, "%s 要绕在基地广场外沿（%.2f）" % [name, distance])
		check(MapGeometry.lane_distance(point) > 3.9, "%s 不能立在兵线路面里（%.2f）" % [name, MapGeometry.lane_distance(point)])
	arena.free()
