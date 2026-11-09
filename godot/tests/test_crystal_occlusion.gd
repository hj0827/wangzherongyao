extends "res://tests/test_base.gd"

# 基地水晶遮挡英雄（2026-11-01）
#
# 现象：英雄走进本方泉水、贴到水晶旁，屏幕上几乎看不见自己 ——
# 截图 `shots/occ_z21_under.png` 里只剩一顶绿帽子从台座后面露出来。
#
# 根因（三层，缺一层都还是会挡）：
# 1. 相机 51° 俯角往下看，`pedestal`（半径 1.3~1.8、高 1.2）+ `gem`（y=3.55）
#    在屏幕上的投影正好罩住英雄站立的那个环带；
# 2. 水晶完全不透明，没有任何「让路」的机制；
# 3. gem 的 emission 2.6 + halo 加法混合渲成一团纯白，把旁边的英雄压得看不见。
#
# 契约：
# 1. 英雄靠近时，**挡路的那几件**（pedestal / gem / halo）降到 `MIN_VISIBLE`，
#    但**贴地圆盘 dais 必须保持不透明** —— 它是玩家定位水晶的唯一线索，
#    也根本不挡人。
# 2. 远离时回到完全不透明，不留残余。
# 3. 淡化靠常驻 `TRANSPARENCY_ALPHA` 的 albedo alpha 完成，
#    不在运行时切 transparency 档位（那会重建渲染管线，逐帧切换就是卡顿）。

const Arena = preload("res://scripts/game/arena.gd")
const Occlusion = preload("res://scripts/game/occlusion_fade.gd")
const MapData = preload("res://sim/map_data.gd")

func _base_entity(team: String = "blue") -> Dictionary:
	var pos: Vector2 = MapData.BLUE_BASE if team == "blue" else MapData.RED_BASE
	return {
		"id": 9001 if team == "blue" else 9002,
		"type": "base",
		"team": team,
		"tier": "core",
		"x": pos.x,
		"y": pos.y,
		"hp": 5000.0,
		"max_hp": 5000.0,
		"alive": true,
		"shield": 0.0,
	}

func _arena_with_base(team: String = "blue") -> Dictionary:
	var arena: Node3D = Arena.new()
	arena._structures_root = Node3D.new()
	arena.add_child(arena._structures_root)
	var record: Dictionary = arena._create_structure_view(_base_entity(team))
	return {"arena": arena, "record": record}

# ---------------- 距离曲线 ----------------

func test_far_away_crystal_stays_fully_opaque() -> void:
	# 边界：远了必须一点都不淡，否则整张地图的水晶都发虚。
	eq(Occlusion.reveal_amount(Occlusion.FADE_FAR), 0.0, "刚好到 FADE_FAR 时应完全不淡")
	eq(Occlusion.reveal_amount(30.0), 0.0, "远处完全不淡")
	eq(Occlusion.visible_alpha(30.0), 1.0, "远处的可见度必须是满的")

func test_hero_at_the_crystal_reveals_to_the_floor() -> void:
	# 边界：贴脸时淡到下限，但**不是 0** —— 全透明会让玩家找不到水晶。
	near(Occlusion.reveal_amount(Occlusion.FADE_NEAR), 1.0, 0.0001, "到 FADE_NEAR 时完全让路")
	near(Occlusion.reveal_amount(0.0), 1.0, 0.0001, "站在水晶正下方时完全让路")
	near(Occlusion.visible_alpha(0.0), Occlusion.MIN_VISIBLE, 0.0001, "贴脸时降到下限而不是 0")
	gt(Occlusion.MIN_VISIBLE, 0.0, "下限必须 >0，水晶不能彻底消失")

func test_reveal_grows_monotonically_as_the_hero_approaches() -> void:
	# 回归：单调。中间出现回弹的话，玩家走动时水晶会一闪一闪。
	var prev := -1.0
	# 从远走到近：距离递减，让路程度必须单调不减。
	for step in range(40, -1, -1):
		var d: float = Occlusion.FADE_FAR * float(step) / 40.0
		var amount: float = Occlusion.reveal_amount(d)
		check(amount >= prev - 0.00001, "reveal 必须随距离减小而单调不减，d=%.2f" % d)
		prev = amount
	# 中点要落在「真的在过渡」的位置，不能整段都贴在两端。
	var mid: float = Occlusion.reveal_amount((Occlusion.FADE_FAR + Occlusion.FADE_NEAR) * 0.5)
	near(mid, 0.5, 0.02, "过渡中点应约为一半")

func test_alpha_drops_faster_than_linear_near_the_hero() -> void:
	# 收尾用 smoothstep：曲线对称，但靠近段比线性更早淡到位。
	# 玩法上的意思：还剩 6 米就要贴上基座，那时必须已经几乎全透，
	# 而不是「走到 4 米才开始揭盖子」。
	var mid_distance: float = (Occlusion.FADE_FAR + Occlusion.FADE_NEAR) * 0.5
	near(
		Occlusion.visible_alpha(mid_distance),
		(1.0 + Occlusion.MIN_VISIBLE) * 0.5,
		0.01,
		"smoothstep 在中点应恰好落在两端的中点（曲线对称）"
	)
	var near_side: float = Occlusion.FADE_NEAR + (Occlusion.FADE_FAR - Occlusion.FADE_NEAR) * 0.25
	var linear_at_near_side := lerpf(1.0, Occlusion.MIN_VISIBLE, 0.75)
	lt(
		Occlusion.visible_alpha(near_side),
		linear_at_near_side - 0.02,
		"靠近段要淡得比线性更快，否则最后几米是突然揭开的"
	)

# ---------------- 作用面 ----------------

func test_only_the_parts_that_block_get_faded() -> void:
	# dais 是半径 4.4 的贴地圆盘，高 0.35 米，俯视下挡不住任何人，
	# 但它同时是「这儿有个水晶」的唯一定位线索 —— 绝不能跟着淡。
	var built := _arena_with_base()
	var record: Dictionary = built.record
	var parts: Array = Occlusion.fade_parts(record)
	gt(float(parts.size()), 0.0, "基地结构必须登记需要淡化的部件")
	var names: Array[String] = []
	for part in parts:
		names.append(str((part as Node).name) if part is Node else "?")
	check(not names.has("dais"), "贴地圆盘不能进入淡化名单：%s" % str(names))
	check(names.has("pedestal"), "水晶柱身必须淡化，它就是挡住英雄上半身的那件：%s" % str(names))
	check(names.has("gem"), "宝石必须淡化，它罩住的是英雄头顶：%s" % str(names))
	(built.arena as Node).free()

func test_fading_lowers_alpha_on_every_listed_part() -> void:
	var built := _arena_with_base()
	var record: Dictionary = built.record
	# 先确认初始是实心的。
	near(Occlusion.apply(record, 40.0), 1.0, 0.0001, "远处应恢复到满不透明")
	for part in Occlusion.fade_parts(record):
		var mat := (part as MeshInstance3D).material_override as StandardMaterial3D
		check(mat != null, "淡化部件必须有 material_override：%s" % (part as Node).name)
		if mat:
			near(mat.albedo_color.a, 1.0, 0.0001, "远处应完全不透明：%s" % (part as Node).name)
	# 贴脸。
	near(Occlusion.apply(record, 2.0), Occlusion.MIN_VISIBLE, 0.0001, "贴脸时整体降到下限")
	for part in Occlusion.fade_parts(record):
		var mat := (part as MeshInstance3D).material_override as StandardMaterial3D
		if mat:
			near(mat.albedo_color.a, Occlusion.MIN_VISIBLE, 0.0001, "贴脸时每个部件都要让路：%s" % (part as Node).name)
			eq(mat.transparency, BaseMaterial3D.TRANSPARENCY_ALPHA, "淡化部件必须常驻 ALPHA 档，不能运行时切档")
	(built.arena as Node).free()

func test_true_alpha_would_hide_the_hero_so_we_keep_the_dais_opaque() -> void:
	# 回归量化：淡到下限后，水晶对英雄的遮挡应该是「几乎透光」。
	# 这里直接量 dais 与 pedestal 的对比 —— 如果哪天有人把 dais 也塞进名单，
	# 玩家就再也分不清水晶在哪。
	var built := _arena_with_base()
	var record: Dictionary = built.record
	var dais: MeshInstance3D = null
	for child in (built.arena as Node).find_children("*", "MeshInstance3D", true, false):
		if str(child.name) == "dais":
			dais = child
	Occlusion.apply(record, 0.0)
	check(dais != null, "基地必须有 dais 节点")
	if dais:
		var dais_mat := dais.material_override as StandardMaterial3D
		check(dais_mat != null, "dais 应带独立材质")
		if dais_mat:
			near(dais_mat.albedo_color.a, 1.0, 0.0001, "英雄贴脸时 dais 仍必须完全不透明")
	(built.arena as Node).free()

func test_enemy_crystal_also_yields() -> void:
	# 英雄冲进敌方泉水同样会被自家视角的水晶挡住，逻辑不分敌我。
	var built := _arena_with_base("red")
	var record: Dictionary = built.record
	gt(float(Occlusion.fade_parts(record).size()), 0.0, "敌方水晶也要登记淡化部件")
	near(Occlusion.apply(record, 1.0), Occlusion.MIN_VISIBLE, 0.0001, "敌方水晶同样要让路")
	(built.arena as Node).free()

# ---------------- 接线 ----------------

func test_sync_structures_actually_applies_the_fade() -> void:
	# 「文件在 + 测试绿」不等于「功能在跑」：必须确认 _sync_structures 真的调了它。
	var source := FileAccess.get_file_as_string("res://scripts/game/arena.gd")
	check(
		has_live_line(source, "OcclusionFade.apply("),
		"_sync_structures 必须每帧调用 OcclusionFade.apply()，否则节点搭好了也没人淡"
	)
	check(
		has_live_line(source, "crystal_fade_parts"),
		"基地构建记录必须带上 crystal_fade_parts 字段"
	)
