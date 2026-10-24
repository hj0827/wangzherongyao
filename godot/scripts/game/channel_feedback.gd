extends RefCounted
class_name ChannelFeedback

# 回城 / 传送的「引导中」表现状态机（纯逻辑，不碰节点）。
#
# 只做一件事：把每帧的英雄快照翻译成「这一帧是否发生了起手 / 结束」，
# 以及当前该画到什么进度。瞬时爆发与音效交给事件层 —— 因为只有事件知道
# 这次是「完成」还是「被打断」，状态机只看得到标记被清空。
#
# 转换语义：
#   "" -> "recall"      = recall_start
#   "" -> "teleport"    = teleport_start
#   "recall" -> "teleport" = teleport_start（模拟层里传送会顶掉回城，就地换配色）
#   "x" -> ""           = x_stop（收尾淡出；不区分原因）

const KIND_RECALL := "recall"
const KIND_TELEPORT := "teleport"

var _kind := ""
var _progress := 0.0

# 返回 "none" / "recall_start" / "recall_stop" / "teleport_start" / "teleport_stop"。
func update(hero: Dictionary) -> String:
	var next := _kind_of(hero)
	_progress = _progress_of(hero, next)
	if next == _kind:
		return "none"
	var previous := _kind
	_kind = next
	if next != "":
		# 回城直接切到传送时只需要一次 start：法阵会就地换配色，不必先收尾再重建。
		return next + "_start"
	if previous != "":
		return previous + "_stop"
	return "none"

func kind() -> String:
	return _kind

# 0..1 的引导进度，供法阵收拢 / 光柱升高 / 粒子加密使用。
func progress() -> float:
	return _progress

func reset() -> void:
	_kind = ""
	_progress = 0.0

# 传送优先：模拟层里开始传送会立刻打断回城，同一帧两个标记都为真时不能画回城。
func _kind_of(hero: Dictionary) -> String:
	if bool(hero.get("teleporting", false)):
		return KIND_TELEPORT
	if bool(hero.get("recalling", false)):
		return KIND_RECALL
	return ""

func _progress_of(hero: Dictionary, kind: String) -> float:
	if kind == "":
		return 0.0
	var total := float(hero.get(kind + "_total", 0.0))
	if total <= 0.0001:
		# 刚起手那一帧 total 可能还没写进快照，或者字段缺失：按 0 处理，不能除零出 NaN。
		return 0.0
	var remaining := float(hero.get(kind + "_timer", 0.0))
	return clampf(1.0 - remaining / total, 0.0, 1.0)
