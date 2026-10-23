extends RefCounted

# 只读的地图情报查询：把「点了地图上的哪个位置」翻译成可展示的区域与附近单位。
# 纯数学 + 快照读取，不依赖任何节点，可在无头测试里直接验证。

const MapData = preload("res://sim/map_data.gd")
const MapLayout = preload("res://sim/map/map_layout.gd")

const INSPECT_RADIUS := 16.0
const MAX_UNITS := 4

const TYPE_LABEL := {
	"hero": "英雄",
	"minion": "小兵",
	"tower": "防御塔",
	"guard": "双子塔",
	"base": "主堡",
	"monster": "野怪",
}
const LANE_LABEL := {
	"mid": "中路",
	"top": "上路",
	"bottom": "下路",
}

# 区域归类优先级：泉水 > 河道 > 兵线 > 野区。
# 河道压在兵线上面，是因为中路桥面同时落在两者范围内，玩家点击桥面时
# 更想知道「这是河道要冲」而不是「这是中路」。
static func region_at(point: Vector2) -> Dictionary:
	var pit: Dictionary = MapLayout.objective_at(point)
	if not pit.is_empty():
		return {
			"name": str(pit.get("name", "首领坑")),
			"kind": "objective",
			"team": "",
			"lane": "",
			"note": "%s首领坑 · 争夺团队级增伤与推进增益" % str(pit.get("name", "首领")),
		}
	var camp: Dictionary = MapLayout.camp_at(point)
	if not camp.is_empty():
		var buff_desc := "蓝BUFF（技能冷却缩减）" if str(camp.get("buff", "")) == "blue" else "红BUFF（攻击减速与增伤）"
		return {
			"name": "%s营地" % str(camp.get("name", "野怪")),
			"kind": "camp",
			"team": "",
			"lane": "",
			"note": "野区营地 · 击杀获得%s" % buff_desc,
		}
	var bush: Dictionary = MapLayout.bush_at(point)
	if not bush.is_empty():
		return {
			"name": "草丛",
			"kind": "bush",
			"team": "",
			"lane": "",
			"note": "草丛隐匿 · 避开敌方视野进行埋伏或脱身",
		}
	if point.distance_to(MapData.BLUE_BASE) <= MapData.FOUNTAIN_RADIUS:
		return {
			"name": "蓝方泉水",
			"kind": "fountain",
			"team": "blue",
			"lane": "",
			"note": "蓝方基地核心 · 每秒回复 18% 生命与法力",
		}
	if point.distance_to(MapData.RED_BASE) <= MapData.FOUNTAIN_RADIUS:
		return {
			"name": "红方泉水",
			"kind": "fountain",
			"team": "red",
			"lane": "",
			"note": "红方基地核心 · 每秒回复 18% 生命与法力",
		}
	if MapData.RIVER_HALF_WIDTH > 0.0 and absf(point.x + point.y) * 0.70710678 <= MapData.RIVER_HALF_WIDTH:
		return {
			"name": "河道",
			"kind": "river",
			"team": "",
			"lane": "",
			"note": "河道要冲 · 视野与中路团战的关键地带",
		}
	var nearest := nearest_lane(point)
	if float(nearest.distance) <= MapData.LANE_HALF_WIDTH:
		var lane := str(nearest.lane)
		var lane_name := str(LANE_LABEL.get(lane, "兵线"))
		return {
			"name": lane_name,
			"kind": "lane",
			"team": "",
			"lane": lane,
			"note": "%s兵线 · 防御塔与兵线推进路径" % lane_name,
		}
	return {
		"name": "野区",
		"kind": "jungle",
		"team": "",
		"lane": "",
		"note": "野区 · 绕后包抄与埋伏区域",
	}

static func nearest_lane(point: Vector2) -> Dictionary:
	var best := {"lane": "mid", "distance": INF}
	for lane in MapData.LANE_ORDER:
		var path: Array = MapData.lane_path(lane)
		for index in range(path.size() - 1):
			var a: Vector2 = path[index]
			var b: Vector2 = path[index + 1]
			var ab := b - a
			var length_sq := ab.length_squared()
			if length_sq < 0.0001:
				continue
			var t := clampf((point - a).dot(ab) / length_sq, 0.0, 1.0)
			var distance := point.distance_to(a + ab * t)
			if distance < float(best.distance):
				best = {"lane": lane, "distance": distance}
	return best

# snapshot 为只读快照；统计口径与 HUD 一致：
# 死亡单位不算，发起者自己不算，只保留半径内单位并按距离由近到远排序。
static func inspect(
	snapshot: Dictionary,
	point: Vector2,
	local_owner: String,
	_local_team := "blue",
	radius := INSPECT_RADIUS
) -> Dictionary:
	var region := region_at(point)
	var units: Array = []
	var counts := {"blue": 0, "red": 0}
	var hero_found := false
	var hero_distance := -1.0
	for entity in snapshot.get("entities", []):
		if not bool(entity.get("alive", false)):
			continue
		var kind := str(entity.get("type", ""))
		if not TYPE_LABEL.has(kind):
			continue
		var entity_pos := Vector2(float(entity.get("x", 0.0)), float(entity.get("y", 0.0)))
		if kind == "hero" and str(entity.get("owner_id", "")) == local_owner:
			hero_found = true
			hero_distance = point.distance_to(entity_pos)
			continue
		var distance := point.distance_to(entity_pos)
		if distance > radius:
			continue
		var team := str(entity.get("team", "blue"))
		counts[team] = int(counts.get(team, 0)) + 1
		units.append({
			"id": int(entity.get("id", -1)),
			"kind": kind,
			"team": team,
			"label": _label(entity, kind),
			"level": int(entity.get("level", 0)),
			"hp": float(entity.get("hp", 0.0)),
			"max_hp": maxf(1.0, float(entity.get("max_hp", 0.0))),
			"distance": distance,
		})
	units.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a.distance) < float(b.distance)
	)
	return {
		"point": point,
		"region": region,
		"radius": radius,
		"units": units.slice(0, MAX_UNITS),
		"total": units.size(),
		"counts": counts,
		"hero_found": hero_found,
		"hero_distance": hero_distance,
	}

static func _label(entity: Dictionary, kind: String) -> String:
	if kind == "hero":
		return str(entity.get("name", "英雄"))
	return str(TYPE_LABEL.get(kind, "单位"))
