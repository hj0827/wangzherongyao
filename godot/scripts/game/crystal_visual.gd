extends RefCounted
class_name CrystalVisual

## 基地主堡水晶的造型与状态表现（2026-11-12 重做）。
##
## 旧版是一颗六棱球 + 圆柱台座 + 一道 torus 光圈 + 一根半透明圆柱光柱
## （`arena.gd` 的 base 分支）。它在 21 米对局机位下能读成「蓝/红发光球」，
## 但离「王者荣耀的水晶」差得很远：没有台基层次、没有晶簇、没有环绕碎片、
## 没有符文轮，两个阵营只靠球体颜色区分。
##
## 这一版把主堡当成一座**独立设施**来建（和 TowerVisual / PortalVisual 同一分工）：
##   Arena 只负责世界坐标、阵营色和血量/护盾状态，形态与动画全部收在这里。
##
## 造型分五层，每一层都在俯视机位下承担一个可读信号：
##   ① 台基（dais）：三层收分圆台 + 8 块径向石墩 + 8 道凹槽 + 金环压边；
##   ② 柱座（pedestal）：8 棱收分石柱 + 8 片花瓣托盘 + 4 条抱晶石爪；
##   ③ 晶簇（gem）：一根 4.35m 主晶 + 3 根贴地副晶，全部是**平面法线**的多面体；
##   ④ 环绕（rings / shards / halo）：三层差速金环 + 6 块轨道碎片 + 一道斜光环；
##   ⑤ 光效（beam / sigil / shield）：双层光柱 + 贴地法阵 + 双塔护盾。
##
## 三条不能改的契约（测试逐条抓）：
##   1. `pedestal` / `gem` 必须在 `crystal_fade_parts` 里，且材质常驻 `TRANSPARENCY_ALPHA`。
##      英雄走进泉水时要把挡视线的部分淡到 `OcclusionFade.MIN_VISIBLE`；
##      `dais` 是贴地定位线索，**绝不能**跟着淡。
##   2. 所有每帧动画只改 transform / 材质参数，**不新建节点、不新建材质**（硬规则 4）。
##   3. 主晶顶部必须高于柱座，晶簇宽度不得超出台基 —— 否则是「一坨浮在台座外面的碎片」。
##
## **二轮（2026-11-12 下午）**：首版实拍出来是「实心蓝塑料宝石 + 三圈黑铁丝 + 灰白井盖底座」，
## 结构和王者荣耀对齐了，质感没对齐。这一轮不动分层与接线，只改观感：
##   ① `gem_energy` 能量外壳：复用 gem 网格再画一遍加法薄壳，fresnel 亮边 + 内部流光上涌
##      + 晶尖呼吸；主体材质、淡化契约、残破曲线一个字不改。
##   ② 晶尖去白帽、棱线降亮：阵营色一直贯到顶端，不再像「红宝石上插了截白蜡」。
##   ③ 金环加粗 + 自发光 + 等距符文：远景从「铁丝」变成「在运转的能量环」。
##   ④ 轨道碎片从水滴改扁晶片：主堡周围应该是碎裂的晶屑，不是六颗雨滴。
##   ⑤ 光柱去白灯管 + 加上升光屑；护盾保住阵营色；台基黑辐条改金属嵌条；
##      法阵加一层贴地柔光池。
##
## 材质**不做静态缓存**：OcclusionFade 会直接改 `albedo_color.a`，而静态缓存会被
## 同一进程里的下一局/下一张测试图复用，上一局淡到 0.16 的水晶会在新局里一出生就半透明。
## 一局只有两座主堡、每座建一次，逐座 new 材质的代价可以忽略；**网格**仍然缓存。

const BEAM_SHADER := preload("res://shaders/crystal_beam.gdshader")
const SHIELD_SHADER := preload("res://shaders/crystal_shield.gdshader")
const SIGIL_SHADER := preload("res://shaders/crystal_sigil.gdshader")
const ENERGY_SHADER := preload("res://shaders/crystal_energy.gdshader")

## 台基半径。玩法层没有对应碰撞体（主堡本体半径 4.0 在 sim 里），
## 视觉上略大一圈才像「水晶长在台子上」，但又不能大到盖住泉水出生点。
const DAIS_RADIUS := 4.72
const DAIS_TOP := 0.62
## 柱座顶面高度。主晶底部从 `GEM_BASE_Y` 起浮，中间留 0.34m 的「悬浮缝」。
const PEDESTAL_TOP := 2.98
const GEM_BASE_Y := 3.32
const GEM_HEIGHT := 4.35
const GEM_TOP := GEM_BASE_Y + GEM_HEIGHT
## 主晶最大半径：1.18m。再粗会盖住柱座，让「水晶浮在柱子上」变成「一根胖柱子」。
const GEM_RADIUS := 1.18
const GEM_SIDES := 6
const SHARD_COUNT := 6
const RING_COUNT := 3
const SHIELD_RADIUS := 4.65

## 血条位置：主晶顶 7.67 + 0.95 的余量，不能压到晶尖上。
const BAR_HEIGHT := 8.75
const BAR_WIDTH := 5.2

## 残破表现的起点。和塔使用同一档（55%）：玩家对「半血」有共同直觉。
const DAMAGE_THRESHOLD := 0.55

## 三种阵营的材质语言。蓝方是冷白石灰蓝金，红方是暖象牙石赤金。
## 数值按 FILMIC + 曝光 1.05 反解过：石头基色落在 0.5~0.8，经过色调映射后
## 仍然是「石头」而不是灰塑料；金色要压到 0.7 以下，否则 bloom 会把金边烧成白线。
const PALETTES := {
	"blue": {
		"stone_light": Color(0.42, 0.48, 0.57),
		"stone_mid": Color(0.26, 0.32, 0.41),
		"stone_dark": Color(0.09, 0.13, 0.19),
		"stone_warm": Color(0.50, 0.55, 0.61),
		"trim": Color(0.62, 0.46, 0.18),
		"trim_dark": Color(0.24, 0.16, 0.06),
		"gem_deep": Color(0.012, 0.055, 0.22),
		"gem_mid": Color(0.05, 0.24, 0.62),
		"gem_hot": Color(0.40, 0.82, 1.0),
		# 晶尖不再取近白：0.84/0.97/1.0 经 emission + rim + FILMIC 后在实拍里
		# 是一截纯白三角帽，阵营色在最该亮的尖端反而丢了。
		"gem_tip": Color(0.36, 0.84, 1.0),
		"gem_accent": Color(0.46, 0.32, 0.96),
	},
	"red": {
		"stone_light": Color(0.52, 0.43, 0.34),
		"stone_mid": Color(0.33, 0.26, 0.20),
		"stone_dark": Color(0.14, 0.09, 0.07),
		"stone_warm": Color(0.60, 0.50, 0.39),
		"trim": Color(0.68, 0.47, 0.16),
		"trim_dark": Color(0.27, 0.16, 0.05),
		"gem_deep": Color(0.22, 0.006, 0.012),
		"gem_mid": Color(0.62, 0.035, 0.02),
		"gem_hot": Color(1.0, 0.20, 0.09),
		"gem_tip": Color(1.0, 0.40, 0.20),
		"gem_accent": Color(1.0, 0.52, 0.08),
	},
}

## 轨道碎片的参数。半径/高度/速度/相位/缩放分别给，6 块碎片才不会像一串念珠。
## 半径收紧到 1.9~2.4：旧版 3.1 米让碎片飞出主晶轮廓，读成「行星环」而不是「主堡水晶」。
## 注意：两圈轨道的高度都落在主晶腰线以上，碎片不能从台座里穿出来。
const SHARD_BANDS := [
	{"radius": 1.92, "y": 4.95, "speed": 0.30, "phase": 0.00, "scale": 0.58},
	{"radius": 2.18, "y": 5.95, "speed": -0.22, "phase": 1.10, "scale": 0.46},
	{"radius": 2.42, "y": 4.50, "speed": 0.18, "phase": 2.20, "scale": 0.52},
]

## 环管半径。首版 0.022~0.036 在实拍里是三圈深褐色细线（像铁丝），
## 21 米机位几乎读不到；提到 0.034~0.056 再配自发光，才成「能量环」。
const RING_SPECS := [
	{"radius": 2.34, "y": 3.78, "tilt": -0.10, "speed": 0.20, "tube": 0.056},
	{"radius": 2.66, "y": 4.34, "tilt": 0.22, "speed": -0.14, "tube": 0.046},
	# 第三道环悬在晶尖上方，不穿过晶体：旧版 1.55m 半径正好卡在晶尖，
	# 俯视下读成「一个呼啦圈套在宝石上」，把最该干净的尖端切碎。
	{"radius": 1.05, "y": 8.02, "tilt": 0.18, "speed": 0.22, "tube": 0.034},
]

static var _meshes: Dictionary = {}


# ---------------------------------------------------------------------------
# 纯函数：状态 → 外观
# ---------------------------------------------------------------------------

static func palette(team: String) -> Dictionary:
	return (PALETTES.get(team, PALETTES["blue"]) as Dictionary).duplicate(true)

## 血量比例 → 残破强度（0 = 完好，1 = 见底）。阈值以上恒为 0，以下单调上升。
static func damage_tone(ratio: float) -> float:
	var r := clampf(ratio, 0.0, 1.0)
	if r >= DAMAGE_THRESHOLD:
		return 0.0
	return clampf(1.0 - r / DAMAGE_THRESHOLD, 0.0, 1.0)

## 主晶自发光随残血衰减。留 0.42 的底：残血水晶仍然要能被看见，
## 只是从「有精神」变成「快灭了」。
static func gem_energy(base_energy: float, damage: float, time: float) -> float:
	var breathe := 0.94 + 0.06 * sin(time * 1.55)
	return base_energy * breathe * (1.0 - 0.58 * clampf(damage, 0.0, 1.0))

## 轨道碎片位置（纯函数，方便 headless 断言「会动、彼此不同、不会穿台座」）。
## `index` 必须是碎片序号而不是 band 序号：同一条轨道上两块碎片只靠 band 参数会重叠。
static func shard_orbit(index: int, time: float) -> Vector3:
	return shard_orbit_with_speed(index % SHARD_BANDS.size(), time, index)

## 护盾强度 0..1。护盾量只影响「厚不厚」，显隐由 `shield > 0` 决定。
static func shield_strength(value: float, maximum: float) -> float:
	if value <= 0.0:
		return 0.0
	if maximum <= 0.0:
		return 1.0
	return clampf(value / maximum, 0.0, 1.0)


# ---------------------------------------------------------------------------
# 造型
# ---------------------------------------------------------------------------

## `team_color` 来自 Arena.BLUE / Arena.RED；`team` 只用于选石材配色。
static func build(team_color: Color, team := "blue") -> Dictionary:
	var palette_data := palette(team)
	var root := Node3D.new()
	root.name = "CrystalBase"
	var fade_parts: Array = []
	var no_shadow_parts: Array = []

	# --- ① 台基 -----------------------------------------------------------
	var dais_material := _stone_material(palette_data, false)
	var dais := MeshInstance3D.new()
	dais.name = "dais"
	dais.mesh = _cached("dais|" + team, func() -> ArrayMesh: return _dais_mesh(palette_data))
	dais.material_override = dais_material
	dais.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	root.add_child(dais)

	var trim_material := _metal_material(false)
	var trim := MeshInstance3D.new()
	trim.name = "base_trim"
	trim.mesh = _cached("trim|" + team, func() -> ArrayMesh: return _trim_mesh(palette_data))
	trim.material_override = trim_material
	trim.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	root.add_child(trim)

	# --- ② 柱座 -----------------------------------------------------------
	var pedestal_material := _stone_material(palette_data, true)
	var pedestal := MeshInstance3D.new()
	pedestal.name = "pedestal"
	pedestal.mesh = _cached("pedestal|" + team, func() -> ArrayMesh: return _pedestal_mesh(palette_data))
	pedestal.material_override = pedestal_material
	pedestal.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	root.add_child(pedestal)
	fade_parts.append(pedestal)

	var pedestal_glow_material := _additive_material(team_color, 0.72, 1.45)
	var pedestal_glow := MeshInstance3D.new()
	pedestal_glow.name = "pedestal_glow"
	pedestal_glow.mesh = _cached("pedestal_glow", func() -> ArrayMesh: return _pedestal_glow_mesh())
	pedestal_glow.material_override = pedestal_glow_material
	pedestal_glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(pedestal_glow)
	fade_parts.append(pedestal_glow)
	no_shadow_parts.append(pedestal_glow)

	# --- ③ 晶簇 -----------------------------------------------------------
	var spin := Node3D.new()
	spin.name = "gem_spin"
	spin.position = Vector3(0.0, GEM_BASE_Y, 0.0)
	spin.set_meta("rest_y", GEM_BASE_Y)
	root.add_child(spin)

	var gem_material := _gem_material(team_color)
	var gem := MeshInstance3D.new()
	gem.name = "gem"
	gem.mesh = _cached("gem|" + team, func() -> ArrayMesh: return _gem_cluster_mesh(palette_data, team_color))
	gem.material_override = gem_material
	gem.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	spin.add_child(gem)
	fade_parts.append(gem)
	no_shadow_parts.append(gem)

	# 能量外壳：**复用 gem 网格**，只放大 1.03 再画一遍加法薄壳。
	# 它不进 fade_parts（ShaderMaterial 不在 OcclusionFade 的作用面里），
	# 但 apply_state 会把 gem 的 albedo.a 同步成 fade_alpha，贴脸时一起让路。
	var energy_material := _energy_material(team_color, palette_data)
	var gem_energy := MeshInstance3D.new()
	gem_energy.name = "gem_energy"
	gem_energy.mesh = gem.mesh
	gem_energy.material_override = energy_material
	gem_energy.scale = Vector3.ONE * 1.03
	gem_energy.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	spin.add_child(gem_energy)
	no_shadow_parts.append(gem_energy)

	# 棱线从「白色描边」降成「微光」：首版 alpha 0.56 / energy 1.95 在实拍里
	# 把每个切面都勾了一道白边，晶体反而更像低多边形塑料玩具。
	var edge_material := _additive_material(team_color.lerp(Color(1.0, 1.0, 1.0), 0.28), 0.30, 1.20)
	var edges := MeshInstance3D.new()
	edges.name = "gem_edges"
	edges.mesh = _cached("gem_edges", func() -> ArrayMesh: return _gem_edges_mesh())
	edges.material_override = edge_material
	edges.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	spin.add_child(edges)
	fade_parts.append(edges)
	no_shadow_parts.append(edges)

	var halo_material := _additive_material(team_color, 0.22, 1.05)
	var halo := MeshInstance3D.new()
	halo.name = "halo"
	halo.mesh = _halo_mesh()
	halo.material_override = halo_material
	halo.position.y = 1.35
	# 固定一个 22° 的倾角：水平圆环在俯视下只是一条线，斜过来才有体积。
	halo.rotation.x = 0.38
	halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	spin.add_child(halo)
	fade_parts.append(halo)
	no_shadow_parts.append(halo)

	# --- ④ 环绕碎片 + 金环 -------------------------------------------------
	var shards: Array = []
	# 碎片比本体亮一档：它们只有 0.5m，21 米机位下用本体的 0.38 emission 会缩成
	# 六个深色小点。独立材质才能让「晶屑」在剪影外缘读得出来。
	var shard_material := _shard_material(team_color)
	# 碎片顶点色写的是阵营宝石梯度，必须按阵营缓存；共用蓝色网格会把红方碎片染成蓝白。
	var shard_mesh: Mesh = _cached("orbit_shard|" + team, func() -> ArrayMesh: return _orbit_shard_mesh(palette_data))
	for i in SHARD_COUNT:
		var shard := MeshInstance3D.new()
		shard.name = "shard_%d" % i
		shard.mesh = shard_mesh
		shard.material_override = shard_material
		shard.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		shard.set_meta("band", i % SHARD_BANDS.size())
		var band: Dictionary = SHARD_BANDS[i % SHARD_BANDS.size()]
		var s := float(band.scale)
		# 扁晶片：等比缩放会把刀锋压回一颗水滴，Z 轴必须明显薄于 X/Y。
		shard.scale = Vector3(s, s * 1.15, s * 0.78)
		root.add_child(shard)
		shards.append(shard)
		fade_parts.append(shard)
		no_shadow_parts.append(shard)

	var ring_roots: Array = []
	var ring_materials: Array = []
	for i in RING_COUNT:
		var spec: Dictionary = RING_SPECS[i]
		var ring_root := Node3D.new()
		ring_root.name = "ring_%d" % i
		ring_root.position.y = float(spec.y)
		root.add_child(ring_root)
		var ring_body := MeshInstance3D.new()
		ring_body.name = "ring_body_%d" % i
		# 悬浮环才带等距符文；广场同心环不传，避免半径 8m 的圈上长一排金疙瘩。
		var rune_count: int = [10, 12, 6][i]
		ring_body.mesh = _ring_mesh(float(spec.radius), float(spec.tube), 64, 6, palette_data, rune_count)
		ring_body.rotation.x = float(spec.tilt)
		var body_material := _ring_body_material(team_color, palette_data)
		ring_body.material_override = body_material
		ring_body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		ring_root.add_child(ring_body)
		var ring_glow := MeshInstance3D.new()
		ring_glow.name = "ring_glow_%d" % i
		ring_glow.mesh = _ring_mesh(float(spec.radius), float(spec.tube) * 1.45, 64, 5, palette_data)
		ring_glow.rotation.x = float(spec.tilt)
		var glow_material := _additive_material(team_color, 0.20, 1.55)
		ring_glow.material_override = glow_material
		ring_glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		ring_root.add_child(ring_glow)
		ring_roots.append(ring_root)
		ring_materials.append(glow_material)
		no_shadow_parts.append(ring_body)
		no_shadow_parts.append(ring_glow)

	# --- ⑤ 光柱 / 法阵 / 护盾 ----------------------------------------------
	# 内芯从「近白灯管」退回队伍亮色：0.92/0.98/1.0 过 glow 后是一根纯白硬线，
	# 红蓝两座基地的光柱长得一模一样，只剩底座分色。
	# 二轮实拍复盘：0.52 的白化 + blend_add 在浅色地面上仍把柱子烧成白灯管，
	# 红方尤其读成粉白。压到 0.30 并略降内芯 alpha，靠加宽外焰补远景体积感。
	var beam_hot := team_color.lerp(Color(1.0, 1.0, 1.0), 0.30)
	var beam_inner_material := _beam_material(team_color, 0.24, beam_hot, 0.70, 0.34)
	var beam_outer_material := _beam_material(team_color, 0.095, beam_hot, 0.58, 0.06)
	var beam_inner := MeshInstance3D.new()
	beam_inner.name = "beam_inner"
	beam_inner.mesh = _beam_mesh(0.15, 0.23, 24.0)
	beam_inner.material_override = beam_inner_material
	# 光柱从晶尖之上起：旧版中心在 14.2（底端 1.2），整根柱从晶体内部穿过，
	# 加色混合把晶体烧成一根白柱。现在底端 = GEM_TOP - 0.2。
	beam_inner.position.y = GEM_TOP + 11.8
	beam_inner.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(beam_inner)
	no_shadow_parts.append(beam_inner)
	var beam_outer := MeshInstance3D.new()
	beam_outer.name = "beam_outer"
	# 外焰：0.78m 底半径在近景糊住半个屏幕；0.62 太细，21 米机位下光柱几乎消失。
	# 0.74 是近景可读 / 远景有光晕的折中，配更饱和的队伍色不会烧成白管。
	beam_outer.mesh = _beam_mesh(0.44, 0.74, 24.0)
	beam_outer.material_override = beam_outer_material
	beam_outer.position.y = GEM_TOP + 11.8
	beam_outer.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(beam_outer)
	no_shadow_parts.append(beam_outer)

	var sigil_material := _sigil_material(team_color)
	var sigil := MeshInstance3D.new()
	sigil.name = "base_sigil_" + team
	sigil.mesh = _plane_mesh(14.0)
	sigil.material_override = sigil_material
	sigil.position.y = 0.095
	sigil.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(sigil)
	no_shadow_parts.append(sigil)

	var plaza_rings: Array = []
	var plaza_ring_materials: Array = []
	for i in 3:
		var radius: float = [8.00, 6.10, 4.96][i]
		var ring := MeshInstance3D.new()
		ring.name = "base_ring_%s_%d" % [team, i]
		ring.mesh = _ring_mesh(radius, [0.045, 0.033, 0.026][i], 96, 5, palette_data)
		var ring_material := _additive_material(team_color, [0.14, 0.11, 0.09][i], 0.72)
		ring.material_override = ring_material
		ring.position.y = 0.10
		ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(ring)
		plaza_rings.append(ring)
		plaza_ring_materials.append(ring_material)
		no_shadow_parts.append(ring)

	var shield_material := _shield_material(team_color)
	var shield := MeshInstance3D.new()
	shield.name = "crystal_shield"
	shield.mesh = _shield_mesh()
	shield.material_override = shield_material
	shield.position.y = 3.15
	shield.visible = false
	shield.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(shield)
	no_shadow_parts.append(shield)

	var light := OmniLight3D.new()
	light.name = "CrystalLight"
	light.light_color = team_color
	# 旧版 1.45 / 19m 把整座台基从内部打亮，石阶没有暗面，远处只剩一团白光。
	# 0.45 / 12m 只做「水晶在照亮脚下一圈」的局部补光，不参与台面主曝光。
	light.light_energy = 0.45
	light.omni_range = 12.0
	light.position = Vector3(0.0, 4.6, 0.0)
	light.shadow_enabled = false
	root.add_child(light)

	var cracks := MeshInstance3D.new()
	cracks.name = "cracks"
	cracks.mesh = _cached("cracks|" + team, func() -> ArrayMesh: return _cracks_mesh(team))
	cracks.material_override = _crack_material()
	cracks.visible = false
	cracks.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(cracks)
	fade_parts.append(cracks)
	no_shadow_parts.append(cracks)

	# 晶体自身的裂纹：残血时主晶表面出现暗色裂线，跟着晶簇一起转。
	# 只裂柱座不裂晶体的话，15% 血时读起来只是「台座脏了」，晶体仍然完好。
	var gem_cracks := MeshInstance3D.new()
	gem_cracks.name = "gem_cracks"
	gem_cracks.mesh = _cached("gem_cracks|" + team, func() -> ArrayMesh: return _gem_cracks_mesh(team))
	gem_cracks.material_override = _crack_material()
	gem_cracks.visible = false
	gem_cracks.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	spin.add_child(gem_cracks)
	fade_parts.append(gem_cracks)
	no_shadow_parts.append(gem_cracks)

	return {
		"node": root,
		"team": team,
		"team_color": team_color,
		"dais": dais,
		"dais_material": dais_material,
		"trim": trim,
		"trim_material": trim_material,
		"pedestal": pedestal,
		"pedestal_material": pedestal_material,
		"pedestal_glow": pedestal_glow,
		"pedestal_glow_material": pedestal_glow_material,
		"spin": spin,
		"gem": gem,
		"gem_material": gem_material,
		"gem_energy": gem_energy,
		"gem_energy_material": energy_material,
		"edges": edges,
		"edge_material": edge_material,
		"halo": halo,
		"halo_material": halo_material,
		"shards": shards,
		"shard_material": shard_material,
		"rings": ring_roots,
		"ring_materials": ring_materials,
		"sigil": sigil,
		"sigil_material": sigil_material,
		"plaza_rings": plaza_rings,
		"plaza_ring_materials": plaza_ring_materials,
		"beam_inner": beam_inner,
		"beam_outer": beam_outer,
		"beam_inner_material": beam_inner_material,
		"beam_outer_material": beam_outer_material,
		"shield": shield,
		"shield_material": shield_material,
		"light": light,
		"cracks": cracks,
		"cracks_material": cracks.material_override,
		"gem_cracks": gem_cracks,
		"fade_parts": fade_parts,
		"no_shadow_parts": no_shadow_parts,
		"bar_height": BAR_HEIGHT,
		"bar_width": BAR_WIDTH,
		"gem_base_energy": gem_material.emission_energy_multiplier,
		"shard_base_energy": shard_material.emission_energy_multiplier,
		"halo_base_alpha": halo_material.albedo_color.a,
		"edge_base_alpha": edge_material.albedo_color.a,
		"light_base_energy": light.light_energy,
		"beam_base_intensity": 1.0,
		"damage": 0.0,
		"shield_strength": 0.0,
		"time": 0.0,
	}


# ---------------------------------------------------------------------------
# 每帧驱动
# ---------------------------------------------------------------------------

## 只改 transform 与已存在的材质参数。`delta` 为 0 时也能安全调用（初始帧）。
static func apply_state(state: Dictionary, delta: float) -> void:
	if state.is_empty():
		return
	var time := float(state.get("time", 0.0)) + delta
	state["time"] = time
	var damage := clampf(float(state.get("damage", 0.0)), 0.0, 1.0)

	var spin := state.get("spin") as Node3D
	if spin != null:
		# 主晶慢转 + 上下浮。转速比旧版更慢：一颗 4 米高的晶体转太快会读成「陀螺」。
		spin.rotation.y = time * 0.11
		var rest := float(spin.get_meta("rest_y", GEM_BASE_Y))
		spin.position.y = rest + sin(time * 0.82) * 0.055

	var halo := state.get("halo") as Node3D
	if halo != null:
		halo.rotation.y = -time * 0.19
		halo.rotation.z = 0.18 * sin(time * 0.6)

	var shards: Array = state.get("shards", [])
	for i in shards.size():
		var shard := shards[i] as Node3D
		if shard == null:
			continue
		var band_index := int(shard.get_meta("band", i % SHARD_BANDS.size()))
		var band: Dictionary = SHARD_BANDS[band_index]
		var speed_scale := 1.0 - 0.45 * damage
		var point := shard_orbit_with_speed(band_index, time * speed_scale, i)
		shard.position = point
		shard.rotation.y = -time * float(band.speed) * 0.8
		shard.rotation.z = 0.24 * sin(time * 0.7 + float(band.phase))

	var rings: Array = state.get("rings", [])
	for i in rings.size():
		var ring := rings[i] as Node3D
		if ring == null:
			continue
		var spec: Dictionary = RING_SPECS[i % RING_SPECS.size()]
		ring.rotation.y = time * float(spec.speed)

	var gem_material := state.get("gem_material") as StandardMaterial3D
	if gem_material != null:
		gem_material.emission_energy_multiplier = gem_energy(float(state.get("gem_base_energy", 1.55)), damage, time)
	var shard_material := state.get("shard_material") as StandardMaterial3D
	if shard_material != null:
		shard_material.emission_energy_multiplier = gem_energy(float(state.get("shard_base_energy", 1.55)), damage, time + 0.7)

	# 能量外壳：三个状态量全在这里推，shader 不藏 TIME。
	# fade_alpha 直接读主体 gem 被 OcclusionFade 写过的 albedo.a —— arena 里
	# apply_state 排在 OcclusionFade.apply 之前，所以是上一帧的值；8 米的平滑
	# 过渡带里差一帧（16ms）看不出来，但贴脸时壳一定会跟着淡，不会留一圈亮边糊住英雄。
	var energy_material := state.get("gem_energy_material") as ShaderMaterial
	if energy_material != null:
		energy_material.set_shader_parameter("phase", time)
		energy_material.set_shader_parameter("damage", damage)
		var gem_for_fade := state.get("gem_material") as StandardMaterial3D
		var fade := 1.0 if gem_for_fade == null else gem_for_fade.albedo_color.a
		energy_material.set_shader_parameter("fade_alpha", fade)
		energy_material.set_shader_parameter("intensity", (1.0 - 0.45 * damage) * (0.94 + 0.06 * sin(time * 1.35)))
	var halo_material := state.get("halo_material") as StandardMaterial3D
	if halo_material != null:
		var base_alpha := float(state.get("halo_base_alpha", 0.28))
		halo_material.albedo_color.a = base_alpha * (0.82 + 0.18 * sin(time * 1.7))
	var edge_material := state.get("edge_material") as StandardMaterial3D
	if edge_material != null:
		edge_material.albedo_color.a = float(state.get("edge_base_alpha", 0.30)) * (0.88 + 0.12 * sin(time * 2.1))

	var light := state.get("light") as OmniLight3D
	if light != null:
		light.light_energy = float(state.get("light_base_energy", 0.72)) * (0.92 + 0.08 * sin(time * 1.45)) * (1.0 - 0.5 * damage)

	var sigil_material := state.get("sigil_material") as ShaderMaterial
	if sigil_material != null:
		sigil_material.set_shader_parameter("spin", time)
		sigil_material.set_shader_parameter("damage", damage)
		sigil_material.set_shader_parameter("shield", float(state.get("shield_strength", 0.0)))
	var beam_inner := state.get("beam_inner_material") as ShaderMaterial
	if beam_inner != null:
		beam_inner.set_shader_parameter("intensity", (1.0 - 0.45 * damage) * (0.94 + 0.06 * sin(time * 1.35)))
	var beam_outer := state.get("beam_outer_material") as ShaderMaterial
	if beam_outer != null:
		beam_outer.set_shader_parameter("intensity", (1.0 - 0.55 * damage) * (0.90 + 0.10 * sin(time * 1.10 + 1.2)))
	var plaza_materials: Array = state.get("plaza_ring_materials", [])
	for i in plaza_materials.size():
		var material := plaza_materials[i] as StandardMaterial3D
		if material != null:
			material.albedo_color.a = [0.14, 0.11, 0.09][i] * (0.80 + 0.20 * sin(time * 0.8 + float(i) * 1.3)) * (1.0 - 0.4 * damage)

## `shard_orbit` 的带速度版本：残血时碎片会「转不动」，用同一个时间轴缩放即可。
static func shard_orbit_with_speed(band_index: int, time: float, index: int) -> Vector3:
	var band: Dictionary = SHARD_BANDS[band_index % SHARD_BANDS.size()]
	var angle := time * float(band.speed) + float(band.phase) + float(index) * 0.12
	var radius := float(band.radius)
	return Vector3(
		cos(angle) * radius,
		float(band.y) + sin(time * 0.9 + float(band.phase)) * 0.11,
		sin(angle) * radius
	)

## 血量 → 残破。只改材质与显隐，不新建任何东西。
static func apply_damage(state: Dictionary, ratio: float) -> void:
	if state.is_empty():
		return
	var tone := damage_tone(ratio)
	if is_equal_approx(tone, float(state.get("damage", -1.0))):
		return
	state["damage"] = tone
	var cracks := state.get("cracks") as MeshInstance3D
	if cracks != null:
		cracks.visible = tone > 0.001
	var gem_cracks := state.get("gem_cracks") as MeshInstance3D
	if gem_cracks != null:
		gem_cracks.visible = tone > 0.001
	var dais_material := state.get("dais_material") as StandardMaterial3D
	if dais_material != null:
		dais_material.albedo_color = _with_alpha(Color(1.0, 1.0, 1.0).lerp(Color(0.42, 0.40, 0.38), tone), dais_material.albedo_color.a)
	var pedestal_material := state.get("pedestal_material") as StandardMaterial3D
	if pedestal_material != null:
		# 保留 alpha：贴脸时 OcclusionFade 已经把柱身降到 0.16，这里改 RGB 不能把它弹回不透明。
		pedestal_material.albedo_color = _with_alpha(Color(1.0, 1.0, 1.0).lerp(Color(0.38, 0.36, 0.35), tone), pedestal_material.albedo_color.a)
	var gem_material := state.get("gem_material") as StandardMaterial3D
	if gem_material != null:
		gem_material.albedo_color = _with_alpha(Color(1.0, 1.0, 1.0).lerp(Color(0.38, 0.36, 0.36), tone * 0.92), gem_material.albedo_color.a)
	var pedestal_glow := state.get("pedestal_glow_material") as StandardMaterial3D
	if pedestal_glow != null:
		pedestal_glow.emission_energy_multiplier = 1.45 * (1.0 - 0.65 * tone)
	var light := state.get("light") as OmniLight3D
	if light != null:
		light.light_energy = float(state.get("light_base_energy", 0.72)) * (1.0 - 0.5 * tone)

## 护盾显隐与强度。`value` 是快照里的 `shield`，`maximum` 是 `shield_max`。
static func apply_shield(state: Dictionary, value: float, maximum: float) -> void:
	if state.is_empty():
		return
	var strength := shield_strength(value, maximum)
	state["shield_strength"] = strength
	var shield := state.get("shield") as MeshInstance3D
	if shield != null:
		shield.visible = value > 0.0
	var material := state.get("shield_material") as ShaderMaterial
	if material != null:
		material.set_shader_parameter("strength", strength)
		material.set_shader_parameter("pulse", 0.0)
	# 法阵也要当场更新：apply_state 在下一帧才会把 shield_strength 写进 shader，
	# 如果这里不写，破盾/满盾会在阵纹上晚一帧（测试能抓到 0↔1 反向）。
	var sigil_material := state.get("sigil_material") as ShaderMaterial
	if sigil_material != null:
		sigil_material.set_shader_parameter("shield", strength)


# ---------------------------------------------------------------------------
# 网格：台基 / 柱座 / 晶簇
# ---------------------------------------------------------------------------

static func _dais_mesh(p: Dictionary) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var light: Color = p.stone_light
	var mid: Color = p.stone_mid
	var dark: Color = p.stone_dark
	var warm: Color = p.stone_warm
	# 三层**平踏面**收分：底沿外扩、每层一个可站人的环面 + 一道竖直踢面。
	# 之前的斜切台阶在 21 米俯视下读成「一个圆台」，看不出「砌了三层」。
	var profile := [
		Vector2(0.0, 0.04), Vector2(4.72, 0.04),
		Vector2(4.78, 0.10), Vector2(4.78, 0.22),
		Vector2(4.42, 0.22), Vector2(4.42, 0.36),
		Vector2(4.06, 0.36), Vector2(4.06, 0.50),
		Vector2(3.72, 0.50), Vector2(3.72, DAIS_TOP),
		Vector2(0.0, DAIS_TOP),
	]
	var colors := [
		dark, dark, mid, light, light, mid, mid, light, light, warm, warm,
	]
	_revolve(st, profile, colors, 64)
	# 内圈平台：把 9.4 米的大圆盘收成「外圈步道 + 内圈祭坛」两级。
	# 没有这一级时，台面中央是一大片空白石板，俯视像一块白盘子。
	var inner_profile := [
		Vector2(0.0, DAIS_TOP), Vector2(2.52, DAIS_TOP),
		Vector2(2.62, DAIS_TOP + 0.06), Vector2(2.62, DAIS_TOP + 0.16),
		Vector2(2.46, DAIS_TOP + 0.22), Vector2(0.0, DAIS_TOP + 0.22),
	]
	var inner_colors := [mid, mid, dark, light, mid, mid]
	_revolve(st, inner_profile, inner_colors, 64)
	# 8 道径向金属嵌条 + 8 块浅石板拼花。
	# 首版这里铺的是 0.94×0.56 的深色石墩，俯视实拍是「八块黑板砖」，
	# 整座台基读成灰白井盖 / 排水格栅 —— 全图最抢眼的负分。
	# 现在收窄成 0.15m 的铜线，间隔里铺浅石板：放射节奏留着，黑块没了。
	var gold: Color = p.trim
	for i in 8:
		var angle := TAU * (float(i) + 0.5) / 8.0
		var point := Vector3(cos(angle) * 3.05, DAIS_TOP + 0.028, sin(angle) * 3.05)
		_add_box(st, point, Vector3(0.94, 0.030, 0.15), -angle, gold.lerp(light, 0.30), gold.lerp(mid, 0.35))
	for i in 8:
		var angle := TAU * float(i) / 8.0
		var point := Vector3(cos(angle) * 3.05, DAIS_TOP + 0.012, sin(angle) * 3.05)
		_add_box(st, point, Vector3(0.72, 0.016, 0.62), -angle, light.lerp(warm, 0.35), mid)
	# 8 道凹槽：铺在内圈平台上，读出「台面是拼出来的」。
	# 颜色从近黑抬到中灰，否则俯视又是一圈黑色短线。
	for i in 8:
		var angle := TAU * float(i) / 8.0
		var point := Vector3(cos(angle) * 2.14, DAIS_TOP + 0.226, sin(angle) * 2.14)
		_add_box(st, point, Vector3(0.78, 0.012, 0.10), -angle, dark.lerp(mid, 0.35), dark.lerp(mid, 0.35))
	return st.commit()

static func _trim_mesh(p: Dictionary) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var gold: Color = p.trim
	var dark: Color = p.trim_dark
	# 两道金环压住台基：外沿一道落在第一级平踏面，台阶收口一道压在顶面边缘。
	# 金线是全图唯一的暖金属，远处一眼就能把「主堡」和野区的石台分开。
	_add_torus(st, 4.60, 0.055, 72, 6, gold, Color(1.0, 1.0, 1.0), 0.22)
	_add_torus(st, 3.62, 0.040, 64, 6, gold.lerp(dark, 0.25), Color(1.0, 1.0, 1.0), DAIS_TOP)
	# 三道暗色收口：俯视机位看不到台阶的立面，没有这三条暗线时三层台基读成一块平板。
	for i in 3:
		_add_torus(st, [4.70, 4.40, 4.04][i], 0.014, 72, 4, dark, dark, [0.215, 0.355, 0.495][i])
	# 柱座基脚的金属圈 + 花尖金饰：把「石台」和「柱座」在材质上咬合起来。
	_add_torus(st, 1.90, 0.032, 48, 6, gold, dark, DAIS_TOP + 0.245)
	_add_torus(st, _pedestal_radius_at(1.55) + 0.018, 0.022, 48, 5, gold, dark, 1.55)
	_add_torus(st, _pedestal_radius_at(1.95) + 0.018, 0.020, 48, 5, gold, dark, 1.95)
	_add_torus(st, 1.50, 0.028, 48, 6, gold, dark, 2.40)
	# 8 片花瓣的外缘包金：只在石头上做花瓣，近看是一圈奶油褶；
	# 沿外缘走一道 2cm 的金线，才有「金属包边」的工艺感。
	for i in 8:
		var angle := TAU * (float(i) + 0.25) / 8.0
		var edge: Array = []
		for k in 7:
			var v := float(k) / 6.0
			var half_width := 0.34 * sin(PI * clampf(0.20 + 0.80 * v, 0.0, 1.0))
			var center_r := lerpf(1.02, 1.90, pow(v, 0.72)) - 0.07 * sin(v * PI)
			var y := lerpf(PEDESTAL_TOP - 0.62, PEDESTAL_TOP + 0.10, pow(v, 0.92)) + 0.09 * sin(v * PI)
			var a := angle + half_width
			edge.append(Vector3(cos(a) * center_r, y, sin(a) * center_r))
		_add_tube(st, edge, 0.024, 0.014, gold, dark, 4)
	for i in 8:
		var angle := TAU * (float(i) + 0.25) / 8.0
		var point := Vector3(cos(angle) * 1.93, PEDESTAL_TOP + 0.075, sin(angle) * 1.93)
		_add_diamond(st, point, 0.13, 0.075, 0.045, -angle, gold)
	# 16 颗铆钉 + 8 片金饰。只放在台基外沿，越靠近水晶越少，避免抢晶体的亮度。
	for i in 16:
		var angle := TAU * float(i) / 16.0
		var point := Vector3(cos(angle) * 4.60, 0.255, sin(angle) * 4.60)
		_add_box(st, point, Vector3(0.14, 0.10, 0.14), -angle, gold, dark)
	for i in 8:
		var angle := TAU * (float(i) + 0.5) / 8.0
		var point := Vector3(cos(angle) * 3.44, DAIS_TOP + 0.030, sin(angle) * 3.44)
		_add_box(st, point, Vector3(0.32, 0.05, 0.17), -angle, gold, dark)
	return st.commit()

static func _pedestal_mesh(p: Dictionary) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var light: Color = p.stone_light
	var mid: Color = p.stone_mid
	var dark: Color = p.stone_dark
	var gold: Color = p.trim
	# 收分柱身。顶面留 1.04m 的托盘，主晶从它上方 0.34m 处浮起。
	var profile := [
		Vector2(0.0, DAIS_TOP), Vector2(1.78, DAIS_TOP),
		Vector2(1.84, DAIS_TOP + 0.10), Vector2(1.56, DAIS_TOP + 0.24),
		Vector2(1.42, DAIS_TOP + 0.38), Vector2(1.30, DAIS_TOP + 0.50),
		Vector2(1.22, DAIS_TOP + 0.68), Vector2(1.12, 2.28),
		Vector2(1.06, PEDESTAL_TOP - 0.46), Vector2(1.18, PEDESTAL_TOP - 0.34),
		Vector2(1.40, PEDESTAL_TOP - 0.20), Vector2(1.28, PEDESTAL_TOP - 0.08),
		Vector2(1.04, PEDESTAL_TOP), Vector2(0.0, PEDESTAL_TOP),
	]
	var colors := [
		dark, dark, mid, light, mid, light, mid, mid, light,
		gold.lerp(light, 0.35), gold, mid, light, light,
	]
	# 8 道竖棱：用顶点色压出凹槽，比额外几何便宜，俯视下也读得出「柱身不是光滑的」。
	_revolve(st, profile, colors, 40, 8, 0.055)
	# 8 片花瓣托盘：从柱身上段向外翻，把晶簇「托」起来。
	# 花瓣从 PEDESTAL_TOP-0.62 起，到顶面外沿收成尖，像一圈承重的铜花瓣。
	for i in 8:
		var angle := TAU * (float(i) + 0.25) / 8.0
		_add_petal(st, angle, 1.02, 1.90, PEDESTAL_TOP - 0.62, PEDESTAL_TOP + 0.10, 0.34, light, dark)
	# 4 条抱晶石爪：从柱身中段外翻、再向上收，像四根手指托住晶体。
	for i in 4:
		var angle := TAU * float(i) / 4.0
		var points: Array = []
		for k in 6:
			var t := float(k) / 5.0
			var radius := _claw_radius(t)
			var y := lerpf(DAIS_TOP + 0.44, PEDESTAL_TOP - 0.10, t)
			points.append(Vector3(cos(angle) * radius, y, sin(angle) * radius))
		_add_tube(st, points, 0.105, 0.042, light, gold, 5)
	return st.commit()

static func _claw_radius(t: float) -> float:
	# 先向外鼓到 1.62，再收回到 1.06：一条有张力的弧，而不是直上直下的栏杆。
	return 1.30 + 0.34 * sin(t * PI) - 0.24 * t

static func _pedestal_glow_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var y := DAIS_TOP + 0.92
	_add_torus(st, 1.205, 0.036, 48, 5, Color(1, 1, 1), Color(1, 1, 1), y)
	# 8 颗菱形符文：沿柱身一圈，近看有细节，远看是一条断续亮线。
	for i in 8:
		var angle := TAU * (float(i) + 0.5) / 8.0
		var point := Vector3(cos(angle) * 1.205, y, sin(angle) * 1.205)
		_add_diamond(st, point, 0.10, 0.16, 0.035, -angle)
	return st.commit()

static func _gem_cluster_mesh(p: Dictionary, team_color: Color) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var gradient := _gem_gradient(p)
	# 主晶：6 棱、4.35m 高。平面法线是「晶体感」的关键 —— 平滑法线会把它变成一根蓝柱子。
	# 顶点色只给「底色」：从根部的深蓝到肩部的亮青，晶尖留一点近白。
	# 亮度不靠 emission 堆，而靠太阳下的切面明暗差。
	_add_shard(st, Vector3.ZERO, GEM_HEIGHT, GEM_RADIUS, GEM_SIDES, 0.20, 0.0, 0.0, gradient, 1.0)
	# 副晶：贴着主晶下半段向上生长的细长晶柱，高度错开、粗细不同。
	# 旧版只有 3 根又短又胖的副晶，远看是「主晶下面挂了三个球」；这一版把它们拉长、收细、
	# 紧贴主晶，剪影从「一根柱子」变成「一簇往上收的晶林」。
	# 副晶根部压到托盘面（-0.28），不能跟着主晶一起悬空 —— 否则俯视下是「碎晶飘着」。
	_add_shard(st, Vector3(0.86, -0.28, 0.46), 2.86, 0.44, 5, 0.62, 0.14, -0.06, gradient, 0.94)
	_add_shard(st, Vector3(-0.82, -0.30, 0.58), 3.12, 0.40, 5, 1.06, -0.16, 0.10, gradient, 0.90)
	_add_shard(st, Vector3(0.18, -0.32, -0.90), 2.44, 0.34, 5, 0.22, 0.10, 0.14, gradient, 0.92)
	_add_shard(st, Vector3(-0.44, -0.34, -0.74), 1.72, 0.42, 5, 0.92, -0.20, -0.08, gradient, 0.82)
	_add_shard(st, Vector3(0.72, -0.36, -0.50), 1.28, 0.30, 5, 0.42, 0.18, 0.18, gradient, 0.84)
	return st.commit()

static func _gem_edges_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var white := Color(1.0, 1.0, 1.0)
	# 主晶：竖棱 + 两道腰线。腰线是「晶体在充能」的最强信号。
	_add_shard_edges(st, Vector3.ZERO, GEM_HEIGHT, GEM_RADIUS, GEM_SIDES, 0.20, 0.0, 0.0, 0.045, white, true)
	_add_shard_edges(st, Vector3(1.12, -0.30, 0.46), 2.18, 0.54, 5, 0.60, 0.26, -0.08, 0.028, white, false)
	_add_shard_edges(st, Vector3(-0.94, -0.32, 0.78), 1.78, 0.46, 5, 1.10, -0.22, 0.14, 0.025, white, false)
	_add_shard_edges(st, Vector3(0.22, -0.34, -1.08), 1.52, 0.38, 5, 0.15, 0.20, 0.18, 0.024, white, false)
	return st.commit()

## 轨道碎片单位网格：高 1.0、宽 0.48、厚 0.22 的**双尖扁晶片**（八面体刀锋）。
## 首版用 5 棱 `_add_shard` 生成的是一颗小水滴，实拍里是「六颗蓝色雨滴围着宝石」；
## 王者水晶周围飞的是碎裂的晶屑，所以改成上下两个尖 + 腰上一圈菱形，
## 再由实例的非等比 scale 压成薄片。顶点色从根部深色走到尖端亮色。
static func _orbit_shard_mesh(p: Dictionary) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var g := _gem_gradient(p)
	var deep: Color = g[0]
	var mid: Color = g[1]
	var hot: Color = g[2]
	var tip: Color = g[3]
	var w := 0.24
	var d := 0.11
	var top := Vector3(0.0, 0.62, 0.0)
	var bottom := Vector3(0.0, -0.38, 0.0)
	var left := Vector3(-w, 0.04, 0.0)
	var right := Vector3(w, 0.04, 0.0)
	var front := Vector3(0.0, 0.0, d)
	var back := Vector3(0.0, 0.0, -d)
	# hint 用面中心向量（物体中心在原点），否则平面法线可能朝内、碎片在阳光下全黑。
	_facet_tri(st, top, front, right, tip, (top + front + right) / 3.0)
	_facet_tri(st, top, right, back, hot, (top + right + back) / 3.0)
	_facet_tri(st, top, back, left, hot.lerp(mid, 0.30), (top + back + left) / 3.0)
	_facet_tri(st, top, left, front, tip.lerp(hot, 0.40), (top + left + front) / 3.0)
	_facet_tri(st, bottom, right, front, mid, (bottom + right + front) / 3.0)
	_facet_tri(st, bottom, back, right, deep.lerp(mid, 0.55), (bottom + back + right) / 3.0)
	_facet_tri(st, bottom, left, back, deep, (bottom + left + back) / 3.0)
	_facet_tri(st, bottom, front, left, mid.lerp(deep, 0.45), (bottom + front + left) / 3.0)
	return st.commit()

static func _cracks_mesh(team: String) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rng := RandomNumberGenerator.new()
	rng.seed = 8117 + (0 if team == "blue" else 977)
	var dark := Color(0.10, 0.085, 0.08, 0.96)
	for i in 7:
		var angle := TAU * (float(i) + rng.randf_range(-0.15, 0.15)) / 7.0
		var y0 := rng.randf_range(DAIS_TOP + 0.35, DAIS_TOP + 1.25)
		var y1 := y0 + rng.randf_range(0.75, 1.55)
		var points: Array = []
		var current := angle
		for k in 5:
			var t := float(k) / 4.0
			var y := lerpf(y0, y1, t)
			var radius := _pedestal_radius_at(y) + 0.012
			current += rng.randf_range(-0.18, 0.18)
			points.append(Vector3(cos(current) * radius, y, sin(current) * radius))
		for k in points.size() - 1:
			var a: Vector3 = points[k]
			var b: Vector3 = points[k + 1]
			var tangent := (b - a).normalized()
			var radial := Vector3(a.x, 0.0, a.z).normalized()
			var side := tangent.cross(radial).normalized() * 0.035
			_quad(st, a - side, a + side, b + side, b - side, dark, dark, dark, dark, radial)
	return st.commit()

## 主晶表面的裂纹。几何直接贴在 6 棱柱的斜面上 —— 用圆半径会浮在切面外，
## 所以按多边形半径公式算到「当前角度所在那一面」的平面距离，再加 12mm 偏移。
static func _gem_cracks_mesh(team: String) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rng := RandomNumberGenerator.new()
	rng.seed = 5221 + (0 if team == "blue" else 313)
	var dark := Color(0.055, 0.045, 0.055, 0.94)
	for i in 6:
		var facet := rng.randi_range(0, GEM_SIDES - 1)
		var t0 := rng.randf_range(0.16, 0.58)
		var t1 := minf(t0 + rng.randf_range(0.16, 0.34), 0.88)
		var angle := 0.20 + TAU * (float(facet) + 0.5) / float(GEM_SIDES) + rng.randf_range(-0.12, 0.12)
		var points: Array = []
		for k in 5:
			var t := lerpf(t0, t1, float(k) / 4.0)
			angle += rng.randf_range(-0.045, 0.045)
			var radius := _shard_surface_radius(t, angle) + 0.012
			points.append(Vector3(cos(angle) * radius, GEM_HEIGHT * t, sin(angle) * radius))
		_add_surface_crack(st, points, 0.026, dark)
	# 两条分叉：从主裂纹中段斜着往下裂，避免六条竖线像栅栏。
	for i in 3:
		var facet := rng.randi_range(0, GEM_SIDES - 1)
		var t0 := rng.randf_range(0.30, 0.55)
		var angle := 0.20 + TAU * (float(facet) + 0.5) / float(GEM_SIDES) + rng.randf_range(-0.10, 0.10)
		var start_r := _shard_surface_radius(t0, angle) + 0.012
		var start := Vector3(cos(angle) * start_r, GEM_HEIGHT * t0, sin(angle) * start_r)
		var points: Array = [start]
		for k in 3:
			t0 -= rng.randf_range(0.06, 0.12)
			angle += rng.randf_range(-0.16, 0.16)
			var radius := _shard_surface_radius(maxf(t0, 0.05), angle) + 0.012
			points.append(Vector3(cos(angle) * radius, GEM_HEIGHT * maxf(t0, 0.05), sin(angle) * radius))
		_add_surface_crack(st, points, 0.020, dark)
	return st.commit()

## 主晶在高度比例 t、角度 angle 处的多边形表面半径（平面切面，不是外接圆）。
static func _shard_surface_radius(t: float, angle: float) -> float:
	var rf := 0.0
	var stops := [
		[0.0, 0.0], [0.14, 0.55], [0.32, 1.0], [0.60, 0.86], [0.82, 0.46], [1.0, 0.0],
	]
	for i in stops.size() - 1:
		var a: Array = stops[i]
		var b: Array = stops[i + 1]
		if t <= float(b[0]):
			var u := (t - float(a[0])) / maxf(float(b[0]) - float(a[0]), 0.0001)
			rf = lerpf(float(a[1]), float(b[1]), clampf(u, 0.0, 1.0))
			break
	var sector := TAU / float(GEM_SIDES)
	var local := fposmod(angle - 0.20, sector) - sector * 0.5
	return GEM_RADIUS * rf * cos(sector * 0.5) / maxf(cos(local), 0.25)

static func _add_surface_crack(st: SurfaceTool, points: Array, width: float, color: Color) -> void:
	for k in points.size() - 1:
		var a: Vector3 = points[k]
		var b: Vector3 = points[k + 1]
		var tangent := (b - a).normalized()
		var radial := Vector3(a.x, 0.0, a.z).normalized()
		var side := tangent.cross(radial).normalized() * width
		_quad(st, a - side, a + side, b + side, b - side, color, color, color, color, radial)

## 柱身在某个高度的大致半径（裂纹贴合用）。分段线性，不追求和 flutes 完全一致。
static func _pedestal_radius_at(y: float) -> float:
	if y <= 1.10:
		return lerpf(1.72, 1.30, clampf((y - DAIS_TOP) / (1.10 - DAIS_TOP), 0.0, 1.0))
	if y <= 2.28:
		return lerpf(1.30, 1.12, clampf((y - 1.10) / 1.18, 0.0, 1.0))
	return lerpf(1.12, 1.04, clampf((y - 2.28) / (PEDESTAL_TOP - 2.28), 0.0, 1.0))


# ---------------------------------------------------------------------------
# 几何工具
# ---------------------------------------------------------------------------

static func _add_shard(st: SurfaceTool, base: Vector3, height: float, radius: float, sides: int, twist: float, tilt_x: float, tilt_z: float, gradient: Array, brightness: float) -> void:
	var rings := _shard_rings(base, height, radius, sides, twist, tilt_x, tilt_z)
	# rings[0] / rings[5] 是单点，1~4 是环。
	var bottom: Vector3 = rings[0][0]
	var top: Vector3 = rings[5][0]
	var body := Basis(Vector3.RIGHT, tilt_x) * Basis(Vector3.FORWARD, tilt_z)
	var axis_hint := body * Vector3.UP
	# 底部锥面
	for s in sides:
		var p0: Vector3 = rings[1][s]
		var p1: Vector3 = rings[1][(s + 1) % sides]
		var shade := _facet_shade(s, 1)
		var color := _facet_color(gradient, 0.02, shade, brightness, sin(float(s) * 2.399 + 1.7))
		_facet_tri(st, bottom, p0, p1, color, p0 + p1 - bottom * 2.0)
	# 环带。三段而不是两段：晶尖多一圈切面，俯视时不会读成一个平的白锥。
	# 每个四边形上下两端用不同色：切面内部有「从深到亮」的竖向渐变，
	# 这是晶体和塑料块最直观的区别（单色切面在阳光下一片死板）。
	for ring_index in [1, 2, 3]:
		var lower: Array = rings[ring_index]
		var upper: Array = rings[ring_index + 1]
		var t_lo: float = [0.10, 0.26, 0.58][ring_index - 1]
		var t_hi: float = [0.20, 0.50, 0.78][ring_index - 1]
		for s in sides:
			var s2 := (s + 1) % sides
			var shade := _facet_shade(s, ring_index)
			var accent := sin(float(s) * 2.399 + float(ring_index) * 1.70 + 0.45)
			var c_lo := _facet_color(gradient, t_lo, shade, brightness, accent)
			var c_hi := _facet_color(gradient, t_hi, shade, brightness, accent)
			var p0: Vector3 = lower[s]
			var p1: Vector3 = lower[s2]
			var p2: Vector3 = upper[s2]
			var p3: Vector3 = upper[s]
			var mid := (p0 + p1 + p2 + p3) * 0.25
			_quad(st, p0, p1, p2, p3, c_lo, c_lo, c_hi, c_hi, mid - Vector3(0.0, mid.y, 0.0) + axis_hint * 0.02)
	# 顶部锥面。0.90 而不是 0.94：旧版整个晶尖都取近白色，
	# 红方看起来像「红宝石上面插了一截白蜡」，阵营色在最该亮的尖端反而丢了。
	var upper_ring: Array = rings[4]
	for s in sides:
		var p0: Vector3 = upper_ring[s]
		var p1: Vector3 = upper_ring[(s + 1) % sides]
		var shade := _facet_shade(s, 4)
		var color := _facet_color(gradient, 0.90, shade, brightness, sin(float(s) * 2.399 + 5.60))
		_facet_tri(st, p0, p1, top, color, (p0 + p1) * 0.5 + axis_hint * 0.4)

static func _shard_rings(base: Vector3, height: float, radius: float, sides: int, twist: float, tilt_x: float, tilt_z: float) -> Array:
	var basis := Basis(Vector3.RIGHT, tilt_x) * Basis(Vector3.FORWARD, tilt_z)
	var specs := [
		[0.0, 0.0], [0.14, 0.55], [0.32, 1.00], [0.60, 0.86], [0.82, 0.46], [1.0, 0.0],
	]
	var rings: Array = []
	for spec in specs:
		var t := float(spec[0])
		var rf := float(spec[1])
		var ring: Array = []
		if rf <= 0.0001:
			ring.append(base + basis * Vector3(0.0, height * t, 0.0))
		else:
			for s in sides:
				var angle := TAU * float(s) / float(sides) + twist
				ring.append(base + basis * Vector3(cos(angle) * radius * rf, height * t, sin(angle) * radius * rf))
		rings.append(ring)
	return rings

static func _add_shard_edges(st: SurfaceTool, base: Vector3, height: float, radius: float, sides: int, twist: float, tilt_x: float, tilt_z: float, width: float, color: Color, belts: bool) -> void:
	var rings := _shard_rings(base, height, radius, sides, twist, tilt_x, tilt_z)
	for s in sides:
		var points: Array = [rings[0][0], rings[1][s], rings[2][s], rings[3][s], rings[4][s], rings[5][0]]
		_add_tube(st, points, width, width * 0.65, color, color, 4)
	if belts:
		for ring_index in [2, 3]:
			var ring: Array = rings[ring_index]
			var points: Array = []
			for s in sides:
				points.append(ring[s])
			points.append(ring[0])
			_add_tube(st, points, width * 0.78, width * 0.78, color, color, 4)

static func _facet_shade(index: int, ring: int) -> float:
	# 相邻面亮度差 20%~24%：太少读不出切面，太多会变成「打翻的调色盘」。
	var wave := sin(float(index) * 2.399 + float(ring) * 1.13)
	return 0.84 + 0.22 * wave

static func _gem_gradient(p: Dictionary) -> Array:
	return [
		p.get("gem_deep", Color(0.02, 0.07, 0.25)),
		p.get("gem_mid", Color(0.06, 0.26, 0.62)),
		p.get("gem_hot", Color(0.40, 0.82, 1.0)),
		p.get("gem_tip", Color(0.90, 0.98, 1.0)),
		# 第 5 色只做「相邻切面微微偏色」：统一色相的明暗差读起来像塑料，
		# 蓝里掺一点紫、红里掺一点琥珀，切面才有折射感。不参与主渐变。
		p.get("gem_accent", Color(0.50, 0.50, 1.0)),
	]

static func _facet_color(gradient: Array, t: float, shade: float, brightness: float, accent := 0.0) -> Color:
	var base: Color
	if t < 0.45:
		base = (gradient[0] as Color).lerp(gradient[1], t / 0.45)
	elif t < 0.80:
		base = (gradient[1] as Color).lerp(gradient[2], (t - 0.45) / 0.35)
	else:
		base = (gradient[2] as Color).lerp(gradient[3], (t - 0.80) / 0.20)
	if gradient.size() >= 5:
		var accent_color: Color = gradient[4]
		base = base.lerp(accent_color, clampf(0.09 + 0.07 * accent, 0.0, 0.17))
	var value := clampf(shade * brightness, 0.0, 1.35)
	return Color(clampf(base.r * value, 0.0, 1.0), clampf(base.g * value, 0.0, 1.0), clampf(base.b * value, 0.0, 1.0), 1.0)

static func _add_petal(st: SurfaceTool, angle: float, base_r: float, tip_r: float, base_y: float, top_y: float, span: float, light: Color, dark: Color) -> void:
	var cols := 3
	var rows := 4
	var grid: Array = []
	var color_grid: Array = []
	for row in rows + 1:
		var v := float(row) / float(rows)
		var half_width := span * sin(PI * clampf(0.20 + 0.80 * v, 0.0, 1.0))
		var center_r := lerpf(base_r, tip_r, pow(v, 0.72)) - 0.07 * sin(v * PI)
		var y := lerpf(base_y, top_y, pow(v, 0.92)) + 0.09 * sin(v * PI)
		var row_points: Array = []
		var row_colors: Array = []
		for col in cols + 1:
			var u := float(col) / float(cols)
			var a := angle + (u - 0.5) * 2.0 * half_width
			var radius := center_r - 0.04 * (1.0 - pow(2.0 * u - 1.0, 2.0)) * (1.0 - v)
			row_points.append(Vector3(cos(a) * radius, y + 0.03 * sin(u * PI) * (1.0 - v), sin(a) * radius))
			var edge := absf(u - 0.5) * 2.0
			row_colors.append(light.lerp(dark, 0.16 + 0.58 * edge + 0.20 * (1.0 - v)))
		grid.append(row_points)
		color_grid.append(row_colors)
	for row in rows:
		for col in cols:
			var p0: Vector3 = grid[row][col]
			var p1: Vector3 = grid[row][col + 1]
			var p2: Vector3 = grid[row + 1][col + 1]
			var p3: Vector3 = grid[row + 1][col]
			var mid := (p0 + p1 + p2 + p3) * 0.25
			_quad(st, p0, p1, p2, p3, color_grid[row][col], color_grid[row][col + 1], color_grid[row + 1][col + 1], color_grid[row + 1][col], Vector3(mid.x, 0.25, mid.z))

static func _add_box(st: SurfaceTool, center: Vector3, size: Vector3, yaw: float, top_color: Color, side_color: Color) -> void:
	var basis := Basis(Vector3.UP, yaw)
	var half := size * 0.5
	var corners: Array = []
	for i in 8:
		var sx := -1.0 if i & 1 == 0 else 1.0
		var sy := -1.0 if i & 2 == 0 else 1.0
		var sz := -1.0 if i & 4 == 0 else 1.0
		corners.append(center + basis * Vector3(half.x * sx, half.y * sy, half.z * sz))
	# corners 位掩码是 (sx, sy, sz)，所以六个面实际是：
	#   -z、+z、底、顶、-x、+x —— 只有 [2,3,7,6] 的 sy 全为 +1，才是俯视看得见的顶面。
	# 旧版把 top_color 标在了 +z 竖直侧面上，真正的顶面拿 side_color。
	# 后果：浅石板拼花在俯视实拍里变成八块深色板砖（井盖感），铜嵌条变成暗褐细线。
	# 这是几何着色 bug，不是配色问题，调颜色永远修不好。
	var faces := [
		[0, 1, 3, 2, false], [4, 6, 7, 5, false], [0, 4, 5, 1, false],
		[2, 3, 7, 6, true], [0, 2, 6, 4, false], [1, 5, 7, 3, false],
	]
	for face in faces:
		var i0 := int(face[0])
		var i1 := int(face[1])
		var i2 := int(face[2])
		var i3 := int(face[3])
		var is_top := bool(face[4])
		var color := top_color if is_top else side_color
		var hint: Vector3 = (corners[i0] + corners[i1] + corners[i2] + corners[i3]) * 0.25 - center
		_quad(st, corners[i0], corners[i1], corners[i2], corners[i3], color, color, color, color, hint)

static func _add_torus(st: SurfaceTool, radius: float, tube: float, segments: int, sides: int, color_a: Color, color_b: Color, center_y := 0.0) -> void:
	var rings: Array = []
	for s in segments:
		var angle := TAU * float(s) / float(segments)
		var center := Vector3(cos(angle) * radius, center_y, sin(angle) * radius)
		var tangent := Vector3(-sin(angle), 0.0, cos(angle))
		var radial := Vector3(cos(angle), 0.0, sin(angle))
		var ring: Array = []
		for k in sides:
			var a := TAU * float(k) / float(sides)
			ring.append(center + radial * cos(a) * tube + Vector3.UP * sin(a) * tube)
		rings.append(ring)
	for s in segments:
		var s2 := (s + 1) % segments
		var color := color_a if s % 4 == 0 else color_b
		for k in sides:
			var k2 := (k + 1) % sides
			var p0: Vector3 = rings[s][k]
			var p1: Vector3 = rings[s][k2]
			var p2: Vector3 = rings[s2][k2]
			var p3: Vector3 = rings[s2][k]
			var mid := (p0 + p1 + p2 + p3) * 0.25
			var radial := Vector3(mid.x, 0.0, mid.z)
			radial = radial.normalized() if radial.length() > 0.0001 else Vector3.RIGHT
			var hint := mid - (radial * radius + Vector3(0.0, center_y, 0.0))
			_quad(st, p0, p1, p2, p3, color, color, color, color, hint)

static func _add_diamond(st: SurfaceTool, center: Vector3, half_w: float, half_h: float, half_d: float, yaw: float, color := Color(1.0, 1.0, 1.0)) -> void:
	var basis := Basis(Vector3.UP, yaw)
	var top := center + Vector3.UP * half_h
	var bottom := center - Vector3.UP * half_h
	var left := center + basis * Vector3(-half_w, 0.0, 0.0)
	var right := center + basis * Vector3(half_w, 0.0, 0.0)
	var front := center + basis * Vector3(0.0, 0.0, half_d)
	var back := center + basis * Vector3(0.0, 0.0, -half_d)
	_facet_tri(st, top, left, front, color, center)
	_facet_tri(st, top, front, right, color, center)
	_facet_tri(st, top, right, back, color, center)
	_facet_tri(st, top, back, left, color, center)
	_facet_tri(st, bottom, front, left, color, center)
	_facet_tri(st, bottom, right, front, color, center)
	_facet_tri(st, bottom, back, right, color, center)
	_facet_tri(st, bottom, left, back, color, center)

static func _facet_tri(st: SurfaceTool, p0: Vector3, p1: Vector3, p2: Vector3, color: Color, hint: Vector3) -> void:
	var normal := (p1 - p0).cross(p2 - p0)
	if normal.length_squared() < 0.0000000001:
		return
	normal = normal.normalized()
	if normal.dot(hint) < 0.0:
		normal = -normal
	_put(st, p0, normal, color)
	_put(st, p1, normal, color)
	_put(st, p2, normal, color)

static func _facet_quad(st: SurfaceTool, p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, color: Color, hint: Vector3) -> void:
	var normal := (p1 - p0).cross(p2 - p0)
	if normal.length_squared() < 0.0000000001:
		normal = (p2 - p0).cross(p3 - p0)
	if normal.length_squared() < 0.0000000001:
		return
	normal = normal.normalized()
	if normal.dot(hint) < 0.0:
		normal = -normal
	_put(st, p0, normal, color)
	_put(st, p1, normal, color)
	_put(st, p2, normal, color)
	_put(st, p0, normal, color)
	_put(st, p2, normal, color)
	_put(st, p3, normal, color)

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

static func _revolve(st: SurfaceTool, profile: Array, colors: Array, segments: int, flutes := 0, flute_depth := 0.0) -> void:
	for i in profile.size() - 1:
		var lo: Vector2 = profile[i]
		var hi: Vector2 = profile[i + 1]
		if absf(lo.y - hi.y) < 0.000001 and absf(lo.x - hi.x) < 0.000001:
			continue
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
			_quad(st, p0, p1, p2, p3, _groove(c_lo, a0, flutes, colors[colors.size() - 1]), _groove(c_lo, a1, flutes, colors[colors.size() - 1]), _groove(c_hi, a1, flutes, colors[colors.size() - 1]), _groove(c_hi, a0, flutes, colors[colors.size() - 1]), hint)

static func _groove(base: Color, angle: float, flutes: int, dark: Color) -> Color:
	if flutes <= 0:
		return base
	return base.lerp(dark, 0.50 * clampf(-cos(float(flutes) * angle), 0.0, 1.0))

static func _add_tube(st: SurfaceTool, points: Array, radius_start: float, radius_end: float, color_start: Color, color_end: Color, sides: int) -> void:
	if points.size() < 2:
		return
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


# ---------------------------------------------------------------------------
# 材质
# ---------------------------------------------------------------------------

static func _stone_material(p: Dictionary, transparent: bool) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.albedo_color = Color(1.0, 1.0, 1.0, 1.0)
	material.roughness = 0.88
	material.metallic = 0.0
	material.metallic_specular = 0.16
	# 程序化石纹：没有贴图的纯顶点色台基在近景里像一块磨砂塑料。
	# 一张 128² 的灰度噪声 + 三平面映射，给石材一层不依赖 UV 的细颗粒。
	material.albedo_texture = _stone_grain()
	material.uv1_triplanar = true
	material.uv1_scale = Vector3(0.42, 0.42, 0.42)
	# 花瓣是单面片；关掉背面剔除才不会有「半片花瓣消失」。
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	if transparent:
		# 常驻 ALPHA：OcclusionFade 只改 albedo.a，运行时切档会重建管线。
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return material

static var _stone_grain_texture: ImageTexture

## 灰度石纹。只生成一次，所有阵营/所有主堡共用 —— 它只给表面加颗粒，
## 阵营色仍然由顶点色决定，不能被这张图染色。
static func _stone_grain() -> ImageTexture:
	if _stone_grain_texture != null:
		return _stone_grain_texture
	var noise := FastNoiseLite.new()
	noise.seed = 7311
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise.frequency = 0.055
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves = 3
	var image := Image.create(128, 128, false, Image.FORMAT_L8)
	for y in 128:
		for x in 128:
			var n := noise.get_noise_2d(float(x), float(y))
			var v := clampf(0.86 + 0.14 * n, 0.0, 1.0)
			image.set_pixel(x, y, Color(v, v, v))
	image.generate_mipmaps()
	_stone_grain_texture = ImageTexture.create_from_image(image)
	return _stone_grain_texture

static func _metal_material(transparent: bool) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.albedo_color = Color(1.0, 1.0, 1.0, 1.0)
	# 兼容渲染器没有反射探针，metallic 0.62 的金饰会把天空反射成一块黑褐木牌。
	# 低金属度 + 高镜面 + 中低粗糙度：靠太阳高光读出「抛光金」，暗面仍是暖褐色。
	material.roughness = 0.32
	material.metallic = 0.18
	material.metallic_specular = 0.92
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	if transparent:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return material

## 悬浮能量环专用：环体暗面占了大半，gl_compatibility 下又没有反射探针，
## 纯金属材质在远景里就是一圈黑铁丝（首版实拍的最大负分）。
## 掺 42% 暖金保留「金属构件」的读感，掺 58% 队伍色 + 0.95 自发光让它真的亮起来。
static func _ring_body_material(team_color: Color, p: Dictionary) -> StandardMaterial3D:
	var material := _metal_material(false)
	material.emission_enabled = true
	var gold: Color = p.get("trim", Color(0.68, 0.48, 0.18))
	material.emission = team_color.lerp(gold, 0.42)
	material.emission_energy_multiplier = 0.95
	return material

## 轨道碎片比本体亮一档：0.5m 的晶屑用 0.38 emission 在 21 米机位下只剩深色小点。
static func _shard_material(team_color: Color) -> StandardMaterial3D:
	var material := _gem_material(team_color)
	material.emission_energy_multiplier = 0.92
	material.rim = 0.85
	return material

## 能量外壳。所有状态量都显式给初值，apply_state 逐帧覆盖，不依赖 shader 默认值。
static func _energy_material(team_color: Color, p: Dictionary) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = ENERGY_SHADER
	material.set_shader_parameter("energy_color", Color(team_color.r, team_color.g, team_color.b, 1.0))
	var hot: Color = p.get("gem_hot", Color(0.6, 0.9, 1.0))
	material.set_shader_parameter("hot_color", hot.lerp(Color(1.0, 1.0, 1.0), 0.35))
	material.set_shader_parameter("phase", 0.0)
	material.set_shader_parameter("intensity", 1.0)
	material.set_shader_parameter("damage", 0.0)
	material.set_shader_parameter("fade_alpha", 1.0)
	# 主体 gem 是 2、裂纹是 4：加色壳必须夹在两者之间。
	material.render_priority = 3
	return material

static func _gem_material(team_color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.albedo_color = Color(1.0, 1.0, 1.0, 1.0)
	# 晶体：低粗糙度 + 中金属度 = 切面有清晰的明暗跳变，不是塑料球。
	material.roughness = 0.10
	material.metallic = 0.22
	material.metallic_specular = 0.95
	material.rim_enabled = true
	material.rim = 0.55
	material.rim_tint = 0.22
	material.backlight_enabled = true
	material.backlight = team_color.lerp(Color(1.0, 1.0, 1.0), 0.35)
	material.emission_enabled = true
	material.emission = team_color
	# 旧版 1.55 把整颗晶体烧成白柱：切面颜色全部落在色调映射的高光肩部。
	# 0.38 只给暗面留一层「它在发光」的底，亮面交给太阳与边缘光。
	material.emission_energy_multiplier = 0.38
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	# 让透明晶体在水晶光柱之前画，减少「光柱压在水晶上」的排序错误。
	material.render_priority = 2
	return material

static func _additive_material(color: Color, alpha: float, energy: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.albedo_color = Color(color.r, color.g, color.b, alpha)
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = energy
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	# 贴地加色层不写深度：写深度会切掉它后面的草叶。
	material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	return material

static func _crack_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(0.10, 0.085, 0.08, 0.96)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	# 晶体本体 render_priority=2；裂纹必须排在它之后，否则会被半透明晶体盖掉。
	material.render_priority = 4
	return material

static func _sigil_material(team_color: Color) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = SIGIL_SHADER
	# 0.55 而不是 0.78：法阵是「地面上的纹章」，不能比水晶本体更亮。
	material.set_shader_parameter("sigil_color", Color(team_color.r, team_color.g, team_color.b, 0.55))
	material.set_shader_parameter("hot_color", team_color.lerp(Color(1.0, 1.0, 1.0), 0.62))
	material.set_shader_parameter("spin", 0.0)
	material.set_shader_parameter("active", 1.0)
	material.set_shader_parameter("intensity", 1.0)
	material.set_shader_parameter("damage", 0.0)
	material.set_shader_parameter("shield", 0.0)
	material.set_shader_parameter("band_gain", 0.50)
	return material

static func _beam_material(team_color: Color, alpha: float, hot_color: Color, fade_start: float, mote_gain: float) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = BEAM_SHADER
	material.set_shader_parameter("beam_color", Color(team_color.r, team_color.g, team_color.b, alpha))
	material.set_shader_parameter("hot_color", hot_color)
	material.set_shader_parameter("intensity", 1.0)
	material.set_shader_parameter("fade_start", fade_start)
	material.set_shader_parameter("mote_gain", mote_gain)
	return material

static func _shield_material(team_color: Color) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = SHIELD_SHADER
	material.set_shader_parameter("shield_color", Color(team_color.r, team_color.g, team_color.b, 1.0))
	# 边缘只提亮 20%：首版 45% 把红方护盾洗成一颗米白肥皂泡，阵营色全丢。
	material.set_shader_parameter("edge_color", team_color.lerp(Color(1.0, 1.0, 1.0), 0.20))
	material.set_shader_parameter("intensity", 1.0)
	material.set_shader_parameter("strength", 1.0)
	material.set_shader_parameter("pulse", 0.0)
	return material


# ---------------------------------------------------------------------------
# 网格缓存（只缓存几何，不缓存会被淡化改 alpha 的材质）
# ---------------------------------------------------------------------------

## 几何按 `key` 复用：网格只含顶点/法线/顶点色，和材质完全解耦，跨局复用安全。
## 键里带阵营：石材顶点色写在几何里，蓝/红不能共用同一个 ArrayMesh。
static func _cached(key: String, factory: Callable) -> Mesh:
	var mesh: Mesh = _meshes.get(key, null)
	if mesh == null:
		mesh = factory.call()
		_meshes[key] = mesh
	return mesh

static func _ring_mesh(radius: float, tube: float, segments: int, sides: int, p: Dictionary, runes := 0) -> ArrayMesh:
	var key := "ring|%.3f|%.3f|%d|%d|%s|%d" % [radius, tube, segments, sides, str(p.get("trim", Color.WHITE)), runes]
	var mesh: ArrayMesh = _meshes.get(key, null)
	if mesh == null:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var gold: Color = p.get("trim", Color(0.72, 0.58, 0.30))
		var dark: Color = p.get("trim_dark", Color(0.40, 0.30, 0.14))
		_add_torus(st, radius, tube, segments, sides, gold, dark)
		if runes > 0:
			# 等距符文嵌在环线上：远景是「一圈断续亮刻度」，
			# 近景能看出环在转（纯色圆环旋转时是看不出转速的）。
			for i in runes:
				var a := TAU * float(i) / float(runes)
				var point := Vector3(cos(a) * radius, 0.0, sin(a) * radius)
				_add_diamond(st, point, tube * 1.7, tube * 3.2, tube * 1.7, -a, gold.lerp(Color.WHITE, 0.55))
		mesh = st.commit()
		_meshes[key] = mesh
	return mesh

static func _beam_mesh(top_radius: float, bottom_radius: float, height: float) -> CylinderMesh:
	var key := "beam|%.3f|%.3f|%.3f" % [top_radius, bottom_radius, height]
	var mesh: CylinderMesh = _meshes.get(key, null)
	if mesh == null:
		mesh = CylinderMesh.new()
		mesh.top_radius = top_radius
		mesh.bottom_radius = bottom_radius
		mesh.height = height
		mesh.radial_segments = 28
		mesh.rings = 1
		mesh.cap_top = false
		mesh.cap_bottom = false
		_meshes[key] = mesh
	return mesh

static func _plane_mesh(size: float) -> PlaneMesh:
	var key := "plane|%.3f" % size
	var mesh: PlaneMesh = _meshes.get(key, null)
	if mesh == null:
		mesh = PlaneMesh.new()
		mesh.size = Vector2(size, size)
		mesh.subdivide_width = 0
		mesh.subdivide_depth = 0
		_meshes[key] = mesh
	return mesh

static func _halo_mesh() -> TorusMesh:
	var key := "halo|torus"
	var mesh: TorusMesh = _meshes.get(key, null)
	if mesh == null:
		mesh = TorusMesh.new()
		# 细环而不是宽盘：旧版内外半径差 0.27，斜放后是一圈半透明雾带，
		# 在水晶腰上糊出一条浅蓝色横带。0.10 的环宽才读成「悬浮的金环」。
		mesh.inner_radius = 1.94
		mesh.outer_radius = 2.04
		mesh.rings = 48
		mesh.ring_segments = 6
		_meshes[key] = mesh
	return mesh

static func _shield_mesh() -> SphereMesh:
	var key := "shield|sphere"
	var mesh: SphereMesh = _meshes.get(key, null)
	if mesh == null:
		mesh = SphereMesh.new()
		mesh.radius = SHIELD_RADIUS
		mesh.height = SHIELD_RADIUS * 2.0
		mesh.radial_segments = 40
		mesh.rings = 20
		_meshes[key] = mesh
	return mesh

static func mesh_count() -> int:
	return _meshes.size()

static func _with_alpha(color: Color, alpha: float) -> Color:
	return Color(color.r, color.g, color.b, alpha)
