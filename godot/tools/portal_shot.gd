extends SceneTree

# 传送阵造型与状态的验收截图工具（入库）。
#
# 为什么要单独一个工具：传送阵的「好看」根本不在静止画面上 ——
# 它要能读出四件事，每一件都在不同的时间点：
#   ① 待机：石台 + 符文轮 + 三根方尖柱 + 浮空晶体（远景能不能认出这是设施）；
#   ② 起手：刚有人踩上阵、开始读条（法阵开始抽亮）；
#   ③ 读条过半：符文扫过一半、齿环抽亮、晶体与点光变强（进度可读）；
#   ④ 抵达/打断：对端炸光 or 符文裂开（"成了 / 断了"必须一眼分开）。
#
# 用法：powershell -ExecutionPolicy Bypass -File godot\tools\shot_offscreen.ps1 tools\portal_shot.gd
#       （别直接 godot --path godot --script：会开窗口闪一下；脚本走隐藏桌面）
# 产物：godot/shots/portal_idle.png / portal_charge_*.png / portal_arrive.png
#      / portal_break.png / portal_sheet.png（截图产物不入库，.gitignore 已拦 shots/）

const Arena = preload("res://scripts/game/arena.gd")
const MapLayout = preload("res://sim/map/map_layout.gd")

var arena: Node3D
var viewport: SubViewport

func _initialize() -> void:
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, true)
	DisplayServer.window_set_position(Vector2i(5200, 3200))
	Engine.max_fps = 20
	viewport = SubViewport.new()
	viewport.size = Vector2i(1280, 720)
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
	print("SHOT %-24s portal_charge=%.2f" % [file_name, arena._portal_charge])

## 手动推进 arena：关掉 _process 之后它不再自己跑，但传送阵的状态必须继续走。
## 三件事缺一不可：
##   ① 重建快照 —— _tick_portals 读的是 current_snapshot，不重建的话英雄的
##      teleporting 永远进不了快照，阵会一直停在「待机」（第一版八张图全是 0.00）；
##   ② 推进单位视图，让英雄真的站到阵上；
##   ③ 推进传送阵状态机。
func _advance(seconds: float) -> void:
	var step := 1.0 / 60.0
	var left := seconds
	while left > 0.0:
		var dt: float = minf(step, left)
		arena.current_snapshot = arena.sim.snapshot_for(arena.local_team)
		arena._sync_units(arena.current_snapshot, dt)
		arena._tick_portals(dt)
		left -= dt
		await process_frame

func _place(eye: Vector3, target: Vector3, fov := 50.0) -> void:
	# arena 自己每帧都会重算相机，所以机位只在拍之前摆一次，靠 render_target 立即取帧。
	arena.camera.fov = fov
	arena.camera.position = eye
	arena.camera.look_at(target, Vector3.UP)

## 摆到某座阵的斜上方。偏移量按阵盘半径给，换机位不必重算。
func _look_at_pad(pad: Dictionary, spread := 1.0, height := 1.0) -> void:
	var center: Vector2 = pad.pos
	_place(
		Vector3(center.x + 7.4 * spread, 6.4 * height, center.y + 8.6 * spread),
		Vector3(center.x, 1.0, center.y),
		50.0
	)

## 直接摆引导状态，不依赖按键时序 —— 按键会被「是否站在阵上」这类前置条件拦住。
func _begin_channel(pad: Dictionary, remaining: float) -> void:
	var hero: Dictionary = arena.sim.get_hero_by_player("p1")
	hero.pos = pad.pos
	hero.teleporting = true
	hero.teleport_timer = remaining
	hero.teleport_total = 2.5
	hero.teleport_cd = 0.0
	hero.teleport_from = pad.pos
	hero.teleport_pad = str(pad.get("id", ""))

func _clear_channel() -> void:
	var hero: Dictionary = arena.sim.get_hero_by_player("p1")
	hero.teleporting = false
	hero.teleport_timer = 0.0
	hero.teleport_total = 0.0

func _run() -> void:
	while not arena.build_complete:
		await process_frame
	await create_timer(0.6).timeout
	arena.hud.visible = false
	# 关掉 arena 自己的 _process：它每帧都会按相机跟随重算机位，也会重建相机目标，
	# 于是工具摆的机位在下一帧就被覆盖（第一版的截图全拍成了"贴着英雄的地面"）。
	# 关掉之后由 _advance() 手动推进我们关心的两段。
	arena.set_process(false)
	var pad: Dictionary = MapLayout.TELEPORT_PADS[0]

	# ① 待机 · 近景
	_look_at_pad(pad, 1.0, 1.0)
	await _advance(0.5)
	await _shot("portal_idle")

	# ①b 待机 · 远景：21 米机位（默认对局视角）下还认不认得出这是设施
	_place(Vector3(pad.pos.x + 9.0, 21.0, pad.pos.y + 15.0), Vector3(pad.pos.x, 0.0, pad.pos.y), 55.0)
	await _advance(0.3)
	await _shot("portal_idle_far")

	# ② 起手：刚读上，进度接近 0
	_begin_channel(pad, 2.42)
	_look_at_pad(pad, 0.86, 0.72)
	await _advance(0.5)
	await _shot("portal_charge_start")

	# ③ 读条过半
	_begin_channel(pad, 1.25)
	await _advance(0.9)
	await _shot("portal_charge_mid")

	# ③b 读条将满
	_begin_channel(pad, 0.35)
	await _advance(0.7)
	await _shot("portal_charge_late")

	# ④a 抵达：闪光照亮整块石台
	_clear_channel()
	_look_at_pad(pad, 1.0, 1.0)
	await _advance(0.3)
	arena._flash_portal_at(pad.pos)
	await _advance(0.1)
	await _shot("portal_arrive")

	# ④b 打断：符文裂开
	await _advance(0.8)
	arena._shatter_portal_at(pad.pos)
	await _advance(0.06)
	await _shot("portal_break")

	# ⑤ 总览：两座阵要能同时看到，且配色与河道之灵分得开
	_place(Vector3(-74.0, 46.0, -74.0), Vector3(-30.0, 0.0, -30.0), 46.0)
	await _advance(0.3)
	await _shot("portal_sheet")

	quit()
