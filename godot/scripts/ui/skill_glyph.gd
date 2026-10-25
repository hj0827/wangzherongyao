extends RefCounted
## 技能图标：项目里没有图标素材，所以按「技能族」矢量画。
##
## 为什么不按技能逐个画：hero_defs 里有 17 种 kind，一张一张画既画不完，
## 玩家也记不住。MOBA 的做法是让同类技能有同一个「视觉语法」——
## 斩击是斜光、爆发是星爆、位移是箭头、防护是盾、射击是箭。
##
## 所有 shapes() 都是纯几何（坐标已按 center/radius 算好），
## 无头测试可以直接断言「图形有没有跑出圆环」。

## 图形半径 / 圆环半径。0.58 是肉眼能认出图形、又不会顶到描边的临界值。
const GLYPH_SCALE := 0.58
const BADGE_DISTANCE := 0.76
const BADGE_SCALE := 0.28

const FAMILIES := {
	"slash": "strike",
	"spin": "strike",
	"quake": "strike",
	"leap_slam": "strike",
	"burst": "burst",
	"line": "burst",
	"meteor_storm": "burst",
	"aoe_shot": "burst",
	"arrow_barrage": "burst",
	"slow": "ward",
	"shield": "ward",
	"taunt_aura": "ward",
	"dash": "move",
	"charge": "move",
	"haste": "move",
	"evade": "move",
	# 召唤师技能（闪现/疾跑）本质都是位移，复用疾风箭头的语法。
	"summoner": "move",
	"arrow": "shot",
	# 普攻键专用：一把剑。它不能用 `slash`（strike 族）—— 那族画的是 45° 的
	# 平行四边形，放大到攻击键的尺寸之后是把整个圆糊成一块褐色方块，
	# 和「技能族语法」里的小图标完全不是一回事。
	"attack": "blade",
}

static func family(kind: String) -> String:
	return str(FAMILIES.get(kind, "strike"))

## 返回画笔指令列表，每项是 {type: "poly"|"line", ...}。
## 不直接画：调用方（SkillButton）才知道该用什么颜色、要不要置灰。
static func shapes(kind: String, center: Vector2, radius: float) -> Array:
	var g := radius * GLYPH_SCALE
	match family(kind):
		"burst":
			return [
				{"type": "poly", "points": _star(center, g), "closed": true},
				# 中心补一个小菱形：35px 下纯星形中心是空的，读起来像「裂开的图形」。
				{"type": "poly", "points": _diamond(center, g * 0.30), "closed": false, "width": 2.0},
			]
		"move":
			return [
				{"type": "poly", "points": _chevron(center, g, 0.58, 0.60, -0.34, 0.0), "closed": false, "width": 3.2},
				{"type": "poly", "points": _chevron(center, g, 0.30, 0.50, 0.10, 0.0), "closed": false, "width": 2.6},
			]
		"ward":
			return [
				{"type": "poly", "points": _shield(center, g), "closed": true},
				{"type": "line", "a": center + Vector2(-0.26, -0.14) * g, "b": center + Vector2(0.26, -0.14) * g, "width": 2.2},
				{"type": "line", "a": center + Vector2(0.0, 0.10) * g, "b": center + Vector2(0.0, 0.42) * g, "width": 2.2},
			]
		"shot":
			return [
				{"type": "line", "a": center + Vector2(-0.78, 0.78) * g, "b": center + Vector2(0.46, -0.46) * g, "width": 2.8},
				{"type": "poly", "points": PackedVector2Array([
					center + Vector2(0.76, -0.76) * g,
					center + Vector2(0.24, -0.50) * g,
					center + Vector2(0.50, -0.24) * g,
				]), "closed": true},
				{"type": "line", "a": center + Vector2(-0.82, 0.42) * g, "b": center + Vector2(-0.42, 0.82) * g, "width": 2.4},
			]
		"blade":
			# 一把竖着的剑：剑尖朝上、护手横穿、剑柄在下。
			# 它是攻击键唯一的图形，要在 130px 的圆里一眼读成「刀剑」，
			# 所以只保留三段剪影（剑身 / 护手 / 剑柄），不加装饰。
			return [
				{"type": "poly", "points": PackedVector2Array([
					center + Vector2(0.0, -0.98) * g,
					center + Vector2(0.19, -0.58) * g,
					center + Vector2(0.19, 0.10) * g,
					center + Vector2(-0.19, 0.10) * g,
					center + Vector2(-0.19, -0.58) * g,
				]), "closed": true},
				{"type": "line", "a": center + Vector2(-0.46, 0.20) * g, "b": center + Vector2(0.46, 0.20) * g, "width": 4.0},
				{"type": "line", "a": center + Vector2(0.0, 0.20) * g, "b": center + Vector2(0.0, 0.66) * g, "width": 5.0},
				{"type": "line", "a": center + Vector2(-0.15, 0.72) * g, "b": center + Vector2(0.15, 0.72) * g, "width": 4.0},
			]
	# strike：一道 45° 的刀光，外加两条速度线
	return [
		{"type": "poly", "points": PackedVector2Array([
			center + Vector2(-0.72, -0.34) * g,
			center + Vector2(-0.34, -0.72) * g,
			center + Vector2(0.72, 0.34) * g,
			center + Vector2(0.34, 0.72) * g,
		]), "closed": true},
		{"type": "line", "a": center + Vector2(-0.86, 0.12) * g, "b": center + Vector2(-0.46, 0.52) * g, "width": 2.4},
		{"type": "line", "a": center + Vector2(-0.48, 0.86) * g, "b": center + Vector2(-0.18, 0.56) * g, "width": 1.8},
	]

## 键位字母的角标位置：右下角。放在圆环内会挡住图形，放在圆环外会跑出按钮。
static func badge_center(center: Vector2, radius: float) -> Vector2:
	return center + Vector2(0.7071, 0.7071) * radius * BADGE_DISTANCE

static func badge_radius(radius: float) -> float:
	return radius * BADGE_SCALE

static func _star(center: Vector2, g: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in 12:
		var angle := -PI * 0.5 + TAU * float(i) / 12.0
		var reach := 0.88 if i % 2 == 0 else 0.38
		points.append(center + Vector2(cos(angle), sin(angle)) * (reach * g))
	return points

static func _chevron(center: Vector2, g: float, span: float, reach: float, offset_x: float, offset_y: float) -> PackedVector2Array:
	var origin := center + Vector2(offset_x, offset_y) * g
	return PackedVector2Array([
		origin + Vector2(-span, -reach) * g,
		origin + Vector2(span * 0.42, 0.0) * g,
		origin + Vector2(-span, reach) * g,
	])

static func _diamond(center: Vector2, r: float) -> PackedVector2Array:
	return PackedVector2Array([
		center + Vector2(0.0, -r),
		center + Vector2(r, 0.0),
		center + Vector2(0.0, r),
		center + Vector2(-r, 0.0),
		center + Vector2(0.0, -r),
	])

static func _shield(center: Vector2, g: float) -> PackedVector2Array:
	return PackedVector2Array([
		center + Vector2(0.0, -0.88) * g,
		center + Vector2(0.62, -0.46) * g,
		center + Vector2(0.62, 0.12) * g,
		center + Vector2(0.0, 0.90) * g,
		center + Vector2(-0.62, 0.12) * g,
		center + Vector2(-0.62, -0.46) * g,
	])

## 把 shapes() 的指令画到任意 CanvasItem 上。
static func paint(canvas: CanvasItem, kind: String, center: Vector2, radius: float, color: Color) -> void:
	for shape in shapes(kind, center, radius):
		match str(shape.get("type", "")):
			"poly":
				var points: PackedVector2Array = shape.get("points", PackedVector2Array())
				if points.size() < 2:
					continue
				if bool(shape.get("closed", true)):
					canvas.draw_colored_polygon(points, color)
				else:
					var width := float(shape.get("width", 3.0))
					canvas.draw_polyline(points, color, width, true)
			"line":
				canvas.draw_line(shape.get("a", Vector2.ZERO), shape.get("b", Vector2.ZERO), color, float(shape.get("width", 2.0)), true)
