extends Control
## 双方经济面板（Tab 计分板）。
##
## 布局参考王者：左右两列镜像，每列一队五人，一行一个人。
## 一行里的信息优先级：谁 → 多少级 → K/D/补刀 → 经济 → 装备。
## 装备格显示图标（assets/ui/items/<id>.png），缺图时退回职业色块，
## 不会因为美术资产没跟上就整行不显示。
##
## 数据来自 sim 快照的 board 字段（穿过视野过滤），所以即使在战争迷雾里
## 也能看到对手的经济 —— 这是公开战报，不构成透视（board 不含坐标）。

const GameTheme = preload("res://scripts/ui/game_theme.gd")
const ItemShop = preload("res://sim/item_shop.gd")
const HeroDefs = preload("res://sim/hero_defs.gd")

const ROW_H := 46.0
const SLOT_COUNT := 6
const SLOT_SIZE := 26.0

const ROLE_COLORS := {
	"坦克": Color(0.42, 0.78, 0.74),
	"战士": Color(0.95, 0.72, 0.36),
	"刺客": Color(0.88, 0.44, 0.74),
	"法师": Color(0.66, 0.55, 1.0),
	"射手": Color(0.58, 0.92, 0.54),
}

var touch_mode := false

var _built := false
var _root: Control
var _panel: PanelContainer
var _blue_rows: VBoxContainer
var _red_rows: VBoxContainer
var _blue_total: Label
var _red_total: Label
var _gap_label: Label
var _local_owner := ""
var _signature := ""

func setup(touch: bool) -> void:
	touch_mode = touch
	_build()

func _ready() -> void:
	_build()

func _build() -> void:
	if _built:
		return
	_built = true
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false

	_root = ColorRect.new()
	(_root as ColorRect).color = Color(0.0, 0.0, 0.0, 0.55)
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	_panel = PanelContainer.new()
	_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	var width := 1180.0 if not touch_mode else 1060.0
	var height := 560.0 if not touch_mode else 600.0
	_panel.offset_left = -width * 0.5
	_panel.offset_right = width * 0.5
	_panel.offset_top = -height * 0.5
	_panel.offset_bottom = height * 0.5
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_theme_stylebox_override("panel", GameTheme.style(Color(0.02, 0.035, 0.05, 0.97), Color(0.7, 0.55, 0.28, 0.9), 2, 12))
	_root.add_child(_panel)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(column)

	# —— 标题行：标题 · 经济差 · 关闭提示 ——
	var title_row := HBoxContainer.new()
	title_row.add_theme_constant_override("separation", 16)
	title_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(title_row)
	title_row.add_child(_label("对局战绩 · 双方经济", 26, GameTheme.GOLD_LIGHT))
	_gap_label = _label("经济持平", 18, GameTheme.TEXT)
	_gap_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_gap_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_row.add_child(_gap_label)
	title_row.add_child(_label("Tab 关闭", 14, GameTheme.MUTED))

	# —— 两列 ——
	var teams := HBoxContainer.new()
	teams.add_theme_constant_override("separation", 14)
	teams.size_flags_vertical = Control.SIZE_EXPAND_FILL
	teams.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(teams)

	var blue_col := _make_team_column("blue")
	teams.add_child(blue_col["frame"] as Control)
	_blue_rows = blue_col["rows"] as VBoxContainer
	_blue_total = blue_col["total"] as Label

	var red_col := _make_team_column("red")
	teams.add_child(red_col["frame"] as Control)
	_red_rows = red_col["rows"] as VBoxContainer
	_red_total = red_col["total"] as Label

# 一队一列：抬头 + 五行（预先建好，靠 visible 控制，避免每帧 new 节点）+ 合计
func _make_team_column(team: String) -> Dictionary:
	var frame := PanelContainer.new()
	frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var accent := GameTheme.BLUE if team == "blue" else GameTheme.RED
	frame.add_theme_stylebox_override("panel", GameTheme.style(Color(0.03, 0.05, 0.07, 0.9), Color(accent.r, accent.g, accent.b, 0.45), 1, 9))

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(box)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(head)
	var team_name := "蓝方" if team == "blue" else "红方"
	head.add_child(_label(team_name, 18, accent))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(spacer)
	var total := _label("0", 18, accent)
	total.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	head.add_child(total)

	box.add_child(_legend())

	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 2)
	rows.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(rows)
	for i in 5:
		rows.add_child(_make_row())

	return {"frame": frame, "rows": rows, "total": total}

func _legend() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var name_col := _label("英雄 / 等级", 12, GameTheme.MUTED)
	name_col.custom_minimum_size.x = 168.0
	row.add_child(name_col)
	var kda := _label("K / D / 补刀", 12, GameTheme.MUTED)
	kda.custom_minimum_size.x = 110.0
	kda.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	row.add_child(kda)
	var econ := _label("经济", 12, GameTheme.MUTED)
	econ.custom_minimum_size.x = 74.0
	econ.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(econ)
	var items := _label("装备", 12, GameTheme.MUTED)
	items.custom_minimum_size.x = SLOT_SIZE * float(SLOT_COUNT) + 6.0 * float(SLOT_COUNT - 1) + 8.0
	items.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(items)
	return row

# 预建一行，避免每次刷新都重建节点。内容通过 meta 里的引用回填。
func _make_row() -> Control:
	var row := PanelContainer.new()
	row.custom_minimum_size = Vector2(0.0, ROW_H)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_stylebox_override("panel", GameTheme.style(Color(0.05, 0.075, 0.095, 0.75), Color(0.18, 0.22, 0.26, 0.7), 1, 6))

	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 6)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(line)

	# 职业色块：没有立绘也能一眼分职业
	var badge := ColorRect.new()
	badge.custom_minimum_size = Vector2(6.0, 0.0)
	badge.color = GameTheme.MUTED
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_child(badge)

	var name_box := VBoxContainer.new()
	name_box.custom_minimum_size.x = 162.0
	name_box.add_theme_constant_override("separation", 0)
	name_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_child(name_box)
	var name_label := _label("", 15, GameTheme.TEXT)
	name_box.add_child(name_label)
	var role_label := _label("", 11, GameTheme.MUTED)
	name_box.add_child(role_label)

	var kda := _label("", 14, GameTheme.TEXT)
	kda.custom_minimum_size.x = 110.0
	kda.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	line.add_child(kda)

	var econ := _label("", 15, GameTheme.GOLD)
	econ.custom_minimum_size.x = 74.0
	econ.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	line.add_child(econ)

	var slots := HBoxContainer.new()
	slots.add_theme_constant_override("separation", 6)
	slots.alignment = BoxContainer.ALIGNMENT_END
	slots.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slots.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_child(slots)
	var slot_nodes: Array = []
	for i in SLOT_COUNT:
		var cell := Control.new()
		cell.custom_minimum_size = Vector2(SLOT_SIZE, SLOT_SIZE)
		cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var bg := ColorRect.new()
		bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		bg.color = Color(0.1, 0.12, 0.15, 0.85)
		bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cell.add_child(bg)
		var icon := TextureRect.new()
		icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon.visible = false
		cell.add_child(icon)
		var initial := _label("", 11, GameTheme.MUTED)
		initial.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		initial.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		initial.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		cell.add_child(initial)
		slots.add_child(cell)
		slot_nodes.append({"cell": cell, "bg": bg, "icon": icon, "text": initial})

	row.set_meta("badge", badge)
	row.set_meta("name", name_label)
	row.set_meta("role", role_label)
	row.set_meta("kda", kda)
	row.set_meta("econ", econ)
	row.set_meta("slots", slot_nodes)
	return row

func set_state(board: Dictionary, local_owner: String) -> void:
	if not _built:
		return
	var blue: Array = board.get("blue", [])
	var red: Array = board.get("red", [])
	var totals: Dictionary = board.get("net_worth", {})
	var signature := _build_signature(blue, red, totals, local_owner)
	if signature == _signature:
		return
	_signature = signature
	_local_owner = local_owner
	_fill_column(_blue_rows, blue, "blue")
	_fill_column(_red_rows, red, "red")
	_blue_total.text = _k(int(totals.get("blue", 0)))
	_red_total.text = _k(int(totals.get("red", 0)))
	var diff := int(totals.get("blue", 0)) - int(totals.get("red", 0))
	if absi(diff) < 50:
		_gap_label.text = "经济持平"
		_gap_label.add_theme_color_override("font_color", GameTheme.MUTED)
	elif diff > 0:
		_gap_label.text = "蓝方领先 %s" % _k(diff)
		_gap_label.add_theme_color_override("font_color", GameTheme.BLUE)
	else:
		_gap_label.text = "红方领先 %s" % _k(-diff)
		_gap_label.add_theme_color_override("font_color", GameTheme.RED)

func _build_signature(blue: Array, red: Array, totals: Dictionary, local_owner: String) -> String:
	var parts: Array[String] = [local_owner]
	for side in [blue, red]:
		for row in side:
			parts.append("%d:%d:%d:%d:%d:%s" % [
				int(row.get("id", 0)), int(row.get("level", 0)),
				int(row.get("kills", 0)), int(row.get("deaths", 0)),
				int(row.get("net_worth", 0)), ",".join(row.get("inventory", [])),
			])
	parts.append("%d/%d" % [int(totals.get("blue", 0)), int(totals.get("red", 0))])
	return "|".join(parts)

func _fill_column(rows: VBoxContainer, data: Array, team: String) -> void:
	var children := rows.get_children()
	for i in children.size():
		var row: Control = children[i]
		if i >= data.size():
			row.visible = false
			continue
		row.visible = true
		var entry: Dictionary = data[i]
		var role := str(entry.get("role", ""))
		var accent: Color = ROLE_COLORS.get(role, GameTheme.MUTED)
		(row.get_meta("badge") as ColorRect).color = accent

		var name_label: Label = row.get_meta("name")
		# 账本里的 name 是玩家昵称（p1 / 小明），计分板要的是英雄名。
		# 英雄中文名属于表现层，所以在这里用 hero_type 翻译，而不是塞进 sim 快照。
		var hero_type := str(entry.get("hero_type", "blade"))
		var display := str(HeroDefs.get_hero(hero_type).get("name", hero_type))
		if str(entry.get("owner_id", "")) == _local_owner:
			display = "%s（你）" % display
		if not bool(entry.get("alive", true)):
			display = "%s  阵亡 %.0fs" % [display, float(entry.get("respawn_timer", 0.0))]
		name_label.text = "Lv.%d  %s" % [int(entry.get("level", 1)), display]
		name_label.add_theme_color_override("font_color", GameTheme.TEXT if bool(entry.get("alive", true)) else GameTheme.MUTED)

		var role_line := "%s · %s" % [role, _lane_name(str(entry.get("lane", "")))]
		var owner_name := str(entry.get("name", ""))
		if owner_name != "" and owner_name != display:
			role_line = "%s · %s" % [role_line, owner_name]
		(row.get_meta("role") as Label).text = role_line
		(row.get_meta("role") as Label).add_theme_color_override("font_color", accent)

		var kda: Label = row.get_meta("kda")
		kda.text = "%d / %d / %d" % [
			int(entry.get("kills", 0)), int(entry.get("deaths", 0)), int(entry.get("cs", 0)),
		]
		(row.get_meta("econ") as Label).text = _k(int(entry.get("net_worth", 0)))

		var slots: Array = row.get_meta("slots")
		var inventory: Array = entry.get("inventory", [])
		for s in slots.size():
			var slot: Dictionary = slots[s]
			var cell: Control = slot.cell
			var bg: ColorRect = slot.bg
			var icon: TextureRect = slot.icon
			var text: Label = slot.text
			if s >= inventory.size():
				cell.visible = false
				continue
			cell.visible = true
			var item_id := str(inventory[s])
			var item: Dictionary = ItemShop.get_item(item_id)
			var tex := GameTheme.item_icon(item_id, int(SLOT_SIZE))
			if tex != null:
				icon.texture = tex
				icon.visible = true
				text.text = ""
				bg.color = Color(0.08, 0.1, 0.13, 0.9)
			else:
				# 图标还没跟上时用「首字 + 分类色」占位，而不是留一个空格子。
				icon.visible = false
				text.text = str(item.get("name", item_id)).substr(0, 1)
				bg.color = _category_color(str(item.get("category", "")))
		for s in range(inventory.size(), slots.size()):
			(slots[s].cell as Control).visible = false

func _lane_name(lane: String) -> String:
	match lane:
		"top":
			return "上路"
		"bottom":
			return "下路"
		"mid":
			return "中路"
		"jungle":
			return "打野"
	return "游走"

func _category_color(category: String) -> Color:
	match category:
		"attack":
			return Color(0.42, 0.26, 0.2, 0.95)
		"magic":
			return Color(0.26, 0.22, 0.44, 0.95)
		"defense":
			return Color(0.2, 0.3, 0.32, 0.95)
		"movement":
			return Color(0.24, 0.32, 0.22, 0.95)
	return Color(0.12, 0.14, 0.17, 0.95)

# 经济统一显示成 1.5k / 12.4k，过千才带 k，避免一列数字宽度跳动。
func _k(value: int) -> String:
	if value >= 1000:
		return "%.1fk" % (float(value) / 1000.0)
	return str(value)

func toggle() -> void:
	if not _built:
		return
	visible = not visible

func open() -> void:
	if _built:
		visible = true

func close() -> void:
	if _built:
		visible = false

func is_open() -> bool:
	return _built and visible

func _label(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label
