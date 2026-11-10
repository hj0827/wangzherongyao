extends "res://tests/test_base.gd"

# 技能图标唯一性（P0 视觉升级）。
#
# 旧版 17 种技能只有 5 族图形，同族技能键面完全一样。
# 现在族图形之外再盖一枚 kind 专属小印记；这里钉住"任意两个 kind 的图形不同"。

const SkillGlyph = preload("res://scripts/ui/skill_glyph.gd")

const KINDS := [
	"slash", "spin", "dash", "leap_slam",
	"burst", "line", "slow", "meteor_storm",
	"quake", "charge", "shield", "taunt_aura",
	"arrow", "aoe_shot", "haste", "arrow_barrage", "evade",
	"summoner", "attack", "",
]

func _signature(kind: String) -> String:
	var parts: Array[String] = []
	for shape in SkillGlyph.shapes(kind, Vector2.ZERO, 35.0):
		var type := str(shape.get("type", ""))
		parts.append(type)
		if type == "poly":
			var points: PackedVector2Array = shape.get("points", PackedVector2Array())
			for point in points:
				parts.append("%.2f,%.2f" % [point.x, point.y])
			parts.append("w%.1f" % float(shape.get("width", 0.0)))
		elif type == "line":
			var a: Vector2 = shape.get("a", Vector2.ZERO)
			var b: Vector2 = shape.get("b", Vector2.ZERO)
			parts.append("%.2f,%.2f>%.2f,%.2f" % [a.x, a.y, b.x, b.y])
			parts.append("w%.1f" % float(shape.get("width", 0.0)))
	return "|".join(parts)

func test_every_kind_has_a_unique_shape_signature() -> void:
	var seen := {}
	for kind in KINDS:
		var sig := _signature(kind)
		check(not seen.has(sig), "kind '%s' 与 '%s' 图形完全相同" % [kind, seen.get(sig, "")])
		seen[sig] = kind
	eq(seen.size(), KINDS.size(), "每个 kind 都必须有独立图形")

func test_marks_add_shapes_without_escaping_the_ring() -> void:
	for kind in KINDS:
		var shapes := SkillGlyph.shapes(kind, Vector2.ZERO, 35.0)
		gt(shapes.size(), 2, "kind '%s' 至少要 2 个基础图形 + 1 个印记" % kind)
		for shape in shapes:
			if str(shape.get("type", "")) != "poly":
				continue
			var points: PackedVector2Array = shape.get("points", PackedVector2Array())
			for point in points:
				lt(point.length(), 35.0 * 0.66, "kind '%s' 的印记不能顶到圆环" % kind)
