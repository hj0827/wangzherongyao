extends RefCounted
class_name PortalVisual

## 河道传送阵的**造型与状态表现**（2026-11-11 升级）。
##
## 旧版是两个 `_add_map_disc` 圆片 + 一根 `_add_map_totem` 灰杆：
## 俯视下就是「一块青色薄饼 + 一根路灯」，和营地圆盘长得几乎一样，
## 玩家读不出「这个角落是传送阵」，更读不出「现在有人正在这里读条」。
##
## 这一版把传送阵当成一个**独立设施**来建（和 TowerVisual / MonsterForms 同一分工）：
##   Arena 只负责给它世界坐标和朝向，形态与状态语义全部收在这里。
##
## 造型四件套（都由基本体拼装，不引资产、不加 draw call 预算以外的开销）：
##   ① 石台：三层收分的圆台，外沿一圈高低交替的缘石 —— 读成「一块砌起来的阵台」；
##   ② 符文轮：贴地平面 + `teleport_rune.gdshader`，会转、会扫、会呼吸（唯一的活动层）；
##   ③ 三根方尖柱：沿角落方向散开 120°，缺口正对从兵线走过来的那一面；
##   ④ 浮空晶体：柱顶悬着、上下浮、随引导变亮 —— 远景下它是这处设施的「信号灯」。
##
## 契约（测试会逐条抓）：
##   - `DAIS_RADIUS` 必须等于 `MapLayout.PAD_DISC_RADIUS`：**看着站在石台上 = 判定在阵里**。
##     两处各写一个 3.0 的下场是「人站在石台边缘，按下去没反应」；
##   - 三根石柱全部在阵盘**之外**：英雄站在阵心读条时不能被自己脚下的柱子挡住；
##   - 引导进度读的是**快照里英雄的位置**，不是 pad id —— 快照白名单里没有 `teleport_pad`，
##     而引导期间英雄不能移动，所以位置就是阵心，主客机用同一份数据（见 `charge_from_entities`）；
##   - 状态与外观之间隔着纯函数（`charge_from_entities` / `flash_envelope` /
##     `shatter_envelope` / `spin_rate` / `crystal_energy` / `light_energy`），
##     headless 能直接断言「读了多久 = 亮到什么程度」，而不是靠截图目测。

const MapLayout = preload("res://sim/map/map_layout.gd")

const RUNE_SHADER := preload("res://shaders/teleport_rune.gdshader")

## 阵盘半径 = 传送判定半径。唯一真身在 MapLayout，这里只是给它一个语义名。
const DAIS_RADIUS := MapLayout.PAD_DISC_RADIUS
## 符文轮半径。比阵盘小一圈：外沿要留给缘石，符文压到缘石底下会被切成断线。
const RUNE_RADIUS := 2.70
## 石柱离阵心的距离。必须 > DAIS_RADIUS，否则柱子会立在判定区内挡住读条的英雄。
const PILLAR_RADIUS := 3.42
const PILLAR_COUNT := 3
const STUD_COUNT := 12
const STUD_RADIUS := 2.86
## 地面光池半径：比阵盘大一圈，于是露出来的那一圈才是「光溢出到草地上」。
const AURA_RADIUS := 3.55

## 引导进度向上/向下收敛的速度（每秒）。模拟层 2.5 秒读完，2.4 让法阵比读条稍微慢半拍，
## 收尾时才不会「读条结束、阵还亮着最后一格」。
const CHARGE_RATE := 2.4
const FLASH_SECONDS := 0.55
const SHATTER_SECONDS := 0.42
## 静止时的自转与呼吸。没有这两个，阵就是一张贴图：圆环各向同性，不转也看不出来。
const IDLE_SPIN := 0.55
const CHARGE_SPIN := 2.35
const IDLE_PULSE := 0.42
const CHARGE_PULSE := 1.15

## 晶体基准自发光。压得比野怪水晶低一档：阵是常驻设施，太亮会在 bloom 下糊成白斑。
const CRYSTAL_ENERGY := 1.15
const CRYSTAL_CHARGE_ENERGY := 2.60
const LIGHT_IDLE := 0.0
const LIGHT_CHARGE := 2.10

## 石料四档。**分两层语言**，这是看实拍图 + 量像素改出来的（别凭手感推翻）：
##   - 外圈台基用浅砌石，和塔/基地读成同一套人造砌石语言；
##   - 台面（符文那一层）必须**真的暗**。加法混合的阵纹叠在亮石板上会被推成纯白 ——
##     实测第一版台面 albedo 0.255 经 FILMIC + 曝光 1.05 + 晴朗主光后落到 175/255，
##     读条将满时整块盘面 255/255 全白，符文和底色糊成一片，什么都读不出来。
## 这和野怪石身「基色要压到 0.1~0.3」是同一条口径，只是这里还要再低一档：
## 阵纹本身是加色的，底色只能做减法。
const STONE_LIGHT := Color(0.46, 0.450, 0.425)
const STONE_MID := Color(0.330, 0.322, 0.302)
const STONE_DARK := Color(0.215, 0.210, 0.198)
## 台面专用：整座阵里最暗的一块。
## 实测口径（别再往上抬到发白、也别再往下压到发黑）：
##   0.055 时台面实测 luminance ≈ 41，而阵外草地 ≈ 178 —— 那不是「深色石板」，
##   是草地上一个洞，玩家第一眼读成「坑」而不是「设施」。0.115 落到 ≈ 60，
##   既保住了符文需要的对比，又让台面仍然读得出是石头。
## 深蓝灰而不是中性灰：中性灰的暗色会和草地阴影像，深蓝灰才能让
## 「青色符文 + 蓝色光池」在同一块底上形成同色系的层次。
const DECK_STONE := Color(0.105, 0.118, 0.145)

static var _materials: Dictionary = {}
static var _meshes: Dictionary = {}

# ---------------------------------------------------------------------------
# 纯函数：状态 → 外观
# ---------------------------------------------------------------------------

## 引导进度：快照里正在这个阵上读条的英雄读了多少。
## 没有 pad id 可用（快照白名单里没有），所以按**位置**判定，口径与 Teleport.pad_at 一致。
static func charge_from_entities(entities: Array, pad_center: Vector2, radius := DAIS_RADIUS) -> float:
	var best := 0.0
	for entity in entities:
		if not (entity is Dictionary):
			continue
		var hero: Dictionary = entity
		if str(hero.get("type", "")) != "hero":
			continue
		if not bool(hero.get("alive", true)):
			continue
		if not bool(hero.get("teleporting", false)):
			continue
		var total := float(hero.get("teleport_total", 0.0))
		if total <= 0.0:
			continue
		var point := Vector2(float(hero.get("x", 0.0)), float(hero.get("y", 0.0)))
		if point.distance_to(pad_center) > radius:
			continue
		best = maxf(best, clampf(1.0 - float(hero.get("teleport_timer", 0.0)) / total, 0.0, 1.0))
	return best

## 落地/抵达闪光：起手最亮，二次方衰减 —— 线性衰减在最后三分之一段看起来是「一直亮着」。
static func flash_envelope(elapsed: float) -> float:
	if elapsed < 0.0 or elapsed >= FLASH_SECONDS:
		return 0.0
	var t := elapsed / FLASH_SECONDS
	var fade := 1.0 - t
	return fade * fade

## 打断：比闪光更快，只在头两帧最明显 —— 语义是「啪地断掉」，不是「慢慢暗下去」。
static func shatter_envelope(elapsed: float) -> float:
	if elapsed < 0.0 or elapsed >= SHATTER_SECONDS:
		return 0.0
	var t := elapsed / SHATTER_SECONDS
	var fade := 1.0 - t
	return fade * fade * fade

## 自转角速度。引导越久转得越急：静止时是「设施在待机」，读条时是「机器在抽能」。
static func spin_rate(charge: float) -> float:
	return IDLE_SPIN + (CHARGE_SPIN - IDLE_SPIN) * clampf(charge, 0.0, 1.0)

## 呼吸频率（每秒周期数）。同样随引导加快。
static func pulse_rate(charge: float) -> float:
	return IDLE_PULSE + (CHARGE_PULSE - IDLE_PULSE) * clampf(charge, 0.0, 1.0)

static func crystal_energy(charge: float, flash: float) -> float:
	var hot := clampf(charge, 0.0, 1.0)
	return CRYSTAL_ENERGY + (CRYSTAL_CHARGE_ENERGY - CRYSTAL_ENERGY) * hot + 2.4 * clampf(flash, 0.0, 1.0)

## 点光源亮度。静止时恒为 0：两盏常亮的点光在移动端是最先吃掉帧预算的东西之一。
static func light_energy(charge: float, flash: float) -> float:
	var hot := clampf(charge, 0.0, 1.0)
	return LIGHT_IDLE + (LIGHT_CHARGE - LIGHT_IDLE) * hot + 1.8 * clampf(flash, 0.0, 1.0)

## 缘石到底是「死石头」还是「会亮的齿」：只在引导时抬自发光，静止时完全不亮，
## 于是「这座阵有人在读条」在余光里也抓得住。
static func stud_energy(charge: float) -> float:
	return 1.9 * clampf(charge, 0.0, 1.0)

# ---------------------------------------------------------------------------
# 造型
# ---------------------------------------------------------------------------

## 建一座阵。`gate_angle` 是「朝地图角落」的弧度：三根柱沿它散开，
## 中间那个缺口自然正对着从兵线走进来的方向。
static func build(color: Color, gate_angle := 0.0) -> Dictionary:
	var root := Node3D.new()
	root.name = "Portal"
	var light_mat := stone_material(STONE_LIGHT)
	var mid_mat := stone_material(STONE_MID)
	var crystal_mat := crystal_material(color)
	var stud_mat := stud_material(color)

	# --- ① 石台：三层收分 ---------------------------------------------------
	# 底层压在草面上（0.04），每上一层收 0.12~0.20 米并抬 0.06，读成砌起来的台阶。
	_add(root, _disc_mesh(DAIS_RADIUS), light_mat, Vector3(0.0, 0.06, 0.0))
	_add(root, _disc_mesh(DAIS_RADIUS - 0.16, 0.09), mid_mat, Vector3(0.0, 0.145, 0.0))
	# 台面：刻意压暗一档，符文才有对比。压暗交给**石料颜色**而不是 shader ——
	# 加法混合的阵纹不需要"底色被减暗"，需要的是"底色别抢戏"。
	_add(root, _disc_mesh(RUNE_RADIUS + 0.06, 0.05), stone_material(DECK_STONE), Vector3(0.0, 0.205, 0.0))

	# --- 缘石：高低交替的 12 块齿石 -----------------------------------------
	# 等高会读成「齿轮」，高低交替才像「一圈人工凿出来的阵沿」。
	for i in STUD_COUNT:
		var a := TAU * float(i) / float(STUD_COUNT)
		var tall := i % 2 == 0
		var size := Vector3(0.20, 0.24 if tall else 0.15, 0.34)
		_add(
			root,
			_box_mesh(size),
			stud_mat,
			Vector3(cos(a) * STUD_RADIUS, 0.12 + size.y * 0.5, sin(a) * STUD_RADIUS),
			Vector3(0.0, -rad_to_deg(a), 0.0)
		)

	# --- ② 符文轮 -----------------------------------------------------------
	var rune_material := ShaderMaterial.new()
	rune_material.shader = RUNE_SHADER
	rune_material.set_shader_parameter("rune_color", Color(color.r, color.g, color.b, 0.92))
	rune_material.set_shader_parameter("hot_color", Color(0.90, 0.99, 1.0, 1.0))
	rune_material.set_shader_parameter("charge", 0.0)
	rune_material.set_shader_parameter("spin", 0.0)
	rune_material.set_shader_parameter("pulse", 0.0)
	rune_material.set_shader_parameter("flash", 0.0)
	rune_material.set_shader_parameter("shatter", 0.0)
	rune_material.set_shader_parameter("intensity", 1.0)
	var rune := _add(root, _plane_mesh(RUNE_RADIUS * 2.0), rune_material, Vector3(0.0, 0.238, 0.0))
	rune.name = "Rune"
	rune.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	# --- ③ 三根方尖柱 -------------------------------------------------------
	var crystals: Array[Node3D] = []
	var pillars: Array[Node3D] = []
	for i in PILLAR_COUNT:
		# 缺口留给「朝地图中心」那一面：柱子排在 gate 方向 ±120°，正中那个空档就是入口。
		var angle := gate_angle + TAU * float(i) / float(PILLAR_COUNT)
		var node := _build_pillar(root, angle, mid_mat, light_mat, crystal_mat)
		pillars.append(node)
		var crystal := node.get_node_or_null(NodePath("Crystal")) as Node3D
		if crystal != null:
			crystals.append(crystal)

	# --- ④ 地面光池 ---------------------------------------------------------
	# 加色圆盘压在石台底下，露出来的是阵沿外那 0.55 米 —— 光从石缝里渗到草地上。
	var aura_material := add_material(color, 0.26)
	var aura := _add(root, _disc_mesh(AURA_RADIUS, 0.02), aura_material, Vector3(0.0, 0.035, 0.0))
	aura.name = "Aura"
	aura.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	# --- 点光源：只在引导/闪光时点亮 ----------------------------------------
	var light := OmniLight3D.new()
	light.name = "Light"
	light.position = Vector3(0.0, 1.30, 0.0)
	light.light_color = color
	light.omni_range = 9.0
	light.light_energy = LIGHT_IDLE
	light.shadow_enabled = false
	root.add_child(light)

	return {
		"root": root,
		"pad_id": "",
		"center": Vector2.ZERO,
		"rune": rune,
		"rune_material": rune_material,
		"pillars": pillars,
		"crystals": crystals,
		"crystal_material": crystal_mat,
		"stud_material": stud_mat,
		"aura": aura,
		"aura_material": aura_material,
		"light": light,
		"color": color,
		# 运行态
		"charge": 0.0,
		"spin": 0.0,
		"pulse": 0.0,
		"flash_elapsed": INF,
		"shatter_elapsed": INF,
	}

static func _build_pillar(root: Node3D, angle: float, mid_mat: Material, light_mat: Material, crystal_mat: Material) -> Node3D:
	var node := Node3D.new()
	node.name = "Pillar"
	node.position = Vector3(cos(angle) * PILLAR_RADIUS, 0.0, sin(angle) * PILLAR_RADIUS)
	node.rotation.y = -angle
	root.add_child(node)
	# 柱基：略宽于柱身，把柱子「压」在草地上而不是插进去。
	_add(node, _disc_mesh(0.42, 0.30), mid_mat, Vector3(0.0, 0.15, 0.0))
	# 柱身：六棱、上细下粗。圆的细杆在俯视下是一条同宽的灰影，读成塑料管。
	_add(node, _cylinder_mesh(0.155, 0.235, 1.72, 6), light_mat, Vector3(0.0, 1.16, 0.0))
	# 两道石箍：一根光杆不管多粗都读成「路牌」，有箍才有分段。
	_add(node, _cylinder_mesh(0.26, 0.26, 0.10, 6), mid_mat, Vector3(0.0, 0.82, 0.0))
	_add(node, _cylinder_mesh(0.225, 0.225, 0.09, 6), mid_mat, Vector3(0.0, 1.66, 0.0))
	# 柱顶托盘 + 晶体底座。
	_add(node, _cylinder_mesh(0.30, 0.19, 0.14, 6), mid_mat, Vector3(0.0, 2.09, 0.0))
	# 晶体：上下两个锥台对接的六棱双锥（八面体拉长），天然有一条腰棱。
	# 不能只用一个 PrismMesh / 圆锥：那种尖顶在 bloom 下就是一个白点，
	# 和「一颗被供在柱顶的能量结晶」读起来完全是两回事 —— 有腰棱才有体积感。
	var crystal := Node3D.new()
	crystal.name = "Crystal"
	crystal.position = Vector3(0.0, 2.62, 0.0)
	crystal.set_meta("rest_y", 2.62)
	node.add_child(crystal)
	# 下半：向上收窄到腰（0.20 → 0.26）。
	_add(crystal, _cylinder_mesh(0.26, 0.10, 0.30, 6), crystal_mat, Vector3(0.0, -0.15, 0.0))
	# 上半：从腰收成尖顶。高度刻意比下半长，读成「越往上越尖」。
	_add(crystal, _cylinder_mesh(0.0, 0.26, 0.46, 6), crystal_mat, Vector3(0.0, 0.23, 0.0))
	return node

# ---------------------------------------------------------------------------
# 每帧驱动
# ---------------------------------------------------------------------------

## 把「目标引导进度 + 时间」推到节点上。`delta` 由 Arena 每帧传入。
## 这里只改材质参数、节点位置与灯能量 —— 不新建任何节点（硬规则 4）。
static func apply_state(record: Dictionary, target_charge: float, delta: float) -> void:
	if record.is_empty():
		return
	var charge := move_toward(float(record.get("charge", 0.0)), clampf(target_charge, 0.0, 1.0), delta * CHARGE_RATE)
	record["charge"] = charge
	var spin := float(record.get("spin", 0.0)) + delta * spin_rate(charge)
	record["spin"] = fmod(spin, TAU)
	var pulse := fmod(float(record.get("pulse", 0.0)) + delta * pulse_rate(charge), 1.0)
	record["pulse"] = pulse

	var flash_elapsed := float(record.get("flash_elapsed", INF)) + delta
	record["flash_elapsed"] = flash_elapsed
	var flash := flash_envelope(flash_elapsed)
	var shatter_elapsed := float(record.get("shatter_elapsed", INF)) + delta
	record["shatter_elapsed"] = shatter_elapsed
	var shatter := shatter_envelope(shatter_elapsed)

	var material := record.get("rune_material") as ShaderMaterial
	if material != null:
		material.set_shader_parameter("charge", charge)
		material.set_shader_parameter("spin", spin)
		material.set_shader_parameter("pulse", 0.5 + 0.5 * sin(pulse * TAU))
		material.set_shader_parameter("flash", flash)
		material.set_shader_parameter("shatter", shatter)

	# 晶体：上下浮 + 自转 + 变亮。幅度随引导加大，于是「有人在读条」还能从柱顶上读出来。
	var bob := sin(pulse * TAU) * (0.045 + 0.055 * charge)
	var energy := crystal_energy(charge, flash)
	for crystal in record.get("crystals", []):
		var node := crystal as Node3D
		if node == null:
			continue
		var rest := float(node.get_meta("rest_y", node.position.y))
		node.position.y = rest + bob
		node.rotation.y += delta * (0.6 + 2.2 * charge)
	# 自发光是**共用一份材质**（见 crystal_material 的静态缓存），所以只写一次。
	# 逐颗写会有两个后果：三颗永远同亮（本来也是）、以及每帧三次无意义的赋值。
	var crystal_mat := record.get("crystal_material") as StandardMaterial3D
	if crystal_mat != null:
		crystal_mat.emission_energy_multiplier = energy

	var light := record.get("light") as OmniLight3D
	if light != null:
		light.light_energy = light_energy(charge, flash)

	var stud_material := record.get("stud_material") as StandardMaterial3D
	if stud_material != null:
		stud_material.emission_energy_multiplier = stud_energy(charge)

	var aura_material := record.get("aura_material") as StandardMaterial3D
	if aura_material != null:
		var origin: Color = record.get("color", Color(0.36, 0.84, 0.98))
		var breathe := 0.5 + 0.5 * sin(pulse * TAU)
		aura_material.albedo_color = Color(
			origin.r, origin.g, origin.b,
			(0.13 + 0.16 * charge + 0.30 * flash) * (0.75 + 0.25 * breathe)
		)

# ---------------------------------------------------------------------------
# 材质与网格缓存
# ---------------------------------------------------------------------------
#
# 两座阵在同屏，材质/网格复用看起来"不必省"，但这条纪律是**入口**：
# 以后如果加第三、第四座阵（或者做成可破坏设施反复重建），逐座 new 就会变成
# 每局几十次资源分配。缓存键只包含真正影响外观的参数，缩放一律放在节点上。

static func stone_material(color: Color) -> StandardMaterial3D:
	var key := "stone|%s" % color.to_html(false)
	var material: StandardMaterial3D = _materials.get(key, null)
	if material == null:
		material = StandardMaterial3D.new()
		material.albedo_color = color
		# 粗糙度拉满、高光压小：默认高光会让石头读成塑料（和野怪石身同一条口径）。
		# 注意属性名是 `metallic_specular`（Godot 4），写 `specular` 不报错但参数被丢掉，
		# 石头会带着默认 0.5 的镜面反射，俯视下每一步台阶上都是一条塑料高光。
		material.roughness = 0.94
		material.metallic = 0.0
		material.metallic_specular = 0.1
		_materials[key] = material
	return material

## 缘石：石头底子 + 可驱动的自发光。引导时整圈抬亮，静止时自发光为 0。
static func stud_material(color: Color) -> StandardMaterial3D:
	var key := "stud|%s" % color.to_html(false)
	var material: StandardMaterial3D = _materials.get(key, null)
	if material == null:
		material = StandardMaterial3D.new()
		material.albedo_color = STONE_LIGHT
		material.roughness = 0.88
		material.metallic = 0.0
		material.metallic_specular = 0.14
		material.emission_enabled = true
		material.emission = color
		material.emission_energy_multiplier = 0.0
		_materials[key] = material
	return material

static func crystal_material(color: Color) -> StandardMaterial3D:
	var key := "crystal|%s" % color.to_html(false)
	var material: StandardMaterial3D = _materials.get(key, null)
	if material == null:
		material = StandardMaterial3D.new()
		material.albedo_color = color.darkened(0.35)
		material.roughness = 0.22
		material.metallic = 0.35
		material.emission_enabled = true
		material.emission = color
		material.emission_energy_multiplier = CRYSTAL_ENERGY
		# 双面：三棱柱在背面剔除下会缺一半面，低模晶体看着像纸片。
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
		_materials[key] = material
	return material

static func add_material(color: Color, alpha: float) -> StandardMaterial3D:
	var key := "add|%s|%.2f" % [color.to_html(false), alpha]
	var material: StandardMaterial3D = _materials.get(key, null)
	if material == null:
		material = StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		material.albedo_color = Color(color.r, color.g, color.b, alpha)
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
		# 不写深度：贴地的一圈加色光写深度会切掉它后面的草叶。
		material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
		_materials[key] = material
	return material

static func material_count() -> int:
	return _materials.size()

static func mesh_count() -> int:
	return _meshes.size()

static func _add(parent: Node3D, mesh: Mesh, material: Material, pos: Vector3, rot_deg := Vector3.ZERO) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = material
	node.position = pos
	node.rotation_degrees = rot_deg
	parent.add_child(node)
	return node

static func _disc_mesh(radius: float, height := 0.12) -> CylinderMesh:
	var key := "disc|%.3f|%.3f" % [radius, height]
	var mesh: CylinderMesh = _meshes.get(key, null)
	if mesh == null:
		mesh = CylinderMesh.new()
		mesh.top_radius = radius
		mesh.bottom_radius = radius
		mesh.height = height
		# 32 段：21 米机位下直径 6 米约 130px，32 段的棱角在轮廓上刚好读成「石头」而不是多边形。
		mesh.radial_segments = 32
		mesh.rings = 1
		_meshes[key] = mesh
	return mesh

static func _cylinder_mesh(top_radius: float, bottom_radius: float, height: float, sides: int) -> CylinderMesh:
	var key := "cyl|%.3f|%.3f|%.3f|%d" % [top_radius, bottom_radius, height, sides]
	var mesh: CylinderMesh = _meshes.get(key, null)
	if mesh == null:
		mesh = CylinderMesh.new()
		mesh.top_radius = top_radius
		mesh.bottom_radius = bottom_radius
		mesh.height = height
		mesh.radial_segments = sides
		mesh.rings = 1
		_meshes[key] = mesh
	return mesh

static func _box_mesh(size: Vector3) -> BoxMesh:
	var key := "box|%.3f|%.3f|%.3f" % [size.x, size.y, size.z]
	var mesh: BoxMesh = _meshes.get(key, null)
	if mesh == null:
		mesh = BoxMesh.new()
		mesh.size = size
		_meshes[key] = mesh
	return mesh

static func _plane_mesh(size: float) -> PlaneMesh:
	var key := "plane|%.3f" % size
	var mesh: PlaneMesh = _meshes.get(key, null)
	if mesh == null:
		mesh = PlaneMesh.new()
		mesh.size = Vector2(size, size)
		# 平面不需要细分：整个符文轮都在 fragment 里画。
		mesh.subdivide_width = 0
		mesh.subdivide_depth = 0
		_meshes[key] = mesh
	return mesh
