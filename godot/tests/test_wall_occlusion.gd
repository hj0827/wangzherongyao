extends "res://tests/test_base.gd"

# 边界墙遮挡契约：可走范围必须让出「相机安全边距」。
#
# 场景：英雄贴到墙根，相机在英雄身后 0.76×zoom、俯角 51°，此时镜头已经越过边界墙，
# 视线在墙位置只剩 0.5~1.7 米高 —— 3.4 米的墙把英雄整条盖住，玩家看不见自己。
#
# 解法不是「墙变透明」（那只是掩盖「这个位置本来就不该能站人」），
# 而是把可走边界往里收，让英雄走不到会被挡住的地方。

const Arena = preload("res://scripts/game/arena.gd")
const MapData = preload("res://sim/map_data.gd")
const MapLayout = preload("res://sim/map/map_layout.gd")
const Collision = preload("res://sim/map/collision.gd")

const HERO_RADIUS := 0.45

func test_clamp_bounds_keeps_hero_away_from_the_wall() -> void:
	gt(MapData.CAMERA_WALL_MARGIN, 0.0, "必须存在相机安全边距")
	var limit := MapData.BOUNDS - HERO_RADIUS - MapData.CAMERA_WALL_MARGIN
	var clamped := Collision.clamp_bounds(Vector2(500.0, -500.0), HERO_RADIUS)
	near(clamped.x, limit, 0.001, "东侧可走边界要让出相机安全边距")
	near(clamped.y, -limit, 0.001, "北侧可走边界要让出相机安全边距")

func test_wall_never_hides_the_hero_at_the_walkable_limit() -> void:
	# 边界墙最高的部件是顶脊的高峰（墙顶 + 岩脊）。视线必须越过它，
	# 不能只越过墙身 —— 旧版这里写的是塔柱 5.2 + 柱帽 0.27。
	var wall_top := MapLayout.BOUNDARY_TOP
	var wall_z := -MapLayout.boundary_inner()
	var hero_z := -(MapData.BOUNDS - HERO_RADIUS - MapData.CAMERA_WALL_MARGIN)
	for zoom in [14.0, 21.0, 34.0]:
		var hero := Vector3(0.0, 0.0, hero_z)
		var cam := Arena.camera_eye(hero, Vector3(0.0, 0.0, 1.0), zoom)
		# 视线与墙线的交点：地面投影沿 z 轴，墙是 z = wall_z 的竖直平面。
		var t := (cam.z - wall_z) / (cam.z - hero_z)
		var view_y := lerpf(cam.y, hero.y + Arena.CAMERA_LOOK_HEIGHT, t)
		gt(view_y, wall_top, "zoom %.0f：贴到可走极限时视线也要高过墙顶" % zoom)
