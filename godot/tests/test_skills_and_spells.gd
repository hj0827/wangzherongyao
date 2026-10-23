extends "res://tests/test_base.gd"

const HeroDefs = preload("res://sim/hero_defs.gd")
const SkillSystem = preload("res://sim/skill_system.gd")
const MatchSim = preload("res://sim/match_sim.gd")

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
	var target_pos: Vector2 = start_pos + Vector2(4.0, 0.0)
	
	var ok: bool = SkillSystem.cast_summoner_spell(blue, "flash", target_pos, sim)
	check(ok, "flash cast should succeed")
	gt(float(blue.get("summoner_cd", 0.0)), 0.0, "summoner spell enters cooldown")
	var end_pos: Vector2 = blue.get("pos", Vector2.ZERO)
	near(end_pos.x, start_pos.x + 4.0, 0.1, "unit teleported by flash")

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
