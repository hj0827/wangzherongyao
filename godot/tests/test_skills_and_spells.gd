extends "res://tests/test_base.gd"

const HeroDefs = preload("res://sim/hero_defs.gd")
const SkillSystem = preload("res://sim/skill_system.gd")
const MatchSim = preload("res://sim/match_sim.gd")
const Collision = preload("res://sim/map/collision.gd")
const MapLayout = preload("res://sim/map/map_layout.gd")
const MapData = preload("res://sim/map_data.gd")

func _create_sim() -> MatchSim:
	return MatchSim.new({
		"mode": "duel",
		"humans": [
			{"id": "p1", "team": "blue", "hero_type": "blade"},
			{"id": "p2", "team": "red", "hero_type": "tank"},
		],
		"bot_fill": false,
	})

func test_hero_defs_has_full_four_skills_and_passive() -> void:
	for hero_type in ["blade", "mage", "tank", "archer"]:
		var def: Dictionary = HeroDefs.get_hero(hero_type)
		check(def.has("passive"), "%s must have passive" % hero_type)
		check(def.has("q"), "%s must have skill Q" % hero_type)
		check(def.has("w"), "%s must have skill W" % hero_type)
		check(def.has("e"), "%s must have skill E" % hero_type)
		check(def.has("r"), "%s must have ultimate R" % hero_type)
		
		var passive: Dictionary = def.get("passive", {})
		check(passive.has("name") and passive.has("desc"), "%s passive must have name and desc" % hero_type)
		
		var w: Dictionary = def.get("w", {})
		check(float(w.get("cooldown", 0.0)) > 0.0, "%s skill W must have cooldown" % hero_type)
		check(float(w.get("cost", 0.0)) > 0.0, "%s skill W must have mana cost" % hero_type)
		
		var r: Dictionary = def.get("r", {})
		check(float(r.get("cooldown", 0.0)) > 10.0, "%s ultimate R must have long cooldown" % hero_type)
		check(float(r.get("cost", 0.0)) > 0.0, "%s ultimate R must have mana cost" % hero_type)

func test_summoner_spells_registered() -> void:
	var spells: Array = SkillSystem.get_available_summoner_spells()
	check(spells.has("flash"), "must include flash")
	check(spells.has("execute"), "must include execute")
	check(spells.has("cleanse"), "must include cleanse")
	check(spells.has("heal"), "must include heal")
	
	var flash: Dictionary = SkillSystem.get_summoner_spell("flash")
	eq(flash.get("name"), "闪现", "flash name")
	check(float(flash.get("range", 0.0)) > 3.0, "flash range")
	check(float(flash.get("cooldown", 0.0)) >= 60.0, "flash cooldown")

func test_cast_skill_w_and_r_spends_mana_and_starts_cooldown() -> void:
	var sim := _create_sim()
	var blue: Dictionary = sim.get_hero_by_player("p1")
	var red: Dictionary = sim.get_hero_by_player("p2")
	check(not blue.is_empty(), "blue hero must exist")
	check(not red.is_empty(), "red hero must exist")
	var bpos: Vector2 = blue.get("pos", Vector2.ZERO)
	red["pos"] = bpos + Vector2(2.0, 0.0)
	
	var mp_before: float = float(blue.get("mp", 0.0))
	var target_pos: Vector2 = red.get("pos", Vector2.ZERO)
	var ok_w: bool = SkillSystem.cast_skill(blue, "w", target_pos, sim)
	check(ok_w, "cast w should succeed")
	gt(float(blue.get("skill_w_cd", 0.0)), 0.0, "skill w enters cooldown")
	lt(float(blue.get("mp", 0.0)), mp_before, "mana spent on w")
	
	var mp_after_w: float = float(blue.get("mp", 0.0))
	var ok_r: bool = SkillSystem.cast_skill(blue, "r", target_pos, sim)
	check(ok_r, "cast r should succeed")
	gt(float(blue.get("skill_r_cd", 0.0)), 0.0, "skill r enters cooldown")
	lt(float(blue.get("mp", 0.0)), mp_after_w, "mana spent on r")

func test_summoner_flash_teleports_unit() -> void:
	var sim := _create_sim()
	var blue: Dictionary = sim.get_hero_by_player("p1")
	var start_pos: Vector2 = blue.get("pos", Vector2.ZERO)
	# 朝地图中心闪：出生点离边界墙只有几米，朝外闪会被可走边界截短。
	var target_pos: Vector2 = start_pos + (-start_pos).normalized() * 4.0
	
	var ok: bool = SkillSystem.cast_summoner_spell(blue, "flash", target_pos, sim)
	check(ok, "flash cast should succeed")
	gt(float(blue.get("summoner_cd", 0.0)), 0.0, "summoner spell enters cooldown")
	var end_pos: Vector2 = blue.get("pos", Vector2.ZERO)
	near(end_pos.distance_to(start_pos), 4.0, 0.1, "unit teleported by flash")

func test_summoner_flash_casts_through_a_wall() -> void:
	# 闪现是「瞬移」不是「冲刺」：野区墙不该截停它。
	# 找一段两侧都站得下人、且中间确实被墙挡住视线的墙，朝另一侧闪。
	var sim := _create_sim()
	var blue: Dictionary = sim.get_hero_by_player("p1")
	var radius := float(blue.get("radius", 0.55))
	var range_val: float = float(SkillSystem.get_summoner_spell("flash").get("range", 4.8))
	var setup: Array = _pick_wall_for_flash(radius, range_val)
	if setup.is_empty():
		check(false, "必须有一段能用来验证穿墙的墙")
		return
	var start: Vector2 = setup[0]
	var goal: Vector2 = setup[1]
	var normal: Vector2 = setup[2]
	var mid: Vector2 = setup[3]
	blue["pos"] = start
	blue["summoner_cd"] = 0.0

	var ok: bool = SkillSystem.cast_summoner_spell(blue, "flash", goal, sim)
	check(ok, "flash cast should succeed")
	var end_pos: Vector2 = blue.get("pos", Vector2.ZERO)
	check(not Collision.is_blocked(end_pos, radius), "落点不能卡在墙里")
	# 关键断言：相对墙心线的法线符号必须翻过去 —— 这正是 Collision.move 做不到的事。
	gt((end_pos - mid).dot(normal), 0.0, "闪现必须落到墙的另一侧（当前停在起始侧）")
	gt(end_pos.distance_to(start), range_val * 0.6, "穿墙闪现不该被墙吃掉大半位移")

func _pick_wall_for_flash(radius: float, range_val: float) -> Array:
	# 起点/落点各离墙心 2.2 米（阻挡带半宽 = 墙厚/2 + 半径 ≈ 1.35），
	# 两点连线必须真的被墙横穿，否则这个用例就没有在测「穿墙」。
	for wall in MapLayout.WALLS:
		var mid: Vector2 = (wall.a + wall.b) * 0.5
		var segment: Vector2 = wall.b - wall.a
		var normal := Vector2(-segment.y, segment.x).normalized()
		var start: Vector2 = mid - normal * 2.2
		var goal: Vector2 = mid + normal * 2.2
		if Collision.is_blocked(start, radius) or Collision.is_blocked(goal, radius):
			continue
		if not Collision.segment_blocked(start, goal):
			continue
		if start.distance_to(goal) > range_val:
			continue
		if maxf(absf(start.x), absf(start.y)) > MapData.BOUNDS - 8.0:
			continue
		if maxf(absf(goal.x), absf(goal.y)) > MapData.BOUNDS - 8.0:
			continue
		return [start, goal, normal, mid]
	return []

func test_summoner_execute_deals_missing_health_true_damage() -> void:
	var sim := _create_sim()
	var blue: Dictionary = sim.get_hero_by_player("p1")
	var red: Dictionary = sim.get_hero_by_player("p2")
	var bpos: Vector2 = blue.get("pos", Vector2.ZERO)
	red["pos"] = bpos + Vector2(2.0, 0.0)
	red["hp"] = 300.0
	var hp_before: float = float(red.get("hp", 0.0))
	
	var rpos: Vector2 = red.get("pos", Vector2.ZERO)
	var ok: bool = SkillSystem.cast_summoner_spell(blue, "execute", rpos, sim)
	check(ok, "execute should succeed when enemy nearby")
	lt(float(red.get("hp", 0.0)), hp_before, "execute deals missing health damage")

func test_summoner_cleanse_removes_slow_and_grants_immunity() -> void:
	var sim := _create_sim()
	var blue: Dictionary = sim.get_hero_by_player("p1")
	blue["slow_timer"] = 3.0
	
	var bpos: Vector2 = blue.get("pos", Vector2.ZERO)
	var ok: bool = SkillSystem.cast_summoner_spell(blue, "cleanse", bpos, sim)
	check(ok, "cleanse should succeed")
	eq(float(blue.get("slow_timer", 0.0)), 0.0, "slow debuff cleared")
	gt(float(blue.get("cc_immune_timer", 0.0)), 0.0, "cc immunity granted")

func test_summoner_heal_restores_health_and_buffs_speed() -> void:
	var sim := _create_sim()
	var blue: Dictionary = sim.get_hero_by_player("p1")
	blue["hp"] = 200.0
	
	var bpos: Vector2 = blue.get("pos", Vector2.ZERO)
	var ok: bool = SkillSystem.cast_summoner_spell(blue, "heal", bpos, sim)
	check(ok, "heal should succeed")
	gt(float(blue.get("hp", 0.0)), 200.0, "hp restored")
	gt(float(blue.get("haste_timer", 0.0)), 0.0, "speed boost granted")

func test_passive_mechanic_applies() -> void:
	var sim := _create_sim()
	var blue: Dictionary = sim.get_hero_by_player("p1")
	var red: Dictionary = sim.get_hero_by_player("p2")
	var bpos: Vector2 = blue.get("pos", Vector2.ZERO)
	red["pos"] = bpos + Vector2(1.0, 0.0)
	
	SkillSystem.on_hero_attack_hit(blue, red, sim)
	check(int(blue.get("passive_stacks", 0)) > 0, "blade gains combo stacks on hit")
