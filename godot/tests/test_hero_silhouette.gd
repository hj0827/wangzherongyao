extends "res://tests/test_base.gd"

# 英雄剪影（P0 视觉升级）。
#
# 5 个英雄只有 2 套身体模型，靠换装/染色拼出来。这里不要求"定制模型"，
# 但要求横轴体型 + 武器比例真的拉开，且身高仍锚在 HERO_HEIGHT（血条/镜头契约）。

const UnitVisual = preload("res://scripts/game/unit_visual.gd")
const ModelUtils = preload("res://scripts/game/model_utils.gd")

const HEROES := ["blade", "mage", "tank", "archer", "assassin"]

func test_all_heroes_keep_the_same_height() -> void:
	for hero_type in HEROES:
		var view := UnitVisual.new()
		view.setup("hero", "blue", hero_type, hero_type, false, "blue")
		# 武器挂在手骨上，会伸到头顶之外；量身高时先把它藏掉，
		# 只量身体 + 衣服 + 头发，才是 HERO_HEIGHT 的契约。
		var weapon := view.model_root.find_child("WeaponSlot", true, false) as Node3D
		if weapon and weapon.get_parent():
			# relative_aabb 不看 visible，必须真的把武器移出树才是"净身高"。
			weapon.get_parent().remove_child(weapon)
		var box := ModelUtils.relative_aabb(view.model_root)
		near(box.size.y, UnitVisual.HERO_HEIGHT, 0.12, "%s 身高必须仍锚在 HERO_HEIGHT" % hero_type)
		if weapon:
			weapon.free()
		view.free()

func test_hero_widths_are_visibly_different() -> void:
	var widths := {}
	for hero_type in HEROES:
		var view := UnitVisual.new()
		view.setup("hero", "blue", hero_type, hero_type, false, "blue")
		widths[hero_type] = snappedf(ModelUtils.relative_aabb(view.model_root).size.x, 0.05)
		view.free()
	var unique := {}
	for hero_type in widths:
		unique[widths[hero_type]] = hero_type
	check(unique.size() >= 4, "5 个英雄至少要有 4 种不同宽度，实际 %s" % str(widths))
	var lowest := 999.0
	var highest := 0.0
	for hero_type in widths:
		lowest = minf(lowest, float(widths[hero_type]))
		highest = maxf(highest, float(widths[hero_type]))
	gt(highest - lowest, 0.15, "最宽与最窄英雄的差距要肉眼可辨（%.2f m）" % (highest - lowest))

func test_weapons_carry_the_hero_accent() -> void:
	for hero_type in HEROES:
		var view := UnitVisual.new()
		view.setup("hero", "blue", hero_type, hero_type, false, "blue")
		var slot := view.model_root.find_child("WeaponSlot", true, false)
		check(slot != null, "%s 必须有 WeaponSlot" % hero_type)
		var tinted := false
		if slot:
			for node in slot.find_children("*", "MeshInstance3D", true, false):
				var mesh_instance := node as MeshInstance3D
				if mesh_instance.mesh == null:
					continue
				for surface in mesh_instance.mesh.get_surface_count():
					if mesh_instance.get_surface_override_material(surface) != null:
						tinted = true
		check(tinted, "%s 的武器要带主色染色" % hero_type)
		view.free()

func test_hero_setup_declares_its_own_body_and_weapon_scale() -> void:
	var body_scales := {}
	var weapon_scales := {}
	for hero_type in HEROES:
		var setup: Dictionary = UnitVisual.HERO_SETUPS.get(hero_type, {})
		check(setup.has("body_scale"), "%s 必须声明 body_scale" % hero_type)
		if setup.has("body_scale"):
			body_scales[str(setup["body_scale"])] = hero_type
		weapon_scales[str(setup.get("weapon_scale", 0.0))] = hero_type
	eq(body_scales.size(), HEROES.size(), "5 个英雄的 body_scale 必须两两不同")
	eq(weapon_scales.size(), HEROES.size(), "5 个英雄的 weapon_scale 必须两两不同")
