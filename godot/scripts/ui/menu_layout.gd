extends RefCounted
class_name MenuLayout

## 主菜单「选择战场」的数据层。
##
## 为什么要把四个按钮的数据从 main.gd 里搬出来：改版的核心决策是
## **「四个一样重」→「只推一个入口」**，而这个决策在节点树里是看不出来的 ——
## 屏幕上都叫 Button，谁主谁次全靠样式，样式又救不了「没有主次」这件事。
##
## 这里只放「结构 + 意图」，不放像素：分组、顺序、谁主推。样式在 main.gd 里，
## 因为它要用 GameTheme 和 hover 状态。
##
## 两条被测试钉住的决策：
##   1. 单机在前。新玩家不需要先找到对手，才能玩自己的游戏。
##   2. 主推必须是**单机** 1V1。主推一个联机模式，等于让第一次打开的人先卡在找房间里。

const MODE_DUEL := "duel"
const MODE_TEAM := "team"

## 模式 → 按钮上的对局标签。只在这一处定义：复制粘贴写错时，
## 屏幕上只会出现「双人联机 · 5 V 5」这种自相矛盾，不会报错。
const MODE_TAGS := {
	MODE_DUEL: "1 V 1",
	MODE_TEAM: "5 V 5",
}

static func tag_for(mode: String) -> String:
	return str(MODE_TAGS.get(mode, ""))

## 分组：单机 → 联机。entries 里的 group 字段用于校验「主推没被藏进第二组」。
static func groups() -> Array:
	return [
		{
			"key": "solo",
			"label": "单 机 试 炼",
			"label_en": "LOCAL",
			"entries": [
				{
					"key": "single",
					"text": "单人试炼",
					"tag": tag_for(MODE_DUEL),
					"mode": MODE_DUEL,
					"online": false,
					"primary": true,
					"group": "solo",
				},
				{
					"key": "ai_team",
					"text": "人机军团",
					"tag": tag_for(MODE_TEAM),
					"mode": MODE_TEAM,
					"online": false,
					"primary": false,
					"group": "solo",
				},
			],
		},
		{
			"key": "online",
			"label": "联 机 对 战",
			"label_en": "ONLINE",
			"entries": [
				{
					"key": "duo",
					"text": "双人联机",
					"tag": tag_for(MODE_DUEL),
					"mode": MODE_DUEL,
					"online": true,
					"primary": false,
					"group": "online",
				},
				{
					"key": "squad",
					"text": "五人联机",
					"tag": tag_for(MODE_TEAM),
					"mode": MODE_TEAM,
					"online": true,
					"primary": false,
					"group": "online",
				},
			],
		},
	]

## 摊平后的四个入口（按屏幕上出现的顺序）。
static func entries() -> Array:
	var result: Array = []
	for group in groups():
		for entry in (group as Dictionary).get("entries", []):
			result.append(entry)
	return result

static func primary() -> Dictionary:
	for entry in entries():
		if bool((entry as Dictionary).get("primary")):
			return entry
	return {}

## 强调等级：1.0 = 主推，其余 0.55。渲染端用它决定字号 / 金边 / 竖条，
## 而不是在一堆 if 里写死「这个按钮特殊一点」。
static func emphasis(entry: Dictionary) -> float:
	return 1.0 if bool(entry.get("primary")) else 0.55

## 按钮上那一行字。标签必须一起拼进去 —— 只有「双人联机」四个字时，
## 1V1 和 5V5 在按钮上没有任何区别。
static func label(entry: Dictionary) -> String:
	return "%s    ·    %s" % [str(entry.get("text")), str(entry.get("tag"))]
