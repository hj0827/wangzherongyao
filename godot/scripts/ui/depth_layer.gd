extends Control
## 卡片内部的装饰层
## 本身只负责铺满整张卡片，但必须把内容的最小尺寸往上传递，
## 否则 PanelContainer 会以为卡片没有内容，把高度塌成 0。

var content: Control

func _get_minimum_size() -> Vector2:
	if content == null:
		return Vector2.ZERO
	return content.get_combined_minimum_size()
