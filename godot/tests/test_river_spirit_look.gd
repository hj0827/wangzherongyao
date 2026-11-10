extends "res://tests/test_base.gd"

# 河道之灵形象（P1 MON-07 的第一版）。
# 旧版是一颗球 + 一个环；现在有水灵该有的头/眼/鳍/尾/伴游光点，俯视能读出朝向。

const UnitVisual = preload("res://scripts/game/unit_visual.gd")

func test_spirit_has_head_tail_fins_and_orbit() -> void:
	var view := UnitVisual.new()
	view.setup("monster", "neutral", "spirit", "河道之灵", false, "blue")
	check(view.model_root != null, "河道之灵必须有模型")
	if view.model_root == null:
		view.free()
		return
	for part in ["SpiritBody", "SpiritHead", "SpiritTail", "SpiritOrbit", "SpiritFinL", "SpiritFinR", "SpiritEyeL", "SpiritEyeR"]:
		check(view.model_root.find_child(part, true, false) != null, "缺少部件：%s" % part)
	var meshes := 0
	for node in view.model_root.find_children("*", "MeshInstance3D", true, false):
		meshes += 1
	gt(float(meshes), 10.0, "水灵至少要有 10 个可见网格（身体/头/眼/鳍/尾/光点）")
	var body := view.model_root.find_child("SpiritBody", true, false) as MeshInstance3D
	if body:
		var material := body.material_override as StandardMaterial3D
		check(material != null and material.emission_enabled, "身体要自发光")
		if material:
			gt(material.emission.b, material.emission.r, "水灵自发光偏青蓝")
	view.free()
