extends "res://tests/test_base.gd"

# 高地双子塔与水晶护盾契约：
# 高地塔倒下后双子塔解锁；双塔存活期间水晶获得可再生护盾；
# 双塔全毁护盾破碎，水晶才能被直接伤害。状态必须进入快照、网络白名单与表现层。

const MatchSim = preload("res://sim/match_sim.gd")
const MapLayout = preload("res://sim/map/map_layout.gd")
const MapData = preload("res://sim/map_data.gd")
const Crystal = preload("res://sim/map/crystal.gd")
const MapView = preload("res://scripts/game/map_view.gd")
const Minimap = preload("res://scripts/ui/minimap.gd")
const Arena = preload("res://scripts/game/arena.gd")
const NetProtocol = preload("res://net/net_protocol.gd")

func _sim(mode := "duel") -> Object:
	return MatchSim.new({
		"mode": mode,
		"humans": [{"id": "p1", "name": "Tester", "team": "blue", "hero_type": "blade"}],
		"bot_fill": true,
		"bot_ai": false,
	})

func _count(sim: Object, type: String, team := "") -> int:
	var total := 0
	for entity in sim.state.entities:
		if str(entity.type) != type or not bool(entity.get("alive", false)):
			continue
		if team != "" and str(entity.team) != team:
			continue
		total += 1
	return total

func _find(sim: Object, type: String, team: String, predicate := Callable()) -> Array:
	var result: Array = []
	for entity in sim.state.entities:
		if str(entity.type) != type or str(entity.team) != team:
			continue
		if predicate.is_valid() and not bool(predicate.call(entity)):
			continue
		result.append(entity)
	return result

func _base(sim: Object, team: String) -> Dictionary:
	var found := _find(sim, "base", team)
	return found[0] if not found.is_empty() else {}

func _expose(sim: Object, team: String) -> void:
	var lane := "mid"
	for tier in ["outer", "inner", "high"]:
		var towers := _find(sim, "tower", team, func(entity): return str(entity.lane) == lane and str(entity.get("tier", "")) == tier)
		if not towers.is_empty():
			sim.apply_damage(int(towers[0].id), 999999.0)
	sim.tick(1.0 / 30.0)

func test_twin_guard_slots_flank_each_crystal() -> void:
	var slots: Array = MapLayout.guardian_slots()
	eq(slots.size(), 4, "双方各两座高地双子塔")
	for team in ["blue", "red"]:
		var owned: Array = slots.filter(func(slot): return str(slot.get("team", "")) == team)
		eq(owned.size(), 2, "%s方双子塔数量" % team)
		var sides := {}
		for slot in owned:
			var base := MapData.BLUE_BASE if team == "blue" else MapData.RED_BASE
			var distance: float = (slot.pos as Vector2).distance_to(base)
			gt(distance, MapData.BASE_RADIUS, "%s双子塔在基地外侧" % team)
			lt(distance, 14.0, "%s双子塔守在高地近处" % team)
			sides[str(slot.get("side", ""))] = true
		eq(sides.size(), 2, "%s双子塔分列左右" % team)
	# 双方基地在同一条对角线上，队伍对称是绕地图中心的 180° 旋转，
	# 而不是 MapLayout.mirror 的 y=x 镜像（那只会把蓝方基地映射回自己）。
	for slot in slots.filter(func(item): return str(item.get("team", "")) == "blue"):
		var opposite: Vector2 = -slot.pos
		var found := false
		for other in slots:
			if str(other.team) == "red" and (other.pos as Vector2).distance_to(opposite) < 0.01:
				found = true
		check(found, "红方双子塔与蓝方中心对称")

func test_guard_gating_follows_high_tower_exposure() -> void:
	var high := {"id": 1, "type": "tower", "team": "red", "lane": "mid", "tier": "high", "alive": true}
	var guard := {"id": 2, "type": "guard", "team": "red", "side": "left", "alive": true}
	eq(Crystal.alive_guards("red", [guard]), 1, "存活双子塔计数")
	check(not Crystal.is_guard_vulnerable(guard, [high, guard]), "高地塔未倒时双子塔无敌")
	high.alive = false
	check(Crystal.is_guard_vulnerable(guard, [high, guard]), "任意一路高地塔倒下后双子塔解锁")
	eq(Crystal.alive_guards("blue", [guard]), 0, "只统计本队双子塔")

func test_crystal_shield_fills_on_exposure_and_regenerates() -> void:
	var sim := _sim()
	eq(_count(sim, "guard", "red"), 2, "红方开局有两座双子塔")
	var base := _base(sim, "red")
	near(float(base.get("shield", 0.0)), 0.0, 0.001, "未暴露时水晶无护盾")
	_expose(sim, "red")
	eq(int(base.get("guards_alive", 0)), 2, "快照可读双塔存活数")
	near(float(base.get("shield", 0.0)), Crystal.SHIELD_PER_GUARD * 2.0, 0.1, "暴露瞬间双塔护盾充满")
	near(float(base.get("shield_max", 0.0)), Crystal.SHIELD_PER_GUARD * 2.0, 0.1, "护盾上限按存活双塔计算")
	var hp := float(base.hp)
	sim.apply_damage(int(base.id), 500.0)
	near(float(base.hp), hp, 0.001, "护盾吸收全部伤害，水晶本体不掉血")
	near(float(base.shield), Crystal.SHIELD_PER_GUARD * 2.0 - 500.0, 0.1, "护盾按伤害扣减")
	sim.state.time = float(sim.state.time) + Crystal.SHIELD_REGEN_DELAY + 1.0
	Crystal.tick(sim.state, 2.0)
	gt(float(base.shield), Crystal.SHIELD_PER_GUARD * 2.0 - 500.0, "脱战延迟后护盾回复")

func test_destroying_both_guards_breaks_shield() -> void:
	var sim := _sim()
	_expose(sim, "red")
	var base := _base(sim, "red")
	var guards := _find(sim, "guard", "red")
	sim.apply_damage(int(guards[0].id), 999999.0)
	Crystal.tick(sim.state, 0.0)
	near(float(base.get("shield_max", 0.0)), Crystal.SHIELD_PER_GUARD, 0.1, "失去一座双子塔后护盾上限减半")
	check(float(base.get("shield", 0.0)) <= Crystal.SHIELD_PER_GUARD + 0.1, "护盾立即压到新上限")
	var events: Array = sim.state.events.map(func(event): return str(event.get("type", "")))
	check(events.has("guard_destroyed"), "双子塔被摧毁会广播事件")
	sim.apply_damage(int(guards[1].id), 999999.0)
	Crystal.tick(sim.state, 0.0)
	near(float(base.get("shield", 1.0)), 0.0, 0.001, "双塔全毁后护盾归零")
	events = sim.state.events.map(func(event): return str(event.get("type", "")))
	check(events.has("crystal_shield_broken"), "护盾破碎会广播事件")
	var hp := float(base.hp)
	sim.apply_damage(int(base.id), 300.0)
	near(float(base.hp), hp - 300.0, 0.1, "无护盾时水晶直接掉血")

func test_crystal_state_reaches_snapshot_and_network() -> void:
	var sim := _sim("team")
	_expose(sim, "red")
	var snap: Dictionary = sim.snapshot()
	var guard_snap: Dictionary = snap.entities.filter(func(entity): return str(entity.type) == "guard")[0]
	check(guard_snap.has("side") and guard_snap.has("vulnerable"), "双子塔快照携带侧位与可攻击状态")
	var base_snap: Dictionary = snap.entities.filter(func(entity): return str(entity.type) == "base" and str(entity.team) == "red")[0]
	check(base_snap.has("shield") and base_snap.has("shield_max"), "基地快照携带水晶护盾")
	eq(int(base_snap.get("guards_alive", 0)), 2, "基地快照携带双塔存活数")
	var result: Dictionary = NetProtocol.sanitize_snapshot({
		"time": 1.0,
		"mode": "team",
		"bounds": 58.0,
		"entities": [
			{"id": 1, "type": "guard", "team": "red", "side": "left", "tier": "twin", "x": 1.0, "y": 1.0, "alive": true, "vulnerable": false, "hp": 100.0, "max_hp": 100.0},
			{"id": 2, "type": "base", "team": "red", "x": 2.0, "y": 2.0, "alive": true, "vulnerable": true, "hp": 100.0, "max_hp": 100.0, "shield": 1200.0, "shield_max": 2400.0, "guards_alive": 1},
		],
		"scores": {},
		"events": [],
	})
	check(bool(result.ok), "双子塔与水晶护盾快照通过白名单")
	if bool(result.ok):
		var entities: Array = result.snapshot.entities
		eq(str(entities[0].type), "guard", "双子塔类型保留")
		eq(str(entities[0].side), "left", "双子塔侧位保留")
		near(float(entities[1].shield), 1200.0, 0.001, "水晶护盾值保留")
		eq(int(entities[1].guards_alive), 1, "双塔存活数保留")

func test_view_and_minimap_mark_guards_and_shield() -> void:
	var marks: Dictionary = MapView.map_marks()
	eq(marks.guards.size(), 4, "MapView 暴露全部双子塔锚点")
	var guard_banner: Dictionary = MapView.event_banner({"type": "guard_destroyed", "team": "red", "guards_left": 1})
	check(str(guard_banner.get("text", "")).contains("双子塔"), "双子塔被毁有专属播报")
	var broken: Dictionary = MapView.event_banner({"type": "crystal_shield_broken", "team": "red"})
	check(str(broken.get("text", "")).contains("护盾"), "护盾破碎有专属播报")
	var guard_mark: Dictionary = Minimap.entity_mark({"type": "guard", "team": "red", "alive": true, "tier": "twin", "vulnerable": false})
	eq(str(guard_mark.get("kind", "")), "guard", "小地图绘制双子塔")
	check(bool(guard_mark.get("locked", false)), "未解锁双子塔带锁定标记")
	var base_mark: Dictionary = Minimap.entity_mark({"type": "base", "team": "red", "alive": true, "vulnerable": true, "shield": 1200.0})
	check(bool(base_mark.get("shield", false)), "小地图标记水晶护盾")

func test_arena_shows_crystal_shield_and_twin_towers() -> void:
	var arena: Node3D = Arena.new()
	arena._structures_root = Node3D.new()
	arena.add_child(arena._structures_root)
	arena._sync_structures({"entities": [{
		"id": 8, "type": "base", "team": "red", "x": 0.0, "y": 0.0,
		"hp": 6000.0, "max_hp": 6000.0, "alive": true, "vulnerable": true,
		"shield": 2400.0, "shield_max": 2400.0, "guards_alive": 2,
	}]}, true)
	var record: Dictionary = arena._structure_views.get(8, {})
	check(not record.is_empty(), "基地视图已创建")
	var bubble: Node3D = record.get("crystal_shield")
	check(bubble != null and bubble.visible, "有护盾时基地显示水晶护盾")
	arena._sync_structures({"entities": [{
		"id": 8, "type": "base", "team": "red", "x": 0.0, "y": 0.0,
		"hp": 6000.0, "max_hp": 6000.0, "alive": true, "vulnerable": true,
		"shield": 0.0, "shield_max": 0.0, "guards_alive": 0,
	}]}, false)
	check(bubble != null and not bubble.visible, "护盾破碎后隐藏水晶护盾")
	arena._sync_structures({"entities": [{
		"id": 9, "type": "guard", "team": "red", "tier": "twin", "side": "left",
		"x": 4.0, "y": 4.0, "hp": 3200.0, "max_hp": 3200.0, "alive": true,
		"vulnerable": false, "radius": 1.6,
	}]}, false)
	var guard_record: Dictionary = arena._structure_views.get(9, {})
	check(not guard_record.is_empty(), "双子塔视图已创建")
	if not guard_record.is_empty():
		near(float(guard_record.get("scale", 0.0)), MapView.tower_scale("twin"), 0.001, "双子塔使用专属体型")
		var shield: Node3D = guard_record.get("shield")
		check(shield != null and shield.visible, "未解锁双子塔显示护盾")
	arena.free()
