extends Control
class_name ShopPanel

signal buy_requested(item_id: String)
signal sell_requested(slot_index: int)
signal quick_buy_requested(item_id: String)
signal close_requested

const GameTheme = preload("res://scripts/ui/game_theme.gd")
const ItemShop = preload("res://sim/item_shop.gd")

var touch_mode := false
var hero_type := "blade"
var gold := 0
var inventory: Array = []

var _built := false
var _gold_label: Label
var _quick_button: Button
var _item_buttons: Dictionary = {}
var _slot_buttons: Array[Button] = []
var _slot_icons: Array[TextureRect] = []
var _slot_labels: Array[Label] = []
var _root: Control
var _state_signature := ""
var _active_category := "all"
var _tabs: Dictionary = {}
var _item_cells: Dictionary = {}
var _detail_name: Label
var _detail_meta: Label
var _detail_stats: Label
var _detail_hint: Label

func setup(type_id: String, mobile: bool) -> void:
	hero_type = type_id
	touch_mode = mobile
	_build()

func _ready() -> void:
	_build()

func _build() -> void:
	if _built:
		return
	_built = true
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	_root = ColorRect.new()
	(_root as ColorRect).color = Color(0.0, 0.0, 0.0, 0.62)
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)

	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.offset_left = -490.0
	panel.offset_right = 490.0
	panel.offset_top = -310.0
	panel.offset_bottom = 310.0
	var ornate := GameTheme.ornate_panel()
	if ornate.texture != null:
		panel.add_theme_stylebox_override("panel", ornate)
	else:
		panel.add_theme_stylebox_override("panel", GameTheme.style(Color(0.025, 0.045, 0.06, 0.98), Color(0.7, 0.55, 0.28, 0.95), 2, 12))
	_root.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	panel.add_child(box)

	var title_row := HBoxContainer.new()
	title_row.add_theme_constant_override("separation", 12)
	box.add_child(title_row)
	var title := _label("装备商店", 30, GameTheme.GOLD_LIGHT, "TitleLabel")
	title_row.add_child(title)
	_gold_label = _label("金币 0", 20, GameTheme.GOLD)
	_gold_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_gold_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	title_row.add_child(_gold_label)
	var close := Button.new()
	close.text = "关闭"
	close.custom_minimum_size = Vector2(92.0, 40.0)
	close.focus_mode = Control.FOCUS_NONE
	close.pressed.connect(func(): close_requested.emit())
	title_row.add_child(close)

	_quick_button = Button.new()
	_quick_button.text = "快捷购买推荐装备"
	_quick_button.custom_minimum_size = Vector2(0.0, 44.0)
	var quick_frame := GameTheme.button_frame()
	if quick_frame.texture != null:
		_quick_button.add_theme_stylebox_override("normal", quick_frame)
	_quick_button.focus_mode = Control.FOCUS_NONE
	_quick_button.pressed.connect(_on_quick_buy)
	box.add_child(_quick_button)

	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 12)
	box.add_child(body)

	var tabs := VBoxContainer.new()
	tabs.custom_minimum_size = Vector2(92.0, 0.0)
	tabs.add_theme_constant_override("separation", 6)
	body.add_child(tabs)
	for entry in [["all", "全部"], ["attack", "攻击"], ["magic", "法术"], ["defense", "防御"], ["movement", "移动"]]:
		var category := str(entry[0])
		var tab := Button.new()
		tab.text = str(entry[1])
		tab.toggle_mode = true
		tab.button_pressed = category == "all"
		tab.focus_mode = Control.FOCUS_NONE
		tab.custom_minimum_size = Vector2(0.0, 34.0)
		tab.pressed.connect(_select_category.bind(category))
		tabs.add_child(tab)
		_tabs[category] = tab

	var grid := GridContainer.new()
	grid.columns = 2
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 8)
	body.add_child(grid)
	for item_id in ItemShop.CATALOGUE:
		grid.add_child(_make_item_cell(str(item_id)))

	# 右侧详情：只放文字，不放 TextureRect —— 商店的图标数量契约按 8 件装备算，
	# 详情再塞一张图会让 test_item_icons 的 "one icon per catalogue entry" 失真。
	var detail := PanelContainer.new()
	detail.custom_minimum_size = Vector2(236.0, 0.0)
	detail.add_theme_stylebox_override("panel", GameTheme.style(Color(0.03, 0.05, 0.07, 0.96), Color(0.42, 0.36, 0.22, 0.85), 1, 8))
	body.add_child(detail)
	var detail_box := VBoxContainer.new()
	detail_box.add_theme_constant_override("separation", 6)
	detail.add_child(detail_box)
	_detail_name = _label("", 20, GameTheme.GOLD_LIGHT, "TitleLabel")
	detail_box.add_child(_detail_name)
	_detail_meta = _label("", 13, GameTheme.MUTED)
	detail_box.add_child(_detail_meta)
	_detail_stats = _label("", 13, GameTheme.TEXT)
	_detail_stats.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail_box.add_child(_detail_stats)
	_detail_hint = _label("", 12, GameTheme.MUTED)
	_detail_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail_box.add_child(_detail_hint)
	if not ItemShop.CATALOGUE.is_empty():
		_show_detail(str(ItemShop.CATALOGUE.keys()[0]))

	var inv_title := _label("已购装备（点击出售，返还 60%）", 15, GameTheme.MUTED)
	box.add_child(inv_title)
	var inv_row := HBoxContainer.new()
	inv_row.add_theme_constant_override("separation", 8)
	box.add_child(inv_row)
	for i in 6:
		var slot := Button.new()
		slot.text = ""
		slot.disabled = true
		slot.focus_mode = Control.FOCUS_NONE
		slot.custom_minimum_size = Vector2(0.0, 70.0)
		slot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		slot.pressed.connect(_on_slot_pressed.bind(i))
		# 用图标 + 小字代替原来的一行文本：格子窄，纯文字塞不下“名字+返还额”。
		var col := VBoxContainer.new()
		col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		col.alignment = BoxContainer.ALIGNMENT_CENTER
		col.add_theme_constant_override("separation", 0)
		col.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.add_child(col)
		var icon := TextureRect.new()
		icon.custom_minimum_size = Vector2(0.0, 36.0)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		col.add_child(icon)
		var caption := _label("空", 11, GameTheme.MUTED)
		caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(caption)
		inv_row.add_child(slot)
		_slot_buttons.append(slot)
		_slot_icons.append(icon)
		_slot_labels.append(caption)
	_refresh()

func _make_item_cell(item_id: String) -> Control:
	var item: Dictionary = ItemShop.get_item(item_id)
	var cell := PanelContainer.new()
	# 品质框走 9-slice 位图（basic/rare/epic/legendary），缺图时退回原来的纯色圆角框。
	var quality_frame := GameTheme.quality_frame(ItemShop.quality_of(item_id))
	if quality_frame.texture != null:
		cell.add_theme_stylebox_override("panel", quality_frame)
	else:
		cell.add_theme_stylebox_override("panel", GameTheme.style(Color(0.035, 0.06, 0.08, 0.96), _quality_color(item_id), 1, 8))
	cell.mouse_entered.connect(_show_detail.bind(item_id))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	cell.add_child(row)
	row.add_child(_make_thumb(item_id, item, 52))
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 1)
	row.add_child(info)
	var name_label := _label(str(item.get("name", item_id)), 17, GameTheme.TEXT)
	info.add_child(name_label)
	var desc := _label(_describe(item), 12, GameTheme.MUTED)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.add_child(desc)
	var buy := Button.new()
	buy.text = "%d g" % int(item.get("cost", 0))
	buy.custom_minimum_size = Vector2(78.0, 42.0 if touch_mode else 38.0)
	var buy_frame := GameTheme.button_frame()
	if buy_frame.texture != null:
		buy.add_theme_stylebox_override("normal", buy_frame)
	buy.focus_mode = Control.FOCUS_NONE
	buy.pressed.connect(func(): buy_requested.emit(item_id))
	row.add_child(buy)
	_item_buttons[item_id] = buy
	_item_cells[item_id] = cell
	return cell

func _quality_color(item_id: String) -> Color:
	match ItemShop.quality_of(item_id):
		"epic":
			return Color(0.72, 0.42, 1.0, 0.95)
		"rare":
			return Color(0.36, 0.62, 1.0, 0.95)
	return Color(0.34, 0.40, 0.44, 0.9)

func _quality_label(item_id: String) -> String:
	match ItemShop.quality_of(item_id):
		"epic":
			return "史诗"
		"rare":
			return "进阶"
	return "基础"

func _category_label(category: String) -> String:
	match category:
		"attack":
			return "攻击"
		"magic":
			return "法术"
		"defense":
			return "防御"
		"movement":
			return "移动"
	return "全部"

func _select_category(category: String) -> void:
	_active_category = category
	for key in _tabs:
		(_tabs[key] as Button).button_pressed = str(key) == category
	var allowed := ItemShop.ids_by_category(category)
	for item_id in _item_cells:
		(_item_cells[item_id] as Control).visible = allowed.has(str(item_id))
	if not _item_cells.is_empty():
		for item_id in _item_cells:
			if (_item_cells[item_id] as Control).visible:
				_show_detail(str(item_id))
				break

func _show_detail(item_id: String) -> void:
	var item: Dictionary = ItemShop.get_item(item_id)
	if item.is_empty():
		return
	if _detail_name:
		_detail_name.text = str(item.get("name", item_id))
	if _detail_meta:
		_detail_meta.text = "%s · %s" % [_category_label(str(item.get("category", ""))), _quality_label(item_id)]
	if _detail_stats:
		_detail_stats.text = _describe(item)
	if _detail_hint:
		var cost := int(item.get("cost", 0))
		_detail_hint.text = "价格 %d g · 出售返还 %d g" % [cost, int(float(cost) * 0.6)]

# 缩略图。图缺了就用「品类色块 + 名字首字」占位，绝不出现一个空白的格子。
# 统一套一个槽位框：图标本身是暗底，直接贴在暗面板上会看不出边界。
func _make_thumb(item_id: String, item: Dictionary, size: int) -> Control:
	var tex := GameTheme.item_icon(item_id, size)
	var holder := PanelContainer.new()
	holder.custom_minimum_size = Vector2(float(size), float(size))
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if tex != null:
		holder.add_theme_stylebox_override("panel", _slot_frame(Color(0.02, 0.03, 0.04, 0.95)))
		var icon := TextureRect.new()
		icon.texture = tex
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.add_child(icon)
		return holder
	holder.add_theme_stylebox_override("panel", _slot_frame(_category_color(str(item.get("category", "")))))
	var initial := _label(str(item.get("name", item_id)).substr(0, 1), 20, GameTheme.TEXT)
	initial.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	initial.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	holder.add_child(initial)
	return holder

# 槽位框。GameTheme.style() 自带 14/10 的内容边距，套在图上是会把图挤小的，
# 所以这里显式清零 —— 图标要正好铺满格子。
func _slot_frame(bg: Color) -> StyleBoxFlat:
	var frame := GameTheme.style(bg, Color(0.42, 0.36, 0.22, 0.85), 1, 6, 0, 0.0)
	frame.content_margin_left = 0.0
	frame.content_margin_right = 0.0
	frame.content_margin_top = 0.0
	frame.content_margin_bottom = 0.0
	return frame

func _category_color(category: String) -> Color:
	match category:
		"attack":
			return Color(0.32, 0.18, 0.14, 0.95)
		"magic":
			return Color(0.22, 0.18, 0.36, 0.95)
		"defense":
			return Color(0.16, 0.24, 0.26, 0.95)
		"movement":
			return Color(0.18, 0.26, 0.18, 0.95)
	return Color(0.12, 0.14, 0.17, 0.95)

func _describe(item: Dictionary) -> String:
	var parts: Array[String] = []
	if float(item.get("ad", 0.0)) > 0.0:
		parts.append("+%d 物攻" % int(item.ad))
	if float(item.get("ap", 0.0)) > 0.0:
		parts.append("+%d 法强" % int(item.ap))
	if float(item.get("hp", 0.0)) > 0.0:
		parts.append("+%d 生命" % int(item.hp))
	if float(item.get("speed", 0.0)) > 0.0:
		parts.append("+%.1f 移速" % float(item.speed))
	if float(item.get("crit", 0.0)) > 0.0:
		parts.append("+%d%% 暴击" % int(float(item.crit) * 100.0))
	# 项 1：防御装第一次能说清"它减伤"，而不只是"它堆血"。
	if float(item.get("armor", 0.0)) > 0.0:
		parts.append("+%d 护甲" % int(item.armor))
	if float(item.get("magic_resist", 0.0)) > 0.0:
		parts.append("+%d 魔抗" % int(item.magic_resist))
	if float(item.get("hp_regen", 0.0)) > 0.0:
		parts.append("+%d 回血" % int(item.hp_regen))
	if float(item.get("cooldown_reduction", 0.0)) > 0.0:
		parts.append("+%d%% 冷却" % int(float(item.cooldown_reduction) * 100.0))
	return " · ".join(parts)

func set_state(current_gold: int, current_inventory: Array, type_id := "") -> void:
	var next_type := type_id if type_id != "" else hero_type
	var inv_text := ""
	for item_id in current_inventory:
		inv_text += str(item_id) + ","
	var signature := "%d|%s|%s" % [current_gold, inv_text, next_type]
	if signature == _state_signature:
		return
	_state_signature = signature
	gold = current_gold
	inventory = current_inventory.duplicate()
	hero_type = next_type
	_refresh()

func _refresh() -> void:
	if not _built:
		return
	if _gold_label != null:
		_gold_label.text = "金币 %d" % gold
	var full := inventory.size() >= 6
	for item_id in _item_buttons:
		var item: Dictionary = ItemShop.get_item(str(item_id))
		var button: Button = _item_buttons[item_id]
		button.disabled = full or gold < int(item.get("cost", 0))
		button.tooltip_text = "金币不足" if gold < int(item.get("cost", 0)) else ""
	for i in _slot_buttons.size():
		var button := _slot_buttons[i]
		var icon: TextureRect = _slot_icons[i]
		var caption: Label = _slot_labels[i]
		if i < inventory.size():
			var item_id := str(inventory[i])
			var sold_item: Dictionary = ItemShop.get_item(item_id)
			var item_name := str(sold_item.get("name", "装备"))
			icon.texture = GameTheme.item_icon(item_id, 34)
			caption.text = "%s\n+%dg" % [item_name, int(float(sold_item.get("cost", 0)) * 0.6)]
			caption.add_theme_color_override("font_color", GameTheme.GOLD)
			button.disabled = false
			button.tooltip_text = "点击出售 %s，返还 60%%" % item_name
		else:
			icon.texture = null
			caption.text = "空"
			caption.add_theme_color_override("font_color", GameTheme.MUTED)
			button.disabled = true
			button.tooltip_text = ""
	if _quick_button != null:
		var recommendation := ItemShop.get_quick_buy_recommendation(
			{"gold": gold, "inventory": inventory},
			ItemShop.build_order_for(hero_type)
		)
		_quick_button.disabled = recommendation == ""
		_quick_button.text = "快捷购买推荐装备" if recommendation == "" else "快捷购买：%s" % str(ItemShop.get_item(recommendation).get("name", ""))

func _on_quick_buy() -> void:
	var recommendation := ItemShop.get_quick_buy_recommendation(
		{"gold": gold, "inventory": inventory},
		ItemShop.build_order_for(hero_type)
	)
	if recommendation != "":
		quick_buy_requested.emit(recommendation)

func _on_slot_pressed(index: int) -> void:
	if index >= 0 and index < inventory.size():
		sell_requested.emit(index)

func _label(text: String, font_size: int, color: Color, variation := "") -> Label:
	var label := Label.new()
	label.text = text
	if variation != "":
		label.theme_type_variation = variation
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label
