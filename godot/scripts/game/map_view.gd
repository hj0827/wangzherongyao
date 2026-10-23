extends RefCounted

# 地图表现适配层：Arena 与 Minimap 都从这里取几何和视觉语义，
# 保证「模拟碰撞用哪条线，地面和小地图就画哪条线」。

const MapData = preload("res://sim/map_data.gd")
const MapLayout = preload("res://sim/map/map_layout.gd")
const GameTheme = preload("res://scripts/ui/game_theme.gd")

const LANE_SMOOTH_STEPS := 6
const TOWER_SCALE := {"outer": 1.0, "inner": 1.07, "high": 1.16, "twin": 0.92}
const TIER_LABELS := {"outer": "外塔", "inner": "内塔", "high": "高地塔", "twin": "双子塔"}
const TEAM_LABELS := {"blue": "蓝方", "red": "红方", "neutral": "中立"}

static func lane_path(lane: String) -> Array:
	return MapLayout.smoothed_lane(lane, LANE_SMOOTH_STEPS)

static func tower_scale(tier: String) -> float:
	return float(TOWER_SCALE.get(tier, 1.0))

static func structure_locked(entity: Dictionary) -> bool:
	return bool(entity.get("alive", true)) and not bool(entity.get("vulnerable", true))

static func structure_tint(team_color: Color, entity: Dictionary) -> Color:
	if structure_locked(entity):
		return team_color.lerp(Color(0.64, 0.69, 0.76), 0.62)
	return team_color

static func map_marks() -> Dictionary:
	return {
		"walls": MapLayout.WALLS,
		"bushes": MapLayout.BUSHES,
		"camps": MapLayout.CAMPS,
		"objectives": MapLayout.OBJECTIVE_PITS,
		"tower_slots": MapLayout.tower_slots(),
		"guards": MapLayout.guardian_slots(),
		"river_spirits": MapLayout.RIVER_SPIRITS,
		"teleports": MapLayout.TELEPORT_PADS,
	}

# 战斗事件 → 播报文案。返回空字典表示该事件不需要横幅。
static func event_banner(event: Dictionary) -> Dictionary:
	var kind := str(event.get("type", ""))
	var team := str(event.get("team", ""))
	var team_label := str(TEAM_LABELS.get(team, "战场"))
	match kind:
		"objective_killed":
			var boss := str(event.get("name", "中立首领"))
			return {
				"text": "%s击杀%s" % [team_label, boss],
				"feed": "%s已被%s击杀，全队获得增伤" % [boss, team_label],
				"color": GameTheme.GOLD_LIGHT,
				"announce": true,
				"duration": 2.0,
			}
		"buff_taken":
			var buff := "蓝BUFF" if str(event.get("buff", "")) == "blue" else "红BUFF"
			return {
				"text": "%s获得%s" % [team_label, buff],
				"feed": "%s拿下了%s增益" % [team_label, buff],
				"color": GameTheme.BLUE if buff == "蓝BUFF" else GameTheme.RED,
				"announce": false,
				"duration": 1.2,
			}
		"base_exposed":
			return {
				"text": "%s主堡暴露" % team_label,
				"feed": "%s高地塔失守，主堡暴露" % team_label,
				"color": GameTheme.GOLD_LIGHT,
				"announce": true,
				"duration": 2.0,
			}
		"tower_destroyed":
			var tier_label := str(TIER_LABELS.get(str(event.get("tier", "outer")), "防御塔"))
			return {
				"text": "%s%s被摧毁" % [team_label, tier_label],
				"feed": "%s%s被摧毁" % [team_label, tier_label],
				"color": GameTheme.GOLD_LIGHT,
				"announce": false,
				"duration": 1.4,
			}
		"guard_destroyed":
			var left := int(event.get("guards_left", 0))
			return {
				"text": "%s双子塔被摧毁" % team_label,
				"feed": "%s双子塔被摧毁，剩余 %d 座，水晶护盾减弱" % [team_label, left],
				"color": GameTheme.GOLD_LIGHT,
				"announce": true,
				"duration": 1.8,
			}
		"crystal_shield_broken":
			return {
				"text": "%s水晶护盾破碎" % team_label,
				"feed": "%s双子塔全毁，水晶护盾消失" % team_label,
				"color": GameTheme.GOLD_LIGHT,
				"announce": true,
				"duration": 2.0,
			}
		"river_spirit_killed":
			return {
				"text": "%s击杀河道之灵" % team_label,
				"feed": "%s获得 60 秒河道视野" % team_label,
				"color": Color(0.46, 0.84, 0.92),
				"announce": true,
				"duration": 1.8,
			}
		"ace":
			return {
				"text": "%s团灭" % team_label,
				"feed": "%s全员阵亡，遭到团灭" % team_label,
				"color": GameTheme.GOLD_LIGHT,
				"announce": true,
				"duration": 2.0,
			}
	return {}
