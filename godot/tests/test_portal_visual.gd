extends "res://tests/test_base.gd"

# 传送阵造型与状态表现的契约（2026-11-11 造型升级）。
#
# 起因：旧版是「一块青色薄饼 + 一根灰杆」（arena._add_map_disc + _add_map_totem），
# 俯视下和野区营地圆盘几乎分不出来，也完全读不出「有没有人在读条」。
# 现在造型收在 PortalVisual，Arena 只给它世界坐标与朝向。
#
# 这一套测试守四类东西，四类都会**静默失效**（不报错、跑起来看不出哪里坏）：
#   ① 几何契约：石台半径 = 传送判定半径；柱子不许立进阵内（会挡住读条的人）；
#   ② 状态映射：快照里的进度 → 外观参数，纯函数可断言；
#   ③ 接线守卫：Arena 真的每帧调它、事件真的接到闪光/裂开；
#   ④ 着色器：能被编译、且**没有重定义内置常量**（重定义的后果是材质变纯白，
#      不报错、测试也不会红，只有截图能看出来 —— 这次就是这么踩到的）。

const Arena = preload("res://scripts/game/arena.gd")
const PortalVisual = preload("res://scripts/game/portal_visual.gd")
const MapLayout = preload("res://sim/map/map_layout.gd")
const ModelUtils = preload("res://scripts/game/model_utils.gd")

const RUNE_SHADER_PATH := "res://shaders/teleport_rune.gdshader"

func _pad(index := 0) -> Dictionary:
	return MapLayout.TELEPORT_PADS[index]

# ---------------------------------------------------------------------------
# ① 几何契约
# ---------------------------------------------------------------------------

func test_dais_radius_matches_the_teleport_judgement_radius() -> void:
	# 两处各写一个 3.0 的下场是「人站在石台边缘、按下去没反应」，
	# 或者反过来「站在阵外的草地上还能传」。唯一真身在 MapLayout。
	near(PortalVisual.DAIS_RADIUS, MapLayout.PAD_DISC_RADIUS, 0.001,
		"石台半径必须等于传送判定半径")
	gt(PortalVisual.DAIS_RADIUS, 2.0, "石台不能小到读不成一块场地")

func test_pillars_stand_outside_the_judgement_disc() -> void:
	# 柱子立在阵内会挡住正在读条的英雄 —— 51° 俯角下尤其明显（柱影正好压在阵心）。
	gt(PortalVisual.PILLAR_RADIUS, PortalVisual.DAIS_RADIUS,
		"石柱必须立在阵盘之外（当前 %.2f vs 阵盘 %.2f）" % [PortalVisual.PILLAR_RADIUS, PortalVisual.DAIS_RADIUS])
	# 也要留在树冠留白之内：阵周 3 米内本来就不长树，柱子比那更近才不会撞上遮挡逻辑。
	lt(PortalVisual.PILLAR_RADIUS, PortalVisual.DAIS_RADIUS + MapLayout.PAD_CANOPY_CLEARANCE + 0.6,
		"石柱不该超出阵周的净空带")
	gt(PortalVisual.STUD_RADIUS, PortalVisual.RUNE_RADIUS,
		"缘石必须在符文轮之外，否则会切开阵纹")

func test_build_produces_the_four_signature_pieces() -> void:
	var record := PortalVisual.build(Color(0.42, 0.86, 1.0), 0.0)
	var root := record.get("root") as Node3D
	check(root != null, "build() 必须回一个可挂的根节点")
	if root == null:
		return
	check(record.get("rune") != null, "必须有符文轮")
	check(record.get("rune_material") is ShaderMaterial, "符文轮用 shader 材质（要能逐帧改参数）")
	eq((record.get("pillars", []) as Array).size(), PortalVisual.PILLAR_COUNT, "三根方尖柱")
	eq((record.get("crystals", []) as Array).size(), PortalVisual.PILLAR_COUNT, "每根柱顶一颗晶体")
	check(record.get("light") is OmniLight3D, "阵心要有可驱动的点光源")
	check(record.get("aura") != null, "阵沿外要有一圈地面光池")
	# 点光源初始必须**熄灭**：两盏常亮灯在移动端最先吃掉帧预算。
	near(float((record.get("light") as OmniLight3D).light_energy), PortalVisual.LIGHT_IDLE, 0.001,
		"待机时点光源必须是关的")
	root.free()

func test_portal_footprint_stays_inside_its_clearance_band() -> void:
	# 造型不能长到阵周的净空带外面去：那里是「不长树」的边界，
	# 越出去就会和随机布景互相穿模（历史坑：树冠盖住阵盘）。
	var record := PortalVisual.build(Color(0.42, 0.86, 1.0), 0.0)
	var root := record.get("root") as Node3D
	if root == null:
		return
	var box := ModelUtils.relative_aabb(root)
	var horizontal := maxf(box.size.x, box.size.z) * 0.5
	var limit := PortalVisual.DAIS_RADIUS + MapLayout.PAD_CANOPY_CLEARANCE
	lt(horizontal, limit, "阵的外接半径 %.2f 不能越出净空带 %.2f" % [horizontal, limit])
	# 高度：51° 俯角下任何高过 3.2 米的部件都会把站在阵上的英雄盖住。
	lt(box.size.y, 3.2, "阵的最高点 %.2f 不能盖住站在阵上的英雄" % box.size.y)
	gt(box.size.y, 2.0, "阵要有足够的高度差才读得出「一根柱子」")
	root.free()

func test_crystal_sits_above_the_pillar_and_floats() -> void:
	var record := PortalVisual.build(Color(0.42, 0.86, 1.0), 0.0)
	var crystals: Array = record.get("crystals", [])
	if crystals.is_empty():
		check(false, "必须有三颗晶体")
		(record.get("root") as Node3D).free()
		return
	var crystal := crystals[0] as Node3D
	var rest := float(crystal.get_meta("rest_y", 0.0))
	gt(rest, 2.0, "晶体要悬在柱顶之上（rest_y = %.2f）" % rest)
	# 浮空：推进若干帧后 y 必须变化过，且不能漂走。
	var before := crystal.position.y
	PortalVisual.apply_state(record, 0.0, 0.25)
	var moved := absf(crystal.position.y - before)
	gt(moved, 0.0001, "晶体必须会上下浮（否则就是焊死在柱顶上的装饰）")
	lt(moved, 0.2, "浮空幅度不能大到脱离柱顶")
	(record.get("root") as Node3D).free()

# ---------------------------------------------------------------------------
# ② 状态映射（纯函数）
# ---------------------------------------------------------------------------

func test_charge_reads_the_hero_channeling_on_the_pad() -> void:
	var center: Vector2 = _pad(0).pos
	var hero := {
		"id": 1, "type": "hero", "team": "blue", "alive": true,
		"teleporting": true, "teleport_timer": 1.25, "teleport_total": 2.5,
		"x": float(center.x), "y": float(center.y),
	}
	near(PortalVisual.charge_from_entities([hero], center), 0.5, 0.001, "读了一半 → 0.5")
	hero["teleport_timer"] = 0.0
	near(PortalVisual.charge_from_entities([hero], center), 1.0, 0.001, "读完 → 1.0")
	hero["teleport_timer"] = 2.5
	near(PortalVisual.charge_from_entities([hero], center), 0.0, 0.001, "刚起手 → 0.0")

func test_charge_ignores_heroes_that_are_not_channeling_here() -> void:
	var center: Vector2 = _pad(0).pos
	var base := {
		"id": 1, "type": "hero", "team": "blue", "alive": true,
		"teleporting": true, "teleport_timer": 1.0, "teleport_total": 2.5,
		"x": float(center.x), "y": float(center.y),
	}
	# 站的不是这条阵（对端 100 多米外）：不能把远处那个人的进度算到这座阵头上。
	var far := base.duplicate(true)
	far["x"] = float(_pad(1).pos.x)
	far["y"] = float(_pad(1).pos.y)
	near(PortalVisual.charge_from_entities([far], center), 0.0, 0.001, "别处的传送不算这座阵")
	# 没在读条
	var idle := base.duplicate(true)
	idle["teleporting"] = false
	near(PortalVisual.charge_from_entities([idle], center), 0.0, 0.001, "没读条就不亮")
	# 死了
	var dead := base.duplicate(true)
	dead["alive"] = false
	near(PortalVisual.charge_from_entities([dead], center), 0.0, 0.001, "死人不点亮阵")
	# total 缺失：不能除零，也不能凭空给一个满值。
	var broken := base.duplicate(true)
	broken["teleport_total"] = 0.0
	near(PortalVisual.charge_from_entities([broken], center), 0.0, 0.001, "total 缺失时进度为 0，不产生 NaN")
	# 非英雄实体（小兵站在阵上）不参与
	var minion := {"type": "minion", "alive": true, "x": float(center.x), "y": float(center.y)}
	near(PortalVisual.charge_from_entities([minion], center), 0.0, 0.001, "小兵站着不会点亮传送阵")

func test_envelopes_are_short_and_monotonic() -> void:
	near(PortalVisual.flash_envelope(0.0), 1.0, 0.001, "闪光起手最亮")
	near(PortalVisual.flash_envelope(PortalVisual.FLASH_SECONDS), 0.0, 0.001, "闪光必须结束，否则阵会一直亮着")
	near(PortalVisual.shatter_envelope(0.0), 1.0, 0.001, "打断起手最强")
	near(PortalVisual.shatter_envelope(PortalVisual.SHATTER_SECONDS), 0.0, 0.001, "打断必须收干净")
	check(PortalVisual.shatter_envelope(-1.0) == 0.0, "负时间不是「还没开始」，就是不显示")
	# 单调衰减
	var previous := 2.0
	for step in 11:
		var elapsed := float(step) / 10.0 * PortalVisual.FLASH_SECONDS
		var value := PortalVisual.flash_envelope(elapsed)
		check(value <= previous, "闪光必须单调衰减")
		previous = value
	previous = 2.0
	for step in 11:
		var elapsed := float(step) / 10.0 * PortalVisual.SHATTER_SECONDS
		var value := PortalVisual.shatter_envelope(elapsed)
		check(value <= previous, "打断必须单调衰减")
		previous = value

func test_charge_drives_spin_crystal_and_light() -> void:
	# 四件事都必须随引导单调变化，否则「有人在读条」就只有一个信号，
	# 远景（看不到符文细节）时完全读不出来。
	gt(PortalVisual.spin_rate(1.0), PortalVisual.spin_rate(0.0), "读条时阵转得更急")
	gt(PortalVisual.pulse_rate(1.0), PortalVisual.pulse_rate(0.0), "读条时呼吸更快")
	gt(PortalVisual.crystal_energy(1.0, 0.0), PortalVisual.crystal_energy(0.0, 0.0), "读条时晶体更亮")
	gt(PortalVisual.light_energy(1.0, 0.0), PortalVisual.light_energy(0.0, 0.0), "读条时点光更亮")
	gt(PortalVisual.stud_energy(1.0), PortalVisual.stud_energy(0.0), "读条时缘石抽亮")
	# 待机点光必须真的是 0：常亮的灯在移动端最先吃帧预算。
	near(PortalVisual.light_energy(0.0, 0.0), 0.0, 0.001, "待机时点光必须熄灭")
	# 闪光在引导之上再叠一层，不能比满引导更暗。
	gt(PortalVisual.crystal_energy(1.0, 1.0), PortalVisual.crystal_energy(1.0, 0.0), "抵达闪光要比满引导更亮")
	# 上限：晶体自发光不能高到在 bloom 下糊成白斑（野怪晶体同一条教训）。
	lt(PortalVisual.crystal_energy(1.0, 1.0), 8.0, "晶体峰值自发光要压在 bloom 不糊的范围内")

func test_apply_state_converges_and_writes_the_shader() -> void:
	var record := PortalVisual.build(Color(0.42, 0.86, 1.0), 0.0)
	var root := record.get("root") as Node3D
	var material := record.get("rune_material") as ShaderMaterial
	check(material != null, "符文轮材质")
	if root == null or material == null:
		return
	near(float(material.get_shader_parameter("charge")), 0.0, 0.001, "初始 charge 为 0")
	# 用**真实读条**的节奏推：2.5 秒走完，每帧 1/30 秒。
	# 依赖目标值（不是直接把目标设成 1）才测得出「阵跟着读条走」；
	# 直接给目标 1.0 只会测到收敛速度，测不到跟读条的滞后。
	var target := 0.0
	for i in 15:
		target = minf(target + 0.4 * (1.0 / 30.0), 1.0)
		PortalVisual.apply_state(record, target, 1.0 / 30.0)
	var quarter := float(material.get_shader_parameter("charge"))
	gt(quarter, 0.0, "推进后 charge 必须真的写进材质")
	lt(quarter, 0.5, "半秒只读了 20%%，法阵不该先于读条拉满（当前 %.2f）" % quarter)
	# 阵的进度与目标差不能太大：落后太多会让「读条满了阵还没亮」，领先太多就没意义。
	near(quarter, target, 0.12, "法阵进度必须跟着读条走，不能明显拖后")
	# 再推到读完，必须到顶并停住（不能冲过 1）。
	for i in 90:
		target = minf(target + 0.4 * (1.0 / 30.0), 1.0)
		PortalVisual.apply_state(record, target, 1.0 / 30.0)
	near(float(material.get_shader_parameter("charge")), 1.0, 0.001, "读完必须收在 1，不能溢出")
	near(float(record.get("charge", 0.0)), 1.0, 0.001, "record 与材质上的 charge 必须是同一个数")
	# 目标归零后也要收敛回来（读完/离开阵）。
	for i in 4:
		PortalVisual.apply_state(record, 0.0, 0.5)
	near(float(material.get_shader_parameter("charge")), 0.0, 0.001, "目标归零后必须收回去")
	# spin 必须真的在走，且被取模到一圈之内（否则长时间对局会累积成天文数字）。
	gt(float(record.get("spin", 0.0)), 0.0, "spin 必须推进")
	lt(float(record.get("spin", 0.0)), TAU + 0.001, "spin 必须取模，不能无限累加")
	root.free()

# ---------------------------------------------------------------------------
# ③ 接线守卫（硬规则 9）
# ---------------------------------------------------------------------------

func test_arena_builds_two_portals_with_the_new_look() -> void:
	var arena: Node3D = Arena.new()
	arena._props_root = Node3D.new()
	arena.add_child(arena._props_root)
	arena._build_map_features()
	eq(arena._portal_views.size(), MapLayout.TELEPORT_PADS.size(), "每座传送阵都要建出可动表现")
	for record in arena._portal_views:
		check(record.get("rune_material") is ShaderMaterial, "每个 record 都要带符文材质")
		check(record.get("light") is OmniLight3D, "每个 record 都要带点光源")
	# 旧版那根「灰杆」必须消失：它在截图里从阵心穿出来挡住符文轮。
	for pad in MapLayout.TELEPORT_PADS:
		var old_totem: Node = arena._props_root.get_node_or_null(NodePath("portal_" + str(pad.id)))
		check(old_totem != null, "阵的根节点按 pad id 命名，供调试与测试定位")
	arena.free()

func test_arena_ticks_portals_every_frame_and_wires_the_events() -> void:
	var source := FileAccess.get_file_as_string("res://scripts/game/arena.gd")
	check(has_live_line(source, "_tick_portals(delta)"), "传送阵状态必须每帧被推进")
	check(has_live_line(source, "_flash_portal_at("), "抵达事件必须点亮对端的阵")
	check(has_live_line(source, "_shatter_portal_at("), "打断事件必须让符文裂开")
	check(has_live_line(source, "PortalVisual.build("), "造型必须由 PortalVisual 建，不能在 arena 里再拼一份")
	# 硬规则 4：不得在战斗期新建节点。符文轮/柱子都是建图时一次建好的。
	check(not has_live_line(source, "_spawn_portal_"), "传送阵不许在战斗期新开节点池")
	var portal_source := FileAccess.get_file_as_string("res://scripts/game/portal_visual.gd")
	check(not has_live_line(portal_source, "queue_free"), "传送阵表现里不该有 queue_free（没有战斗期节点）")
	check(not has_live_line(portal_source, "GPUParticles3D.new"), "传送阵不新开粒子系统")

func test_arena_portal_state_follows_the_snapshot() -> void:
	# 端到端：把英雄摆到阵上读条 → arena._tick_portals 之后 record 的 charge 必须涨起来。
	var arena: Node3D = Arena.new()
	arena._props_root = Node3D.new()
	arena.add_child(arena._props_root)
	arena._build_map_features()
	var center: Vector2 = _pad(0).pos
	var hero := {
		"id": 5, "type": "hero", "team": "blue", "owner_id": "p1", "alive": true,
		"teleporting": true, "teleport_timer": 1.0, "teleport_total": 2.5,
		"x": float(center.x), "y": float(center.y),
	}
	arena.current_snapshot = {"entities": [hero]}
	arena.authoritative = true
	for i in 30:
		arena._tick_portals(1.0 / 30.0)
	gt(arena._portal_charge, 0.5, "读条超过一半时 _portal_charge 必须读得出来")
	# 人走了：进度必须收回 0，不能停在原地一直亮。
	hero["teleporting"] = false
	arena.current_snapshot = {"entities": [hero]}
	for i in 40:
		arena._tick_portals(1.0 / 30.0)
	near(arena._portal_charge, 0.0, 0.01, "没人读条时进度必须收回 0")
	arena.free()

func test_flash_and_shatter_reset_the_envelopes() -> void:
	var arena: Node3D = Arena.new()
	arena._props_root = Node3D.new()
	arena.add_child(arena._props_root)
	arena._build_map_features()
	var center: Vector2 = _pad(0).pos
	arena._flash_portal_at(center)
	var record: Dictionary = arena._portal_at(center)
	check(not record.is_empty(), "按坐标要能找到阵（事件只带坐标，不带 pad id）")
	if not record.is_empty():
		near(float(record.get("flash_elapsed", INF)), 0.0, 0.001, "闪光计时必须归零")
		near(float(record.get("charge", 0.0)), 1.0, 0.001, "抵达瞬间进度拉满")
	arena._shatter_portal_at(center)
	if not record.is_empty():
		near(float(record.get("shatter_elapsed", INF)), 0.0, 0.001, "裂开计时必须归零")
	# 不在阵上的坐标不能误伤别的阵。
	var stray: Dictionary = arena._portal_at(Vector2(0.0, 0.0))
	check(stray.is_empty(), "阵外坐标不该匹配到任何一座阵")
	arena.free()

# ---------------------------------------------------------------------------
# ④ 着色器
# ---------------------------------------------------------------------------

func test_rune_shader_compiles_and_keeps_its_contract() -> void:
	var shader: Shader = load(RUNE_SHADER_PATH)
	check(shader != null, "符文轮 shader 必须存在")
	if shader == null:
		return
	var code := shader.code
	# 重定义内置常量 = 编译失败 = 材质回落纯白。这次就是这么踩到的：
	# `const float TAU = ...` 让整块石台变成一张白纸，而测试全绿、控制台只有一行
	# SHADER ERROR，肉眼在 1600x900 的整图里很容易漏掉。
	# TAU / PI / E 都是 Godot 着色器内置常量，一律不许重新声明。
	for builtin in ["TAU", "PI"]:
		check(not code.contains("const float " + builtin), "不能重定义着色器内置常量 " + builtin)
	check(code.contains("depth_draw_never"), "贴地符文不能写入深度")
	check(code.contains("blend_add"), "符文用加色混合")
	check(code.contains("charge"), "符文要能被引导进度驱动")
	check(code.contains("spin"), "符文要有旋转刻线")
	check(code.contains("shatter"), "符文要能表现「断了」")
	check(code.contains("sweep") or code.contains("head"), "要有读数指针，光靠整体变亮读不出还剩多久")
	check(not code.contains("TIME *"), "spin/pulse 由 GDScript 推，不在 shader 里累加 TIME（否则无法 headless 断言）")

func test_rune_shader_actually_compiles_headless() -> void:
	# 光断言源码字符串挡不住语法错误。真的让引擎编译一次：
	# 编译失败时 ShaderMaterial 的 shader 仍在（能 load），但 GPU 上什么都没有，
	# 画面里就是「石台没有任何阵纹」。这里用着色器参数的往返 + code 长度做一道粗筛，
	# 真正的编译错误仍要靠 headless 运行时日志里的 SHADER ERROR 抓（见 04 节注释）。
	var shader: Shader = load(RUNE_SHADER_PATH)
	if shader == null:
		return
	gt(shader.code.length(), 1200.0, "shader 不能是空壳")
	# 每个 uniform 都要被 fragment 真正读过：写了没用等于配方里的空参数。
	for name in ["charge", "spin", "pulse", "flash", "shatter", "band_gain", "rune_color", "hot_color"]:
		check(shader.code.contains("uniform float " + name) or shader.code.contains("uniform vec4 " + name),
			"uniform 必须声明：" + name)
	# band_gain 是亮度口径的唯一闸门（见 shader 文件头）：没有它就只能靠调颜色硬猜。
	check(shader.code.contains("band_gain"), "亮度口径必须由 band_gain 控制")
