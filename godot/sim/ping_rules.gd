extends RefCounted

# 快捷信号（验收 11.1）的唯一事实来源：协议白名单、模拟侧校验、HUD 文案与颜色都从这里取。
# 以前这类枚举容易三处各写一份，联机时客机收到一个协议层没拦的值就静默显示成空白。

const KINDS := ["missing", "help", "attack", "retreat"]

static func is_valid(kind: String) -> bool:
	return KINDS.has(kind)

static func label(kind: String) -> String:
	match kind:
		"missing":
			return "敌人消失"
		"help":
			return "请求支援"
		"attack":
			return "进攻"
		"retreat":
			return "撤退"
	return "信号"

# 小地图上只放一个字：206px 的图里 12px 字号再塞三个字会糊成一块。
static func glyph(kind: String) -> String:
	match kind:
		"missing":
			return "?"
		"help":
			return "!"
		"attack":
			return "攻"
		"retreat":
			return "退"
	return "!"

static func color(kind: String) -> Color:
	match kind:
		"missing":
			return Color(0.98, 0.62, 0.22)
		"help":
			return Color(0.42, 0.78, 1.0)
		"attack":
			return Color(0.98, 0.38, 0.32)
		"retreat":
			return Color(0.44, 0.90, 0.56)
	return Color(0.92, 0.82, 0.5)

static func feed_text(kind: String, sender: String) -> String:
	var who := sender if sender != "" else "队友"
	return "%s：%s" % [who, label(kind)]
