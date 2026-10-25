extends "res://tests/test_base.gd"

# 普攻特效契约：防御塔与小兵的每一次攻击都要在表现层留下可见痕迹。
#
# 背景：小兵攻击此前只改数值、不发事件，打起来看不出谁在出手；
# 防御塔虽然有 structure_attack，但只有一颗快速飞过的小球，远看像没开火。
#
# 表现配方必须是纯数据（Arena.attack_fx_plan），才能在 --headless 下断言
# 「近战 / 远程 / 炮车 / 塔」四种攻击不会长得一样——否则「加了特效」无法验证。

const Arena = preload("res://scripts/game/arena.gd")
const MatchSim = preload("res://sim/match_sim.gd")
const NetProtocol = preload("res://net/net_protocol.gd")
const UnitVisual = preload("res://scripts/game/unit_visual.gd")
const WaveRules = preload("res://sim/map/wave_rules.gd")

const MINION_TYPES := ["melee", "ranged", "cannon", "super"]

func _sim() -> Object:
	return MatchSim.new({
		"mode": "duel",
		"humans": [{"id": "p1", "team": "blue", "hero_type": "blade"}],
		"bot_fill": false,
		"bot_ai": false,
	})

func _minion(id: int, team: String, minion_type: String, pos: Vector2) -> Dictionary:
	var stats: Dictionary = WaveRules.stats(minion_type, 1)
	return {
		"id": id,
		"type": "minion",
		"team": team,
		"lane": "mid",
		"minion_type": minion_type,
		"pos": pos,
		"radius": float(stats.radius),
		"hp": float(stats.hp),
		"max_hp": float(stats.max_hp),
		"alive": true,
		"speed": 0.0,
		"attack_damage": 10.0,
		"attack_range": float(stats.attack_range),
		"attack_interval": 1.0,
		"attack_cd": 0.0,
		"path": [pos, pos],
		"path_index": 0,
		"path_dir": 1,
	}

func _attacks_by(events: Array, source_id: int) -> Array:
	return events.filter(func(event): return str(event.get("type", "")) == "minion_attack" and int(event.get("source", -1)) == source_id)

func test_every_minion_type_emits_a_renderable_attack_event() -> void:
	for minion_type in MINION_TYPES:
		var sim := _sim()
		# 每种兵都放在自己射程内，避免「远程兵够不着」把测试变成假绿。
		var stats: Dictionary = WaveRules.stats(str(minion_type), 1)
		var gap := minf(float(stats.attack_range) * 0.6, 4.0)
		sim.state.entities.append(_minion(9001, "blue", str(minion_type), Vector2.ZERO))
		sim.state.entities.append(_minion(9002, "red", "melee", Vector2(gap, 0.0)))
		sim.consume_events()
		sim.tick(0.05)
		var attacks := _attacks_by(sim.consume_events(), 9001)
		eq(attacks.size(), 1, "%s 小兵进入射程后必须发出一条攻击事件" % str(minion_type))
		if attacks.is_empty():
			continue
		var event: Dictionary = attacks[0]
		eq(str(event.get("minion_type", "")), str(minion_type), "事件要带兵种，近战/远程特效不同")
		eq(int(event.get("target", -1)), 9002, "事件要带被打的目标")
		near(float(event.get("target_x", 0.0)), gap, 0.001, "事件要带目标坐标")
		check(event.has("x") and event.has("y"), "事件要带起点坐标")

func test_structure_attack_carries_tier_and_source_type() -> void:
	var sim := _sim()
	var tower: Dictionary = {}
	for entity in sim.state.entities:
		if str(entity.get("type", "")) == "tower" and str(entity.get("team", "")) == "red":
			tower = entity
			break
	check(not tower.is_empty(), "对局里必须有红方防御塔")
	if tower.is_empty():
		return
	var hero: Dictionary = sim.get_hero_by_player("p1")
	hero["pos"] = (tower["pos"] as Vector2) + Vector2(2.0, 0.0)
	hero["hp"] = 99999.0
	tower["attack_cd"] = 0.0
	sim.consume_events()
	sim.tick(0.05)
	var shots: Array = sim.consume_events().filter(func(event): return str(event.get("type", "")) == "structure_attack")
	eq(shots.size(), 1, "英雄进入射程后防御塔必须开火")
	if shots.is_empty():
		return
	eq(str(shots[0].get("source_type", "")), "tower", "事件要带建筑类型：主堡枪口比塔低")
	eq(str(shots[0].get("tier", "")), str(tower.get("tier", "")), "事件要带塔的层级：高地塔枪口更高")

func test_attack_plans_are_visually_distinct() -> void:
	var melee: Dictionary = Arena.attack_fx_plan({"type": "minion_attack", "minion_type": "melee"})
	var ranged: Dictionary = Arena.attack_fx_plan({"type": "minion_attack", "minion_type": "ranged"})
	var cannon: Dictionary = Arena.attack_fx_plan({"type": "minion_attack", "minion_type": "cannon"})
	var super_minion: Dictionary = Arena.attack_fx_plan({"type": "minion_attack", "minion_type": "super"})
	var outer: Dictionary = Arena.attack_fx_plan({"type": "structure_attack", "source_type": "tower", "tier": "outer"})
	var high: Dictionary = Arena.attack_fx_plan({"type": "structure_attack", "source_type": "tower", "tier": "high"})
	var base: Dictionary = Arena.attack_fx_plan({"type": "structure_attack", "source_type": "base"})

	eq(str(melee.get("mode", "")), "melee", "近战兵是短促刀光")
	eq(str(super_minion.get("mode", "")), "melee", "超级兵也是近战")
	eq(str(ranged.get("mode", "")), "projectile", "远程兵要打飞行弹丸")
	eq(str(cannon.get("mode", "")), "projectile", "炮车要打飞行弹丸")
	eq(str(outer.get("mode", "")), "lance", "防御塔是持续一小段的光束，不是小圆点")
	gt(float(cannon.get("radius", 0.0)), float(ranged.get("radius", 0.0)), "炮车弹丸要比普通远程兵大")
	gt(float(outer.get("radius", 0.0)), float(ranged.get("radius", 0.0)), "塔的光束要比小兵弹丸粗")
	lt(float(melee.get("duration", 1.0)), float(ranged.get("duration", 0.0)), "刀光必须比弹丸更快")
	near(float(outer.get("from_height", 0.0)), Arena.TOWER_CRYSTAL_HEIGHT, 0.001, "外塔的水晶枪口在模型顶部")
	gt(float(high.get("from_height", 0.0)), float(outer.get("from_height", 0.0)), "高地塔更高，枪口也要更高")
	lt(float(base.get("from_height", 0.0)), float(outer.get("from_height", 0.0)), "主堡水晶比防御塔低")
	gt(float(outer.get("to_height", 0.0)), 0.9, "塔从高处往下打，命中点要在单位胸口以上")

func test_lance_geometry_connects_gun_muzzle_and_target() -> void:
	var from := Vector3(0.0, 7.0, 0.0)
	var to := Vector3(4.0, 1.1, 0.0)
	var xf: Transform3D = Arena.lance_transform(from, to, 0.2)
	# 圆柱的本地端点 (0, ±0.5, 0) 变换后必须正好落在枪口与目标上；
	# 以前用 Basis.scaled（世界轴缩放）会让光束竖直穿过枪口，这里钉住。
	near((xf * Vector3(0.0, -0.5, 0.0)).distance_to(from), 0.0, 0.01, "光束起点必须贴着枪口")
	near((xf * Vector3(0.0, 0.5, 0.0)).distance_to(to), 0.0, 0.01, "光束终点必须落在目标身上")

func test_net_snapshot_keeps_attack_event_fields() -> void:
	var result: Dictionary = NetProtocol.sanitize_snapshot({
		"time": 1.0,
		"mode": "duel",
		"bounds": 58.0,
		"entities": [],
		"events": [
			{
				"type": "minion_attack",
				"source": 7,
				"team": "blue",
				"minion_type": "ranged",
				"target": 8,
				"target_type": "hero",
				"x": 1.0,
				"y": 2.0,
				"target_x": 3.0,
				"target_y": 4.0,
			},
			{
				"type": "structure_attack",
				"source": 9,
				"team": "red",
				"source_type": "tower",
				"tier": "high",
				"x": 5.0,
				"y": 6.0,
				"target_x": 7.0,
				"target_y": 8.0,
			},
		],
	})
	check(bool(result.get("ok", false)), "快照要被接受")
	var events: Array = result.get("snapshot", {}).get("events", [])
	eq(events.size(), 2, "两条攻击事件都要保留")
	if events.size() < 2:
		return
	var minion_event: Dictionary = events[0]
	eq(int(minion_event.get("source", -1)), 7, "客机也要知道是谁在打")
	eq(str(minion_event.get("minion_type", "")), "ranged", "客机要靠兵种选弹丸/刀光")
	eq(str(minion_event.get("target_type", "")), "hero", "客机要靠目标类型选命中高度")
	var tower_event: Dictionary = events[1]
	eq(str(tower_event.get("source_type", "")), "tower", "客机要靠建筑类型选枪口高度")
	eq(str(tower_event.get("tier", "")), "high", "客机要靠层级还原枪口高度")

func test_minion_attack_animations_exist_on_both_skeleton_models() -> void:
	var models: Array = [
		load("res://assets/characters/Skeleton_Warrior.glb").instantiate(),
		load("res://assets/characters/Skeleton_Rogue.glb").instantiate(),
	]
	for model in models:
		var names := {}
		for node in (model as Node).find_children("*", "AnimationPlayer", true, false):
			var player := node as AnimationPlayer
			for lib_name in player.get_animation_library_list():
				var library := player.get_animation_library(lib_name)
				for anim_name in library.get_animation_list():
					names[anim_name] = true
		for minion_type in MINION_TYPES:
			var anim: String = UnitVisual.minion_attack_anim(str(minion_type))
			check(anim != "", "%s 小兵必须有攻击动作名" % str(minion_type))
			check(names.has(anim), "%s 小兵的攻击动作 %s 必须存在于模型里" % [str(minion_type), anim])
		(model as Node).free()
