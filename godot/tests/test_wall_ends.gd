extends "res://tests/test_base.gd"

# 墙端露头（2026-10-25）
#
# 现象：墙体本身已经像石头了，但每段墙的**两端**都是被刀切过一样的平整矩形端面 ——
# 一排「切好的石块」摆在草地上，而不是一片山体。
#
# 真因：墙体是逐段独立的 BoxMesh，端面就是盒子的一个面，没有任何东西去收口。
# 想靠「转角」修也不成立：实测两段墙的端点根本没有接在一起（最近也有 3 米），
# 那是留给玩家钻的缺口，不是接缝。
#
# 契约（对齐王者荣耀的野区石壁：山体在两端**露头**）：
# 1. 每个墙端都算出一个露头位置（`MapLayout.wall_ends()`，一段墙两个）。
# 2. 露头石必须**盖住墙的截面**：半径不小于半个墙厚，否则端面还是从石头边上露出来。
# 3. 露头石必须**高过墙顶**，读成山岩，而不是墙顶压了块石子。
# 4. 尺寸由「离兵线 / 营地还剩多少」决定，空间不够就别放 —— 小兵不寻路，蹭到就卡死。
# 5. 与墙身共用同一份石壁材质。

const MapData = preload("res://sim/map_data.gd")
const MapLayout = preload("res://sim/map/map_layout.gd")
const Arena = preload("res://scripts/game/arena.gd")

const MIN_RADIUS := 0.85

func test_every_wall_has_two_ends_and_they_point_outward() -> void:
	var ends: Array = MapLayout.wall_ends()
	eq(ends.size(), MapLayout.WALLS.size() * 2, "每段墙两个端头，一个都不能少")
	var keys := {}
	for entry in ends:
		var key := "%s:%s" % [str(entry.wall), str(entry.end)]
		check(not keys.has(key), "端头重复：%s" % key)
		keys[key] = true
		# 「朝外」方向必须背离墙身：露头石是往墙外探出去的，朝里就变成墙中间的疙瘩。
		var wall := _wall_by_id(str(entry.wall))
		if wall.is_empty():
			continue
		var other: Vector2 = wall.b if str(entry.end) == "a" else wall.a
		var outward: Vector2 = entry.outward
		gt(outward.dot((entry.pos as Vector2) - other), 0.5, "端头朝向搞反了：%s" % key)

func _wall_by_id(id: String) -> Dictionary:
	for wall in MapLayout.WALLS:
		if str(wall.id) == id:
			return wall
	return {}

func test_end_rocks_are_wide_enough_to_swallow_the_wall_face() -> void:
	# 半径小于半个墙厚时，石头只盖住端面的中间，两侧墙角仍然露在外面 ——
	# 那还是「一块石头贴在被切平的墙头上」，收不了口。
	# 另一头也要管住：1.9 米的半径在画面上是一块 3.8 米宽的巨板，
	# 比墙厚两倍多，站在旁边看就是「墙边放了块水泥预制板」。
	for entry in MapLayout.wall_ends():
		var radius: float = float(entry.radius)
		if radius < MIN_RADIUS:
			continue
		gt(radius, MapLayout.WALL_THICKNESS * 0.5 - 0.15, "露头石盖不住墙截面：半径 %.2f @ %s" % [radius, str(entry.id)])
		lt(radius, MapLayout.WALL_THICKNESS * 1.2, "露头石比墙厚一倍还多，会读成水泥预制板：半径 %.2f @ %s" % [radius, str(entry.id)])

func test_end_rocks_never_reach_into_a_lane_camp_or_pit() -> void:
	for entry in MapLayout.wall_ends():
		var pos: Vector2 = entry.pos
		var radius: float = float(entry.radius)
		if radius < MIN_RADIUS:
			continue
		gt(
			MapLayout.distance_to_lanes(pos),
			MapData.LANE_HALF_WIDTH + radius + 0.2,
			"露头石伸进兵线路面 %.2f 米：%s（半径 %.2f）" % [
				MapLayout.distance_to_lanes(pos) - MapData.LANE_HALF_WIDTH - radius, str(entry.id), radius,
			]
		)
		for camp in MapLayout.CAMPS:
			gt(
				pos.distance_to(camp.pos),
				float(camp.radius) + radius + 0.15,
				"露头石盖住营地 %s：%s" % [str(camp.id), str(entry.id)]
			)
		for pit in MapLayout.OBJECTIVE_PITS:
			gt(
				pos.distance_to(pit.pos),
				float(pit.radius) + radius + 0.15,
				"露头石盖住首领坑 %s：%s" % [str(pit.id), str(entry.id)]
			)
		for pad in MapLayout.TELEPORT_PADS:
			gt(
				pos.distance_to(pad.pos),
				3.0 + radius + 0.15,
				"露头石盖住传送阵 %s：%s" % [str(pad.id), str(entry.id)]
			)

func test_every_wall_end_is_capped_or_deliberately_skipped() -> void:
	# 「没生成」有两种：空间不够（合法）与漏了（bug）。这条把两者分开。
	var arena: Node3D = Arena.new()
	arena._props_root = Node3D.new()
	arena.add_child(arena._props_root)
	arena._build_map_features()
	var stone: ShaderMaterial = arena._wall_stone_material()
	var built := 0
	for entry in MapLayout.wall_ends():
		var node_name := "wall_end_%s_%s" % [str(entry.wall), str(entry.end)]
		var node: Node3D = arena._props_root.get_node_or_null(NodePath(node_name))
		if float(entry.radius) < MIN_RADIUS:
			check(node == null, "空间不够的墙端不该硬塞石头：%s" % node_name)
			continue
		check(node != null, "墙端缺少露头石，端面会直接露在玩家面前：%s" % node_name)
		if node == null:
			continue
		built += 1
		near(node.position.x, (entry.pos as Vector2).x, 0.4, "露头石要压在墙端上")
		near(node.position.z, (entry.pos as Vector2).y, 0.4, "露头石要压在墙端上")
		near(node.position.y, 0.0, 0.05, "露头石从地面长出来，不能浮空")
		near(
			float(node.get_meta("end_radius", 0.0)),
			float(entry.radius),
			0.001,
			"渲染用的半径必须就是 sim 层算出来的那个：%s" % node_name
		)
		for child in node.find_children("*", "MeshInstance3D", true, false):
			var mesh_instance := child as MeshInstance3D
			if mesh_instance.mesh == null:
				continue
			for surface in mesh_instance.mesh.get_surface_count():
				eq(mesh_instance.get_surface_override_material(surface), stone, "露头石必须与墙身同材质：%s" % node_name)
	gt(float(built), float(MapLayout.WALLS.size()) * 1.8, "至少九成墙端要真的长出石头，当前 %d" % built)
	arena.free()

func test_end_rocks_stay_below_the_wall_top_so_they_never_hide_the_hero() -> void:
	# 这条不是审美，是遮挡契约：野区墙没有「可走边界」可以兜底，
	# 英雄完全可以贴着墙根站。任何**高过墙顶**的部件都会把英雄整条盖住
	# （`test_wall_occlusion` 那套解法只对边界墙有效）。
	# 所以露头石必须比墙顶低，它的职责只是把平整端面收成断口，不是加高。
	var arena: Node3D = Arena.new()
	arena._props_root = Node3D.new()
	arena.add_child(arena._props_root)
	arena._build_map_features()
	var heights: Array[float] = []
	for entry in MapLayout.wall_ends():
		var node: Node3D = arena._props_root.get_node_or_null(
			NodePath("wall_end_%s_%s" % [str(entry.wall), str(entry.end)])
		)
		if node == null:
			continue
		var height: float = float(node.get_meta("end_height", 0.0))
		lt(height, float(MapLayout.WALL_HEIGHT) - 0.15, "露头石高过墙顶会挡住贴墙站的英雄，当前 %.2f" % height)
		gt(height, 1.2, "露头石低于 1.2 米只是一块墙脚碎石，收不了端面，当前 %.2f" % height)
		heights.append(height)
	gt(float(heights.size()), 0.0, "至少要有一块露头石")
	if heights.is_empty():
		return
	# 高度必须参差：等高的一圈石头，俯视看是一条锯齿完全相同的花边。
	gt(heights.max() - heights.min(), 0.15, "露头石高度要参差，当前跨度只有 %.2f 米" % (heights.max() - heights.min()))
	arena.free()
