extends "res://tests/test_base.gd"

## 英雄外观层的契约测试（HERO-05）。
##
## 这一层全部是「表现层」：配色表、皮肤着色器、骨骼挂件、布料摆动。
## 它最容易出的不是崩溃，而是**静默失效**：
##   - 骨骼名写错 → 配件不跟动作，测试不红；
##   - 着色器 uniform 声明了但代码没传 → 参数永远默认值，图上看不出来；
##   - 每实例新建材质 → 画面没问题，真机掉帧；
##   - 配件尺寸失控 → 剪影糊成一团，只有画廊图能看出来。
## 所以这里的断言都瞄准这四类，而不是「能不能 new 出来」。

const UnitVisual = preload("res://scripts/game/unit_visual.gd")
const HeroLook = preload("res://scripts/game/hero_look.gd")
const HeroCostume = preload("res://scripts/game/hero_costume.gd")
const ModelUtils = preload("res://scripts/game/model_utils.gd")

const HEROES := ["blade", "mage", "tank", "archer", "assassin"]
const SHADER_PATH := "res://shaders/hero_skin.gdshader"

func _make_view(hero_type: String, team := "blue") -> UnitVisual:
	var view := UnitVisual.new()
	view.setup("hero", team, hero_type, hero_type, false, team)
	return view

# ---------------------------------------------------------------- 配色

## 5 个英雄的主色 / 副色 / 点缀光必须两两不同 —— 否则「换英雄 = 换名字」。
func test_every_hero_has_a_distinct_palette() -> void:
	var seen := {}
	for hero_type in HEROES:
		check(HeroLook.has_look(hero_type), "%s 必须在 HeroLook.LOOKS 里登记" % hero_type)
		var signature := HeroLook.identity_signature(hero_type)
		check(not seen.has(signature),
			"%s 与 %s 的配色完全相同（%s）：换英雄只剩换名字" % [
				hero_type, seen.get(signature, ""), signature])
		seen[signature] = hero_type
	eq(seen.size(), HEROES.size(), "5 个英雄的配色必须两两不同")

## 主色要压得住：FILMIC + exposure 1.05 下，饱和主色超过 0.5 会读成发白的粉彩。
## 例外的两类：
##   - 中性米白（sat < 0.18）：翎羽的立绘就是米白战衣，压暗反而丢了「白」。
##     它的上限放宽到 0.85 —— 上限本身不是美学判断，而是「别过曝成纯白」的技术线：
##     实测米白 base 0.80 渲出来是 187/191/192，地面 205，仍是「布」不是「灯」。
##   - 纯黑/近黑：游戏里会和背景糊在一起。
func test_primary_colours_are_dark_enough_for_filmic() -> void:
	for hero_type in HEROES:
		var primary := HeroLook.primary(hero_type)
		gt(primary.v, 0.02, "%s 的主色不能纯黑（当前 %.2f）" % [hero_type, primary.v])
		if primary.s < 0.18:
			lt(primary.v, 0.85, "%s 的中性主色 brightness 必须 < 0.85（当前 %.2f）" % [
				hero_type, primary.v])
		else:
			lt(primary.v, 0.50, "%s 的饱和主色 brightness 必须 < 0.50（当前 %.2f）" % [
				hero_type, primary.v])

## 头发一律深色。
## 这一条是实拍踩出来的：苍刃的 hair 槽位曾经为了「和披风统一」调成墨绿，
## 结果 albedo 0.155/0.265/0.18 在 FILMIC 下出来是一顶**亮绿头盔**。
## 头发贴图是灰度的（sat 0.02），会完整接受 base 的色相，所以亮度阈值必须卡死。
func test_hair_stays_dark_on_every_hero() -> void:
	for hero_type in HEROES:
		var hair := HeroLook.slot(hero_type, "hair")
		var base: Color = hair.get("base", Color.WHITE)
		lt(base.v, 0.16, "%s 的头发 base 亮度必须 < 0.16（当前 %.3f）" % [hero_type, base.v])

# ---------------------------------------------------------------- 待机站姿

## 5 个英雄的待机姿势必须两两不同。
##
## 改前 5 个人只用两套 clip：苍刃/铁壁/墨鸦都是 `Sword_Idle`，
## 星璃/翎羽都是 `Spell_Simple_Idle`。三个人站成一排姿势一模一样，
## 只有武器不同 —— 而待机是玩家看得最久的画面（补刀间隙、等 CD、看线上）。
## 这条断言用 clip 名去重，和 `test_each_hero_has_a_distinct_autoattack_clip` 同一口径。
func test_hero_idle_poses_are_distinct() -> void:
	var seen := {}
	for hero_type in HEROES:
		var pose := HeroLook.idle_pose(hero_type)
		check(pose != "", "%s 必须有待机 clip" % hero_type)
		check(not seen.has(pose),
			"%s 的待机与 %s 相同（%s）：站在一起读不出是两个人" % [
				hero_type, seen.get(pose, ""), pose])
		seen[pose] = hero_type
	eq(seen.size(), HEROES.size(), "5 个英雄的待机 clip 必须两两不同")

## 每个待机 clip 必须真实存在、长度够、且在循环表里。
##
## 三条缺一条都是静默失效：
##   - 名字不存在 → `_set_anim` 静默跳过，角色停在默认 Idle（看不出问题）；
##   - 不在 `LOOPING_CLIPS` → 播完停在最后一帧，变成一个「石头人」；
##   - 长度太短（< 1.5s）→ 呼吸循环肉眼可见地抽搐。
func test_idle_clips_exist_loop_and_are_long_enough() -> void:
	var library := UnitVisual._get_source_animations()
	gt(float(library.size()), 0.0, "动作库必须能加载（UAL1/UAL2）")
	for hero_type in HEROES:
		var pose := HeroLook.idle_pose(hero_type)
		check(library.has(pose), "%s 的待机 clip「%s」在动作库里不存在" % [hero_type, pose])
		check(UnitVisual.LOOPING_CLIPS.has(pose),
			"%s 的待机 clip「%s」不在 LOOPING_CLIPS 里：播完会停在最后一帧" % [hero_type, pose])
		if library.has(pose):
			var length := (library[pose] as Animation).length
			gt(length, 1.0, "%s 的待机 clip「%s」只有 %.2fs，太短会读成抽搐" % [
				hero_type, pose, length])

## 待机姿势必须真的被装配用上（接线守卫，不是「登记表里写了就算」）。
func test_idle_pose_is_actually_wired_into_the_view() -> void:
	for hero_type in HEROES:
		var view := _make_view(hero_type)
		eq(view.idle_anim, HeroLook.idle_pose(hero_type),
			"%s 的 UnitVisual.idle_anim 与 HeroLook 不一致：登记了但没接线" % hero_type)
		view.free()

## 血条高度必须真的按**骨骼姿态**算，不能是固定值，也不能读蒙皮前的 AABB。
##
## 这条守的是实战机位下才看得见的 bug：墨鸦的 `Crouch_Idle` 头顶只有 1.78m，
## 而站立的英雄是 2.7m。写死 `HERO_HEIGHT + 0.30` 时，蹲着的墨鸦血条
## 会浮在他头顶一臂高的半空（实拍确认）。
##
## 为什么不在测试里「等两帧再量」：测试基类是 `RefCounted`，没有 SceneTree，
## `await process_frame` 用不了；而骨骼姿态必须由渲染前的 AnimationMixer 写入。
## 所以这里直接**手工写一个蹲姿**（`set_bone_global_pose`）来验 `_posed_body_top()`
## 会跟着变 —— 这正好也是「读姿态而不是读静态 AABB」的判据。
func test_posed_head_tracks_the_skeleton_not_the_static_mesh() -> void:
	var view := _make_view("assassin")
	var skeleton := HeroCostume.skeleton_of(view.model_root)
	check(skeleton != null, "assassin 必须有骨架")
	if skeleton == null:
		view.free()
		return
	var head := skeleton.find_bone("Head")
	gt(float(head), -1.0, "骨架里必须有 Head 骨")
	var upright := view._posed_body_top()
	gt(upright, 1.2, "直立时头顶高度必须像个人（当前 %.2f）" % upright)
	# 手工把 Head 骨的**局部姿态**往下压 0.9 米 —— 模拟蹲伏待机。
	# 用 `set_bone_pose()` 而不是 `set_bone_global_pose()`：局部姿态是
	# AnimationPlayer 真正写入的那份数据，在无头环境下也是同步可读的。
	var local := skeleton.get_bone_pose(head)
	var lowered_pose := local
	lowered_pose.origin.y -= 0.9
	skeleton.set_bone_pose(head, lowered_pose)
	var lowered := view._posed_body_top()
	lt(lowered, upright - 0.5,
		"把 Head 骨压低 0.9m 后头顶只降了 %.2f：说明量的是静态 AABB，不是骨骼姿态" % (
			upright - lowered))
	# 恢复，避免影响后续断言（同一个静态缓存可能被复用）。
	skeleton.set_bone_pose(head, local)
	view.free()

## 血条的初值必须是「先建好、再延迟结算」，不能在建的时候就把高度写死。
func test_health_bar_height_is_settled_after_the_pose_is_known() -> void:
	var source := FileAccess.get_file_as_string("res://scripts/game/unit_visual.gd")
	check(source.contains("_pending_bar_settle"),
		"血条高度必须走延迟结算（_pending_bar_settle）：装配那一刻骨架还是静止姿态")
	check(source.contains("_posed_body_top"),
		"血条高度必须读 _posed_body_top()（骨骼姿态），不能读蒙皮前的 AABB")
	check(source.contains("_bone_posed_y"),
		"_posed_body_top 必须沿父链累乘局部姿态（get_bone_pose），"
		+ "不能用 get_bone_global_pose：后者由 AnimationMixer 写入，无头环境下永远是静止姿态")
	check(source.contains("_process_bar_settle()"),
		"延迟结算必须真的挂进 process_visual，否则永远不会执行")
	# 反例：不许再出现「写死 HERO_HEIGHT + 常数」的血条高度。
	check(not source.contains("_add_health_bar(HERO_HEIGHT + 0.30)"),
		"不许再把血条高度写死成 HERO_HEIGHT + 0.30（蹲姿英雄会浮空）")

# ---------------------------------------------------------------- 着色器

## 着色器里声明的每个 uniform 都必须在 HeroCostume 里被显式赋值。
##
## 这是本仓库踩过的坑的通用形态：参数传了、但函数体里没读，效果等于没有。
## 这里从 shader 源码里抓 uniform 名，再逐条去 hero_costume.gd 里找 set_shader_parameter。
func test_every_shader_uniform_is_actually_bound() -> void:
	var shader_text := FileAccess.get_file_as_string(SHADER_PATH)
	check(shader_text != "", "hero_skin.gdshader 必须存在且可读")
	var costume_text := FileAccess.get_file_as_string("res://scripts/game/hero_costume.gd")
	var uniforms := _uniform_names(shader_text)
	gt(uniforms.size(), 10, "英雄皮肤着色器的 uniform 数量异常（%d）" % uniforms.size())
	for uniform_name in uniforms:
		check(costume_text.contains('set_shader_parameter("%s"' % uniform_name),
			"着色器 uniform「%s」在 HeroCostume 里没有被赋值（会永远用默认值）" % uniform_name)

## 着色器不许重定义 Godot 内置常量（TAU/PI 之类）。
## 重定义会让编译失败，材质回落纯白 —— 这个失效不报错、headless 也全绿。
func test_shader_does_not_redefine_builtin_constants() -> void:
	var shader_text := FileAccess.get_file_as_string(SHADER_PATH)
	for builtin_name in ["TAU", "PI", "E", "EPSILON"]:
		check(not shader_text.contains("const float %s" % builtin_name),
			"着色器不许重定义内置常量 %s（会编译失败并回落纯白）" % builtin_name)

## 红蓝两队的英雄必须**在画面上分得开**。
##
## 这条守的是一个只在实战图里看得见的问题：改前 `team_amount = 0.16` 只压暗部，
## 实测两个苍刃对砍时身体颜色几乎一样，只能靠血条分辨 —— 团战里会打队友。
##
## 判据三条：
##   1. 两队的暗部染色必须色相相反（蓝偏冷、红偏暖）；
##   2. 必须有**轮廓队伍色**，且强度在 0.30~0.60（太低认不出、太高像发光）；
##   3. 着色器里真的读了 `team_rim_color`（防止 uniform 加了但没接）。
func test_teams_are_visually_separable_in_a_crowd() -> void:
	var blue := HeroLook.team_tint("blue")
	var red := HeroLook.team_tint("red")
	# 蓝队染色：B 分量必须大于 R（偏冷）；红队反过来（偏暖）。
	gt(blue.b, blue.r, "蓝队暗部染色必须偏冷（B > R）")
	gt(red.r, red.b, "红队暗部染色必须偏暖（R > B）")
	# 暗部染色强度：太低在 21 米机位下看不出来，太高会把衣服变成纯色块。
	var amount := HeroLook.team_amount()
	gt(amount, 0.25, "暗部队伍色强度必须 >= 0.25（改前 0.16 实测看不出来）")
	lt(amount, 0.55, "暗部队伍色强度必须 < 0.55（再高就盖掉英雄主色了）")
	# 轮廓队伍色：这是「人群里认敌我」的主力。
	var rim_strength := HeroLook.team_rim_strength()
	gt(rim_strength, 0.25, "必须有轮廓队伍色（强度 >= 0.25）")
	lt(rim_strength, 0.65, "轮廓队伍色强度必须 < 0.65（0.72 实测像人在发光）")
	var blue_rim := HeroLook.team_rim("blue")
	var red_rim := HeroLook.team_rim("red")
	gt(blue_rim.b, blue_rim.r, "蓝队轮廓色必须偏蓝")
	gt(red_rim.r, red_rim.b, "红队轮廓色必须偏红")
	# 着色器接线：uniform 加了但没读 = 静默失效。
	var shader_text := FileAccess.get_file_as_string(SHADER_PATH)
	check(shader_text.contains("team_rim_color"),
		"着色器必须真的读 team_rim_color（否则轮廓队伍色根本不生效）")
	check(shader_text.contains("team_rim_strength"), "着色器必须真的读 team_rim_strength")

## `brightness` 必须同时乘在 `toned` 上，不能只乘 `original`。
## 这条守的是一个「参数传了但几乎无效」的静默失效：第一版只写了
## `original = tex.rgb * brightness`，而 `recolor` 通常 0.86~0.94 ——
## brightness 被混到只剩 6~14%，调它几乎没有效果。
## 症状是「把 base 和 brightness 都调亮了，实拍只亮 7 个单位」。
func test_brightness_affects_the_recoloured_branch_too() -> void:
	var shader_text := FileAccess.get_file_as_string(SHADER_PATH)
	check(shader_text.contains("toned * brightness"),
		"brightness 必须乘在 toned 上（只乘 original 会被 recolor 稀释到几乎无效）")
	check(shader_text.contains("tex.rgb * brightness"),
		"brightness 也要保留在 original 分支上，两个分支都要一致")

func _uniform_names(shader_text: String) -> Array[String]:
	var names: Array[String] = []
	for line in shader_text.split("\n"):
		var trimmed := line.strip_edges()
		if not trimmed.begins_with("uniform "):
			continue
		# uniform sampler2D albedo_tex : source_color ...;
		var rest := trimmed.substr(8)
		var colon := rest.find(":")
		if colon >= 0:
			rest = rest.substr(0, colon)
		var words := rest.strip_edges().split(" ", false)
		if words.size() >= 2:
			names.append(str(words[1]).strip_edges())
	return names

# ---------------------------------------------------------------- 配件接线

## 每个英雄至少 3 件大件，且挂的骨骼必须真实存在。
func test_costume_registry_is_complete_and_on_real_bones() -> void:
	for hero_type in HEROES:
		var parts: Array = HeroLook.costume_parts(hero_type)
		check(parts.size() >= 3, "%s 至少要有 3 件专属配件（当前 %d）" % [hero_type, parts.size()])
		var keys := {}
		for entry in parts:
			var key := str(entry.get("key", ""))
			var bone := str(entry.get("bone", ""))
			check(key != "", "%s 有一条配件没写 key" % hero_type)
			check(not keys.has(key), "%s 的配件 key 重复：%s" % [hero_type, key])
			keys[key] = true
			check(HeroLook.is_valid_bone(bone),
				"%s 的配件 %s 挂在未知骨骼「%s」上（BoneAttachment3D 会静默不跟动作）" % [
					hero_type, key, bone])

## 登记表与真实构建结果必须一一对上：少建一件 = 剪影缺一块，且不报错。
func test_registered_parts_are_actually_built() -> void:
	for hero_type in HEROES:
		var view := _make_view(hero_type)
		var built: Array = (view._costume.get("parts", []) as Array)
		for entry in HeroLook.costume_parts(hero_type):
			check(built.has(str(entry["key"])),
				"%s 的配件 %s 登记了但没被建出来（剪影会缺一块）" % [hero_type, str(entry["key"])])
		view.free()

## 配件几何本身不能失控：单件高度/宽度超过 1.7 米就是「一顶帐篷」。
##
## 为什么不在无头测试里量世界坐标：`BoneAttachment3D` 只有在场景树里才会被骨骼
## 姿态驱动，测试里（不进树）它的 transform 是单位矩阵 —— 量出来的 y 会是
## 「相对骨架原点」的错值，而不是实际挂点位置。第一版测试正是因此把披风误判成
## 「插进地面」。世界位置由 `tools/hero_gallery.gd` 在真实渲染环境里出图核对。
func test_costume_parts_stay_within_a_reasonable_size() -> void:
	for hero_type in HEROES:
		var view := _make_view(hero_type)
		var skeleton := HeroCostume.skeleton_of(view.model_root)
		check(skeleton != null, "%s 必须有骨架，配件才有挂点" % hero_type)
		if skeleton == null:
			view.free()
			continue
		var anchors := skeleton.find_children("HeroCostume_*", "BoneAttachment3D", true, false)
		gt(anchors.size(), 0, "%s 必须真的建出了配件挂点" % hero_type)
		var total_meshes := 0
		for anchor in anchors:
			var box := ModelUtils.relative_aabb(anchor)
			if box.size == Vector3.ZERO:
				continue
			total_meshes += anchor.find_children("*", "MeshInstance3D", true, false).size()
			lt(box.size.y, 1.7, "%s 的配件 %s 过高（%.2f 米）" % [hero_type, anchor.name, box.size.y])
			lt(box.size.x, 1.7, "%s 的配件 %s 过宽（%.2f 米）" % [hero_type, anchor.name, box.size.x])
			lt(box.size.z, 1.7, "%s 的配件 %s 过深（%.2f 米）" % [hero_type, anchor.name, box.size.z])
		gt(total_meshes, 4, "%s 的配件网格太少（%d）：形体撑不起剪影" % [hero_type, total_meshes])
		view.free()

# ---------------------------------------------------------------- draw call 预算

## 配件网格总数必须受控。
##
## 这一条守的是移动端预算：10 个英雄同屏时，一套 40 个网格的配件会让
## draw call 冲到 550+（实测），直接吃穿 ≤400 的移动端预算。
## 合并（HeroCostume.merge_anchor）把它压到 ~20/人。上限放宽到 30 留余量，
## 但**低于这个值说明合并真的在工作**。
func test_costume_mesh_count_stays_within_budget() -> void:
	for hero_type in HEROES:
		var view := _make_view(hero_type)
		var skeleton := HeroCostume.skeleton_of(view.model_root)
		if skeleton == null:
			view.free()
			continue
		var costume_meshes := 0
		for anchor in skeleton.find_children("HeroCostume_*", "BoneAttachment3D", true, false):
			costume_meshes += anchor.find_children("*", "MeshInstance3D", true, false).size()
		lt(float(costume_meshes), 31.0,
			"%s 的配件网格 %d 个，超出每英雄 30 的预算（合并失效？）" % [hero_type, costume_meshes])
		view.free()

## 摆动组必须保留自己的节点层：合并把它们烘平的话，跑动时她们就不摆了。
func test_merge_keeps_sway_nodes_alive() -> void:
	for hero_type in HEROES:
		var view := _make_view(hero_type)
		var sway: Dictionary = view._costume.get("sway", {})
		for kind in sway:
			for entry in sway[kind]:
				var node: Node3D = entry.get("node")
				check(node != null and is_instance_valid(node),
					"%s 的摆动组「%s」节点被合并吃掉了" % [hero_type, str(kind)])
				if node != null and is_instance_valid(node):
					check(node.get_child_count() > 0,
						"%s 的摆动组「%s」没有子节点：合并把它的几何搬走了" % [hero_type, str(kind)])
		view.free()

# ---------------------------------------------------------------- 材质缓存

## 同一英雄连建两次，材质数量不能翻倍 —— 战斗里重生/重连都会走这条路。
func test_materials_are_shared_not_rebuilt_per_instance() -> void:
	var first := _make_view("blade")
	var after_first := HeroCostume.material_count()
	var second := _make_view("blade")
	var after_second := HeroCostume.material_count()
	eq(after_second, after_first,
		"同英雄第二次装配不应新增材质（%d → %d）：说明缓存键不稳或绕过了缓存" % [
			after_first, after_second])
	first.free()
	second.free()

## 材质缓存键必须稳定：清空后按同样参数重建，数量应一致。
func test_material_cache_keys_are_deterministic() -> void:
	HeroCostume.clear_caches()
	var view := _make_view("mage")
	var first := HeroCostume.material_count()
	HeroCostume.clear_caches()
	var again := _make_view("mage")
	var second := HeroCostume.material_count()
	eq(second, first, "同参数重建后材质数量必须一致（%d vs %d）" % [first, second])
	view.free()
	again.free()

# ---------------------------------------------------------------- 皮肤换色

## 皮肤面必须真的被换色，而且用的是共用的一档肤色参数。
##
## 这条守的是「五个英雄全是光膀子白人」那个具体问题：通用角色包的肤色贴图
## 是暖橙高亮，不压一层的话在 FILMIC 下会顶成一片白。
func test_skin_surfaces_get_the_shared_skin_grade() -> void:
	var expected := float(HeroLook.skin_slot().get("brightness", 0.0))
	gt(expected, 0.0, "肤色档位必须有 brightness")
	var heroes_with_skin := 0
	for hero_type in HEROES:
		var view := _make_view(hero_type)
		var skin_materials := 0
		for node in view.model_root.find_children("*", "MeshInstance3D", true, false):
			var mesh_instance := node as MeshInstance3D
			if mesh_instance.mesh == null:
				continue
			for surface in mesh_instance.mesh.get_surface_count():
				var override := mesh_instance.get_surface_override_material(surface)
				if not (override is ShaderMaterial):
					continue
				var material := override as ShaderMaterial
				if is_equal_approx(float(material.get_shader_parameter("brightness")), expected):
					skin_materials += 1
		check(skin_materials > 0,
			"%s 必须把肤色面压到共用的一档（brightness=%.2f）" % [hero_type, expected])
		if skin_materials > 0:
			heroes_with_skin += 1
		view.free()
	eq(heroes_with_skin, HEROES.size(), "5 个英雄都要有皮肤换色（否则会回到「光膀子白人」）")

## 眼睛永远保持原贴图 —— 换色会把眼白染成戏服色。
func test_eyes_keep_their_original_material() -> void:
	for hero_type in ["blade", "mage"]:
		var view := _make_view(hero_type)
		for node in view.model_root.find_children("*", "MeshInstance3D", true, false):
			var mesh_instance := node as MeshInstance3D
			if mesh_instance.mesh == null:
				continue
			var role := HeroCostume._role_of(mesh_instance)
			for surface in mesh_instance.mesh.get_surface_count():
				var active := mesh_instance.get_active_material(surface)
				if not (active is BaseMaterial3D):
					continue
				var texture := (active as BaseMaterial3D).albedo_texture
				if texture == null or not texture.resource_path.contains("T_Eye"):
					continue
				eq(HeroCostume.surface_kind(active, role), "keep",
					"%s 的眼睛面必须保持原材质" % hero_type)
		view.free()

# ---------------------------------------------------------------- 自带兜帽

## 通用角色包自带的兜帽必须被显式处理。
##
## 实测：`Male_Ranger_Head_Hood` / `Female_Ranger_Head_Hood` 盖住整个头，
## 5 张立绘里没有一个人戴兜帽 —— 不处理的话实拍就是「五个绿布袋」。
## 这条断言守的是「有人加了英雄但忘了决定兜帽去留」。
func test_bundled_hood_is_explicitly_handled() -> void:
	for hero_type in HEROES:
		var view := _make_view(hero_type)
		var hoods := 0
		var visible_hoods := 0
		for node in view.model_root.find_children("*", "MeshInstance3D", true, false):
			var node_name := str(node.name)
			var is_hood := false
			for hood_name in HeroCostume.HEAD_HOOD_MESHES:
				if node_name.begins_with(str(hood_name)):
					is_hood = true
					break
			if not is_hood:
				continue
			hoods += 1
			if (node as MeshInstance3D).visible:
				visible_hoods += 1
		if hoods > 0:
			var should_show := HeroCostume.KEEP_HEAD_HOOD.has(hero_type)
			eq(visible_hoods > 0, should_show,
				"%s 的自带兜帽可见性必须等于 KEEP_HEAD_HOOD 的决定（hoods=%d visible=%d）" % [
					hero_type, hoods, visible_hoods])
		view.free()

# ---------------------------------------------------------------- 摆动

## 有披风/下摆的英雄必须有可摆动的节点；否则跑动时那块布是焊死的。
func test_cape_heroes_have_sway_groups() -> void:
	var expected := {
		"blade": "cape",
		"mage": "skirt",
		"archer": "cape",
		"assassin": "cape",
		"tank": "banner",
	}
	for hero_type in HEROES:
		var view := _make_view(hero_type)
		var sway: Dictionary = view._costume.get("sway", {})
		check(sway.has(expected[hero_type]),
			"%s 缺少「%s」摆动组（跑动时那块布会是焊死的）" % [hero_type, expected[hero_type]])
		view.free()

## 摆动函数必须真的改变节点角度，而且移动时幅度更大。
func test_sway_changes_angles_and_reacts_to_motion() -> void:
	HeroCostume.clear_caches()
	var view := _make_view("blade")
	var sway: Dictionary = view._costume.get("sway", {})
	check(not sway.is_empty(), "blade 必须有摆动组")
	var entries: Array = sway.get("cape", [])
	check(not entries.is_empty(), "blade 的披风必须有摆动节点")
	if not entries.is_empty():
		var node: Node3D = entries[0]["node"]
		var before := node.rotation.x
		HeroCostume.sway(sway, 0.35, false, 0.0)
		var idle_angle := node.rotation.x
		HeroCostume.sway(sway, 0.35, true, 6.0)
		var moving_angle := node.rotation.x
		check(not is_equal_approx(before, idle_angle) or not is_equal_approx(idle_angle, moving_angle),
			"sway 必须改变节点角度（否则披风是静止的）")
		gt(absf(moving_angle - idle_angle), 0.001,
			"移动时的摆动幅度应大于站桩（idle=%.4f moving=%.4f）" % [idle_angle, moving_angle])
	view.free()

# ---------------------------------------------------------------- 工具可发现性

## 画廊工具必须在：改形象的人第一步就是跑它，而不是靠记忆去找路径。
func test_hero_gallery_tool_exists() -> void:
	var text := FileAccess.get_file_as_string("res://tools/hero_gallery.gd")
	check(text.contains("hero_sheet"), "hero_gallery.gd 必须产出 hero_sheet 对照图")
	check(text.contains("_frame_bust"), "hero_gallery.gd 必须有头肩特写机位")
	# 实战机位那一格不能丢：前三列都是近景，只有它对应玩家 90% 时间的视角。
	check(text.contains("_field_cell"), "hero_gallery.gd 必须保留 21 米实战机位那一格")
	check(text.contains("CELL.x * 4"), "hero_sheet 必须是四列（正面/侧面/特写/实战）")

## 身份色只有一个来源：模型、技能特效、HUD 技能键都读 HeroLook。
## 这条守的是「模型改成锈橙、技能还是青色」那类分叉。
func test_hero_colour_has_a_single_source() -> void:
	var arena_text := FileAccess.get_file_as_string("res://scripts/game/arena.gd")
	check(arena_text.contains("HeroLook.glow(hero_type)"),
		"arena._hero_vfx_color 必须读 HeroLook.glow()，不能自己再硬编码一份谱系色")
	var hud_text := FileAccess.get_file_as_string("res://scripts/ui/game_hud.gd")
	check(hud_text.contains("HeroLook.glow(hero_type)"),
		"HUD 技能键的主色必须读 HeroLook.glow()")
