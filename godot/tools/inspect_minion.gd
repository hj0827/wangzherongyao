extends SceneTree
func _initialize() -> void:
	for path in ["res://assets/characters/Skeleton_Minion.glb", "res://assets/characters/Skeleton_Warrior.glb", "res://assets/characters/Skeleton_Mage.glb", "res://assets/characters/Skeleton_Rogue.glb"]:
		var scene: PackedScene = load(path)
		var node = scene.instantiate()
		root.add_child(node)
		print("== ", path.get_file())
		for ap in node.find_children("*", "AnimationPlayer", true, false):
			var player: AnimationPlayer = ap
			for lib_name in player.get_animation_library_list():
				var lib = player.get_animation_library(lib_name)
				for anim_name in lib.get_animation_list():
					print("  ", anim_name, " ", lib.get_animation(anim_name).length)
		node.queue_free()
	quit()
