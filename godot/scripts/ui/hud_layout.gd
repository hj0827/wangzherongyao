extends RefCounted
## HUD 分区表：把「哪块 UI 放哪里」从节点里拆出来，变成一张可测的矩形表。
##
## 为什么要有它：之前每个面板各写各的 anchor/offset，没人算得清两块 UI 会不会撞上，
## 结果实机上出现「兵线播报压在商店按钮下面」「右下操作提示压在英雄面板上」
## 「攻击模式面板浮在兵线正中」。改成先算分区、再按分区摆节点，这些都能在无头测试里断言。
##
## 约定：
## - 所有矩形都是「视口像素」，左上角为原点。
## - 只描述常驻 HUD；播报条、阵亡遮罩、结算面板是瞬时的，不占分区。
## - 尺寸是「控件真实占位」，不是美好愿望：比分板 77 高、英雄卡 149 高都是
##   PanelContainer 按内容算出来的最小值。这里写小了，面板会向外顶出去压住别人，
##   而且测试还查不出来（tests/test_hud_layout.gd 里的常量要和这里对齐）。

const MARGIN := 16.0

# 桌面窗口的下限。再小，1600x900 的设计稿会被 canvas_items 缩到 0.7 以下，
# 13px 的说明文字实机只剩 9px，读不出来——那是另一种形式的「挡住」。
const MIN_VIEWPORT := Vector2(1280.0, 720.0)

# 顶部信息带
const MINIMAP_W := 234.0
const MINIMAP_H := 256.0
const SCORE_W := 460.0
const SCORE_H := 80.0
const SHOP_W := 150.0
const SHOP_H := 56.0
# 经济差条：贴在比分板右侧。顶部纵向没有余量（比分板下沿离安全区只剩 5px），
# 所以只能往横向要空间；实在挤不下就把宽度收敛到 0，由 HUD 隐藏整条。
const ECON_W := 208.0
const ECON_H := 58.0
const FEED_W := 320.0
const FEED_H := 132.0

# 底部操作带
const SKILL_W := 96.0
const SKILL_H := 112.0
const SKILL_GAP := 8.0
const SKILL_COUNT := 5
# 和技能条同宽（5*96+4*8），两块左边缘才会对齐成一列，而不是浮在上面。
const MODE_W := 512.0
const MODE_H := 84.0
const MODE_GAP := 8.0
const HERO_W := 640.0
const HERO_H := 152.0
const HINT_W := 840.0
const HINT_H := 24.0

# 触屏专用
const TOUCH_HERO_W := 840.0
const TOUCH_HERO_H := 180.0
const TOUCH_HERO_BOTTOM := 24.0
const JOYSTICK_SIZE := 260.0
const JOYSTICK_MARGIN := Vector2(12.0, 40.0)

# 中央「视野安全区」，按视口比例给。这块矩形里不许出现常驻 HUD：
# 镜头中心是兵线交汇、敌人出现、自己站位的唯一位置，占住它就是在挡玩家。
const SAFE_CENTER := Rect2(0.27, 0.14, 0.46, 0.54)

static func skills_width() -> float:
	return SKILL_W * float(SKILL_COUNT) + SKILL_GAP * float(SKILL_COUNT - 1)

# 窄窗口下优先压英雄面板，保证它和技能条之间永远留得出间隙。
static func hero_width(viewport_width: float) -> float:
	var room := viewport_width - MARGIN * 3.0 - skills_width() - 24.0
	return clampf(minf(HERO_W, room), 320.0, HERO_W)

# 提示行同理：不能伸到右下角操作簇底下，窄窗口时收窄（文字超长由 Label 省略）。
static func hint_width(viewport_width: float) -> float:
	var room := viewport_width - MARGIN * 2.0 - skills_width() - 24.0
	return clampf(minf(HINT_W, room), 360.0, HINT_W)

static func skill_rect(skills_zone: Rect2, index: int) -> Rect2:
	return Rect2(
		skills_zone.position + Vector2(float(index) * (SKILL_W + SKILL_GAP), 0.0),
		Vector2(SKILL_W, SKILL_H)
	)

static func safe_center(viewport: Vector2) -> Rect2:
	return Rect2(
		SAFE_CENTER.position.x * viewport.x,
		SAFE_CENTER.position.y * viewport.y,
		SAFE_CENTER.size.x * viewport.x,
		SAFE_CENTER.size.y * viewport.y
	)

## 返回 { 分区名: Rect2 }。touch=true 走拇指操作区的排法，false 走键鼠排法。
static func zones(viewport: Vector2, touch: bool) -> Dictionary:
	var w := maxf(viewport.x, 640.0)
	var h := maxf(viewport.y, 360.0)
	var m := MARGIN
	var z: Dictionary = {}

	# —— 顶部信息带：小地图在左、比分居中、商店在右上、播报退到商店下面 ——
	z["minimap"] = Rect2(m, m, MINIMAP_W, MINIMAP_H)
	z["score"] = Rect2((w - SCORE_W) * 0.5, m, SCORE_W, SCORE_H)
	var econ_left := (w + SCORE_W) * 0.5 + 10.0
	var econ_right := w - m - SHOP_W - 10.0
	z["econ"] = Rect2(econ_left, m, clampf(econ_right - econ_left, 0.0, ECON_W), ECON_H)
	z["shop"] = Rect2(w - m - SHOP_W, m, SHOP_W, SHOP_H)
	z["feed"] = Rect2(w - m - FEED_W, m + SHOP_H + 4.0, FEED_W, FEED_H)
	# 草丛状态是瞬时提示，放在比分正下方一行，不占分区，但也不许压住常驻控件。
	z["bush"] = Rect2((w - 320.0) * 0.5, m + SCORE_H + 6.0, 320.0, 26.0)

	var skills_w := skills_width()
	z["skills"] = Rect2(w - m - skills_w, h - m - SKILL_H, skills_w, SKILL_H)
	z["mode"] = Rect2(w - m - MODE_W, h - m - SKILL_H - MODE_GAP - MODE_H, MODE_W, MODE_H)

	if touch:
		# 拇指区：左下摇杆、右下攻击键 + 技能弧（弧由 TouchLayout 负责，这里只留摇杆和状态卡）。
		z["hero"] = Rect2((w - TOUCH_HERO_W) * 0.5, h - TOUCH_HERO_BOTTOM - TOUCH_HERO_H, TOUCH_HERO_W, TOUCH_HERO_H)
		z["joystick"] = Rect2(
			JOYSTICK_MARGIN.x,
			h - JOYSTICK_MARGIN.y - JOYSTICK_SIZE,
			JOYSTICK_SIZE,
			JOYSTICK_SIZE
		)
		# 攻击模式放在摇杆正上方：手机上右上角已经被播报和菜单占了，塞不下第三个面板。
		z["mode"] = Rect2(
			JOYSTICK_MARGIN.x,
			h - JOYSTICK_MARGIN.y - JOYSTICK_SIZE - 8.0 - MODE_H,
			MODE_W,
			MODE_H
		)
		z["hints"] = Rect2(m + 4.0, h - JOYSTICK_MARGIN.y - JOYSTICK_SIZE - 32.0, 560.0, HINT_H)
	else:
		# 键鼠区：状态卡贴左下、技能条贴右下，中间那片（英雄脚下）刻意留空。
		z["hero"] = Rect2(m, h - m - HERO_H, hero_width(w), HERO_H)
		z["hints"] = Rect2(m, h - m - HERO_H - HINT_H - 10.0, hint_width(w), HINT_H)

	return z
