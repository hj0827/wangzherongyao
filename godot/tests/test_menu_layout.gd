extends "res://tests/test_base.gd"

# 主菜单「战场选择」分组的回归守卫。
#
# 起因：原来四个按钮一模一样重（1V1 / 5V5 混排在同一条队列里），玩家第一眼不知道
# 该点哪个 —— 有「主推」和「没主推」，在体感上是两种游戏。
#
# 改版把按钮拆成「单机试炼 / 联机对战」两组，并且只推一个入口。这里守的是**决策**，
# 不是像素：
#
#   · 分组必须真的分开了，且顺序稳定（单机在前 —— 玩家不需要先有对手才能玩）
#   · 有且只有一个主推，且必须是「点下去立刻能开局」的单机模式
#   · 主推不许藏在第二组里
#   · 四个入口一个都不能少（重构最容易悄悄丢掉一个模式）
#   · 标签必须和模式对得上（duel 配 5V5 这种复制粘贴错误，屏幕上不会报错）

const MenuLayout = preload("res://scripts/ui/menu_layout.gd")

func test_entries_cover_every_mode_and_connection_combination() -> void:
	var seen := {}
	for entry in MenuLayout.entries():
		var key := "%s/%s" % [entry.get("mode"), str(entry.get("online"))]
		check(not seen.has(key), "同一个模式+联机组合出现了两次：%s" % key)
		seen[key] = true
	eq(seen.size(), 4, "四个入口必须都在：单机1V1 / 单机5V5 / 联机1V1 / 联机5V5")
	for key in ["duel/false", "team/false", "duel/true", "team/true"]:
		check(seen.has(key), "缺少入口：%s" % key)

func test_groups_are_split_and_offline_comes_first() -> void:
	var groups := MenuLayout.groups()
	eq(groups.size(), 2, "按钮必须分成两组：单机 / 联机")
	eq((groups[0] as Dictionary).get("key"), "solo", "第一组必须是单机（新玩家不需要先找对手）")
	eq((groups[1] as Dictionary).get("key"), "online", "第二组必须是联机")
	for index in groups.size():
		var group: Dictionary = groups[index]
		check(not str(group.get("label", "")).is_empty(), "第 %d 组缺少中文组名" % index)
		check(not str(group.get("label_en", "")).is_empty(), "第 %d 组缺少英文小标" % index)
		var entries: Array = group.get("entries", [])
		eq(entries.size(), 2, "第 %d 组必须正好两个入口" % index)
		for entry in entries:
			eq(bool((entry as Dictionary).get("online")), index == 1,
				"入口 %s 被放进了错误的组" % str((entry as Dictionary).get("key")))

func test_exactly_one_primary_and_it_is_offline_duel() -> void:
	var primaries: Array = []
	for entry in MenuLayout.entries():
		if bool((entry as Dictionary).get("primary")):
			primaries.append(entry)
	eq(primaries.size(), 1, "有且只有一个主推入口，多了就等于没有主推")
	var primary: Dictionary = primaries[0]
	eq(primary.get("mode"), "duel", "主推必须是能单人开局的 1V1")
	eq(bool(primary.get("online")), false, "主推不能是联机模式（没有对手时按钮点了没反应）")
	# 主推不许藏在第二组里 —— 藏在里面的话，视线仍然从第一组开始扫，等于白推。
	eq(primary.get("group"), "solo", "主推必须挂在第一组上")

func test_tags_match_their_modes() -> void:
	# 复制粘贴写错标签时，屏幕上只有「双人联机 · 5 V 5」这种自相矛盾，不报错。
	for entry in MenuLayout.entries():
		var tag: String = MenuLayout.tag_for(str(entry.get("mode")))
		check(not tag.is_empty(), "模式 %s 没有对应标签" % str(entry.get("mode")))
		check(str(entry.get("tag")) == tag,
			"入口 %s 的标签写成了 %s，应该是 %s" % [str(entry.get("key")), str(entry.get("tag")), tag])

func test_emphasis_makes_the_primary_stand_out() -> void:
	var primary: Dictionary = MenuLayout.primary()
	near(MenuLayout.emphasis(primary), 1.0, 0.001, "主推的强调等级必须是最高的 1.0")
	for entry in MenuLayout.entries():
		if entry == primary:
			continue
		var value: float = MenuLayout.emphasis(entry)
		lt(value, 0.99, "非主推入口不能和主推一样重：%s" % str(entry.get("key")))
		gt(value, 0.0, "非主推入口也要有基本的可读强调：%s" % str(entry.get("key")))

func test_button_label_keeps_the_mode_tag() -> void:
	# 按钮只有一个 text 字段，名称和标签必须一起拼进去 —— 少了标签，
	# 「双人联机」和「五人联机」在按钮上的区别就只剩四个字。
	var primary: Dictionary = MenuLayout.primary()
	var label: String = MenuLayout.label(primary)
	check(label.contains(str(primary.get("text"))), "按钮文字必须包含入口名称")
	check(label.contains(str(primary.get("tag"))), "按钮文字必须包含模式标签")
	for entry in MenuLayout.entries():
		check(not str(entry.get("key")).is_empty(), "每个入口都要有稳定的 key（用于连接与测试定位）")
		check(not str(entry.get("text")).is_empty(), "每个入口都要有名称")
