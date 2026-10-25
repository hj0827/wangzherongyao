extends "res://tests/test_base.gd"

## 小地图英雄头像（2026-10-25）。
##
## 英雄在缩略图上原来只是一个圆点/箭头，混战里认不出「那个红点是哪个英雄」。
## 改成王者荣耀式的圆形头像：裁成圆、带队伍色环，朝向用小三角贴在环外。

const Minimap = preload("res://scripts/ui/minimap.gd")
const HeroDefs = preload("res://sim/hero_defs.gd")
const GameTheme = preload("res://scripts/ui/game_theme.gd")

func test_every_hero_has_a_round_minimap_avatar() -> void:
	for hero_type in HeroDefs.BOT_TYPES:
		var tex: Texture2D = Minimap.hero_avatar(str(hero_type))
		check(tex != null, "missing minimap avatar for %s" % hero_type)
		if tex == null:
			continue
		eq(tex.get_width(), Minimap.AVATAR_TEXTURE_SIZE, "%s avatar must be square" % hero_type)
		eq(tex.get_height(), Minimap.AVATAR_TEXTURE_SIZE, "%s avatar must be square" % hero_type)
		var img := tex.get_image()
		check(img != null and not img.is_empty(), "%s avatar must keep its pixels" % hero_type)
		if img == null or img.is_empty():
			continue
		# 四角必须透明：方形贴图在地图上会盖住地块，读起来像一块色块而不是头像。
		lt(img.get_pixel(0, 0).a, 0.05, "%s avatar corner must be transparent" % hero_type)
		lt(img.get_pixel(Minimap.AVATAR_TEXTURE_SIZE - 1, 0).a, 0.05, "%s avatar corner must be transparent" % hero_type)
		var middle := Minimap.AVATAR_TEXTURE_SIZE / 2
		gt(img.get_pixel(middle, middle).a, 0.9, "%s avatar center must stay opaque" % hero_type)

func test_face_crop_is_square_and_inside_the_portrait() -> void:
	# 裁切的宽高必须相等：非方形会在圆形头像里把脸拉扁。
	var crop: Rect2 = Minimap.HERO_FACE_CROP
	near(crop.size.x, crop.size.y, 0.001, "the face crop must be square")
	check(crop.position.x >= 0.0 and crop.position.y >= 0.0, "the face crop must start inside the portrait")
	check(crop.end.x <= 1.0 and crop.end.y <= 1.0, "the face crop must end inside the portrait")
	check(crop.size.x >= 0.3, "a tiny crop would only show an eye at minimap size")

func test_unknown_hero_type_has_no_avatar() -> void:
	# 快照里 hero_type 缺失/未知时不能崩，也不能画出一张空图：调用方回落到队伍色圆点。
	check(Minimap.hero_avatar("") == null, "empty hero type must have no avatar")
	check(Minimap.hero_avatar("no_such_hero") == null, "unknown hero type must have no avatar")

func test_hero_marker_color_follows_relation_not_absolute_team() -> void:
	# 小地图上的英雄按「和本地玩家的关系」着色：自己绿 / 友军蓝 / 敌军红 ——
	# 和头顶血条同一套语义。**不能按绝对阵营**：红方玩家眼里的队友是红队，
	# 按阵营画就成了满屏红点，读出来是「我被一群敌人围住了」。
	eq(Minimap.hero_mark_color(true, "red", "red"), GameTheme.GREEN, "自己永远是绿（不分阵营）")
	eq(Minimap.hero_mark_color(true, "blue", "blue"), GameTheme.GREEN, "自己永远是绿")
	eq(Minimap.hero_mark_color(false, "red", "red"), GameTheme.BLUE, "红方玩家看红队队友必须是蓝")
	eq(Minimap.hero_mark_color(false, "blue", "red"), GameTheme.RED, "红方玩家看蓝队是敌军，必须红")
	eq(Minimap.hero_mark_color(false, "blue", "blue"), GameTheme.BLUE, "蓝方玩家看蓝队队友是蓝")
	eq(Minimap.hero_mark_color(false, "red", "blue"), GameTheme.RED, "蓝方玩家看红队是红")

func test_the_three_hero_colors_are_far_apart_in_hue() -> void:
	# 三个颜色必须靠通道差分开，而不是靠亮度：小地图只有 14px，亮度差读不出来。
	# 这条同时挡住「把常量换成同一个色系」这类改动。
	var green := Minimap.hero_mark_color(true, "blue", "blue")
	var ally := Minimap.hero_mark_color(false, "blue", "blue")
	var enemy := Minimap.hero_mark_color(false, "red", "blue")
	gt(green.g - green.r, 0.2, "自己必须真的偏绿（%s）" % str(green))
	gt(ally.b - ally.g, 0.2, "友军必须真的偏蓝（%s）" % str(ally))
	gt(enemy.r - enemy.g, 0.3, "敌军必须真的偏红（%s）" % str(enemy))
	gt(enemy.r - ally.r, 0.3, "敌军和友军在红通道上必须拉开，否则远看都是亮点")

	var hero: Dictionary = Minimap.entity_mark({"type": "hero", "team": "red"})
	var minion: Dictionary = Minimap.entity_mark({"type": "minion", "team": "red"})
	check(not hero.is_empty(), "hero must keep a minimap mark")
	gt(float(hero.radius), float(minion.radius) * 3.0, "a head icon needs far more room than a minion dot")
	lt(float(hero.radius), 10.0, "the avatar must not swallow the lane")

func test_facing_tab_sits_outside_the_avatar_rim() -> void:
	for facing in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
		var radius := 8.0
		var tab := Minimap.hero_facing_tab(Vector2.ZERO, facing, radius)
		eq(tab.size(), 3, "the facing tab is a triangle")
		var dir: Vector2 = (facing as Vector2).normalized()
		var side := Vector2(-dir.y, dir.x)
		gt(tab[0].dot(dir), radius, "the tip must stick out past the avatar rim (%s)" % facing)
		near(tab[1].dot(dir), radius, 0.01, "the left base must sit on the rim")
		near(tab[2].dot(dir), radius, 0.01, "the right base must sit on the rim")
		near(tab[1].dot(side), -tab[2].dot(side), 0.01, "the tab must be symmetric")
		gt(absf(tab[1].dot(side)), 1.0, "the tab must actually spread")

func test_facing_tab_follows_the_hero_direction() -> void:
	var right := Minimap.hero_facing_tab(Vector2.ZERO, Vector2(1, 0), 8.0)
	var down := Minimap.hero_facing_tab(Vector2.ZERO, Vector2(0, 1), 8.0)
	gt(right[0].distance_to(down[0]), 4.0, "rotating the hero must rotate the tab")

func test_zero_facing_tab_does_not_collapse() -> void:
	# 出生/传送落地瞬间 facing 是 (0,0)，不能画出零面积三角形。
	var tab := Minimap.hero_facing_tab(Vector2(10, 10), Vector2.ZERO, 8.0)
	eq(tab.size(), 3, "a zero facing must still produce a triangle")
	lt(tab[0].y, 10.0, "zero facing falls back to pointing up (screen y grows downward)")
	for point in tab:
		check(not is_nan(point.x) and not is_nan(point.y), "the tab must not contain NaN")
