extends Control
class_name AttackCluster

signal mode_changed(mode: String)
signal lock_changed(target_id: int)

const GameTheme = preload("res://scripts/ui/game_theme.gd")
const HeroDefs = preload("res://sim/hero_defs.gd")

const MODES := [
	{"id": "default", "label": "普攻"},
	{"id": "minion", "label": "补刀"},
	{"id": "tower", "label": "推塔"},
]
const MAX_LOCK_TARGETS := 5
# 键鼠端是低频率控件，占 460x176 去挡兵线不值当；压成两行 30px 的小条。
const COMPACT_SIZE := Vector2(420.0, 84.0)
const TOUCH_SIZE := Vector2(460.0, 176.0)

var attack_mode := "default"
var locked_target := -1
var touch_mode := false

var _built := false
var _mode_buttons: Dictionary = {}
var _lock_buttons: Array[Button] = []
var _lock_ids: Array[int] = []

func setup(mobile: bool) -> void:
	touch_mode = mobile
	_build()

func _ready() -> void:
	_build()

func _build() -> void:
	if _built:
		return
	_built = true
	custom_minimum_size = TOUCH_SIZE if touch_mode else COMPACT_SIZE
	var row_height := 42.0 if touch_mode else 30.0
	var gap := 6.0 if touch_mode else 4.0
	var lock_width := 64.0 if touch_mode else 46.0
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel", GameTheme.style(Color(0.02, 0.035, 0.05, 0.82), Color(0.55, 0.44, 0.24, 0.55), 1, 9))
	add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", gap)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(box)

	var mode_row := HBoxContainer.new()
	mode_row.add_theme_constant_override("separation", gap)
	box.add_child(mode_row)
	mode_row.add_child(_make_label("攻击"))
	for entry in MODES:
		var button := Button.new()
		button.text = str(entry.label)
		button.toggle_mode = true
		button.focus_mode = Control.FOCUS_NONE
		button.custom_minimum_size = Vector2(0.0, row_height)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(_on_mode_pressed.bind(str(entry.id)))
		if not touch_mode:
			_compact_button(button)
		mode_row.add_child(button)
		_mode_buttons[str(entry.id)] = button

	var lock_row := HBoxContainer.new()
	lock_row.add_theme_constant_override("separation", gap)
	box.add_child(lock_row)
	lock_row.add_child(_make_label("锁定"))
	for i in MAX_LOCK_TARGETS:
		var button := Button.new()
		button.text = "—"
		button.toggle_mode = true
		button.disabled = true
		button.focus_mode = Control.FOCUS_NONE
		button.custom_minimum_size = Vector2(lock_width, row_height)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(_on_lock_pressed.bind(i))
		if not touch_mode:
			_compact_button(button)
		lock_row.add_child(button)
		_lock_buttons.append(button)
	_sync_visuals()

# 键鼠端的小号按钮：字体和内边距都收一档。
# 否则主题里 24/12 的内边距会把 30px 的行撑到 50px，整个面板又长回 176 高。
func _compact_button(button: Button) -> void:
	var base := GameTheme.style(Color(0.06, 0.095, 0.125, 0.9), Color(0.5, 0.4, 0.22, 0.55), 1, 8, 3, 0.4)
	base.content_margin_left = 6.0
	base.content_margin_right = 6.0
	base.content_margin_top = 2.0
	base.content_margin_bottom = 2.0
	button.add_theme_stylebox_override("normal", base)
	var hover := base.duplicate() as StyleBoxFlat
	hover.bg_color = Color(0.11, 0.16, 0.2, 0.95)
	hover.border_color = GameTheme.GOLD
	button.add_theme_stylebox_override("hover", hover)
	var held := base.duplicate() as StyleBoxFlat
	held.bg_color = Color(0.15, 0.12, 0.06, 0.96)
	held.border_color = GameTheme.GOLD_LIGHT
	button.add_theme_stylebox_override("pressed", held)
	button.add_theme_font_size_override("font_size", 14)

func refresh_enemies(entities: Array, local_team: String) -> void:
	var enemies: Array = []
	for entity in entities:
		if str(entity.get("type", "")) != "hero":
			continue
		if str(entity.get("team", "")) == local_team:
			continue
		if not bool(entity.get("alive", true)):
			continue
		enemies.append(entity)
	enemies.sort_custom(func(a, b): return int(a.get("id", 0)) < int(b.get("id", 0)))
	if enemies.size() > MAX_LOCK_TARGETS:
		enemies = enemies.slice(0, MAX_LOCK_TARGETS)
	var ids: Array[int] = []
	for entity in enemies:
		ids.append(int(entity.get("id", -1)))
	var changed := ids.size() != _lock_ids.size()
	if not changed:
		for i in ids.size():
			if ids[i] != _lock_ids[i]:
				changed = true
				break
	var cleared := false
	if locked_target > 0 and not ids.has(locked_target):
		locked_target = -1
		cleared = true
	_lock_ids = ids
	if changed:
		for i in MAX_LOCK_TARGETS:
			var button := _lock_buttons[i]
			if i < enemies.size():
				var entity: Dictionary = enemies[i]
				var hero_type := str(entity.get("hero_type", "blade"))
				var display := str(HeroDefs.get_hero(hero_type).get("name", "英雄"))
				button.text = display.substr(0, 2)
				button.disabled = false
				button.tooltip_text = str(entity.get("name", display))
			else:
				button.text = "—"
				button.disabled = true
				button.tooltip_text = ""
	_sync_visuals()
	if cleared:
		lock_changed.emit(-1)

func set_targeting_state(mode: String, target_id: int) -> void:
	attack_mode = mode if _mode_buttons.has(mode) else "default"
	locked_target = target_id
	_sync_visuals()

func _on_mode_pressed(mode: String) -> void:
	attack_mode = mode
	_sync_visuals()
	mode_changed.emit(mode)

func _on_lock_pressed(index: int) -> void:
	if index < 0 or index >= _lock_ids.size():
		return
	var target_id := _lock_ids[index]
	locked_target = -1 if locked_target == target_id else target_id
	_sync_visuals()
	lock_changed.emit(locked_target)

func _sync_visuals() -> void:
	for mode in _mode_buttons:
		var button: Button = _mode_buttons[mode]
		button.button_pressed = mode == attack_mode
	for i in _lock_buttons.size():
		var pressed := i < _lock_ids.size() and _lock_ids[i] == locked_target
		_lock_buttons[i].button_pressed = pressed

func _make_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", GameTheme.MUTED)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label
