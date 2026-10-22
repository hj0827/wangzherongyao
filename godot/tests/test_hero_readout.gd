extends "res://tests/test_base.gd"

# 英雄头顶读数 + 地面射程指示器 + 泉水恢复的回归守卫。
#
# 对应三条需求：
#   1. 能看到普攻范围与技能范围（地面圆环，以英雄为圆心）
#   2. 英雄血条一律红色、蓝条一律蓝色。原先血条按阵营着色，
#      蓝方英雄的血条是蓝的，和蓝条撞色，根本分不清哪条是血。
#   3. 站在己方泉水里回血要明显快于野外脱战回血。

const UnitVisual = preload("res://scripts/game/unit_visual.gd")
const HeroDefs = preload("res://sim/hero_defs.gd")
const MatchSim = preload("res://sim/match_sim.gd")
const MapData = preload("res://sim/map_data.gd")
const Arena = preload("res://scripts/game/arena.gd")

func _is_red(c: Color) -> bool:
	return c.r > 0.6 and c.g < 0.45 and c.b < 0.45

func _is_blue(c: Color) -> bool:
	return c.b > 0.7 and c.r < 0.45

func _sim() -> Object:
	return MatchSim.new({
		"mode": "duel",
		"humans": [{"id": "p1", "name": "测试", "team": "blue", "hero_type": "blade"}],
		"bot_fill": false,
	})

func _tick_for(sim: Object, seconds: float) -> void:
	var steps := int(round(seconds * 30.0))
	for i in steps:
		sim.tick(1.0 / 30.0)

# --- 血条 / 蓝条 ---

func test_hero_bars_are_red_hp_and_blue_mana() -> void:
	for team in ["blue", "red"]:
		var view = UnitVisual.new()
		view.setup("hero", team, "blade", "测试", false)
		check(view.bar_material != null, "%s hero must have a health bar" % team)
		check(view.mp_material != null, "%s hero must have a mana bar" % team)
		if view.bar_material:
			var hp: Color = view.bar_material.get_shader_parameter("fill_color")
			check(_is_red(hp), "%s hero health bar must be red, got %s" % [team, str(hp)])
		if view.mp_material:
			var mp: Color = view.mp_material.get_shader_parameter("fill_color")
			check(_is_blue(mp), "%s hero mana bar must be blue, got %s" % [team, str(mp)])
		if view.mp_mesh:
			lt(view.mp_mesh.position.y, 0.0, "%s hero mana bar must sit below the health bar" % team)
		view.free()

func test_minion_bar_keeps_team_color() -> void:
	# 小兵没有蓝条，血条继续按阵营着色，别被英雄的改动带跑。
	var blue = UnitVisual.new()
	blue.setup("minion", "blue", "minion", "", false)
	var blue_color: Color = blue.bar_material.get_shader_parameter("fill_color")
	check(_is_blue(blue_color), "blue minion keeps a blue bar, got %s" % str(blue_color))
	blue.free()

	var red = UnitVisual.new()
	red.setup("minion", "red", "minion", "", false)
	var red_color: Color = red.bar_material.get_shader_parameter("fill_color")
	check(_is_red(red_color), "red minion keeps a red bar, got %s" % str(red_color))
	red.free()

# --- 射程数据 ---

func test_attack_range_comes_from_hero_data() -> void:
	near(HeroDefs.attack_range("blade"), 2.0, 0.001, "blade attack range")
	near(HeroDefs.attack_range("tank"), 2.1, 0.001, "tank attack range")
	near(HeroDefs.attack_range("archer"), 6.4, 0.001, "archer attack range")

func test_skill_range_comes_from_skill_data() -> void:
	near(HeroDefs.skill_range("blade", "q"), 5.5, 0.001, "blade q range")
	near(HeroDefs.skill_range("archer", "q"), 9.0, 0.001, "archer q range")
	near(HeroDefs.skill_range("mage", "e"), 6.5, 0.001, "mage e range")
	near(HeroDefs.skill_range("tank", "e"), 0.0, 0.001, "self-buff has no range")
	near(HeroDefs.skill_range("archer", "e"), 0.0, 0.001, "haste buff has no range")

# --- 地面圆环几何 ---

func test_ground_ring_geometry_matches_radius() -> void:
	var arena = Arena.new()
	if not arena.has_method("_make_ground_ring"):
		check(false, "arena must build ground rings for range indicators")
		arena.free()
		return
	var ring = arena._make_ground_ring(5.5, Color(1.0, 0.8, 0.3), 0.4, 0.12)
	check(ring is MeshInstance3D, "range ring must be a MeshInstance3D")
	if ring is MeshInstance3D:
		var torus: TorusMesh = ring.mesh
		var mid := (torus.inner_radius + torus.outer_radius) * 0.5
		near(mid, 5.5, 0.01, "ring radius must match the requested range")
		near(torus.outer_radius - torus.inner_radius, 0.12, 0.02, "ring line width")
		check(ring.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "ring must not cast shadow")
		ring.free()
	arena.free()

func test_skill_range_is_skipped_for_self_buffs() -> void:
	# 护盾/加速这类自身技能没有射程，不该画出 0 半径的环。
	var arena = Arena.new()
	if not arena.has_method("_make_skill_range_ring"):
		check(false, "arena must expose _make_skill_range_ring")
		arena.free()
		return
	check(arena._make_skill_range_ring("tank", "e", Vector3.ZERO) == null, "self-buff must not draw a range ring")
	var ring = arena._make_skill_range_ring("blade", "q", Vector3.ZERO)
	check(ring != null, "blade q must draw a range ring")
	if ring != null:
		var torus: TorusMesh = ring.mesh
		near((torus.inner_radius + torus.outer_radius) * 0.5, 5.5, 0.01, "skill ring radius follows skill data")
		ring.free()
	arena.free()

# --- 泉水恢复 ---

func test_fountain_restores_fast() -> void:
	var sim = _sim()
	var hero: Dictionary = sim.get_hero_by_player("p1")
	hero.hp = 100.0
	hero.mp = 0.0
	hero.pos = MapData.BLUE_BASE
	hero.last_damage_time = -999.0
	_tick_for(sim, 1.0)
	gt(float(hero.hp) - 100.0, float(hero.max_hp) * 0.15, "fountain must restore >= 15% max hp per second")
	gt(float(hero.mp), float(hero.max_mp) * 0.12, "fountain must also refill mana fast")

func test_fountain_beats_field_regen() -> void:
	var fountain_sim = _sim()
	var f: Dictionary = fountain_sim.get_hero_by_player("p1")
	f.hp = 100.0
	f.pos = MapData.BLUE_BASE
	f.last_damage_time = -999.0
	_tick_for(fountain_sim, 1.0)
	var fountain_gain := float(f.hp) - 100.0

	var field_sim = _sim()
	var g: Dictionary = field_sim.get_hero_by_player("p1")
	g.hp = 100.0
	g.pos = Vector2(-20.0, -20.0)
	g.last_damage_time = -999.0
	_tick_for(field_sim, 1.0)
	var field_gain := float(g.hp) - 100.0

	gt(field_gain, 0.0, "field regen must still work")
	gt(fountain_gain, field_gain * 3.0, "fountain must be much faster than field regen (got %.1f vs %.1f)" % [fountain_gain, field_gain])

func test_fountain_does_not_overheal() -> void:
	var sim = _sim()
	var hero: Dictionary = sim.get_hero_by_player("p1")
	hero.hp = float(hero.max_hp) - 1.0
	hero.mp = float(hero.max_mp) - 1.0
	hero.pos = MapData.BLUE_BASE
	hero.last_damage_time = -999.0
	_tick_for(sim, 2.0)
	near(float(hero.hp), float(hero.max_hp), 0.001, "fountain must clamp at max hp")
	near(float(hero.mp), float(hero.max_mp), 0.001, "fountain must clamp at max mana")
