extends RefCounted

# 战斗事件分发。C17 拆分第五步：把 arena.gd 里 `_process_events` 的 match 分发搬出来。
#
# host 就是最小的表现层上下文：音频导演、HUD、单位视图表、镜头状态与各类
# 特效生成器都还在 arena 上，本模块只负责「事件类型 → 处理分支」的路由。
# 这样做的目的：把 150 行分发逻辑从 6000 行文件里分离；后续把单个 _handle_*
# 继续搬进来时，不需要再动 arena 的分发结构，也不需要引入更重的上下文对象。

const SkillFx = preload("res://scripts/game/skill_fx.gd")
const MapView = preload("res://scripts/game/map_view.gd")
const MapLayout = preload("res://sim/map/map_layout.gd")
const MapData = preload("res://sim/map_data.gd")
const GameTheme = preload("res://scripts/ui/game_theme.gd")
const AudioDirector = preload("res://scripts/game/audio_director.gd")
const UnitVisual = preload("res://scripts/game/unit_visual.gd")

static func process(host, events: Array) -> void:
	# 音效与表现共用同一批事件：模拟侧算一次，主机/客机听到的是同一场战斗。
	if host._audio != null:
		host._audio.handle_events(events, host.TICK)
	# 技能表现统一从 SkillFx.requests() 取：Q/E 的 skill、W/R 的 skill_cast、
	# 召唤师技能的 summoner_cast 在这里归一。以前只认 skill，W/R 放出去毫无表现。
	for request in SkillFx.requests(events):
		host._spawn_skill_fx(request)
		# MON-04 技能预警：敌方 AOE 落地位置铺一圈红色危险圈。
		# 不做"延迟伤害"式的假预警——sim 没有前摇，这里只是把危险范围画清楚，
		# 让玩家在后续 0.6s 的余爆/残留里知道哪里不能站。
		if str(request.get("team", "")) != "" and str(request.get("team", "")) != host.local_team:
			var kind := str(request.get("kind", ""))
			if host.DANGER_SKILL_KINDS.has(kind):
				var aim: Vector2 = request.get("aim", Vector2.ZERO)
				var radius: float = host._recipe_radius(request.get("recipe", {}))
				if radius >= 2.0:
					host._spawn_ring(Vector3(aim.x, 0.07, aim.y), Color(1.0, 0.24, 0.18),
						radius * 0.97, radius, 0.6, 0.5, false, 1)
	for event in events:
		if not (event is Dictionary):
			continue
		var banner := MapView.event_banner(event)
		if not banner.is_empty() and host.hud != null:
			var banner_color: Color = banner.get("color", GameTheme.GOLD_LIGHT)
			if bool(banner.get("announce", false)):
				host.hud.announce(str(banner.get("text", "")), banner_color, float(banner.get("duration", 1.6)))
			host.hud.add_feed(str(banner.get("feed", "")), banner_color)
		match str(event.get("type", "")):
			"projectile_spawned":
				# 项 3：弹道是**真实飞行的实体**，不是施法瞬间补的一段特效。
				# 这里只负责把"发射了"变成画面上的一个弹丸；命中时另收 projectile_hit。
				host._handle_projectile_spawned(event)
			"projectile_hit":
				host._handle_projectile_hit(event)
			"attack":
				host._handle_hero_attack(event)
			"hit":
				handle_hit_event(host, event)
			"heal":
				# FX-11 治疗飘字：绿色 + 号，位置在治疗者脚下（吸血/回复都走这里）。
				var heal_pos := Vector3(float(event.get("x", 0.0)), 0.0, float(event.get("y", 0.0)))
				host._spawn_damage_number(heal_pos + Vector3(0, 1.9, 0), float(event.get("amount", 0.0)), Color(0.55, 0.95, 0.62), "+")
			"death":
				host._handle_death_event(event)
			"tower_destroyed":
				var pos := Vector3(float(event.get("x", 0.0)), 1.0, float(event.get("y", 0.0)))
				host._explosion(pos, host.RED if str(event.get("team", "red")) == "red" else host.BLUE, 32)
				host._trigger_hit_stop(0.06, 0.22)
				host._start_structure_collapse(event)
			"guard_destroyed":
				var guard_pos := Vector3(float(event.get("x", 0.0)), 1.0, float(event.get("y", 0.0)))
				host._explosion(guard_pos, host.RED if str(event.get("team", "red")) == "red" else host.BLUE, 30)
				host._camera_shake = maxf(host._camera_shake, 0.14)
				host._start_structure_collapse(event)
			"ping_mark":
				# 项 11.1：只画地面环 + 短时文字，不参与命中停顿/震屏，避免打断对线操作。
				host._spawn_ping_marker(event)
				if host.hud != null:
					host.hud.show_ping(event)
			"crystal_shield_broken":
				var crystal_pos := Vector3(float(event.get("x", 0.0)), 2.0, float(event.get("y", 0.0)))
				host._spawn_ring(crystal_pos, Color(0.55, 0.84, 1.0), 1.0, 8.0, 1.0)
				host._spawn_particles(crystal_pos + Vector3(0, 2.0, 0), Color(0.62, 0.86, 1.0), 30, 6.0)
				host._camera_shake = maxf(host._camera_shake, 0.22)
				host._trigger_hit_stop(0.1, 0.3)
			"teleport":
				var from_pos := Vector3(float(event.get("x", 0.0)), 0.2, float(event.get("y", 0.0)))
				var to_pos := Vector3(float(event.get("to_x", 0.0)), 0.2, float(event.get("to_y", 0.0)))
				host._handle_channel_departure(int(event.get("hero", -1)), "teleport", from_pos, to_pos)
			"teleport_interrupt":
				var break_pos := Vector3(float(event.get("x", 0.0)), 0.2, float(event.get("y", 0.0)))
				host._handle_channel_break(int(event.get("hero", -1)), "teleport", break_pos)
			"recall":
				var leave_pos := Vector3(float(event.get("x", 0.0)), 0.2, float(event.get("y", 0.0)))
				var home_pos := Vector3(float(event.get("to_x", 0.0)), 0.2, float(event.get("to_y", 0.0)))
				host._handle_channel_departure(int(event.get("hero", -1)), "recall", leave_pos, home_pos)
			"recall_interrupt":
				var cancel_pos := Vector3(float(event.get("x", 0.0)), 0.2, float(event.get("y", 0.0)))
				host._handle_channel_break(int(event.get("hero", -1)), "recall", cancel_pos)
			"river_spirit_killed":
				var spirit_pos := Vector3(float(event.get("x", 0.0)), 0.5, float(event.get("y", 0.0)))
				host._spawn_ring(spirit_pos, Color(0.46, 0.86, 0.94), 0.6, 4.0, 0.8)
			"objective_spawn":
				# 首领刷新是全局事件：两个坑各起一圈地面冲击 + 金色粒子，配合顶部播报。
				for pit in MapLayout.OBJECTIVE_PITS:
					var pit_pos := Vector3(float(pit.pos.x), 0.1, float(pit.pos.y))
					host._spawn_ring(pit_pos, Color(0.92, 0.66, 0.28), 1.0, 5.5, 1.0, 0.65)
					# 2 秒的慢速预警环：在 1 秒冲击环散掉之后继续圈住坑位，
					# 读成「这里已经有人了」，而不是一闪而过。
					host._spawn_ring(pit_pos, Color(1.0, 0.78, 0.36), 3.0, 5.8, 2.0, 0.28)
					host._spawn_particles(pit_pos + Vector3(0.0, 0.8, 0.0), host.GOLD, 16, 3.0, 0.1, 0.7)
				host._camera_shake = maxf(host._camera_shake, 0.12)
				host._zoom_kick = maxf(host._zoom_kick, host.OBJECTIVE_ZOOM_KICK * host._fx_intensity())
			"objective_killed":
				var boss_pos := Vector3(float(event.get("x", 0.0)), 1.0, float(event.get("y", 0.0)))
				host._explosion(boss_pos, host.GOLD, 40)
				host._spawn_ring(Vector3(boss_pos.x, 0.1, boss_pos.z), host.GOLD, 1.0, 6.0, 0.9)
				host._spawn_decal(Vector2(boss_pos.x, boss_pos.z), host.GOLD, 5.0, 2.2)
				host._trigger_hit_stop(0.12, 0.35)
				host._camera_shake = maxf(host._camera_shake, 0.2)
			"buff_taken":
				var buff_pos := Vector3(float(event.get("x", 0.0)), 0.2, float(event.get("y", 0.0)))
				var buff_color: Color = host.BLUE if str(event.get("buff", "")) == "blue" else host.RED
				host._spawn_ring(buff_pos, buff_color, 0.6, 3.0, 0.7)
				host._spawn_particles(buff_pos + Vector3(0, 0.8, 0), buff_color, 16, 3.0)
			"base_exposed":
				host._camera_shake = maxf(host._camera_shake, 0.16)
			"level_up":
				var hero: UnitVisual = host._views.get(int(event.get("hero", -1)))
				if hero:
					host._spawn_ring(hero.position, host.GOLD, 0.3, 2.2, 0.6)
					host._spawn_particles(hero.position + Vector3(0, 1.0, 0), host.GOLD, 20, 4.0)
			"wave":
				var wave := int(event.get("wave", 1))
				if wave == 1 or wave % 3 == 0:
					host.hud.announce("第 %d 波兵线出发" % wave, Color(0.93, 0.82, 0.6), 1.4)
				host.hud.add_feed("第 %d 波兵线出发" % wave, GameTheme.MUTED)
			"minion_attack":
				host._handle_minion_attack(event)
			"monster_attack":
				host._handle_monster_attack(event)
			"structure_attack":
				host._handle_structure_attack(event)
			"respawn":
				var respawn_pos := Vector3(float(event.get("x", 0.0)), 0.1, float(event.get("y", 0.0)))
				host._spawn_ring(respawn_pos, host.GOLD, 0.4, 2.0, 0.6)
			"match_end":
				var match_winner := str(event.get("winner", ""))
				# 败方基地：水晶碎成光屑 + 一圈扩散到广场边缘的冲击环。
				# match_end 只带 winner，败方基地由 winner 反推，不新增协议字段。
				var loser_base: Vector2 = MapData.RED_BASE if match_winner == "blue" else MapData.BLUE_BASE
				var loser_color: Color = host.RED if match_winner == "blue" else host.BLUE
				host._explosion(Vector3(loser_base.x, 1.6, loser_base.y), loser_color, 80)
				host._spawn_ring(Vector3(loser_base.x, 0.12, loser_base.y), loser_color, 1.0, 12.0, 1.2, 0.8)
				host._camera_shake = maxf(host._camera_shake, 0.3)
				if host.hud != null:
					host.hud.announce("主堡陷落", GameTheme.GOLD_LIGHT, 2.0)
				host._trigger_hit_stop(0.16, 0.45)
				# 结算曲按本地队伍判：赢了上行号角，输了下行钟声。
				# 这两个是一次性音（不循环），所以不走 play_cue 的声道池。
				if host._audio != null:
					var winner := str(event.get("winner", ""))
					if winner == host.local_team:
						host._audio.play_music(AudioDirector.MUSIC_VICTORY)
					else:
						host._audio.play_music(AudioDirector.MUSIC_DEFEAT)

# 受击表现：伤害飘字（含护盾吸收）+ 受击/出手反馈 + 命中粒子。
static func handle_hit_event(host, event: Dictionary) -> void:
	var pos := Vector3(float(event.get("x", 0.0)), 0.0, float(event.get("y", 0.0)))
	var amount := float(event.get("amount", 0.0))
	var target_id := int(event.get("target", -1))
	var target_type := str(event.get("target_type", ""))
	var color := Color(1.0, 0.92, 0.72) if amount >= 150.0 else Color(0.95, 0.96, 1.0)
	host._spawn_damage_number(pos + Vector3(0, 1.7 if target_type == "hero" else 1.0, 0), amount, color)
	# FX-11 护盾吸收：蓝色「盾 N」飘在伤害数字上方。全额被盾吃掉时 amount=0，
	# 这时更要显示吸收量，否则玩家会觉得这一下完全没打中。
	var absorbed := float(event.get("absorbed", 0.0))
	if absorbed > 0.5:
		host._spawn_damage_number(
			pos + Vector3(0, 2.05 if target_type == "hero" else 1.35, 0),
			absorbed,
			Color(0.58, 0.84, 1.0),
			"盾 "
		)
	# 受击反馈对所有单位生效：英雄/小兵/野怪被命中时都要缩身 + 闪白，
	# 否则打野和清兵只剩飘字，模型毫无反应。
	var view: UnitVisual = host._views.get(target_id)
	if view:
		view.play_hit()
	# 出手者反馈：野怪/小兵没有独立的 attack 事件，用 hit 的来源 id 补一次前倾。
	var source_id := int(event.get("source", -1))
	var source_type := str(event.get("source_type", ""))
	if (source_type == "monster" or source_type == "minion") and source_id >= 0:
		var attacker: UnitVisual = host._views.get(source_id)
		if attacker:
			attacker.play_attack_reaction()
	if target_type == "hero":
		host._spawn_particles(pos + Vector3(0, 1.0, 0), Color(1.0, 0.72, 0.4), 10, 3.0)
		if target_id == host._local_entity_id:
			host._camera_shake = maxf(host._camera_shake, 0.12)
	else:
		host._spawn_particles(pos + Vector3(0, 0.55, 0), Color(0.9, 0.72, 0.4), 4, 1.8, 0.05, 0.3)
