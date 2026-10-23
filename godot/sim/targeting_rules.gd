extends RefCounted

# 纯逻辑目标仲裁：sim 直接调用，UI 侧的 TargetingSystem 只是转发同一份规则，
# 避免「界面按补刀键、模拟仍按最近目标」的双实现漂移。

const MAX_LOCK_DISTANCE := 14.0

static func is_lock_valid(hero: Dictionary, locked_id: int, entities: Array) -> bool:
	if locked_id <= 0:
		return false
	var hero_pos: Vector2 = hero.get("pos", Vector2.ZERO)
	for e in entities:
		if int(e.get("id", -1)) == locked_id:
			if not bool(e.get("alive", false)):
				return false
			var pos: Vector2 = e.get("pos", Vector2.ZERO)
			if hero_pos.distance_to(pos) > MAX_LOCK_DISTANCE:
				return false
			return true
	return false

static func resolve_attack_target(
	hero: Dictionary,
	entities: Array,
	attack_mode: String,
	locked_target_id: int,
	drag_direction: Vector2
) -> Dictionary:
	var hero_pos: Vector2 = hero.get("pos", Vector2.ZERO)
	var hero_team: String = str(hero.get("team", ""))
	var max_range: float = float(hero.get("attack_range", 6.5)) + 1.5

	if locked_target_id > 0 and is_lock_valid(hero, locked_target_id, entities):
		for e in entities:
			if int(e.get("id", -1)) == locked_target_id:
				return e

	if drag_direction.length() > 0.3:
		var dir := drag_direction.normalized()
		var best_wheel: Dictionary = {}
		var max_dot := -2.0
		for e in entities:
			if not bool(e.get("alive", false)):
				continue
			if str(e.get("team", "")) == hero_team:
				continue
			var pos: Vector2 = e.get("pos", Vector2.ZERO)
			var to_e := pos - hero_pos
			if to_e.length() > max_range:
				continue
			var dot := dir.dot(to_e.normalized())
			if dot > max_dot:
				max_dot = dot
				best_wheel = e
		# 只有明显朝该方向的拖拽才覆盖普通索敌；鼠标停在远处空地时
		# 方向向量依然存在，若无角度下限会把背后目标也选中。
		if not best_wheel.is_empty() and max_dot >= 0.3:
			return best_wheel

	var candidates: Array = []
	for e in entities:
		if not bool(e.get("alive", false)):
			continue
		if str(e.get("team", "")) == hero_team:
			continue
		var pos: Vector2 = e.get("pos", Vector2.ZERO)
		var dist := hero_pos.distance_to(pos)
		if dist <= max_range:
			candidates.append({"entity": e, "dist": dist})

	if candidates.is_empty():
		return {}

	match attack_mode:
		"minion":
			var best_minion: Dictionary = {}
			var min_dist := INF
			for c in candidates:
				var t: String = str(c.entity.get("type", ""))
				if t == "minion" or t == "monster":
					if float(c.dist) < min_dist:
						min_dist = float(c.dist)
						best_minion = c.entity
			return best_minion

		"tower":
			var best_tower: Dictionary = {}
			var min_tower_dist := INF
			for c in candidates:
				var t: String = str(c.entity.get("type", ""))
				if t == "tower" or t == "base":
					if float(c.dist) < min_tower_dist:
						min_tower_dist = float(c.dist)
						best_tower = c.entity
			return best_tower

		_:
			var best_hero: Dictionary = {}
			var min_hero_dist := INF
			var best_other: Dictionary = {}
			var min_other_dist := INF
			for c in candidates:
				var t: String = str(c.entity.get("type", ""))
				if t == "hero":
					if float(c.dist) < min_hero_dist:
						min_hero_dist = float(c.dist)
						best_hero = c.entity
				elif t == "minion" or t == "monster":
					if float(c.dist) < min_other_dist:
						min_other_dist = float(c.dist)
						best_other = c.entity
				elif best_other.is_empty():
					best_other = c.entity
			if not best_hero.is_empty():
				return best_hero
			return best_other
