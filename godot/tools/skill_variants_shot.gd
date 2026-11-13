extends SceneTree

# 英雄技能变体对照画廊（入库工具）：把「共用 kind 的两个英雄」各拍一张，
# 左右并排成一行，用来判断「不看颜色、只看形状，能不能分出是谁的技能」。
#
# 为什么需要单独一个工具：`skill_fx_shot.gd` 是按 kind 出图的（17 张），
# 它证明不了「星璃 Q 和墨鸦 W 长得不一样」—— 那是同一张图。这一份按
# (hero, kind) 成对出图，并把双方的名字与签名烧在图形上没法做（无字体），
# 所以靠**固定行序**对照：每行 = 一对共用 kind，左 = 第一个人，右 = 第二个人。
#
# 用法（必须走隐藏桌面，见 AGENTS.md 环境硬约束）：
#   powershell -ExecutionPolicy Bypass -File godot\tools\shot_offscreen.ps1 tools\skill_variants_shot.gd
# 产物：godot/shots/skill_variants.png（3 行 × 2 列对照图）
#      godot/shots/skill_variant_<hero>_<kind>.png（单张）

const Arena = preload("res://scripts/game/arena.gd")
const SkillFx = preload("res://scripts/game/skill_fx.gd")

const CELL := Vector2i(620, 420)
const AIM_OFFSET_NEAR := Vector3(0.0, 0.0, 2.6)
# 施法点：和 `skill_fx_shot.gd` 同一个落点（`(10, -10)` 的河道边草地）。
#
# 踩过两次坑，都是「背景选错 → 误以为变体没生效」：
#   ① 中路石板正中央：石板 albedo 接近 0.9，加法混合的特效被高光整个吃掉；
#   ② 河道水面：水面 shader 本身就是亮青色，青系技能（墨鸦 charge 的冷白）
#      完全看不见。
# 结论：验收技能必须站在**中低亮度背景**上，否则读的是背景不是技能。
const SPOT := Vector3(10.0, 0.0, -10.0)
const AIM_OFFSET := Vector3(0.0, 0.0, 3.6)

# 每行一对：共用同一个 kind、但应该长得不一样的两个英雄。
# 顺序就是对照图的阅读顺序，改顺序等于改验收口径 —— 测试会核对这张表
# 与 SkillFx.HERO_VARIANTS 一致（见 test_hero_skill_variants）。
const PAIRS := [
	{"kind": "burst", "left": "mage", "right": "assassin"},
	{"kind": "charge", "left": "tank", "right": "assassin"},
	{"kind": "leap_slam", "left": "blade", "right": "assassin"},
]

var arena: Node3D
var viewport: SubViewport
var camera: Camera3D
var _hero: Dictionary = {}

func _initialize() -> void:
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	DisplayServer.window_set_position(Vector2i(5200, 3200))
	Engine.max_fps = 15
	viewport = SubViewport.new()
	viewport.size = CELL
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	_run()

func _build_arena() -> void:
	var config := {
		"mode": "duel",
		"humans": [{"id": "p1", "name": "观察者", "team": "blue", "hero_type": "blade"}],
		"bot_fill": false,
		"bot_ai": false,
	}
	arena = Arena.new()
	arena.configure({"config": config, "authoritative": true, "local_owner": "p1"})
	viewport.add_child(arena)
	while not arena.build_complete:
		await process_frame
	await create_timer(0.4).timeout
	arena.hud.visible = false
	# 机位交给 arena 自己管：`_process` 每帧在 `_update_camera()` 里重设
	# camera.position / look_at，手工摆相机会被下一帧覆盖（`skill_fx_shot.gd`
	# 的文件头也写着这条）。做法是把本地英雄钉在施法点上，相机自然跟过去。
	camera = arena.camera
	if camera == null:
		printerr("arena.camera 为空：无法出图")
		quit(1)
		return
	_hero = arena.sim.get_hero_by_player("p1")
	arena.zoom = 12.0
	# 机位交给 arena：把英雄钉在草地上，`_update_camera()` 会把镜头带过去。
	# `_pin` 每帧都写一次 pos —— sim 的走路惯性/施法位移会把它推开。
	await _pin(14)

func _clear_fx() -> void:
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

func _pin(frames: int) -> void:
	for i in frames:
		if not _hero.is_empty():
			_hero["pos"] = Vector2(SPOT.x, SPOT.z)
			_hero["moving"] = false
			_hero["hp"] = float(_hero.get("max_hp", 1000.0))
		await process_frame

func _settle(frames: int) -> void:
	for i in frames:
		await process_frame

func _shoot(hero_type: String, kind: String) -> Image:
	_clear_fx()
	# 用**英雄当前真实位置**当施法点：arena 的相机跟着英雄走，
	# 硬编码 SPOT 会和镜头错开（第一版技能全落在画面外）。
	var origin := SPOT
	if not _hero.is_empty():
		var pos: Vector2 = _hero.get("pos", Vector2(SPOT.x, SPOT.z))
		origin = Vector3(pos.x, 0.0, pos.y)
	# 走**渲染层真正用的入口**：requests() 会用 recipe_for 取英雄变体。
	# 这里如果直接调 recipe(kind)，拍出来就还是通用配方 —— 验收图会骗人。
	var requests := SkillFx.requests([{
		"type": "skill", "slot": "q", "hero_type": hero_type, "kind": kind,
		"hero": -1, "team": "blue",
		"x": origin.x, "y": origin.z,
		"aim_x": origin.x + AIM_OFFSET.x, "aim_y": origin.z + AIM_OFFSET.z,
	}])
	var request: Dictionary = requests[0] if not requests.is_empty() else {}
	if request.is_empty():
		printerr("no request for ", hero_type, " / ", kind)
		return Image.create_empty(CELL.x, CELL.y, false, Image.FORMAT_RGBA8)
	request["from"] = Vector2(origin.x, origin.z)
	request["aim"] = Vector2(origin.x + AIM_OFFSET.x, origin.z + AIM_OFFSET.z)
	arena._spawn_skill_fx(request)
	# 30fps 下 7 帧 ≈ 0.23s：延迟二次爆（0.08~0.16s）已经落地，主环还没散。
	await _settle(5)
	await RenderingServer.frame_post_draw
	var image: Image = viewport.get_texture().get_image()
	print("VARSHOT %-9s %-10s sig=%s" % [
		hero_type, kind, str(request.get("recipe", {}).get("signature", ""))])
	return image

func _run() -> void:
	await _build_arena()
	var sheet := Image.create_empty(CELL.x * 2, CELL.y * PAIRS.size(), false, Image.FORMAT_RGBA8)
	sheet.fill(Color(0.05, 0.06, 0.08, 1.0))
	for row in PAIRS.size():
		var pair: Dictionary = PAIRS[row]
		var columns := [pair["left"], pair["right"]]
		for column in 2:
			var hero_type := str(columns[column])
			var kind := str(pair["kind"])
			var image := await _shoot(hero_type, kind)
			image.save_png(ProjectSettings.globalize_path(
				"res://shots/skill_variant_%s_%s.png" % [hero_type, kind]))
			sheet.blit_rect(image, Rect2i(Vector2i.ZERO, CELL),
				Vector2i(column * CELL.x, row * CELL.y))
	sheet.save_png(ProjectSettings.globalize_path("res://shots/skill_variants.png"))
	print("VARSHOT sheet ", sheet.get_size())
	quit(0)
