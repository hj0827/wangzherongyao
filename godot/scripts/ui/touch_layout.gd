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
const SKILL_ARC_RADIUS := 330.0
# 四个技能按 Q / W / E / R 顺序从拇指侧向斜上方排开。
const SKILL_ARC_ANGLES_DEG := [185.0, 210.0, 235.0, 260.0]

# 右下角锚点偏移：回城/传送/召唤师排在技能弧上方，避免盖住 Q 的触摸区。
const UTILITY_BUTTON_SIZE := Vector2(96.0, 96.0)
const UTILITY_SUMMONER_RECT := Rect2(-784.0, -326.0, 96.0, 96.0)
const UTILITY_TELEPORT_RECT := Rect2(-688.0, -326.0, 96.0, 96.0)
const UTILITY_RECALL_RECT := Rect2(-592.0, -326.0, 96.0, 96.0)

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

static func dp_for_virtual(virtual_px: float, screen_height_px: float, viewport_height_px: float, dpi: float) -> float:
	if viewport_height_px <= 0.0 or dpi <= 0.0:
		return 0.0
	var physical_px := virtual_px * screen_height_px / viewport_height_px
	return physical_px / (dpi / 160.0)
