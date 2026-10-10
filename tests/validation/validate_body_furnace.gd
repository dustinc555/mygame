extends "res://tests/validation/test_case.gd"

const BODY_FURNACE_SCENE := preload("res://features/world/bridge/props/body_furnace.tscn")
const FACTION_HUMANOID_SCRIPT := preload("res://features/actors/projection/humanoid/faction_humanoid.gd")
const RUSTDEAD_HUMANOID_SCRIPT := preload("res://features/actors/projection/rustdead/rustdead_humanoid_character.gd")
const GECS_WORLD_CONTROLLER_SCRIPT := preload("res://features/core/gecs_world_controller.gd")
const POPULATION_CONTROLLER_SCRIPT := preload("res://features/world_sim/sim/population/population_controller.gd")
const CINDER_FLASK := preload("res://features/inventory/resources/items/cinder_flask.tres")

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	await _validate_manual_flask_conservation()
	await _validate_flask_observer_atomicity()
	await _validate_furnace_acceptance_and_removal()
	await _validate_furnace_projection_loss()
	if _failures.is_empty():
		print("BODY_FURNACE_OK")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	print("BODY_FURNACE_FAILED count=%d" % _failures.size())
	quit(1)


func _validate_manual_flask_conservation() -> void:
	var scene := Node3D.new()
	root.add_child(scene)
	var actor := _add_humanoid(scene, "ManualBurner", Vector3.ZERO)
	var target := _add_rustdead(scene, "ManualBody", Vector3(0.6, 0.0, 0.0))
	await _wait_frames(3)
	actor.assign_finish_off_target(target, true)
	if actor.get_interaction().current_finish_off_target != null:
		_fail("Standing Rustdead must refuse a finish-off order")
	target.force_unconscious()
	actor.assign_finish_off_target(target, true)
	actor.get_interaction().try_complete_finish_off_interaction()
	if target.life_state == NpcRules.LifeState.DEAD or actor.inventory.count_item(CINDER_FLASK) != 0:
		_fail("No-flask manual Burn must leave target and inventory unchanged")
	actor.inventory.add_item_count(CINDER_FLASK, 2)
	actor.global_position = Vector3(20, 0, 0)
	actor.assign_finish_off_target(target, true)
	if actor.get_interaction().try_complete_finish_off_interaction() or actor.inventory.count_item(CINDER_FLASK) != 2:
		_fail("Out-of-reach manual Burn must refuse without consuming a flask")
	actor.get_interaction().process_finish_off_interaction()
	if actor.get_interaction().current_finish_off_target != target:
		_fail("Out-of-reach Burn must retain its exact target while approaching, not cancel through a missing actor hook")
	actor.global_position = target.get_follow_anchor_position()
	actor.assign_finish_off_target(target, true)
	actor.get_interaction().try_complete_finish_off_interaction()
	if target.life_state != NpcRules.LifeState.DEAD:
		_fail("Real finish-off interaction must start cinder death")
	if actor.inventory.count_item(CINDER_FLASK) != 1:
		_fail("Real finish-off interaction must debit exactly one carried flask")
	actor.assign_finish_off_target(target, true)
	actor.get_interaction().try_complete_finish_off_interaction()
	if actor.inventory.count_item(CINDER_FLASK) != 1:
		_fail("Duplicate Burn must not debit a second flask")
	scene.queue_free()
	await _wait_frames(3)


func _validate_flask_observer_atomicity() -> void:
	var scene := Node3D.new()
	root.add_child(scene)
	var actor := _add_humanoid(scene, "ObservedBurner", Vector3.ZERO)
	var body := _add_rustdead(scene, "ObservedBody", Vector3(0.6, 0, 0))
	await _wait_frames(3)
	body.force_unconscious()
	var payload := {"stolen": true, "origin": "distinct-cinder", "nested": {"quality": 17}}
	actor.inventory.add_entry_with_contents(CINDER_FLASK, 1, {}, payload, "distinct-flask")
	var entry = actor.inventory.entries.back()
	var position_before: Vector2i = entry.grid_position
	actor.global_position = body.get_follow_anchor_position()
	var seen := {"notifications": 0, "uncommitted_debit": false}
	# A real synchronous observer used to invalidate the target BETWEEN debit
	# and ignition. Refusal must retain the exact entry, not a generic refund.
	actor.inventory.changed.connect(func() -> void:
		seen.notifications += 1
		if is_instance_valid(body) and body.life_state != NpcRules.LifeState.DEAD:
			seen.uncommitted_debit = true
			body.queue_free()
	)
	var disposal = preload("res://features/actors/projection/rustdead/rustdead_disposal.gd").new()
	var burned: bool = disposal.burn(actor.get_interaction(), body, false)
	if not burned:
		_fail("In-range real flask transaction must commit before notifying its observer")
	if seen.uncommitted_debit:
		_fail("Flask observers must never see a debit before fire commits; callback invalidated target")
	if not burned and (not actor.inventory.entries.has(entry) or entry.count != 1 \
			or entry.stack_id != "distinct-flask" or entry.metadata != payload or entry.grid_position != position_before):
		_fail("Refused fire must preserve exact distinctive flask identity/grid/metadata")
	if burned and (actor.inventory.count_item(CINDER_FLASK) != 0 or seen.notifications != 1):
		_fail("Committed fire must publish exactly one debit")
	scene.queue_free()
	await _wait_frames(3)


func _validate_furnace_acceptance_and_removal() -> void:
	var scene := Node3D.new()
	root.add_child(scene)
	_add_population_controllers(scene)
	var carrier := _add_humanoid(scene, "Carrier", Vector3.ZERO)
	var rustdead := _add_rustdead(scene, "FurnaceRustdead", Vector3(0.6, 0.0, 0.0))
	var human := _add_humanoid(scene, "HumanBody", Vector3(1.2, 0.0, 0.0))
	var furnace := BODY_FURNACE_SCENE.instantiate()
	scene.add_child(furnace)
	furnace.set("burn_seconds", 0.05)
	await _wait_frames(6)
	rustdead.force_kill(carrier)
	human.force_unconscious()
	await _wait_frames(3)
	if not bool(furnace.call("can_accept_body", rustdead)):
		_fail("Furnace should accept unconscious Rustdead")
	if bool(furnace.call("can_accept_body", human)):
		_fail("Furnace should reject unconscious non-Rustdead humanoids")
	human.force_kill(carrier)
	await _wait_frames(2)
	if not bool(furnace.call("can_accept_body", human)):
		_fail("Furnace should accept dead non-Rustdead humanoids")
	rustdead.inventory.add_item_count(CINDER_FLASK, 1)
	var population := scene.get_node("PopulationController")
	var record: Dictionary = population.call("register_actor", rustdead, "test_town", {"role_id": "corpse"})
	var actor_id := str(record.get("actor_id", ""))
	carrier.call("_attach_carried_character", rustdead)
	if furnace.call("get_world_context_actions", carrier).is_empty():
		_fail("Furnace should expose Place in while carrying a valid body")
	carrier.assign_place_carried_in_furnace_target(furnace, false)
	carrier.global_position = furnace.call("get_interaction_position", carrier)
	carrier.get_interaction().process_place_in_furnace_interaction()
	await create_timer(0.12).timeout
	if is_instance_valid(rustdead) and rustdead.is_inside_tree():
		_fail("Furnace burn should remove the placed body")
	var cremated_record: Dictionary = population.call("get_actor_record", actor_id) if not actor_id.is_empty() else {}
	if cremated_record.is_empty() or str(cremated_record.get("body_state", "")) != "cremated":
		_fail("Furnace burn should retain the person and mark their body cremated")
	if population.call("get_live_actor", actor_id) != null:
		_fail("Furnace burn should unregister the destroyed body projection")
	if not cremated_record.get("inventory_entries", []).is_empty() or not cremated_record.get("equipment_slots", {}).is_empty():
		_fail("Cremation must destroy contents after unregister snapshots the body")
	if int(cremated_record.get("life_state", -1)) != NpcRules.LifeState.DEAD:
		_fail("Cremated Rustdead must be durably dead, never a living ledger person")
	scene.queue_free()
	await _wait_frames(3)


func _validate_furnace_projection_loss() -> void:
	for destroy_furnace in [false, true]:
		var scene := Node3D.new()
		root.add_child(scene)
		_add_population_controllers(scene)
		var carrier := _add_humanoid(scene, "LodCarrier", Vector3.ZERO)
		var body := _add_rustdead(scene, "LodBody", Vector3.ZERO)
		var furnace := BODY_FURNACE_SCENE.instantiate()
		furnace.burn_seconds = 0.05
		scene.add_child(furnace)
		await _wait_frames(3)
		body.force_unconscious()
		body.inventory.add_item_count(CINDER_FLASK, 1)
		var population := scene.get_node("PopulationController")
		var record: Dictionary = population.register_actor(body, "test_town")
		var actor_id := str(record.get("actor_id", ""))
		if not furnace.place_carried_body(carrier, body):
			_fail("LOD regression must start the production furnace timer")
		if destroy_furnace:
			furnace.queue_free()
		else:
			population.unregister_actor(body)
			body.queue_free()
		await create_timer(0.12).timeout
		var after: Dictionary = population.get_actor_record(actor_id)
		if after.get("body_state", "") != "cremated" or int(after.get("life_state", -1)) != NpcRules.LifeState.DEAD:
			_fail("Furnace commit must survive projection loss (furnace=%s)" % destroy_furnace)
		if not after.get("inventory_entries", []).is_empty():
			_fail("Furnace LOD must not resurrect disposed inventory")
		if is_instance_valid(body):
			_fail("Removing a burning furnace must not strand its accepted body")
		scene.queue_free()
		await _wait_frames(3)


func _add_population_controllers(scene: Node) -> void:
	if scene.has_node("GecsWorldController"):
		return
	var ground := StaticBody3D.new()
	ground.name = "TestGround"
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(64, 0.2, 64)
	collision.shape = shape
	ground.add_child(collision)
	ground.position.y = -0.1
	scene.add_child(ground)
	var context := BootstrapContext.new(scene)
	BootstrapContext.active = context
	scene.tree_exiting.connect(func() -> void:
		if BootstrapContext.active == context:
			BootstrapContext.active = null
	)
	var gecs = GECS_WORLD_CONTROLLER_SCRIPT.new()
	gecs.name = "GecsWorldController"
	scene.add_child(gecs)
	context.register(gecs.SERVICE_ID, gecs)
	gecs.initialize(context)
	var population = POPULATION_CONTROLLER_SCRIPT.new()
	population.name = "PopulationController"
	scene.add_child(population)
	population.initialize(context)
	context.register(population.SERVICE_ID, population)
	var query := ActorQueryController.new()
	query.name = "ActorQueryController"
	scene.add_child(query)
	context.register(query.SERVICE_ID, query)
	query.initialize(context)


func _add_humanoid(scene: Node, actor_name: String, position: Vector3) -> HumanoidCharacter:
	_add_population_controllers(scene)
	var actor: HumanoidCharacter = FACTION_HUMANOID_SCRIPT.new()
	actor.name = actor_name
	actor.stable_id = actor_name
	actor.position = position
	actor.faction_name = "TownGuard"
	scene.add_child(actor)
	return actor


func _add_rustdead(scene: Node, actor_name: String, position: Vector3) -> HumanoidCharacter:
	_add_population_controllers(scene)
	var actor: HumanoidCharacter = RUSTDEAD_HUMANOID_SCRIPT.new()
	actor.name = actor_name
	actor.stable_id = actor_name
	actor.position = position
	actor.faction_name = "Rustdead"
	scene.add_child(actor)
	return actor


func _wait_frames(count: int) -> void:
	for _index in range(count):
		await process_frame


func _fail(message: String) -> void:
	_failures.append(message)
	print("DISPOSAL_CHECK: " + message)
