extends RefCounted

# 地图几何查询。C17 拆分第一步：从 arena.gd 抽出"给定点返回距离/布尔"的纯计算，
# 不建节点、不碰材质，所以建图流程与测试都能直接调用。
#
# 这些函数原来散在 arena.gd（6400 行）里，与建 mesh 的代码混在一起，
# 想验证"某个点该不该长草"只能把整个 Arena 实例化。抽出来之后是纯函数，逐位等价。

const MapData = preload("res://sim/map_data.gd")
const MapIntel = preload("res://sim/map_intel.gd")
const MapLayout = preload("res://sim/map/map_layout.gd")
const MapView = preload("res://scripts/game/map_view.gd")

# 布景取地形高度。地形是可玩区外才抬升的，所以可玩区里恒为 0，
# 布景摆放不会因为地形改动而漂移。
static func terrain_height(x: float, z: float, terrain) -> float:
	if terrain == null:
		return 0.0
	return float(terrain.height_at(x, z))

# 只长在草地上：路面、河道、基地广场和草丛（玩法区域）都要排除，
# 否则会出现「草长在路中间」「草盖住草丛」这种一眼假的情况。
static func can_grow_grass(point: Vector2, noise: FastNoiseLite, bushes: Array) -> bool:
	if noise.get_noise_2d(point.x, point.y) < -0.18:
		return false
	if lane_distance(point) < 4.6:
		return false
	if river_distance(point) < 12.5:
		return false
	if base_distance(point) < 11.5:
		return false
	# 地表草也要避开贴地圆盘：草丛是按草根撒的，草根长在石盘上就是
	# 「绿点从法阵里冒出来」。留 0.3 米让草丛边缘自然收口，不要一圈秃边。
	if MapLayout.on_ground_mark(point, 0.3):
		return false
	for bush in bushes:
		# 留在草丛外沿 0.45m 处的草可以长进来，让叶簇和地表草自然衔接；
		# 全部排除会留出一圈生硬的秃边。
		if point.distance_to(bush.pos) < float(bush.radius) - 0.45:
			return false
	return true

static func lane_distance(point: Vector2) -> float:
	# 最近兵线距离只有 MapIntel 一份实现：以前这里手抄过一遍同样的折线投影，
	# 两边改路径时必然会漂移，植被就会长进路面或远离路面。
	return float(MapIntel.nearest_lane(point).get("distance", INF))

static func base_distance(point: Vector2) -> float:
	return minf(point.distance_to(MapData.BLUE_BASE), point.distance_to(MapData.RED_BASE))

static func river_distance(point: Vector2) -> float:
	# 与 TerrainBuilder.river_distance / MapIntel 同源：河道中心线是 x - y = 0。
	return absf(point.x - point.y) * 0.70710678

# 墙体/草丛/营地/首领坑/传送阵/角落广场/边界墙周围留白，避免随机植被长进可交互区域。
static func feature_clear(point: Vector2, margin: float) -> bool:
	if MapLayout.near_boundary(point, 2.5 + margin):
		return false
	# 角落广场是整块石面：树长在石板上比长在阵盘上更离谱。
	# 广场外沿本来就吃掉了边界留白，这里按内沿外扩 margin 判。
	if MapLayout.inside_corner_plaza(point, margin):
		return false
	var marks := MapView.map_marks()
	for wall in marks.walls:
		if segment_distance(point, wall.a, wall.b) < 1.5 + margin:
			return false
	for bush in marks.bushes:
		if point.distance_to(bush.pos) < float(bush.radius) + margin:
			return false
	# 贴地圆盘（营地 / 首领坑 / 传送阵）的占位只有 MapLayout.on_ground_mark 一份。
	# 曾经在这里手抄过一遍半径，传送阵是后加的、清单没跟上，树就长到了阵盘正中。
	if MapLayout.on_ground_mark(point, margin):
		return false
	return true

static func segment_distance(point: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var length_sq := ab.length_squared()
	if length_sq < 0.0001:
		return point.distance_to(a)
	var t := clampf((point - a).dot(ab) / length_sq, 0.0, 1.0)
	return point.distance_to(a + ab * t)
