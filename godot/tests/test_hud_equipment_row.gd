extends "res://tests/test_base.gd"

# 英雄面板装备格（P0 视觉升级）。
#
# 旧版状态卡只有头像/血蓝/KDA/金币，看不出出了什么装。
# 现在底部有 6 个装备槽，图标复用商店的 256² 资源，尺寸缩到 16/20px。

const MatchSim = preload("res://sim/match_sim.gd")
const GameHUD = preload("res://scripts/ui/game_hud.gd")
const HudLayout = preload("res://scripts/ui/hud_layout.gd")

func _sim() -> MatchSim:
	return MatchSim.new({"mode": "duel", "humans": [{"id": "p1", "team": "blue", "hero_type": "blade"}], "bot_fill": false})

func _hud(sim: MatchSim) -> Control:
	var hud: Control = GameHUD.new()
	hud.setup("p1", "blue", "blade", "苍刃", false, false)
	hud._ready()
	hud.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	hud.size = Vector2(1600.0, 900.0)
	hud._apply_layout()
	hud.update_snapshot(sim.snapshot())
	return hud

func test_six_equipment_slots_exist() -> void:
	var sim := _sim()
	var hud := _hud(sim)
	eq(hud._equip_icons.size(), 6, "英雄面板必须有 6 个装备槽")
	check(HudLayout.HERO_H >= 152.0, "状态卡高度要容得下装备行（实测 %s）" % HudLayout.HERO_H)
	hud.free()

func test_bought_items_show_icons_and_empty_slots_stay_blank() -> void:
	var sim := _sim()
	var hero: Dictionary = sim.get_hero_by_player("p1")
	hero["inventory"] = ["boots", "iron_sword"]
	hero["gold"] = 1000
	var hud := _hud(sim)
	check(hud._equip_icons[0].texture != null, "第一件装备要有图标")
	check(hud._equip_icons[1].texture != null, "第二件装备要有图标")
	check(hud._equip_icons[2].texture == null, "空槽不能显示上一件装备的图标")
	hud.free()

func test_inventory_change_updates_icons() -> void:
	var sim := _sim()
	var hero: Dictionary = sim.get_hero_by_player("p1")
	hero["inventory"] = ["boots"]
	var hud := _hud(sim)
	check(hud._equip_icons[0].texture != null, "初始装备有图标")
	hero["inventory"] = []
	hud.update_snapshot(sim.snapshot())
	check(hud._equip_icons[0].texture == null, "卖光后图标要清掉")
	hud.free()
