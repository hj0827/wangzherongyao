extends RefCounted
class_name TowerVisual

# 防御塔的 3D 模型（纯程序化）。
#
# 参考图：王者荣耀的塔 —— 米黄石雕、外扩的花瓣裙摆、竖棱收分的塔柱、
# 笼状塔冠里一颗发光核心，塔脚一圈暖色光池。
# 旧实现是直接 load 一个贴图瞭望塔 glb，和程序化地形不是一套材质，
# 而且塔身粗、形状平。这里用 SurfaceTool 拼出石构件：
#   1. 石料全部走**一个**网格 + 顶点色 —— 一座塔只占一个不透明 draw call；
#   2. 光效（核心 / 光池 / 花瓣）单独拆出来，方便每帧只改颜色，不重建网格；
#   3. 光池和花瓣不放进 model，避免撑大 AABB 破坏「细高不挡英雄」的契约。

const CORE_HEIGHT := 8.2
const TOP_HEIGHT := 8.95
const GROUND_GLOW_Y := 0.07

const BASE_RADIUS := 1.34
const SHAFT_BOTTOM_RADIUS := 0.86
const SHAFT_TOP_RADIUS := 0.49
const SHAFT_TOP_Y := 6.52

const PETAL_COUNT := 8
const FLOATING_PETAL_COUNT := 6

const STONE_LIGHT := Color(0.74, 0.65, 0.50)
const STONE_MID := Color(0.57, 0.48, 0.35)
const STONE_SHADOW := Color(0.32, 0.26, 0.19)
const TRIM := Color(0.66, 0.48, 0.22)

const GLOW_SHADER := preload("res://shaders/tower_glow.gdshader")

## 残破表现的起点：血量低于这个比例才开始变暗 / 露裂纹。
## 0.55 与 sim 里「坦克 AI 在 55% 血才开盾」是同一个量级，玩家对「半血」有共同直觉；
## 太早（0.8）会让每座塔常年带伤，太晚（0.3）就来不及读，塔已经没了。
const DAMAGE_THRESHOLD := 0.55

## 分级造型表：塔的层级不能只靠缩放区分（1.00 / 1.07 / 1.16 在 21m 机位下几乎看不出来）。
## 三个可读信号逐级升级：塔冠石肋数（剪影密度）、肋顶宝珠（点状高光）、石箍圈数（横向节奏）。
## 双子塔是「矮而敦」的另一种塔，所以肋数反而少于外塔 —— 它是不同的塔，不是更弱的塔。
const TIER_STYLES := {
	"outer": {"ribs": 6, "finials": 0, "bands": [2.35, 4.05, 5.45], "crown_ring": false},
	"inner": {"ribs": 7, "finials": 3, "bands": [2.20, 3.60, 5.00, 6.00], "crown_ring": false},
	"high": {"ribs": 8, "finials": 6, "bands": [2.10, 3.20, 4.30, 5.40, 6.20], "crown_ring": true},
	"twin": {"ribs": 5, "finials": 2, "bands": [2.50, 4.20], "crown_ring": false},
}

## 未知层级一律回落成外塔：宁可造一座普通的塔，也不要造一座畸形塔。
static func tier_style(tier: String) -> Dictionary:
	return (TIER_STYLES.get(tier, TIER_STYLES["outer"]) as Dictionary).duplicate(true)

## 血量比例 → 残破强度（0 = 完好，1 = 见底）。阈值以上恒为 0，以下单调上升。
## 抽成纯函数是为了能在 headless 里断言「单调」「阈值」，而不是靠截图目测。
static func damage_tone(ratio: float) -> float:
	var r := clampf(ratio, 0.0, 1.0)
	if r >= DAMAGE_THRESHOLD:
		return 0.0
	return clampf(1.0 - r / DAMAGE_THRESHOLD, 0.0, 1.0)

## 开火包络：0 → 1，1 → 0，先急后缓。塔开火只有 0.18 秒光束，
## 塔身自己的反应必须同样短促，否则会读成「塔一直在发光」。
static func fire_envelope(elapsed: float) -> float:
	var t := clampf(elapsed, 0.0, 1.0)
	var fade := 1.0 - t
	return fade * fade

static func build(team_color: Color, tier := "outer") -> Dictionary:
	var style := tier_style(tier)
	var node := Node3D.new()
	node.name = "TowerStone"

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_add_plinth(st)
	_add_shaft(st)
	_add_shaft_bands(st, style.get("bands", []))
	_add_skirt(st)
	_add_collar(st)
	_add_crown(st, style)
	var stone := MeshInstance3D.new()
	stone.name = "Stone"
	stone.mesh = st.commit()
	var stone_mat := StandardMaterial3D.new()
	stone_mat.vertex_color_use_as_albedo = true
	stone_mat.albedo_color = Color.WHITE
	stone_mat.roughness = 0.86
	stone_mat.metallic_specular = 0.3
	# 花瓣和塔冠是单面片，双面渲染才不会有「半片花瓣消失」。
	stone_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	stone.material_override = stone_mat
	node.add_child(stone)

	var core := _make_core(team_color)
	node.add_child(core)
	var halo := _make_halo(team_color)
	node.add_child(halo)

	var glow := _make_ground_glow(team_color)
	var petals := _make_floating_petals()

	return {
		"node": node,
		"tier": tier,
		"style": style,
		"core": core,
		"halo": halo,
		"glow": glow,
		"petals": petals,
		"height": TOP_HEIGHT,
		"base_width": BASE_RADIUS * 2.0,
		"stone_material": stone_mat,
	}

# ---------- 石构件 ----------

static func _add_plinth(st: SurfaceTool) -> void:
	# 两阶梯石台：底层外扩，上层收回来承托裙摆。
	var profile := [
		Vector2(0.0, 0.0), Vector2(1.34, 0.0), Vector2(1.38, 0.09),
		Vector2(1.24, 0.26), Vector2(1.06, 0.34), Vector2(1.06, 0.46),
		Vector2(0.0, 0.46),
	]
	var colors := [STONE_SHADOW, STONE_SHADOW, STONE_MID, STONE_LIGHT, STONE_LIGHT, STONE_MID, STONE_MID]
	_revolve(st, profile, colors, 28)

static func _add_shaft(st: SurfaceTool) -> void:
	# 向上收分的塔柱 + 12 道竖棱。棱槽用顶点色压暗，读成凿出来的石槽。
	var rings := 10
	var profile: Array = []
	var colors: Array = []
	for i in rings + 1:
		var t := float(i) / float(rings)
		var y := lerpf(0.42, SHAFT_TOP_Y, t)
		var radius := _shaft_radius(t)
		profile.append(Vector2(radius, y))
		var shade := 0.10 + 0.34 * smoothstep(0.0, 1.0, absf(t - 0.42) * 1.6)
		colors.append(STONE_LIGHT.lerp(STONE_MID, shade))
	# 12 道棱至少每道 3 个分段，否则棱槽会被顶点插值抹平。
	_revolve(st, profile, colors, 36, 12, 0.045)

static func _shaft_radius(t: float) -> float:
	return lerpf(SHAFT_BOTTOM_RADIUS, SHAFT_TOP_RADIUS, pow(clampf(t, 0.0, 1.0), 0.62))

static func _add_shaft_bands(st: SurfaceTool, bands: Array) -> void:
	# 一道道石箍把长柱分段，读起来像砌起来的石构件，而不是一根白柱子。
	# 圈数与位置由分级造型表给（越高地越密），所以这里只负责"把给定的高度画成箍"。
	for value in bands:
		var y := float(value)
		var t := (y - 0.42) / (SHAFT_TOP_Y - 0.42)
		var radius := _shaft_radius(t) + 0.05
		var profile := [
			Vector2(0.0, y - 0.11), Vector2(radius + 0.06, y - 0.05),
			Vector2(radius + 0.06, y + 0.05), Vector2(radius - 0.02, y + 0.10),
			Vector2(0.0, y + 0.10),
		]
		var colors := [STONE_SHADOW, STONE_MID, STONE_LIGHT, STONE_MID, STONE_SHADOW]
		_revolve(st, profile, colors, 24)

static func _add_skirt(st: SurfaceTool) -> void:
	# 两层花瓣裙摆：外层大瓣从石台铺到塔柱，内层小瓣错半个角度补缝。
	# 相邻花瓣换一个明度，边界才看得出是「一片一片」而不是一根喇叭口。
	for i in PETAL_COUNT:
		var tone := STONE_LIGHT if i % 2 == 0 else STONE_LIGHT.lerp(STONE_MID, 0.45)
		_add_petal(st, TAU * float(i) / PETAL_COUNT, 1.30, 0.72, 2.30, 0.42, tone, STONE_SHADOW)
	for i in PETAL_COUNT:
		_add_petal(st, TAU * (float(i) + 0.5) / PETAL_COUNT, 1.04, 0.64, 1.68, 0.30, STONE_MID.lerp(STONE_SHADOW, 0.25), STONE_SHADOW)

static func _add_petal(st: SurfaceTool, angle: float, base_r: float, tip_r: float, top_y: float, span: float, light: Color, dark: Color) -> void:
	var cols := 3
	var rows := 4
	var grid: Array = []
	var color_grid: Array = []
	for row in rows + 1:
		var v := float(row) / float(rows)
		var half_width := span * sin(PI * clampf(0.22 + 0.78 * v, 0.0, 1.0))
		var center_r := _petal_radius(base_r, tip_r, v)
		var y := 0.10 + (top_y - 0.10) * pow(v, 0.92)
		var row_points: Array = []
		var row_colors: Array = []
		for col in cols + 1:
			var u := float(col) / float(cols)
			var a := angle + (u - 0.5) * 2.0 * half_width
			# 边缘略向内收：单面片也能读出一片有厚度的花瓣。
			var r := center_r - 0.05 * (1.0 - pow(2.0 * u - 1.0, 2.0)) * (1.0 - v)
			row_points.append(Vector3(cos(a) * r, y + 0.035 * sin(u * PI) * (1.0 - v), sin(a) * r))
			var edge := absf(u - 0.5) * 2.0
			row_colors.append(light.lerp(dark, 0.18 + 0.62 * edge + 0.24 * (1.0 - v)))
		grid.append(row_points)
		color_grid.append(row_colors)
	for row in rows:
		for col in cols:
			var p0: Vector3 = grid[row][col]
			var p1: Vector3 = grid[row][col + 1]
			var p2: Vector3 = grid[row + 1][col + 1]
			var p3: Vector3 = grid[row + 1][col]
			var mid := (p0 + p1 + p2 + p3) * 0.25
			_quad(
				st, p0, p1, p2, p3,
				color_grid[row][col], color_grid[row][col + 1],
				color_grid[row + 1][col + 1], color_grid[row + 1][col],
				Vector3(mid.x, 0.35, mid.z)
			)

static func _petal_radius(base_r: float, tip_r: float, v: float) -> float:
	return lerpf(base_r, tip_r, pow(v, 0.7)) - 0.10 * sin(v * PI)

static func _add_collar(st: SurfaceTool) -> void:
	# 塔柱顶部的束腰 + 一圈金箍，再向外翻成承托塔冠的托盘。
	var profile := [
		Vector2(0.0, 6.34), Vector2(0.48, 6.34), Vector2(0.56, 6.40),
		Vector2(0.56, 6.50), Vector2(0.46, 6.56), Vector2(0.72, 6.64),
		Vector2(0.90, 6.74), Vector2(0.66, 6.88), Vector2(0.50, 6.96),
		Vector2(0.0, 6.96),
	]
	var colors := [
		STONE_MID, STONE_MID, TRIM, TRIM, TRIM,
		STONE_LIGHT, STONE_LIGHT, STONE_MID, STONE_MID, STONE_MID,
	]
	_revolve(st, profile, colors, 28)

static func _add_crown(st: SurfaceTool, style: Dictionary) -> void:
	# 笼状塔冠：石肋向外鼓起，在核心上方收拢，盖一个石顶。
	# 肋数 / 肋顶宝珠 / 金箍全部来自分级造型表 —— 这是「这是哪一级塔」最直接的剪影信号。
	var ribs := maxi(3, int(style.get("ribs", 6)))
	var finials := maxi(0, int(style.get("finials", 0)))
	for i in ribs:
		var a := TAU * float(i) / float(ribs)
		var points: Array = []
		for k in 7:
			var t := float(k) / 6.0
			var r := _bezier(0.50, 1.12, 0.32, t)
			var y := _bezier(6.94, 7.96, 8.60, t)
			points.append(Vector3(cos(a) * r, y, sin(a) * r))
		_add_tube(st, points, 0.105, 0.065, STONE_LIGHT, STONE_MID, 5)
		# 肋顶宝珠：沿肋均匀挑几根加一颗小球，形成"点状高光"的节奏差。
		# 不用每根都加 —— 全加会连成一圈念珠，反而读不出"更高级"。
		# 位置取 k=5 而不是最后一点：肋的末端在 8.60 收拢、正好被石顶（8.56 起）罩住，
		# 宝珠放末端会在图里完全看不见（第一版就是这么白做的）。k=5 落在石顶下沿之外，
		# 又贴着核心高度，俯视时是轮廓上最亮的那几个点。
		if finials > 0 and i % maxi(1, int(round(float(ribs) / float(finials)))) == 0:
			_add_finial(st, points[5])
	# 灯笼腰箍：夹在核心上下，读成「核心被石架托住」。
	var rim := [
		Vector2(0.0, 8.24), Vector2(0.58, 8.24), Vector2(0.62, 8.30),
		Vector2(0.62, 8.40), Vector2(0.56, 8.44), Vector2(0.0, 8.44),
	]
	_revolve(st, rim, [STONE_MID, TRIM, TRIM, TRIM, STONE_MID, STONE_MID], 20)
	# 高地塔的塔冠多一圈金箍：全塔唯一的"金线"落在核心周围，远看就是一道亮环。
	if bool(style.get("crown_ring", false)):
		var ring := [
			Vector2(0.66, 8.02), Vector2(0.70, 8.06), Vector2(0.70, 8.12),
			Vector2(0.62, 8.16),
		]
		_revolve(st, ring, [TRIM, TRIM, TRIM, STONE_MID], 24)
	var dome := [
		Vector2(0.0, 8.56), Vector2(0.38, 8.56), Vector2(0.40, 8.64),
		Vector2(0.24, 8.82), Vector2(0.0, TOP_HEIGHT),
	]
	_revolve(st, dome, [TRIM, TRIM, STONE_LIGHT, STONE_LIGHT, STONE_LIGHT], 20)

static func _add_finial(st: SurfaceTool, tip: Vector3) -> void:
	# 肋顶宝珠 = 一颗低模球。**必须是球**，不能是尖角：
	# 试过两版尖的（八面体 + 拉长八面体），俯视下都读成"塔冠上竖了一排白刺"，
	# 和"更高级"没有关系，反而像防御工事。球在 bloom 下是一个柔和亮点，才是要的东西。
	# 直径 0.26m ≈ 塔冠 1.4m 宽的五分之一：再大在 bloom 下会糊成一团白斑
	# （和野怪晶体同一条教训，见 monster_forms_jungle.gd 顶部注释）。
	var r := 0.13
	var segments := 8
	var rows := 4
	var rings: Array = []
	for k in rows + 1:
		var t := float(k) / float(rows)
		var ang := -PI * 0.5 + PI * t
		var ring_radius := r * cos(ang)
		var ring: Array = []
		for s in segments:
			var a := TAU * float(s) / float(segments)
			ring.append(tip + Vector3(cos(a) * ring_radius, r * sin(ang), sin(a) * ring_radius))
		rings.append(ring)
	var top_color := STONE_LIGHT.lerp(Color.WHITE, 0.35)
	var mid_color := STONE_LIGHT.lerp(TRIM, 0.25)
	var bottom_color := STONE_LIGHT.lerp(STONE_MID, 0.7)
	for k in rows:
		var upper_t := float(k) / float(rows)
		var c0: Color = top_color.lerp(mid_color, upper_t * 2.0 if upper_t < 0.5 else 1.0)
		var c1: Color = top_color.lerp(mid_color, float(k + 1) / float(rows) * 2.0 if float(k + 1) / float(rows) < 0.5 else 1.0)
		if float(k + 1) / float(rows) > 0.5:
			c1 = c1.lerp(bottom_color, (float(k + 1) / float(rows) - 0.5) * 2.0)
		for s in segments:
			var s2 := (s + 1) % segments
			var p0: Vector3 = rings[k][s]
			var p1: Vector3 = rings[k][s2]
			var p2: Vector3 = rings[k + 1][s2]
			var p3: Vector3 = rings[k + 1][s]
			var mid := (p0 + p1 + p2 + p3) * 0.25
			var hint := mid - tip
			if k == 0:
				_tri(st, p1, p2, p3, c0, c1, c1, hint)
			elif k == rows - 1:
				_tri(st, p0, p1, p3, c0, c0, c1, hint)
			else:
				_quad(st, p0, p1, p2, p3, c0, c0, c1, c1, hint)

static func _tri(st: SurfaceTool, p0: Vector3, p1: Vector3, p2: Vector3, c0: Color, c1: Color, c2: Color, hint: Vector3) -> void:
	var normal := (p1 - p0).cross(p2 - p0)
	if normal.length_squared() < 0.0000000001:
		return
	normal = normal.normalized()
	if normal.dot(hint) < 0.0:
		normal = -normal
	_put(st, p0, normal, c0)
	_put(st, p1, normal, c1)
	_put(st, p2, normal, c2)

# ---------- 光效 ----------

static func _make_core(team_color: Color) -> MeshInstance3D:
	var core := MeshInstance3D.new()
	core.name = "Core"
	var sphere := SphereMesh.new()
	sphere.radius = 0.32
	sphere.height = 0.64
	sphere.radial_segments = 16
	sphere.rings = 8
	core.mesh = sphere
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = team_color
	mat.emission_enabled = true
	mat.emission = team_color
	mat.emission_energy_multiplier = 4.2
	core.material_override = mat
	core.position.y = CORE_HEIGHT
	core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return core

static func _make_halo(team_color: Color) -> MeshInstance3D:
	var halo := MeshInstance3D.new()
	halo.name = "CoreHalo"
	var sphere := SphereMesh.new()
	sphere.radius = 0.62
	sphere.height = 1.24
	sphere.radial_segments = 16
	sphere.rings = 8
	halo.mesh = sphere
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.albedo_color = Color(team_color.r, team_color.g, team_color.b, 0.20)
	mat.emission_enabled = true
	mat.emission = team_color
	mat.emission_energy_multiplier = 1.3
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	halo.material_override = mat
	halo.position.y = CORE_HEIGHT
	halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return halo

static func _make_ground_glow(team_color: Color) -> MeshInstance3D:
	var glow := MeshInstance3D.new()
	glow.name = "GroundGlow"
	var plane := PlaneMesh.new()
	plane.size = Vector2(6.4, 6.4)
	glow.mesh = plane
	glow.position.y = GROUND_GLOW_Y
	var mat := ShaderMaterial.new()
	mat.shader = GLOW_SHADER
	mat.set_shader_parameter("glow_color", Color(team_color.r, team_color.g, team_color.b, 0.85))
	# 亮环落在石台外沿（1.38m / 3.2m 半宽）。
	mat.set_shader_parameter("ring_radius", 0.43)
	glow.material_override = mat
	glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return glow

# ---------- 残破 ----------

## 裂纹：沿塔柱爬升的暗色折线带。
##
## 为什么做成"预建网格 + 开/关显隐"而不是每帧改石料 shader：
##   石料是 vertex_color 上一个共享 StandardMaterial3D，靠改 albedo 只能整体变暗，
##   做不出"哪一条裂了"。裂纹单独一片薄壳贴在塔柱外侧，用纯色不发光材质，
##   残血时显示、满血时隐藏 —— 零战斗期分配，也不碰塔身的 AABB（贴合 0.01m 内）。
##
## 走折线而不是直线：直线在俯视下像一根绑在塔上的杆子；折线才读成"裂开了"。
static func build_cracks(rand_seed: int) -> MeshInstance3D:
	var rng := RandomNumberGenerator.new()
	rng.seed = rand_seed
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var count := 5
	for i in count:
		var base_angle := TAU * (float(i) + rng.randf_range(-0.18, 0.18)) / float(count)
		var y0 := rng.randf_range(0.75, 2.4)
		var y1 := y0 + rng.randf_range(1.6, 3.4)
		# 宽度 0.055~0.095m：第一版 0.030~0.055 在塔冠特写下才看得见，
		# 拉到 21m 实战机位就只剩几条灰线（截图 tower_health_low 复核过）。
		var width := rng.randf_range(0.055, 0.095)
		# 分 6 段折线爬升，每段随机拐一点角度。
		var points: Array = []
		var angle := base_angle
		var steps := 6
		for k in steps + 1:
			var t := float(k) / float(steps)
			var y := lerpf(y0, y1, t)
			angle += rng.randf_range(-0.16, 0.16)
			var radius := _shaft_radius((y - 0.42) / (SHAFT_TOP_Y - 0.42)) + 0.014
			points.append({
				"p": Vector3(cos(angle) * radius, y, sin(angle) * radius),
				"dir": Vector3(-sin(angle), 0.0, cos(angle)),
			})
		for k in steps:
			var lo: Dictionary = points[k]
			var hi: Dictionary = points[k + 1]
			var lp: Vector3 = lo["p"]
			var hp: Vector3 = hi["p"]
			var ld: Vector3 = lo["dir"]
			var hd: Vector3 = hi["dir"]
			var lw := width * (1.0 - 0.35 * float(k) / float(steps))
			var hw := width * (1.0 - 0.35 * float(k + 1) / float(steps))
			var hint := (lp + hp) * 0.5
			hint.y = 0.0
			_quad(st, lp - ld * lw, lp + ld * lw, hp + hd * hw, hp - hd * hw, CRACK_DARK, CRACK_DARK, CRACK_DARK, CRACK_DARK, hint)
	var crack := MeshInstance3D.new()
	crack.name = "Cracks"
	crack.mesh = st.commit()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = CRACK_DARK
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	crack.material_override = mat
	crack.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return crack

## 裂纹颜色。比 STONE_SHADOW 再深一档，且略偏冷 —— 暖色裂纹会像花纹而不是断口。
const CRACK_DARK := Color(0.16, 0.13, 0.12, 0.92)

static func _make_floating_petals() -> Node3D:
	var group := Node3D.new()
	group.name = "FloatingPetals"
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in FLOATING_PETAL_COUNT:
		var a := TAU * float(i) / FLOATING_PETAL_COUNT + 0.35
		var radius := 1.28 + 0.18 * sin(float(i) * 2.1)
		var y := 6.65 + 0.30 * float(i)
		var center := Vector3(cos(a) * radius, y, sin(a) * radius)
		var tangent := Vector3(-sin(a), 0.0, cos(a))
		var radial := Vector3(cos(a), 0.0, sin(a))
		var half_w := 0.13
		var half_h := 0.19
		var curl := 0.06
		var p0 := center - tangent * half_w - Vector3.UP * half_h
		var p1 := center + tangent * half_w - Vector3.UP * half_h
		var p2 := center + tangent * half_w + Vector3.UP * half_h + radial * curl
		var p3 := center - tangent * half_w + Vector3.UP * half_h + radial * curl
		var tint := Color(1.0, 0.80, 0.88, 0.95) if i % 2 == 0 else Color(1.0, 0.80, 0.44, 0.95)
		_quad(st, p0, p1, p2, p3, tint, tint, tint, tint, radial)
	var mesh := MeshInstance3D.new()
	mesh.name = "PetalMesh"
	mesh.mesh = st.commit()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.albedo_color = Color.WHITE
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh.material_override = mat
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	group.add_child(mesh)
	return group

# ---------- 网格工具 ----------

# 旋转体：profile 是 (半径, 高度) 序列，法线取该段轮廓的二维外法线。
# flutes > 0 时在半径上叠一圈余弦棱，顶点色同步压暗棱槽。
static func _revolve(st: SurfaceTool, profile: Array, colors: Array, segments: int, flutes := 0, flute_depth := 0.0) -> void:
	for i in profile.size() - 1:
		var lo: Vector2 = profile[i]
		var hi: Vector2 = profile[i + 1]
		var dr := hi.x - lo.x
		var dy := hi.y - lo.y
		var n2 := Vector2(dy, -dr)
		if n2.length_squared() < 0.000001:
			continue
		n2 = n2.normalized()
		var c_lo: Color = colors[i]
		var c_hi: Color = colors[i + 1]
		for s in segments:
			var a0 := TAU * float(s) / float(segments)
			var a1 := TAU * float(s + 1) / float(segments)
			var r0 := lo.x
			var r1 := lo.x
			var r2 := hi.x
			var r3 := hi.x
			if flutes > 0:
				r0 *= 1.0 + cos(float(flutes) * a0) * flute_depth
				r1 *= 1.0 + cos(float(flutes) * a1) * flute_depth
				r2 *= 1.0 + cos(float(flutes) * a1) * flute_depth
				r3 *= 1.0 + cos(float(flutes) * a0) * flute_depth
			var p0 := Vector3(cos(a0) * r0, lo.y, sin(a0) * r0)
			var p1 := Vector3(cos(a1) * r1, lo.y, sin(a1) * r1)
			var p2 := Vector3(cos(a1) * r2, hi.y, sin(a1) * r2)
			var p3 := Vector3(cos(a0) * r3, hi.y, sin(a0) * r3)
			var mid_a := (a0 + a1) * 0.5
			var hint := Vector3(cos(mid_a) * n2.x, n2.y, sin(mid_a) * n2.x)
			_quad(
				st, p0, p1, p2, p3,
				_groove(c_lo, a0, flutes), _groove(c_lo, a1, flutes),
				_groove(c_hi, a1, flutes), _groove(c_hi, a0, flutes),
				hint
			)

static func _groove(base: Color, angle: float, flutes: int) -> Color:
	if flutes <= 0:
		return base
	return base.lerp(STONE_SHADOW, 0.34 * clampf(-cos(float(flutes) * angle), 0.0, 1.0))

static func _add_tube(st: SurfaceTool, points: Array, radius_start: float, radius_end: float, color_start: Color, color_end: Color, sides: int) -> void:
	var rings: Array = []
	for i in points.size():
		var p: Vector3 = points[i]
		var prev: Vector3 = points[maxi(i - 1, 0)]
		var next: Vector3 = points[mini(i + 1, points.size() - 1)]
		var tangent := (next - prev).normalized()
		var radial := Vector3(p.x, 0.0, p.z)
		radial = radial.normalized() if radial.length() > 0.0001 else Vector3.RIGHT
		var side := tangent.cross(radial).normalized()
		if side.length_squared() < 0.000001:
			side = Vector3.RIGHT
		var up := side.cross(tangent).normalized()
		var t := float(i) / float(maxi(points.size() - 1, 1))
		var radius := lerpf(radius_start, radius_end, t)
		var ring: Array = []
		for s in sides:
			var a := TAU * float(s) / float(sides)
			ring.append(p + side * cos(a) * radius + up * sin(a) * radius)
		rings.append(ring)
	for i in points.size() - 1:
		var center_a: Vector3 = (points[i] + points[i + 1]) * 0.5
		var t := float(i) / float(maxi(points.size() - 2, 1))
		var c0 := color_start.lerp(color_end, t)
		var c1 := color_start.lerp(color_end, minf(t + 0.2, 1.0))
		for s in sides:
			var s2 := (s + 1) % sides
			var p0: Vector3 = rings[i][s]
			var p1: Vector3 = rings[i][s2]
			var p2: Vector3 = rings[i + 1][s2]
			var p3: Vector3 = rings[i + 1][s]
			var mid := (p0 + p1 + p2 + p3) * 0.25
			_quad(st, p0, p1, p2, p3, c0, c0, c1, c1, mid - center_a)

static func _quad(st: SurfaceTool, p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, c0: Color, c1: Color, c2: Color, c3: Color, hint: Vector3) -> void:
	var normal := (p1 - p0).cross(p2 - p0)
	if normal.length_squared() < 0.0000000001:
		normal = (p2 - p0).cross(p3 - p0)
	if normal.length_squared() < 0.0000000001:
		return
	normal = normal.normalized()
	if normal.dot(hint) < 0.0:
		normal = -normal
	_put(st, p0, normal, c0)
	_put(st, p1, normal, c1)
	_put(st, p2, normal, c2)
	_put(st, p0, normal, c0)
	_put(st, p2, normal, c2)
	_put(st, p3, normal, c3)

static func _put(st: SurfaceTool, vertex: Vector3, normal: Vector3, color: Color) -> void:
	st.set_normal(normal)
	st.set_color(color)
	st.add_vertex(vertex)

static func _bezier(a: float, b: float, c: float, t: float) -> float:
	var u := 1.0 - t
	return u * u * a + 2.0 * u * t * b + t * t * c
