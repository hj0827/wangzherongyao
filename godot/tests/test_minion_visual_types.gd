extends "res://tests/test_base.gd"

# 小兵四类型外观：近战 / 远程 / 炮车 / 超级兵。
# 旧版四种类型共用一套骷髅模型，兵线看起来永远是一排同款；
# 现在至少靠配件 + 体型让四种类型在 21m 俯视下能分开。

const UnitVisual = preload("res://scripts/game/unit_visual.gd")
const ModelUtils = preload("res://scripts/game/model_utils.gd")

func _width(view: UnitVisual) -> float:
	return ModelUtils.relative_aabb(view.model_root).size.x

func test_each_minion_type_shows_its_own_kit() -> void:
	for minion_type in ["melee", "ranged", "cannon", "super"]:
		var view := UnitVisual.new()
		view.setup("minion", "blue", minion_type, "", false, "blue")
		check(view._minion_props.has(minion_type), "缺少 %s 的配件槽" % minion_type)
		for key in view._minion_props:
			var node: Node3D = view._minion_props[key]
			if node == null:
				continue
			eq(node.visible, key == minion_type, "%s 类型只显示自己的配件（%s）" % [minion_type, key])
		view.free()

func test_cannon_and_super_are_bulkier_than_melee() -> void:
	var melee := UnitVisual.new()
	melee.setup("minion", "blue", "melee", "", false, "blue")
	var cannon := UnitVisual.new()
	cannon.setup("minion", "blue", "cannon", "", false, "blue")
	var super_minion := UnitVisual.new()
	super_minion.setup("minion", "blue", "super", "", false, "blue")
	gt(_width(cannon), _width(melee), "炮车要比近战兵宽")
	gt(_width(super_minion), _width(cannon), "超级兵要比炮车更大")
	melee.free()
	cannon.free()
	super_minion.free()

func test_pool_reset_switches_the_kit_without_rebuilding() -> void:
	var view := UnitVisual.new()
	view.setup("minion", "blue", "melee", "", false, "blue")
	var ranged: Node3D = view._minion_props["ranged"]
	var cannon: Node3D = view._minion_props["cannon"]
	check(not ranged.visible and not cannon.visible, "近战兵初始不显示配件")
	view.reset_minion("red", Vector3(3.0, 0.0, 4.0), "cannon")
	check(cannon.visible, "池化复用切到炮车时要显示炮管")
	check(not ranged.visible, "切换后旧配件要隐藏")
	view.reset_minion("blue", Vector3.ZERO, "ranged")
	check(ranged.visible and not cannon.visible, "再切回远程兵要正确切换")
	view.free()
