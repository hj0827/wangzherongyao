extends SceneTree

const Arena = preload("res://scripts/game/arena.gd")

var viewport: SubViewport
var arena: Node3D

func _initialize() -> void:
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, true)
	DisplayServer.window_set_position(Vector2i(5200, 3200))
	DisplayServer.window_set_size(Vector2i(1, 1))
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	viewport = SubViewport.new()
	viewport.size = Vector2i(1600, 900)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.gui_disable_input = true
	root.add_child(viewport)
	arena = Arena.new()
	arena.configure({
		"config": {
			"mode": "team",
			"humans": [{"id": "p1", "name": "你", "team": "blue", "hero_type": "archer"}],
			"bot_fill": true,
			"bot_ai": true,
		},
		"authoritative": true,
		"local_owner": "p1",
	})
	viewport.add_child(arena)
	_run()

func _run() -> void:
	while not arena.build_complete:
		await process_frame
	await create_timer(3.0).timeout
	var samples: Array[float] = []
	for i in 12:
		await create_timer(0.5).timeout
		samples.append(Engine.get_frames_per_second())
	var total := 0.0
	var worst := 9999.0
	var best := 0.0
	for value in samples:
		total += value
		worst = minf(worst, value)
		best = maxf(best, value)
	var snapshot: Dictionary = arena.current_snapshot
	print("PERF 5v5 1600x900 avg=%.1f min=%.1f max=%.1f fps" % [total / samples.size(), worst, best])
	print("PERF entities=", snapshot.get("entities", []).size(), " time=", snappedf(float(snapshot.get("time", 0.0)), 0.1))
	quit()
