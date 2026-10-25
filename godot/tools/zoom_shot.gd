extends SceneTree

# HUD 细节放大镜（入库工具）。
#
# 为什么要有它：小地图 206px、技能键 96px，在 1600x900 的整帧里根本看不清，
# 「图标画歪了 / 角标压住了图形 / 提示和卡片粘住」全靠肉眼盯整帧是看不出来的。
# 这里把已有截图按比例裁一块再放大，专门看这些 100px 级的东西。
#
# 用法：godot --path godot --script res://tools/zoom_shot.gd
# 产物：godot/shots/zoom_<名字>.png（shots/ 已忽略，不入库）
# 依赖：先用 tools/arena_shot.gd 或 tools/mobile_shot.gd 出整帧。

const JOBS := [
	# rect 用「占整帧的比例」，不写像素：不同工具出的图分辨率不一样。
	{"src": "hero_hud", "rect": Rect2(0.0, 0.0, 0.16, 0.30), "scale": 4, "name": "zoom_minimap"},
	{"src": "hero_hud", "rect": Rect2(0.66, 0.78, 0.34, 0.22), "scale": 3, "name": "zoom_skills"},
	{"src": "hero_hud", "rect": Rect2(0.0, 0.68, 0.42, 0.32), "scale": 3, "name": "zoom_hint_card"},
	{"src": "mobile_match_team", "rect": Rect2(0.0, 0.0, 0.14, 0.42), "scale": 4, "name": "zoom_minimap_touch"},
]

func _initialize() -> void:
	for job in JOBS:
		_zoom(str(job["src"]), job["rect"], int(job["scale"]), str(job["name"]))
	quit()

func _zoom(source: String, rect: Rect2, factor: int, name: String) -> void:
	var path := "res://shots/%s.png" % source
	if not FileAccess.file_exists(path):
		print("SKIP ", name, " (missing ", source, ")")
		return
	var image := Image.load_from_file(ProjectSettings.globalize_path(path))
	if image == null or image.is_empty():
		print("SKIP ", name, " (cannot read ", source, ")")
		return
	var size := Vector2(image.get_width(), image.get_height())
	var origin := Vector2i(int(rect.position.x * size.x), int(rect.position.y * size.y))
	var extent := Vector2i(
		maxi(1, int(rect.size.x * size.x)),
		maxi(1, int(rect.size.y * size.y))
	)
	var region := image.get_region(Rect2i(origin, extent))
	region.resize(extent.x * factor, extent.y * factor, Image.INTERPOLATE_NEAREST)
	var out := ProjectSettings.globalize_path("res://shots/%s.png" % name)
	region.save_png(out)
	print("ZOOM ", name, " ", region.get_size())
