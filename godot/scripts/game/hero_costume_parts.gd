extends RefCounted

## 5 个英雄的专属服饰几何（纯表现层，无 sim / 协议改动）。
##
## ★ 坐标口径（实测，写建之前先读这一段）
##   模型静止时 **+Z 是正面、-Z 是背后**（`arena` 里 facing_y=1 时 rotation.y=0，
##   而 0° 的模型脸朝 +Z）。这条判反一次，披风会盖在胸口、星环会挡在脸上，
##   而且不报错 —— 只能靠画廊图看出来。第一次就是这么翻车的。
##
##   其余轴向：+Y 向上、+X 是角色左侧、-X 是右侧（`hand_r` 在 x≈-0.70）。
##
## 单位与骨骼一致（未乘 model_root 缩放，渲染时再乘 ~1.45）：
##   脚底 y≈0.09、膝 y≈0.54、胯 y≈0.93、腰 y≈1.00、胸 y≈1.18、
##   肩 y≈1.44、颈 y≈1.52、头心 y≈1.60、发顶 y≈1.81；
##   躯干半宽 ≈0.18、肩关节 x≈±0.21、肘 x≈±0.46、手 x≈±0.70。
##
## 尺寸口径（21 米机位下英雄只占屏高 7%）：
##   - 大件必须**厚过一像素**：披风/下摆厚 0.02~0.03 就够，远看读轮廓不读厚度；
##   - 小件（纽扣、纹样、发丝）等于不存在 —— 每件配件都要在剪影上占一个凸起或缺口；
##   - 发光件面积要小、亮度要高（bloom 会膨胀），大面积发光会糊成白斑。
##
## 三条形态纪律（看实拍图改出来的，别换回盒子）：
##   1. **布用 sheet_mesh**：一整块 BoxMesh 披风在任何机位都读成「背着一块板」；
##   2. **甲用 dome / band**：压扁的球 + 环是护肩，盒子是砖；
##   3. **羽用 shard**：棱柱收尖才有羽尖，薄盒子只是木片。
##
## 第四个纪律（这一版新增）：**先穿衣服，再挂配件**。
##   通用角色包是背心短裤的西式游侠，不先包一层主色躯干/袖管/裤管，
##   21 米机位下最抢眼的是大片浅肤色 —— 五个英雄全是「光膀子的白人」，
##   再好看的护肩也救不回来。

const Kit = preload("res://scripts/game/hero_costume.gd")
const HeroLook = preload("res://scripts/game/hero_look.gd")

## 返回 {"parts": [已建的件名], "sway": {类别: [Node3D]}}
## sway 交给 UnitVisual 逐帧摆动（披风/下摆/围巾），没有骨骼也能有风感。
static func build(hero_type: String, skeleton: Skeleton3D) -> Dictionary:
	var result := {"parts": [], "sway": {}}
	if skeleton == null:
		return result
	match hero_type:
		"blade":
			_blade(skeleton, result)
		"mage":
			_mage(skeleton, result)
		"tank":
			_tank(skeleton, result)
		"archer":
			_archer(skeleton, result)
		"assassin":
			_assassin(skeleton, result)
	return result

static func _record(result: Dictionary, key: String, node: Node3D, sway_kind := "") -> void:
	result.parts.append(key)
	if sway_kind != "":
		var list: Array = result.sway.get(sway_kind, [])
		list.append({"node": node, "phase": float(list.size()) * 0.7})
		result.sway[sway_kind] = list

static func _palette(hero_type: String) -> Dictionary:
	return HeroLook.palette(hero_type)

## 每个人都要穿的「底衣」：躯干壳 + 肩轭 + 肩头圆盖 + 胯部围裙 + 袖子 + 裤管。
##
## 这一段是「看起来像英雄」和「看起来像光膀子的低模」之间的分界线。
## 半径比身体大 0.01~0.015：不改蒙皮、不穿模，关节处两段自然叠一点。
static func _dress(
	skeleton: Skeleton3D,
	body: Material,
	trim: Material,
	opts := {}
) -> void:
	var torso_top := float(opts.get("torso_top", 0.182))
	var torso_bottom := float(opts.get("torso_bottom", 0.138))
	var torso_height := float(opts.get("torso_height", 0.46))
	var torso_center := float(opts.get("torso_center", 0.07))
	var sleeve := float(opts.get("sleeve", 1.0))
	var legs := bool(opts.get("legs", true))
	var upper_radius := float(opts.get("arm_radius", 0.068))
	var leg_radius := float(opts.get("leg_radius", 0.110))
	var neck_radius := float(opts.get("collar", 0.0))
	var wrap: Dictionary = opts.get("pelvis_wrap", {})
	Kit.torso_shell(skeleton, torso_top, torso_bottom, torso_height, body, "Dress",
		torso_center, 14)
	# 肩轭：把躯干壳的顶口收到颈根。一段锥面同时封住皮肤与做成肩线，
	# 比「领口圆环」稳 —— 环做大了是一圈金呼啦圈，做小了封不住顶口。
	if neck_radius > 0.0:
		Kit.yoke(skeleton, torso_top, neck_radius, 0.13, body, 0.18)
	# 肩头圆盖：通用包在「躯干 ↔ 上臂」之间有一块裸肩三角，
	# 袖子从 upperarm 骨原点才开始，正好漏掉这一块。
	for side in ["l", "r"]:
		var cap := Kit.upright_pivot(skeleton, "upperarm_" + side, "ShoulderCap" + str(side).to_upper())
		if cap != null:
			Kit.dome(cap, upper_radius * 1.35, body, Vector3.ZERO, 0.85)
	# 胯部围裙：盖住通用包的浅色短裤（露肤面积里最刺眼的一块）。
	if not wrap.is_empty():
		Kit.pelvis_wrap(skeleton, float(wrap.get("top", torso_bottom + 0.004)),
			float(wrap.get("bottom", 0.190)), float(wrap.get("height", 0.26)),
			body, "Wrap", float(wrap.get("center_y", -0.07)))
	# 袖子：从肩到肘用主色布，小臂包一层护臂（通用包的裸小臂是最明显的露肤点）。
	for side in ["l", "r"]:
		Kit.limb_tube(skeleton, "upperarm_" + side, upper_radius, upper_radius * 0.92,
			0.20 * sleeve, body, 10, "Sleeve" + str(side).to_upper())
		Kit.limb_tube(skeleton, "lowerarm_" + side, upper_radius * 0.82, upper_radius * 0.70,
			0.20, trim, 10, "Bracer" + str(side).to_upper())
	if legs:
		for side in ["l", "r"]:
			# 大腿：整个包住（短裤以下露腿是「光膀子感」的主要来源）。
			Kit.limb_tube(skeleton, "thigh_" + side, leg_radius, leg_radius * 0.90,
				0.40, body, 10, "Thigh" + str(side).to_upper())
			# 小腿：只包到踝上，靴子留出来。
			Kit.limb_tube(skeleton, "calf_" + side, leg_radius * 0.84, leg_radius * 0.62,
				0.34, body, 10, "Calf" + str(side).to_upper())
			Kit.limb_band(skeleton, "calf_" + side, leg_radius * 0.86, 0.045, 0.035, trim, 10)

# ---------------------------------------------------------------------------
# 苍刃 · 战士：墨绿披风 + 右肩圆顶鳞甲（重）/ 左肩薄皮甲（轻）+ 旧金腰带
# ---------------------------------------------------------------------------

static func _blade(skeleton: Skeleton3D, result: Dictionary) -> void:
	var palette := _palette("blade")
	var primary: Color = palette.get("primary", Color(0.13, 0.24, 0.16))
	var metal: Color = palette.get("metal", Color(0.42, 0.32, 0.15))
	var cloth := Kit.cloth(primary.lightened(0.34))
	var cloth_dark := Kit.cloth(primary.darkened(0.12))
	var trim := Kit.gold(metal.darkened(0.2))
	var leather := Kit.plate(Color(0.12, 0.095, 0.07), 0.08)

	# 底衣：墨绿躯干 + 同色袖 + 深色裤 + 旧金护腕/护胫口
	_dress(skeleton, Kit.cloth(primary.darkened(0.15)), trim,
		{"arm_radius": 0.070, "leg_radius": 0.118, "torso_top": 0.180,
		"collar": 0.098, "pelvis_wrap": {"top": 0.172, "bottom": 0.198, "height": 0.22}})

	# --- 披风：从肩后垂到膝上的一整片布（-Z 方向弯出去） ---
	var cape := Kit.upright_pivot(skeleton, "spine_03", "BladeCape")
	if cape != null:
		cape.position = Vector3(0.0, 0.10, -0.055)
		# 上窄下宽、向背后弯：curve 传负数 = 往 -Z（背后）鼓。
		# 长度 0.82 是量出来的：0.94 时披风下缘扫到脚踝，21 米机位下把两条腿
		# 一起吞掉，读成「英雄下半身是一块黑布」。
		Kit.part(cape, Kit.sheet_mesh(0.30, 0.46, 0.82, -0.10, 0.016), cloth,
			Vector3.ZERO, Vector3(7.0, 0.0, 0.0))
		# 内衬短一截、颜色更深，露出的边缘就是「两层布」。
		Kit.part(cape, Kit.sheet_mesh(0.24, 0.36, 0.70, -0.06, 0.012), cloth_dark,
			Vector3(0.0, -0.02, 0.015), Vector3(5.0, 0.0, 0.0))
		# 破边：三片长短不一的垂布，挂在主布片下缘。
		for i in 3:
			Kit.part(cape, Kit.sheet_mesh(0.08, 0.10, 0.12 + 0.03 * float(i), -0.03, 0.008),
				cloth_dark,
				Vector3(-0.14 + 0.14 * float(i), -0.79, 0.02),
				Vector3(4.0, 0.0, 3.0 * float(i) - 3.0))
		# 下缘压边：一道比布亮一档的窄条，把「一整块黑布」切成「有边的披风」。
		Kit.part(cape, Kit.sheet_mesh(0.30, 0.46, 0.05, -0.10, 0.0, 5, 1),
			Kit.cloth(primary.lightened(0.55)),
			Vector3(0.0, -0.78, 0.0), Vector3(7.0, 0.0, 0.0))
		# 肩部压条：把布收拢在锁骨高度，否则俯视是一块飘在背后的板。
		Kit.part(cape, Kit.box_mesh(Vector3(0.36, 0.045, 0.075)), cloth_dark,
			Vector3(0.0, 0.015, 0.045))
		_record(result, "blade_cape", cape, "cape")

	# --- 右肩：圆顶甲 + 金环 + 外翻刺（「重」的一侧） ---
	var shoulder_r := Kit.upright_pivot(skeleton, "upperarm_r", "BladePauldronR")
	if shoulder_r != null:
		shoulder_r.rotation_degrees = Vector3(0.0, 0.0, -12.0)
		Kit.dome(shoulder_r, 0.135, leather, Vector3(0.0, 0.038, 0.0), 0.5)
		Kit.band(shoulder_r, 0.122, 0.142, trim, Vector3(0.0, 0.026, 0.0), Vector3.ZERO)
		Kit.part(shoulder_r, Kit.shard_mesh(Vector3(0.07, 0.16, 0.055)), trim,
			Vector3(0.085, 0.085, 0.0), Vector3(-14.0, 0.0, 38.0))
		_record(result, "blade_pauldron_r", shoulder_r)

	# --- 左肩：一片薄皮甲（「轻」的一侧，不对称才像战士） ---
	var shoulder_l := Kit.upright_pivot(skeleton, "upperarm_l", "BladePauldronL")
	if shoulder_l != null:
		shoulder_l.rotation_degrees = Vector3(0.0, 0.0, 10.0)
		Kit.dome(shoulder_l, 0.095, leather, Vector3(0.0, 0.030, 0.0), 0.42)
		Kit.band(shoulder_l, 0.083, 0.100, trim, Vector3(0.0, 0.022, 0.0), Vector3.ZERO, 14)
		_record(result, "blade_pauldron_l", shoulder_l)

	# --- 腰带：窄皮带 + 旧金方扣（扣在身前 +Z） ---
	var belt := Kit.upright_pivot(skeleton, "pelvis", "BladeBelt")
	if belt != null:
		belt.position = Vector3(0.0, 0.055, 0.0)
		Kit.band(belt, 0.122, 0.152, leather, Vector3.ZERO, Vector3.ZERO, 18)
		Kit.part(belt, Kit.box_mesh(Vector3(0.095, 0.080, 0.032)), trim, Vector3(0.0, 0.0, 0.152))
		Kit.part(belt, Kit.box_mesh(Vector3(0.060, 0.050, 0.040)),
			Kit.plate(primary.darkened(0.5), 0.2), Vector3(0.0, 0.0, 0.169))
		_record(result, "blade_belt", belt)
		# 腰侧垂布
		var sash := Kit.group(belt, "BladeSash")
		sash.position = Vector3(0.140, 0.0, 0.02)
		Kit.part(sash, Kit.sheet_mesh(0.09, 0.115, 0.42, -0.015, 0.010), cloth,
			Vector3.ZERO, Vector3(0.0, 0.0, 4.0))
		Kit.part(sash, Kit.sheet_mesh(0.065, 0.085, 0.30, -0.012, 0.008), cloth_dark,
			Vector3(0.02, -0.02, 0.025), Vector3(0.0, 0.0, 9.0))
		_record(result, "blade_sash", sash, "skirt")

# ---------------------------------------------------------------------------
# 星璃 · 法师：星纹长裙 + 金月冠 + 背后星环 + 宽袖
# ---------------------------------------------------------------------------

static func _mage(skeleton: Skeleton3D, result: Dictionary) -> void:
	var palette := _palette("mage")
	var primary: Color = palette.get("primary", Color(0.16, 0.13, 0.34))
	var metal: Color = palette.get("metal", Color(0.55, 0.44, 0.18))
	var glow_color: Color = palette.get("glow", Color(0.62, 0.52, 1.0))
	var robe := Kit.cloth(primary.lightened(0.06))
	var robe_dark := Kit.cloth(primary.darkened(0.34))
	var trim := Kit.gold(metal)
	var star := Kit.glow(glow_color, 1.1)

	# 底衣：靛紫罗袍上身 + 宽袖。长裙由 mage_skirt 负责，这里不包腿。
	_dress(skeleton, robe, trim,
		{"arm_radius": 0.072, "torso_top": 0.176, "torso_bottom": 0.140, "legs": false,
		"collar": 0.092, "pelvis_wrap": {"top": 0.168, "bottom": 0.188, "height": 0.16}})

	# --- 长裙：敞口圆台，比若干块板拼的圆台自然得多 ---
	var skirt := Kit.upright_pivot(skeleton, "pelvis", "MageSkirt")
	if skirt != null:
		# 底半径 0.30（≈0.43m）刚好盖住大腿、露出靴尖；0.50 会变成一个钟罩。
		Kit.part(skirt, Kit.cone_mesh(0.175, 0.30, 0.62, 18), robe,
			Vector3(0.0, -0.29, 0.0), Vector3.ZERO)
		Kit.band(skirt, 0.288, 0.305, trim, Vector3(0.0, -0.60, 0.0), Vector3.ZERO, 24)
		# 前开衩的两片：让走路时能看到腿，不是一口钟。
		for side in [-1.0, 1.0]:
			Kit.part(skirt, Kit.sheet_mesh(0.13, 0.18, 0.40, 0.015, 0.008), robe_dark,
				Vector3(side * 0.085, 0.0, 0.15), Vector3(4.0, 0.0, side * 5.0))
		# 腰封
		Kit.band(skirt, 0.112, 0.145, robe_dark, Vector3(0.0, 0.02, 0.0), Vector3.ZERO, 18)
		Kit.part(skirt, Kit.box_mesh(Vector3(0.075, 0.09, 0.035)), trim, Vector3(0.0, 0.02, 0.142))
		_record(result, "mage_skirt", skirt, "skirt")

	# --- 背后星环：法师的远看标记，竖着立在背后、缓慢自转（-Z） ---
	var halo := Kit.upright_pivot(skeleton, "spine_03", "MageHalo")
	if halo != null:
		halo.position = Vector3(0.0, 0.20, -0.15)
		var ring := Kit.group(halo, "HaloRing")
		# 竖直环 = torus 绕 X 转 90°（默认躺在 XZ 平面）。
		Kit.part(ring, Kit.torus_mesh(0.155, 0.175, 26), Kit.glow(glow_color, 0.7),
			Vector3.ZERO, Vector3(90.0, 0.0, 0.0))
		for i in 4:
			var angle := TAU * float(i) / 4.0 + PI * 0.25
			Kit.part(ring, Kit.shard_mesh(Vector3(0.035, 0.075, 0.012)), star,
				Vector3(cos(angle) * 0.165, sin(angle) * 0.165, 0.0),
				Vector3(0.0, 0.0, rad_to_deg(angle) - 90.0))
		_record(result, "mage_halo", ring, "halo")

	# --- 额前金月冠 + 星坠（+Z 一侧是脸） ---
	var head := Kit.upright_pivot(skeleton, "Head", "MageCrown")
	if head != null:
		head.position = Vector3(0.0, 0.11, 0.085)
		Kit.part(head, Kit.torus_mesh(0.045, 0.062, 14), trim, Vector3.ZERO, Vector3(90.0, 0.0, 0.0))
		Kit.part(head, Kit.shard_mesh(Vector3(0.028, 0.07, 0.028)), trim,
			Vector3(0.0, 0.065, 0.0), Vector3(-18.0, 0.0, 0.0))
		Kit.part(head, Kit.sphere_mesh(0.016, 8), star, Vector3(0.0, 0.0, 0.03))
		_record(result, "mage_crown", head)

	# --- 宽袖：小臂外侧一片会垂的布 + 金环 ---
	for side in ["l", "r"]:
		var sign := 1.0 if side == "l" else -1.0
		var arm := Kit.upright_pivot(skeleton, "lowerarm_" + side, "MageSleeve" + str(side).to_upper())
		if arm == null:
			continue
		Kit.part(arm, Kit.sheet_mesh(0.105, 0.175, 0.26, -0.01, 0.008), robe,
			Vector3(sign * 0.02, -0.02, 0.0), Vector3(0.0, 0.0, sign * -6.0))
		Kit.band(arm, 0.085, 0.098, trim, Vector3(sign * 0.02, -0.26, 0.0), Vector3(0.0, 90.0, 0.0), 14)
		_record(result, "mage_sleeves", arm, "sleeve")

	# --- 双肩金月牙（小件，只做「有金饰」的暗示） ---
	for side in ["l", "r"]:
		var sign := 1.0 if side == "l" else -1.0
		var shoulder := Kit.upright_pivot(skeleton, "upperarm_" + side, "MageMoon" + str(side).to_upper())
		if shoulder == null:
			continue
		shoulder.rotation_degrees = Vector3(0.0, 0.0, sign * 14.0)
		Kit.dome(shoulder, 0.072, trim, Vector3(0.0, 0.030, 0.0), 0.3)
		Kit.part(shoulder, Kit.shard_mesh(Vector3(0.026, 0.075, 0.026)), trim,
			Vector3(sign * 0.015, 0.085, 0.0), Vector3(0.0, 0.0, sign * -22.0))
		_record(result, "mage_shoulders", shoulder)

# ---------------------------------------------------------------------------
# 铁壁 · 坦克：青铜兽首重甲（双肩）+ 背后战旗 + 胸口铜盘 + 铁札甲裙
# ---------------------------------------------------------------------------

static func _tank(skeleton: Skeleton3D, result: Dictionary) -> void:
	var palette := _palette("tank")
	var secondary: Color = palette.get("secondary", Color(0.58, 0.24, 0.09))
	var metal: Color = palette.get("metal", Color(0.40, 0.30, 0.14))
	var iron := Kit.plate(Color(0.155, 0.148, 0.142), 0.15)
	var iron_dark := Kit.plate(Color(0.082, 0.076, 0.072), 0.10)
	var bronze := Kit.gold(metal)
	var tabard := Kit.cloth(secondary)
	var ember := Kit.glow(Color(1.0, 0.58, 0.20), 1.0)

	# 底衣：铁甲上身 + 铁袖 + 皮护腿（立绘里是全身札甲，露肤最少的一个）
	_dress(skeleton, iron, bronze,
		{"arm_radius": 0.076, "leg_radius": 0.132, "torso_top": 0.196, "torso_bottom": 0.152,
		"collar": 0.104, "pelvis_wrap": {"top": 0.188, "bottom": 0.212, "height": 0.22}})

	# --- 背后战旗：斜插的杆 + 会飘的旗面（-Z 背后）。旗面大、慢，是「重装」的读点 ---
	var banner := Kit.upright_pivot(skeleton, "spine_03", "TankBanner")
	if banner != null:
		banner.position = Vector3(-0.11, 0.11, -0.16)
		Kit.part(banner, Kit.cylinder_mesh(0.014, 0.86, 6), Kit.plate(Color(0.19, 0.14, 0.08), 0.2),
			Vector3(0.0, 0.20, 0.0), Vector3(0.0, 0.0, -7.0))
		Kit.part(banner, Kit.sphere_mesh(0.030, 8), bronze, Vector3(0.0, 0.62, 0.0))
		var flag := Kit.group(banner, "BannerFlag")
		flag.position = Vector3(-0.02, 0.56, -0.01)
		# 旗面：从杆顶往身体左侧铺开，稍微向外卷。
		Kit.part(flag, Kit.sheet_mesh(0.22, 0.28, 0.40, -0.035, 0.018, 4, 3), tabard,
			Vector3(-0.11, 0.0, 0.0), Vector3(0.0, 0.0, -4.0))
		Kit.part(flag, Kit.sheet_mesh(0.22, 0.27, 0.030, 0.0, 0.0, 4, 1), bronze,
			Vector3(-0.11, -0.395, 0.0), Vector3(0.0, 0.0, -4.0))
		_record(result, "tank_banner", flag, "banner")

	# --- 双肩：大圆顶铁甲 + 铜环（左肩加兽眼与外角，更重） ---
	var shoulder_l := Kit.upright_pivot(skeleton, "upperarm_l", "TankPauldronL")
	if shoulder_l != null:
		shoulder_l.rotation_degrees = Vector3(0.0, 0.0, 9.0)
		Kit.dome(shoulder_l, 0.165, iron, Vector3(0.0, 0.040, 0.0), 0.55)
		Kit.part(shoulder_l, Kit.box_mesh(Vector3(0.24, 0.045, 0.26)), iron_dark,
			Vector3(0.0, -0.070, 0.0))
		Kit.band(shoulder_l, 0.145, 0.165, bronze, Vector3(0.0, 0.024, 0.0), Vector3.ZERO, 18)
		Kit.part(shoulder_l, Kit.sphere_mesh(0.028, 8), ember, Vector3(-0.070, 0.018, 0.125))
		Kit.part(shoulder_l, Kit.sphere_mesh(0.028, 8), ember, Vector3(0.070, 0.018, 0.125))
		Kit.part(shoulder_l, Kit.shard_mesh(Vector3(0.062, 0.17, 0.05)), bronze,
			Vector3(0.145, 0.085, 0.0), Vector3(-12.0, 0.0, 32.0))
		_record(result, "tank_pauldron_l", shoulder_l)

	var shoulder_r := Kit.upright_pivot(skeleton, "upperarm_r", "TankPauldronR")
	if shoulder_r != null:
		shoulder_r.rotation_degrees = Vector3(0.0, 0.0, -9.0)
		Kit.dome(shoulder_r, 0.140, iron, Vector3(0.0, 0.036, 0.0), 0.55)
		Kit.part(shoulder_r, Kit.box_mesh(Vector3(0.21, 0.040, 0.23)), iron_dark,
			Vector3(0.0, -0.062, 0.0))
		Kit.band(shoulder_r, 0.122, 0.140, bronze, Vector3(0.0, 0.022, 0.0), Vector3.ZERO, 18)
		Kit.part(shoulder_r, Kit.shard_mesh(Vector3(0.05, 0.14, 0.045)), iron_dark,
			Vector3(-0.115, 0.085, 0.0), Vector3(-10.0, 0.0, -30.0))
		_record(result, "tank_pauldron_r", shoulder_r)

	# --- 胸口铜盘：立绘里最醒目的圆形兽面 ---
	var chest := Kit.upright_pivot(skeleton, "spine_02", "TankChest")
	if chest != null:
		chest.position = Vector3(0.0, 0.03, 0.150)
		Kit.part(chest, Kit.cylinder_mesh(0.075, 0.025, 16), bronze, Vector3.ZERO, Vector3(90.0, 0.0, 0.0))
		Kit.part(chest, Kit.torus_mesh(0.068, 0.085, 18), iron_dark, Vector3.ZERO, Vector3(90.0, 0.0, 0.0))
		_record(result, "tank_chest", chest)

	# --- 腰间披巾（两条锈橙）+ 铜环 + 四片甲裙 ---
	var belt := Kit.upright_pivot(skeleton, "pelvis", "TankSash")
	if belt != null:
		belt.position = Vector3(0.0, 0.05, 0.0)
		Kit.band(belt, 0.126, 0.164, iron_dark, Vector3.ZERO, Vector3.ZERO, 18)
		Kit.part(belt, Kit.torus_mesh(0.048, 0.066, 14), bronze, Vector3(0.0, 0.0, 0.158), Vector3(90.0, 0.0, 0.0))
		for i in 2:
			var strip := Kit.group(belt, "Sash%d" % i)
			strip.position = Vector3(-0.070 + 0.14 * float(i), -0.02, 0.135)
			Kit.part(strip, Kit.sheet_mesh(0.085, 0.115, 0.36, 0.02, 0.012), tabard,
				Vector3.ZERO, Vector3(0.0, 0.0, (-1.0 if i == 0 else 1.0) * 5.0))
			_record(result, "tank_sash", strip, "skirt")
		for i in 4:
			var angle := TAU * float(i) / 4.0 + PI * 0.25
			var tasset := Kit.group(belt, "Tasset%d" % i)
			tasset.position = Vector3(sin(angle) * 0.135, -0.05, cos(angle) * 0.135)
			tasset.rotation_degrees = Vector3(0.0, rad_to_deg(angle), 0.0)
			Kit.part(tasset, Kit.sheet_mesh(0.16, 0.19, 0.24, 0.012, 0.006, 4, 2), iron,
				Vector3(0.0, 0.0, 0.015), Vector3(6.0, 0.0, 0.0))
			Kit.part(tasset, Kit.sheet_mesh(0.16, 0.18, 0.028, 0.0, 0.0, 4, 1), bronze,
				Vector3(0.0, -0.245, 0.045), Vector3(6.0, 0.0, 0.0))
			_record(result, "tank_tassets", tasset, "skirt")

# ---------------------------------------------------------------------------
# 翎羽 · 射手：白羽披肩 + 背后箭袋 + 青碧腰带 + 米白短下摆
# ---------------------------------------------------------------------------

static func _archer(skeleton: Skeleton3D, result: Dictionary) -> void:
	var palette := _palette("archer")
	var primary: Color = palette.get("primary", Color(0.62, 0.62, 0.55))
	var secondary: Color = palette.get("secondary", Color(0.10, 0.36, 0.32))
	var metal: Color = palette.get("metal", Color(0.36, 0.30, 0.16))
	var cream := Kit.cloth(primary)
	var teal := Kit.cloth(secondary.lightened(0.10))
	var leather := Kit.plate(metal.darkened(0.32), 0.1)
	var feather := Kit.cloth(Color(0.90, 0.92, 0.88))
	var feather_teal := Kit.cloth(secondary.lightened(0.34))
	var trim := Kit.gold(metal)

	# 底衣：米白上衣 + 米白袖 + 青碧护腕 + 米白腿袜 + 青碧护胫口
	_dress(skeleton, cream, teal,
		{"arm_radius": 0.066, "leg_radius": 0.112, "torso_top": 0.170, "torso_bottom": 0.138,
		"collar": 0.090, "pelvis_wrap": {"top": 0.166, "bottom": 0.186, "height": 0.16}})

	# --- 白羽披肩：肩背上一圈参差羽片（只在背后与两侧，胸前留空）+ 青碧滚边 ---
	var mantle := Kit.upright_pivot(skeleton, "spine_03", "ArcherMantle")
	if mantle != null:
		mantle.position = Vector3(0.0, 0.10, 0.0)
		for i in 13:
			# 角度从背后（-Z，180°）向两侧铺开，收到 ±110°：正面不退到胸口。
			var angle := PI + (float(i) / 12.0 - 0.5) * PI * 1.30
			var radius := 0.150 + 0.014 * sin(float(i) * 2.1)
			var length := 0.16 + 0.10 * absf(sin(float(i) * 1.7))
			var node := Kit.group(mantle, "Feather%d" % i)
			# 羽根贴着肩线、羽尖向外下方垂：绕 Y 转到圆弧切向，再向外倾。
			node.position = Vector3(cos(angle) * radius * 1.35, 0.03, sin(angle) * radius * 1.0)
			node.rotation_degrees = Vector3(0.0, rad_to_deg(angle) + 90.0,
				cos(angle) * 55.0)
			Kit.feather(node, 0.058, length, feather if i % 3 != 1 else feather_teal,
				Vector3(0.0, -length * 0.42, 0.0), Vector3.ZERO, 0.3)
		Kit.band(mantle, 0.120, 0.146, teal, Vector3(0.0, 0.015, 0.0), Vector3.ZERO, 18)
		_record(result, "archer_mantle", mantle, "cape")

	# --- 背后箭袋：桶 + 三支箭（羽尾朝上）。只留三支，多了远看是一团白点 ---
	var quiver := Kit.upright_pivot(skeleton, "spine_02", "ArcherQuiver")
	if quiver != null:
		quiver.position = Vector3(0.13, 0.06, -0.145)
		quiver.rotation_degrees = Vector3(0.0, 0.0, -14.0)
		Kit.part(quiver, Kit.cylinder_mesh(0.046, 0.32, 10), leather, Vector3(0.0, 0.03, 0.0))
		Kit.band(quiver, 0.044, 0.058, teal, Vector3(0.0, 0.175, 0.0), Vector3.ZERO, 12)
		for i in 3:
			var offset := (float(i) - 1.0) * 0.022
			Kit.part(quiver, Kit.cylinder_mesh(0.006, 0.26, 5),
				Kit.plate(Color(0.46, 0.38, 0.26), 0.1), Vector3(offset, 0.27, offset * 0.4))
			Kit.feather(quiver, 0.040, 0.09, feather, Vector3(offset, 0.39, offset * 0.4),
				Vector3(0.0, 0.0, 10.0))
		_record(result, "archer_quiver", quiver, "quiver")

	# --- 腰带 + 垂羽 + 米白短下摆 ---
	var skirt := Kit.upright_pivot(skeleton, "pelvis", "ArcherSkirt")
	if skirt != null:
		skirt.position = Vector3(0.0, 0.05, 0.0)
		Kit.band(skirt, 0.118, 0.146, teal, Vector3.ZERO, Vector3.ZERO, 18)
		Kit.part(skirt, Kit.torus_mesh(0.038, 0.054, 12), trim, Vector3(0.0, 0.0, 0.144), Vector3(90.0, 0.0, 0.0))
		for i in 4:
			var angle := TAU * float(i) / 4.0 + PI * 0.25
			var panel := Kit.group(skirt, "Skirt%d" % i)
			panel.position = Vector3(sin(angle) * 0.135, -0.02, cos(angle) * 0.135)
			panel.rotation_degrees = Vector3(0.0, rad_to_deg(angle), 0.0)
			Kit.part(panel, Kit.sheet_mesh(0.14, 0.18, 0.24, -0.012, 0.008, 4, 2), cream,
				Vector3.ZERO, Vector3(7.0, 0.0, 0.0))
			_record(result, "archer_skirt", panel, "skirt")
		# 左胯三根垂羽
		var bundle := Kit.group(skirt, "FeatherBundle")
		bundle.position = Vector3(0.140, 0.0, -0.01)
		for i in 3:
			Kit.feather(bundle, 0.040, 0.20 + 0.045 * float(i),
				feather_teal if i == 1 else feather,
				Vector3(0.010 * float(i), -0.13 - 0.03 * float(i), 0.0),
				Vector3(0.0, 0.0, 6.0 - 6.0 * float(i)), 0.3)
		_record(result, "archer_sash", bundle, "skirt")

	# --- 头饰：丸子头上的两簇白羽 + 一枚青玉环（+Z 是脸） ---
	var head := Kit.upright_pivot(skeleton, "Head", "ArcherHairpins")
	if head != null:
		head.position = Vector3(0.0, 0.08, 0.02)
		for side in [-1.0, 1.0]:
			for i in 2:
				Kit.feather(head, 0.040, 0.11 + 0.035 * float(i), feather,
					Vector3(side * (0.085 + 0.022 * float(i)), 0.055, -0.015),
					Vector3(-20.0, 0.0, side * (28.0 + 10.0 * float(i))), 0.3)
		Kit.band(head, 0.040, 0.054, Kit.glow(secondary.lightened(0.42), 0.4),
			Vector3(0.0, 0.015, 0.088), Vector3(90.0, 0.0, 0.0), 12)
		_record(result, "archer_hairpins", head)

# ---------------------------------------------------------------------------
# 墨鸦 · 刺客：兜帽 + 单侧紫斗篷 + 颈围巾 + 后腰双匕鞘
# ---------------------------------------------------------------------------

static func _assassin(skeleton: Skeleton3D, result: Dictionary) -> void:
	var palette := _palette("assassin")
	var primary: Color = palette.get("primary", Color(0.10, 0.09, 0.11))
	var secondary: Color = palette.get("secondary", Color(0.26, 0.15, 0.36))
	var metal: Color = palette.get("metal", Color(0.46, 0.44, 0.42))
	var leather := Kit.plate(primary.lightened(0.18), 0.14)
	var cloth_dark := Kit.cloth(primary.lightened(0.06))
	var purple := Kit.cloth(secondary.lightened(0.10))
	var purple_dark := Kit.cloth(secondary.darkened(0.30))
	var steel := Kit.plate(metal, 0.6)

	# 底衣：近黑皮衣 + 紫护腕 + 黑裤。刺客露肤最少，越黑越像。
	_dress(skeleton, cloth_dark, purple_dark,
		{"arm_radius": 0.066, "leg_radius": 0.112, "torso_top": 0.170, "torso_bottom": 0.138,
		"collar": 0.090, "pelvis_wrap": {"top": 0.166, "bottom": 0.186, "height": 0.16}})

	# --- 兜帽：包住后脑（-Z）的半圆 + 背后的尖 + 两侧颊片。正面必须留出脸 ---
	var head := Kit.upright_pivot(skeleton, "Head", "AssassinHood")
	if head != null:
		head.position = Vector3(0.0, 0.02, 0.0)
		# 球心往背后推 0.05、半径 0.112、压扁 0.85：正面只到 z≈+0.06，
		# 脸（z≈+0.12）与刘海都留出来。球做大了整张脸会埋进布里。
		Kit.dome(head, 0.112, cloth_dark, Vector3(0.0, 0.040, -0.050), 0.85)
		Kit.part(head, Kit.sheet_mesh(0.24, 0.27, 0.24, -0.05, 0.010), cloth_dark,
			Vector3(0.0, 0.05, -0.02), Vector3(0.0, 0.0, 0.0))
		Kit.part(head, Kit.shard_mesh(Vector3(0.13, 0.20, 0.045)), purple_dark,
			Vector3(0.0, 0.00, -0.16), Vector3(-48.0, 0.0, 0.0))
		for side in [-1.0, 1.0]:
			Kit.part(head, Kit.sheet_mesh(0.05, 0.07, 0.18, -0.015, 0.006), cloth_dark,
				Vector3(side * 0.115, -0.05, 0.005), Vector3(0.0, 0.0, side * -6.0))
		_record(result, "assassin_hood", head)

	# --- 单侧紫斗篷：三片长短不一的布，全在左侧（+X）背后，不对称才有刺客味 ---
	var cloak := Kit.upright_pivot(skeleton, "spine_03", "AssassinCloak")
	if cloak != null:
		cloak.position = Vector3(0.10, 0.10, -0.075)
		var panels := [
			{"x": 0.02, "len": 0.92, "w": 0.22, "rot": 3.0},
			{"x": 0.18, "len": 0.78, "w": 0.19, "rot": 7.0},
			{"x": 0.31, "len": 0.58, "w": 0.16, "rot": 12.0},
		]
		for i in panels.size():
			var entry: Dictionary = panels[i]
			var panel := Kit.group(cloak, "CloakPanel%d" % i)
			panel.position = Vector3(float(entry.x), 0.0, 0.0)
			panel.rotation_degrees = Vector3(4.0, float(entry.rot), float(entry.rot) * 0.4)
			Kit.part(panel, Kit.sheet_mesh(float(entry.w) * 0.5, float(entry.w),
				float(entry.len), -0.08, 0.012), purple if i != 1 else purple_dark,
				Vector3.ZERO, Vector3.ZERO)
			_record(result, "assassin_cloak", panel, "cape")
		Kit.part(cloak, Kit.box_mesh(Vector3(0.38, 0.040, 0.085)), purple_dark,
			Vector3(0.14, 0.0, 0.02))

	# --- 颈围巾：一圈紫布 + 背后一条长尾 ---
	var neck := Kit.upright_pivot(skeleton, "neck_01", "AssassinScarf")
	if neck != null:
		Kit.band(neck, 0.082, 0.116, purple, Vector3(0.0, -0.005, 0.0), Vector3.ZERO, 16)
		var tail := Kit.group(neck, "ScarfTail")
		tail.position = Vector3(0.06, -0.02, -0.085)
		Kit.part(tail, Kit.sheet_mesh(0.09, 0.115, 0.36, -0.05, 0.010), purple,
			Vector3.ZERO, Vector3(-14.0, 0.0, 3.0))
		_record(result, "assassin_scarf", tail, "scarf")

	# --- 后腰双匕鞘（-Z） ---
	var belt := Kit.upright_pivot(skeleton, "pelvis", "AssassinSheath")
	if belt != null:
		belt.position = Vector3(0.0, 0.05, 0.0)
		Kit.band(belt, 0.110, 0.138, leather, Vector3.ZERO, Vector3.ZERO, 16)
		for side in [-1.0, 1.0]:
			var sheath := Kit.group(belt, "Sheath%d" % int(side))
			sheath.position = Vector3(side * 0.10, 0.0, -0.115)
			sheath.rotation_degrees = Vector3(0.0, 0.0, side * 24.0)
			Kit.part(sheath, Kit.box_mesh(Vector3(0.040, 0.22, 0.040)), leather,
				Vector3(0.0, -0.11, 0.0))
			Kit.part(sheath, Kit.box_mesh(Vector3(0.045, 0.028, 0.045)), steel,
				Vector3(0.0, 0.0, 0.0))
		_record(result, "assassin_sheath", belt)

	# --- 右肩薄钢护肩（单边） ---
	var pauldron := Kit.upright_pivot(skeleton, "upperarm_r", "AssassinPauldron")
	if pauldron != null:
		pauldron.rotation_degrees = Vector3(0.0, 0.0, -16.0)
		Kit.dome(pauldron, 0.098, steel, Vector3(0.0, 0.026, 0.0), 0.38)
		Kit.band(pauldron, 0.086, 0.102, steel, Vector3(0.0, 0.019, 0.0), Vector3.ZERO, 14)
		Kit.part(pauldron, Kit.shard_mesh(Vector3(0.038, 0.11, 0.035)), steel,
			Vector3(-0.075, 0.070, -0.015), Vector3(-12.0, 0.0, -42.0))
		_record(result, "assassin_pauldron", pauldron)
