extends "res://tests/test_base.gd"

# 墙端岩石变体（P0 视觉升级，WALL-01 的岩石部分）。
# 同一块 Rock.glb 复制二十次会读成一排相同轮廓；墙端交替使用 Rock 与 Rock_Group。

const Arena = preload("res://scripts/game/arena.gd")

func test_wall_ends_use_more_than_one_rock_silhouette() -> void:
	var arena: Node3D = Arena.new()
	arena._props_root = Node3D.new()
	arena.add_child(arena._props_root)
	arena._build_map_features()
	var single := 0
	var group := 0
	for child in arena._props_root.get_children():
		if not str(child.name).begins_with("wall_end_"):
			continue
		match str(child.get_meta("end_variant", "")):
			"single":
				single += 1
			"group":
				group += 1
	gt(float(single), 0.0, "墙端至少要保留一部分单块岩石")
	gt(float(group), 0.0, "墙端至少要有一部分岩石群剪影")
	arena.free()
