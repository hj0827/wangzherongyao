extends "res://tests/test_base.gd"

# 点击移动（左键点地走位）的行为契约。
#
# 这一层刻意不建场景：Arena.new() 不入树，_ready 不跑，只驱动输入层
# （_set_move_target / _click_move_vector / _gather_input）。
# 位移用「sim 的 clamp 公式手动推进」，不依赖塔、小兵、AI，
# 免得英雄半路被打死让断言假通过。

const Arena = preload("res://scripts/game/arena.gd")
const MatchSim = preload("res://sim/match_sim.gd")
const MapData = preload("res://sim/map_data.gd")

const DT := 1.0 / 30.0

func _arena() -> Node3D:
	var arena := Arena.new()
	arena.local_owner = "p1"
	arena.local_team = "blue"
	return arena

# 形状对齐 match_sim._snapshot_entity 给出的真实快照字段（x/y，不是 pos）。
func _hero_at(pos: Vector2, overrides := {}) -> Dictionary:
	var hero := {
		"type": "hero",
		"owner_id": "p1",
		"team": "blue",
		"x": pos.x,
		"y": pos.y,
		"radius": 0.55,
		"speed": 6.4,
		"alive": true,
		"haste_timer": 0.0,
		"slow_timer": 0.0,
	}
	for key in overrides:
		hero[key] = overrides[key]
	return hero

func _attach(arena: Node3D, hero: Dictionary) -> void:
	arena.current_snapshot = {"entities": [hero]}

func _move_hero_dict(hero: Dictionary, pos: Vector2) -> void:
	hero["x"] = pos.x
	hero["y"] = pos.y

# 手动推进一个 tick，clamp 规则与 match_sim._clamp_position 完全一致。
func _step(hero: Dictionary, move: Vector2) -> Vector2:
	var radius := float(hero.get("radius", 0.0))
	var limit := MapData.BOUNDS - radius
	var pos := Vector2(float(hero.x), float(hero.y))
	var speed := float(hero.speed)
	if float(hero.get("haste_timer", 0.0)) > 0.0:
		speed *= 1.4
	if float(hero.get("slow_timer", 0.0)) > 0.0:
		speed *= 0.65
	pos += move * speed * DT
	pos = Vector2(clampf(pos.x, -limit, limit), clampf(pos.y, -limit, limit))
	_move_hero_dict(hero, pos)
	return pos

# ---------------------------------------------------------------- 落点合法性

func test_click_target_stays_inside_hero_walkable_area() -> void:
	# 点在屏幕最外侧时会被投到地图外。目标点若比「英雄可走边界」更靠外，
	# sim 的 _clamp_position 会先把英雄拦下来 → 距离永远差一截 → 目标永不失效。
	var arena := _arena()
	var radius := 0.55
	var hero := _hero_at(Vector2.ZERO, {"radius": radius})
	_attach(arena, hero)
	arena._set_move_target(Vector2(9999.0, 9999.0))
	var walkable := MapData.BOUNDS - radius
	check(
		absf(arena._move_target.x) <= walkable + 0.0001 and absf(arena._move_target.y) <= walkable + 0.0001,
		"目标必须落在英雄可走范围内（walkable=%.2f，实际=(%.2f, %.2f)）" % [walkable, arena._move_target.x, arena._move_target.y]
	)
	arena.free()

func test_click_beyond_map_edge_still_ends_and_arrives() -> void:
	var arena := _arena()
	var hero := _hero_at(Vector2(50.0, 0.0))
	_attach(arena, hero)
	arena._set_move_target(Vector2(9999.0, 0.0))
	var reached := false
	var ticks := 0
	for i in 240:
		var move: Vector2 = arena._click_move_vector()
		if not arena._move_target_valid:
			reached = true
			ticks = i
			break
		_step(hero, move)
		_attach(arena, hero)
	check(reached, "点在可走范围外时也必须能结束移动，否则英雄贴边原地踏步、目标永不失效")
	check(
		Vector2(float(hero.x), float(hero.y)).distance_to(arena._move_target) <= Arena.MOVE_ARRIVE_EPS + 0.01,
		"到达后应停在目标 eps 内（实际 %.3f）" % Vector2(float(hero.x), float(hero.y)).distance_to(arena._move_target)
	)
	lt(float(ticks), 60.0, "边界点不该走到超时（实际 %d tick）" % ticks)
	arena.free()

func test_click_target_survives_snapshot_with_zero_radius() -> void:
	# 客机快照的 radius 可能缺失，或被 net_protocol 清洗成 0。
	# 若按 0 算边界，目标会落到 58.0，host 侧把英雄拦在 57.45 → 差 0.55，永远到不了。
	var arena := _arena()
	var hero := _hero_at(Vector2(50.0, 0.0), {"radius": 0.0})
	_attach(arena, hero)
	arena._set_move_target(Vector2(9999.0, 0.0))
	check(
		arena._move_target.x <= MapData.BOUNDS - 0.65 + 0.0001,
		"radius 缺失时必须按最大英雄半径（0.65）收目标，否则客机会贴边原地踏步"
	)
	arena.free()

func test_absurd_radius_does_not_pull_target_towards_center() -> void:
	var arena := _arena()
	var hero := _hero_at(Vector2.ZERO, {"radius": 16.0})
	_attach(arena, hero)
	arena._set_move_target(Vector2(9999.0, 0.0))
	gt(
		arena._move_target.x,
		MapData.BOUNDS - 2.0,
		"异常大的 radius 不能把点击目标钳到地图中央（玩家会点不动远处）"
	)
	arena.free()

# ---------------------------------------------------------------- 精确到点

func test_click_move_lands_within_arrival_epsilon() -> void:
	var arena := _arena()
	var hero := _hero_at(Vector2.ZERO)
	_attach(arena, hero)
	arena._set_move_target(Vector2(5.0, 0.0))
	var reached := false
	for i in 240:
		var move: Vector2 = arena._click_move_vector()
		if not arena._move_target_valid:
			reached = true
			break
		_step(hero, move)
		_attach(arena, hero)
	check(reached, "5 米外点击应在一个合理时间内到达")
	var final_pos := Vector2(float(hero.x), float(hero.y))
	near(final_pos.distance_to(Vector2(5.0, 0.0)), 0.0, Arena.MOVE_ARRIVE_EPS, "落点误差必须在 eps 内")
	gt(final_pos.x, 4.5, "必须真的走到目标附近，不能半路就判定到达")
	arena.free()

func test_final_short_step_does_not_overshoot_target() -> void:
	# 距离小于「一个 tick 的步长」时必须返回缩短向量（模拟侧只归一化 >1 的向量），
	# 否则每帧都跨过目标点、在两侧来回抽搐。
	var arena := _arena()
	var speed := 12.0
	var remaining := 0.4
	var hero := _hero_at(Vector2.ZERO, {"speed": speed, "haste_timer": 1.0})
	_attach(arena, hero)
	arena._set_move_target(Vector2(remaining, 0.0))
	var move: Vector2 = arena._click_move_vector()
	var step_length := speed * 1.4 * DT
	lt(move.length(), 1.0, "一步能走完时向量必须缩短，不能被归一化")
	near(move.length() * step_length, remaining, 0.0001, "缩短向量的位移必须恰好等于剩余距离")
	arena.free()

func test_far_click_returns_unit_direction() -> void:
	var arena := _arena()
	var hero := _hero_at(Vector2.ZERO)
	_attach(arena, hero)
	arena._set_move_target(Vector2(0.0, 12.0))
	var move: Vector2 = arena._click_move_vector()
	near(move.length(), 1.0, 0.0001, "远距离时必须是单位向量")
	gt(move.y, 0.999, "方向必须指向目标（+y）")
	near(move.x, 0.0, 0.0001, "方向不能有横向漂移")
	arena.free()

func test_last_click_wins_over_previous_target() -> void:
	var arena := _arena()
	var hero := _hero_at(Vector2.ZERO)
	_attach(arena, hero)
	arena._set_move_target(Vector2(10.0, 0.0))
	arena._set_move_target(Vector2(0.0, -10.0))
	var move: Vector2 = arena._click_move_vector()
	near(move.x, 0.0, 0.0001, "前一次点击必须被整份覆盖，不是排队")
	lt(move.y, -0.999, "只朝最后一次点击的方向移动")
	arena.free()

# ---------------------------------------------------------------- 取消条件

func test_click_target_is_dropped_when_hero_dies() -> void:
	var arena := _arena()
	var hero := _hero_at(Vector2.ZERO, {"alive": false})
	_attach(arena, hero)
	arena._set_move_target(Vector2(5.0, 0.0))
	var move: Vector2 = arena._click_move_vector()
	eq(move, Vector2.ZERO, "死亡后不再产生移动向量")
	check(not arena._move_target_valid, "死亡后必须清掉点击目标，复活后才不会自动接着走")
	arena.free()

func test_click_target_is_dropped_when_snapshot_has_no_hero() -> void:
	var arena := _arena()
	arena.current_snapshot = {"entities": []}
	arena._set_move_target(Vector2(5.0, 0.0))
	eq(arena._click_move_vector(), Vector2.ZERO, "拿不到本地英雄时不能盲走")
	check(not arena._move_target_valid, "没有英雄数据时必须放弃目标")
	arena.free()

# ---------------------------------------------------------------- 朝向

func test_facing_follows_movement_while_click_walking() -> void:
	var sim := MatchSim.new({
		"mode": "duel",
		"humans": [{"id": "p1", "name": "p1", "team": "blue", "hero_type": "blade"}],
		"bot_fill": false,
		"bot_ai": false,
	})
	var hero: Dictionary = sim.get_hero_by_player("p1")
	hero.pos = Vector2.ZERO
	# 准星在正右方，但人往正上方走（点击移动经常是往身后走）
	sim.set_input("p1", {
		"move": Vector2(0.0, -1.0),
		"aim": Vector2(10.0, 0.0),
		"skill_q": false,
		"skill_e": false,
		"attack": false,
	})
	sim.tick(DT)
	lt(float(hero.facing.y), -0.9, "移动时应朝移动方向，否则点击身后会倒着走")
	near(float(hero.facing.x), 0.0, 0.1, "移动朝向不该被准星拉走")

func test_facing_follows_aim_when_standing_still() -> void:
	var sim := MatchSim.new({
		"mode": "duel",
		"humans": [{"id": "p1", "name": "p1", "team": "blue", "hero_type": "blade"}],
		"bot_fill": false,
		"bot_ai": false,
	})
	var hero: Dictionary = sim.get_hero_by_player("p1")
	hero.pos = Vector2.ZERO
	hero.facing = Vector2(0.0, -1.0)
	sim.set_input("p1", {
		"move": Vector2.ZERO,
		"aim": Vector2(10.0, 0.0),
		"skill_q": false,
		"skill_e": false,
		"attack": false,
	})
	sim.tick(DT)
	gt(float(hero.facing.x), 0.9, "站住时应朝准星，瞄准手感不能丢")

# ---------------------------------------------------------------- 步长一致性

func test_arena_tick_matches_sim_tick_rate() -> void:
	# _click_move_vector 用 Arena.TICK 估算一步走多远，sim 用 TICK_RATE。
	# 两边不一致会让「最后一步」算错，出现跨越或永远差半步。
	near(Arena.TICK, 1.0 / MatchSim.TICK_RATE, 0.000001, "输入层步长必须与模拟层一致")
