extends SceneTree

# make_ui_assets.gd —— 程序化生成 UI 骨架资产（视觉升级第二批）。
#
# 运行：
#   godot --headless --path godot --script res://tools/make_ui_assets.gd
#   只重生成一类：... -- --only=frames|banners|mvp
#
# 产物（覆盖同名 PNG，手绘替换时直接盖掉即可，代码不用改）：
#   assets/ui/frames/  panel_gold.png button_gold.png slot_quality_{basic,rare,epic,legendary}.png
#   assets/ui/banners/ kill_banner.png streak_{first,double,triple,quadra,penta}.png
#   assets/ui/mvp/     mvp_bg.png medal_mvp.png medal_participation.png
#
# 为什么程序化而不是先画：
#   1. 确定性 —— 唯一随机点是固定 seed 的微光点缀，重跑产物逐字节一致，可 diff；
#   2. 零依赖 —— 只用 Godot 的 Image API，headless 可跑，队友 clone 下来就能复现；
#   3. 先占位后精修 —— 界面按最终结构（9-slice / 4:1 横幅 / 纹章位）先跑起来，
#      美术交付后只替换 PNG，不用改 game_theme 的访问器与 HUD 的接线。
#
# 画法：所有形状按 SS 倍超采样、逐行 fill_rect 硬边绘制（原生调用，快），
#       最后 LANCZOS 降采样得到抗锯齿；透明边用 fix_alpha_edges() 去掉黑边。

const SS := 3  # 超采样倍数
const PATCH_WIDTH := 4096  # 混合用 1 行色块的宽度上限（超采样像素）

const OUT_FRAMES := "res://assets/ui/frames/"
const OUT_BANNERS := "res://assets/ui/banners/"
const OUT_MVP := "res://assets/ui/mvp/"

# 与 GameTheme 同一套色：金 / 暗蓝黑底。
const GOLD := Color(0.84, 0.66, 0.34)
const GOLD_LIGHT := Color(1.0, 0.86, 0.55)
const GOLD_DARK := Color(0.42, 0.30, 0.12)
const PANEL := Color(0.035, 0.06, 0.085, 0.95)
const PANEL_LIGHT := Color(0.075, 0.11, 0.145, 0.97)
const STEEL := Color(0.72, 0.78, 0.85)
const STEEL_DARK := Color(0.36, 0.42, 0.50)

const QUALITY_COLORS := {
	"basic": Color(0.46, 0.50, 0.55),
	"rare": Color(0.36, 0.62, 1.0),
	"epic": Color(0.72, 0.42, 1.0),
	"legendary": Color(1.0, 0.72, 0.28),
}
const QUALITY_PIPS := {"basic": 1, "rare": 2, "epic": 3, "legendary": 4}
const STREAK_ORDER := ["first", "double", "triple", "quadra", "penta"]
const STREAK_COLORS := [
	Color(1.0, 0.88, 0.55),
	Color(1.0, 0.80, 0.42),
	Color(1.0, 0.68, 0.30),
	Color(1.0, 0.52, 0.24),
	Color(1.0, 0.38, 0.22),
]

var _row_patches: Dictionary = {}
var _only := ""

func _initialize() -> void:
	_parse_args()
	var started := Time.get_ticks_msec()
	if _only == "" or _only == "frames":
		_make_panel_gold()
		_make_button_gold()
		for tier in QUALITY_COLORS.keys():
			_make_quality_frame(str(tier))
	if _only == "" or _only == "banners":
		_make_kill_banner()
		for i in STREAK_ORDER.size():
			_make_streak_emblem(i + 1, str(STREAK_ORDER[i]), STREAK_COLORS[i])
	if _only == "" or _only == "mvp":
		_make_mvp_background()
		_make_medal(true)
		_make_medal(false)
	print("ui assets done in %d ms" % (Time.get_ticks_msec() - started))
	quit()

func _parse_args() -> void:
	for arg in OS.get_cmdline_user_args():
		var text := str(arg)
		if text.begins_with("--only="):
			_only = text.split("=")[1]

# ================================================================ 画布与基础图元

func _canvas(w: int, h: int) -> Image:
	var img := Image.create_empty(w * SS, h * SS, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	return img

func _save(img: Image, dir: String, file_name: String, w: int, h: int) -> void:
	img.resize(w, h, Image.INTERPOLATE_LANCZOS)
	img.fix_alpha_edges()
	var abs_dir := ProjectSettings.globalize_path(dir)
	DirAccess.make_dir_recursive_absolute(abs_dir)
	var path := abs_dir.path_join(file_name)
	var err := img.save_png(path)
	if err != OK:
		push_error("save failed: %s (%d)" % [path, err])
	else:
		print("  wrote %s%s  %dx%d" % [dir, file_name, w, h])

# 单行色块：同色只建一次 PATCH_WIDTH×1 的 patch，之后反复 blend_rect 取子区间。
# key 必须用浮点全精度：用 to_html() 会做 8bit 量化，把两张不同资产的相近颜色混成同一个
# patch，产物就会随"先生成哪一类"变化 —— 那就不是确定性生成了。
func _row_patch(color: Color) -> Image:
	var key := "%.6f_%.6f_%.6f_%.6f" % [color.r, color.g, color.b, color.a]
	if _row_patches.has(key):
		return _row_patches[key]
	var patch := Image.create_empty(PATCH_WIDTH, 1, false, Image.FORMAT_RGBA8)
	patch.fill(color)
	_row_patches[key] = patch
	return patch

func _row(img: Image, x: int, y: int, w: int, color: Color, blend: bool) -> void:
	if y < 0 or y >= img.get_height():
		return
	var start := maxi(0, x)
	var skip := start - x
	var width := mini(w - skip, img.get_width() - start)
	if width <= 0:
		return
	if blend:
		var take := mini(width, PATCH_WIDTH)
		img.blend_rect(_row_patch(color), Rect2i(0, 0, take, 1), Vector2i(start, y))
		if width > take:
			img.blend_rect(_row_patch(color), Rect2i(0, 0, PATCH_WIDTH, 1), Vector2i(start + take, y))
	else:
		img.fill_rect(Rect2i(start, y, width, 1), color)

# 圆角矩形每行的内缩量（超采样像素）。
func _corner_inset(row: int, hh: int, rr: int) -> int:
	if rr <= 0:
		return 0
	var dy := 0.0
	if row < rr:
		dy = float(rr - row) - 0.5
	elif row >= hh - rr:
		dy = float(row - (hh - rr)) + 0.5
	if dy <= 0.0:
		return 0
	return int(ceil(float(rr) - sqrt(maxf(0.0, float(rr * rr) - dy * dy))))

func _rounded(img: Image, rect: Rect2, radius: float, color: Color, blend := false) -> void:
	var x0 := int(round(rect.position.x * SS))
	var y0 := int(round(rect.position.y * SS))
	var ww := int(round(rect.size.x * SS))
	var hh := int(round(rect.size.y * SS))
	var rr := mini(int(round(radius * SS)), mini(ww, hh) / 2)
	for row in hh:
		var inset := _corner_inset(row, hh, rr)
		_row(img, x0 + inset, y0 + row, ww - inset * 2, color, blend)

func _rounded_gradient(img: Image, rect: Rect2, radius: float, top: Color, bottom: Color, blend := false) -> void:
	var x0 := int(round(rect.position.x * SS))
	var y0 := int(round(rect.position.y * SS))
	var ww := int(round(rect.size.x * SS))
	var hh := int(round(rect.size.y * SS))
	var rr := mini(int(round(radius * SS)), mini(ww, hh) / 2)
	for row in hh:
		var inset := _corner_inset(row, hh, rr)
		var t := float(row) / maxf(1.0, float(hh - 1))
		_row(img, x0 + inset, y0 + row, ww - inset * 2, top.lerp(bottom, t), blend)

# 圆角矩形描边：只画边框带（左右两段），不会把内部挖空。
func _rounded_stroke(img: Image, rect: Rect2, radius: float, thickness: float, color: Color, blend := true) -> void:
	var x0 := int(round(rect.position.x * SS))
	var y0 := int(round(rect.position.y * SS))
	var ww := int(round(rect.size.x * SS))
	var hh := int(round(rect.size.y * SS))
	var rr := mini(int(round(radius * SS)), mini(ww, hh) / 2)
	var tt := maxi(1, int(round(thickness * SS)))
	for row in hh:
		var outer := _corner_inset(row, hh, rr)
		var inner := 0
		var band := 0
		if row >= tt and row < hh - tt:
			var dy := 0.0
			var ir := maxi(0, rr - tt)
			if row - tt < ir:
				dy = float(ir - (row - tt)) - 0.5
			elif row - tt >= hh - tt - ir:
				dy = float((row - tt) - (hh - tt - ir)) + 0.5
			if dy > 0.0:
				inner = int(ceil(float(ir) - sqrt(maxf(0.0, float(ir * ir) - dy * dy))))
			band = tt - (inner - outer)
		if band <= 0:
			_row(img, x0 + outer, y0 + row, ww - outer * 2, color, blend)
			continue
		_row(img, x0 + outer, y0 + row, band, color, blend)
		_row(img, x0 + ww - outer - band, y0 + row, band, color, blend)

func _ellipse(img: Image, center: Vector2, radius: Vector2, color: Color, blend := true) -> void:
	var cx := int(round(center.x * SS))
	var cy := int(round(center.y * SS))
	var rx := radius.x * float(SS)
	var ry := radius.y * float(SS)
	if rx <= 0.0 or ry <= 0.0:
		return
	for row in range(int(round(float(cy) - ry)), int(round(float(cy) + ry)) + 1):
		var dy := float(row - cy) / ry
		if absf(dy) > 1.0:
			continue
		var half := rx * sqrt(maxf(0.0, 1.0 - dy * dy))
		_row(img, int(round(float(cx) - half)), row, int(round(half * 2.0)), color, blend)

# 椭圆描边：只画环带，不挖空内部。
func _ellipse_stroke(img: Image, center: Vector2, radius: Vector2, thickness: float, color: Color, blend := true) -> void:
	var cx := int(round(center.x * SS))
	var cy := int(round(center.y * SS))
	var rx := radius.x * float(SS)
	var ry := radius.y * float(SS)
	var tt := thickness * float(SS)
	var in_rx := rx - tt
	var in_ry := ry - tt
	if rx <= 0.0 or ry <= 0.0:
		return
	for row in range(int(round(float(cy) - ry)), int(round(float(cy) + ry)) + 1):
		var dy := float(row - cy) / ry
		if absf(dy) > 1.0:
			continue
		var half := rx * sqrt(maxf(0.0, 1.0 - dy * dy))
		var inner := 0.0
		if in_rx > 0.0 and in_ry > 0.0 and absf(float(row - cy)) < in_ry:
			var idy := float(row - cy) / in_ry
			inner = in_rx * sqrt(maxf(0.0, 1.0 - idy * idy))
		var left := int(round(float(cx) - half))
		var right := int(round(float(cx) + half))
		var inner_left := int(round(float(cx) - inner))
		var inner_right := int(round(float(cx) + inner))
		_row(img, left, row, inner_left - left, color, blend)
		_row(img, inner_right, row, right - inner_right, color, blend)

# 柔光：同心椭圆逐层叠加，比逐像素高斯快得多。
func _glow(img: Image, center: Vector2, radius: Vector2, color: Color, layers := 16) -> void:
	for i in range(layers, 0, -1):
		var f := float(i) / float(layers)
		var layer := Color(color.r, color.g, color.b, color.a / float(layers))
		_ellipse(img, center, radius * f, layer, true)

func _diamond(img: Image, center: Vector2, half: float, color: Color, blend := true) -> void:
	var cx := int(round(center.x * SS))
	var cy := int(round(center.y * SS))
	var hh := half * float(SS)
	for row in range(int(round(float(cy) - hh)), int(round(float(cy) + hh)) + 1):
		var dy := absf(float(row - cy)) / hh
		if dy > 1.0:
			continue
		var w := int(round((1.0 - dy) * hh * 2.0))
		_row(img, int(round(float(cx) - float(w) * 0.5)), row, w, color, blend)

# 粗线段（方形笔头 + 超采样，端点够用）。
func _stroke(img: Image, a: Vector2, b: Vector2, thickness: float, color: Color, blend := true) -> void:
	var steps := maxi(1, int(ceil((b - a).length() * float(SS))))
	var size := maxi(2, int(round(thickness * float(SS))))
	var patch := Image.create_empty(size, size, false, Image.FORMAT_RGBA8)
	patch.fill(color)
	for i in range(steps + 1):
		var p: Vector2 = a.lerp(b, float(i) / float(steps))
		var x := int(round(p.x * SS)) - size / 2
		var y := int(round(p.y * SS)) - size / 2
		if blend:
			img.blend_rect(patch, Rect2i(0, 0, size, size), Vector2i(x, y))
		else:
			img.fill_rect(Rect2i(x, y, size, size), color)

# 扫描线多边形（偶奇规则），用来画星形这类小徽记。
func _polygon(img: Image, points: Array, color: Color, blend := true) -> void:
	if points.size() < 3:
		return
	var min_y := INF
	var max_y := -INF
	for p in points:
		min_y = minf(min_y, (p as Vector2).y * float(SS))
		max_y = maxf(max_y, (p as Vector2).y * float(SS))
	for row in range(int(floor(min_y)), int(ceil(max_y)) + 1):
		var xs: Array[float] = []
		for i in points.size():
			var a: Vector2 = points[i]
			var b: Vector2 = points[(i + 1) % points.size()]
			var ay := a.y * float(SS)
			var by := b.y * float(SS)
			if (ay <= float(row) and by > float(row)) or (by <= float(row) and ay > float(row)):
				var t := (float(row) - ay) / (by - ay)
				xs.append((a.x + (b.x - a.x) * t) * float(SS))
		if xs.size() < 2:
			continue
		xs.sort()
		for k in range(0, xs.size() - 1, 2):
			var x0 := int(round(xs[k]))
			var x1 := int(round(xs[k + 1]))
			_row(img, x0, row, x1 - x0, color, blend)

func _star_points(center: Vector2, outer: float, inner: float, spikes := 5) -> Array:
	var pts: Array = []
	for i in spikes * 2:
		var r := outer if i % 2 == 0 else inner
		var angle := -PI * 0.5 + PI * float(i) / float(spikes)
		pts.append(center + Vector2(cos(angle), sin(angle)) * r)
	return pts

# ================================================================ 9-slice 边框

# 四个角的 L 形饰角 + 菱形钉，全部落在 24px 切片区内，九宫格拉伸不会变形。
func _corner_ornaments(img: Image, size: int, inset: float, color: Color) -> void:
	for sx in [1.0, -1.0]:
		for sy in [1.0, -1.0]:
			var cx := inset if sx > 0.0 else float(size) - inset
			var cy := inset if sy > 0.0 else float(size) - inset
			var corner := Vector2(cx, cy)
			_stroke(img, corner, corner + Vector2(sx * 8.0, 0.0), 1.6, color)
			_stroke(img, corner, corner + Vector2(0.0, sy * 8.0), 1.6, color)
			_diamond(img, corner + Vector2(sx * 6.0, sy * 6.0), 2.0, color)

func _make_panel_gold() -> void:
	var size := 96
	var img := _canvas(size, size)
	var plate := Rect2(2, 2, float(size - 4), float(size - 4))
	# 金边（上亮下暗）+ 内部暗底；再补一圈内细线与角饰。
	_rounded_gradient(img, plate, 10.0, GOLD_LIGHT, GOLD_DARK)
	_rounded(img, plate.grow(-2.4), 8.0, PANEL)
	_rounded_stroke(img, Rect2(7, 7, float(size - 14), float(size - 14)), 6.0, 1.0, Color(GOLD, 0.28))
	_corner_ornaments(img, size, 7.0, Color(GOLD_LIGHT, 0.85))
	_save(img, OUT_FRAMES, "panel_gold.png", size, size)

func _make_button_gold() -> void:
	var size := 96
	var img := _canvas(size, size)
	var plate := Rect2(1, 1, float(size - 2), float(size - 2))
	_rounded_gradient(img, plate, 10.0, GOLD, GOLD_DARK)
	_rounded_gradient(img, plate.grow(-2.0), 8.5, PANEL_LIGHT, PANEL)
	# 顶部高光 + 底部压暗：按钮才有"按得动"的立体感。
	_rounded(img, Rect2(9, 6, float(size - 18), 2.0), 1.0, Color(GOLD_LIGHT, 0.35))
	_rounded(img, Rect2(9, float(size - 9), float(size - 18), 2.0), 1.0, Color(GOLD_DARK, 0.55))
	for sx in [1.0, -1.0]:
		for sy in [1.0, -1.0]:
			var px := 8.0 if sx > 0.0 else float(size - 8)
			var py := 8.0 if sy > 0.0 else float(size - 8)
			_diamond(img, Vector2(px, py), 2.2, Color(GOLD_LIGHT, 0.9))
	_save(img, OUT_FRAMES, "button_gold.png", size, size)

func _make_quality_frame(tier: String) -> void:
	var size := 72
	var accent: Color = QUALITY_COLORS.get(tier, QUALITY_COLORS["basic"])
	var img := _canvas(size, size)
	var plate := Rect2(2, 2, float(size - 4), float(size - 4))
	_rounded_gradient(img, plate, 8.0, accent.lightened(0.25), accent.darkened(0.35))
	_rounded(img, plate.grow(-2.2), 6.5, Color(0.03, 0.045, 0.06, 0.95))
	_rounded_stroke(img, Rect2(6, 6, float(size - 12), float(size - 12)), 5.0, 1.0, Color(accent, 0.25))
	# 角上的小折角 + 底部品质星数（1/2/3/4），一眼读出档次。
	for sx in [1.0, -1.0]:
		for sy in [1.0, -1.0]:
			var cx := 6.0 if sx > 0.0 else float(size - 6)
			var cy := 6.0 if sy > 0.0 else float(size - 6)
			var corner := Vector2(cx, cy)
			_stroke(img, corner, corner + Vector2(sx * 6.0, 0.0), 1.5, Color(accent, 0.8))
			_stroke(img, corner, corner + Vector2(0.0, sy * 6.0), 1.5, Color(accent, 0.8))
	var pips := int(QUALITY_PIPS.get(tier, 1))
	var gap := 6.0
	var start_x := float(size) * 0.5 - gap * float(pips - 1) * 0.5
	for i in pips:
		_diamond(img, Vector2(start_x + gap * float(i), float(size) - 8.0), 2.4, accent)
	_save(img, OUT_FRAMES, "slot_quality_%s.png" % tier, size, size)

# ================================================================ 击杀横幅与连杀纹章

func _make_kill_banner() -> void:
	var w := 1024
	var h := 256
	var img := _canvas(w, h)
	var plate := Rect2(8, 8, float(w - 16), float(h - 16))
	_rounded_gradient(img, plate, 22.0, GOLD, GOLD_DARK)
	_rounded_gradient(img, plate.grow(-2.6), 20.0, Color(0.055, 0.075, 0.105, 0.94), Color(0.015, 0.025, 0.038, 0.96))
	# 中心压暗一块，让白字/金字的对比度稳定。
	_glow(img, Vector2(512, 128), Vector2(430, 96), Color(0.0, 0.0, 0.0, 0.35), 10)
	# 上下金轨 + 两端斜翼：左右各留出 ~120px 给头像位。
	_rounded(img, Rect2(70, 30, 884, 6), 3.0, Color(GOLD, 0.85))
	_rounded(img, Rect2(70, 220, 884, 6), 3.0, Color(GOLD, 0.7))
	_stroke(img, Vector2(38, 44), Vector2(64, 128), 3.0, Color(GOLD_LIGHT, 0.8))
	_stroke(img, Vector2(38, 212), Vector2(64, 128), 3.0, Color(GOLD_LIGHT, 0.8))
	_stroke(img, Vector2(986, 44), Vector2(960, 128), 3.0, Color(GOLD_LIGHT, 0.8))
	_stroke(img, Vector2(986, 212), Vector2(960, 128), 3.0, Color(GOLD_LIGHT, 0.8))
	# 中轴装饰：一个大菱形 + 两条细线，给名字做底纹。
	_diamond(img, Vector2(512, 128), 96.0, Color(GOLD, 0.07))
	_rounded(img, Rect2(206, 112, 612, 1.6), 0.8, Color(GOLD_LIGHT, 0.20))
	_rounded(img, Rect2(206, 142, 612, 1.6), 0.8, Color(GOLD_LIGHT, 0.20))
	_diamond(img, Vector2(512, 128), 7.0, Color(GOLD_LIGHT, 0.55))
	# 固定 seed 的微光点缀：确定性，不引入 diff 噪声。
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261111
	for i in 14:
		var px := rng.randf_range(120.0, float(w) - 120.0)
		var py := rng.randf_range(46.0, 86.0) if i % 2 == 0 else rng.randf_range(170.0, 210.0)
		_diamond(img, Vector2(px, py), rng.randf_range(1.4, 2.6), Color(GOLD_LIGHT, 0.30), true)
	_save(img, OUT_BANNERS, "kill_banner.png", w, h)

func _make_streak_emblem(streak: int, name: String, accent: Color) -> void:
	var size := 256
	var center := Vector2(128, 128)
	var img := _canvas(size, size)
	# 背光 → 暗盘 → 金环：越靠后的连杀越亮、射线越多。
	_glow(img, center, Vector2(112, 112), Color(accent, 0.45 + 0.06 * float(streak)), 18)
	_ellipse(img, center, Vector2(96, 96), Color(0.03, 0.045, 0.06, 0.96), false)
	_ellipse(img, center, Vector2(90, 90), Color(accent, 0.10), true)
	var rays := 8 + streak * 2
	for i in rays:
		var angle := TAU * float(i) / float(rays)
		var dir := Vector2(cos(angle), sin(angle))
		_stroke(img, center + dir * 60.0, center + dir * 92.0, 2.0, Color(accent, 0.45), true)
	_ellipse_stroke(img, center, Vector2(98, 98), 5.0, accent)
	_ellipse_stroke(img, center, Vector2(88, 88), 1.6, Color(accent.lightened(0.4), 0.55))
	# 中心纹章：streak 个菱形绕一圈排开 —— 数得清、也一眼看得出等级。
	if streak == 1:
		_diamond(img, center, 26.0, accent)
		_diamond(img, center, 13.0, Color(1, 1, 1, 0.85))
	else:
		for i in streak:
			var angle := -PI * 0.5 + TAU * float(i) / float(streak)
			var p := center + Vector2(cos(angle), sin(angle)) * 30.0
			_diamond(img, p, 13.0, accent)
		_diamond(img, center, 9.0, Color(accent.lightened(0.5), 0.9))
	_save(img, OUT_BANNERS, "streak_%s.png" % name, size, size)

# ================================================================ MVP 结算

func _make_mvp_background() -> void:
	var w := 768
	var h := 512
	var img := _canvas(w, h)
	var plate := Rect2(6, 6, float(w - 12), float(h - 12))
	_rounded_gradient(img, plate, 20.0, GOLD, GOLD_DARK)
	_rounded_gradient(img, plate.grow(-2.6), 18.0, Color(0.06, 0.085, 0.115, 0.97), Color(0.012, 0.02, 0.032, 0.98))
	# 顶部天光：逐行渐隐的暖色，比长射线稳（射线一出画框就会顶穿圆角）。
	var top_from := 22
	var top_to := 250
	var band_x := int(round((plate.position.x + 3.0) * float(SS)))
	var band_w := int(round((plate.size.x - 6.0) * float(SS)))
	for row in range(top_from, top_to):
		var t := float(row - top_from) / float(top_to - top_from)
		var band := Color(GOLD.r, GOLD.g, GOLD.b, 0.20 * (1.0 - t) * (1.0 - t))
		_row(img, band_x, row * SS, band_w, band, true)
	# 中部：只留一块柔和的暗底给头像/勋章，不再画大圆环 ——
	# 结算页那一行是 [勋章][头像][标题]，圆环会和标题打架。
	var medal := Vector2(384, 208)
	_glow(img, medal, Vector2(210, 130), Color(0.0, 0.0, 0.0, 0.40), 14)
	# 地平线 + 底部数据条：给名字/战绩留一条稳定的深色带。
	_rounded(img, Rect2(48, 340, float(w - 96), 2.0), 1.0, Color(GOLD, 0.30))
	_rounded(img, Rect2(52, 372, float(w - 104), 92), 14.0, Color(0.015, 0.025, 0.038, 0.75))
	_rounded(img, Rect2(70, 374, float(w - 140), 1.6), 0.8, Color(GOLD, 0.40))
	_rounded_stroke(img, Rect2(22, 22, float(w - 44), float(h - 44)), 15.0, 1.2, Color(GOLD, 0.28))
	for sx in [1.0, -1.0]:
		for sy in [1.0, -1.0]:
			var cx := 34.0 if sx > 0.0 else float(w - 34)
			var cy := 34.0 if sy > 0.0 else float(h - 34)
			var corner := Vector2(cx, cy)
			_stroke(img, corner, corner + Vector2(sx * 16.0, 0.0), 2.0, Color(GOLD_LIGHT, 0.7))
			_stroke(img, corner, corner + Vector2(0.0, sy * 16.0), 2.0, Color(GOLD_LIGHT, 0.7))
	_save(img, OUT_MVP, "mvp_bg.png", w, h)

func _make_medal(is_mvp: bool) -> void:
	var size := 128
	var center := Vector2(64, 58)
	var light := GOLD_LIGHT if is_mvp else STEEL
	var dark := GOLD_DARK if is_mvp else STEEL_DARK
	var img := _canvas(size, size)
	# 绶带
	var ribbon := Color(0.68, 0.16, 0.16) if is_mvp else Color(0.28, 0.34, 0.42)
	_stroke(img, Vector2(50, 92), Vector2(34, 124), 13.0, ribbon)
	_stroke(img, Vector2(78, 92), Vector2(94, 124), 13.0, ribbon)
	# 盘面：外深环 → 亮环 → 内盘，层次靠"填-填-填"而不是挖空。
	_glow(img, center, Vector2(52, 52), Color(light, 0.35), 12)
	_ellipse(img, center, Vector2(44, 44), dark, false)
	_ellipse(img, center, Vector2(41, 41), light, false)
	_ellipse(img, center, Vector2(34, 34), dark.lerp(light, 0.35), false)
	_ellipse_stroke(img, center, Vector2(44, 44), 2.5, light.lightened(0.2))
	# 桂冠刻线
	for i in 14:
		var angle := PI * 0.18 + PI * 0.64 * float(i) / 13.0
		var dir := Vector2(cos(angle), sin(angle))
		_stroke(img, center + dir * 36.0, center + dir * 43.0, 1.8, Color(dark, 0.9), true)
	# 中心徽记：MVP 五角星 / 参战交叉双剑
	if is_mvp:
		_polygon(img, _star_points(center, 22.0, 9.0), Color(1.0, 0.97, 0.86))
		_polygon(img, _star_points(center, 9.0, 4.0), Color(0.72, 0.44, 0.12))
	else:
		_stroke(img, center + Vector2(-13, -14), center + Vector2(13, 14), 3.0, Color(0.92, 0.95, 0.99))
		_stroke(img, center + Vector2(13, -14), center + Vector2(-13, 14), 3.0, Color(0.92, 0.95, 0.99))
		_diamond(img, center, 5.0, Color(0.16, 0.20, 0.26))
	_save(img, OUT_MVP, "medal_%s.png" % ("mvp" if is_mvp else "participation"), size, size)
