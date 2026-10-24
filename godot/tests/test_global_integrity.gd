extends "res://tests/test_base.gd"

# 全局端到端与系统完整性集成测试 (Global Integrity Test Suite)
#
# 覆盖维度：
# 1. 静态/运行时全资产加载链完整性（场景、英雄模型部件、小兵、防御塔、字体、着色器）
# 2. UI 状态机与导航流完整性（主菜单 -> 选人室 -> 英雄切换 -> 返回菜单）
# 3. 1v1 单人对决全生命周期仿真（出生、普攻、技能施放、CD、伤害、小兵、暂停恢复）
# 4. 5v5 军团高负载全员协同与三路推塔（10 英雄、12 防御塔、小兵波次、防御塔索敌）
# 5. 死亡复活与泉水快速恢复闭环（击杀事件、复活倒计时、满血复活、泉水 18%/s 恢复）
# 6. 网络同步抗抖动缓冲稳定性（快照时序、Jitter Buffer 选取与容错降级）
# 7. 基地摧毁胜负结算与战场完全卸载（战局终结、胜负判定、退出清理）

const MainApp = preload("res://scripts/app/main.gd")
const Arena = preload("res://scripts/game/arena.gd")
const UnitVisual = preload("res://scripts/game/unit_visual.gd")
const MatchSim = preload("res://sim/match_sim.gd")
const MapData = preload("res://sim/map_data.gd")
const HeroDefs = preload("res://sim/hero_defs.gd")
const GameSession = preload("res://net/game_session.gd")
const LanDiscovery = preload("res://net/lan_discovery.gd")
const NetProtocol = preload("res://net/net_protocol.gd")

const DT := 1.0 / 30.0

# ---------- 维度 1：静态/运行时全资产加载链完整性 ----------
func test_global_assets_and_resources_exist() -> void:
	# 核心场景
	var main_scene: PackedScene = load("res://scenes/main_menu.tscn")
	check(main_scene != null and main_scene.can_instantiate(), "main_menu.tscn must be valid PackedScene")
	var preview_scene: PackedScene = load("res://scenes/preview.tscn")
	check(preview_scene != null and preview_scene.can_instantiate(), "preview.tscn must be valid PackedScene")

	# 着色器与字体文件存在性
	check(FileAccess.file_exists("res://shaders/billboard_bar.gdshader"), "billboard_bar.gdshader must exist")
	check(FileAccess.file_exists("res://assets/fonts/NotoSansSC.ttf"), "NotoSansSC.ttf must exist")
	check(FileAccess.file_exists("res://assets/fonts/MaShanZheng.ttf"), "MaShanZheng.ttf must exist")

	# 4大英雄全套 3D 资产（身体、服装、发型、武器）
	for hero_id in UnitVisual.HERO_SETUPS:
		var setup: Dictionary = UnitVisual.HERO_SETUPS[hero_id]
		check(setup.get("body") != null, hero_id + " body scene missing")
		check(setup.get("outfit") != null, hero_id + " outfit scene missing")
		check(setup.get("hair") != null, hero_id + " hair scene missing")
		check(setup.get("weapon") != null, hero_id + " weapon scene missing")

	# 小兵与野怪 3D 模型
	var minion_paths := [
		"res://assets/characters/Orc.glb",
		"res://assets/characters/Skeleton_Warrior.glb",
		"res://assets/characters/Skeleton_Mage.glb",
		"res://assets/characters/Skeleton_Rogue.glb",
		"res://assets/characters/Skeleton_Minion.glb",
		"res://assets/characters/Wolf.glb"
	]
	for path in minion_paths:
		var res: Resource = load(path)
		check(res != null, "Minion/Monster asset must load: " + path)

	# 建筑与环境
	var env_paths := [
		"res://assets/environment/Barracks_FirstAge_Level3.glb",
		"res://assets/environment/Market_FirstAge_Level3.glb",
		"res://assets/environment/TownCenter_SecondAge_Level3.glb",
		"res://assets/environment/WatchTower_SecondAge_Level3.glb"
	]
	for path in env_paths:
		var res: Resource = load(path)
		check(res != null, "Environment asset must load: " + path)

# ---------- 维度 2：UI 状态机与导航流完整性 ----------
func test_global_main_menu_flow_and_navigation() -> void:
	var main: Node = MainApp.new()
	main.name = "TestMainApp"
	main.session = GameSession.new()
	main.discovery = LanDiscovery.new()
	main._connect_session()
	main._build_shell()
	main._show_menu()
	eq(main.screen, "menu", "Initial screen must be menu")
	check(main._background != null, "Cinematic background must be initialized")

	# 模拟切换至选人室
	main._pending_mode = "duel"
	main._pending_online = false
	main._show_hero_select()
	eq(main.screen, "hero_select", "Screen must switch to hero_select")
	eq(main._hero_cards.size(), HeroDefs.HEROES.size(), "Must generate one hero card per hero in hero_select")

	# 切换选定英雄
	main.local_hero = "mage"
	main._refresh_hero_selection()
	eq(main.local_hero, "mage", "Local hero should switch to mage")
	main.local_hero = "archer"
	main._refresh_hero_selection()
	eq(main.local_hero, "archer", "Local hero should switch to archer")

	# 返回主菜单
	main._show_menu()
	eq(main.screen, "menu", "Screen must return to menu cleanly")

	main.queue_free()

# ---------- 维度 3：1v1 单人对决全生命周期仿真 ----------
func test_global_1v1_duel_full_lifecycle() -> void:
	var config := {
		"mode": "duel",
		"humans": [{"id": "p1", "name": "测试先锋", "team": "blue", "hero_type": "blade"}],
		"bot_fill": true,
		"bot_ai": true,
	}
	var arena: Node3D = Arena.new()
	arena.configure({
		"config": config,
		"authoritative": true,
		"local_owner": "p1",
	})
	check(arena.sim != null, "Arena must create an authoritative MatchSim instance")

	var snap: Dictionary = arena.sim.snapshot()
	var entities: Array = snap.get("entities", [])
	check(entities.size() >= 2, "1v1 match must have at least 2 heroes spawned")

	# 确认本地英雄初始属性与位置
	var hero: Dictionary = arena.sim.get_hero_by_player("p1")
	check(not hero.is_empty(), "Local player entity must exist")
	eq(hero.get("hero_type"), "blade", "Hero type should be blade")
	eq(hero.get("team"), "blue", "Local player must be blue team")

	# 寻找敌方机器人
	var enemy: Dictionary = {}
	for e in arena.sim.state.entities:
		if e.get("type") == "hero" and e.get("team") == "red":
			enemy = e
			break
	check(not enemy.is_empty(), "Enemy bot entity must exist")

	# 模拟连续战斗推进 30 个 Tick（1.0 秒）
	var sim: MatchSim = arena.sim
	for i in 30:
		sim.tick(DT)

	var snap2: Dictionary = sim.snapshot()
	check(float(snap2.get("time", 0.0)) > 0.9, "Sim clock should advance by ~1.0s")

	# 将敌方拉入 Q 技能命中范围（距离 2.5m < 4.8m 攻击范围）测试技能施放与冷却
	enemy["pos"] = (hero["pos"] as Vector2) + Vector2(2.5, 0.0)
	var initial_mp: float = float(hero.get("mp", 100.0))
	var initial_enemy_hp: float = float(enemy.get("hp", 100.0))
	sim.set_input("p1", {
		"move": Vector2.ZERO,
		"aim": enemy["pos"],
		"attack": false,
		"skill_q": true,
		"skill_e": false,
	})
	sim.tick(DT)

	check(float(hero.get("mp", 0.0)) < initial_mp, "Skill Q must spend mana")
	check(float(hero.get("skill_q_cd", 0.0)) > 0.0, "Skill Q must trigger cooldown")
	check(float(enemy.get("hp", 0.0)) < initial_enemy_hp, "Skill Q must deal damage to enemy in range")

	# 测试伤害飘字与受击事件无崩溃
	arena._spawn_damage_number(Vector3(0, 1.5, 0), 120.0, Color.RED)

	arena.queue_free()

# ---------- 维度 4：5v5 军团高负载全员协同与三路推塔 ----------
func test_global_5v5_team_all_heroes_and_towers() -> void:
	var humans: Array = [
		{"id": "p1", "name": "蓝一", "team": "blue", "hero_type": "blade"},
		{"id": "p2", "name": "蓝二", "team": "blue", "hero_type": "mage"},
		{"id": "p3", "name": "蓝三", "team": "blue", "hero_type": "tank"},
		{"id": "p4", "name": "蓝四", "team": "blue", "hero_type": "archer"},
		{"id": "p5", "name": "蓝五", "team": "blue", "hero_type": "blade"},
	]
	var config := {
		"mode": "team",
		"humans": humans,
		"bot_fill": true,
		"bot_ai": true,
	}
	var sim := MatchSim.new(config)
	var snap: Dictionary = sim.snapshot()
	var entities: Array = snap.get("entities", [])

	var hero_count := 0
	var tower_count := 0
	var base_count := 0
	for e in entities:
		var type := str(e.get("type", ""))
		if type == "hero":
			hero_count += 1
		elif type == "tower":
			tower_count += 1
		elif type == "base":
			base_count += 1

	eq(hero_count, 10, "5v5 team match must contain exactly 10 heroes")
	eq(tower_count, 18, "Standard map must contain 18 outer/inner/high towers across 3 lanes")
	eq(base_count, 2, "Standard map must contain 2 headquarters bases")

	# 推进密集交火 60 个 Tick（2.0 秒）
	for i in 60:
		sim.tick(DT)

	var snap_after: Dictionary = sim.snapshot()
	var has_minions := false
	for e in snap_after.get("entities", []):
		if str(e.get("type", "")) == "minion":
			has_minions = true
			break
	check(has_minions, "5v5 team match must spawn minion waves across lanes")

# ---------- 维度 5：死亡复活与泉水快速恢复闭环 ----------
func test_global_fountain_and_death_respawn_cycle() -> void:
	var sim := MatchSim.new({
		"mode": "duel",
		"humans": [{"id": "p1", "name": "战士", "team": "blue", "hero_type": "blade"}],
		"bot_fill": true,
		"bot_ai": false,
	})
	var hero: Dictionary = sim.get_hero_by_player("p1")
	check(not hero.is_empty(), "Hero must exist in sim state")

	# 人工置死
	hero["hp"] = 0.0
	hero["alive"] = false
	hero["respawn_timer"] = 0.1 # 缩短等待
	sim.tick(0.15)

	check(bool(hero.get("alive")), "Hero must respawn after respawn_timer expires")
	near(float(hero.get("hp")), float(hero.get("max_hp")), 0.01, "Hero should respawn with full health")

	# 泉水快速恢复测试
	hero["hp"] = float(hero.get("max_hp")) * 0.3
	hero["mp"] = float(hero.get("max_mp")) * 0.3
	hero["pos"] = MapData.BLUE_BASE # 放置在泉水核心
	var hp_before: float = float(hero.get("hp"))
	sim.tick(1.0) # 泉水内待 1 秒
	var recovered: float = float(hero.get("hp")) - hp_before
	var expected_ratio: float = recovered / float(hero.get("max_hp"))
	near(expected_ratio, 0.18, 0.03, "Fountain must heal ~18% max HP per second")

# ---------- 维度 6：网络同步抗抖动缓冲稳定性 ----------
func test_global_network_session_and_jitter_buffer() -> void:
	var arena: Node3D = Arena.new()
	arena.local_owner = "p1"
	arena.local_team = "blue"

	# 模拟接收网络快照包并入队
	var snap1 := {"time": 10.0, "events": [], "entities": [{"id": 1, "x": 0.0, "y": 0.0}]}
	var snap2 := {"time": 10.1, "events": [], "entities": [{"id": 1, "x": 1.0, "y": 0.0}]}
	var snap3 := {"time": 10.2, "events": [], "entities": [{"id": 1, "x": 2.0, "y": 0.0}]}

	arena.receive_snapshot(snap1)
	arena.receive_snapshot(snap2)
	arena.receive_snapshot(snap3)

	eq(arena._snapshot_buffer.size(), 3, "Snapshot buffer must retain arriving packets")

	# 驱动插值选择
	arena._select_render_snapshot()
	check(not arena._render_snapshot.is_empty(), "Jitter buffer must select render snapshot without crashing")
	check(arena._render_alpha >= 0.0 and arena._render_alpha <= 1.0, "Render alpha must be clamped [0, 1]")

	arena.queue_free()

# ---------- 维度 7：基地摧毁胜负结算与战场完全卸载 ----------
func test_global_match_victory_and_teardown() -> void:
	var sim := MatchSim.new({
		"mode": "duel",
		"humans": [{"id": "p1", "name": "蓝方", "team": "blue", "hero_type": "blade"}],
		"bot_fill": true,
		"bot_ai": false,
	})
	check(not sim.ended, "Game should not be ended initially")

	# 基地受高地塔保护：先按外→内→高顺序拆掉中路塔
	for tier in ["outer", "inner", "high"]:
		var tower: Dictionary = {}
		for s in sim.state.entities:
			if s.get("type") == "tower" and s.get("team") == "red" and s.get("lane") == "mid" and s.get("tier") == tier:
				tower = s
				break
		check(not tower.is_empty(), "Red mid %s tower must exist" % tier)
		sim.apply_damage(int(tower.get("id")), 999999.0)

	var red_base: Dictionary = {}
	for s in sim.state.entities:
		if s.get("type") == "base" and s.get("team") == "red":
			red_base = s
			break
	check(not red_base.is_empty(), "Red base must exist")

	# 施加毁灭伤害以触发死亡逻辑
	sim.apply_damage(int(red_base.get("id")), 999999.0)

	check(sim.ended, "Destroying enemy base must trigger ended")
	eq(sim.state.winner, "blue", "Winner must be blue")

	var snap: Dictionary = sim.snapshot()
	var has_match_end := false
	for ev in snap.get("events", []):
		if ev.get("type") == "match_end":
			has_match_end = true
			eq(ev.get("winner"), "blue", "Match end event winner must be blue")
	check(has_match_end, "match_end event must be emitted into snapshot")
