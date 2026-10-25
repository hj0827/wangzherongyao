extends Control
class_name LockBar

## 真机锁定：遇见敌方英雄 → 他头顶冒出一颗头像 → 点一下锁定 → 一根短线连着他。
##
## 为什么头像跟着人走，而不是在右上角排一排固定槽位：
## 1. **够不到**。右手拇指在右下角，右上角在 2000x900 的视口里要伸 1700px；
## 2. **抢地**。三颗 48dp（120px）的头像需要一个 120x376 的槽位，而「攻击键正上方」
##    这条竖带正是技能弧最上一颗（R）的家，两块必然重叠；
## 3. **对不上人**。右上角第一颗到底是场上哪个人，玩家得自己猜。头像浮在他头上，
##    「谁是谁」这个问题就消失了。
##
## 三条必须钉死的规则（tests/test_touch_hud_grouping.gd 全都有用例）：
## 1. **遇见才出现**：超出 TargetingRules.MAX_LOCK_DISTANCE 的敌人不上条；
## 2. **最多三个**：留最近的三个 —— 你要点的本来就是离你最近的那个；
## 3. **不许叠、不许出画**：五个人挤在屏幕同一点时头像要自己错开；
##    人站在屏幕边上时头像要往内夹，不能跟着跑到画布外。
##
## 本节点铺满整个 HUD，自己只负责画线；头像是有自己触摸区的子节点。
## 这样线可以画在任何东西底下（包括头像），点击又不会被线吃掉。

signal lock_changed(target_id: int)

const TouchLayout = preload("res://scripts/ui/touch_layout.gd")
const GameTheme = preload("res://scripts/ui/game_theme.gd")
const LockPortraitScript = preload("res://scripts/ui/lock_portrait.gd")
const TargetingRules = preload("res://sim/targeting_rules.gd")

## 120 = 900 高视口下的 48dp，能点准的下限（见 test_touch_hud_grouping）。
const PORTRAIT_SIZE := TouchLayout.LOCK_PORTRAIT_SIZE
## 头像下沿离「敌人屏幕点」的净空。90 让头像压在头顶上方而不是盖住人，
## 同时把连线留在「一眼看得出是同一条」的长度（60 + 90 = 150px 的短线）。
const HEAD_CLEARANCE := 90.0
## 贴边时留的空白：贴着画布边画会跟 HUD 边框糊在一起。
const SCREEN_INSET := 8.0
## 头像互相避让时的额外间隙。
const STACK_STEP := 8.0
const MAX_PLACE_TRIES := 8
# 线端离屏幕边缘的留白。
const CLIP_INSET := 8.0

var locked_target := -1
var touch_mode := true

var _targets: Array = []
var _portraits: Array[Control] = []
var _slots: Array[Rect2] = []

func setup(mobile: bool) -> void:
	touch_mode = mobile
	_build()

func _ready() -> void:
	_build()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	resized.connect(_relayout)

func _build() -> void:
	if not _portraits.is_empty():
		return
	focus_mode = Control.FOCUS_NONE
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	for i in TouchLayout.MAX_LOCK_PORTRAITS:
		var portrait: Control = LockPortraitScript.new()
		portrait.name = "LockPortrait%d" % i
		portrait.setup(touch_mode)
		portrait.visible = false
		portrait.pressed.connect(_on_portrait_pressed.bind(i))
		add_child(portrait)
		_portraits.append(portrait)

# ---------------------------------------------------------------- 数据入口

## targets 每项 {id, hero_type, name, dist, screen}。screen 是世界坐标投影出来的屏幕点，
## 由 arena 每 20Hz 送一次（无头测试里没有相机，所以这一层不碰 3D）。
func set_targets(targets: Array) -> void:
	var kept: Array = []
	for target in targets:
		if float(target.get("dist", INF)) > TargetingRules.MAX_LOCK_DISTANCE:
			continue
		# 没有投影点的目标（相机背后 / 这一帧没算）不挂头像：挂在 (0,0) 上会变成
		# 左上角一颗凭空出现的头像，比不显示更误导。
		var screen: Vector2 = target.get("screen", Vector2(-1.0, -1.0))
		if screen.x < 0.0 or screen.y < 0.0:
			continue
		kept.append(target)
	kept.sort_custom(func(a, b): return float(a.get("dist", INF)) < float(b.get("dist", INF)))
	if kept.size() > TouchLayout.MAX_LOCK_PORTRAITS:
		kept = kept.slice(0, TouchLayout.MAX_LOCK_PORTRAITS)
	var released := false
	if locked_target > 0 and _index_of(kept, locked_target) < 0:
		# 目标死了 / 走远了 / 被挤出前三：锁定必须跟着失效，
		# 否则 sim 会一直往一个不存在的人身上打。
		locked_target = -1
		released = true
	_targets = kept
	visible = not _targets.is_empty()
	_relayout()
	if released:
		lock_changed.emit(-1)

func set_locked(target_id: int) -> void:
	if locked_target == target_id:
		return
	locked_target = target_id
	_sync_active()
	queue_redraw()

func set_viewport_size(viewport: Vector2) -> void:
	# 进树之后 size 由 PRESET_FULL_RECT 的锚点决定，这里只补一个无头测试用的尺寸。
	if not is_inside_tree():
		size = viewport
	_relayout()

# ---------------------------------------------------------------- 查询（给测试和绘制用）

func target_count() -> int:
	return _targets.size()

func target_id(index: int) -> int:
	if index < 0 or index >= _targets.size():
		return -1
	return int(_targets[index].get("id", -1))

func portrait_rect(index: int) -> Rect2:
	if index < 0 or index >= _slots.size():
		return Rect2()
	return _slots[index]

## 锁定时返回 [头像中心, 线端点]；没锁定回空数组。
func line_endpoints() -> Array[Vector2]:
	var points: Array[Vector2] = []
	if locked_target <= 0:
		return points
	var index := _index_of(_targets, locked_target)
	if index < 0 or index >= _slots.size():
		return points
	var anchor: Vector2 = _slots[index].get_center()
	var target: Vector2 = _targets[index].get("screen", anchor)
	points.append(anchor)
	points.append(_clip_to_screen(anchor, target))
	return points

## 目标是否真的在画面里。视野外的目标只能画一根「指向屏幕外」的提示线，不能当准心用。
func is_locked_in_view() -> bool:
	if locked_target <= 0 or size.x <= 1.0 or size.y <= 1.0:
		return false
	var index := _index_of(_targets, locked_target)
	if index < 0:
		return false
	var point: Vector2 = _targets[index].get("screen", Vector2(-1.0, -1.0))
	return Rect2(Vector2.ZERO, size).has_point(point)

# ---------------------------------------------------------------- 交互

## 点第 index 个头像：没锁就锁上，锁着就松开。测试直接调它，不必伪造触摸事件。
func press_portrait(index: int) -> void:
	if index < 0 or index >= _targets.size():
		return
	var target_id := int(_targets[index].get("id", -1))
	locked_target = -1 if locked_target == target_id else target_id
	_sync_active()
	queue_redraw()
	lock_changed.emit(locked_target)

func _on_portrait_pressed(index: int) -> void:
	press_portrait(index)

# ---------------------------------------------------------------- 排布

## 一颗头像的「理想位置」：水平居中于敌人，下沿压在头顶上方 HEAD_CLEARANCE，
## 再整体夹进屏幕。单独抽出来是为了让测试能直接量「挂在哪」。
static func head_slot(target_screen: Vector2, viewport: Vector2) -> Rect2:
	var center := Vector2(target_screen.x, target_screen.y - HEAD_CLEARANCE - PORTRAIT_SIZE * 0.5)
	return clamp_slot(center, viewport)

## 把一个「想要的中心」夹成屏内的方框。窄视口下 min > max 会让 clampf 反着来，
## 所以两侧边界都先过一遍 maxf。
static func clamp_slot(center: Vector2, viewport: Vector2) -> Rect2:
	var half := PORTRAIT_SIZE * 0.5
	var lo := SCREEN_INSET + half
	var hi_x := maxf(viewport.x - SCREEN_INSET - half, lo)
	var hi_y := maxf(viewport.y - SCREEN_INSET - half, lo)
	return Rect2(
		Vector2(clampf(center.x, lo, hi_x) - half, clampf(center.y, lo, hi_y) - half),
		Vector2(PORTRAIT_SIZE, PORTRAIT_SIZE)
	)

func _relayout() -> void:
	var viewport := size
	if viewport.x <= 1.0 or viewport.y <= 1.0:
		viewport = Vector2(1600.0, 900.0)
	_slots = _layout_slots(viewport)
	for i in _portraits.size():
		var portrait: Control = _portraits[i]
		if i >= _targets.size() or i >= _slots.size():
			portrait.visible = false
			continue
		portrait.position = _slots[i].position
		portrait.size = _slots[i].size
		portrait.set_hero(str(_targets[i].get("hero_type", "blade")))
		portrait.set_active(int(_targets[i].get("id", -1)) == locked_target)
		portrait.visible = true
	queue_redraw()

func _layout_slots(viewport: Vector2) -> Array[Rect2]:
	var placed: Array[Rect2] = []
	for target in _targets:
		var screen: Vector2 = target.get("screen", Vector2(viewport.x * 0.5, viewport.y * 0.5))
		placed.append(_place_slot(screen, viewport, placed))
	return placed

## 团战时两个人可能站在屏幕上同一个点：先往上错一档，顶到屏幕边就改往左错。
## 挪不开（屏幕只够放一颗）时返回原位，宁可叠着也不要抖。
func _place_slot(screen: Vector2, viewport: Vector2, placed: Array[Rect2]) -> Rect2:
	var slot := head_slot(screen, viewport)
	var step := PORTRAIT_SIZE + STACK_STEP
	for attempt in MAX_PLACE_TRIES:
		if not _hits_any(slot, placed):
			return slot
		var moved := clamp_slot(slot.get_center() + Vector2(0.0, -step), viewport)
		if moved.position.is_equal_approx(slot.position):
			moved = clamp_slot(slot.get_center() + Vector2(-step, 0.0), viewport)
		if moved.position.is_equal_approx(slot.position):
			return slot
		slot = moved
	return slot

func _hits_any(rect: Rect2, others: Array[Rect2]) -> bool:
	for other in others:
		if rect.intersects(other):
			return true
	return false

func _sync_active() -> void:
	for i in _portraits.size():
		var is_active := i < _targets.size() and int(_targets[i].get("id", -1)) == locked_target
		_portraits[i].set_active(is_active)

func _index_of(targets: Array, target_id: int) -> int:
	for i in targets.size():
		if int(targets[i].get("id", -1)) == target_id:
			return i
	return -1

# 把 from→to 这段夹到屏幕内：超出就求交点。相机背后的点投影会翻到另一侧，
# 不夹的话线会横穿整个画面，比不画更误导。
func _clip_to_screen(from: Vector2, to: Vector2) -> Vector2:
	if size.x <= 1.0 or size.y <= 1.0:
		return to
	var inner := Rect2(
		Vector2(CLIP_INSET, CLIP_INSET),
		Vector2(maxf(size.x - CLIP_INSET * 2.0, 1.0), maxf(size.y - CLIP_INSET * 2.0, 1.0))
	)
	if inner.has_point(to):
		return to
	var dir := to - from
	if dir.length() < 0.001:
		return from
	var best := INF
	if dir.x > 0.0:
		best = minf(best, (inner.end.x - from.x) / dir.x)
	elif dir.x < 0.0:
		best = minf(best, (inner.position.x - from.x) / dir.x)
	if dir.y > 0.0:
		best = minf(best, (inner.end.y - from.y) / dir.y)
	elif dir.y < 0.0:
		best = minf(best, (inner.position.y - from.y) / dir.y)
	if best == INF or best <= 0.0:
		return from
	return from + dir * minf(best, 1.0)

func _draw() -> void:
	var ends := line_endpoints()
	if ends.size() < 2:
		return
	var in_view := is_locked_in_view()
	# 两层线：底层压暗托底，顶层亮金实线。单层细线压在亮地砖上会直接消失。
	var glow := Color(0.0, 0.0, 0.0, 0.38)
	draw_line(ends[0], ends[1], glow, 9.0, true)
	var halo := GameTheme.GOLD
	halo.a = 0.30 if in_view else 0.14
	draw_line(ends[0], ends[1], halo, 5.0, true)
	var body := GameTheme.GOLD_LIGHT
	body.a = 1.0 if in_view else 0.5
	draw_line(ends[0], ends[1], body, 2.5, true)
	# 目标端准心：在视野内是双环，在视野外只剩一圈半亮的环（提示「他在那边」）。
	draw_arc(ends[1], 26.0, 0.0, TAU, 32, body, 2.5, true)
	if in_view:
		draw_arc(ends[1], 8.0, 0.0, TAU, 16, body, 2.0, true)
