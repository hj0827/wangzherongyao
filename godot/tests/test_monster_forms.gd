extends "res://tests/test_base.gd"

# 野怪形象契约（2026-11-10）。
#
# 这一套守的是「形象」这件事本身，不是「代码不报错」：
#   1. 每个真实野点都能解析到一个建得出来的形态 —— 漏了就是**隐形野怪**（看不见却能被攻击）；
#   2. 形态两两剪影互异 —— 六个野点全都长成同一只狼，是玩家抱怨的原问题；
#   3. 体型与模拟层的碰撞半径对得上 —— 「看着小、实际被打范围大」是俯视 MOBA 的硬伤；
#   4. 红蓝 BUFF 一眼可分（发光色相，不只是靠头顶那行字）；
#   5. 程序化动画真的在动（腿/翅/尾/轨道/呼吸），不是一尊雕像；
#   6. UnitVisual 按快照里的 monster_type 装配（接线关）、死亡会倒地、复活会站回来。

const UnitVisual = preload("res://scripts/game/unit_visual.gd")
const MonsterForms = preload("res://scripts/game/monster_forms.gd")
const MapLayout = preload("res://sim/map/map_layout.gd")
const ModelUtils = preload("res://scripts/game/model_utils.gd")
const MatchSim = preload("res://sim/match_sim.gd")

func _footprint(spec: Dictionary) -> Vector2:
	var box := ModelUtils.relative_aabb(spec["root"])
	return Vector2(maxf(box.size.x, box.size.z), box.size.y)

func _max_emission(root: Node) -> Color:
	var best := Color(0, 0, 0)
	var best_energy := -1.0
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.material_override == null:
			continue
		var material := mesh_instance.material_override as StandardMaterial3D
		if material == null or not material.emission_enabled:
			continue
		if material.emission_energy_multiplier > best_energy:
			best_energy = material.emission_energy_multiplier
			best = material.emission
	return best

# --- 1. 每个野点都有形象，而且不是空模型 ------------------------------------

func test_every_camp_resolves_to_a_buildable_form() -> void:
	for camp in MapLayout.CAMPS:
		var form := MonsterForms.form_key(str(camp.get("monster_type", "")), false, "", str(camp.id))
		check(
			MonsterForms.CAMP_FORMS.has(str(camp.id)),
			"野点 %s 必须在 MonsterForms.CAMP_FORMS 里登记形象（新增野点忘了登记 = 长成一只狼）" % str(camp.id)
		)
		if not MonsterForms.is_procedural(form):
			check(form == "wolf", "%s 的非程序化形态只能是狼，实际 %s" % [str(camp.id), form])
			continue
		var spec := MonsterForms.build(form)
		check(not spec.is_empty(), "%s 必须能拼出形象" % str(camp.id))
		if spec.is_empty():
			continue
		check(spec["root"] is Node3D, "%s 的形象要是一棵 Node3D" % str(camp.id))
		check(spec["body"] is Node3D, "%s 的形象要有可动支点" % str(camp.id))
		var measured := ModelUtils.relative_aabb(spec["root"])
		check(measured.size.y > 0.3, "%s 不能是空壳（高度必须为正）" % str(camp.id))

func test_camp_forms_table_covers_every_camp_and_nothing_else() -> void:
	var registered: Array[String] = []
	for camp in MapLayout.CAMPS:
		registered.append(str(camp.id))
	eq(MonsterForms.CAMP_FORMS.size(), registered.size(), "CAMP_FORMS 与 CAMPS 必须一一对应")
	for camp_id in MonsterForms.CAMP_FORMS:
		check(registered.has(str(camp_id)), "CAMP_FORMS 里的 %s 已经不是野点了（表漂移）" % str(camp_id))

func test_objective_pits_build_their_own_beast() -> void:
	for pit in MapLayout.OBJECTIVE_PITS:
		var form := MonsterForms.form_key(str(pit.get("monster_type", "")), true, str(pit.id))
		eq(form, str(pit.id), "首领坑 id 与形态键同名：%s" % str(pit.id))
		var spec := MonsterForms.build(form, 4.2 if form == "overlord" else 3.8)
		check(not spec.is_empty(), "%s 必须能拼出首领形象" % form)
		if not spec.is_empty():
			near(
				ModelUtils.relative_aabb(spec["root"]).size.y,
				UnitVisual.OVERLORD_HEIGHT if form == "overlord" else UnitVisual.TYRANT_HEIGHT,
				0.05,
				"%s 身高与 UnitVisual 的常量一致（血条/脚下环按它算）" % form
			)

func test_unknown_monster_type_falls_back_to_wolf_instead_of_nothing() -> void:
	# 类型写错（或来自旧版本的 "orc"）时宁可显示一只狼，也不能让野怪隐形。
	eq(MonsterForms.form_key("orc", false, ""), "wolf", "未登记的类型回落狼")
	eq(MonsterForms.form_key("", false, ""), "wolf", "空类型回落狼")
	eq(MonsterForms.form_key("spirit", false, ""), "spirit", "河道之灵走自己的分支")
	var view := UnitVisual.new()
	view.setup("monster", "neutral", "orc", "石卫", false, "blue")
	check(view.model_root != null, "回落形态也必须装配出模型")
	eq(view.monster_form, "wolf", "回落形态记录为 wolf")
	view.free()

# --- 2. 形态两两剪影互异 ----------------------------------------------------

func test_camp_forms_have_distinct_silhouettes() -> void:
	# wolf 走 UnitVisual 的 Wolf.glb 分支；MonsterForms.build("wolf") 按设计返回空字典，
	# 不能直接塞进 _footprint(spec) —— 那会在断言前抛错，测试却仍然 PASS（假绿）。
	var camp_forms := ["lizard", "boar", "bird"]
	var seen: Array[String] = []
	for form in camp_forms:
		var spec := MonsterForms.build(form)
		var shape := "%s" % str(_footprint(spec))
		check(not seen.has(shape), "剪影不能和别的野怪一模一样：%s" % form)
		seen.append(shape)
	var wolf := UnitVisual.new()
	wolf.setup("monster", "neutral", "wolf", "双狼", false, "blue")
	var wolf_box := ModelUtils.relative_aabb(wolf.model_root)
	var wolf_shape := "%s" % str(Vector2(maxf(wolf_box.size.x, wolf_box.size.z), wolf_box.size.y))
	check(not seen.has(wolf_shape), "狼的剪影不能和程序化野怪撞脸")
	wolf.free()

func test_buff_sentinels_differ_in_both_silhouette_and_colour() -> void:
	var blue := MonsterForms.build("blue_sentinel")
	var red := MonsterForms.build("red_sentinel")
	var blue_size := _footprint(blue)
	var red_size := _footprint(red)
	check(
		absf(blue_size.x - red_size.x) > 0.2 or absf(blue_size.y - red_size.y) > 0.1,
		"蓝/红石像的体型要能分开（修长 vs 宽壮）"
	)
	var blue_glow := _max_emission(blue["root"])
	var red_glow := _max_emission(red["root"])
	gt(blue_glow.b - blue_glow.r, 0.2, "蔚蓝石像最亮的发光件必须偏蓝")
	gt(red_glow.r - red_glow.b, 0.3, "猩红石像最亮的发光件必须偏红")

# --- 3. 体型对得上碰撞半径 --------------------------------------------------

func test_form_footprint_tracks_the_collision_radius() -> void:
	for camp in MapLayout.CAMPS:
		var form := MonsterForms.form_key("wolf", false, "", str(camp.id))
		var spec := MonsterForms.build(form)
		if spec.is_empty():
			continue
		var radius := float(camp.get("radius", 1.5))
		var footprint := _footprint(spec).x
		# 上限：形象不能明显超出被攻击的范围（俯视下「看着小、打得到」很怪，
		# 反过来「看着大、打不到」也一样）。下限：不能缩成一个小点。
		check(footprint <= radius * 2.0 + 1.2, "%s 的体量不能超出碰撞直径太多（%.2f）" % [form, footprint])
		check(footprint >= radius * 0.9, "%s 的体量不能明显小于碰撞半径（%.2f）" % [form, footprint])

func test_objective_beasts_fill_their_hit_circle() -> void:
	var tyrant := MonsterForms.build("tyrant", UnitVisual.TYRANT_HEIGHT)
	var overlord := MonsterForms.build("overlord", UnitVisual.OVERLORD_HEIGHT)
	for entry in [{"form": "暴君", "spec": tyrant}, {"form": "主宰", "spec": overlord}]:
		var spec: Dictionary = entry["spec"]
		var box := ModelUtils.relative_aabb(spec["root"])
		# 横向（size.x）对齐碰撞直径 5.6：正对玩家看到的就是这个宽度。
		check(box.size.x > 4.4 and box.size.x < 5.8, "%s 身板宽度贴合 2.8 碰撞半径（%.2f）" % [entry["form"], box.size.x])
		# 纵深可以比直径长一点（四足兽），但不能靠环绕光点把包围盒撑爆。
		check(box.size.z < 6.8, "%s 纵深不能超出碰撞直径太多（%.2f）" % [entry["form"], box.size.z])

# --- 4. 程序化动画真的在动 --------------------------------------------------

func test_procedural_animation_moves_legs_tail_and_orbit() -> void:
	var spec := MonsterForms.build("lizard")
	var leg: Node3D = spec["legs"][0]
	var tail: Node3D = spec["tail"]
	var body: Node3D = spec["body"]
	var rest_y := body.position.y
	for i in 8:
		MonsterForms.animate(spec, 0.05, true, 4.0)
	check(absf(leg.rotation.x) > 0.02, "走路时腿要摆起来")
	check(absf(tail.rotation.y) > 0.01, "尾巴要摇")
	check(absf(body.position.y - rest_y) > 0.005, "身体要有起伏（呼吸/步态）")

func test_bird_wings_flap_and_buff_orbit_spins() -> void:
	var bird := MonsterForms.build("bird")
	var wing: Node3D = bird["wings"][0]
	for i in 8:
		MonsterForms.animate(bird, 0.05, false, 0.0)
	check(absf(wing.rotation.z) > 0.01, "站着也要扇翅膀（否则是一块静态贴图）")

	var sentinel := MonsterForms.build("blue_sentinel")
	var orbit: Node3D = sentinel["orbits"][0]
	for i in 4:
		MonsterForms.animate(sentinel, 0.05, false, 0.0)
	gt(orbit.rotation.y, 0.05, "石像的肩甲要绕体缓转")

func test_moving_swings_legs_harder_than_standing() -> void:
	var idle := MonsterForms.build("boar")
	var walking := MonsterForms.build("boar")
	for i in 10:
		MonsterForms.animate(idle, 0.05, false, 0.0)
		MonsterForms.animate(walking, 0.05, true, 5.0)
	var idle_leg: Node3D = idle["legs"][0]
	var walk_leg: Node3D = walking["legs"][0]
	gt(absf(walk_leg.rotation.x), absf(idle_leg.rotation.x), "移动幅度必须大于待机")

# --- 5. 接线：UnitVisual 按 monster_type 装配 --------------------------------

func test_unit_visual_builds_the_form_named_by_the_snapshot() -> void:
	for camp in MapLayout.CAMPS:
		var view := UnitVisual.new()
		view.setup(
			"monster",
			"neutral",
			str(camp.get("monster_type", "")),
			str(camp.get("name", "")),
			false,
			"blue",
			false,
			"",
			str(camp.id)
		)
		eq(
			view.monster_form,
			str(MonsterForms.CAMP_FORMS.get(str(camp.id), "wolf")),
			"UnitVisual 必须按 camp_id 装配：%s" % str(camp.id)
		)
		check(view.model_root != null, "每个野点都要有模型：%s" % str(camp.id))
		check(view.bar_root != null, "每个野点都要有血条：%s" % str(camp.id))
		view.free()

func test_arena_passes_buff_and_objective_identity_into_the_form() -> void:
	var sim := MatchSim.new({"mode": "duel", "humans": [{"id": "p1", "team": "blue"}], "bot_fill": false})
	var forms := {}
	for entity in sim.snapshot().get("entities", []):
		if str(entity.get("type", "")) != "monster":
			continue
		var form := MonsterForms.form_key(
			str(entity.get("monster_type", "")),
			bool(entity.get("objective", false)),
			str(entity.get("objective_id", "")),
			str(entity.get("camp_id", ""))
		)
		forms[form] = true
	for expected in ["blue_sentinel", "red_sentinel", "wolf", "lizard", "boar", "bird"]:
		check(forms.has(expected), "开局野区要有 %s 的形象" % expected)
	eq(forms.size(), 6, "六个野点必须是六种形象，实际 %d 种" % forms.size())

func test_death_tips_a_boneless_monster_over_and_respawn_stands_it_back_up() -> void:
	var view := UnitVisual.new()
	view.setup("monster", "neutral", "boar", "三猪", false, "blue")
	var alive := {
		"x": 0.0, "y": 0.0, "hp": 500.0, "max_hp": 500.0, "alive": true,
		"facing_x": 0.0, "facing_y": 1.0, "moving": false,
	}
	view.set_snapshot(alive, 1.0)
	var dead := alive.duplicate()
	dead["hp"] = 0.0
	dead["alive"] = false
	view.set_snapshot(dead, 1.0)
	for i in 20:
		view.process_visual(0.05)
	check(view.dead, "血量归零要进入死亡态")
	lt(view.model_root.rotation.x, -0.2, "没有骨骼动作的野怪要程序化倒地，不能站着不动")
	view.set_snapshot(alive, 1.0)
	check(not view.dead, "复活后要回到存活态")
	near(view.model_root.rotation.x, 0.0, 0.001, "复活要把倒地姿态收回去")
	view.free()

func test_monster_view_reuses_shared_materials_across_spawns() -> void:
	# 12 只野怪各建一份材质的话，真机上的材质切换与显存都是白给的开销。
	# 这里钉住「同一形态重复装配不新增材质」。
	var first := MonsterForms.build("red_sentinel")
	var second := MonsterForms.build("red_sentinel")
	var first_material := _first_material(first["root"])
	var second_material := _first_material(second["root"])
	check(first_material != null and first_material == second_material, "同形态的材质必须复用同一份")
	first["root"].free()
	second["root"].free()

func _first_material(root: Node) -> Material:
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.material_override != null:
			return mesh_instance.material_override
	return null
