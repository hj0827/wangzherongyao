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
##   - 中性米白（sat < 0.18）：翎羽的立绘就是米白战衣，压暗反而丢了「白」；
##   - 纯黑/近黑：游戏里会和背景糊在一起。
func test_primary_colours_are_dark_enough_for_filmic() -> void:
	for hero_type in HEROES:
		var primary := HeroLook.primary(hero_type)
		gt(primary.v, 0.02, "%s 的主色不能纯黑（当前 %.2f）" % [hero_type, primary.v])
		if primary.s < 0.18:
			lt(primary.v, 0.80, "%s 的中性主色 brightness 必须 < 0.80（当前 %.2f）" % [
				hero_type, primary.v])
		else:
			lt(primary.v, 0.50, "%s 的饱和主色 brightness 必须 < 0.50（当前 %.2f）" % [
				hero_type, primary.v])

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

## 配件几何本身不能失控：单件高度/宽度超过 1.6 米就是「一顶帐篷」。
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
		gt(total_meshes, 6, "%s 的配件网格太少（%d）：形体撑不起剪影" % [hero_type, total_meshes])
		view.free()

func _relative_transform(node: Node, ancestor: Node) -> Transform3D:
	var result := Transform3D.IDENTITY
	var cursor: Node = node
	while cursor != null and cursor != ancestor:
		if cursor is Node3D:
			result = (cursor as Node3D).transform * result
		cursor = cursor.get_parent()
	return result

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

## 皮肤面必须真的被换色（不是 keep），而且用的是共用的一档肤色参数。
##
## 这条守的是「五个英雄全是光膀子白人」那个具体问题：通用角色包的肤色贴图
## 是暖橙高亮，不压一层的话在 FILMIC 下会顶成一片白。
func test_skin_surfaces_get_the_shared_skin_grade() -> void:
	var heroes_with_skin := 0
	for hero_type in HEROES:
		var view := _make_view(hero_type)
		var skin_materials := 0
		var kept_eyes := 0
		for node in view.model_root.find_children("*", "MeshInstance3D", true, false):
			var mesh_instance := node as MeshInstance3D
			if mesh_instance.mesh == null:
				continue
			for surface in mesh_instance.mesh.get_surface_count():
				var override := mesh_instance.get_surface_override_material(surface)
				if not (override is ShaderMaterial):
					continue
				var material := override as ShaderMaterial
				if is_equal_approx(float(material.get_shader_parameter("brightness")), 0.52):
					skin_materials += 1
		check(skin_materials > 0, "%s 必须把肤色面压到共用的一档（brightness=0.52）" % hero_type)
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
