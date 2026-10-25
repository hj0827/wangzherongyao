extends Control
## 双方经济面板（Tab 计分板 / 点顶部经济条）。
##
## 布局参考王者：左右两列镜像，每列一队五人，一行一个人。
## 一行分两层：上层是「谁 → 等级 → K/D/A → 补刀 → 经济 → 装备」，
## 下层是属性行（攻击 / 法强 / 生命 / 移速 / 暴击 / 输出 / 承伤 / 推塔）。
## 王者把输出、承伤、参团、推塔放在「数据」页；本作信息量没那么大，
## 直接并进同一行，省一次点击。
## 装备格显示图标（assets/ui/items/<id>.png），缺图时退回职业色块，
## 不会因为美术资产没跟上就整行不显示。
##
## 数据来自 sim 快照的 board 字段（穿过视野过滤），所以即使在战争迷雾里
## 也能看到对手的经济 —— 这是公开战报，不构成透视（board 不含坐标）。

const GameTheme = preload("res://scripts/ui/game_theme.gd")
const ItemShop = preload("res://sim/item_shop.gd")
const HeroDefs = preload("res://sim/hero_defs.gd")

const ROW_H := 62.0
const SLOT_COUNT := 6
const SLOT_SIZE := 24.0
const AVATAR_SIZE := 48.0
# 列宽。两列加起来必须装得进面板内宽（面板宽 - 28 的 content margin），
# 否则 HBoxContainer 会去挤第一个 Label，标题首字被切掉半截。
const NAME_W := 138.0
const KDA_W := 100.0
const ECON_W := 70.0

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
var _rate_label: Label
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
	# 弹层必须压在所有 HUD 控件之上：小地图在左上角、商店在右上角，
	# 面板居中展开时两者在几何上是重叠的。只靠 add_child 的顺序不够稳
	# （HUD 之后还会插别的控件），显式抬 z。
	z_index = 100

	_root = ColorRect.new()
	(_root as ColorRect).color = Color(0.0, 0.0, 0.0, 0.55)
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# 点面板外的空白处收起 —— 弹窗的默认预期，省得玩家回去找 Tab。
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.gui_input.connect(_on_backdrop_input)
	add_child(_root)

	_panel = PanelContainer.new()
	_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	var width := 1240.0 if not touch_mode else 1180.0
	var height := 470.0 if not touch_mode else 500.0
	_panel.offset_left = -width * 0.5
	_panel.offset_right = width * 0.5
	_panel.offset_top = -height * 0.5
	_panel.offset_bottom = height * 0.5
	# STOP：点击落在面板上就停住，不会冒泡到遮罩被当成「点空白」。
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
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
	title_row.add_child(_label("对局战绩 · 双方经济", 22, GameTheme.GOLD_LIGHT))
	_gap_label = _label("经济持平", 18, GameTheme.TEXT)
	_gap_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_gap_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_row.add_child(_gap_label)
	# 分均经济：王者面板之外，玩家真正用来判断「谁在滚雪球」的指标。
	_rate_label = _label("分均 蓝 0 · 红 0", 14, GameTheme.MUTED)
	title_row.add_child(_rate_label)
	title_row.add_child(_label("Tab", 13, GameTheme.MUTED))

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
	# 头像列 + 间距 + 名字列，和图例下面的行对齐。
	name_col.custom_minimum_size.x = AVATAR_SIZE + 4.0 + 6.0 + NAME_W
	row.add_child(name_col)
	var kda := _label("K / D / A", 12, GameTheme.MUTED)
	kda.custom_minimum_size.x = KDA_W
	kda.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	row.add_child(kda)
	var econ := _label("经济", 12, GameTheme.MUTED)
	econ.custom_minimum_size.x = ECON_W
	econ.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(econ)
	var items := _label("装备", 12, GameTheme.MUTED)
	items.custom_minimum_size.x = SLOT_SIZE * float(SLOT_COUNT) + 6.0 * float(SLOT_COUNT - 1) + 8.0
	items.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(items)
	return row

# 行内边距比面板小一档：GameTheme.style 默认 14/10 会把每行撑到 80 高、576 宽，
# 两列叠起来把面板顶到 1260，标题行反而被挤。
func _row_style() -> StyleBoxFlat:
	var box := GameTheme.style(Color(0.05, 0.075, 0.095, 0.75), Color(0.18, 0.22, 0.26, 0.7), 1, 6, 4, 0.3)
	box.content_margin_left = 4
	box.content_margin_right = 6
	box.content_margin_top = 3
	box.content_margin_bottom = 3
	return box

# 预建一行，避免每次刷新都重建节点。内容通过 meta 里的引用回填。
func _make_row() -> Control:
	var row := PanelContainer.new()
	row.custom_minimum_size = Vector2(0.0, ROW_H)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_stylebox_override("panel", _row_style())

	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 1)
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(stack)

	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 6)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_child(line)

	# 头像：一张脸比「战士」两个字认人快得多。边框用职业色，
	# 于是原来那条 6px 的职业色块就并进边框里了，不占额外宽度。
	var avatar_frame := PanelContainer.new()
	avatar_frame.custom_minimum_size = Vector2(AVATAR_SIZE + 4.0, AVATAR_SIZE + 4.0)
	avatar_frame.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	avatar_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var avatar_box := StyleBoxFlat.new()
	avatar_box.bg_color = Color(0.02, 0.03, 0.04, 0.95)
	avatar_box.border_color = GameTheme.MUTED
	avatar_box.set_border_width_all(2)
	avatar_box.set_corner_radius_all(7)
	avatar_box.set_content_margin_all(0)
	avatar_frame.add_theme_stylebox_override("panel", avatar_box)
	line.add_child(avatar_frame)

	var avatar := TextureRect.new()
	avatar.custom_minimum_size = Vector2(AVATAR_SIZE, AVATAR_SIZE)
	avatar.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	avatar.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	avatar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	avatar_frame.add_child(avatar)

	var name_box := VBoxContainer.new()
	name_box.custom_minimum_size.x = NAME_W
	name_box.add_theme_constant_override("separation", 0)
	name_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_child(name_box)
	var name_label := _label("", 15, GameTheme.TEXT)
	name_box.add_child(name_label)
	var role_label := _label("", 11, GameTheme.MUTED)
	name_box.add_child(role_label)

	var kda := _label("", 14, GameTheme.TEXT)
	kda.custom_minimum_size.x = KDA_W
	kda.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	line.add_child(kda)

	var econ := _label("", 15, GameTheme.GOLD)
	econ.custom_minimum_size.x = ECON_W
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

	# 属性行：攻击 / 法强 / 生命 / 移速 / 暴击 / 输出 / 承伤 / 推塔。
	# 王者把这部分拆到「数据」页；本作信息量小，直接并进同一行省一次点击。
	var stats_label := _label("", 11, GameTheme.MUTED)
	stats_label.clip_text = true
	stack.add_child(stats_label)

	row.set_meta("avatar", avatar)
	row.set_meta("avatar_box", avatar_box)
	row.set_meta("name", name_label)
	row.set_meta("role", role_label)
	row.set_meta("kda", kda)
	row.set_meta("econ", econ)
	row.set_meta("stats", stats_label)
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
	# 分均经济：把「已经打了多久」折算进去，避免开局 3 分钟 1.2k 看着比
	# 20 分钟 6k 还肥。不足一分钟按一分钟算，否则开局那几秒会炸出天文数字。
	var minutes := maxf(float(board.get("time", 0.0)) / 60.0, 1.0)
	if _rate_label != null:
		_rate_label.text = "分均 蓝 %s · 红 %s" % [
			_k(int(round(float(totals.get("blue", 0)) / minutes))),
			_k(int(round(float(totals.get("red", 0)) / minutes))),
		]
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
			parts.append("%d:%d:%d:%d:%d:%d:%d:%d:%d:%s" % [
				int(row.get("id", 0)), int(row.get("level", 0)),
				int(row.get("kills", 0)), int(row.get("deaths", 0)),
				int(row.get("assists", 0)), int(row.get("tower_kills", 0)),
				int(row.get("net_worth", 0)),
				# 伤害取到 10 的整数倍：每帧都在涨的浮点数会让整张表每帧重排，
				# 面板是看一眼的东西，不需要逐帧刷新。
				int(float(row.get("damage_dealt", 0.0)) / 10.0),
				int(float(row.get("damage_taken", 0.0)) / 10.0),
				",".join(row.get("inventory", [])),
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
		# 账本里的 name 是玩家昵称（p1 / 小明），计分板要的是英雄名。
		# 英雄中文名属于表现层，所以在这里用 hero_type 翻译，而不是塞进 sim 快照。
		var hero_type := str(entry.get("hero_type", "blade"))
		var alive := bool(entry.get("alive", true))
		var avatar: TextureRect = row.get_meta("avatar")
		var avatar_tex := GameTheme.hero_avatar(hero_type, int(AVATAR_SIZE))
		avatar.texture = avatar_tex
		avatar.visible = avatar_tex != null
		# 边框 = 职业色（原来那条 6px 色块的位置让给头像了）。
		(row.get_meta("avatar_box") as StyleBoxFlat).border_color = accent
		# 阵亡时头像压暗，和名字变灰是同一套语言。
		avatar.modulate = Color(1.0, 1.0, 1.0) if alive else Color(0.42, 0.44, 0.5)

		var name_label: Label = row.get_meta("name")
		var display := str(HeroDefs.get_hero(hero_type).get("name", hero_type))
		if str(entry.get("owner_id", "")) == _local_owner:
			display = "%s（你）" % display
		if not alive:
			display = "%s  阵亡 %.0fs" % [display, float(entry.get("respawn_timer", 0.0))]
		name_label.text = "Lv.%d  %s" % [int(entry.get("level", 1)), display]
		name_label.add_theme_color_override("font_color", GameTheme.TEXT if alive else GameTheme.MUTED)

		var role_line := "%s · %s" % [role, _lane_name(str(entry.get("lane", "")))]
		var owner_name := str(entry.get("name", ""))
		if owner_name != "" and owner_name != display:
			role_line = "%s · %s" % [role_line, owner_name]
		(row.get_meta("role") as Label).text = role_line
		(row.get_meta("role") as Label).add_theme_color_override("font_color", accent)

		var kda: Label = row.get_meta("kda")
		kda.text = "%d / %d / %d" % [
			int(entry.get("kills", 0)), int(entry.get("deaths", 0)), int(entry.get("assists", 0)),
		]
		(row.get_meta("econ") as Label).text = _k(int(entry.get("net_worth", 0)))
		var stats_label: Label = row.get_meta("stats")
		if stats_label != null:
			stats_label.text = _stats_text(entry)

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

# 属性行：把「这个人到底强在哪」压成一行。
# 零值项不占宽度（法师不需要看「法强 0」），但补刀/攻击/生命/移速常显 ——
# 少了它们，面板就退回成一张只有经济的表。
func _stats_text(entry: Dictionary) -> String:
	var parts: Array[String] = []
	parts.append("补刀 %d" % int(entry.get("cs", 0)))
	parts.append("攻击 %d" % int(round(float(entry.get("attack_damage", 0.0)))))
	var ap := float(entry.get("ability_power", 0.0))
	if ap > 0.5:
		parts.append("法强 %d" % int(round(ap)))
	parts.append("生命 %d" % int(round(float(entry.get("max_hp", 0.0)))))
	parts.append("移速 %.1f" % float(entry.get("speed", 0.0)))
	var crit := float(entry.get("crit_rate", 0.0))
	if crit > 0.001:
		parts.append("暴击 %d%%" % int(round(crit * 100.0)))
	parts.append("输出 %s" % _amount(float(entry.get("damage_dealt", 0.0))))
	parts.append("承伤 %s" % _amount(float(entry.get("damage_taken", 0.0))))
	parts.append("推塔 %d" % int(entry.get("tower_kills", 0)))
	return " · ".join(parts)

func _amount(value: float) -> String:
	if value >= 1000.0:
		return "%.1fk" % (value / 1000.0)
	return str(int(round(value)))

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

func _on_backdrop_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var click := event as InputEventMouseButton
		if click.pressed and click.button_index == MOUSE_BUTTON_LEFT:
			close()
	elif event is InputEventScreenTouch:
		if (event as InputEventScreenTouch).pressed:
			close()

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
