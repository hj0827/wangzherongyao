extends "res://tests/test_base.gd"

# 河道之灵与传送阵契约：
# 之灵延迟刷新、击杀给团队河道视野；传送阵成对、引导可被打断。
# 视野、快照、网络白名单与 HUD 意图都必须走同一条链路。

const MatchSim = preload("res://sim/match_sim.gd")
const MapLayout = preload("res://sim/map/map_layout.gd")
const MapData = preload("res://sim/map_data.gd")
const Collision = preload("res://sim/map/collision.gd")
const River = preload("res://sim/map/river.gd")
const Teleport = preload("res://sim/map/teleport.gd")
const Vision = preload("res://sim/map/vision.gd")
const MapView = preload("res://scripts/game/map_view.gd")
const Minimap = preload("res://scripts/ui/minimap.gd")
const Arena = preload("res://scripts/game/arena.gd")
const GameHUD = preload("res://scripts/ui/game_hud.gd")
const NetProtocol = preload("res://net/net_protocol.gd")

func _sim(mode := "duel") -> Object:
	return MatchSim.new({
		"mode": mode,
		"humans": [{"id": "p1", "name": "Tester", "team": "blue", "hero_type": "blade"}],
		"bot_fill": true,
		"bot_ai": false,
	})

func _monsters(sim: Object, type_id := "") -> Array:
	var result: Array = []
	for entity in sim.state.entities:
		if str(entity.type) != "monster":
			continue
		if type_id != "" and str(entity.get("monster_type", "")) != type_id:
			continue
		result.append(entity)
	return result

func _force_spirits(sim: Object) -> void:
	sim.state.river.spawn_timer = 0.001
	sim.tick(0.01)

func _event_types(sim: Object) -> Array:
	return sim.state.events.map(func(event): return str(event.get("type", "")))

func test_river_spirits_spawn_after_delay_and_are_mirrored() -> void:
	var sim := _sim()
	eq(_monsters(sim, "spirit").size(), 0, "开局河道之灵未刷新，野区仍是四座营地")
	near(float(sim.state.river.spawn_timer), River.FIRST_SPAWN, 0.001, "河道之灵按首刷计时")
	_force_spirits(sim)
	var spirits := _monsters(sim, "spirit")
	eq(spirits.size(), 2, "上下河道各一只河道之灵")
	for spirit in spirits:
		eq(str(spirit.team), "neutral", "河道之灵中立")
		check(bool(spirit.get("river_spirit", false)), "河道之灵带专属标记")
	var mirrored: Vector2 = MapLayout.mirror(spirits[0].pos)
	check((spirits[1].pos as Vector2).distance_to(mirrored) < 0.01, "两只河道之灵关于 y=-x 镜像")
	near(float(sim.state.river.spawn_timer), 0.0, 0.001, "刷新后计时归零")

func test_killing_river_spirit_grants_reveal_and_xp() -> void:
	var sim := _sim()
	_force_spirits(sim)
	var hero: Dictionary = sim.get_hero_by_player("p1")
	var spirit: Dictionary = _monsters(sim, "spirit")[0]
	var xp_before := float(hero.xp)
	var level_before := int(hero.level)
	sim.apply_damage(int(spirit.id), 999999.0, int(hero.id))
	check(not bool(spirit.alive), "河道之灵被击杀")
	check(float(hero.xp) > xp_before or int(hero.level) > level_before, "击杀河道之灵获得经验")
	var reveals: Array = River.reveals_for(sim.state, "blue")
	eq(reveals.size(), 1, "击杀方获得一处河道视野")
	if not reveals.is_empty():
		near(float(reveals[0].radius), River.REVEAL_RADIUS, 0.001, "视野半径正确")
		gt(float(reveals[0].timer), River.REVEAL_DURATION - 1.0, "视野持续时间满额")
	var events := _event_types(sim)
	check(events.has("river_spirit_killed"), "击杀河道之灵有专属事件")
	check(not events.has("buff_taken"), "河道之灵不发放红蓝增益")
	near(float(spirit.get("respawn_timer", 0.0)), River.RESPAWN_TIME, 0.1, "河道之灵按自身周期重生")

func test_river_reveal_exposes_enemy_in_fog() -> void:
	var enemy := {
		"id": 1, "type": "hero", "team": "red", "x": -30.0, "y": 30.0,
		"hp": 100.0, "max_hp": 100.0, "alive": true, "radius": 0.6,
	}
	var viewer := {
		"id": 2, "type": "hero", "team": "blue", "x": 46.0, "y": 46.0,
		"hp": 100.0, "max_hp": 100.0, "alive": true, "radius": 0.6,
	}
	var snapshot := {
		"entities": [enemy, viewer],
		"river": {"spawn_timer": 0.0, "reveals": {"blue": [], "red": []}},
	}
	eq(Vision.filter_snapshot(snapshot, "blue").entities.size(), 1, "无视野时远处敌人被剔除")
	snapshot.river.reveals.blue = [{"x": -30.0, "y": 30.0, "radius": River.REVEAL_RADIUS, "timer": 20.0}]
	eq(Vision.filter_snapshot(snapshot, "blue").entities.size(), 2, "河道之灵视野揭示雾中敌人")
	eq(Vision.filter_snapshot(snapshot, "red").entities.size(), 1, "蓝方获得的视野不会透给红方视角")

func test_river_snapshot_and_network_carry_reveals() -> void:
	var sim := _sim()
	_force_spirits(sim)
	var hero: Dictionary = sim.get_hero_by_player("p1")
	sim.apply_damage(int(_monsters(sim, "spirit")[0].id), 999999.0, int(hero.id))
	var snap: Dictionary = sim.snapshot()
	check(snap.has("river"), "快照携带河道状态")
	eq(snap.river.reveals.blue.size(), 1, "快照携带己方视野")
	var result: Dictionary = NetProtocol.sanitize_snapshot({
		"time": 1.0,
		"mode": "duel",
		"bounds": 58.0,
		"entities": [],
		"scores": {},
		"events": [],
		"river": {
			"spawn_timer": 0.0,
			"reveals": {
				"blue": [{"x": -30.0, "y": 30.0, "radius": 16.0, "timer": 30.0}],
				"red": [],
			},
		},
	})
	check(bool(result.ok), "带河道状态的快照通过白名单")
	if bool(result.ok):
		eq(result.snapshot.river.reveals.blue.size(), 1, "河道视野保留")
		near(float(result.snapshot.river.reveals.blue[0].radius), 16.0, 0.001, "视野半径保留")

func test_corner_plazas_pave_the_two_empty_corners() -> void:
	# 2026-10-28（玩家：「把这个角落全部铺上……不需要那个桥」）：
	# 两个空角落整块铺石，角落桥拆掉。三条硬约束：
	#   ① 广场必须盖住上下路的跨河点 —— 桥没了，那里只剩广场兜底，
	#      盖不住就是「一条土路悬在河面上」；
	#   ② 广场外沿必须够到边界墙内表面 —— 差一截就是墙脚一条水缝；
	#   ③ 两座绕原点 180° 对称（公平性）。
	var plazas: Array = MapLayout.corner_plazas()
	eq(plazas.size(), 2, "两个空角落各一块广场")
	var crossings: Array = MapLayout.lane_river_crossings()
	eq(crossings.size(), 2, "上下路各有一个跨河点")
	for plaza in plazas:
		# 外沿越靠外，绝对值越大：取两块顶点里更靠墙的那个。
		gt(maxf(absf(float(plaza.min.x)), absf(float(plaza.max.x))), MapLayout.boundary_inner() - 0.5,
			"广场必须铺到墙脚，否则墙根留一条水缝")
		gt(maxf(absf(float(plaza.min.y)), absf(float(plaza.max.y))), MapLayout.boundary_inner() - 0.5,
			"广场必须铺到墙脚，否则墙根留一条水缝")
	for crossing in crossings:
		check(MapLayout.inside_corner_plaza(crossing.pos),
			"%s 路的跨河点必须落在角落广场里（桥拆了，这里只剩广场兜底）" % str(crossing.lane))

	# 只验「跨河点」是不够的：跨河点落在广场上、但广场内沿切进水面时，
	# 路面仍然会从水上方伸出去一截（把 INNER 改成 46 就是这样，跨河点 47.66 照样在广场里）。
	# 所以逐个采样兵线：**凡是在水面上方的路面点，都必须落在广场里**。
	for lane in ["top", "bottom"]:
		var paved := 0
		for sample in _lane_samples(str(lane), 0.5):
			var a := absf(sample.x - sample.y)
			if a > MapData.RIVER_HALF_WIDTH - 0.5:
				continue
			if maxf(absf(sample.x), absf(sample.y)) < 30.0:
				continue
			check(MapLayout.inside_corner_plaza(sample),
				"%s 路在水面上的路面点 %s 没有铺到广场里 —— 桥拆了之后那里是悬空路面" % [str(lane), str(sample)])
			paved += 1
		gt(float(paved), 0.0, "%s 路必须真的有一段跨在河上（否则这条断言是空的）" % str(lane))

	# 对称：两块广场互为 180° 取反。
	var first: Dictionary = plazas[0]
	var second: Dictionary = plazas[1]
	near(float(first.min.x), -float(second.max.x), 0.01, "两座广场 x 对称")
	near(float(first.min.y), -float(second.max.y), 0.01, "两座广场 y 对称")

# 兵线逐 0.5 米采样（跨河段要按采样点量，只看航点会正好跳过水面）。
func _lane_samples(lane: String, step: float) -> Array:
	var points: Array = []
	var path: Array = MapData.lane_path(lane)
	for index in range(path.size() - 1):
		var a: Vector2 = path[index]
		var b: Vector2 = path[index + 1]
		var length := a.distance_to(b)
		var count := maxi(int(ceil(length / step)), 1)
		for i in count:
			points.append(a.lerp(b, float(i) / float(count)))
	return points

func test_teleport_pads_sit_deep_in_the_two_corners() -> void:
	var pads: Array = MapLayout.TELEPORT_PADS
	eq(pads.size(), 2, "地图的两个空角落各一座传送阵")
	var first: Dictionary = pads[0]
	var second: Dictionary = Teleport.partner_of(str(first.id))
	check(not second.is_empty(), "传送阵能查到对端")
	if not second.is_empty():
		eq(str(Teleport.partner_of(str(second.id)).get("id", "")), str(first.id), "对端关系双向")
		# 对称口径仍然是**绕地图中心 180°**（-p），不是 y=-x 镜像。
		# 和营地犯过的是同一个错：mirror 会把两座阵都放到同一侧。
		check((second.pos as Vector2).distance_to(-(first.pos as Vector2)) < 0.01, "两座传送阵绕地图中心 180° 对称")

	# 2026-10-28 第二版的位置契约（玩家：「将这个传送阵放在最角落里面」）：
	#   ① 阵心在角落广场里 —— 广场铺到墙脚，阵才有地方站；
	#   ② 阵心必须真的靠角落：离地图角点不超过 12 米（旧两版分别是 30+ 和 14.6）；
	#   ③ 阵心必须还站得进去：可走边界 = BOUNDS - 相机边距 - 英雄半径 = 53.65，
	#      至少留 1 米余量，否则「看得见阵、走不进去」；
	#   ④ 两座都是中立设施（到两方基地等距）。
	var walk_limit := MapData.BOUNDS - MapData.CAMERA_WALL_MARGIN - 0.55
	for pad in pads:
		var point: Vector2 = pad.pos
		check(MapLayout.inside_corner_plaza(point), "%s 必须落在角落广场上" % str(pad.id))
		var map_corner := Vector2(signf(point.x) * MapData.BOUNDS, signf(point.y) * MapData.BOUNDS)
		lt(point.distance_to(map_corner), 12.0,
			"%s 要放在最角落（离地图角点 %.2f 米）" % [str(pad.id), point.distance_to(map_corner)])
		lt(maxf(absf(point.x), absf(point.y)), walk_limit - 1.0,
			"%s 必须还给英雄留出走路余量（可走上限 %.2f）" % [str(pad.id), walk_limit])
		var to_blue := point.distance_to(MapData.BLUE_BASE)
		var to_red := point.distance_to(MapData.RED_BASE)
		near(to_blue, to_red, 0.01, "传送阵是中立设施：到两方基地距离必须相等")
		# 阵心本身要能站人：有墙的地方点不进去，阵就永远用不了。
		check(not Collision.is_blocked(point, 0.55), "阵心可以站人")
		check(not Teleport.pad_at(point).is_empty(), "站在阵内能识别传送阵")
	check(Teleport.pad_at(Vector2(0.0, 0.0)).is_empty(), "阵外不识别")

func test_vegetation_keeps_a_canopy_clearance_around_every_pad() -> void:
	# 截图里阵盘正中长着一棵树：避让半径只按阵盘半径 3.0 算，
	# 而树冠的水平半径就有 2~3.5 米 —— 树干站在盘边 1 米外，树冠照样盖住整个阵。
	# 契约：布景避让要按**树冠**而不是树干留白，阵盘半径之外再加一圈树冠空间。
	var arena: Node3D = Arena.new()
	arena._props_root = Node3D.new()
	arena.add_child(arena._props_root)
	gt(float(MapLayout.PAD_CANOPY_CLEARANCE), 2.0, "树冠留白至少 2 米，否则树冠会探进阵里")
	for pad in MapLayout.TELEPORT_PADS:
		var point: Vector2 = pad.pos
		check(
			not bool(arena.call("_feature_clear", point, 2.0)),
			"阵盘正中不能长布景：%s" % str(pad.id)
		)
		check(
			not bool(arena.call("_feature_clear", point + Vector2(0.0, MapLayout.PAD_DISC_RADIUS + 2.5), 2.0)),
			"阵盘边缘一圈也不该种树（树冠会盖上来）：%s" % str(pad.id)
		)
		# 反向对照：远在树冠之外的点至少有一部分是能长东西的 ——
		# 否则上面的断言只是「这个函数永远返回 false」，等于什么都没测。
		# 扫描半径取 30 米：阵现在在角落广场里，广场 + 边界留白会把 12 米的环整个吃掉，
		# 那一圈上「能不能长东西」全都只能是 false，测不出这个函数有没有坏。
		var clear := 0
		for i in 36:
			var angle := TAU * float(i) / 36.0
			var ring := point + Vector2(cos(angle), sin(angle)) * 30.0
			if bool(arena.call("_feature_clear", ring, 2.0)):
				clear += 1
		gt(float(clear), 0.0, "阵外远处必须还有能长布景的地方：%s" % str(pad.id))
	arena.free()

func test_random_props_keep_clear_of_the_pads() -> void:
	# 阵盘从河心挪到岸上之后立刻暴露的一个问题：岸上是有随机树木 / 石头的，
	# 而布景的避让清单里只写了墙、草丛、营地、首领坑 —— 没有传送阵。
	# 结果是第一版截图里正有一棵树长在阵盘正中。
	var arena: Node3D = Arena.new()
	for pad in MapLayout.TELEPORT_PADS:
		check(
			not arena._feature_clear(pad.pos, 1.0),
			"阵心不能长树：%s" % str(pad.id)
		)
		# 阵盘边缘也要干净，不然树冠会压进圈里。
		var rim: Vector2 = pad.pos + Vector2(MapLayout.PAD_DISC_RADIUS * 0.7, 0.0)
		check(
			not arena._feature_clear(rim, 1.0),
			"阵盘边缘不能长树：%s" % str(pad.id)
		)
	# 反例：阵外远处必须有布景自由，否则等于把整片野区的植被都关了。
	# 不写死偏移方向，也不贴着小圈扫：阵挪进角落广场之后，
	# 阵周 12 米内全是广场石面和墙脚留白，「能不能长东西」永远只能 false。
	# 扫一圈 30 米：桥外、野区里仍然必须允许布景。
	var clear := 0
	for index in 24:
		var angle := TAU * float(index) / 24.0
		var probe: Vector2 = MapLayout.TELEPORT_PADS[0].pos \
			+ Vector2(cos(angle), sin(angle)) * 30.0
		if arena._feature_clear(probe, 0.0):
			clear += 1
	gt(float(clear), 0.0, "阵外仍然允许布景")
	arena.free()

func test_teleport_channels_to_partner_and_starts_cooldown() -> void:
	var sim := _sim()
	var hero: Dictionary = sim.get_hero_by_player("p1")
	var pad: Dictionary = MapLayout.TELEPORT_PADS[0]
	var partner: Dictionary = Teleport.partner_of(str(pad.id))
	hero.pos = pad.pos
	sim.set_input("p1", {"teleport": true})
	sim.tick(1.0 / 30.0)
	check(bool(hero.get("teleporting", false)), "站在阵上按传送开始引导")
	gt(float(hero.get("teleport_timer", 0.0)), 0.0, "引导计时开始")
	for i in 100:
		sim.tick(1.0 / 30.0)
		if not bool(hero.get("teleporting", false)):
			break
	check(not bool(hero.get("teleporting", false)), "引导结束")
	check((hero.pos as Vector2).distance_to(partner.pos) < 0.6, "落点是对端传送阵")
	gt(float(hero.get("teleport_cd", 0.0)), 0.0, "传送后进入冷却")

	var away := _sim()
	var away_hero: Dictionary = away.get_hero_by_player("p1")
	away_hero.pos = Vector2(0.0, 0.0)
	away.set_input("p1", {"teleport": true})
	away.tick(1.0 / 30.0)
	check(not bool(away_hero.get("teleporting", false)), "不在阵上不能传送")

func test_teleport_interrupts_on_move_and_damage() -> void:
	var sim := _sim()
	var hero: Dictionary = sim.get_hero_by_player("p1")
	var pad: Dictionary = MapLayout.TELEPORT_PADS[1]
	hero.pos = pad.pos
	sim.set_input("p1", {"teleport": true})
	sim.tick(1.0 / 30.0)
	check(bool(hero.get("teleporting", false)), "引导中")
	sim.set_input("p1", {"move": Vector2(1.0, 0.0)})
	sim.tick(1.0 / 30.0)
	check(not bool(hero.get("teleporting", false)), "移动打断传送")
	check((hero.pos as Vector2).distance_to(pad.pos) < 1.0, "打断后没有位移到对端")

	hero.pos = pad.pos
	hero.teleport_cd = 0.0
	sim.set_input("p1", {"teleport": true})
	sim.tick(1.0 / 30.0)
	check(bool(hero.get("teleporting", false)), "重新开始引导")
	sim.apply_damage(int(hero.id), 10.0)
	check(not bool(hero.get("teleporting", false)), "受击打断传送")

func test_teleport_snapshot_network_and_hud_intent() -> void:
	var sim := _sim()
	var hero: Dictionary = sim.get_hero_by_player("p1")
	hero.pos = MapLayout.TELEPORT_PADS[0].pos
	sim.set_input("p1", {"teleport": true})
	sim.tick(1.0 / 30.0)
	var hero_snap: Dictionary = sim.snapshot().entities.filter(func(entity): return str(entity.type) == "hero" and str(entity.owner_id) == "p1")[0]
	check(hero_snap.has("teleporting") and hero_snap.has("teleport_timer"), "英雄快照携带传送状态")
	check(bool(hero_snap.get("teleporting", false)), "引导状态进入快照")
	eq(bool(NetProtocol.sanitize_input({"teleport": true}).teleport), true, "传送输入通过白名单")

	var marks: Dictionary = MapView.map_marks()
	eq(marks.teleports.size(), 2, "MapView 暴露传送阵锚点")
	var teleport_shapes: Array = Minimap.feature_shapes().filter(func(shape): return str(shape.get("kind", "")) == "teleport")
	eq(teleport_shapes.size(), 2, "小地图绘制传送阵")

	var hud := GameHUD.new()
	hud.setup("p1", "blue", "blade", "你", true, false)
	hud._ready()
	var slots: Array = []
	hud.skill_pressed.connect(func(slot): slots.append(slot))
	check(hud._teleport_button != null, "触摸 HUD 提供传送按钮")
	if hud._teleport_button:
		hud._teleport_button.pressed.emit()
	eq(slots, ["teleport"], "传送按钮发出传送意图")
	hud.free()

	var arena: Node3D = Arena.new()
	arena._on_skill_button("teleport")
	check(arena._queued_teleport, "Arena 接受传送按钮意图")
	arena.free()
