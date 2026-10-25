extends RefCounted

const HeroDefs = preload("res://sim/hero_defs.gd")
const Collision = preload("res://sim/map/collision.gd")
const Jungle = preload("res://sim/map/jungle.gd")

const SUMMONER_SPELLS := {
	"flash": {
		"id": "flash",
		"name": "闪现",
		"desc": "向指定方向瞬间位移一段距离。",
		"cooldown": 90.0,
		"range": 4.8,
	},
	"execute": {
		"id": "execute",
		"name": "终结",
		"desc": "对身旁残血敌人造成基于已损生命的真实伤害。",
		"cooldown": 90.0,
		"range": 4.0,
		"base_damage": 120.0,
		"missing_hp_pct": 0.14,
	},
	"cleanse": {
		"id": "cleanse",
		"name": "净化",
		"desc": "解除所有控制与负面状态，并在短时间内获得免控。",
		"cooldown": 90.0,
		"range": 0.0,
		"duration": 1.5,
	},
	"heal": {
		"id": "heal",
		"name": "治疗",
		"desc": "立即回复自身与周围生命值最低友军的生命并提升移速。",
		"cooldown": 90.0,
		"range": 5.5,
		"heal_pct": 0.15,
		"speed_boost_time": 2.0,
	},
}

static func get_available_summoner_spells() -> Array:
	return SUMMONER_SPELLS.keys()

static func get_summoner_spell(spell_id: String) -> Dictionary:
	return SUMMONER_SPELLS.get(spell_id, SUMMONER_SPELLS["flash"])

static func cast_skill(hero: Dictionary, slot: String, aim: Vector2, sim: Object) -> bool:
	if not bool(hero.get("alive", true)):
		return false
	var hero_type: String = str(hero.get("hero_type", "blade"))
	var hero_def: Dictionary = HeroDefs.get_hero(hero_type)
	if not hero_def.has(slot):
		return false
	var skill: Dictionary = hero_def[slot]
	var cd_key := "skill_%s_cd" % slot
	if float(hero.get(cd_key, 0.0)) > 0.0:
		return false
	var cost: float = float(skill.get("cost", 0.0))
	if float(hero.get("mp", 0.0)) < cost:
		return false

	hero["mp"] = float(hero.get("mp", 0.0)) - cost
	hero[cd_key] = float(skill.get("cooldown", 5.0)) * Jungle.cooldown_scale(hero)
	
	var damage: float = float(skill.get("damage", 0.0))
	if damage > 0.0:
		damage += float(hero.get("ability_power", 0.0)) * 0.3
	var range_val: float = float(skill.get("range", 5.0))
	var kind: String = str(skill.get("kind", ""))
	var hero_pos: Vector2 = hero.get("pos", Vector2.ZERO)
	var facing: Vector2 = hero.get("facing", Vector2.UP)

	match kind:
		"spin":
			_apply_aoe_damage(hero, hero_pos, range_val, damage, sim)
		"dash":
			# 纯位移型（苍刃 E「疾风步」）：向前冲一段，不造成伤害。
			var dash_dir: Vector2 = (aim - hero_pos).normalized()
			if dash_dir == Vector2.ZERO:
				dash_dir = facing
			hero["facing"] = dash_dir
			var dash_dist: float = range_val if (aim - hero_pos).length() < 0.1 else minf((aim - hero_pos).length(), range_val)
			var dash_dest: Vector2 = Collision.move(hero_pos, hero_pos + dash_dir * dash_dist, float(hero.get("radius", 0.55)))
			hero["pos"] = dash_dest
			if damage > 0.0:
				_apply_aoe_damage(hero, dash_dest, 1.8, damage, sim)
		"shield":
			# 自身护盾型（铁壁 E「守护壁垒」）：护盾值随技能等级/法强线性走。
			var shield_gain: float = 320.0 + float(skill.get("damage", 0.0)) + float(hero.get("ability_power", 0.0)) * 0.5
			hero["shield"] = float(hero.get("shield", 0.0)) + shield_gain
			hero["shield_timer"] = float(skill.get("duration", 4.0))
		"haste":
			# 自身加速型（翎羽 E「鹰眼」）：短时移速。
			hero["haste_timer"] = float(skill.get("duration", 3.0))
		"evade":
			# 刺客 E「匿踪」：加速 + 免控 + 清减速，短窗口内脱离缠斗。
			hero["haste_timer"] = float(skill.get("duration", 2.5))
			hero["cc_immune_timer"] = float(skill.get("immune", 1.2))
			hero["slow_timer"] = 0.0
			hero["revealed_timer"] = 0.0
		"line":
			var dir: Vector2 = (aim - hero_pos).normalized()
			if dir == Vector2.ZERO:
				dir = facing
			hero["facing"] = dir
			_apply_line_damage(hero, hero_pos, dir, range_val, damage, sim, 2.0)
		"charge":
			var dir: Vector2 = (aim - hero_pos).normalized()
			if dir == Vector2.ZERO:
				dir = facing
			hero["facing"] = dir
			var target_pos: Vector2 = hero_pos + dir * range_val
			target_pos = Collision.move(hero_pos, target_pos, float(hero.get("radius", 0.55)))
			hero["pos"] = target_pos
			_apply_aoe_damage(hero, target_pos, 2.5, damage, sim)
		"aoe_shot":
			var target_pos: Vector2 = aim
			if (target_pos - hero_pos).length() > range_val:
				target_pos = hero_pos + (target_pos - hero_pos).normalized() * range_val
			_apply_aoe_damage(hero, target_pos, 2.8, damage, sim)
		"leap_slam":
			var target_pos: Vector2 = aim
			if (target_pos - hero_pos).length() > range_val:
				target_pos = hero_pos + (target_pos - hero_pos).normalized() * range_val
			target_pos = Collision.move(hero_pos, target_pos, float(hero.get("radius", 0.55)))
			hero["pos"] = target_pos
			_apply_aoe_damage(hero, target_pos, 3.2, damage, sim)
		"meteor_storm":
			var target_pos: Vector2 = aim
			if (target_pos - hero_pos).length() > range_val:
				target_pos = hero_pos + (target_pos - hero_pos).normalized() * range_val
			_apply_aoe_damage(hero, target_pos, 4.0, damage, sim)
		"taunt_aura":
			hero["shield"] = float(hero.get("shield", 0.0)) + 350.0
			hero["shield_timer"] = 5.0
			_apply_aoe_damage(hero, hero_pos, range_val, damage, sim)
		"arrow_barrage":
			var dir: Vector2 = (aim - hero_pos).normalized()
			if dir == Vector2.ZERO:
				dir = facing
			hero["facing"] = dir
			_apply_cone_damage(hero, hero_pos, dir, range_val, damage, sim)
		_:
			if damage > 0.0:
				var target: Dictionary = _find_target_near(hero, aim, range_val, sim)
				if not target.is_empty():
					_deal_damage(hero, target, damage, sim)

	# 渲染层要靠这些字段出特效：hero_type / kind 决定配方，start_* 是施法瞬间的站位
	# （冲锋类技能会改 hero.pos，不能拿结束位置当起点），aim 是落点。
	if sim.has_method("_emit"):
		sim._emit("skill_cast", {
			"caster_id": hero.get("id", 0),
			"slot": slot,
			"hero_type": hero_type,
			"name": str(skill.get("name", "")),
			"kind": kind,
			"team": str(hero.get("team", "")),
			"pos": [hero_pos.x, hero_pos.y],
			"x": float(hero_pos.x),
			"y": float(hero_pos.y),
			"start_x": float(hero_pos.x),
			"start_y": float(hero_pos.y),
			"aim_x": float(aim.x),
			"aim_y": float(aim.y),
		})
	return true

static func cast_summoner_spell(hero: Dictionary, spell_id: String, aim: Vector2, sim: Object) -> bool:
	if not bool(hero.get("alive", true)):
		return false
	if float(hero.get("summoner_cd", 0.0)) > 0.0:
		return false
	var spell: Dictionary = get_summoner_spell(spell_id)
	var cd: float = float(spell.get("cooldown", 90.0))
	var range_val: float = float(spell.get("range", 5.0))
	var hero_pos: Vector2 = hero.get("pos", Vector2.ZERO)
	var facing: Vector2 = hero.get("facing", Vector2.UP)

	match spell_id:
		"flash":
			var dir: Vector2 = (aim - hero_pos).normalized()
			if dir == Vector2.ZERO:
				dir = facing
			var dist: float = minf((aim - hero_pos).length(), range_val)
			if dist < 0.1:
				dist = range_val
			# 闪现是瞬移，不是冲刺：不能交给 Collision.move —— 那条路径会逐步防穿墙、
			# 撞墙后只保留切向滑行，实测 4.4 米的穿墙闪只走出 0.8 米。
			# nearest_free 兜住两件事：落点不许卡在墙里，以及地图可走边界
			# （内部 clamp_bounds 让出相机安全边距），所以闪现闪不出地图。
			hero["pos"] = Collision.nearest_free(hero_pos + dir * dist, float(hero.get("radius", 0.55)))
		"execute":
			var enemy: Dictionary = _find_target_near(hero, hero_pos, range_val, sim)
			if enemy.is_empty():
				return false
			var missing_hp: float = maxf(0.0, float(enemy.get("max_hp", 1.0)) - float(enemy.get("hp", 0.0)))
			var true_damage: float = float(spell.get("base_damage", 120.0)) + missing_hp * float(spell.get("missing_hp_pct", 0.14))
			_deal_damage(hero, enemy, true_damage, sim)
		"cleanse":
			hero["slow_timer"] = 0.0
			hero["cc_immune_timer"] = float(spell.get("duration", 1.5))
		"heal":
			var max_hp: float = float(hero.get("max_hp", 100.0))
			var cur_hp: float = float(hero.get("hp", 0.0))
			var heal_amount: float = max_hp * float(spell.get("heal_pct", 0.15))
			hero["hp"] = minf(max_hp, cur_hp + heal_amount)
			hero["haste_timer"] = float(spell.get("speed_boost_time", 2.0))
			var ally: Dictionary = _find_lowest_hp_ally(hero, range_val, sim)
			if not ally.is_empty() and int(ally.get("id", 0)) != int(hero.get("id", 0)):
				var ally_max_hp: float = float(ally.get("max_hp", 100.0))
				var ally_cur_hp: float = float(ally.get("hp", 0.0))
				ally["hp"] = minf(ally_max_hp, ally_cur_hp + ally_max_hp * float(spell.get("heal_pct", 0.15)))
				ally["haste_timer"] = float(spell.get("speed_boost_time", 2.0))
		_:
			return false

	hero["summoner_cd"] = cd
	if sim.has_method("_emit"):
		sim._emit("summoner_cast", {
			"caster_id": hero.get("id", 0),
			"spell_id": spell_id,
			"hero_type": str(hero.get("hero_type", "")),
			"team": str(hero.get("team", "")),
			"pos": [hero_pos.x, hero_pos.y],
			"x": float(hero_pos.x),
			"y": float(hero_pos.y),
			"start_x": float(hero_pos.x),
			"start_y": float(hero_pos.y),
			"aim_x": float(aim.x),
			"aim_y": float(aim.y),
		})
	return true

static func on_hero_attack_hit(attacker: Dictionary, target: Dictionary, sim: Object) -> void:
	var hero_type: String = str(attacker.get("hero_type", "blade"))
	match hero_type:
		"blade":
			var stacks: int = int(attacker.get("passive_stacks", 0)) + 1
			if stacks >= 3:
				_deal_damage(attacker, target, 45.0, sim)
				target["slow_timer"] = 1.2
				stacks = 0
			attacker["passive_stacks"] = stacks
		"archer":
			attacker["haste_timer"] = 1.5
		"tank":
			if float(attacker.get("hp", 1.0)) / maxf(1.0, float(attacker.get("max_hp", 1.0))) < 0.4:
				attacker["shield"] = float(attacker.get("shield", 0.0)) + 120.0
				attacker["shield_timer"] = 3.0
		"mage":
			attacker["mp"] = minf(float(attacker.get("max_mp", 1.0)), float(attacker.get("mp", 0.0)) + 20.0)
		"assassin":
			# 背刺：attacker 相对 target 的方位与 target 朝向相反时额外加伤。
			# 判定用点积而不是角度，避免每一击都算 atan2。
			var to_attacker: Vector2 = attacker.get("pos", Vector2.ZERO) - target.get("pos", Vector2.ZERO)
			var target_facing: Vector2 = target.get("facing", Vector2.UP)
			if to_attacker.length() > 0.01 and target_facing.length() > 0.01:
				if to_attacker.normalized().dot(target_facing.normalized()) < -0.15:
					_deal_damage(attacker, target, float(attacker.get("attack_damage", 0.0)) * 0.25, sim)

static func _find_target_near(hero: Dictionary, center: Vector2, max_dist: float, sim: Object) -> Dictionary:
	var best: Dictionary = {}
	var best_dist: float = max_dist
	for e in sim.state.entities:
		if not bool(e.get("alive", true)):
			continue
		if str(e.get("team", "")) == str(hero.get("team", "")):
			continue
		var pos: Vector2 = e.get("pos", Vector2.ZERO)
		var dist: float = (pos - center).length()
		if dist <= best_dist:
			best_dist = dist
			best = e
	return best

static func _find_lowest_hp_ally(hero: Dictionary, max_dist: float, sim: Object) -> Dictionary:
	var best: Dictionary = {}
	var min_hp_ratio: float = 1.1
	var hero_pos: Vector2 = hero.get("pos", Vector2.ZERO)
	for e in sim.state.entities:
		if not bool(e.get("alive", true)):
			continue
		if str(e.get("team", "")) != str(hero.get("team", "")) or str(e.get("type", "")) != "hero":
			continue
		var pos: Vector2 = e.get("pos", Vector2.ZERO)
		var dist: float = (pos - hero_pos).length()
		if dist <= max_dist:
			var ratio: float = float(e.get("hp", 0.0)) / maxf(1.0, float(e.get("max_hp", 1.0)))
			if ratio < min_hp_ratio:
				min_hp_ratio = ratio
				best = e
	return best

static func _apply_aoe_damage(hero: Dictionary, center: Vector2, radius: float, damage: float, sim: Object) -> void:
	for e in sim.state.entities:
		if not bool(e.get("alive", true)):
			continue
		if str(e.get("team", "")) == str(hero.get("team", "")):
			continue
		var pos: Vector2 = e.get("pos", Vector2.ZERO)
		if (pos - center).length() <= radius:
			_deal_damage(hero, e, damage, sim)

static func _apply_line_damage(hero: Dictionary, start: Vector2, dir: Vector2, length: float, damage: float, sim: Object, slow_sec: float) -> void:
	for e in sim.state.entities:
		if not bool(e.get("alive", true)):
			continue
		if str(e.get("team", "")) == str(hero.get("team", "")):
			continue
		var pos: Vector2 = e.get("pos", Vector2.ZERO)
		var to_e: Vector2 = pos - start
		var proj: float = to_e.dot(dir)
		if proj >= 0.0 and proj <= length:
			var perp: float = (to_e - dir * proj).length()
			if perp <= 1.2:
				_deal_damage(hero, e, damage, sim)
				if slow_sec > 0.0:
					e["slow_timer"] = slow_sec

static func _apply_cone_damage(hero: Dictionary, origin: Vector2, dir: Vector2, range_val: float, damage: float, sim: Object) -> void:
	for e in sim.state.entities:
		if not bool(e.get("alive", true)):
			continue
		if str(e.get("team", "")) == str(hero.get("team", "")):
			continue
		var pos: Vector2 = e.get("pos", Vector2.ZERO)
		var to_e: Vector2 = pos - origin
		var dist: float = to_e.length()
		if dist > 0.1 and dist <= range_val:
			if to_e.normalized().dot(dir) > 0.5:
				_deal_damage(hero, e, damage, sim)

static func _deal_damage(attacker: Dictionary, target: Dictionary, amount: float, sim: Object) -> void:
	if sim != null and sim.has_method("_damage"):
		sim._damage(target, amount, attacker)
		return
	var final_damage: float = amount
	var shield: float = float(target.get("shield", 0.0))
	if shield > 0.0:
		if shield >= final_damage:
			target["shield"] = shield - final_damage
			final_damage = 0.0
		else:
			final_damage -= shield
			target["shield"] = 0.0
	var cur_hp: float = float(target.get("hp", 0.0))
	target["hp"] = maxf(0.0, cur_hp - final_damage)
	target["last_attacker_id"] = attacker.get("id", -1)
	target["last_attacker_time"] = sim.state.time
	if str(attacker.get("type", "")) == "hero":
		target["last_hero_attacker_id"] = attacker.get("id", -1)
		target["last_hero_attacker_time"] = sim.state.time
	if float(target.get("hp", 0.0)) <= 0.0:
		target["alive"] = false
