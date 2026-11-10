extends "res://tests/test_base.gd"

# 防御塔层级束带（P1 STRUCT-03 的第一版）。
# 内塔/高地塔不只靠体型缩放；塔冠下多一条逐级加宽的团队色束带。

const Arena = preload("res://scripts/game/arena.gd")

func _tower(id: int, tier: String, alive := true) -> Dictionary:
	return {
		"id": id, "type": "tower", "team": "red", "x": 10.0 + float(id), "y": 6.0,
		"hp": 100.0 if alive else 0.0, "max_hp": 100.0, "alive": alive,
		"tier": tier, "vulnerable": true, "radius": 1.0,
	}

func test_tier_band_radius_grows_with_tier() -> void:
	var arena: Node3D = Arena.new()
	arena._structures_root = Node3D.new()
	arena.add_child(arena._structures_root)
	arena._sync_structures({"entities": [
		_tower(1, "outer"), _tower(2, "inner"), _tower(3, "high"),
	]}, true)
	var radii := {}
	for tier in ["outer", "inner", "high"]:
		var record: Dictionary = {}
		for id in [1, 2, 3]:
			var candidate: Dictionary = arena._structure_views.get(id, {})
			if str(candidate.get("tier", "")) == tier:
				record = candidate
				break
		var root: Node3D = record.get("root")
		var band := root.find_child("tier_band_" + tier, true, false) as MeshInstance3D
		check(band != null, "%s 塔要有层级束带" % tier)
		if band:
			var torus := band.mesh as TorusMesh
			radii[tier] = torus.outer_radius
	gt(float(radii.get("inner", 0.0)), float(radii.get("outer", 0.0)), "内塔束带比外塔宽")
	gt(float(radii.get("high", 0.0)), float(radii.get("inner", 0.0)), "高地塔束带比内塔宽")
	arena.free()

func test_tier_band_hides_after_death() -> void:
	var arena: Node3D = Arena.new()
	arena._structures_root = Node3D.new()
	arena.add_child(arena._structures_root)
	arena._sync_structures({"entities": [_tower(1, "high")]}, true)
	var record: Dictionary = arena._structure_views.get(1, {})
	var root: Node3D = record.get("root")
	var band := root.find_child("tier_band_high", true, false) as MeshInstance3D
	arena._sync_structures({"entities": [_tower(1, "high", false)]}, false)
	check(not band.visible, "塔毁后层级束带要隐藏")
	arena.free()
