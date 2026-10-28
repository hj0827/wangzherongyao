extends "res://tests/test_base.gd"

# 进草「不可见」标记契约：
# 1. 贴图程序化生成并缓存，不能每次进草重新逐像素算。
# 2. 杏仁眼 + 斜线必须真的画出来，且四角透明（否则头顶是一个黑方块）。
# 3. 只有英雄有这只眼睛，敌人进草不会在本地画面里冒标记。

const BushEye = preload("res://scripts/game/bush_eye.gd")
const UnitVisual = preload("res://scripts/game/unit_visual.gd")
const Arena = preload("res://scripts/game/arena.gd")

func test_texture_is_cached_and_square() -> void:
	var first := BushEye.texture()
	var second := BushEye.texture()
	check(first != null, "眼睛贴图必须生成成功")
	check(first == second, "贴图必须缓存：第二只眼睛复用同一张 ImageTexture")
	if first == null:
		return
	eq(first.get_width(), BushEye.TEXTURE_SIZE, "贴图是 96px 的正方形")
	eq(first.get_height(), BushEye.TEXTURE_SIZE, "贴图是 96px 的正方形")

func test_texture_draws_an_eye_with_a_slash_and_transparent_corners() -> void:
	var texture := BushEye.texture()
	if texture == null:
		check(false, "眼睛贴图必须存在")
		return
	var image := texture.get_image()
	var half := BushEye.TEXTURE_SIZE / 2
	var corner := image.get_pixel(0, 0)
	lt(corner.a, 0.01, "四角必须透明，不能是黑方块")
	var body := image.get_pixel(half + half / 3, half)
	gt(body.a, 0.5, "杏仁眼主体必须不透明")
	var slash := image.get_pixel(half, half)
	gt(slash.a, 0.8, "斜线必须从中心穿过")
	# y = -x 方向上的点必须也被斜线压住：证明斜线不是水平线。
	var on_slash := image.get_pixel(half + half / 4, half - half / 4)
	gt(on_slash.a, 0.5, "斜线方向应为 y = -x")
	# 眼形之外（同一行、更靠外的位置）必须透明，避免变成整块绿雾。
	var outside := image.get_pixel(half + half * 4 / 5, half + half * 4 / 5)
	lt(outside.a, 0.05, "眼形与光晕之外必须透明")

func test_only_hero_views_can_show_the_eye() -> void:
	var hero := UnitVisual.new()
	hero.setup("hero", "blue", "blade", "你", true, "blue")
	check(hero.bush_eye != null, "英雄视图必须构建头顶眼睛节点")
	if hero.bush_eye:
		check(not hero.bush_eye.visible, "默认隐藏")
		check(hero.bush_eye.texture == BushEye.texture(), "使用缓存贴图")
		check(hero.bush_eye.no_depth_test, "眼睛要压在草丛叶簇之上")
	hero.set_bush_hidden(true)
	check(hero.bush_hidden, "进草后记录隐匿态")
	check(hero.bush_eye != null and hero.bush_eye.visible, "进草后头顶显示斜划眼")
	hero.set_bush_hidden(false)
	check(not hero.bush_eye.visible, "出草后眼睛消失")

	var monster := UnitVisual.new()
	monster.setup("monster", "neutral", "wolf", "霜狼", false, "blue")
	monster.set_bush_hidden(true)
	check(not monster.bush_hidden, "野怪不能被误标成隐匿")
	check(monster.bush_eye == null, "野怪视图不构建眼睛节点")
	hero.free()
	monster.free()

func test_arena_routes_the_eye_to_the_local_hero_only() -> void:
	var arena: Node3D = Arena.new()
	var local := UnitVisual.new()
	local.setup("hero", "blue", "blade", "你", true, "blue")
	var enemy := UnitVisual.new()
	enemy.setup("hero", "red", "archer", "敌人", false, "blue")
	arena._views[5] = local
	arena._views[6] = enemy
	arena._local_entity_id = 5
	arena._set_local_bush_eye(true)
	check(local.bush_hidden and local.bush_eye.visible, "本地英雄进草显示头顶眼睛")
	check(not enemy.bush_hidden, "敌方英雄不会被打上隐匿标记")
	arena._set_local_bush_eye(false)
	check(not local.bush_eye.visible, "离开草丛后本地眼睛隐藏")
	arena.free()
	local.free()
	enemy.free()
