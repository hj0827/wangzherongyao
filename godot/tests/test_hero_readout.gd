extends "res://tests/test_base.gd"

# 英雄头顶读数 + 地面射程指示器 + 泉水恢复的回归守卫。
#
# 对应三条需求：
#   1. 能看到普攻范围与技能范围（地面圆环，以英雄为圆心）
#   2. 血条按「与本地玩家的关系」着色：自己绿、友军蓝、敌军红；蓝条一律蓝色。
#   3. 站在己方泉水里回血要明显快于野外脱战回血。

const UnitVisual = preload("res://scripts/game/unit_visual.gd")
const HeroDefs = preload("res://sim/hero_defs.gd")
const MatchSim = preload("res://sim/match_sim.gd")
const MapData = preload("res://sim/map_data.gd")
const Arena = preload("res://scripts/game/arena.gd")

func _is_red(c: Color) -> bool:
	return c.r > 0.6 and c.g < 0.45 and c.b < 0.45

func _is_blue(c: Color) -> bool:
	# b - g 这道门槛是防「蓝被渲染成青」的：
	# 场景用 FILMIC + exposure 1.05，蓝血条如果 G 太高，渲染后 G 和 B 一起顶到 1.0，
	# 屏幕上就是青白色。旧的 (0.34,0.74,1.0) 满足 b>0.7 和 r<0.45，肉眼却是青的，
	# 所以必须再要求 B 和 G 拉开距离。MANA 和 HP_ALLY 都要过这一关。
	return c.b > 0.7 and c.r < 0.45 and (c.b - c.g) > 0.40

func _is_green(c: Color) -> bool:
	return c.g > 0.6 and c.r < 0.6 and c.b < 0.6 and (c.g - c.b) > 0.25

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

# --- 血条配色：自己绿 / 友军蓝 / 敌军红 ---

func _hp_color(view) -> Color:
	return view.bar_material.get_shader_parameter("fill_color")

func test_own_hero_bar_is_green() -> void:
	# 本地玩家在哪一方，自己头顶的血条都必须是绿色。
	for team in ["blue", "red"]:
		var view = UnitVisual.new()
		view.setup("hero", team, "blade", "测试", true, team)
		check(view.bar_material != null, "%s local hero must have a health bar" % team)
		if view.bar_material:
			var hp := _hp_color(view)
			check(_is_green(hp), "%s local hero health bar must be green, got %s" % [team, str(hp)])
			check(not _is_blue(hp), "%s local hero bar must not read as an ally bar" % team)
			check(not _is_red(hp), "%s local hero bar must not read as an enemy bar" % team)
		view.free()

func test_hero_bars_follow_the_viewer_side() -> void:
	# 关键：颜色取决于「相对本地玩家」而不是绝对阵营。
	# 本地在蓝方时蓝方英雄是友军（蓝），本地切到红方后同一支蓝方英雄必须变红。
	# 只按 team == "blue" 取色的实现在后两条用例上会露馅。
	var cases := [
		["blue", "blue", true],
		["red", "blue", false],
		["red", "red", true],
		["blue", "red", false],
	]
	for c in cases:
		var team: String = c[0]
		var viewer: String = c[1]
		var is_ally: bool = c[2]
		var view = UnitVisual.new()
		view.setup("hero", team, "blade", "测试", false, viewer)
		var hp := _hp_color(view)
		if is_ally:
			check(_is_blue(hp), "%s hero seen from %s side must be blue, got %s" % [team, viewer, str(hp)])
			check(not _is_red(hp), "%s ally hero must not be red, got %s" % [team, str(hp)])
			# 友军英雄头顶同时有蓝条，血条要比蓝条更亮才分得清
			var mp: Color = view.mp_material.get_shader_parameter("fill_color")
			check(not hp.is_equal_approx(mp), "%s ally hero HP bar must differ from its mana bar" % team)
			check(hp.g > mp.g, "%s ally hero HP bar must be brighter than its mana bar" % team)
		else:
			check(_is_red(hp), "%s hero seen from %s side must be red, got %s" % [team, viewer, str(hp)])
			check(not _is_blue(hp), "%s enemy hero must not be blue, got %s" % [team, str(hp)])
		view.free()

func test_hero_bars_are_large_enough_to_read_on_a_phone() -> void:
	# 默认镜头下英雄只占屏高 ~7%，血条太细时手机竖屏读不出剩余血量。
	var view = UnitVisual.new()
	view.setup("hero", "blue", "blade", "测试", false, "blue")
	var hp: QuadMesh = view.bar_mesh.mesh
	check(hp.size.x >= 1.4, "hero health bar must be wider than 1.4 m (got %.2f)" % hp.size.x)
	check(hp.size.y >= 0.18, "hero health bar must be thick enough to read (got %.2f)" % hp.size.y)
	var mp: QuadMesh = view.mp_mesh.mesh
	check(mp.size.y < hp.size.y, "mana bar must stay thinner than the health bar")
	check(
		view.mp_mesh.position.y + mp.size.y * 0.5 <= -hp.size.y * 0.5,
		"mana bar must not overlap the thicker health bar"
	)
	view.free()

func test_hero_mana_bar_stays_blue_below_health() -> void:
	for team in ["blue", "red"]:
		var view = UnitVisual.new()
		view.setup("hero", team, "blade", "测试", false, team)
		check(view.mp_material != null, "%s hero must have a mana bar" % team)
		if view.mp_material:
			var mp: Color = view.mp_material.get_shader_parameter("fill_color")
			check(_is_blue(mp), "%s hero mana bar must be blue, got %s" % [team, str(mp)])
		if view.mp_mesh:
			lt(view.mp_mesh.position.y, 0.0, "%s hero mana bar must sit below the health bar" % team)
		view.free()

func test_minion_bar_follows_relation_not_absolute_team() -> void:
	# 小兵没有蓝条，但血条同样按「与本地玩家的关系」着色。
	var ally = UnitVisual.new()
	ally.setup("minion", "red", "minion", "", false, "red")
	check(_is_blue(_hp_color(ally)), "allied minion must have a blue bar, got %s" % str(_hp_color(ally)))
	ally.free()

	var enemy = UnitVisual.new()
	enemy.setup("minion", "blue", "minion", "", false, "red")
	check(_is_red(_hp_color(enemy)), "enemy minion must have a red bar, got %s" % str(_hp_color(enemy)))
	enemy.free()

	var monster = UnitVisual.new()
	monster.setup("monster", "neutral", "wolf", "霜狼", false, "blue")
	check(_is_red(_hp_color(monster)), "neutral monster must read as an enemy (red), got %s" % str(_hp_color(monster)))
	monster.free()

func test_arena_passes_viewer_side_into_unit_visuals() -> void:
	# 配色逻辑再对，arena 不把 local_team 传进去也白搭（单元测试全绿但线上全是红）。
	# 这里用源码守卫钉住接线，防止后续重构悄悄把第 6 个参数丢掉。
	var src := FileAccess.get_file_as_string("res://scripts/game/arena.gd")
	check(src.contains(", is_local, local_team)"), "arena must pass local_team for hero views")
	check(src.contains("\"\", false, local_team)"), "arena must pass local_team for minion views")
	check(src.contains("\"野怪\")), false, local_team)"), "arena must pass local_team for monster views")

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
