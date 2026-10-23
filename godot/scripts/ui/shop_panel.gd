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
var _root: Control
var _state_signature := ""

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
	panel.offset_left = -390.0
	panel.offset_right = 390.0
	panel.offset_top = -286.0
	panel.offset_bottom = 286.0
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
	_quick_button.focus_mode = Control.FOCUS_NONE
	_quick_button.pressed.connect(_on_quick_buy)
	box.add_child(_quick_button)

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 8)
	box.add_child(grid)
	for item_id in ItemShop.CATALOGUE:
		grid.add_child(_make_item_cell(str(item_id)))

	var inv_title := _label("已购装备（点击出售，返还 60%）", 15, GameTheme.MUTED)
	box.add_child(inv_title)
	var inv_row := HBoxContainer.new()
	inv_row.add_theme_constant_override("separation", 8)
	box.add_child(inv_row)
	for i in 6:
		var slot := Button.new()
		slot.text = "空"
		slot.disabled = true
		slot.focus_mode = Control.FOCUS_NONE
		slot.custom_minimum_size = Vector2(0.0, 42.0)
		slot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		slot.pressed.connect(_on_slot_pressed.bind(i))
		inv_row.add_child(slot)
		_slot_buttons.append(slot)
	_refresh()

func _make_item_cell(item_id: String) -> Control:
	var item: Dictionary = ItemShop.get_item(item_id)
	var cell := PanelContainer.new()
	cell.add_theme_stylebox_override("panel", GameTheme.style(Color(0.035, 0.06, 0.08, 0.96), Color(0.22, 0.28, 0.34, 0.9), 1, 8))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	cell.add_child(row)
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
	buy.focus_mode = Control.FOCUS_NONE
	buy.pressed.connect(func(): buy_requested.emit(item_id))
	row.add_child(buy)
	_item_buttons[item_id] = buy
	return cell

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
		if i < inventory.size():
			var sold_item: Dictionary = ItemShop.get_item(str(inventory[i]))
			button.text = "%s\n+%dg" % [str(sold_item.get("name", "装备")), int(float(sold_item.get("cost", 0)) * 0.6)]
			button.disabled = false
		else:
			button.text = "空"
			button.disabled = true
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
