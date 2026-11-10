extends "res://tests/test_base.gd"

# VFX 位图资产（P1）。
# 以前是程序化 GradientTexture2D；现在优先加载 assets/vfx/textures 下的 PNG。

const FxTextures = preload("res://scripts/game/fx_textures.gd")

func test_bitmap_vfx_textures_are_loaded_and_cached() -> void:
	for name in ["glow", "spark", "shock", "rune", "slash", "smoke"]:
		var first := FxTextures.file_texture(str(name))
		check(first != null, "缺少 VFX 贴图：%s" % name)
		if first:
			check(FxTextures.file_texture(str(name)) == first, "VFX 贴图要缓存：%s" % name)
			eq(first.get_width(), first.get_height(), "VFX 贴图必须是正方形：%s" % name)

func test_soft_glow_prefers_the_bitmap_glow() -> void:
	var glow := FxTextures.file_texture("glow")
	check(glow != null, "glow.png 必须存在")
	if glow:
		check(FxTextures.soft_glow() == glow, "soft_glow 必须优先使用位图 glow.png")
