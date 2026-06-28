extends SceneTree

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
	await _validate_furnace_acceptance_and_removal()
	await _validate_auto_flask_without_furnace()
	await _validate_auto_furnace_priority()
	await _validate_auto_no_resource_backoff()
	await _validate_auto_combat_hold()
	if _failures.is_empty():
		print("BODY_FURNACE_AUTO_BURN_OK")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	print("BODY_FURNACE_AUTO_BURN_FAILED count=%d" % _failures.size())
	quit(1)


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
	var population := scene.get_node("PopulationController")
	var record: Dictionary = population.call("register_actor", rustdead, "test_town", {"role_id": "corpse"})
	var actor_id := str(record.get("actor_id", ""))
	carrier.call("_attach_carried_character", rustdead)
	if furnace.call("get_world_context_actions", carrier).is_empty():
		_fail("Furnace should expose Place in while carrying a valid body")
	carrier.assign_place_carried_in_furnace_target(furnace, false)
	carrier.global_position = furnace.call("get_interaction_position", carrier)
	carrier.call("_process_place_in_furnace_interaction")
	await _wait_frames(12)
	if is_instance_valid(rustdead) and rustdead.is_inside_tree():
		_fail("Furnace burn should remove the placed body")
	if not actor_id.is_empty() and not (population.call("get_actor_record", actor_id) as Dictionary).is_empty():
		_fail("Furnace burn should remove the body population record")
	scene.queue_free()
	await _wait_frames(3)


func _validate_auto_flask_without_furnace() -> void:
	var scene := Node3D.new()
	root.add_child(scene)
	var actor := _add_humanoid(scene, "FlaskGuard", Vector3.ZERO)
	var rustdead := _add_rustdead(scene, "FlaskRustdead", Vector3(0.75, 0.0, 0.0))
	await _wait_frames(6)
	actor.auto_burn_rustdead_enabled = true
	actor.inventory.add_item_count(CINDER_FLASK, 1)
	rustdead.force_kill(actor)
	await _wait_frames(3)
	var before_flasks := actor.inventory.count_item(CINDER_FLASK)
	if not bool(actor.call("_try_assign_auto_burn_action")):
		_fail("Auto Burn Rustdead should assign Cinder Flask burn when no furnace is accessible")
	actor.global_position = rustdead.global_position
	actor.call("_try_complete_finish_off_interaction", 10.0)
	await _wait_frames(3)
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
	actor.auto_burn_rustdead_enabled = true
	actor.auto_burn_furnace_access_radius = 8.0
	actor.inventory.add_item_count(CINDER_FLASK, 1)
	rustdead.force_kill(actor)
	await _wait_frames(3)
	var before_flasks := actor.inventory.count_item(CINDER_FLASK)
	if not bool(actor.call("_try_assign_auto_burn_action")):
		_fail("Auto Burn Rustdead should assign furnace carry when a furnace is accessible")
	if actor.get("_current_carry_target") != rustdead:
		_fail("Accessible furnace should be preferred over Cinder Flask")
	actor.global_position = rustdead.global_position
	actor.call("_process_carry_interaction")
	if actor.get_carried_character() != rustdead:
		_fail("Auto furnace path should pick up the Rustdead body")
	actor.call("_try_assign_auto_burn_action")
	if actor.get("_current_place_furnace_target") != furnace:
		_fail("Auto furnace path should route carried body to the reserved furnace")
	actor.global_position = furnace.call("get_interaction_position", actor)
	actor.call("_process_place_in_furnace_interaction")
	await _wait_frames(12)
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
	actor.auto_burn_rustdead_enabled = true
	rustdead.force_kill(actor)
	await _wait_frames(3)
	if bool(actor.call("_try_assign_auto_burn_action")):
		_fail("Auto Burn Rustdead should not assign work without furnace access or Cinder Flask")
	if actor.get("_current_carry_target") != null or actor.get("_current_finish_off_target") != null:
		_fail("No-resource auto burn should not clog carry or finish-off assignments")
	if rustdead.has_meta("auto_burn_reserved_by_instance_id"):
		_fail("No-resource auto burn should not reserve downed Rustdead targets")
	scene.queue_free()
	await _wait_frames(3)


func _validate_auto_combat_hold() -> void:
	var scene := Node3D.new()
	root.add_child(scene)
	var actor := _add_humanoid(scene, "CombatGuard", Vector3.ZERO)
	var enemy := _add_humanoid(scene, "Enemy", Vector3(1.4, 0.0, 0.0))
	var rustdead := _add_rustdead(scene, "CombatIgnoredRustdead", Vector3(0.75, 0.0, 0.0))
	await _wait_frames(6)
	actor.auto_burn_rustdead_enabled = true
	actor.inventory.add_item_count(CINDER_FLASK, 1)
	rustdead.force_kill(actor)
	actor.mark_hostile(enemy)
	if not actor.assign_attack_target(enemy, false):
		actor.set("_current_order_type", HumanoidCharacter.OrderType.ATTACK)
		actor.set("_current_attack_target", enemy)
	await _wait_frames(2)
	if bool(actor.call("_try_assign_auto_burn_action")):
		_fail("Auto Burn Rustdead should not interrupt combat")
	if actor.get("_current_finish_off_target") == rustdead or actor.get("_current_carry_target") == rustdead:
		_fail("Combating actors should not assign burn/carry work")
	scene.queue_free()
	await _wait_frames(3)


func _add_population_controllers(scene: Node) -> void:
	var context := BootstrapContext.new(scene)
	var gecs = GECS_WORLD_CONTROLLER_SCRIPT.new()
	gecs.name = "GecsWorldController"
	scene.add_child(gecs)
	context.register(gecs.SERVICE_ID, gecs)
	gecs.initialize(context)
	var population = POPULATION_CONTROLLER_SCRIPT.new()
	population.name = "PopulationController"
	scene.add_child(population)
	population.initialize(context)


func _add_humanoid(scene: Node, actor_name: String, position: Vector3) -> HumanoidCharacter:
	var actor: HumanoidCharacter = FACTION_HUMANOID_SCRIPT.new()
	actor.name = actor_name
	actor.position = position
	actor.faction_name = "TownGuard"
	scene.add_child(actor)
	return actor


func _add_rustdead(scene: Node, actor_name: String, position: Vector3) -> HumanoidCharacter:
	var actor: HumanoidCharacter = RUSTDEAD_HUMANOID_SCRIPT.new()
	actor.name = actor_name
	actor.position = position
	actor.faction_name = "Rustdead"
	scene.add_child(actor)
	return actor


func _wait_frames(count: int) -> void:
	for _index in range(count):
		await process_frame


func _fail(message: String) -> void:
	_failures.append(message)
