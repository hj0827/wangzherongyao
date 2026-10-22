extends SceneTree

# 读数与射程指示器的验收截图：
#   readout_bars  —— 近景看英雄头顶（红血条 + 蓝条）
#   readout_range —— 普攻范围环（常驻）
#   readout_skill —— 技能范围环（按下 Q 时闪一下）
#   readout_base  —— 泉水范围（基地脚下的圈）

const Arena = preload("res://scripts/game/arena.gd")
const MapData = preload("res://sim/map_data.gd")

var arena: Node3D
var viewport: SubViewport

func _initialize() -> void:
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, true)
	DisplayServer.window_set_position(Vector2i(5200, 3200))
	DisplayServer.window_set_size(Vector2i(1, 1))
	viewport = SubViewport.new()
	viewport.size = Vector2i(1280, 720)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.gui_disable_input = true
	root.add_child(viewport)
	arena = Arena.new()
	arena.configure({
		"config": {
			"mode": "duel",
			"humans": [{"id": "p1", "name": "苍刃", "team": "blue", "hero_type": "archer"}],
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

func _run() -> void:
	await create_timer(1.2).timeout
	arena.hud.visible = false
	arena._mouse_valid = false
	var hero: Dictionary = arena.sim.get_hero_by_player("p1")

	# 1) 近景血条：站到空地，拉近
	hero.pos = Vector2(0.0, 0.0)
	arena.zoom = 5.0
	arena._update_camera(1.0, true)
	await create_timer(0.8).timeout
	await _shot("readout_bars")

	# 2) 普攻范围环（archer 6.4）
	arena.zoom = 13.0
	arena._update_camera(1.0, true)
	await create_timer(0.5).timeout
	await _shot("readout_range")

	# 3) 技能范围环：手动触发 Q 的闪烁，趁没淡出赶紧抓
	arena._flash_skill_range("q")
	await create_timer(0.12).timeout
	await _shot("readout_skill")

	# 4) 泉水范围：站回基地
	hero.pos = MapData.BLUE_BASE + Vector2(2.0, 2.0)
	arena.zoom = 20.0
	arena._update_camera(1.0, true)
	await create_timer(1.0).timeout
	await _shot("readout_base")

	quit()
