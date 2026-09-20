extends RefCounted

## Test-side orchestration of current public population/assignment APIs.
## Never synthesize staff bodies at historical NodePaths.
static func staff(tree: SceneTree, settlement_id: String, owner_id: String, role_id: String, seconds := 8.0) -> HumanoidCharacter:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < deadline:
		var settlements := BootstrapContext.service(SettlementController.SERVICE_ID) as SettlementController
		var population := BootstrapContext.service(PopulationController.SERVICE_ID) as PopulationController
		if settlements != null and population != null:
			for slot in settlements.get_assignment_slots_for_realization(settlement_id):
				if str(slot.get("role_id", "")) != role_id or (str(slot.get("owner_id", "")) != owner_id and str(slot.get("facility_id", "")) != owner_id):
					continue
				var actor_id := str(slot.get("occupant_actor_id", ""))
				if actor_id.is_empty():
					continue
				settlements.realize_assignment_slot(settlement_id, str(slot.get("assignment_domain", "employment")), str(slot.get("slot_id", "")))
				var actor := population.get_live_actor(actor_id) as HumanoidCharacter
				if is_instance_valid(actor) and actor.is_inside_tree():
					return actor
		await tree.physics_frame
	var settlements := BootstrapContext.service(SettlementController.SERVICE_ID) as SettlementController
	print("STAFF_REALIZATION_MISSING settlement=%s owner=%s role=%s slots=%s" % [settlement_id, owner_id, role_id, JSON.stringify(settlements.get_assignment_slots(settlement_id, "employment")) if settlements != null else "no service"])
	return null

## Await actual bootstrap/navigation ownership, not an arbitrary sleep.
static func wait_world_ready(tree: SceneTree, max_frames := 1800) -> bool:
	for _frame in range(max_frames):
		await tree.physics_frame
		var navigation := BootstrapContext.service(WorldNavigationController.SERVICE_ID) as WorldNavigationController
		var time := BootstrapContext.service(WorldTimeController.SERVICE_ID) as WorldTimeController
		if navigation != null and time != null and navigation.get("_mode") != WorldNavigationController.Mode.INACTIVE and not navigation.is_initial_navigation_pending() and not time.is_world_paused():
			return true
	return false


static func reset_order(actor: WorldActor) -> void:
	if not is_instance_valid(actor):
		return
	actor.get_interaction().begin_combat_order()
	actor.stop_movement()
	actor.clear_all_personal_hostility()

static func is_law_response(responder: WorldActor, target: WorldActor) -> bool:
	if not is_instance_valid(responder) or not is_instance_valid(target):
		return false
	var responses := BootstrapContext.service(GameCombatResponseSystem.SERVICE_ID) as GameCombatResponseSystem
	if responses == null:
		return false
	return responses.is_law_enforcement_pair(responder.stable_id, target.stable_id)

static func defense_threat_actor_ids(responses: GameCombatResponseSystem, target_actor_id: String) -> PackedStringArray:
	var result := PackedStringArray()
	if responses == null:
		return result
	for intent in responses.get_active_intents():
		if str(intent.target_actor_id) != target_actor_id or int(intent.kind) not in [CGameCombatResponseIntent.Kind.PRIVATE_DEFENSE, CGameCombatResponseIntent.Kind.LAW_ENFORCEMENT]:
			continue
		var responder_id := str(intent.responder_actor_id)
		if not result.has(responder_id):
			result.append(responder_id)
	return result

static func inventory_snapshot(inventory: InventoryData) -> Dictionary:
	var items: Array = []
	for entry in inventory.entries:
		items.append({"stack_id": entry.stack_id, "definition": entry.definition, "grid_position": entry.grid_position, "count": entry.count, "contained_item_counts": entry.contained_item_counts.duplicate(true), "metadata": entry.metadata.duplicate(true)})
	return {"items": items, "next_stack_sequence": inventory.next_stack_sequence}

static func release_world(world: Node, tree: SceneTree) -> void:
	if not is_instance_valid(world):
		return
	# Release projections while their owners and transforms still exist, then free
	# the scene. This is orderly fixture teardown, not a simulated LOD round-trip.
	var settlements := BootstrapContext.service(SettlementController.SERVICE_ID) as SettlementController
	if settlements != null:
		for state in settlements.get_all_settlement_states():
			var anchor := settlements.get_settlement_anchor(str(state.get("settlement_id", "")))
			if is_instance_valid(anchor) and world.is_ancestor_of(anchor):
				settlements.unregister_settlement_anchor(anchor)
	var context := BootstrapContext.active
	world.queue_free()
	# A process-frame signal may occur before this frame's deletion flush.
	# Do not initialize the next normal world while the old one is exiting.
	while is_instance_valid(world):
		await tree.process_frame
	if BootstrapContext.active == context:
		BootstrapContext.active = null
