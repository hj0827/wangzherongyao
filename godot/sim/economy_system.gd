extends RefCounted

const NATURAL_GOLD_PER_SECOND := 3.0
const MINION_KILL_GOLD := 54
const MINION_ASSIST_GOLD := 32
const HERO_KILL_GOLD := 200
const FIRST_BLOOD_BONUS := 100
const TOWER_DESTROY_GOLD := 120

static func tick_natural_gold(hero: Dictionary, dt: float) -> void:
	if not bool(hero.get("alive", true)):
		return
	var current_acc: float = float(hero.get("gold_fraction", 0.0)) + NATURAL_GOLD_PER_SECOND * dt
	var full_gold := int(current_acc)
	if full_gold > 0:
		hero["gold"] = int(hero.get("gold", 0)) + full_gold
		hero["gold_fraction"] = current_acc - float(full_gold)
	else:
		hero["gold_fraction"] = current_acc

static func award_minion_kill(hero: Dictionary, last_hit: bool) -> void:
	var award := MINION_KILL_GOLD if last_hit else MINION_ASSIST_GOLD
	hero["gold"] = int(hero.get("gold", 0)) + award

static func award_hero_kill(killer: Dictionary, is_first_blood: bool) -> void:
	var total := HERO_KILL_GOLD + (FIRST_BLOOD_BONUS if is_first_blood else 0)
	killer["gold"] = int(killer.get("gold", 0)) + total

static func award_tower_team_gold(team: String, entities: Array) -> void:
	for e in entities:
		if str(e.get("type", "")) == "hero" and str(e.get("team", "")) == team:
			e["gold"] = int(e.get("gold", 0)) + TOWER_DESTROY_GOLD
