extends "res://tests/test_base.gd"

const HeroDefs = preload("res://sim/hero_defs.gd")
const MatchSim = preload("res://sim/match_sim.gd")
const ModelUtils = preload("res://scripts/game/model_utils.gd")
const UnitVisual = preload("res://scripts/game/unit_visual.gd")
const Arena = preload("res://scripts/game/arena.gd")
const GameSession = preload("res://net/game_session.gd")
const LanDiscovery = preload("res://net/lan_discovery.gd")
const MAIN := preload("res://scripts/app/main.gd")

# 1. 验证所有英雄都具备专属台词与视频资源（声音由视频原声提供）
func test_all_heroes_have_quotes_and_videos() -> void:
	for hero_type in ["blade", "mage", "tank", "archer"]:
		var def: Dictionary = HeroDefs.get_hero(hero_type)
		check(def.has("quote") and str(def.quote).length() > 0, hero_type + " must have non-empty quote")
		check(def.has("video_path") and ResourceLoader.exists(def.video_path), hero_type + " video must exist at " + str(def.get("video_path", "")))

# 2. 验证选英雄界面中各英雄卡片视频组件与台词展示
func test_hero_select_video_and_quote_presentation() -> void:
	var main: Node = MAIN.new()
	# 测试不入场景树，需手动注入依赖（正常运行时由 _ready 创建）
	main.session = GameSession.new()
	main.discovery = LanDiscovery.new()
	main._build_shell()
	main._show_hero_select()
	eq(main.screen, "hero_select", "Screen should be hero_select")
	
	# 检查4位英雄的视频组件与卡片生成
	check(main._hero_cards.size() == 4, "Must have 4 hero cards")
	check(main._hero_videos.size() == 4, "Must have 4 hero video players")
	
	# 默认选中 blade
	eq(main.local_hero, "blade", "Default selected hero is blade")
	check(main._quote_label != null, "Quote label must be initialized")
	check(main._quote_label.text.contains("剑气破长空"), "Default quote must match blade")
	
	# 切换为 archer
	main.local_hero = "archer"
	main._refresh_hero_selection()
	check(main._quote_label.text.contains("箭出无回"), "Quote must update to archer's quote")
	
	main.queue_free()

# 3. 验证死亡小兵在 MatchSim 中的自动延迟回收，杜绝无限膨胀
func test_dead_minions_cleaned_up_in_sim() -> void:
	var sim := MatchSim.new({
		"mode": "duel",
		"humans": [{"id": "p1", "name": "蓝一", "team": "blue", "hero_type": "blade"}],
		"bot_fill": true,
	})
	
	# 推进时间生成小兵
	for i in 60:
		sim.tick(0.1)
		
	var initial_entities: Array = sim.snapshot().entities
	var minions: Array = initial_entities.filter(func(e): return e.type == "minion")
	gt(minions.size(), 0, "Minions should have spawned")
	
	# 击杀一个小兵
	var target_minion: Dictionary = minions[0]
	sim.apply_damage(target_minion.id, 99999.0, 1)
	
	# 击杀后立即检查：状态变为 dead，且持有 death_cleanup_timer
	var snap1: Dictionary = sim.snapshot()
	var killed_e: Array = snap1.entities.filter(func(e): return e.id == target_minion.id)
	check(killed_e.size() == 1 and not killed_e[0].alive, "Killed minion should be marked dead")
	
	# 模拟经过 3 秒（超过 2.0s 清理时间）
	for i in 35:
		sim.tick(0.1)
		
	var snap2: Dictionary = sim.snapshot()
	var remaining_killed: Array = snap2.entities.filter(func(e): return e.id == target_minion.id)
	eq(remaining_killed.size(), 0, "Dead minion must be safely cleaned up from simulation entities")

# 4. 验证 ModelUtils 的 AABB 缓存工作正常
func test_model_utils_scene_box_caching() -> void:
	var pine: PackedScene = load("res://assets/environment/Rock.glb")
	if pine != null:
		var node1 := ModelUtils.fit_scene(pine, 2.0)
		check(ModelUtils._scene_box_cache.has(pine.resource_path), "ModelUtils must cache scene box")
		var cached_box: AABB = ModelUtils._scene_box_cache[pine.resource_path]
		gt(cached_box.size.y, 0.0, "Cached box must be valid")
		var node2 := ModelUtils.fit_scene(pine, 3.0)
		check(node1 != null and node2 != null, "Both fitted instances must be created successfully")
		node1.queue_free()
		node2.queue_free()

# 5. 切换界面时必须释放旧节点，避免选人界面的视频/模型长期驻留
func test_hero_select_screen_nodes_are_freed_on_navigation() -> void:
	var main: Node = MAIN.new()
	main.session = GameSession.new()
	main.discovery = LanDiscovery.new()
	main._build_shell()
	main._show_hero_select()
	var card: Node = main._hero_cards.get("blade")
	check(card != null, "Hero card must exist")
	main._show_menu()
	check(card != null and card.is_queued_for_deletion(), "Leaving hero select must free the old hero cards")
	main.queue_free()

# 8. 进场加载遮罩必须独立于主 UI 层，并实时反映分帧构建进度
func test_loading_overlay_reports_staged_build_progress() -> void:
	var main: Node = MAIN.new()
	main.session = GameSession.new()
	main.discovery = LanDiscovery.new()
	main._build_shell()
	main.local_hero = "mage"
	main._show_loading_transition("mage")
	check(main._loading_layer != null, "Loading layer must be created")
	check(main._loading_layer.layer >= 20, "Loading layer must sit above gameplay HUD")
	check(main._loading_screen.get_parent() == main._loading_layer, "Loading screen must live on its own CanvasLayer")
	main._on_arena_build_progress(0.42, "摆放战场设施")
	near(main._loading_progress.value, 42.0, 0.1, "Progress bar must track build progress")
	check(main._loading_status.text.begins_with("摆放战场设施"), "Status must show current build stage")
	check(main._loading_status.text.contains("42"), "Status must show percent")
	# 重复进场时必须替换旧遮罩，而不是叠出两层
	main._show_loading_transition("blade")
	check(main._loading_status != null and main._loading_progress.value == 0.0, "Second entry must reset progress")
	main.queue_free()

# 9. 只有被选中的英雄才加载并显示视频；切换英雄时旧视频隐藏、台词重新触发
func test_hero_select_plays_only_the_selected_video() -> void:
	var main: Node = MAIN.new()
	main.session = GameSession.new()
	main.discovery = LanDiscovery.new()
	main._build_shell()
	main._show_hero_select()
	var blade_video: VideoStreamPlayer = main._hero_videos["blade"]
	check(blade_video.stream != null, "Default selected hero video must be loaded")
	check(blade_video.visible, "Default selected hero video must be visible")
	check(main._hero_videos["mage"].stream == null, "Unselected heroes must not decode video")
	check(main._hero_videos["tank"].stream == null, "Unselected heroes must not decode video")

	main.local_hero = "archer"
	main._refresh_hero_selection()
	var archer_video: VideoStreamPlayer = main._hero_videos["archer"]
	check(archer_video.stream != null and archer_video.visible, "Newly selected hero video must load and show")
	check(not blade_video.visible, "Previously selected hero video must hide")
	main.queue_free()

# 6. 小兵对象池复用时必须恢复血条、队伍环和待机动画
func test_minion_pool_reuse_restores_visible_state() -> void:
	var view := UnitVisual.new()
	view.setup("minion", "blue", "minion", "", false)
	view._update_dead_state(false)
	view.recycle()
	check(not view.visible, "Recycled minion must be hidden")
	view.reset_minion("blue", Vector3(2.0, 0.0, 3.0))
	check(not view.dead and view.visible, "Reused minion must be alive and visible again")
	check(view.current_animation == "Idle", "Reused minion must restart idle animation")
	check(view.team_ring != null and view.team_ring.visible, "Reused minion must restore its team ring")
	view.free()

# 7. 单位不参与方向光阴影渲染，降低对战时阴影 pass 与 draw call 压力
func test_unit_meshes_cast_no_shadows() -> void:
	var view := UnitVisual.new()
	view.setup("minion", "red", "minion", "", false)
	var offenders := 0
	for node in view.find_children("*", "GeometryInstance3D", true, false):
		var mesh := node as GeometryInstance3D
		if mesh != null and mesh.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
			offenders += 1
	eq(offenders, 0, "Unit meshes should not cast shadows")
	view.free()
