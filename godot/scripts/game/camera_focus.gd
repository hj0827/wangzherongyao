extends RefCounted

# 相机注视点的唯一真身。
#
# 常态：刚性跟随英雄（返回 hero 原值，不做任何平滑）——移动时的稳定性全靠这一点，
# 一旦在这里叠 lerp，相机和 look_at 就产生相位差，画面开始抖。
#
# 观察态：按住小地图时，注视点从当前位置匀速滑到目标点；松手立刻滑回英雄，
# 归位完成才切回刚性跟随。滑行用 move_toward（匀速）而不是 lerp（指数衰减）：
# 指数衰减首帧走掉一大截，观感上和瞬移没区别。
#
# 两个时间参数：
# - MIN_SHOW：轻点一下至少展示这么久，否则「点哪看哪」一闪而过什么也看不见。
#   按住超过这个时长的，松手当帧就开始回位，没有额外停留。
# - MAX_SHOW：兜底。收不到松手信号（触摸丢失 / 窗口失焦）时不至于永远停在别处。

# 一次定位至少展示的时长（秒）。
const MIN_SHOW := 0.35
# 兜底上限：一直没有松手信号也强制回位。
const MAX_SHOW := 8.0
# 归位判定阈值（世界单位）。小于这个距离就当已归位，避免无限逼近带来的抖动。
const SNAP_EPSILON := 0.35

var _active := false
# 已松手，但还在补足 MIN_SHOW 的剩余展示时间。
var _tail := 0.0
var _returning := false
var _elapsed := 0.0
var _target := Vector2.ZERO
var _point := Vector3.ZERO
var _point_valid := false

func is_active() -> bool:
	return _active

# 请求把镜头移到世界坐标 world。按住期间反复调用（拖拽）即持续改目标。
# from 只在第一次请求时用作滑行起点（通常是英雄当前位置）。
func request(world: Vector2, from: Vector3) -> void:
	if not _active:
		_elapsed = 0.0
		_tail = 0.0
	_target = world
	_active = true
	_returning = false
	if not _point_valid:
		_point = Vector3(from.x, 0.0, from.z)
		_point_valid = true

# 松手：展示够久了就立刻回位，不够久就补足 MIN_SHOW 再回位。
func release() -> void:
	if not _active:
		return
	_active = false
	if _elapsed < MIN_SHOW:
		_tail = MIN_SHOW - _elapsed
	else:
		_returning = true

# 重置到「刚性跟随」状态（相机重建 / 初始化时用）。
func reset() -> void:
	_active = false
	_tail = 0.0
	_returning = false
	_elapsed = 0.0
	_point_valid = false

# 每帧调用一次，返回本帧的相机注视点。
# return_speed 留空时与 glide_speed 相同（测试用）；实际运行时归位比观察更快，
# 因为「松手立刻回到自己」需要短促。
func update(delta: float, hero: Vector3, glide_speed: float, return_speed := -1.0) -> Vector3:
	var back_speed := return_speed if return_speed >= 0.0 else glide_speed
	if _active:
		_elapsed += delta
		if _elapsed >= MAX_SHOW:
			# 兜底：一直没收到松手信号，强制退出。
			_active = false
			_returning = true
		else:
			return _slide_to_target(delta, glide_speed)
	if _tail > 0.0:
		_tail -= delta
		if _tail > 0.0:
			return _point
		_tail = 0.0
		_returning = true
	if _returning:
		_point = _point.move_toward(hero, maxf(0.0, back_speed) * delta)
		if _point.distance_to(hero) <= SNAP_EPSILON:
			# 归位完成：清掉滑行态，下一帧起走刚性分支。
			_returning = false
			_point_valid = false
			return hero
		return _point
	_point_valid = false
	return hero

func focus_point() -> Vector3:
	return _point if _point_valid else Vector3.ZERO

func _slide_to_target(delta: float, glide_speed: float) -> Vector3:
	var want := Vector3(_target.x, 0.0, _target.y)
	if not _point_valid:
		_point = want
		_point_valid = true
		return _point
	_point = _point.move_toward(want, maxf(0.0, glide_speed) * delta)
	return _point
