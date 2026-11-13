extends SceneTree

## 临时探针：无头构建两座水晶，打印 AABB / 节点清单 / 淡化部件，验证几何与契约。
## 用法：godot --headless --path godot --script res://tools/crystal_probe.gd

const CrystalVisual = preload("res://scripts/game/crystal_visual.gd")
const ModelUtils = preload("res://scripts/game/model_utils.gd")

func _initialize() -> void:
	for team in ["blue", "red"]:
		var color := Color(0.22, 0.6, 1.0) if team == "blue" else Color(1.0, 0.32, 0.26)
		var state := CrystalVisual.build(color, team)
		var root: Node3D = state.node
		var box := ModelUtils.relative_aabb(root)
		print("[%s] aabb pos=%s size=%s" % [team, str(box.position), str(box.size)])
		var meshes := root.find_children("*", "MeshInstance3D", true, false)
		print("[%s] meshes=%d fade=%d noshadow=%d" % [team, meshes.size(), state.fade_parts.size(), state.no_shadow_parts.size()])
		for mesh in meshes:
			var mi := mesh as MeshInstance3D
			var mat := mi.material_override
			var kind := "?"
			if mat is StandardMaterial3D:
				kind = "std/a=%.2f" % (mat as StandardMaterial3D).albedo_color.a
			elif mat is ShaderMaterial:
				kind = "shader"
			print("  %-18s %-12s %s surfaces=%d" % [mi.name, kind, str(mi.get_aabb().size), mi.mesh.get_surface_count() if mi.mesh else 0])
		var names: Array[String] = []
		for part in state.fade_parts:
			names.append(str((part as Node).name))
		print("[%s] fade parts: %s" % [team, str(names)])
		print("[%s] shard0 t0=%s t1=%s" % [team, str(CrystalVisual.shard_orbit(0, 0.0)), str(CrystalVisual.shard_orbit(0, 1.0))])
		print("[%s] mesh cache=%d" % [team, CrystalVisual.mesh_count()])
		root.free()
	quit()
