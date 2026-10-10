extends Node3D

const SCENARIO := preload("res://features/world_sim/resources/start_scenario_definition.gd")

## Standalone test/demo scene input. A containing WorldRoot owns the actual
## campaign choice and takes precedence over this local authoring input.
@export var start_scenario: SCENARIO

var _spawned := false


func _ready() -> void:
	add_to_group(BootstrapContext.SERVICE_CONSUMER_GROUP)


func _on_bootstrap_context_ready(context: BootstrapContext) -> void:
	if _spawned:
		return
	var root_scene := _get_root_scene()
	if root_scene == null or context.root_scene != root_scene:
		return
	var party_root := _get_party_root(root_scene)
	var party_manager := root_scene.get_node_or_null("PartyManager") as PartyManager
	var population := context.require(PopulationController.SERVICE_ID) as PopulationController
	var gecs := context.require(GecsWorldController.SERVICE_ID) as GecsWorldController
	var player_party := context.require(&"player_party")
	if party_root == null or party_manager == null or population == null or gecs == null or player_party == null:
		return
	var world_root := root_scene
	while world_root != null and not (world_root is WorldRoot):
		world_root = world_root.get_parent()
	var scenario: SCENARIO = world_root.get_start_scenario() if world_root != null else start_scenario
	var anchor := (world_root if world_root != null else root_scene) as Node3D
	player_party.start_scenario(scenario, anchor.global_transform)
	_spawned = true
	gecs.world_reindexed.connect(_restore_saved_party.bind(context))
	_restore_saved_party(context)


func _restore_saved_party(context: BootstrapContext) -> void:
	var party_root := _get_party_root(context.root_scene)
	var party_manager := context.root_scene.get_node("PartyManager") as PartyManager
	var realizer := context.require(PopulationCharacterRealizer.SERVICE_ID) as PopulationCharacterRealizer
	var gecs := context.require(GecsWorldController.SERVICE_ID) as GecsWorldController
	# One startup/load snapshot, never a per-frame population scan. The saved
	# population, not the scenario resource, decides which bodies are required.
	var records := gecs.get_population_records()
	var existing := {}
	for member in party_manager.party_members.duplicate():
		var record: Dictionary = records.get(member.stable_id, {})
		if str(record.get("party_id", "")) != PartyManager.PLAYER_PARTY_ID:
			party_manager.unregister_party_member(member)
		else:
			existing[member.stable_id] = member
	var spawned_members: Array[WorldActor] = []
	for record in records.values():
		if str(record.get("party_id", "")) != PartyManager.PLAYER_PARTY_ID or int(record.get("life_state", NpcRules.LifeState.ALIVE)) == NpcRules.LifeState.DEAD:
			continue
		if existing.has(str(record["actor_id"])):
			continue
		var member := realizer.realize_record_actor(str(record["actor_id"]), party_root, _node_name_for_actor_id(str(record["actor_id"]))) as WorldActor
		if member != null:
			gecs.register_actor(member)
			spawned_members.append(member)
	if not spawned_members.is_empty() and party_manager.selected_members.is_empty():
		party_manager.select_only(spawned_members[0])


func _get_party_root(root_scene: Node) -> Node3D:
	var parent_node := get_parent() as Node3D
	if parent_node != null and parent_node.name == "PartyMembers":
		return parent_node
	var party_root := root_scene.get_node_or_null("PartyMembers") as Node3D
	return party_root


func _get_root_scene() -> Node:
	var parent_node := get_parent()
	if parent_node != null and parent_node.get_parent() != null:
		return parent_node.get_parent()
	return get_tree().current_scene if is_inside_tree() else null


func _node_name_for_actor_id(actor_id: String) -> String:
	var node_name := ""
	var capitalize_next := true
	for index in range(actor_id.length()):
		var character := actor_id.substr(index, 1)
		if (character >= "a" and character <= "z") or (character >= "A" and character <= "Z") or (character >= "0" and character <= "9"):
			node_name += character.to_upper() if capitalize_next else character
			capitalize_next = false
		else:
			capitalize_next = true
	return node_name if not node_name.is_empty() else "Character"
