extends Node3D


func _ready() -> void:
	await get_tree().process_frame
	await get_tree().physics_frame
	var actor := $BedSleepTest/PartyMembers/Mira as HumanoidCharacter
	var carrier := $BedSleepTest/PartyMembers/Tomas as HumanoidCharacter
	var conscious_patient := $BedSleepTest/PartyMembers/Sigrid as HumanoidCharacter
	var bed := $BedSleepTest/BedTwin1 as SleepableBed
	var ray := PhysicsRayQueryParameters3D.create(bed.global_position + Vector3.UP * 5.0, bed.global_position - Vector3.UP)
	var hit := get_world_3d().direct_space_state.intersect_ray(ray)
	assert(hit.get("collider") == bed, "bed interaction hitbox must remain directly selectable")
	actor.assign_sleep_target(bed)
	for _frame in range(180):
		var body := actor.get_body_projection() as HumanoidBodyProjection
		if actor.life_state == NpcRules.LifeState.ASLEEP and body != null and not body.is_current_clip_playing():
			break
		await get_tree().physics_frame
	var sleep_position := bed.get_sleep_position(actor)
	assert(actor.life_state == NpcRules.LifeState.ASLEEP, "actor must enter GECS sleep state")
	assert(absf(actor.global_position.y - sleep_position.y) < 0.01, "mattress collision must not push sleeper upward")
	var destination := actor.get_floor_aligned_origin_position(Vector3(4.0, 0.0, 2.2))
	actor.set_move_target(destination, true)
	for _frame in range(300):
		if actor.life_state == NpcRules.LifeState.ALIVE and actor.global_position.distance_to(destination) < 0.6:
			break
		await get_tree().physics_frame
	assert(actor.global_position.distance_to(destination) < 0.6, "wake move must survive LayToIdle")

	# A medically downed passenger keeps that medical state while bed occupancy
	# owns presentation and recovery. Carry detachment must never start ground
	# ragdoll between the carrier and the mattress.
	actor.force_unconscious()
	var downed_state := actor.life_state
	_place_carried_in_bed(carrier, actor, bed)
	var body := actor.get_body_projection() as HumanoidBodyProjection
	assert(actor.life_state == downed_state, "bed placement must preserve unconscious medical state")
	assert(actor.is_in_bed_rest(), "downed passenger must become a bed occupant")
	assert(bed.get_sleeper() == actor, "bed must claim the downed passenger")
	assert(is_equal_approx(actor.get_vitals().recovery_multiplier, bed.get_recovery_multiplier()), "downed bed occupant must receive bed recovery bonus")
	assert(body != null and not body.is_ragdoll_active(), "bed placement must stop downed ragdoll")
	assert(body.get_current_clip() == HumanoidBodyProjection.LAY_ENTER_ANIMATION_NAME, "downed bed occupant must use the lay pose")
	assert(actor.global_position.distance_to(bed.get_sleep_position(actor)) < 0.01, "downed occupant must stay aligned to mattress")

	# Picking the patient back up releases bed state and its recovery bonus. A
	# subsequent ground drop restores their downed ragdoll presentation.
	carrier._attach_carried_character(actor)
	assert(not actor.is_in_bed_rest() and not bed.is_occupied(), "pickup must release bed occupancy")
	assert(is_equal_approx(actor.get_vitals().recovery_multiplier, VitalsCapability.RECOVERY_MULTIPLIER_GROUND), "pickup must remove bed recovery bonus")
	carrier._detach_carried_character()
	body.process_downed_visuals(10.0)
	assert(body.is_ragdoll_active(), "dropping an unconscious bed occupant on the ground must restore ragdoll")

	# Death changes medical state only. Bed occupancy still owns the same stable
	# lying presentation, without granting any possibility of recovery.
	actor.force_kill()
	_place_carried_in_bed(carrier, actor, bed)
	assert(actor.life_state == NpcRules.LifeState.DEAD, "dead bed occupant must remain dead")
	assert(actor.is_in_bed_rest() and not body.is_ragdoll_active(), "dead bed occupant must lie stably without ragdoll")
	assert(body.get_current_clip() == HumanoidBodyProjection.LAY_ENTER_ANIMATION_NAME, "dead bed occupant must use the lay pose")

	# Free the bed, then verify that placing a conscious passenger requests and
	# reaches the ordinary ASLEEP state rather than leaving them standing.
	carrier._attach_carried_character(actor)
	carrier._detach_carried_character()
	body.process_downed_visuals(10.0)
	assert(body.is_ragdoll_active(), "dropping a dead bed occupant on the ground must restore ragdoll")
	_place_carried_in_bed(carrier, conscious_patient, bed)
	for _frame in range(60):
		if conscious_patient.life_state == NpcRules.LifeState.ASLEEP:
			break
		await get_tree().physics_frame
	assert(conscious_patient.life_state == NpcRules.LifeState.ASLEEP, "conscious passenger placed in bed must become asleep")
	assert(conscious_patient.is_in_bed_rest(), "conscious sleeper must retain bed occupancy")
	assert((conscious_patient.get_body_projection() as HumanoidBodyProjection).get_current_clip() == HumanoidBodyProjection.LAY_ENTER_ANIMATION_NAME, "conscious passenger must lie down instead of standing")
	print("PASS validate_bed_sleep_interaction")
	get_tree().quit()


func _place_carried_in_bed(carrier: HumanoidCharacter, passenger: HumanoidCharacter, bed: SleepableBed) -> void:
	carrier.global_position = bed.get_interaction_position(carrier)
	carrier._attach_carried_character(passenger)
	assert(carrier.get_carry().get_carried_character() == passenger, "bed test carrier must pick up passenger")
	var interaction := carrier.get_interaction()
	interaction.assign_place_carried_in_bed_target(bed, true)
	carrier._clear_actor_move_target()
	carrier._process_active_order(1.0 / 60.0)
	assert(carrier.get_carry().get_carried_character() == null, "bed placement must release passenger from carrier")
