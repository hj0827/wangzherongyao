extends Control
class_name RecallBar

## 回城进度条：屏幕底部正中一条细带（手游的做法，参考王者的回城进度）。
##
## 为什么必须单独一条：手机端的状态卡已经收进左上角，原来写在「角色」那一行里的
## 「[回城中...]」在 234px 宽的柱子里放不下，被藏掉了。而回城是 4 秒引导，
## 移动 / 施法 / 受击都会打断 —— 玩家必须看得见还剩多久，否则会以为按键没反应。

const GameTheme = preload("res://scripts/ui/game_theme.gd")

const BAR_BG := Color(0.02, 0.035, 0.05, 0.86)
const BAR_TRACK := Color(0.0, 0.0, 0.0, 0.5)
const BAR_FILL := Color(0.32, 0.68, 1.0)
const BAR_EDGE := Color(0.55, 0.44, 0.24, 0.6)
const BAR_INSET := 3.0

var remaining := 0.0
var total := 0.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false

## 每帧从快照里喂：recall_timer / recall_total。
func set_state(new_remaining: float, new_total: float) -> void:
	remaining = maxf(new_remaining, 0.0)
	total = maxf(new_total, 0.0)
	visible = is_active()
	queue_redraw()

## 只有「正在引导」才算激活。传 0/0 表示没在回城 —— 整条隐藏，
## 而不是留一条空槽在屏幕底部（玩家会以为那是某种可交互的东西）。
func is_active() -> bool:
	return total > 0.001 and remaining > 0.001

## 已完成比例。0 = 刚起手，1 = 即将落点。
func fill_fraction() -> float:
	if total <= 0.001:
		return 0.0
	return clampf(1.0 - remaining / total, 0.0, 1.0)

static func format_text(value: float) -> String:
	return "回城中  %.1f" % maxf(value, 0.0)

func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, size)
	draw_rect(rect, BAR_BG, true)
	var inner := Rect2(
		Vector2(BAR_INSET, BAR_INSET),
		Vector2(maxf(size.x - BAR_INSET * 2.0, 0.0), maxf(size.y - BAR_INSET * 2.0, 0.0))
	)
	draw_rect(inner, BAR_TRACK, true)
	var fraction := fill_fraction()
	var fill_width := inner.size.x * fraction
	if fill_width > 0.0:
		draw_rect(Rect2(inner.position, Vector2(fill_width, inner.size.y)), BAR_FILL, true)
	draw_rect(rect, BAR_EDGE, false, 1.5)
	var text := format_text(remaining)
	var pos := Vector2(0.0, size.y * 0.5 + 5.0)
	# 先描一圈深色再压白字：填充条扫过文字时，纯白字在亮蓝上会糊。
	draw_string_outline(GameTheme.FONT_REGULAR, pos, text, HORIZONTAL_ALIGNMENT_CENTER, size.x, 14, 3, Color(0.0, 0.0, 0.0, 0.9))
	draw_string(GameTheme.FONT_REGULAR, pos, text, HORIZONTAL_ALIGNMENT_CENTER, size.x, 14, GameTheme.TEXT)
