extends SceneTree
const HeroLook = preload("res://scripts/game/hero_look.gd")
const UnitVisual = preload("res://scripts/game/unit_visual.gd")
const HeroCostume = preload("res://scripts/game/hero_costume.gd")
const SkillFx = preload("res://scripts/game/skill_fx.gd")
const HeroDefs = preload("res://sim/hero_defs.gd")
func _initialize() -> void:
	print("%-9s %-16s %-14s %-22s %-10s" % ["英雄","主色","待机","武器握持","技能变体"])
	for hero in ["blade","mage","tank","archer","assassin"]:
		var view := UnitVisual.new()
		view.setup("hero", "blue", hero, hero, false, "blue")
		var p := HeroLook.primary(hero)
		var idle := HeroLook.idle_pose(hero)
		var box := ModelUtilsAabb(view.model_root)
		var wpn := view.model_root.find_child("WeaponSlot", true, false)
		var offs := "有武器" if wpn != null else "无"
		# 技能变体数
		var def := HeroDefs.get_hero(hero)
		var variants := 0
		for slot in ["q","w","e","r"]:
			var kind := str((def.get(slot, {}) as Dictionary).get("kind",""))
			if kind != "" and SkillFx.has_variant(hero, kind):
				variants += 1
		print("%-9s #%s %-14s %-22s %d 个" % [hero, p.to_html(false), idle, offs, variants])
		view.free()
	quit()
func ModelUtilsAabb(root: Node) -> AABB:
	const MU = preload("res://scripts/game/model_utils.gd")
	return MU.relative_aabb(root)
