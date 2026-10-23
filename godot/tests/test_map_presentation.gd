extends "res://tests/test_base.gd"

# 地图表现层契约：Arena / 小地图 / HUD 共用 MapView 的几何与语义；
# 野怪、塔层、锁定态、回城输入都必须真正进入表现链路。

const MapView = preload("res://scripts/game/map_view.gd")
const MapLayout = preload("res://sim/map/map_layout.gd")
const MapData = preload("res://sim/map_data.gd")
const Minimap = preload("res://scripts/ui/minimap.gd")
const Arena = preload("res://scripts/game/arena.gd")
const GameHUD = preload("res://scripts/ui/game_hud.gd")

func test_map_view_smooths_lanes_and_exposes_features() -> void:
	for lane in MapData.LANE_ORDER:
		var raw: Array = MapData.lane_path(lane)
		var smooth: Array = MapView.lane_path(lane)
		gt(float(smooth.size()), float(raw.size()), "%s lane must render smoothed" % lane)
		near(smooth[0].distance_to(raw[0]), 0.0, 0.001, "%s smoothed lane keeps start" % lane)
		near(smooth[smooth.size() - 1].distance_to(raw[raw.size() - 1]), 0.0, 0.001, "%s smoothed lane keeps end" % lane)
	var marks: Dictionary = MapView.map_marks()
	eq(marks.walls.size(), MapLayout.WALLS.size(), "walls come from MapLayout")
	eq(marks.bushes.size(), MapLayout.BUSHES.size(), "bushes come from MapLayout")
	eq(marks.camps.size(), MapLayout.CAMPS.size(), "camps come from MapLayout")
	eq(marks.objectives.size(), MapLayout.OBJECTIVE_PITS.size(), "objective pits come from MapLayout")
	eq(marks.tower_slots.size(), 18, "all 18 tower slots exposed to the view")

func test_map_view_tower_tiers_and_lock_visuals() -> void:
	gt(MapView.tower_scale("high"), MapView.tower_scale("inner"), "high tower model larger than inner")
	gt(MapView.tower_scale("inner"), MapView.tower_scale("outer"), "inner tower model larger than outer")
	var red := Color(0.8, 0.2, 0.2)
	var open := MapView.structure_tint(red, {"alive": true, "vulnerable": true})
	var locked := MapView.structure_tint(red, {"alive": true, "vulnerable": false})
	near(open.r, red.r, 0.001, "vulnerable structure keeps team color")
	check(locked.r < red.r or locked.g > red.g, "locked structure desaturated toward stone")
	eq(MapView.structure_locked({"alive": true, "vulnerable": false}), true, "locked state detected")
	eq(MapView.structure_locked({"alive": true, "vulnerable": true}), false, "open state detected")

func test_map_view_builds_event_banners() -> void:
	var boss := MapView.event_banner({"type": "objective_killed", "team": "blue", "name": "暴君"})
	check(str(boss.get("text", "")).contains("暴君"), "objective banner names the boss")
	check(str(boss.get("text", "")).contains("蓝方"), "objective banner names the team")
	var buff := MapView.event_banner({"type": "buff_taken", "team": "red", "buff": "blue", "name": "霜狼"})
	check(str(buff.get("text", "")).contains("蓝BUFF"), "buff banner names the buff")
	var exposed := MapView.event_banner({"type": "base_exposed", "team": "red", "lane": "mid"})
	check(str(exposed.get("text", "")).contains("红方"), "base exposure names the team")
	check(str(exposed.get("text", "")).contains("暴露"), "base exposure warns of exposure")
	var tower := MapView.event_banner({"type": "tower_destroyed", "team": "red", "tier": "high"})
	check(str(tower.get("feed", "")).contains("高地塔"), "tower banner distinguishes high tower")
	eq(MapView.event_banner({"type": "wave", "wave": 2}), {}, "unrelated events produce no banner")

func test_minimap_feature_shapes_cover_map_and_monsters() -> void:
	var shapes: Array = Minimap.feature_shapes()
	var kinds := {}
	for shape in shapes:
		kinds[str(shape.get("kind", ""))] = true
	for kind in ["wall", "bush", "camp", "objective"]:
		check(kinds.has(kind), "minimap draws " + kind)
	gt(float(shapes.size()), 10.0, "minimap feature shapes are populated")
	var monster := Minimap.entity_mark({"type": "monster", "team": "neutral", "alive": true, "monster_type": "wolf"})
	eq(str(monster.get("kind", "")), "monster", "minimap has a monster mark")
	gt(float(monster.get("radius", 0.0)), 0.0, "monster mark has size")
	var high := Minimap.entity_mark({"type": "tower", "team": "red", "alive": true, "tier": "high", "vulnerable": true})
	var outer := Minimap.entity_mark({"type": "tower", "team": "red", "alive": true, "tier": "outer", "vulnerable": true})
	gt(float(high.radius), float(outer.radius), "high tower mark bigger on minimap")
	var locked := Minimap.entity_mark({"type": "tower", "team": "red", "alive": true, "tier": "outer", "vulnerable": false})
	check(bool(locked.get("locked", false)), "minimap marks locked towers")

func test_arena_builds_map_feature_props() -> void:
	var arena: Node3D = Arena.new()
	arena._props_root = Node3D.new()
	arena.add_child(arena._props_root)
	arena._build_map_features()
	var props = arena._props_root.get_child_count()
	gt(float(props), 40.0, "walls/bushes/camps/pits create visual props")
	check(props >= MapLayout.WALLS.size() * 4 + MapLayout.BUSHES.size() * 8, "every feature has visible geometry")
	arena.free()

func test_arena_syncs_monster_views() -> void:
	var arena: Node3D = Arena.new()
	arena._units_root = Node3D.new()
	arena.add_child(arena._units_root)
	var alive_snapshot := {"entities": [{
		"id": 77, "type": "monster", "team": "neutral", "x": 3.0, "y": 4.0,
		"hp": 700.0, "max_hp": 720.0, "alive": true, "monster_type": "wolf", "name": "霜狼",
	}]}
	arena._sync_units(alive_snapshot, 0.016)
	var view: UnitVisual = arena._views.get(77)
	check(view != null, "monster gets a UnitVisual")
	if view:
		eq(str(view.kind), "monster", "view kind is monster")
		eq(str(view.monster_type), "wolf", "monster model type propagated")
		check(view.bar_mesh != null, "monster has a health bar")
		var dead_snapshot := {"entities": [{
			"id": 77, "type": "monster", "team": "neutral", "x": 3.0, "y": 4.0,
			"hp": 0.0, "max_hp": 720.0, "alive": false, "monster_type": "wolf", "name": "霜狼",
		}]}
		arena._sync_units(dead_snapshot, 0.016)
		check(bool(view.dead), "dead monster enters death state")
	arena.free()

func test_arena_structure_view_marks_locked_tower() -> void:
	var arena: Node3D = Arena.new()
	arena._structures_root = Node3D.new()
	arena.add_child(arena._structures_root)
	arena._sync_structures({"entities": [{
		"id": 9, "type": "tower", "team": "red", "x": 10.0, "y": 10.0,
		"hp": 100.0, "max_hp": 100.0, "alive": true, "tier": "high",
		"vulnerable": false, "radius": 1.0,
	}]}, true)
	var record: Dictionary = arena._structure_views.get(9, {})
	check(not record.is_empty(), "tower view created")
	if not record.is_empty():
		var shield: Node3D = record.get("shield")
		check(shield != null and shield.visible, "locked tower shows shield")
		near(float(record.get("scale", 0.0)), MapView.tower_scale("high"), 0.001, "high tower uses larger model")
		arena._sync_structures({"entities": [{
			"id": 9, "type": "tower", "team": "red", "x": 10.0, "y": 10.0,
			"hp": 100.0, "max_hp": 100.0, "alive": true, "tier": "high",
			"vulnerable": true, "radius": 1.0,
		}]}, false)
		check(not shield.visible, "unlocked tower hides shield")
	arena.free()

func test_arena_recall_intent_is_wired() -> void:
	var arena: Node3D = Arena.new()
	arena._on_skill_button("recall")
	check(arena._queued_recall, "recall button queues recall")
	arena.touch_mode = true
	arena._gather_touch_input()
	check(bool(arena._local_input.get("recall", false)), "touch gather delivers recall input")
	arena.free()

func test_hud_touch_recall_button_emits_recall() -> void:
	var hud := GameHUD.new()
	hud.setup("p1", "blue", "blade", "你", true, false)
	hud._ready()
	var slots: Array = []
	hud.skill_pressed.connect(func(slot): slots.append(slot))
	check(hud._recall_button != null, "touch HUD exposes a recall button")
	if hud._recall_button:
		hud._recall_button.pressed.emit()
	eq(slots, ["recall"], "recall button emits recall intent")
	hud.free()
