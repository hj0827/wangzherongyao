extends RefCounted

# 河道传送阵：站上阵眼后引导 2.5 秒传送到对端；移动、施法、普攻或受击都会打断。
# 完成一次后个人冷却 45 秒，避免变成无成本的全球位移。

const MapLayout = preload("res://sim/map/map_layout.gd")

const CHANNEL_TIME := 2.5
const COOLDOWN := 45.0
# 阵眼半径 = 地面阵盘半径。两处各写一个 3.0 的后果是「看着站在阵里，判定却说不在」，
# 或者反过来「站在阵外的水边还能传」。唯一真身在 MapLayout。
const PAD_RADIUS := MapLayout.PAD_DISC_RADIUS
const MOVE_EPSILON := 0.05

static func pad_at(point: Vector2) -> Dictionary:
	for pad in MapLayout.TELEPORT_PADS:
		if point.distance_to(pad.pos) <= PAD_RADIUS:
			return pad
	return {}

static func partner_of(pad_id: String) -> Dictionary:
	for pad in MapLayout.TELEPORT_PADS:
		if str(pad.get("id", "")) != pad_id:
			continue
		for other in MapLayout.TELEPORT_PADS:
			if str(other.get("id", "")) == str(pad.get("partner", "")):
				return other
	return {}

static func start(hero: Dictionary) -> bool:
	if not bool(hero.get("alive", true)):
		return false
	if bool(hero.get("teleporting", false)):
		return false
	if float(hero.get("teleport_cd", 0.0)) > 0.0:
		return false
	var pos: Vector2 = hero.get("pos", Vector2.ZERO)
	var pad := pad_at(pos)
	if pad.is_empty():
		return false
	hero["teleporting"] = true
	hero["teleport_timer"] = CHANNEL_TIME
	hero["teleport_total"] = CHANNEL_TIME
	hero["teleport_pad"] = str(pad.get("id", ""))
	hero["teleport_from"] = pos
	return true

static func tick(hero: Dictionary, input: Dictionary, delta: float) -> bool:
	if not bool(hero.get("teleporting", false)):
		return false
	if not bool(hero.get("alive", true)) or _input_breaks_channel(input):
		interrupt(hero)
		return false
	var remaining := float(hero.get("teleport_timer", 0.0)) - delta
	if remaining > 0.0001:
		hero["teleport_timer"] = remaining
		return false
	var partner := partner_of(str(hero.get("teleport_pad", "")))
	if partner.is_empty():
		interrupt(hero)
		return false
	hero["teleporting"] = false
	hero["teleport_timer"] = 0.0
	hero["teleport_total"] = 0.0
	hero["teleport_cd"] = COOLDOWN
	hero["pos"] = partner.pos
	return true

# 返回「这次调用是否真的打断了一段正在进行的引导」，语义与 RecallRules.interrupt 一致：
# 幂等，只有真正中断的那一次返回 true，调用方据此发打断事件。
static func interrupt(hero: Dictionary) -> bool:
	if not bool(hero.get("teleporting", false)):
		return false
	hero["teleporting"] = false
	hero["teleport_timer"] = 0.0
	hero["teleport_total"] = 0.0
	return true

static func _input_breaks_channel(input: Dictionary) -> bool:
	var move: Variant = input.get("move", Vector2.ZERO)
	if move is Vector2 and (move as Vector2).length() > MOVE_EPSILON:
		return true
	return bool(input.get("attack", false)) \
		or bool(input.get("skill_q", false)) \
		or bool(input.get("skill_e", false)) \
		or bool(input.get("recall", false))
