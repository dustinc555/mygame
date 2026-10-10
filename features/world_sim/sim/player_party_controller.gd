extends Node

class_name PlayerPartyController

## Owns the one-time start transaction and saved squad definitions, never bodies.
const SERVICE_ID := &"player_party"
const STATE := preload("res://features/world_sim/sim/c_game_player_party_state.gd")
const ENTITY := preload("res://addons/gecs/ecs/entity.gd")
const SCENARIO := preload("res://features/world_sim/resources/start_scenario_definition.gd")

signal roster_changed

var state: Resource
var _gecs: GecsWorldController
var _population: PopulationController
var _party: PartyManager

func initialize(context: BootstrapContext) -> void:
	_gecs = context.require(GecsWorldController.SERVICE_ID) as GecsWorldController
	_population = context.require(PopulationController.SERVICE_ID) as PopulationController
	_party = context.root_scene.get_node_or_null("PartyManager") as PartyManager
	_gecs.world_reindexed.connect(_on_world_reindexed)
	_bind_state(false)

func _bind_state(restoring: bool) -> void:
	state = null
	for entity in _gecs.world.query.with_all([STATE]).execute():
		state = entity.get_component(STATE)
		break
	if state == null:
		var entity := ENTITY.new()
		entity.name = "PlayerPartyState"
		entity.id = "player_party:state"
		var initial := STATE.new()
		# Older saves have no start receipt. They are still saves, never permission
		# to re-create dead/departed characters from a new-game definition.
		initial.start_applied = restoring
		_gecs.world.add_entity(entity, [initial])
		state = entity.get_component(STATE)
	roster_changed.emit()

func _on_world_reindexed() -> void:
	_bind_state(true)

func start_scenario(scenario: SCENARIO, world_transform := Transform3D.IDENTITY) -> Array[Dictionary]:
	if state == null or state.start_applied:
		return []
	if scenario == null:
		push_error("A new game requires a start scenario.")
		return []
	var records := scenario.create_records(world_transform)
	if records.is_empty():
		return []
	# Validate the entire roster before committing any starting conditions.
	for record in records:
		if not _population.get_actor_record(str(record["actor_id"])).is_empty():
			push_error("Starting character already exists: %s" % record["actor_id"])
			return []
	for record in records:
		_gecs.upsert_population_record(record)
	state.scenario_id = scenario.scenario_id.strip_edges()
	state.squad_names = PackedStringArray([scenario.squad_name.strip_edges()])
	state.start_applied = true
	roster_changed.emit()
	return records

func get_squad_names() -> Array[String]:
	var names: Array[String] = []
	if state != null:
		names.assign(state.squad_names)
	if _party != null:
		for member in _party.party_members:
			var squad := member.squad_name.strip_edges()
			if not squad.is_empty() and not names.has(squad):
				names.append(squad)
	return names


func create_squad(raw_name: String) -> bool:
	var squad := raw_name.strip_edges()
	if state == null or not _name_available(squad):
		return false
	state.squad_names.append(squad)
	roster_changed.emit()
	return true


func rename_squad(old_name: String, raw_name: String) -> bool:
	var squad := raw_name.strip_edges()
	if state == null or not get_squad_names().has(old_name) or not _name_available(squad, old_name):
		return false
	# Rename the durable records first, including members without a live body.
	for record in _population.get_records_for_squad(old_name):
		if str(record.get("party_id", "")) == PartyManager.PLAYER_PARTY_ID:
			_population.update_actor_record(str(record["actor_id"]), {"squad_name": squad})
	var index: int = state.squad_names.find(old_name)
	if index >= 0:
		state.squad_names[index] = squad
	else:
		state.squad_names.append(squad)
	if _party != null:
		for member in _party.party_members:
			if member.squad_name.strip_edges() == old_name:
				member.squad_name = squad
	roster_changed.emit()
	return true


func _name_available(squad: String, ignored_name := "") -> bool:
	if squad.is_empty() or squad.to_lower() in ["all", "default"]:
		return false
	for existing in get_squad_names():
		if existing != ignored_name and existing.to_lower() == squad.to_lower():
			return false
	return true
