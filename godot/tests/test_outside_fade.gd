extends "res://tests/test_base.gd"

# 墙外渐隐的回归守卫。
#
# 起因：边界墙（±58）外面还有 70 米草地 + 丘陵，它是背景不是玩法区，
# 但铺满了画面上缘和两侧 —— 玩家贴墙时墙外草地能占掉三分之一屏，
# 比墙内还抢眼。
#
# 契约：从城墙内表面往外，地形和水面一起逐渐压暗、去饱和、混冷灰。
# 公式只有一份（ArenaLook.OUTSIDE_*），两个 shader 都从那里拼 ——
# 地形暗了水面不暗，墙外就会留一条亮青色的河，比不压暗更扎眼。

const ArenaLook = preload("res://scripts/game/arena_look.gd")
const TerrainBuilder = preload("res://scripts/game/terrain_builder.gd")
const MapData = preload("res://sim/map_data.gd")

const FADE_PARAMS := [
	"play_half",
	"outside_fade",
	"outside_base",
	"outside_darken",
	"outside_tint",
	"outside_tint_mix",
]

func test_fade_starts_at_the_walkable_boundary() -> void:
	# 起点必须是 MapData.BOUNDS（= 城墙内表面），不能另写一个数：
	# 城墙或可走边界一挪，渐隐起点要跟着挪，否则墙根会露出一条亮带。
	var material := TerrainBuilder.build_material()
	near(float(material.get_shader_parameter("play_half")), MapData.BOUNDS, 0.001, "渐隐起点必须等于可走边界")

func test_every_fade_parameter_is_bound() -> void:
	# 少绑一个参数不会报错，shader 会安静地用默认值 —— 典型的静默失效。
	var material := TerrainBuilder.build_material()
	for key in FADE_PARAMS:
		check(material.get_shader_parameter(key) != null, "材质必须绑上 %s" % key)

func test_shader_source_has_no_leftover_placeholder() -> void:
	# 占位符没替换掉的话 shader 编译会失败，但只在真机上才发现。
	var material := TerrainBuilder.build_material()
	var code := material.shader.code
	check(not code.contains("__OUTSIDE"), "shader 里不能残留 __OUTSIDE 占位符")
	check(code.contains("outside"), "替换后的 shader 必须真的包含墙外渐隐逻辑")

func test_terrain_and_river_share_one_snippet() -> void:
	# 两个 shader 都必须走 apply_outside_fade，而不是各抄一份公式。
	# 用 has_live_line 而不是 contains：把调用注释掉之后字符串还在，守卫会假绿。
	var terrain := FileAccess.get_file_as_string("res://scripts/game/terrain_builder.gd")
	var arena := FileAccess.get_file_as_string("res://scripts/game/arena.gd")
	check(has_live_line(terrain, "ArenaLook.apply_outside_fade("), "地形必须用共享的渐隐片段")
	check(has_live_line(arena, "ArenaLook.apply_outside_fade("), "水面必须用共享的渐隐片段")
	check(has_live_line(terrain, "ArenaLook.bind_outside_fade("), "地形必须绑定共享参数")
	check(has_live_line(arena, "ArenaLook.bind_outside_fade("), "水面必须绑定共享参数")
	# 公式本身只允许出现在 arena_look.gd 里。
	check(not has_live_line(terrain, "smoothstep(play_half"), "地形里不能自带一份渐隐公式")
	check(not has_live_line(arena, "smoothstep(play_half"), "水面里不能自带一份渐隐公式")

func test_fade_uses_chebyshev_distance_not_euclidean() -> void:
	# 城墙是方的、clamp_bounds 也是方的。用欧氏距离会让四个角比四条边晚暗一大圈，
	# 角上留一块亮斑 —— 那正是「墙外没收干净」的观感来源。
	var code := ArenaLook.OUTSIDE_APPLY
	check(code.contains("max(abs(wpos.x), abs(wpos.z))"), "渐隐必须按切比雪夫距离（方形口径）")

func test_wall_root_is_already_dimmed() -> void:
	# 从 0 开始渐变是错的：画面里看到的墙外恰恰是墙脚下最近那一圈，
	# 从 0 起意味着「离玩家最近、最该退后的那块」是全场最亮的。
	gt(ArenaLook.OUTSIDE_BASE, 0.3, "墙根处必须已经压掉一截")
	lt(ArenaLook.OUTSIDE_BASE, 1.0, "墙根处不能直接全暗，否则墙线会变成一条硬边")
	lt(ArenaLook.OUTSIDE_DARKEN, ArenaLook.OUTSIDE_BASE, "越往外越暗，不能反过来")

func test_fade_is_slow_enough_to_read_as_distance() -> void:
	# 太窄就是一圈黑边，太宽就等于没压。18 米在 21 米机位上是「墙根往外一屏半」。
	gt(ArenaLook.OUTSIDE_FADE, 10.0, "过渡太窄会变成黑边")
	lt(ArenaLook.OUTSIDE_FADE, 30.0, "过渡太宽等于没压暗")
