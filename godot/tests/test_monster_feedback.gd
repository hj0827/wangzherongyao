extends "res://tests/test_base.gd"

# 野怪/小兵受击与出手反馈（P0 视觉升级）。
#
# 契约：
# 1. hit 事件必须带 source / source_type，表现层才能找到出手者；
# 2. 受击要闪白 + 缩身，0.2s 内回到静止姿态；
# 3. 出手要前倾，0.2s 内回到静止姿态；
# 4. arena._handle_hit_event 真的把这两条反馈接到视图上（不是只在 UnitVisual 里写完）。

const MatchSim = preload("res://sim/match_sim.gd")
const UnitVisual = preload("res://scripts/game/unit_visual.gd")
const Arena = preload("res://scripts/game/arena.gd")
const ModelUtils = preload("res://scripts/game/model_utils.gd")

func _first_monster(sim) -> Dictionary:
	for entity in sim.snapshot().get("entities", []):
		if str(entity.get("type", "")) == "monster":
			return entity
	return {}

func test_hit_event_carries_source_id_and_type() -> void:
	var sim := MatchSim.new({"mode": "duel", "humans": [{"id": "p1", "team": "blue"}], "bot_fill": false})
	var hero: Dictionary = sim.get_hero_by_player("p1")
	var monster := _first_monster(sim)
	check(not monster.is_empty(), "duel 里必须有野怪")
	if monster.is_empty():
		return
	sim.consume_events()
	sim.apply_damage(int(monster.id), 10.0, int(hero.id))
	var hit := {}
	for event in sim.consume_events():
		if str(event.get("type", "")) == "hit":
			hit = event
			break
	check(not hit.is_empty(), "apply_damage 必须发 hit 事件")
	eq(int(hit.get("source", -1)), int(hero.id), "hit 事件带出手者 id")
	eq(str(hit.get("source_type", "")), "hero", "hit 事件带出手者类型")

func test_monster_hit_flashes_squashes_and_restores() -> void:
	var view := UnitVisual.new()
	view.setup("monster", "neutral", "boar", "三猪", false, "blue")
	# 先让出生缩放入场跑完，否则受击缩身会和 spawn scale 叠在一起。
	for i in 8:
		view.process_visual(0.05)
	var rest_scale := view._model_rest_scale
	view.play_hit()
	check(view.flash_mesh != null and view.flash_mesh.visible, "受击要闪白")
	gt(view._hit_squash_timer, 0.0, "受击要进入缩身计时")
	view.process_visual(0.04)
	lt(view.model_root.scale.y, rest_scale.y, "缩身时纵向压扁")
	view.process_visual(0.20)
	check(not view.flash_mesh.visible, "闪白结束要隐藏")
	near(view.model_root.scale.y, rest_scale.y, 0.001, "缩身结束要回到静止比例")
	near(view.model_root.position.z, view._model_rest_position.z, 0.001, "缩身结束要回到静止位置")
	view.free()

func test_monster_attack_lunges_forward_and_returns() -> void:
	var view := UnitVisual.new()
	view.setup("monster", "neutral", "lizard", "蜥蜴", false, "blue")
	var rest_z := view._model_rest_position.z
	view.play_attack_reaction()
	gt(view._attack_lunge_timer, 0.0, "出手要进入前倾计时")
	view.process_visual(0.06)
	gt(view.model_root.position.z, rest_z + 0.001, "出手时模型要向前探")
	view.process_visual(0.20)
	near(view.model_root.position.z, rest_z, 0.001, "出手结束要回到静止位置")
	view.free()

func test_arena_routes_hit_to_victim_and_attacker() -> void:
	var arena: Node3D = Arena.new()
	var victim := UnitVisual.new()
	victim.setup("monster", "neutral", "boar", "三猪", false, "blue")
	var attacker := UnitVisual.new()
	attacker.setup("monster", "neutral", "boar", "三猪", false, "blue")
	arena._views[11] = victim
	arena._views[22] = attacker
	arena._handle_hit_event({
		"target": 11, "target_type": "monster",
		"source": 22, "source_type": "monster",
		"x": 0.0, "y": 0.0, "amount": 25.0, "team": "neutral",
	})
	gt(victim._hit_flash_timer, 0.0, "受害者要闪白")
	gt(attacker._attack_lunge_timer, 0.0, "出手者要前倾")
	arena._views.clear()
	victim.free()
	attacker.free()
	arena.free()

func test_minion_feedback_uses_the_same_reaction() -> void:
	var view := UnitVisual.new()
	view.setup("minion", "blue", "ranged", "", false, "blue")
	view.play_hit()
	gt(view._hit_flash_timer, 0.0, "小兵受击也要闪白")
	view.play_attack_reaction()
	gt(view._attack_lunge_timer, 0.0, "小兵出手也要前倾")
	view.free()
