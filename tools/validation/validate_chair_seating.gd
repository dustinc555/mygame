extends SceneTree

const DEMO_PATH := "res://scenes/test_levels/chair_seating_demo.tscn"
const INTERACTION_PATH := "res://features/actors/bridge/capabilities/interaction_capability.gd"
const HUMANOID_PATH := "res://features/actors/projection/humanoid/humanoid_character.gd"
const BAR_PATH := "res://features/settlements/bridge/settlement_bar.gd"
const VISIT_PATH := "res://features/settlements/bridge/facility_visit_activity_point.gd"
const WORLD_INTERACTION_PATH := "res://features/world/bridge/world_interaction_controller.gd"
const PAIRS := [
	["Chair1", "Actors/Chair1Actor"],
	["Chair3", "Actors/Chair3Actor"],
	["Stool", "Actors/StoolActor"],
	["Throne", "Actors/ThroneActor"],
]

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_validate_source_contracts()
	var packed := load(DEMO_PATH) as PackedScene
	_expect(packed != null, "Chair seating demo must load")
	if packed == null:
		_finish()
		return
	var demo := packed.instantiate()
	root.add_child(demo)
	await create_timer(4.0).timeout
	_validate_seats(demo, "initial seating")
	for pair in PAIRS:
		var seat := demo.get_node("Chairs/%s" % pair[0])
		var actor := demo.get_node(pair[1])
		var interaction = actor.get_interaction() if actor != null else null
		_expect(interaction != null and interaction.sit_at_seat_immediately(seat), "%s must support idempotent immediate seating" % pair[0])
	await create_timer(2.5).timeout
	_validate_seats(demo, "repeated seating")
	demo.queue_free()
	await process_frame
	_finish()


func _validate_source_contracts() -> void:
	var interaction := FileAccess.get_file_as_string(INTERACTION_PATH)
	var humanoid := FileAccess.get_file_as_string(HUMANOID_PATH)
	var bar := FileAccess.get_file_as_string(BAR_PATH)
	var visit := FileAccess.get_file_as_string(VISIT_PATH)
	var world_interaction := FileAccess.get_file_as_string(WORLD_INTERACTION_PATH)
	_expect(interaction.contains("is_sitting and current_seat_target == seat"), "Immediate seating must be idempotent for an occupied seat")
	_expect(interaction.contains("_call_void(\"cancel_stand_up_exit\")"), "Immediate seating must cancel a pending stand-up exit")
	_expect(interaction.count("_set_actor_global_rotation(seat") == 3, "Every seat placement path must apply the authored global seat rotation in global space")
	_expect(interaction.contains("_set_actor_global_rotation(sleep_target.call(\"get_sleep_rotation\"))"), "Bed placement must apply authored global rotation in global space")
	_expect(humanoid.contains("func cancel_stand_up_exit()"), "Humanoid presentation must expose pending stand-up cancellation")
	_expect(not bar.contains("actor.has_method(\"sit_at_seat_immediately\")"), "Bar seating must not call the removed actor-owned immediate-seat API")
	_expect(not visit.contains("actor.has_method(\"sit_at_seat_immediately\")"), "Facility visits must not call the removed actor-owned immediate-seat API")
	_expect(world_interaction.contains("var occupied_seat := _find_sittable_seat(collider)"), "World clicks must identify occupied seats before resolving click targets")
	_expect(world_interaction.contains("seat.call(\"get_sitter\") == actor"), "An occupied seat must be transparent only when testing visibility of its sitter")
	var raycast_target_source := world_interaction.get_slice("func _raycast_target_from_screen", 1).get_slice("func _find_sittable_seat", 0)
	_expect(raycast_target_source.find("var occupied_seat := _find_sittable_seat(collider)") < raycast_target_source.find("var actor_collider := _resolve_actor_collider(collider)"), "Occupied seat collision must be skipped before actor click resolution")


func _validate_seats(demo: Node, phase: String) -> void:
	for pair in PAIRS:
		var seat := demo.get_node("Chairs/%s" % pair[0]) as Node3D
		var actor := demo.get_node(pair[1])
		var label := "%s during %s" % [pair[0], phase]
		_expect(seat.get_sitter() == actor, "%s must remain occupied by its actor" % label)
		_expect(actor.is_sitting(), "%s actor must remain in sitting state" % label)
		_expect(actor.global_position.distance_to(seat.get_seat_position(actor)) < 0.001, "%s actor must remain centered at the authored seat pose" % label)
		_expect((-actor.global_basis.z).dot(seat.global_basis.z) > 0.999, "%s actor must face the chair front" % label)
		var body = actor.get_body_projection()
		_expect(body != null and str(body.call("get_current_clip")) == "Sitting_Idle", "%s actor must hold Sitting_Idle" % label)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
		push_error(message)


func _finish() -> void:
	if _failures.is_empty():
		print("CHAIR_SEATING_OK")
	else:
		print("CHAIR_SEATING_FAILED count=%d" % _failures.size())
	quit(0 if _failures.is_empty() else 1)
