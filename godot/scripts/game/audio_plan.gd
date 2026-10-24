extends RefCounted

# 战斗事件 → 音效 cue 的**纯逻辑**层（无节点、无引擎音频 API，可 --headless 直测）。
#
# 为什么要拆出这一层：
#   1) `scripts/game/audio_director.gd` 是 Node，测试里不能进树，逻辑放那儿就测不到；
#   2) 「什么事件该响什么音」是规则，不是渲染，规则要能被断言钉住；
#   3) 节流（冷却 + 单帧上限）决定了团战会不会糊成噪音，这是可量化的。
#
# 三条规则：
#   - 距离衰减：贴身 0dB，40 米外直接丢弃（不占声道）。自己身上的事不衰减。
#   - 同名冷却：小兵命中 0.10s、英雄命中 0.06s…… 防止一帧几十次叠成爆音。
#   - 单帧上限：MAX_CUES_PER_FRAME。团战一帧最多这么多个声音，多出来的这一帧不响。
#
# 热度（heat）：近处交战行为累加，停手后衰减。驱动战斗 BGM 的强度层音量，
# 所以它统计的是**事件**而不是「真的放出来的声音」——被节流掉的那次交手照样算数。

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

# 本层能发出的全部 cue。测试会逐条核实「AudioCues 真的合成得出来」，
# 少一条就是静默失效（事件来了，没声音，不报错）。
const CUES := [
	CUE_ATTACK_SWING, CUE_HIT_HERO, CUE_HIT_MINION, CUE_HIT_STRUCTURE, CUE_CRIT,
	CUE_SKILL_BLADE, CUE_SKILL_TANK, CUE_SKILL_MAGE, CUE_SKILL_ARCHER, CUE_SKILL_ULT,
	CUE_DEATH_HERO, CUE_DEATH_MINION, CUE_TOWER_DOWN, CUE_GUARD_DOWN, CUE_SHIELD_BREAK,
	CUE_LEVEL_UP, CUE_PURCHASE, CUE_OBJECTIVE_DOWN, CUE_BUFF_TAKEN, CUE_SPIRIT_DOWN,
	CUE_WAVE_HORN, CUE_BASE_FALL, CUE_RESPAWN, CUE_DENIED, CUE_LOW_HP, CUE_TOWER_SHOT,
]

# 贴身半径：这个距离内不衰减。比英雄碰撞半径大得多，但远小于技能射程。
const EARSHOT := 6.0
# 超过这个距离的事件直接丢掉，连声道都不占。
const FAR_LIMIT := 40.0
# 最远衰减量（dB）。40 米时正好到 -22，再远就是丢弃。
const FAR_ATTENUATION := -22.0
# 低于这个增益的 cue 直接不出声（省声道，也避免几十个极轻的声音叠成底噪）。
const SILENT_DB := -40.0
# 一帧最多发几个声音。5v5 团战一帧能有 20+ 个事件，全放就是噪音墙。
const MAX_CUES_PER_FRAME := 6
# 单次交手给热度加多少。约 5 次交手把强度层推到顶。
const HEAT_GAIN := 0.22
# 热度每秒衰减。停手 3 秒基本归零，音乐回落。
const HEAT_DECAY := 0.35
# 残血心跳的触发阈值与最小间隔。
const LOW_HP_RATIO := 0.28
const LOW_HP_COOLDOWN := 1.4

const DEFAULT_COOLDOWN := 0.03
# 同名 cue 的最小间隔（秒）。越「吵」的音隔得越久。
const COOLDOWN := {
	"attack_swing": 0.05,
	"hit_hero": 0.06,
	"hit_minion": 0.10,
	"hit_structure": 0.14,
	"crit": 0.12,
	"death_hero": 0.20,
	"death_minion": 0.18,
	"tower_shot": 0.30,
	"low_hp": LOW_HP_COOLDOWN,
	"wave_horn": 2.0,
	"purchase": 0.12,
}

var _now := 0.0
var _frame_budget := MAX_CUES_PER_FRAME
var _last_play := {}
var _heat := 0.0
var _low_hp_cd := 0.0

# 每帧开头调用一次：推进时钟、重置单帧预算、衰减热度、顺手判定残血心跳。
# 返回本帧的「心跳」类 cue（事件驱动的 cue 走 cues_for）。
func begin_frame(delta: float, ctx: Dictionary = {}) -> Array:
	var step := maxf(delta, 0.0)
	_now += step
	_frame_budget = MAX_CUES_PER_FRAME
	_heat = maxf(_heat - HEAT_DECAY * step, 0.0)
	_low_hp_cd = maxf(_low_hp_cd - step, 0.0)
	var out := []
	# 死人不响心跳：否则死亡遮罩那几秒会一直「咚咚」。
	if float(ctx.get("hp_ratio", 1.0)) < LOW_HP_RATIO and _low_hp_cd <= 0.0:
		if _admit(CUE_LOW_HP):
			_low_hp_cd = LOW_HP_COOLDOWN
			out.append(_make(CUE_LOW_HP, 0.0))
	return out

func cues_for(event: Dictionary, ctx: Dictionary) -> Array:
	var out := []
	var kind := str(event.get("type", ""))
	var local_id := int(ctx.get("local", -1))
	match kind:
		"attack":
			var is_local := int(event.get("hero", -1)) == local_id
			_push(out, CUE_ATTACK_SWING, 0.0 if is_local else _distance_gain(event, ctx))
			if bool(event.get("crit", false)):
				# 暴击是叠在挥砍之上的第二层，不是替换：听感上是「砍 + 金属炸裂」。
				_push(out, CUE_CRIT, 0.0 if is_local else _distance_gain(event, ctx), -1.5)
		"hit":
			var victim_local := int(event.get("target", -1)) == local_id
			var gain := 2.0 if victim_local else _distance_gain(event, ctx)
			var target_type := str(event.get("target_type", ""))
			var cue := CUE_HIT_STRUCTURE
			if target_type == "hero":
				cue = CUE_HIT_HERO
			elif target_type == "minion" or target_type == "monster":
				cue = CUE_HIT_MINION
			_push(out, cue, gain)
		"skill":
			var slot := str(event.get("slot", "q"))
			var cue := CUE_SKILL_MAGE
			var hero_type := str(event.get("hero_type", "blade"))
			if slot == "r":
				cue = CUE_SKILL_ULT
			elif hero_type == "tank":
				cue = CUE_SKILL_TANK
			elif hero_type == "archer":
				cue = CUE_SKILL_ARCHER
			elif hero_type == "assassin":
				cue = CUE_SKILL_ASSASSIN
			elif hero_type == "blade":
				cue = CUE_SKILL_BLADE
			# 未知英雄类型回落到法师音：宁可音色不准，也不能静默无声。
			_push(out, cue, 0.0 if int(event.get("hero", -1)) == local_id else _distance_gain(event, ctx))
		"death":
			var entity_type := str(event.get("entity_type", "minion"))
			if entity_type == "hero":
				var victim_is_local := int(event.get("hero", -1)) == local_id
				_push(out, CUE_DEATH_HERO, 2.0 if victim_is_local else _distance_gain(event, ctx))
			else:
				_push(out, CUE_DEATH_MINION, _distance_gain(event, ctx))
		"tower_destroyed":
			_push(out, CUE_TOWER_DOWN, _distance_gain(event, ctx), -4.0)
		"guard_destroyed":
			_push(out, CUE_GUARD_DOWN, _distance_gain(event, ctx), -4.0)
		"crystal_shield_broken":
			_push(out, CUE_SHIELD_BREAK, _distance_gain(event, ctx), -6.0)
		"objective_killed":
			_push(out, CUE_OBJECTIVE_DOWN, _distance_gain(event, ctx), -4.0)
		"buff_taken":
			_push(out, CUE_BUFF_TAKEN, _distance_gain(event, ctx))
		"river_spirit_killed":
			_push(out, CUE_SPIRIT_DOWN, _distance_gain(event, ctx))
		"structure_attack":
			_push(out, CUE_TOWER_SHOT, _distance_gain(event, ctx))
		"level_up":
			if int(event.get("hero", -1)) == local_id:
				_push(out, CUE_LEVEL_UP, 0.0)
		"purchase", "sold":
			# 队友买东西不该吵到我，只有自己的钱包有声音。
			if int(event.get("hero", -1)) == local_id:
				_push(out, CUE_PURCHASE, 0.0)
		"respawn":
			if int(event.get("hero", -1)) == local_id:
				_push(out, CUE_RESPAWN, 0.0)
		"wave":
			# 和 HUD 播报同一条规则：第 1 波与每 3 波吹一次号角，否则太吵。
			var wave := int(event.get("wave", 1))
			if wave == 1 or wave % 3 == 0:
				_push(out, CUE_WAVE_HORN, 0.0, -8.0)
		"match_end":
			# 全局事件：主堡倒了，全场都该听到。距离衰减只在极远时削一点。
			_push(out, CUE_BASE_FALL, 0.0, -2.0)
	return out

func heat() -> float:
	return _heat

func reset() -> void:
	_now = 0.0
	_frame_budget = MAX_CUES_PER_FRAME
	_last_play.clear()
	_heat = 0.0
	_low_hp_cd = 0.0

# 距离 → 增益（dB）。贴身 0，越远越轻，超出 FAR_LIMIT 视为听不见。
static func gain_for_distance(distance: float) -> float:
	if distance <= EARSHOT:
		return 0.0
	if distance >= FAR_LIMIT:
		return FAR_ATTENUATION - 20.0
	var ratio := (distance - EARSHOT) / (FAR_LIMIT - EARSHOT)
	return FAR_ATTENUATION * clampf(ratio, 0.0, 1.0)

func _distance_gain(event: Dictionary, ctx: Dictionary) -> float:
	var dx := float(event.get("x", 0.0)) - float(ctx.get("x", 0.0))
	var dy := float(event.get("y", 0.0)) - float(ctx.get("y", 0.0))
	return gain_for_distance(sqrt(dx * dx + dy * dy))

func _push(out: Array, cue: String, gain_db: float, bias_db := 0.0) -> void:
	var gain := gain_db + bias_db
	if gain <= SILENT_DB:
		return
	# 热度统计的是「发生了一次交手」，与有没有真的放出声音无关：
	# 被节流掉的那次也是战斗，音乐不该因此掉下来。
	if gain > -6.0:
		_heat = minf(_heat + HEAT_GAIN, 1.0)
	if not _admit(cue):
		return
	out.append(_make(cue, gain))

func _make(cue: String, gain_db: float) -> Dictionary:
	return {"cue": cue, "gain_db": gain_db}

func _admit(cue: String) -> bool:
	if _frame_budget <= 0:
		return false
	var cooldown := float(COOLDOWN.get(cue, DEFAULT_COOLDOWN))
	if _now - float(_last_play.get(cue, -1000.0)) < cooldown:
		return false
	_last_play[cue] = _now
	_frame_budget -= 1
	return true
