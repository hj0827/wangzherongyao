extends RefCounted

# 河道之灵：30 秒首刷、90 秒重生。击杀后击杀方获得 60 秒河道视野，
# 把「谁在河道蹲人」变成一条可被争夺的信息资源，而不是纯野怪经济。

const MapLayout = preload("res://sim/map/map_layout.gd")

const FIRST_SPAWN := 30.0
const RESPAWN_TIME := 90.0
const REVEAL_RADIUS := 16.0
const REVEAL_DURATION := 60.0
const SPIRIT_XP := 70.0

static var SPIRITS: Array = MapLayout.RIVER_SPIRITS.duplicate(true)

static func initial_state() -> Dictionary:
	return {
		"spawn_timer": FIRST_SPAWN,
		"spawned": false,
		"reveals": {"blue": [], "red": []},
	}

static func ensure_state(state: Dictionary) -> void:
	var river: Variant = state.get("river", null)
	if not (river is Dictionary):
		river = initial_state()
		state["river"] = river
	var data: Dictionary = river
	if not (data.get("reveals", null) is Dictionary):
		data["reveals"] = {"blue": [], "red": []}
	else:
		var reveals: Dictionary = data.reveals
		for team in ["blue", "red"]:
			if not (reveals.get(team, null) is Array):
				reveals[team] = []

static func spirit_stats(spot: Dictionary) -> Dictionary:
	var pos: Vector2 = spot.get("pos", Vector2.ZERO)
	return {
		"type": "monster",
		"team": "neutral",
		"monster_type": "spirit",
		"name": str(spot.get("name", "河道之灵")),
		"camp_id": str(spot.get("id", "")),
		"river_spirit": true,
		"pos": pos,
		"x": pos.x,
		"y": pos.y,
		"radius": 1.2,
		"hp": 900.0,
		"max_hp": 900.0,
		"attack_damage": 70.0,
		"attack_range": 2.2,
		"attack_interval": 1.3,
		"aggro_range": 6.0,
		"leash_range": 12.0,
		"move_speed": 3.6,
		"respawn_time": RESPAWN_TIME,
		"alive": true,
	}

# 返回本 tick 需要刷新的河道之灵锚点；视野计时在这里统一递减。
static func tick(state: Dictionary, delta: float) -> Array:
	ensure_state(state)
	var river: Dictionary = state.river
	var reveals: Dictionary = river.reveals
	for team in ["blue", "red"]:
		var kept: Array = []
		for reveal in reveals.get(team, []):
			if not (reveal is Dictionary):
				continue
			var timer := float(reveal.get("timer", 0.0)) - delta
			if timer <= 0.0:
				continue
			var next: Dictionary = reveal.duplicate()
			next["timer"] = timer
			kept.append(next)
		reveals[team] = kept
	if bool(river.get("spawned", false)):
		return []
	river.spawn_timer = maxf(0.0, float(river.get("spawn_timer", 0.0)) - delta)
	if float(river.spawn_timer) > 0.0:
		return []
	river.spawned = true
	return SPIRITS.duplicate(true)

static func grant_reveal(state: Dictionary, team: String, center: Vector2) -> Dictionary:
	if team != "blue" and team != "red":
		return {}
	ensure_state(state)
	var reveal := {
		"x": float(center.x),
		"y": float(center.y),
		"radius": REVEAL_RADIUS,
		"timer": REVEAL_DURATION,
	}
	state.river.reveals[team].append(reveal)
	return reveal

static func reveals_for(state: Dictionary, team: String) -> Array:
	ensure_state(state)
	return state.river.reveals.get(team, [])
