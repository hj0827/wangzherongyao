extends RefCounted

# 地图布局的唯一数据源。模拟层、战场表现、小地图与情报面板都必须从这里取点，
# 避免「地面画了一套墙、碰撞用了另一套」的错位。
#
# 坐标沿用 map_data.gd：蓝方基地 (-46,-46)，红方基地 (46,46)，河道沿 y=x。
# 上下路关于 y=x 镜像，因此所有墙体/草丛/营地/首领坑都成对定义。

const MapData = preload("res://sim/map_data.gd")

const TOWER_TIERS := ["outer", "inner", "high"]
const TOWER_RANKS := {"outer": 0, "inner": 1, "high": 2}
const TOWER_LABELS := {"outer": "外塔", "inner": "内塔", "high": "高地塔"}
# 从己方基地沿兵线量起的推进比例。外塔靠近中线，高地塔守在基地门前。
const TOWER_PROGRESS := {"outer": 0.36, "inner": 0.24, "high": 0.18}
const WALL_THICKNESS := 1.6

const BUSHES := [
	{"id": "bush_blue_mid", "pos": Vector2(-18.0, 18.0), "radius": 4.2},
	{"id": "bush_red_mid", "pos": Vector2(18.0, -18.0), "radius": 4.2},
	{"id": "bush_blue_jungle", "pos": Vector2(-28.0, 16.0), "radius": 3.8},
	{"id": "bush_red_jungle", "pos": Vector2(16.0, -28.0), "radius": 3.8},
	{"id": "bush_top_river", "pos": Vector2(6.0, 30.0), "radius": 3.6},
	{"id": "bush_bottom_river", "pos": Vector2(30.0, 6.0), "radius": 3.6},
]

const WALLS := [
	{"id": "wall_top_west", "a": Vector2(-36.0, -8.0), "b": Vector2(-26.0, 4.0)},
	{"id": "wall_bottom_west", "a": Vector2(-8.0, -36.0), "b": Vector2(4.0, -26.0)},
	{"id": "wall_top_east", "a": Vector2(-8.0, 20.0), "b": Vector2(2.0, 28.0)},
	{"id": "wall_bottom_east", "a": Vector2(20.0, -8.0), "b": Vector2(28.0, 2.0)},
]

# 四座营地两两镜像：上侧两座在蓝方野区，下侧两座在红方野区。
const CAMPS := [
	{"id": "blue_buff_blue_side", "pos": Vector2(-22.0, 12.0), "buff": "blue", "monster_type": "wolf", "name": "霜狼", "radius": 2.2},
	{"id": "red_buff_blue_side", "pos": Vector2(4.0, 20.0), "buff": "red", "monster_type": "wolf", "name": "赤狼", "radius": 2.2},
	{"id": "blue_buff_red_side", "pos": Vector2(12.0, -22.0), "buff": "blue", "monster_type": "wolf", "name": "霜狼", "radius": 2.2},
	{"id": "red_buff_red_side", "pos": Vector2(20.0, 4.0), "buff": "red", "monster_type": "wolf", "name": "赤狼", "radius": 2.2},
]

const OBJECTIVE_PITS := [
	{"id": "tyrant", "pos": Vector2(-38.0, 24.0), "name": "暴君", "monster_type": "orc", "radius": 2.8},
	{"id": "overlord", "pos": Vector2(24.0, -38.0), "name": "主宰", "monster_type": "orc", "radius": 2.8},
]

# 河道之灵：沿河道成对刷新，击杀后为全队提供一段河道视野。
const RIVER_SPIRITS := [
	{"id": "river_spirit_north", "pos": Vector2(-30.0, 30.0), "name": "河道之灵"},
	{"id": "river_spirit_south", "pos": Vector2(30.0, -30.0), "name": "河道之灵"},
]

# 传送阵：河道两端各一座，互为对端；引导期间移动/施法/受击都会打断。
const TELEPORT_PADS := [
	{"id": "river_pad_north", "pos": Vector2(-34.0, 34.0), "partner": "river_pad_south", "name": "北路传送阵"},
	{"id": "river_pad_south", "pos": Vector2(34.0, -34.0), "partner": "river_pad_north", "name": "南路传送阵"},
]

static func mirror(point: Vector2) -> Vector2:
	return Vector2(point.y, point.x)

static func mirror_lane(lane: String) -> String:
	if lane == "top":
		return "bottom"
	if lane == "bottom":
		return "top"
	return lane

static func lane_length(lane: String) -> float:
	var path: Array = MapData.lane_path(lane)
	var total := 0.0
	for index in range(path.size() - 1):
		total += (path[index + 1] as Vector2).distance_to(path[index])
	return total

# progress 始终从蓝方基地量起（0 = 蓝方基地，1 = 红方基地）。
static func point_along_lane(lane: String, progress: float) -> Vector2:
	var path: Array = MapData.lane_path(lane)
	var total := lane_length(lane) * clampf(progress, 0.0, 1.0)
	for index in range(path.size() - 1):
		var a: Vector2 = path[index]
		var b: Vector2 = path[index + 1]
		var segment := a.distance_to(b)
		if total <= segment or index == path.size() - 2:
			var t := 0.0 if segment < 0.0001 else clampf(total / segment, 0.0, 1.0)
			return a.lerp(b, t)
		total -= segment
	return path[path.size() - 1]

static func tower_anchor(lane: String, team: String, tier: String) -> Vector2:
	var from_own_base := float(TOWER_PROGRESS.get(tier, 0.36))
	var progress := from_own_base if team == "blue" else 1.0 - from_own_base
	return point_along_lane(lane, progress)

static func tower_slots() -> Array:
	var slots: Array = []
	for lane in MapData.LANE_ORDER:
		for team in ["blue", "red"]:
			for tier in TOWER_TIERS:
				slots.append({
					"lane": str(lane),
					"team": team,
					"tier": tier,
					"pos": tower_anchor(str(lane), team, tier),
				})
	return slots

# 高地双子塔：守在基地两侧、基地圈之外。蓝方以基地为原点取两个错开的侧位，
# 红方用绕地图中心的 180° 旋转（不是 y=x 镜像 —— 双方基地都在那条对角线上）。
const GUARDIAN_OFFSETS := [
	{"side": "left", "offset": Vector2(-9.0, -6.0)},
	{"side": "right", "offset": Vector2(-6.0, -9.0)},
]

static func guardian_slots() -> Array:
	var slots: Array = []
	for team in ["blue", "red"]:
		var base := MapData.BLUE_BASE if team == "blue" else MapData.RED_BASE
		var flips := 1.0 if team == "blue" else -1.0
		for entry in GUARDIAN_OFFSETS:
			var offset: Vector2 = entry.offset
			slots.append({
				"team": team,
				"side": str(entry.side),
				"tier": "twin",
				"pos": base + offset * flips,
			})
	return slots

# Chaikin 切角平滑：保留首尾航点，但把折线尖角磨圆，兵线行走与地面贴合更自然。
static func smoothed_lane(lane: String, iterations := 2) -> Array:
	var points: Array = MapData.lane_path(lane).duplicate()
	var rounds := clampi(iterations, 1, 2)
	for _round in rounds:
		var next: Array = [points[0]]
		for index in range(points.size() - 1):
			var a: Vector2 = points[index]
			var b: Vector2 = points[index + 1]
			next.append(a.lerp(b, 0.25))
			next.append(a.lerp(b, 0.75))
		next.append(points[points.size() - 1])
		points = next
	return points

static func bush_at(point: Vector2) -> Dictionary:
	return _region_at(point, BUSHES)

static func camp_at(point: Vector2) -> Dictionary:
	return _region_at(point, CAMPS)

static func objective_at(point: Vector2) -> Dictionary:
	return _region_at(point, OBJECTIVE_PITS)

static func _region_at(point: Vector2, regions: Array) -> Dictionary:
	for region in regions:
		if point.distance_to(region.pos) <= float(region.get("radius", 3.0)):
			return region
	return {}

static func distance_to_lanes(point: Vector2) -> float:
	var best := INF
	for lane in MapData.LANE_ORDER:
		var path: Array = MapData.lane_path(lane)
		for index in range(path.size() - 1):
			best = minf(best, point_to_segment_distance(point, path[index], path[index + 1]))
	return best

static func point_to_segment_distance(point: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var length_sq := ab.length_squared()
	if length_sq < 0.0001:
		return point.distance_to(a)
	var t := clampf((point - a).dot(ab) / length_sq, 0.0, 1.0)
	return point.distance_to(a + ab * t)
