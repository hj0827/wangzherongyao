extends SceneTree

# 技能特效画廊（验收工具，入库）。
#
#   powershell -ExecutionPolicy Bypass -File godot\tools\shot_offscreen.ps1 tools\skill_fx_shot.gd
#
# 别直接 `godot --path godot --script ...` 跑：它要开窗口，会在用户桌面上闪一下。
# shot_offscreen.ps1 把窗口建在隐藏桌面上，产物路径不变。
#
# 给 17 种技能 kind 各拍一张同一机位、同一落点的特写，再拼成一张总览图，
# 用来回答一个问题：**不看颜色，能不能认出这是哪个技能？**
#
# 为什么需要它：`test_skill_signature.gd` 只能证明"配方参数两两不同"，
# 证明不了"画面上真的看得出不同"。差距文档 §7.5 的 G4 视觉关要求并排对比。
#
# 产物（不入库，落 godot/shots/）：
#   skill_fx_<kind>.png      单技能特写
#   skill_fx_sheet.png       5×4 总览拼图
#
# **机位必须交给 arena 自己管**：`_process` 每帧都在 `_update_camera()` 里
# 重设 camera.position / look_at，手工摆相机会被下一帧覆盖 ——
# 这样拍出来 17 张全是同一个空地，看起来"没有任何特效"，但其实是特效在镜头外。
# 所以这里改为：把本地英雄摆到干净空地上 + 设 zoom + 让 arena 跟拍，
# 特效则围绕**英雄当前位置**生成。

const Arena = preload("res://scripts/game/arena.gd")
const SkillFx = preload("res://scripts/game/skill_fx.gd")

const KINDS := [
	"slash", "spin", "dash", "leap_slam", "burst",
	"line", "slow", "meteor_storm", "quake", "charge",
	"shield", "taunt_aura", "arrow", "aoe_shot", "haste",
	"arrow_barrage", "evade",
]

const SHOT_SIZE := Vector2i(520, 380)
const CELLS_PER_ROW := 5
const ZOOM := 6.8
# 落点相对英雄的偏移。屏幕右 = 世界 -X（蓝方相机朝 +Y 看），
# 所以 x 取负、y 取正才是「画面上偏右上」，特效不会被压在画面左下角。
const AIM_OFFSET := Vector2(-1.2, 1.0)

var viewport: SubViewport
var arena: Node3D
var _hero: Dictionary = {}
var _spot := Vector2.ZERO

func _initialize() -> void:
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, true)
	DisplayServer.window_set_position(Vector2i(5200, 3200))
	viewport = SubViewport.new()
	viewport.size = SHOT_SIZE
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	_run()

func _wait(frames: int) -> void:
	for i in frames:
		await process_frame

func _run() -> void:
	arena = Arena.new()
	arena.configure({
		"config": {
			"mode": "duel",
			"humans": [{"id": "p1", "name": "苍刃", "team": "blue", "hero_type": "blade"}],
			"bot_fill": false,
			"bot_ai": false,
		},
		"authoritative": true,
		"local_owner": "p1",
	})
	viewport.add_child(arena)
	while not arena.build_complete:
		await process_frame
	await _wait(8)
	if arena.hud != null:
		arena.hud.visible = false
	_hero = arena.sim.get_hero_by_player("p1")
	# 中路靠近河道的直段路面：平整、没有墙/草丛/野怪，特效不被场景抢读。
	# 不要放在桥心或河道上 —— 特写里会被水面和桥栏切碎。
	_spot = Vector2(10.0, -10.0)
	arena.zoom = ZOOM
	await _pin(20)
	if arena.camera == null:
		print("FXSHOT 没有相机，放弃")
		quit(1)
		return
	print("FXSHOT camera=%s zoom=%.1f hero=%s" % [
		str(arena.camera.position), arena.zoom, str(_hero.get("pos", Vector2.ZERO))])

	var shots: Array[Image] = []
	# 对照组：**不放任何技能**。用来区分「画面上那些环是我的特效」还是
	# 「本来就有的攻击范围环 / 防御塔范围环」。没有这张图，视觉验收会把自己的
	# 场景元素当成技能效果，也可能反过来把特效当成场景。
	await _capture_kind("")
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	viewport.get_texture().get_image().save_png(
		ProjectSettings.globalize_path("res://shots/skill_fx_control.png"))
	print("FXSHOT control      （不放技能，作为对照）")

	for kind in KINDS:
		await _capture_kind(str(kind))
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		var img: Image = viewport.get_texture().get_image()
		img.save_png(ProjectSettings.globalize_path("res://shots/skill_fx_%s.png" % str(kind)))
		print("FXSHOT %-14s sig=%s" % [str(kind), str(SkillFx.recipe(str(kind)).get("signature", ""))])
		shots.append(img)

	_build_sheet(shots)
	print("FXSHEET done kinds=", shots.size())
	quit(0)

# 每帧把英雄钉回空地上：bot 之外的 AI 不会动它，但 sim 的走路惯性/施法位移会，
# 位置一漂镜头就跟着漂，17 张图机位就不一致了。
func _pin(frames: int) -> void:
	for i in frames:
		if not _hero.is_empty():
			_hero["pos"] = _spot
			_hero["moving"] = false
			_hero["hp"] = float(_hero.get("max_hp", 1000.0))
		await process_frame

func _capture_kind(kind: String) -> void:
	# 清空上一轮：**先把节点藏起来再清数组**。
	# 只 clear() 数组是不够的 —— 节点仍然 visible=true 停在上一张的位置上，
	# 于是每张图都会叠上前几个技能的"鬼影"。
	# 注意 `_decal_active` 存的是 Dictionary（含 node/time），不是节点本身，
	# 必须取出 "node"：直接当节点用不会报错，只会静默地一张都没藏住，
	# 表现为"每张图上叠着七八圈同心圆"，很容易被误读成"我的环特效画多了"。
	for pool in [arena._ring_active, arena._slash_active, arena._hit_particles_active,
			arena._tracer_active, arena._trail_active, arena._lance_active, arena._decal_active]:
		for entry in pool:
			var node: Variant = entry.get("node") if entry is Dictionary else entry
			if not is_instance_valid(node):
				continue
			node.visible = false
			if node is GPUParticles3D:
				(node as GPUParticles3D).emitting = false
		pool.clear()
	arena._fx_queue.clear()
	if kind == "":
		# 对照组：只清场、不生成，直接拍。
		await _pin(6)
		return
	var aim := _spot + AIM_OFFSET
	arena._spawn_skill_fx({
		"hero_id": -1,
		"slot": "q",
		"hero_type": "blade",
		"kind": kind,
		"from": _spot,
		"aim": aim,
		"recipe": SkillFx.recipe(kind),
	})
	# 拍在特效"最满"的那一帧：延迟二次爆（0.12~0.3s）还来得及出现。
	# 30fps 下 6 帧 ≈ 0.2s，正好让大多数延迟爆落地。
	await _pin(6)

func _build_sheet(shots: Array[Image]) -> void:
	if shots.is_empty():
		return
	var rows := int(ceil(float(shots.size()) / float(CELLS_PER_ROW)))
	var sheet := Image.create(
		SHOT_SIZE.x * CELLS_PER_ROW, SHOT_SIZE.y * rows, false, Image.FORMAT_RGBA8
	)
	sheet.fill(Color(0.06, 0.07, 0.09, 1.0))
	for index in shots.size():
		var col := index % CELLS_PER_ROW
		var row := index / CELLS_PER_ROW
		sheet.blit_rect(shots[index], Rect2i(Vector2i.ZERO, SHOT_SIZE),
			Vector2i(col * SHOT_SIZE.x, row * SHOT_SIZE.y))
	sheet.save_png(ProjectSettings.globalize_path("res://shots/skill_fx_sheet.png"))
	print("FXSHEET sheet ", sheet.get_size())
