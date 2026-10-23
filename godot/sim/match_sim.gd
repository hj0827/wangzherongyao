extends RefCounted

const MapData = preload("res://sim/map_data.gd")
const HeroDefs = preload("res://sim/hero_defs.gd")
const SkillSystem = preload("res://sim/skill_system.gd")
const TargetingRules = preload("res://sim/targeting_rules.gd")
const EconomySystem = preload("res://sim/economy_system.gd")
const ItemShop = preload("res://sim/item_shop.gd")
const CombatAnnouncer = preload("res://sim/combat_announcer.gd")
const MapLayout = preload("res://sim/map/map_layout.gd")
const Collision = preload("res://sim/map/collision.gd")
const Vision = preload("res://sim/map/vision.gd")
const TowerRules = preload("res://sim/map/tower_rules.gd")
const WaveRules = preload("res://sim/map/wave_rules.gd")
const Jungle = preload("res://sim/map/jungle.gd")
const Objectives = preload("res://sim/map/objectives.gd")
const RecallRules = preload("res://sim/map/recall.gd")
const Crystal = preload("res://sim/map/crystal.gd")
const River = preload("res://sim/map/river.gd")
const Teleport = preload("res://sim/map/teleport.gd")

const TICK_RATE := 30.0
const HERO_RESPAWN_BASE := 6.0
const WAVE_INTERVAL := 18.0
const FIRST_WAVE_DELAY := 1.0
const MINION_AGGRO_RANGE := 5.5
const STRUCTURE_RANGE := 8.0
const BASE_RANGE := 9.0
const MAX_LEVEL := 15

const TOWER_HP := {"outer": 2800.0, "inner": 3200.0, "high": 3600.0}
const TOWER_DAMAGE := {"outer": 150.0, "inner": 170.0, "high": 190.0}

# 野外脱战回血（每秒 % 最大生命）与基础回蓝
const FIELD_HP_REGEN := 0.025
const FIELD_MP_REGEN := 6.0
# 出手或受击后脱离草丛隐身的显形时长（秒）。
const REVEAL_AFTER_COMBAT := 1.5
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
var kill_log: Array[Dictionary] = []
var _announcer := CombatAnnouncer.new()
# 固定种子的线性同余，保证暴击判定在主机模拟里可复现，也不依赖引擎随机源。
var _rng_state := 0x2F6E2B1

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
		"objective": {"spawn_timer": Objectives.FIRST_SPAWN, "spawned": false},
		"objectives": {"buffs": {"blue": 0.0, "red": 0.0}},
		"river": River.initial_state(),
		"bot_ai": bool(config.get("bot_ai", false)),
	}
	_setup_teams()
	_setup_structures()
	_setup_jungle()
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
		"skill_w_cd": 0.0,
		"skill_e_cd": 0.0,
		"skill_r_cd": 0.0,
		"summoner_spell": "flash",
		"summoner_cd": 0.0,
		"attack_mode": "default",
		"locked_target": -1,
		"attack_drag": Vector2.ZERO,
		"gold": 0,
		"gold_fraction": 0.0,
		"inventory": [],
		"base_hp": float(hero_def.max_hp),
		"base_ad": float(hero_def.attack_damage),
		"base_speed": float(hero_def.speed),
		"ability_power": 0.0,
		"crit_rate": 0.0,
		"last_input_seq": -1,
		"last_purchase_seq": -1,
		"passive_stacks": 0,
		"cc_immune_timer": 0.0,
		"facing": Vector2(0.0, -1.0) if team == "blue" else Vector2(0.0, 1.0),
		"shield": 0.0,
		"shield_timer": 0.0,
		"haste_timer": 0.0,
		"slow_timer": 0.0,
		"revealed_timer": 0.0,
		"last_damage_time": -999.0,
		"last_attacker_id": -1,
		"last_attacker_time": -999.0,
		"last_hero_attacker_id": -1,
		"last_hero_attacker_time": -999.0,
		"last_killer_id": -1,
		"last_killer_name": "",
		"last_killer_type": "",
		"recalling": false,
		"recall_timer": 0.0,
		"recall_total": 0.0,
		"teleporting": false,
		"teleport_timer": 0.0,
		"teleport_total": 0.0,
		"teleport_cd": 0.0,
		"teleport_pad": "",
		"teleport_from": spawn,
		"buff_red_timer": 0.0,
		"buff_blue_timer": 0.0,
		"path": path,
		"path_index": path_index,
		"path_dir": 1 if team == "blue" else -1,
	}
	state.entities.append(hero)

func _setup_structures() -> void:
	var lanes: Array = ["mid"] if mode == "duel" else MapData.LANE_ORDER
	for slot in MapLayout.tower_slots():
		if not lanes.has(str(slot.lane)):
			continue
		_add_tower(str(slot.team), slot.pos, str(slot.lane), str(slot.tier))
	_add_base("blue", MapData.BLUE_BASE)
	_add_base("red", MapData.RED_BASE)
	for slot in MapLayout.guardian_slots():
		_add_guard(str(slot.team), slot.pos, str(slot.side))

func _add_tower(team: String, pos: Vector2, lane: String, tier: String) -> void:
	var hp: float = float(TOWER_HP.get(tier, 2800.0))
	state.entities.append({
		"id": _next_id(),
		"type": "tower",
		"team": team,
		"lane": lane,
		"tier": tier,
		"pos": pos,
		"radius": MapData.TOWER_RADIUS,
		"hp": hp,
		"max_hp": hp,
		"alive": true,
		"range": STRUCTURE_RANGE,
		"attack_damage": float(TOWER_DAMAGE.get(tier, 150.0)),
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
		"shield": 0.0,
		"shield_max": 0.0,
		"guards_alive": 0,
		"exposed": false,
		"last_shield_hit_time": -999.0,
	})

func _add_guard(team: String, pos: Vector2, side: String) -> void:
	state.entities.append({
		"id": _next_id(),
		"type": "guard",
		"team": team,
		"lane": "core",
		"side": side,
		"tier": "twin",
		"pos": pos,
		"radius": MapData.TOWER_RADIUS * 0.85,
		"hp": 3200.0,
		"max_hp": 3200.0,
		"alive": true,
		"range": STRUCTURE_RANGE - 1.0,
		"attack_damage": 160.0,
		"attack_interval": 1.1,
		"attack_cd": 0.0,
	})

func _setup_jungle() -> void:
	for camp in Jungle.CAMPS:
		_spawn_monster(Jungle.monster_stats(camp))

func _spawn_monster(stats: Dictionary) -> Dictionary:
	var monster: Dictionary = stats.duplicate(true)
	var pos: Vector2 = stats.get("pos", Vector2.ZERO)
	monster["id"] = _next_id()
	monster["pos"] = pos
	monster["home_pos"] = pos
	monster["attack_cd"] = 0.0
	monster["respawn_timer"] = 0.0
	monster["alive"] = true
	state.entities.append(monster)
	return monster

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
			var super_enabled := WaveRules.super_unlocked(str(lane), str(team), state.entities)
			var composition: Array = WaveRules.composition(int(state.wave), super_enabled)
			for index in composition.size():
				_spawn_minion(str(team), str(lane), path, index, str(composition[index]))
	_emit("wave", {"wave": state.wave})

func _spawn_minion(team: String, lane: String, path: Array, index: int, minion_type: String) -> void:
	var blue := team == "blue"
	var base: Vector2 = path[0] if blue else path[path.size() - 1]
	var path_index := 1 if blue else path.size() - 2
	var waypoint: Vector2 = path[path_index]
	var toward := (waypoint - base).normalized()
	var side := Vector2(-toward.y, toward.x)
	var pos := base + toward * 2.6 + side * (float(index) - 1.0) * 1.0
	var stats: Dictionary = WaveRules.stats(minion_type, int(state.wave))
	var minion := {
		"id": _next_id(),
		"type": "minion",
		"team": team,
		"lane": lane,
		"minion_type": minion_type,
		"pos": pos,
		"radius": float(stats.radius),
		"hp": float(stats.hp),
		"max_hp": float(stats.max_hp),
		"alive": true,
		"speed": float(stats.move_speed),
		"attack_damage": float(stats.attack_damage),
		"attack_range": float(stats.attack_range),
		"attack_interval": float(stats.attack_interval),
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
	var next := input.duplicate()
	var previous: Dictionary = inputs.get(player_id, {})
	if not previous.is_empty():
		# 购买/出售是离散意图。20Hz 输入可能晚于 30Hz 模拟到达，不能被下一条纯移动输入覆盖。
		if str(next.get("buy_item", "")) == "" and str(previous.get("buy_item", "")) != "":
			next["buy_item"] = previous["buy_item"]
		if int(next.get("sell_slot", -1)) < 0 and int(previous.get("sell_slot", -1)) >= 0:
			next["sell_slot"] = int(previous["sell_slot"])
	inputs[player_id] = next

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
	_update_objectives(dt)
	for spot in River.tick(state, dt):
		_spawn_monster(River.spirit_stats(spot))
	_update_hero_timers(dt)
	_apply_human_inputs(dt)
	_update_bots(dt)
	_update_minions(dt)
	_update_monsters(dt)
	_update_structures(dt)
	Crystal.tick(state, dt)
	_update_respawns(dt)
	_cleanup_dead_minions(dt)
	Objectives.tick(state, dt)

func _update_objectives(dt: float) -> void:
	if bool(state.objective.get("spawned", false)):
		return
	state.objective.spawn_timer = maxf(0.0, float(state.objective.spawn_timer) - dt)
	if float(state.objective.spawn_timer) > 0.0:
		return
	state.objective.spawned = true
	state.objective.spawn_timer = 0.0
	for pit in Objectives.PITS:
		_spawn_monster(Objectives.monster_stats(pit))
	_emit("objective_spawn", {"name": "暴君与主宰"})

func _update_monsters(dt: float) -> void:
	for entity in state.entities:
		if entity.type != "monster":
			continue
		entity.attack_cd = maxf(0.0, float(entity.get("attack_cd", 0.0)) - dt)
		if not bool(entity.get("alive", false)):
			entity.respawn_timer = maxf(0.0, float(entity.get("respawn_timer", 0.0)) - dt)
			if float(entity.respawn_timer) <= 0.0:
				_respawn_monster(entity)
			continue
		var target: Dictionary = _monster_target(entity)
		if target.is_empty():
			_advance_monster_home(entity, dt)
			continue
		var reach: float = float(entity.attack_range) + float(target.get("radius", 0.0))
		if entity.pos.distance_to(target.pos) <= reach:
			if float(entity.attack_cd) <= 0.0:
				entity.attack_cd = float(entity.attack_interval)
				entity.facing = (target.pos - entity.pos).normalized()
				_damage(target, float(entity.attack_damage), entity)
		elif not bool(entity.get("objective", false)):
			var home: Vector2 = entity.get("home_pos", entity.pos)
			if entity.pos.distance_to(home) <= float(entity.get("leash_range", 11.0)):
				var next: Vector2 = entity.pos + (target.pos - entity.pos).normalized() * float(entity.move_speed) * dt
				entity.pos = Collision.move(entity.pos, next, float(entity.get("radius", 1.0)))
				entity.moving = true

func _monster_target(monster: Dictionary) -> Dictionary:
	var best: Dictionary = {}
	var best_distance := float(monster.get("aggro_range", 5.5))
	for entity in state.entities:
		if not bool(entity.get("alive", false)) or str(entity.get("type", "")) != "hero":
			continue
		if str(entity.get("team", "")) == "neutral" or str(entity.get("team", "")) == str(monster.get("team", "")):
			continue
		var distance: float = monster.pos.distance_to(entity.pos)
		if distance < best_distance:
			best_distance = distance
			best = entity
	if not best.is_empty():
		return best
	var attacker: Dictionary = _entity_by_id(int(monster.get("last_attacker_id", -1)))
	if not attacker.is_empty() and bool(attacker.get("alive", false)) and str(attacker.get("type", "")) == "hero":
		if monster.pos.distance_to(attacker.pos) <= float(monster.get("leash_range", 11.0)):
			return attacker
	return {}

func _advance_monster_home(monster: Dictionary, dt: float) -> void:
	var home: Vector2 = monster.get("home_pos", monster.pos)
	if monster.pos.distance_to(home) <= 0.2:
		return
	var next: Vector2 = monster.pos + (home - monster.pos).normalized() * float(monster.get("move_speed", 3.0)) * dt
	monster.pos = Collision.move(monster.pos, next, float(monster.get("radius", 1.0)))

func _respawn_monster(monster: Dictionary) -> void:
	monster.alive = true
	monster.hp = float(monster.max_hp)
	monster.pos = monster.get("home_pos", monster.pos)
	monster.respawn_timer = 0.0
	monster.attack_cd = 0.0
	monster.last_attacker_id = -1
	monster.last_attacker_time = -999.0
	monster.last_hero_attacker_id = -1
	monster.last_hero_attacker_time = -999.0
	_emit("monster_respawn", {
		"name": str(monster.get("name", "野怪")),
		"x": float(monster.pos.x),
		"y": float(monster.pos.y),
	})

func _cleanup_dead_minions(dt: float) -> void:
	for i in range(state.entities.size() - 1, -1, -1):
		var entity: Dictionary = state.entities[i]
		if entity.type == "minion" and not bool(entity.get("alive", false)):
			var timer: float = float(entity.get("death_cleanup_timer", 2.0)) - dt
			if timer <= 0.0:
				state.entities.remove_at(i)
			else:
				entity["death_cleanup_timer"] = timer

# 是否站在己方泉水范围内（基地中心 MapData.FOUNTAIN_RADIUS 以内）。
func _in_fountain(entity: Dictionary) -> bool:
	var base := MapData.BLUE_BASE if str(entity.team) == "blue" else MapData.RED_BASE
	return (entity.pos as Vector2).distance_to(base) <= MapData.FOUNTAIN_RADIUS

func _update_hero_timers(dt: float) -> void:
	for entity in state.entities:
		if entity.type != "hero" or not entity.alive:
			continue
		EconomySystem.tick_natural_gold(entity, dt)
		Jungle.tick_buffs(entity, dt)
		entity.skill_q_cd = maxf(0.0, float(entity.skill_q_cd) - dt)
		entity.skill_w_cd = maxf(0.0, float(entity.get("skill_w_cd", 0.0)) - dt)
		entity.skill_e_cd = maxf(0.0, float(entity.skill_e_cd) - dt)
		entity.skill_r_cd = maxf(0.0, float(entity.get("skill_r_cd", 0.0)) - dt)
		entity.summoner_cd = maxf(0.0, float(entity.get("summoner_cd", 0.0)) - dt)
		entity.teleport_cd = maxf(0.0, float(entity.get("teleport_cd", 0.0)) - dt)
		entity.cc_immune_timer = maxf(0.0, float(entity.get("cc_immune_timer", 0.0)) - dt)
		entity.attack_cd = maxf(0.0, float(entity.attack_cd) - dt)
		entity.shield_timer = maxf(0.0, float(entity.shield_timer) - dt)
		if float(entity.shield_timer) <= 0.0:
			entity.shield = 0.0
		entity.haste_timer = maxf(0.0, float(entity.haste_timer) - dt)
		entity.slow_timer = maxf(0.0, float(entity.slow_timer) - dt)
		entity["revealed_timer"] = maxf(0.0, float(entity.get("revealed_timer", 0.0)) - dt)
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
		entity["attack_mode"] = str(input.get("attack_mode", "default"))
		entity["locked_target"] = int(input.get("locked_target", -1))
		entity["attack_drag"] = aim_vector if bool(input.get("attack", false)) else Vector2.ZERO
		var seq := int(input.get("seq", 0))
		var buy_item_id := str(input.get("buy_item", ""))
		var sell_slot := int(input.get("sell_slot", -1))
		# 意图只消费一次：否则 set_input 的合并逻辑会把旧购买带进下一个输入序列。
		input["buy_item"] = ""
		input["sell_slot"] = -1
		if seq > int(entity.get("last_input_seq", -1)):
			entity["last_input_seq"] = seq
		# 购买走可靠通道，可能与不可靠的移动输入乱序，所以用独立的购买序号去重，
		# 不能被先到的移动输入把 last_input_seq 抬高而吞掉。
		if (buy_item_id != "" or sell_slot >= 0) and seq > int(entity.get("last_purchase_seq", -1)):
			entity["last_purchase_seq"] = seq
			if buy_item_id != "" and ItemShop.buy_item(entity, buy_item_id):
				_emit("purchase", {
					"hero": entity.id,
					"buy_item": buy_item_id,
					"amount": int(ItemShop.get_item(buy_item_id).get("cost", 0)),
				})
			if sell_slot >= 0 and ItemShop.sell_item(entity, sell_slot):
				_emit("sold", {"hero": entity.id, "sell_slot": sell_slot})
		if move.length() > 1.0:
			move = move.normalized()
		if bool(input.get("teleport", false)) and not bool(entity.get("teleporting", false)):
			if Teleport.start(entity):
				RecallRules.interrupt(entity)
		if bool(entity.get("teleporting", false)):
			var departure: Vector2 = entity.get("teleport_from", entity.pos)
			if Teleport.tick(entity, input, dt):
				_emit("teleport", {
					"team": entity.team,
					"pad": str(entity.get("teleport_pad", "")),
					"x": float(departure.x),
					"y": float(departure.y),
					"to_x": float(entity.pos.x),
					"to_y": float(entity.pos.y),
				})
				continue
		if bool(input.get("recall", false)) and not bool(entity.get("recalling", false)) and not _in_fountain(entity):
			RecallRules.start(entity)
		if bool(entity.get("recalling", false)):
			if RecallRules.tick(entity, input, dt):
				continue
		if move.length() > 0.01:
			# 移动时朝向移动方向：点击移动经常是「往身后走」，若还朝着准星就成了倒着走。
			# 站住时才看向准星；技能与普攻随后各自把 facing 改回目标方向，瞄准手感不变。
			entity.facing = move.normalized()
			_move_hero(entity, move, dt)
		elif aim_vector.length() > 0.6:
			entity.facing = aim_vector.normalized()
		if bool(input.get("skill_q", false)):
			_cast_q(entity, aim)
		if bool(input.get("skill_w", false)):
			SkillSystem.cast_skill(entity, "w", aim, self)
		if bool(input.get("skill_e", false)):
			_cast_e(entity, aim)
		if bool(input.get("skill_r", false)):
			SkillSystem.cast_skill(entity, "r", aim, self)
		if bool(input.get("summoner", false)):
			SkillSystem.cast_summoner_spell(entity, str(entity.get("summoner_spell", "flash")), aim, self)
		if bool(input.get("attack", false)):
			_try_attack(entity)

func _update_bots(dt: float) -> void:
	if not bool(state.bot_ai):
		return
	for entity in state.entities:
		if entity.type != "hero" or not entity.alive or entity.controller != "bot":
			continue
		var recommended := ItemShop.get_quick_buy_recommendation(entity, ItemShop.build_order_for(str(entity.hero_type)))
		if recommended != "":
			ItemShop.buy_item(entity, recommended)
		var target: Dictionary = _nearest_enemy(entity, 9.0)
		if target.is_empty():
			_advance_along_path(entity, dt)
			continue
		var to_target: Vector2 = target.pos - entity.pos
		if to_target.length() > 0.1:
			entity.facing = to_target.normalized()
		var distance := to_target.length()
		if float(entity.skill_q_cd) <= 0.0 and distance <= 9.0:
			_cast_q(entity, target.pos)
		var hero_def: Dictionary = HeroDefs.get_hero(str(entity.hero_type))
		var w_def: Dictionary = hero_def.w
		if float(entity.skill_w_cd) <= 0.0 and distance <= float(w_def.range) + 1.0 and float(entity.mp) >= float(w_def.cost):
			SkillSystem.cast_skill(entity, "w", target.pos, self)
		var r_def: Dictionary = hero_def.r
		if float(entity.skill_r_cd) <= 0.0 and distance <= float(r_def.range) + float(target.get("radius", 0.0)) and float(entity.mp) >= float(r_def.cost):
			SkillSystem.cast_skill(entity, "r", target.pos, self)
		_use_bot_summoner(entity, target, distance)
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

func _use_bot_summoner(hero: Dictionary, target: Dictionary, distance: float) -> void:
	if float(hero.summoner_cd) > 0.0:
		return
	var spell := str(hero.get("summoner_spell", "flash"))
	var hp_ratio := float(hero.hp) / maxf(1.0, float(hero.max_hp))
	match spell:
		"heal":
			if hp_ratio < 0.55:
				SkillSystem.cast_summoner_spell(hero, spell, hero.pos, self)
		"execute":
			var target_ratio := float(target.get("hp", 0.0)) / maxf(1.0, float(target.get("max_hp", 1.0)))
			if distance <= 4.0 and target_ratio < 0.4:
				SkillSystem.cast_summoner_spell(hero, spell, target.pos, self)
		"cleanse":
			if float(hero.slow_timer) > 0.0:
				SkillSystem.cast_summoner_spell(hero, spell, hero.pos, self)
		"flash":
			if hp_ratio < 0.3 and distance < 3.0:
				SkillSystem.cast_summoner_spell(hero, spell, hero.pos + (hero.pos - target.pos), self)

func _move_hero(hero: Dictionary, direction: Vector2, dt: float) -> void:
	var speed: float = float(hero.speed)
	if float(hero.haste_timer) > 0.0:
		speed *= 1.4
	if float(hero.slow_timer) > 0.0:
		speed *= 0.65
	var destination: Vector2 = hero.pos + direction * speed * dt
	hero.pos = Collision.move(hero.pos, destination, float(hero.get("radius", 0.55)))
	hero.moving = true

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
		var destination: Vector2 = entity.pos + to_point.normalized() * speed * dt
		entity.pos = Collision.move(entity.pos, destination, float(entity.get("radius", 0.4)))
		entity.moving = true

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
			var destination: Vector2 = entity.pos + step * float(entity.speed) * dt
			entity.pos = Collision.move(entity.pos, destination, float(entity.get("radius", 0.4)))
			entity.moving = true

func _update_structures(dt: float) -> void:
	for entity in state.entities:
		if entity.type != "tower" and entity.type != "base" and entity.type != "guard":
			continue
		if not entity.alive:
			continue
		if entity.type == "guard" and not Crystal.is_guard_vulnerable(entity, state.entities):
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
	return TowerRules.select_target(structure, state.entities, float(state.time))

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
		if entity.type == "tower" or entity.type == "base" or entity.type == "guard":
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
	hero.skill_q_cd = float(skill.cooldown) * Jungle.cooldown_scale(hero)
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
			if entity.type != "hero" and entity.type != "minion" and entity.type != "monster":
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
		var destination: Vector2 = hero.pos + direction.normalized() * float(skill.range)
		hero.pos = Collision.move(hero.pos, destination, float(hero.get("radius", 0.55)))
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
			if entity.type != "hero" and entity.type != "minion" and entity.type != "monster":
				continue
			if entity.pos.distance_to(target.pos) <= 3.0:
				entity.slow_timer = maxf(float(entity.get("slow_timer", 0.0)), 2.5)
				_damage(entity, float(skill.damage), hero)
	hero.mp = float(hero.mp) - float(skill.cost)
	hero.skill_e_cd = float(skill.cooldown) * Jungle.cooldown_scale(hero)
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
		if entity.type != "hero" and entity.type != "minion" and entity.type != "tower" and entity.type != "guard" and entity.type != "monster":
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
	var mode := str(hero.get("attack_mode", "default"))
	var locked := int(hero.get("locked_target", -1))
	var drag: Vector2 = hero.get("attack_drag", Vector2.ZERO)
	var target: Dictionary = TargetingRules.resolve_attack_target(hero, state.entities, mode, locked, drag)
	if target.is_empty():
		return
	var reach: float = float(hero.attack_range) + float(target.get("radius", 0.0))
	if hero.pos.distance_to(target.pos) > reach:
		# 拖拽指向的目标够不着时退回常规索敌，避免「朝着空地按住普攻就完全不攻击」。
		if drag.length() > 0.3 and not TargetingRules.is_lock_valid(hero, locked, state.entities):
			target = TargetingRules.resolve_attack_target(hero, state.entities, mode, -1, Vector2.ZERO)
			if target.is_empty():
				return
			reach = float(hero.attack_range) + float(target.get("radius", 0.0))
			if hero.pos.distance_to(target.pos) > reach:
				return
		else:
			return
	hero.attack_cd = float(hero.attack_interval)
	hero.facing = (target.pos - hero.pos).normalized()
	var damage: float = float(hero.attack_damage)
	var crit := float(hero.get("crit_rate", 0.0)) > 0.0 and _next_random() < float(hero.get("crit_rate", 0.0))
	if crit:
		damage *= 1.5
	_emit("attack", {
		"hero": hero.id,
		"x": float(hero.pos.x),
		"y": float(hero.pos.y),
		"aim_x": float(target.pos.x),
		"aim_y": float(target.pos.y),
		"crit": crit,
	})
	_damage(target, damage, hero)
	# 被动挂在真实普攻命中上：英雄详情里的描述与实战数值必须同源。
	SkillSystem.on_hero_attack_hit(hero, target, self)

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
			entity.last_attacker_id = -1
			entity.last_attacker_time = -999.0
			entity.last_hero_attacker_id = -1
			entity.last_hero_attacker_time = -999.0
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
	if target.type == "tower" and not TowerRules.is_tower_vulnerable(target, state.entities):
		return
	if target.type == "guard" and not Crystal.is_guard_vulnerable(target, state.entities):
		return
	if target.type == "base" and not TowerRules.is_base_vulnerable(target, state.entities):
		return
	var incoming := amount
	if target.type == "tower":
		incoming *= TowerRules.damage_scale(target, state.time)
	if not source.is_empty() and str(source.get("type", "")) == "hero":
		incoming *= Jungle.damage_scale(source) * Objectives.damage_scale(state, str(source.get("team", "")))
	# 交手即暴露：草丛里的英雄一出手/一挨打就短暂显形，否则回放里会出现
	# 「血条自己掉、伤害来源不可见」的诡异画面。
	if target.type == "hero" and not source.is_empty() and str(source.get("team", "")) != str(target.get("team", "")):
		target["revealed_timer"] = REVEAL_AFTER_COMBAT
		if str(source.get("type", "")) == "hero":
			source["revealed_timer"] = REVEAL_AFTER_COMBAT
	var remaining := incoming
	if float(target.get("shield", 0.0)) > 0.0:
		var absorbed: float = minf(float(target.shield), remaining)
		target.shield = float(target.shield) - absorbed
		remaining -= absorbed
		if target.type == "base":
			target["last_shield_hit_time"] = float(state.time)
	if remaining <= 0.0:
		return
	if target.type == "hero":
		RecallRules.interrupt(target)
		Teleport.interrupt(target)
	target.hp = float(target.hp) - remaining
	if target.type == "hero":
		target.last_damage_time = float(state.time)
		if not source.is_empty():
			target.last_attacker_id = int(source.get("id", -1))
			target.last_attacker_time = float(state.time)
			if str(source.get("type", "")) == "hero" and str(source.get("team", "")) != str(target.get("team", "")):
				target.last_hero_attacker_id = int(source.get("id", -1))
				target.last_hero_attacker_time = float(state.time)
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
		RecallRules.interrupt(target)

		# 判定真正击杀者 (Killer Attribution)
		var killer: Dictionary = {}
		# 1. 致命伤害直接来自敌方英雄
		if not source.is_empty() and str(source.get("type", "")) == "hero" and str(source.get("team", "")) != str(target.get("team", "")):
			killer = source
		# 2. 致命伤害来自防御塔/小兵/机关等非英雄，但近期受到敌方英雄伤害（10秒内判定为英雄击杀）
		elif float(state.time) - float(target.get("last_hero_attacker_time", -999.0)) <= 10.0:
			var hero_attacker: Dictionary = _entity_by_id(int(target.get("last_hero_attacker_id", -1)))
			if not hero_attacker.is_empty() and str(hero_attacker.get("type", "")) == "hero" and str(hero_attacker.get("team", "")) != str(target.get("team", "")):
				killer = hero_attacker
		# 3. 致命伤害来自防御塔/小兵，无英雄参与伤害
		elif not source.is_empty():
			killer = source

		var killer_id: int = -1
		var killer_type := "unknown"
		var killer_name := "战场机关"
		var killer_team: String = "blue" if str(target.team) == "red" else "red"
		var killer_hero_type := ""

		if not killer.is_empty():
			killer_id = int(killer.get("id", -1))
			killer_type = str(killer.get("type", "unknown"))
			killer_team = str(killer.get("team", killer_team))
			if killer_type == "hero":
				killer_name = str(killer.get("name", "英雄"))
				killer_hero_type = str(killer.get("hero_type", ""))
				killer.kills = int(killer.get("kills", 0)) + 1
				state.scores[killer.team].kills = int(state.scores[killer.team].kills) + 1
				EconomySystem.award_hero_kill(killer, kill_log.is_empty())
				_add_xp(killer, 130.0)
			elif killer_type == "tower" or killer_type == "base":
				killer_name = "防御塔" if killer_type == "tower" else "主堡"
			elif killer_type == "minion":
				killer_name = "小兵"
			elif killer_type == "monster":
				killer_name = str(killer.get("name", "野怪"))
			else:
				killer_name = str(killer.get("name", "战场机关"))

		target["last_killer_id"] = killer_id
		target["last_killer_name"] = killer_name
		target["last_killer_type"] = killer_type
		target["last_killer_team"] = killer_team

		var announce: Dictionary
		if killer_type == "hero":
			announce = _announcer.record_kill(
				killer_id, killer_hero_type, killer_team,
				int(target.id), str(target.hero_type), str(target.team), float(state.time)
			)
		else:
			announce = _announcer.record_death(int(target.id))

		var kill_record := {
			"time": float(state.time),
			"victim_id": int(target.id),
			"victim_name": str(target.name),
			"victim_team": str(target.team),
			"victim_hero_type": str(target.hero_type),
			"killer_id": killer_id,
			"killer_name": killer_name,
			"killer_team": killer_team,
			"killer_type": killer_type,
			"killer_hero_type": killer_hero_type,
			"announcement": str(announce.get("announcement", "")),
			"streak_title": str(announce.get("streak_title", "")),
		}
		kill_log.append(kill_record)

		_emit("death", {
			"entity_type": "hero",
			"hero": target.id,
			"team": target.team,
			"hero_type": target.hero_type,
			"victim_name": str(target.name),
			"victim_team": str(target.team),
			"victim_id": int(target.id),
			"killer": killer_id,
			"killer_id": killer_id,
			"killer_type": killer_type,
			"killer_name": killer_name,
			"killer_hero_type": killer_hero_type,
			"killer_team": killer_team,
			"announcement": str(announce.get("announcement", "")),
			"streak_title": str(announce.get("streak_title", "")),
			"x": float(target.pos.x),
			"y": float(target.pos.y),
		})
		if _announcer.check_ace(str(target.team), state.entities):
			_emit("ace", {
				"team": target.team,
				"victim_team": target.team,
			})
	elif target.type == "minion":
		target.death_cleanup_timer = 2.0
		if not source.is_empty() and source.type == "hero":
			_add_xp(source, 32.0)
			_award_minion_gold(target, source)
		else:
			_award_minion_gold(target, {})
		_emit("death", {
			"entity_type": "minion",
			"team": target.team,
			"x": float(target.pos.x),
			"y": float(target.pos.y),
		})
	elif target.type == "monster":
		target.respawn_timer = float(target.get("respawn_time", Jungle.RESPAWN_TIME))
		target.last_attacker_id = -1
		target.last_attacker_time = -999.0
		if bool(target.get("objective", false)):
			if not source.is_empty() and str(source.get("type", "")) == "hero":
				Objectives.grant_buff(state, str(source.get("team", "")))
				_add_xp(source, 160.0)
			_emit("objective_killed", {
				"team": str(source.get("team", "")),
				"name": str(target.get("name", "首领")),
				"objective_id": str(target.get("objective_id", "")),
				"x": float(target.pos.x),
				"y": float(target.pos.y),
			})
		elif bool(target.get("river_spirit", false)):
			if not source.is_empty() and str(source.get("type", "")) == "hero":
				River.grant_reveal(state, str(source.get("team", "")), target.pos)
				_add_xp(source, River.SPIRIT_XP)
			_emit("river_spirit_killed", {
				"team": str(source.get("team", "")),
				"name": str(target.get("name", "河道之灵")),
				"x": float(target.pos.x),
				"y": float(target.pos.y),
			})
		else:
			if not source.is_empty() and str(source.get("type", "")) == "hero":
				Jungle.apply_buff(source, str(target.get("buff_type", "")))
				_add_xp(source, 45.0)
			_emit("buff_taken", {
				"team": str(source.get("team", "")),
				"buff": str(target.get("buff_type", "")),
				"name": str(target.get("name", "野怪")),
				"x": float(target.pos.x),
				"y": float(target.pos.y),
			})
		_emit("death", {
			"entity_type": "monster",
			"team": "neutral",
			"name": str(target.get("name", "野怪")),
			"x": float(target.pos.x),
			"y": float(target.pos.y),
		})
	elif target.type == "guard":
		var info: Dictionary = Crystal.on_guard_destroyed(state, target)
		if not source.is_empty() and source.type == "hero":
			_add_xp(source, 120.0)
		_emit("guard_destroyed", {
			"team": target.team,
			"side": str(target.get("side", "")),
			"guards_left": int(info.get("guards_alive", 0)),
			"x": float(target.pos.x),
			"y": float(target.pos.y),
		})
		if bool(info.get("broken", false)):
			_emit("crystal_shield_broken", {
				"team": target.team,
				"x": float(target.pos.x),
				"y": float(target.pos.y),
			})
		_emit("death", {
			"entity_type": "guard",
			"team": target.team,
			"x": float(target.pos.x),
			"y": float(target.pos.y),
		})
	elif target.type == "tower":
		var winner_team := "blue" if target.team == "red" else "red"
		state.scores[winner_team].towers = int(state.scores[winner_team].towers) + 1
		EconomySystem.award_tower_team_gold(winner_team, state.entities)
		if not source.is_empty() and source.type == "hero":
			_add_xp(source, 80.0)
		_emit("tower_destroyed", {
			"team": target.team,
			"lane": target.lane,
			"tier": str(target.get("tier", "")),
			"x": float(target.pos.x),
			"y": float(target.pos.y),
		})
		if str(target.get("tier", "")) == "high":
			_emit("base_exposed", {"team": target.team, "lane": target.lane})
	elif target.type == "base":
		state.winner = "blue" if target.team == "red" else "red"
		ended = true
		_emit("match_end", {"winner": state.winner})

func _award_minion_gold(victim: Dictionary, last_hitter: Dictionary) -> void:
	const ASSIST_RADIUS := 8.0
	if not last_hitter.is_empty():
		EconomySystem.award_minion_kill(last_hitter, true)
		for entity in state.entities:
			if entity.type != "hero" or not entity.alive:
				continue
			if str(entity.team) != str(last_hitter.team) or int(entity.id) == int(last_hitter.id):
				continue
			if entity.pos.distance_to(victim.pos) <= ASSIST_RADIUS:
				EconomySystem.award_minion_kill(entity, false)
		return
	# 没有英雄补刀时，最近的一名敌方英雄获得基础金币，避免小兵对拼时经济完全断流。
	var best: Dictionary = {}
	var best_dist := ASSIST_RADIUS
	for entity in state.entities:
		if entity.type != "hero" or not entity.alive:
			continue
		if str(entity.team) == str(victim.get("team", "")):
			continue
		var dist: float = entity.pos.distance_to(victim.pos)
		if dist <= best_dist:
			best_dist = dist
			best = entity
	if not best.is_empty():
		EconomySystem.award_minion_kill(best, false)

func _next_random() -> float:
	_rng_state = (_rng_state * 1103515245 + 12345) & 0x7FFFFFFF
	return float(_rng_state) / 2147483648.0

func _add_xp(hero: Dictionary, amount: float) -> void:
	if hero.type != "hero" or not hero.alive:
		return
	hero.xp = float(hero.xp) + amount
	while int(hero.level) < MAX_LEVEL and float(hero.xp) >= _xp_needed(int(hero.level)):
		hero.xp = float(hero.xp) - _xp_needed(int(hero.level))
		hero.level = int(hero.level) + 1
		var hero_def: Dictionary = HeroDefs.get_hero(str(hero.hero_type))
		# 成长值写进 base_*，再由装备系统统一重算，避免装备加成被升级覆盖或重复叠加。
		hero.base_hp = float(hero.get("base_hp", hero.max_hp)) + float(hero_def.hp_growth)
		hero.base_ad = float(hero.get("base_ad", hero.attack_damage)) + float(hero_def.damage_growth)
		hero.max_mp = float(hero.max_mp) + float(hero_def.mp_growth)
		ItemShop.recalculate_stats(hero)
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
		"objectives": _snapshot_objectives(),
		"river": _snapshot_river(),
	}

# 客机视角快照：只包含己方与视野内目标，避免全图透视。
# events_override 用于联机广播：服务端把两次快照之间的全部事件攒下来传入，
# 避免 10Hz 快照只带得走最后 1/30 秒的事件。
func snapshot_for(team: String, events_override: Variant = null) -> Dictionary:
	var shot := snapshot()
	if events_override is Array:
		shot["events"] = (events_override as Array).duplicate(true)
	return Vision.filter_snapshot(shot, team)

func _snapshot_objectives() -> Dictionary:
	var spawn_timer := float(state.objective.get("spawn_timer", 0.0))
	if bool(state.objective.get("spawned", false)):
		spawn_timer = 0.0
		var pending := 0.0
		var waiting := false
		for entity in state.entities:
			if entity.type != "monster" or not bool(entity.get("objective", false)):
				continue
			if bool(entity.get("alive", true)):
				continue
			var timer: float = float(entity.get("respawn_timer", Objectives.RESPAWN))
			pending = timer if not waiting else minf(pending, timer)
			waiting = true
		if waiting:
			spawn_timer = pending
	var buffs: Dictionary = state.objectives.get("buffs", {})
	return {
		"spawn_timer": spawn_timer,
		"blue_buff": float(buffs.get("blue", 0.0)),
		"red_buff": float(buffs.get("red", 0.0)),
	}

func _snapshot_river() -> Dictionary:
	River.ensure_state(state)
	var reveals: Dictionary = state.river.reveals
	return {
		"spawn_timer": float(state.river.get("spawn_timer", 0.0)),
		"reveals": {
			"blue": (reveals.get("blue", []) as Array).duplicate(true),
			"red": (reveals.get("red", []) as Array).duplicate(true),
		},
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
		data["skill_w_cd"] = float(entity.get("skill_w_cd", 0.0))
		data["skill_e_cd"] = float(entity.skill_e_cd)
		data["skill_r_cd"] = float(entity.get("skill_r_cd", 0.0))
		data["summoner_cd"] = float(entity.get("summoner_cd", 0.0))
		data["summoner_spell"] = str(entity.get("summoner_spell", "flash"))
		data["gold"] = int(entity.get("gold", 0))
		data["inventory"] = (entity.get("inventory", []) as Array).duplicate()
		data["ability_power"] = float(entity.get("ability_power", 0.0))
		data["crit_rate"] = float(entity.get("crit_rate", 0.0))
		data["speed"] = float(entity.speed)
		data["shield"] = float(entity.shield)
		data["facing_x"] = float(facing.x)
		data["facing_y"] = float(facing.y)
		data["attack_cd"] = float(entity.attack_cd)
		data["haste_timer"] = float(entity.haste_timer)
		data["slow_timer"] = float(entity.slow_timer)
		data["moving"] = bool(entity.get("moving", false))
		data["last_killer_name"] = str(entity.get("last_killer_name", ""))
		data["recalling"] = bool(entity.get("recalling", false))
		data["recall_timer"] = float(entity.get("recall_timer", 0.0))
		data["recall_total"] = float(entity.get("recall_total", 0.0))
		data["teleporting"] = bool(entity.get("teleporting", false))
		data["teleport_timer"] = float(entity.get("teleport_timer", 0.0))
		data["teleport_total"] = float(entity.get("teleport_total", 0.0))
		data["teleport_cd"] = float(entity.get("teleport_cd", 0.0))
		data["buff_red_timer"] = float(entity.get("buff_red_timer", 0.0))
		data["buff_blue_timer"] = float(entity.get("buff_blue_timer", 0.0))
		data["revealed_timer"] = float(entity.get("revealed_timer", 0.0))
		# 客机用它把「已被服务端处理的最后一个输入」对掉，剩余输入重放。
		data["last_input_seq"] = int(entity.get("last_input_seq", -1))
	elif entity.type == "minion":
		data["lane"] = str(entity.lane)
		data["minion_type"] = str(entity.get("minion_type", "melee"))
		data["speed"] = float(entity.speed)
		data["moving"] = bool(entity.get("moving", false))
	elif entity.type == "tower":
		data["lane"] = str(entity.lane)
		data["tier"] = str(entity.get("tier", "outer"))
		data["range"] = float(entity.range)
		data["vulnerable"] = TowerRules.is_tower_vulnerable(entity, state.entities)
	elif entity.type == "guard":
		data["lane"] = str(entity.get("lane", "core"))
		data["tier"] = str(entity.get("tier", "twin"))
		data["side"] = str(entity.get("side", ""))
		data["range"] = float(entity.get("range", 7.0))
		data["vulnerable"] = Crystal.is_guard_vulnerable(entity, state.entities)
	elif entity.type == "base":
		data["vulnerable"] = TowerRules.is_base_vulnerable(entity, state.entities)
		data["shield"] = float(entity.get("shield", 0.0))
		data["shield_max"] = float(entity.get("shield_max", 0.0))
		data["guards_alive"] = int(entity.get("guards_alive", 0))
	elif entity.type == "monster":
		data["monster_type"] = str(entity.get("monster_type", "wolf"))
		data["camp_id"] = str(entity.get("camp_id", ""))
		data["buff_type"] = str(entity.get("buff_type", ""))
		data["objective"] = bool(entity.get("objective", false))
		data["objective_id"] = str(entity.get("objective_id", ""))
		data["name"] = str(entity.get("name", "野怪"))
		data["respawn_timer"] = float(entity.get("respawn_timer", 0.0)) if not bool(entity.get("alive", true)) else 0.0
	return data

func get_last_kill() -> Dictionary:
	return kill_log.back() if not kill_log.is_empty() else {}

func get_killer_of(victim_id: int) -> Dictionary:
	for i in range(kill_log.size() - 1, -1, -1):
		if int(kill_log[i].victim_id) == victim_id:
			return kill_log[i]
	return {}
