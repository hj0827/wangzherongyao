extends RefCounted
class_name HeroModelRegistry

## HERO-04 定制模型接入契约。
##
## 约定目录：
##   res://assets/characters/hero_models/<hero_type>/<hero_type>.glb
## 例：res://assets/characters/hero_models/blade/blade.glb
##
## 模型必须自带骨骼、服装、武器与动作；UnitVisual 不再拼 body/outfit/hair/weapon。
## 动作名沿用 UAL 命名（与现有 ANIM_ATTACK / ANIM_Q 表兼容），见 docs/英雄定制模型规范-HERO-04.md。

const CUSTOM_ROOT := "res://assets/characters/hero_models/"

const REQUIRED_ANIMATIONS := [
	"Idle",
	"Walk",
	"Run",
	"Sword_Regular_A",
	"Sword_Regular_B",
	"Sword_Regular_C",
	"Roll",
	"Hit_Chest",
	"Death01",
]

static func model_path(hero_type: String) -> String:
	if hero_type == "":
		return ""
	return CUSTOM_ROOT + hero_type + "/" + hero_type + ".glb"

static func has_custom_model(hero_type: String) -> bool:
	var path := model_path(hero_type)
	return path != "" and ResourceLoader.exists(path)

static func missing_animations(player: AnimationPlayer) -> Array[String]:
	var missing: Array[String] = []
	if player == null:
		for anim_name in REQUIRED_ANIMATIONS:
			missing.append(anim_name)
		return missing
	for anim_name in REQUIRED_ANIMATIONS:
		if not player.has_animation(anim_name):
			missing.append(anim_name)
	return missing
