extends SceneTree

# 野怪 / 小兵普攻特效画廊（验收工具，入库）。
#
#   powershell -ExecutionPolicy Bypass -File godot\tools\shot_offscreen.ps1 tools\unit_attack_shot.gd --fixed-fps 30
#
# 别直接 `godot --path godot --script ...` 跑：它要开窗口，会在用户桌面上闪一下。
# shot_offscreen.ps1 把窗口建在隐藏桌面上（已自动带 --audio-driver Dummy），产物路径不变。
#
# 回答一个 `test_monster_attack_fx` 答不了的问题：**这些配方画出来，玩家分得清吗？**
# 测试只能证明「参数两两不同」「渲染层真的读了 shape」，证明不了「野猪和狼在
# 20 米机位下一眼能分开」。差距文档 §7.2 的 F3/F4 要求并排对比。
#
# 做法：逐个物种触发**真实的 monster_attack / minion_attack 事件**（走
# `_process_events`，不是直接调 `_spawn_*`），每格同一机位、同一落点拍在特效最满的一帧。
#
# 产物（shots/ 已忽略，不入库）：
#   unit_attack_<key>.png   单个物种特写
#   unit_attack_sheet.png   4×3 总览
#   unit_attack_control.png 对照组（不放任何攻击）
#
# ---------------------------------------------------------------------------
# 三个必须记住的机位坑（每一版都是实拍改出来的，别凭直觉改回去）
# ---------------------------------------------------------------------------
# ① **必须关掉 arena 自己的相机**。`arena._process()` 每帧都会 `_update_camera()`
#    重设 camera.position / look_at；不关掉的话手工摆的相机会被下一帧覆盖，
#    拍出来是一排空地（`skill_fx_shot.gd` 的注释里也记着这一条）。
#    关掉之后这个工具自己建一台固定机位，"同一机位"才是真的同一机位。
# ② **必须 `--fixed-fps 30`**。刀光只有 0.12~0.22 秒，而这台机器（Quadro K420）
#    真实一帧可能 0.15 秒以上 —— 不固定帧率时按快门那一刻弧已经淡完，
#    12 张图全是空地面，看起来像「配方没生效」。
# ③ **每格都要清场并把节点还回池**。池节点不主动隐藏就不会淡出，只 clear 数组
#    会让上一格的弧/环/残留一直停在原地，后半张对照图变成「前几个物种叠在一起」；
#    而不归还池会让池越用越少，「池空抢占」退化成抢同一个节点。
#
# 机位是**俯视 51°**（与实战 `CAMERA_PITCH_*` 同源），因为玩家看到的就是这个角度：
# 平视特写里好看的弧，在俯视下可能缩成一条线。

const Arena = preload("res://scripts/game/arena.gd")
const ArenaLook = preload("res://scripts/game/arena_look.gd")

# 一行一组。`event` 是喂给 _process_events 的**真实事件结构**（与 sim 发出的字段一致）。
const CASES := [
	{"key": "minion_melee", "label": "近战兵", "event": {
		"type": "minion_attack", "minion_type": "melee", "team": "blue"}},
	{"key": "minion_ranged", "label": "远程兵", "event": {
		"type": "minion_attack", "minion_type": "ranged", "team": "blue"}},
	{"key": "minion_cannon", "label": "炮车", "event": {
		"type": "minion_attack", "minion_type": "cannon", "team": "blue"}},
	{"key": "minion_super", "label": "超级兵", "event": {
		"type": "minion_attack", "minion_type": "super", "team": "blue"}},
	{"key": "monster_wolf", "label": "双狼（双爪）", "event": {
		"type": "monster_attack", "monster_type": "wolf", "team": "neutral"}},
	{"key": "monster_boar", "label": "三猪（扬土）", "event": {
		"type": "monster_attack", "monster_type": "boar", "team": "neutral"}},
	{"key": "monster_lizard", "label": "蜥蜴（突咬）", "event": {
		"type": "monster_attack", "monster_type": "lizard", "team": "neutral"}},
	{"key": "monster_bird", "label": "红鸟（双击）", "event": {
		"type": "monster_attack", "monster_type": "bird", "team": "neutral"}},
	{"key": "monster_buff", "label": "BUFF 石像", "event": {
		"type": "monster_attack", "monster_type": "wolf", "buff_type": "red",
		"camp_id": "red_buff_blue_side", "team": "neutral"}},
	{"key": "monster_spirit", "label": "河道之灵（水花）", "event": {
		"type": "monster_attack", "monster_type": "spirit", "team": "neutral"}},
	{"key": "monster_boss", "label": "暴君（砸地）", "event": {
		"type": "monster_attack", "monster_type": "orc", "objective": true,
		"objective_id": "tyrant", "team": "neutral"}},
	{"key": "tower_shot", "label": "防御塔（对照）", "event": {
		"type": "structure_attack", "source_type": "tower", "tier": "outer", "team": "red"}},
]

const SHOT_SIZE := Vector2i(520, 380)
const CELLS_PER_ROW := 4
# 出手者所在的世界点。取地图中线附近的干净路面（没有墙/草丛/野怪抢读）。
const ORIGIN := Vector2(10.0, -10.0)
# 落点相对出手者：朝画面右下（屏幕右 = 世界 -X，屏幕下 = 世界 -Y）。
const AIM_OFFSET := Vector2(-1.15, -0.95)
# 固定机位。俯角 51°、距离 9.5 米 —— 与实战同一个读图角度，
# 但足够近，能看清弧的厚度与扬尘的颗粒。
const CAM_DISTANCE := 9.5
const CAM_PITCH_DEG := 51.0
const CAM_YAW_DEG := 45.0
# 拍第几帧。固定 30fps 下 2 帧 = 0.066s，弧刚张开、火星还在飞。
const SHOT_FRAME := 2

var viewport: SubViewport
var arena: Node3D
var camera: Camera3D
var _shots: Array[Image] = []

func _initialize() -> void:
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
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
	# ① 关掉 arena 的相机与 HUD 刷新：之后所有机位都由本工具说了算。
	arena.set_process(false)
	arena.set_physics_process(false)
	_build_camera()
	# 把英雄挪出镜头（它还带着血条与范围环，会挡在特效前面）。
	var hero: Dictionary = arena.sim.get_hero_by_player("p1")
	if not hero.is_empty():
		hero["pos"] = ORIGIN + Vector2(40.0, 40.0)
	for node in [arena.attack_range_ring, arena.move_marker, arena.aim_marker]:
		if node != null:
			(node as Node3D).visible = false
	await _wait(4)
	print("UNITSHOT camera=%s origin=%s" % [str(camera.global_position), str(ORIGIN)])

	# 对照组：**不放任何攻击**。没有它，无法区分「画面里那些环是我的特效」
	# 还是「场景里本来就有的东西」。
	await _clear_fx()
	await _wait(2)
	viewport.get_texture().get_image().save_png(
		ProjectSettings.globalize_path("res://shots/unit_attack_control.png"))
	print("UNITSHOT control（不放攻击，作为对照）")

	for entry in CASES:
		await _capture(str(entry.key), entry.event as Dictionary)

	_build_sheet()
	print("UNITSHEET done cases=", _shots.size())
	quit(0)

# 固定机位：俯视 51°，与实战同一读图角度；不动、不跟拍。
func _build_camera() -> void:
	camera = Camera3D.new()
	camera.fov = 42.0
	camera.near = 0.1
	camera.far = 400.0
	var pitch := deg_to_rad(CAM_PITCH_DEG)
	var yaw := deg_to_rad(CAM_YAW_DEG)
	var target := Vector3(ORIGIN.x, 0.75, ORIGIN.y)
	# 从目标点朝斜上方退开：yaw 决定方位，pitch 决定俯角。
	var offset := Vector3(
		-sin(yaw) * cos(pitch),
		sin(pitch),
		-cos(yaw) * cos(pitch)
	) * CAM_DISTANCE
	camera.position = target - offset
	# 让相机"看向原点"，而不是手动算欧拉角：俯角与朝向只有一个真身。
	camera.look_at(target, Vector3.UP)
	viewport.add_child(camera)
	camera.current = true

func _clear_fx() -> void:
	# [活动列表, 它的池]：借出的节点必须还原成池成员，否则池会越用越少，
	# 到后面几格「池空抢占」就退化成抢同一个节点，画面直接错乱。
	for pair in [
		[arena._slash_active, arena._slash_pool],
		[arena._ring_active, arena._ring_pool],
		[arena._tracer_active, arena._tracer_pool],
		[arena._trail_active, arena._trail_pool],
		[arena._lance_active, arena._lance_pool],
		[arena._hit_particles_active, arena._hit_particles_pool],
	]:
		_return_pool(pair[0], pair[1])
	# 残留的条目是 Dictionary（含 node/time），形状和其它池不一样，单独走一趟。
	_return_pool(_decal_nodes(), arena._decal_pool)
	arena._fx_queue.clear()
	await process_frame

func _decal_nodes() -> Array:
	var out: Array = []
	for entry in arena._decal_active:
		var node: Variant = entry.get("node") if entry is Dictionary else entry
		if is_instance_valid(node):
			out.append(node)
	arena._decal_active.clear()
	return out

func _return_pool(active: Array, pool: Array) -> void:
	for entry in active:
		var node: Variant = entry.get("node") if entry is Dictionary else entry
		if not is_instance_valid(node):
			continue
		var item := node as Node3D
		if item != null:
			item.visible = false
		if node is GPUParticles3D:
			(node as GPUParticles3D).emitting = false
		var tween: Variant = node.get_meta("tween", null)
		if tween is Tween and (tween as Tween).is_valid():
			(tween as Tween).kill()
		if not pool.has(node):
			pool.append(node)
	active.clear()

func _capture(key: String, base_event: Dictionary) -> void:
	# ③ 每格清场（见文件头的第 ③ 条）。
	await _clear_fx()
	var from := ORIGIN
	var aim := ORIGIN + AIM_OFFSET
	var event := base_event.duplicate(true)
	event["x"] = from.x
	event["y"] = from.y
	event["target_x"] = aim.x
	event["target_y"] = aim.y
	event["source"] = 900
	event["target"] = 901
	event["target_type"] = "hero"
	# 走真实事件入口：这样踩到的是 _process_events 的分发与早退逻辑，
	# 而不是「我直接调了 _spawn_*」——后者会漏掉整条接线。
	arena._process_events([event])
	# ② 固定帧率下等两帧（见文件头的第 ② 条）。用 frame_post_draw 而不是
	# process_frame：前者在"这一帧画完之后"返回，正好拿到刚画好的那一帧。
	for i in SHOT_FRAME:
		await RenderingServer.frame_post_draw
	# 自检：这一格到底有没有把特效画出来。`lit=0` 就是快门太晚 / 配方没生效，
	# 两种原因在图上看起来一样（都是空地面），必须在日志里分得开。
	var lit := 0
	for slash in arena._slash_active:
		var material := slash.material_override as StandardMaterial3D
		if slash.visible and material != null and material.albedo_color.a > 0.05:
			lit += 1
	print("UNITSHOT %-16s slash=%d lit=%d ring=%d decal=%d" % [
		key, arena._slash_active.size(), lit, arena._ring_active.size(), arena._decal_active.size()])
	viewport.get_texture().get_image().save_png(
		ProjectSettings.globalize_path("res://shots/unit_attack_%s.png" % key))
	_shots.append(viewport.get_texture().get_image())

func _build_sheet() -> void:
	if _shots.is_empty():
		return
	var rows := int(ceil(float(_shots.size()) / float(CELLS_PER_ROW)))
	var sheet := Image.create(
		SHOT_SIZE.x * CELLS_PER_ROW, SHOT_SIZE.y * rows, false, Image.FORMAT_RGBA8
	)
	sheet.fill(Color(0.06, 0.07, 0.09, 1.0))
	for index in _shots.size():
		var col := index % CELLS_PER_ROW
		var row := index / CELLS_PER_ROW
		sheet.blit_rect(_shots[index], Rect2i(Vector2i.ZERO, SHOT_SIZE),
			Vector2i(col * SHOT_SIZE.x, row * SHOT_SIZE.y))
	sheet.save_png(ProjectSettings.globalize_path("res://shots/unit_attack_sheet.png"))
	print("UNITSHEET sheet ", sheet.get_size())
