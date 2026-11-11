extends RefCounted

# FX-09：反馈强度四档总表（纯数据）。
#
# 设计口径来自 docs/特效升级-对标王者荣耀.md §4.5：
#   - 任何新反馈必须先落进四档之一，不许在事件分支里再散写一组数字；
#   - 档位必须单调：重档的顿帧/震屏/粒子量不得小于轻档；
#   - 强度滑杆只缩放「装饰量」，不缩放身份信息（技能主环、飘字、阵营色）。
#
# priority 是池/预算用的优先级：**数字越小越重要**（0 = 终局，1 = 技能主环/击杀，
# 2 = 普通命中，3 = 纯装饰）。take_particle_slot 只允许重要性不高于自己的节点被抢占。

const LIGHT := "light"
const MEDIUM := "medium"
const HEAVY := "heavy"
const FINAL := "final"
const TIERS := [LIGHT, MEDIUM, HEAVY, FINAL]

const TABLE := {
	LIGHT: {
		"rank": 0, "hit_stop": 0.0, "shake": 0.0, "flash": 0.10,
		"decal": false, "priority": 3, "particles": 0.45,
	},
	MEDIUM: {
		"rank": 1, "hit_stop": 0.045, "shake": 0.18, "flash": 0.12,
		"decal": true, "priority": 2, "particles": 1.0,
	},
	HEAVY: {
		"rank": 2, "hit_stop": 0.09, "shake": 0.34, "flash": 0.16,
		"decal": true, "priority": 1, "particles": 1.3,
	},
	FINAL: {
		"rank": 3, "hit_stop": 0.16, "shake": 0.45, "flash": 0.20,
		"decal": true, "priority": 0, "particles": 1.6,
	},
}

# 事件 → 档位。未列出的事件按 medium 处理（宁可多给一点反馈，也不要静默没有）。
const EVENT_TIERS := {
	"ping_mark": LIGHT,
	"monster_attack": LIGHT,
	"attack": MEDIUM,
	"hit": MEDIUM,
	"death": HEAVY,
	"tower_destroyed": HEAVY,
	"guard_destroyed": HEAVY,
	"crystal_shield_broken": HEAVY,
	"objective_kill": HEAVY,
	"match_end": FINAL,
}

static func is_valid(tier: String) -> bool:
	return TABLE.has(tier)

static func feedback(tier: String) -> Dictionary:
	return TABLE.get(tier, TABLE[MEDIUM])

static func tier_of(event_type: String) -> String:
	return str(EVENT_TIERS.get(event_type, MEDIUM))

static func priority_of(tier: String) -> int:
	return int(feedback(tier).get("priority", 2))

static func rank_of(tier: String) -> int:
	return int(feedback(tier).get("rank", 1))

## 强度滑杆对顿帧/震屏的缩放：0 → 50%，1 → 100%（默认不变）。
static func scale_time(value: float, intensity: float) -> float:
	return maxf(0.0, value * lerpf(0.5, 1.0, clampf(intensity, 0.0, 1.0)))

## 强度滑杆对粒子颗数的缩放：0 → 35%，1 → 100%。至少留 1 颗，便于看出「打中了」。
static func scale_particles(amount: int, intensity: float, tier := MEDIUM) -> int:
	var scale := lerpf(0.35, 1.0, clampf(intensity, 0.0, 1.0))
	scale *= float(feedback(tier).get("particles", 1.0))
	return maxi(1, roundi(float(amount) * scale))

## 四档单调性：轻 → 中 → 重 → 终局，顿帧/震屏/粒子量都必须不减。
## 测试直接调它；生产里不需要，但保留成纯函数便于以后调表时先自检。
static func is_monotonic() -> bool:
	var previous_hit := -1.0
	var previous_shake := -1.0
	var previous_particles := -1.0
	for tier in TIERS:
		var row := feedback(tier)
		var hit := float(row.get("hit_stop", 0.0))
		var shake := float(row.get("shake", 0.0))
		var particles := float(row.get("particles", 0.0))
		if hit < previous_hit or shake < previous_shake or particles < previous_particles:
			return false
		previous_hit = hit
		previous_shake = shake
		previous_particles = particles
	return true
