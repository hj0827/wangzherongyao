extends RefCounted

const MIN_DP := 48.0
const BUTTON_HEIGHT := 120.0
const PAUSE_BUTTON_SIZE := Vector2(120.0, 120.0)
const SKILL_TOUCH_SIZE := Vector2(128.0, 148.0)
const SKILL_DESKTOP_SIZE := Vector2(96.0, 112.0)
const PAUSE_MENU_BUTTON_HEIGHT := 120.0
const RESULT_BUTTON_SIZE := Vector2(260.0, 120.0)
const BOTTOM_PANEL_HEIGHT := 180.0
const ATTACK_BUTTON_SIZE := 152.0
const ATTACK_MARGIN := Vector2(18.0, 40.0)
# 技能弧半径从 330 拉到 380：330 时代圆心距只有 143，画出来的圆直径 116，
# 四颗之间只剩 27px 缝，实机上连成一串看不出是四个按钮。380 + 26° 间距后
# 圆心距 171、缝 55px，扫一眼能数清。
#
# 试过「窄屏（1600x900）自动收半径，把 W 的触摸框推出中央视野区」，结论是**不能收**：
# 收半径会把整条弧压向攻击键，圆心距掉到 148，正是最初那个「连成一串」。
# 16:9 下 W 的触摸框必然擦进视野区右下角约 48x103（0.7~0.73 宽、0.56~0.68 高那小块），
# 这是四个 128 宽的触摸框 + 一个 152 攻击键挤在 432px 宽的地块里的物理极限。
# 视野区那条规矩是给**面板**立的（挡住战场），不是给拇指上的半透明圆键 —— 别再收。
const SKILL_ARC_RADIUS := 380.0
# 四个技能按 Q / W / E / R 顺序从拇指侧向斜上方排开。
# 186° 让 Q 的框贴着攻击键左边（再往下会掉出屏幕底），264° 让 R 停在正上方偏左 ——
# 正上方那条竖带留给「攻击键 → 屏幕顶」的空白，不再堆圆。
const SKILL_ARC_ANGLES_DEG := [186.0, 212.0, 238.0, 264.0]

# 右下角锚点偏移：召唤师 / 传送 / 回城整列排在技能弧左侧，
# 由 utility_button_rects() 统一算（不再用写死的右下角 offset）。
const UTILITY_BUTTON_SIZE := 96.0
const UTILITY_BUTTON_GAP := 12.0
const UTILITY_BUTTON_COUNT := 3
# 功能键横排与 Q 左沿之间的呼吸位。小于 16px 两块就又粘成一坨。
const UTILITY_SKILL_GAP := 16.0

# 攻击模式（普攻 / 补刀 / 推塔）在真机上是一列圆按钮，紧贴攻击键左侧。
#
# 尺寸 88（攻击键 152 的 0.58）：76 只有攻击键的一半，真机上读起来像技能弧里
# 混进来的小挂件；88 配同一套双层金环之后才是「同一个人的缩一档」。
# 为什么不是更大：这三颗要挤在「攻击键左沿」和「E 触摸框右沿」之间那条竖缝里，
# 1600x900 下缝只有 35px 宽，靠的是**纵向**走廊 —— 从攻击键底到 E 框下沿约 285px。
# 3*88 + 2*8 = 280 刚好装下并留 5px；92 就顶进 E 的触摸区（实测压 2.6px）。
const MODE_BUTTON_SIZE := 88.0
const MODE_BUTTON_GAP := 8.0
const MODE_BUTTON_COUNT := 3
# 圆按钮与攻击键外沿之间的呼吸位。
const MODE_BUTTON_INSET := 10.0

# 锁定头像：遇见敌方英雄后浮在**他头顶**，点一下锁定、用一根短线连着他
# （位置由 LockBar 每帧按屏幕投影算，这里只定尺寸）。
# 120 虚拟 px 在 900 高视口 = 48dp，正好是能点准的下限；再小就点不准。
const LOCK_PORTRAIT_SIZE := 120.0
const LOCK_PORTRAIT_GAP := 8.0
const MAX_LOCK_PORTRAITS := 3

static func button_height(touch: bool, desktop: float) -> float:
	return BUTTON_HEIGHT if touch else desktop

static func attack_center(viewport_size: Vector2) -> Vector2:
	var half := ATTACK_BUTTON_SIZE * 0.5
	return viewport_size - ATTACK_MARGIN - Vector2(half, half)

static func skill_arc_centers(viewport_size: Vector2) -> Array[Vector2]:
	var centers: Array[Vector2] = []
	var attack := attack_center(viewport_size)
	for angle_deg in SKILL_ARC_ANGLES_DEG:
		var angle := deg_to_rad(float(angle_deg))
		centers.append(attack + Vector2(cos(angle), sin(angle)) * SKILL_ARC_RADIUS)
	return centers

# 技能弧的包围盒。只有包围盒能当「别往这儿放东西」的下界用：
# 逐个按钮去比会把 Q 和 R 之间的斜缝也算成空地，而那条缝其实是走不到的。
static func skill_arc_rect(viewport_size: Vector2) -> Rect2:
	var rects: Array[Rect2] = []
	for center in skill_arc_centers(viewport_size):
		rects.append(Rect2(center - SKILL_TOUCH_SIZE * 0.5, SKILL_TOUCH_SIZE))
	if rects.is_empty():
		return Rect2()
	var box := rects[0]
	for i in range(1, rects.size()):
		box = box.merge(rects[i])
	return box

# 三颗模式圆：中心线在攻击键左侧一条竖线上，最下面一颗与攻击键底对齐往上叠。
# 顺序与 AttackCluster.MODES 一致（普攻在最下，拇指最短路径）。
static func mode_button_centers(viewport_size: Vector2) -> Array[Vector2]:
	var centers: Array[Vector2] = []
	var attack := attack_center(viewport_size)
	var attack_half := ATTACK_BUTTON_SIZE * 0.5
	var radius := MODE_BUTTON_SIZE * 0.5
	var x := attack.x - attack_half - MODE_BUTTON_INSET - radius
	var base_y := attack.y + attack_half - radius
	var step := MODE_BUTTON_SIZE + MODE_BUTTON_GAP
	for i in MODE_BUTTON_COUNT:
		centers.append(Vector2(x, base_y - float(i) * step))
	return centers

static func mode_button_rects(viewport_size: Vector2) -> Array[Rect2]:
	var rects: Array[Rect2] = []
	var box := Vector2(MODE_BUTTON_SIZE, MODE_BUTTON_SIZE)
	for center in mode_button_centers(viewport_size):
		rects.append(Rect2(center - box * 0.5, box))
	return rects

## 回城 / 传送 / 召唤师三颗功能键：王者式的**底部横排**，紧贴技能弧左侧。
##
## 排布从左到右是 回城 → 传送 → 召唤师：召唤师离技能弧最近（拇指从技能滑过去最短），
## 回城最远、最不容易误触。整排底边与 Q 的触摸框底边对齐，正好落在拇指自然弧线上。
## 旧版是三颗竖着排在 Q 左侧，实战里和技能弧挤成一小摞圆点，分不清哪颗是回城。
static func utility_button_rects(viewport_size: Vector2) -> Array[Rect2]:
	var rects: Array[Rect2] = []
	var arc := skill_arc_centers(viewport_size)
	if arc.is_empty():
		return rects
	var q_center: Vector2 = arc[0]
	var q_left := q_center.x - SKILL_TOUCH_SIZE.x * 0.5
	var q_bottom := q_center.y + SKILL_TOUCH_SIZE.y * 0.5
	var right := q_left - UTILITY_SKILL_GAP
	var total := UTILITY_BUTTON_SIZE * float(UTILITY_BUTTON_COUNT) \
		+ UTILITY_BUTTON_GAP * float(UTILITY_BUTTON_COUNT - 1)
	var left := maxf(8.0, right - total)
	var bottom := minf(q_bottom, viewport_size.y - 16.0)
	var top := maxf(8.0, bottom - UTILITY_BUTTON_SIZE)
	for i in UTILITY_BUTTON_COUNT:
		var x := left + float(i) * (UTILITY_BUTTON_SIZE + UTILITY_BUTTON_GAP)
		rects.append(Rect2(Vector2(x, top), Vector2(UTILITY_BUTTON_SIZE, UTILITY_BUTTON_SIZE)))
	return rects

static func dp_for_virtual(virtual_px: float, screen_height_px: float, viewport_height_px: float, dpi: float) -> float:
	if viewport_height_px <= 0.0 or dpi <= 0.0:
		return 0.0
	var physical_px := virtual_px * screen_height_px / viewport_height_px
	return physical_px / (dpi / 160.0)
