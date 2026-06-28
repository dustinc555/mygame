extends SceneTree

## Focused sanity check for CarryCapability relationship state.
## Run: godot --headless --path . --script res://tools/validation/validate_carry_capability.gd
##
## Verifies: begin_carry reciprocal state, carried/carrier queries, carry
## eligibility gates, collision suppression/restoration, and drop cleanup.


func _initialize() -> void:
	_run_validation.call_deferred()


func _run_validation() -> void:
	var failures: Array[String] = []

	_validate_carry_state_machine(failures)
	_validate_pose_solver(failures)

	if failures.is_empty():
		print("PASS: CarryCapability state machine + pose solver sane (18 checks)")
		quit(0)
	else:
		for f in failures:
			printerr("FAIL: ", f)
		quit(1)


func _validate_carry_state_machine(failures: Array[String]) -> void:
	var carrier := _make_actor("carrier", "team_a")
	var carried := _make_actor("carried", "team_b")
	var carrier_carry := carrier.get_carry()
	var carried_carry := carried.get_carry()

	_expect(failures, "carrier has carry capability", carrier_carry != null)
	_expect(failures, "carried has carry capability", carried_carry != null)
	if carrier_carry == null or carried_carry == null:
		carrier.free()
		carried.free()
		return

	# Eligibility takes the same-faction verdict as data (the actor facade resolves
	# faction from node properties). false = not same faction, true = same faction.
	_expect(failures, "alive enemy cannot be carried", not carried_carry.can_be_carried_by(false))
	_expect(failures, "alive faction member can be carried", carried_carry.can_be_carried_by(true))

	carried.force_unconscious()
	_expect(failures, "downed enemy can be carried", carried_carry.can_be_carried_by(false))

	var original_collision_layer := carried.collision_layer
	var original_collision_mask := carried.collision_mask
	var started := carrier_carry.begin_carry(carried_carry)
	_expect(failures, "begin_carry succeeds", started)
	_expect(failures, "carrier reports carrying", carrier_carry.is_carrying_someone())
	_expect(failures, "carried reports carried", carried_carry.is_carried())
	_expect(failures, "carrier points at carried", carrier_carry.get_carried_character() == carried)
	_expect(failures, "carried points at carrier", carried_carry.get_carrier() == carrier)
	_expect(failures, "already carried cannot be carried again", not carried_carry.can_be_carried_by(false))
	_expect(failures, "carried collision suppressed", carried.collision_layer == 0 and carried.collision_mask == 0)

	var dropped := carrier_carry.drop()
	_expect(failures, "drop returns carried actor", dropped == carried)
	_expect(failures, "drop clears reciprocal state", not carrier_carry.is_carrying_someone() and not carried_carry.is_carried() and carrier_carry.get_carried_character() == null and carried_carry.get_carrier() == null)
	_expect(failures, "drop restores collision", carried.collision_layer == original_collision_layer and carried.collision_mask == original_collision_mask)

	carrier.free()
	carried.free()


## CarryPoseSolver runs in-game only on the carrier's projection node
## (HumanoidCharacter._physics_process), which the relationship test can't reach
## (bare WorldActor has no body projection). Smoke the no-skeleton FALLBACK path
## directly: a base BodyProjection (null skeleton, empty bounds) must still yield
## a finite, above-feet, normalized transform via the default anchor -- catching
## null deref, the Variant `is Vector3` branch, and transform-compose typos.
func _validate_pose_solver(failures: Array[String]) -> void:
	var carrier_node := CharacterBody3D.new()
	root.add_child(carrier_node)
	carrier_node.global_transform = Transform3D(Basis.IDENTITY, Vector3(3.0, 0.0, -2.0))
	var body := BodyProjection.new()
	carrier_node.add_child(body)

	var profile: HumanoidCarryPoseProfile = CarryCapability.DEFAULT_CARRY_POSE_PROFILE
	var result := CarryPoseSolver.solve_carried_transform(body, carrier_node, profile)

	_expect(failures, "pose solver origin is finite", _is_finite_vector(result.origin))
	_expect(failures, "pose solver anchors above carrier feet", result.origin.y > carrier_node.global_position.y)
	_expect(failures, "pose solver basis stays valid (det ~ 1)", absf(result.basis.determinant() - 1.0) < 0.01)

	carrier_node.free()


func _is_finite_vector(v: Vector3) -> bool:
	return is_finite(v.x) and is_finite(v.y) and is_finite(v.z)


func _make_actor(actor_name: String, faction: String) -> WorldActor:
	var actor := WorldActor.new()
	actor.name = actor_name
	actor.faction_name = faction
	root.add_child(actor)
	actor._create_actor_capabilities()
	for capability in actor._capabilities.values():
		(capability as ActorCapability).setup(actor)
	for capability in actor._capabilities.values():
		(capability as ActorCapability).ready()
	return actor


func _expect(failures: Array[String], label: String, condition: bool) -> void:
	if not condition:
		failures.append(label)
