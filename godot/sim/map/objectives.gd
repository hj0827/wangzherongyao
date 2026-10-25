extends RefCounted

# 中立首领：暴君与主宰两分钟首刷、三分钟刷新。
# 击杀方全队获得限时增伤，制造围绕河道与野区入口的争夺点。

const MapLayout = preload("res://sim/map/map_layout.gd")

const FIRST_SPAWN := 120.0
const RESPAWN := 180.0
const BUFF_DURATION := 60.0
const TEAM_DAMAGE_SCALE := 1.12

static var PITS: Array = MapLayout.OBJECTIVE_PITS.duplicate(true)

static func monster_stats(pit: Dictionary) -> Dictionary:
	var pos: Vector2 = pit.get("pos", Vector2.ZERO)
	var is_tyrant := str(pit.get("id", "")) == "tyrant"
	var hp := 6800.0 if is_tyrant else 7600.0
	return {
		"type": "monster",
		"team": "neutral",
		"monster_type": str(pit.get("monster_type", "orc")),
		"name": str(pit.get("name", "首领")),
		"objective": true,
		"objective_id": str(pit.get("id", "")),
		"pos": pos,
		"x": pos.x,
		"y": pos.y,
		"radius": 2.6,
		"hp": hp,
		"max_hp": hp,
		"attack_damage": 120.0,
		"attack_range": 3.4,
		"attack_interval": 1.4,
		"leash_range": 14.0,
		"move_speed": 3.0,
		"respawn_time": RESPAWN,
		"alive": true,
	}

static func ensure_state(state: Dictionary) -> void:
	var objectives: Variant = state.get("objectives", null)
	if not (objectives is Dictionary):
		objectives = {}
		state["objectives"] = objectives
	var data: Dictionary = objectives
	if not (data.get("buffs", null) is Dictionary):
		data["buffs"] = {"blue": 0.0, "red": 0.0}
	else:
		var buffs: Dictionary = data.buffs
		if not buffs.has("blue"):
			buffs["blue"] = 0.0
		if not buffs.has("red"):
			buffs["red"] = 0.0

static func grant_buff(state: Dictionary, team: String) -> bool:
	if team != "blue" and team != "red":
		return false
	ensure_state(state)
	state.objectives.buffs[team] = BUFF_DURATION
	return true

static func damage_scale(state: Dictionary, team: String) -> float:
	var objectives: Variant = state.get("objectives", null)
	if not (objectives is Dictionary):
		return 1.0
	var buffs: Variant = objectives.get("buffs", null)
	if not (buffs is Dictionary):
		return 1.0
	if float(buffs.get(team, 0.0)) > 0.0:
		return TEAM_DAMAGE_SCALE
	return 1.0

static func tick(state: Dictionary, delta: float) -> void:
	var objectives: Variant = state.get("objectives", null)
	if not (objectives is Dictionary):
		return
	var buffs: Variant = objectives.get("buffs", null)
	if not (buffs is Dictionary):
		return
	for team in ["blue", "red"]:
		buffs[team] = maxf(0.0, float(buffs.get(team, 0.0)) - delta)
