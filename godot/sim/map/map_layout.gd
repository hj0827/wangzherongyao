extends RefCounted

# 地图布局的唯一数据源。模拟层、战场表现、小地图与情报面板都必须从这里取点，
# 避免「地面画了一套墙、碰撞用了另一套」的错位。
#
# 坐标沿用 map_data.gd（已整体顺时针旋转 90°）：蓝方基地 (46,-46)，红方基地 (-46,46)，
# 河道沿 y = x。上下路关于 y = -x 镜像，因此所有墙体/草丛/营地/首领坑都成对定义。

const MapData = preload("res://sim/map_data.gd")

const TOWER_TIERS := ["outer", "inner", "high"]
const TOWER_RANKS := {"outer": 0, "inner": 1, "high": 2}
const TOWER_LABELS := {"outer": "外塔", "inner": "内塔", "high": "高地塔"}
# 从己方基地沿兵线量起的推进比例。外塔靠近中线，高地塔守在基地门前。
const TOWER_PROGRESS := {"outer": 0.36, "inner": 0.24, "high": 0.18}
const WALL_THICKNESS := 1.6
# 野区墙体高度。1.7 米在 51° 俯视下只剩一条石坎，读不出「这是石壁」；
# 再高就会在英雄贴墙时把自己的脚盖住（机位 21 米、俯角 51°，2.2 米是上限附近的值）。
const WALL_HEIGHT := 2.2

const BUSHES := [
	{"id": "bush_blue_mid", "pos": Vector2(-18.0, -18.0), "radius": 4.2},
	{"id": "bush_red_mid", "pos": Vector2(18.0, 18.0), "radius": 4.2},
	{"id": "bush_blue_jungle", "pos": Vector2(-16.0, -28.0), "radius": 3.8},
	{"id": "bush_red_jungle", "pos": Vector2(28.0, 16.0), "radius": 3.8},
	{"id": "bush_top_river", "pos": Vector2(-30.0, 6.0), "radius": 3.6},
	{"id": "bush_bottom_river", "pos": Vector2(-6.0, 30.0), "radius": 3.6},
]

# 野区墙体（2026-10-25 重做）。
#
# 坐标用两个量描述最省事：a = x - y（垂直河道，蓝方正）、b = x + y（沿河道，也是离中路多远）。
# - a = 0 是河道中心线；a > 0 在蓝方半场，a < 0 在红方半场。
# - b = 0 是中路中心线；b < 0 是上野，b > 0 是下野。
#
# 两类墙分工：
# 1. 中路走廊墙（b 恒定）：贴着中路两侧各一条，中间留 9 米以上净宽。这是「中路是有墙的走廊」
#    这件事唯一说得清的地方，也是最像 MOBA 野区的那一眼。
# 2. 河道岸壁（a 恒定）：河两岸各有两段，把 buff 营地兜成半封闭的窝，逼迫从窄口绕进来。
#
# 全部关于 y = -x 成对定义（mirror(p) = (-p.y, -p.x)）：
# 蓝上 ↔ 蓝下、红上 ↔ 红下。test_jungle_walls 会校验每一段都有孪生兄弟。
#
# 避让是硬约束，不是审美：小兵沿折线直走 + 滑墙、不寻路，墙压进路面就是永久堵车；
# 墙盖住营地/草丛/首领坑就是把那里变成不可进入的石头堆。
const WALLS := [
	# --- 中路走廊（b = ∓13，离路中心 9.2 米）---------------------------------
	{"id": "wall_blue_mid_corridor_top", "a": Vector2(2.5, -15.5), "b": Vector2(14.5, -27.5)},
	{"id": "wall_blue_mid_corridor_bottom", "a": Vector2(15.5, -2.5), "b": Vector2(27.5, -14.5)},
	# --- 蓝方深野区：与原有墙平行的第二道（b = -37），夹出一条 4 米净宽的走廊 ---
	{"id": "wall_blue_deep_top", "a": Vector2(-7.5, -29.5), "b": Vector2(-1.5, -35.5)},
	{"id": "wall_blue_deep_bottom", "a": Vector2(29.5, 7.5), "b": Vector2(35.5, 1.5)},
	# --- 蓝 buff 坑围墙（a = 18：营地就在河岸边，只能往里让出一个身位）---------
	{"id": "wall_blue_buff_ring_top", "a": Vector2(-5.0, -23.0), "b": Vector2(-11.0, -29.0)},
	{"id": "wall_blue_buff_ring_bottom", "a": Vector2(23.0, 5.0), "b": Vector2(29.0, 11.0)},
	# --- 红方野区：两个 buff 营地都紧贴中路（b = ∓16），放不下整条中廊墙，
	# 改成围营地的一对平行短墙（b = ∓11 / ∓21），开口朝河道与基地两侧。-----------
	{"id": "wall_red_upper_ring_mid_side", "a": Vector2(-14.5, 3.5), "b": Vector2(-20.5, 9.5)},
	{"id": "wall_red_upper_ring_river_side", "a": Vector2(-19.5, -1.5), "b": Vector2(-25.5, 4.5)},
	{"id": "wall_red_lower_ring_mid_side", "a": Vector2(-3.5, 14.5), "b": Vector2(-9.5, 20.5)},
	{"id": "wall_red_lower_ring_river_side", "a": Vector2(1.5, 19.5), "b": Vector2(-4.5, 25.5)},
	# --- 野区深处的隔断（原有 4 段，保留）------------------------------------
	{"id": "wall_top_west", "a": Vector2(8.0, -36.0), "b": Vector2(-4.0, -26.0)},
	{"id": "wall_bottom_west", "a": Vector2(36.0, -8.0), "b": Vector2(26.0, 4.0)},
	{"id": "wall_top_east", "a": Vector2(-20.0, -8.0), "b": Vector2(-28.0, 2.0)},
	{"id": "wall_bottom_east", "a": Vector2(8.0, 20.0), "b": Vector2(-2.0, 28.0)},
]

# 四座营地：**每个半场各一个红、一个蓝**。
#
# 上一版全部用 `mirror()`（轴 = 中路 y = -x）配对，而 mirror **保持 a 不变**
# —— a = x - y 是「离河道多远」，也就是「在哪一队的半场」。于是镜像出来的营地
# 跟原营地同队：蓝方半场两个都是蓝 buff、红方半场两个都是红 buff，
# 任何一队在自己野区里永远见不到另一种增益。首领坑犯的是同一个错，
# 暴君与主宰双双落在蓝方半场，红方野区一个首领都没有。
#
# 现在改成「每半场各一套」，红方那两座是蓝方的 180° 近似点对称（容差 8 米）。
# 为什么只是"近似"：两半场的石壁形状本来就不是同一个图形 ——
# 红方野区的墙贴着中路（a ≈ -18 ~ -30），蓝方的墙在野区深处（a ≈ +18 ~ +44）。
# 硬要精确旋转，红方那座就会正好压在石壁上（实测被压 1.6 米）。
# 精确旋转是以后重做红方野区地形时才该做的事，不是靠挪野怪能凑出来的。
#
# 位置口径（全部用 a / b 想，别用裸 x,y）：
# - a = x - y：离河道中心线 |a| * 0.7071 米。地面法阵圆盘半径 3.4，
#   所以 |a| >= 17.5 才能保证整块圆盘在水面之外。
# - b = x + y：离中路中心线 |b| * 0.7071 米。
# 所有点位都过了三关才落笔：离石壁 ≥ 1 米（墙有碰撞）、从泉水走得到（网格 BFS）、
# 和别的营地 / 首领坑 / 传送阵互不重叠。探针 tools/probe_camp_sites.gd 会把这些数打出来。
# --- 地面圆盘（法阵）半径 -------------------------------------------------
# 这三块圆盘画在地上，同时被「随机布景避让」和「选点探针」当成占位面积。
# 以前渲染层写 3.4 / 5.6 / 3.0、探针里再抄一遍、避让清单里干脆漏掉传送阵 ——
# 于是树长到了阵盘上。现在只有一个来源，三处都读这里。
const CAMP_DISC_RADIUS := 3.4
const PIT_DISC_RADIUS := 5.6
const PAD_DISC_RADIUS := 3.0
# 阵盘之外还要留一圈**树冠**空间。只按阵盘半径避让只能挡住树干：
# 树冠水平半径 2~3.5 米，树干站在盘边 1 米外，树冠照样把整个阵盖住
# （截图里阵盘正中就长着一棵树，俯视看还以为是阵眼）。
const PAD_CANOPY_CLEARANCE := 3.0

const CAMPS := [
	# 蓝方半场：蓝 buff 在上野（b<0），红 buff 在下野（b>0）。
	{"id": "blue_buff_blue_side", "pos": Vector2(-1.0, -23.0), "buff": "blue", "monster_type": "wolf", "name": "霜狼", "radius": 2.2},
	{"id": "red_buff_blue_side", "pos": Vector2(23.0, 1.0), "buff": "red", "monster_type": "wolf", "name": "赤狼", "radius": 2.2},
	# 红方半场：同样一个蓝（上野）一个红（下野）。
	{"id": "blue_buff_red_side", "pos": Vector2(6.0, 27.0), "buff": "blue", "monster_type": "wolf", "name": "霜狼", "radius": 2.2},
	{"id": "red_buff_red_side", "pos": Vector2(-27.0, -6.0), "buff": "red", "monster_type": "wolf", "name": "赤狼", "radius": 2.2},
]

# 两个首领坑分处两个半场，并且是精确的 180° 点对称（(-17,-39) ↔ (17,39)）。
# 坑盘半径 5.6（arena._add_map_disc），|a| = 22 → 离河心 15.56 米，
# 减水面 9 米还剩 6.56，圆盘外缘离水 0.96 米；离兵线路面也还有 4 米以上。
# 旧值 |a| = 14 时盘子有 1.9 米泡在河里，而且两座都在蓝方半场。
const OBJECTIVE_PITS := [
	{"id": "tyrant", "pos": Vector2(-17.0, -39.0), "name": "暴君", "monster_type": "orc", "radius": 2.8},
	{"id": "overlord", "pos": Vector2(17.0, 39.0), "name": "主宰", "monster_type": "orc", "radius": 2.8},
]

# 河道之灵：沿河道成对刷新，击杀后为全队提供一段河道视野。
const RIVER_SPIRITS := [
	{"id": "river_spirit_north", "pos": Vector2(-30.0, -30.0), "name": "河道之灵"},
	{"id": "river_spirit_south", "pos": Vector2(30.0, 30.0), "name": "河道之灵"},
]

# 传送阵：河道两岸各一座，互为对端；引导期间移动/施法/受击都会打断。
#
# 2026-10-25 挪位：原来两座都在 (∓34, ∓34)，a = x - y = 0 —— 正压河心线，
# 阵盘整个漂在水面上，中间还插一根图腾柱。水面能走，功能没坏，
# 但俯视图上就是「两块浮在水里的塑料盘子」，而且是全图最显眼的两块。
#
# 现在整盘落在**河岸**上（盘半径 3.0，离水面 0.73 米、离兵线路缘 1.25 米，
# 正好卡在水面与边路之间那条走廊的中线上 —— 探针 tools/probe_pad_sites.gd 量的）。
# 两座用**绕地图中心 180°**（-p）配对，一队一座；用 mirror 配对会让两座
# 都落在蓝方河岸（mirror 保持 a 不变），那和营地当初的错是同一个。
const TELEPORT_PADS := [
	{"id": "river_pad_north", "pos": Vector2(-42.0, -24.0), "partner": "river_pad_south", "name": "北路传送阵"},
	{"id": "river_pad_south", "pos": Vector2(42.0, 24.0), "partner": "river_pad_north", "name": "南路传送阵"},
]

# --- 边界城墙 -------------------------------------------------------------
# 模拟层用 collision.clamp_bounds 兜底（走到 ±(BOUNDS - radius) 就停），
# 但那是一堵**看不见的**墙：玩家看到草地一直延伸到远处山坡，撞上去才知道走不动。
# 这里给出一圈看得见的石墙，内表面正好贴在可走边界外侧，
# 于是「看到的墙」和「走不过去的线」是同一条。
const BOUNDARY_CENTER := 58.9      # 墙心线到地图中心的距离
# 墙厚 1.8（原 1.0）。1 米厚在 51° 俯视下只剩一条石板边，读起来是「围栏」；
# 加厚到 1.8 之后墙顶才有一条能看出进深的平台，立面才有重量。
# 内表面仍然正好贴在 MapData.BOUNDS 上：58.9 - 1.8/2 = 58.0。
const BOUNDARY_THICK := 1.8
# 高度取 3.4：相机是 21m 高、约 51° 俯视，2.2m 的墙在屏幕上只剩一条矮石坎，
# 读不出"这是墙"。3.4m 大约两个身位，立面才立得起来。
const BOUNDARY_HEIGHT := 3.4
# --- 城墙范式：压顶石 + 壁柱（2026-10-25 第三次改）------------------------
# 演进史，别再走回头路：
#   ① 每 9 米一根 5.2 米方柱 + 石帽 → 俯视是一圈**城垛**；
#   ② 墙顶撒参差岩脊 → 那是「塌方」的语言，而参考图是一道**砌筑**的城墙；
#   ③ 现在是砌石城墙的三件套：墙面砖缝（在 rock_wall.gdshader 里铺）、
#      **外挑**的压顶石、等距的**壁柱 + 柱帽**（柱帽越出压顶一条起伏线）。
# 砖缝在 shader 里，不需要额外网格；这里只给壁柱与压顶的尺寸。
#
# 壁柱间距 3.6 米是「20 米机位下每屏 5~6 根」算出来的：小于 2.6 米读成一排齿，
# 大于 5 米一段墙只剩一根，就没有节奏了。
const WALL_BUTTRESS_SPACING := 3.6
const WALL_BUTTRESS_WIDTH := 0.92      # 沿墙方向的宽度
const WALL_BUTTRESS_DEPTH := 0.36      # 每侧外挑出墙面的厚度（两侧对称，四面都看得见）
const WALL_BUTTRESS_RISE := 0.24       # 柱身高出墙顶多少
const WALL_BUTTRESS_CAP := 0.20        # 柱帽厚度
const WALL_BUTTRESS_CAP_SLACK := 0.10  # 柱帽比柱身宽出多少（每侧）
const WALL_COPING_OVERHANG := 0.16     # 压顶石每侧外挑
const WALL_COPING_THICK := 0.22
# 最高部件 = 墙顶 + 柱帽上沿。相机安全边距按这个数反解，改大要回头验遮挡。
const WALL_TOP := WALL_HEIGHT + WALL_BUTTRESS_RISE + WALL_BUTTRESS_CAP
const BOUNDARY_COPING_OVERHANG := 0.18
const BOUNDARY_BUTTRESS_SPACING := 4.2
const BOUNDARY_TOP := BOUNDARY_HEIGHT + WALL_BUTTRESS_RISE + WALL_BUTTRESS_CAP

# 四面墙首尾相连围成闭合方框（端点用 BOUNDARY_CENTER，四角落在一起）。
static func boundary_walls() -> Array:
	var c := BOUNDARY_CENTER
	return [
		{"id": "boundary_north", "a": Vector2(-c, -c), "b": Vector2(c, -c)},
		{"id": "boundary_south", "a": Vector2(-c, c), "b": Vector2(c, c)},
		{"id": "boundary_west", "a": Vector2(-c, -c), "b": Vector2(-c, c)},
		{"id": "boundary_east", "a": Vector2(c, -c), "b": Vector2(c, c)},
	]

# 墙的内表面：玩家能走到这里为止，再往前就是墙。
static func boundary_inner() -> float:
	return BOUNDARY_CENTER - BOUNDARY_THICK * 0.5

# 某个点是否贴着边界墙（供随机布景避让）。
static func near_boundary(point: Vector2, margin := 2.5) -> bool:
	var limit := BOUNDARY_CENTER - BOUNDARY_THICK * 0.5 - margin
	return absf(point.x) >= limit or absf(point.y) >= limit

# 三块贴地圆盘（营地 / 首领坑 / 传送阵）的占位判定，**只此一份**。
#
# 以前渲染层手抄了一遍避让清单、草丛那边干脆没抄：结果是树避开了、
# 草从盘面里长出来，绿点直接冒在石盘上。占位面积只有一份来源，
# 随机布景（按树干算）与地表草丛（按草根算）都读这里。
# 传送阵还要多算 PAD_CANOPY_CLEARANCE：树干避开不等于树冠避开。
static func on_ground_mark(point: Vector2, margin := 0.0) -> bool:
	for camp in CAMPS:
		if point.distance_to(camp.pos) < CAMP_DISC_RADIUS + margin:
			return true
	for pit in OBJECTIVE_PITS:
		if point.distance_to(pit.pos) < PIT_DISC_RADIUS + margin:
			return true
	for pad in TELEPORT_PADS:
		if point.distance_to(pad.pos) < PAD_DISC_RADIUS + PAD_CANOPY_CLEARANCE + margin:
			return true
	return false

# --- 墙端露头 -------------------------------------------------------------
# 墙体是逐段独立的 BoxMesh，端面就是盒子的一个面：一段墙看起来像被刀切过。
# 想靠「转角」收口也不成立 —— 实测相邻两段墙的端点根本不接（最近也有 3 米），
# 那是留给玩家钻的缺口，不是接缝。
# 王者的野区石壁是「山体在两端露头」，所以这里给每个墙端算一个露头位置，
# 由渲染层压一块高过墙顶的岩体，把平整端面吞进石头里。
#
# 半径**不拍固定值**：兵线贴着墙走的地方，固定尺寸必然伸进路面，
# 而小兵不寻路，蹭到就是一整条兵线卡死。所以这里是「还剩多少空间就用多少」。
const END_MIN_RADIUS := 0.85        # 小于这个数就别放石头：压不住截面，只是块碍事的碎石
# 上限 1.15：1.9 米半径在画面上是一块 3.8 米宽的巨板（墙厚两倍多），
# 读起来是「墙边放了块水泥预制板」，反而比平整端面更假。
const END_MAX_RADIUS := 1.15
const END_LANE_MARGIN := 0.2        # 石面离兵线路面至少留这么多
const END_AREA_MARGIN := 0.15       # 石面离营地 / 首领坑 / 传送阵边缘至少留这么多

# 返回 [{"id", "wall", "end", "pos", "outward", "radius"}, ...]，一段墙两个端头。
static func wall_ends() -> Array:
	var ends: Array = []
	for wall in WALLS:
		var a: Vector2 = wall.a
		var b: Vector2 = wall.b
		var axis := (b - a).normalized()
		ends.append({
			"id": "%s:a" % str(wall.id),
			"wall": str(wall.id),
			"end": "a",
			"pos": a,
			"outward": -axis,
			"radius": wall_end_radius(a),
		})
		ends.append({
			"id": "%s:b" % str(wall.id),
			"wall": str(wall.id),
			"end": "b",
			"pos": b,
			"outward": axis,
			"radius": wall_end_radius(b),
		})
	return ends

# 这个位置最大能放多大的石头：取「离最近的兵线路面 / 营地 / 首领坑 / 传送阵还剩多少」。
static func wall_end_radius(point: Vector2) -> float:
	var radius := END_MAX_RADIUS
	radius = minf(radius, distance_to_lanes(point) - MapData.LANE_HALF_WIDTH - END_LANE_MARGIN)
	for camp in CAMPS:
		radius = minf(radius, point.distance_to(camp.pos) - float(camp.get("radius", 3.0)) - END_AREA_MARGIN)
	for pit in OBJECTIVE_PITS:
		radius = minf(radius, point.distance_to(pit.pos) - float(pit.get("radius", 4.0)) - END_AREA_MARGIN)
	# 传送阵没有统一半径字段，沿用阵盘那条判定。
	for pad in TELEPORT_PADS:
		radius = minf(radius, point.distance_to(pad.pos) - PAD_DISC_RADIUS - END_AREA_MARGIN)
	# 向下取整到 5 厘米：贴着兵线的墙端算出来的余量是**正好**卡在边界上的
	# （5.762 - 3.75 - 0.2 = 1.812），不取整就永远和余量打平，浮点误差会来回翻。
	return floorf(radius / 0.05) * 0.05

# 边路与河心线（y = x）的交点。
#
# 河道一直通到地图两端，而贴边的 L 形边路拐角必然压在河心线上 ——
# 那个位置需要一座桥，否则路面就是一块悬在水面上的板子。
# 渲染层按这个结果摆桥，测试按同一个结果验「桥真的压在跨河点上」。
static func lane_river_crossings() -> Array:
	var crossings: Array = []
	for lane in ["top", "bottom"]:
		var path: Array = MapData.lane_path(lane)
		for index in range(path.size() - 1):
			var a: Vector2 = path[index]
			var b: Vector2 = path[index + 1]
			# 到河心线的有符号距离只差一个常数因子，用 (x - y) 就够判断在哪一侧。
			var da := a.x - a.y
			var db := b.x - b.y
			if da * db > 0.0:
				continue
			var t := 0.0
			if not is_equal_approx(da, db):
				t = da / (da - db)
			crossings.append({
				"lane": lane,
				"pos": a.lerp(b, clampf(t, 0.0, 1.0)),
				"tangent": (b - a).normalized(),
			})
			break
	return crossings

# 关于 y = -x 的镜像（旋转 90° 后新的对称轴）。
# 注意：这不是「交换 x/y」—— 那条是旧对称轴，用在新地图上会把上下路映射错。
static func mirror(point: Vector2) -> Vector2:
	return Vector2(-point.y, -point.x)
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

# 高地双子塔：守在基地朝战场的一侧，一左一右夹住中路。
#
# 以前用的是固定 (x, y) 偏移 —— 两座塔一起落在基地**背离战场**的墙角（泉水背后）。
# 敌人从地图中心方向推上高地时，塔不在防线上；玩家在基地里看过去，也是「塔缩在水晶后面」。
# 改成沿「基地 → 地图中心」这个轴摆位：前出 GUARDIAN_FORWARD，左右各 GUARDIAN_SPREAD。
# 双方基地在同一条对角线上，各自取自己的 toward，天然是绕地图中心的 180° 对称。
const GUARDIAN_FORWARD := 12.0
const GUARDIAN_SPREAD := 5.0
const GUARDIAN_SIDES := [{"side": "left", "sign": 1.0}, {"side": "right", "sign": -1.0}]

static func guardian_slots() -> Array:
	var slots: Array = []
	for team in ["blue", "red"]:
		var base := MapData.BLUE_BASE if team == "blue" else MapData.RED_BASE
		var toward := (Vector2.ZERO - base).normalized()
		var side := Vector2(-toward.y, toward.x)
		for entry in GUARDIAN_SIDES:
			slots.append({
				"team": team,
				"side": str(entry.side),
				"tier": "twin",
				"pos": base + toward * GUARDIAN_FORWARD + side * GUARDIAN_SPREAD * float(entry.sign),
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
