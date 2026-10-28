extends "res://tests/test_base.gd"

# 野怪 UI 契约：
# 1. 野怪头顶要有名字，蓝/红 BUFF 与首领要能一眼区分。
# 2. 营地/首领坑地面要有符阵，野怪死亡时暗下去、重生时亮回来。
# 3. 野怪死亡后视图会被回收，倒计时牌必须留在营地上。

const Arena = preload("res://scripts/game/arena.gd")
const MapLayout = preload("res://sim/map/map_layout.gd")
const ModelUtils = preload("res://scripts/game/model_utils.gd")
const UnitVisual = preload("res://scripts/game/unit_visual.gd")

const SIGIL_SHADER := "res://shaders/camp_sigil.gdshader"

func test_monster_badge_names_buff_type_and_objective() -> void:
	var blue := UnitVisual.new()
	blue.setup("monster", "neutral", "wolf", "霜狼", false, "blue")
	check(blue.name_label != null, "野怪必须有头顶名牌")
	if blue.name_label:
		eq(blue.name_label.text, "霜狼", "默认显示野怪名")
	blue.set_monster_badge("blue", false)
	if blue.name_label:
		check(blue.name_label.text.contains("蓝BUFF"), "蓝 BUFF 怪要标出增益")
		check(blue.name_label.modulate.b > blue.name_label.modulate.r, "蓝 BUFF 名牌偏蓝")
	blue.set_monster_badge("red", false)
	if blue.name_label:
		check(blue.name_label.text.contains("红BUFF"), "红 BUFF 怪要标出增益")
		check(blue.name_label.modulate.r > blue.name_label.modulate.b, "红 BUFF 名牌偏红")
	blue.set_monster_badge("", true)
	if blue.name_label:
		check(blue.name_label.text.contains("首领"), "主宰/暴君要标出首领身份")

	var minion := UnitVisual.new()
	minion.setup("minion", "blue", "melee", "", false, "blue")
	minion.set_monster_badge("blue", false)
	check(minion.name_label == null, "小兵没有野怪名牌")
	blue.free()
	minion.free()

func test_objective_monsters_tower_over_heroes_and_match_their_hitbox() -> void:
	var tyrant := UnitVisual.new()
	tyrant.setup("monster", "neutral", "orc", "暴君", false, "blue", true, "tyrant")
	var tyrant_box := ModelUtils.relative_aabb(tyrant.model_root)
	check(tyrant.is_objective, "暴君必须走首领体型分支")
	near(tyrant_box.size.y, UnitVisual.TYRANT_HEIGHT, 0.05, "暴君身高 3.8 m")
	check(tyrant_box.size.y >= UnitVisual.HERO_HEIGHT * 1.35, "暴君至少比英雄高 35%")
	# 模拟层暴君碰撞半径 2.6（直径 5.2）：身板宽度要能对得上，不能看小打大。
	check(tyrant_box.size.x > 4.4 and tyrant_box.size.x < 5.8, "暴君身板宽度贴合 2.6 碰撞半径")
	check(tyrant.bar_root.position.y > UnitVisual.HERO_HEIGHT + 1.0, "首领血条要整体抬到英雄头顶之上")

	var overlord := UnitVisual.new()
	overlord.setup("monster", "neutral", "orc", "主宰", false, "blue", true, "overlord")
	var overlord_height := ModelUtils.relative_aabb(overlord.model_root).size.y
	near(overlord_height, UnitVisual.OVERLORD_HEIGHT, 0.05, "主宰身高 4.2 m")
	check(overlord_height > tyrant_box.size.y, "主宰要比暴君更大")

	var camp_orc := UnitVisual.new()
	camp_orc.setup("monster", "neutral", "orc", "石卫", false, "blue")
	near(ModelUtils.relative_aabb(camp_orc.model_root).size.y, 2.4, 0.05, "普通兽人营地保持原身高")
	check(not camp_orc.is_objective, "普通营地不能误走首领体型")
	tyrant.free()
	overlord.free()
	camp_orc.free()

func test_arena_routes_objective_identity_into_the_monster_view() -> void:
	var arena: Node3D = Arena.new()
	arena._units_root = Node3D.new()
	arena.add_child(arena._units_root)
	var view: UnitVisual = arena._create_unit_view({
		"id": 77, "type": "monster", "team": "neutral", "monster_type": "orc",
		"name": "暴君", "x": 0.0, "y": 0.0, "hp": 6800.0, "max_hp": 6800.0,
		"alive": true, "objective": true, "objective_id": "tyrant", "radius": 2.6,
	})
	check(view.is_objective, "Arena 必须把 objective 标记传给表现层")
	eq(view.objective_id, "tyrant", "Arena 必须把坑位 id 传下去，暴君/主宰才能分尺寸")
	near(ModelUtils.relative_aabb(view.model_root).size.y, UnitVisual.TYRANT_HEIGHT, 0.05, "战场里的暴君也是首领体型")
	arena.free()

func test_camp_sigils_and_respawn_labels_follow_monster_state() -> void:
	var arena: Node3D = Arena.new()
	arena._props_root = Node3D.new()
	arena.add_child(arena._props_root)
	arena._build_map_features()

	for camp in MapLayout.CAMPS:
		var key := "camp_" + str(camp.id)
		check(arena._camp_sigils.has(key), "每个营地都要有符阵：" + key)
		check(arena._camp_labels.has(str(camp.id)), "每个营地都要有重生牌：" + str(camp.id))
		check(
			arena._props_root.get_node_or_null(NodePath("camp_sigil_" + key)) != null,
			"符阵必须作为独立节点挂在地面上：" + key
		)
	for pit in MapLayout.OBJECTIVE_PITS:
		check(arena._camp_sigils.has("pit_" + str(pit.id)), "首领坑也要有符阵：" + str(pit.id))
		check(arena._camp_labels.has(str(pit.id)), "首领坑也要有重生牌：" + str(pit.id))

	var camp: Dictionary = MapLayout.CAMPS[0]
	var label: Label3D = arena._camp_labels.get(str(camp.id), null)
	var material: ShaderMaterial = arena._camp_sigils.get("camp_" + str(camp.id), null)
	check(label != null and material != null, "第一个营地的牌与符阵都已创建")
	if label == null or material == null:
		arena.free()
		return
	check(not label.visible, "野怪活着时重生牌隐藏")
	near(float(material.get_shader_parameter("active")), 1.0, 0.001, "野怪活着时符阵点亮")

	var dead := {"entities": [{
		"id": 900, "type": "monster", "team": "neutral",
		"x": float(camp.pos.x), "y": float(camp.pos.y),
		"hp": 0.0, "max_hp": 100.0, "alive": false,
		"camp_id": str(camp.id), "name": str(camp.name), "respawn_timer": 42.4,
	}]}
	arena._sync_camp_states(dead)
	check(label.visible, "野怪死亡后营地显示重生倒计时")
	check(label.text.contains(str(camp.name)), "倒计时牌要写清是哪个野怪")
	check(label.text.contains("43"), "剩余秒数向上取整（42.4 → 43）")
	near(float(material.get_shader_parameter("active")), 0.0, 0.001, "野怪死亡后符阵暗下去")

	var alive := {"entities": [{
		"id": 900, "type": "monster", "team": "neutral",
		"x": float(camp.pos.x), "y": float(camp.pos.y),
		"hp": 100.0, "max_hp": 100.0, "alive": true,
		"camp_id": str(camp.id), "name": str(camp.name), "respawn_timer": 0.0,
	}]}
	arena._sync_camp_states(alive)
	check(not label.visible, "重生后倒计时牌隐藏")
	near(float(material.get_shader_parameter("active")), 1.0, 0.001, "重生后符阵重新点亮")
	arena.free()

func test_camp_sigil_shader_is_a_ground_sigil_not_a_flat_tint() -> void:
	var shader: Shader = load(SIGIL_SHADER)
	check(shader != null, "营地符阵 shader 必须存在")
	if shader == null:
		return
	var code := shader.code
	check(code.contains("spin_speed"), "符阵要有旋转刻线")
	check(code.contains("active"), "符阵要能被野怪存活状态切换")
	check(code.contains("depth_draw_never"), "贴地符阵不能写入深度")
	check(code.contains("blend_add"), "符阵用加色混合，读成发光阵纹")
