extends "res://tests/test_base.gd"

# 商店分类 / 详情 / 品质框（P0 视觉升级）。
#
# 契约：
# 1. 分类页签能过滤出正确的装备数量；
# 2. 选中/悬停装备时右侧详情显示名称、属性、价格；
# 3. 品质由价格推导，同一件装备的颜色稳定，不同品质颜色不同；
# 4. 详情不额外塞 TextureRect（否则 test_item_icons 的 8 图标契约会被打破）。

const ShopPanel = preload("res://scripts/ui/shop_panel.gd")
const ItemShop = preload("res://sim/item_shop.gd")

func test_category_filter_shows_only_that_category() -> void:
	var panel := ShopPanel.new()
	panel.setup("blade", false)
	panel._select_category("magic")
	var visible_count := 0
	for item_id in panel._item_cells:
		if (panel._item_cells[item_id] as Control).visible:
			visible_count += 1
	eq(visible_count, ItemShop.ids_by_category("magic").size(), "法术页签只显示法术装备")
	panel._select_category("all")
	visible_count = 0
	for item_id in panel._item_cells:
		if (panel._item_cells[item_id] as Control).visible:
			visible_count += 1
	eq(visible_count, ItemShop.CATALOGUE.size(), "全部页签显示所有装备")
	panel.free()

func test_detail_shows_name_stats_and_price() -> void:
	var panel := ShopPanel.new()
	panel.setup("blade", false)
	panel._show_detail("iron_sword")
	check(panel._detail_name.text == "铁剑", "详情显示装备名")
	check(panel._detail_stats.text.contains("+20 物攻"), "详情显示属性：%s" % panel._detail_stats.text)
	check(panel._detail_hint.text.contains("250"), "详情显示价格：%s" % panel._detail_hint.text)
	panel._show_detail("infinity_edge")
	check(panel._detail_name.text == "无尽战刃", "切换装备详情要跟着变")
	check(panel._detail_stats.text.contains("暴击"), "成装详情要带暴击")
	panel.free()

func test_quality_colour_is_derived_from_price_and_stable() -> void:
	eq(ItemShop.quality_of("iron_sword"), "basic", "250g 是基础品质")
	eq(ItemShop.quality_of("resistance_boots"), "rare", "710g 是进阶品质")
	eq(ItemShop.quality_of("infinity_edge"), "epic", "2140g 是史诗品质")
	var panel := ShopPanel.new()
	panel.setup("blade", false)
	check(panel._quality_color("iron_sword") != panel._quality_color("infinity_edge"), "基础与史诗边框颜色要不同")
	check(panel._quality_color("iron_sword") == panel._quality_color("iron_sword"), "同一件装备颜色稳定")
	panel.free()

func test_detail_adds_no_extra_texture_rect() -> void:
	# test_item_icons 依赖"每个目录条目恰好一张 52px 缩略图"。
	# 详情面板必须只用文字，不能偷偷加一张 TextureRect。
	var panel := ShopPanel.new()
	panel.setup("blade", false)
	var textured := _count_textured(panel)
	eq(textured, ItemShop.CATALOGUE.size(), "详情不能增加 TextureRect 数量")
	panel.free()

func _count_textured(node: Node) -> int:
	var total := 0
	if node is TextureRect and (node as TextureRect).texture != null:
		total += 1
	for child in node.get_children():
		total += _count_textured(child)
	return total
