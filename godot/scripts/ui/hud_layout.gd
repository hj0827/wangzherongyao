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

const TouchLayout = preload("res://scripts/ui/touch_layout.gd")

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
# 两行键位 + 底板内边距。原来 24px 只够一行，第二行会被裁掉。
const HINT_H := 46.0

# 触屏专用
# 手机端的状态卡不横在底部：那里是摇杆和技能弧（拇指要够得着），中间是战场。
# 改成小地图正下方一根窄柱，宽度直接跟小地图对齐 —— 两块合成一个「左上信息块」。
# 高度只够放下 56 头像 + 血/蓝两条 + 一行金币：血量本来就同时在头顶血条上。
const TOUCH_HERO_H := 132.0
const TOUCH_CARD_GAP := 6.0
# 回城进度条：底部正中一条细带。手机端放得下（状态卡已经搬去左上角，中间那条缝是空的）；
# 键鼠端正中下方被状态卡和键位提示占着，所以只有触屏才有这个分区。
const RECALL_W := 420.0
const RECALL_H := 28.0
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
	# 触屏端的攻击模式不再是横条面板，而是贴在攻击键旁的三颗圆（见 TouchLayout），
	# 所以这里只给键鼠端留 mode 分区。
	if not touch:
		z["mode"] = Rect2(w - m - MODE_W, h - m - SKILL_H - MODE_GAP - MODE_H, MODE_W, MODE_H)

	if touch:
		# 拇指区：左下摇杆、右下攻击键 + 技能弧（弧由 TouchLayout 负责，这里只留摇杆）。
		# 状态卡挂在小地图正下方，和小地图同宽同左沿：手机屏幕上「底部」和「中央」
		# 都要留给战斗，能放常驻信息的只有左上这条已经存在的竖列。
		z["hero"] = Rect2(m, m + MINIMAP_H + TOUCH_CARD_GAP, MINIMAP_W, TOUCH_HERO_H)
		# 回城条：左边是摇杆、右边是技能弧，中间这条 420 宽的带正好空着。
		z["recall"] = Rect2((w - RECALL_W) * 0.5, h - m - RECALL_H, RECALL_W, RECALL_H)
		z["joystick"] = Rect2(
			JOYSTICK_MARGIN.x,
			h - JOYSTICK_MARGIN.y - JOYSTICK_SIZE,
			JOYSTICK_SIZE,
			JOYSTICK_SIZE
		)
		# 暂停键贴在状态卡右侧、与它同顶。它原来写死在右侧 (1854,276)，
		# 被写死偏移的控件不进分区表，就永远测不出它压住了别人。
		# 放回左上角这条竖列，是因为右侧下半屏已经全给了拇指
		# （技能弧 + 攻击键 + 模式圆 + 功能列）。
		z["pause"] = Rect2(
			m + MINIMAP_W + 8.0,
			m + MINIMAP_H + TOUCH_CARD_GAP,
			TouchLayout.PAUSE_BUTTON_SIZE.x,
			TouchLayout.PAUSE_BUTTON_SIZE.y
		)
		# 提示行整块落在摇杆上方。HINT_H 从 24 涨到 46 之后，旧的固定 "-32" 会压到摇杆顶上。
		z["hints"] = Rect2(
			m + 4.0,
			h - JOYSTICK_MARGIN.y - JOYSTICK_SIZE - 8.0 - HINT_H,
			560.0,
			HINT_H
		)
	else:
		# 键鼠区：状态卡贴左下、技能条贴右下，中间那片（英雄脚下）刻意留空。
		z["hero"] = Rect2(m, h - m - HERO_H, hero_width(w), HERO_H)
		# 提示行和状态卡之间留 16px：10px 在 1600x900 缩到 1080p 窗口后只剩 6px，
		# 视觉上两块会粘在一起，看起来像提示压住了卡片。
		z["hints"] = Rect2(m, h - m - HERO_H - HINT_H - 16.0, hint_width(w), HINT_H)

	return z
