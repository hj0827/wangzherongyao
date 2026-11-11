extends RefCounted

# 只读的地图语义查询：把世界坐标翻译成可展示的区域。
# 纯数学，不依赖任何节点，可在无头测试里直接验证。
# 近期情报面板的统计接口（inspect）随面板一起移除；区域分类与最近兵线
# 仍被表现层（arena 的植被避让）与地图契约测试共用。

const MapData = preload("res://sim/map_data.gd")
const MapLayout = preload("res://sim/map/map_layout.gd")

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
		var buff := str(camp.get("buff", ""))
		var buff_desc := "经验"
		if buff == "blue":
			buff_desc = "蓝BUFF（技能冷却缩减）"
		elif buff == "red":
			buff_desc = "红BUFF（攻击减速与增伤）"
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
	if MapData.RIVER_HALF_WIDTH > 0.0 and absf(point.x - point.y) * 0.70710678 <= MapData.RIVER_HALF_WIDTH:
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
