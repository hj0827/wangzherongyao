extends "res://tests/test_base.gd"

# 选人页 3D 预览骨架（HERO-03 第一版）。
# 复用现有 UnitVisual 模型；不新增模型/动作资产。

const HeroPreview = preload("res://scripts/app/hero_preview.gd")

func test_preview_builds_a_viewport_and_current_hero_model() -> void:
	var preview: SubViewportContainer = HeroPreview.new()
	preview.setup("blade")
	check(preview.get_child_count() > 0, "预览必须创建 SubViewport")
	var hero = preview.get("_hero")
	check(hero != null, "预览必须装配英雄模型")
	if hero != null:
		check(hero.model_root != null, "英雄模型要有 model_root")
		check(hero.kind == "hero", "预览走英雄装配分支")
	check(preview.get("_pivot") != null, "预览要有旋转支点")
	preview.free()

func test_switching_hero_rebuilds_the_model() -> void:
	var preview: SubViewportContainer = HeroPreview.new()
	preview.setup("blade")
	var first = preview.get("_hero")
	preview.setup("mage")
	var second = preview.get("_hero")
	check(first != second, "切换英雄要重建模型")
	check(str(preview.get("_current_hero")) == "mage", "当前英雄要更新")
	preview.free()
