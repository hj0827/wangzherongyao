extends "res://tests/test_base.gd"

# 装备图标：商店每一件、背包每一格、计分板每一格都必须有图。
#
# 这一组守的是「资产在 + 代码引用」两头：
#  - 只放 png 不写 .import，编辑器里能看见，导出包里 load() 直接失败；
#  - 只改 UI 不加图，TextureRect 是空的，格子看着像坏了，但没有任何报错。
# 所以每条都要求具体数量/尺寸，而不是 check(tex != null)。

const GameTheme = preload("res://scripts/ui/game_theme.gd")
const ItemShop = preload("res://sim/item_shop.gd")
const ShopPanel = preload("res://scripts/ui/shop_panel.gd")
const Scoreboard = preload("res://scripts/ui/scoreboard.gd")

# ---------------------------------------------------------------- 资产

func test_every_catalogue_item_has_a_source_png_and_an_import() -> void:
	var missing_png: Array[String] = []
	var missing_import: Array[String] = []
	for item_id in ItemShop.CATALOGUE:
		var path := GameTheme.item_icon_path(str(item_id))
		if not FileAccess.file_exists(path):
			missing_png.append(str(item_id))
		# .import 不在 = 资源没进导入管线，导出包里 load() 会返回 null。
		if not FileAccess.file_exists(path + ".import"):
			missing_import.append(str(item_id))
	check(missing_png.is_empty(), "items without an icon png: %s" % ", ".join(missing_png))
	check(missing_import.is_empty(), "items without a .import file: %s" % ", ".join(missing_import))
	eq(ItemShop.CATALOGUE.size(), 8, "catalogue size (icons are authored one per item)")

func test_each_icon_loads_as_a_square_texture() -> void:
	var loaded := 0
	for item_id in ItemShop.CATALOGUE:
		var path := GameTheme.item_icon_path(str(item_id))
		if not ResourceLoader.exists(path):
			check(false, "icon not importable: %s" % path)
			continue
		var res := load(path)
		if not (res is Texture2D):
			check(false, "icon is not a Texture2D: %s" % path)
			continue
		var tex := res as Texture2D
		loaded += 1
		eq(tex.get_width(), tex.get_height(), "icon must be square: %s" % path)
		check(tex.get_width() >= 64, "icon too small for a 52px cell: %s is %dpx" % [path, tex.get_width()])
	eq(loaded, ItemShop.CATALOGUE.size(), "every icon must load")

# ---------------------------------------------------------------- 主题缓存

func test_item_icon_helper_resamples_to_the_requested_size() -> void:
	var big := GameTheme.item_icon("iron_sword", 52)
	var small := GameTheme.item_icon("iron_sword", 26)
	check(big != null, "52px icon should exist")
	check(small != null, "26px icon should exist")
	if big == null or small == null:
		return
	eq(big.get_width(), 52, "icon is downsampled to the requested width")
	eq(big.get_height(), 52, "icon is downsampled to the requested height")
	eq(small.get_width(), 26, "a smaller request yields a smaller texture")
	check(big != small, "different sizes must not share one cache entry")

func test_item_icon_helper_caches_by_id_and_size() -> void:
	# 商店每次刷新都会取图标；不缓存就是每帧重新解压 + 重采样。
	var a := GameTheme.item_icon("boots", 34)
	var b := GameTheme.item_icon("boots", 34)
	check(a != null, "boots icon should exist")
	check(a == b, "repeated lookups must reuse the cached texture instance")

func test_unknown_item_degrades_instead_of_crashing() -> void:
	check(not GameTheme.has_item_icon("no_such_item"), "unknown id must report no icon")
	var tex := GameTheme.item_icon("no_such_item", 32)
	check(tex == null, "unknown id returns null so callers can draw a placeholder")
	# 缓存也要记住这个 miss，避免每帧重复走 ResourceLoader.exists
	check(GameTheme.item_icon("no_such_item", 32) == null, "the miss is cached too")

# ---------------------------------------------------------------- 商店面板

func test_shop_renders_one_icon_per_catalogue_entry() -> void:
	var panel := ShopPanel.new()
	panel.setup("blade", false)
	eq(_count_textured(panel), ItemShop.CATALOGUE.size(), "one icon per shop row")
	_check_every_textured_has_size(panel, 52)
	panel.free()

func test_inventory_slots_show_icon_and_refund() -> void:
	var panel := ShopPanel.new()
	panel.setup("blade", false)
	panel.set_state(1000, ["boots", "iron_sword"])
	var icons: Array[TextureRect] = panel._slot_icons
	var captions: Array[Label] = panel._slot_labels
	eq(icons.size(), 6, "six equip slots")
	check(icons[0].texture != null, "bought boots must show an icon")
	check(captions[0].text.contains("神速之靴"), "slot names the item: %s" % captions[0].text)
	# 250 * 0.6 = 150
	check(captions[0].text.contains("+150g"), "slot shows the 60%% refund: %s" % captions[0].text)
	check(icons[1].texture != null, "second bought item must show an icon")
	check(icons[2].texture == null, "empty slot has no icon")
	eq(captions[2].text, "空", "empty slot says so")
	panel.free()

# ---------------------------------------------------------------- 计分板

func test_scoreboard_equip_slots_use_item_icons() -> void:
	var board := {
		"blue": [{
			"id": 1, "owner_id": "p1", "name": "p1", "team": "blue",
			"hero_type": "blade", "role": "战士", "lane": "top",
			"level": 3, "kills": 1, "deaths": 0, "cs": 12,
			"gold": 300, "net_worth": 550, "alive": true, "respawn_timer": 0.0,
			"inventory": ["boots", "iron_sword"],
		}],
		"red": [],
		"net_worth": {"blue": 550, "red": 0},
	}
	var sb := Scoreboard.new()
	sb.setup(false)
	sb.set_state(board, "p1")
	var rows: VBoxContainer = sb._blue_rows
	var slots: Array = rows.get_child(0).get_meta("slots")
	var icon: TextureRect = slots[0].get("icon")
	check(icon.visible, "a bought item must show its icon, not the first-character fallback")
	check(icon.texture != null, "the icon texture must be assigned")
	if icon.texture != null:
		eq(icon.texture.get_width(), int(Scoreboard.SLOT_SIZE), "icon is pre-shrunk to the slot size")
	var empty_icon: TextureRect = slots[2].get("icon")
	check(not empty_icon.visible, "unused slots keep the icon hidden")
	sb.free()

# ---------------------------------------------------------------- 工具

func _count_textured(node: Node) -> int:
	var total := 0
	if node is TextureRect and (node as TextureRect).texture != null:
		total += 1
	for child in node.get_children():
		total += _count_textured(child)
	return total

func _check_every_textured_has_size(node: Node, size: int) -> void:
	if node is TextureRect:
		var tex := (node as TextureRect).texture
		if tex != null and tex.get_width() != size:
			check(false, "shop thumbnail should be %dpx, got %dpx" % [size, tex.get_width()])
	for child in node.get_children():
		_check_every_textured_has_size(child, size)
