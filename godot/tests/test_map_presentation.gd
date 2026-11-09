extends "res://tests/test_base.gd"

# 地图表现层契约：Arena / 小地图 / HUD 共用 MapView 的几何与语义；
# 野怪、塔层、锁定态、回城输入都必须真正进入表现链路。

const MapView = preload("res://scripts/game/map_view.gd")
const MapLayout = preload("res://sim/map/map_layout.gd")
const MapData = preload("res://sim/map_data.gd")
const Minimap = preload("res://scripts/ui/minimap.gd")
const Arena = preload("res://scripts/game/arena.gd")
const ModelUtils = preload("res://scripts/game/model_utils.gd")
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
	check(props >= MapLayout.WALLS.size() * 4 + MapLayout.BUSHES.size() * 2, "every feature has visible geometry")
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

func test_map_scenery_ships_no_trees() -> void:
	# 玩家要求地图里不放树：树只是布景，却会把兵线、野区和草丛挡得看不清。
	# 源码级断言把「以后又加回来」也挡在门外（_build_scenery 带 await，headless 不便直接跑）。
	var source := FileAccess.get_file_as_string("res://scripts/game/arena.gd")
	check(not source.contains("Resource_PineTree_Group.glb"), "地图不再加载松树模型")
	check(not source.contains("Resource_Tree_Group.glb"), "地图不再加载阔叶树模型")
	check(not source.contains("Resource_Tree1.glb"), "地图不再加载单株树模型")
	var start := source.find("func _build_scenery")
	var end := source.find("func _lane_distance", start)
	check(start >= 0 and end > start, "_build_scenery 要在")
	if start >= 0 and end > start:
		var body := source.substr(start, end - start)
		check(not body.contains("tree"), "布景里不能再生成树")
		check(body.contains("_props_root.add_child(rock)"), "岩石留着")
		check(body.contains("_props_root.add_child(mountain)"), "远山留着")

func test_backdrop_mountains_hide_when_the_camera_reaches_them() -> void:
	# 玩家反馈：贴到地图下边缘并拉远镜头时，相机会钻进远山，
	# 半个屏幕被岩壁糊住、英雄看不见。远山只是布景 —— 相机进入或贴近
	# 山体包围盒时整座隐藏，离远后恢复（判定用 AABB 而不是中心点）。
	var box := AABB(Vector3(-63.0, 8.6, -115.0), Vector3(62.0, 26.4, 63.0))
	check(not Arena.backdrop_hidden(Vector3(0.0, 20.0, 0.0), box), "相机在地图中心时远山照常显示")
	check(Arena.backdrop_hidden(Vector3(-19.0, 32.0, -76.0), box), "相机钻进山体时必须隐藏")
	check(Arena.backdrop_hidden(Vector3(-19.0, 32.0, -58.0), box), "相机贴着山体近面也要隐藏")
	check(not Arena.backdrop_hidden(Vector3(-19.0, 32.0, -20.0), box), "离得远就保持可见")

func test_arena_toggles_backdrop_visibility_from_the_camera() -> void:
	var arena: Node3D = Arena.new()
	var mountain := Node3D.new()
	arena.add_child(mountain)
	arena._backdrop_mountains.append({
		"node": mountain,
		"box": AABB(Vector3(-63.0, 8.6, -115.0), Vector3(62.0, 26.4, 63.0)),
	})
	arena._update_backdrop_visibility(Vector3(-19.0, 32.0, -70.0))
	check(not mountain.visible, "相机进山体时要把它关掉")
	arena._update_backdrop_visibility(Vector3(0.0, 20.0, 0.0))
	check(mountain.visible, "相机离远后要恢复")
	# 「写好了但没人调用」的老坑：建图要登记远山，相机每帧要刷新显隐。
	var source := FileAccess.get_file_as_string("res://scripts/game/arena.gd")
	check(source.contains("_backdrop_mountains.append"), "建图时必须登记每一座远山")
	check(source.contains("_update_backdrop_visibility(camera.global_position)"), "相机每帧要刷新远山显隐")
	arena.free()

func test_tower_model_is_slim_and_tall() -> void:
	# 塔身太宽会把站在塔后的英雄整条盖住（玩家反馈「塔挡视野」）。
	# 契约：视觉宽高比至少 2.8（细而尖），且血条必须悬在模型顶之上。
	# 当前外塔 7.3 高 / 3.8 宽只有 1.92，这条必须先红。
	var arena: Node3D = Arena.new()
	arena._structures_root = Node3D.new()
	arena.add_child(arena._structures_root)
	arena._sync_structures({"entities": [{
		"id": 21, "type": "tower", "team": "red", "x": 12.0, "y": 8.0,
		"hp": 100.0, "max_hp": 100.0, "alive": true, "tier": "outer",
		"vulnerable": true, "radius": 1.0,
	}]}, true)
	var record: Dictionary = arena._structure_views.get(21, {})
	check(not record.is_empty(), "outer tower view created")
	if not record.is_empty():
		var model: Node3D = record.get("model")
		check(model != null, "tower view keeps a reference to its model")
		if model:
			var box := ModelUtils.relative_aabb(model)
			var girth := maxf(box.size.x, box.size.z)
			gt(box.size.y, 8.2, "tower must read taller than before (got %.2f m)" % box.size.y)
			lt(girth, 3.0, "tower body must stay slim (got %.2f m)" % girth)
			gt(box.size.y / maxf(girth, 0.001), 2.8, "tower must look slim and pointed (aspect %.2f)" % (box.size.y / maxf(girth, 0.001)))
			gt(float(record.get("bar_height", 0.0)), box.size.y, "tower health bar must sit above the model top")
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
