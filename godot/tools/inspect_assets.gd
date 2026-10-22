extends SceneTree

func _initialize() -> void:
	var ual1: PackedScene = load("res://assets/animations/ual1.glb")
	var ual2: PackedScene = load("res://assets/animations/ual2.glb")
	var names := {}
	for scene in [ual1, ual2]:
		var source: Node = scene.instantiate()
		root.add_child(source)
		for node in source.find_children("*", "AnimationPlayer", true, false):
			var player: AnimationPlayer = node
			for lib_name in player.get_animation_library_list():
				var lib := player.get_animation_library(lib_name)
				for anim_name in lib.get_animation_list():
					var anim := lib.get_animation(anim_name)
					names[anim_name] = "%.2fs/%d tracks" % [anim.length, anim.get_track_count()]
		source.queue_free()
	var sorted_names: Array = names.keys()
	sorted_names.sort()
	print("=== ANIMATIONS (%d) ===" % sorted_names.size())
	for name in sorted_names:
		print(name, "  ", names[name])
	var assets := [
		"res://assets/characters/hero_warrior.glb",
		"res://assets/characters/hero_mage.glb",
		"res://assets/characters/outfit_ranger_m.glb",
		"res://assets/characters/outfit_ranger_f.glb",
		"res://assets/characters/outfit_peasant_m.glb",
		"res://assets/characters/hair_long.glb",
		"res://assets/characters/hair_buns.glb",
		"res://assets/characters/hair_beard.glb",
		"res://assets/characters/hair_buzzed.glb",
		"res://assets/characters/Skeleton_Minion.glb",
		"res://assets/characters/Skeleton_Warrior.glb",
		"res://assets/characters/Skeleton_Mage.glb",
		"res://assets/characters/Skeleton_Rogue.glb",
		"res://assets/weapons/Claymore.glb",
		"res://assets/weapons/Scythe.glb",
		"res://assets/weapons/Hammer_Double.glb",
		"res://assets/weapons/Bow_Wooden2.glb",
		"res://assets/environment/WatchTower_SecondAge_Level3.glb",
		"res://assets/environment/Temple_FirstAge_Level3.glb",
		"res://assets/environment/TownCenter_SecondAge_Level3.glb",
		"res://assets/environment/Resource_PineTree_Group.glb",
		"res://assets/environment/Resource_Tree_Group.glb",
		"res://assets/environment/Rock_Group.glb",
		"res://assets/environment/Mountain_Group_1.glb",
		"res://assets/environment/Wall_FirstAge.glb",
		"res://assets/environment/Barracks_FirstAge_Level3.glb",
	]
	print("=== MODELS ===")
	for path in assets:
		var scene: PackedScene = load(path)
		if scene == null:
			print(path, " FAILED")
			continue
		var node: Node3D = scene.instantiate()
		root.add_child(node)
		var aabb := _model_aabb(node)
		var skeletons: Array = []
		for sk in node.find_children("*", "Skeleton3D", true, false):
			skeletons.append(str(node.get_path_to(sk)))
		var anims: Array = []
		for ap in node.find_children("*", "AnimationPlayer", true, false):
			anims.append(str(node.get_path_to(ap)))
		print(path.get_file(), " aabb=", aabb, " skel=", skeletons, " anim=", anims)
		node.queue_free()
	quit()

func _model_aabb(node: Node) -> AABB:
	var result := AABB()
	var first := true
	for mesh in node.find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = mesh
		if mi.mesh == null:
			continue
		var box: AABB = mi.global_transform * mi.get_aabb()
		if first:
			result = box
			first = false
		else:
			result = result.merge(box)
	return result
