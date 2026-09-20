extends "res://tests/validation/test_case.gd"
## Run: python3 tests/run_validation.py --jobs 1 --filter tests/validation/validate_ada_recruitment.gd

const ADA_PATH := "res://features/actors/resources/characters/ada.tres"
const DIALOGUE_PATH := "res://features/conversation/resources/ada_recruitment.tres"
const HOE_PATH := "res://features/inventory/resources/items/hoe.tres"
const TOMATO_SEEDS_PATH := "res://features/inventory/resources/items/tomato_seeds.tres"
const CONDITION_EVALUATOR := preload("res://features/settlements/sim/actor_condition_evaluator.gd")
const POPULATION_SOURCE_PATH := "res://features/world_sim/sim/population/population_controller.gd"
const POPULATION_COMPONENT_SOURCE_PATH := "res://features/world_sim/sim/population/c_game_population_record.gd"
const CONVERSATION_SOURCE_PATH := "res://features/conversation/conversation_controller.gd"
const PARTY_MANAGER_PATH := "res://features/core/party/party_manager.gd"


var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var definition := load(ADA_PATH) as CharacterRecordDefinition
	_expect(definition != null, "Ada permanent character definition loads")
	if definition == null:
		_finish()
		return
	var record := definition.to_record()
	_expect(str(record.get("conversation_definition_path", "")) == DIALOGUE_PATH, "Ada record owns her recruitment conversation")
	var dialogue := load(DIALOGUE_PATH) as ConversationDefinition
	_expect(dialogue != null, "Ada recruitment conversation loads")
	if dialogue == null:
		_finish()
		return
	var recruit_response = _recruit_response(dialogue)
	_expect(recruit_response != null, "Ada conversation offers recruitment")
	var not_party_condition = recruit_response.visible_conditions[0] if recruit_response != null and not recruit_response.visible_conditions.is_empty() else null
	_expect(not_party_condition != null and str(not_party_condition.condition_id) == "actor.is_player_party_member" and bool(not_party_condition.negate), "Recruitment is offered only while Ada is outside the party")
	var join_effect = _join_effect(dialogue, recruit_response)
	_expect(join_effect != null, "Ada recruitment uses the shared join-party effect")
	# Live realization/recruitment/persistence: validate_recruited_party_selection.gd

	var equipment: Dictionary = record.get("equipment_slots", {})
	_expect(str(equipment.get("weapon", "")) == HOE_PATH, "Ada's durable record equips the Hoe")
	var tomato_seed_count := 0
	for entry_value in record.get("inventory_entries", []):
		var entry: Dictionary = entry_value
		if str(entry.get("item_id", "")) == TOMATO_SEEDS_PATH:
			tomato_seed_count += int(entry.get("count", 0))
	_expect(tomato_seed_count == 10, "Ada starts with 10 tomato seeds")
	_finish()


func _recruit_response(dialogue: ConversationDefinition):
	var intro = dialogue.get_node_by_id(dialogue.start_node_id)
	if intro == null:
		return null
	for response in intro.responses:
		if response != null and not str(response.next_node_id).is_empty():
			return response
	return null


func _join_effect(dialogue: ConversationDefinition, recruit_response):
	if recruit_response == null:
		return null
	var join_node = dialogue.get_node_by_id(str(recruit_response.next_node_id))
	if join_node == null:
		return null
	for effect in join_node.effects:
		if effect != null and str(effect.action_id) == "core.join_party":
			return effect
	return null


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("ADA_RECRUITMENT_OK")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	print("ADA_RECRUITMENT_FAILED count=%d" % _failures.size())
	quit(1)
