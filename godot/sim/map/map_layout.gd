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
# 石壁不是一块等高的墙：低基座 + 岩脊。基座高度在下面 WALL_CORE_HEIGHT，
# 岩脊最高点受 WALL_TOP 约束。机位 21 米、俯角 51°，2.45 米的岩脊
# 已经能读成「石壁」，再高会在英雄贴墙时把脚盖住。

const BUSHES := [
	{"id": "bush_blue_mid", "pos": Vector2(-18.0, -18.0), "radius": 4.2},
	{"id": "bush_red_mid", "pos": Vector2(18.0, 18.0), "radius": 4.2},
	{"id": "bush_blue_jungle", "pos": Vector2(-16.0, -28.0), "radius": 3.8},
	{"id": "bush_red_jungle", "pos": Vector2(28.0, 16.0), "radius": 3.8},
	{"id": "bush_top_river", "pos": Vector2(-30.0, 6.0), "radius": 3.6},
	{"id": "bush_bottom_river", "pos": Vector2(-6.0, 30.0), "radius": 3.6},
	# 外圈补两对：原来 6 丛全挤在河道与中路之间，边路和野区深处蹲不了人。
	# 半径统一 3.4：这几处离石壁/营地都只剩 5~6 米余量，按 3.8 会压进墙体重叠。
	# 位置全部过探针：离兵线 > 9 米、离最近墙体 > 5.5 米、不碰营地/首领坑/传送阵。
	{"id": "bush_top_deep", "pos": Vector2(-38.0, -4.0), "radius": 3.4},
	{"id": "bush_bottom_deep", "pos": Vector2(4.0, 38.0), "radius": 3.4},
	{"id": "bush_top_outer", "pos": Vector2(-36.0, 18.0), "radius": 3.4},
	{"id": "bush_bottom_outer", "pos": Vector2(-18.0, 36.0), "radius": 3.4},
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

# 野区：**每个半场 6 个野点**，对齐王者峡谷的野怪分布。
#
# 上一版只有 4 座 buff 营地：两队各一个红、一个蓝，野区其余位置全是空地。
# 王者峡谷每个半场是「红蓝 BUFF 各一 + 蓝区双狼/蜥蜴 + 红区三猪/红鸟」，
# 小野点负责给打野补经验、也让入侵路线有东西可抢。这里保留这个结构：
#   - 蓝 buff 所在野区（b 与 buff 同侧）配 双狼 + 蜥蜴；
#   - 红 buff 所在野区配 三猪 + 红鸟；
#   - 小野点不带增益，血量和经验都低于 buff 怪，只作为野区节奏点。
#
# 小野点的半径（碰撞/选点）是 1.5，地面阵盘单独用 SMALL_CAMP_DISC_RADIUS；
# buff 营地仍用 CAMP_DISC_RADIUS。所有点位都过了「离墙 / 草丛 / 河道 / 兵线
# 不重叠 + 从泉水走得到」的探针，位置不是按格子摆的。
const SMALL_CAMP_DISC_RADIUS := 2.4

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
	# --- 蓝方半场（a > 0）：上野是蓝区，下野是红区 -------------------------
	{"id": "blue_buff_blue_side", "pos": Vector2(-1.0, -23.0), "buff": "blue", "monster_type": "wolf", "name": "霜狼", "radius": 2.2},
	{"id": "blue_wolf_blue_side", "pos": Vector2(-10.0, -33.7), "monster_type": "wolf", "name": "双狼", "radius": 1.5, "disc_radius": SMALL_CAMP_DISC_RADIUS, "hp": 460.0, "damage": 34.0, "xp": 30.0, "respawn_time": 60.0},
	{"id": "blue_lizard_blue_side", "pos": Vector2(5.9, -27.0), "monster_type": "wolf", "name": "蜥蜴", "radius": 1.5, "disc_radius": SMALL_CAMP_DISC_RADIUS, "hp": 420.0, "damage": 32.0, "xp": 28.0, "respawn_time": 60.0},
	{"id": "red_buff_blue_side", "pos": Vector2(23.0, 1.0), "buff": "red", "monster_type": "wolf", "name": "赤狼", "radius": 2.2},
	{"id": "red_pig_blue_side", "pos": Vector2(27.0, -5.9), "monster_type": "wolf", "name": "三猪", "radius": 1.5, "disc_radius": SMALL_CAMP_DISC_RADIUS, "hp": 500.0, "damage": 36.0, "xp": 32.0, "respawn_time": 60.0},
	{"id": "red_bird_blue_side", "pos": Vector2(35.1, 8.0), "monster_type": "wolf", "name": "红鸟", "radius": 1.5, "disc_radius": SMALL_CAMP_DISC_RADIUS, "hp": 420.0, "damage": 32.0, "xp": 28.0, "respawn_time": 60.0},
	# --- 红方半场（a < 0）：下野是蓝区，上野是红区 -------------------------
	{"id": "blue_buff_red_side", "pos": Vector2(6.0, 27.0), "buff": "blue", "monster_type": "wolf", "name": "霜狼", "radius": 2.2},
	{"id": "blue_wolf_red_side", "pos": Vector2(12.1, 30.5), "monster_type": "wolf", "name": "双狼", "radius": 1.5, "disc_radius": SMALL_CAMP_DISC_RADIUS, "hp": 460.0, "damage": 34.0, "xp": 30.0, "respawn_time": 60.0},
	{"id": "blue_lizard_red_side", "pos": Vector2(-3.0, 37.7), "monster_type": "wolf", "name": "蜥蜴", "radius": 1.5, "disc_radius": SMALL_CAMP_DISC_RADIUS, "hp": 420.0, "damage": 32.0, "xp": 28.0, "respawn_time": 60.0},
	{"id": "red_buff_red_side", "pos": Vector2(-27.0, -6.0), "buff": "red", "monster_type": "wolf", "name": "赤狼", "radius": 2.2},
	{"id": "red_pig_red_side", "pos": Vector2(-35.5, -14.5), "monster_type": "wolf", "name": "三猪", "radius": 1.5, "disc_radius": SMALL_CAMP_DISC_RADIUS, "hp": 500.0, "damage": 36.0, "xp": 32.0, "respawn_time": 60.0},
	{"id": "red_bird_red_side", "pos": Vector2(-43.0, -11.8), "monster_type": "wolf", "name": "红鸟", "radius": 1.5, "disc_radius": SMALL_CAMP_DISC_RADIUS, "hp": 420.0, "damage": 32.0, "xp": 28.0, "respawn_time": 60.0},
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

# 传送阵：两座在地图的两个**空角落**，互为对端；引导期间移动/施法/受击都会打断。
#
# 2026-10-28 第二版（玩家原话：「把这个角落全部铺上，然后将这个传送阵放在最角落里面
# 不需要那个桥」）。第一版把阵压在角落桥桥面正中（±47.66），玩家看过之后要求：
# 角落整块铺石、阵再往里挪、角落桥不要了。
#
# 现在的口径：
#   - 两个空角落各铺一块**角落广场**（见下面的 CORNER_PLAZA_*），广场从 ±40 一直铺到
#     边界墙脚，把上下路的跨河段整段盖住 —— 所以角落桥不再建（中路桥保留）；
#   - 阵心 (∓52, ∓52)：比广场中心更靠角落，是「最角落里面」；
#     可走边界是 |坐标| ≤ 53.65（BOUNDS 58 - 相机边距 3.8 - 英雄半径 0.55），
#     所以阵心四周还有 1.65 米可站，人走得进去、按得下去；
#   - 两座绕地图中心 180°（-p）配对，各自到两个基地的距离完全相等 —— 中立设施。
#
# 玩家视角：蓝方的小地图是整张转 180° 的（见 minimap.oriented），
# 所以东南角那座显示在**左上**、西北角那座显示在**右下** —— 就是需求里的两个角。
# 名字按世界轴取（城墙命名口径：north = -y、east = +x），不按某一队的屏幕方向取，
# 否则换一边看，名字就和位置对不上了。
#
# 历史上的两次错，一并记在这里，免得下次再犯：
#   ① 最初两座在 (∓34, ∓34)，a = x - y = 0，正压河心线，阵盘整个漂在水面上；
#   ② 后来挪到河岸走廊中线 (∓42, ∓24)，两座分处两个半场，但离角落还很远。
# totem 是图腾柱相对阵心的偏移：朝角落里，离阵心 4.2 米（在阵盘 3.0 之外），
# 站在广场上、不立在路面也不立在水里。
const TELEPORT_PADS := [
	{
		"id": "corner_pad_southeast",
		"pos": Vector2(52.0, 52.0),
		"partner": "corner_pad_northwest",
		"name": "东南角传送阵",
		"totem": Vector2(2.97, 2.97),
	},
	{
		"id": "corner_pad_northwest",
		"pos": Vector2(-52.0, -52.0),
		"partner": "corner_pad_southeast",
		"name": "西北角传送阵",
		"totem": Vector2(-2.97, -2.97),
	},
]

# --- 角落广场 ---------------------------------------------------------------
# 两个空角落整块铺石（2026-10-28，玩家：「把这个角落全部铺上……不需要那个桥」）。
#
# 之前那里是「石桥 + 桥外一片水 + 一圈边界乱石」：斜俯视能看见桥与墙之间那个水窟窿。
# 改成整块广场之后角落是一个完整石面，阵放到最角落，角落桥不再建。
#
# 几何口径（两条都被 test_river_and_teleport 钉住）：
#   - INNER = 40：必须**盖住上下路的跨河点**。跨河段沿路 ±(桥长/2)=±6.4 米，
#     最远到 (43.1, 43.1)，40 留出 3 米余量，拆桥之后路面不会悬在水上；
#   - OUTER = 58.6：塞进边界墙基座下面（墙内表面 58.0），墙脚不留缝。
# 两座按**角落符号**取（+1/+1 与 -1/-1），天然绕原点 180° 对称。
const CORNER_PLAZA_INNER := 40.0
const CORNER_PLAZA_OUTER := 58.6
const CORNER_PLAZA_SIGNS := [Vector2(1.0, 1.0), Vector2(-1.0, -1.0)]

static func corner_plazas() -> Array:
	var plazas: Array = []
	for sign_point in CORNER_PLAZA_SIGNS:
		var corner: Vector2 = sign_point
		var near_point := corner * CORNER_PLAZA_INNER
		var far_point := corner * CORNER_PLAZA_OUTER
		plazas.append({
			"corner": corner,
			"min": Vector2(minf(near_point.x, far_point.x), minf(near_point.y, far_point.y)),
			"max": Vector2(maxf(near_point.x, far_point.x), maxf(near_point.y, far_point.y)),
		})
	return plazas

# 点是否落在某块角落广场上（margin > 0 表示向外扩，给布景避让用）。
static func inside_corner_plaza(point: Vector2, margin := 0.0) -> bool:
	for plaza in corner_plazas():
		if point.x >= float(plaza.min.x) - margin and point.x <= float(plaza.max.x) + margin \
				and point.y >= float(plaza.min.y) - margin and point.y <= float(plaza.max.y) + margin:
			return true
	return false

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
# 边界基座的高度。真正的轮廓由上面的岩脊负责，基座只负责封边和进深。
const BOUNDARY_CORE_HEIGHT := 2.0
# --- 石壁范式：砌石基座 + 自然岩脊（2026-10-28）--------------------------
# 旧版是「直方盒墙身 + 外挑压顶 + 等距壁柱」，俯视是一圈规整的城墙/城垛，
# 和王者峡谷的野区石壁（自然岩脊、起伏不定）差得太远。现在改成：
#   - 低矮的砌石基座负责封住碰撞线，砖缝仍在 rock_wall.gdshader 里；
#   - 基座上沿墙铺一条高低错落、左右轻微摆动的 Rock.glb 岩脊，压掉直顶边；
#   - 两端与边界转角用更大的岩体收口，不再有等距壁柱的机械节奏。
# 基座高度必须低于岩脊最低点；岩脊最高点受 WALL_TOP / BOUNDARY_TOP 约束，
# 相机安全边距按这两个值反解，改大要回头验遮挡。
const WALL_CORE_HEIGHT := 1.25
const WALL_ROCK_MIN_HEIGHT := 1.55
const WALL_ROCK_MAX_HEIGHT := 2.45
const WALL_ROCK_SPACING := 1.75
# 野区岩脊只允许「贴着碰撞线长」：玩家最近能站到离墙心 0.8 + 0.55 = 1.35 米，
# 岩块旋转后的 AABB 角点也不能越过这条线，否则会出现人穿进石头。
# Rock.glb 高宽比约 1:0.79，宽度系数超过 0.95 时最高那块的对角半宽就会超标。
const WALL_ROCK_WIDTH_MIN := 0.85
const WALL_ROCK_WIDTH_MAX := 0.95
const WALL_TOP := WALL_ROCK_MAX_HEIGHT
const BOUNDARY_ROCK_MIN_HEIGHT := 2.65
const BOUNDARY_ROCK_MAX_HEIGHT := 3.7
const BOUNDARY_ROCK_SPACING := 4.0
const BOUNDARY_ROCK_WIDTH_MIN := 1.5
const BOUNDARY_ROCK_WIDTH_MAX := 1.7
# 边界岩脊可以往可玩区探一点：玩家最近只能走到 BOUNDS - 相机边距 = 54.2 米，
# 岩体前缘留在 54.3 米以外，既能看到凹凸岩壁，又不会穿进英雄身体。
# 上限 0.8 是按「最大岩块旋转后的对角半宽」反解的，别只按正面宽度算。
const BOUNDARY_ROCK_INTRUDE := 0.8
const BOUNDARY_ROCK_OUTWARD := 0.5
const BOUNDARY_TOP := BOUNDARY_ROCK_MAX_HEIGHT

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
		if point.distance_to(camp.pos) < float(camp.get("disc_radius", CAMP_DISC_RADIUS)) + margin:
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
# 那个位置的路面必须落在石面上，否则就是一块悬在水面的板子。
# 2026-10-28 起这两个跨河点由**角落广场**整块盖住（角落桥已拆，中路桥保留），
# 所以现在这里同时是两个用途：广场的定位依据 + 测试量「跨河点有没有被石面盖住」。
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
