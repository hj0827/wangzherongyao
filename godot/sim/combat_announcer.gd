extends RefCounted

const MULTI_KILL_WINDOW := 10.0 # 10秒内连续击杀判定

var _first_blood_claimed := false
var _hero_streaks := {} # hero_id -> int (当前单命连杀数)
var _last_kill_times := {} # hero_id -> float (上次击杀时间)
var _multi_kill_counts := {} # hero_id -> int (多杀段数)

func record_kill(
	killer_id: int,
	killer_hero_type: String,
	killer_team: String,
	victim_id: int,
	victim_hero_type: String,
	victim_team: String,
	time: float
) -> Dictionary:
	var result := {
		"killer_id": killer_id,
		"victim_id": victim_id,
		"announcement": "",
		"streak_title": "",
	}

	# 1. 终结判断 (Shutdown)
	var victim_streak: int = int(_hero_streaks.get(victim_id, 0))
	if victim_streak >= 3:
		result["announcement"] = "shutdown"
	_hero_streaks[victim_id] = 0
	_multi_kill_counts[victim_id] = 0

	# 2. 一血判断 (First Blood)
	if not _first_blood_claimed:
		_first_blood_claimed = true
		if str(result.announcement) == "":
			result["announcement"] = "first_blood"

	# 3. 多杀判断 (Double / Triple / Quadra / Penta)
	var last_time: float = float(_last_kill_times.get(killer_id, -999.0))
	var current_multi: int = 1
	if time - last_time <= MULTI_KILL_WINDOW:
		current_multi = int(_multi_kill_counts.get(killer_id, 1)) + 1
	_multi_kill_counts[killer_id] = current_multi
	_last_kill_times[killer_id] = time

	if current_multi == 2:
		result["announcement"] = "double_kill"
	elif current_multi == 3:
		result["announcement"] = "triple_kill"
	elif current_multi == 4:
		result["announcement"] = "quadra_kill"
	elif current_multi >= 5:
		result["announcement"] = "penta_kill"

	# 4. 连杀头衔 (Killing Spree / Rampage / Godlike / Legendary)
	var killer_streak: int = int(_hero_streaks.get(killer_id, 0)) + 1
	_hero_streaks[killer_id] = killer_streak
	if killer_streak == 3:
		result["streak_title"] = "killing_spree"
	elif killer_streak == 5:
		result["streak_title"] = "rampage"
	elif killer_streak == 7:
		result["streak_title"] = "godlike"
	elif killer_streak >= 8:
		result["streak_title"] = "legendary"

	return result

# 非英雄击杀（塔/兵/野怪）：仍然要推进一血与连杀重置，只是没有多杀播报。
func record_death(victim_id: int) -> Dictionary:
	var result := {
		"killer_id": -1,
		"victim_id": victim_id,
		"announcement": "",
		"streak_title": "",
	}
	_hero_streaks[victim_id] = 0
	_multi_kill_counts[victim_id] = 0
	if not _first_blood_claimed:
		_first_blood_claimed = true
		result["announcement"] = "first_blood"
	return result

func check_ace(team: String, team_entities: Array) -> bool:
	var hero_count := 0
	for e in team_entities:
		if str(e.get("type", "")) == "hero" and str(e.get("team", "")) == team:
			hero_count += 1
			if bool(e.get("alive", false)):
				return false
	# 1v1 里唯一的英雄阵亡不算团灭，团灭至少需要两名队友。
	return hero_count >= 2
