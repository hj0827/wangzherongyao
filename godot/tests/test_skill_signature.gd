extends "res://tests/test_base.gd"

# 技能签名（P1 FX-03 完成版，2026-11-11）。
#
# 起因（差距文档 §8 表格）：「17 个技能 -> 5 类配方」——同一族的技能（星璃 Q 爆裂 与
# 翎羽 W 爆裂疾射）除了颜色之外长得一模一样，玩家读不出「这是谁放的什么」。
# 差距文档给的 P0 口径是：**每个 kind 至少改一处形状/节奏**；任务卡 FX-03 写的是
# 「增加 signature（形状/次级爆炸/延迟/颜色偏移），保证任意两个 kind 的配方不完全相同」。
#
# 这个文件把口径钉成可执行的两件事：
#   ① 每个 kind 都有**人读的签名标签** + **机读的形状/节奏轴**，且 17 个两两不同；
#   ② 这些轴必须真的被渲染层消费（竖直环 / 粒子贴图 / 粒子尺寸 / 延迟二次爆 / 残留贴图 /
#      渐宽光束 / 落点刀光弧），且技能链路里不许再出现战斗期 new/queue_free。

const SkillFx = preload("res://scripts/game/skill_fx.gd")
const FxTextures = preload("res://scripts/game/fx_textures.gd")
const Arena = preload("res://scripts/game/arena.gd")

const KINDS := [
	"slash", "spin", "dash", "leap_slam", "burst", "line", "slow", "meteor_storm",
	"quake", "charge", "shield", "taunt_aura", "arrow", "aoe_shot", "haste",
	"arrow_barrage", "evade",
]

func _arena() -> Node3D:
	var arena: Node3D = Arena.new()
	arena._effects_root = Node3D.new()
	arena.add_child(arena._effects_root)
	arena._init_vfx_pools()
	return arena

func _minimal_request(recipe: Dictionary) -> Dictionary:
	return {
		"hero_id": -1, "slot": "q", "hero_type": "blade", "kind": "slash",
		"from": Vector2.ZERO, "aim": Vector2(4.0, 0.0), "recipe": recipe,
	}

# ---------------------------------------------------------------------------
# 配方层：签名标签 / 形状节奏轴 必须两两不同
# ---------------------------------------------------------------------------

func test_every_kind_has_its_own_signature_tag() -> void:
	var seen := {}
	for kind in KINDS:
		var tag := str(SkillFx.recipe(str(kind)).get("signature", ""))
		check(tag != "", "%s 必须有签名标签（人读的技能记忆点）" % str(kind))
		check(not seen.has(tag), "签名标签重复：%s 与 %s" % [str(kind), str(seen.get(tag, ""))])
		seen[tag] = kind
	eq(seen.size(), KINDS.size(), "17 个 kind 的签名标签必须互不相同")

func test_every_kind_has_its_own_shape_and_rhythm_axes() -> void:
	var seen := {}
	for kind in KINDS:
		var axes := SkillFx.signature_axes(SkillFx.recipe(str(kind)))
		check(axes != "", "%s 的形状/节奏轴不能为空" % str(kind))
		check(
			not seen.has(axes),
			"%s 与 %s 的形状/节奏参数完全相同：%s" % [str(kind), str(seen.get(axes, "")), axes]
		)
		seen[axes] = kind
	eq(seen.size(), KINDS.size(), "17 个 kind 的形状/节奏轴必须互不相同")

func test_every_kind_moves_at_least_one_shape_or_rhythm_axis() -> void:
	# 差距文档 §8 P0 原话：每个 kind 至少改一处形状/节奏。
	for kind in KINDS:
		var recipe: Dictionary = SkillFx.recipe(str(kind))
		var axes := _axis_count(recipe)
		gt(float(axes), 0.0, "%s 必须至少有一处独有的形状/节奏参数（不能只换颜色）" % str(kind))

func test_axes_helper_notices_real_parameter_changes() -> void:
	# 防止 signature_axes 退化成「只回签名标签」的恒真函数：
	# 下面三次改动都只动一个渲染参数，轴串必须跟着变。
	var base := {
		"rings": [],
		"particles": [{
			"at": "aim", "count": 10, "speed": 3.0, "height": 0.5,
			"life": 0.4, "size": 0.12, "texture": "spark", "delay": 0.0,
		}],
	}
	var other_texture := base.duplicate(true)
	other_texture["particles"][0]["texture"] = "shock"
	check(
		SkillFx.signature_axes(base) != SkillFx.signature_axes(other_texture),
		"换粒子贴图必须改变签名轴"
	)
	var delayed := base.duplicate(true)
	delayed["particles"][0]["delay"] = 0.2
	check(
		SkillFx.signature_axes(base) != SkillFx.signature_axes(delayed),
		"加延迟二次爆必须改变签名轴"
	)
	var tilted := {
		"rings": [{"at": "self", "from": 0.4, "to": 2.0, "dur": 0.3, "alpha": 0.5, "tilt": true}],
		"particles": [],
	}
	var flat := {
		"rings": [{"at": "self", "from": 0.4, "to": 2.0, "dur": 0.3, "alpha": 0.5, "tilt": false}],
		"particles": [],
	}
	check(
		SkillFx.signature_axes(tilted) != SkillFx.signature_axes(flat),
		"竖直环必须改变签名轴"
	)

func test_the_recipe_family_actually_uses_several_particle_textures() -> void:
	var used := {}
	for kind in KINDS:
		for burst in SkillFx.recipe(str(kind)).get("particles", []):
			var texture := str(burst.get("texture", ""))
			if texture != "":
				used[texture] = true
	gt(float(used.size()), 3.0, "至少四种粒子贴图，否则「形状差异」只是换色")

func test_every_referenced_texture_exists() -> void:
	# 贴图名写错时 file_texture() 返回 null、粒子静默回落成白方片 —— 不报错。
	# 所以配方里出现的每个名字都必须能取到真资源。
	for kind in KINDS:
		var recipe: Dictionary = SkillFx.recipe(str(kind))
		for burst in recipe.get("particles", []):
			var texture := str(burst.get("texture", ""))
			if texture != "":
				check(
					FxTextures.file_texture(texture) != null,
					"%s 的粒子贴图 '%s' 不存在" % [str(kind), texture]
				)
		var decal := str(recipe.get("decal", ""))
		if decal != "":
			check(
				FxTextures.file_texture(decal) != null,
				"%s 的残留贴图 '%s' 不存在" % [str(kind), decal]
			)
		var arc: Dictionary = recipe.get("arc", {})
		if not arc.is_empty():
			gt(float(arc.get("deg", 0.0)), 90.0, "%s 的落点刀光必须有明显弧度" % str(kind))
			gt(float(arc.get("reach", 0.0)), 0.5, "%s 的落点刀光必须有长度" % str(kind))

# ---------------------------------------------------------------------------
# 渲染层：每个轴都要真的被消费
# ---------------------------------------------------------------------------

func test_delayed_secondary_burst_waits_for_its_delay_then_fires() -> void:
	var arena := _arena()
	var recipe := {
		"rings": [], "particles": [{
			"at": "aim", "count": 6, "speed": 2.0, "height": 0.5,
			"life": 0.3, "size": 0.1, "texture": "shock", "delay": 0.25,
		}],
		"projectile": 0.0, "trail": 0, "beam": 0, "shake": 0.0, "hit_stop": 0.0,
	}
	arena._spawn_skill_fx(_minimal_request(recipe))
	eq(arena._fx_queue.size(), 1, "延迟二次爆必须先入队")
	eq(arena._hit_particles_active.size(), 0, "延迟没到之前不能先炸出来")
	arena._update_fx_queue(0.1)
	eq(arena._hit_particles_active.size(), 0, "只过了 0.1s，还不到 0.25s")
	arena._update_fx_queue(0.2)
	eq(arena._fx_queue.size(), 0, "时间到后必须出队")
	eq(arena._hit_particles_active.size(), 1, "时间到后才真的放出这一簇")
	arena.free()

func test_immediate_burst_does_not_go_through_the_queue() -> void:
	var arena := _arena()
	var recipe := {
		"rings": [], "particles": [{
			"at": "aim", "count": 6, "speed": 2.0, "height": 0.5,
			"life": 0.3, "size": 0.1, "texture": "spark", "delay": 0.0,
		}],
		"projectile": 0.0, "trail": 0, "beam": 0, "shake": 0.0, "hit_stop": 0.0,
	}
	arena._spawn_skill_fx(_minimal_request(recipe))
	eq(arena._fx_queue.size(), 0, "delay = 0 的簇不该进队列（白占一帧）")
	eq(arena._hit_particles_active.size(), 1, "delay = 0 的簇必须立刻出现")
	arena.free()

func test_particle_texture_and_size_reach_the_emitter() -> void:
	var arena := _arena()
	arena._spawn_particles(Vector3.ZERO, Color.WHITE, 6, 2.0, 0.09, 0.3, "shock")
	eq(arena._hit_particles_active.size(), 1, "借出一簇粒子")
	if arena._hit_particles_active.is_empty():
		arena.free()
		return
	var emitter: GPUParticles3D = arena._hit_particles_active[0]
	var quad := emitter.draw_pass_1 as QuadMesh
	check(quad != null, "粒子必须有一个 quad 绘制面")
	if quad == null:
		arena.free()
		return
	var material := quad.material as StandardMaterial3D
	check(material != null, "quad 必须有材质")
	if material != null:
		eq(material.albedo_texture, FxTextures.file_texture("shock"), "粒子贴图必须换到发射器上")
	near(quad.size.x, 0.09, 0.0001, "粒子尺寸参数必须真的作用到 quad（以前是个空参数）")
	# 下一簇不给贴图名时，必须回到兜底 spark，而不是继承上一簇的 shock。
	arena._spawn_particles(Vector3.ZERO, Color.WHITE, 6, 2.0, 0.12, 0.3)
	eq(arena._hit_particles_active.size(), 2, "再借一簇")
	if arena._hit_particles_active.size() == 2:
		var second := arena._hit_particles_active[1].draw_pass_1 as QuadMesh
		var second_mat := second.material as StandardMaterial3D
		eq(second_mat.albedo_texture, FxTextures.spark(), "缺贴图名时必须回到 spark 兜底")
	arena.free()

func test_tilted_ring_is_vertical_and_flat_ring_resets_the_pose() -> void:
	var arena := _arena()
	arena._spawn_ring(Vector3.ZERO, Color.WHITE, 0.4, 2.0, 0.3, 0.5, true)
	eq(arena._ring_active.size(), 1, "借出一枚环")
	if arena._ring_active.is_empty():
		arena.free()
		return
	var ring: MeshInstance3D = arena._ring_active[0]
	near(ring.rotation.x, PI * 0.5, 0.001, "竖直环必须立起来")
	# 环节点是从池里复用的：换回平环时必须复位，否则竖环会污染下一个技能。
	arena._ring_active.clear()
	arena._ring_pool.append(ring)
	arena._spawn_ring(Vector3.ZERO, Color.WHITE, 0.4, 2.0, 0.3, 0.5)
	near(ring.rotation.x, 0.0, 0.001, "平环必须复位，不能继承上一枚的竖直朝向")
	arena.free()

func test_decal_texture_and_scale_follow_the_recipe() -> void:
	var arena := _arena()
	arena._spawn_decal(Vector2.ZERO, Color.WHITE, 1.0, Arena.DECAL_SECONDS, "shock", 1.5)
	eq(arena._decal_active.size(), 1, "生成一枚残留")
	if arena._decal_active.is_empty():
		arena.free()
		return
	var node := arena._decal_active[0].get("node") as MeshInstance3D
	check(node != null, "残留节点存在")
	if node != null:
		var material := node.material_override as StandardMaterial3D
		check(material != null, "残留有材质")
		if material != null:
			eq(material.albedo_texture, FxTextures.file_texture("shock"), "残留贴图必须跟着配方走")
		near(node.scale.x, 3.0, 0.001, "残留尺寸要吃得下 decal_scale")
	arena.free()

func test_skill_projectile_and_beam_go_through_the_pools() -> void:
	var arena := _arena()
	var recipe := {
		"rings": [], "particles": [],
		"projectile": 0.2, "trail": 0, "beam": 1, "beam_taper": true,
		"shake": 0.0, "hit_stop": 0.0,
	}
	arena._spawn_skill_fx(_minimal_request(recipe))
	eq(arena._tracer_active.size(), 1, "技能弹道必须借池里的弹丸（不是 new 一个再 queue_free）")
	gt(float(arena._trail_active.size()), 0.0, "技能弹道也要有拖尾")
	eq(arena._lance_active.size(), 3, "渐宽光束用三段由细到粗的光柱")
	var radii: Array[float] = []
	for lance in arena._lance_active:
		radii.append(lance.transform.basis.get_scale().x)
	check(radii.size() == 3 and radii[0] < radii[1] and radii[1] < radii[2], "三段光柱必须由细到粗")
	arena.free()

# W/R 走 SkillSystem.cast_skill()：sim 会为远程技能 spawn_projectile，
# 于是同一帧里既有 skill_cast（配方）又有 projectile_spawned（真实弹道）。
# 两颗都画就是重影；升级后两颗都带拖尾，重影一眼可见。只准画真实的那一颗。
func test_a_real_projectile_is_not_drawn_twice() -> void:
	var arena := _arena()
	arena._process_events([
		{"type": "skill_cast", "caster_id": 5, "slot": "w", "hero_type": "assassin", "kind": "burst",
			"x": 0.0, "y": 0.0, "aim_x": 4.0, "aim_y": 0.0},
		{"type": "projectile_spawned", "id": 900, "team": "blue", "owner_id": 5, "kind": "burst",
			"slot": "w", "x": 0.0, "y": 0.0, "aim_x": 4.0, "aim_y": 0.0},
	])
	eq(arena._tracer_active.size(), 1, "同一帧里只该有一颗弹道：真实的那颗，不能重影")
	eq(arena._trail_active.size(), 1, "拖尾也只该有一条")
	arena.free()

# 反向守卫：Q/E 是瞬发（match_sim._cast_q/_cast_e 不发弹道事件），
# 配方里的 projectile 就是它们唯一的表现 —— 不能被上面那条规则一起掐掉。
func test_hitscan_q_and_e_still_draw_their_own_projectile() -> void:
	var arena := _arena()
	arena._process_events([
		{"type": "skill", "hero": 5, "slot": "q", "hero_type": "mage", "kind": "burst",
			"x": 0.0, "y": 0.0, "aim_x": 4.0, "aim_y": 0.0},
	])
	eq(arena._tracer_active.size(), 1, "Q 是瞬发，必须靠配方画出那一颗法球")
	arena.free()

func test_unpooled_skill_projectile_helpers_are_gone() -> void:
	var source := FileAccess.get_file_as_string("res://scripts/game/arena.gd")
	# 接线守卫（硬规则 9）：函数写好了不算，必须真的在技能链路上被调用。
	check(has_live_line(source, "_spawn_tracer(from,"), "技能弹道要接到池化的 _spawn_tracer")
	check(has_live_line(source, "_spawn_lance("), "技能光束要接到池化的 _spawn_lance")
	check(has_live_line(source, "_update_fx_queue("), "延迟二次爆必须在 _process 里被推进")
	check(has_live_line(source, 'bool(ring.get("tilt", false))'), "竖直环必须接线")
	check(has_live_line(source, 'str(burst.get("texture", ""))'), "粒子贴图必须接线")
	check(has_live_line(source, 'str(recipe.get("decal", ""))'), "残留贴图必须接线")
	check(has_live_line(source, "FxTextures.file_texture("), "粒子/残留贴图必须走 FxTextures 静态缓存")
	# 硬规则 4：技能链路不得再有战斗期 .new() / queue_free()。
	check(not has_live_line(source, "_spawn_projectile("), "技能弹道不能走战斗期 new/queue_free 的实现")
	check(not has_live_line(source, "_spawn_beam("), "技能光束不能走战斗期 new/queue_free 的实现")

# ---------------------------------------------------------------------------

static func _axis_count(recipe: Dictionary) -> int:
	var axes := 0
	for ring in recipe.get("rings", []):
		if bool(ring.get("tilt", false)):
			axes += 1
	for burst in recipe.get("particles", []):
		if str(burst.get("texture", "")) != "":
			axes += 1
		if float(burst.get("delay", 0.0)) > 0.0:
			axes += 1
	if str(recipe.get("decal", "")) != "":
		axes += 1
	if not (recipe.get("arc", {}) as Dictionary).is_empty():
		axes += 1
	if bool(recipe.get("beam_taper", false)):
		axes += 1
	return axes
