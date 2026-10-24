extends "res://tests/test_base.gd"

# 视觉地形的回归守卫。
#
# 地形高度**只影响画面**：模拟层的碰撞 / 寻路 / 视野全跑在 MapData 的 2D 平面上。
# 所以最关键的一条是「可玩区内高度必须严格为 0」——一旦地形在可玩区里抬起，
# 单位（永远在 y=0）就会陷进坡里，而这种失效 tsc / 构建 / 其余测试都不会报错。

const TerrainBuilder = preload("res://scripts/game/terrain_builder.gd")
const MapData = preload("res://sim/map_data.gd")

func _terrain():
	return TerrainBuilder.new()

func test_playable_area_stays_perfectly_flat() -> void:
	# 单位最远走到 ±BOUNDS。除了河道（本身就是障碍）之外，任何一点都必须是 0。
	var terrain = _terrain()
	var limit: float = MapData.BOUNDS - 0.5
	var river_safe: float = MapData.RIVER_HALF_WIDTH + TerrainBuilder.RIVER_SLOPE + 2.0
	var worst := 0.0
	var worst_at := Vector2.ZERO
	for i in 48:
		var angle := TAU * float(i) / 48.0
		for r in [0.0, 12.0, 26.0, 40.0, limit]:
			var x: float = cos(angle) * r
			var z: float = sin(angle) * r
			if terrain.river_distance(x, z) < river_safe:
				continue
			var h: float = terrain.height_at(x, z)
			if absf(h) > absf(worst):
				worst = h
				worst_at = Vector2(x, z)
	near(worst, 0.0, 0.001, "terrain must be flat inside playable area, worst point (%.1f, %.1f)" % [worst_at.x, worst_at.y])

func test_rise_starts_outside_bounds() -> void:
	# 抬升起点必须严格大于可玩边界，否则边界附近的人会被埋。
	gt(TerrainBuilder.PLAY_HALF, float(MapData.BOUNDS), "terrain rise must start beyond MapData.BOUNDS")

func test_river_bed_is_below_water_surface() -> void:
	# 河心必须下陷，且比水面低 —— 否则水面浮在草地上、或者河床露出水面。
	var terrain = _terrain()
	var bed: float = terrain.height_at(0.0, 0.0)
	lt(bed, -1.0, "river bed must be carved below the flat plane")
	# 水面在 -0.42（见 arena._build_river），河床必须比它低
	lt(bed, -0.42, "river bed must sit below the water surface")
	gt(bed, -4.0, "river bed must not be a bottomless pit")

func test_river_distance_matches_sim_collision() -> void:
	# 视觉河道和碰撞河道必须同源，否则会出现「看得见水却能走进去」。
	var terrain = _terrain()
	near(terrain.river_distance(9.0, -9.0), 0.0, 0.001, "point on the river centre line")
	near(terrain.river_distance(0.0, 0.0), 0.0, 0.001, "map centre is on the river line")
	# 沿法线 (1,1)/√2 走 RIVER_HALF 正好到岸线
	var half: float = MapData.RIVER_HALF_WIDTH
	var on_bank := half * 0.70710678
	near(terrain.river_distance(on_bank, on_bank), half, 0.01, "river_distance must match RIVER_HALF_WIDTH")

func test_outer_ring_lifts_into_hills() -> void:
	# 地图外围要有真实起伏，否则还是「一块平板 + 一圈纸片山」。
	# 河道走廊是刻意不抬升的（山丘被河谷切开），采样要避开它。
	var terrain = _terrain()
	var heights: Array[float] = []
	for i in 24:
		var angle := TAU * float(i) / 24.0
		var x: float = cos(angle) * 100.0
		var z: float = sin(angle) * 100.0
		if terrain.river_distance(x, z) < 30.0:
			continue
		heights.append(terrain.height_at(x, z))
	gt(float(heights.size()), 8.0, "sample ring must have points outside the river corridor")
	var lowest := heights[0]
	var highest := heights[0]
	for h in heights:
		lowest = minf(lowest, h)
		highest = maxf(highest, h)
	gt(lowest, 2.0, "outer ring must rise into hills, not stay flat")
	gt(highest - lowest, 3.0, "hills need variation, otherwise it reads as a smooth dome")

func test_river_corridor_cuts_through_the_hills() -> void:
	# 河谷不能被丘陵堵死：河心在外围也必须保持低洼，
	# 否则水面会插进山体里，河看起来是断的。
	var terrain = _terrain()
	for r in [70.0, 90.0, 110.0]:
		var p := Vector2(r * 0.70710678, -r * 0.70710678)
		lt(terrain.height_at(p.x, p.y), 0.5, "river corridor must stay low at radius %.0f" % r)

func test_mesh_is_a_single_shared_index_surface() -> void:
	var terrain = _terrain()
	var mesh: ArrayMesh = terrain.build_mesh()
	check(mesh != null, "terrain must build a mesh")
	if mesh == null:
		return
	eq(mesh.get_surface_count(), 1, "terrain must be one surface (one draw call)")
	var arrays: Array = mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var row := TerrainBuilder.CELLS + 1
	eq(verts.size(), row * row, "terrain vertex count must be shared-indexed, not per-triangle")
	eq(indices.size(), TerrainBuilder.CELLS * TerrainBuilder.CELLS * 6, "terrain index count")
	check(arrays[Mesh.ARRAY_NORMAL] != null, "terrain needs normals for lighting")
	check(arrays[Mesh.ARRAY_TANGENT] != null, "terrain needs tangents for the normal map")
	var aabb := mesh.get_aabb()
	near(aabb.size.x, TerrainBuilder.SIZE, 0.01, "terrain must span SIZE on x")
	near(aabb.size.z, TerrainBuilder.SIZE, 0.01, "terrain must span SIZE on z")
