extends "res://tests/test_base.gd"

## 锁定层的契约（2026-10-25 改版后）。
##
## 旧版把三颗头像排在**右上角一条固定槽位**里，本文件旧版钉的正是那条槽位
## （`LockBar.layout_slots(area, n)`、`HudLayout.zones()` 里的 `lock` 分区）。
## 用户反馈「锁定要遇见英雄之后出现对方的头像，点了用一根线连着」，
## 于是头像改成浮在敌人头顶、跟着人走 —— 槽位那套连同它的断言一起作废。
##
## 现在这里守的是「不依赖排版」的那几条：
## 1. 遇见才出现（超出 MAX_LOCK_DISTANCE 的不上条）、没人就整层隐藏；
## 2. 团战只留最近的三个；
## 3. 点头像 = 锁 / 再点 = 松，事件必须到达 sim；
## 4. 目标没了锁定必须跟着失效（否则 sim 会一直打空气）；
## 5. 连线只在锁定时存在，且一定被夹在屏幕内。
##
## 「头像挂在他头顶多高、会不会叠在一起」在 tests/test_touch_hud_grouping.gd。

const TouchLayout = preload("res://scripts/ui/touch_layout.gd")
const LockBar = preload("res://scripts/ui/lock_bar.gd")
const LockPortraitScript = preload("res://scripts/ui/lock_portrait.gd")
const TargetingRules = preload("res://sim/targeting_rules.gd")

const PHONE := Vector2(2000.0, 900.0)

func _bar(viewport := PHONE) -> Control:
	var bar: Control = LockBar.new()
	bar.setup(true)
	bar.size = viewport
	return bar

func _target(id: int, dist: float, screen: Vector2, hero_type := "blade") -> Dictionary:
	return {"id": id, "hero_type": hero_type, "name": "敌人%d" % id, "screen": screen, "dist": dist}

# ---------------------------------------------------------------- 遇见才出现

func test_only_enemies_you_actually_met_show_up() -> void:
	var bar := _bar()
	bar.set_targets([
		_target(1, TargetingRules.MAX_LOCK_DISTANCE - 1.0, Vector2(1000.0, 500.0)),
		_target(2, TargetingRules.MAX_LOCK_DISTANCE + 6.0, Vector2(1800.0, 300.0), "mage"),
	])
	eq(bar.target_count(), 1, "an enemy beyond the lock radius must not take up the bar")
	eq(bar.target_id(0), 1, "the met enemy stays")

func test_the_whole_bar_hides_when_nobody_is_around() -> void:
	var bar := _bar()
	bar.set_targets([_target(3, TargetingRules.MAX_LOCK_DISTANCE + 20.0, Vector2(1200.0, 400.0))])
	eq(bar.target_count(), 0, "no enemy means no portraits")
	check(not bar.visible, "the layer hides itself instead of leaving empty rings on screen")

func test_a_target_without_a_projected_point_is_skipped() -> void:
	# 相机背后 / 这一帧没算投影时 screen 是 (-1,-1)。挂在 (0,0) 上会变成
	# 左上角一颗凭空出现的头像 —— 比不显示更误导。
	var bar := _bar()
	bar.set_targets([_target(1, 4.0, Vector2(-1.0, -1.0))])
	eq(bar.target_count(), 0, "a target without a projection is not drawn")

func test_a_crowd_keeps_only_the_three_closest() -> void:
	# 团战五个人不可能都排上；离你最近的那三个才是你要点的。
	var bar := _bar()
	var targets: Array = []
	for i in 5:
		targets.append(_target(i + 1, 3.0 + float(i), Vector2(1000.0 + float(i) * 40.0, 480.0)))
	bar.set_targets(targets)
	eq(bar.target_count(), TouchLayout.MAX_LOCK_PORTRAITS, "the layer caps the crowd")
	eq(bar.target_id(0), 1, "closest enemy comes first")
	eq(bar.target_id(2), 3, "the third slot holds the third closest")

# ---------------------------------------------------------------- 头像本体

func test_the_avatar_is_anchored_so_it_actually_covers_the_ring() -> void:
	# 真机第一次跑出来的就是「三个空黑圈」：TextureRect 只写了 offset、没铺 anchor，
	# 宽被算成 offset_right - offset_left = -8，控件在树里、纹理也在，一个像素都不画。
	# 这里不量渲染，只量「按 anchor + offset 推出来的框」是不是正的 —— 那正是当初算错的地方。
	var portrait: Control = LockPortraitScript.new()
	portrait.setup(true)
	var avatar: Control = portrait.get_node_or_null("Avatar")
	check(avatar != null, "the portrait builds an avatar child")
	if avatar == null:
		return
	near(avatar.anchor_right, 1.0, 0.001, "the avatar must stretch with its parent")
	near(avatar.anchor_bottom, 1.0, 0.001, "the avatar must stretch with its parent")
	check(avatar.offset_left > 0.0 and avatar.offset_right < 0.0, "the avatar is inset from the ring on both sides")
	var implied_width := avatar.anchor_right * 120.0 + avatar.offset_right - (avatar.anchor_left * 120.0 + avatar.offset_left)
	var implied_height := avatar.anchor_bottom * 120.0 + avatar.offset_bottom - (avatar.anchor_top * 120.0 + avatar.offset_top)
	gt(implied_width, 100.0, "the avatar box resolves to a real width, not a negative one")
	gt(implied_height, 100.0, "the avatar box resolves to a real height, not a negative one")
	near(implied_width, implied_height, 0.01, "the avatar stays square so the round mask does not squash it")

func test_the_round_mask_shader_exists_and_is_wired() -> void:
	# 头像必须是圆的（方形立绘的四角会从环里顶出来）。
	var path := "res://shaders/ui_round_mask.gdshader"
	check(FileAccess.file_exists(path), "the round mask shader must be in the project")
	var portrait: Control = LockPortraitScript.new()
	portrait.setup(true)
	var avatar: Control = portrait.get_node_or_null("Avatar")
	check(avatar != null and avatar.material is ShaderMaterial, "the avatar must carry the round mask material")

# ---------------------------------------------------------------- 点一下就锁

func test_clicking_a_portrait_locks_it_and_clicking_again_releases() -> void:
	var bar := _bar()
	var seen: Array = []
	bar.lock_changed.connect(func(target_id: int): seen.append(target_id))
	bar.set_targets([_target(7, 6.0, Vector2(900.0, 520.0))])
	bar.press_portrait(0)
	eq(bar.locked_target, 7, "tapping a portrait locks that enemy")
	eq(seen, [7], "locking emits exactly one event")
	bar.press_portrait(0)
	eq(bar.locked_target, -1, "tapping the same portrait again releases the lock")
	eq(seen, [7, -1], "releasing emits -1")

func test_lock_drops_when_the_target_dies_or_leaves() -> void:
	var bar := _bar()
	var seen: Array = []
	bar.lock_changed.connect(func(target_id: int): seen.append(target_id))
	bar.set_targets([_target(7, 6.0, Vector2(900.0, 520.0))])
	bar.set_locked(7)
	check(bar.locked_target == 7, "the lock is applied")
	bar.set_targets([])
	eq(bar.locked_target, -1, "a dead or escaped target releases the lock")
	eq(seen[seen.size() - 1], -1, "the release reaches the simulation")

# ---------------------------------------------------------------- 连线

func test_the_lock_line_joins_the_portrait_and_the_enemy() -> void:
	var bar := _bar()
	bar.set_targets([_target(7, 6.0, Vector2(900.0, 520.0))])
	bar.set_locked(7)
	var line: Array = bar.line_endpoints()
	eq(line.size(), 2, "a locked target draws exactly one line")
	if line.size() < 2:
		return
	var slot: Rect2 = bar.portrait_rect(0)
	near(line[0].x, slot.get_center().x, 0.01, "the line starts at the portrait")
	near(line[0].y, slot.get_center().y, 0.01, "the line starts at the portrait")
	near(line[1].x, 900.0, 0.01, "the line ends on the enemy")
	near(line[1].y, 520.0, 0.01, "the line ends on the enemy")
	check(bar.is_locked_in_view(), "a visible enemy is lockable in view")

func test_no_line_before_anything_is_locked() -> void:
	var bar := _bar()
	bar.set_targets([_target(7, 6.0, Vector2(900.0, 520.0))])
	eq(bar.line_endpoints().size(), 0, "an unlocked bar draws no line")

func test_offscreen_enemy_gets_the_line_clipped_to_the_screen() -> void:
	# 头像被夹回屏内、敌人却在右边缘外一点点时，线不能画到画布外（玩家会以为线断了）。
	var bar := _bar()
	bar.set_targets([_target(7, 6.0, Vector2(2060.0, 400.0))])
	bar.set_locked(7)
	var line: Array = bar.line_endpoints()
	eq(line.size(), 2, "an offscreen enemy still gets a line")
	if line.size() < 2:
		return
	check(line[1].x <= 2000.0 and line[1].y <= 900.0, "the line must stop at the screen edge (%s)" % [line[1]])
	check(line[1].x >= 0.0 and line[1].y >= 0.0, "the line must stop at the screen edge (%s)" % [line[1]])
	check(not bar.is_locked_in_view(), "an offscreen target is not in view")
