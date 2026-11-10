extends "res://tests/test_base.gd"

# 位图视觉资产（P1 批次）。
# 技能 19 张、状态 8 张、VFX 6 张、9-slice 边框、小地图底图。

const GameTheme = preload("res://scripts/ui/game_theme.gd")
const FxTextures = preload("res://scripts/game/fx_textures.gd")

const SKILLS := [
	"slash", "spin", "dash", "leap_slam", "burst", "line", "slow",
	"meteor_storm", "quake", "charge", "shield", "taunt_aura",
	"arrow", "aoe_shot", "haste", "arrow_barrage", "evade",
	"attack", "summoner",
]
const STATUSES := ["buff_red", "buff_blue", "shield", "slow", "haste", "regen", "stun", "silence"]

func test_every_skill_kind_has_a_bitmap_icon() -> void:
	for kind in SKILLS:
		check(GameTheme.has_skill_icon(str(kind)), "缺少技能图标：%s" % kind)
		var texture := GameTheme.skill_icon(str(kind))
		check(texture != null, "技能图标加载失败：%s" % kind)
		if texture:
			eq(texture.get_width(), texture.get_height(), "技能图标必须是正方形：%s" % kind)
			gt(float(texture.get_width()), 64.0, "技能图标尺寸太小：%s" % kind)

func test_every_status_has_an_icon() -> void:
	for status in STATUSES:
		var texture := GameTheme.status_icon(str(status))
		check(texture != null, "缺少状态图标：%s" % status)
		if texture:
			eq(texture.get_width(), texture.get_height(), "状态图标必须是正方形：%s" % status)

func test_vfx_and_ui_textures_load() -> void:
	for name in ["glow", "spark", "shock", "rune", "slash", "smoke"]:
		check(FxTextures.file_texture(str(name)) != null, "缺少 VFX 贴图：%s" % name)
	check(GameTheme.minimap_background() != null, "缺少小地图底图")
	var panel := GameTheme.ornate_panel()
	check(panel.texture != null, "缺少 9-slice 面板边框")

func test_texture_cache_returns_same_instance() -> void:
	var first := GameTheme.skill_icon("slash")
	check(first != null and GameTheme.skill_icon("slash") == first, "技能图标要缓存")
	var small := GameTheme.skill_icon("slash", 64)
	check(small != null and small.get_width() == 64, "尺寸请求要真的降采样")
