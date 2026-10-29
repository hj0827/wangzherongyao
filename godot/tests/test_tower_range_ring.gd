extends "res://tests/test_base.gd"

## 防御塔攻击范围圈。
##
## 玩家问的是「塔能打到哪里」，所以圈必须画在**塔真实的攻击半径**上
## （普通塔 8 / 双生塔 7 / 主堡 9，取自实体自己的 range 字段），
## 而不是拍一个好看的数字。本地英雄踏进敌方范围时整圈变红。
##
## 圈默认**不画**：整张图十几座塔同时铺射程圈就是一片蓝雾。只有敌方小兵/英雄
## 真的踏进这座塔的射程（塔马上要开火）时才亮起，这才是玩家要的那条线。
##
## 判定逻辑抽成静态纯函数，因为它同时要满足几件容易写错的事：
## 1. 只有**敌方**塔才警告（站在自家塔下不该满屏红光）；
## 2. 边界算「在内」（距离 <= range，和塔的命中判定一致）；
## 3. 死亡/缺席的本地英雄不能继续报警；
## 4. 亮圈只看塔真正会打的目标：敌方小兵/英雄；自家小兵、野怪不算。

const Arena = preload("res://scripts/game/arena.gd")
const MatchSim = preload("res://sim/match_sim.gd")
const NetProtocol = preload("res://net/net_protocol.gd")

const BLUE := Color(0.36, 0.68, 1.0)
const RED := Color(1.0, 0.42, 0.36)

func _sim() -> Object:
	return MatchSim.new({
		"mode": "duel",
		"humans": [{"id": "p1", "name": "T", "team": "blue", "hero_type": "blade"}],
		"bot_fill": false,
		"bot_ai": false,
	})

func _tower(x: float, y: float, attack_range: float, team := "red") -> Dictionary:
	return {"type": "tower", "team": team, "x": x, "y": y, "range": attack_range, "alive": true}

func _viewer(x: float, y: float, team := "blue", alive := true) -> Dictionary:
	return {"type": "hero", "team": team, "x": x, "y": y, "alive": alive}

func _enemy_minion(x: float, y: float, alive := true) -> Dictionary:
	return {"type": "minion", "team": "blue", "x": x, "y": y, "alive": alive}

func _enemy_hero(x: float, y: float, alive := true) -> Dictionary:
	return {"type": "hero", "team": "blue", "x": x, "y": y, "alive": alive}

func test_ring_radius_is_the_structure_own_attack_range() -> void:
	for attack_range in [7.0, 8.0, 9.0]:
		var state := Arena.range_ring_state(_tower(0.0, 0.0, attack_range), RED, {})
		near(float(state.radius), attack_range, 0.001, "圈半径必须等于该塔的攻击距离")

func test_ring_warns_when_local_hero_enters_enemy_range() -> void:
	var state := Arena.range_ring_state(_tower(0.0, 0.0, 8.0), RED, _viewer(6.0, 0.0))
	check(bool(state.warned), "英雄在敌方塔的射程内要报警")
	var color: Color = state.color
	gt(color.r - color.g, 0.35, "警告色必须偏红，而不是原阵营色")
	gt(color.r - color.b, 0.35, "警告色不能被蓝通道拉成紫/白")
	gt(color.a, 0.35, "警告圈要够亮才看得见")

func test_ring_stays_calm_when_hero_is_outside_range() -> void:
	var state := Arena.range_ring_state(_tower(0.0, 0.0, 8.0), RED, _viewer(9.5, 0.0))
	check(not bool(state.warned), "射程外不报警")
	var color: Color = state.color
	near(color.r, RED.r, 0.001, "不报警时保持阵营色")
	near(color.g, RED.g, 0.001, "不报警时保持阵营色")
	lt(color.a, 0.3, "平时要淡，否则整张地图都是圈")

func test_boundary_counts_as_inside() -> void:
	var state := Arena.range_ring_state(_tower(0.0, 0.0, 8.0), RED, _viewer(8.0, 0.0))
	check(bool(state.warned), "刚好站在边界上算在射程内（与塔的命中判定一致）")

func test_own_tower_never_warns() -> void:
	var state := Arena.range_ring_state(_tower(0.0, 0.0, 8.0, "blue"), BLUE, _viewer(1.0, 0.0, "blue"))
	check(not bool(state.warned), "站在自家塔下不该变红")
	near(state.color.r, BLUE.r, 0.001, "自家塔保持蓝色")

func test_dead_or_missing_hero_does_not_warn() -> void:
	check(not bool(Arena.range_ring_state(_tower(0.0, 0.0, 8.0), RED, _viewer(1.0, 0.0, "blue", false)).warned), "本地英雄阵亡时不该继续报警")
	check(not bool(Arena.range_ring_state(_tower(0.0, 0.0, 8.0), RED, {}).warned), "没有本地英雄时不报警")

func test_ring_is_hidden_when_nothing_attackable_is_inside() -> void:
	var tower := _tower(0.0, 0.0, 8.0)
	check(not Arena.range_ring_revealed(tower, []), "空场不显示范围圈")
	check(not bool(Arena.range_ring_state(tower, RED, {}).visible), "没有目标时整圈隐藏")
	check(not bool(Arena.range_ring_state(tower, RED, {}, []).visible), "显式传空列表也隐藏")

func test_enemy_minion_inside_turns_the_ring_on() -> void:
	var tower := _tower(0.0, 0.0, 8.0)
	check(Arena.range_ring_revealed(tower, [_enemy_minion(6.0, 0.0)]), "敌方小兵进圈要亮圈")
	check(bool(Arena.range_ring_state(tower, RED, {}, [_enemy_minion(6.0, 0.0)]).visible), "状态里的 visible 要跟着打开")
	check(not Arena.range_ring_revealed(tower, [_enemy_minion(9.5, 0.0)]), "圈外的小兵不亮圈")

func test_enemy_hero_inside_turns_the_ring_on_without_a_viewer() -> void:
	var tower := _tower(0.0, 0.0, 8.0)
	check(Arena.range_ring_revealed(tower, [_enemy_hero(1.0, 0.0)]), "敌方英雄进圈要亮圈")
	check(not Arena.range_ring_revealed(tower, [_enemy_hero(9.5, 0.0)]), "圈外的英雄不亮圈")
	check(not Arena.range_ring_revealed(tower, [_enemy_hero(1.0, 0.0, false)]), "阵亡英雄不亮圈")

func test_ring_ignores_allied_neutral_and_irrelevant_units() -> void:
	var tower := _tower(0.0, 0.0, 8.0)
	check(not Arena.range_ring_revealed(tower, [{"type": "minion", "team": "red", "x": 2.0, "y": 0.0, "alive": true}]), "自家小兵不是塔的攻击目标")
	check(not Arena.range_ring_revealed(tower, [{"type": "hero", "team": "red", "x": 2.0, "y": 0.0, "alive": true}]), "自家英雄不是塔的攻击目标")
	check(not Arena.range_ring_revealed(tower, [{"type": "monster", "team": "neutral", "x": 2.0, "y": 0.0, "alive": true}]), "野怪不触发（与塔的选靶规则一致）")
	check(not Arena.range_ring_revealed(tower, [{"type": "tower", "team": "blue", "x": 2.0, "y": 0.0, "alive": true}]), "建筑不是塔的普攻目标")

func test_minion_on_boundary_reveals_the_ring() -> void:
	check(Arena.range_ring_revealed(_tower(0.0, 0.0, 8.0), [_enemy_minion(8.0, 0.0)]), "边界算在射程内（与塔的命中判定一致）")

func test_revealed_ring_keeps_team_color_and_is_readable() -> void:
	var state := Arena.range_ring_state(_tower(0.0, 0.0, 8.0), RED, {}, [_enemy_minion(6.0, 0.0)])
	var color: Color = state.color
	near(color.r, RED.r, 0.001, "有目标但本地英雄没挨打时保持阵营色")
	near(color.g, RED.g, 0.001, "有目标但本地英雄没挨打时保持阵营色")
	gt(color.a, 0.25, "亮起的圈要看得见")
	check(not bool(state.warned), "小兵进圈不算本地英雄的警报")

func test_snapshot_carries_range_for_every_structure_type() -> void:
	# 范围圈的半径只能从快照里读，快照漏了这个字段就会静默退回默认 8 米，
	# 主堡（9 米）和双生塔（7 米）的圈都会画错，而且不会有任何报错。
	var sim := _sim()
	var snap: Dictionary = sim.snapshot()
	var kinds := {}
	for entity in snap.get("entities", []):
		var kind := str(entity.get("type", ""))
		if kind != "tower" and kind != "guard" and kind != "base":
			continue
		kinds[kind] = true
		gt(float(entity.get("range", 0.0)), 0.0, "%s 的快照必须带 range" % kind)
	eq(kinds.size(), 3, "塔 / 双生塔 / 主堡三种结构都要出现在快照里")
	var base: Dictionary = {}
	for entity in snap.get("entities", []):
		if str(entity.get("type", "")) == "base":
			base = entity
			break
	near(float(base.get("range", 0.0)), 9.0, 0.001, "主堡的射程是 9 米，不是塔的 8 米")

func test_net_protocol_keeps_structure_range() -> void:
	# 联机客机的快照要过一层白名单；白名单漏掉 range，客机上的圈同样会画错。
	var sim := _sim()
	var clean: Dictionary = NetProtocol.sanitize_snapshot(sim.snapshot())
	check(bool(clean.get("ok", false)), "快照能过白名单")
	var checked := 0
	for entity in clean.get("snapshot", {}).get("entities", []):
		var kind := str(entity.get("type", ""))
		if kind != "tower" and kind != "guard" and kind != "base":
			continue
		checked += 1
		gt(float(entity.get("range", 0.0)), 0.0, "白名单要保留 %s 的 range" % kind)
	gt(float(checked), 0.0, "白名单里至少要有一种结构")

func test_arena_actually_wires_the_ring_into_structure_views() -> void:
	# 「函数写好了但没人调用」是这个仓库踩过的坑：断言源码里真的接了线。
	var source := FileAccess.get_file_as_string("res://scripts/game/arena.gd")
	check(source.contains("\"range_ring\": range_ring"), "塔视图必须持有范围圈节点")
	check(source.contains("range_ring.visible = false"), "刚建出来的塔不能先亮一圈")
	var create_start := source.find("func _create_structure_view")
	var sync_start := source.find("func _sync_structures")
	check(create_start >= 0 and sync_start >= 0, "两个函数都要在")
	if create_start >= 0 and sync_start >= 0:
		# 只截 _sync_structures 自己的函数体：后面的静态判定函数不算「接了线」。
		var next_static := source.find("\nstatic func ", sync_start + 1)
		var sync_body := source.substr(sync_start, next_static - sync_start if next_static > sync_start else source.length() - sync_start)
		check(sync_body.contains("range_ring_state("), "范围圈的颜色要在 _sync_structures 里刷新")
		check(sync_body.contains("ring_state.visible"), "范围圈的显隐必须每帧跟随「有没有敌人进圈」")
		check(sync_body.contains("ring_targets"), "每帧同步要把小兵/英雄列表喂给同一套判定")
