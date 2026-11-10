extends "res://tests/test_base.gd"

# 建筑摧毁残骸（P0 视觉升级）。
#
# 旧版 _sync_structures 在 alive=false 时直接 root.visible=false —— 塔整座消失，
# 玩家看不到"这里曾经有塔"。现在要求：root 保留，活体部件隐藏，残骸显示。

const Arena = preload("res://scripts/game/arena.gd")

func _tower(alive := true) -> Dictionary:
	return {
		"id": 31, "type": "tower", "team": "red", "x": 12.0, "y": 8.0,
		"hp": 100.0 if alive else 0.0, "max_hp": 100.0, "alive": alive,
		"tier": "outer", "vulnerable": true, "radius": 1.0,
	}

func _base(alive := true) -> Dictionary:
	return {
		"id": 32, "type": "base", "team": "blue", "x": 46.0, "y": -46.0,
		"hp": 500.0 if alive else 0.0, "max_hp": 500.0, "alive": alive,
		"shield": 0.0, "shield_max": 0.0, "guards_alive": 0,
		"vulnerable": true, "radius": 4.0, "range": 9.0,
	}

func test_tower_keeps_rubble_after_death() -> void:
	var arena: Node3D = Arena.new()
	arena._structures_root = Node3D.new()
	arena.add_child(arena._structures_root)
	arena._sync_structures({"entities": [_tower(true)]}, true)
	var record: Dictionary = arena._structure_views.get(31, {})
	check(not record.is_empty(), "塔视图必须创建")
	if record.is_empty():
		arena.free()
		return
	var rubble: Node3D = record.get("rubble")
	var model: Node3D = record.get("model")
	check(rubble != null and not rubble.visible, "存活时残骸隐藏")
	check(model != null and model.visible, "存活时塔身显示")
	arena._sync_structures({"entities": [_tower(false)]}, false)
	var root: Node3D = record.get("root")
	check(root.visible, "死亡后根节点保留（不能整座消失）")
	check(rubble.visible, "死亡后残骸显示")
	check(not model.visible, "死亡后塔身隐藏")
	var bar: MeshInstance3D = record.get("bar")
	check(bar != null and not bar.get_parent().visible, "死亡后血条隐藏")
	arena.free()

func test_base_keeps_rubble_after_death() -> void:
	var arena: Node3D = Arena.new()
	arena._structures_root = Node3D.new()
	arena.add_child(arena._structures_root)
	arena._sync_structures({"entities": [_base(true)]}, true)
	var record: Dictionary = arena._structure_views.get(32, {})
	check(not record.is_empty(), "主堡视图必须创建")
	if record.is_empty():
		arena.free()
		return
	arena._sync_structures({"entities": [_base(false)]}, false)
	var root: Node3D = record.get("root")
	check(root.visible, "主堡死亡后根节点保留")
	check((record.get("rubble") as Node3D).visible, "主堡死亡后残骸显示")
	check(not (record.get("model") as Node3D).visible, "主堡死亡后水晶隐藏")
	arena.free()

func test_rubble_does_not_add_collision_metadata() -> void:
	# 残骸是纯表现：不能再挂 radius / collision 之类会被逻辑读到的字段。
	var arena: Node3D = Arena.new()
	var rubble: Node3D = arena._build_structure_rubble("tower", Color(0.3, 0.5, 1.0), 1.0, 7)
	check(rubble.get_meta("rubble_kind", "") == "tower", "残骸要标记类型，便于调试")
	check(not rubble.has_meta("radius"), "残骸不能伪装成碰撞体")
	rubble.free()
	arena.free()
