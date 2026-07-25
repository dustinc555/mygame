extends Node

class_name EncounterController

const SERVICE_ID := &"encounter"

## Drives world-sim encounters through timed phases (grace periods) — pure logic, no
## bodies, no rendering. When an attack squad reaches its target the mover hands it off
## here by setting phase = "demand". This controller counts down each grace window and
## applies the WINNER's objective on resolve. Watchable entirely from the F9 brain log
## and the M map. Source of truth stays the GECS squad records.
##
## Phase flow (demand_tribute):
##   demand  -> town decides (personality leaning, committed at timer end)
##               comply -> pay tribute, raiders march home
##               refuse -> fight
##   fight   -> standoff grace, then dice on combat-stat leverage -> aftermath
##   aftermath -> winner's objective applied:
##               raiders won  -> haul loot home
##               town won     -> capture some raiders (jail), survivors flee home

const TICK_INTERVAL := 0.5
const DEMAND_OBJECTIVE_PATH := "res://features/world_sim/resources/encounters/demand_tribute.tres"
const AFTERMATH_HOLD_SECONDS := 4.0

var _tick_remaining := 0.0
var _objective: Resource
var _context: BootstrapContext


func initialize(context: BootstrapContext) -> void:
	_context = context


func _ready() -> void:
	add_to_group("encounter_controller")
	_objective = load(DEMAND_OBJECTIVE_PATH)


func _process(delta: float) -> void:
	_tick_remaining -= delta
	if _tick_remaining > 0.0:
		return
	_tick_remaining = TICK_INTERVAL
	_tick(TICK_INTERVAL)


func _tick(dt: float) -> void:
	var gecs := _get_gecs_world()
	if gecs == null or not gecs.has_method("get_world_sim_squads"):
		return
	var faction_ctrl := _get_faction_world_sim()
	for record in gecs.get_world_sim_squads():
		if str(record.get("phase", "")).is_empty():
			continue
		# A squad whose bodies are live fights for real — don't let the data brain
		# resolve it underneath the player.
		if _is_world_sim_squad_realized(str(record.get("squad_id", "")), faction_ctrl):
			continue
		_advance_phase(gecs, faction_ctrl, record, dt)


func _advance_phase(gecs: Node, faction_ctrl: Node, record: Dictionary, dt: float) -> void:
	match str(record.get("phase", "")):
		"demand":
			_advance_demand(gecs, record, dt)
		"fight":
			_advance_fight(gecs, faction_ctrl, record, dt)
		"aftermath":
			_advance_aftermath(gecs, record, dt)
		_:
			gecs.upsert_world_sim_squad(record)


## DEMAND — first sight forms the leaning (shown immediately so the player has a window);
## the timer counts down and the leaning commits at zero.
func _advance_demand(gecs: Node, record: Dictionary, dt: float) -> void:
	var faction_id := str(record.get("faction_id", ""))
	var target_id := str(record.get("target_settlement_id", ""))
	if str(record.get("decision", "")).is_empty():
		var leaning := _decide_defender(record)
		record["decision"] = leaning
		record["phase_timer"] = _objective_float("demand_grace_seconds", 18.0)
		_log(gecs, "%s demands tribute from %s — %s leaning to %s" % [faction_id, target_id, target_id, leaning])
		gecs.upsert_world_sim_squad(record)
		return
	var timer := float(record.get("phase_timer", 0.0)) - dt
	record["phase_timer"] = timer
	if timer > 0.0:
		gecs.upsert_world_sim_squad(record)
		return
	# Commit.
	if str(record.get("decision", "")) == "comply":
		var amount := _objective_float("demand_food_amount", 25.0)
		var transferred := _transfer_food(target_id, str(record.get("owner_id", "")), absf(amount))
		_log(gecs, "%s pays %d food units tribute to %s — raiders march home" % [target_id, int(transferred), faction_id])
		_send_home(record, "march home with tribute")
		gecs.upsert_world_sim_squad(record)
	else:
		record["phase"] = "fight"
		record["phase_timer"] = _objective_float("fight_grace_seconds", 12.0)
		_log(gecs, "%s refuses %s — battle in %ds" % [target_id, faction_id, int(record["phase_timer"])])
		gecs.upsert_world_sim_squad(record)


## FIGHT — standoff grace, then dice on combat-stat leverage.
func _advance_fight(gecs: Node, faction_ctrl: Node, record: Dictionary, dt: float) -> void:
	var timer := float(record.get("phase_timer", 0.0)) - dt
	record["phase_timer"] = timer
	if timer > 0.0:
		gecs.upsert_world_sim_squad(record)
		return
	var faction_id := str(record.get("faction_id", ""))
	var target_id := str(record.get("target_settlement_id", ""))
	var attackers := int(record.get("member_count", 0))
	if str(record.get("owner_kind", "")) == "faction" and faction_ctrl != null and faction_ctrl.has_method("ensure_faction_squad_people"):
		faction_ctrl.call("ensure_faction_squad_people", record)
	elif str(record.get("owner_kind", "")) == "nest" and get_tree() != null:
		var nest_plugin := get_tree().get_first_node_in_group("nest_world_sim_plugin")
		if nest_plugin != null and nest_plugin.has_method("ensure_nest_squad_people_for_record"):
			nest_plugin.call("ensure_nest_squad_people_for_record", record)
	var outcome: Dictionary = {}
	if faction_ctrl != null and faction_ctrl.has_method("roll_raid"):
		outcome = faction_ctrl.roll_raid(attackers, target_id)
	var won := bool(outcome.get("won", false))
	var survivors := int(outcome.get("survivors", attackers))
	var population := _context.get_optional(PopulationController.SERVICE_ID) if _context != null else null
	if population != null and population.has_method("apply_offscreen_squad_casualties"):
		population.call("apply_offscreen_squad_casualties", str(record.get("squad_id", "")), survivors, record.get("position", Vector3.ZERO))
	record["member_count"] = survivors
	record["decision"] = "won" if won else "lost"
	record["phase"] = "aftermath"
	record["phase_timer"] = AFTERMATH_HOLD_SECONDS
	var verdict := "WON" if won else "REPELLED"
	_log(gecs, "%s %s the battle at %s (%.0f%% odds) — %d/%d raiders standing" % [
		faction_id, verdict, target_id, float(outcome.get("win_chance", 0.0)) * 100.0, survivors, attackers])
	gecs.upsert_world_sim_squad(record)


## AFTERMATH — apply the winner's objective, then send survivors home or retire.
func _advance_aftermath(gecs: Node, record: Dictionary, dt: float) -> void:
	var timer := float(record.get("phase_timer", 0.0)) - dt
	record["phase_timer"] = timer
	if timer > 0.0:
		gecs.upsert_world_sim_squad(record)
		return
	var faction_id := str(record.get("faction_id", ""))
	var target_id := str(record.get("target_settlement_id", ""))
	var survivors := int(record.get("member_count", 0))
	if str(record.get("decision", "")) == "won":
		var loot := _objective_float("loot_food_on_win", 35.0)
		var faction_ctrl := _get_faction_world_sim()
		if faction_ctrl != null and faction_ctrl.has_method("apply_raid_win_spoils"):
			faction_ctrl.apply_raid_win_spoils(target_id, str(record.get("owner_id", "")), loot)
		_log(gecs, "%s loots %d food from %s and heads home" % [faction_id, int(loot), target_id])
		_send_home(record, "haul loot home")
		gecs.upsert_world_sim_squad(record)
		return
	# Town won: capture some raiders (jailed), the rest flee home.
	var capture_fraction := _objective_float("capture_fraction_on_defense_win", 0.5)
	var captured := int(floor(float(survivors) * capture_fraction))
	var fleeing := maxi(0, survivors - captured)
	if captured > 0:
		var population := _context.get_optional(PopulationController.SERVICE_ID) if _context != null else null
		var captured_actor_ids: Array[String] = []
		if population != null and population.has_method("apply_offscreen_squad_captures"):
			captured_actor_ids.assign(population.call("apply_offscreen_squad_captures", str(record.get("squad_id", "")), captured, target_id, record.get("position", Vector3.ZERO)))
		var law_order := _context.get_optional(LawOrderController.SERVICE_ID) if _context != null else null
		var settlement := _get_settlement_controller()
		var settlement_state: Dictionary = settlement.call("get_settlement_state", target_id) if settlement != null and settlement.has_method("get_settlement_state") else {}
		var jurisdiction_faction_id := str(settlement_state.get("faction_id", ""))
		if law_order != null and law_order.has_method("register_offscreen_prisoner"):
			for actor_id in captured_actor_ids:
				law_order.call("register_offscreen_prisoner", actor_id, target_id, jurisdiction_faction_id)
		_log(gecs, "%s captures %d raider(s) — held at %s" % [target_id, captured, target_id])
	if fleeing > 0:
		record["member_count"] = fleeing
		_log(gecs, "%d %s survivor(s) flee back home" % [fleeing, faction_id])
		_send_home(record, "flee home")
		gecs.upsert_world_sim_squad(record)
	else:
		_log(gecs, "%s war party wiped out at %s" % [faction_id, target_id])
		gecs.remove_world_sim_squad(str(record.get("squad_id", "")))


## Send the squad back to its home settlement — clears the encounter so the mover
## resumes transport. Retires on arrival (mover's "return" branch).
func _send_home(record: Dictionary, _reason: String) -> void:
	record["objective"] = "return"
	record["phase"] = ""
	record["decision"] = ""
	record["phase_timer"] = 0.0
	record["target_position"] = record.get("home_position", record.get("position", Vector3.ZERO))


## Defender personality leaning: proud/aggressive/strong towns refuse; timid/outgunned
## towns pay. Returns "comply" or "refuse".
func _decide_defender(record: Dictionary) -> String:
	var target_id := str(record.get("target_settlement_id", ""))
	var personality := _faction_personality(_settlement_faction_id(target_id))
	var aggression := 0.25
	var honor := 0.5
	if personality != null:
		if personality.get("aggression") != null:
			aggression = float(personality.get("aggression"))
		if personality.get("honor") != null:
			honor = float(personality.get("honor"))
	var attackers := float(maxi(int(record.get("member_count", 0)), 1))
	var defenders := _settlement_defender_power(target_id)
	var strength := defenders / maxf(attackers + defenders, 0.001)
	var refuse_score := aggression * 0.4 + honor * 0.35 + strength * 0.25
	return "refuse" if refuse_score >= 0.5 else "comply"


func _settlement_defender_power(settlement_id: String) -> float:
	var settlements := _get_settlement_controller()
	if settlements != null and settlements.has_method("get_settlement_state"):
		var state: Dictionary = settlements.call("get_settlement_state", settlement_id)
		return float(state.get("population", 0)) + 3.0
	return 6.0


func _settlement_faction_id(settlement_id: String) -> String:
	if get_tree() == null:
		return ""
	for node in get_tree().get_nodes_in_group("settlement_town"):
		var node_id := str(node.call("get_settlement_id")) if node.has_method("get_settlement_id") else str(node.name)
		if node_id != settlement_id:
			continue
		if node.has_method("get_faction_id"):
			return str(node.call("get_faction_id"))
		if node.get("faction_id") != null:
			return str(node.get("faction_id"))
	return ""


func _faction_personality(faction_id: String) -> Resource:
	if faction_id.is_empty():
		return null
	var factions := _get_faction_controller()
	if factions == null or not factions.has_method("get_faction_definition"):
		return null
	var definition = factions.get_faction_definition(faction_id)
	if definition == null or not definition.has_method("get_personality_profile"):
		return null
	return definition.get_personality_profile()


func _transfer_food(source_settlement_id: String, target_settlement_id: String, amount: float) -> float:
	var stock := _context.get_optional(InventoryStockController.SERVICE_ID) as InventoryStockController if _context != null else null
	if stock == null or target_settlement_id.is_empty():
		return 0.0
	return float(stock.transfer_food_units(source_settlement_id, target_settlement_id, amount).get("food_units", 0.0))


func _objective_float(property: String, fallback: float) -> float:
	if _objective != null and _objective.get(property) != null:
		return float(_objective.get(property))
	return fallback


func _is_world_sim_squad_realized(squad_id: String, faction_ctrl: Node) -> bool:
	if faction_ctrl != null and faction_ctrl.has_method("is_faction_squad_realized") and bool(faction_ctrl.call("is_faction_squad_realized", squad_id)):
		return true
	var ticker := _get_world_sim_squad_controller()
	if ticker == null or not ticker.has_method("get_world_sim_plugins"):
		return false
	for plugin in ticker.call("get_world_sim_plugins"):
		if plugin is Node and (plugin as Node).has_method("is_world_sim_squad_realized") and bool((plugin as Node).call("is_world_sim_squad_realized", squad_id)):
			return true
	return false


func _log(gecs: Node, message: String) -> void:
	if gecs != null and gecs.has_method("log_world_event"):
		gecs.log_world_event("encounter", message, {})


func _get_settlement_controller() -> Node:
	return _context.get_optional(SettlementController.SERVICE_ID) if _context != null else null


func _get_faction_controller() -> Node:
	return _context.get_optional(FactionController.SERVICE_ID) if _context != null else null


func _get_faction_world_sim() -> Node:
	return _context.get_optional(FactionWorldSimController.SERVICE_ID) if _context != null else null


func _get_world_sim_squad_controller() -> Node:
	return _context.get_optional(WorldSimSquadController.SERVICE_ID) if _context != null else null


func _get_gecs_world() -> Node:
	return _context.get_optional(GecsWorldController.SERVICE_ID) if _context != null else null
