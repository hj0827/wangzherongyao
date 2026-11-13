extends RefCounted
class_name HeroCostume

## 英雄专属服饰工具箱（纯表现层）。
##
## 设计口径与 MonsterKit 一致，但服务的对象不同：
##   - 野怪读「剪影 + 配色」，可以纯基本体；
##   - 英雄在 21 米机位下只占屏高 ~7%，读的是**轮廓的一两个大件**（披风 / 下摆 /
##     战旗 / 兜帽）＋ 边缘的一圈主色。所以配件必须**大、薄、贴着身体轮廓长**，
##     小零件（纽扣、纹样、发丝）在这个距离上是纯浪费。
##
## 三条硬约束：
##   1. **不许改 body/outfit/hair/weapon 的装配逻辑**：配件只往上叠，拿掉配件
##      仍然是一个能跑的英雄（定制 GLB 到位后也能保留这套配件）；
##   2. **材质与网格走静态缓存**：5 个英雄同屏 + 重连重建，不能每次 instantiate
##      都 new 一批材质（硬规则 4 的精神）；
##   3. **配件必须挂在真实骨骼上**：BoneAttachment3D 的 bone_name 写错不会报错，
##      配件会静静留在原地不跟动作 —— 所以 `HeroLook.VALID_BONES` + 测试双保险。
##
## 坐标系提醒（踩过一次，别改回去）：
##   Godot 的 `BoneAttachment3D` 每帧把自己的 transform **整个**设成骨骼姿态，
##   在它身上写 basis 会被覆盖。所以「抵消骨骼静止旋转、让配件回到模型坐标系」
##   这件事必须做在它的**子节点**上（见 `upright_pivot`）。
##   骨架里 +Y 向上、模型正面朝 -Z、脚底 y≈0.087、头顶 y≈1.81（未乘 model_root 缩放）。

const HeroLook = preload("res://scripts/game/hero_look.gd")
const ModelUtils = preload("res://scripts/game/model_utils.gd")

const SKIN_SHADER_PATH := "res://shaders/hero_skin.gdshader"

static var _materials: Dictionary = {}
static var _meshes: Dictionary = {}
static var _shader: Shader = null
static var _flat: Texture2D = null
# 本次装配已经建过的骨骼挂点：一根骨骼只留一个挂点。
# 见 `shared_pivot()` 的注释（这是 draw call 数量的一半）。
static var _pivot_cache: Dictionary = {}

## 同一次装配内，一根骨骼只建一个挂点。
##
## 为什么重要：袖子、护肩、肩盖、臂环都挂在 upperarm 上，各建一个
## BoneAttachment3D 就是 4 次 draw call —— 但它们的父骨骼完全相同，
## 每帧变换也完全相同，合并成一份网格后没有任何视觉差别。
## 10 个英雄同屏时，这一条能把配件 draw call 从 ~32/人 压到 ~16/人。
##
## `aligned=false`（沿骨骼轴）优先：只要需要沿骨轴的件先建，这个挂点就是沿骨轴的；
## 反过来的情况各建一个，绝不混用（混用会让「正立」的件横过来）。
static func shared_pivot(skeleton: Skeleton3D, bone_name: String, aligned := true) -> Node3D:
	var key := "%d|%s|%s" % [skeleton.get_instance_id(), bone_name, str(aligned)]
	var cached: Node3D = _pivot_cache.get(key, null)
	if cached != null and is_instance_valid(cached):
		return cached
	var pivot := attach(skeleton, bone_name, "Shared_" + bone_name, aligned)
	if pivot != null:
		_pivot_cache[key] = pivot
	return pivot

## 每次装配开始前调用：清掉上一个英雄的挂点缓存，避免跨英雄复用。
static func begin_build() -> void:
	_pivot_cache.clear()

# ---------------------------------------------------------------------------
# 材质
# ---------------------------------------------------------------------------

static func skin_shader() -> Shader:
	if _shader == null:
		var loaded = load(SKIN_SHADER_PATH)
		if loaded is Shader:
			_shader = loaded as Shader
	return _shader

static func _flat_texture() -> Texture2D:
	if _flat == null:
		var image := Image.create(4, 4, false, Image.FORMAT_RGBA8)
		image.fill(Color(1.0, 1.0, 1.0))
		_flat = ImageTexture.create_from_image(image)
	return _flat

## 参数 → 稳定键。Dictionary 没有 hash()，手工拼串（顺序固定，别用 acc.hash）。
static func _params_key(params: Dictionary) -> String:
	var parts: Array[String] = []
	for field in ["base", "accent", "rim", "glow"]:
		parts.append(str(params.get(field, Color.BLACK)))
	for field in ["accent_amount", "recolor", "lighting_keep", "contrast", "brightness",
			"rim_strength", "rim_power", "glow_strength", "roughness", "metallic", "specular"]:
		parts.append("%.3f" % float(params.get(field, 0.0)))
	return "|".join(parts)

## 把一套 `HeroLook.slot()` 参数变成 ShaderMaterial。
## `texture` 为 null 时用纯白 4×4，shader 的分支退化成「纯色塑造」。
static func skin_material(params: Dictionary, texture: Texture2D, team: String) -> ShaderMaterial:
	var tex_key := texture.resource_path if texture != null else "flat"
	var key := "%s#%s#%s" % [_params_key(params), tex_key, team]
	var cached: ShaderMaterial = _materials.get(key, null)
	if cached != null:
		return cached
	var material := ShaderMaterial.new()
	material.shader = skin_shader()
	material.set_shader_parameter("albedo_tex", texture if texture != null else _flat_texture())
	material.set_shader_parameter("base_color", params.get("base", Color.WHITE))
	material.set_shader_parameter("accent_color", params.get("accent", Color.BLACK))
	material.set_shader_parameter("accent_amount", float(params.get("accent_amount", 0.0)))
	material.set_shader_parameter("recolor", float(params.get("recolor", 0.85)))
	material.set_shader_parameter("lighting_keep", float(params.get("lighting_keep", 0.55)))
	material.set_shader_parameter("contrast", float(params.get("contrast", 1.35)))
	material.set_shader_parameter("brightness", float(params.get("brightness", 1.0)))
	material.set_shader_parameter("rim_color", params.get("rim", Color.WHITE))
	material.set_shader_parameter("rim_strength", float(params.get("rim_strength", 0.0)))
	material.set_shader_parameter("rim_power", float(params.get("rim_power", 3.0)))
	material.set_shader_parameter("glow_color", params.get("glow", Color.WHITE))
	material.set_shader_parameter("glow_strength", float(params.get("glow_strength", 0.0)))
	material.set_shader_parameter("roughness_value", float(params.get("roughness", 0.82)))
	material.set_shader_parameter("metallic_value", float(params.get("metallic", 0.0)))
	material.set_shader_parameter("specular_value", float(params.get("specular", 0.35)))
	material.set_shader_parameter("team_tint", HeroLook.team_tint(team))
	material.set_shader_parameter("team_amount", HeroLook.team_amount())
	material.set_shader_parameter("team_rim_color", HeroLook.team_rim(team))
	material.set_shader_parameter("team_rim_strength", HeroLook.team_rim_strength())
	_materials[key] = material
	return material

# ---------------------------------------------------------------------------
# 配件材质（不需要贴图，纯色 + 发光）
# ---------------------------------------------------------------------------

static func cloth(color: Color) -> StandardMaterial3D:
	var key := "cloth|%s" % color.to_html(true)
	var material: StandardMaterial3D = _materials.get(key, null)
	if material == null:
		material = StandardMaterial3D.new()
		material.albedo_color = color
		material.roughness = 0.88
		material.metallic = 0.0
		material.metallic_specular = 0.14
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
		# 一点自发光：游戏主光的方向让披风内侧面（背光面）在 21 米机位下
		# 直接变成纯黑，远看是「英雄背着一块黑板」。实测 0.10 还不够，
		# 0.30 才把死黑抬到「能看出是墨绿布」而不会像在发光。
		material.emission_enabled = true
		material.emission = color
		material.emission_energy_multiplier = 0.30
		_materials[key] = material
	return material

static func plate(color: Color, metallic := 0.35) -> StandardMaterial3D:
	var key := "plate|%s|%.2f" % [color.to_html(true), metallic]
	var material: StandardMaterial3D = _materials.get(key, null)
	if material == null:
		material = StandardMaterial3D.new()
		material.albedo_color = color
		material.roughness = 0.52
		# 兼容渲染器没有反射探针：metallic 一过 0.3 金属面就变成近黑（环境光只剩
		# 天空的漫反射）。实测 0.5 的铁色渲染出来是 (0.06,0.06,0.07)，读成黑塑料。
		material.metallic = clampf(metallic, 0.0, 0.3)
		material.metallic_specular = 0.4
		_materials[key] = material
	return material

## 金 / 铜饰件：靠 albedo 的暖色 + 一点点自发光出「铜」的观感，
## 不靠 metallic —— 兼容渲染器下 high metallic 等于「一块黑铁」。
static func gold(color: Color) -> StandardMaterial3D:
	var key := "gold|%s" % color.to_html(true)
	var material: StandardMaterial3D = _materials.get(key, null)
	if material == null:
		material = StandardMaterial3D.new()
		material.albedo_color = color.lightened(0.16)
		material.roughness = 0.38
		material.metallic = 0.28
		material.metallic_specular = 0.6
		material.emission_enabled = true
		material.emission = color
		material.emission_energy_multiplier = 0.32
		_materials[key] = material
	return material

## 发光件（晶石 / 星点 / 刃光）：unshaded + 加色，在 bloom 下才「亮」。
static func glow(color: Color, energy := 1.8) -> StandardMaterial3D:
	var key := "glow|%s|%.2f" % [color.to_html(true), energy]
	var material: StandardMaterial3D = _materials.get(key, null)
	if material == null:
		material = StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
		material.albedo_color = Color(color.r, color.g, color.b, 0.85)
		material.emission_enabled = true
		material.emission = color
		material.emission_energy_multiplier = energy
		material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
		_materials[key] = material
	return material

static func material_count() -> int:
	return _materials.size()

## 只给测试用：清缓存后重建，验证「同参数复用同一份材质」。
static func clear_caches() -> void:
	_materials.clear()
	_meshes.clear()

# ---------------------------------------------------------------------------
# 网格缓存
# ---------------------------------------------------------------------------

static func _mesh(key: String, factory: Callable) -> Mesh:
	var mesh: Mesh = _meshes.get(key, null)
	if mesh == null:
		mesh = factory.call()
		_meshes[key] = mesh
	return mesh

static func box_mesh(size: Vector3) -> BoxMesh:
	return _mesh("box|%.3f|%.3f|%.3f" % [size.x, size.y, size.z], func() -> BoxMesh:
		var mesh := BoxMesh.new()
		mesh.size = size
		return mesh)

static func cylinder_mesh(radius: float, height: float, sides := 8, top_radius := -1.0) -> CylinderMesh:
	var top := radius if top_radius < 0.0 else top_radius
	return _mesh("cyl|%.3f|%.3f|%.3f|%d" % [top, radius, height, sides], func() -> CylinderMesh:
		var mesh := CylinderMesh.new()
		mesh.top_radius = top
		mesh.bottom_radius = radius
		mesh.height = height
		mesh.radial_segments = sides
		return mesh)

static func sphere_mesh(radius: float, segments := 10) -> SphereMesh:
	return _mesh("ball|%.3f|%d" % [radius, segments], func() -> SphereMesh:
		var mesh := SphereMesh.new()
		mesh.radius = radius
		mesh.height = radius * 2.0
		mesh.radial_segments = segments
		mesh.rings = maxi(4, segments / 2)
		return mesh)

## 薄板 / 羽片 / 破布：棱柱天然带一条中脊，俯视下不是一块平纸。
static func shard_mesh(size: Vector3, lean := 0.5) -> PrismMesh:
	return _mesh("shard|%.3f|%.3f|%.3f|%.2f" % [size.x, size.y, size.z, lean], func() -> PrismMesh:
		var mesh := PrismMesh.new()
		mesh.size = size
		mesh.left_to_right = lean
		return mesh)

static func torus_mesh(inner: float, outer: float, rings := 24) -> TorusMesh:
	return _mesh("torus|%.3f|%.3f|%d" % [inner, outer, rings], func() -> TorusMesh:
		var mesh := TorusMesh.new()
		mesh.inner_radius = inner
		mesh.outer_radius = outer
		mesh.rings = rings
		mesh.ring_segments = 6
		return mesh)

## 敞口圆台 = 裙摆 / 宽袖。cap_top / cap_bottom 关掉才是一层布，
## 不关的话俯视会看到「一个扣在身上的盆」。
static func cone_mesh(top_radius: float, bottom_radius: float, height: float, sides := 14) -> CylinderMesh:
	return _mesh("cone|%.3f|%.3f|%.3f|%d" % [top_radius, bottom_radius, height, sides], func() -> CylinderMesh:
		var mesh := CylinderMesh.new()
		mesh.top_radius = top_radius
		mesh.bottom_radius = bottom_radius
		mesh.height = height
		mesh.radial_segments = sides
		mesh.cap_top = false
		mesh.cap_bottom = false
		return mesh)

## 一片会下垂的布：宽 top→bottom 渐变 + 向背后弯出去 + 布料起伏。
##
## 为什么值得手写网格：披风是英雄最主要的剪影，而 BoxMesh 拼的披风在任何机位
## 下都读成「背着的一块板」。整片布只需要一个 surface / 一次 draw call，
## 比「五片盒子」既好看又便宜。
##
## 参数（模型坐标，-Z 为正面）：
##   width_top / width_bottom  上/下摆宽
##   length                    垂下来的长度
##   curve                     向 +Z（背后）弯出去的量
##   wave                      布面左右起伏的幅度（0 = 平板）
static func sheet_mesh(
	width_top: float,
	width_bottom: float,
	length: float,
	curve := 0.06,
	wave := 0.012,
	columns := 5,
	rows := 4
) -> ArrayMesh:
	var key := "sheet|%.3f|%.3f|%.3f|%.3f|%.3f|%d|%d" % [
		width_top, width_bottom, length, curve, wave, columns, rows]
	var cached: ArrayMesh = _meshes.get(key, null)
	if cached != null:
		return cached
	var vertices := PackedVector3Array()
	var indices := PackedInt32Array()
	for row in rows + 1:
		var v := float(row) / float(rows)
		var half := lerpf(width_top, width_bottom, v) * 0.5
		var y := -v * length
		var z := curve * sin(v * PI * 0.55)
		for column in columns + 1:
			var u := float(column) / float(columns)
			var x := lerpf(-half, half, u)
			# 布面起伏：中间鼓、两侧收一点，边缘加一点波浪，俯视不是一条直线。
			var ripple := sin(u * PI) * wave * 0.35 * sin(v * 5.0 + u * 2.0)
			vertices.append(Vector3(x, y, z + ripple))
	for row in rows:
		for column in columns:
			var a := row * (columns + 1) + column
			var b := a + 1
			var c := a + columns + 1
			var d := c + 1
			indices.append_array([a, c, b, b, c, d])
	var normals := PackedVector3Array()
	normals.resize(vertices.size())
	for i in indices.size() / 3:
		var ia := indices[i * 3]
		var ib := indices[i * 3 + 1]
		var ic := indices[i * 3 + 2]
		var face := (vertices[ib] - vertices[ia]).cross(vertices[ic] - vertices[ia])
		normals[ia] += face
		normals[ib] += face
		normals[ic] += face
	for i in normals.size():
		normals[i] = normals[i].normalized()
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_meshes[key] = mesh
	return mesh

static func mesh_count() -> int:
	return _meshes.size()

# ---------------------------------------------------------------------------
# 几何拼装
# ---------------------------------------------------------------------------

static func part(
	parent: Node3D,
	mesh: Mesh,
	material: Material,
	pos: Vector3,
	rot_deg := Vector3.ZERO,
	part_scale := Vector3.ONE
) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	instance.position = pos
	instance.rotation_degrees = rot_deg
	instance.scale = part_scale
	# 英雄整体关闭投影（unit_visual 的口径）：配件跟着关，否则一套披风就是一次 shadow pass。
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(instance)
	return instance

static func group(parent: Node3D, node_name: String, pos := Vector3.ZERO, rot_deg := Vector3.ZERO) -> Node3D:
	var node := Node3D.new()
	node.name = node_name
	node.position = pos
	node.rotation_degrees = rot_deg
	parent.add_child(node)
	return node

## 两段式布片：上窄下宽 + 一条深色下摆压边。
##
## 为什么不用一整块 BoxMesh：一整块布在实机上读成「一块纸板」，而王者那类角色
## 的衣服靠**上下两段的宽度差**表现垂坠。两段之间错开 0.01 米 + 下摆压边，
## 21 米机位下就是一条清楚的「衣褶线」。
static func cloth_panel(
	parent: Node3D,
	w_top: float,
	w_bottom: float,
	length: float,
	material: Material,
	hem: Material,
	pos := Vector3.ZERO,
	rot_deg := Vector3.ZERO,
	tilt_deg := 0.0
) -> Node3D:
	var root := group(parent, "ClothPanel", pos, rot_deg)
	var upper_length := length * 0.52
	var lower_length := length * 0.52
	# 上段：略窄、几乎垂直；下段：更宽、外翻 —— 这就是「垂坠」。
	part(root, box_mesh(Vector3(w_top, upper_length, 0.024)), material,
		Vector3(0.0, -upper_length * 0.5, 0.0), Vector3(tilt_deg, 0.0, 0.0))
	part(root, box_mesh(Vector3(w_bottom, lower_length, 0.026)), material,
		Vector3(0.0, -upper_length - lower_length * 0.5 + 0.006, 0.012 + 0.01 * sin(deg_to_rad(tilt_deg))),
		Vector3(tilt_deg * 1.45, 0.0, 0.0))
	part(root, box_mesh(Vector3(w_bottom + 0.008, 0.026, 0.028)), hem,
		Vector3(0.0, -length + 0.004, 0.024 + 0.014 * sin(deg_to_rad(tilt_deg))),
		Vector3(tilt_deg * 1.45, 0.0, 0.0))
	return root

## 环 / 腰带 / 护肩滚边：torus 默认躺在 XZ 平面（孔沿 Y 轴），
## 想让它套在身体上（胸前/腰上）就得绕 X 轴转 90°。
static func band(
	parent: Node3D,
	inner: float,
	outer: float,
	material: Material,
	pos: Vector3,
	rot_deg := Vector3(90.0, 0.0, 0.0),
	rings := 20
) -> MeshInstance3D:
	return part(parent, torus_mesh(inner, outer, rings), material, pos, rot_deg)

## 扁平护肩：压扁的球 = 圆顶甲片。盒子做的护肩在任何机位都像一块砖。
static func dome(
	parent: Node3D,
	radius: float,
	material: Material,
	pos: Vector3,
	flat := 0.55,
	rot_deg := Vector3.ZERO
) -> MeshInstance3D:
	return part(parent, sphere_mesh(radius, 12), material, pos, rot_deg,
		Vector3(1.0, flat, 1.0))

## 羽片 / 布条：棱柱的一侧收成尖，天然是「羽毛」而不是「木片」。
static func feather(
	parent: Node3D,
	width: float,
	length: float,
	material: Material,
	pos: Vector3,
	rot_deg := Vector3.ZERO,
	lean := 0.35
) -> MeshInstance3D:
	return part(parent, shard_mesh(Vector3(width, length, 0.012), lean), material, pos, rot_deg)

# ---------------------------------------------------------------------------
# 骨骼挂点
# ---------------------------------------------------------------------------

static func skeleton_of(root: Node) -> Skeleton3D:
	if root == null:
		return null
	for node in root.find_children("*", "Skeleton3D", true, false):
		return node as Skeleton3D
	return null

## 在骨架上挂一个 BoneAttachment3D，返回它下面的容器 Node3D。
##
## 命名约定：节点名一律以 `HeroCostume_` 开头。原因不是洁癖 ——
## 身高契约测试要在只量「身体 + 衣服 + 头发」时把配件整体摘掉
## （`test_hero_silhouette` 对武器也是这么做的），统一前缀才摘得干净。
## 配件本身会合理地超出头顶（战旗/月冠），不该算进 HERO_HEIGHT 这个身体契约。
##
## 三层结构（缺一层就会静默错位）：
##   BoneAttachment3D ── 每帧被骨骼姿态整个覆盖；
##     Align          ── basis = 骨骼静止旋转的逆，把坐标系掰回模型坐标；
##       Pivot        ── 真正的配件容器，builder 写的位置都是「模型坐标偏移」。
##
## 如果直接把位置写在 Align 上，偏移会被骨骼旋转带着走 —— 实测星环会从背后
## 飞到右上方（x=0.22 而不是 0）。这类错位不报错，只在实拍图里看得出来。
static func attach(skeleton: Skeleton3D, bone_name: String, node_name: String, aligned := true) -> Node3D:
	if skeleton == null or skeleton.find_bone(bone_name) < 0:
		return null
	var attachment := BoneAttachment3D.new()
	attachment.name = "HeroCostume_" + node_name
	attachment.bone_name = bone_name
	skeleton.add_child(attachment)
	if not aligned:
		# 沿骨骼轴：用于「包住肢体」的袖子/护胫。此时 +Y 沿骨长（Mixamo 骨架
		# 的 Y 轴就是骨长方向），不能抵消 —— 抵消之后袖管会横在身体前面。
		var raw := Node3D.new()
		raw.name = node_name
		attachment.add_child(raw)
		return raw
	var align := Node3D.new()
	align.name = "Align"
	var rest := skeleton.get_bone_global_rest(skeleton.find_bone(bone_name))
	align.basis = rest.basis.inverse().orthonormalized()
	attachment.add_child(align)
	var pivot := Node3D.new()
	pivot.name = node_name
	align.add_child(pivot)
	return pivot

## 兼容旧调用名：`attach()` 现在自带 Align 层，这个函数只做同一件事。
## 保留它是为了让 builder 读起来是「我要一个正立的挂点」而不是「我要一个附件」。
static func upright_pivot(skeleton: Skeleton3D, bone_name: String, node_name: String) -> Node3D:
	return attach(skeleton, bone_name, node_name)

## 躯干外壳：一件贴身的锥形上衣（胸甲 / 长袍上身 / 皮背心）。
## 注册在 spine_02 上，跟着上身转动；半径比躯干大 0.012，不参与蒙皮。
##
## `center_y` 是相对 spine_02 的中点偏移：默认 0.10 时下摆落在腰（≈1.0）、
## 上沿落在锁骨下（≈1.4）。写太高会把脖子包成一个方盒子（第一版就这么翻车的）。
static func torso_shell(
	skeleton: Skeleton3D,
	top_radius: float,
	bottom_radius: float,
	height: float,
	material: Material,
	node_name := "Torso",
	center_y := 0.10,
	sides := 14
) -> Node3D:
	var pivot := upright_pivot(skeleton, "spine_02", node_name)
	if pivot == null:
		return null
	# 用「敞口圆台」而不是带盖圆柱：带盖时肩线处会出现一块平圆盘，
	# 近景是一块绿色平台，远景是一条亮边。开盖后脖子从口里穿出来，自然。
	var mesh := cone_mesh(top_radius, bottom_radius, height, sides)
	part(pivot, mesh, material, Vector3(0.0, center_y, 0.0))
	return pivot

## 胯部围裙：从骨盆往下的一小段锥裙，盖住通用包的浅色短裤 + 大腿根。
## 挂在 pelvis 上（不跟腿摆），跑动时腿从下面露出来，正好。
static func pelvis_wrap(
	skeleton: Skeleton3D,
	top_radius: float,
	bottom_radius: float,
	height: float,
	material: Material,
	node_name := "PelvisWrap",
	center_y := -0.10,
	sides := 14
) -> Node3D:
	var pivot := upright_pivot(skeleton, "pelvis", node_name)
	if pivot == null:
		return null
	part(pivot, cylinder_mesh(bottom_radius, height, sides, top_radius), material,
		Vector3(0.0, center_y, 0.0))
	return pivot

## 肩轭：从躯干壳顶沿收到颈根的一小段锥面。
##
## 为什么不用「领口圆环」：环的半径等于胸围时，它会在脖子周围形成一个大金圈
## （实测近景像戴了个呼啦圈）；半径等于颈围时又封不住躯干壳的顶口，露出皮肤。
## 一段「胸围 → 颈围」的锥面同时解决两件事，而且读起来就是衣服的肩线。
static func yoke(
	skeleton: Skeleton3D,
	bottom_radius: float,
	neck_radius: float,
	height: float,
	material: Material,
	offset_y := 0.20
) -> void:
	var pivot := upright_pivot(skeleton, "spine_03", "Yoke")
	if pivot == null:
		return
	part(pivot, cone_mesh(neck_radius, bottom_radius, height, 16), material,
		Vector3(0.0, offset_y, 0.0))

## 把一部分肢体包进「袖子 / 护胫 / 胸甲」：英雄在 21 米机位下首先读的是
## 「这个人穿着一身什么」，而不是脸。通用角色包本身是背心短裤的西式游侠，
## 不额外包一层，五个英雄看起来都是「光着膀子的白人」。
##
## 沿骨骼轴挂（不在 Align 坐标系里）：骨骼局部 +Y 就是骨长方向，
## 圆台中心摆在 +length/2 处，正好从关节往下/往外套住这段肢体。
## 半径比身体大 0.008~0.015，不改蒙皮、不穿模；关节处两段自然叠一点。
static func limb_tube(
	skeleton: Skeleton3D,
	bone: String,
	top_radius: float,
	bottom_radius: float,
	length: float,
	material: Material,
	sides := 10,
	node_name := "",
	start_offset := 0.0
) -> Node3D:
	# 沿骨轴挂：袖管/护胫本来就要跟着骨长方向走。
	# 走 shared_pivot：同一根骨上的袖管、护臂、肩盖共用一份挂点，
	# 最后跨层合并成 1 个网格（10 人同屏省一半配件 draw call）。
	var pivot := shared_pivot(skeleton, bone, false)
	if pivot == null:
		return null
	var mesh := cylinder_mesh(bottom_radius, length, sides, top_radius)
	part(pivot, mesh, material, Vector3(0.0, start_offset + length * 0.5, 0.0))
	return pivot

## 贴在骨骼上的一圈「甲环」（护腕 / 护胫口 / 臂环）：短圆台，比肢体粗。
static func limb_band(
	skeleton: Skeleton3D,
	bone: String,
	radius: float,
	height: float,
	offset: float,
	material: Material,
	sides := 12
) -> void:
	var pivot := shared_pivot(skeleton, bone, false)
	if pivot == null:
		return
	part(pivot, cylinder_mesh(radius, height, sides), material, Vector3(0.0, offset, 0.0))

# ---------------------------------------------------------------------------
# 皮肤着色：把通用角色包的杂色贴图重上色成每个英雄的设定色
# ---------------------------------------------------------------------------

## 按贴图文件名判断这个面是「皮肤 / 眼睛 / 头发 / 布料」。
##
## 判定依据（用 tools/probe_hero_textures.gd 量过）：
##   - `*_Dark*.png` / `*_Regular_*.png`：肤色贴图（hue 0.07、sat 0.52）；
##   - `*_Hair_*.png`：头发（灰度）；
##   - `*_Eye_*.png`：眼睛；
##   - `*_Ranger_*.png` / `*_Peasant_*.png`：布料与皮甲（暗橄榄）；
##   - 没有贴图的纯色面：身体底衣 / 甲片。
##
## 换色**必须跳过皮肤与眼睛**：把脸染成墨绿是这套方案最容易出的丑。
static func surface_kind(material: Material, role: String) -> String:
	if role == "weapon":
		return "weapon"
	if not (material is BaseMaterial3D):
		return "keep"
	var base := material as BaseMaterial3D
	var texture := base.albedo_texture
	if texture == null:
		return "hair" if role == "hair" else ("outfit" if role == "outfit" else "body")
	var path := texture.resource_path
	if path.contains("T_Eye"):
		return "keep"
	if path.contains("_Hair_"):
		return "hair"
	if path.contains("_Dark") or path.contains("_Regular_"):
		# 肤色面：单独一档压亮提对比，否则在深色戏服旁边是一块发白的浅橙。
		return "skin"
	if path.contains("_Ranger_") or path.contains("_Peasant_") or path.contains("outfit"):
		return "outfit"
	return "hair" if role == "hair" else ("outfit" if role == "outfit" else "body")

## 网格节点属于哪个装配槽（Body / Outfit / Hair / Weapon）。
## apply_skin 的换色档位靠它区分「这是衣服还是头发」—— 判错会把头发染成衣服色。
static func _role_of(mesh_instance: MeshInstance3D) -> String:
	var node: Node = mesh_instance
	while node != null:
		var node_name := str(node.name)
		if node_name == "WeaponSlot":
			return "weapon"
		if node_name == "Body" or node_name == "Outfit" or node_name == "Hair":
			return node_name.to_lower()
		node = node.get_parent()
	return "body"

## 把整套英雄网格换成英雄专属的皮肤材质。
## 返回被改写的面数（测试用它证明「真的改了」，而不是静默跳过）。
static func apply_skin(root: Node3D, hero_type: String, team: String) -> int:
	if root == null or not HeroLook.has_look(hero_type):
		return 0
	var changed := 0
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.mesh == null:
			continue
		var role := _role_of(mesh_instance)
		var surfaces := mesh_instance.mesh.get_surface_count()
		for surface in surfaces:
			var active := mesh_instance.get_active_material(surface)
			var kind := surface_kind(active, role)
			if kind == "keep":
				continue
			if kind == "weapon":
				var weapon_params := HeroLook.slot(hero_type, "weapon")
				var texture: Texture2D = null
				if active is BaseMaterial3D:
					texture = (active as BaseMaterial3D).albedo_texture
				mesh_instance.set_surface_override_material(
					surface, skin_material(weapon_params, texture, team))
				changed += 1
				continue
			# 皮肤：全英雄共用一档，不跟着英雄主色走（否则会有绿脸/紫脸）。
			var params := HeroLook.skin_slot() if kind == "skin" else HeroLook.slot(hero_type, kind)
			var tex: Texture2D = null
			if active is BaseMaterial3D:
				tex = (active as BaseMaterial3D).albedo_texture
			mesh_instance.set_surface_override_material(surface, skin_material(params, tex, team))
			changed += 1
	return changed

## 通用角色包自带的两件「兜帽」网格（不是我们加的配件）。
##
## 实测（tools/probe_hero_head.gd）：`Male_Ranger_Head_Hood` / `Female_Ranger_Head_Hood`
## 是包 outfit 里自带的兜帽，盖住整个头（模型坐标 y≈1.47~1.87）。默认是深褐皮革，
## 重上色之后变成一顶跟衣服同色的布袋 —— 实拍里五个英雄头顶都是它。
##
## 处理口径：
##   - 苍刃 / 星璃 / 翎羽：**保留**（立绘里本来就有兜帽或披风帽），跟衣服同色；
##   - 墨鸦：立绘是高马尾 + 无帽，**把这件网格藏起来**（visible=false）。
##     藏而不是删：它的蒙皮挂在骨架上，删了会在原地留一个洞。
const HEAD_HOOD_MESHES := ["Male_Ranger_Head_Hood", "Female_Ranger_Head_Hood"]

## 保留自带兜帽的英雄。
##
## 现在是**空的**：5 张立绘（assets/ui/portraits/*.png）里没有一个人戴兜帽 ——
## 苍刃短发、星璃长发 + 月冠、铁壁光头 + 发髻、翎羽双丸子 + 羽饰、墨鸦高马尾。
## 通用包那顶兜帽会盖住整张脸，实拍就是「五个绿布袋」。
## 剪影改由各英雄自己的配件承担（披风 / 披肩 / 兜帽配件 / 战旗）。
## 想给某个英雄恢复兜帽，把 hero_type 加进这个数组即可。
const KEEP_HEAD_HOOD: Array[String] = []

## 按英雄决定自带兜帽出不出现。必须在 apply_skin 之后调用
## （先把它染成衣服色，再决定是否显示）。
static func apply_head_hood(root: Node3D, hero_type: String) -> void:
	if root == null:
		return
	var keep := KEEP_HEAD_HOOD.has(hero_type)
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var node_name := str(node.name)
		for hood_name in HEAD_HOOD_MESHES:
			if node_name.begins_with(str(hood_name)):
				(node as MeshInstance3D).visible = keep
				break

## 武器：除了重上色，再挂一条刃口发光（鞘/柄不发光，靠几何挑选）。
## 不新建节点也能读到「这把武器是橙金色系」。
static func highlight_weapon(root: Node3D, hero_type: String) -> void:
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		if _role_of(mesh_instance) != "weapon":
			continue
		var params := HeroLook.slot(hero_type, "weapon")
		var energy := float(params.get("glow_strength", 0.0))
		if energy <= 0.0:
			continue
		mesh_instance.set_meta("hero_glow", params.get("glow", Color.WHITE))
		mesh_instance.set_meta("hero_glow_energy", energy)

# ---------------------------------------------------------------------------
# 服饰构建
# ---------------------------------------------------------------------------

## 给英雄装上专属服饰。返回 {"parts": [...], "sway": {...}}。
## `HeroCostumeParts` 只负责几何，这里负责找骨架、挂骨骼、记账、最后合并网格。
static func build_costume(root: Node3D, hero_type: String) -> Dictionary:
	var empty := {"parts": [], "sway": {}}
	var skeleton := skeleton_of(root)
	if skeleton == null:
		return empty
	var parts_script = load("res://scripts/game/hero_costume_parts.gd")
	if parts_script == null:
		return empty
	begin_build()
	var result: Dictionary = parts_script.build(hero_type, skeleton)
	# 合并必须在**全部建完之后**做，否则后面新建的件又不会进合并组。
	for anchor in skeleton.find_children("HeroCostume_*", "BoneAttachment3D", true, false):
		merge_anchor(anchor as Node3D)
	return result

# ---------------------------------------------------------------------------
# 网格合并（draw call）
# ---------------------------------------------------------------------------

## 合并一个挂点下的所有静态网格（自底向上）。
##
## 为什么必须做：一套配件大约 38 个 MeshInstance3D，10 个英雄同屏实测
## 614 draw call / 686 mesh —— 移动端预算（≤400）直接被配件吃穿。
##
## 三条安全约束：
##   1. **只在 `HeroCostume_*` 挂点里合并**：身体网格有蒙皮权重，烘成静态网格
##      会立刻变成「脱了骨架的一坨」；
##   2. **按材质分桶**：不同材质的网格合并后会共享一份 material_override，
##      金边和布料会糊成同色；
##   3. **自底向上**：先并叶子组（ClothPanel 里的三片布），再并父层，
##      这样摆动组的节点本身还在，`sway()` 写的 rotation 依然有效。
static func _merge_static_meshes(root: Node) -> void:
	for child in root.get_children():
		_merge_static_meshes(child)
	if not (root is Node3D) or root is MeshInstance3D:
		return
	var buckets: Dictionary = {}
	for child in root.get_children():
		if not (child is MeshInstance3D):
			continue
		var mesh_instance := child as MeshInstance3D
		if mesh_instance.mesh == null:
			continue
		if mesh_instance.get_child_count() > 0:
			continue
		var key := str(mesh_instance.material_override)
		var list: Array = buckets.get(key, [])
		list.append(mesh_instance)
		buckets[key] = list
	for key in buckets:
		var list: Array = buckets[key]
		if list.size() < 2:
			continue
		var merged := _merge_meshes(list)
		if merged == null:
			continue
		var first: MeshInstance3D = list[0]
		first.mesh = merged
		first.position = Vector3.ZERO
		first.rotation = Vector3.ZERO
		first.scale = Vector3.ONE
		for i in range(1, list.size()):
			var extra: MeshInstance3D = list[i]
			root.remove_child(extra)
			extra.free()

## 跨层合并：把一个挂点下**所有不在摆动组里**的网格按材质烘成一份。
##
## 上面的逐层合并只能把「同一个组的三个零件」并成一个；一套配件真正的浪费在于
## 「披风挂点下 5 个组，每组 1~2 个网格」，逐层合并一个都并不掉。
## 这里按「材质」跨层并，一个挂点通常只剩 2~4 个网格。
##
## 摆动组整棵子树跳过：它们的 rotation 每帧被 sway() 改写，烘进静态网格就摆不动了，
## 而且不报错 —— 表现为「跑起来披风是焊死的」。
## 跨层合并：把一个挂点下的网格按材质烘成尽可能少的几份。
##
## 为什么必须做：一套配件约 30~44 个 MeshInstance3D，10 个英雄同屏实测
## 554 draw call / 626 mesh —— 移动端预算（≤400）直接被配件吃穿。
##
## 三条安全约束（每条都对应一次实际踩坑）：
##   1. **摆动节点必须保留自己那一层**：它们的 rotation 每帧被 `sway()` 改写。
##      把子网格烘到挂点根上的话，披风的旋转就再也影响不到那些几何，
##      表现是「跑起来披风焊死在背上」——而且不报错。
##      做法是：**在每个摆动节点自己名下就地合并**（holder 挂在它下面），
##      剩下的再跨层合并到挂点根；
##   2. **只在 `HeroCostume_*` 挂点里合并**：身体网格带蒙皮权重，烘成静态网格
##      会立刻变成「脱了骨架的一坨」；
##   3. **按材质分桶**：不同材质合并后会共享一份 material_override，
##      金边和布料会糊成同色。
static func merge_anchor(anchor: Node3D) -> void:
	# 先就地合并每个摆动节点自己的子树（保留它们各自的变换层）。
	for marked in _sway_nodes_under(anchor):
		_merge_subtree_into(marked, marked)
	# 再把剩下的（不含已合并的摆动节点）并到挂点根。
	_merge_subtree_into(anchor, anchor)

static func _merge_subtree_into(root: Node3D, holder_parent: Node3D) -> void:
	var buckets: Dictionary = {}
	_collect_merged_meshes(root, Transform3D.IDENTITY, buckets, root)
	for key in buckets:
		var entries: Array = buckets[key]
		if entries.size() < 2:
			continue
		var merged := _merge_transformed(entries)
		if merged == null:
			continue
		var source: MeshInstance3D = entries[0]["node"]
		var holder := MeshInstance3D.new()
		holder.name = "Merged"
		holder.mesh = merged
		holder.material_override = source.material_override
		holder.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		holder_parent.add_child(holder)
		for entry in entries:
			var node: MeshInstance3D = entry["node"]
			if node.get_parent() != null:
				node.get_parent().remove_child(node)
			node.free()

## 收集 `root` 子树里的静态网格。`root` 自己若是摆动节点，不因此跳过自己的子网格
## （它们相对于 root 的变换是固定的，烘进挂在 root 下的 holder 仍然正确）。
static func _collect_merged_meshes(
	node: Node,
	xform: Transform3D,
	buckets: Dictionary,
	root: Node3D
) -> void:
	for child in node.get_children():
		if child is MeshInstance3D:
			var mesh_instance := child as MeshInstance3D
			if mesh_instance.mesh != null:
				var key := str(mesh_instance.material_override)
				var list: Array = buckets.get(key, [])
				list.append({"node": mesh_instance, "xform": xform * mesh_instance.transform})
				buckets[key] = list
			continue
		if child is Node3D:
			# 别的摆动节点：它的变换由 sway() 负责，保持独立。
			if child != root and _is_sway_node(child):
				continue
			_collect_merged_meshes(child, xform * (child as Node3D).transform, buckets, root)
		else:
			_collect_merged_meshes(child, xform, buckets, root)

static func _merge_transformed(entries: Array) -> ArrayMesh:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	for entry in entries:
		var mesh_instance: MeshInstance3D = entry["node"]
		var xform: Transform3D = entry["xform"]
		var normal_basis := xform.basis.inverse().transposed()
		var mesh := mesh_instance.mesh
		for surface in mesh.get_surface_count():
			var arrays := mesh.surface_get_arrays(surface)
			if arrays.size() <= Mesh.ARRAY_VERTEX or arrays[Mesh.ARRAY_VERTEX] == null:
				continue
			var base := vertices.size()
			var src_verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var src_normals: PackedVector3Array = PackedVector3Array()
			if arrays.size() > Mesh.ARRAY_NORMAL and arrays[Mesh.ARRAY_NORMAL] != null:
				src_normals = arrays[Mesh.ARRAY_NORMAL]
			for i in src_verts.size():
				vertices.append(xform * src_verts[i])
				normals.append((normal_basis * src_normals[i]).normalized() if i < src_normals.size() else Vector3.UP)
			if arrays.size() > Mesh.ARRAY_INDEX and arrays[Mesh.ARRAY_INDEX] != null:
				for index in (arrays[Mesh.ARRAY_INDEX] as PackedInt32Array):
					indices.append(base + index)
			else:
				for i in src_verts.size():
					indices.append(base + i)
	if vertices.is_empty():
		return null
	var out := []
	out.resize(Mesh.ARRAY_MAX)
	out[Mesh.ARRAY_VERTEX] = vertices
	out[Mesh.ARRAY_NORMAL] = normals
	out[Mesh.ARRAY_INDEX] = indices
	var merged := ArrayMesh.new()
	merged.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, out)
	return merged

## 摆动组的名字前缀：与 HeroCostumeParts 里被 `_record(..., sway_kind)` 登记的节点一致。
## 漏一个 → 那个组被烘进静态网格 → 跑动时它不摆（静默失效）。
## 多一个（把不摆的组也排除在合并外）→ 只是多几个 draw call，不会错。
##
## 注意 `Sash` / `Tasset` / `Skirt` 同时也是**躯干配件**的组名：它们在
## `_record(..., "skirt")` 里被登记成摆动组，所以必须整组保留。
const SWAY_PREFIXES := ["CapePanel", "CloakPanel", "Skirt", "FeatherBundle", "Tasset",
	"ScarfTail", "BannerFlag", "HaloRing", "BladeSash", "Sash0", "Tasset0"]

static func _is_sway_node(node: Node) -> bool:
	var node_name := str(node.name)
	for prefix in SWAY_PREFIXES:
		if node_name.begins_with(str(prefix)):
			return true
	return false

## 挂点下所有摆动节点（用于「就地合并」）。自顶向下，遇到就收，不深入。
static func _sway_nodes_under(anchor: Node3D) -> Array[Node3D]:
	var out: Array[Node3D] = []
	for child in anchor.get_children():
		if child is Node3D:
			_collect_sway_nodes(child as Node3D, out)
	return out

static func _collect_sway_nodes(node: Node3D, out: Array[Node3D]) -> void:
	if _is_sway_node(node):
		out.append(node)
		return
	for child in node.get_children():
		if child is Node3D:
			_collect_sway_nodes(child as Node3D, out)

## 把若干 MeshInstance3D（各自带 position/rotation/scale）烘成一个 ArrayMesh。
## 法线用逆转置矩阵变换，非等比缩放（护肩 dome 压扁到 0.38）才不会把光照算歪。
static func _merge_meshes(meshes: Array) -> ArrayMesh:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	var material: Material = null
	for entry in meshes:
		var mesh_instance := entry as MeshInstance3D
		var mesh := mesh_instance.mesh
		if material == null:
			material = mesh_instance.material_override
		var xform := mesh_instance.transform
		var normal_basis := xform.basis.inverse().transposed()
		for surface in mesh.get_surface_count():
			var arrays := mesh.surface_get_arrays(surface)
			if arrays.size() <= Mesh.ARRAY_VERTEX or arrays[Mesh.ARRAY_VERTEX] == null:
				continue
			var base := vertices.size()
			var src_verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var src_normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL] if arrays.size() > Mesh.ARRAY_NORMAL and arrays[Mesh.ARRAY_NORMAL] != null else PackedVector3Array()
			for i in src_verts.size():
				vertices.append(xform * src_verts[i])
				if i < src_normals.size():
					normals.append((normal_basis * src_normals[i]).normalized())
				else:
					normals.append(Vector3.UP)
			if arrays.size() > Mesh.ARRAY_INDEX and arrays[Mesh.ARRAY_INDEX] != null:
				for index in (arrays[Mesh.ARRAY_INDEX] as PackedInt32Array):
					indices.append(base + index)
			else:
				for i in src_verts.size():
					indices.append(base + i)
	if vertices.is_empty():
		return null
	var out := []
	out.resize(Mesh.ARRAY_MAX)
	out[Mesh.ARRAY_VERTEX] = vertices
	out[Mesh.ARRAY_NORMAL] = normals
	out[Mesh.ARRAY_INDEX] = indices
	var merged := ArrayMesh.new()
	merged.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, out)
	# 材质统一由调用方的 MeshInstance3D 提供（material_override），这里不烧进 surface。
	return merged

## 布料摆动：没有骨骼，靠每帧给「下摆 / 披风 / 围巾」写一个小角度。
##   - `moving` 决定幅度（站桩只呼吸，移动时后飘）；
##   - 相位按件缓存（见 parts 里的 phase 字段），否则五片披风会像一块板子。
static func sway(sway: Dictionary, time: float, moving: bool, speed: float) -> void:
	var amplitude := 0.10 if moving else 0.028
	var rate := clampf(1.4 + speed * 0.35, 1.4, 3.4)
	for kind in sway:
		var amount := amplitude
		var freq := rate
		if str(kind) == "banner":
			# 战旗更慢更大：旗面大，快摆会读成抽搐。
			amount *= 1.5
			freq *= 0.6
		elif str(kind) == "halo":
			# 星环不是布，是缓慢自转。
			for entry in sway[kind]:
				var halo: Node3D = entry.get("node")
				if halo != null:
					halo.rotation.y = time * 0.6 + float(entry.get("phase", 0.0))
			continue
		for entry in sway[kind]:
			var node: Node3D = entry.get("node")
			if node == null or not is_instance_valid(node):
				continue
			var phase := float(entry.get("phase", 0.0))
			var wave := sin(time * freq + phase)
			node.rotation.x = wave * amount
			node.rotation.z = cos(time * freq * 0.8 + phase) * amount * 0.5
