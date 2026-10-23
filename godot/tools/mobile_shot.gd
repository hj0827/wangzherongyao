extends SceneTree

const MAIN := preload("res://scenes/main_menu.tscn")
const Arena = preload("res://scripts/game/arena.gd")
const ModelUtils = preload("res://scripts/game/model_utils.gd")
const TouchLayout = preload("res://scripts/ui/touch_layout.gd")

var OUT_DIR := ProjectSettings.globalize_path("res://shots/")
const PHONE_SIZE := Vector2i(2000, 900)
const TABLET_SIZE := Vector2i(1600, 1200)

var viewport: SubViewport
var arena: Node3D
var passed := 0
var failed := 0

func _initialize() -> void:
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, true)
	DisplayServer.window_set_position(Vector2i(5200, 3200))
	DisplayServer.window_set_size(Vector2i(1, 1))
	Engine.max_fps = 30
	viewport = SubViewport.new()
	viewport.size = PHONE_SIZE
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.gui_disable_input = true
	root.add_child(viewport)
	_run()

func _check(condition: bool, message: String) -> void:
	if condition:
		passed += 1
		print("  OK   ", message)
	else:
		failed += 1
		print("  FAIL ", message)

func _near(actual: float, expected: float, epsilon: float, message: String) -> void:
	_check(absf(actual - expected) <= epsilon, "%s (expected %.2f, got %.2f)" % [message, expected, actual])

func _shot(file_name: String) -> void:
	var drawn := [false]
	RenderingServer.frame_post_draw.connect(func() -> void: drawn[0] = true, CONNECT_ONE_SHOT)
	var waits := 0
	while not drawn[0] and waits < 180:
		await process_frame
		waits += 1
	if not drawn[0]:
		print("SHOT SKIP ", file_name, " (render stalled)")
		return
	var img: Image = viewport.get_texture().get_image()
	img.save_png(OUT_DIR + file_name + ".png")
	print("SHOT ", file_name, " ", img.get_size())

func _touch(index: int, pressed: bool, position := Vector2.ZERO) -> InputEventScreenTouch:
	var event := InputEventScreenTouch.new()
	event.index = index
	event.pressed = pressed
	event.position = position
	return event

func _dump_buttons(label: String) -> void:
	for node in viewport.find_children("*", "Button", true, false):
		var button := node as Button
		if button == null or not button.is_visible_in_tree():
			continue
		var rect := button.get_global_rect()
		print("RECT %s '%s' %.1f %.1f %.1f %.1f center %.1f,%.1f" % [
			label, button.text, rect.position.x, rect.position.y, rect.size.x, rect.size.y,
			rect.get_center().x, rect.get_center().y,
		])

func _dump_control(label: String, control: Control) -> void:
	if control == null or not control.is_visible_in_tree():
		return
	var rect := control.get_global_rect()
	print("RECT %s %s %.1f %.1f %.1f %.1f center %.1f,%.1f" % [
		label, control.get_class(), rect.position.x, rect.position.y, rect.size.x, rect.size.y,
		rect.get_center().x, rect.get_center().y,
	])

func _run() -> void:
	var main: Node = MAIN.instantiate()
	viewport.add_child(main)
	await create_timer(0.9).timeout
	main.touch_mode = true
	main._show_menu()
	await create_timer(0.5).timeout
	await _shot("mobile_menu")
	_dump_buttons("menu")
	main._show_hero_select()
	await create_timer(0.5).timeout
	await _shot("mobile_hero_select")
	_dump_buttons("hero")
	main.notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	await process_frame
	_check(main.screen == "menu", "android back returns from hero select to menu")
	main._pending_online = true
	main._pending_mode = "team"
	main._show_online()
	await create_timer(0.5).timeout
	await _shot("mobile_online")
	_dump_buttons("online")
	main.notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	await process_frame
	_check(main.screen == "menu", "android back returns from online to menu")
	var hosted: Dictionary = main.session.host_game(24680, main.player_name, main.local_hero, "team")
	if bool(hosted.get("ok", false)):
		main._show_lobby()
		await create_timer(0.5).timeout
		await _shot("mobile_lobby")
		_dump_buttons("lobby")
	main.queue_free()
	await process_frame
	viewport.gui_disable_input = false

	var config := {
		"mode": "team",
		"humans": [{"id": "p1", "name": "你", "team": "blue", "hero_type": "archer"}],
		"bot_fill": true,
		"bot_ai": false,
		"touch_controls": true,
	}
	arena = Arena.new()
	arena.configure({"config": config, "authoritative": true, "local_owner": "p1"})
	viewport.add_child(arena)
	while not arena.build_complete:
		await process_frame
	await create_timer(0.4).timeout

	_check(arena.touch_mode, "arena switches to touch mode")
	_check(arena.hud.touch_mode, "HUD switches to touch mode")
	_check(arena.hud._joystick != null and arena.hud._attack_button != null and arena.hud._pause_button != null, "touch controls are built")
	_check(arena.hud._skill_q.touch_mode and arena.hud._skill_e.touch_mode, "skill buttons accept raw touch")
	_check(arena.hud._skill_q.size.x >= 110.0, "touch skill button is enlarged")
	_dump_control("hud_joystick", arena.hud._joystick)
	_dump_control("hud_attack", arena.hud._attack_button)
	_dump_control("hud_pause", arena.hud._pause_button)
	_dump_control("hud_q", arena.hud._skill_q)
	_dump_control("hud_e", arena.hud._skill_e)
	_dump_control("hud_minimap", arena.hud._minimap)
	_dump_control("hud_feed", arena.hud._feed_box)

	var hero_height := 0.0
	var minion_height := 0.0
	for entity_id in arena._views:
		var view = arena._views[entity_id]
		if view.kind == "hero" and hero_height <= 0.0:
			hero_height = ModelUtils.relative_aabb(view.model_root).size.y
		elif view.kind == "minion" and minion_height <= 0.0:
			minion_height = ModelUtils.relative_aabb(view.model_root).size.y
	print("UNIT HEIGHTS hero=%.2f minion=%.2f" % [hero_height, minion_height])
	_check(hero_height >= 2.2, "hero model measures at least 2.2 m")
	_check(minion_height > 0.8 and minion_height <= 1.6, "minion model stays small")
	_check(hero_height >= minion_height * 1.6, "hero reads clearly larger than a minion")

	var joystick: Control = arena.hud._joystick
	_check_control_gaps("phone")
	arena.notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	await process_frame
	_check(arena._paused and arena.hud.paused, "android back pauses a touch match")
	await create_timer(0.3).timeout
	await _shot("mobile_pause")
	_dump_buttons("pause_overlay")
	arena.notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	await process_frame
	_check(not arena._paused and not arena.hud.paused, "android back resumes a touch match")
	var center := joystick.size * 0.5
	joystick._gui_input(_touch(0, true, center + Vector2(0, -80)))
	_check(joystick.value.y < -0.5, "joystick press tilts up")
	_check(arena._touch_move.y < -0.5, "joystick emits movement to arena")
	joystick._gui_input(_touch(0, false, center + Vector2(0, -80)))
	_check(joystick.value == Vector2.ZERO and arena._touch_move == Vector2.ZERO, "joystick release stops movement")

	var joy_center: Vector2 = joystick.get_global_rect().get_center()
	var attack_center: Vector2 = arena.hud._attack_button.get_global_rect().get_center()
	viewport.push_input(_touch(10, true, joy_center + Vector2(0, -78)))
	viewport.push_input(_touch(11, true, attack_center))
	await process_frame
	_check(joystick.value.y < -0.5 and arena._touch_attack, "two fingers move and attack at the same time")
	viewport.push_input(_touch(10, false, joy_center + Vector2(0, -78)))
	viewport.push_input(_touch(11, false, attack_center))
	await process_frame
	_check(joystick.value == Vector2.ZERO and not arena._touch_attack, "lifting both fingers clears touch input")

	var q_center: Vector2 = arena.hud._skill_q.get_global_rect().get_center()
	viewport.push_input(_touch(12, true, joy_center + Vector2(-70, 0)))
	viewport.push_input(_touch(13, true, q_center))
	_check(joystick.value.x < -0.5 and arena._queued_q, "skills queue while the joystick is held")
	viewport.push_input(_touch(12, false, joy_center + Vector2(-70, 0)))
	viewport.push_input(_touch(13, false, q_center))
	arena._queued_q = false
	arena._consume_skill_queue()
	await process_frame

	var attack_button: Control = arena.hud._attack_button
	attack_button._gui_input(_touch(1, true, Vector2(70, 70)))
	_check(arena._touch_attack, "attack button press reports held")
	attack_button._gui_input(_touch(1, false, Vector2(70, 70)))
	_check(not arena._touch_attack, "attack button release stops attack")

	arena.hud._skill_q._gui_input(_touch(2, true, Vector2(50, 50)))
	_check(arena._queued_q, "skill button queues raw touch cast")
	arena._queued_q = false

	var local_sim: Variant = arena.sim.get_hero_by_player("p1")
	var enemy_sim: Dictionary = {}
	if local_sim != null:
		local_sim.pos = Vector2(0.0, 0.0)
		local_sim.hp = local_sim.max_hp
		local_sim.mp = local_sim.max_mp
		local_sim.skill_q_cd = 0.0
		local_sim.skill_e_cd = 0.0
		for entity in arena.sim.state.entities:
			if entity.type == "hero" and entity.team == "red":
				entity.pos = Vector2(4.0, 0.4)
				entity.hp = entity.max_hp
				enemy_sim = entity
				break
	await create_timer(0.35).timeout

	arena._touch_aim_valid = false
	var auto_aim: Vector2 = arena._resolve_touch_aim()
	_near_vector(auto_aim, Vector2(4.0, 0.4), 1.4, "auto aim locks the nearby enemy")

	var camera_right: Vector3 = arena.camera.global_transform.basis.x
	var screen_right := Vector2(camera_right.x, camera_right.z).normalized()
	var before: Dictionary = arena._snapshot_local_hero().duplicate()
	arena._on_touch_move(Vector2(1, 0))
	await create_timer(0.5).timeout
	arena._on_touch_move(Vector2.ZERO)
	var after: Dictionary = arena._snapshot_local_hero()
	var moved := Vector2(
		float(after.get("x", 0.0)) - float(before.get("x", 0.0)),
		float(after.get("y", 0.0)) - float(before.get("y", 0.0))
	)
	_check(moved.dot(screen_right) > 0.2, "joystick right moves the hero along camera right")
	var forward: Vector3 = arena._camera_forward()
	arena._on_touch_move(Vector2(0, -1))
	await create_timer(0.1).timeout
	_check(arena._local_input.move.dot(Vector2(forward.x, forward.z)) > 0.9, "joystick up matches the camera forward direction")
	arena._on_touch_move(Vector2(1, 0))
	await create_timer(0.1).timeout
	_check(arena._local_input.move.dot(screen_right) > 0.9, "joystick right matches the real camera right direction")
	arena._on_touch_move(Vector2.ZERO)
	await create_timer(0.1).timeout

	if local_sim != null:
		local_sim.pos = Vector2(0.0, 0.0)
	await create_timer(0.15).timeout

	var enemy_hp := float(enemy_sim.get("hp", 0.0))
	arena._on_touch_attack(true)
	await create_timer(0.7).timeout
	arena._on_touch_attack(false)
	_check(float(enemy_sim.get("hp", 0.0)) < enemy_hp, "held attack damages a nearby enemy")

	local_sim = arena.sim.get_hero_by_player("p1")
	if local_sim != null:
		local_sim.pos = Vector2(0.0, 0.0)
		local_sim.mp = local_sim.max_mp
		local_sim.skill_q_cd = 0.0
		local_sim.hp = local_sim.max_hp
		enemy_sim.hp = enemy_sim.max_hp
		enemy_sim.pos = Vector2(4.0, 0.3)
	arena._touch_aim_valid = false
	await create_timer(0.2).timeout
	arena.hud._skill_q._gui_input(_touch(3, true, Vector2(50, 50)))
	await create_timer(0.25).timeout
	var local_after_cast: Variant = arena.sim.get_hero_by_player("p1")
	_check(local_after_cast != null and (float(local_after_cast.skill_q_cd) > 0.0 or float(enemy_sim.get("hp", 1.0)) < float(enemy_sim.get("max_hp", 1.0))), "skill cast fires with auto aim")

	var local_snapshot: Dictionary = arena._snapshot_local_hero()
	print("STEP result panel")
	if not local_snapshot.is_empty():
		arena.hud.show_result("blue", local_snapshot)
	await create_timer(0.5).timeout
	print("STEP result shot")
	await _shot("mobile_result")
	_dump_buttons("result_overlay")
	print("STEP result back")
	var exited := [false]
	arena.exit_requested.connect(func(): exited[0] = true)
	arena.notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	await process_frame
	_check(exited[0], "android back leaves the result screen")
	arena.hud._result_overlay.visible = false
	arena.hud.result_shown = false
	if arena.hud._announce_tween != null and arena.hud._announce_tween.is_valid():
		arena.hud._announce_tween.kill()
	arena.hud._announce_panel.visible = false

	if local_sim != null:
		local_sim.pos = Vector2(0.0, 0.0)
		local_sim.hp = local_sim.max_hp
		local_sim.mp = local_sim.max_mp
		local_sim.skill_q_cd = 0.0
		local_sim.skill_e_cd = 0.0
	enemy_sim.hp = enemy_sim.max_hp
	enemy_sim.pos = Vector2(3.4, 0.6)
	arena.zoom = 19.0
	await create_timer(0.8).timeout
	arena._on_touch_attack(true)
	await create_timer(0.15).timeout
	await _shot("mobile_match_team")
	arena._on_touch_attack(false)

	var skill_ready: bool = local_sim != null and float(local_sim.skill_q_cd) <= 0.0
	if not skill_ready and local_sim != null:
		local_sim.skill_q_cd = 0.0
		local_sim.mp = local_sim.max_mp
	arena.hud._skill_q._gui_input(_touch(4, true, Vector2(50, 50)))
	await create_timer(0.12).timeout
	await _shot("mobile_skill")
	arena.hud._skill_q._gui_input(_touch(4, false, Vector2(50, 50)))

	viewport.size = TABLET_SIZE
	await create_timer(0.7).timeout
	_check_control_gaps("tablet")
	await _shot("mobile_match_tablet")

	print("")
	print("MOBILE CHECKS: %d  PASSED: %d  FAILED: %d" % [passed + failed, passed, failed])
	quit(0 if failed == 0 else 1)

func _check_control_gaps(label: String) -> void:
	var joy_rect: Rect2 = arena.hud._joystick.get_global_rect()
	var q_rect: Rect2 = arena.hud._skill_q.get_global_rect()
	var e_rect: Rect2 = arena.hud._skill_e.get_global_rect()
	var attack_rect: Rect2 = arena.hud._attack_button.get_global_rect()
	var pause_rect: Rect2 = arena.hud._pause_button.get_global_rect()
	var minimap_rect: Rect2 = arena.hud._minimap.get_global_rect()
	var feed_rect: Rect2 = arena.hud._feed_box.get_global_rect()
	var attack_center := attack_rect.get_center()
	var q_center := q_rect.get_center()
	var e_center := e_rect.get_center()
	_check(joy_rect.end.x < q_rect.position.x, "%s: joystick clears the skill arc" % label)
	_check(q_center.x < attack_center.x - 40.0 and e_center.x < attack_center.x - 40.0, "%s: skills sit left of attack" % label)
	_near(q_center.distance_to(attack_center), TouchLayout.SKILL_ARC_RADIUS, 1.0, "%s: Q follows the attack arc" % label)
	_near(e_center.distance_to(attack_center), TouchLayout.SKILL_ARC_RADIUS, 1.0, "%s: E follows the attack arc" % label)
	_check(not q_rect.intersects(attack_rect) and not e_rect.intersects(attack_rect), "%s: skill targets clear attack" % label)
	_check(not q_rect.intersects(e_rect), "%s: skill targets keep their own touch area" % label)
	_check(pause_rect.end.y < viewport.size.y * 0.5, "%s: pause sits in the upper half" % label)
	_check(attack_rect.end.x <= viewport.size.x and attack_rect.end.y <= viewport.size.y, "%s: attack button stays on screen" % label)
	_check(minimap_rect.position.x < viewport.size.x * 0.2 and minimap_rect.position.y < viewport.size.y * 0.3, "%s: minimap sits in the top-left" % label)
	_check(not minimap_rect.intersects(feed_rect), "%s: minimap clears the kill feed" % label)
	_check(feed_rect.position.x > viewport.size.x * 0.5, "%s: kill feed sits on the right" % label)

func _near_vector(actual: Vector2, expected: Vector2, epsilon: float, message: String) -> void:
	_check(actual.distance_to(expected) <= epsilon, "%s (expected %s, got %s)" % [message, str(expected), str(actual)])
