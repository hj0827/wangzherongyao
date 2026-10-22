extends RefCounted

const MapData = preload("res://sim/map_data.gd")
const HeroDefs = preload("res://sim/hero_defs.gd")

const TICK_RATE := 30.0
const HERO_RESPAWN_BASE := 6.0
const WAVE_INTERVAL := 18.0
const FIRST_WAVE_DELAY := 1.0
const MINIONS_PER_LANE := 3
const MINION_AGGRO_RANGE := 5.5
const STRUCTURE_RANGE := 8.0
const BASE_RANGE := 9.0
const MAX_LEVEL := 15

# 野外脱战回血（每秒 % 最大生命）与基础回蓝
const FIELD_HP_REGEN := 0.025
const FIELD_MP_REGEN := 6.0
# 泉水恢复速率（每秒 % 最大生命 / 法力）。约 5 秒回满，
# 比野外脱战回血快 7 倍，且不需要等 8 秒脱战计时。
const FOUNTAIN_HP_RATE := 0.18
const FOUNTAIN_MP_RATE := 0.15

const SPAWN_OFFSETS := [0.0, -22.0, 22.0, -44.0, 44.0]

var config: Dictionary
var mode: String
var state: Dictionary
var ended := false
var inputs: Dictionary = {}

func _init(match_config: Dictionary) -> void:
	config = match_config.duplicate(true)
	mode = str(config.get("mode", "duel"))
	if mode != "team":
		mode = "duel"
	state = {
		"time": 0.0,
		"bounds": MapData.BOUNDS,
		"winner": "",
		"mode": mode,
		"entities": [],
		"events": [],
		"next_id": 1,
		"wave": 0,
		"wave_timer": FIRST_WAVE_DELAY,
		"scores": {
			"blue": {"kills": 0, "towers": 0},
			"red": {"kills": 0, "towers": 0},
		},
		"bot_ai": bool(config.get("bot_ai", false)),
	}
	_setup_teams()
	_setup_structures()
	_update_wave(FIRST_WAVE_DELAY)

func _next_id() -> int:
	var id: int = int(state.next_id)
	state.next_id = id + 1
	return id

func _emit(event_type: String, data: Dictionary = {}) -> void:
	var event := {"type": event_type}
	for key in data:
		event[key] = data[key]
	state.events.append(event)

func _setup_teams() -> void:
	var humans: Array = config.get("humans", [])
	var bot_fill: bool = bool(config.get("bot_fill", false))
	var per_team := 1 if mode == "duel" else 5
	var slots := {"blue": 0, "red": 0}
	var human_counts := {"blue": 0, "red": 0}
	var bot_counter := 0

	for entry in humans:
		if not (entry is Dictionary):
			continue
		var data: Dictionary = entry
		var team: String = str(data.get("team", "blue"))
		if team != "red":
			team = "blue"
		if slots[team] >= per_team:
			continue
		var owner_id: String = str(data.get("id", "p%d" % (human_counts["blue"] + human_counts["red"] + 1)))
		var hero_type: String = str(data.get("hero_type", "blade"))
		if not HeroDefs.is_valid(hero_type):
			hero_type = "blade"
		var display_name: String = str(data.get("name", owner_id))
		_spawn_hero(owner_id, display_name, team, "human", hero_type, slots[team])
		slots[team] += 1
		human_counts[team] += 1

	if bot_fill:
		for team in ["blue", "red"]:
			while slots[team] < per_team:
				var pool: Array = HeroDefs.BOT_TYPES
				var hero_type: String = str(pool[slots[team] % pool.size()])
				var owner_id := "bot_%d" % (bot_counter + 1)
				var display_name := "AI·" + str(HeroDefs.get_hero(hero_type).name)
				_spawn_hero(owner_id, display_name, team, "bot", hero_type, slots[team])
				bot_counter += 1
				slots[team] += 1

func _spawn_point(team: String, slot: int) -> Vector2:
	var base := MapData.BLUE_BASE if team == "blue" else MapData.RED_BASE
	var base_angle := 45.0 if team == "blue" else 225.0
	var offset: float = SPAWN_OFFSETS[slot % SPAWN_OFFSETS.size()]
	var angle := deg_to_rad(base_angle + offset)
	var point := base + Vector2(cos(angle), sin(angle)) * 8.2
	var limit := MapData.BOUNDS - 1.0
	return Vector2(clampf(point.x, -limit, limit), clampf(point.y, -limit, limit))

func _spawn_hero(owner_id: String, display_name: String, team: String, controller: String, hero_type: String, slot: int) -> void:
	var hero_def: Dictionary = HeroDefs.get_hero(hero_type)
	var lane := "mid"
	if mode == "team":
		lane = str(MapData.LANE_ORDER[slot % MapData.LANE_ORDER.size()])
	var path: Array = MapData.lane_path(lane)
	var spawn := _spawn_point(team, slot)
	var path_index := 1 if team == "blue" else path.size() - 2
	var hero := {
		"id": _next_id(),
		"type": "hero",
		"owner_id": owner_id,
		"name": display_name,
		"team": team,
		"controller": controller,
		"hero_type": hero_type,
		"lane": lane,
		"pos": spawn,
		"spawn_pos": spawn,
		"radius": float(hero_def.radius),
		"level": 1,
		"xp": 0.0,
		"hp": float(hero_def.max_hp),
		"max_hp": float(hero_def.max_hp),
		"mp": float(hero_def.max_mp),
		"max_mp": float(hero_def.max_mp),
		"speed": float(hero_def.speed),
		"attack_damage": float(hero_def.attack_damage),
		"attack_range": float(hero_def.attack_range),
		"attack_interval": float(hero_def.attack_interval),
		"attack_cd": 0.0,
		"kills": 0,
		"deaths": 0,
		"alive": true,
		"respawn_timer": 0.0,
		"skill_q_cd": 0.0,
		"skill_e_cd": 0.0,
		"facing": Vector2(0.0, -1.0) if team == "blue" else Vector2(0.0, 1.0),
		"shield": 0.0,
		"shield_timer": 0.0,
		"haste_timer": 0.0,
		"slow_timer": 0.0,
		"last_damage_time": -999.0,
		"path": path,
		"path_index": path_index,
		"path_dir": 1 if team == "blue" else -1,
	}
	state.entities.append(hero)

func _setup_structures() -> void:
	var lanes: Array = ["mid"] if mode == "duel" else MapData.LANE_ORDER
	for lane in lanes:
		var lpath: Array = MapData.lane_path(str(lane))
		_add_tower("blue", lpath[MapData.TOWER_INNER_INDEX], str(lane))
		_add_tower("blue", lpath[MapData.TOWER_OUTER_INDEX], str(lane))
		_add_tower("red", lpath[MapData.TOWER_RED_OUTER_INDEX], str(lane))
		_add_tower("red", lpath[MapData.TOWER_RED_INNER_INDEX], str(lane))
	_add_base("blue", MapData.BLUE_BASE)
	_add_base("red", MapData.RED_BASE)

func _add_tower(team: String, pos: Vector2, lane: String) -> void:
	state.entities.append({
		"id": _next_id(),
		"type": "tower",
		"team": team,
		"lane": lane,
		"pos": pos,
		"radius": MapData.TOWER_RADIUS,
		"hp": 3200.0,
		"max_hp": 3200.0,
		"alive": true,
		"range": STRUCTURE_RANGE,
		"attack_damage": 150.0,
		"attack_interval": 1.1,
		"attack_cd": 0.0,
	})

func _add_base(team: String, pos: Vector2) -> void:
	state.entities.append({
		"id": _next_id(),
		"type": "base",
		"team": team,
		"lane": "",
		"pos": pos,
		"radius": MapData.BASE_RADIUS,
		"hp": 6000.0,
		"max_hp": 6000.0,
		"alive": true,
		"range": BASE_RANGE,
		"attack_damage": 180.0,
		"attack_interval": 1.2,
		"attack_cd": 0.0,
	})

func _update_wave(dt: float) -> void:
	state.wave_timer = float(state.wave_timer) - dt
	if float(state.wave_timer) > 0.0:
		return
	state.wave_timer = WAVE_INTERVAL
	state.wave = int(state.wave) + 1
	var lanes: Array = ["mid"] if mode == "duel" else MapData.LANE_ORDER
	for lane in lanes:
		var path: Array = MapData.lane_path(str(lane))
		for team in ["blue", "red"]:
			for i in MINIONS_PER_LANE:
				_spawn_minion(str(team), str(lane), path, i)
	_emit("wave", {"wave": state.wave})

func _spawn_minion(team: String, lane: String, path: Array, index: int) -> void:
	var blue := team == "blue"
	var base: Vector2 = path[0] if blue else path[path.size() - 1]
	var path_index := 1 if blue else path.size() - 2
	var waypoint: Vector2 = path[path_index]
	var toward := (waypoint - base).normalized()
	var side := Vector2(-toward.y, toward.x)
	var pos := base + toward * 2.6 + side * (float(index) - 1.0) * 0.95
	var minion := {
		"id": _next_id(),
		"type": "minion",
		"team": team,
		"lane": lane,
		"pos": pos,
		"radius": 0.36,
		"hp": 260.0,
		"max_hp": 260.0,
		"alive": true,
		"speed": 3.3,
		"attack_damage": 16.0 + float(state.wave - 1) * 2.0,
		"attack_range": 2.2,
		"attack_interval": 1.0,
		"attack_cd": 0.0,
		"path": path,
		"path_index": path_index,
		"path_dir": 1 if blue else -1,
	}
	state.entities.append(minion)

func get_hero_by_player(owner_id: String) -> Variant:
	for entity in state.entities:
		if entity.type == "hero" and entity.owner_id == owner_id:
			return entity
	return null

func set_input(player_id: String, input: Dictionary) -> void:
	inputs[player_id] = input.duplicate()

func set_player_controller(owner_id: String, controller: String) -> void:
	var hero: Variant = get_hero_by_player(owner_id)
	if hero == null:
		return
	hero.controller = controller
	if controller == "bot":
		state.bot_ai = true

func tick(dt: float) -> void:
	if ended:
		return
	state.time = float(state.time) + dt
	state.events = []
	for entity in state.entities:
		entity.moving = false
	_update_wave(dt)
	_update_hero_timers(dt)
	_apply_human_inputs(dt)
	_update_bots(dt)
	_update_minions(dt)
	_update_structures(dt)
	_update_respawns(dt)

# 是否站在己方泉水范围内（基地中心 MapData.FOUNTAIN_RADIUS 以内）。
func _in_fountain(entity: Dictionary) -> bool:
	var base := MapData.BLUE_BASE if str(entity.team) == "blue" else MapData.RED_BASE
	return (entity.pos as Vector2).distance_to(base) <= MapData.FOUNTAIN_RADIUS

func _update_hero_timers(dt: float) -> void:	for entity in state.entities:
		if entity.type != "hero" or not entity.alive:
			continue
		entity.skill_q_cd = maxf(0.0, float(entity.skill_q_cd) - dt)
		entity.skill_e_cd = maxf(0.0, float(entity.skill_e_cd) - dt)
		entity.attack_cd = maxf(0.0, float(entity.attack_cd) - dt)
		entity.shield_timer = maxf(0.0, float(entity.shield_timer) - dt)
		if float(entity.shield_timer) <= 0.0:
			entity.shield = 0.0
		entity.haste_timer = maxf(0.0, float(entity.haste_timer) - dt)
		entity.slow_timer = maxf(0.0, float(entity.slow_timer) - dt)
		entity.mp = minf(float(entity.max_mp), float(entity.mp) + FIELD_MP_REGEN * dt)
		if float(entity.hp) < float(entity.max_hp) and float(state.time) - float(entity.last_damage_time) > 8.0:
			entity.hp = minf(float(entity.max_hp), float(entity.hp) + float(entity.max_hp) * FIELD_HP_REGEN * dt)
		# 泉水：站在己方基地范围内快速回满，不必等脱战计时。
		if _in_fountain(entity):
			entity.hp = minf(float(entity.max_hp), float(entity.hp) + float(entity.max_hp) * FOUNTAIN_HP_RATE * dt)
			entity.mp = minf(float(entity.max_mp), float(entity.mp) + float(entity.max_mp) * FOUNTAIN_MP_RATE * dt)

func _apply_human_inputs(dt: float) -> void:
	for entity in state.entities:
		if entity.type != "hero" or not entity.alive or entity.controller != "human":
			continue
		var input: Dictionary = inputs.get(entity.owner_id, {})
		if input.is_empty():
			continue
		var aim: Vector2 = input.get("aim", Vector2.ZERO)
		var aim_vector: Vector2 = aim - entity.pos
		var move: Vector2 = input.get("move", Vector2.ZERO)
		if move.length() > 1.0:
			move = move.normalized()
		if move.length() > 0.01:
			# 移动时朝向移动方向：点击移动经常是「往身后走」，若还朝着准星就成了倒着走。
			# 站住时才看向准星；技能与普攻随后各自把 facing 改回目标方向，瞄准手感不变。
			entity.facing = move.normalized()
			_move_hero(entity, move, dt)
		elif aim_vector.length() > 0.6:
			entity.facing = aim_vector.normalized()
		if bool(input.get("skill_q", false)):
			_cast_q(entity, aim)
		if bool(input.get("skill_e", false)):
			_cast_e(entity, aim)
		if bool(input.get("attack", false)):
			_try_attack(entity)

func _update_bots(dt: float) -> void:
	if not bool(state.bot_ai):
		return
	for entity in state.entities:
		if entity.type != "hero" or not entity.alive or entity.controller != "bot":
			continue
		var target: Dictionary = _nearest_enemy(entity, 9.0)
		if target.is_empty():
			_advance_along_path(entity, dt)
			continue
		var to_target: Vector2 = target.pos - entity.pos
		if to_target.length() > 0.1:
			entity.facing = to_target.normalized()
		if float(entity.skill_q_cd) <= 0.0 and to_target.length() <= 9.0:
			_cast_q(entity, target.pos)
		if float(entity.skill_e_cd) <= 0.0:
			var e_def: Dictionary = HeroDefs.get_hero(str(entity.hero_type)).e
			var kind := str(e_def.kind)
			if kind == "shield" and float(entity.hp) < float(entity.max_hp) * 0.55:
				_cast_e(entity, entity.pos + to_target)
			elif kind == "haste" and to_target.length() > 3.5:
				_cast_e(entity, target.pos)
			elif kind == "dash" and to_target.length() > 2.5 and to_target.length() < 5.0:
				_cast_e(entity, target.pos)
		var reach: float = float(entity.attack_range) + float(target.get("radius", 0.0))
		if to_target.length() > reach:
			_move_hero(entity, to_target.normalized(), dt)
		else:
			_try_attack(entity)

func _move_hero(hero: Dictionary, direction: Vector2, dt: float) -> void:
	var speed: float = float(hero.speed)
	if float(hero.haste_timer) > 0.0:
		speed *= 1.4
	if float(hero.slow_timer) > 0.0:
		speed *= 0.65
	hero.pos += direction * speed * dt
	hero.moving = true
	_clamp_position(hero)

func _advance_along_path(entity: Dictionary, dt: float) -> void:
	var path: Array = entity.path
	var index: int = int(entity.path_index)
	if index < 0 or index >= path.size():
		return
	var waypoint: Vector2 = path[index]
	var to_point: Vector2 = waypoint - entity.pos
	var speed := float(entity.get("speed", 3.3))
	if float(entity.get("slow_timer", 0.0)) > 0.0:
		speed *= 0.65
	if to_point.length() < 0.9:
		index += int(entity.path_dir)
		entity.path_index = index
		if index < 0 or index >= path.size():
			return
		waypoint = path[index]
		to_point = waypoint - entity.pos
	if to_point.length() > 0.01:
		entity.pos += to_point.normalized() * speed * dt
		entity.moving = true
		_clamp_position(entity)

func _update_minions(dt: float) -> void:
	for entity in state.entities:
		if entity.type != "minion" or not entity.alive:
			continue
		entity.attack_cd = maxf(0.0, float(entity.attack_cd) - dt)
		var target: Dictionary = _nearest_enemy(entity, MINION_AGGRO_RANGE)
		if target.is_empty():
			_advance_along_path(entity, dt)
			continue
		var reach: float = float(entity.attack_range)
		if target.type == "tower" or target.type == "base":
			reach += float(target.radius)
		if entity.pos.distance_to(target.pos) <= reach:
			if float(entity.attack_cd) <= 0.0:
				entity.attack_cd = float(entity.attack_interval)
				entity.facing = (target.pos - entity.pos).normalized()
				_damage(target, float(entity.attack_damage), entity)
		else:
			var step: Vector2 = (target.pos - entity.pos).normalized()
			entity.pos += step * float(entity.speed) * dt
			entity.moving = true
			_clamp_position(entity)

func _update_structures(dt: float) -> void:
	for entity in state.entities:
		if (entity.type != "tower" and entity.type != "base") or not entity.alive:
			continue
		entity.attack_cd = maxf(0.0, float(entity.attack_cd) - dt)
		var target: Dictionary = _structure_target(entity)
		if target.is_empty():
			continue
		if float(entity.attack_cd) <= 0.0:
			entity.attack_cd = float(entity.attack_interval)
			_emit("structure_attack", {
				"source": entity.id,
				"team": entity.team,
				"x": float(entity.pos.x),
				"y": float(entity.pos.y),
				"target_x": float(target.pos.x),
				"target_y": float(target.pos.y),
			})
			_damage(target, float(entity.attack_damage), entity)

func _structure_target(structure: Dictionary) -> Dictionary:
	var minion_target: Dictionary = {}
	var minion_dist := INF
	var hero_target: Dictionary = {}
	var hero_dist := INF
	var attack_range: float = float(structure.range)
	for entity in state.entities:
		if not entity.alive or entity.team == structure.team:
			continue
		if entity.type != "minion" and entity.type != "hero":
			continue
		var dist: float = structure.pos.distance_to(entity.pos)
		if dist > attack_range:
			continue
		if entity.type == "minion" and dist < minion_dist:
			minion_dist = dist
			minion_target = entity
		elif entity.type == "hero" and dist < hero_dist:
			hero_dist = dist
			hero_target = entity
	if not minion_target.is_empty():
		return minion_target
	return hero_target

func _nearest_enemy(seeker: Dictionary, max_range: float) -> Dictionary:
	var best: Dictionary = {}
	var best_dist := max_range
	for entity in state.entities:
		if not entity.alive or entity.team == seeker.team or entity.id == seeker.id:
			continue
		if entity.type == "hero":
			var hero_dist: float = seeker.pos.distance_to(entity.pos) - 0.65
			if hero_dist < best_dist:
				best_dist = hero_dist
				best = entity
			continue
		var dist: float = seeker.pos.distance_to(entity.pos)
		if entity.type == "tower" or entity.type == "base":
			dist -= float(entity.radius) * 0.7
		if dist < best_dist:
			best_dist = dist
			best = entity
	return best

func _cast_q(hero: Dictionary, aim: Vector2) -> bool:
	var hero_def: Dictionary = HeroDefs.get_hero(str(hero.hero_type))
	var skill: Dictionary = hero_def.q
	if float(hero.skill_q_cd) > 0.0 or float(hero.mp) < float(skill.cost):
		return false
	var target: Dictionary = _pick_skill_target(hero, aim, float(skill.range))
	if target.is_empty():
		return false
	hero.mp = float(hero.mp) - float(skill.cost)
	hero.skill_q_cd = float(skill.cooldown)
	var kind := str(skill.kind)
	var damage: float = float(skill.damage) + float(hero.attack_damage) * 0.5 + float(hero.level - 1) * 8.0
	hero.facing = (target.pos - hero.pos).normalized()
	_emit("skill", {
		"slot": "q",
		"hero": hero.id,
		"hero_type": hero.hero_type,
		"name": skill.name,
		"x": float(hero.pos.x),
		"y": float(hero.pos.y),
		"aim_x": float(target.pos.x),
		"aim_y": float(target.pos.y),
	})
	if kind == "quake" or kind == "slow":
		var radius := 3.2
		for entity in state.entities:
			if not entity.alive or entity.team == hero.team:
				continue
			if entity.type != "hero" and entity.type != "minion":
				continue
			if entity.pos.distance_to(target.pos) <= radius:
				_damage(entity, damage, hero)
				if kind == "slow":
					entity.slow_timer = maxf(float(entity.get("slow_timer", 0.0)), 2.5)
	else:
		_damage(target, damage, hero)
	return true

func _cast_e(hero: Dictionary, aim: Vector2) -> bool:
	var hero_def: Dictionary = HeroDefs.get_hero(str(hero.hero_type))
	var skill: Dictionary = hero_def.e
	if float(hero.skill_e_cd) > 0.0 or float(hero.mp) < float(skill.cost):
		return false
	var kind := str(skill.kind)
	if kind == "dash":
		var direction: Vector2 = aim - hero.pos
		if direction.length() < 0.2:
			direction = hero.facing
		hero.pos += direction.normalized() * float(skill.range)
		_clamp_position(hero)
	elif kind == "shield":
		hero.shield = 350.0 + float(hero.level - 1) * 25.0
		hero.shield_timer = 4.0
	elif kind == "haste":
		hero.haste_timer = 4.0
	elif kind == "slow":
		var target: Dictionary = _pick_skill_target(hero, aim, float(skill.range))
		if target.is_empty():
			return false
		for entity in state.entities:
			if not entity.alive or entity.team == hero.team:
				continue
			if entity.type != "hero" and entity.type != "minion":
				continue
			if entity.pos.distance_to(target.pos) <= 3.0:
				entity.slow_timer = maxf(float(entity.get("slow_timer", 0.0)), 2.5)
				_damage(entity, float(skill.damage), hero)
	hero.mp = float(hero.mp) - float(skill.cost)
	hero.skill_e_cd = float(skill.cooldown)
	_emit("skill", {
		"slot": "e",
		"hero": hero.id,
		"hero_type": hero.hero_type,
		"name": skill.name,
		"x": float(hero.pos.x),
		"y": float(hero.pos.y),
		"aim_x": float(aim.x),
		"aim_y": float(aim.y),
	})
	return true

func _pick_skill_target(hero: Dictionary, aim: Vector2, max_range: float) -> Dictionary:
	var best: Dictionary = {}
	var best_score := INF
	var aim_dir: Vector2 = aim - hero.pos
	var has_aim := aim_dir.length() > 0.4
	if has_aim:
		aim_dir = aim_dir.normalized()
	for entity in state.entities:
		if not entity.alive or entity.team == hero.team:
			continue
		if entity.type != "hero" and entity.type != "minion" and entity.type != "tower":
			continue
		var dist: float = hero.pos.distance_to(entity.pos)
		if dist > max_range:
			continue
		var direction: Vector2 = (entity.pos - hero.pos).normalized()
		if has_aim and direction.dot(aim_dir) < -0.15:
			continue
		var score := dist
		if entity.type == "hero":
			score -= 1.2
		if score < best_score:
			best_score = score
			best = entity
	return best

func _try_attack(hero: Dictionary) -> void:
	if float(hero.attack_cd) > 0.0:
		return
	var target: Dictionary = _nearest_enemy(hero, float(hero.attack_range) + 0.8)
	if target.is_empty():
		return
	var reach: float = float(hero.attack_range) + float(target.get("radius", 0.0))
	if hero.pos.distance_to(target.pos) > reach:
		return
	hero.attack_cd = float(hero.attack_interval)
	hero.facing = (target.pos - hero.pos).normalized()
	var damage: float = float(hero.attack_damage) + float(hero.level - 1) * float(HeroDefs.get_hero(str(hero.hero_type)).damage_growth)
	_emit("attack", {
		"hero": hero.id,
		"x": float(hero.pos.x),
		"y": float(hero.pos.y),
		"aim_x": float(target.pos.x),
		"aim_y": float(target.pos.y),
	})
	_damage(target, damage, hero)

func _update_respawns(dt: float) -> void:
	for entity in state.entities:
		if entity.type != "hero" or entity.alive:
			continue
		entity.respawn_timer = maxf(0.0, float(entity.respawn_timer) - dt)
		if float(entity.respawn_timer) <= 0.0:
			entity.alive = true
			entity.hp = float(entity.max_hp)
			entity.mp = float(entity.max_mp)
			entity.pos = entity.spawn_pos
			entity.shield = 0.0
			entity.shield_timer = 0.0
			entity.haste_timer = 0.0
			entity.slow_timer = 0.0
			entity.last_damage_time = -999.0
			_emit("respawn", {"hero": entity.id, "x": float(entity.pos.x), "y": float(entity.pos.y)})

func apply_damage(entity_id: int, amount: float, source_id: int = -1) -> void:
	var target: Dictionary = _entity_by_id(entity_id)
	if target.is_empty() or not target.alive:
		return
	var source: Dictionary = {}
	if source_id >= 0:
		source = _entity_by_id(source_id)
	_damage(target, amount, source)

func _damage(target: Dictionary, amount: float, source: Dictionary) -> void:
	if target.is_empty() or not target.alive or amount <= 0.0:
		return
	var remaining := amount
	if float(target.get("shield", 0.0)) > 0.0:
		var absorbed: float = minf(float(target.shield), remaining)
		target.shield = float(target.shield) - absorbed
		remaining -= absorbed
	if remaining <= 0.0:
		return
	target.hp = float(target.hp) - remaining
	if target.type == "hero":
		target.last_damage_time = float(state.time)
	_emit("hit", {
		"target": target.id,
		"target_type": target.type,
		"x": float(target.pos.x),
		"y": float(target.pos.y),
		"amount": remaining,
		"team": target.team,
	})
	if float(target.hp) <= 0.0:
		_kill_entity(target, source)

func _kill_entity(target: Dictionary, source: Dictionary) -> void:
	if not target.alive:
		return
	target.hp = 0.0
	target.alive = false
	if target.type == "hero":
		target.deaths = int(target.deaths) + 1
		target.respawn_timer = HERO_RESPAWN_BASE + float(target.level) * 0.4
		target.shield = 0.0
		target.shield_timer = 0.0
		if not source.is_empty() and source.type == "hero" and source.team != target.team:
			source.kills = int(source.kills) + 1
			state.scores[source.team].kills = int(state.scores[source.team].kills) + 1
			_add_xp(source, 130.0)
		_emit("death", {
			"entity_type": "hero",
			"hero": target.id,
			"team": target.team,
			"x": float(target.pos.x),
			"y": float(target.pos.y),
		})
	elif target.type == "minion":
		if not source.is_empty() and source.type == "hero":
			_add_xp(source, 32.0)
		_emit("death", {
			"entity_type": "minion",
			"team": target.team,
			"x": float(target.pos.x),
			"y": float(target.pos.y),
		})
	elif target.type == "tower":
		var winner_team := "blue" if target.team == "red" else "red"
		state.scores[winner_team].towers = int(state.scores[winner_team].towers) + 1
		if not source.is_empty() and source.type == "hero":
			_add_xp(source, 80.0)
		_emit("tower_destroyed", {
			"team": target.team,
			"lane": target.lane,
			"x": float(target.pos.x),
			"y": float(target.pos.y),
		})
	elif target.type == "base":
		state.winner = "blue" if target.team == "red" else "red"
		ended = true
		_emit("match_end", {"winner": state.winner})

func _add_xp(hero: Dictionary, amount: float) -> void:
	if hero.type != "hero" or not hero.alive:
		return
	hero.xp = float(hero.xp) + amount
	while int(hero.level) < MAX_LEVEL and float(hero.xp) >= _xp_needed(int(hero.level)):
		hero.xp = float(hero.xp) - _xp_needed(int(hero.level))
		hero.level = int(hero.level) + 1
		var hero_def: Dictionary = HeroDefs.get_hero(str(hero.hero_type))
		hero.max_hp = float(hero.max_hp) + float(hero_def.hp_growth)
		hero.max_mp = float(hero.max_mp) + float(hero_def.mp_growth)
		hero.attack_damage = float(hero.attack_damage) + float(hero_def.damage_growth)
		hero.hp = minf(float(hero.max_hp), float(hero.hp) + float(hero_def.hp_growth))
		hero.mp = minf(float(hero.max_mp), float(hero.mp) + float(hero_def.mp_growth))
		_emit("level_up", {"hero": hero.id, "level": hero.level})

func _xp_needed(level: int) -> float:
	return 120.0 + float(level - 1) * 90.0

func _entity_by_id(entity_id: int) -> Dictionary:
	for entity in state.entities:
		if entity.id == entity_id:
			return entity
	return {}

func _clamp_position(entity: Dictionary) -> void:
	var limit: float = MapData.BOUNDS - float(entity.get("radius", 0.0))
	entity.pos = Vector2(
		clampf(float(entity.pos.x), -limit, limit),
		clampf(float(entity.pos.y), -limit, limit)
	)

func snapshot() -> Dictionary:
	var entities: Array = []
	for entity in state.entities:
		entities.append(_snapshot_entity(entity))
	var events: Array = []
	for event in state.events:
		events.append(event.duplicate())
	return {
		"time": float(state.time),
		"winner": state.winner,
		"mode": mode,
		"bounds": float(state.bounds),
		"ended": ended,
		"entities": entities,
		"scores": state.scores.duplicate(true),
		"events": events,
		"wave": state.wave,
	}

func _snapshot_entity(entity: Dictionary) -> Dictionary:
	var pos: Vector2 = entity.pos
	var data := {
		"id": int(entity.id),
		"type": str(entity.type),
		"team": str(entity.team),
		"x": float(pos.x),
		"y": float(pos.y),
		"radius": float(entity.get("radius", 0.0)),
		"hp": float(entity.get("hp", 0.0)),
		"max_hp": float(entity.get("max_hp", 0.0)),
		"alive": bool(entity.get("alive", false)),
	}
	if entity.type == "hero":
		var facing: Vector2 = entity.facing
		data["owner_id"] = str(entity.owner_id)
		data["name"] = str(entity.name)
		data["hero_type"] = str(entity.hero_type)
		data["controller"] = str(entity.controller)
		data["lane"] = str(entity.lane)
		data["level"] = int(entity.level)
		data["xp"] = float(entity.xp)
		data["mp"] = float(entity.mp)
		data["max_mp"] = float(entity.max_mp)
		data["kills"] = int(entity.kills)
		data["deaths"] = int(entity.deaths)
		data["respawn_timer"] = 0.0 if entity.alive else float(entity.respawn_timer)
		data["skill_q_cd"] = float(entity.skill_q_cd)
		data["skill_e_cd"] = float(entity.skill_e_cd)
		data["speed"] = float(entity.speed)
		data["shield"] = float(entity.shield)
		data["facing_x"] = float(facing.x)
		data["facing_y"] = float(facing.y)
		data["attack_cd"] = float(entity.attack_cd)
		data["haste_timer"] = float(entity.haste_timer)
		data["slow_timer"] = float(entity.slow_timer)
		data["moving"] = bool(entity.get("moving", false))
	elif entity.type == "minion":
		data["lane"] = str(entity.lane)
		data["speed"] = float(entity.speed)
		data["moving"] = bool(entity.get("moving", false))
	elif entity.type == "tower":
		data["lane"] = str(entity.lane)
		data["range"] = float(entity.range)
	return data
