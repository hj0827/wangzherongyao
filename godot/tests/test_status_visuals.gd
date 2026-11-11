extends "res://tests/test_base.gd"

# C9 / FX-11 状态可视守卫：加速风线、免控光环、护盾吸收、治疗飘字、低血红晕。
# 这些信息以前只存在模拟层的计时器里，表现层拿不到或只当布尔用；
# 本文件保证「字段能过协议 → 快照带得走 → 视觉节点真的亮/灭」。

const MatchSim = preload("res://sim/match_sim.gd")
const NetProtocol = preload("res://net/net_protocol.gd")
const GameHUD = preload("res://scripts/ui/game_hud.gd")
const UnitVisual = preload("res://scripts/game/unit_visual.gd")

func _duel() -> Dictionary:
	var sim := MatchSim.new({
		"mode": "duel",
		"humans": [
			{"id": "p1", "name": "小明", "team": "blue", "hero_type": "blade"},
			{"id": "p2", "name": "小红", "team": "red", "hero_type": "tank"},
		],
		"bot_fill": false,
	})
	return {"sim": sim, "blue": sim.get_hero_by_player("p1"), "red": sim.get_hero_by_player("p2")}

func _event_of_type(events: Array, type: String) -> Dictionary:
	for event in events:
		if event is Dictionary and str(event.get("type", "")) == type:
			return event
	return {}

func test_snapshot_carries_cc_immune_timer() -> void:
	var ctx := _duel()
	var sim: MatchSim = ctx["sim"]
	var blue: Dictionary = ctx["blue"]
	blue["cc_immune_timer"] = 2.0
	var shot := sim.snapshot()
	var found := {}
	for entity in shot.get("entities", []):
		if int(entity.get("id", -1)) == int(blue.id):
			found = entity
	eq(float(found.get("cc_immune_timer", -1.0)), 2.0, "快照带免控剩余时间，客户端能画完整时长的光环")

func test_cc_immune_timer_survives_the_wire() -> void:
	var clean := NetProtocol._sanitize_entity({
		"type": "hero", "id": 1, "team": "blue", "x": 0.0, "y": 0.0, "cc_immune_timer": 1.25,
	}, 58.0)
	eq(float(clean.get("cc_immune_timer", -1.0)), 1.25, "免控计时器进实体白名单")
	var clamped := NetProtocol._sanitize_entity({
		"type": "hero", "id": 1, "team": "blue", "x": 0.0, "y": 0.0, "cc_immune_timer": 99.0,
	}, 58.0)
	eq(float(clamped.get("cc_immune_timer", -1.0)), 10.0, "免控计时器夹在 0~10s")

func test_fully_absorbed_hit_emits_absorbed_event() -> void:
	var ctx := _duel()
	var sim: MatchSim = ctx["sim"]
	var blue: Dictionary = ctx["blue"]
	var red: Dictionary = ctx["red"]
	red["shield"] = 5000.0
	sim._damage(red, 200.0, blue, "physical")
	var hit := _event_of_type(sim.consume_events(), "hit")
	check(not hit.is_empty(), "全额被盾吃掉也要发 hit，不能静默")
	if not hit.is_empty():
		eq(float(hit.get("amount", -1.0)), 0.0, "护盾全吸时伤害为 0")
		check(float(hit.get("absorbed", 0.0)) > 0.0, "事件带吸收量，HUD 能飘「盾 N」")

func test_absorbed_survives_the_wire() -> void:
	var packet := NetProtocol.sanitize_events({"time": 1.0, "events": [{
		"type": "hit", "team": "red", "target": 2, "amount": 0.0, "absorbed": 86.0,
		"x": 1.0, "y": 2.0,
	}]})
	var events: Array = packet.get("events", [])
	eq(events.size(), 1, "护盾命中事件通过白名单")
	if events.size() == 1:
		eq(float(events[0].get("absorbed", 0.0)), 86.0, "吸收量透传")

func test_lifesteal_emits_heal_event_with_source_position() -> void:
	var ctx := _duel()
	var sim: MatchSim = ctx["sim"]
	var blue: Dictionary = ctx["blue"]
	var red: Dictionary = ctx["red"]
	blue["lifesteal"] = 0.5
	blue["hp"] = 100.0
	blue["max_hp"] = 5000.0
	sim._damage(red, 240.0, blue, "physical")
	var heal := _event_of_type(sim.consume_events(), "heal")
	check(not heal.is_empty(), "吸血要发 heal 事件")
	if not heal.is_empty():
		check(float(heal.get("amount", 0.0)) > 0.5, "治疗量大于 0")
		eq(float(heal.get("x", 999.0)), float(blue.pos.x), "治疗飘字落在治疗者脚下 x")
		eq(float(heal.get("y", 999.0)), float(blue.pos.y), "治疗飘字落在治疗者脚下 y")

func test_unit_visual_toggles_haste_and_immune_rings() -> void:
	var view := UnitVisual.new()
	view.setup("hero", "blue", "blade", "你", true, "blue")
	check(view.haste_ring != null, "英雄有加速风线节点")
	check(view.immune_aura != null, "英雄有免控护体节点")
	var base := {
		"id": 1, "kind": "hero", "team": "blue", "hero_type": "blade",
		"hp": 500.0, "max_hp": 1000.0, "x": 0.0, "y": 0.0, "alive": true,
	}
	var hasted := base.duplicate()
	hasted["haste_timer"] = 1.0
	hasted["moving"] = true
	hasted["cc_immune_timer"] = 1.0
	view.set_snapshot(hasted, 0.016)
	check(view.haste_ring.visible, "加速且移动时显示风线")
	check(view.immune_aura.visible, "免控时显示护体光环")
	var idle := base.duplicate()
	idle["haste_timer"] = 1.0
	idle["moving"] = false
	view.set_snapshot(idle, 0.016)
	check(not view.haste_ring.visible, "站着不动时不画风线（否则像常驻光圈）")
	check(not view.immune_aura.visible, "免控结束后光环熄灭")
	view.free()

func test_hud_low_health_vignette_thresholds() -> void:
	var hud := GameHUD.new()
	hud.setup("p1", "blue", "blade", "你", false, false)
	hud._ready()
	check(hud._low_health != null, "HUD 有低血红晕层")
	hud.set_low_health(0.8)
	check(not hud._low_health.visible, "健康时不显示红晕")
	hud.set_low_health(0.15)
	check(hud._low_health.visible, "残血时显示红晕")
	check(hud._low_health.modulate.a > 0.0, "红晕强度随缺失血量增加")
	hud.set_low_health(1.0)
	check(not hud._low_health.visible, "回满/死亡时关闭红晕")
	hud.free()
