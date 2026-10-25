extends "res://tests/test_base.gd"

# 音频系统：事件 → cue 的映射（纯逻辑）、合成音效、程序化 BGM、以及生产接线守卫。
#
# 这个仓库已经踩过一次坑：module 文件在、测试绿、生产引用为 0。
# 所以除了逻辑断言，这里还有两条「源码守卫」用例，钉住 arena/main 真的调了音频导演。

const AudioPlan = preload("res://scripts/game/audio_plan.gd")
const AudioCues = preload("res://scripts/game/audio_cues.gd")
const BgmSynth = preload("res://scripts/game/bgm_synth.gd")

const LOCAL_ID := 7

# ---------------------------------------------------------------- 工具

func _ctx(overrides: Dictionary = {}) -> Dictionary:
	var ctx := {"local": LOCAL_ID, "x": 0.0, "y": 0.0, "team": "blue", "hp_ratio": 1.0}
	for key in overrides:
		ctx[key] = overrides[key]
	return ctx

func _cues(plan: Object, event: Dictionary, ctx: Dictionary) -> Array:
	plan.begin_frame(1.0 / 30.0, ctx)
	return plan.cues_for(event, ctx)

func _names(list: Array) -> Array:
	var out := []
	for item in list:
		out.append(str(item.get("cue", "")))
	return out

func _samples(stream: AudioStreamWAV) -> PackedFloat32Array:
	var count := stream.data.size() / 2
	var out := PackedFloat32Array()
	out.resize(count)
	for i in count:
		out[i] = float(stream.data.decode_s16(i * 2)) / 32767.0
	return out

func _seconds(stream: AudioStreamWAV) -> float:
	if stream == null or stream.mix_rate <= 0:
		return 0.0
	return (stream.data.size() / 2) / float(stream.mix_rate)

# 高频能量占比（一阶高通 1.2kHz 之后的能量 / 总能量）。
# 用它比「数起音」稳：战斗曲有战鼓与踩镲，菜单曲几乎全是长音垫，
# 两者的高频占比差一倍以上，而「起音次数」会被长音垫和底噪搅乱。
func _high_share(values: PackedFloat32Array) -> float:
	if values.size() < 8:
		return 0.0
	var alpha := 1.0 - exp(-TAU * 1200.0 / 16000.0)
	var low := 0.0
	var total_energy := 0.0
	var high_energy := 0.0
	for value in values:
		low += alpha * (value - low)
		var high := value - low
		total_energy += value * value
		high_energy += high * high
	return high_energy / maxf(total_energy, 0.000001)

# 循环接缝处的样点跳变（末样点 → 首样点）。
func _seam_delta(values: PackedFloat32Array) -> float:
	if values.size() < 2:
		return 999.0
	return absf(values[0] - values[values.size() - 1])

# 这段音频「正常时的样点变化」：所有相邻差值的 95% 分位。
# 用它当尺子，才能区分「接缝跳变」和「鼓点本身就该有的瞬态」。
func _typical_delta(values: PackedFloat32Array) -> float:
	var deltas := PackedFloat32Array()
	for i in range(1, values.size()):
		deltas.append(absf(values[i] - values[i - 1]))
	deltas.sort()
	var index := int(float(deltas.size() - 1) * 0.95)
	return maxf(deltas[index], 0.0005)

# ---------------------------------------------------------------- 事件映射

func test_combat_events_map_to_cues() -> void:
	var plan := AudioPlan.new()
	eq(_names(_cues(plan, {"type": "attack", "hero": LOCAL_ID, "crit": false}, _ctx())), ["attack_swing"], "本地普攻 -> 挥砍音")
	var crit := _names(_cues(plan, {"type": "attack", "hero": LOCAL_ID, "crit": true}, _ctx()))
	check(crit.has("crit"), "暴击在挥砍音之上再叠一击")
	eq(_names(_cues(plan, {"type": "hit", "target": 3, "target_type": "hero", "x": 1.0, "y": 0.0}, _ctx())), ["hit_hero"], "打英雄是一声闷响")
	eq(_names(_cues(plan, {"type": "hit", "target": 4, "target_type": "minion", "x": 1.0, "y": 0.0}, _ctx())), ["hit_minion"], "打小兵更轻")
	eq(_names(_cues(plan, {"type": "hit", "target": 5, "target_type": "tower", "x": 1.0, "y": 0.0}, _ctx())), ["hit_structure"], "打建筑是金属声")
	eq(_names(_cues(plan, {"type": "not_a_real_event"}, _ctx())), [], "未知事件不出声，也不能崩")

func test_skill_cues_follow_slot_and_hero_type() -> void:
	var plan := AudioPlan.new()
	eq(_names(_cues(plan, {"type": "skill", "hero": LOCAL_ID, "hero_type": "mage", "slot": "q"}, _ctx())), ["skill_mage"], "法师技能音")
	eq(_names(_cues(plan, {"type": "skill", "hero": LOCAL_ID, "hero_type": "tank", "slot": "q"}, _ctx())), ["skill_tank"], "坦克技能音")
	eq(_names(_cues(plan, {"type": "skill", "hero": LOCAL_ID, "hero_type": "blade", "slot": "e"}, _ctx())), ["skill_blade"], "刺客技能音")
	eq(_names(_cues(plan, {"type": "skill", "hero": LOCAL_ID, "hero_type": "archer", "slot": "q"}, _ctx())), ["skill_archer"], "射手技能音")
	# 大招不分英雄：统一一个更重的音，玩家能听出「有人开了大」。
	eq(_names(_cues(plan, {"type": "skill", "hero": LOCAL_ID, "hero_type": "mage", "slot": "r"}, _ctx())), ["skill_ult"], "大招有专属音")
	# 不是英雄类型也不能没声音（否则新英雄上线就静音）。
	eq(_names(_cues(plan, {"type": "skill", "hero": LOCAL_ID, "hero_type": "???", "slot": "q"}, _ctx())), ["skill_mage"], "未知英雄类型回落到默认技能音")
	eq(_names(_cues(plan, {"type": "skill", "hero": LOCAL_ID, "hero_type": "assassin", "slot": "q"}, _ctx())), ["skill_assassin"], "刺客技能音有独立音色")

# W/R 走 SkillSystem.cast_skill()，事件名是 skill_cast；召唤师技能是 summoner_cast。
# 这两类事件曾经完全没有 cue 分支 —— 大招和闪现放出去是哑的，而且不报错。
func test_w_and_r_cast_events_make_sound() -> void:
	var plan := AudioPlan.new()
	eq(_names(_cues(plan, {"type": "skill_cast", "caster_id": LOCAL_ID, "hero_type": "blade", "slot": "w"}, _ctx())), ["skill_blade"], "W 有技能音")
	plan.reset()
	eq(_names(_cues(plan, {"type": "skill_cast", "caster_id": LOCAL_ID, "hero_type": "mage", "slot": "r"}, _ctx())), ["skill_ult"], "R 有大招音")
	plan.reset()
	eq(_names(_cues(plan, {"type": "skill_cast", "caster_id": 99, "hero_type": "archer", "slot": "w", "x": 200.0, "y": 0.0}, _ctx())), [], "远处敌人的 W 被距离丢弃")

func test_summoner_cast_makes_sound() -> void:
	var plan := AudioPlan.new()
	eq(_names(_cues(plan, {"type": "summoner_cast", "caster_id": LOCAL_ID, "spell_id": "flash"}, _ctx())), ["summoner_spell"], "召唤师技能有音")
	plan.reset()
	eq(_names(_cues(plan, {"type": "summoner_cast", "caster_id": 99, "spell_id": "heal", "x": 200.0, "y": 0.0}, _ctx())), [], "远处的召唤师技能被距离丢弃")

func test_map_and_economy_events_have_cues() -> void:
	var plan := AudioPlan.new()
	eq(_names(_cues(plan, {"type": "tower_destroyed", "x": 4.0, "y": 0.0, "team": "red"}, _ctx())), ["tower_down"], "塔倒")
	eq(_names(_cues(plan, {"type": "guard_destroyed", "x": 4.0, "y": 0.0}, _ctx())), ["guard_down"], "高地塔倒")
	eq(_names(_cues(plan, {"type": "crystal_shield_broken", "x": 4.0, "y": 0.0}, _ctx())), ["shield_break"], "水晶护盾破")
	eq(_names(_cues(plan, {"type": "objective_killed", "x": 4.0, "y": 0.0, "name": "暴君"}, _ctx())), ["objective_down"], "暴君/主宰被击杀")
	eq(_names(_cues(plan, {"type": "buff_taken", "x": 4.0, "y": 0.0, "buff": "blue"}, _ctx())), ["buff_taken"], "拿野区 buff")
	eq(_names(_cues(plan, {"type": "river_spirit_killed", "x": 4.0, "y": 0.0}, _ctx())), ["spirit_down"], "河道之灵")
	eq(_names(_cues(plan, {"type": "wave", "wave": 3}, _ctx())), ["wave_horn"], "第 3 波有号角")
	eq(_names(_cues(plan, {"type": "wave", "wave": 2}, _ctx())), [], "普通波次不吹号角（太吵）")
	eq(_names(_cues(plan, {"type": "purchase", "hero": LOCAL_ID, "buy_item": "x"}, _ctx())), ["purchase"], "买装备")
	eq(_names(_cues(plan, {"type": "purchase", "hero": 99, "buy_item": "x"}, _ctx())), [], "队友买装备不吵我")
	eq(_names(_cues(plan, {"type": "level_up", "hero": LOCAL_ID, "level": 3}, _ctx())), ["level_up"], "自己升级")
	eq(_names(_cues(plan, {"type": "respawn", "hero": LOCAL_ID, "x": 1.0, "y": 1.0}, _ctx())), ["respawn"], "自己复活")
	eq(_names(_cues(plan, {"type": "match_end", "winner": "blue"}, _ctx())), ["base_fall"], "主堡陷落")

func test_distant_cues_are_attenuated_or_dropped() -> void:
	var plan := AudioPlan.new()
	var near_list := _cues(plan, {"type": "hit", "target": 3, "target_type": "hero", "x": 0.0, "y": 0.0}, _ctx())
	eq(near_list.size(), 1, "脚边命中要发声")
	near(float(near_list[0].get("gain_db", -99.0)), 0.0, 0.01, "脚边不衰减")

	plan.reset()
	var mid := _cues(plan, {"type": "hit", "target": 3, "target_type": "hero", "x": 20.0, "y": 0.0}, _ctx())
	eq(mid.size(), 1, "20 米内仍然听得见")
	lt(float(mid[0].get("gain_db", 0.0)), -3.0, "20 米要明显变轻")
	gt(float(mid[0].get("gain_db", -99.0)), -30.0, "但还没到听不见")

	plan.reset()
	var far := _cues(plan, {"type": "hit", "target": 3, "target_type": "hero", "x": 60.0, "y": 0.0}, _ctx())
	eq(far.size(), 0, "60 米外的事件直接丢掉，不占声道")

	# 打在自己身上不吃距离衰减：自己挨打的反馈不能因为坐标漂移变小声。
	plan.reset()
	var on_self := _cues(plan, {"type": "hit", "target": LOCAL_ID, "target_type": "hero", "x": 44.0, "y": 0.0}, _ctx())
	eq(on_self.size(), 1, "自己挨打必须发声")
	gt(float(on_self[0].get("gain_db", -99.0)), -1.0, "自己挨打不衰减")

func test_repeated_cues_are_throttled() -> void:
	var plan := AudioPlan.new()
	plan.reset()
	plan.begin_frame(0.0, _ctx())
	eq(plan.cues_for({"type": "hit", "target": 3, "target_type": "hero"}, _ctx()).size(), 1, "第一声要发声")
	eq(plan.cues_for({"type": "hit", "target": 3, "target_type": "hero"}, _ctx()).size(), 0, "同一时刻重复命中不叠")
	plan.begin_frame(0.5, _ctx())
	eq(plan.cues_for({"type": "hit", "target": 3, "target_type": "hero"}, _ctx()).size(), 1, "超过冷却后重新发声")

func test_frame_budget_caps_simultaneous_cues() -> void:
	var plan := AudioPlan.new()
	plan.reset()
	plan.begin_frame(1.0 / 30.0, _ctx())
	var events := [
		{"type": "attack", "hero": LOCAL_ID, "crit": true},
		{"type": "hit", "target": 3, "target_type": "hero"},
		{"type": "hit", "target": 4, "target_type": "minion"},
		{"type": "hit", "target": 5, "target_type": "tower"},
		{"type": "death", "entity_type": "hero", "hero": 9, "team": "red", "x": 2.0, "y": 0.0},
		{"type": "death", "entity_type": "minion", "x": 2.0, "y": 0.0},
		{"type": "tower_destroyed", "x": 2.0, "y": 0.0, "team": "red"},
		{"type": "guard_destroyed", "x": 2.0, "y": 0.0},
	]
	var total := 0
	for event in events:
		total += plan.cues_for(event, _ctx()).size()
	gt(total, 0, "不能一帧全吞掉")
	lt(total, events.size() + 1, "团战一帧不能把所有声音都放出来（会糊成噪音）")
	eq(total, AudioPlan.MAX_CUES_PER_FRAME, "上限就是 MAX_CUES_PER_FRAME")

func test_low_health_triggers_heartbeat() -> void:
	var plan := AudioPlan.new()
	plan.reset()
	var healthy := plan.begin_frame(0.5, _ctx({"hp_ratio": 0.9}))
	eq(_names(healthy), [], "血够多不响心跳")
	var hurt := plan.begin_frame(0.5, _ctx({"hp_ratio": 0.2}))
	eq(_names(hurt), ["low_hp"], "残血开始心跳")
	var again := plan.begin_frame(0.5, _ctx({"hp_ratio": 0.2}))
	eq(_names(again), [], "心跳不能每帧都响")
	var later := plan.begin_frame(1.2, _ctx({"hp_ratio": 0.2}))
	eq(_names(later), ["low_hp"], "冷却过后再响一次")

func test_combat_heat_drives_the_music_layer() -> void:
	var plan := AudioPlan.new()
	plan.reset()
	near(plan.heat(), 0.0, 0.01, "开局没有热度")
	for i in 6:
		plan.begin_frame(0.05, _ctx())
		plan.cues_for({"type": "hit", "target": 3, "target_type": "hero", "x": 1.0, "y": 0.0}, _ctx())
	gt(plan.heat(), 0.5, "连续贴身交战把热度推起来")
	lt(plan.heat(), 1.01, "热度上限为 1")
	for i in 40:
		plan.begin_frame(0.1, _ctx())
	lt(plan.heat(), 0.25, "停手后热度衰减下去")

# ---------------------------------------------------------------- 合成音效

func test_every_planned_cue_can_be_synthesized() -> void:
	var missing := []
	for name in AudioPlan.CUES:
		var stream: AudioStreamWAV = AudioCues.cue(str(name))
		if stream == null:
			missing.append(name)
			continue
		var values := _samples(stream)
		var peak := 0.0
		var energy := 0.0
		for value in values:
			peak = maxf(peak, absf(value))
			energy += absf(value)
		gt(peak, 0.05, "%s 有实际波形（不是静音）" % name)
		lt(peak, 1.001, "%s 不削波" % name)
		gt(energy / maxf(float(values.size()), 1.0), 0.002, "%s 平均能量非零" % name)
		var seconds := _seconds(stream)
		gt(seconds, 0.02, "%s 太短，听不到" % name)
		lt(seconds, 3.5, "%s 太长，会盖住下一个音" % name)
	eq(missing, [], "AudioPlan 能发出的每个 cue 都必须有合成实现（漏一个就是静默失效）")

# 反射守卫：每个 CUE_* 常量都必须进 CUES 注册表。
# skill_assassin 就漏在这 —— 常量在、cues_for 里在用、但没进 CUES，
# 于是「每个 cue 都能合成」那条测试根本没检查它，刺客技能一直静音。
func test_every_cue_constant_is_registered() -> void:
	var constants: Dictionary = AudioPlan.new().get_script().get_script_constant_map()
	var registered := {}
	for name in AudioPlan.CUES:
		registered[str(name)] = true
	var missing := []
	for key in constants:
		var key_name := str(key)
		if not key_name.begins_with("CUE_"):
			continue
		if not registered.has(str(constants[key])):
			missing.append(key_name)
	eq(missing, [], "每个 CUE_* 常量都要进 CUES 注册表，否则守卫测试会漏掉它")

func test_cue_registry_matches_plan() -> void:
	var unknown := []
	for name in AudioPlan.CUES:
		if not AudioCues.NAMES.has(name):
			unknown.append(name)
	eq(unknown, [], "cue 名称必须两边一致，拼错会静默不出声")
	check(AudioCues.NAMES.size() >= 28, "音效表至少要覆盖战斗/地图/UI 三类，实际 %d 条" % AudioCues.NAMES.size())

func test_short_cues_stay_short() -> void:
	lt(_seconds(AudioCues.cue("ui_click")), 0.16, "UI 点击音必须极短")
	lt(_seconds(AudioCues.cue("hit_minion")), 0.2, "小兵命中音要短，否则团战会糊")
	gt(_seconds(AudioCues.cue("tower_down")), _seconds(AudioCues.cue("hit_structure")), "塔倒要比打塔重得多")
	gt(_seconds(AudioCues.cue("base_fall")), 1.0, "主堡陷落是长尾音")

# ---------------------------------------------------------------- 程序化 BGM

func test_bgm_tracks_are_audible_and_loop_cleanly() -> void:
	for name in [BgmSynth.TRACK_MENU, BgmSynth.TRACK_BATTLE, BgmSynth.TRACK_BATTLE_STEM]:
		var stream: AudioStreamWAV = BgmSynth.track(name)
		check(stream != null, "%s 有音频流" % name)
		if stream == null:
			continue
		eq(stream.format, AudioStreamWAV.FORMAT_16_BITS, "%s 是 16-bit PCM" % name)
		eq(stream.stereo, false, "%s 单声道（体积减半，够用）" % name)
		eq(stream.loop_mode, AudioStreamWAV.LOOP_FORWARD, "%s 必须原生循环，不能靠外部重播" % name)
		var count := stream.data.size() / 2
		eq(stream.loop_end, count, "%s 循环终点等于总长" % name)
		gt(stream.mix_rate, 8000, "%s 采样率有效" % name)
		var values := _samples(stream)
		var peak := 0.0
		var energy := 0.0
		for value in values:
			peak = maxf(peak, absf(value))
			energy += absf(value)
		gt(peak, 0.30, "%s 有实际波形" % name)
		lt(peak, 0.98, "%s 留有峰值余量，不和音效抢" % name)
		gt(energy / maxf(float(values.size()), 1.0), 0.02, "%s 平均能量非零" % name)
		# 接缝：循环点两侧的跳变不能超过信号自身 95% 分位的样点差。
		# 直接量「首尾差」会被正拍鼓点冤枉（第一拍本来就是瞬态），
		# 所以拿它和「这段音频正常时的样点变化」比：折尾做对了就分辨不出接缝。
		lt(_seam_delta(values), _typical_delta(values) * 1.5, "%s 循环接缝无跳变" % name)
		near(_seconds(stream), BgmSynth.loop_seconds(name), 0.02, "%s 长度与谱面一致" % name)

func test_battle_theme_is_denser_than_menu_theme() -> void:
	var menu := _high_share(_samples(BgmSynth.track(BgmSynth.TRACK_MENU)))
	var battle := _high_share(_samples(BgmSynth.track(BgmSynth.TRACK_BATTLE)))
	gt(menu, 0.005, "菜单曲也有内容（风声垫底）")
	gt(battle, menu * 1.6, "战斗曲有战鼓与踩镲，中高频占比要明显高于菜单曲（%.3f vs %.3f）" % [battle, menu])

func test_stings_are_one_shot_and_distinct() -> void:
	for name in [BgmSynth.TRACK_VICTORY, BgmSynth.TRACK_DEFEAT]:
		var stream: AudioStreamWAV = BgmSynth.track(name)
		check(stream != null, "%s 有音频流" % name)
		if stream == null:
			continue
		check(stream.loop_mode != AudioStreamWAV.LOOP_FORWARD, "%s 是一次性结算音，不能循环" % name)
		lt(_seconds(stream), 7.0, "%s 不能太长" % name)
		gt(_seconds(stream), 1.5, "%s 要能被听清" % name)
	var victory := _samples(BgmSynth.track(BgmSynth.TRACK_VICTORY))
	var defeat := _samples(BgmSynth.track(BgmSynth.TRACK_DEFEAT))
	check(victory.size() != defeat.size() or victory[victory.size() / 2] != defeat[defeat.size() / 2], "胜利与失败不能是同一段音")

# ---------------------------------------------------------------- 结构与接线守卫

func test_simulation_layer_has_no_audio_nodes() -> void:
	# 硬规则 2：sim/ 是纯逻辑，不许出现任何音频引擎对象。
	var offenders := []
	var stack := ["res://sim"]
	while not stack.is_empty():
		var dir_path: String = stack.pop_back()
		var dir := DirAccess.open(dir_path)
		if dir == null:
			continue
		for file_name in dir.get_files():
			if file_name.ends_with(".gd"):
				var source := FileAccess.get_file_as_string(dir_path + "/" + file_name)
				if source.contains("AudioStream") or source.contains("AudioServer"):
					offenders.append(dir_path + "/" + file_name)
		for sub in dir.get_directories():
			stack.append(dir_path + "/" + sub)
	eq(offenders, [], "sim/ 里不许出现音频节点")

func test_arena_wires_the_audio_director() -> void:
	var source := FileAccess.get_file_as_string("res://scripts/game/arena.gd")
	check(source.contains("res://scripts/game/audio_director.gd"), "arena 必须 preload 音频导演")
	check(source.contains("_audio.handle_events("), "战斗事件必须送进音频导演（否则打起来没声音）")
	check(source.contains("_audio.play_music("), "进入战斗必须切换 BGM")
	check(source.contains("AudioDirector.MUSIC_BATTLE"), "战斗曲常量必须真的用上")
	check(source.contains("_audio.set_context("), "音频导演必须拿到本地英雄位置与血量（距离衰减/心跳）")

func test_main_shell_wires_menu_music_and_ui_sounds() -> void:
	var source := FileAccess.get_file_as_string("res://scripts/app/main.gd")
	check(source.contains("res://scripts/game/audio_director.gd"), "应用壳必须持有音频导演")
	check(source.contains("AudioDirector.MUSIC_MENU"), "主菜单/选人/大厅要有 BGM")
	check(source.contains("play_cue(AudioCues.CUE_UI_CLICK)"), "按钮点击要有声音")
