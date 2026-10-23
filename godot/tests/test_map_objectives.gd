extends "res://tests/test_base.gd"

# 中立首领契约：暴君 / 主宰两处镜像首领坑、首刷与刷新节奏、击杀后全队增伤。
# 首领给团队一个「争夺时间点」，而不是让玩家从头到尾只在一条路上互推。

const Objectives = preload("res://sim/map/objectives.gd")
const MapLayout = preload("res://sim/map/map_layout.gd")

func test_two_mirrored_objective_pits_with_distinct_bosses() -> void:
	eq(Objectives.PITS.size(), 2, "暴君与主宰各一处")
	var names := {}
	for pit in Objectives.PITS:
		names[str(pit.name)] = true
		check(MapLayout.objective_at(MapLayout.mirror(pit.pos)).size() > 0, "首领坑必须镜像")
	eq(names.size(), 2, "两处首领名称不同")
	eq(Objectives.FIRST_SPAWN, 120.0, "首领两分钟首刷")
	eq(Objectives.RESPAWN, 180.0, "首领三分钟刷新")

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
