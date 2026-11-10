extends RefCounted
class_name MonsterForms

## 野怪形态派发 + 程序化动画驱动。
##
## 分工：
##   monster_kit.gd          工具箱（材质缓存 / 基本体 / 量体对齐）
##   monster_forms_jungle.gd 野区常规野怪与红蓝 BUFF（石像 / 蜥蜴 / 猪 / 鸟）
##   monster_forms_boss.gd   暴君 / 主宰
##   本文件                   monster_type → 形态、形态 → 脚下环半径、待机/移动/环绕动画
##
## 为什么形态要由 `monster_type` 决定而不是由名字猜：
## `monster_type` 本来就在快照与 `net_protocol._sanitize_entity` 的白名单里，
## 把每个野点的类型写进 `MapLayout.CAMPS` 就能一路流到客机，不需要新增任何字段
## （新增字段要过 6 处链路，少一处就是「主机看得见、客机看不见」的静默失效）。
##
## 动画是**程序化**的（关节旋转 + 呼吸 + 环绕），不走骨骼：
## 形象是基本体拼的，没有骨骼可播；反过来，这也让「换形象」与「加动画」互不影响。

const Kit = preload("res://scripts/game/monster_kit.gd")
const JungleForms = preload("res://scripts/game/monster_forms_jungle.gd")
const BossForms = preload("res://scripts/game/monster_forms_boss.gd")

## 能够程序化拼出来的形态。不在表里的（wolf / spirit）走 UnitVisual 自己的分支：
## wolf 用现成狼模型（它本来就是狼），spirit 是河道之灵的水球。
const PROCEDURAL_FORMS := ["blue_sentinel", "red_sentinel", "lizard", "boar", "bird", "tyrant", "overlord"]

## 野点 id → 形态。
##
## 为什么按 `camp_id` 而不是给 `MapLayout.CAMPS` 加字段：**换模型不改任何玩法数值**，
## 它是纯表现层的事。`camp_id` 本来就在快照与 `net_protocol._sanitize_entity` 的白名单里
## （客机拿得到同一个 id），所以形象双端一致，且不必动 sim / 联机白名单。
## 代价是多了一张表 —— 由 `test_monster_forms` 守卫：`MapLayout.CAMPS` 里**每一个** id
## 都必须在这张表里，新增野点忘了登记就直接红。
const CAMP_FORMS := {
	"blue_buff_blue_side": "blue_sentinel",
	"blue_buff_red_side": "blue_sentinel",
	"red_buff_blue_side": "red_sentinel",
	"red_buff_red_side": "red_sentinel",
	"blue_wolf_blue_side": "wolf",
	"blue_wolf_red_side": "wolf",
	"blue_lizard_blue_side": "lizard",
	"blue_lizard_red_side": "lizard",
	"red_pig_blue_side": "boar",
	"red_pig_red_side": "boar",
	"red_bird_blue_side": "bird",
	"red_bird_red_side": "bird",
}

## 形态对应的脚下环半径（米）。环是玩家判断「这只怪的实际体积」的第一依据，
## 所以它必须按形态给：石像宽、蜥蜴扁、首领占满坑。
const RING_RADII := {
	"blue_sentinel": 0.95,
	"red_sentinel": 1.02,
	"lizard": 0.68,
	"boar": 0.66,
	"bird": 0.6,
	"wolf": 0.6,
	"tyrant": 2.4,
	"overlord": 2.6,
}

## monster_type / camp_id / 首领标记 → 形态键。
##
## 判定顺序有讲究：首领与河道之灵先判（它们不看 camp_id），然后是 `monster_type` 里
## **已经登记的形态**，最后才查 camp_id 表 —— 于是「数据层直接写形态名」与
## 「只在表现层登记 camp_id」两条路都能用，不会互相打架。
##
## 未知类型回落到 wolf：宁可显示一只普通的狼，也不要出现空模型
## （空模型在游戏里就是「看不见但能被打」的隐形野怪）。
static func form_key(monster_type: String, objective: bool, objective_id: String, camp_id := "") -> String:
	if objective:
		return "overlord" if objective_id == "overlord" else "tyrant"
	if monster_type == "spirit":
		return "spirit"
	if PROCEDURAL_FORMS.has(monster_type):
		return monster_type
	var camp_form := str(CAMP_FORMS.get(camp_id, ""))
	if camp_form != "":
		return camp_form
	return "wolf"

static func is_procedural(form: String) -> bool:
	return PROCEDURAL_FORMS.has(form)

static func ring_radius(form: String) -> float:
	return float(RING_RADII.get(form, 0.6))

## 拼出形态。wolf / spirit 返回空字典（由 UnitVisual 自己装配）。
##
## height 只对首领有意义：暴君 / 主宰的身高是 UnitVisual 的常量（血条、脚下环、
## 首领牌都按它算），从外面传进来就不会出现「形象 3.8、血条按 4.2 摆」的漂移。
static func build(form: String, height := 0.0) -> Dictionary:
	match form:
		"blue_sentinel":
			return JungleForms.blue_sentinel()
		"red_sentinel":
			return JungleForms.red_sentinel()
		"lizard":
			return JungleForms.lizard()
		"boar":
			return JungleForms.boar()
		"bird":
			return JungleForms.bird()
		"tyrant":
			return BossForms.tyrant(height if height > 0.0 else BossForms.TYRANT_HEIGHT)
		"overlord":
			return BossForms.overlord(height if height > 0.0 else BossForms.OVERLORD_HEIGHT)
	return {}

## 每帧的程序化动画。普通的野怪只有「站」和「走」两态，所以这里不做状态机：
## 移动时步频加快、幅度加大，静止时缩回呼吸 —— 一眼能读出「它有没有在动」。
static func animate(spec: Dictionary, delta: float, moving: bool, speed: float) -> void:
	var body: Node3D = spec.get("body", null)
	if body == null:
		return
	var t := float(spec.get("t", 0.0)) + delta
	spec["t"] = t
	var stride := clampf(maxf(speed, 0.0) / 3.2, 0.55, 2.0)
	var gait := (6.6 if moving else 1.7) * stride
	# 静止也要有呼吸：完全不动的野怪会被读成场景装饰，玩家不会觉得它「活着」。
	body.position.y = sin(t * gait) * (0.08 if moving else 0.028)
	var roll := sin(t * gait) * (0.04 if moving else 0.0)
	body.rotation.z = lerp(body.rotation.z, roll, clampf(delta * 7.0, 0.0, 1.0))

	var legs: Array = spec.get("legs", [])
	var swing := 0.5 if moving else 0.0
	for i in legs.size():
		var leg: Node3D = legs[i]
		if leg == null:
			continue
		var phase := t * gait + PI * float(i % 2) + (PI * 0.5 if i >= 2 else 0.0)
		leg.rotation.x = lerp(leg.rotation.x, sin(phase) * swing, clampf(delta * 9.0, 0.0, 1.0))

	var wings: Array = spec.get("wings", [])
	for i in wings.size():
		var wing: Node3D = wings[i]
		if wing == null:
			continue
		var direction := 1.0 if i % 2 == 0 else -1.0
		var flap := 0.46 if moving else 0.16
		wing.rotation.z = direction * sin(t * (7.6 if moving else 2.1)) * flap

	var tail: Node3D = spec.get("tail", null)
	if tail != null:
		tail.rotation.y = sin(t * (3.4 if moving else 1.5)) * 0.3

	# 肩甲 / 火星 / 光点绕体缓转：静止的石像与首领需要一点「悬停」的动感。
	var orbits: Array = spec.get("orbits", [])
	for orbit in orbits:
		if orbit is Node3D:
			(orbit as Node3D).rotation.y += delta * 0.5
	var motes: Node3D = spec.get("motes", null)
	if motes != null:
		motes.rotation.y += delta * 0.32
		motes.position.y = sin(t * 1.3) * 0.12

	# 核心呼吸：晶体与熔核靠**自身缩放**而不是改材质发光强度 ——
	# 材质是全局共享的，改发光会让全场的同类野怪一起闪（谁最后写谁赢）。
	var pulses: Array = spec.get("pulses", [])
	var pulse := 1.0 + sin(t * 2.6) * 0.07
	for node in pulses:
		if node is Node3D:
			(node as Node3D).scale = Vector3.ONE * pulse
