extends RefCounted
class_name BushFeedback

# 草丛进出的表现状态机：只负责「是否换了草丛」和镜头焦段，
# 音效/HUD 由 Arena 消费返回值统一驱动。

const MapLayout = preload("res://sim/map/map_layout.gd")

# 进入草丛时镜头轻微拉近，强化「藏起来了」的体感；数值刻意很小，
# 避免 MOBA 里频繁进出草丛导致画面来回抽动。
const FOV_SCALE := 0.92

var in_bush := false
var bush_id := ""
var _initialized := false

# 返回 "enter" / "exit" / "none"。首次采样落在草丛内也算一次进入，
# 避免出生点或传送落点在草里时漏掉提示。
func update(point: Vector2) -> String:
	var bush: Dictionary = MapLayout.bush_at(point)
	var now_in := not bush.is_empty()
	if not _initialized:
		_initialized = true
		in_bush = now_in
		bush_id = str(bush.get("id", ""))
		return "enter" if now_in else "none"
	if now_in == in_bush:
		return "none"
	in_bush = now_in
	bush_id = str(bush.get("id", ""))
	return "enter" if now_in else "exit"

func target_fov(base_fov: float) -> float:
	return base_fov * FOV_SCALE if in_bush else base_fov

# 死亡/重生时清空采样状态：复活点不在草里，下一次 update 不应补发 exit。
func reset() -> void:
	in_bush = false
	bush_id = ""
	_initialized = false
