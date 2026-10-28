extends "res://tests/test_base.gd"

## 战场观感护栏（2026-10-24）。
##
## 这几条不是「好不好看」，而是四件会静默失效的事：
## 1. bloom 被关掉 —— 技能/水晶/塔的发光不会有溢出，画面只是「浅色块」；
## 2. 地形不投影 —— 山体和丘陵不落到地面上，远山像一排贴纸；
## 3. 饱和度回到 1.1 —— 草地变塑料绿；
## 4. 阵营色偏消失 —— 蓝红半场一样，玩家只能靠小地图判断方位。
##
## 参数全部收在 arena_look.gd，这里只断言「值」和「arena 真的用了它」。

const ArenaLook = preload("res://scripts/game/arena_look.gd")
const TerrainBuilder = preload("res://scripts/game/terrain_builder.gd")

func test_bloom_is_on_and_has_real_intensity() -> void:
	var env := Environment.new()
	ArenaLook.apply_environment(env)
	check(env.glow_enabled, "bloom must be enabled on the battlefield environment")
	gt(env.glow_intensity, 0.4, "glow intensity is high enough to be visible")
	gt(env.glow_bloom, 0.0, "a little bloom keeps highlights from looking like hard-edged discs")

func test_ssao_flag_is_honest_about_the_renderer() -> void:
	# GL Compatibility 不支持 SSAO：开着不报错也不出效果。
	# 常量必须如实反映「没开」，否则以后有人以为接触阴影已经有人管了。
	var env := Environment.new()
	ArenaLook.apply_environment(env)
	eq(env.ssao_enabled, ArenaLook.SSAO_ENABLED, "the environment must match the SSAO constant")
	var project := FileAccess.get_file_as_string("res://project.godot")
	if project.contains("gl_compatibility"):
		check(not ArenaLook.SSAO_ENABLED, "GL Compatibility cannot do SSAO, so the constant stays false")

func test_saturation_comes_down_from_oversaturated() -> void:
	var env := Environment.new()
	ArenaLook.apply_environment(env)
	near(env.adjustment_saturation, ArenaLook.SATURATION, 0.001, "the environment reads the shared saturation")
	lt(ArenaLook.SATURATION, 1.0, "saturation must sit below 1.0 or the grass turns plastic")
	gt(ArenaLook.SATURATION, 0.85, "saturation must not wash the map grey")
	# 乘数也要跟着降：只改 adjustment 不改贴图乘数，草地还是翠的。
	check(ArenaLook.GRASS_GAIN.y < 0.55, "the grass multiplier must not push green past 0.55")

func test_ambient_drops_so_form_shadows_read() -> void:
	# 环境光 0.68 时整张图是均匀打亮的，山体和单位都没有暗面。
	lt(ArenaLook.AMBIENT_ENERGY, 0.6, "ambient light must leave room for a dark side")
	gt(ArenaLook.SUN_ENERGY, 1.6, "the key light has to carry the contrast ambient gave up")

func test_faction_tint_cools_the_blue_half() -> void:
	var tint := ArenaLook.faction_tint(46.0, -46.0)
	gt(tint.b, tint.r, "the blue half must lean cool")
	gt(tint.b, 1.0, "cool means the blue channel is lifted")

func test_faction_tint_warms_the_red_half() -> void:
	var tint := ArenaLook.faction_tint(-46.0, 46.0)
	gt(tint.r, tint.b, "the red half must lean warm")
	gt(tint.r, 1.0, "warm means the red channel is lifted")

func test_faction_tint_is_neutral_along_the_river() -> void:
	# 河道是两边的分界，河心必须回到中性，否则河面会出现一条明显色带。
	for point in [Vector2(0.0, 0.0), Vector2(12.0, 12.0), Vector2(-30.0, -30.0)]:
		var tint := ArenaLook.faction_tint(point.x, point.y)
		near(tint.r, 1.0, 0.02, "river tint r at %s" % point)
		near(tint.g, 1.0, 0.02, "river tint g at %s" % point)
		near(tint.b, 1.0, 0.02, "river tint b at %s" % point)

func test_faction_tint_stays_subtle_and_continuous() -> void:
	# 阵营色是「暗示」不是「换皮」：任何通道都不许超过 ±10%，
	# 而且沿轴线采样时不能出现跳变（跳变会变成一条可见的直线）。
	var previous := ArenaLook.faction_tint(-58.0, 58.0)
	var worst_step := 0.0
	var worst_channel := 0.0
	for i in 117:
		var t := -58.0 + float(i + 1)
		var current := ArenaLook.faction_tint(t, -t)
		worst_step = maxf(worst_step, absf(current.r - previous.r))
		worst_step = maxf(worst_step, absf(current.g - previous.g))
		worst_step = maxf(worst_step, absf(current.b - previous.b))
		worst_channel = maxf(worst_channel, absf(current.r - 1.0))
		worst_channel = maxf(worst_channel, absf(current.g - 1.0))
		worst_channel = maxf(worst_channel, absf(current.b - 1.0))
		previous = current
	lt(worst_channel, 0.10, "no channel may swing more than 10% across the whole map")
	lt(worst_step, 0.01, "the tint must drift, not step — a step shows up as a seam")

func test_terrain_casts_its_own_shadow() -> void:
	eq(ArenaLook.TERRAIN_SHADOW, GeometryInstance3D.SHADOW_CASTING_SETTING_ON, "the terrain must cast shadows")
	check(
		FileAccess.get_file_as_string("res://scripts/game/arena.gd").contains("ArenaLook.TERRAIN_SHADOW"),
		"arena must take the terrain shadow mode from ArenaLook instead of hard-coding OFF"
	)

func test_terrain_shader_receives_the_faction_colours() -> void:
	var material := TerrainBuilder.build_material()
	var warm: Variant = material.get_shader_parameter("faction_warm")
	var cool: Variant = material.get_shader_parameter("faction_cool")
	check(warm != null and cool != null, "the terrain shader needs faction_warm / faction_cool uniforms")
	if warm != null and cool != null:
		near((warm as Vector3).x, ArenaLook.WARM_TINT.x, 0.001, "warm tint is wired from ArenaLook")
		near((cool as Vector3).z, ArenaLook.COOL_TINT.z, 0.001, "cool tint is wired from ArenaLook")
	var gain: Variant = material.get_shader_parameter("grass_gain")
	check(gain != null, "the grass multiplier must come from ArenaLook.GRASS_GAIN")
	if gain != null:
		near((gain as Vector3).y, ArenaLook.GRASS_GAIN.y, 0.001, "grass gain is wired from ArenaLook")

func test_mobile_terrain_drops_two_fullscreen_texture_samples() -> void:
	# 地表 shader 铺满整屏。手机端保留 1 层草 + 1 层泥土，去掉第二层草与法线，
	# 否则移动镜头时 fill-rate 会把帧率直接压到 20 多。
	var mobile := TerrainBuilder.build_material(true)
	var mobile_code := mobile.shader.code
	check(not mobile_code.contains("__TERRAIN"), "地形 shader 不能残留未替换的采样占位符")
	check(mobile_code.contains("vec3 g3 = g1;"), "手机端不应再采样第二层草")
	check(mobile_code.contains("NORMAL_MAP = vec3(0.5, 0.5, 1.0);"), "手机端不采样地表法线")
	var desktop := TerrainBuilder.build_material(false)
	check(desktop.shader.code.contains("vec3 g3 = texture(grass_tex"), "桌面端保留第二层草")
	check(desktop.shader.code.contains("NORMAL_MAP = texture(grass_nor"), "桌面端保留法线贴图")

func test_arena_builds_the_environment_through_arena_look() -> void:
	# 防「参数表写好了但 arena 还在用旧的硬编码」——这正是本仓库踩过的坑。
	var source := FileAccess.get_file_as_string("res://scripts/game/arena.gd")
	check(source.contains("ArenaLook.apply_environment("), "arena must apply the shared environment")
	check(source.contains("ArenaLook.apply_sun("), "arena must apply the shared sun")
	check(not source.contains("adjustment_saturation = 1.1"), "the old oversaturated value must be gone")
