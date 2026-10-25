extends "res://tests/test_base.gd"

# 菜单装饰纹样的回归守卫。
#
# 起因：主菜单的标题只有「金色字 + 黑描边」，按钮是清一色的直角矩形，整体读起来
# 像一份排版工整的说明书，不像一个东方奇幻游戏的门面。
#
# 加花边这件事本身很难用肉眼验：卷草的螺线少卷半圈、中轴线左右差 2px、角饰压到
# 按钮边框上 —— 屏幕上都「看着还行」，但放大就是歪的。所以纹样几何被抽成
# scripts/ui/ornament.gd 的纯函数，用可量化的性质来守：
#
#   · 螺线半径必须单调收敛（否则会画出一朵疯长的卷）
#   · 渐细带的首尾宽度必须是真的宽度（笔锋是 taper 出来的，不是画细了）
#   · 中轴花边必须关于中心左右镜像（手写点集最容易在这里差半个像素）
#   · 角饰必须落在它被要求的那一个角里（翻转方向写反会悄悄画到对角去）
#
# 渲染端（ornate_title / ornate_frame）另有两条：浮雕层必须只往下堆、装饰层不能吃点击。

const Ornament = preload("res://scripts/ui/ornament.gd")
const OrnateTitle = preload("res://scripts/ui/ornate_title.gd")
const OrnateFrame = preload("res://scripts/ui/ornate_frame.gd")

const EPS := 0.01

func _count(parts: Dictionary) -> int:
	return (parts.get("strokes", []) as Array).size() + (parts.get("fills", []) as Array).size()

# ---------- 卷草：螺线必须真的往回收 ----------

func test_curl_shrinks_toward_its_centre() -> void:
	var centre := Vector2(10.0, 20.0)
	var points := Ornament.curl(centre, 18.0, 3.0, 0.0, TAU * 0.9, 24)
	eq(points.size(), 25, "螺线点数 = 段数 + 1")
	near(points[0].distance_to(centre), 18.0, EPS, "起点半径")
	near(points[points.size() - 1].distance_to(centre), 3.0, EPS, "收尾半径")
	# 半径单调递减。中途回弹 = 画出一朵越卷越大的疯花，屏幕上非常显眼。
	var previous := INF
	for point in points:
		var radius: float = point.distance_to(centre)
		check(radius <= previous + 0.001, "螺线半径必须单调收敛：%.3f 大于前一点 %.3f" % [radius, previous])
		previous = radius

func test_curl_rejects_a_zero_segment_count() -> void:
	# 段数为 0 时不能返回空数组：调用方会拿到一条画不出来的线，静默消失。
	var points := Ornament.curl(Vector2.ZERO, 5.0, 1.0, 0.0, TAU, 0)
	check(points.size() >= 2, "段数为 0 也至少要给出两个点")

# ---------- 渐细带：笔锋是宽度收敛出来的 ----------

func test_taper_tapers_from_both_ends() -> void:
	var band := Ornament.taper(Vector2.ZERO, Vector2(60.0, 0.0), 6.0, 0.0, 0.0, 8)
	eq(band.size(), 18, "渐细带 = 2 × (段数 + 1) 个点，首尾相接围成闭合轮廓")
	# 轮廓是「去程在左、回程在右」，所以首尾两点之间的距离就是起笔宽度。
	near(band[0].distance_to(band[band.size() - 1]), 6.0, EPS, "起笔宽度必须等于 start_width")
	# 中间那一对是终点宽度 —— 收成尖，笔锋才立得住。
	near(band[8].distance_to(band[9]), 0.0, EPS, "收笔必须收成尖")

func test_taper_keeps_its_width_at_a_bend() -> void:
	# 弯曲的花枝如果用「起点法线」一路推，拐点处宽度会塌掉，看起来像被掐了一下。
	var straight := Ornament.taper(Vector2.ZERO, Vector2(60.0, 0.0), 6.0, 6.0, 0.0, 12)
	var bent := Ornament.taper(Vector2.ZERO, Vector2(60.0, 0.0), 6.0, 6.0, 30.0, 12)
	near(straight[0].distance_to(straight[straight.size() - 1]), 6.0, EPS, "直枝起笔宽度")
	near(bent[0].distance_to(bent[bent.size() - 1]), 6.0, EPS, "弯枝起笔宽度不能被弯度吃掉")
	near(bent[12].distance_to(bent[13]), 6.0, EPS, "弯枝收笔宽度不能被弯度吃掉")

# ---------- 宝珠：等距菱形 ----------

func test_diamond_is_evenly_spaced() -> void:
	var centre := Vector2(50.0, 20.0)
	var shape := Ornament.diamond(centre, 8.0)
	eq(shape.size(), 4, "宝珠是四角菱形")
	for point in shape:
		near(point.distance_to(centre), 8.0, EPS, "四个角到中心必须等距")

# ---------- 中轴花边：必须左右镜像 ----------

func test_center_rule_mirrors_around_the_middle() -> void:
	var width := 400.0
	var parts := Ornament.center_rule(width, 0.0, 1.6)
	gt(float(_count(parts)), 2.0, "中轴花边至少要有横线与宝珠，不能只剩一条线")
	var points := Ornament.points_of(parts)
	gt(float(points.size()), 8.0, "中轴花边点数太少，画不出纹样")
	# 逐点找镜像点：每个 (x, y) 都必须存在一个 (width - x, y)。
	for point in points:
		var mirror := Vector2(width - point.x, point.y)
		var found := false
		for other in points:
			if other.distance_to(mirror) <= 0.02:
				found = true
				break
		check(found, "中轴花边不对称：缺少 (%.3f, %.3f) 的镜像点" % [mirror.x, mirror.y])

func test_center_rule_stays_within_its_width() -> void:
	var width := 320.0
	var parts := Ornament.center_rule(width, 0.0, 1.6)
	for point in Ornament.points_of(parts):
		check(point.x >= -EPS and point.x <= width + EPS, "中轴花边越界：x = %.3f" % point.x)

# ---------- 角饰：必须落在被要求的那一个角 ----------

func test_corner_ornament_stays_inside_its_corner() -> void:
	var rect := Rect2(0.0, 0.0, 300.0, 60.0)
	var arm := 18.0
	var parts := Ornament.corner(rect, arm, 2.0, Vector2i(0, 0))
	gt(float(_count(parts)), 0.0, "左上角饰至少要有一条折线")
	for point in Ornament.points_of(parts):
		check(point.x >= rect.position.x - EPS and point.x <= rect.position.x + arm + EPS,
			"左上角饰横向越界：x = %.3f（允许 0 ~ %.1f）" % [point.x, arm])
		check(point.y >= rect.position.y - EPS and point.y <= rect.position.y + arm + EPS,
			"左上角饰纵向越界：y = %.3f（允许 0 ~ %.1f）" % [point.y, arm])

func test_corner_ornament_flips_to_the_requested_corner() -> void:
	# 翻转写反在屏幕上只是「花纹跑到对角去了」，肉眼要盯很久才发现，所以按象限验。
	var rect := Rect2(0.0, 0.0, 300.0, 60.0)
	var arm := 18.0
	var placements := [
		{"anchor": Vector2i(0, 0), "x": Vector2(0.0, arm), "y": Vector2(0.0, arm)},
		{"anchor": Vector2i(1, 0), "x": Vector2(rect.size.x - arm, rect.size.x), "y": Vector2(0.0, arm)},
		{"anchor": Vector2i(0, 1), "x": Vector2(0.0, arm), "y": Vector2(rect.size.y - arm, rect.size.y)},
		{"anchor": Vector2i(1, 1), "x": Vector2(rect.size.x - arm, rect.size.x), "y": Vector2(rect.size.y - arm, rect.size.y)},
	]
	for placement in placements:
		var parts := Ornament.corner(rect, arm, 2.0, placement.anchor)
		var x_range: Vector2 = placement.x
		var y_range: Vector2 = placement.y
		for point in Ornament.points_of(parts):
			check(point.x >= x_range.x - EPS and point.x <= x_range.y + EPS,
				"anchor %s 的角饰横向跑到 %.3f" % [str(placement.anchor), point.x])
			check(point.y >= y_range.x - EPS and point.y <= y_range.y + EPS,
				"anchor %s 的角饰纵向跑到 %.3f" % [str(placement.anchor), point.y])

# ---------- 左右翼：facing 翻转只能镜像 x ----------

func test_wing_mirrors_when_facing_flips() -> void:
	var right := Ornament.wing(Vector2.ZERO, 60.0, 26.0, 1.0)
	var left := Ornament.wing(Vector2.ZERO, 60.0, 26.0, -1.0)
	var a := Ornament.points_of(right)
	var b := Ornament.points_of(left)
	eq(a.size(), b.size(), "左右翼点数必须一致，否则镜像会错位")
	gt(float(a.size()), 10.0, "单侧花枝点数太少，画不出卷草")
	for index in a.size():
		near(b[index].x, -a[index].x, 0.02, "facing = -1 必须是 x 镜像（第 %d 点）" % index)
		near(b[index].y, a[index].y, 0.02, "facing 翻转不能改动 y（第 %d 点）" % index)

func test_wing_mirrors_around_its_own_root_not_the_world_origin() -> void:
	# 真实踩过的坑：facing 翻转如果绕 x = 0 镜像，根部不在原点的花枝会被整株甩到
	# 轴的另一侧 —— 标题左边的花枝扑到字上（看着像花纹压了笔画），按钮左边的花枝
	# 直接画到负坐标、彻底看不见。上面那条用例把 origin 放在 (0,0)，所以一个都没抓到。
	var origin := Vector2(120.0, 60.0)
	var right := Ornament.points_of(Ornament.wing(origin, 40.0, 20.0, 1.0))
	var left := Ornament.points_of(Ornament.wing(origin, 40.0, 20.0, -1.0))
	eq(right.size(), left.size(), "左右翼点数必须一致")
	var nearest := INF
	for point in left:
		nearest = minf(nearest, point.distance_to(origin))
	lt(nearest, 2.0, "翻转后花枝的根部必须还贴在 origin 上，不能被镜像到别处")
	for index in right.size():
		near(left[index].x, origin.x * 2.0 - right[index].x, 0.02,
			"镜像轴必须是 origin.x，不能是 0（第 %d 点）" % index)

func test_tendril_mirrors_around_its_root_too() -> void:
	# 细须是按钮上唯一可见的花边，镜像错了整排按钮只有半边有装饰 —— 单独守一遍。
	var origin := Vector2(200.0, 30.0)
	var right := Ornament.points_of(Ornament.tendril(origin, 30.0, 20.0, 1.0))
	var left := Ornament.points_of(Ornament.tendril(origin, 30.0, 20.0, -1.0))
	eq(right.size(), left.size(), "细须左右点数必须一致")
	var reach := 0.0
	for point in right:
		reach = maxf(reach, point.distance_to(origin))
	gt(reach, 20.0, "细须必须真的伸出去，否则读不出是花边")
	for index in right.size():
		near(left[index].x, origin.x * 2.0 - right[index].x, 0.02,
			"细须的镜像轴必须是 origin.x（第 %d 点）" % index)

func test_wing_extends_outward_and_curls_up() -> void:
	# 卷草没有卷就不是卷草，只是一根斜线。这里量三件事：
	# 伸得够远、没伸出界、上下有起伏（有起伏才卷得起来）。
	var parts := Ornament.wing(Vector2.ZERO, 60.0, 26.0, 1.0)
	var points := Ornament.points_of(parts)
	gt(float(points.size()), 10.0, "单侧花枝点数太少，画不出卷草")
	var max_x := -INF
	var min_y := INF
	var max_y := -INF
	for point in points:
		max_x = maxf(max_x, point.x)
		min_y = minf(min_y, point.y)
		max_y = maxf(max_y, point.y)
	gt(max_x, 40.0, "花枝必须真的向外伸出（给定宽度 60，至少要占到 40）")
	lt(max_x, 78.0, "花枝不能超出给定宽度太多，否则会顶到旁边的文字")
	gt(max_y - min_y, 12.0, "花枝必须有上下起伏，一条直线不是卷草")

# ---------- 浮雕标题：层只能往下堆 ----------

func test_ornate_title_layers_stack_upward_toward_the_face() -> void:
	var layers := OrnateTitle.layers(112.0)
	gt(float(layers.size()), 2.0, "浮雕字至少要三层（投影 / 立体 / 面）")
	var previous_y := INF
	var previous_lum := -INF
	for layer in layers:
		var offset: Vector2 = layer.offset
		# 负偏移 = 底层跑到字的上面去了，黑边会露在笔画上沿，整行字看起来是脏的。
		check(offset.y >= 0.0, "浮雕层不能往上偏：%.2f" % offset.y)
		check(offset.y <= previous_y + 0.001,
			"越靠后的层必须越贴近原位（offset.y 单调递减）：%.2f 大于前一层 %.2f" % [offset.y, previous_y])
		previous_y = offset.y
		# 同时亮度必须单调递增 —— 否则中间某层会比它下面那层还暗，厚度就看不出来了。
		var luminance: float = (layer.color as Color).get_luminance()
		check(luminance >= previous_lum - 0.001,
			"层序必须由深到浅：亮度 %.3f 低于前一层 %.3f" % [luminance, previous_lum])
		previous_lum = luminance
	var face: Color = (layers[layers.size() - 1] as Dictionary).color
	var deepest: Color = (layers[0] as Dictionary).color
	gt(face.get_luminance(), deepest.get_luminance() + 0.2, "面层必须明显亮于最深的底层")

func test_ornate_title_measures_the_real_glyph_box() -> void:
	# 花边是按文字实测宽度画的；宽度取错会立刻变成「花纹浮在字外面」。
	var title := OrnateTitle.build("烽 火 峡 谷", 112)
	var text_width: float = title.get_meta("text_size", Vector2.ZERO).x
	gt(text_width, 200.0, "112px 的四字标题实测宽度不该小于 200px")
	gt(title.custom_minimum_size.x, text_width, "控件必须给花边留出比文字更宽的横向余量")
	gt(title.custom_minimum_size.y, title.get_meta("text_size", Vector2.ZERO).y,
		"控件必须给花边留出比文字更高的纵向余量")
	title.free()

# ---------- 按钮花边：不许吃点击、不许多余留白 ----------

func test_ornate_frame_does_not_eat_button_clicks() -> void:
	var button := Button.new()
	button.text = "单人试炼    ·    1 V 1"
	var overlay := OrnateFrame.attach(button, 58.0)
	check(overlay != null, "attach 必须返回装饰层")
	eq(overlay.mouse_filter, Control.MOUSE_FILTER_IGNORE, "花边是画上去的，不能接管按钮的点击")
	eq(button.get_child_count(), 1, "按钮上只挂一层装饰，不要叠成一堆")
	button.free()

func test_ornate_frame_hugs_the_button() -> void:
	var button := Button.new()
	button.text = "人机军团    ·    5 V 5"
	button.size = Vector2(380.0, 58.0)
	var overlay := OrnateFrame.attach(button, 58.0)
	eq(overlay.anchor_left, 0.0, "装饰层左锚点要贴满按钮")
	eq(overlay.anchor_right, 1.0, "装饰层右锚点要贴满按钮")
	eq(overlay.anchor_top, 0.0, "装饰层上锚点要贴满按钮")
	eq(overlay.anchor_bottom, 1.0, "装饰层下锚点要贴满按钮")
	check(overlay.offset_left >= 0.0 and overlay.offset_right <= 0.0,
		"装饰层不能往按钮外面撑，否则会顶乱面板布局")
	button.free()

func test_ornate_frame_reacts_to_hover() -> void:
	# 花边是「亮起来」的，不是一直亮着 —— 一直亮会盖过文字。
	var button := Button.new()
	button.text = "五人联机    ·    5 V 5"
	var overlay := OrnateFrame.attach(button, 58.0)
	var idle: float = overlay.get("glow")
	check(button.mouse_entered.get_connections().size() > 0, "必须接上悬停信号，否则花边是死的")
	check(button.mouse_exited.get_connections().size() > 0, "必须接上离开信号")
	near(idle, 0.0, EPS, "未悬停时花边处于基础亮度（glow = 0）")
	button.free()
