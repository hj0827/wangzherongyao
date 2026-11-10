extends RefCounted

## 首领（暴君 / 主宰）的程序化形象。
##
## 王者的两位首领是「巨大的重甲魔兽」：躯干比英雄整个人还宽，四条粗腿撑起，
## 从头到背一排甲刺，胸口一颗发光核心。它们和普通野怪的区别不是贴图精度，
## 而是**三件事**：肩宽（俯视占屏）、甲刺（剪影不是方块）、核心（一眼看出这是首领坑）。
##
## 体型硬约束来自模拟层：碰撞半径 2.8（直径 5.6），旧版 Orc 宽 5.11 / 5.65。
## 形象必须撑满这个量级，否则就是「看着窄、实际被打范围宽」——
## test_monster_ui 会按 AABB 的横向尺寸卡这道关，塌了就是红。
##
## 暴君与主宰共用一套骨架（_beast），靠**配色 + 角数 + 甲刺长度 + 背晶**分开：
## 骨架相同是刻意的（它们是同一类目标），一眼能分开靠的是颜色与额头符石。

const Kit = preload("res://scripts/game/monster_kit.gd")

const TYRANT_HEIGHT := 3.8
const OVERLORD_HEIGHT := 4.2
const OBJECTIVE_BAR_WIDTH := 1.55

## 四足重甲躯干。返回腿部与可动部件，由调用方决定身高与配色语义。
static func _beast(
	root: Node3D,
	body: Node3D,
	hide_color: Color,
	plate_color: Color,
	core_color: Color,
	accent: Color,
	horn_count: int,
	spike_scale: float
) -> Dictionary:
	var hide_mat := Kit.hide_mat(hide_color, 0.68)
	var plate := Kit.chitin(plate_color)
	var plate_dark := Kit.stone(plate_color.darkened(0.4))
	var core := Kit.gem(core_color, 3.0)
	var glow := Kit.glow(accent, 2.2)

	# --- 四条粗腿：站距 3.0 米，「重」这件事在俯视下才成立 ---
	var legs: Array[Node3D] = []
	for side in [-1.0, 1.0]:
		for back in [0.0, 1.0]:
			var z := 1.0 - float(back) * 1.95
			legs.append(Kit.leg(
				body,
				Vector3(side * 1.5, 2.0, z),
				Vector3(0.62, 1.0, 0.66),
				Vector3(0.5, 0.8, 0.54),
				hide_mat,
				plate_dark,
				Vector3(0.8, 0.3, 0.86)
			))

	# --- 躯干：三层甲板叠出层次，最宽的一层在肩部 ---
	Kit.box(body, Vector3(3.0, 1.5, 2.2), hide_mat, Vector3(0.0, 2.15, 0.05))
	Kit.box(body, Vector3(3.34, 0.42, 2.34), plate, Vector3(0.0, 2.86, 0.02))
	Kit.box(body, Vector3(2.7, 0.44, 1.9), plate_dark, Vector3(0.0, 1.5, 0.05))
	Kit.box(body, Vector3(2.2, 1.0, 1.6), hide_mat, Vector3(0.0, 2.2, -0.5))
	# --- 胸口核心：首领坑「可争夺」的那口「活气」全靠这颗会呼吸的芯 ---
	var heart := Kit.ball(body, 0.52, core, Vector3(0.0, 2.2, 1.16))
	Kit.box(body, Vector3(1.6, 0.24, 0.22), plate_dark, Vector3(0.0, 2.2, 1.18))
	Kit.box(body, Vector3(0.24, 1.34, 0.22), plate_dark, Vector3(0.0, 2.2, 1.18))
	# --- 肩甲：两片带刺的巨甲，把剪影宽度顶到碰撞直径量级。
	# 不能做成两块高耸的方塔：那会读成「城堡」而不是「魔兽」。压低 + 外倾 14° 才像肩。
	for side in [-1.0, 1.0]:
		Kit.box(body, Vector3(1.06, 0.78, 1.6), plate, Vector3(side * 1.84, 2.64, 0.05), Vector3(0.0, 0.0, side * -14.0))
		for i in 3:
			var z := 0.5 - float(i) * 0.52
			Kit.spike(body, 0.19 * spike_scale, 0.9 * spike_scale, plate_dark, Vector3(side * 1.94, 3.02, z), Vector3(0.0, 0.0, side * -30.0))
	# --- 背脊甲刺：最高的一根决定整体身高 ---
	for i in 5:
		var z := 0.9 - float(i) * 0.62
		var tall := (1.0 - absf(float(i) - 2.0) * 0.22) * spike_scale
		Kit.spike(body, 0.18 * spike_scale, 1.2 * tall, plate_dark, Vector3(0.0, 3.36, z), Vector3(-16.0, 0.0, 0.0))
	# --- 头：短颈 + 窄吻 + 下颌 + 角 + 发光眼 + 上翘獠牙。
	# 头必须比躯干窄一大截，否则俯视下和躯干连成一块，看不出「脸朝哪边」。
	Kit.box(body, Vector3(1.05, 0.9, 0.9), hide_mat, Vector3(0.0, 2.72, 1.6), Vector3(-14.0, 0.0, 0.0))
	Kit.box(body, Vector3(1.34, 0.96, 1.05), hide_mat, Vector3(0.0, 2.66, 1.94))
	Kit.box(body, Vector3(1.46, 0.3, 0.72), plate_dark, Vector3(0.0, 3.06, 2.06))
	Kit.box(body, Vector3(0.98, 0.44, 0.74), plate_dark, Vector3(0.0, 2.32, 2.34))
	Kit.box(body, Vector3(0.3, 0.22, 0.09), glow, Vector3(-0.42, 2.78, 2.0))
	Kit.box(body, Vector3(0.3, 0.22, 0.09), glow, Vector3(0.42, 2.78, 2.0))
	for i in horn_count:
		var offset := float(i) - float(horn_count - 1) * 0.5
		Kit.spike(body, 0.16, 0.95, plate, Vector3(offset * 0.3, 3.2, 1.7), Vector3(-34.0, 0.0, offset * 26.0))
	# 獠牙从下颌两侧**向上外翻**。朝前摆会连成一排白板，正面读成「一张嘴」而不是两枚牙。
	for i in 4:
		var side_tusk := -1.0 if i < 2 else 1.0
		Kit.spike(
			body,
			0.075,
			0.48,
			Kit.chitin(Color(0.92, 0.9, 0.8)),
			Vector3(side_tusk * (0.3 + 0.14 * float(i % 2)), 2.4, 2.66),
			Vector3(-48.0, 0.0, side_tusk * (30.0 + 12.0 * float(i % 2))),
			5
		)
	# --- 尾：两节锥体，扫尾由 animate() 驱动 ---
	var tail := Kit.group(body, "Tail", Vector3(0.0, 2.5, -1.2))
	Kit.box(tail, Vector3(0.72, 0.72, 1.0), hide_mat, Vector3(0.0, 0.0, -0.4))
	Kit.spike(tail, 0.34, 1.4, plate_dark, Vector3(0.0, 0.0, -1.45), Vector3(-96.0, 0.0, 0.0))

	var limbs := {
		"legs": legs,
		"tail": tail,
		"heart": heart,
	}
	return limbs

## 环绕首领缓慢转动的光点：让首领坑在俯视下一直有东西在动。
static func _orbit_motes(body: Node3D, material: Material, radius: float, count: int) -> Array[Node3D]:
	var orbit := Kit.group(body, "Orbit")
	for i in count:
		var angle := TAU * float(i) / float(count)
		Kit.ball(orbit, 0.17, material, Vector3(cos(angle) * radius, 1.15 + float(i % 3) * 0.9, sin(angle) * radius))
	var orbits: Array[Node3D] = [orbit]
	return orbits

## 暴君：暗赤铁甲的装甲巨兽，四角，甲刺短厚（力量感）。
static func tyrant(target_height := TYRANT_HEIGHT) -> Dictionary:
	var root := Node3D.new()
	var body := Kit.group(root, "Body")
	var parts := _beast(
		root,
		body,
		Color(0.1, 0.07, 0.07),
		Color(0.22, 0.05, 0.05),
		Color(1.0, 0.34, 0.08),
		Color(1.0, 0.5, 0.16),
		4,
		1.0
	)
	Kit.shard(
		body,
		Vector3(0.32, 0.48, 0.2),
		Kit.gem(Color(1.0, 0.28, 0.05), 3.2),
		Vector3(0.0, 3.12, 2.0),
		Vector3(-18.0, 0.0, 0.0)
	)
	var spec := Kit.finish("tyrant", root, body, target_height, OBJECTIVE_BAR_WIDTH)
	spec["legs"] = parts["legs"]
	spec["tail"] = parts["tail"]
	var pulses: Array[MeshInstance3D] = [parts["heart"]]
	spec["pulses"] = pulses
	spec["orbits"] = _orbit_motes(body, Kit.glow(Color(1.0, 0.5, 0.2), 1.8), 2.6, 6)
	return spec

## 主宰：紫黑暗甲魔兽，六角，甲刺更长，背生晶簇（压迫感）。
static func overlord(target_height := OVERLORD_HEIGHT) -> Dictionary:
	var root := Node3D.new()
	var body := Kit.group(root, "Body")
	var parts := _beast(
		root,
		body,
		Color(0.07, 0.06, 0.12),
		Color(0.16, 0.1, 0.3),
		Color(0.6, 0.34, 1.0),
		Color(0.74, 0.5, 1.0),
		6,
		1.18
	)
	for i in 3:
		var offset := (float(i) - 1.0) * 0.36
		Kit.shard(
			body,
			Vector3(0.26, 0.84, 0.22),
			Kit.gem(Color(0.55, 0.3, 1.0), 3.0),
			Vector3(offset, 3.5, -0.42),
			Vector3(-12.0, 0.0, offset * 40.0)
		)
	# 中心光点绕体缓转就够了。上一版还套了一圈加色光环，实拍是一道刺眼的白色圆环 —— 删掉。
	var orbits := _orbit_motes(body, Kit.glow(Color(0.8, 0.58, 1.0), 2.2), 2.6, 7)
	var spec := Kit.finish("overlord", root, body, target_height, OBJECTIVE_BAR_WIDTH)
	spec["legs"] = parts["legs"]
	spec["tail"] = parts["tail"]
	var pulses: Array[MeshInstance3D] = [parts["heart"]]
	spec["pulses"] = pulses
	spec["orbits"] = orbits
	return spec
