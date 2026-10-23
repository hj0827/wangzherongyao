extends RefCounted

# 战争迷雾：视野半径 + 草丛隐藏 + 墙体遮挡。
# 建筑视为永久可见的地标，草里的敌人只有贴脸、刚出手或已被显形时才会暴露。

const MapLayout = preload("res://sim/map/map_layout.gd")
const Collision = preload("res://sim/map/collision.gd")

const HERO_VISION := 14.0
const MINION_VISION := 8.0
const TOWER_VISION := 11.0
const BASE_VISION := 15.0
const BUSH_REVEAL := 3.2

const VISION_TYPES := ["hero", "minion", "tower", "guard", "base"]
const ALWAYS_VISIBLE_TYPES := ["tower", "guard", "base"]

static func radius_of(entity: Dictionary) -> float:
	match str(entity.get("type", "")):
		"hero":
			return HERO_VISION
		"minion":
			return MINION_VISION
		"tower":
			return TOWER_VISION
		"guard":
			return TOWER_VISION
		"base":
			return BASE_VISION
	return 0.0

static func can_see_team(viewer_team: String) -> bool:
	return viewer_team == "blue" or viewer_team == "red"

static func is_visible(target: Dictionary, viewer_team: String, entities: Array, reveals: Array = []) -> bool:
	if not can_see_team(viewer_team):
		return true
	if str(target.get("team", "neutral")) == viewer_team:
		return true
	if ALWAYS_VISIBLE_TYPES.has(str(target.get("type", ""))):
		return true
	var target_pos := _pos(target)
	# 河道之灵提供的「视野区」：在揭示半径内直接可见，不受墙体和草丛影响。
	for reveal in reveals:
		if not (reveal is Dictionary):
			continue
		var center := Vector2(float(reveal.get("x", 0.0)), float(reveal.get("y", 0.0)))
		if target_pos.distance_to(center) <= float(reveal.get("radius", 0.0)):
			return true
	var in_bush := not MapLayout.bush_at(target_pos).is_empty()
	var revealed := float(target.get("revealed_timer", 0.0)) > 0.0
	for viewer in entities:
		if not (viewer is Dictionary):
			continue
		var viewer_data: Dictionary = viewer
		if str(viewer_data.get("team", "")) != viewer_team:
			continue
		if not bool(viewer_data.get("alive", true)):
			continue
		if not VISION_TYPES.has(str(viewer_data.get("type", ""))):
			continue
		var viewer_pos := _pos(viewer_data)
		var distance := viewer_pos.distance_to(target_pos)
		if distance > radius_of(viewer_data):
			continue
		if Collision.segment_blocked(viewer_pos, target_pos):
			continue
		if in_bush and not revealed and distance > BUSH_REVEAL:
			continue
		return true
	return false

# 副本过滤：友军全留、建筑全留，敌方与中立单位只有被看见才进快照。
static func filter_snapshot(snapshot: Dictionary, viewer_team: String) -> Dictionary:
	var filtered: Dictionary = snapshot.duplicate(true)
	var source: Array = snapshot.get("entities", [])
	var reveals: Array = []
	var river: Variant = snapshot.get("river", null)
	if river is Dictionary:
		var reveal_map: Variant = river.get("reveals", null)
		if reveal_map is Dictionary and reveal_map.get(viewer_team, null) is Array:
			reveals = reveal_map.get(viewer_team)
	var kept: Array = []
	for item in source:
		if not (item is Dictionary):
			continue
		var entity: Dictionary = item
		if bool(is_visible(entity, viewer_team, source, reveals)):
			kept.append(entity.duplicate(true))
	filtered["entities"] = kept
	# 河道视野也是队内情报，不能把敌方掌握的眼位透给本视角。
	if river is Dictionary and can_see_team(viewer_team):
		filtered["river"] = {
			"spawn_timer": float(river.get("spawn_timer", 0.0)),
			"reveals": {"blue": [], "red": []},
		}
		filtered.river.reveals[viewer_team] = reveals.duplicate(true)
	return filtered

static func _pos(entity: Dictionary) -> Vector2:
	var stored: Variant = entity.get("pos", null)
	if stored is Vector2:
		return stored
	return Vector2(float(entity.get("x", 0.0)), float(entity.get("y", 0.0)))
