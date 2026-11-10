extends RefCounted

const MapData = preload("res://sim/map_data.gd")
const HeroDefs = preload("res://sim/hero_defs.gd")
const SkillSystem = preload("res://sim/skill_system.gd")
const ProjectileSystem = preload("res://sim/projectile_system.gd")
const ControlRules = preload("res://sim/control_rules.gd")
const TargetingRules = preload("res://sim/targeting_rules.gd")
const EconomySystem = preload("res://sim/economy_system.gd")
const ItemShop = preload("res://sim/item_shop.gd")
const CombatAnnouncer = preload("res://sim/combat_announcer.gd")
const MapLayout = preload("res://sim/map/map_layout.gd")
const Collision = preload("res://sim/map/collision.gd")
const Vision = preload("res://sim/map/vision.gd")
const TowerRules = preload("res://sim/map/tower_rules.gd")
const WaveRules = preload("res://sim/map/wave_rules.gd")
const Jungle = preload("res://sim/map/jungle.gd")
const Objectives = preload("res://sim/map/objectives.gd")
const RecallRules = preload("res://sim/map/recall.gd")
const Crystal = preload("res://sim/map/crystal.gd")
const River = preload("res://sim/map/river.gd")
const Teleport = preload("res://sim/map/teleport.gd")

const TICK_RATE := 30.0

# 路径跟随的"卡死"恢复参数（项 6b）。
# 背景：实体沿 waypoint 前进，但碰撞系统会把被墙挡住的位移吃掉大半，
# 而"到点"判定要求距离 < 0.9m。一旦实体钻进野区围墙，它每 tick 只挪一点点，
# 永远到不了点、path_index 也不前进 —— 实测蓝方射手这样卡了 6 分钟、CS 停在 4。
# RESYNC_DISTANCE：当前 waypoint 离得远到这个程度，说明索引已经脱节，直接重吸附。
const RESYNC_DISTANCE := 12.0
# 实际位移低于应走距离的这个比例，即视为"被挡住"。
const STUCK_PROGRESS_RATIO := 0.5
# 连续卡住这么多 tick（约 1 秒）就重吸附一次。
const STUCK_TICKS_LIMIT := 30

# bot 兵线纪律（项 6b）：离自家兵线路径超过这个垂直距离就算"脱线"。
# 取值参考：兵线宽度约 6m，英雄攻速射程 6.4m，留一倍余量到 12m。
# 脱线后不再追敌方英雄（但清理小兵/塔不受限）。
const BOT_LEASH_RADIUS := 12.0

# 小兵起步点距自家基地端点的弧长（项 6b）。
# 必须按**弧长**取而不是按索引取：边路是螺旋线，两侧同一索引的实际距离不等，
# 会导致一侧小兵每波先接触、长期累积成稳定的对局偏向。
const MINION_SPAWN_OFFSET := 12.0

# 小兵起步点占路径总长的比例（项 6b）。
# 用比例而非弧长：边路首段 12.649m、末段 8.944m 不等长，
# 按弧长从两端各走 12m 落到相差 21.4m 的两个位置。
# 12/190 ≈ 0.063，与原来的"离基地 12m"意图一致。
const MINION_SPAWN_PROGRESS := 0.063

# 点对称 (x,y) -> (-x,-y) 下的路名映射（项 6b）。
# 实测依据：top 上每点的镜像到 bottom 最近点最大距离 4.0m（纯采样偏移），
# 而 top 映射到自身时偏差 134m。mid 在对称轴上，自映射。
const LANE_MIRROR := {"mid": "mid", "top": "bottom", "bottom": "top"}

# 英雄沿路径起步的弧长（项 6b）。与小兵同理：必须按弧长而非索引，
# 否则边路两侧的实际起步距离不等（实测 12.65m vs 8.94m）。
const HERO_PATH_ENTRY_ARC := 12.0

## 选起步路径点：**取离实体最近的路径点**（沿前进方向略微前移一格避开抖动）。
##
## 为什么不再用"固定弧长阈值"：边路相邻路径点间距从 8.94m 到 16.0m 不等，
## 固定阈值 12m 会落进不同的离散点 —— 实测蓝方刺客落在 idx=1（距自身 4.52m），
## 红方落在 idx=12（距自身 29.55m），两者到各自第一个 waypoint 的距离差 25m，
## 这直接决定了谁先接触、谁先补刀。
##
## 用最近点就天然对称：两侧实体到自家端点的距离本来就相同（出生点严格点对称），
## 所以"最近的路径点"也是对称的。
## 按**路径总长比例**取点（项 6b）。progress=0 是 path[0]，=1 是末端。
## from_head=true 从头部量，false 从末端量（即 1-progress）。
##
## 为什么用"比例"而不是"弧长"：边路的首段与末段长度不等（12.649m vs 8.944m），
## 两侧各沿弧长走同一距离，落到的位置相差 21.4m。而地图是点对称的，
## 镜像会把 progress ↔ 1-progress 对调，所以**同名 progress 从两端量**
## 天然落到镜像位置上。
static func _point_at_progress(path: Array, progress: float, from_head: bool) -> Vector2:
	if path.is_empty():
		return Vector2.ZERO
	if path.size() == 1:
		return path[0]
	var total := 0.0
	for i in range(1, path.size()):
		total += (path[i] as Vector2).distance_to(path[i - 1])
	if total < 0.0001:
		return path[0]
	var frac := clampf(progress, 0.0, 1.0)
	return _point_at_arc(path, total * frac, from_head)

## 沿路径累计弧长取点（项 6b）。from_head=true 从 path[0] 量，false 从末端量。
##
## 与小兵/英雄起步点配套：这样取出的点**严格落在路径上**，
## 而"基地 + 前进单位向量 × 距离"会因边路一出基地就拐弯而偏离路径，
## 两侧偏离量不同（实测 25.70 vs 21.75）。
static func _point_at_arc(path: Array, arc: float, from_head: bool) -> Vector2:
	if path.is_empty():
		return Vector2.ZERO
	if path.size() == 1:
		return path[0]
	var remaining := maxf(arc, 0.0)
	var order: Array = []
	if from_head:
		for i in range(1, path.size()):
			order.append([i - 1, i])
	else:
		for i in range(path.size() - 1, 0, -1):
			order.append([i, i - 1])
	for seg in order:
		var a: Vector2 = path[int(seg[0])]
		var b: Vector2 = path[int(seg[1])]
		var len := a.distance_to(b)
		if remaining <= len or len < 0.0001:
			var t := 0.0 if len < 0.0001 else clampf(remaining / len, 0.0, 1.0)
			return a.lerp(b, t)
		remaining -= len
	return path[0] if from_head else path[path.size() - 1]

## 沿路径从自家端点出发的前进单位向量（蓝方从头、红方从尾）。
## 小兵起步点用它把"离基地 12m"折算成一个落点，再问最近路径点。
static func _forward_unit(path: Array, from_head: bool) -> Vector2:
	if path.size() < 2:
		return Vector2.UP
	var a: Vector2 = path[0] if from_head else path[path.size() - 1]
	var b: Vector2 = path[1] if from_head else path[path.size() - 2]
	var d := b - a
	return d.normalized() if d.length() > 0.001 else Vector2.UP

func _index_for_arc(path: Array, entity_pos: Vector2, from_head: bool) -> int:
	if path.size() < 2:
		return 0
	var best := -1
	var best_dist := INF
	for i in path.size():
		var d: float = entity_pos.distance_to(path[i])
		if d < best_dist:
			best_dist = d
			best = i
	if best < 0:
		return 0
	# 往前进一格：避免"刚起步就判定已到点"在原地抖动。
	# 只前移、不回退（与 _resync_path_index 同一条纪律）。
	#
	# from_head 表示"沿正序方向前进"，所以两个分支都是 **+1**：
	#   - 蓝方走原路径正序     -> 索引递增
	#   - 红方走镜像路正序     -> 同样递增（镜像路起点已在红方侧）
	#   - 红方走原路径（mid）  -> 反向，用 -1
	# 旧实现把 from_head 直接当成方向，导致镜像路上红方被选到路径末端。
	var forward := 1 if from_head else -1
	var next := best + forward
	if next >= 0 and next < path.size():
		best = next
	return best
const HERO_RESPAWN_BASE := 6.0
const WAVE_INTERVAL := 18.0
const FIRST_WAVE_DELAY := 1.0
const MINION_AGGRO_RANGE := 5.5
const STRUCTURE_RANGE := 8.0
const BASE_RANGE := 9.0
const MAX_LEVEL := HeroDefs.MAX_LEVEL
# --- 技能等级化（项 2，差距文档 §3.2）-------------------------------------
# 规则常量的真身在 HeroDefs（sim 与 net_protocol 都 preload 它，两边引用同一组），
# 这里只做别名，方便 sim 内部读起来顺手。绝不在这两处各写一个数字。
# Q/W/E 出生 1 级、上限 6 级；R 出生 0 级 = 未学习、上限 3 级。
# 用 0 而不是"1 级但锁住"：后者会出现「等级 1 却放不出来」的歧义状态，
# 伤害公式 damage_grow * (level - 1) 还要额外解释一次。
const MAX_SKILL_LEVEL_NORMAL := HeroDefs.MAX_SKILL_LEVEL_NORMAL
const MAX_SKILL_LEVEL_ULT := HeroDefs.MAX_SKILL_LEVEL_ULT
# 大招三档的学习门槛（对标王者 4/7/10）。索引 = 目标等级 - 1。
const ULT_UNLOCK_LEVELS := HeroDefs.ULT_UNLOCK_LEVELS
const SKILL_SLOTS := HeroDefs.SKILL_SLOTS
# 助攻判定窗口：和击杀归属用的是同一个 10 秒口径（见 _kill_entity 的分支 2），
# 两处不一致会出现「算他击杀、却不给旁边那个一起打的人助攻」。
const ASSIST_WINDOW := 10.0

const TOWER_HP := {"outer": 2800.0, "inner": 3200.0, "high": 3600.0}
const TOWER_DAMAGE := {"outer": 150.0, "inner": 170.0, "high": 190.0}

# 野外脱战回血（每秒 % 最大生命）与基础回蓝
const FIELD_HP_REGEN := 0.025
const FIELD_MP_REGEN := 6.0
# 小兵 / 野怪（非主宰暴君）打英雄时的伤害系数。
# 为什么只对英雄打折、不去改 wave_rules / jungle 的原始攻击力：
# 那一改会连带把小兵互殴的清兵速度、小兵推塔速度一起压低，兵线节奏会整条崩掉。
# 英雄血池抬到 1.2 倍之后，这个系数把「一波兵 8 秒打死 1 级英雄」拉回到 15 秒以上。
const PVE_HERO_DAMAGE_SCALE := 0.62
# 出手或受击后脱离草丛隐身的显形时长（秒）。
const REVEAL_AFTER_COMBAT := 1.5
# 泉水恢复速率（每秒 % 最大生命 / 法力）。约 5 秒回满，
# 比野外脱战回血快 7 倍，且不需要等 8 秒脱战计时。
const FOUNTAIN_HP_RATE := 0.18
const FOUNTAIN_MP_RATE := 0.15

# --- 战斗属性（项 1，差距文档 §3.1）--------------------------------------
# 减伤公式：有效伤害 = raw * K / (K + resist)。resist = K 时恰好减半。
# K 定在 100：与王者口径一致，护甲 100 免 50%。resist=0 时乘子恒等 1.0，
# 因此小兵 / 塔 / 旧实体的伤害逐位不变（survivability 里锚死的 near 靠这条不红）。
const MATCH_MITIGATION_K := 100.0
# 冷却缩减上限 40%（对标王者），与蓝 buff（×0.8）叠乘。
const CDR_CAP := 0.4
# 攻速加成上限（+250%），防止极端叠攻速把普攻间隔压成 0。
const ATTACK_SPEED_CAP := 2.5

# 有效普攻间隔 = 基础间隔 / (1 + 攻速加成)。缺字段（小兵/塔/野怪/旧实体）恒等原值。
static func hero_attack_interval(unit: Dictionary) -> float:
	var base := float(unit.get("attack_interval", 1.0))
	if base <= 0.0:
		return base
	var bonus := float(unit.get("attack_speed", 0.0))
	if float(unit.get("passive_as_timer", 0.0)) > 0.0:
		bonus += float(unit.get("passive_as_bonus", 0.0))
	bonus = clampf(bonus, 0.0, ATTACK_SPEED_CAP)
	return base / (1.0 + bonus)

# 技能冷却最终系数 = 蓝buff缩放 ×(1 - 钳制后的 CDR)。实例方法，SkillSystem 通过 sim 调用。
func hero_cooldown_scale(hero: Dictionary) -> float:
	var cdr := clampf(float(hero.get("cooldown_reduction", 0.0)), 0.0, CDR_CAP)
	return Jungle.cooldown_scale(hero) * (1.0 - cdr)

const SPAWN_OFFSETS := [0.0, -22.0, 22.0, -44.0, 44.0]

var config: Dictionary
var mode: String
var state: Dictionary
var ended := false
var inputs: Dictionary = {}
var kill_log: Array[Dictionary] = []
var _announcer := CombatAnnouncer.new()
# 固定种子的线性同余，保证暴击判定在主机模拟里可复现，也不依赖引擎随机源。
# config 可用 "seed" 改初始值（项 6 的多 seed 抽样要用）。默认值保持不变，
# 所以不传 seed 的对局逐位等于历史行为 —— 既有测试的数值断言因此不受影响。
const DEFAULT_RNG_SEED := 0x2F6E2B1
var _rng_state := DEFAULT_RNG_SEED

func _init(match_config: Dictionary) -> void:
	config = match_config.duplicate(true)
	mode = str(config.get("mode", "duel"))
	# 项 6：允许按 seed 做多样本抽样。值必须落在 LCG 的正整数域里，
	# 否则 0 会让所有随机数退化成同一个常数（暴击永远不触发/永远触发）。
	var raw_seed := int(config.get("seed", DEFAULT_RNG_SEED))
	_rng_state = raw_seed & 0x7FFFFFFF
	if _rng_state == 0:
		_rng_state = DEFAULT_RNG_SEED
	if mode != "team":
		mode = "duel"
	state = {
		"time": 0.0,
		"bounds": MapData.BOUNDS,
		"winner": "",
		"mode": mode,
		"entities": [],
		"events": [],
		"next_id": 1,
		"wave": 0,
		"wave_timer": FIRST_WAVE_DELAY,
		"scores": {
			"blue": {"kills": 0, "towers": 0},
			"red": {"kills": 0, "towers": 0},
		},
		"objective": {"spawn_timer": Objectives.FIRST_SPAWN, "spawned": false},
		"objectives": {"buffs": {"blue": 0.0, "red": 0.0}},
		"river": River.initial_state(),
		"bot_ai": bool(config.get("bot_ai", false)),
	}
	_setup_teams()
	_setup_structures()
	_setup_jungle()
	_update_wave(FIRST_WAVE_DELAY)

func _next_id() -> int:
	var id: int = int(state.next_id)
	state.next_id = id + 1
	return id

func _emit(event_type: String, data: Dictionary = {}) -> void:
	var event := {"type": event_type}
	for key in data:
		event[key] = data[key]
	state.events.append(event)

## 发射一枚投射物（项 3）。由 SkillSystem 在施放远程技能时调用。
##
## 为什么把"建实体"放在 sim 而不是 skill_system：id 分配、实体列表、tick 推进
## 都是 sim 的职责；skill_system 是 static 工具，拿不到 next_id，硬塞会破坏分层。
func spawn_projectile(owner: Dictionary, slot: String, kind: String, aim: Vector2,
		damage: float, dtype: String, aoe_radius: float, slow_sec: float, speed := 0.0) -> Dictionary:
	var proj := ProjectileSystem.build(owner, slot, kind, aim, damage, dtype, aoe_radius, slow_sec, speed)
	proj["id"] = int(state.next_id)
	state.next_id = int(state.next_id) + 1
	state.entities.append(proj)
	# 表现层要靠这条事件立即出施法动作（而不是等命中）；命中另有 projectile_hit。
	_emit("projectile_spawned", {
		"id": int(proj.id),
		"team": str(proj.team),
		"owner_id": proj.get("owner_id", 0),
		"kind": kind,
		"slot": slot,
		"x": float((proj.origin as Vector2).x),
		"y": float((proj.origin as Vector2).y),
		"aim_x": float(aim.x),
		"aim_y": float(aim.y),
	})
	return proj

## 推进投射物并结算命中（项 3）。
## 伤害仍然走 _damage —— 护甲/魔抗/减伤/暴击只有一份实现，弹道不复制它。
func _update_projectiles(dt: float) -> void:
	var hits := ProjectileSystem.tick(state.entities, dt)
	for hit in hits:
		var proj: Dictionary = hit.get("projectile", {})
		# source 必须是**真实的施法者实体**，不能手工拼一个字典冒充。
		# 原因：_damage → _kill_entity → _add_xp 会读 source.alive / source.level /
		# source.base_hp 等一长串字段，凑不齐就刷 "Invalid access to property"。
		# 找不到施法者时（已死亡/已离开）退化成空字典 —— 各处都有 is_empty 守卫。
		var source: Dictionary = {}
		var owner_id: Variant = proj.get("owner_id", 0)
		for entity in state.entities:
			if entity is Dictionary and entity.get("id", -1) == owner_id:
				source = entity
				break
		for target in hit.get("targets", []):
			if not bool(target.get("alive", true)):
				continue
			# 范围弹（aoe_radius>0）对同一目标只结算一次，靠 hit_ids 记账。
			var hit_ids: Array = proj.get("hit_ids", [])
			hit_ids.append(target.get("id", 0))
			proj["hit_ids"] = hit_ids
			_damage(target, float(proj.get("damage", 0.0)), source, str(proj.get("damage_type", "physical")))
			var slow_sec := float(proj.get("slow_sec", 0.0))
			if slow_sec > 0.0:
				# 走统一入口，让"免控"真的挡得住减速（旧实现直接写字段，免疫形同虚设）。
				ControlRules.apply_slow(target, slow_sec)
			_emit("projectile_hit", {
				"id": int(proj.get("id", 0)),
				"team": str(proj.get("team", "")),
				"owner_id": proj.get("owner_id", 0),
				"target": target.get("id", 0),
				"target_type": str(target.get("type", "")),
				"x": float((target.get("pos", Vector2.ZERO) as Vector2).x),
				"y": float((target.get("pos", Vector2.ZERO) as Vector2).y),
			})
	# 回收：死亡投射物从实体表移除，否则会无限累积（每 tick 都在追加）。
	_cleanup_dead_projectiles()

func _cleanup_dead_projectiles() -> void:
	var kept: Array = []
	for entity in state.entities:
		if entity is Dictionary and str(entity.get("type", "")) == "projectile" and not bool(entity.get("alive", true)):
			continue
		kept.append(entity)
	state.entities = kept

func _setup_teams() -> void:
	var humans: Array = config.get("humans", [])
	var bot_fill: bool = bool(config.get("bot_fill", false))
	var per_team := 1 if mode == "duel" else 5
	var slots := {"blue": 0, "red": 0}
	var human_counts := {"blue": 0, "red": 0}
	var bot_counter := 0

	for entry in humans:
		if not (entry is Dictionary):
			continue
		var data: Dictionary = entry
		var team: String = str(data.get("team", "blue"))
		if team != "red":
			team = "blue"
		if slots[team] >= per_team:
			continue
		var owner_id: String = str(data.get("id", "p%d" % (human_counts["blue"] + human_counts["red"] + 1)))
		var hero_type: String = str(data.get("hero_type", "blade"))
		if not HeroDefs.is_valid(hero_type):
			hero_type = "blade"
		var display_name: String = str(data.get("name", owner_id))
		_spawn_hero(owner_id, display_name, team, "human", hero_type, slots[team])
		slots[team] += 1
		human_counts[team] += 1

	if bot_fill:
		# 项 6：config 可用 "bot_comp" 指定阵容（每队同一个列表），用于节奏抽样里
		# 覆盖"双前排/全脆皮/缺刺客"这类极端组合。不传时退回历史行为
		# （BOT_TYPES 按下标取），所以既有对局逐位不变。
		var comp: Array = []
		var raw_comp: Variant = config.get("bot_comp", null)
		if raw_comp is Array and not (raw_comp as Array).is_empty():
			for entry in (raw_comp as Array):
				var candidate := str(entry)
				if HeroDefs.is_valid(candidate):
					comp.append(candidate)
		for team in ["blue", "red"]:
			while slots[team] < per_team:
				var hero_type := ""
				if not comp.is_empty():
					hero_type = str(comp[slots[team] % comp.size()])
				else:
					var pool: Array = HeroDefs.BOT_TYPES
					hero_type = str(pool[slots[team] % pool.size()])
				var owner_id := "bot_%d" % (bot_counter + 1)
				var display_name := "AI·" + str(HeroDefs.get_hero(hero_type).name)
				_spawn_hero(owner_id, display_name, team, "bot", hero_type, slots[team])
				bot_counter += 1
				slots[team] += 1

func _spawn_point(team: String, slot: int) -> Vector2:
	var base := MapData.BLUE_BASE if team == "blue" else MapData.RED_BASE
	var base_angle := 45.0 if team == "blue" else 225.0
	var offset: float = SPAWN_OFFSETS[slot % SPAWN_OFFSETS.size()]
	var angle := deg_to_rad(base_angle + offset)
	var point := base + Vector2(cos(angle), sin(angle)) * 8.2
	var limit := MapData.BOUNDS - 1.0
	return Vector2(clampf(point.x, -limit, limit), clampf(point.y, -limit, limit))

func _spawn_hero(owner_id: String, display_name: String, team: String, controller: String, hero_type: String, slot: int) -> void:
	var hero_def: Dictionary = HeroDefs.get_hero(hero_type)
	var lane := "mid"
	# 红方是否走镜像路（top↔bottom）。
	var mirrored := false
	if mode == "team":
		var slot_lane := str(MapData.LANE_ORDER[slot % MapData.LANE_ORDER.size()])
		lane = slot_lane
		# 项 6b —— **这是镜像局稳定偏向红方的第二个根因**。
		# 地图是点对称的，而点对称把 top 路映射到 **bottom 路**（不是映射到自身）。
		# 实测：top 上每个点的镜像到 bottom 最近点的最大距离只有 4.0m（纯采样偏移），
		# 而 top 映射到自身时偏差高达 134m。
		# 所以"双方都走同名路"在几何上就不可能对称 —— 蓝方英雄在 top 上，
		# 红方英雄却在**同一条物理路径**的另一头，两者面对的兵线/地形完全不同。
		# 正确做法：红方走镜像路。mid 在对称轴上，自映射。
		if team == "red":
			lane = str(LANE_MIRROR.get(slot_lane, slot_lane))
			mirrored = true
	var path: Array = MapData.lane_path(lane)
	var spawn := _spawn_point(team, slot)
	# 方向：**所有路的 path[0] 都在蓝方基地侧、path[-1] 在红方基地侧**
	# （实测 top/bottom/mid 三条路的首末点完全相同：(46,-46) → (-46,46)）。
	# 所以无论走哪条路，红方都必须沿反序前进（path_dir = -1）。
	# 上一轮我把"镜像路 + 正向"配在一起，结果红方起点被算到路径另一端，距离 120m。
	var forward := team == "blue"
	var dir := 1 if forward else -1
	# 起步点取"离出生点最近的路径点"：出生点严格点对称，所以两侧最近的路径点也对称。
	var path_index := _index_for_arc(path, spawn, forward)
	var hero := {
		"id": _next_id(),
		"type": "hero",
		"owner_id": owner_id,
		"name": display_name,
		"team": team,
		"controller": controller,
		"hero_type": hero_type,
		"lane": lane,
		"pos": spawn,
		"spawn_pos": spawn,
		"radius": float(hero_def.radius),
		"level": 1,
		"xp": 0.0,
		"hp": float(hero_def.max_hp),
		"max_hp": float(hero_def.max_hp),
		"mp": float(hero_def.max_mp),
		"max_mp": float(hero_def.max_mp),
		"speed": float(hero_def.speed),
		"attack_damage": float(hero_def.attack_damage),
		"attack_range": float(hero_def.attack_range),
		"attack_interval": float(hero_def.attack_interval),
		# 战斗属性（项 1）。出生值 = 该英雄的基础值；装备与被动只改这些字段，
		# 结算侧永远从字段读，不再写死常量。
		"armor": float(hero_def.get("armor", 0.0)),
		"magic_resist": float(hero_def.get("magic_resist", 0.0)),
		"base_armor": float(hero_def.get("armor", 0.0)),
		"base_magic_resist": float(hero_def.get("magic_resist", 0.0)),
		"cooldown_reduction": 0.0,
		"attack_speed": 0.0,
		"base_attack_speed": float(hero_def.get("attack_speed", 0.0)),
		"crit_damage": 1.5,
		"base_crit_damage": 1.5,
		"hp_regen": float(hero_def.get("hp_regen", 0.0)),
		"mana_regen": float(hero_def.get("mana_regen", 0.0)),
		"base_hp_regen": float(hero_def.get("hp_regen", 0.0)),
		"base_mana_regen": float(hero_def.get("mana_regen", 0.0)),
		"passive_as_bonus": 0.0,
		"passive_as_timer": 0.0,
		"attack_cd": 0.0,
		"kills": 0,
		"deaths": 0,
		"assists": 0,
		# 经济面板的统计口径：输出/承伤按「打出去的伤害」算（含被护盾吃掉的部分），
		# 因为那同样是玩家打出的输出；面板要能回答「谁在打伤害」，不是「谁破了盾」。
		"damage_dealt": 0.0,
		"damage_taken": 0.0,
		"tower_kills": 0,
		# 助攻判定：谁在这 10 秒内对目标造成过伤害（id → 时刻）。
		# 只留 last_hero_attacker 一个字段的话，多打一就只剩最后那一下的人算助攻。
		"hero_damagers": {},
		"alive": true,
		"respawn_timer": 0.0,
		"skill_q_cd": 0.0,
		"skill_w_cd": 0.0,
		"skill_e_cd": 0.0,
		"skill_r_cd": 0.0,
		# 技能等级（项 2）。q/w/e 出生已学 1 级，r 出生 0 级 = 未学习。
		"skill_q_level": 1,
		"skill_w_level": 1,
		"skill_e_level": 1,
		"skill_r_level": 0,
		"skill_points": 0,
		"summoner_spell": "flash",
		"summoner_cd": 0.0,
		"attack_mode": "default",
		"locked_target": -1,
		"attack_drag": Vector2.ZERO,
		"gold": 0,
		"gold_fraction": 0.0,
		"cs": 0,
		"inventory": [],
		"base_hp": float(hero_def.max_hp),
		"base_ad": float(hero_def.attack_damage),
		"base_speed": float(hero_def.speed),
		"ability_power": 0.0,
		"crit_rate": 0.0,
		"last_input_seq": -1,
		"last_purchase_seq": -1,
		"passive_stacks": 0,
		"cc_immune_timer": 0.0,
		# 硬控（项 4）：四个独立计时。分开而不是合成一个"被控"标志，
		# 是因为行动矩阵不同（沉默不禁普攻、定身不禁施法）。
		"stun_timer": 0.0,
		"knockup_timer": 0.0,
		"silence_timer": 0.0,
		"root_timer": 0.0,
		"facing": Vector2(0.0, -1.0) if team == "blue" else Vector2(0.0, 1.0),
		"shield": 0.0,
		"shield_timer": 0.0,
		"haste_timer": 0.0,
		"slow_timer": 0.0,
		"revealed_timer": 0.0,
		"last_damage_time": -999.0,
		"last_attacker_id": -1,
		"last_attacker_time": -999.0,
		"last_hero_attacker_id": -1,
		"last_hero_attacker_time": -999.0,
		"last_killer_id": -1,
		"last_killer_name": "",
		"last_killer_type": "",
		"recalling": false,
		"recall_timer": 0.0,
		"recall_total": 0.0,
		"recall_from": spawn,
		"teleporting": false,
		"teleport_timer": 0.0,
		"teleport_total": 0.0,
		"teleport_cd": 0.0,
		"teleport_pad": "",
		"teleport_from": spawn,
		"buff_red_timer": 0.0,
		"buff_blue_timer": 0.0,
		"path": path,
		"path_index": path_index,
		"path_dir": dir,
	}
	state.entities.append(hero)

func _setup_structures() -> void:
	var lanes: Array = ["mid"] if mode == "duel" else MapData.LANE_ORDER
	for slot in MapLayout.tower_slots():
		if not lanes.has(str(slot.lane)):
			continue
		_add_tower(str(slot.team), slot.pos, str(slot.lane), str(slot.tier))
	_add_base("blue", MapData.BLUE_BASE)
	_add_base("red", MapData.RED_BASE)
	for slot in MapLayout.guardian_slots():
		_add_guard(str(slot.team), slot.pos, str(slot.side))

func _add_tower(team: String, pos: Vector2, lane: String, tier: String) -> void:
	var hp: float = float(TOWER_HP.get(tier, 2800.0))
	state.entities.append({
		"id": _next_id(),
		"type": "tower",
		"team": team,
		"lane": lane,
		"tier": tier,
		"pos": pos,
		"radius": MapData.TOWER_RADIUS,
		"hp": hp,
		"max_hp": hp,
		"alive": true,
		"range": STRUCTURE_RANGE,
		"attack_damage": float(TOWER_DAMAGE.get(tier, 150.0)),
		"attack_interval": 1.1,
		"attack_cd": 0.0,
	})

func _add_base(team: String, pos: Vector2) -> void:
	state.entities.append({
		"id": _next_id(),
		"type": "base",
		"team": team,
		"lane": "",
		"pos": pos,
		"radius": MapData.BASE_RADIUS,
		"hp": 6000.0,
		"max_hp": 6000.0,
		"alive": true,
		"range": BASE_RANGE,
		"attack_damage": 180.0,
		"attack_interval": 1.2,
		"attack_cd": 0.0,
		"shield": 0.0,
		"shield_max": 0.0,
		"guards_alive": 0,
		"exposed": false,
		"last_shield_hit_time": -999.0,
	})

func _add_guard(team: String, pos: Vector2, side: String) -> void:
	state.entities.append({
		"id": _next_id(),
		"type": "guard",
		"team": team,
		"lane": "core",
		"side": side,
		"tier": "twin",
		"pos": pos,
		"radius": MapData.TOWER_RADIUS * 0.85,
		"hp": 3200.0,
		"max_hp": 3200.0,
		"alive": true,
		"range": STRUCTURE_RANGE - 1.0,
		"attack_damage": 160.0,
		"attack_interval": 1.1,
		"attack_cd": 0.0,
	})

func _setup_jungle() -> void:
	for camp in Jungle.CAMPS:
		_spawn_monster(Jungle.monster_stats(camp))

func _spawn_monster(stats: Dictionary) -> Dictionary:
	var monster: Dictionary = stats.duplicate(true)
	var pos: Vector2 = stats.get("pos", Vector2.ZERO)
	monster["id"] = _next_id()
	monster["pos"] = pos
	monster["home_pos"] = pos
	monster["attack_cd"] = 0.0
	monster["respawn_timer"] = 0.0
	monster["alive"] = true
	state.entities.append(monster)
	return monster

func _update_wave(dt: float) -> void:
	state.wave_timer = float(state.wave_timer) - dt
	if float(state.wave_timer) > 0.0:
		return
	state.wave_timer = WAVE_INTERVAL
	state.wave = int(state.wave) + 1
	var lanes: Array = ["mid"] if mode == "duel" else MapData.LANE_ORDER
	for lane in lanes:
		for team in ["blue", "red"]:
			# 项 6b：红方小兵走镜像路，与英雄一致 —— 只有这样两侧才真正点对称。
			# 若红方也走 top，两军就在**同一条物理路径**上相向而行，
			# 而 top 路首段 12.649m、末段 8.944m 不等长，两侧接触时刻必然不同。
			var wave_lane := str(lane)
			if str(team) == "red":
				wave_lane = str(LANE_MIRROR.get(str(lane), str(lane)))
			var path: Array = MapData.lane_path(wave_lane)
			var super_enabled := WaveRules.super_unlocked(str(lane), str(team), state.entities)
			var composition: Array = WaveRules.composition(int(state.wave), super_enabled)
			for index in composition.size():
				_spawn_minion(str(team), str(lane), path, index, str(composition[index]))
	_emit("wave", {"wave": state.wave})

func _spawn_minion(team: String, lane: String, path: Array, index: int, minion_type: String) -> void:
	# 项 6b：三条路的 path[0] 都在蓝方基地侧、path[-1] 在红方基地侧
	#（实测首末点完全相同：(46,-46) → (-46,46)）。
	# 所以走哪条路都一样，红方沿反序前进。
	var forward := team == "blue"
	var base: Vector2 = path[0] if forward else path[path.size() - 1]
	# 起步点按**路径总长比例**取（不是固定索引、也不是固定弧长）。
	# 依据：top 路首段 12.649m、末段 8.944m 不等长，按弧长从两端各走 12m 会落到
	# 相差 21.4m 的位置；而按比例取点时镜像偏差只有 0.27~0.40m。
	var entry_probe := _point_at_progress(path, MINION_SPAWN_PROGRESS, forward)
	var path_index := _index_for_arc(path, entry_probe, forward)
	var waypoint: Vector2 = path[path_index]
	var toward := (waypoint - base).normalized()
	var side := Vector2(-toward.y, toward.x)
	var pos := base + toward * 2.6 + side * (float(index) - 1.0) * 1.0
	var stats: Dictionary = WaveRules.stats(minion_type, int(state.wave))
	var minion := {
		"id": _next_id(),
		"type": "minion",
		"team": team,
		"lane": lane,
		"minion_type": minion_type,
		"pos": pos,
		"radius": float(stats.radius),
		"hp": float(stats.hp),
		"max_hp": float(stats.max_hp),
		"alive": true,
		"speed": float(stats.move_speed),
		"attack_damage": float(stats.attack_damage),
		"attack_range": float(stats.attack_range),
		"attack_interval": float(stats.attack_interval),
		"attack_cd": 0.0,
		"path": path,
		"path_index": path_index,
		"path_dir": 1 if forward else -1,
	}
	state.entities.append(minion)

func get_hero_by_player(owner_id: String) -> Variant:
	for entity in state.entities:
		if entity.type == "hero" and entity.owner_id == owner_id:
			return entity
	return null

func set_input(player_id: String, input: Dictionary) -> void:
	var next := input.duplicate()
	var previous: Dictionary = inputs.get(player_id, {})
	if not previous.is_empty():
		# 购买/出售是离散意图。20Hz 输入可能晚于 30Hz 模拟到达，不能被下一条纯移动输入覆盖。
		if str(next.get("buy_item", "")) == "" and str(previous.get("buy_item", "")) != "":
			next["buy_item"] = previous["buy_item"]
		if int(next.get("sell_slot", -1)) < 0 and int(previous.get("sell_slot", -1)) >= 0:
			next["sell_slot"] = int(previous["sell_slot"])
		# 加点同理（项 2）：一条移动输入不能把还没被消费的 upgrade_slot 冲掉。
		if str(next.get("upgrade_slot", "")) == "" and str(previous.get("upgrade_slot", "")) != "":
			next["upgrade_slot"] = previous["upgrade_slot"]
	inputs[player_id] = next

func set_player_controller(owner_id: String, controller: String) -> void:
	var hero: Variant = get_hero_by_player(owner_id)
	if hero == null:
		return
	hero.controller = controller
	if controller == "bot":
		state.bot_ai = true

# 取走本批事件并清空。事件是一次性的，消费方（表现层 / 联机广播）必须显式取走。
#
# 为什么不靠 tick() 开头那句 state.events = [] 兜底：对局结束后 tick() 直接 return，
# 清空那一行就再也不执行，而快照每帧都从 state.events 复制事件。于是 match_end 被
# 每个 tick 重放一次 —— 顿帧常驻、震屏每帧重算、结算音乐反复重播，结算界面持续抖动。
func consume_events() -> Array:
	var events: Array = state.events
	state.events = []
	return events

func tick(dt: float) -> void:
	if ended:
		# 结束后不再推进模拟，但事件不能在这里清空：可能还有一方没取走
		# （例如 ended 由 tick 之外的 apply_damage 触发）。取走由 consume_events 负责。
		return
	state.time = float(state.time) + dt
	state.events = []
	for entity in state.entities:
		entity.moving = false
	_update_wave(dt)
	_update_objectives(dt)
	for spot in River.tick(state, dt):
		_spawn_monster(River.spirit_stats(spot))
	_update_hero_timers(dt)
	_apply_human_inputs(dt)
	_update_bots(dt)
	_update_minions(dt)
	_update_monsters(dt)
	# 项 3：投射物在小兵/野怪更新之后推进，保证它们看到的是本 tick 的最终位置。
	_update_projectiles(dt)
	_update_structures(dt)
	Crystal.tick(state, dt)
	_update_respawns(dt)
	_cleanup_dead_minions(dt)
	Objectives.tick(state, dt)

func _update_objectives(dt: float) -> void:
	if bool(state.objective.get("spawned", false)):
		return
	state.objective.spawn_timer = maxf(0.0, float(state.objective.spawn_timer) - dt)
	if float(state.objective.spawn_timer) > 0.0:
		return
	state.objective.spawned = true
	state.objective.spawn_timer = 0.0
	for pit in Objectives.PITS:
		_spawn_monster(Objectives.monster_stats(pit))
	_emit("objective_spawn", {"name": "暴君与主宰"})

func _update_monsters(dt: float) -> void:
	for entity in state.entities:
		if entity.type != "monster":
			continue
		entity.attack_cd = maxf(0.0, float(entity.get("attack_cd", 0.0)) - dt)
		if not bool(entity.get("alive", false)):
			entity.respawn_timer = maxf(0.0, float(entity.get("respawn_timer", 0.0)) - dt)
			if float(entity.respawn_timer) <= 0.0:
				_respawn_monster(entity)
			continue
		var target: Dictionary = _monster_target(entity)
		if target.is_empty():
			_advance_monster_home(entity, dt)
			continue
		var reach: float = float(entity.attack_range) + float(target.get("radius", 0.0))
		if entity.pos.distance_to(target.pos) <= reach:
			if float(entity.attack_cd) <= 0.0:
				entity.attack_cd = float(entity.attack_interval)
				entity.facing = (target.pos - entity.pos).normalized()
				_damage(target, float(entity.attack_damage), entity)
		elif not bool(entity.get("objective", false)):
			var home: Vector2 = entity.get("home_pos", entity.pos)
			if entity.pos.distance_to(home) <= float(entity.get("leash_range", 11.0)):
				var next: Vector2 = entity.pos + (target.pos - entity.pos).normalized() * float(entity.move_speed) * dt
				entity.pos = Collision.move(entity.pos, next, float(entity.get("radius", 1.0)))
				entity.moving = true

func _monster_target(monster: Dictionary) -> Dictionary:
	# 野怪纯反击：不主动索敌。英雄站在旁边、路过、蹲草丛都不会把它引过来，
	# 只有对它造成过伤害的人才会被它盯上（2026-10-24 用户定稿）。
	# 以前这里有一段「aggro_range 内自动锁最近的英雄」，结果是打野还没出手
	# 野怪就先扑上来，蹲草丛绕后也完全无效。
	var attacker: Dictionary = _entity_by_id(int(monster.get("last_attacker_id", -1)))
	if attacker.is_empty() or not bool(attacker.get("alive", false)):
		return {}
	if str(attacker.get("type", "")) != "hero":
		return {}
	if monster.pos.distance_to(attacker.pos) > float(monster.get("leash_range", 11.0)):
		# 追丢了就彻底忘掉。否则它会带着旧账回窝，英雄再靠近就「隔空」冲出来咬人，
		# 等于又变回主动索敌。
		monster["last_attacker_id"] = -1
		monster["last_attacker_time"] = -999.0
		return {}
	return attacker

func _advance_monster_home(monster: Dictionary, dt: float) -> void:
	var home: Vector2 = monster.get("home_pos", monster.pos)
	if monster.pos.distance_to(home) <= 0.2:
		return
	var next: Vector2 = monster.pos + (home - monster.pos).normalized() * float(monster.get("move_speed", 3.0)) * dt
	monster.pos = Collision.move(monster.pos, next, float(monster.get("radius", 1.0)))

func _respawn_monster(monster: Dictionary) -> void:
	monster.alive = true
	monster.hp = float(monster.max_hp)
	monster.pos = monster.get("home_pos", monster.pos)
	monster.respawn_timer = 0.0
	monster.attack_cd = 0.0
	monster.last_attacker_id = -1
	monster.last_attacker_time = -999.0
	monster.last_hero_attacker_id = -1
	monster.last_hero_attacker_time = -999.0
	_emit("monster_respawn", {
		"name": str(monster.get("name", "野怪")),
		"x": float(monster.pos.x),
		"y": float(monster.pos.y),
	})

func _cleanup_dead_minions(dt: float) -> void:
	for i in range(state.entities.size() - 1, -1, -1):
		var entity: Dictionary = state.entities[i]
		if entity.type == "minion" and not bool(entity.get("alive", false)):
			var timer: float = float(entity.get("death_cleanup_timer", 2.0)) - dt
			if timer <= 0.0:
				state.entities.remove_at(i)
			else:
				entity["death_cleanup_timer"] = timer

# 是否站在己方泉水范围内（基地中心 MapData.FOUNTAIN_RADIUS 以内）。
func _in_fountain(entity: Dictionary) -> bool:
	var base := MapData.BLUE_BASE if str(entity.team) == "blue" else MapData.RED_BASE
	return (entity.pos as Vector2).distance_to(base) <= MapData.FOUNTAIN_RADIUS

# 回城与传送的引导推进。返回 true 表示本 tick 已被引导消费（完成瞬移后不该再处理移动与施法）。
# 单独成函数是因为它不能挂在「有输入」这个前提上：客户端站着不动时推的是空字典。
func _tick_channels(entity: Dictionary, input: Dictionary, dt: float) -> bool:
	# 硬控打断引导（项 4）：眩晕/击飞/沉默都该打断回城与传送。
	# 这不只是"合理"——回城是脱离手段，如果被控还能安然读条回家，
	# 硬控在防守端的价值就没了。定身不打断（它不禁施法，见 ControlRules 矩阵）。
	if not ControlRules.can_cast(entity):
		var was_recalling := bool(entity.get("recalling", false))
		var was_teleporting := bool(entity.get("teleporting", false))
		if was_recalling or was_teleporting:
			var break_pos: Vector2 = entity.pos
			RecallRules.interrupt(entity)
			Teleport.interrupt(entity)
			# 事件形状与下面"自然打断"的两处保持一致（team/hero/x/y），
			# 否则表现层要为同一个语义写两套解析。
			if was_recalling:
				_emit("recall_interrupt", {
					"team": entity.team, "hero": entity.id,
					"x": float(break_pos.x), "y": float(break_pos.y),
				})
			if was_teleporting:
				_emit("teleport_interrupt", {
					"team": entity.team, "hero": entity.id,
					"x": float(break_pos.x), "y": float(break_pos.y),
				})
			return false
	if bool(input.get("teleport", false)) and not bool(entity.get("teleporting", false)):
		if Teleport.start(entity):
			# 传送优先。这里静默取消回城而不发打断事件：客户端会看到 kind 从
			# recall 直接切到 teleport，法阵就地换配色，不需要多播一次断裂音。
			RecallRules.interrupt(entity)
	if bool(entity.get("teleporting", false)):
		var departure: Vector2 = entity.get("teleport_from", entity.pos)
		if Teleport.tick(entity, input, dt):
			_emit("teleport", {
				"team": entity.team,
				"hero": entity.id,
				"pad": str(entity.get("teleport_pad", "")),
				"x": float(departure.x),
				"y": float(departure.y),
				"to_x": float(entity.pos.x),
				"to_y": float(entity.pos.y),
			})
			return true
		elif not bool(entity.get("teleporting", false)):
			# tick 返回 false 且引导标记已被清空 = 中途被打断（移动/施法/受击）。
			_emit("teleport_interrupt", {
				"team": entity.team,
				"hero": entity.id,
				"x": float(departure.x),
				"y": float(departure.y),
			})
	if bool(input.get("recall", false)) and not bool(entity.get("recalling", false)) and not _in_fountain(entity):
		RecallRules.start(entity)
	if bool(entity.get("recalling", false)):
		var recall_from: Vector2 = entity.get("recall_from", entity.pos)
		if RecallRules.tick(entity, input, dt):
			_emit("recall", {
				"team": entity.team,
				"hero": entity.id,
				"x": float(recall_from.x),
				"y": float(recall_from.y),
				"to_x": float(entity.pos.x),
				"to_y": float(entity.pos.y),
			})
			return true
		elif not bool(entity.get("recalling", false)):
			_emit("recall_interrupt", {
				"team": entity.team,
				"hero": entity.id,
				"x": float(recall_from.x),
				"y": float(recall_from.y),
			})
	return false

func _update_hero_timers(dt: float) -> void:
	for entity in state.entities:
		if entity.type != "hero":
			continue
		# 死亡不是时间暂停：复活等待期间冷却、buff、护盾计时照样走。
		# 以前整段都挂在 alive 上，死一次大招 CD 就白送（复活后仍是 60 秒）。
		EconomySystem.tick_natural_gold(entity, dt)
		Jungle.tick_buffs(entity, dt)
		entity.skill_q_cd = maxf(0.0, float(entity.skill_q_cd) - dt)
		entity.skill_w_cd = maxf(0.0, float(entity.get("skill_w_cd", 0.0)) - dt)
		entity.skill_e_cd = maxf(0.0, float(entity.skill_e_cd) - dt)
		entity.skill_r_cd = maxf(0.0, float(entity.get("skill_r_cd", 0.0)) - dt)
		entity.summoner_cd = maxf(0.0, float(entity.get("summoner_cd", 0.0)) - dt)
		entity.teleport_cd = maxf(0.0, float(entity.get("teleport_cd", 0.0)) - dt)
		# 调试开关挂在实体上而不是全局：客机上这些键不存在，等于永远关闭，
		# 也不需要进快照白名单（它们不参与任何结算结果的下发）。
		if bool(entity.get("debug_no_cooldown", false)):
			entity.skill_q_cd = 0.0
			entity.skill_w_cd = 0.0
			entity.skill_e_cd = 0.0
			entity.skill_r_cd = 0.0
			entity.summoner_cd = 0.0
		if bool(entity.get("debug_infinite_mana", false)):
			entity.mp = float(entity.max_mp)
		entity.cc_immune_timer = maxf(0.0, float(entity.get("cc_immune_timer", 0.0)) - dt)
		# 硬控计时（项 4）：统一递减，避免"四个字段各写一遍、漏掉一个就永久眩晕"。
		ControlRules.tick(entity, dt)
		entity.attack_cd = maxf(0.0, float(entity.attack_cd) - dt)
		entity.shield_timer = maxf(0.0, float(entity.shield_timer) - dt)
		if float(entity.shield_timer) <= 0.0:
			entity.shield = 0.0
		entity.haste_timer = maxf(0.0, float(entity.haste_timer) - dt)
		entity.slow_timer = maxf(0.0, float(entity.slow_timer) - dt)
		# 翎羽被动的攻速窗口（项 1.4b）：窗口过了必须把加成清零，否则
		# passive_as_bonus 变成永久 35% 攻速——字段在、计时也在走、但没人收账，
		# 是这一类静默失效的标准形态（对照护盾 shield_timer 归零清 shield）。
		entity.passive_as_timer = maxf(0.0, float(entity.get("passive_as_timer", 0.0)) - dt)
		if float(entity.passive_as_timer) <= 0.0:
			entity.passive_as_bonus = 0.0
		entity["revealed_timer"] = maxf(0.0, float(entity.get("revealed_timer", 0.0)) - dt)
		if not entity.alive:
			continue
		# 回复属性化（项 1.6）：基础值 + 装备/被动给的 hp_regen / mana_regen。
		# 属性默认 0，所以旧单位逐位不变；泉水仍是独立的百分比通道，不受影响。
		entity.mp = minf(float(entity.max_mp), float(entity.mp) + (FIELD_MP_REGEN + float(entity.get("mana_regen", 0.0))) * dt)
		if float(entity.hp) < float(entity.max_hp) and float(state.time) - float(entity.last_damage_time) > 8.0:
			entity.hp = minf(float(entity.max_hp), float(entity.hp) + (float(entity.max_hp) * FIELD_HP_REGEN + float(entity.get("hp_regen", 0.0))) * dt)
		# 泉水：站在己方基地范围内快速回满，不必等脱战计时。
		if _in_fountain(entity):
			entity.hp = minf(float(entity.max_hp), float(entity.hp) + float(entity.max_hp) * FOUNTAIN_HP_RATE * dt)
			entity.mp = minf(float(entity.max_mp), float(entity.mp) + float(entity.max_mp) * FOUNTAIN_MP_RATE * dt)

func _apply_human_inputs(dt: float) -> void:
	for entity in state.entities:
		if entity.type != "hero" or not entity.alive or entity.controller != "human":
			continue
		var input: Dictionary = inputs.get(entity.owner_id, {})
		if input.is_empty():
			# 站着不动时客户端仍会推空输入。引导必须照常推进，
			# 否则「按 B 回城然后松手」会永远卡在引导里（旧实现就卡在这儿）。
			_tick_channels(entity, input, dt)
			continue
		var aim: Vector2 = input.get("aim", Vector2.ZERO)
		var aim_vector: Vector2 = aim - entity.pos
		var move: Vector2 = input.get("move", Vector2.ZERO)
		entity["attack_mode"] = str(input.get("attack_mode", "default"))
		entity["locked_target"] = int(input.get("locked_target", -1))
		entity["attack_drag"] = aim_vector if bool(input.get("attack", false)) else Vector2.ZERO
		var seq := int(input.get("seq", 0))
		var buy_item_id := str(input.get("buy_item", ""))
		var sell_slot := int(input.get("sell_slot", -1))
		# 项 2：加点是离散意图，和购买一样"取走即清"，否则下一条纯移动输入会重放它。
		var upgrade_slot := str(input.get("upgrade_slot", ""))
		# 意图只消费一次：否则 set_input 的合并逻辑会把旧购买带进下一个输入序列。
		input["buy_item"] = ""
		input["sell_slot"] = -1
		input["upgrade_slot"] = ""
		if seq > int(entity.get("last_input_seq", -1)):
			entity["last_input_seq"] = seq
		# 购买走可靠通道，可能与不可靠的移动输入乱序，所以用独立的购买序号去重，
		# 不能被先到的移动输入把 last_input_seq 抬高而吞掉。
		if (buy_item_id != "" or sell_slot >= 0) and seq > int(entity.get("last_purchase_seq", -1)):
			entity["last_purchase_seq"] = seq
			if buy_item_id != "" and ItemShop.buy_item(entity, buy_item_id):
				_emit("purchase", {
					"hero": entity.id,
					"buy_item": buy_item_id,
					"amount": int(ItemShop.get_item(buy_item_id).get("cost", 0)),
				})
			if sell_slot >= 0 and ItemShop.sell_item(entity, sell_slot):
				_emit("sold", {"hero": entity.id, "sell_slot": sell_slot})
		# 加点与移动同包走不可靠通道，不需要购买那套独立序号去重；
		# spend_skill_point 内部已保证"被拒不吞点"，重复投递最多是空转一次。
		if upgrade_slot != "":
			spend_skill_point(entity, upgrade_slot)
		if move.length() > 1.0:
			move = move.normalized()
		if _tick_channels(entity, input, dt):
			continue
		# 硬控门控（项 4）：行动矩阵的真身在 ControlRules，这里只问"能不能"。
		# 两条**刻意的例外**，写在这里免得后来者以为是漏判：
		#   1. 转向不受限制 —— 定身/眩晕时仍可调整朝向。连朝向都锁死，
		#      手感会变成"游戏卡住了"而不是"我被控住了"。
		#   2. 召唤师技能不受沉默/眩晕限制 —— 否则"净化"永远解不开自己身上的控，
		#      这张牌就废了（它的全部意义就是在被控时使用）。
		var can_move := ControlRules.can_move(entity)
		var can_cast := ControlRules.can_cast(entity)
		if move.length() > 0.01 and can_move:
			# 移动时朝向移动方向：点击移动经常是「往身后走」，若还朝着准星就成了倒着走。
			# 站住时才看向准星；技能与普攻随后各自把 facing 改回目标方向，瞄准手感不变。
			entity.facing = move.normalized()
			_move_hero(entity, move, dt)
		elif aim_vector.length() > 0.6:
			entity.facing = aim_vector.normalized()
		if can_cast and bool(input.get("skill_q", false)):
			_cast_q(entity, aim)
		if can_cast and bool(input.get("skill_w", false)):
			SkillSystem.cast_skill(entity, "w", aim, self)
		if can_cast and bool(input.get("skill_e", false)):
			_cast_e(entity, aim)
		if can_cast and bool(input.get("skill_r", false)):
			SkillSystem.cast_skill(entity, "r", aim, self)
		if bool(input.get("summoner", false)):
			SkillSystem.cast_summoner_spell(entity, str(entity.get("summoner_spell", "flash")), aim, self)
		if bool(input.get("attack", false)) and ControlRules.can_attack(entity):
			_try_attack(entity)

func _update_bots(dt: float) -> void:
	if not bool(state.bot_ai):
		return
	for entity in state.entities:
		if entity.type != "hero" or not entity.alive or entity.controller != "bot":
			continue
		var recommended := ItemShop.get_quick_buy_recommendation(entity, ItemShop.build_order_for(str(entity.hero_type)))
		if recommended != "":
			ItemShop.buy_item(entity, recommended)
		# 硬控必须对 bot 生效（4.2）：AI 读不到控就等于白控 ——
		# 玩家把控制交出去，bot 照样走位放技能，那这套硬控只是"给玩家看的动画"。
		# 购买不受门控（和人类路径一致：买装备不是身体动作）。
		var can_move := ControlRules.can_move(entity)
		var can_cast := ControlRules.can_cast(entity)
		var can_attack := ControlRules.can_attack(entity)
		var controlled := not can_move and not can_cast and not can_attack
		# 刻意**不**在这里 continue：召唤师技能不受门控（净化必须能在被控时用），
		# 若提前退出，被控的 bot 永远交不出净化 —— 那正好把这张牌废掉。
		# 其余动作各自按 can_move / can_cast / can_attack 门控，行为等价且无死角。
		var target: Dictionary = _nearest_enemy(entity, 9.0)
		if target.is_empty():
			if can_move:
				_advance_along_path(entity, dt)
			if controlled:
				_use_bot_summoner(entity, {}, 999.0)
			continue
		var to_target: Vector2 = target.pos - entity.pos
		if to_target.length() > 0.1:
			entity.facing = to_target.normalized()
		var distance := to_target.length()
		# 追击上限（项 6b）：bot 不能为了追一个英雄而离开自己的兵线。
		# 修复前实测蓝方射手 15 秒内跑了 100m 直捣对方基地，全程 CS=0、等级停在 1，
		# 而同阵容红方射手正常发育到 CS=17/lv5 —— 这是镜像局稳定偏向一侧的直接原因。
		# 判据用"离自家兵线路径的垂直距离"而不是"离出生点距离"：
		# 英雄本来就该沿兵线前压，只有**脱线**才需要被拉回。
		var leash_exceeded := false
		if _off_lane_distance(entity) > BOT_LEASH_RADIUS:
			# 只有"追敌方英雄"才会被 leash 限制；小兵/塔/野怪是推进目标，不该被限制，
			# 否则清完线就再也不推塔了。
			leash_exceeded = str(target.get("type", "")) == "hero"
		if leash_exceeded:
			target = {}
		if target.is_empty():
			# 脱线且只看到英雄：回到兵线继续推进，而不是继续追杀。
			if can_move:
				_advance_along_path(entity, dt)
			if can_cast:
				_use_bot_summoner(entity, {}, 999.0)
			continue
		if can_cast:
			if float(entity.skill_q_cd) <= 0.0 and distance <= 9.0:
				_cast_q(entity, target.pos)
			var hero_def: Dictionary = HeroDefs.get_hero(str(entity.hero_type))
			var w_def: Dictionary = hero_def.w
			if float(entity.skill_w_cd) <= 0.0 and distance <= float(w_def.range) + 1.0 and float(entity.mp) >= float(w_def.cost):
				SkillSystem.cast_skill(entity, "w", target.pos, self)
			var r_def: Dictionary = hero_def.r
			if float(entity.skill_r_cd) <= 0.0 and distance <= float(r_def.range) + float(target.get("radius", 0.0)) and float(entity.mp) >= float(r_def.cost):
				SkillSystem.cast_skill(entity, "r", target.pos, self)
		# 召唤师技能不被沉默/眩晕门控：净化必须在被控时能用（同人类路径的理由）。
		_use_bot_summoner(entity, target, distance)
		if can_cast and float(entity.skill_e_cd) <= 0.0:
			var e_def: Dictionary = HeroDefs.get_hero(str(entity.hero_type)).e
			var kind := str(e_def.kind)
			if kind == "shield" and float(entity.hp) < float(entity.max_hp) * 0.55:
				_cast_e(entity, entity.pos + to_target)
			elif kind == "haste" and to_target.length() > 3.5:
				_cast_e(entity, target.pos)
			elif kind == "dash" and to_target.length() > 2.5 and to_target.length() < 5.0:
				_cast_e(entity, target.pos)
		var reach: float = float(entity.attack_range) + float(target.get("radius", 0.0))
		if to_target.length() > reach:
			# 定身/眩晕时不能靠近，但仍允许放技能（上面已按 can_cast 判过）。
			if can_move:
				_move_hero(entity, to_target.normalized(), dt)
		elif can_attack:
			_try_attack(entity)

func _use_bot_summoner(hero: Dictionary, target: Dictionary, distance: float) -> void:
	if float(hero.summoner_cd) > 0.0:
		return
	var spell := str(hero.get("summoner_spell", "flash"))
	var hp_ratio := float(hero.hp) / maxf(1.0, float(hero.max_hp))
	match spell:
		"heal":
			if hp_ratio < 0.55:
				SkillSystem.cast_summoner_spell(hero, spell, hero.pos, self)
		"execute":
			if target.is_empty():
				return
			var target_ratio := float(target.get("hp", 0.0)) / maxf(1.0, float(target.get("max_hp", 1.0)))
			if distance <= 4.0 and target_ratio < 0.4:
				SkillSystem.cast_summoner_spell(hero, spell, target.pos, self)
		"cleanse":
			# 项 4：净化要在**任何控制**下都能交，不只是减速。
			# 原来只判 slow_timer，于是被眩晕/沉默时 bot 挨打也不解控 ——
			# 净化这张牌在 AI 手里等于不存在。
			if ControlRules.dominant_status(hero) != "" or float(hero.get("slow_timer", 0.0)) > 0.0:
				SkillSystem.cast_summoner_spell(hero, spell, hero.pos, self)
		"flash":
			if target.is_empty():
				return
			if hp_ratio < 0.3 and distance < 3.0:
				SkillSystem.cast_summoner_spell(hero, spell, hero.pos + (hero.pos - target.pos), self)

## 实体离自己兵线路径的**垂直距离**（项 6b）。
## 用垂直距离而不是"离出生点距离"：英雄本来就该沿兵线前压，
## 只有**脱线**（跑到野区或对面半场乱窜）才该被拉回。
func _off_lane_distance(entity: Dictionary) -> float:
	var path: Array = entity.get("path", [])
	if path.size() < 2:
		return 0.0
	var pos: Vector2 = entity.get("pos", Vector2.ZERO)
	var best := INF
	for i in range(path.size() - 1):
		var a: Vector2 = path[i]
		var b: Vector2 = path[i + 1]
		var ab := b - a
		var len_sq := ab.length_squared()
		if len_sq < 0.000001:
			best = minf(best, pos.distance_to(a))
			continue
		var t := clampf((pos - a).dot(ab) / len_sq, 0.0, 1.0)
		best = minf(best, pos.distance_to(a + ab * t))
	return best

func _move_hero(hero: Dictionary, direction: Vector2, dt: float) -> void:
	var speed: float = float(hero.speed)
	if float(hero.haste_timer) > 0.0:
		speed *= 1.4
	if float(hero.slow_timer) > 0.0:
		speed *= 0.65
	var destination: Vector2 = hero.pos + direction * speed * dt
	hero.pos = Collision.move(hero.pos, destination, float(hero.get("radius", 0.55)))
	hero.moving = true

func _advance_along_path(entity: Dictionary, dt: float) -> void:
	var path: Array = entity.path
	var index: int = int(entity.path_index)
	if index < 0 or index >= path.size():
		return
	var waypoint: Vector2 = path[index]
	var to_point: Vector2 = waypoint - entity.pos
	var speed := float(entity.get("speed", 3.3))
	if float(entity.get("slow_timer", 0.0)) > 0.0:
		speed *= 0.65
	# 路径点严重脱节时重新吸附（见下方 _resync_path_index）。
	# 不修的话会出现永久卡死：实体被墙挡住、每次只挪动一点点，
	# 而"到点"判定要求 < 0.9m，于是 path_index 永远不前进 ——
	# 实测蓝方射手卡在野区围墙边 6 分钟、CS 停在 4，而同阵容红方 CS 是 32。
	if to_point.length() > RESYNC_DISTANCE:
		index = _resync_path_index(entity, path)
		entity.path_index = index
		if index < 0 or index >= path.size():
			return
		waypoint = path[index]
		to_point = waypoint - entity.pos
	if to_point.length() < 0.9:
		index += int(entity.path_dir)
		entity.path_index = index
		if index < 0 or index >= path.size():
			return
		waypoint = path[index]
		to_point = waypoint - entity.pos
	if to_point.length() > 0.01:
		var before: Vector2 = entity.pos
		var destination: Vector2 = entity.pos + to_point.normalized() * speed * dt
		entity.pos = Collision.move(entity.pos, destination, float(entity.get("radius", 0.4)))
		entity.moving = true
		# 撞墙检测：这一 tick 实际位移远小于应走距离，说明被挡住了。
		# 连续卡住超过阈值就重新吸附，避免"贴着墙磨到天荒地老"。
		var progress := before.distance_to(entity.pos)
		if progress < speed * dt * STUCK_PROGRESS_RATIO:
			entity["stuck_ticks"] = int(entity.get("stuck_ticks", 0)) + 1
			if int(entity.get("stuck_ticks", 0)) > STUCK_TICKS_LIMIT:
				entity["stuck_ticks"] = 0
				entity.path_index = _resync_path_index(entity, path)
		else:
			entity["stuck_ticks"] = 0

## 把 path_index 重新吸附到**离当前位置最近的路径点**（沿前进方向取）。
## 返回新的索引；路径为空时返回 -1。
##
## 曾经写成"总是再往前多取一格"来避免在两点间抖动，但那会在路径点稀疏时
## 把实体甩到很远的点上（实测 (5,-5) 最近的点是 (0,0)，多走一格变成 (-18,18)，
## 距离 32.5m，比不吸附还糟）。正确做法是：**只有恰好落在已过的点上时才前移一格**。
static func _resync_path_index(entity: Dictionary, path: Array) -> int:
	if path.is_empty():
		return -1
	var pos: Vector2 = entity.pos
	var best := -1
	var best_dist := INF
	for i in path.size():
		var d: float = pos.distance_to(path[i])
		if d < best_dist:
			best_dist = d
			best = i
	if best < 0:
		return -1
	# 只有当实体已经越过最近点时才前移一格；否则保持原索引。
	# 判据：下一个点比当前点更近，说明当前点已经被越过。
	var dir := int(entity.get("path_dir", 1))
	var forward := best + dir
	if forward >= 0 and forward < path.size():
		var to_point: Vector2 = path[best] - pos
		var to_next: Vector2 = path[forward] - pos
		if to_next.length() < to_point.length():
			best = forward
	# 关键修正：吸附只能**沿前进方向推进，绝不回退**。
	# 否则会在出生点附近出现死循环：小兵刚离开出生点，被吸回 idx=0（出生点本身），
	# 于是"已到点"立刻成立、索引再 +1 回到 idx=1，下一帧又被吸回 idx=0……
	# 实测表现为小兵每 30 帧里只有第 0 帧动 0.1m、其余原地不动，位移恒为 0。
	var current := int(entity.get("path_index", best))
	if dir > 0:
		return maxi(best, current)
	if dir < 0:
		return mini(best, current)
	return best

func _update_minions(dt: float) -> void:
	for entity in state.entities:
		if entity.type != "minion" or not entity.alive:
			continue
		entity.attack_cd = maxf(0.0, float(entity.attack_cd) - dt)
		var target: Dictionary = _nearest_enemy(entity, MINION_AGGRO_RANGE)
		if target.is_empty():
			_advance_along_path(entity, dt)
			continue
		var reach: float = float(entity.attack_range)
		if target.type == "tower" or target.type == "base":
			reach += float(target.radius)
		if entity.pos.distance_to(target.pos) <= reach:
			if float(entity.attack_cd) <= 0.0:
				entity.attack_cd = float(entity.attack_interval)
				entity.facing = (target.pos - entity.pos).normalized()
				# 表现层靠这条事件画刀光/弹丸：小兵攻击不能再只改数值。
				#
				# 曾经试过"小兵打小兵时抽稀到 1/3"来省网络预算（事件量第一，4678 次），
				# 但 test_unit_attack_fx 立刻变红：**每一刀都必须有可渲染的反馈**，
				# 否则清兵时玩家看不到自己在打什么。这条测试的意图是对的，抽稀已回退。
				# 事件量改从别处优化（hit 已对小兵互殴静音，省了 40%）。
				_emit("minion_attack", {
					"source": entity.id,
					"team": entity.team,
					"minion_type": str(entity.get("minion_type", "melee")),
					"x": float(entity.pos.x),
					"y": float(entity.pos.y),
					"target": target.id,
					"target_type": target.type,
					"target_x": float(target.pos.x),
					"target_y": float(target.pos.y),
				})
				_damage(target, float(entity.attack_damage), entity)
		else:
			var step: Vector2 = (target.pos - entity.pos).normalized()
			var destination: Vector2 = entity.pos + step * float(entity.speed) * dt
			entity.pos = Collision.move(entity.pos, destination, float(entity.get("radius", 0.4)))
			entity.moving = true

func _update_structures(dt: float) -> void:
	for entity in state.entities:
		if entity.type != "tower" and entity.type != "base" and entity.type != "guard":
			continue
		if not entity.alive:
			continue
		if entity.type == "guard" and not Crystal.is_guard_vulnerable(entity, state.entities):
			continue
		entity.attack_cd = maxf(0.0, float(entity.attack_cd) - dt)
		var target: Dictionary = _structure_target(entity)
		if target.is_empty():
			continue
		if float(entity.attack_cd) <= 0.0:
			entity.attack_cd = float(entity.attack_interval)
			_emit("structure_attack", {
				"source": entity.id,
				"source_type": entity.type,
				"tier": str(entity.get("tier", "")),
				"team": entity.team,
				"x": float(entity.pos.x),
				"y": float(entity.pos.y),
				"target_x": float(target.pos.x),
				"target_y": float(target.pos.y),
			})
			_damage(target, float(entity.attack_damage), entity)

func _structure_target(structure: Dictionary) -> Dictionary:
	return TowerRules.select_target(structure, state.entities, float(state.time))

func _nearest_enemy(seeker: Dictionary, max_range: float) -> Dictionary:
	var best: Dictionary = {}
	var best_dist := max_range
	for entity in state.entities:
		if not entity.alive or entity.team == seeker.team or entity.id == seeker.id:
			continue
		# 项 3：投射物是**效果实体**，不是战斗单位，任何索敌都不能把它当目标。
		# 它有 team/pos/alive，能通过下面所有距离判定；一旦被选为目标，
		# _damage 会因为拿不到 hp 而刷 "Invalid access to property 'hp'"，
		# 但小兵的攻击会和投射物互相"拦截"，表现为伤害凭空消失。
		if str(entity.get("type", "")) == "projectile":
			continue
		if entity.type == "hero":
			var hero_dist: float = seeker.pos.distance_to(entity.pos) - 0.65
			if hero_dist < best_dist:
				best_dist = hero_dist
				best = entity
			continue
		var dist: float = seeker.pos.distance_to(entity.pos)
		if entity.type == "tower" or entity.type == "base" or entity.type == "guard":
			dist -= float(entity.radius) * 0.7
		if dist < best_dist:
			best_dist = dist
			best = entity
	return best

func _cast_q(hero: Dictionary, aim: Vector2) -> bool:
	var hero_def: Dictionary = HeroDefs.get_hero(str(hero.hero_type))
	var skill: Dictionary = hero_def.q
	if float(hero.skill_q_cd) > 0.0 or float(hero.mp) < float(skill.cost):
		return false
	var target: Dictionary = _pick_skill_target(hero, aim, float(skill.range))
	if target.is_empty():
		return false
	hero.mp = float(hero.mp) - float(skill.cost)
	hero.skill_q_cd = float(skill.cooldown) * hero_cooldown_scale(hero)
	var kind := str(skill.kind)
	var dtype := str(skill.get("damage_type", "physical"))
	# 项 2：技能基础伤害走"表值 + damage_grow*(技能等级-1)"，与 W/R 路径同一个函数真身。
	var damage: float = HeroDefs.scaled_damage(hero, "q") + float(hero.attack_damage) * 0.5 + float(hero.level - 1) * 8.0
	hero.facing = (target.pos - hero.pos).normalized()
	_emit("skill", {
		"slot": "q",
		"hero": hero.id,
		"hero_type": hero.hero_type,
		"name": skill.name,
		"kind": kind,
		"team": hero.team,
		"x": float(hero.pos.x),
		"y": float(hero.pos.y),
		"start_x": float(hero.pos.x),
		"start_y": float(hero.pos.y),
		"aim_x": float(target.pos.x),
		"aim_y": float(target.pos.y),
	})
	if kind == "quake" or kind == "slow":
		var radius := 3.2
		for entity in state.entities:
			if not entity.alive or entity.team == hero.team:
				continue
			if entity.type != "hero" and entity.type != "minion" and entity.type != "monster":
				continue
			if entity.pos.distance_to(target.pos) <= radius:
				_damage(entity, damage, hero, dtype)
				if kind == "slow":
					ControlRules.apply_slow(entity, 2.5)
	else:
		_damage(target, damage, hero, dtype)
	return true

func _cast_e(hero: Dictionary, aim: Vector2) -> bool:
	var hero_def: Dictionary = HeroDefs.get_hero(str(hero.hero_type))
	var skill: Dictionary = hero_def.e
	if float(hero.skill_e_cd) > 0.0 or float(hero.mp) < float(skill.cost):
		return false
	# 疾风步会先改 hero.pos 再发事件：起点必须在这里留一份，
	# 否则渲染层拿到的 from == 落点，位移拖尾就整段丢了。
	var start_pos: Vector2 = hero.pos
	var kind := str(skill.kind)
	if kind == "dash":
		var direction: Vector2 = aim - hero.pos
		if direction.length() < 0.2:
			direction = hero.facing
		var destination: Vector2 = hero.pos + direction.normalized() * float(skill.range)
		hero.pos = Collision.move(hero.pos, destination, float(hero.get("radius", 0.55)))
	elif kind == "shield":
		hero.shield = 350.0 + float(hero.level - 1) * 25.0
		hero.shield_timer = 4.0
	elif kind == "haste":
		hero.haste_timer = 4.0
	elif kind == "slow":
		var target: Dictionary = _pick_skill_target(hero, aim, float(skill.range))
		if target.is_empty():
			return false
		for entity in state.entities:
			if not entity.alive or entity.team == hero.team:
				continue
			if entity.type != "hero" and entity.type != "minion" and entity.type != "monster":
				continue
			if entity.pos.distance_to(target.pos) <= 3.0:
				ControlRules.apply_slow(entity, 2.5)
				# 项 2：E 的伤害也走等级缩放，与 Q/W/R 同源。
				_damage(entity, HeroDefs.scaled_damage(hero, "e"), hero, str(skill.get("damage_type", "magic")))
	hero.mp = float(hero.mp) - float(skill.cost)
	hero.skill_e_cd = float(skill.cooldown) * hero_cooldown_scale(hero)
	_emit("skill", {
		"slot": "e",
		"hero": hero.id,
		"hero_type": hero.hero_type,
		"name": skill.name,
		"kind": kind,
		"team": hero.team,
		"x": float(hero.pos.x),
		"y": float(hero.pos.y),
		"start_x": float(start_pos.x),
		"start_y": float(start_pos.y),
		"aim_x": float(aim.x),
		"aim_y": float(aim.y),
	})
	return true

func _pick_skill_target(hero: Dictionary, aim: Vector2, max_range: float) -> Dictionary:
	var best: Dictionary = {}
	var best_score := INF
	var aim_dir: Vector2 = aim - hero.pos
	var has_aim := aim_dir.length() > 0.4
	if has_aim:
		aim_dir = aim_dir.normalized()
	for entity in state.entities:
		if not entity.alive or entity.team == hero.team:
			continue
		if entity.type != "hero" and entity.type != "minion" and entity.type != "tower" and entity.type != "guard" and entity.type != "monster":
			continue
		var dist: float = hero.pos.distance_to(entity.pos)
		if dist > max_range:
			continue
		var direction: Vector2 = (entity.pos - hero.pos).normalized()
		if has_aim and direction.dot(aim_dir) < -0.15:
			continue
		var score := dist
		if entity.type == "hero":
			score -= 1.2
		if score < best_score:
			best_score = score
			best = entity
	return best

func _try_attack(hero: Dictionary) -> void:
	if float(hero.attack_cd) > 0.0:
		return
	var mode := str(hero.get("attack_mode", "default"))
	var locked := int(hero.get("locked_target", -1))
	var drag: Vector2 = hero.get("attack_drag", Vector2.ZERO)
	var target: Dictionary = TargetingRules.resolve_attack_target(hero, state.entities, mode, locked, drag)
	if target.is_empty():
		return
	var reach: float = float(hero.attack_range) + float(target.get("radius", 0.0))
	if hero.pos.distance_to(target.pos) > reach:
		# 拖拽指向的目标够不着时退回常规索敌，避免「朝着空地按住普攻就完全不攻击」。
		if drag.length() > 0.3 and not TargetingRules.is_lock_valid(hero, locked, state.entities):
			target = TargetingRules.resolve_attack_target(hero, state.entities, mode, -1, Vector2.ZERO)
			if target.is_empty():
				return
			reach = float(hero.attack_range) + float(target.get("radius", 0.0))
			if hero.pos.distance_to(target.pos) > reach:
				return
		else:
			return
	hero.attack_cd = hero_attack_interval(hero)
	hero.facing = (target.pos - hero.pos).normalized()
	var damage: float = float(hero.attack_damage)
	var crit := float(hero.get("crit_rate", 0.0)) > 0.0 and _next_random() < float(hero.get("crit_rate", 0.0))
	if crit:
		damage *= float(hero.get("crit_damage", 1.5))
	_emit("attack", {
		"hero": hero.id,
		# 表现层要靠英雄类型选形态与配色：近战挥刀光、远程打弹道。
		# 客机这一帧可能还没建好英雄视图，事件里带上就不用回查快照。
		"hero_type": str(hero.hero_type),
		"x": float(hero.pos.x),
		"y": float(hero.pos.y),
		"aim_x": float(target.pos.x),
		"aim_y": float(target.pos.y),
		"crit": crit,
	})
	_damage(target, damage, hero, "physical")
	# 被动挂在真实普攻命中上：英雄详情里的描述与实战数值必须同源。
	SkillSystem.on_hero_attack_hit(hero, target, self)

func _update_respawns(dt: float) -> void:
	for entity in state.entities:
		if entity.type != "hero" or entity.alive:
			continue
		entity.respawn_timer = maxf(0.0, float(entity.respawn_timer) - dt)
		if float(entity.respawn_timer) <= 0.0:
			entity.alive = true
			entity.hp = float(entity.max_hp)
			entity.mp = float(entity.max_mp)
			entity.pos = entity.spawn_pos
			entity.shield = 0.0
			entity.shield_timer = 0.0
			entity.haste_timer = 0.0
			entity.slow_timer = 0.0
			entity.passive_as_timer = 0.0
			entity.passive_as_bonus = 0.0
			entity.last_damage_time = -999.0
			entity.last_attacker_id = -1
			entity.last_attacker_time = -999.0
			entity.last_hero_attacker_id = -1
			entity.last_hero_attacker_time = -999.0
			_emit("respawn", {"hero": entity.id, "x": float(entity.pos.x), "y": float(entity.pos.y)})

func apply_damage(entity_id: int, amount: float, source_id: int = -1, damage_type := "physical") -> void:
	var target: Dictionary = _entity_by_id(entity_id)
	if target.is_empty() or not target.alive:
		return
	var source: Dictionary = {}
	if source_id >= 0:
		source = _entity_by_id(source_id)
	_damage(target, amount, source, damage_type)

func _damage(target: Dictionary, amount: float, source: Dictionary, damage_type := "physical") -> void:
	if target.is_empty() or not target.alive or amount <= 0.0:
		return
	# 调试无敌：只挡伤害，不挡仇恨。塔和小兵仍然会锁定他，
	# 否则一开无敌，整条兵线就停在原地不动了。
	if target.type == "hero" and bool(target.get("debug_god", false)):
		return
	if target.type == "tower" and not TowerRules.is_tower_vulnerable(target, state.entities):
		return
	if target.type == "guard" and not Crystal.is_guard_vulnerable(target, state.entities):
		return
	if target.type == "base" and not TowerRules.is_base_vulnerable(target, state.entities):
		return
	var incoming := amount
	if target.type == "tower":
		incoming *= TowerRules.damage_scale(target, state.time)
	# 小兵 / 野怪（不含主宰暴君这类大目标）对英雄的伤害单独收一档。
	# 只影响"英雄挨打"这一侧，小兵打小兵、打塔的实际数值保持不变。
	if target.type == "hero" and not source.is_empty():
		var source_type := str(source.get("type", ""))
		if source_type == "minion":
			incoming *= PVE_HERO_DAMAGE_SCALE
		elif source_type == "monster" and not bool(source.get("objective", false)):
			incoming *= PVE_HERO_DAMAGE_SCALE
	if not source.is_empty() and str(source.get("type", "")) == "hero":
		incoming *= Jungle.damage_scale(source) * Objectives.damage_scale(state, str(source.get("team", "")))
	# —— 分型减伤（项 1，验收表 1.1/1.2）——
	# 有效伤害 = incoming * K / (K + resist)，resist=K 减半。
	# 只对英雄生效：小兵/塔/野怪没有抗性字段，维持"原样结算"，
	#   兵线互殴与推塔节奏因此逐位不变（survivability 锚死的 near 靠这条不红）。
	# 真实伤害（终结）不读任何抗性。resist=0 时乘子恒等 1.0 = 旧减法。
	if target.type == "hero":
		var resist := 0.0
		match damage_type:
			"physical":
				resist = maxf(0.0, float(target.get("armor", 0.0)))
			"magic":
				resist = maxf(0.0, float(target.get("magic_resist", 0.0)))
			_:
				resist = 0.0
		if resist > 0.0:
			incoming *= MATCH_MITIGATION_K / (MATCH_MITIGATION_K + resist)
	# 交手即暴露：草丛里的英雄一出手/一挨打就短暂显形，否则回放里会出现
	# 「血条自己掉、伤害来源不可见」的诡异画面。
	if target.type == "hero" and not source.is_empty() and str(source.get("team", "")) != str(target.get("team", "")):
		target["revealed_timer"] = REVEAL_AFTER_COMBAT
		if str(source.get("type", "")) == "hero":
			source["revealed_timer"] = REVEAL_AFTER_COMBAT
	# 交手记账必须在护盾结算之前。被盾吃掉的伤害同样是「有人打我」：
	# 脱战回血计时、回城/传送打断、击杀归属、助攻都读这些字段，
	# 放在护盾 return 之后会让「打盾」变成完全没有战斗痕迹。
	if not source.is_empty():
		target["last_attacker_id"] = int(source.get("id", -1))
		target["last_attacker_time"] = float(state.time)
	if target.type == "hero":
		target.last_damage_time = float(state.time)
		# 受击打断引导：只有真正中断的那一次才发事件（interrupt 幂等）。
		if RecallRules.interrupt(target):
			_emit("recall_interrupt", {
				"team": target.team,
				"hero": target.id,
				"x": float(target.get("recall_from", target.pos).x),
				"y": float(target.get("recall_from", target.pos).y),
			})
		if Teleport.interrupt(target):
			_emit("teleport_interrupt", {
				"team": target.team,
				"hero": target.id,
				"x": float(target.get("teleport_from", target.pos).x),
				"y": float(target.get("teleport_from", target.pos).y),
			})
		if not source.is_empty():
			if str(source.get("type", "")) == "hero" and str(source.get("team", "")) != str(target.get("team", "")):
				target.last_hero_attacker_id = int(source.get("id", -1))
				target.last_hero_attacker_time = float(state.time)
				# 助攻要靠「所有打过他的人」，单靠 last_hero_attacker 只留得下最后一下。
				var damagers: Dictionary = target.get("hero_damagers", {})
				damagers[int(source.get("id", -1))] = float(state.time)
				target["hero_damagers"] = damagers
	# —— 面板统计 ——
	# 记的是护盾结算**之前**的伤害：被盾吃掉的输出一样是玩家打出来的，
	# 面板要能回答「谁在打输出」，而不是「谁把盾打破了」。
	if not source.is_empty() and str(source.get("type", "")) == "hero":
		source["damage_dealt"] = float(source.get("damage_dealt", 0.0)) + incoming
	if target.type == "hero":
		target["damage_taken"] = float(target.get("damage_taken", 0.0)) + incoming
	var remaining := incoming
	if float(target.get("shield", 0.0)) > 0.0:
		var absorbed: float = minf(float(target.shield), remaining)
		target.shield = float(target.shield) - absorbed
		remaining -= absorbed
		if target.type == "base":
			target["last_shield_hit_time"] = float(state.time)
	if remaining <= 0.0:
		return
	target.hp = float(target.hp) - remaining
	# 项 3.5：**小兵打小兵不广播 hit**。
	# 实测事件构成：hit 占 7301 次（总量 65% 的大头之一），而双方小兵每波互殴
	# 会产生大量只为"飘个伤害数字"的事件。玩家不会去数小兵互相打了多少，
	# 这类事件纯属挤占 32 条/批的网络预算（峰值批里 hit 占 8/24）。
	# 注意：**伤害照常结算**，这里只是不发表现事件 —— 数值与胜负完全不受影响。
	# 英雄/塔/野怪参与的任何一次命中都照常广播。
	var quiet := str(target.type) == "minion" and not source.is_empty() \
		and str(source.get("type", "")) == "minion"
	if not quiet:
		_emit("hit", {
			"target": target.id,
			"target_type": target.type,
			# 表现层靠这两个字段找到出手者：野怪/小兵没有独立的 attack 事件，
			# 不给 source 就只能看到目标掉血、看不到谁打的。
			"source": int(source.get("id", -1)) if not source.is_empty() else -1,
			"source_type": str(source.get("type", "")),
			"x": float(target.pos.x),
			"y": float(target.pos.y),
			"amount": remaining,
			"team": target.team,
		})
	if float(target.hp) <= 0.0:
		_kill_entity(target, source)

func _kill_entity(target: Dictionary, source: Dictionary) -> void:
	if not target.alive:
		return
	target.hp = 0.0
	target.alive = false
	if target.type == "hero":
		target.deaths = int(target.deaths) + 1
		target.respawn_timer = HERO_RESPAWN_BASE + float(target.level) * 0.4
		target.shield = 0.0
		target.shield_timer = 0.0
		RecallRules.interrupt(target)

		# 判定真正击杀者 (Killer Attribution)
		var killer: Dictionary = {}
		# 1. 致命伤害直接来自敌方英雄
		if not source.is_empty() and str(source.get("type", "")) == "hero" and str(source.get("team", "")) != str(target.get("team", "")):
			killer = source
		# 2. 致命伤害来自防御塔/小兵/机关等非英雄，但近期受到敌方英雄伤害（10秒内判定为英雄击杀）
		elif float(state.time) - float(target.get("last_hero_attacker_time", -999.0)) <= ASSIST_WINDOW:
			var hero_attacker: Dictionary = _entity_by_id(int(target.get("last_hero_attacker_id", -1)))
			if not hero_attacker.is_empty() and str(hero_attacker.get("type", "")) == "hero" and str(hero_attacker.get("team", "")) != str(target.get("team", "")):
				killer = hero_attacker
		# 3. 致命伤害来自防御塔/小兵，无英雄参与伤害
		elif not source.is_empty():
			killer = source

		var killer_id: int = -1
		var killer_type := "unknown"
		var killer_name := "战场机关"
		var killer_team: String = "blue" if str(target.team) == "red" else "red"
		var killer_hero_type := ""

		if not killer.is_empty():
			killer_id = int(killer.get("id", -1))
			killer_type = str(killer.get("type", "unknown"))
			killer_team = str(killer.get("team", killer_team))
			if killer_type == "hero":
				killer_name = str(killer.get("name", "英雄"))
				killer_hero_type = str(killer.get("hero_type", ""))
				killer.kills = int(killer.get("kills", 0)) + 1
				state.scores[killer.team].kills = int(state.scores[killer.team].kills) + 1
				_award_assists(target, killer_id)
				EconomySystem.award_hero_kill(killer, kill_log.is_empty())
				_add_xp(killer, 130.0)
			elif killer_type == "tower" or killer_type == "base":
				killer_name = "防御塔" if killer_type == "tower" else "主堡"
			elif killer_type == "minion":
				killer_name = "小兵"
			elif killer_type == "monster":
				killer_name = str(killer.get("name", "野怪"))
			else:
				killer_name = str(killer.get("name", "战场机关"))

		target["last_killer_id"] = killer_id
		target["last_killer_name"] = killer_name
		target["last_killer_type"] = killer_type
		target["last_killer_team"] = killer_team

		var announce: Dictionary
		if killer_type == "hero":
			announce = _announcer.record_kill(
				killer_id, killer_hero_type, killer_team,
				int(target.id), str(target.hero_type), str(target.team), float(state.time)
			)
		else:
			announce = _announcer.record_death(int(target.id))

		var kill_record := {
			"time": float(state.time),
			"victim_id": int(target.id),
			"victim_name": str(target.name),
			"victim_team": str(target.team),
			"victim_hero_type": str(target.hero_type),
			"killer_id": killer_id,
			"killer_name": killer_name,
			"killer_team": killer_team,
			"killer_type": killer_type,
			"killer_hero_type": killer_hero_type,
			"announcement": str(announce.get("announcement", "")),
			"streak_title": str(announce.get("streak_title", "")),
		}
		kill_log.append(kill_record)

		_emit("death", {
			"entity_type": "hero",
			"hero": target.id,
			"team": target.team,
			"hero_type": target.hero_type,
			"victim_name": str(target.name),
			"victim_team": str(target.team),
			"victim_id": int(target.id),
			"killer": killer_id,
			"killer_id": killer_id,
			"killer_type": killer_type,
			"killer_name": killer_name,
			"killer_hero_type": killer_hero_type,
			"killer_team": killer_team,
			"announcement": str(announce.get("announcement", "")),
			"streak_title": str(announce.get("streak_title", "")),
			"x": float(target.pos.x),
			"y": float(target.pos.y),
		})
		if _announcer.check_ace(str(target.team), state.entities):
			_emit("ace", {
				"team": target.team,
				"victim_team": target.team,
			})
	elif target.type == "minion":
		target.death_cleanup_timer = 2.0
		if not source.is_empty() and source.type == "hero":
			_add_xp(source, 32.0)
			_award_minion_gold(target, source)
		else:
			_award_minion_gold(target, {})
		_emit("death", {
			"entity_type": "minion",
			"team": target.team,
			"x": float(target.pos.x),
			"y": float(target.pos.y),
		})
	elif target.type == "monster":
		target.respawn_timer = float(target.get("respawn_time", Jungle.RESPAWN_TIME))
		target.last_attacker_id = -1
		target.last_attacker_time = -999.0
		if bool(target.get("objective", false)):
			if not source.is_empty() and str(source.get("type", "")) == "hero":
				Objectives.grant_buff(state, str(source.get("team", "")))
				_add_xp(source, 160.0)
			_emit("objective_killed", {
				"team": str(source.get("team", "")),
				"name": str(target.get("name", "首领")),
				"objective_id": str(target.get("objective_id", "")),
				"x": float(target.pos.x),
				"y": float(target.pos.y),
			})
		elif bool(target.get("river_spirit", false)):
			if not source.is_empty() and str(source.get("type", "")) == "hero":
				River.grant_reveal(state, str(source.get("team", "")), target.pos)
				_add_xp(source, River.SPIRIT_XP)
			_emit("river_spirit_killed", {
				"team": str(source.get("team", "")),
				"name": str(target.get("name", "河道之灵")),
				"x": float(target.pos.x),
				"y": float(target.pos.y),
			})
		else:
			var buff_type := str(target.get("buff_type", ""))
			var xp_gain := float(target.get("xp", 45.0))
			if not source.is_empty() and str(source.get("type", "")) == "hero":
				# 小野点没有增益，不能发 buff_taken：事件白名单里 buff 为空时
				# 播报层会把它误读成红 BUFF。
				if buff_type != "":
					Jungle.apply_buff(source, buff_type)
				_add_xp(source, xp_gain)
			if buff_type != "":
				_emit("buff_taken", {
					"team": str(source.get("team", "")),
					"buff": buff_type,
					"name": str(target.get("name", "野怪")),
					"x": float(target.pos.x),
					"y": float(target.pos.y),
				})
		_emit("death", {
			"entity_type": "monster",
			"team": "neutral",
			"name": str(target.get("name", "野怪")),
			"x": float(target.pos.x),
			"y": float(target.pos.y),
		})
	elif target.type == "guard":
		var info: Dictionary = Crystal.on_guard_destroyed(state, target)
		if not source.is_empty() and source.type == "hero":
			_add_xp(source, 120.0)
		_emit("guard_destroyed", {
			"team": target.team,
			"side": str(target.get("side", "")),
			"guards_left": int(info.get("guards_alive", 0)),
			"x": float(target.pos.x),
			"y": float(target.pos.y),
		})
		if bool(info.get("broken", false)):
			_emit("crystal_shield_broken", {
				"team": target.team,
				"x": float(target.pos.x),
				"y": float(target.pos.y),
			})
		_emit("death", {
			"entity_type": "guard",
			"team": target.team,
			"x": float(target.pos.x),
			"y": float(target.pos.y),
		})
	elif target.type == "tower":
		var winner_team := "blue" if target.team == "red" else "red"
		state.scores[winner_team].towers = int(state.scores[winner_team].towers) + 1
		EconomySystem.award_tower_team_gold(winner_team, state.entities)
		if not source.is_empty() and source.type == "hero":
			_add_xp(source, 80.0)
			source["tower_kills"] = int(source.get("tower_kills", 0)) + 1
		_emit("tower_destroyed", {
			"team": target.team,
			"lane": target.lane,
			"tier": str(target.get("tier", "")),
			"x": float(target.pos.x),
			"y": float(target.pos.y),
		})
		if str(target.get("tier", "")) == "high":
			_emit("base_exposed", {"team": target.team, "lane": target.lane})
	elif target.type == "base":
		state.winner = "blue" if target.team == "red" else "red"
		ended = true
		_emit("match_end", {"winner": state.winner})

func _award_assists(victim: Dictionary, killer_id: int) -> void:
	# 助攻 = 在窗口内对目标造成过伤害的其他敌方英雄。
	# 击杀者自己不算；窗口结束后清账，避免下一次团战把旧账算进来。
	var damagers: Dictionary = victim.get("hero_damagers", {})
	if damagers.is_empty():
		return
	var now := float(state.time)
	var victim_team := str(victim.get("team", ""))
	for key in damagers.keys():
		var hero_id := int(key)
		if hero_id == killer_id:
			continue
		if now - float(damagers[key]) > ASSIST_WINDOW:
			continue
		var helper: Dictionary = _entity_by_id(hero_id)
		if helper.is_empty() or str(helper.get("type", "")) != "hero":
			continue
		if str(helper.get("team", "")) == victim_team:
			continue
		helper["assists"] = int(helper.get("assists", 0)) + 1
	victim["hero_damagers"] = {}

func _award_minion_gold(victim: Dictionary, last_hitter: Dictionary) -> void:
	const ASSIST_RADIUS := 8.0
	if not last_hitter.is_empty():
		EconomySystem.award_minion_kill(last_hitter, true)
		for entity in state.entities:
			if entity.type != "hero" or not entity.alive:
				continue
			if str(entity.team) != str(last_hitter.team) or int(entity.id) == int(last_hitter.id):
				continue
			if entity.pos.distance_to(victim.pos) <= ASSIST_RADIUS:
				EconomySystem.award_minion_kill(entity, false)
		return
	# 没有英雄补刀时，最近的一名敌方英雄获得基础金币，避免小兵对拼时经济完全断流。
	var best: Dictionary = {}
	var best_dist := ASSIST_RADIUS
	for entity in state.entities:
		if entity.type != "hero" or not entity.alive:
			continue
		if str(entity.team) == str(victim.get("team", "")):
			continue
		var dist: float = entity.pos.distance_to(victim.pos)
		if dist <= best_dist:
			best_dist = dist
			best = entity
	if not best.is_empty():
		EconomySystem.award_minion_kill(best, false)

func _next_random() -> float:
	_rng_state = (_rng_state * 1103515245 + 12345) & 0x7FFFFFFF
	return float(_rng_state) / 2147483648.0

func _add_xp(hero: Dictionary, amount: float) -> void:
	if hero.type != "hero" or not hero.alive:
		return
	hero.xp = float(hero.xp) + amount
	while int(hero.level) < MAX_LEVEL and float(hero.xp) >= _xp_needed(int(hero.level)):
		hero.xp = float(hero.xp) - _xp_needed(int(hero.level))
		hero.level = int(hero.level) + 1
		var hero_def: Dictionary = HeroDefs.get_hero(str(hero.hero_type))
		# 成长值写进 base_*，再由装备系统统一重算，避免装备加成被升级覆盖或重复叠加。
		hero.base_hp = float(hero.get("base_hp", hero.max_hp)) + float(hero_def.hp_growth)
		hero.base_ad = float(hero.get("base_ad", hero.attack_damage)) + float(hero_def.damage_growth)
		hero.max_mp = float(hero.max_mp) + float(hero_def.mp_growth)
		ItemShop.recalculate_stats(hero)
		hero.hp = minf(float(hero.max_hp), float(hero.hp) + float(hero_def.hp_growth))
		hero.mp = minf(float(hero.max_mp), float(hero.mp) + float(hero_def.mp_growth))
		# 项 2：每升 1 级给 1 点技能点。1 级（出生）不给，所以发点数发生在升级之后。
		hero.skill_points = int(hero.get("skill_points", 0)) + 1
		if bool(config.get("auto_skill_points", true)):
			_auto_spend(hero)
		_emit("level_up", {"hero": hero.id, "level": hero.level})

func _xp_needed(level: int) -> float:
	return 120.0 + float(level - 1) * 90.0

# --- 技能等级化（项 2）-----------------------------------------------------

# 某个技能槽位的等级上限：大招 3 级，其余 6 级。
static func skill_cap(slot: String) -> int:
	return MAX_SKILL_LEVEL_ULT if slot == "r" else MAX_SKILL_LEVEL_NORMAL

# 学/升大招需要的英雄等级：0→1 要 4 级，1→2 要 7 级，2→3 要 10 级。
# 普通技能不设英雄等级门槛（点数本身受等级约束，攒不满就点不动），
# 只有大招需要，因为"4 级解锁大招"是 MOBA 的核心节奏器。
static func ult_require_level(current_r_level: int) -> int:
	if current_r_level < 0 or current_r_level >= ULT_UNLOCK_LEVELS.size():
		return 9999
	return int(ULT_UNLOCK_LEVELS[current_r_level])

# 花 1 点技能点升某个槽位。返回 false 时**绝不消耗点数**（非法请求不能吞点）。
func spend_skill_point(hero: Dictionary, slot: String) -> bool:
	if hero.is_empty() or not SKILL_SLOTS.has(slot):
		return false
	if int(hero.get("skill_points", 0)) <= 0:
		return false
	var lv := HeroDefs.skill_level(hero, slot)
	if lv >= skill_cap(slot):
		return false
	if slot == "r" and int(hero.get("level", 1)) < ult_require_level(lv):
		return false
	hero["skill_%s_level" % slot] = lv + 1
	hero["skill_points"] = int(hero.get("skill_points", 0)) - 1
	_emit("skill_upgrade", {"hero": hero.get("id", -1), "slot": slot, "level": lv + 1})
	return true

# 自动加点：按英雄预设的逐等级表点技能。表里第 i 项对应"升到 i+2 级"那一次。
# 表项非法（撞上限/门槛）时退回到"点当前等级最低且合法的技能"，
# 保证点数不会凭空消失 —— 那正是"点数被吞且不报错"的静默失效形态。
func _auto_spend(hero: Dictionary) -> void:
	if int(hero.get("skill_points", 0)) <= 0:
		return
	var plan: Array = HeroDefs.get_hero(str(hero.get("hero_type", "blade"))).get("skill_plan", [])
	var index := int(hero.get("level", 1)) - 2
	if index >= 0 and index < plan.size():
		if spend_skill_point(hero, str(plan[index])):
			return
	for slot in SKILL_SLOTS:
		if int(hero.get("skill_points", 0)) <= 0:
			return
		if HeroDefs.skill_level(hero, slot) < skill_cap(slot):
			spend_skill_point(hero, slot)
			return


func _entity_by_id(entity_id: int) -> Dictionary:
	for entity in state.entities:
		if entity.id == entity_id:
			return entity
	return {}

# --- 开发者调试接口 ---------------------------------------------------------
# 只给主机用：客机没有 sim，这些方法根本不会被调用。
# 全部走 owner_id 而不直接收字典，避免表现层拿着过期实体引用改到复制出来的快照。

func debug_hero(owner_id: String) -> Dictionary:
	return get_hero_by_player(owner_id)

func debug_level_up(owner_id: String) -> bool:
	var hero: Dictionary = get_hero_by_player(owner_id)
	if hero.is_empty() or not bool(hero.get("alive", false)):
		return false
	if int(hero.level) >= MAX_LEVEL:
		return false
	# 只补到「刚好升一级」的经验，避免连升两级把等级 +1 变成 +2。
	var amount: float = maxf(0.0, _xp_needed(int(hero.level)) - float(hero.xp))
	_add_xp(hero, amount)
	return true

func debug_add_gold(owner_id: String, amount: int) -> bool:
	var hero: Dictionary = get_hero_by_player(owner_id)
	if hero.is_empty():
		return false
	hero.gold = int(hero.get("gold", 0)) + maxi(0, amount)
	return true

func debug_heal(owner_id: String) -> bool:
	var hero: Dictionary = get_hero_by_player(owner_id)
	if hero.is_empty() or not bool(hero.get("alive", false)):
		return false
	hero.hp = float(hero.max_hp)
	hero.mp = float(hero.max_mp)
	return true

func debug_teleport_hero(owner_id: String, pos: Vector2) -> bool:
	var hero: Dictionary = get_hero_by_player(owner_id)
	if hero.is_empty() or not bool(hero.get("alive", false)):
		return false
	# 走 nearest_free 而不是直接赋值：传进墙里会让英雄卡死，回城/传送也读 pos。
	hero.pos = Collision.nearest_free(pos, float(hero.get("radius", 0.55)))
	hero.moving = false
	hero["recall_from"] = hero.pos
	return true

func debug_clear_minions() -> int:
	var removed := 0
	for i in range(state.entities.size() - 1, -1, -1):
		if str(state.entities[i].get("type", "")) == "minion":
			state.entities.remove_at(i)
			removed += 1
	return removed

func debug_respawn_monsters() -> int:
	var revived := 0
	for entity in state.entities:
		if str(entity.get("type", "")) != "monster" or bool(entity.get("alive", false)):
			continue
		_respawn_monster(entity)
		revived += 1
	return revived

func snapshot() -> Dictionary:
	var entities: Array = []
	for entity in state.entities:
		entities.append(_snapshot_entity(entity))
	var events: Array = []
	for event in state.events:
		events.append(event.duplicate())
	return {
		"time": float(state.time),
		"winner": state.winner,
		"mode": mode,
		"bounds": float(state.bounds),
		"ended": ended,
		"entities": entities,
		"scores": state.scores.duplicate(true),
		"board": _snapshot_board(),
		"events": events,
		"wave": state.wave,
		"objectives": _snapshot_objectives(),
		"river": _snapshot_river(),
	}

# 客机视角快照：只包含己方与视野内目标，避免全图透视。
# events_override 用于联机广播：服务端把两次快照之间的全部事件攒下来传入，
# 避免 10Hz 快照只带得走最后 1/30 秒的事件。
# base 允许主机复用同一份世界快照按队伍过滤：2 队 × 10Hz 不再重复构建两次全量快照。
# filter_snapshot 会先深拷贝，传入的 base 不会被改写。
func snapshot_for(team: String, events_override: Variant = null, base: Variant = null) -> Dictionary:
	var shot: Dictionary
	var shared := false
	if base is Dictionary and not (base as Dictionary).is_empty():
		shot = base
		shared = true
	else:
		shot = snapshot()
	if events_override is Array:
		if shared:
			shot = shot.duplicate(false)
		shot["events"] = (events_override as Array).duplicate(true)
	return Vision.filter_snapshot(shot, team)

# 联机事件包：只按队伍可见性过滤事件，不构造整份快照。
# 与 snapshot_for 共用 Vision 的同一套规则，避免两条路径对「敌人是否看得见」判断不一致。
func events_for(team: String, events: Array) -> Array:
	River.ensure_state(state)
	var per_team: Dictionary = state.river.get("reveals", {})
	var reveals: Array = per_team.get(team, []) if per_team.get(team, null) is Array else []
	return Vision.filter_events(events, team, state.entities, reveals)

# 双方账本：计分板用的全员公开统计。
#
# 为什么不复用 entities：entities 要过视野过滤，敌方英雄在战争迷雾里会被剔掉，
# 计分板就会缺人。而「对面几级、几个人头、多少钱」在 MOBA 里是公开战报。
# 这张表只放统计，不放坐标，所以不会变成透视。
func _snapshot_board() -> Dictionary:
	var blue: Array = []
	var red: Array = []
	for entity in state.entities:
		if str(entity.type) != "hero":
			continue
		var inventory: Array = entity.get("inventory", [])
		var item_value := 0
		for item_id in inventory:
			item_value += int(ItemShop.get_item(str(item_id)).get("cost", 0))
		var gold := int(entity.get("gold", 0))
		var alive := bool(entity.get("alive", true))
		var hero_type := str(entity.get("hero_type", "blade"))
		var row := {
			"id": int(entity.id),
			"owner_id": str(entity.get("owner_id", "")),
			"name": str(entity.get("name", "")),
			"team": str(entity.team),
			"hero_type": hero_type,
			"role": str(HeroDefs.get_hero(hero_type).get("role", "")),
			"lane": str(entity.get("lane", "")),
			"controller": str(entity.get("controller", "")),
			"level": int(entity.level),
			"kills": int(entity.kills),
			"deaths": int(entity.deaths),
			"assists": int(entity.get("assists", 0)),
			"cs": int(entity.get("cs", 0)),
			"gold": gold,
			# 总经济的口径 = 手上的钱 + 已买装备的原价。
			# 买装备不改变总经济，只改变它的形态；这符合玩家的直觉。
			"net_worth": gold + item_value,
			# 面板要能回答「他出了什么装、打多少输出、扛多少伤害、推了几座塔」。
			# 这几项都是公开战报，不带坐标，不会变成透视。
			"item_value": item_value,
			"damage_dealt": float(entity.get("damage_dealt", 0.0)),
			"damage_taken": float(entity.get("damage_taken", 0.0)),
			"tower_kills": int(entity.get("tower_kills", 0)),
			# 当前面板属性（已含装备加成，recalculate_stats 写回的实时值）。
			"attack_damage": float(entity.get("attack_damage", 0.0)),
			"ability_power": float(entity.get("ability_power", 0.0)),
			"max_hp": float(entity.get("max_hp", 0.0)),
			"speed": float(entity.get("speed", 0.0)),
			"crit_rate": float(entity.get("crit_rate", 0.0)),
			# 防御与成长属性（项 1，链路 3）：详情面板要回答"他扛不扛得住"。
			# 与坐标无关，属于公开战报，不构成透视。
			"armor": float(entity.get("armor", 0.0)),
			"magic_resist": float(entity.get("magic_resist", 0.0)),
			"cooldown_reduction": float(entity.get("cooldown_reduction", 0.0)),
			"attack_speed": float(entity.get("attack_speed", 0.0)),
			"crit_damage": float(entity.get("crit_damage", 1.5)),
			"alive": alive,
			"respawn_timer": 0.0 if alive else float(entity.get("respawn_timer", 0.0)),
			"inventory": inventory.duplicate(),
		}
		if str(entity.team) == "blue":
			blue.append(row)
		else:
			red.append(row)
	blue.sort_custom(_board_row_before)
	red.sort_custom(_board_row_before)
	return {
		"blue": blue,
		"red": red,
		"net_worth": {
			"blue": _sum_net_worth(blue),
			"red": _sum_net_worth(red),
		},
		# 面板要算分均经济，需要「这局打了多久」。跟着 board 一起走，
		# 免得 UI 再去猜时间戳（客机的本地时钟和服务端不是同一个）。
		"time": float(state.time),
	}

func _board_row_before(a: Dictionary, b: Dictionary) -> bool:
	return int(a.get("id", 0)) < int(b.get("id", 0))

func _sum_net_worth(rows: Array) -> int:
	var total := 0
	for row in rows:
		total += int(row.get("net_worth", 0))
	return total

func _snapshot_objectives() -> Dictionary:
	var spawn_timer := float(state.objective.get("spawn_timer", 0.0))
	if bool(state.objective.get("spawned", false)):
		spawn_timer = 0.0
		var pending := 0.0
		var waiting := false
		for entity in state.entities:
			if entity.type != "monster" or not bool(entity.get("objective", false)):
				continue
			if bool(entity.get("alive", true)):
				continue
			var timer: float = float(entity.get("respawn_timer", Objectives.RESPAWN))
			pending = timer if not waiting else minf(pending, timer)
			waiting = true
		if waiting:
			spawn_timer = pending
	var buffs: Dictionary = state.objectives.get("buffs", {})
	return {
		"spawn_timer": spawn_timer,
		"blue_buff": float(buffs.get("blue", 0.0)),
		"red_buff": float(buffs.get("red", 0.0)),
	}

func _snapshot_river() -> Dictionary:
	River.ensure_state(state)
	var reveals: Dictionary = state.river.reveals
	return {
		"spawn_timer": float(state.river.get("spawn_timer", 0.0)),
		"reveals": {
			"blue": (reveals.get("blue", []) as Array).duplicate(true),
			"red": (reveals.get("red", []) as Array).duplicate(true),
		},
	}

func _snapshot_entity(entity: Dictionary) -> Dictionary:
	var pos: Vector2 = entity.pos
	var data := {
		"id": int(entity.id),
		"type": str(entity.type),
		"team": str(entity.team),
		"x": float(pos.x),
		"y": float(pos.y),
		"radius": float(entity.get("radius", 0.0)),
		"hp": float(entity.get("hp", 0.0)),
		"max_hp": float(entity.get("max_hp", 0.0)),
		"alive": bool(entity.get("alive", false)),
	}
	if entity.type == "hero":
		var facing: Vector2 = entity.facing
		data["owner_id"] = str(entity.owner_id)
		data["name"] = str(entity.name)
		data["hero_type"] = str(entity.hero_type)
		data["controller"] = str(entity.controller)
		data["lane"] = str(entity.lane)
		data["level"] = int(entity.level)
		data["xp"] = float(entity.xp)
		data["mp"] = float(entity.mp)
		data["max_mp"] = float(entity.max_mp)
		data["kills"] = int(entity.kills)
		data["deaths"] = int(entity.deaths)
		data["respawn_timer"] = 0.0 if entity.alive else float(entity.respawn_timer)
		data["skill_q_cd"] = float(entity.skill_q_cd)
		data["skill_w_cd"] = float(entity.get("skill_w_cd", 0.0))
		data["skill_e_cd"] = float(entity.skill_e_cd)
		data["skill_r_cd"] = float(entity.get("skill_r_cd", 0.0))
		# 项 2：技能等级与剩余点数进快照，否则客机技能按钮永远显示未学习（不报错）。
		data["skill_q_level"] = HeroDefs.skill_level(entity, "q")
		data["skill_w_level"] = HeroDefs.skill_level(entity, "w")
		data["skill_e_level"] = HeroDefs.skill_level(entity, "e")
		data["skill_r_level"] = HeroDefs.skill_level(entity, "r")
		data["skill_points"] = int(entity.get("skill_points", 0))
		data["summoner_cd"] = float(entity.get("summoner_cd", 0.0))
		data["summoner_spell"] = str(entity.get("summoner_spell", "flash"))
		data["gold"] = int(entity.get("gold", 0))
		data["cs"] = int(entity.get("cs", 0))
		data["inventory"] = (entity.get("inventory", []) as Array).duplicate()
		data["ability_power"] = float(entity.get("ability_power", 0.0))
		data["crit_rate"] = float(entity.get("crit_rate", 0.0))
		# 战斗属性（项 1，链路 3）：漏一个键 = HUD/详情永远读到默认值且不报错。
		data["armor"] = float(entity.get("armor", 0.0))
		data["magic_resist"] = float(entity.get("magic_resist", 0.0))
		data["cooldown_reduction"] = float(entity.get("cooldown_reduction", 0.0))
		data["attack_speed"] = float(entity.get("attack_speed", 0.0))
		data["crit_damage"] = float(entity.get("crit_damage", 1.5))
		data["hp_regen"] = float(entity.get("hp_regen", 0.0))
		data["mana_regen"] = float(entity.get("mana_regen", 0.0))
		data["speed"] = float(entity.speed)
		data["shield"] = float(entity.shield)
		data["facing_x"] = float(facing.x)
		data["facing_y"] = float(facing.y)
		data["attack_cd"] = float(entity.attack_cd)
		data["haste_timer"] = float(entity.haste_timer)
		data["slow_timer"] = float(entity.slow_timer)
		# 硬控（项 4，链路 3）：客机要靠这些画头顶状态图标。
		# 同时下发聚合状态码 cc_status，免得客机自己按优先级重算一遍 ——
		# "哪个控更重"属于规则，双实现必然漂移。空串表示未被控。
		data["stun_timer"] = float(entity.get("stun_timer", 0.0))
		data["knockup_timer"] = float(entity.get("knockup_timer", 0.0))
		data["silence_timer"] = float(entity.get("silence_timer", 0.0))
		data["root_timer"] = float(entity.get("root_timer", 0.0))
		data["cc_status"] = ControlRules.dominant_status(entity)
		data["moving"] = bool(entity.get("moving", false))
		data["last_killer_name"] = str(entity.get("last_killer_name", ""))
		data["recalling"] = bool(entity.get("recalling", false))
		data["recall_timer"] = float(entity.get("recall_timer", 0.0))
		data["recall_total"] = float(entity.get("recall_total", 0.0))
		data["teleporting"] = bool(entity.get("teleporting", false))
		data["teleport_timer"] = float(entity.get("teleport_timer", 0.0))
		data["teleport_total"] = float(entity.get("teleport_total", 0.0))
		data["teleport_cd"] = float(entity.get("teleport_cd", 0.0))
		data["buff_red_timer"] = float(entity.get("buff_red_timer", 0.0))
		data["buff_blue_timer"] = float(entity.get("buff_blue_timer", 0.0))
		data["revealed_timer"] = float(entity.get("revealed_timer", 0.0))
		# 客机用它把「已被服务端处理的最后一个输入」对掉，剩余输入重放。
		data["last_input_seq"] = int(entity.get("last_input_seq", -1))
	elif entity.type == "minion":
		data["lane"] = str(entity.lane)
		data["minion_type"] = str(entity.get("minion_type", "melee"))
		data["speed"] = float(entity.speed)
		data["moving"] = bool(entity.get("moving", false))
	elif entity.type == "tower":
		data["lane"] = str(entity.lane)
		data["tier"] = str(entity.get("tier", "outer"))
		data["range"] = float(entity.range)
		data["vulnerable"] = TowerRules.is_tower_vulnerable(entity, state.entities)
	elif entity.type == "guard":
		data["lane"] = str(entity.get("lane", "core"))
		data["tier"] = str(entity.get("tier", "twin"))
		data["side"] = str(entity.get("side", ""))
		data["range"] = float(entity.get("range", 7.0))
		data["vulnerable"] = Crystal.is_guard_vulnerable(entity, state.entities)
	elif entity.type == "base":
		data["vulnerable"] = TowerRules.is_base_vulnerable(entity, state.entities)
		data["shield"] = float(entity.get("shield", 0.0))
		data["shield_max"] = float(entity.get("shield_max", 0.0))
		data["guards_alive"] = int(entity.get("guards_alive", 0))
		# 主堡也打人（射程 9 米）。漏了这条，客户端只能用默认值画范围圈。
		data["range"] = float(entity.get("range", BASE_RANGE))
	elif entity.type == "monster":
		data["monster_type"] = str(entity.get("monster_type", "wolf"))
		data["camp_id"] = str(entity.get("camp_id", ""))
		data["buff_type"] = str(entity.get("buff_type", ""))
		data["objective"] = bool(entity.get("objective", false))
		data["objective_id"] = str(entity.get("objective_id", ""))
		data["name"] = str(entity.get("name", "野怪"))
		data["respawn_timer"] = float(entity.get("respawn_timer", 0.0)) if not bool(entity.get("alive", true)) else 0.0
	elif entity.type == "projectile":
		# 项 3（链路 3）：客机必须能画出真实弹道，否则就是"血凭空掉"。
		# 方向拍平成 dir_x/dir_y 两个标量：协议层只接受数值字段做钳制，
		# 传 Vector2 会在 _sanitize_entity 里被 _number() 吃成 0，弹道全变成横向直线。
		var dir: Vector2 = entity.get("dir", Vector2.RIGHT)
		data["dir_x"] = float(dir.x)
		data["dir_y"] = float(dir.y)
		data["speed"] = float(entity.get("speed", 0.0))
		data["lifetime"] = float(entity.get("lifetime", 0.0))
		data["age"] = float(entity.get("age", 0.0))
		data["kind"] = str(entity.get("kind", ""))
		data["slot"] = str(entity.get("slot", ""))
		data["owner_id"] = int(entity.get("owner_id", 0))
		data["aoe_radius"] = float(entity.get("aoe_radius", 0.0))
	return data

func get_last_kill() -> Dictionary:
	return kill_log.back() if not kill_log.is_empty() else {}

func get_killer_of(victim_id: int) -> Dictionary:
	for i in range(kill_log.size() - 1, -1, -1):
		if int(kill_log[i].victim_id) == victim_id:
			return kill_log[i]
	return {}
