extends Node

class CarryOrderTarget:
	extends Node3D

	func can_be_carried_by(_carrier) -> bool:
		return true


class CountingBed:
	extends Node3D

	var interaction_position_calls := 0

	func get_interaction_position(_member) -> Vector3:
		interaction_position_calls += 1
		return global_position

	func claim_sleeper(_member) -> bool:
		return true

	func release_sleeper(_member) -> void:
		pass

	func get_sleep_position(_member = null) -> Vector3:
		return global_position

	func get_sleep_rotation() -> Vector3:
		return Vector3.ZERO

## Focused sanity check for CarryCapability relationship state.
## Run: godot --headless --path . res://tools/validation/validate_carry_capability.tscn
##
## Verifies: begin_carry reciprocal state, one-to-one/non-recursive relationship
## invariants, incapacitation release, collision suppression/restoration, and
## drop cleanup.

var _check_count := 0


func _ready() -> void:
	_run_validation.call_deferred()


func _run_validation() -> void:
	var failures: Array[String] = []

	_validate_carry_state_machine(failures)
	_validate_player_carry_order_priority(failures)
	_validate_bed_approach_cache(failures)
	_validate_pose_solver(failures)

	if failures.is_empty():
		print("PASS: CarryCapability state machine + pose solver sane (%d checks)" % _check_count)
		get_tree().quit(0)
	else:
		for f in failures:
			printerr("FAIL: ", f)
		get_tree().quit(1)


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

	var rescuer := _make_actor("rescuer", "team_a")
	var other_downed := _make_actor("other_downed", "team_b")
	var rescuer_carry := rescuer.get_carry()
	var other_downed_carry := other_downed.get_carry()
	other_downed.force_unconscious()
	_expect(failures, "an actor carrying someone cannot be carried", not carrier_carry.can_be_carried_by(true))
	_expect(failures, "pickup rejects a target who is carrying someone", not rescuer_carry.begin_carry(carrier_carry, true))
	_expect(failures, "a carried actor cannot begin another carry", not carried_carry.begin_carry(other_downed_carry, true))
	_expect(failures, "failed recursive pickups preserve original relationship", carrier_carry.get_carried_character() == carried and carried_carry.get_carrier() == carrier)

	var dropped := carrier_carry.drop()
	_expect(failures, "drop returns carried actor", dropped == carried)
	_expect(failures, "drop clears reciprocal state", not carrier_carry.is_carrying_someone() and not carried_carry.is_carried() and carrier_carry.get_carried_character() == null and carried_carry.get_carrier() == null)
	_expect(failures, "drop restores collision", carried.collision_layer == original_collision_layer and carried.collision_mask == original_collision_mask)

	# Reattach, then down the carrier. The vitals signal must release the carried
	# actor immediately and restore the reciprocal relationship/collision state.
	_expect(failures, "reattach before incapacitation succeeds", carrier_carry.begin_carry(carried_carry))
	carrier.force_unconscious()
	_expect(failures, "incapacitated carrier immediately releases carried actor", not carrier_carry.is_carrying_someone() and not carried_carry.is_carried())
	_expect(failures, "incapacitation release clears reciprocal pointers", carrier_carry.get_carried_character() == null and carried_carry.get_carrier() == null)
	_expect(failures, "incapacitation release restores carried collision", carried.collision_layer == original_collision_layer and carried.collision_mask == original_collision_mask)
	_expect(failures, "incapacitated actor cannot begin another carry", not carrier_carry.begin_carry(other_downed_carry, true))
	_expect(failures, "released actor can be rescued normally", rescuer_carry.begin_carry(carried_carry, true))
	rescuer_carry.drop()

	carrier.free()
	carried.free()
	rescuer.free()
	other_downed.free()


func _validate_player_carry_order_priority(failures: Array[String]) -> void:
	var rescuer := _make_actor("ordered_rescuer", "team_a")
	var enemy := _make_actor("combat_enemy", "team_b")
	var carry_target := CarryOrderTarget.new()
	carry_target.name = "carry_order_target"
	add_child(carry_target)
	rescuer.global_position = Vector3.ZERO
	carry_target.global_position = Vector3(8.0, 0.0, 0.0)
	rescuer._system_target_id = enemy.get_instance_id()

	var interaction := rescuer.get_interaction()
	interaction.assign_carry_target(carry_target, true)
	_expect(failures, "player carry order becomes active during combat", rescuer.has_active_player_order())
	_expect(failures, "player carry order immediately clears automatic combat target", rescuer.get_current_combat_target() == null)

	# Simulate a stale combat bridge being written again before the next targeting
	# tick. The explicit carry order must still start its approach immediately.
	rescuer._system_target_id = enemy.get_instance_id()
	rescuer._process_active_order(1.0 / 60.0)
	_expect(failures, "player carry order survives a stale combat bridge", interaction.current_order_type == InteractionCapability.ORDER_TYPE_CARRY)
	_expect(failures, "player carry order starts moving toward rescue target", rescuer.has_move_target())

	rescuer.free()
	enemy.free()
	carry_target.free()


func _validate_bed_approach_cache(failures: Array[String]) -> void:
	var carrier := _make_actor("bed_carrier", "team_a")
	var passenger := _make_actor("bed_passenger", "team_a")
	var bed := CountingBed.new()
	bed.name = "counting_bed"
	add_child(bed)
	bed.global_position = Vector3(20.0, 0.0, 0.0)
	_expect(failures, "bed approach setup begins carry", carrier.get_carry().begin_carry(passenger.get_carry(), true))

	var interaction := carrier.get_interaction()
	interaction.assign_place_carried_in_bed_target(bed, true)
	for _frame in range(20):
		interaction.process_place_in_bed_interaction()
	_expect(failures, "bed approach position is solved once per order", bed.interaction_position_calls == 1)

	carrier.free()
	passenger.free()
	bed.free()


## CarryPoseSolver runs in-game only on the carrier's projection node
## (HumanoidCharacter._physics_process), which the relationship test can't reach
## (bare WorldActor has no body projection). Smoke the no-skeleton FALLBACK path
## directly: a base BodyProjection (null skeleton, empty bounds) must still yield
## a finite, above-feet, normalized transform via the default anchor -- catching
## null deref, the Variant `is Vector3` branch, and transform-compose typos.
func _validate_pose_solver(failures: Array[String]) -> void:
	var carrier_node := CharacterBody3D.new()
	add_child(carrier_node)
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
	add_child(actor)
	return actor


func _expect(failures: Array[String], label: String, condition: bool) -> void:
	_check_count += 1
	if not condition:
		failures.append(label)
