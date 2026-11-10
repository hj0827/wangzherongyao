extends RefCounted

## 野区常规野怪与红蓝增益怪的程序化形象（王者峡谷口径）。
##
## 设计口径（参考《王者荣耀》野区）：**红蓝 BUFF 是石像，小野点是野兽**。
##   蓝 BUFF → 蔚蓝石像：漂浮的石躯 + 胸口蓝色晶簇 + 肩甲绕体缓转；
##   红 BUFF → 猩红石像：更宽更壮、肩背带尖、岩浆裂纹 + 环绕火星；
##   双狼   → 沿用现有狼模型（见 unit_visual 的 _polish_wolf），不在这里重造；
##   蜥蜴   → 低伏四足、背脊鳍刺、长尾；
##   三猪   → 短粗野猪、上翘獠牙、鬃背；
##   红鸟   → 赤色猛禽、翼展明显、长尾羽。
##
## 两条硬经验（都是看了实拍图才改的）：
##   1. **块不要大**：一整块大方块在任何机位下都读成「纸箱」，同一体积拆成两三块、
##      各自转几度，才有石/甲/肉的层次；
##   2. **发光件要小而亮**：颜色越亮越大，在 bloom 下越糊成一坨白斑。晶体做成晶簇、
##      核心缩到拳头大小，靠 emission 能量而不是靠面积去抢视线。
##
## 每个 builder 只负责「摆石块」，动画由 monster_forms.animate() 统一驱动：
## 腿绕髋关节摆、翅膀扇、尾巴摇、肩甲/火星绕体转、晶体呼吸。
## 这样换形象不用碰 UnitVisual，加动画也不用改每个 builder。

const Kit = preload("res://scripts/game/monster_kit.gd")

# ---------------------------------------------------------------------------
# 蓝 BUFF：蔚蓝石像
# ---------------------------------------------------------------------------

static func blue_sentinel() -> Dictionary:
	var root := Node3D.new()
	var body := Kit.group(root, "Body")
	var stone := Kit.stone(Color(0.12, 0.17, 0.3))
	var stone_dark := Kit.stone(Color(0.06, 0.09, 0.17))
	var rune := Kit.glow(Color(0.55, 0.86, 1.0), 2.6)
	var crystal := Kit.gem(Color(0.18, 0.58, 1.0), 3.0)

	# 躯干：三块递减的石板叠出的「胸甲」，比一整块方箱更像被凿出来的石像。
	Kit.box(body, Vector3(1.18, 0.6, 0.78), stone, Vector3(0.0, 1.66, 0.0), Vector3(3.0, 0.0, 0.0))
	Kit.box(body, Vector3(1.32, 0.44, 0.88), stone_dark, Vector3(0.0, 1.32, 0.02), Vector3(1.5, 0.0, 0.0))
	Kit.box(body, Vector3(1.06, 0.4, 0.7), stone, Vector3(0.0, 1.0, 0.02))
	# 胸口晶簇：一个菱形主晶 + 两颗斜插的小晶。菱形靠两块棱柱背对背拼出来 ——
	# 单块棱柱是「一片三角形」，在俯视下读成纸片，不是宝石。
	# 尺寸刻意压小：bloom 会让发光件膨胀，做大了整块胸甲都会被自己的晶体吃掉。
	var heart := Kit.shard(body, Vector3(0.26, 0.34, 0.24), crystal, Vector3(0.0, 1.6, 0.42))
	var heart_low := Kit.shard(body, Vector3(0.26, 0.34, 0.24), crystal, Vector3(0.0, 1.6, 0.42), Vector3(180.0, 0.0, 0.0))
	Kit.shard(body, Vector3(0.14, 0.24, 0.14), crystal, Vector3(-0.24, 1.48, 0.36), Vector3(0.0, 0.0, -28.0))
	Kit.shard(body, Vector3(0.14, 0.24, 0.14), crystal, Vector3(0.24, 1.48, 0.36), Vector3(0.0, 0.0, 28.0))
	var core := Kit.ball(body, 0.1, rune, Vector3(0.0, 1.6, 0.48))
	# 浮空下摆：四片向外撇的石裙，读成「下半身是一块悬空的石头」而不是缺了腿。
	for i in 4:
		var angle := TAU * float(i) / 4.0 + PI * 0.25
		Kit.box(
			body,
			Vector3(0.5, 0.52, 0.2),
			stone_dark,
			Vector3(cos(angle) * 0.34, 0.62, sin(angle) * 0.3),
			Vector3(6.0, rad_to_deg(-angle) + 90.0, 10.0)
		)
	Kit.box(body, Vector3(0.42, 0.3, 0.34), stone, Vector3(0.0, 0.36, 0.0))
	# 头 + 眉脊 + 双眼 + 头顶晶冠
	Kit.box(body, Vector3(0.56, 0.44, 0.5), stone, Vector3(0.0, 2.12, 0.02))
	Kit.box(body, Vector3(0.62, 0.12, 0.34), stone_dark, Vector3(0.0, 2.28, 0.16))
	Kit.box(body, Vector3(0.26, 0.14, 0.36), stone_dark, Vector3(0.0, 1.96, 0.1))
	Kit.box(body, Vector3(0.12, 0.08, 0.06), rune, Vector3(-0.14, 2.12, 0.27))
	Kit.box(body, Vector3(0.12, 0.08, 0.06), rune, Vector3(0.14, 2.12, 0.27))
	Kit.shard(body, Vector3(0.22, 0.42, 0.22), crystal, Vector3(0.0, 2.5, -0.02))
	Kit.shard(body, Vector3(0.22, 0.42, 0.22), crystal, Vector3(0.0, 2.5, -0.02), Vector3(180.0, 0.0, 0.0))
	Kit.shard(body, Vector3(0.14, 0.26, 0.14), crystal, Vector3(-0.2, 2.42, -0.06), Vector3(0.0, 0.0, -26.0))
	Kit.shard(body, Vector3(0.14, 0.26, 0.14), crystal, Vector3(0.2, 2.42, -0.06), Vector3(0.0, 0.0, 26.0))
	# 背后尖石：俯视时把剪影从「一块方石头」掰成有指向的图腾。
	Kit.shard(body, Vector3(0.18, 0.46, 0.18), stone_dark, Vector3(-0.26, 1.9, -0.42), Vector3(-26.0, 0.0, -16.0))
	Kit.shard(body, Vector3(0.18, 0.56, 0.18), stone_dark, Vector3(0.0, 1.96, -0.46), Vector3(-26.0, 0.0, 0.0))
	Kit.shard(body, Vector3(0.18, 0.46, 0.18), stone_dark, Vector3(0.26, 1.9, -0.42), Vector3(-26.0, 0.0, 16.0))
	# 肩甲 + 石拳挂在轨道组上：静止的石像会读成「场景装饰」，缓慢绕体转才有生命感。
	var orbit := Kit.group(body, "Orbit")
	var left := Kit.group(orbit, "Left")
	var right := Kit.group(orbit, "Right")
	Kit.box(left, Vector3(0.42, 0.36, 0.5), stone, Vector3(-0.94, 1.84, 0.0), Vector3(0.0, 0.0, 14.0))
	Kit.box(left, Vector3(0.2, 0.1, 0.34), rune, Vector3(-1.0, 1.84, 0.06), Vector3(0.0, 0.0, 14.0))
	Kit.box(right, Vector3(0.42, 0.36, 0.5), stone, Vector3(0.94, 1.84, 0.0), Vector3(0.0, 0.0, -14.0))
	Kit.box(right, Vector3(0.2, 0.1, 0.34), rune, Vector3(1.0, 1.84, 0.06), Vector3(0.0, 0.0, -14.0))
	Kit.box(left, Vector3(0.22, 0.44, 0.24), stone_dark, Vector3(-0.82, 1.42, 0.04), Vector3(0.0, 0.0, 8.0))
	Kit.box(right, Vector3(0.22, 0.44, 0.24), stone_dark, Vector3(0.82, 1.42, 0.04), Vector3(0.0, 0.0, -8.0))
	Kit.ball(left, 0.18, stone_dark, Vector3(-0.84, 1.12, 0.06))
	Kit.ball(right, 0.18, stone_dark, Vector3(0.84, 1.12, 0.06))

	var spec := Kit.finish("blue_sentinel", root, body, 2.45, 0.95)
	var orbits: Array[Node3D] = [orbit]
	var pulses: Array[MeshInstance3D] = [heart, heart_low, core]
	spec["orbits"] = orbits
	spec["pulses"] = pulses
	return spec

# ---------------------------------------------------------------------------
# 红 BUFF：猩红石像
# ---------------------------------------------------------------------------

static func red_sentinel() -> Dictionary:
	var root := Node3D.new()
	var body := Kit.group(root, "Body")
	var stone := Kit.stone(Color(0.19, 0.06, 0.05))
	var stone_dark := Kit.stone(Color(0.09, 0.03, 0.03))
	var ember := Kit.glow(Color(1.0, 0.45, 0.12), 2.8)
	var magma := Kit.gem(Color(1.0, 0.24, 0.04), 3.0)

	# 比蓝石像更宽更矮：一蓝一红除了配色，剪影也要能分开（宽壮 vs 修长）。
	Kit.box(body, Vector3(1.5, 0.62, 0.94), stone, Vector3(0.0, 1.58, 0.0), Vector3(2.0, 0.0, 0.0))
	Kit.box(body, Vector3(1.66, 0.46, 1.04), stone_dark, Vector3(0.0, 1.24, 0.02), Vector3(1.0, 0.0, 0.0))
	Kit.box(body, Vector3(1.3, 0.42, 0.84), stone, Vector3(0.0, 0.94, 0.02))
	# 岩浆裂纹：三条贴在胸口的发光细条，颜色就是红 BUFF 的第一读点。
	Kit.box(body, Vector3(0.06, 0.66, 0.05), magma, Vector3(-0.3, 1.58, 0.48), Vector3(0.0, 0.0, 10.0))
	Kit.box(body, Vector3(0.06, 0.5, 0.05), magma, Vector3(0.04, 1.62, 0.5))
	Kit.box(body, Vector3(0.06, 0.4, 0.05), magma, Vector3(0.34, 1.5, 0.46), Vector3(0.0, 0.0, -12.0))
	var heart := Kit.ball(body, 0.22, Kit.gem(Color(1.0, 0.3, 0.05), 3.4), Vector3(0.0, 1.58, 0.42))
	# 浮空下摆
	for i in 4:
		var angle := TAU * float(i) / 4.0 + PI * 0.25
		Kit.box(
			body,
			Vector3(0.58, 0.54, 0.22),
			stone_dark,
			Vector3(cos(angle) * 0.4, 0.6, sin(angle) * 0.34),
			Vector3(6.0, rad_to_deg(-angle) + 90.0, 10.0)
		)
	Kit.box(body, Vector3(0.46, 0.3, 0.38), stone, Vector3(0.0, 0.34, 0.0))
	# 头 + 双角 + 琥珀眼
	Kit.box(body, Vector3(0.62, 0.46, 0.56), stone, Vector3(0.0, 2.04, 0.04))
	Kit.box(body, Vector3(0.68, 0.14, 0.34), stone_dark, Vector3(0.0, 2.22, 0.18))
	Kit.box(body, Vector3(0.3, 0.12, 0.32), stone_dark, Vector3(0.0, 1.9, 0.14))
	Kit.box(body, Vector3(0.13, 0.09, 0.06), ember, Vector3(-0.15, 2.04, 0.3))
	Kit.box(body, Vector3(0.13, 0.09, 0.06), ember, Vector3(0.15, 2.04, 0.3))
	Kit.spike(body, 0.11, 0.54, stone_dark, Vector3(-0.28, 2.32, -0.04), Vector3(-14.0, 0.0, -30.0))
	Kit.spike(body, 0.11, 0.54, stone_dark, Vector3(0.28, 2.32, -0.04), Vector3(-14.0, 0.0, 30.0))
	# 肩背尖刺：石像的「攻击性」全靠这排刺。
	for i in 3:
		var offset := (float(i) - 1.0) * 0.4
		var tall := 0.46 + (1.0 - absf(float(i) - 1.0)) * 0.24
		Kit.spike(body, 0.12, tall, stone_dark, Vector3(offset, 1.92, -0.4), Vector3(-32.0, 0.0, 0.0))
	# 肩甲 + 石拳 + 环绕火星
	var orbit := Kit.group(body, "Orbit")
	var left := Kit.group(orbit, "Left")
	var right := Kit.group(orbit, "Right")
	Kit.box(left, Vector3(0.54, 0.42, 0.62), stone, Vector3(-1.06, 1.78, 0.0), Vector3(0.0, 0.0, 16.0))
	Kit.box(right, Vector3(0.54, 0.42, 0.62), stone, Vector3(1.06, 1.78, 0.0), Vector3(0.0, 0.0, -16.0))
	Kit.spike(left, 0.1, 0.34, stone_dark, Vector3(-1.14, 2.04, 0.0), Vector3(-10.0, 0.0, -34.0))
	Kit.spike(right, 0.1, 0.34, stone_dark, Vector3(1.14, 2.04, 0.0), Vector3(-10.0, 0.0, 34.0))
	Kit.box(left, Vector3(0.24, 0.46, 0.26), stone_dark, Vector3(-0.92, 1.34, 0.04), Vector3(0.0, 0.0, 8.0))
	Kit.box(right, Vector3(0.24, 0.46, 0.26), stone_dark, Vector3(0.92, 1.34, 0.04), Vector3(0.0, 0.0, -8.0))
	Kit.ball(left, 0.2, stone_dark, Vector3(-0.94, 1.04, 0.06))
	Kit.ball(right, 0.2, stone_dark, Vector3(0.94, 1.04, 0.06))
	var motes := Kit.group(body, "Motes")
	for i in 5:
		var angle := TAU * float(i) / 5.0
		Kit.ball(motes, 0.08, ember, Vector3(cos(angle) * 1.34, 0.8 + float(i % 3) * 0.46, sin(angle) * 1.34))

	var spec := Kit.finish("red_sentinel", root, body, 2.6, 0.95)
	var orbits: Array[Node3D] = [orbit]
	var pulses: Array[MeshInstance3D] = [heart]
	spec["orbits"] = orbits
	spec["pulses"] = pulses
	spec["motes"] = motes
	return spec

# ---------------------------------------------------------------------------
# 小野点：蜥蜴
# ---------------------------------------------------------------------------

static func lizard() -> Dictionary:
	var root := Node3D.new()
	var body := Kit.group(root, "Body")
	var scale_dark := Kit.hide_mat(Color(0.06, 0.19, 0.14))
	var scale_light := Kit.hide_mat(Color(0.12, 0.35, 0.21))
	var belly := Kit.hide_mat(Color(0.4, 0.42, 0.22))
	var fin := Kit.hide_mat(Color(0.03, 0.1, 0.09))
	var eye := Kit.glow(Color(1.0, 0.86, 0.28), 2.6)

	# 主体低伏而长：身高只到英雄一半，长度约 2.6 米。
	# 俯视下「细长 + 背脊刺 + 拖尾」这三件套就是蜥蜴的签名，缺一件就会读成别的东西。
	# 身体不能宽：宽过 0.6 米就从「蜥蜴」读成「蛤蟆」。
	Kit.box(body, Vector3(0.52, 0.38, 1.3), scale_dark, Vector3(0.0, 0.56, -0.16))
	Kit.box(body, Vector3(0.44, 0.16, 1.14), belly, Vector3(0.0, 0.36, -0.16))
	Kit.box(body, Vector3(0.4, 0.26, 0.4), scale_light, Vector3(0.0, 0.6, 0.52))
	# 颈 + 头 + 吻 + 眼（头略抬起，剪影上要有一个能认出的「头」）
	Kit.box(body, Vector3(0.3, 0.24, 0.34), scale_light, Vector3(0.0, 0.68, 0.8), Vector3(-10.0, 0.0, 0.0))
	Kit.box(body, Vector3(0.28, 0.2, 0.4), scale_dark, Vector3(0.0, 0.72, 1.1), Vector3(-6.0, 0.0, 0.0))
	Kit.box(body, Vector3(0.22, 0.12, 0.28), scale_dark, Vector3(0.0, 0.64, 1.28), Vector3(-8.0, 0.0, 0.0))
	Kit.ball(body, 0.05, eye, Vector3(-0.12, 0.82, 0.95))
	Kit.ball(body, 0.05, eye, Vector3(0.12, 0.82, 0.95))
	# 头冠 + 背脊鳍刺：一直连到尾巴，剪影才有「龙蜥」的味道
	for i in 3:
		Kit.shard(body, Vector3(0.07, 0.24, 0.18), fin, Vector3(0.0, 0.88 - float(i) * 0.02, 0.96 - float(i) * 0.2), Vector3(-20.0, 0.0, 0.0))
	for i in 5:
		var z := 0.48 - float(i) * 0.34
		var tall := 0.3 - float(i) * 0.024
		Kit.shard(body, Vector3(0.06, tall, 0.24), fin, Vector3(0.0, 0.78 - float(i) * 0.012, z), Vector3(-14.0, 0.0, 0.0))
	# 尾：三节收窄 + 尾鳍，挂在尾根组上左右摆
	var tail := Kit.group(body, "Tail", Vector3(0.0, 0.54, -0.78))
	Kit.box(tail, Vector3(0.32, 0.28, 0.46), scale_dark, Vector3(0.0, 0.0, -0.2))
	Kit.box(tail, Vector3(0.22, 0.2, 0.44), scale_light, Vector3(0.0, -0.01, -0.58))
	Kit.box(tail, Vector3(0.14, 0.14, 0.38), scale_dark, Vector3(0.0, -0.02, -0.92))
	Kit.shard(tail, Vector3(0.05, 0.2, 0.3), fin, Vector3(0.0, 0.11, -0.8), Vector3(-16.0, 0.0, 0.0))
	var leg_specs := [
		{"x": -0.3, "z": 0.48, "spread": -18.0},
		{"x": 0.3, "z": 0.48, "spread": 18.0},
		{"x": -0.3, "z": -0.42, "spread": -30.0},
		{"x": 0.3, "z": -0.42, "spread": 30.0},
	]
	var legs: Array[Node3D] = []
	for entry in leg_specs:
		var joint := Kit.leg(
			body,
			Vector3(entry.x, 0.58, entry.z),
			Vector3(0.14, 0.28, 0.16),
			Vector3(0.11, 0.24, 0.13),
			scale_light,
			scale_dark,
			Vector3(0.2, 0.07, 0.26)
		)
		joint.rotation_degrees = Vector3(0.0, 0.0, float(entry.spread))
		legs.append(joint)

	var spec := Kit.finish("lizard", root, body, 1.15, 0.8)
	spec["legs"] = legs
	spec["tail"] = tail
	return spec

# ---------------------------------------------------------------------------
# 小野点：三猪（野猪）
# ---------------------------------------------------------------------------

static func boar() -> Dictionary:
	var root := Node3D.new()
	var body := Kit.group(root, "Body")
	var bristle := Kit.hide_mat(Color(0.11, 0.07, 0.05))
	var bristle_light := Kit.hide_mat(Color(0.2, 0.13, 0.09))
	var snout := Kit.hide_mat(Color(0.32, 0.2, 0.17))
	var tusk := Kit.chitin(Color(0.93, 0.91, 0.8))
	var eye := Kit.glow(Color(1.0, 0.34, 0.22), 2.4)

	# 桶形躯干 + 前肩隆起的肉峰：「前高后低」是野猪和狼最容易分开的地方。
	Kit.box(body, Vector3(0.82, 0.66, 1.3), bristle, Vector3(0.0, 0.82, -0.18))
	Kit.box(body, Vector3(0.74, 0.22, 1.2), bristle_light, Vector3(0.0, 1.14, -0.2))
	Kit.ball(body, 0.44, bristle, Vector3(0.0, 0.9, 0.42), Vector3(1.0, 0.82, 0.86))
	Kit.ball(body, 0.36, bristle_light, Vector3(0.0, 1.06, -0.5), Vector3(1.0, 0.7, 0.9))
	# 头：斜面楔形 + 前伸的吻 + 鼻盘 + 竖起的耳朵
	Kit.box(body, Vector3(0.54, 0.46, 0.5), bristle, Vector3(0.0, 0.86, 0.82), Vector3(6.0, 0.0, 0.0))
	Kit.box(body, Vector3(0.38, 0.32, 0.42), snout, Vector3(0.0, 0.78, 1.16), Vector3(8.0, 0.0, 0.0))
	Kit.box(body, Vector3(0.3, 0.24, 0.08), Kit.hide_mat(Color(0.2, 0.15, 0.14)), Vector3(0.0, 0.74, 1.36), Vector3(8.0, 0.0, 0.0))
	# 獠牙：从下颌两侧**向上外翻**。上一版朝前，正面看是一排白板 —— 像嘴不像牙。
	Kit.spike(body, 0.07, 0.5, tusk, Vector3(-0.21, 0.7, 1.24), Vector3(-42.0, 0.0, -40.0), 5)
	Kit.spike(body, 0.07, 0.5, tusk, Vector3(0.21, 0.7, 1.24), Vector3(-42.0, 0.0, 40.0), 5)
	Kit.ball(body, 0.07, eye, Vector3(-0.18, 1.0, 1.0))
	Kit.ball(body, 0.07, eye, Vector3(0.18, 1.0, 1.0))
	Kit.shard(body, Vector3(0.14, 0.26, 0.1), bristle, Vector3(-0.26, 1.14, 0.84), Vector3(0.0, 0.0, -30.0))
	Kit.shard(body, Vector3(0.14, 0.26, 0.1), bristle, Vector3(0.26, 1.14, 0.84), Vector3(0.0, 0.0, 30.0))
	# 鬃背：一排后倒的硬毛，中间最高
	for i in 5:
		var z := 0.34 - float(i) * 0.3
		var tall := 0.46 - absf(float(i) - 2.0) * 0.06
		Kit.spike(body, 0.075, tall, bristle_light, Vector3(0.0, 1.26 - absf(float(i) - 2.0) * 0.03, z), Vector3(-38.0, 0.0, 0.0))
	# 短尾
	var tail := Kit.group(body, "Tail", Vector3(0.0, 1.0, -0.78))
	Kit.rod(tail, 0.055, 0.32, bristle, Vector3(0.0, 0.06, -0.1), Vector3(76.0, 0.0, 0.0), 6)
	var leg_specs := [
		{"x": -0.34, "z": 0.4},
		{"x": 0.34, "z": 0.4},
		{"x": -0.34, "z": -0.52},
		{"x": 0.34, "z": -0.52},
	]
	var legs: Array[Node3D] = []
	for entry in leg_specs:
		legs.append(Kit.leg(
			body,
			Vector3(entry.x, 0.7, entry.z),
			Vector3(0.2, 0.28, 0.22),
			Vector3(0.17, 0.24, 0.18),
			bristle,
			bristle_light,
			Vector3(0.24, 0.12, 0.28)
		))

	var spec := Kit.finish("boar", root, body, 1.4, 0.85)
	spec["legs"] = legs
	spec["tail"] = tail
	return spec

# ---------------------------------------------------------------------------
# 小野点：红鸟
# ---------------------------------------------------------------------------

static func bird() -> Dictionary:
	var root := Node3D.new()
	var body := Kit.group(root, "Body")
	var feather := Kit.hide_mat(Color(0.4, 0.05, 0.05))
	var feather_dark := Kit.hide_mat(Color(0.18, 0.02, 0.03))
	var chest := Kit.hide_mat(Color(0.85, 0.3, 0.08))
	var beak_mat := Kit.chitin(Color(0.85, 0.55, 0.1))
	var eye := Kit.glow(Color(1.0, 0.95, 0.6), 2.4)

	# 躯干：水滴形（球压扁 + 尾端收窄）。重心高、离地 —— 鸟和四足兽的剪影差别就在这里。
	Kit.ball(body, 0.4, feather, Vector3(0.0, 1.14, 0.02), Vector3(0.78, 0.92, 1.3))
	Kit.ball(body, 0.3, chest, Vector3(0.0, 1.02, 0.28), Vector3(0.72, 0.8, 0.78))
	Kit.box(body, Vector3(0.28, 0.26, 0.4), feather_dark, Vector3(0.0, 1.1, -0.42))
	# 颈 + 头 + 钩喙 + 眼 + 三根冠羽
	Kit.rod(body, 0.11, 0.28, feather, Vector3(0.0, 1.5, 0.14), Vector3(12.0, 0.0, 0.0), 6)
	Kit.ball(body, 0.21, feather, Vector3(0.0, 1.68, 0.2), Vector3(1.0, 0.94, 1.0))
	Kit.spike(body, 0.1, 0.3, beak_mat, Vector3(0.0, 1.66, 0.42), Vector3(96.0, 0.0, 0.0), 5)
	Kit.spike(body, 0.07, 0.16, beak_mat, Vector3(0.0, 1.6, 0.5), Vector3(126.0, 0.0, 0.0), 5)
	Kit.ball(body, 0.06, eye, Vector3(-0.12, 1.74, 0.3))
	Kit.ball(body, 0.06, eye, Vector3(0.12, 1.74, 0.3))
	for i in 3:
		var side := (float(i) - 1.0) * 0.1
		Kit.shard(body, Vector3(0.06, 0.26, 0.22), feather_dark, Vector3(side, 1.84, -0.02), Vector3(-46.0, 0.0, side * 70.0))
	# 双翼：肩关节组 + 三片带后掠角的羽板。翼展约 2.1 米，俯视下最醒目的一条横线。
	var wings: Array[Node3D] = []
	for side in [-1.0, 1.0]:
		var wing := Kit.group(body, "Wing", Vector3(side * 0.26, 1.3, 0.04))
		Kit.box(wing, Vector3(0.46, 0.08, 0.44), feather, Vector3(side * 0.24, 0.0, -0.04), Vector3(0.0, side * 12.0, side * 6.0))
		Kit.box(wing, Vector3(0.6, 0.06, 0.36), feather, Vector3(side * 0.6, -0.03, -0.2), Vector3(0.0, side * 30.0, side * 4.0))
		Kit.shard(wing, Vector3(0.09, 0.2, 0.44), feather_dark, Vector3(side * 0.92, -0.05, -0.34), Vector3(0.0, side * 52.0, 0.0))
		wings.append(wing)
	# 尾羽：三根长羽向后下方展开
	var tail := Kit.group(body, "Tail", Vector3(0.0, 1.06, -0.56))
	Kit.shard(tail, Vector3(0.34, 0.09, 0.86), feather, Vector3(0.0, -0.02, -0.42), Vector3(10.0, 0.0, 0.0), 0.5)
	Kit.shard(tail, Vector3(0.34, 0.08, 0.7), feather_dark, Vector3(-0.12, 0.04, -0.36), Vector3(6.0, 0.0, -14.0), 0.5)
	Kit.shard(tail, Vector3(0.34, 0.08, 0.7), feather_dark, Vector3(0.12, 0.04, -0.36), Vector3(6.0, 0.0, 14.0), 0.5)
	# 双腿 + 爪（短而粗，别做成两根亮黄筷子）
	var legs: Array[Node3D] = []
	for side in [-1.0, 1.0]:
		legs.append(Kit.leg(
			body,
			Vector3(side * 0.16, 0.96, 0.06),
			Vector3(0.11, 0.28, 0.13),
			Vector3(0.1, 0.3, 0.12),
			beak_mat,
			beak_mat,
			Vector3(0.24, 0.08, 0.26)
		))

	var spec := Kit.finish("bird", root, body, 1.75, 0.85)
	spec["legs"] = legs
	spec["wings"] = wings
	spec["tail"] = tail
	return spec
