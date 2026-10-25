extends RefCounted
## 一次选中里，英雄台词只念一遍。
##
## 选人卡面的视频是 loop 的（`VideoStreamPlayer.loop = true`）：7 秒一轮，
## 那句台词每轮都会重念一遍 —— 停在选人界面超过 7 秒就会听到第二遍、第三遍。
## 这里把「一次选中」切成若干轮播放：
##   第 1 轮 → 原声（台词）
##   第 2 轮起 → 静音（画面照常动，只是不出声）
## 重新选中该英雄时 `reset()`，第一轮又能听到。
##
## 换轮的判据是 `stream_position` **回卷**，不是「播够了 7.29 秒」：
## 素材时长、帧率、解码起点都可能变，只有回卷是引擎自己给出的事实。
## 阈值 0.25s 用来吸收解码抖动（24fps 下一帧 0.042s，回退一两帧很正常），
## 而真回卷一次跨 7 秒以上 —— 两者差了一个量级，不会混淆。

const VOICE_DB := 0.0
const MUTED_DB := -80.0
## 位置回退超过这个量才算进入下一轮；小于它的回退视为解码抖动。
const WRAP_THRESHOLD := 0.25

var _passes := 0
var _last_position := 0.0
var _started := false

## 重新选中时调用：第一轮重新带原声。
func reset() -> void:
	_passes = 0
	_last_position = 0.0
	_started = false

## 这一轮该不该出声。第 2 轮起一律不出声。
func wants_voice() -> bool:
	return _passes == 0

## 直接喂给 `VideoStreamPlayer.volume_db`。
func volume_db() -> float:
	return VOICE_DB if wants_voice() else MUTED_DB

## 本次选中里已经走完的完整轮数。
func passes() -> int:
	return _passes

## 每帧喂一次当前播放位置。返回 true 表示这一帧刚跨进下一轮。
func sample(position: float) -> bool:
	if not _started:
		_started = true
		_last_position = position
		return false
	var wrapped: bool = position + WRAP_THRESHOLD < _last_position
	_last_position = position
	if wrapped:
		_passes += 1
	return wrapped
