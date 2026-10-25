extends "res://tests/test_base.gd"

# 经济面板：点顶部那条「红方领先 658」要能打开一张明细表，
# 每人一行给出「够做决策」的信息：经济 / 装备 / 等级 / KDA / 输出 / 承伤 / 推塔 / 攻防属性。
#
# 两条最容易静默失效的地方：
#  1. 统计字段只加在 sim 实体上、没进 _snapshot_board → UI 永远显示 0，不报错。
#  2. 进了 board 但没进 NetProtocol 的白名单 → 单机正常、客机全 0，也不报错。
# 所以这里同时钉「实体上有数」「快照里有数」「过网还在」三处。

const MatchSim = preload("res://sim/match_sim.gd")
const NetProtocol = preload("res://net/net_protocol.gd")
const ItemShop = preload("res://sim/item_shop.gd")
const GameHUD = preload("res://scripts/ui/game_hud.gd")

# 面板一行要有的字段（相对 board 行）。
const PANEL_FIELDS := [
	"assists",
	"damage_dealt",
	"damage_taken",
	"tower_kills",
	"attack_damage",
	"ability_power",
	"max_hp",
	"speed",
	"crit_rate",
	"item_value",
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

func _team() -> MatchSim:
	return MatchSim.new({
		"mode": "team",
		"humans": [
			{"id": "p1", "team": "blue", "hero_type": "blade"},
			{"id": "p2", "team": "blue", "hero_type": "mage"},
			{"id": "p3", "team": "red", "hero_type": "tank"},
		],
		"bot_fill": false,
	})

func _row(sim: MatchSim, hero_id: int) -> Dictionary:
	var board: Dictionary = sim.snapshot().get("board", {})
	for side in ["blue", "red"]:
		for row in board.get(side, []):
			if int(row.get("id", -1)) == hero_id:
				return row
	check(false, "board has no row for hero id %d" % hero_id)
	return {}

func _hero(sim: MatchSim, owner: String) -> Dictionary:
	return sim.get_hero_by_player(owner)

# ---------------------------------------------------------------- 数据层

func test_board_row_carries_every_panel_field() -> void:
	var sim := _duel()
	var row := _row(sim, int(_hero(sim, "p1").id))
	if row.is_empty():
		return
	for field in PANEL_FIELDS:
		check(row.has(field), "board row missing panel field '%s'" % field)
	# 开局：0 助攻 0 输出 0 承伤 0 推塔，但属性必须是英雄的真实初始值。
	eq(int(row.get("assists", -1)), 0, "no assists at spawn")
	eq(int(row.get("tower_kills", -1)), 0, "no tower kills at spawn")
	near(float(row.get("damage_dealt", -1.0)), 0.0, 0.001, "no damage at spawn")
	near(float(row.get("attack_damage", -1.0)), 78.0, 0.001, "blade attack damage")
	near(float(row.get("max_hp", -1.0)), 1320.0, 0.001, "blade max hp")
	gt(float(row.get("speed", 0.0)), 0.0, "move speed is exposed")

func test_buying_an_item_shows_up_in_the_attributes() -> void:
	# 面板要能回答「他出了什么装、攻击涨到多少」。装备加成必须体现在属性行里。
	var sim := _duel()
	var hero := _hero(sim, "p1")
	hero["gold"] = 250
	check(ItemShop.buy_item(hero, "iron_sword"), "afford the iron sword")
	var row := _row(sim, int(hero.id))
	near(float(row.get("attack_damage", 0.0)), 98.0, 0.001, "iron sword adds 20 attack")
	eq(int(row.get("item_value", -1)), 250, "item value is exposed for the panel")

func test_damage_dealt_and_taken_are_tracked_per_hero() -> void:
	var sim := _duel()
	var attacker := _hero(sim, "p1")
	var victim := _hero(sim, "p2")
	sim.apply_damage(int(victim.id), 120.0, int(attacker.id))
	var a_row := _row(sim, int(attacker.id))
	var v_row := _row(sim, int(victim.id))
	near(float(a_row.get("damage_dealt", 0.0)), 120.0, 0.001, "attacker output is counted")
	near(float(a_row.get("damage_taken", -1.0)), 0.0, 0.001, "attacker took nothing")
	near(float(v_row.get("damage_taken", 0.0)), 120.0, 0.001, "victim damage taken is counted")

func test_damage_absorbed_by_a_shield_still_counts_as_output() -> void:
	# 护盾吃掉的伤害也是实打实的输出，不能因为没掉血就从面板里消失。
	var sim := _duel()
	var attacker := _hero(sim, "p1")
	var victim := _hero(sim, "p2")
	victim["shield"] = 500.0
	sim.apply_damage(int(victim.id), 200.0, int(attacker.id))
	near(float(_row(sim, int(attacker.id)).get("damage_dealt", 0.0)), 200.0, 0.001, "shielded damage still counts")

func test_assist_goes_to_the_other_hero_who_dealt_damage() -> void:
	var sim := _team()
	var killer := _hero(sim, "p1")
	var helper := _hero(sim, "p2")
	var victim := _hero(sim, "p3")
	sim.apply_damage(int(victim.id), 300.0, int(helper.id))
	sim.apply_damage(int(victim.id), 999999.0, int(killer.id))
	eq(int(_row(sim, int(killer.id)).get("kills", -1)), 1, "killer gets the kill")
	eq(int(_row(sim, int(helper.id)).get("assists", -1)), 1, "helper gets an assist")
	eq(int(_row(sim, int(killer.id)).get("assists", -1)), 0, "the killer does not assist himself")
	eq(int(_row(sim, int(victim.id)).get("deaths", -1)), 1, "victim dies once")

func test_stale_damage_does_not_earn_an_assist() -> void:
	# 十分钟前蹭过一下就算助攻，面板会变得毫无参考价值。
	var sim := _team()
	var killer := _hero(sim, "p1")
	var helper := _hero(sim, "p2")
	var victim := _hero(sim, "p3")
	sim.apply_damage(int(victim.id), 100.0, int(helper.id))
	sim.state.time = float(sim.state.time) + 30.0
	sim.apply_damage(int(victim.id), 999999.0, int(killer.id))
	eq(int(_row(sim, int(helper.id)).get("assists", -1)), 0, "damage older than the assist window does not count")

func test_destroying_a_tower_credits_the_last_hitter() -> void:
	var sim := _duel()
	var hero := _hero(sim, "p1")
	var tower := {}
	for entity in sim.state.entities:
		if str(entity.type) == "tower" and str(entity.team) == "red":
			tower = entity
			break
	check(not tower.is_empty(), "red towers exist")
	if tower.is_empty():
		return
	sim.apply_damage(int(tower.id), 999999.0, int(hero.id))
	eq(int(_row(sim, int(hero.id)).get("tower_kills", -1)), 1, "the last hitter is credited with the tower")

func test_net_sanitizer_keeps_the_panel_fields() -> void:
	var sim := _duel()
	var hero := _hero(sim, "p1")
	sim.apply_damage(int(_hero(sim, "p2").id), 90.0, int(hero.id))
	var result := NetProtocol.sanitize_snapshot(sim.snapshot())
	check(bool(result.get("ok", false)), "snapshot should sanitize")
	var board: Dictionary = (result.get("snapshot", {}) as Dictionary).get("board", {})
	var rows: Array = board.get("blue", [])
	check(not rows.is_empty(), "blue rows survive the wire")
	if rows.is_empty():
		return
	for field in PANEL_FIELDS:
		check((rows[0] as Dictionary).has(field), "net whitelist drops panel field '%s'" % field)
	near(float((rows[0] as Dictionary).get("damage_dealt", 0.0)), 90.0, 0.001, "output survives the wire")

# ---------------------------------------------------------------- HUD 接线

func _hud(sim: MatchSim) -> Control:
	var hud: Control = GameHUD.new()
	hud.setup("p1", "blue", "blade", "苍刃", false, false)
	hud._ready()
	hud.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	hud.size = Vector2(1600.0, 900.0)
	hud._apply_layout()
	hud.update_snapshot(sim.snapshot())
	return hud

func test_clicking_the_economy_strip_opens_the_panel() -> void:
	var sim := _duel()
	var hud := _hud(sim)
	check(hud._scoreboard != null, "HUD owns the panel")
	check(not hud._scoreboard.is_open(), "panel starts closed")
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	hud._econ_panel.gui_input.emit(click)
	check(hud._scoreboard.is_open(), "clicking the economy strip opens the panel")
	# 再点一次收起：常驻的顶栏条不占视野，点开看完要能关掉。
	hud._econ_panel.gui_input.emit(click)
	check(not hud._scoreboard.is_open(), "clicking again closes it")
	hud.free()

func test_clicking_the_backdrop_closes_the_panel() -> void:
	var sim := _duel()
	var hud := _hud(sim)
	hud._scoreboard.open()
	check(hud._scoreboard.is_open(), "panel is open")
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	hud._scoreboard._root.gui_input.emit(click)
	check(not hud._scoreboard.is_open(), "clicking outside the panel closes it")
	hud.free()

func test_panel_row_shows_a_hero_avatar() -> void:
	# 一张脸比「战士」两个字认人快。头像是裁出来的（立绘 1024²，整张缩到 44px 看不见脸），
	# 所以这里钉「真的有纹理」，而不是「节点在」。
	var sim := _team()
	var hud := _hud(sim)
	hud._scoreboard.open()
	hud.update_snapshot(sim.snapshot())
	var rows: VBoxContainer = hud._scoreboard._blue_rows
	var row: Control = rows.get_child(0)
	var avatar: TextureRect = row.get_meta("avatar")
	check(avatar != null, "row must own an avatar node")
	if avatar != null:
		check(avatar.texture != null, "avatar must carry a texture")
		check(avatar.visible, "avatar is visible for a live hero")
	# 不同英雄必须是不同的脸，不能五个人共用一张。
	var second: Control = rows.get_child(1)
	var other: TextureRect = second.get_meta("avatar")
	if avatar != null and other != null:
		check(avatar.texture != other.texture, "different heroes use different avatars")
	hud.free()

func test_dead_hero_avatar_is_dimmed() -> void:
	var sim := _duel()
	var hero := _hero(sim, "p1")
	hero["alive"] = false
	hero["respawn_timer"] = 12.0
	var hud := _hud(sim)
	hud._scoreboard.open()
	hud.update_snapshot(sim.snapshot())
	var avatar: TextureRect = (hud._scoreboard._blue_rows.get_child(0) as Control).get_meta("avatar")
	check(avatar.modulate.r < 0.9, "dead hero avatar is dimmed: %s" % avatar.modulate)
	hud.free()

func test_panel_row_renders_economy_equipment_and_attributes() -> void:
	var sim := _duel()
	var hero := _hero(sim, "p1")
	hero["gold"] = 900
	check(ItemShop.buy_item(hero, "iron_sword"), "afford the iron sword")
	sim.apply_damage(int(_hero(sim, "p2").id), 150.0, int(hero.id))
	var hud := _hud(sim)
	hud._scoreboard.open()
	hud.update_snapshot(sim.snapshot())

	var rows: VBoxContainer = hud._scoreboard._blue_rows
	var row: Control = rows.get_child(0)
	check(row.visible, "the local hero occupies the first blue row")
	check(str((row.get_meta("econ") as Label).text).contains("900"), "row shows net worth (650 gold + 250 item): %s" % (row.get_meta("econ") as Label).text)
	check(str((row.get_meta("kda") as Label).text).contains("/"), "row shows K/D/A")
	# 属性行：攻击 / 生命 / 移速 必须出现在同一行里，玩家不用二次点开。
	var stats_label: Label = row.get_meta("stats")
	check(stats_label != null, "row must own an attribute line")
	if stats_label != null:
		check(stats_label.text.contains("攻击"), "attribute line names attack: %s" % stats_label.text)
		check(stats_label.text.contains("98"), "attribute line shows the buffed attack: %s" % stats_label.text)
		check(stats_label.text.contains("生命"), "attribute line names max hp: %s" % stats_label.text)
		check(stats_label.text.contains("输出"), "attribute line names damage dealt: %s" % stats_label.text)
	var slots: Array = row.get_meta("slots")
	check((slots[0].cell as Control).visible, "the bought item fills a slot")
	hud.free()

func test_panel_header_shows_gold_per_minute() -> void:
	# 王者经济面板之外，玩家真正用来判断局势的是「分均经济」。
	var sim := _duel()
	_hero(sim, "p1")["gold"] = 1200
	sim.state.time = 120.0
	var hud := _hud(sim)
	hud._scoreboard.open()
	hud.update_snapshot(sim.snapshot())
	# 用 get() 取属性：属性不存在时直接访问会抛运行时错误，被测试框架当成 PASS。
	var sub: Variant = hud._scoreboard.get("_rate_label")
	check(sub != null, "panel must expose a gold-per-minute line")
	if sub != null:
		check(sub.text.contains("分均"), "gold per minute line is labelled: %s" % sub.text)
		# 1200 金币 / 2 分钟 = 600 每分钟。
		check(sub.text.contains("600"), "1200 gold in 2 minutes is 600/min: %s" % sub.text)
	hud.free()
