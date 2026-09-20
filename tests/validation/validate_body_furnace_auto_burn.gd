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
	var interaction := InteractionCapability.new()
	if interaction.has_method("try_assign_auto_burn_action"):
		await _validate_auto_flask_without_furnace()
		await _validate_auto_furnace_priority()
		await _validate_auto_no_resource_backoff()
		await _validate_auto_combat_hold()
		await _validate_idle_and_inventory_wakeup()
		await _validate_manual_order_hold()
		await _validate_auto_projection_loss()
	else:
		_fail("Advertised Auto Burn setting must assign disposal through InteractionCapability")
	if _failures.is_empty():
		print("BODY_FURNACE_AUTO_BURN_OK")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	print("BODY_FURNACE_AUTO_BURN_FAILED count=%d" % _failures.size())
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


func _validate_auto_flask_without_furnace() -> void:
	var scene := Node3D.new()
	root.add_child(scene)
	var actor := _add_humanoid(scene, "FlaskGuard", Vector3.ZERO)
	var rustdead := _add_rustdead(scene, "FlaskRustdead", Vector3(0.75, 0.0, 0.0))
	await _wait_frames(6)
	actor.inventory.add_item_count(CINDER_FLASK, 1)
	rustdead.force_kill(actor)
	var before_flasks := actor.inventory.count_item(CINDER_FLASK)
	actor.set_auto_burn_rustdead_enabled(true)
	# Exercise the setting -> real physics tick -> finish-off path, not a test
	# call to the auto-assignment helper that could exist but never be scheduled.
	for _frame in range(12):
		await physics_frame
		if rustdead.life_state == NpcRules.LifeState.DEAD:
			break
	if rustdead.life_state != NpcRules.LifeState.DEAD:
		_fail("Auto Cinder Flask burn should mark downed Rustdead dead")
	if actor.inventory.count_item(CINDER_FLASK) != before_flasks - 1:
		_fail("Auto Cinder Flask burn should consume one flask")
	scene.queue_free()
	await _wait_frames(3)


func _validate_auto_furnace_priority() -> void:
	var scene := Node3D.new()
	root.add_child(scene)
	var actor := _add_humanoid(scene, "FurnaceGuard", Vector3.ZERO)
	var rustdead := _add_rustdead(scene, "FreeBurnRustdead", Vector3(0.75, 0.0, 0.0))
	var furnace := BODY_FURNACE_SCENE.instantiate()
	furnace.position = Vector3(2.0, 0.0, 0.0)
	scene.add_child(furnace)
	furnace.set("burn_seconds", 0.05)
	await _wait_frames(6)
	actor.inventory.add_item_count(CINDER_FLASK, 1)
	rustdead.force_kill(actor)
	var before_flasks := actor.inventory.count_item(CINDER_FLASK)
	actor.set_auto_burn_rustdead_enabled(true)
	await physics_frame
	await process_frame
	if actor.get_interaction().current_carry_target != rustdead:
		_fail("Accessible furnace should be preferred over Cinder Flask")
	actor.global_position = rustdead.global_position
	actor.get_interaction().process_carry_interaction()
	if actor.get_carried_character() != rustdead:
		_fail("Auto furnace path should pick up the Rustdead body")
	await physics_frame
	await process_frame
	if actor.get_interaction().current_place_furnace_target != furnace:
		_fail("Auto furnace path should route carried body to the reserved furnace")
	actor.global_position = furnace.call("get_interaction_position", actor)
	actor.get_interaction().process_place_in_furnace_interaction()
	await create_timer(0.12).timeout
	if is_instance_valid(rustdead) and rustdead.is_inside_tree():
		_fail("Auto furnace path should remove the Rustdead body after burning")
	if actor.inventory.count_item(CINDER_FLASK) != before_flasks:
		_fail("Auto furnace path should not consume a Cinder Flask")
	scene.queue_free()
	await _wait_frames(3)


func _validate_auto_no_resource_backoff() -> void:
	var scene := Node3D.new()
	root.add_child(scene)
	var actor := _add_humanoid(scene, "NoResourceGuard", Vector3.ZERO)
	var rustdead := _add_rustdead(scene, "IgnoredRustdead", Vector3(0.75, 0.0, 0.0))
	await _wait_frames(6)
	actor.set_auto_burn_rustdead_enabled(true)
	rustdead.force_kill(actor)
	await _wait_frames(3)
	if bool(actor.get_interaction().call("try_assign_auto_burn_action")):
		_fail("Auto Burn Rustdead should not assign work without furnace access or Cinder Flask")
	if actor.get_interaction().current_carry_target != null or actor.get_interaction().current_finish_off_target != null:
		_fail("No-resource auto burn should not clog carry or finish-off assignments")
	if rustdead.has_meta("auto_burn_reserved_by_instance_id"):
		_fail("No-resource auto burn should not reserve downed Rustdead targets")
	scene.queue_free()
	await _wait_frames(3)


func _validate_auto_combat_hold() -> void:
	var scene := Node3D.new()
	root.add_child(scene)
	_add_population_controllers(scene)
	var actor := _add_humanoid(scene, "CombatGuard", Vector3.ZERO)
	var enemy := _add_humanoid(scene, "Enemy", Vector3(1.4, 0.0, 0.0))
	var rustdead := _add_rustdead(scene, "CombatIgnoredRustdead", Vector3(0.75, 0.0, 0.0))
	await _wait_frames(6)
	actor.inventory.add_item_count(CINDER_FLASK, 1)
	rustdead.force_kill(actor)
	var bridge := scene.get_node("GecsWorldController")
	bridge.register_actor(actor)
	bridge.register_actor(enemy)
	actor.mark_hostile(enemy)
	if not actor.assign_attack_target(enemy, false):
		_fail("Combat setup should assign the hostile target")
	var combat_state = bridge.get_actor_entity(actor).get_component(CGameCombatState)
	# Retarget jitter can exceed the old fixed 0.6-second step. Advance the
	# actual scheduled deadline, then require real acquisition before Auto Burn.
	bridge.world.process(float(combat_state.system_target_retarget_remaining) + 0.01)
	if not actor.is_in_combat() or actor.get_current_combat_target() != enemy:
		_fail("Combat hold fixture must acquire a real GECS target before enabling Auto Burn")
	actor.set_auto_burn_rustdead_enabled(true)
	await _wait_frames(2)
	if bool(actor.get_interaction().call("try_assign_auto_burn_action")):
		_fail("Auto Burn Rustdead should not interrupt combat")
	if actor.get_interaction().current_finish_off_target == rustdead or actor.get_interaction().current_carry_target == rustdead:
		_fail("Combating actors should not assign burn/carry work")
	scene.queue_free()
	await _wait_frames(3)


func _validate_auto_projection_loss() -> void:
	for destroy_furnace in [false, true]:
		var scene := Node3D.new()
		root.add_child(scene)
		var actor := _add_humanoid(scene, "ClaimGuard", Vector3.ZERO)
		var target := _add_rustdead(scene, "ClaimBody", Vector3(8, 0, 0))
		var furnace := BODY_FURNACE_SCENE.instantiate()
		scene.add_child(furnace)
		actor.set_physics_process(false)
		await _wait_frames(2)
		target.force_kill(actor)
		actor.set_auto_burn_rustdead_enabled(true)
		if not actor.get_interaction().try_assign_auto_burn_action():
			_fail("LOD fixture must acquire an automatic furnace/body reservation")
		if destroy_furnace:
			furnace.queue_free()
		else:
			target.queue_free()
		await _wait_frames(2)
		actor.set_physics_process(true)
		await physics_frame
		await process_frame
		if actor.get_interaction().current_carry_target != null or actor.get_interaction().current_place_furnace_target != null:
			_fail("Automatic disposal must cancel work whose target/furnace disappeared")
		if is_instance_valid(furnace) and furnace.is_reserved_by(actor):
			_fail("Missing body must release its furnace reservation")
		if is_instance_valid(target) and target.has_meta("auto_burn_reserved_by_instance_id"):
			_fail("Missing furnace must release its body reservation")
		actor.set_physics_process(false)
		if destroy_furnace:
			furnace = BODY_FURNACE_SCENE.instantiate()
			scene.add_child(furnace)
		else:
			target = _add_rustdead(scene, "ClaimBody", Vector3(8, 0, 0))
			target.force_unconscious()
		await _wait_frames(3)
		actor.set_physics_process(true)
		await physics_frame
		await process_frame
		if actor.get_interaction().current_carry_target != target:
			_fail("Recreated body/furnace must wake idle disposal and reacquire work")
		actor.queue_free()
		await _wait_frames(3)
		if target.has_meta("auto_burn_reserved_by_instance_id") or not furnace.is_available_for(null, target):
			_fail("Destroyed worker must release its body claim")
		actor = _add_humanoid(scene, "ClaimGuard", Vector3.ZERO)
		actor.set_auto_burn_rustdead_enabled(true)
		await physics_frame
		await process_frame
		if actor.get_interaction().current_carry_target != target or not furnace.is_reserved_by(actor):
			_fail("Recreated worker identity must reacquire body and furnace")
		scene.queue_free()
		await _wait_frames(3)


func _validate_idle_and_inventory_wakeup() -> void:
	var scene := Node3D.new()
	root.add_child(scene)
	var actor := _add_humanoid(scene, "IdleGuard", Vector3.ZERO)
	var body := _add_rustdead(scene, "IdleBody", Vector3(0.75, 0, 0))
	actor.set_physics_process(false)
	body.force_unconscious()
	actor.set_auto_burn_rustdead_enabled(true)
	await _wait_frames(3)
	var interaction = actor.get_interaction()
	var disposal = interaction.rustdead_disposal
	disposal.tick(interaction)
	var before: int = disposal.assignment_queries
	var start := Time.get_ticks_usec()
	for _frame in range(512):
		disposal.tick(interaction)
	var elapsed := Time.get_ticks_usec() - start
	if disposal.assignment_queries != before:
		_fail("Unchanged idle disposal must not query bodies/furnaces again")
	actor.inventory.add_item_count(CINDER_FLASK, 1)
	disposal.tick(interaction)
	if interaction.current_finish_off_target != body:
		_fail("Inventory availability must wake a resource-starved worker immediately")
	print("DISPOSAL_IDLE ticks=512 additional_queries=%d usec=%d" % [disposal.assignment_queries - before - 1, elapsed])
	scene.queue_free()
	await _wait_frames(3)


func _validate_manual_order_hold() -> void:
	var scene := Node3D.new()
	root.add_child(scene)
	var actor := _add_humanoid(scene, "OrderedGuard", Vector3.ZERO)
	var body := _add_rustdead(scene, "OrderedBody", Vector3(7, 0, 0))
	actor.set_physics_process(false)
	body.force_unconscious()
	actor.inventory.add_item_count(CINDER_FLASK, 1)
	actor.set_auto_burn_rustdead_enabled(true)
	await _wait_frames(3)
	actor.get_interaction().try_assign_auto_burn_action()
	if not body.has_meta("auto_burn_reserved_by_instance_id"):
		_fail("Manual replacement fixture must start with a real body claim")
	actor.assign_carry_target(body, true)
	actor.get_interaction().rustdead_disposal.tick(actor.get_interaction())
	if actor.get_interaction().current_carry_target != body or not actor.has_active_player_order():
		_fail("Automatic disposal cleanup must preserve the newer manual order")
	if body.has_meta("auto_burn_reserved_by_instance_id"):
		_fail("A manual replacement must release the prior automatic reservation")
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
