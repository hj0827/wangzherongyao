extends SceneTree

# 复现用户场景（站在塔旁不动）并连拍，同时打印显示器刷新率 / vsync / 帧节奏。
# 抓完的帧交给外部做逐像素 diff，判断画面里到底是什么在动。

const Arena = preload("res://scripts/game/arena.gd")

var arena: Node3D
var viewport: SubViewport
var dts: Array = []
var cams: Array = []
var views: Array = []
var shakes: Array = []

func _initialize() -> void:
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, true)
	DisplayServer.window_set_position(Vector2i(5200, 3200))
	DisplayServer.window_set_size(Vector2i(1, 1))
	print("SCREEN refresh=%.2fHz vsync=%d" % [
		DisplayServer.screen_get_refresh_rate(),
		DisplayServer.window_get_vsync_mode(),
	])
	viewport = SubViewport.new()
	viewport.size = Vector2i(1080, 580)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.gui_disable_input = true
	root.add_child(viewport)
	arena = Arena.new()
	arena.configure({
		"config": {
			"mode": "duel",
			"humans": [{"id": "p1", "name": "苍刃", "team": "blue", "hero_type": "blade"}],
			"bot_fill": true,
			"bot_ai": true,
		},
		"authoritative": true,
		"local_owner": "p1",
	})
	viewport.add_child(arena)
	_run()

func _shot(file_name: String) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = viewport.get_texture().get_image()
	img.save_png(ProjectSettings.globalize_path("res://shots/%s.png" % file_name))
	print("SHOT ", file_name)

func _process(delta: float) -> bool:
	dts.append(delta)
	if arena != null and arena.camera != null:
		cams.append(arena.camera.position)
		shakes.append(arena._camera_shake)
		var v = arena._views.get(arena._local_entity_id, null)
		if v:
			views.append(v.position)
			if views.size() % 20 == 0:
				var h: Dictionary = arena.sim.get_hero_by_player("p1")
				print("t=%d input_move=%s view=%s sim_pos=%s alive=%s hp=%.0f" % [
					views.size(),
					str(arena._local_input.get("move", Vector2.ZERO)),
					str(v.position),
					str(h.get("pos", Vector2.ZERO)),
					str(h.get("alive", true)),
					float(h.get("hp", 0.0)),
				])
	return false

func _run() -> void:
	await create_timer(1.2).timeout
	arena.hud.visible = false
	arena._mouse_valid = false
	# 把英雄挪到蓝方中路塔旁边，贴近用户截图的取景
	var tower_pos := Vector2(0, 0)
	for e in arena.sim.snapshot().get("entities", []):
		if str(e.get("type")) == "tower" and str(e.get("team")) == "blue" and str(e.get("lane")) == "mid":
			tower_pos = Vector2(float(e.get("x")), float(e.get("y")))
			break
	var hero: Dictionary = arena.sim.get_hero_by_player("p1")
	hero.pos = tower_pos + Vector2(-4.0, 2.0)
	print("HERO controller=", hero.get("controller"), " pos=", hero.pos, " target=", hero.get("target_pos"))
	arena.zoom = 21.0
	arena._update_camera(1.0, true)
	await create_timer(2.5).timeout
	print("CAM ", arena.camera.position, " VIEW ", arena._views[arena._local_entity_id].position)
	for i in 8:
		await _shot("tower_%d" % i)
		await RenderingServer.frame_post_draw
	# 帧节奏统计
	var total := 0.0
	var mn := 9.0
	var mx := 0.0
	for d in dts:
		total += float(d)
		mn = minf(mn, float(d))
		mx = maxf(mx, float(d))
	print("FRAME n=%d avg=%.2fms min=%.2f max=%.2f" % [dts.size(), total / maxf(1.0, dts.size()) * 1000.0, mn * 1000.0, mx * 1000.0])
	_report_vec("CAM", cams)
	_report_vec("VIEW", views)
	_report_float("SHAKE", shakes)
	quit()

func _report_vec(label: String, hist: Array) -> void:
	if hist.is_empty():
		print(label, " <empty>")
		return
	var mn: Vector3 = hist[0]
	var mx: Vector3 = hist[0]
	var flips := 0
	for i in hist.size():
		var v: Vector3 = hist[i]
		mn = Vector3(minf(mn.x, v.x), minf(mn.y, v.y), minf(mn.z, v.z))
		mx = Vector3(maxf(mx.x, v.x), maxf(mx.y, v.y), maxf(mx.z, v.z))
		if i > 0 and v != hist[i - 1]:
			flips += 1
	print("%s span=(%.5f,%.5f,%.5f) changed=%d/%d" % [label, mx.x - mn.x, mx.y - mn.y, mx.z - mn.z, flips, hist.size()])

func _report_float(label: String, hist: Array) -> void:
	if hist.is_empty():
		print(label, " <empty>")
		return
	var mn: float = hist[0]
	var mx: float = hist[0]
	var flips := 0
	for i in hist.size():
		mn = minf(mn, float(hist[i]))
		mx = maxf(mx, float(hist[i]))
		if i > 0 and float(hist[i]) != float(hist[i - 1]):
			flips += 1
	print("%s span=%.6f changed=%d/%d" % [label, mx - mn, flips, hist.size()])
