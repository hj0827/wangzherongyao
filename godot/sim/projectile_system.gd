extends RefCounted

# 投射物系统（项 3）：非指向技能在 sim 内成为**实体**，飞行途中才结算命中。
#
# 为什么必须放进 sim 而不是表现层：
#   改造前所有技能在施放的**那个 tick** 就 `_damage` 完毕，arena 只是事后补一段
#   "弹丸飞过去"的特效。结果是玩家无法靠走位规避——落点在按下瞬间就定了，
#   这与 MOBA 的操作上限相冲突（差距文档 §3.2 称之为"最根本的差距"）。
#
# 设计边界（刻意收窄，避免把整套战斗改成弹道）：
#   - 只把"真的飞出去"的远程技能变成投射物；
#   - 位移/自身增益/近战范围（dash、shield、haste、evade、leap_slam、spin、
#     taunt_aura、charge）保持瞬发 —— 它们本来就没有飞行过程，硬做成弹道是错的。
#
# 实体形状（进快照，客机据此画弹道，见 net_protocol 白名单）：
#   {type:"projectile", id, team, owner_id, pos, dir, speed, radius,
#    lifetime, damage, damage_type, slot, kind, target_mode, aoe_radius, slow_sec}

const DEFAULT_SPEED := 26.0
const DEFAULT_RADIUS := 0.45
# 寿命兜底：即使一直没撞到东西也必须消失，否则实体会永久累积。
const MAX_LIFETIME := 2.5

## 该 kind 是否走投射物。与 hero_defs 的 kind 一一对应，集中在此避免各处各写一份。
const PROJECTILE_KINDS := [
	"arrow",          # 射手 Q 贯穿箭
	"burst",          # 法师 Q / 刺客 W 爆发弹
	"aoe_shot",       # 射手 W 范围弹
	"line",           # 法师 W 直线冲击
	"arrow_barrage",  # 射手 R 扇形箭雨
	"meteor_storm",   # 法师 R 陨星
]

static func is_projectile_kind(kind: String) -> bool:
	return PROJECTILE_KINDS.has(kind)

## 建造一个投射物实体。owner 为施法者（只读其字段）。
## aim 是世界坐标落点；dir 由 (aim - pos) 归一化得出。
static func build(owner: Dictionary, slot: String, kind: String, aim: Vector2, damage: float,
		dtype: String, aoe_radius: float, slow_sec: float, speed: float) -> Dictionary:
	var from: Vector2 = owner.get("pos", Vector2.ZERO)
	var delta := aim - from
	var dir := delta.normalized()
	if dir == Vector2.ZERO:
		dir = Vector2(owner.get("facing", Vector2.UP))
	var travel := delta.length()
	var v := speed if speed > 0.0 else DEFAULT_SPEED
	# 寿命按"飞完全程还需多久"给足余量，再夹到上限：
	# 固定 2.5s 会让长距离技能半路消失，而按需计算又可能被极远 aim 拉到无限。
	var needed := travel / maxf(v, 0.001) + 0.4
	return {
		"type": "projectile",
		"id": 0,
		"team": str(owner.get("team", "")),
		"owner_id": owner.get("id", 0),
		"owner_type": str(owner.get("type", "")),
		"pos": from,
		"origin": from,
		"aim": aim,
		"dir": dir,
		"speed": v,
		"radius": DEFAULT_RADIUS,
		"lifetime": minf(needed, MAX_LIFETIME),
		"age": 0.0,
		"damage": damage,
		"damage_type": dtype,
		"slot": slot,
		"kind": kind,
		"aoe_radius": aoe_radius,
		"slow_sec": slow_sec,
		# 单体穿透弹（arrow）与范围弹（aoe_shot/meteor_storm）走不同命中判定。
		"target_mode": "aoe" if aoe_radius > 0.0 else "single",
		"alive": true,
		"hit_ids": [],
	}

## 推进所有投射物。返回本 tick 产生的命中列表，由调用方负责结算伤害。
## 这样"移动"与"结算"分离：伤害仍走 match_sim._damage，属性/减伤逻辑只有一份。
static func tick(entities: Array, dt: float) -> Array:
	var hits: Array = []
	for proj in entities:
		if not (proj is Dictionary) or str(proj.get("type", "")) != "projectile":
			continue
		if not bool(proj.get("alive", true)):
			continue
		var from: Vector2 = proj.get("pos", Vector2.ZERO)
		var to: Vector2 = from + (proj.get("dir", Vector2.RIGHT) as Vector2) * float(proj.get("speed", DEFAULT_SPEED)) * dt
		proj["age"] = float(proj.get("age", 0.0)) + dt
		var hit := _resolve(proj, from, to, entities)
		if not hit.is_empty():
			hits.append(hit)
			# 单体弹命中即销毁；范围弹继续飞（贯穿），但记录已命中目标避免重复结算。
			if str(proj.get("target_mode", "single")) == "single":
				proj["alive"] = false
				continue
		proj["pos"] = to
		if float(proj.get("age", 0.0)) >= float(proj.get("lifetime", MAX_LIFETIME)):
			proj["alive"] = false
	return hits

## 本 tick 的扫掠段 (from → to) 命中判定。
## 用**线段**而不是单点：一步走 26*0.033≈0.86m，若只检测落点，
## 薄目标会被整段跳过（tunneling），表现为"偶尔不掉血"这种最难查的 bug。
##
## 只认**有 hp 的活体**：投射物自身、建筑、以及任何非战斗实体都不能进结果。
## 旧实现按 type 白名单过滤，但漏掉了"目标可能没有 hp"——
## 一旦把无 hp 的字典交给 _damage，就会刷 "Invalid access to property 'hp'"，
## 而测试仍可能全绿（错误只打到 stderr）。
static func _resolve(proj: Dictionary, from: Vector2, to: Vector2, entities: Array) -> Dictionary:
	var team := str(proj.get("team", ""))
	var aoe := float(proj.get("aoe_radius", 0.0))
	var reach := float(proj.get("radius", DEFAULT_RADIUS)) + aoe
	var hit_ids: Array = proj.get("hit_ids", [])
	var found: Array = []
	for entity in entities:
		if not (entity is Dictionary):
			continue
		var etype := str(entity.get("type", ""))
		if etype != "hero" and etype != "minion" and etype != "monster":
			continue
		# 硬性前置：没有 hp 键的东西不是战斗单位，不能当目标。
		if not entity.has("hp"):
			continue
		if not bool(entity.get("alive", true)):
			continue
		if str(entity.get("team", "")) == team:
			continue
		if hit_ids.has(entity.get("id", 0)):
			continue
		var center: Vector2 = entity.get("pos", Vector2.ZERO)
		var body := float(entity.get("radius", 0.5))
		if _segment_distance(center, from, to) <= reach + body:
			found.append(entity)
	if found.is_empty():
		return {}
	return {
		"projectile": proj,
		"targets": found,
	}

static func _segment_distance(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var len_sq := ab.length_squared()
	if len_sq < 0.000001:
		return p.distance_to(a)
	var t := clampf((p - a).dot(ab) / len_sq, 0.0, 1.0)
	return p.distance_to(a + ab * t)
