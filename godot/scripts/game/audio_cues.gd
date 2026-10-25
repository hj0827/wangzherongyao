extends RefCounted

# 项目没有音效资源，所有提示音都用合成 PCM 现场生成：
# 草丛进出的气流声、回城与传送的引导/完成/打断。
#
# 约定：
# - 引导音（*_channel）铺底、稍长，起手时播一次；
# - 完成音（*_done）短促、有瞬态，是打击点；
# - 打断音（*_break）下行、闷，语义是「断了」。
# 完成音必须比引导音短，否则会和后续战斗音糊在一起。

const SAMPLE_RATE := 22050

# 合成一次要跑几万次采样，起手时重算会卡一帧。缓存住，同一个 cue 只生成一次。
static var _cache: Dictionary = {}

static func enter_bush() -> AudioStreamWAV:
	return _sweep(0.22, 260.0, 880.0, 0.34, 0.3, 1701)

static func exit_bush() -> AudioStreamWAV:
	return _sweep(0.18, 760.0, 250.0, 0.24, 0.22, 9027)

# ---------------- 回城 ----------------

# 引导：低频和声缓慢上行 + 一层气流。铺底用，不抢战斗音。
static func recall_channel() -> AudioStreamWAV:
	return _cached("recall_channel", func() -> AudioStreamWAV:
		return _render(1.4, 4801, func(t: float, rng: RandomNumberGenerator, state: Dictionary) -> float:
			var freq := lerpf(174.0, 246.0, t) * (1.0 + 0.006 * sin(TAU * 5.2 * t))
			state.phase = float(state.phase) + TAU * freq / SAMPLE_RATE
			var phase := float(state.phase)
			var tone := sin(phase) * 0.55 + sin(phase * 2.0) * 0.22 + sin(phase * 3.0) * 0.11
			var air := rng.randf_range(-1.0, 1.0) * 0.06
			# 淡入 0.3 秒，尾端继续上扬，暗示「快读完了」。
			var envelope := minf(t / 0.22, 1.0) * (0.55 + 0.45 * t)
			return (tone + air) * envelope * 0.62
		)
	)

# 完成：明亮钟声上扫 + 极短的噪声瞬态，落点是「叮」。
static func recall_done() -> AudioStreamWAV:
	return _cached("recall_done", func() -> AudioStreamWAV:
		return _render(0.55, 9111, func(t: float, rng: RandomNumberGenerator, state: Dictionary) -> float:
			var freq := lerpf(660.0, 990.0, minf(t * 2.2, 1.0))
			state.phase = float(state.phase) + TAU * freq / SAMPLE_RATE
			var phase := float(state.phase)
			var bell := sin(phase) * 0.5 + sin(phase * 2.01) * 0.26 + sin(phase * 3.98) * 0.12
			var shimmer := sin(phase * 6.02) * 0.06 * exp(-t * 6.0)
			var transient := rng.randf_range(-1.0, 1.0) * 0.35 * exp(-t * 55.0)
			var envelope := minf(t / 0.006, 1.0) * pow(1.0 - t, 2.2)
			return (bell + shimmer + transient) * envelope * 0.8
		)
	)

# 打断：下行闷响 + 软削波，听感是「断了」而不是「成功了」。
static func recall_break() -> AudioStreamWAV:
	return _cached("recall_break", func() -> AudioStreamWAV:
		return _render(0.3, 3021, func(t: float, rng: RandomNumberGenerator, state: Dictionary) -> float:
			var freq := lerpf(300.0, 82.0, pow(t, 0.55))
			state.phase = float(state.phase) + TAU * freq / SAMPLE_RATE
			var body := tanh(sin(float(state.phase)) * 2.4) * 0.5
			var thud := rng.randf_range(-1.0, 1.0) * 0.3 * exp(-t * 30.0)
			var envelope := minf(t / 0.004, 1.0) * pow(1.0 - t, 2.8)
			return (body + thud) * envelope * 0.72
		)
	)

# ---------------- 河道传送阵 ----------------

# 引导：高频能量汇聚，28Hz 颤动，金属感。比回城更急促。
static func teleport_channel() -> AudioStreamWAV:
	return _cached("teleport_channel", func() -> AudioStreamWAV:
		return _render(1.0, 5510, func(t: float, rng: RandomNumberGenerator, state: Dictionary) -> float:
			var freq := lerpf(720.0, 1320.0, t * t)
			state.phase = float(state.phase) + TAU * freq / SAMPLE_RATE
			var phase := float(state.phase)
			var tremolo := 0.65 + 0.35 * sin(TAU * 28.0 * t)
			var tone := sin(phase) * 0.4 + sin(phase * 2.5) * 0.18
			var spark := rng.randf_range(-1.0, 1.0) * 0.12
			var envelope := minf(t / 0.12, 1.0) * (0.5 + 0.5 * t)
			return (tone * tremolo + spark) * envelope * 0.6
		)
	)

# 完成：快速下扫的「咻」+ 噪声爆，瞬态在极短的 3ms 内建立。
static func teleport_done() -> AudioStreamWAV:
	return _cached("teleport_done", func() -> AudioStreamWAV:
		return _render(0.45, 7733, func(t: float, rng: RandomNumberGenerator, state: Dictionary) -> float:
			var freq := lerpf(2100.0, 280.0, pow(t, 0.4))
			state.phase = float(state.phase) + TAU * freq / SAMPLE_RATE
			var whiz := sin(float(state.phase)) * 0.45
			var crack := rng.randf_range(-1.0, 1.0) * 0.55 * exp(-t * 18.0)
			var envelope := minf(t / 0.003, 1.0) * pow(1.0 - t, 1.8)
			return (whiz + crack) * envelope * 0.85
		)
	)

# 打断：断电式下行，短且干。
static func teleport_break() -> AudioStreamWAV:
	return _cached("teleport_break", func() -> AudioStreamWAV:
		return _render(0.25, 6211, func(t: float, rng: RandomNumberGenerator, state: Dictionary) -> float:
			var freq := lerpf(900.0, 140.0, pow(t, 0.35))
			state.phase = float(state.phase) + TAU * freq / SAMPLE_RATE
			var body := tanh(sin(float(state.phase)) * 3.0) * 0.42
			var fizz := rng.randf_range(-1.0, 1.0) * 0.22 * exp(-t * 14.0)
			var envelope := minf(t / 0.003, 1.0) * pow(1.0 - t, 2.4)
			return (body + fizz) * envelope * 0.7
		)
	)

# ================================================================
# 战斗 / 地图 / UI 音效
#
# 与上面回城传送那批的区别：这批用 spec 字典 + _synth() 合成，
# 因为它们的形状高度相似（一段有包络的滑音 + 一撮噪声），
# 逐个写采样函数会变成 30 段几乎一样的循环体。
#
# 命名即契约：`AudioPlan.CUES` 里的每个名字都必须在这里有实现，
# `tests/test_audio_system.gd` 会逐条核实，漏一个就是「事件来了没声音」。
# ================================================================

const CUE_ATTACK_SWING := "attack_swing"
const CUE_HIT_HERO := "hit_hero"
const CUE_HIT_MINION := "hit_minion"
const CUE_HIT_STRUCTURE := "hit_structure"
const CUE_CRIT := "crit"
const CUE_SKILL_BLADE := "skill_blade"
const CUE_SKILL_TANK := "skill_tank"
const CUE_SKILL_MAGE := "skill_mage"
const CUE_SKILL_ARCHER := "skill_archer"
const CUE_SKILL_ASSASSIN := "skill_assassin"
const CUE_SKILL_ULT := "skill_ult"
# 召唤师技能（闪现/终结/净化/治疗）共用一个短促的施法音：
# 它们形态差异大，但「按下 F 生效了」这一层反馈是同一个。
const CUE_SUMMONER := "summoner_spell"
const CUE_DEATH_HERO := "death_hero"
const CUE_DEATH_MINION := "death_minion"
const CUE_TOWER_DOWN := "tower_down"
const CUE_GUARD_DOWN := "guard_down"
const CUE_SHIELD_BREAK := "shield_break"
const CUE_LEVEL_UP := "level_up"
const CUE_PURCHASE := "purchase"
const CUE_OBJECTIVE_DOWN := "objective_down"
const CUE_BUFF_TAKEN := "buff_taken"
const CUE_SPIRIT_DOWN := "spirit_down"
const CUE_WAVE_HORN := "wave_horn"
const CUE_BASE_FALL := "base_fall"
const CUE_RESPAWN := "respawn"
const CUE_DENIED := "denied"
const CUE_LOW_HP := "low_hp"
const CUE_TOWER_SHOT := "tower_shot"
const CUE_UI_CLICK := "ui_click"
const CUE_UI_CONFIRM := "ui_confirm"
const CUE_UI_BACK := "ui_back"
const CUE_UI_ERROR := "ui_error"

const NAMES := [
	CUE_ATTACK_SWING, CUE_HIT_HERO, CUE_HIT_MINION, CUE_HIT_STRUCTURE, CUE_CRIT,
	CUE_SKILL_BLADE, CUE_SKILL_TANK, CUE_SKILL_MAGE, CUE_SKILL_ARCHER, CUE_SKILL_ASSASSIN, CUE_SKILL_ULT,
	CUE_SUMMONER,
	CUE_DEATH_HERO, CUE_DEATH_MINION, CUE_TOWER_DOWN, CUE_GUARD_DOWN, CUE_SHIELD_BREAK,
	CUE_LEVEL_UP, CUE_PURCHASE, CUE_OBJECTIVE_DOWN, CUE_BUFF_TAKEN, CUE_SPIRIT_DOWN,
	CUE_WAVE_HORN, CUE_BASE_FALL, CUE_RESPAWN, CUE_DENIED, CUE_LOW_HP, CUE_TOWER_SHOT,
	CUE_UI_CLICK, CUE_UI_CONFIRM, CUE_UI_BACK, CUE_UI_ERROR,
	"enter_bush", "exit_bush",
	"recall_channel", "recall_done", "recall_break",
	"teleport_channel", "teleport_done", "teleport_break",
]

# 按名字取音频。导演层只认名字，不认识波形。
static func cue(cue_name: String) -> AudioStreamWAV:
	match cue_name:
		CUE_ATTACK_SWING:
			return attack_swing()
		CUE_HIT_HERO:
			return hit_hero()
		CUE_HIT_MINION:
			return hit_minion()
		CUE_HIT_STRUCTURE:
			return hit_structure()
		CUE_CRIT:
			return crit()
		CUE_SKILL_BLADE:
			return skill_blade()
		CUE_SKILL_TANK:
			return skill_tank()
		CUE_SKILL_MAGE:
			return skill_mage()
		CUE_SKILL_ARCHER:
			return skill_archer()
		CUE_SKILL_ASSASSIN:
			return skill_assassin()
		CUE_SKILL_ULT:
			return skill_ult()
		CUE_SUMMONER:
			return summoner_spell()
		CUE_DEATH_HERO:
			return death_hero()
		CUE_DEATH_MINION:
			return death_minion()
		CUE_TOWER_DOWN:
			return tower_down()
		CUE_GUARD_DOWN:
			return guard_down()
		CUE_SHIELD_BREAK:
			return shield_break()
		CUE_LEVEL_UP:
			return level_up()
		CUE_PURCHASE:
			return purchase()
		CUE_OBJECTIVE_DOWN:
			return objective_down()
		CUE_BUFF_TAKEN:
			return buff_taken()
		CUE_SPIRIT_DOWN:
			return spirit_down()
		CUE_WAVE_HORN:
			return wave_horn()
		CUE_BASE_FALL:
			return base_fall()
		CUE_RESPAWN:
			return respawn()
		CUE_DENIED:
			return denied()
		CUE_LOW_HP:
			return low_hp()
		CUE_TOWER_SHOT:
			return tower_shot()
		CUE_UI_CLICK:
			return ui_click()
		CUE_UI_CONFIRM:
			return ui_confirm()
		CUE_UI_BACK:
			return ui_back()
		CUE_UI_ERROR:
			return ui_error()
		"enter_bush":
			return enter_bush()
		"exit_bush":
			return exit_bush()
		"recall_channel":
			return recall_channel()
		"recall_done":
			return recall_done()
		"recall_break":
			return recall_break()
		"teleport_channel":
			return teleport_channel()
		"teleport_done":
			return teleport_done()
		"teleport_break":
			return teleport_break()
	return null

# ---------------- 普攻 / 命中 ----------------

# 挥砍：纯噪声扫频。没有音高，所以连着砍不会变成旋律。
static func attack_swing() -> AudioStreamWAV:
	return _cached(CUE_ATTACK_SWING, func() -> AudioStreamWAV:
		return _synth(0.13, 2101, {"from": 1900.0, "to": 480.0, "harm": [], "noise": 0.62, "noise_decay": 16.0, "attack": 0.003, "decay": 3.0, "gain": 0.5})
	)

# 打英雄：有音高的闷响 + 一记脆响，是「打到了」的确认音。
static func hit_hero() -> AudioStreamWAV:
	return _cached(CUE_HIT_HERO, func() -> AudioStreamWAV:
		return _synth(0.17, 2203, {"from": 190.0, "to": 88.0, "curve": 1.3, "harm": [1.0, 0.5], "noise": 0.45, "noise_decay": 26.0, "decay": 3.2, "gain": 0.72})
	)

# 打小兵：更轻更短。团战时这个音会出现几十次，长一点就糊。
static func hit_minion() -> AudioStreamWAV:
	return _cached(CUE_HIT_MINION, func() -> AudioStreamWAV:
		return _synth(0.09, 2309, {"from": 330.0, "to": 180.0, "harm": [1.0, 0.3], "noise": 0.3, "noise_decay": 40.0, "decay": 3.6, "gain": 0.34})
	)

# 打塔/水晶：非谐波叠出来的金属声，和血肉有明确区分。
static func hit_structure() -> AudioStreamWAV:
	return _cached(CUE_HIT_STRUCTURE, func() -> AudioStreamWAV:
		return _synth(0.16, 2411, {"freq": 330.0, "harm": [1.0, 0.72, 0.48, 0.3], "noise": 0.32, "noise_decay": 30.0, "decay": 2.8, "gain": 0.42})
	)

# 暴击：上扫的金属炸裂，叠在挥砍音之上。
static func crit() -> AudioStreamWAV:
	return _cached(CUE_CRIT, func() -> AudioStreamWAV:
		return _synth(0.26, 2513, {"from": 920.0, "to": 2050.0, "harm": [1.0, 0.55, 0.25], "noise": 0.4, "noise_decay": 20.0, "decay": 2.4, "gain": 0.6})
	)

# ---------------- 技能 ----------------

# 战士：快速下滑的刀风。
static func skill_blade() -> AudioStreamWAV:
	return _cached(CUE_SKILL_BLADE, func() -> AudioStreamWAV:
		return _synth(0.26, 2601, {"from": 2400.0, "to": 700.0, "harm": [], "noise": 0.58, "noise_decay": 11.0, "decay": 2.4, "gain": 0.55})
	)

# 坦克：低频震地，越沉越有重量。
static func skill_tank() -> AudioStreamWAV:
	return _cached(CUE_SKILL_TANK, func() -> AudioStreamWAV:
		return _synth(0.5, 2707, {"from": 96.0, "to": 44.0, "curve": 1.4, "harm": [1.0, 0.6], "noise": 0.42, "noise_decay": 12.0, "decay": 2.6, "gain": 0.78})
	)

# 法师：带颤音的滑动，是「能量」而不是「打击」。
static func skill_mage() -> AudioStreamWAV:
	return _cached(CUE_SKILL_MAGE, func() -> AudioStreamWAV:
		return _synth(0.32, 2803, {"from": 420.0, "to": 1180.0, "curve": 0.7, "harm": [1.0, 0.4, 0.2], "trem": 22.0, "trem_depth": 0.55, "attack": 0.01, "decay": 2.2, "gain": 0.5})
	)

# 射手：短促的弦响 + 一点气流。
static func skill_archer() -> AudioStreamWAV:
	return _cached(CUE_SKILL_ARCHER, func() -> AudioStreamWAV:
		return _synth(0.2, 2909, {"from": 880.0, "to": 520.0, "harm": [1.0, 0.35], "noise": 0.36, "noise_decay": 28.0, "decay": 3.4, "gain": 0.5})
	)

# 刺客：两指薄的金属摩擦，高频上挑，比战士更快更尖。
static func skill_assassin() -> AudioStreamWAV:
	return _cached(CUE_SKILL_ASSASSIN, func() -> AudioStreamWAV:
		return _synth(0.2, 3137, {"from": 3100.0, "to": 1650.0, "harm": [1.0, 0.22], "noise": 0.66, "noise_decay": 19.0, "decay": 3.8, "gain": 0.52})
	)

# 大招：长上扫 + 尾音持续。全场都该听见「有人开大」。
static func skill_ult() -> AudioStreamWAV:
	return _cached(CUE_SKILL_ULT, func() -> AudioStreamWAV:
		return _synth(0.85, 3011, {"from": 180.0, "to": 1400.0, "curve": 0.6, "harm": [1.0, 0.5, 0.25], "noise": 0.28, "noise_decay": 3.0, "attack": 0.02, "sustain": 0.18, "decay": 1.6, "gain": 0.66})
	)

# 召唤师技能：短促上挑 + 颤音，比英雄技能更「魔法」、更短。
# 比引导音（回城/传送）短，因为它是一次性瞬发，不是持续吟唱。
static func summoner_spell() -> AudioStreamWAV:
	return _cached(CUE_SUMMONER, func() -> AudioStreamWAV:
		return _synth(0.34, 3203, {"from": 760.0, "to": 1900.0, "curve": 0.75, "harm": [1.0, 0.45, 0.18], "trem": 30.0, "trem_depth": 0.35, "noise": 0.3, "noise_decay": 16.0, "attack": 0.004, "decay": 2.6, "gain": 0.62})
	)

# ---------------- 击杀 / 建筑 ----------------

static func death_hero() -> AudioStreamWAV:
	return _cached(CUE_DEATH_HERO, func() -> AudioStreamWAV:
		return _synth(0.75, 3109, {"from": 330.0, "to": 68.0, "curve": 1.4, "harm": [1.0, 0.5, 0.2], "noise": 0.3, "noise_decay": 8.0, "decay": 1.9, "gain": 0.72})
	)

static func death_minion() -> AudioStreamWAV:
	return _cached(CUE_DEATH_MINION, func() -> AudioStreamWAV:
		return _synth(0.16, 3203, {"from": 430.0, "to": 160.0, "harm": [1.0, 0.3], "noise": 0.3, "noise_decay": 30.0, "decay": 3.0, "gain": 0.3})
	)

# 塔倒：低频塌陷 + 碎石灰。要比打塔重一个量级。
static func tower_down() -> AudioStreamWAV:
	return _cached(CUE_TOWER_DOWN, func() -> AudioStreamWAV:
		return _synth(1.25, 3301, {"from": 92.0, "to": 34.0, "curve": 1.5, "harm": [1.0, 0.6], "noise": 0.55, "noise_decay": 2.4, "decay": 2.0, "gain": 0.85})
	)

static func guard_down() -> AudioStreamWAV:
	return _cached(CUE_GUARD_DOWN, func() -> AudioStreamWAV:
		return _synth(0.9, 3407, {"from": 120.0, "to": 52.0, "curve": 1.4, "harm": [1.0, 0.5], "noise": 0.45, "noise_decay": 3.2, "decay": 2.2, "gain": 0.7})
	)

# 护盾破碎：高频非谐波 + 噪声长尾 = 玻璃。
static func shield_break() -> AudioStreamWAV:
	return _cached(CUE_SHIELD_BREAK, func() -> AudioStreamWAV:
		return _synth(0.7, 3503, {"freq": 1400.0, "harm": [1.0, 0.6, 0.5, 0.36], "noise": 0.62, "noise_decay": 8.0, "decay": 2.8, "gain": 0.5})
	)

# 暴君/主宰被击杀：更长的塌陷 + 号角层。
static func objective_down() -> AudioStreamWAV:
	return _cached(CUE_OBJECTIVE_DOWN, func() -> AudioStreamWAV:
		return _layer(1.5, 3607, [
			{"at": 0.0, "dur": 1.5, "spec": {"from": 70.0, "to": 30.0, "curve": 1.5, "harm": [1.0, 0.55], "noise": 0.5, "noise_decay": 1.6, "decay": 1.7, "gain": 0.85}},
			{"at": 0.0, "dur": 0.9, "spec": {"freq": 155.0, "harm": [1.0, 0.5, 0.3], "attack": 0.06, "sustain": 0.5, "decay": 1.2, "trem": 5.0, "trem_depth": 0.35, "gain": 0.42}},
		])
	)

# ---------------- 地图 / 经济 ----------------

static func level_up() -> AudioStreamWAV:
	return _cached(CUE_LEVEL_UP, func() -> AudioStreamWAV:
		return _layer(0.6, 3701, [
			{"at": 0.0, "dur": 0.3, "spec": {"freq": 440.0, "harm": [1.0, 0.4, 0.2], "attack": 0.004, "decay": 3.0, "gain": 0.34}},
			{"at": 0.09, "dur": 0.3, "spec": {"freq": 523.25, "harm": [1.0, 0.4, 0.2], "attack": 0.004, "decay": 3.0, "gain": 0.34}},
			{"at": 0.18, "dur": 0.3, "spec": {"freq": 659.25, "harm": [1.0, 0.4, 0.2], "attack": 0.004, "decay": 3.0, "gain": 0.34}},
			{"at": 0.27, "dur": 0.33, "spec": {"freq": 880.0, "harm": [1.0, 0.45, 0.22], "attack": 0.004, "decay": 2.6, "gain": 0.36}},
		])
	)

static func purchase() -> AudioStreamWAV:
	return _cached(CUE_PURCHASE, func() -> AudioStreamWAV:
		return _layer(0.2, 3803, [
			{"at": 0.0, "dur": 0.09, "spec": {"freq": 1568.0, "harm": [1.0, 0.3], "attack": 0.002, "decay": 4.0, "gain": 0.3}},
			{"at": 0.06, "dur": 0.14, "spec": {"freq": 2093.0, "harm": [1.0, 0.3], "attack": 0.002, "decay": 4.0, "gain": 0.26}},
		])
	)

static func buff_taken() -> AudioStreamWAV:
	return _cached(CUE_BUFF_TAKEN, func() -> AudioStreamWAV:
		return _synth(0.4, 3907, {"from": 600.0, "to": 1200.0, "harm": [1.0, 0.4], "trem": 14.0, "trem_depth": 0.4, "attack": 0.01, "decay": 2.2, "gain": 0.4})
	)

static func spirit_down() -> AudioStreamWAV:
	return _cached(CUE_SPIRIT_DOWN, func() -> AudioStreamWAV:
		return _synth(0.32, 4001, {"from": 1200.0, "to": 300.0, "curve": 0.5, "harm": [], "noise": 0.55, "noise_decay": 9.0, "decay": 2.6, "gain": 0.42})
	)

# 号角：第 1 波与每 3 波一次，提醒「兵线动了」。
static func wave_horn() -> AudioStreamWAV:
	return _cached(CUE_WAVE_HORN, func() -> AudioStreamWAV:
		return _synth(0.9, 4103, {"freq": 155.0, "harm": [1.0, 0.55, 0.3, 0.15], "attack": 0.08, "sustain": 0.55, "decay": 1.1, "trem": 5.0, "trem_depth": 0.3, "gain": 0.44})
	)

# 主堡陷落：最重的一记。之后由导演层接胜利/失败音乐。
static func base_fall() -> AudioStreamWAV:
	return _cached(CUE_BASE_FALL, func() -> AudioStreamWAV:
		return _synth(2.2, 4201, {"from": 62.0, "to": 26.0, "curve": 1.4, "harm": [1.0, 0.5], "noise": 0.5, "noise_decay": 1.2, "decay": 1.5, "gain": 0.9})
	)

static func respawn() -> AudioStreamWAV:
	return _cached(CUE_RESPAWN, func() -> AudioStreamWAV:
		return _synth(0.55, 4307, {"from": 300.0, "to": 900.0, "harm": [1.0, 0.35], "attack": 0.03, "decay": 2.0, "gain": 0.4})
	)

# ---------------- 战斗内提示 ----------------

# 技能按不出来（CD / 蓝不够）：两声闷 blip，语义是「不行」。
static func denied() -> AudioStreamWAV:
	return _cached(CUE_DENIED, func() -> AudioStreamWAV:
		return _layer(0.2, 4409, [
			{"at": 0.0, "dur": 0.06, "spec": {"freq": 220.0, "harm": [1.0, 0.5], "attack": 0.002, "decay": 3.0, "gain": 0.26}},
			{"at": 0.08, "dur": 0.06, "spec": {"freq": 196.0, "harm": [1.0, 0.5], "attack": 0.002, "decay": 3.0, "gain": 0.26}},
		])
	)

# 残血心跳：两下闷鼓，间隔 0.18s，和真实心跳同节奏。
static func low_hp() -> AudioStreamWAV:
	return _cached(CUE_LOW_HP, func() -> AudioStreamWAV:
		return _layer(0.42, 4507, [
			{"at": 0.0, "dur": 0.14, "spec": {"from": 92.0, "to": 52.0, "curve": 1.5, "harm": [1.0, 0.4], "attack": 0.004, "decay": 3.0, "gain": 0.62}},
			{"at": 0.18, "dur": 0.14, "spec": {"from": 78.0, "to": 44.0, "curve": 1.5, "harm": [1.0, 0.4], "attack": 0.004, "decay": 3.0, "gain": 0.44}},
		])
	)

static func tower_shot() -> AudioStreamWAV:
	return _cached(CUE_TOWER_SHOT, func() -> AudioStreamWAV:
		return _synth(0.22, 4603, {"from": 900.0, "to": 300.0, "harm": [1.0, 0.3], "noise": 0.26, "noise_decay": 20.0, "decay": 2.8, "gain": 0.4})
	)

# ---------------- UI ----------------

static func ui_click() -> AudioStreamWAV:
	return _cached(CUE_UI_CLICK, func() -> AudioStreamWAV:
		return _synth(0.05, 4703, {"freq": 1200.0, "harm": [1.0, 0.3], "attack": 0.001, "decay": 3.2, "gain": 0.26})
	)

static func ui_confirm() -> AudioStreamWAV:
	return _cached(CUE_UI_CONFIRM, func() -> AudioStreamWAV:
		return _layer(0.22, 4801, [
			{"at": 0.0, "dur": 0.08, "spec": {"freq": 660.0, "harm": [1.0, 0.35], "attack": 0.002, "decay": 3.0, "gain": 0.28}},
			{"at": 0.07, "dur": 0.15, "spec": {"freq": 990.0, "harm": [1.0, 0.35], "attack": 0.002, "decay": 3.0, "gain": 0.3}},
		])
	)

static func ui_back() -> AudioStreamWAV:
	return _cached(CUE_UI_BACK, func() -> AudioStreamWAV:
		return _layer(0.2, 4903, [
			{"at": 0.0, "dur": 0.08, "spec": {"freq": 700.0, "harm": [1.0, 0.35], "attack": 0.002, "decay": 3.0, "gain": 0.26}},
			{"at": 0.06, "dur": 0.14, "spec": {"freq": 520.0, "harm": [1.0, 0.35], "attack": 0.002, "decay": 3.0, "gain": 0.26}},
		])
	)

static func ui_error() -> AudioStreamWAV:
	return _cached(CUE_UI_ERROR, func() -> AudioStreamWAV:
		return _synth(0.22, 5003, {"freq": 180.0, "harm": [1.0, 0.6, 0.35], "trem": 30.0, "trem_depth": 0.5, "attack": 0.004, "decay": 2.0, "gain": 0.3})
	)

# ---------------- spec 合成底层 ----------------

# 一段音符的波形（不带其它音符）。常用参数见 _add_to_buffer 的注释。
static func _synth(duration: float, seed_value: int, spec: Dictionary) -> AudioStreamWAV:
	return _layer(duration, seed_value, [{"at": 0.0, "dur": duration, "spec": spec}])

# 多个音符叠在一条缓冲里（琶音、双音、心跳）。
static func _layer(duration: float, seed_value: int, notes: Array) -> AudioStreamWAV:
	var count := maxi(int(duration * SAMPLE_RATE), 2)
	var buf := PackedFloat32Array()
	buf.resize(count)
	for index in notes.size():
		var note: Dictionary = notes[index]
		var spec: Dictionary = (note.get("spec", {}) as Dictionary).duplicate()
		if not spec.has("seed"):
			spec["seed"] = seed_value + index * 37
		_add_to_buffer(buf, float(note.get("at", 0.0)), float(note.get("dur", duration)), spec)
	var data := PackedByteArray()
	data.resize(count * 2)
	# 软限幅：几层音叠在一起很容易顶到 1.0，硬 clamp 会变成削波失真（听感是「破」）。
	# 只在这条 cue 真的顶到天花板时才整体缩一点，平时不动，避免把安静的音效抬响。
	var peak := 0.0
	for value in buf:
		peak = maxf(peak, absf(value))
	var scale := 1.0
	if peak > 0.92:
		scale = 0.9 / peak
	for i in count:
		data.encode_s16(i * 2, int(clampf(buf[i] * scale, -1.0, 1.0) * 32767.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = SAMPLE_RATE
	stream.stereo = false
	stream.data = data
	return stream

# spec:
#   freq / from / to   音高（只给 freq 就是定音，from+to 是滑音）
#   curve              滑音曲线指数
#   harm               谐波振幅（[] = 纯噪声）
#   noise / noise_decay   噪声量与衰减
#   attack / decay / sustain  包络（秒 / 指数 / 尾音电平）
#   trem / trem_depth  颤音
#   gain / seed        音量与随机种子
static func _add_to_buffer(buf: PackedFloat32Array, at: float, duration: float, spec: Dictionary) -> void:
	var total := buf.size()
	var start := int(round(at * SAMPLE_RATE))
	var count := maxi(int(duration * SAMPLE_RATE), 1)
	var f0 := float(spec.get("freq", spec.get("from", 440.0)))
	var f1 := float(spec.get("to", f0))
	var curve := float(spec.get("curve", 1.0))
	var harm: Array = spec.get("harm", [1.0])
	var noise_amount := float(spec.get("noise", 0.0))
	var noise_decay := float(spec.get("noise_decay", 10.0))
	var attack := maxf(float(spec.get("attack", 0.004)), 0.0005)
	var decay := float(spec.get("decay", 2.0))
	var sustain := float(spec.get("sustain", 0.0))
	var gain := float(spec.get("gain", 0.4))
	var trem := float(spec.get("trem", 0.0))
	var trem_depth := float(spec.get("trem_depth", 0.0))
	var rng := RandomNumberGenerator.new()
	rng.seed = int(spec.get("seed", 1)) * 31 + start
	var phase := 0.0
	var last := float(maxi(count - 1, 1))
	for i in count:
		var index := start + i
		if index >= total:
			break
		var t := float(i) / last
		var freq := lerpf(f0, f1, pow(t, curve))
		phase += TAU * freq / SAMPLE_RATE
		var tone := 0.0
		for h in harm.size():
			tone += sin(phase * float(h + 1)) * float(harm[h])
		var envelope := minf(t * duration / attack, 1.0) * (sustain + (1.0 - sustain) * pow(1.0 - t, decay))
		if trem > 0.0:
			envelope *= 1.0 - trem_depth * 0.5 * (1.0 - sin(TAU * trem * t * duration))
		var sample := tone
		if noise_amount > 0.0:
			sample += rng.randf_range(-1.0, 1.0) * noise_amount * exp(-t * duration * noise_decay)
		buf[index] += sample * envelope * gain

# ---------------- 合成底层 ----------------

# sample_fn(t: 0..1 归一化时间, rng, state: 跨采样保持的相位等) -> -1..1 的样本值。
static func _render(duration: float, seed_value: int, sample_fn: Callable) -> AudioStreamWAV:
	var count := maxi(int(duration * SAMPLE_RATE), 2)
	var data := PackedByteArray()
	data.resize(count * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var state := {"phase": 0.0}
	for i in count:
		var t := float(i) / float(count - 1)
		var value: float = sample_fn.call(t, rng, state)
		data.encode_s16(i * 2, int(clampf(value, -1.0, 1.0) * 32767.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = SAMPLE_RATE
	stream.stereo = false
	stream.data = data
	return stream

static func _cached(key: String, builder: Callable) -> AudioStreamWAV:
	if _cache.has(key):
		return _cache[key]
	var stream: AudioStreamWAV = builder.call()
	_cache[key] = stream
	return stream

static func _sweep(duration: float, from_hz: float, to_hz: float, noise_amount: float, gain: float, seed_value: int) -> AudioStreamWAV:
	var count := int(duration * SAMPLE_RATE)
	var data := PackedByteArray()
	data.resize(count * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var phase := 0.0
	for i in count:
		var t := float(i) / maxf(float(count - 1), 1.0)
		var frequency := lerpf(from_hz, to_hz, t)
		phase += TAU * frequency / SAMPLE_RATE
		var attack := minf(t * 14.0, 1.0)
		var envelope := attack * pow(1.0 - t, 1.5)
		var noise := rng.randf_range(-1.0, 1.0) * noise_amount
		var sample := (sin(phase) + noise) * envelope * gain
		data.encode_s16(i * 2, int(clampf(sample, -1.0, 1.0) * 32767.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = SAMPLE_RATE
	stream.stereo = false
	stream.data = data
	return stream
