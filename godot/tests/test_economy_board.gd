extends "res://tests/test_base.gd"

# 双方经济面板的数据层：快照必须带一份「两队全员的公开账本」。
#
# 两条不变量最容易静默失效：
#  1. 账本是 snapshot 级字段，Vision.filter_snapshot 会 duplicate 整份快照，
#     所以必须在过滤后仍然存在（敌方英雄不在视野里也要能看到他的经济）。
#  2. 联机走 NetProtocol.sanitize_snapshot 的字段白名单，不登记 board 就
#     只在单机可见——客机计分板一片空白，且不报错。
#
# 注意：这里所有取数一律走 .get() + 显式 check。直接写 board.blue[0].gold
# 在字段缺失时会抛运行时错误，被测试框架当成 PASS ——假绿比红更危险。

const HeroDefs = preload("res://sim/hero_defs.gd")
const MatchSim = preload("res://sim/match_sim.gd")
const ItemShop = preload("res://sim/item_shop.gd")
const EconomySystem = preload("res://sim/economy_system.gd")
const Vision = preload("res://sim/map/vision.gd")
const NetProtocol = preload("res://net/net_protocol.gd")
const GameHUD = preload("res://scripts/ui/game_hud.gd")

const ROW_FIELDS := [
	"id", "owner_id", "name", "team", "hero_type", "role", "lane",
	"level", "kills", "deaths", "cs", "gold", "net_worth",
	"alive", "respawn_timer", "inventory", "controller",
]

func _duel() -> MatchSim:
	return MatchSim.new({
		"mode": "duel",
		"humans": [
			{"id": "p1", "team": "blue", "hero_type": "blade"},
			{"id": "p2", "team": "red", "hero_type": "tank"},
		],
		"bot_fill": false,
	})

func _board(sim: MatchSim) -> Dictionary:
	var shot: Dictionary = sim.snapshot()
	if not shot.has("board"):
		check(false, "snapshot must expose a board")
		return {}
	var board: Variant = shot.get("board", null)
	if not (board is Dictionary):
		check(false, "board must be a dictionary")
		return {}
	return board as Dictionary

# ---------------------------------------------------------------- 结构

func test_board_lists_every_hero_on_both_teams() -> void:
	var board := _board(_duel())
	if board.is_empty():
		return
	eq((board.get("blue", []) as Array).size(), 1, "duel: one blue row")
	eq((board.get("red", []) as Array).size(), 1, "duel: one red row")

	var team_sim := MatchSim.new({
		"mode": "team",
		"humans": [{"id": "p1", "team": "blue", "hero_type": "archer"}],
		"bot_fill": true,
	})
	var team_board := _board(team_sim)
	if team_board.is_empty():
		return
	eq((team_board.get("blue", []) as Array).size(), 5, "team: five blue rows")
	eq((team_board.get("red", []) as Array).size(), 5, "team: five red rows")

func test_every_row_carries_the_full_stat_line() -> void:
	var row := _row(_duel(), 1)
	if row.is_empty():
		return
	for field in ROW_FIELDS:
		check(row.has(field), "board row missing field '%s'" % field)
	eq(str(row.get("team", "")), "blue", "first hero belongs to blue")
	eq(str(row.get("hero_type", "")), "blade", "first hero is the blade")
	eq(int(row.get("level", -1)), 1, "everyone starts at level 1")
	eq(int(row.get("kills", -1)), 0, "no kills at spawn")
	eq(int(row.get("gold", -1)), 0, "no gold at spawn")
	eq((row.get("inventory", [null]) as Array).size(), 0, "inventory starts empty")

func test_board_rows_expose_owner_ids() -> void:
	# 谁是「我」由 UI 侧决定（sim 不知道本地玩家是谁），所以账本必须带 owner_id。
	var board := _board(_duel())
	if board.is_empty():
		return
	var owners := []
	for side in ["blue", "red"]:
		for row in board.get(side, []):
			owners.append(str(row.get("owner_id", "")))
			eq(str(row.get("team", "")), side, "row team matches the bucket it sits in")
	eq(owners.size(), 2, "duel has two owners")
	check(owners.has("p1"), "blue owner id is preserved")
	check(owners.has("p2"), "red owner id is preserved")

# ---------------------------------------------------------------- 经济口径

func test_net_worth_counts_gold_plus_item_value() -> void:
	var sim := _duel()
	var hero: Dictionary = sim.get_hero_by_player("p1")
	var hero_id := int(hero.id)

	hero["gold"] = 250
	var row := _row(sim, hero_id)
	if row.is_empty():
		return
	eq(int(row.get("net_worth", -1)), 250, "bare hero net worth equals gold")

	# 买下 250 的装备：金币清零，但总经济不变（钱变成了装备）
	check(ItemShop.buy_item(hero, "iron_sword"), "should afford the iron sword")
	eq(int(hero.gold), 0, "gold spent")
	row = _row(sim, hero_id)
	eq(int(row.get("gold", -1)), 0, "board shows the spent gold")
	eq(int(row.get("net_worth", -1)), 250, "net worth is unchanged by buying — gold turned into an item")

	hero["gold"] = 400
	row = _row(sim, hero_id)
	eq(int(row.get("net_worth", -1)), 650, "net worth = gold + item value")

func test_selling_lowers_net_worth_by_the_refund_gap() -> void:
	var sim := _duel()
	var hero: Dictionary = sim.get_hero_by_player("p1")
	hero["gold"] = 250
	ItemShop.buy_item(hero, "iron_sword")
	var before := int(_row(sim, int(hero.id)).get("net_worth", -1))
	ItemShop.sell_item(hero, 0)
	var after := int(_row(sim, int(hero.id)).get("net_worth", -1))
	# 60% 返还：250 -> 150，净损失 100。
	eq(before, 250, "before selling")
	eq(after, 150, "selling at 60% refund loses 40% of the item value")

func test_team_net_worth_is_the_sum_of_its_rows() -> void:
	var sim := _duel()
	sim.get_hero_by_player("p1")["gold"] = 1200
	var board := _board(sim)
	if board.is_empty():
		return
	var summed := 0
	for row in board.get("blue", []):
		summed += int(row.get("net_worth", 0))
	var totals: Dictionary = board.get("net_worth", {})
	eq(int(totals.get("blue", -1)), summed, "blue total equals the sum of its rows")
	eq(int(totals.get("blue", -1)), 1200, "single hero carries the whole team economy")
	eq(int(totals.get("red", -1)), 0, "red team is broke at spawn")

# ---------------------------------------------------------------- 补刀

func test_cs_only_counts_last_hits() -> void:
	var sim := _duel()
	var hero: Dictionary = sim.get_hero_by_player("p1")
	eq(int(hero.get("cs", -1)), 0, "cs starts at zero")

	EconomySystem.award_minion_kill(hero, true)
	eq(int(hero.get("cs", -1)), 1, "a last hit adds one cs")

	EconomySystem.award_minion_kill(hero, false)
	eq(int(hero.get("cs", -1)), 1, "an assist does not add cs")

	var row := _row(sim, int(hero.id))
	if row.is_empty():
		return
	eq(int(row.get("cs", -1)), 1, "board mirrors the cs counter")

# ---------------------------------------------------------------- 两条传输通道

func test_vision_filter_keeps_the_enemy_board() -> void:
	var sim := _duel()
	sim.tick(0.05)

	var full: Dictionary = sim.snapshot()
	var filtered: Dictionary = Vision.filter_snapshot(full, "blue")
	check(filtered.has("board"), "filtered snapshot must still carry the board")
	var board: Dictionary = filtered.get("board", {})
	eq((board.get("red", []) as Array).size(), 1, "enemy hero stays on the scoreboard even when unseen")
	eq((board.get("blue", []) as Array).size(), 1, "own team stays on the scoreboard")

func test_net_sanitizer_keeps_the_board() -> void:
	var sim := _duel()
	sim.get_hero_by_player("p1")["gold"] = 640
	var result := NetProtocol.sanitize_snapshot(sim.snapshot())
	check(bool(result.get("ok", false)), "snapshot should sanitize")
	var shot: Dictionary = result.get("snapshot", {})
	check(shot.has("board"), "net sanitizer must whitelist the board (else clients see an empty scoreboard)")
	var board: Dictionary = shot.get("board", {})
	eq((board.get("blue", []) as Array).size(), 1, "blue rows survive the wire")
	eq((board.get("red", []) as Array).size(), 1, "red rows survive the wire")
	eq(int((board.get("net_worth", {}) as Dictionary).get("blue", -1)), 640, "economy survives the wire")

# ---------------------------------------------------------------- HUD 接线

func test_hud_exposes_the_scoreboard() -> void:
	var hud_source := FileAccess.get_file_as_string("res://scripts/ui/game_hud.gd")
	check(hud_source.contains("_scoreboard"), "the HUD must own a scoreboard overlay")
	check(hud_source.contains("KEY_TAB"), "TAB must toggle the scoreboard")
	check(hud_source.contains("\"board\""), "the HUD must read the board field")
	check(hud_source.contains("net_worth"), "the HUD must show net worth, not just gold")

# ---------------------------------------------------------------- 真实节点

func test_real_hud_populates_the_scoreboard() -> void:
	# 前面都是数据层。这条把 HUD 真建出来，确认它把 board 渲染到了节点上——
	# 「字段在快照里」和「玩家看得见」是两件事。
	var sim := _duel()
	var hero: Dictionary = sim.get_hero_by_player("p1")
	hero["gold"] = 1500
	check(ItemShop.buy_item(hero, "boots"), "afford boots")

	var hud: Control = GameHUD.new()
	hud.setup("p1", "blue", "blade", "苍刃", false, false)
	hud._ready()
	hud.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	hud.size = Vector2(1600.0, 900.0)
	hud._apply_layout()

	var shot: Dictionary = sim.snapshot()
	hud.update_snapshot(shot)
	check(hud._scoreboard != null, "HUD must build a scoreboard overlay")
	check(hud._econ_label != null, "HUD must build the economy strip")
	check(not hud._scoreboard.is_open(), "the scoreboard starts closed")
	check(hud._econ_label.text.contains("领先"), "econ strip calls out who is ahead: %s" % hud._econ_label.text)
	check(hud._econ_label.text.contains("1.5k"), "econ strip shows the lead in k: %s" % hud._econ_label.text)
	# 副行必须给两队总额。只写差值的话，落后方为 0 时会和差值撞成同一个数字
	# （"领先 1.5k · 1.5k"），读起来像重复，所以总额要走独立一行。
	# 用 get() 取属性：属性不存在时属性访问会抛运行时错误并被当成 PASS。
	var sub: Variant = hud.get("_econ_sub")
	check(sub != null, "HUD must build the economy total line")
	if sub != null:
		var sub_text := str((sub as Label).text)
		check(sub_text.contains("蓝 1.5k"), "econ strip shows the blue total: %s" % sub_text)
		check(sub_text.contains("红 0"), "econ strip shows the red total: %s" % sub_text)

	# 打开后必须真的填出双方各一人（duel），多出来的行隐藏而不是留着空壳。
	hud._scoreboard.open()
	hud.update_snapshot(shot)
	var blue_rows: VBoxContainer = hud._scoreboard._blue_rows
	var red_rows: VBoxContainer = hud._scoreboard._red_rows
	eq(blue_rows.get_child_count(), 5, "one prebuilt row per slot")
	check(blue_rows.get_child(0).visible, "blue hero occupies row 0")
	check(not blue_rows.get_child(1).visible, "unused blue rows are hidden")
	check(red_rows.get_child(0).visible, "red hero occupies row 0")
	check(not red_rows.get_child(1).visible, "unused red rows are hidden")

	var name_label: Label = blue_rows.get_child(0).get_meta("name")
	check(name_label.text.contains("苍刃"), "scoreboard names the hero: %s" % name_label.text)
	check(name_label.text.contains("Lv.1"), "scoreboard shows the level: %s" % name_label.text)
	var econ_label: Label = blue_rows.get_child(0).get_meta("econ")
	eq(econ_label.text, "1.5k", "row economy uses net worth, not raw gold")
	# 已购的靴子必须占一格装备，而不是空着
	var slots: Array = blue_rows.get_child(0).get_meta("slots")
	check((slots[0].cell as Control).visible, "the bought item fills the first equip slot")
	check(not (slots[1].cell as Control).visible, "unused equip slots are hidden")

	hud._scoreboard.close()
	check(not hud._scoreboard.is_open(), "closing works")
	hud.free()

func _row(sim: MatchSim, hero_id: int) -> Dictionary:
	var board := _board(sim)
	for side in ["blue", "red"]:
		for row in board.get(side, []):
			if int(row.get("id", -1)) == hero_id:
				return row
	check(false, "board has no row for hero id %d" % hero_id)
	return {}
