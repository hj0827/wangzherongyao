extends "res://tests/test_base.gd"

# 击杀信息流头像（P1 UI-04 的第一版）。
# 英雄击杀：击杀者头像 + 文字 + 受害者头像；塔/小兵击杀只显示受害者头像。
# 头像复用立绘裁切缓存，不新增资产。

const GameHUD = preload("res://scripts/ui/game_hud.gd")

func _hud() -> Control:
	var hud: Control = GameHUD.new()
	hud.setup("p1", "blue", "blade", "苍刃", false, false)
	hud._ready()
	# _ready 里建节点，进树是为了 create_tween 有 SceneTree；_ready 自带幂等闸。
	var tree := Engine.get_main_loop() as SceneTree
	tree.root.add_child(hud)
	hud._apply_layout()
	return hud

func _count_avatar_textures(node: Node) -> int:
	var count := 0
	if node is TextureRect and (node as TextureRect).texture != null:
		count += 1
	for child in node.get_children():
		count += _count_avatar_textures(child)
	return count

func test_hero_kill_feed_has_two_avatars() -> void:
	var hud := _hud()
	hud.add_kill_feed("苍刃", "blade", "星璃", "mage", Color.WHITE, true)
	var row: Node = hud._feed_box.get_child(hud._feed_box.get_child_count() - 1)
	eq(_count_avatar_textures(row), 2, "英雄击杀要有击杀者 + 受害者两张头像")
	hud.free()

func test_tower_kill_feed_has_only_victim_avatar() -> void:
	var hud := _hud()
	hud.add_kill_feed("防御塔", "", "星璃", "mage", Color.WHITE, false)
	var row: Node = hud._feed_box.get_child(hud._feed_box.get_child_count() - 1)
	eq(_count_avatar_textures(row), 1, "非英雄击杀只显示受害者头像")
	hud.free()

func test_feed_keeps_only_five_rows() -> void:
	var hud := _hud()
	for i in 8:
		hud.add_kill_feed("苍刃", "blade", "星璃", "mage", Color.WHITE, true)
	eq(hud._feed_box.get_child_count(), 5, "信息流最多保留 5 条")
	hud.free()
