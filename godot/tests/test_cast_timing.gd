extends "res://tests/test_base.gd"

# 技能前摇 / 后摇计时（项 3.3）
#
# 实体字典里已有 cast_slot / cast_left / cast_aim / cast_recover 四个字段，
# match_sim.tick() 里也有 _tick_casts(dt) 调用，但实现曾整段缺失——
# 调用了一个不存在的函数，导致 match_sim 解析失败、arena/main 连锁编译失败、
# 开窗即黑屏（503 个 SCRIPT ERROR，全部源自这一处）。
#
# 这组用例钉住三件事：
# 1. tick 能跑（不再有悬空调用）；
# 2. 三个计时器按 dt 递减，且夹在 0 不为负；
# 3. 前摇没走完之前，后摇不会开始（两段计时是串联，不是并联）。

const MatchSim = preload("res://sim/match_sim.gd")
const Arena = preload("res://scripts/game/arena.gd")
const MainApp = preload("res://scripts/app/main.gd")

func _entity(overrides := {}) -> Dictionary:
	var e := {
		"cast_slot": "",
		"cast_left": 0.0,
		"cast_aim": Vector2.ZERO,
		"cast_recover": 0.0,
	}
	e.merge(overrides, true)
	return e

func test_match_sim_compiles_and_ticks() -> void:
	# 回归：这行曾经因为 _tick_casts 未定义而让整个 sim 编译失败。
	var sim = MatchSim.new({"mode": "duel", "humans": [], "bot_fill": false})
	check(sim != null, "MatchSim must instantiate (a dangling helper call breaks the whole compile)")
	# 起手中的实体过一 tick，前摇必须真的在走。
	var e := _entity({"cast_slot": "q", "cast_left": 0.6})
	sim._tick_casts_for(0.1, [e])
	near(float(e.cast_left), 0.5, 0.0001, "cast_left must count down by dt")
	eq(e.cast_slot, "q", "cast must still be in flight while cast_left > 0")

func test_main_entry_scripts_are_loadable() -> void:
	# 黑屏的最外层守卫：main.gd 是 scene 挂的入口，它解析失败 = 窗口开出来是纯黑。
	# 一次悬空的函数调用曾是 503 条 SCRIPT ERROR 的唯一源头，但当时没有任何用例
	# 断言"入口脚本能加载"——真正的 sim 必须能 new 出来，否则这行就红。
	check(Arena != null, "arena.gd must compile")
	check(MainApp != null, "main.gd must compile (a black window means it did not)")
	var sim = MatchSim.new({"mode": "duel", "humans": [], "bot_fill": false})
	check(sim.state != null, "duel sim must build a state to play a match")

func test_cast_left_floors_at_zero() -> void:
	var e := _entity({"cast_slot": "q", "cast_left": 0.05})
	MatchSim.new({"mode": "duel", "humans": [], "bot_fill": false})._tick_casts_for(0.1, [e])
	near(float(e.cast_left), 0.0, 0.0001, "cast_left must clamp to 0, never go negative")
	eq(e.cast_slot, "", "cast_slot must clear once the wind-up finishes")

func test_recovery_only_starts_after_windup() -> void:
	# 串联语义：前摇还在走的时候后摇不该被动减。
	var e := _entity({"cast_slot": "q", "cast_left": 0.5, "cast_recover": 0.3})
	MatchSim.new({"mode": "duel", "humans": [], "bot_fill": false})._tick_casts_for(0.1, [e])
	near(float(e.cast_recover), 0.3, 0.0001, "recovery must not drain during wind-up")

	# 前摇结束后，后摇才逐帧递减。
	var done := _entity({"cast_slot": "", "cast_left": 0.0, "cast_recover": 0.3})
	MatchSim.new({"mode": "duel", "humans": [], "bot_fill": false})._tick_casts_for(0.1, [done])
	near(float(done.cast_recover), 0.2, 0.0001, "recovery must drain once wind-up is over")

func test_recovery_floors_at_zero() -> void:
	var e := _entity({"cast_recover": 0.04})
	MatchSim.new({"mode": "duel", "humans": [], "bot_fill": false})._tick_casts_for(0.1, [e])
	near(float(e.cast_recover), 0.0, 0.0001, "cast_recover must clamp to 0")

func test_idle_entities_are_untouched() -> void:
	var e := _entity()
	var before := e.duplicate(true)
	MatchSim.new({"mode": "duel", "humans": [], "bot_fill": false})._tick_casts_for(0.1, [e])
	eq(e, before, "an entity with no cast in flight must not be mutated")
