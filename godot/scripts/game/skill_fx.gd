extends RefCounted

# 技能特效的唯一真身。
#
# 这里只做两件纯逻辑的事，不碰任何节点：
#   ① recipe(kind)       —— 技能「长什么样」的配方（环 / 粒子 / 抛射物 / 拖尾 / 震屏）
#   ② requests(events)   —— 把模拟层的事件翻成渲染请求（唯一取口）
#
# 为什么按 kind 而不是按 hero_type：Q 和 W 是同一个英雄的两个技能，按英雄出效果
# 必然撞车。kind 才是技能形态（斩击 / 旋风 / 冲锋 / 陨石…），不同英雄复用同一形态
# 本来就该长得一样。
#
# 为什么要有 requests()：W/R 走 SkillSystem.cast_skill()，事件名是 skill_cast；
# Q/E 走 match_sim._cast_q/_cast_e，事件名是 skill。渲染层曾经只认后者，
# 于是大招放出去毫无表现、也不报错。现在两种事件在同一个入口归一，事件名不再是契约。
#
# ---------------------------------------------------------------------------
# 技能签名（FX-03，2026-11-11）
# ---------------------------------------------------------------------------
# 差距文档 §8 记录的老问题：「17 个技能 -> 5 类配方」——同族技能除了颜色完全一样，
# 玩家读不出「这是谁放的什么」。现在的口径是**每个 kind 至少有一处独有的形状或
# 节奏参数**，一共七个轴（都由 arena 真正消费）：
#
#   | 轴 | 配方键 | 画面上是什么 |
#   | --- | --- | --- |
#   | 粒子贴图 | `burst.texture` | 火花 / 烟 / 光点 / 法阵 / 刀光 / 冲击环 六种剪影 |
#   | 粒子尺寸 | `burst.size` | 大团烟幕 vs 细碎火星（这个参数以前是**空的**，见下） |
#   | 延迟二次爆 | `burst.delay` | 先炸一下、隔 0.12~0.3s 再炸一下 = 节奏 |
#   | 竖直环 | `ring.tilt` | 贴地冲击环 vs 立起来的「光门 / 禁锢柱」 |
#   | 落点刀光 | `arc` | 落点补一片新月（斩击族的形状记忆点） |
#   | 地面残留 | `decal` / `decal_scale` | 灼痕 / 冰阵 / 星尘 / 烟迹的贴图与大小 |
#   | 渐宽光束 | `beam_taper` | 贯穿光带由细到粗，而不是一根等宽圆柱 |
#
# `signature` 是给人读的记忆点名字，`signature_axes()` 是给测试读的机读指纹：
# 后者**只看渲染参数**、不看名字，所以「两个 kind 只是名字不同」会被它抓出来。
# 17 个 kind 的指纹必须两两不同（见 `tests/test_skill_signature.gd`）。
#
# 注意 `size` 曾经是个静默失效的参数：配方里写了、`_spawn_particles()` 也收下了，
# 但函数体里从来没用过它 —— 所有粒子都是一样大的方片。升级时把它接到 quad 尺寸上，
# 它是「烟幕」和「火星」唯一能拉开体量的手段。

const HeroDefs = preload("res://sim/hero_defs.gd")

# 落点刀光的默认高度：和 arena.HERO_SLASH_HEIGHT（胸口）同一个值。
# 51° 俯角下贴地的弧会被路面和血迹吃掉，必须抬到胸口才读得出。
const ARC_HEIGHT := 1.35

# 兜底：新加的 kind 忘了写配方时，至少还有一圈光和一把碎屑，不会「放了没反应」。
const DEFAULT_RECIPE := {
	"signature": "通用冲击",
	"rings": [{"at": "aim", "from": 0.4, "to": 2.4, "dur": 0.3, "alpha": 0.55, "tilt": false}],
	"particles": [{"at": "aim", "count": 12, "speed": 3.0, "height": 0.5, "life": 0.45, "size": 0.12, "texture": "spark", "delay": 0.0}],
	"projectile": 0.0,
	"trail": 0,
	"beam": 0,
	"beam_taper": false,
	"decal": "",
	"decal_scale": 1.0,
	"arc": {},
	"shake": 0.0,
	"hit_stop": 0.0,
}

# 技能强调色：英雄谱系色负责"这是谁"，强调色负责"这是哪个技能"。
# 17 个 kind 各有一个色相，渲染层用 55% 英雄色 + 45% 强调色混合；
# 不新增贴图/资产，就能让同族技能（如 slash/spin）在战场上分开。
const KIND_ACCENTS := {
	"slash": Color(1.0, 0.62, 0.22),
	"spin": Color(1.0, 0.88, 0.35),
	"dash": Color(0.35, 0.90, 0.92),
	"leap_slam": Color(1.0, 0.34, 0.22),
	"burst": Color(0.76, 0.42, 1.0),
	"line": Color(0.30, 0.78, 1.0),
	"slow": Color(0.38, 0.55, 1.0),
	"meteor_storm": Color(1.0, 0.32, 0.72),
	"quake": Color(0.88, 0.56, 0.24),
	"charge": Color(1.0, 0.78, 0.20),
	"shield": Color(0.32, 0.88, 0.72),
	"taunt_aura": Color(0.95, 0.66, 0.26),
	"arrow": Color(0.46, 0.94, 0.42),
	"aoe_shot": Color(0.72, 0.96, 0.30),
	"haste": Color(0.42, 0.98, 0.68),
	"arrow_barrage": Color(0.30, 0.82, 0.34),
	"evade": Color(0.78, 0.36, 0.78),
	"summoner": Color(0.80, 0.90, 1.0),
}

static func accent_color(kind: String) -> Color:
	return KIND_ACCENTS.get(kind, Color(0.9, 0.92, 1.0))

# 英雄谱系色与技能强调色的混合口径。arena 与测试读同一个函数，避免两处公式漂移。
#
# `amount = 1` 表示**完全取强调色**（这是既有契约，被 test_skill_accent_colors 钉住）。
# 色相撞车的处理不在这里做 —— 见 `HERO_VARIANTS` 的 `accent` 字段。
static func blend_color(hero_color: Color, kind: String, amount := 0.45) -> Color:
	return hero_color.lerp(accent_color(kind), clampf(amount, 0.0, 1.0))

## 某个英雄放某个 kind 时的**强调色**。变体可以覆盖它。
##
## 为什么需要：立绘上星璃和墨鸦都是紫色系（9e85ff / cc6beb，色相差 0.03），
## 而 `burst` 的强调色也是紫。两者混出来的颜色几乎一样 —— 团战里同一个 burst
## 技能分不出是谁放的。给墨鸦的变体单独指定一个偏青的强调色，
## 就能在不改全局公式的前提下把这一对拆开。
static func accent_for(hero_type: String, kind: String) -> Color:
	var override: Dictionary = HERO_VARIANTS.get("%s|%s" % [hero_type, kind], {})
	if override.has("accent"):
		return override["accent"]
	return accent_color(kind)

const SUMMONER_COLORS := {
	"flash": Color(0.78, 0.92, 1.0),
	"sprint": Color(0.7, 1.0, 0.55),
	"cleanse": Color(0.55, 0.95, 0.9),
	"heal": Color(0.45, 0.95, 0.6),
}

static func recipe(kind: String) -> Dictionary:
	match kind:
		"slash":
			# 苍刃 Q 裂空斩：贴地短斩环 + **落点一片新月** + 前冲碎屑。
			return _signed(
				_make([_ring("aim", 0.5, 2.6, 0.32, 0.65)], [_burst("aim", 22, 5.0, 0.6, 0.55, 0.16)]),
				"裂空刃",
				{"arc": _arc(118.0, 2.6), "decal": "slash"}
			)
		"spin":
			# 苍刃 W 旋风斩：**立起来的旋风壁** + 脚下双环外扩 + 绕身的刀光碎屑。
			# 和 Q 的区别不是颜色：Q 是"往前斩一片"，W 是"围着自己转一圈"。
			return _signed(
				_make(
					[_ring("self", 0.4, 3.4, 0.42, 0.55, true), _ring("self", 0.3, 2.0, 0.3, 0.5)],
					[_burst("self", 26, 4.2, 0.9, 0.5, 0.14, "slash")],
					0.0, 0, 0, 0.08
				),
				"旋风壁"
			)
		"dash":
			# 苍刃 E 疾风步：起步环 + 路径残影，**残影留的是烟不是火花**（人已经走了）。
			return _signed(
				_make(
					[_ring("self", 0.4, 1.6, 0.26, 0.5)],
					[_burst("self", 8, 2.4, 0.5, 0.35, 0.2, "smoke")],
					0.0, 3
				),
				"疾风残影"
			)
		"leap_slam":
			# 苍刃 / 墨鸦 R：落点大环 + 立环 + **隔 0.16s 的第二下冲击** + 震屏，必须比 Q 重。
			return _signed(
				_make(
					[_ring("aim", 0.8, 5.0, 0.5, 0.7), _ring("aim", 0.4, 2.4, 0.3, 0.6, true)],
					[
						_burst("aim", 30, 6.0, 0.8, 0.6, 0.2, "shock"),
						_burst("aim", 12, 2.6, 0.3, 0.4, 0.1, "shock", 0.16),
					],
					0.0, 0, 0, 0.26, 0.06
				),
				"跳斩震地",
				{"arc": _arc(150.0, 3.4)}
			)
		"burst":
			# 星璃 Q / 墨鸦 W：法球飞到落点再炸开，**0.2s 后补一下次级爆**（法球要"余爆"）。
			return _signed(
				_make(
					[_ring("aim", 0.5, 2.8, 0.3, 0.6)],
					[
						_burst("aim", 20, 4.6, 0.6, 0.5, 0.13, "glow"),
						_burst("aim", 10, 2.4, 0.3, 0.35, 0.09, "shock", 0.2),
					],
					0.22
				),
				"法球迟爆",
				{"decal": "glow", "decal_scale": 1.15}
			)
		"line":
			# 星璃 W 虚空织流：一道**由细到粗**的光带贯穿，沿线补残影环与法阵残留。
			return _signed(
				_make(
					[_ring("aim", 0.4, 2.2, 0.28, 0.55)],
					[_burst("aim", 14, 3.2, 0.5, 0.45, 0.1, "rune")],
					0.0, 3, 1
				),
				"虚空织流",
				{"beam_taper": true, "decal": "rune", "decal_scale": 1.25}
			)
		"slow":
			# 星璃 E 星界禁锢：落点**立起一道禁锢环**，冷雾下沉，地上留一圈冰阵。
			return _signed(
				_make(
					[_ring("aim", 0.4, 3.0, 0.5, 0.55, true)],
					[_burst("aim", 16, 2.6, 0.7, 0.6, 0.19, "smoke")]
				),
				"星界禁锢",
				{"decal": "rune", "decal_scale": 1.35}
			)
		"meteor_storm":
			# 星璃 R 星河天倾：最大的一发 —— 三层环 + **三段延迟陨击（0.15 / 0.3）** + 长震屏。
			return _signed(
				_make(
					[_ring("aim", 1.0, 6.0, 0.6, 0.7), _ring("aim", 0.5, 3.2, 0.45, 0.6, true)],
					[
						_burst("aim", 36, 7.0, 1.0, 0.7, 0.22, "shock"),
						_burst("aim", 16, 3.0, 0.4, 0.5, 0.14, "shock", 0.15),
						_burst("aim", 12, 2.2, 0.3, 0.4, 0.1, "rune", 0.3),
					],
					0.0, 0, 0, 0.3, 0.08
				),
				"星河倾落",
				{"arc": _arc(200.0, 4.2)}
			)
		"quake":
			# 铁壁 Q 震地：自身为圆心的地面冲击环，**扬起来的是土（烟）不是火花**。
			return _signed(
				_make(
					[_ring("self", 0.5, 4.2, 0.5, 0.65)],
					[_burst("self", 20, 3.6, 0.4, 0.5, 0.21, "smoke")],
					0.0, 0, 0, 0.18
				),
				"震地裂土",
				{"decal": "shock", "decal_scale": 1.1}
			)
		"charge":
			# 铁壁 W / 墨鸦 Q：冲锋，路径上留一串残影，**撞上去是一片肩撞的新月**。
			return _signed(
				_make(
					[_ring("aim", 0.4, 2.2, 0.3, 0.55)],
					[_burst("aim", 14, 3.4, 0.5, 0.45, 0.12, "spark")],
					0.0, 4, 0, 0.14
				),
				"铁壁冲撞",
				{"arc": _arc(96.0, 2.2, 1.0)}
			)
		"shield":
			# 铁壁 E 守护壁垒：贴身收拢的**竖直光罩** + 上浮的光点。
			return _signed(
				_make(
					[_ring("self", 0.5, 2.6, 0.45, 0.6, true)],
					[_burst("self", 18, 2.0, 1.2, 0.6, 0.15, "glow")]
				),
				"守护壁垒",
				{"decal": "glow", "decal_scale": 0.85}
			)
		"taunt_aura":
			# 铁壁 R 不破要塞：以自身为中心向外推两圈，其中一圈**立起来**当"要塞墙"。
			return _signed(
				_make(
					[_ring("self", 0.6, 5.0, 0.55, 0.65), _ring("self", 0.4, 3.0, 0.4, 0.55, true)],
					[_burst("self", 24, 3.0, 1.1, 0.6, 0.17, "shock")],
					0.0, 0, 0, 0.2
				),
				"不破要塞"
			)
		"arrow":
			# 翎羽 Q 穿云箭：一支高速箭矢 —— **拖尾拉长、粒子最小**，读成一根线。
			return _signed(
				_make(
					[],
					[_burst("aim", 8, 2.2, 0.4, 0.35, 0.08, "glow")],
					0.12, 5
				),
				"穿云箭",
				{"decal": "slash", "decal_scale": 0.8}
			)
		"aoe_shot":
			# 翎羽 W 爆裂疾射：箭矢 + 落点炸开，**0.12s 后再补一发小爆**（连爆两下）。
			return _signed(
				_make(
					[_ring("aim", 0.5, 3.0, 0.32, 0.6)],
					[
						_burst("aim", 18, 4.0, 0.6, 0.5, 0.13, "shock"),
						_burst("aim", 9, 2.0, 0.4, 0.3, 0.08, "shock", 0.12),
					],
					0.18
				),
				"爆裂疾射",
				{"decal": "shock", "decal_scale": 1.3}
			)
		"haste":
			# 翎羽 E 鹰眼：脚下上浮的光点（加速是"往上飘"，不是"往外炸"）。
			return _signed(
				_make(
					[_ring("self", 0.4, 2.2, 0.4, 0.55)],
					[_burst("self", 14, 2.4, 1.4, 0.65, 0.11, "glow")],
					0.0, 2
				),
				"鹰眼疾行"
			)
		"arrow_barrage":
			# 翎羽 R 万箭归宗：落点连片箭雨 —— **三波延迟落点（0.14 / 0.28）** + 一片横扫新月。
			return _signed(
				_make(
					[_ring("aim", 0.8, 5.2, 0.5, 0.65), _ring("aim", 0.4, 2.6, 0.3, 0.55, true)],
					[
						_burst("aim", 34, 6.5, 0.9, 0.6, 0.12, "spark"),
						_burst("aim", 14, 3.0, 0.5, 0.4, 0.1, "spark", 0.14),
						_burst("aim", 10, 2.0, 0.35, 0.3, 0.08, "glow", 0.28),
					],
					0.0, 0, 0, 0.16
				),
				"万箭归宗",
				{"arc": _arc(140.0, 3.8)}
			)
		"evade":
			# 墨鸦 E 匿踪：淡出，刻意最轻 —— **一蓬烟**，连冲击环都不给。
			return _signed(
				_make(
					[_ring("self", 0.3, 1.8, 0.3, 0.45)],
					[_burst("self", 12, 1.8, 0.6, 0.4, 0.23, "smoke", 0.06)]
				),
				"匿踪烟幕",
				{"decal": "smoke", "decal_scale": 0.7}
			)
	return DEFAULT_RECIPE.duplicate(true)

static func summoner_recipe(spell: String) -> Dictionary:
	match spell:
		"flash":
			# 闪现：起点和落点各一圈，中间补残影，才读得出「瞬移」。
			return _signed(
				_make(
					[_ring("self", 0.3, 1.4, 0.22, 0.5), _ring("aim", 0.3, 1.4, 0.22, 0.5)],
					[_burst("self", 10, 2.0, 0.5, 0.4, 0.11, "glow")],
					0.0, 2
				),
				"闪现"
			)
		"sprint":
			# 疾跑：脚下扩散一圈 + 背后拖尾，读得出「加速」而不是伤害。
			return _signed(
				_make(
					[_ring("self", 0.4, 1.8, 0.24, 0.45)],
					[_burst("self", 14, 3.2, 0.45, 0.5, 0.12, "glow")],
					0.0, 2
				),
				"疾跑"
			)
		"cleanse":
			# 净化：脚下向上扫一圈立环，法阵感。
			return _signed(
				_make(
					[_ring("self", 0.4, 2.2, 0.45, 0.6, true)],
					[_burst("self", 16, 2.2, 1.3, 0.55, 0.12, "rune")]
				),
				"净化"
			)
		"heal":
			# 治疗：绿色上浮光点。
			return _signed(
				_make(
					[_ring("self", 0.4, 2.8, 0.5, 0.6)],
					[_burst("self", 20, 2.0, 1.5, 0.6, 0.13, "glow")]
				),
				"治疗",
				{"decal": "glow"}
			)
	return DEFAULT_RECIPE.duplicate(true)

static func summoner_color(spell: String) -> Color:
	return SUMMONER_COLORS.get(spell, Color(0.9, 0.92, 1.0))

# 老事件没有 kind 字段时，按 hero_type + slot 反查技能定义。
static func kind_for(hero_type: String, slot: String) -> String:
	if hero_type == "" or slot == "":
		return ""
	var def: Dictionary = HeroDefs.get_hero(hero_type)
	var skill: Dictionary = def.get(slot, {})
	return str(skill.get("kind", ""))

# ---------------------------------------------------------------------------
# 英雄级技能变体（HERO-06）
# ---------------------------------------------------------------------------
#
# 为什么需要这一层：`recipe(kind)` 只按 kind 分派，而 17 个 kind 里有 3 个是
# **两个英雄共用的**：
#   - `burst`      → 星璃 Q（星陨·法术）与 墨鸦 W（毒牙·近身毒爆）
#   - `charge`     → 铁壁 W（野蛮冲撞·重装冲撞）与 墨鸦 Q（影袭·瞬身突刺）
#   - `leap_slam`  → 苍刃 R（裂地崩山·巨剑砸地）与 墨鸦 R（绝影处决·突进处决）
# 这三对以前**形状完全一样**，只靠英雄色 + 强调色混合来区分 —— 在 5v5 团战里
# 「是谁放的」和「这是哪个技能」两个问题会互相顶掉。
#
# 做法：给这几对加英雄级覆盖，只改**形状轴与节奏轴**（环的朝向/半径、粒子贴图、
# 二次爆延迟、残留贴图、光束渐宽），不动结构字段（projectile/trail/beam/shake/hit_stop）——
# 那些决定「sim 里有没有真实弹道」，画错就是重复画一颗弹丸。
#
# 覆盖键是 `"<hero_type>|<kind>"`。没有覆盖的走 `recipe(kind)`，行为完全不变。

const HERO_VARIANTS := {
	# 墨鸦 W 毒牙：近身毒爆 —— 不是法球飞过去炸，而是**贴地扩散的毒圈**。
	# 形状：一圈爬升的绿雾 + 一圈低矮的贴地环；节奏：无延迟（毒是瞬间的）。
	"assassin|burst": {
		"signature": "毒牙扩散",
		# 强调色改青绿：星璃的 burst 是紫，两人立绘都是紫系，不改色相就分不开。
		"accent": Color(0.42, 1.0, 0.58),
		"rings": [
			{"at": "self", "from": 0.4, "to": 2.4, "dur": 0.34, "alpha": 0.6, "tilt": false},
		],
		"particles": [
			{"at": "self", "count": 18, "speed": 2.8, "height": 0.3, "life": 0.7, "size": 0.17,
				"texture": "smoke", "delay": 0.0},
			{"at": "self", "count": 8, "speed": 1.6, "height": 0.15, "life": 0.5, "size": 0.1,
				"texture": "spark", "delay": 0.08},
		],
		"decal": "smoke",
		"decal_scale": 1.0,
	},
	# 墨鸦 Q 影袭：瞬身突刺 —— 没有重装冲撞的震屏与前冲，是**一条残影线**。
	# 形状：起点一圈收束环 + 沿途 4 段残影；节奏：极短、无二次爆。
	"assassin|charge": {
		"signature": "影袭残线",
		"accent": Color(0.72, 0.90, 1.0),
		"rings": [
			{"at": "self", "from": 0.5, "to": 1.4, "dur": 0.2, "alpha": 0.5, "tilt": true},
		],
		"particles": [
			{"at": "self", "count": 10, "speed": 3.4, "height": 0.5, "life": 0.34, "size": 0.13,
				"texture": "smoke", "delay": 0.0},
		],
		"trail": 4,
		"decal": "slash",
		"decal_scale": 0.85,
	},
	# 墨鸦 R 绝影处决：突进处决 —— 比苍刃的「跳斩震地」**窄而深**。
	# 形状：落点一个窄环 + 竖直刀光扇面；节奏：两段但间隔更短（处决是连贯的）。
	"assassin|leap_slam": {
		"signature": "绝影处决",
		"accent": Color(1.0, 0.36, 0.78),
		"rings": [
			{"at": "aim", "from": 1.2, "to": 3.6, "dur": 0.4, "alpha": 0.65, "tilt": false},
			{"at": "aim", "from": 0.5, "to": 1.8, "dur": 0.26, "alpha": 0.55, "tilt": true},
		],
		"particles": [
			{"at": "aim", "count": 22, "speed": 5.2, "height": 1.1, "life": 0.5, "size": 0.15,
				"texture": "slash", "delay": 0.0},
			{"at": "aim", "count": 10, "speed": 2.0, "height": 0.4, "life": 0.36, "size": 0.1,
				"texture": "smoke", "delay": 0.12},
		],
		"arc": {"deg": 76.0, "reach": 2.6, "height": 1.15},
		"decal": "slash",
		"decal_scale": 1.1,
	},
	# 铁壁 W 野蛮冲撞：重装冲撞 —— 比影袭**宽得多、慢得多**，带扬尘与震荡环。
	# 形状：脚下一大圈冲击环 + 两侧扬尘；节奏：单段但更长。
	"tank|charge": {
		"signature": "重装冲撞",
		"rings": [
			{"at": "self", "from": 0.8, "to": 3.2, "dur": 0.44, "alpha": 0.6, "tilt": false},
		],
		"particles": [
			{"at": "self", "count": 20, "speed": 3.0, "height": 0.25, "life": 0.68, "size": 0.2,
				"texture": "smoke", "delay": 0.0},
			{"at": "self", "count": 10, "speed": 2.0, "height": 0.5, "life": 0.5, "size": 0.14,
				"texture": "shock", "delay": 0.1},
		],
		"trail": 2,
		"decal": "shock",
		"decal_scale": 1.3,
	},
}

## 取某个英雄放某个 kind 时的配方。**这是渲染层应该用的入口**，
## `recipe(kind)` 只留给「不知道是谁放的」的场合（例如测试与预警圈）。
static func recipe_for(hero_type: String, kind: String) -> Dictionary:
	var override: Dictionary = HERO_VARIANTS.get("%s|%s" % [hero_type, kind], {})
	if override.is_empty():
		return recipe(kind)
	# 以通用配方为底，再叠英雄覆盖 —— 这样覆盖只需要写「和通用不同的键」，
	# 结构字段（projectile/trail/beam/shake/hit_stop）默认继承，不会因为漏写而丢。
	var merged := recipe(kind).duplicate(true)
	for key in override:
		merged[key] = override[key]
	return merged

## 这个英雄的某个 kind 是否走了专属变体（测试与文档用）。
static func has_variant(hero_type: String, kind: String) -> bool:
	return HERO_VARIANTS.has("%s|%s" % [hero_type, kind])

# 机读指纹：**只看渲染参数**（环朝向 / 粒子贴图与节奏与体量 / 残留 / 刀光弧 / 光束渐宽），
# 不看 `signature` 名字。两个 kind 只要长得不一样，这里就一定不一样。
# 测试用它做「17 个 kind 两两去重」——名字撞车、参数撞车都能抓出来。
static func signature_axes(recipe: Dictionary) -> String:
	var parts: Array[String] = []
	for ring in recipe.get("rings", []):
		parts.append("r:%s:%.2f-%.2f/%s" % [
			str(ring.get("at", "aim")),
			float(ring.get("from", 0.0)),
			float(ring.get("to", 0.0)),
			"v" if bool(ring.get("tilt", false)) else "f",
		])
	for burst in recipe.get("particles", []):
		parts.append("p:%s:%d:%.2f:%s:%.2f" % [
			str(burst.get("at", "aim")),
			int(burst.get("count", 0)),
			float(burst.get("delay", 0.0)),
			str(burst.get("texture", "")),
			float(burst.get("size", 0.12)),
		])
	var decal := str(recipe.get("decal", ""))
	if decal != "":
		parts.append("d:%s:%.2f" % [decal, float(recipe.get("decal_scale", 1.0))])
	var arc: Dictionary = recipe.get("arc", {})
	if not arc.is_empty():
		parts.append("a:%.0f:%.1f" % [float(arc.get("deg", 0.0)), float(arc.get("reach", 0.0))])
	if bool(recipe.get("beam_taper", false)):
		parts.append("b:taper")
	return "|".join(parts)

# 事件 → 渲染请求。Q/E 的 skill、W/R 的 skill_cast、召唤师技能的 summoner_cast
# 全部在这里归一，渲染层不再关心事件名。
static func requests(events: Array) -> Array:
	var out: Array = []
	for item in events:
		if not (item is Dictionary):
			continue
		var event: Dictionary = item
		var type := str(event.get("type", ""))
		if type == "skill" or type == "skill_cast":
			var slot := str(event.get("slot", "q"))
			var hero_type := str(event.get("hero_type", ""))
			var kind := str(event.get("kind", ""))
			if kind == "":
				kind = kind_for(hero_type, slot)
			out.append({
				"hero_id": int(event.get("hero", event.get("caster_id", -1))),
				"slot": slot,
				"hero_type": hero_type,
				"kind": kind,
				"team": str(event.get("team", "")),
				"summoner": "",
				"from": _point(event, "start_x", "start_y", "x", "y"),
				"aim": _point(event, "aim_x", "aim_y", "x", "y"),
				# 英雄级变体：同 kind 的两个英雄（如 burst = 星璃Q / 墨鸦W）
				# 拿到的形状与节奏不同，而不是只换颜色。
				"recipe": recipe_for(hero_type, kind),
			})
		elif type == "summoner_cast":
			var spell := str(event.get("spell_id", "flash"))
			out.append({
				"hero_id": int(event.get("caster_id", -1)),
				"slot": "",
				"hero_type": str(event.get("hero_type", "")),
				"kind": "summoner_" + spell,
				"team": str(event.get("team", "")),
				"summoner": spell,
				"from": _point(event, "start_x", "start_y", "x", "y"),
				"aim": _point(event, "aim_x", "aim_y", "x", "y"),
				"recipe": summoner_recipe(spell),
			})
	return out

static func _make(rings: Array, particles: Array, projectile := 0.0, trail := 0, beam := 0, shake := 0.0, hit_stop := 0.0) -> Dictionary:
	return {
		"signature": "",
		"rings": rings,
		"particles": particles,
		"projectile": projectile,
		"trail": trail,
		"beam": beam,
		"beam_taper": false,
		"decal": "",
		"decal_scale": 1.0,
		"arc": {},
		"shake": shake,
		"hit_stop": hit_stop,
	}

# 给配方挂上人类可读的签名名与额外的形状/节奏键（`arc` / `decal` / `beam_taper`）。
# 结构字段（projectile / trail / beam / shake / hit_stop）仍然只由 `_make` 的位置参数给，
# 一个键只有一个写法 —— 两个入口写同一个键迟早会漂移。
static func _signed(recipe: Dictionary, signature: String, extra: Dictionary = {}) -> Dictionary:
	recipe["signature"] = signature
	for key in extra:
		recipe[key] = extra[key]
	return recipe

static func _arc(deg: float, reach: float, height := ARC_HEIGHT) -> Dictionary:
	return {"deg": deg, "reach": reach, "height": height}

static func _ring(at: String, from: float, to: float, dur: float, alpha: float, tilt := false) -> Dictionary:
	return {"at": at, "from": from, "to": to, "dur": dur, "alpha": alpha, "tilt": tilt}

static func _burst(at: String, count: int, speed: float, height: float, life: float, size := 0.12, texture := "spark", delay := 0.0) -> Dictionary:
	return {
		"at": at, "count": count, "speed": speed, "height": height,
		"life": life, "size": size, "texture": texture, "delay": delay,
	}

static func _point(event: Dictionary, kx1: String, ky1: String, kx2: String, ky2: String) -> Vector2:
	if event.has(kx1) and event.has(ky1):
		return Vector2(float(event.get(kx1, 0.0)), float(event.get(ky1, 0.0)))
	return Vector2(float(event.get(kx2, 0.0)), float(event.get(ky2, 0.0)))
