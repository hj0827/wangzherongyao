extends "res://tests/test_base.gd"

# 技能强调色（P1 FX-03 的第一版）。
# 英雄谱系色负责"这是谁"，kind 强调色负责"这是哪个技能"；两者 55/45 混合。

const SkillFx = preload("res://scripts/game/skill_fx.gd")

const KINDS := [
	"slash", "spin", "dash", "leap_slam",
	"burst", "line", "slow", "meteor_storm",
	"quake", "charge", "shield", "taunt_aura",
	"arrow", "aoe_shot", "haste", "arrow_barrage", "evade",
	"summoner",
]

func test_every_kind_has_a_distinct_accent_colour() -> void:
	var seen := {}
	for kind in KINDS:
		var color := SkillFx.accent_color(str(kind))
		var key := "%.3f_%.3f_%.3f" % [color.r, color.g, color.b]
		check(not seen.has(key), "kind '%s' 与 '%s' 强调色重复" % [kind, seen.get(key, "")])
		seen[key] = kind
	eq(seen.size(), KINDS.size(), "每个 kind 必须有独立强调色")

func test_blend_keeps_hero_identity_but_shifts_per_kind() -> void:
	var hero_color := Color(1.0, 0.72, 0.30)
	var slash := SkillFx.blend_color(hero_color, "slash")
	var spin := SkillFx.blend_color(hero_color, "spin")
	check(slash != hero_color, "混合后不能还是英雄原色")
	check(spin != hero_color, "混合后不能还是英雄原色")
	check(slash != spin, "同英雄的 Q/W 要靠强调色分开")
	eq(SkillFx.blend_color(hero_color, "slash", 0.0), hero_color, "amount=0 时保持英雄色")
	eq(SkillFx.blend_color(hero_color, "slash", 1.0), SkillFx.accent_color("slash"), "amount=1 时完全取强调色")
