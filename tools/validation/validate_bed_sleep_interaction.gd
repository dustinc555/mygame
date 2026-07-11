extends Node3D


func _ready() -> void:
	await get_tree().process_frame
	await get_tree().physics_frame
	var actor := $BedSleepTest/PartyMembers/Mira as HumanoidCharacter
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
	print("PASS validate_bed_sleep_interaction")
	get_tree().quit()
