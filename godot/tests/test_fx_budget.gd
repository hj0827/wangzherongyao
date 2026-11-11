extends "res://tests/test_base.gd"

# FX-08 / FX-09 守卫（验收 10.4 的事件预算 + 特效升级文档 F8/F3）。
# 关键契约：
#   1. 四档表单调，且「越重」的反馈顿帧/震屏/粒子量都不小；
#   2. 强度滑杆只缩装饰量，1.0 时数值必须与旧版完全一致（不许偷偷改手感）；
#   3. 抢占只允许重要性不高于自己的节点 —— 池里全是击杀环时，普通命中宁可丢弃。

const Arena = preload("res://scripts/game/arena.gd")
const FxIntensity = preload("res://scripts/game/fx_intensity.gd")

func test_feedback_tiers_are_monotonic() -> void:
	check(FxIntensity.is_monotonic(), "四档的顿帧/震屏/粒子量单调不减")
	var light := FxIntensity.feedback(FxIntensity.LIGHT)
	var final_tier := FxIntensity.feedback(FxIntensity.FINAL)
	check(float(light.get("hit_stop", -1.0)) < float(final_tier.get("hit_stop", 0.0)), "终局顿帧重于轻档")
	check(int(light.get("priority", 9)) > int(final_tier.get("priority", -1)), "终局优先级数字更小（更重要）")
	check(not bool(light.get("decal", true)), "轻档不留地贴")
	check(bool(final_tier.get("decal", false)), "终局留地贴")

func test_intensity_slider_is_identity_at_full() -> void:
	eq(FxIntensity.scale_time(0.12, 1.0), 0.12, "强度 1.0 时顿帧不变")
	eq(FxIntensity.scale_particles(20, 1.0), 20, "强度 1.0 时粒子颗数不变")
	check(FxIntensity.scale_time(0.12, 0.0) < FxIntensity.scale_time(0.12, 1.0), "调低强度会减弱顿帧")
	check(FxIntensity.scale_particles(20, 0.0) < 20, "调低强度会减少粒子")
	check(FxIntensity.scale_particles(1, 0.0) >= 1, "再低也至少留一颗，保证能看出打中了")
	# 单调：强度越高反馈越强。
	var previous := -1.0
	for step in 6:
		var value := FxIntensity.scale_time(0.2, float(step) / 5.0)
		check(value >= previous, "强度滑杆单调")
		previous = value

func test_pool_steals_only_same_or_lower_priority() -> void:
	var active: Array = []
	for index in 30:
		active.append({"id": index, "priority": 2})
	var critical := {"id": "p0", "priority": 0}
	active.append(critical)
	var slot: Dictionary = Arena.take_particle_slot([], active, 0)
	check(bool(slot.get("stolen", false)), "P0 进来时可以从 P2 手里抢")
	eq((slot.get("node") as Dictionary).get("id"), 0, "优先抢最不重要且最老的一簇")
	check(active.has(critical), "P0 节点本身不会被抢")
	var only_critical: Array = [critical]
	eq(Arena.take_particle_slot([], only_critical, 0), {}, "同级 P0 之间也不抢，宁可丢弃")
	eq(only_critical.size(), 1, "丢弃时不会误删活动节点")
	var peers: Array = [{"id": 0, "priority": 2}, {"id": 1, "priority": 2}]
	eq((Arena.take_particle_slot([], peers, 2).get("node") as Dictionary).get("id"), 0, "同级 P2 抢最老")

func test_pool_prefers_free_slot_before_stealing() -> void:
	var pool: Array = ["free-node"]
	var active: Array = [{"id": 7, "priority": 3}]
	var slot: Dictionary = Arena.take_particle_slot(pool, active, 3)
	eq(slot.get("node"), "free-node", "有空闲节点时直接借")
	check(not bool(slot.get("stolen", true)), "不算抢占")
	eq(active.size(), 1, "活动列表不被改动")

func test_frame_budget_drops_decoration_but_keeps_identity() -> void:
	var arena := Arena.new()
	# 不挂相机 = 距离档不可用，只测预算。
	arena.camera = null
	arena._fx_budget_left = 2
	arena.fx_dropped = 0
	check(arena._fx_allowed(3, Vector3.ZERO), "预算内允许装饰特效")
	check(arena._fx_allowed(2, Vector3.ZERO), "预算内允许普通命中")
	check(not arena._fx_allowed(3, Vector3.ZERO), "预算耗尽时丢弃装饰特效")
	eq(arena.fx_dropped, 1, "丢弃会计数，不是静默")
	check(arena._fx_allowed(1, Vector3.ZERO), "技能主环/击杀不占预算，始终放行")
	check(arena._fx_allowed(0, Vector3.ZERO), "终局反馈始终放行")
	arena.free()
