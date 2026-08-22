extends SceneTree
## Run: godot --headless --path . --script res://tools/validation/validate_bulk_deposit_all.gd

const PLATFORM_PATH := "res://features/world/projection/containers/bulk_storage_platform.tscn"
const TOMATO := preload("res://features/inventory/resources/items/tomato.tres")
const EGGPLANT := preload("res://features/inventory/resources/items/eggplant.tres")

var failures: Array[String] = []
var _ecs_placeholder: Node


class ActorFixture:
	extends Node3D
	var faction_name := "Market Ward"
	var inventory := InventoryData.new(10, 4, 60.0, true)
	var assigned_container

	func assign_open_container(container, _issued_by_player := true) -> void:
		assigned_container = container


class InteractionActorFixture:
	extends Node3D
	var move_target := Vector3.ZERO

	func _set_actor_move_target(target: Vector3) -> void:
		move_target = target

	func _clear_actor_move_target() -> void:
		move_target = Vector3.ZERO


class ContainerFixture:
	extends Node3D
	var register_count := 0
	var release_count := 0

	func get_interaction_position(_actor) -> Vector3:
		return global_position

	func register_interactor(_actor) -> void:
		register_count += 1

	func release_interactor(_actor) -> void:
		release_count += 1


func _initialize() -> void:
	if not Engine.has_singleton("ECS"):
		_ecs_placeholder = Node.new()
		Engine.register_singleton("ECS", _ecs_placeholder)
	call_deferred("_run")


func _run() -> void:
	var interaction_source := FileAccess.get_file_as_string("res://features/world/bridge/world_interaction_controller.gd")
	_expect(interaction_source.find("Deposited %d") < 0 and interaction_source.find("Nothing deposited") < 0, "Deposit All completion never spawns animated world text")
	var scene := load(PLATFORM_PATH) as PackedScene
	var holder := Node3D.new()
	root.add_child(holder)
	var platform = scene.instantiate() if scene != null else null
	_expect(platform != null, "bulk platform loads")
	if platform == null:
		_finish()
		return
	platform.container_id = "validation.bulk_deposit_all"
	platform.owner_faction_name = "Player"
	holder.add_child(platform)
	var actor := ActorFixture.new()
	holder.add_child(actor)
	await process_frame

	_expect(platform.has_method("get_world_context_actions"), "platform exposes deposit actions to ordinary right-click context")
	_expect(platform.has_method("perform_world_context_action"), "platform dispatches deposit context actions")
	_expect(platform.has_method("resolve_pending_deposit"), "platform resolves deposit only after actor reaches it")
	if not platform.has_method("get_world_context_actions") or not platform.has_method("perform_world_context_action") or not platform.has_method("resolve_pending_deposit"):
		holder.free()
		_finish()
		return

	_expect(actor.inventory.add_item_count(EGGPLANT, 7), "foreign actor carries seven individual eggplants")
	_expect(platform.deposit_item_count(EGGPLANT, 50), "platform starts as an eggplant platform")
	var actions: Array = platform.get_world_context_actions(actor)
	_expect(actions.size() == 1 and str(actions[0].get("label", "")) == "Deposit All Eggplants", "right-click offers Deposit All Eggplants when actor and platform share eggplants")
	_expect(not actions.is_empty() and str(actions[0].get("key", "")).begins_with("deposit_all|"), "deposit action carries exact actor and item identity")
	if not actions.is_empty():
		platform.perform_world_context_action(str(actions[0].get("key", "")), [actor])
	_expect(actor.assigned_container == platform and actor.inventory.count_item(EGGPLANT) == 7 and platform.get_stored_item_count(EGGPLANT) == 50, "choosing Deposit All assigns travel without teleporting inventory")
	var result: Dictionary = platform.resolve_pending_deposit(actor)
	_expect(bool(result.get("handled", false)) and int(result.get("amount", 0)) == 7, "arrival resolves the pending deposit transaction")
	_expect(actor.inventory.count_item(EGGPLANT) == 0 and platform.get_stored_item_count(EGGPLANT) == 57, "arrival transfers every carried eggplant into the platform stack")
	_expect(platform.owner_faction_name == "Player" and actor.faction_name == "Market Ward", "deposit availability is independent of platform ownership")

	platform.withdraw_item_count(EGGPLANT, 57)
	var stolen_metadata := {"stolen": true, "stolen_from_faction_id": "Orchard Guild"}
	_expect(actor.inventory.add_item_count_with_metadata(EGGPLANT, 2, stolen_metadata), "actor can carry metadata-bearing eggplants")
	actions = platform.get_world_context_actions(actor)
	if not actions.is_empty():
		platform.perform_world_context_action(str(actions[0].get("key", "")), [actor])
		result = platform.resolve_pending_deposit(actor)
	var metadata_entry = platform.inventory.entries[0] if not platform.inventory.entries.is_empty() else null
	_expect(int(result.get("amount", 0)) == 2 and metadata_entry != null and bool(metadata_entry.metadata.get("stolen", false)), "Deposit All preserves item ownership and theft metadata")
	_expect(platform.release_inventory_entry(metadata_entry, actor.inventory), "metadata-bearing platform item can be withdrawn")
	var restored_metadata := false
	for entry in actor.inventory.entries:
		if entry.definition == EGGPLANT and bool(entry.metadata.get("stolen", false)):
			restored_metadata = true
			break
	_expect(restored_metadata, "withdrawal restores ownership and theft metadata to the individual item")
	actor.inventory.remove_item_count(EGGPLANT, actor.inventory.count_item(EGGPLANT))
	platform.withdraw_item_count(EGGPLANT, platform.get_stored_item_count(EGGPLANT))
	_expect(actor.inventory.add_item_count_with_metadata(EGGPLANT, 31, stolen_metadata), "actor carries thirty-one equal-metadata individual eggplants")
	actions = platform.get_world_context_actions(actor)
	if not actions.is_empty():
		platform.perform_world_context_action(str(actions[0].get("key", "")), [actor])
		result = platform.resolve_pending_deposit(actor)
	await process_frame
	_expect(int(result.get("amount", 0)) == 31 and platform.get_stored_item_count(EGGPLANT) == 31 \
			and platform.inventory.entries.size() == 3 and platform.get_displayed_visual_count() == 3, "31 equal-metadata eggplants form three stacks and exactly three crates at 12 per crate")
	_expect(platform.inventory.entries[0].count == 12 and platform.inventory.entries[1].count == 12 \
			and platform.inventory.entries[2].count == 7, "each eggplant stack represents one bounded physical crate")
	actor.inventory.remove_item_count(EGGPLANT, actor.inventory.count_item(EGGPLANT))
	platform.withdraw_item_count(EGGPLANT, platform.get_stored_item_count(EGGPLANT))
	platform.deposit_item_count(EGGPLANT, 5)
	var clean_stack = platform.inventory.entries[0]
	_expect(platform.release_inventory_entry_with_metadata(clean_stack, actor.inventory, stolen_metadata), "one stolen withdrawal can leave a clean partial crate behind")
	var withdrawn_stolen := false
	for entry in actor.inventory.entries:
		if entry.definition == EGGPLANT and bool(entry.metadata.get("stolen", false)):
			withdrawn_stolen = true
	_expect(withdrawn_stolen and clean_stack.count == 4 and clean_stack.metadata.is_empty(), "the withdrawn unit becomes stolen without tainting the remaining four items in its crate stack")
	actor.inventory.remove_item_count(EGGPLANT, actor.inventory.count_item(EGGPLANT))
	platform.withdraw_item_count(EGGPLANT, platform.get_stored_item_count(EGGPLANT))

	var no_match := ActorFixture.new()
	holder.add_child(no_match)
	no_match.inventory.add_item_count(TOMATO, 1)
	platform.deposit_item_count(EGGPLANT, 1)
	_expect(platform.get_world_context_actions(no_match).is_empty(), "platform offers no deposit action when actor lacks its stored item")

	platform.withdraw_item_count(EGGPLANT, 1)
	platform.deposit_item_count(EGGPLANT, 358)
	actor.inventory.add_item_count(EGGPLANT, 7)
	actions = platform.get_world_context_actions(actor)
	if not actions.is_empty():
		platform.perform_world_context_action(str(actions[0].get("key", "")), [actor])
		result = platform.resolve_pending_deposit(actor)
	_expect(int(result.get("amount", 0)) == 2 and actor.inventory.count_item(EGGPLANT) == 5 \
			and platform.get_stored_item_count(EGGPLANT) == 360, "Deposit All transfers only the amount that fits and leaves the remainder with the actor")
	platform.withdraw_item_count(EGGPLANT, 360)
	platform.deposit_item_count(TOMATO, 899)
	var source_inventory := InventoryData.new(2, 2, 0.0, false)
	source_inventory.add_item_count(TOMATO, 1)
	var incoming_tomato = source_inventory.entries[0]
	_expect(platform.can_receive_inventory_entry(incoming_tomato), "clean final tomato can fill the last partial crate")
	_expect(not platform.can_receive_inventory_entry_with_metadata(incoming_tomato, stolen_metadata), "stolen metadata preflight rejects a transfer that would require a thirty-first crate slot")
	platform.withdraw_item_count(TOMATO, 899)

	var interaction_actor := InteractionActorFixture.new()
	var interaction_script := load("res://features/actors/bridge/capabilities/interaction_capability.gd") as Script
	_expect(interaction_script != null, "interaction capability loads for replacement-order regression")
	var interaction = interaction_script.new() if interaction_script != null else null
	if interaction == null:
		holder.free()
		_finish()
		return
	interaction.setup(interaction_actor)
	var replacement_container := ContainerFixture.new()
	holder.add_child(interaction_actor)
	holder.add_child(replacement_container)
	interaction.assign_open_container(replacement_container)
	interaction.assign_open_container(replacement_container)
	_expect(replacement_container.register_count == 2 and replacement_container.release_count == 1, "reissuing Open on the same container releases the pending interaction before replacement")
	interaction.teardown()

	holder.free()
	_finish()


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _finish() -> void:
	if _ecs_placeholder != null:
		Engine.unregister_singleton("ECS")
		_ecs_placeholder.free()
	if failures.is_empty():
		print("BULK_DEPOSIT_ALL_OK")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("BULK_DEPOSIT_ALL_FAILED count=%d" % failures.size())
	quit(1)
