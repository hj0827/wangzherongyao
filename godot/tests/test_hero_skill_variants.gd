extends "res://tests/test_base.gd"

## 英雄级技能变体的契约测试（HERO-06）。
##
## 为什么需要这一层：`SkillFx.recipe(kind)` 只按 kind 分派，而 17 个 kind 里有
## **3 个是两个英雄共用的**：
##   - `burst`     → 星璃 Q（星陨·法术）与 墨鸦 W（毒牙·近身毒爆）
##   - `charge`    → 铁壁 W（野蛮冲撞·重装冲撞）与 墨鸦 Q（影袭·瞬身突刺）
##   - `leap_slam` → 苍刃 R（裂地崩山·巨剑砸地）与 墨鸦 R（绝影处决·突进处决）
## 这三对以前形状完全一样，只靠颜色区分 —— 团战里「是谁放的」和「这是哪个技能」
## 两个问题会互相顶掉。
##
## 这里守四件事：
##   1. 每一对共用 kind 的两个英雄，形状轴**必须不同**；
##   2. 变体不能改结构字段（projectile/trail/beam/shake/hit_stop 由 sim 决定）；
##   3. 没登记的英雄走通用配方，行为一字不变（不能误伤）；
##   4. 变体的签名标签与粒子贴图都要真实存在。

const SkillFx = preload("res://scripts/game/skill_fx.gd")
const HeroDefs = preload("res://sim/hero_defs.gd")

const HEROES := ["blade", "mage", "tank", "archer", "assassin"]
const SLOTS := ["q", "w", "e", "r"]

## 真实存在于 hero_defs 里的 kind（不是凭空列的清单）。
func _all_kinds() -> Array[String]:
	var out: Array[String] = []
	for hero_type in HEROES:
		var def: Dictionary = HeroDefs.get_hero(hero_type)
		for slot in SLOTS:
			var kind := str((def.get(slot, {}) as Dictionary).get("kind", ""))
			if kind != "" and not out.has(kind):
				out.append(kind)
	return out

## 找出「同一个 kind 被多个英雄使用」的那些 (kind, [hero...])。
func _shared_kinds() -> Dictionary:
	var owners := {}
	for hero_type in HEROES:
		var def: Dictionary = HeroDefs.get_hero(hero_type)
		for slot in SLOTS:
			var kind := str((def.get(slot, {}) as Dictionary).get("kind", ""))
			if kind == "":
				continue
			var list: Array = owners.get(kind, [])
			if not list.has(hero_type):
				list.append(hero_type)
			owners[kind] = list
	var shared := {}
	for kind in owners:
		if (owners[kind] as Array).size() > 1:
			shared[kind] = owners[kind]
	return shared

# ---------------------------------------------------------------------------
# 核心：共用 kind 的每一对英雄必须长得不一样
# ---------------------------------------------------------------------------

## 这条是整个 HERO-06 的目的所在。
##
## 只断言「轴串不同」是不够的 —— 轴串会不同也可能只是粒子数从 20 变成 22，
## 玩家根本看不出。所以这里额外要求两边**至少有一个变体真的登记过**
## （`has_variant`），否则那对英雄就是「什么都没做」。
func test_shared_kinds_are_split_per_hero() -> void:
	var shared := _shared_kinds()
	gt(float(shared.size()), 0.0, "必须有共用 kind 才会需要这一层（当前没有：这份测试应被删除）")
	for kind in shared:
		var heroes: Array = shared[kind]
		var axes_seen := {}
		var variants := 0
		for hero_type in heroes:
			var recipe := SkillFx.recipe_for(str(hero_type), str(kind))
			var axes := SkillFx.signature_axes(recipe)
			check(not axes_seen.has(axes),
				"%s 的两个英雄（%s / %s）形状轴完全相同：%s —— 只靠颜色区分，团战读不出" % [
					str(kind), str(hero_type), str(axes_seen.get(axes, "")), axes])
			axes_seen[axes] = hero_type
			if SkillFx.has_variant(str(hero_type), str(kind)):
				variants += 1
		eq(axes_seen.size(), heroes.size(),
			"%s 的 %d 个英雄必须各自不同的形状轴" % [str(kind), heroes.size()])
		check(variants > 0,
			"%s 的共用英雄里一个变体都没登记：说明这一对根本没被拆开" % str(kind))

## 变体必须有自己的签名标签，不能继续叫通用配方的名字。
func test_variants_have_their_own_signature() -> void:
	var base_tags := {}
	for kind in _all_kinds():
		base_tags[str(SkillFx.recipe(str(kind)).get("signature", ""))] = kind
	for hero_type in HEROES:
		var def: Dictionary = HeroDefs.get_hero(hero_type)
		for slot in SLOTS:
			var kind := str((def.get(slot, {}) as Dictionary).get("kind", ""))
			if kind == "" or not SkillFx.has_variant(hero_type, kind):
				continue
			var recipe := SkillFx.recipe_for(hero_type, kind)
			var tag := str(recipe.get("signature", ""))
			check(tag != "", "%s 的 %s 变体必须有签名标签" % [hero_type, kind])
			check(tag != str(SkillFx.recipe(kind).get("signature", "")),
				"%s 的 %s 变体不能沿用通用签名「%s」" % [hero_type, kind, tag])
			check(not base_tags.has(tag) or str(base_tags[tag]) == kind,
				"%s 的 %s 变体签名「%s」与别的 kind 撞车" % [hero_type, kind, tag])

# ---------------------------------------------------------------------------
# 变体不许碰结构字段
# ---------------------------------------------------------------------------

## `projectile` / `trail` / `beam` / `shake` / `hit_stop` 决定「sim 里有没有真实
## 弹道、要不要震屏」——它们是行为，不是外观。变体层只允许改外观。
##
## 唯一的例外是 `trail`：它是**残影圈数**，纯表现（sim 不读）。
## 但为了不让人误会，这里把它一起列进白名单并注明；其余一律不许改。
const STRUCTURAL_KEYS := ["projectile", "beam", "shake", "hit_stop"]
# `accent` 不是渲染配方键，而是 `SkillFx.accent_for()` 读的调色覆盖；
# `recipe_for()` 会把它一起透传，所以出现在配方字典里但**没有静默失效**。
const ALLOWED_EXTRA := ["signature", "rings", "particles", "decal", "decal_scale", "arc", "trail",
	"beam_taper", "accent"]

## 同一对共用 kind 的英雄，最终**渲染色**必须真的分得开。
##
## 这条守的是一个具体实测：星璃立绘 `9e85ff` 与墨鸦 `cc6beb` 都是紫系
## （色相差 0.03），而 `burst` 的强调色也是紫 —— 三个人撞在一起，
## 同一个 burst 技能在团战里**分不出是谁放的**。
## 判据用「色相差 ≥ 0.10」而不是「颜色不相等」：后者对
## 「差 3% 色相」也算通过，但玩家看不出来。
func test_shared_kind_colours_are_visually_separable() -> void:
	var shared := _shared_kinds()
	var Arena = load("res://scripts/game/arena.gd")
	for kind in shared:
		var colours := {}
		for hero_type in shared[kind]:
			var hero_color: Color = Arena._hero_vfx_color(str(hero_type))
			var accent := SkillFx.accent_for(str(hero_type), str(kind))
			var final: Color = hero_color.lerp(accent, 0.45)
			colours[str(hero_type)] = final
		var heroes: Array = colours.keys()
		for i in heroes.size():
			for j in range(i + 1, heroes.size()):
				var a: Color = colours[heroes[i]]
				var b: Color = colours[heroes[j]]
				var gap := absf(a.h - b.h)
				gap = minf(gap, 1.0 - gap)
				check(gap >= 0.10,
					"%s 的 %s 与 %s 最终渲染色色相只差 %.3f（%s vs %s）：玩家分不出" % [
						str(kind), str(heroes[i]), str(heroes[j]), gap,
						a.to_html(false), b.to_html(false)])

func test_variants_do_not_change_structural_fields() -> void:
	for hero_type in HEROES:
		var def: Dictionary = HeroDefs.get_hero(hero_type)
		for slot in SLOTS:
			var kind := str((def.get(slot, {}) as Dictionary).get("kind", ""))
			if kind == "" or not SkillFx.has_variant(hero_type, kind):
				continue
			var base := SkillFx.recipe(kind)
			var variant := SkillFx.recipe_for(hero_type, kind)
			for key in STRUCTURAL_KEYS:
				eq(variant.get(key, null), base.get(key, null),
					"%s 的 %s 变体改了结构字段 %s：那是 sim 行为，不是外观" % [
						hero_type, kind, key])
			for key in variant:
				check(ALLOWED_EXTRA.has(str(key)) or STRUCTURAL_KEYS.has(str(key)),
					"%s 的 %s 变体引入了未登记的参数「%s」（写进配方但渲染层不读＝静默失效）" % [
						hero_type, kind, str(key)])

# ---------------------------------------------------------------------------
# 不误伤：没登记的英雄必须走通用配方
# ---------------------------------------------------------------------------

## 这条守的是「加变体时手滑」：如果 `recipe_for` 对任何 hero_type 都返回
## 一份改造过的配方，那所有英雄的技能都会跟着变。
func test_unregistered_heroes_keep_the_generic_recipe() -> void:
	for kind in _all_kinds():
		var generic := SkillFx.signature_axes(SkillFx.recipe(str(kind)))
		for hero_type in HEROES:
			if SkillFx.has_variant(hero_type, str(kind)):
				continue
			eq(SkillFx.signature_axes(SkillFx.recipe_for(hero_type, str(kind))), generic,
				"%s 没登记 %s 的变体，但配方被改了：会误伤这个英雄" % [hero_type, str(kind)])

## 空 hero_type（客机事件缺字段、纯逻辑调用）必须回落到通用配方，不能崩也不能变。
func test_empty_hero_type_falls_back_to_generic() -> void:
	for kind in _all_kinds():
		eq(SkillFx.signature_axes(SkillFx.recipe_for("", str(kind))),
			SkillFx.signature_axes(SkillFx.recipe(str(kind))),
			"hero_type 为空时必须回落到通用配方（%s）" % str(kind))
		check(not SkillFx.has_variant("", str(kind)), "空 hero_type 不该有变体")

# ---------------------------------------------------------------------------
# 资源真实性
# ---------------------------------------------------------------------------

## 变体里出现的每个粒子/残留贴图都必须真实存在 —— 否则是白方片，且不报错。
func test_variant_textures_exist() -> void:
	var names := {}
	for hero_type in HEROES:
		for kind in _all_kinds():
			if not SkillFx.has_variant(hero_type, str(kind)):
				continue
			var recipe := SkillFx.recipe_for(hero_type, str(kind))
			for burst in recipe.get("particles", []):
				names[str(burst.get("texture", ""))] = true
			var decal := str(recipe.get("decal", ""))
			if decal != "":
				names[decal] = true
	gt(float(names.size()), 0.0, "变体必须至少引用一种特效贴图")
	for tex in names:
		check(ResourceLoader.exists("res://assets/vfx/textures/%s.png" % str(tex)),
			"变体引用的特效贴图不存在：%s.png（会静默变成白方片）" % str(tex))

## 变体必须真的通过 `requests()` 送到渲染层。
##
## 这条守的是「加了变体但没接进事件归一」那类静默失效：
## `recipe_for` 写好了，但 `requests()` 还在调 `recipe()`，游戏里一点变化都没有。
func test_variants_reach_the_renderer_through_requests() -> void:
	var found := 0
	for hero_type in HEROES:
		var def: Dictionary = HeroDefs.get_hero(hero_type)
		for slot in SLOTS:
			var kind := str((def.get(slot, {}) as Dictionary).get("kind", ""))
			if kind == "" or not SkillFx.has_variant(hero_type, kind):
				continue
			var requests := SkillFx.requests([{
				"type": "skill",
				"slot": slot,
				"hero_type": hero_type,
				"kind": kind,
				"hero": 1,
				"team": "blue",
				"x": 0.0, "y": 0.0, "aim_x": 1.0, "aim_y": 0.0,
			}])
			eq(requests.size(), 1, "skill 事件必须产出一条渲染请求")
			if requests.is_empty():
				continue
			var recipe: Dictionary = requests[0].get("recipe", {})
			eq(str(recipe.get("signature", "")),
				str(SkillFx.recipe_for(hero_type, kind).get("signature", "")),
				"%s 的 %s 变体没有经过 requests() 送到渲染层（还在调 recipe()）" % [
					hero_type, kind])
			found += 1
	gt(float(found), 0.0, "至少有一个变体必须走通 requests()")
