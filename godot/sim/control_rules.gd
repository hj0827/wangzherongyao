extends RefCounted

const Collision = preload("res://sim/map/collision.gd")

# 控制效果（项 4）：眩晕 / 击飞 / 沉默 / 定身。
#
# 为什么要有这个模块，而不是在各处写 if：
#   1. "谁能做什么"是一张**矩阵**（stun 禁三样、silence 只禁技能、root 只禁移动），
#      散落在移动/施法/普攻/bot 四处判断里，迟早出现"眩晕了还能普攻"这种漏项。
#   2. 免疫判定必须有唯一真身。**改造前 `cc_immune_timer` 只被赋值、从不被读取**：
#      evade 与净化都给它写值，测试还断言它 >0，但没有任何地方拿它挡控制 ——
#      也就是说"免疫"完全是装饰（减速照吃不误）。这是仓库反复警告的
#      "字段在、计时在走、没人收账"形态。本模块把唯一的读取点收在此处。
#
# 行动矩阵（4.1 的目标门限，逐项可测）：
#   kind      禁移动  禁施法  禁普攻  附加
#   stun        ✓       ✓      ✓
#   knockup     ✓       ✓      ✓     强制位移
#   silence     ✗       ✓      ✗
#   root        ✓       ✗      ✗     仍可转向

const STUN := "stun"
const KNOCKUP := "knockup"
const SILENCE := "silence"
const ROOT := "root"

const KINDS := [STUN, KNOCKUP, SILENCE, ROOT]

const TIMER_FIELD := {
	STUN: "stun_timer",
	KNOCKUP: "knockup_timer",
	SILENCE: "silence_timer",
	ROOT: "root_timer",
}

# 击飞的强制位移距离（世界单位，与英雄半径 0.55 同量级）。
const KNOCKUP_DISTANCE := 2.2

static func timer_field(kind: String) -> String:
	return str(TIMER_FIELD.get(kind, ""))

static func is_known(kind: String) -> bool:
	return TIMER_FIELD.has(kind)

## 控制的中文名。展示层用它生成提示，避免各处各写一份中文。
static func display_name(kind: String) -> String:
	match kind:
		STUN:
			return "眩晕"
		KNOCKUP:
			return "击飞"
		SILENCE:
			return "沉默"
		ROOT:
			return "定身"
	return ""

## 某控制的剩余时长。缺失字段按 0 —— 历史数据/客机上没这些键时等于"没被控"。
static func remaining(entity: Dictionary, kind: String) -> float:
	var field := timer_field(kind)
	if field == "":
		return 0.0
	return maxf(0.0, float(entity.get(field, 0.0)))

## 免疫是否生效。**这是全仓唯一读取 `cc_immune_timer` 的地方。**
static func is_immune(entity: Dictionary) -> bool:
	return float(entity.get("cc_immune_timer", 0.0)) > 0.0

## 施加一个控制。返回是否真的生效（被免疫或参数非法时返回 false）。
## 免疫时**不消耗、不写入**任何计时：玩家开了净化就该完全不吃这一下。
static func apply(target: Dictionary, kind: String, duration: float, source_pos := Vector2.ZERO) -> bool:
	if not is_known(kind) or duration <= 0.0:
		return false
	if not bool(target.get("alive", true)):
		return false
	if is_immune(target):
		return false
	var field := timer_field(kind)
	# 取 max 而不是累加：连续命中不该把控制时长叠成无限，
	# 但"更长的那一次"要能覆盖"更短的那一次"。
	target[field] = maxf(float(target.get(field, 0.0)), duration)
	if kind == KNOCKUP:
		_push(target, source_pos)
	return true

## 减速是"软控"：不改行动矩阵（照样能走能打，只是变慢），但**同样吃免疫**。
## 单独一个入口，避免"免疫只管硬控、减速照吃"的半吊子状态 ——
## 玩家开了净化却还被减速粘住，观感上和没开一样。
static func apply_slow(target: Dictionary, duration: float) -> bool:
	if duration <= 0.0 or not bool(target.get("alive", true)):
		return false
	if is_immune(target):
		return false
	target["slow_timer"] = maxf(float(target.get("slow_timer", 0.0)), duration)
	return true

## 击飞的强制位移：把目标沿"施法者 → 目标"方向推开，遇墙仍走 Collision。
static func _push(target: Dictionary, source_pos: Vector2) -> void:
	var from: Vector2 = target.get("pos", Vector2.ZERO)
	var dir := from - source_pos
	if dir.length() < 0.01:
		# 施法者与目标几乎重合：没有明确推离方向，退化为"朝目标背后推"，
		# 而不是留下零向量让 normalize 出 NaN。
		dir = -(target.get("facing", Vector2.UP) as Vector2)
	if dir.length() < 0.01:
		dir = Vector2.UP
	dir = dir.normalized()
	var destination := from + dir * KNOCKUP_DISTANCE
	target["pos"] = Collision.move(from, destination, float(target.get("radius", 0.55)))

static func can_move(entity: Dictionary) -> bool:
	return remaining(entity, STUN) <= 0.0 \
		and remaining(entity, KNOCKUP) <= 0.0 \
		and remaining(entity, ROOT) <= 0.0

static func can_cast(entity: Dictionary) -> bool:
	return remaining(entity, STUN) <= 0.0 \
		and remaining(entity, KNOCKUP) <= 0.0 \
		and remaining(entity, SILENCE) <= 0.0

static func can_attack(entity: Dictionary) -> bool:
	return remaining(entity, STUN) <= 0.0 \
		and remaining(entity, KNOCKUP) <= 0.0

## 递减所有控制计时。由 sim 的每 tick 计时统一调用。
static func tick(entity: Dictionary, dt: float) -> void:
	for kind in KINDS:
		var field := timer_field(kind)
		entity[field] = maxf(0.0, float(entity.get(field, 0.0)) - dt)

## 当前生效的控制种类（可能同时多个）。表现层用它画状态图标。
static func active_kinds(entity: Dictionary) -> Array:
	var out: Array = []
	for kind in KINDS:
		if remaining(entity, kind) > 0.0:
			out.append(kind)
	return out

## 供 UI/快照用的单一状态码：取"最重"的一个。
## 优先级按限制强度排（stun/knockup 最强），避免同时中两个控时图标乱跳。
static func dominant_status(entity: Dictionary) -> String:
	for kind in [STUN, KNOCKUP, SILENCE, ROOT]:
		if remaining(entity, kind) > 0.0:
			return kind
	return ""
