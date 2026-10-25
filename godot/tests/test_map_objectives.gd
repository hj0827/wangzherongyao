extends "res://tests/test_base.gd"

# 中立首领契约：暴君 / 主宰两处首领坑、首刷与刷新节奏、击杀后全队增伤。
# 首领给团队一个「争夺时间点」，而不是让玩家从头到尾只在一条路上互推。

const Objectives = preload("res://sim/map/objectives.gd")
const MapLayout = preload("res://sim/map/map_layout.gd")
const MapData = preload("res://sim/map_data.gd")

func test_two_rotated_objective_pits_with_distinct_bosses() -> void:
	eq(Objectives.PITS.size(), 2, "暴君与主宰各一处")
	var names := {}
	var halves := {}
	for pit in Objectives.PITS:
		names[str(pit.name)] = true
		# 对称用**绕地图中心 180°（-p）**，不是 y=-x 镜像：
		# mirror 保持 a = x-y 不变，也就是「同一个半场」——
		# 上一版用 mirror，结果暴君和主宰双双落在蓝方半场，红方野区一个首领都没有。
		check(MapLayout.objective_at(-(pit.pos as Vector2)).size() > 0, "首领坑必须 180° 对称")
		halves["blue" if (pit.pos as Vector2).x - (pit.pos as Vector2).y > 0.0 else "red"] = true
	eq(names.size(), 2, "两处首领名称不同")
	eq(halves.size(), 2, "暴君与主宰必须分处两个半场")
	eq(Objectives.FIRST_SPAWN, 120.0, "首领两分钟首刷")
	eq(Objectives.RESPAWN, 180.0, "首领三分钟刷新")

func test_objective_pits_stand_whole_on_the_bank() -> void:
	# 坑盘半径 5.6（arena._add_map_disc），整圈都得露出水面 ——
	# 旧数据 |a| = 14 时盘子有 1.9 米泡在河里。
	for pit in Objectives.PITS:
		var offset: float = absf((pit.pos as Vector2).x - (pit.pos as Vector2).y) * 0.70710678
		var dry: float = offset - MapData.RIVER_HALF_WIDTH
		gt(dry, 5.6, "首领坑的盘子必须整圈在岸上：%s（离水面 %.2f 米）" % [str(pit.id), dry])
	for pit in Objectives.PITS:
		gt(MapLayout.distance_to_lanes(pit.pos), MapData.LANE_HALF_WIDTH + 2.0, "首领坑不能压在兵线上：%s" % str(pit.id))

func test_objective_monster_stats_are_team_level_threats() -> void:
	for pit in Objectives.PITS:
		var stats: Dictionary = Objectives.monster_stats(pit)
		eq(str(stats.type), "monster", "首领是野怪实体")
		eq(str(stats.team), "neutral", "首领中立")
		check(bool(stats.objective), "标记为首领")
		gt(float(stats.hp), 5000.0, "首领血量远高于普通野怪")
		gt(float(stats.attack_range), 3.0, "首领会近身反击")
		eq(str(stats.objective_id), str(pit.id), "首领记住所属坑位")

func test_killing_objective_grants_team_damage_buff() -> void:
	var state := {
		"objectives": {
			"buffs": {"blue": 0.0, "red": 0.0},
		},
	}
	near(Objectives.damage_scale(state, "blue"), 1.0, 0.001, "未击杀时没有增伤")
	Objectives.grant_buff(state, "blue")
	near(Objectives.damage_scale(state, "blue"), Objectives.TEAM_DAMAGE_SCALE, 0.001, "击杀首领后全队增伤")
	near(Objectives.damage_scale(state, "red"), 1.0, 0.001, "增益只作用于击杀方")
	gt(float(state.objectives.buffs.blue), 0.0, "增益有持续时间")
	Objectives.tick(state, 10.0)
	lt(float(state.objectives.buffs.blue), Objectives.BUFF_DURATION, "增益计时会递减")
	state.objectives.buffs.blue = 0.0
	near(Objectives.damage_scale(state, "blue"), 1.0, 0.001, "增益过期后恢复")
