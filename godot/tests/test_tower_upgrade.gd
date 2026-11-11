extends "res://tests/test_base.gd"

# 防御塔升级（2026-11-11）：分级外观 / 开火反馈 / 低血残破 / 摧毁演出。
#
# 起因（视觉升级开发文档 STRUCT-03 + 差距文档 §5.3）：
# 外塔 / 内塔 / 高地塔 / 双子塔目前**只靠缩放 1.00 / 1.07 / 1.16 / 0.92 区分**，
# 再叠一条逐级加宽的束带；21m 机位下四座塔的剪影几乎一样。
# 塔开火时也只有一道光束，塔本身没有反应；掉血到残血看不出"这座塔快没了"；
# 被推掉是"爆炸 → 直接换成残骸"，少一个"倒下去"的节拍。
#
# 四条升级全部落在**表现层**：不改数值、不改协议、不加战斗中分配。
# 契约分两层：
#   ① 纯函数层（tier_style / damage_tone / fire_envelope）—— headless 直接断言；
#   ② 接线层（record 上的 cracks / 材质引用 / fire_timer / collapse_timer）—— 断言真的被消费。

const Arena = preload("res://scripts/game/arena.gd")
const TowerVisual = preload("res://scripts/game/tower_visual.gd")
const ModelUtils = preload("res://scripts/game/model_utils.gd")

const TOWER_ID := 41

func _arena_with(entity: Dictionary) -> Node3D:
	var arena: Node3D = Arena.new()
	arena._structures_root = Node3D.new()
	arena.add_child(arena._structures_root)
	arena._sync_structures({"entities": [entity]}, true)
	return arena

func _tower(extra: Dictionary = {}) -> Dictionary:
	var entity := {
		"id": TOWER_ID, "type": "tower", "team": "red", "tier": "outer",
		"x": 12.0, "y": 8.0, "hp": 3200.0, "max_hp": 3200.0,
		"alive": true, "vulnerable": true, "range": 8.0, "radius": 1.4,
	}
	entity.merge(extra, true)
	return entity

func _record(arena: Node3D) -> Dictionary:
	return arena._structure_views.get(TOWER_ID, {})

# ---------------------------------------------------------------------------
# ① 纯函数层：分级样式 / 残血强度 / 开火包络
# ---------------------------------------------------------------------------

func test_tier_styles_escalate_with_tower_tier() -> void:
	var outer := TowerVisual.tier_style("outer")
	var inner := TowerVisual.tier_style("inner")
	var high := TowerVisual.tier_style("high")
	var twin := TowerVisual.tier_style("twin")
	# 塔冠石肋数：越往高地越密（剪影读出"这座更高级"）。
	lt(float(outer.get("ribs", 0)), float(inner.get("ribs", 0)), "内塔塔冠肋数要多于外塔")
	lt(float(inner.get("ribs", 0)), float(high.get("ribs", 0)), "高地塔塔冠肋数要多于内塔")
	lt(float(twin.get("ribs", 0)), float(outer.get("ribs", 0)), "双子塔是矮塔，肋数要少于外塔")
	# 肋顶宝珠与石箍圈数同步升级。
	lt(float(outer.get("finials", 0)), float(high.get("finials", 0)), "高地塔肋顶要有宝珠")
	lt(float((outer.get("bands", []) as Array).size()), float((high.get("bands", []) as Array).size()), "高地塔石箍更多")
	check(bool(high.get("crown_ring", false)), "高地塔塔冠要有一圈金箍")

func test_tier_style_falls_back_to_outer_for_unknown_tier() -> void:
	var unknown := TowerVisual.tier_style("nonsense")
	var outer := TowerVisual.tier_style("outer")
	eq(int(unknown.get("ribs", -1)), int(outer.get("ribs", -2)), "未知层级要回落成外塔，不能造出畸形塔")

func test_every_tier_builds_a_slim_tall_tower() -> void:
	# 视觉升级不能把「细高不挡英雄」的契约撑破（差距文档 §5.3 / test_tower_look）。
	for tier in ["outer", "inner", "high", "twin"]:
		var built := TowerVisual.build(Color(1.0, 0.32, 0.26), tier)
		var model: Node3D = built.get("node")
		check(model != null, "%s 塔要能建出来" % tier)
		if model == null:
			continue
		var box := ModelUtils.relative_aabb(model)
		var girth := maxf(box.size.x, box.size.z)
		gt(box.size.y, 8.2, "%s 塔要够高（%.2f m）" % [tier, box.size.y])
		lt(girth, 3.0, "%s 塔身不能变胖（%.2f m）" % [tier, girth])
		gt(box.size.y / maxf(girth, 0.001), 2.8, "%s 塔要细而尖（宽高比 %.2f）" % [tier, box.size.y / maxf(girth, 0.001)])
		eq(str(built.get("tier", "")), tier, "build() 必须回带 tier，渲染层才不会再自己猜一遍")
		model.free()

func test_damage_tone_only_kicks_in_below_the_threshold() -> void:
	# 断言用的是**写死的比例**，不是从 DAMAGE_THRESHOLD 反推 ——
	# 否则阈值常量被改掉时测试会跟着一起动，等于什么都没测（变异验证会漏）。
	eq(TowerVisual.damage_tone(1.0), 0.0, "满血不许有任何残破表现")
	eq(TowerVisual.damage_tone(0.6), 0.0, "六成血还不该露相（阈值要落在半血附近）")
	eq(TowerVisual.damage_tone(0.55), 0.0, "阈值上不许有残破表现")
	gt(TowerVisual.damage_tone(0.5), 0.0, "半血以下要有残破表现")
	gt(TowerVisual.damage_tone(0.25), 0.0, "四分之一血要有明显残破")
	near(TowerVisual.damage_tone(0.0), 1.0, 0.001, "血见底时残破要拉满")
	# 单调：血越少，残破越重。
	var previous := -1.0
	for step in 11:
		var ratio := 1.0 - float(step) / 10.0
		var tone := TowerVisual.damage_tone(ratio)
		check(tone >= previous, "残破强度必须随血量单调不减（%.1f -> %.2f）" % [ratio, tone])
		previous = tone

func test_fire_envelope_starts_hot_and_decays() -> void:
	near(TowerVisual.fire_envelope(0.0), 1.0, 0.001, "开火瞬间最亮")
	near(TowerVisual.fire_envelope(1.0), 0.0, 0.001, "包络结束必须归零，否则塔会一直亮着")
	var previous := 2.0
	for step in 11:
		var elapsed := float(step) / 10.0
		var value := TowerVisual.fire_envelope(elapsed)
		check(value <= previous, "开火包络必须单调衰减")
		previous = value

# ---------------------------------------------------------------------------
# ② 分级外观落到塔上
# ---------------------------------------------------------------------------

func test_each_tier_gets_its_own_crown_on_the_real_tower() -> void:
	var ribs := {}
	for tier in ["outer", "inner", "high"]:
		var arena := _arena_with(_tower({"tier": tier}))
		var record := _record(arena)
		check(not record.is_empty(), "%s 塔视图要建出来" % tier)
		ribs[tier] = int(record.get("crown_ribs", -1))
		check(ribs[tier] == int(TowerVisual.tier_style(tier).get("ribs", -2)), "%s 塔冠肋数要来自 tier_style" % tier)
		arena.free()
	lt(float(ribs.get("outer", 0)), float(ribs.get("inner", 0)), "塔上真的长出更多肋（不只是表里改了数）")

# ---------------------------------------------------------------------------
# ③ 开火反馈
# ---------------------------------------------------------------------------

func test_firing_brightens_the_core_then_settles_back() -> void:
	var arena := _arena_with(_tower())
	var record := _record(arena)
	check(not record.is_empty(), "塔视图已创建")
	if record.is_empty():
		arena.free()
		return
	var core_mat := record.get("core_mat") as StandardMaterial3D
	check(core_mat != null, "塔冠核心材质要能被开火反馈驱动")
	if core_mat == null:
		arena.free()
		return
	var base_energy := float(core_mat.emission_energy_multiplier)
	# 塔开火：事件里的 source 就是这座塔的 id。
	arena._handle_structure_attack({
		"type": "structure_attack", "source": TOWER_ID, "source_type": "tower",
		"tier": "outer", "team": "red", "x": 12.0, "y": 8.0,
		"target_x": 6.0, "target_y": 8.0,
	})
	arena._sync_structures({"entities": [_tower()]}, false, 0.016)
	gt(float(core_mat.emission_energy_multiplier), base_energy, "开火瞬间核心必须更亮")
	# 时间推进到包络结束，核心要回到基准亮度（不能永久变亮）。
	for i in 30:
		arena._sync_structures({"entities": [_tower()]}, false, 0.02)
	near(float(core_mat.emission_energy_multiplier), base_energy, 0.01, "开火结束后核心必须回到基准亮度")
	arena.free()

func test_firing_kicks_the_tower_back_and_resets() -> void:
	var arena := _arena_with(_tower())
	var record := _record(arena)
	var model: Node3D = record.get("model")
	check(model != null, "塔模型存在")
	if model == null:
		arena.free()
		return
	arena._handle_structure_attack({
		"type": "structure_attack", "source": TOWER_ID, "source_type": "tower",
		"tier": "outer", "team": "red", "x": 12.0, "y": 8.0,
		"target_x": 6.0, "target_y": 8.0,
	})
	arena._sync_structures({"entities": [_tower()]}, false, 0.016)
	lt(model.rotation.x, 0.0, "开火时塔身要有一点后仰")
	for i in 40:
		arena._sync_structures({"entities": [_tower()]}, false, 0.02)
	near(model.rotation.x, 0.0, 0.0001, "后仰必须复位，否则塔会一直歪着")
	arena.free()

# ---------------------------------------------------------------------------
# ④ 低血残破
# ---------------------------------------------------------------------------

func test_damaged_tower_dims_and_shows_cracks() -> void:
	var arena := _arena_with(_tower())
	var record := _record(arena)
	var cracks: MeshInstance3D = record.get("cracks")
	check(cracks != null, "塔要预建裂纹节点（不满足条件时隐藏）")
	var stone := record.get("stone_render_mat") as StandardMaterial3D
	check(stone != null, "要抓得住渲染时真正生效的石料材质（tint 之后的那份）")
	if cracks == null or stone == null:
		arena.free()
		return
	check(not cracks.visible, "满血时裂纹必须隐藏")
	var full_albedo := stone.albedo_color
	# 掉到 15% 血。
	arena._sync_structures({"entities": [_tower({"hp": 480.0})]}, false, 0.016)
	check(cracks.visible, "残血时裂纹要显示出来")
	var dimmed := stone.albedo_color
	check(dimmed.v < full_albedo.v, "残血石料要变暗（%.2f -> %.2f）" % [full_albedo.v, dimmed.v])
	var core_mat := record.get("core_mat") as StandardMaterial3D
	if core_mat != null:
		lt(float(core_mat.emission_energy_multiplier), 4.2, "残血核心要变弱，读得出「快没了」")
	# 回满血要复原（复活/调试不会留下永久黑塔）。
	arena._sync_structures({"entities": [_tower()]}, false, 0.016)
	check(not cracks.visible, "回满血后裂纹要收起来")
	near(stone.albedo_color.v, full_albedo.v, 0.001, "石料亮度要复原")
	arena.free()

# ---------------------------------------------------------------------------
# ⑤ 摧毁演出
# ---------------------------------------------------------------------------

func test_tower_collapses_before_the_rubble_appears() -> void:
	var arena := _arena_with(_tower())
	var record := _record(arena)
	var model: Node3D = record.get("model")
	var rubble: Node3D = record.get("rubble")
	check(model != null and rubble != null, "塔身与残骸都要有")
	if model == null or rubble == null:
		arena.free()
		return
	# 塔被推掉：事件先到（tower_destroyed 不带 id，只能按坐标+阵营匹配）。
	arena._process_events([{
		"type": "tower_destroyed", "team": "red", "tier": "outer",
		"x": 12.0, "y": 8.0,
	}])
	gt(float(record.get("collapse_timer", 0.0)), 0.0, "摧毁事件必须启动倒塌演出")
	var dead := _tower({"alive": false, "hp": 0.0})
	arena._sync_structures({"entities": [dead]}, false, 0.05)
	check(model.visible, "倒塌过程中塔身不能立刻消失（否则还是「啪一下换成残骸」）")
	check(not rubble.visible, "倒塌过程中残骸还不能出现")
	# 推完整个演出。
	for i in 40:
		arena._sync_structures({"entities": [dead]}, false, 0.05)
	check(not model.visible, "演出结束后塔身隐藏")
	check(rubble.visible, "演出结束后残骸出现")
	arena.free()

func test_collapse_tilts_the_tower_over() -> void:
	var arena := _arena_with(_tower())
	var record := _record(arena)
	var model: Node3D = record.get("model")
	if model == null:
		arena.free()
		return
	arena._process_events([{
		"type": "tower_destroyed", "team": "red", "tier": "outer", "x": 12.0, "y": 8.0,
	}])
	arena._sync_structures({"entities": [_tower({"alive": false, "hp": 0.0})]}, false, 0.25)
	check(absf(model.rotation.z) > 0.02, "倒塌时塔身要真的倾斜（当前 %.3f）" % model.rotation.z)
	lt(model.position.y, 0.0, "倒塌时塔身要往下沉")
	arena.free()

func test_no_collapse_when_snapshot_reports_death_without_event() -> void:
	# 客机可能先收到快照再收到事件：没有事件时必须走旧的即时路径，
	# 不能让塔永远卡在"倒到一半"的状态里。
	var arena := _arena_with(_tower())
	var record := _record(arena)
	var model: Node3D = record.get("model")
	var rubble: Node3D = record.get("rubble")
	if model == null or rubble == null:
		arena.free()
		return
	arena._sync_structures({"entities": [_tower({"alive": false, "hp": 0.0})]}, false, 0.05)
	check(not model.visible, "没有倒塌事件时沿用旧行为：塔身直接隐藏")
	check(rubble.visible, "没有倒塌事件时残骸直接显示")
	arena.free()

# ---------------------------------------------------------------------------
# ⑥ 接线守卫（硬规则 9：函数写好了不算，必须真的在生产路径上被调用）
# ---------------------------------------------------------------------------

func test_tower_upgrade_is_wired_into_production_code() -> void:
	var arena_source := FileAccess.get_file_as_string("res://scripts/game/arena.gd")
	check(has_live_line(arena_source, "_pulse_tower_fire("), "开火反馈必须接到事件分支")
	check(has_live_line(arena_source, "_start_tower_collapse("), "摧毁演出必须接到事件分支")
	check(has_live_line(arena_source, "TowerVisual.damage_tone("), "低血残破必须在每帧状态里被消费")
	check(has_live_line(arena_source, "TowerVisual.fire_envelope("), "开火包络必须被消费")
	check(has_live_line(arena_source, "TowerVisual.build(team_color, "), "建塔时必须把 tier 传给 TowerVisual")
	var tower_source := FileAccess.get_file_as_string("res://scripts/game/tower_visual.gd")
	check(has_live_line(tower_source, "tier_style("), "塔冠造型必须由 tier_style 驱动")
	# 硬规则 4：升级不得在战斗中新建节点。
	check(not has_live_line(arena_source, "_spawn_tower_"), "塔的瞬时反馈不许新开一套战斗期节点池")
