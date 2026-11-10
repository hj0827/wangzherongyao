extends RefCounted
class_name MonsterKit

## 野怪形象工具箱（纯表现层）：材质缓存 + 基本体拼装 + 量体对齐。
##
## 为什么程序化拼模型，而不是继续找现成 glb：
##   1. 授权留痕（docs/gap-analysis-vs-honor-of-kings.md §5.1）：现成模型的 glb 里
##      连 license 字段都没有，野怪再引一套资产等于再加一处合规风险；
##   2. 包体与显存（同文档 §12）：基本体 + 共享材质，移动端没有额外贴图与骨骼开销；
##   3. 识别度：俯视 20 米机位下玩家读的是**剪影 + 配色**，不是面数。
##
## 材质全部走静态缓存：12 只野怪同屏时共用同一批 StandardMaterial3D，
## 不会每只怪各建一份（硬规则 4 的精神：战斗里不新建材质）。

const ModelUtils = preload("res://scripts/game/model_utils.gd")

static var _materials: Dictionary = {}

# ---------------------------------------------------------------------------
# 材质
# ---------------------------------------------------------------------------

## 石身：粗糙、几乎没有高光。specular 压低是关键 —— 默认高光会让石头读成塑料。
static func stone(color: Color, roughness := 0.94) -> StandardMaterial3D:
	var key := "stone|%s|%.2f" % [color.to_html(false), roughness]
	var material: StandardMaterial3D = _materials.get(key, null)
	if material == null:
		material = StandardMaterial3D.new()
		material.albedo_color = color
		material.roughness = roughness
		material.metallic = 0.0
		material.specular = 0.1
		_materials[key] = material
	return material

## 兽皮 / 甲壳：比石头亮一点、带一点点金属感，让野兽和石像看得出是两种材质体系。
static func hide_mat(color: Color, roughness := 0.72) -> StandardMaterial3D:
	var key := "hide|%s|%.2f" % [color.to_html(false), roughness]
	var material: StandardMaterial3D = _materials.get(key, null)
	if material == null:
		material = StandardMaterial3D.new()
		material.albedo_color = color
		material.roughness = roughness
		material.metallic = 0.08
		material.specular = 0.28
		_materials[key] = material
	return material

## 甲片 / 骨 / 牙：更亮更硬。
static func chitin(color: Color) -> StandardMaterial3D:
	var key := "chitin|%s" % color.to_html(false)
	var material: StandardMaterial3D = _materials.get(key, null)
	if material == null:
		material = StandardMaterial3D.new()
		material.albedo_color = color
		material.roughness = 0.42
		material.metallic = 0.3
		material.specular = 0.5
		_materials[key] = material
	return material

## 宝石：受光但自发光。石像胸口那颗晶体在背光面也要亮，否则俯视下只剩一块石头。
static func gem(color: Color, energy := 2.2) -> StandardMaterial3D:
	var key := "gem|%s|%.2f" % [color.to_html(false), energy]
	var material: StandardMaterial3D = _materials.get(key, null)
	if material == null:
		material = StandardMaterial3D.new()
		material.albedo_color = color.darkened(0.45)
		material.roughness = 0.22
		material.metallic = 0.4
		material.emission_enabled = true
		material.emission = color
		material.emission_energy_multiplier = energy
		_materials[key] = material
	return material

## 无光照自发光：眼睛、符文、火星。屏幕上就是一块纯色高光，不会被阴影吃掉。
static func glow(color: Color, energy := 1.6) -> StandardMaterial3D:
	var key := "glow|%s|%.2f" % [color.to_html(false), energy]
	var material: StandardMaterial3D = _materials.get(key, null)
	if material == null:
		material = StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.albedo_color = color
		material.emission_enabled = true
		material.emission = color
		material.emission_energy_multiplier = energy
		_materials[key] = material
	return material

## 加色半透明：脚下光晕、首领威压圈。gl_compatibility 下加色混合最稳。
static func aura(color: Color, alpha := 0.4) -> StandardMaterial3D:
	var key := "aura|%s|%.2f" % [color.to_html(false), alpha]
	var material: StandardMaterial3D = _materials.get(key, null)
	if material == null:
		material = StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		var tinted := Color(color.r, color.g, color.b, alpha)
		material.albedo_color = tinted
		material.emission_enabled = true
		material.emission = color
		material.emission_energy_multiplier = 1.0
		# 光晕不写深度：贴在草地上的一圈加色光，写深度会切掉后面的草叶。
		material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
		_materials[key] = material
	return material

static func material_count() -> int:
	return _materials.size()

# ---------------------------------------------------------------------------
# 基本体
# ---------------------------------------------------------------------------

## 分组：需要「整体绕某个关节转」的部件（腿、翅膀、轨道碎片）都挂在分组下，
## 关节旋转由 UnitVisual 的程序化动画驱动，不需要骨骼。
static func group(parent: Node3D, node_name: String, pos := Vector3.ZERO) -> Node3D:
	var node := Node3D.new()
	node.name = node_name
	node.position = pos
	parent.add_child(node)
	return node

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
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(instance)
	return instance

static func box(
	parent: Node3D,
	size: Vector3,
	material: Material,
	pos: Vector3,
	rot_deg := Vector3.ZERO
) -> MeshInstance3D:
	return part(parent, _box_mesh(size), material, pos, rot_deg)

static func ball(
	parent: Node3D,
	radius: float,
	material: Material,
	pos: Vector3,
	part_scale := Vector3.ONE,
	rot_deg := Vector3.ZERO
) -> MeshInstance3D:
	return part(parent, _sphere_mesh(radius), material, pos, rot_deg, part_scale)

## 圆柱 / 蹄腿段 / 石柱。
static func rod(
	parent: Node3D,
	radius: float,
	height: float,
	material: Material,
	pos: Vector3,
	rot_deg := Vector3.ZERO,
	sides := 8
) -> MeshInstance3D:
	return part(parent, _cylinder_mesh(radius, height, sides), material, pos, rot_deg)

## 尖刺 / 角 / 獠牙：圆柱退化成锥体，低面数就有棱。
static func spike(
	parent: Node3D,
	radius: float,
	height: float,
	material: Material,
	pos: Vector3,
	rot_deg := Vector3.ZERO,
	sides := 6
) -> MeshInstance3D:
	return part(parent, _cylinder_mesh(0.0, height, sides, radius), material, pos, rot_deg)

# ---------------------------------------------------------------------------
# 网格缓存
# ---------------------------------------------------------------------------
#
# 形象是「有限的几种尺寸 × 有限的基本体」，所以网格可以按尺寸复用。
# 野怪会在战斗中重生 / 重新进入视野时重建视图，如果每次都 new 一份 BoxMesh，
# 一只首领就是二十来个网格资源 —— 这正是硬规则 4 想避免的那类战斗中分配。
# 缩放一律放在 MeshInstance3D.scale 或根节点上，网格本身只读，才能安全共享。

static var _meshes: Dictionary = {}

static func _box_mesh(size: Vector3) -> BoxMesh:
	var key := "box|%.3f|%.3f|%.3f" % [size.x, size.y, size.z]
	var mesh: BoxMesh = _meshes.get(key, null)
	if mesh == null:
		mesh = BoxMesh.new()
		mesh.size = size
		_meshes[key] = mesh
	return mesh

static func _sphere_mesh(radius: float) -> SphereMesh:
	var key := "ball|%.3f" % radius
	var mesh: SphereMesh = _meshes.get(key, null)
	if mesh == null:
		mesh = SphereMesh.new()
		mesh.radius = radius
		mesh.height = radius * 2.0
		mesh.radial_segments = 14
		mesh.rings = 8
		_meshes[key] = mesh
	return mesh

## top_radius = 0 即锥体；尖刺与圆柱共用同一条缓存键规则。
static func _cylinder_mesh(top_radius: float, height: float, sides: int, bottom_radius := -1.0) -> CylinderMesh:
	var bottom := top_radius if bottom_radius < 0.0 else bottom_radius
	var key := "cyl|%.3f|%.3f|%.3f|%d" % [top_radius, bottom, height, sides]
	var mesh: CylinderMesh = _meshes.get(key, null)
	if mesh == null:
		mesh = CylinderMesh.new()
		mesh.top_radius = top_radius
		mesh.bottom_radius = bottom
		mesh.height = height
		mesh.radial_segments = sides
		_meshes[key] = mesh
	return mesh

static func mesh_count() -> int:
	return _meshes.size()

## 晶石 / 背鳍 / 尾羽：三棱柱，天然带一条锋利的中脊。
static func shard(
	parent: Node3D,
	size: Vector3,
	material: Material,
	pos: Vector3,
	rot_deg := Vector3.ZERO,
	lean := 0.5
) -> MeshInstance3D:
	var key := "shard|%.3f|%.3f|%.3f|%.2f" % [size.x, size.y, size.z, lean]
	var mesh: PrismMesh = _meshes.get(key, null)
	if mesh == null:
		mesh = PrismMesh.new()
		mesh.size = size
		mesh.left_to_right = lean
		mesh.subdivide_width = 0
		mesh.subdivide_height = 0
		_meshes[key] = mesh
	return part(parent, mesh, material, pos, rot_deg)

static func ring(
	parent: Node3D,
	inner: float,
	outer: float,
	material: Material,
	pos: Vector3,
	rot_deg := Vector3.ZERO
) -> MeshInstance3D:
	var key := "ring|%.3f|%.3f" % [inner, outer]
	var mesh: TorusMesh = _meshes.get(key, null)
	if mesh == null:
		mesh = TorusMesh.new()
		mesh.inner_radius = inner
		mesh.outer_radius = outer
		mesh.rings = 24
		mesh.ring_segments = 6
		_meshes[key] = mesh
	return part(parent, mesh, material, pos, rot_deg)

## 一节肢体：上段 + 下段 + 脚。四条腿的野兽全靠这个拼，改尺寸就能从狼腿变成猪腿。
static func leg(
	parent: Node3D,
	pos: Vector3,
	upper: Vector3,
	lower: Vector3,
	upper_material: Material,
	lower_material: Material,
	foot: Vector3
) -> Node3D:
	var joint := group(parent, "Leg", pos)
	box(joint, upper, upper_material, Vector3(0.0, -upper.y * 0.5, 0.0))
	box(joint, lower, lower_material, Vector3(0.0, -upper.y - lower.y * 0.5, 0.0))
	box(joint, foot, lower_material, Vector3(0.0, -upper.y - lower.y - foot.y * 0.5, foot.z * 0.5))
	return joint

# ---------------------------------------------------------------------------
# 量体
# ---------------------------------------------------------------------------

## 把整棵树按高度等比缩放到 target_height，并把**底面中心**摆到局部原点。
##
## 为什么必须做这一步：血条高度、脚下环、碰撞半径全部按「米」算，
## 形象差 20% 就会读成「看着小、实际被打范围大」。所以形象一律先建，
## 建完再统一对齐，不允许每个 builder 自己手调 scale。
static func fit_height(root: Node3D, target_height: float) -> float:
	var box := ModelUtils.relative_aabb(root)
	if box.size.y <= 0.0001:
		return 1.0
	var factor := target_height / box.size.y
	var center := box.get_center()
	root.scale = Vector3.ONE * factor
	root.position = Vector3(-center.x * factor, -box.position.y * factor, -center.z * factor)
	return factor

static func measure(root: Node3D) -> AABB:
	return ModelUtils.relative_aabb(root)

## 收尾：量体对齐 + 组装形态字典。
##
## 所有 builder 必须走这里返回，UnitVisual 只认这一份键名 —— 少一个键就是
## 「野怪站着不动」这种静默失效（读不存在的键返回 null，不报错）。
static func finish(form: String, root: Node3D, body: Node3D, height: float, bar_width: float) -> Dictionary:
	root.name = form
	fit_height(root, height)
	var no_legs: Array[Node3D] = []
	var no_wings: Array[Node3D] = []
	var no_orbits: Array[Node3D] = []
	var no_pulses: Array[MeshInstance3D] = []
	return {
		"form": form,
		"root": root,
		"body": body,
		"height": height,
		"bar_width": bar_width,
		"legs": no_legs,
		"wings": no_wings,
		"orbits": no_orbits,
		"pulses": no_pulses,
		"tail": null,
	}
