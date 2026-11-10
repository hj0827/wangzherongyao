extends "res://tests/test_base.gd"

# HERO-04 定制模型接入契约。
# 当前没有 5 套定制 glb，必须稳定回退共享模型；未来按路径放入即生效。

const Registry = preload("res://scripts/game/hero_model_registry.gd")

func test_custom_model_path_convention() -> void:
	for hero_type in ["blade", "mage", "tank", "archer", "assassin"]:
		eq(Registry.model_path(hero_type), "res://assets/characters/hero_models/%s/%s.glb" % [hero_type, hero_type], "路径约定不能漂移")
		check(not Registry.has_custom_model(hero_type), "当前不应存在定制模型：%s" % hero_type)

func test_required_animation_contract() -> void:
	for anim_name in ["Idle", "Walk", "Sword_Regular_A", "Sword_Regular_B", "Sword_Regular_C", "Roll", "Hit_Chest", "Death01"]:
		check(Registry.REQUIRED_ANIMATIONS.has(anim_name), "缺少必需动作：%s" % anim_name)
	var missing := Registry.missing_animations(null)
	eq(missing.size(), Registry.REQUIRED_ANIMATIONS.size(), "空 AnimationPlayer 应报告全部缺失")

func test_shared_model_fallback_still_builds() -> void:
	var UnitVisual = load("res://scripts/game/unit_visual.gd")
	var view = UnitVisual.new()
	view.setup("hero", "blue", "blade", "苍刃", false, "blue")
	check(view.model_root != null, "没有定制模型时必须回退共享模型")
	view.free()
