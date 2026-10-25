extends RefCounted

class_name ModelUtils

static func relative_aabb(node: Node, xform: Transform3D = Transform3D.IDENTITY) -> AABB:
	var box := AABB()
	var found := false
	var node_xform := xform
	if node is Node3D:
		node_xform = xform * (node as Node3D).transform
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.mesh != null:
			var mesh_box: AABB = node_xform * mesh_instance.get_aabb()
			box = mesh_box
			found = true
	for child in node.get_children():
		var child_box := relative_aabb(child, node_xform)
		if child_box.size == Vector3.ZERO:
			continue
		if not found:
			box = child_box
			found = true
		else:
			box = box.merge(child_box)
	return box

static var _scene_box_cache: Dictionary = {}

static func fit_scene(scene: PackedScene, target_height: float, max_width := 0.0, girth := 1.0) -> Node3D:
	var wrapper := Node3D.new()
	var fit_root := Node3D.new()
	wrapper.add_child(fit_root)
	var model: Node3D = scene.instantiate()
	fit_root.add_child(model)
	var path := scene.resource_path
	var box: AABB
	if path != "" and _scene_box_cache.has(path):
		box = _scene_box_cache[path]
	else:
		box = relative_aabb(model)
		if path != "":
			_scene_box_cache[path] = box
	if box.size.y <= 0.000001:
		return wrapper
	var factor := target_height / box.size.y
	if max_width > 0.0:
		var width := maxf(box.size.x, box.size.z)
		if width > 0.000001:
			factor = minf(factor, max_width / width)
	fit_root.scale = Vector3(girth, 1.0, girth) * factor
	var center := box.get_center()
	fit_root.position = Vector3(-center.x * factor * girth, -box.position.y * factor, -center.z * factor * girth)
	return wrapper

static func tint(root: Node, color: Color, amount: float) -> void:
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.mesh == null:
			continue
		for surface in mesh_instance.mesh.get_surface_count():
			var material := mesh_instance.get_active_material(surface)
			if material is StandardMaterial3D:
				var tinted := (material as StandardMaterial3D).duplicate() as StandardMaterial3D
				tinted.albedo_color = tinted.albedo_color.lerp(color, amount)
				mesh_instance.set_surface_override_material(surface, tinted)

# 把一份材质强行盖到整棵子树的每个网格面上。
# 用途：glb 自带材质（比如 Rock.glb 的灰白石头）和程序化石壁贴在一起时，
# 一眼就能看出是两套东西。共用一份材质才能读成同一块山体。
static func override_material(root: Node, material: Material) -> void:
	if material == null:
		return
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.mesh == null:
			continue
		for surface in mesh_instance.mesh.get_surface_count():
			mesh_instance.set_surface_override_material(surface, material)

static func enable_shadows(root: Node, cast := true) -> void:
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if cast else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

static func load_texture(path: String) -> Texture2D:
	var texture: Texture2D = load(path)
	if texture:
		texture.set_meta("path", path)
	return texture

static func make_ground_material(diffuse: String, normal: String, roughness: String, uv_scale: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_texture = load_texture(diffuse)
	material.normal_enabled = true
	material.normal_texture = load_texture(normal)
	material.normal_scale = 0.85
	material.roughness_texture = load_texture(roughness)
	material.roughness = 1.0
	material.uv1_scale = Vector3(uv_scale, uv_scale, 1.0)
	material.uv1_triplanar = false
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return material

static func make_flat_material(color: Color, emission := 0.0) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if emission > 0.0:
		material.emission_enabled = true
		material.emission = color
		material.emission_energy_multiplier = emission
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return material
