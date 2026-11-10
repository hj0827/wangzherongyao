extends "res://tests/test_base.gd"

# 基地广场法阵/同心环（P1 STRUCT-04 的第一版）。
# 旧广场是一块圆柱贴图，俯视像木地板；现在加贴地旋转符阵 + 三道团队色环。

const Arena = preload("res://scripts/game/arena.gd")

func _base(alive := true) -> Dictionary:
	return {
		"id": 41, "type": "base", "team": "blue", "x": 46.0, "y": -46.0,
		"hp": 500.0 if alive else 0.0, "max_hp": 500.0, "alive": alive,
		"shield": 0.0, "shield_max": 0.0, "guards_alive": 0,
		"vulnerable": true, "radius": 4.0, "range": 9.0,
	}

func test_base_plaza_has_sigil_and_three_rings() -> void:
	var arena: Node3D = Arena.new()
	arena._structures_root = Node3D.new()
	arena.add_child(arena._structures_root)
	arena._sync_structures({"entities": [_base(true)]}, true)
	var record: Dictionary = arena._structure_views.get(41, {})
	if record.is_empty():
		check(false, "主堡视图必须创建")
		arena.free()
		return
	var root: Node3D = record.get("root")
	var sigil := root.find_child("base_sigil_blue", true, false) as MeshInstance3D
	check(sigil != null, "基地广场要有贴地符阵")
	if sigil:
		var material := sigil.material_override as ShaderMaterial
		check(material != null, "符阵用 camp_sigil shader")
		if material:
			check(material.shader.code.contains("spin_speed"), "符阵必须带旋转刻线")
	for i in 3:
		check(root.find_child("base_ring_blue_%d" % i, true, false) != null, "第 %d 道同心环要存在" % i)
	arena.free()

func test_base_plaza_fx_hide_after_destruction() -> void:
	var arena: Node3D = Arena.new()
	arena._structures_root = Node3D.new()
	arena.add_child(arena._structures_root)
	arena._sync_structures({"entities": [_base(true)]}, true)
	var record: Dictionary = arena._structure_views.get(41, {})
	var root: Node3D = record.get("root")
	var sigil := root.find_child("base_sigil_blue", true, false) as MeshInstance3D
	var ring := root.find_child("base_ring_blue_0", true, false) as MeshInstance3D
	arena._sync_structures({"entities": [_base(false)]}, false)
	check(not sigil.visible, "基地摧毁后符阵要隐藏")
	check(not ring.visible, "基地摧毁后同心环要隐藏")
	arena.free()
