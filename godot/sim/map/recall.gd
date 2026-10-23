extends RefCounted

# 回城：4 秒引导，期间移动、施法、普攻或受击都会打断；完成后回到出生点。

const MapData = preload("res://sim/map_data.gd")

const CHANNEL_TIME := 4.0
const MOVE_EPSILON := 0.05

static func start(hero: Dictionary) -> bool:
	if not bool(hero.get("alive", true)):
		return false
	hero["recalling"] = true
	hero["recall_timer"] = CHANNEL_TIME
	hero["recall_total"] = CHANNEL_TIME
	return true

static func tick(hero: Dictionary, input: Dictionary, delta: float) -> bool:
	if not bool(hero.get("recalling", false)):
		return false
	if not bool(hero.get("alive", true)):
		interrupt(hero)
		return false
	if _input_breaks_channel(input):
		interrupt(hero)
		return false
	var remaining := float(hero.get("recall_timer", 0.0)) - delta
	if remaining > 0.0001:
		hero["recall_timer"] = remaining
		return false
	hero["recall_timer"] = 0.0
	hero["recall_total"] = 0.0
	hero["recalling"] = false
	hero["pos"] = spawn_point(hero)
	return true

static func interrupt(hero: Dictionary) -> void:
	hero["recalling"] = false
	hero["recall_timer"] = 0.0
	hero["recall_total"] = 0.0

static func spawn_point(hero: Dictionary) -> Vector2:
	var stored: Variant = hero.get("spawn_pos", null)
	if stored is Vector2:
		return stored
	return MapData.BLUE_BASE if str(hero.get("team", "blue")) == "blue" else MapData.RED_BASE

static func _input_breaks_channel(input: Dictionary) -> bool:
	var move: Variant = input.get("move", Vector2.ZERO)
	if move is Vector2 and (move as Vector2).length() > MOVE_EPSILON:
		return true
	return bool(input.get("attack", false)) \
		or bool(input.get("skill_q", false)) \
		or bool(input.get("skill_e", false))
