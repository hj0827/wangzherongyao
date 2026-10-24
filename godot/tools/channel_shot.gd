extends SceneTree

# 回城 / 传送的引导表现截图。
# 直接摆好英雄的引导状态再让 Arena 跑几帧，避免依赖按键时序。

const Arena = preload("res://scripts/game/arena.gd")
const MapLayout = preload("res://sim/map/map_layout.gd")

var arena: Node3D
var viewport: SubViewport

func _initialize() -> void:
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	DisplayServer.window_set_position(Vector2i(5200, 3200))
	Engine.max_fps = 30
	viewport = SubViewport.new()
	viewport.size = Vector2i(1600, 900)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var config := {
		"mode": "duel",
		"humans": [{"id": "p1", "name": "苍刃", "team": "blue", "hero_type": "blade"}],
		"bot_fill": true,
		"bot_ai": false,
	}
	arena = Arena.new()
	arena.configure({"config": config, "authoritative": true, "local_owner": "p1"})
	viewport.add_child(arena)
	_run()

func _shot(file_name: String) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = viewport.get_texture().get_image()
	img.save_png(ProjectSettings.globalize_path("res://shots/%s.png" % file_name))
	var hero := _hero()
	var line := "SHOT %-26s recalling=%s timer=%.2f" % [file_name, str(hero.get("recalling", false)), float(hero.get("recall_timer", 0.0))]
	for eid in arena._channel_feedback:
		var fb = arena._channel_feedback[eid]
		line += " | fb kind=%s p=%.2f" % [fb.kind(), fb.progress()]
	print(line)

func _hero() -> Dictionary:
	return arena.sim.get_hero_by_player("p1")

func _begin_recall(at: Vector2, remaining: float) -> void:
	var hero := _hero()
	hero.pos = at
	hero.recalling = true
	hero.recall_timer = remaining
	hero.recall_total = 4.0
	hero.recall_from = at

func _begin_teleport(at: Vector2, remaining: float) -> void:
	var hero := _hero()
	hero.pos = at
	hero.teleporting = true
	hero.teleport_timer = remaining
	hero.teleport_total = 2.5
	hero.teleport_cd = 0.0
	hero.teleport_from = at
	hero.teleport_pad = str(MapLayout.TELEPORT_PADS[0].get("id", ""))

func _run() -> void:
	while not arena.build_complete:
		await process_frame
	await create_timer(0.5).timeout
	arena.zoom = 12.0
	arena._update_camera(1.0, true)

	# 回城：起手（法阵刚立起来，光柱很矮）
	_begin_recall(Vector2(-18.0, -14.0), 3.9)
	await create_timer(0.35).timeout
	await _shot("channel_recall_start")

	# 回城：读到一半（法阵收拢、光柱升高、粒子变密）
	_begin_recall(Vector2(-18.0, -14.0), 2.0)
	await create_timer(0.35).timeout
	await _shot("channel_recall_mid")

	# 回城：即将完成
	_begin_recall(Vector2(-18.0, -14.0), 0.45)
	await create_timer(0.3).timeout
	await _shot("channel_recall_late")

	# 回城落地：镜头已跟到泉水，落点环还在
	await create_timer(0.25).timeout
	await _shot("channel_recall_landed")

	# 传送：引导中
	_begin_teleport(MapLayout.TELEPORT_PADS[0].pos, 1.25)
	arena._update_camera(1.0, true)
	await create_timer(0.4).timeout
	await _shot("channel_teleport_mid")

	# 传送抵达
	await create_timer(1.4).timeout
	await _shot("channel_teleport_arrived")

	# 打断：法阵内爆
	_begin_teleport(MapLayout.TELEPORT_PADS[0].pos, 1.0)
	await create_timer(0.35).timeout
	var hero := _hero()
	hero.teleporting = false
	hero.teleport_timer = 0.0
	hero.teleport_total = 0.0
	arena.sim._emit("teleport_interrupt", {
		"team": hero.team, "hero": hero.id, "x": hero.pos.x, "y": hero.pos.y,
	})
	arena._process_events(arena.sim.state.events)
	await create_timer(0.16).timeout
	await _shot("channel_teleport_break")

	quit()
