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
	var selected_actor: Node3D = demo.get_node("Actors/Chair1Actor")
	if selected_actor.get_node_or_null("SelectionRing") == null:
		var ring_fixture := MeshInstance3D.new()
		ring_fixture.name = "SelectionRing"
		selected_actor.add_child(ring_fixture)
	selected_actor.call("set_selected", true)
	await physics_frame
	var selected_body := selected_actor.call("get_body_projection") as Node3D
	var selection_ring := selected_actor.get_node_or_null("SelectionRing") as Node3D
	_expect(selection_ring != null and selected_body != null \
			and Vector2(selection_ring.global_position.x - selected_body.global_position.x, selection_ring.global_position.z - selected_body.global_position.z).length() < 0.1,
			"selected seated actor ring must follow the visual body into the chair (ring=%s body=%s actor=%s)" % [selection_ring.global_position if selection_ring != null else Vector3.INF, selected_body.global_position if selected_body != null else Vector3.INF, selected_actor.global_position])
	selected_actor.call("set_selected", false)
	var entry_seat: Node3D = demo.get_node("Chairs/Chair3")
	var entry_actor: Node3D = demo.get_node("Actors/Chair3Actor")
	var entry_interaction = entry_actor.get_interaction()
	entry_interaction.stop_seat_assignment()
	await create_timer(1.9).timeout
	entry_actor.global_position = entry_seat.global_position + Vector3(2.5, 0.0, 0.0)
	entry_actor.call("stop_movement")
	await physics_frame
	var distant_entry_origin := entry_actor.global_position
	entry_interaction.assign_seat_target(entry_seat, true)
	await physics_frame
	_expect(entry_actor.global_position.distance_to(distant_entry_origin) < 0.001,
			"assigning a distant chair must not relocate the actor before ordinary movement reaches it")
	_expect(not entry_interaction.is_sitting and entry_actor.call("has_move_target"),
			"distant chair assignment must remain walking until the actor actually reaches interaction range")
	entry_actor.global_position = entry_seat.call("get_interaction_position", entry_actor)
	entry_actor.call("stop_movement")
	entry_interaction.process_seat_interaction()
	var entry_body := entry_actor.call("get_body_projection") as Node3D
	var seated_visual_position: Vector3 = entry_seat.call("get_seat_position", entry_actor)
	var initial_visual_distance := entry_body.global_position.distance_to(seated_visual_position)
	_expect(entry_interaction.is_sitting and entry_body.global_position.distance_to(entry_actor.global_position) < 0.05 \
			and initial_visual_distance > 0.2,
			"reached chair begins sitting presentation at the physical approach anchor instead of teleporting the body into the seat")
	await create_timer(0.11).timeout
	var mid_visual_distance := entry_body.global_position.distance_to(seated_visual_position)
	_expect(mid_visual_distance < initial_visual_distance and mid_visual_distance > 0.02,
			"sitting presentation moves continuously from the approach anchor toward the chair")
	await create_timer(0.25).timeout
	_expect(entry_body.global_position.distance_to(seated_visual_position) < 0.01,
			"sitting presentation finishes at the authored chair pose")
	entry_interaction.stop_seat_assignment()
	var exit_seat: Node3D = demo.get_node("Chairs/Chair1")
	var exit_actor: Node3D = demo.get_node("Actors/Chair1Actor")
	var exit_interaction = exit_actor.get_interaction()
	exit_interaction.stop_seat_assignment()
	await create_timer(1.5).timeout
	var blocker := StaticBody3D.new()
	blocker.name = "ExitTableBlocker"
	var blocker_shape := CollisionShape3D.new()
	var blocker_box := BoxShape3D.new()
	blocker_box.size = Vector3(1.4, 0.9, 1.4)
	blocker_shape.shape = blocker_box
	blocker_shape.position.y = 0.45
	blocker.add_child(blocker_shape)
	demo.add_child(blocker)
	blocker.global_position = exit_seat.get_stand_position()
	await physics_frame
	_expect(exit_interaction.sit_at_seat_immediately(exit_seat), "blocked chair fixture must seat using a dynamically resolved floor anchor")
	await create_timer(0.2).timeout
	var blocked_exit: Vector3 = exit_seat.get_stand_position()
	var physics_anchor := exit_actor.global_position
	var exit_clip_seconds := float(exit_actor.get_body_projection().get_clip_length("Sitting_Exit"))
	exit_interaction.stop_seat_assignment()
	await create_timer(exit_clip_seconds + 0.08).timeout
	_expect(exit_actor.global_position.distance_to(physics_anchor) < 0.02, "stand-up never moves or teleports the physics actor off its reachable chair approach anchor")
	_expect(exit_actor.get_body_projection().position.length() > 0.02, "stand-up presentation eases the visual body from the chair after physics is safe")
	await create_timer(0.35).timeout
	_expect(exit_actor.get_body_projection().position.length() < 0.01, "stand-up visual settles back onto the actor origin")
	var flat_exit_delta := Vector2(exit_actor.global_position.x - blocked_exit.x, exit_actor.global_position.z - blocked_exit.z)
	_expect(flat_exit_delta.length() > 1.05, "standing cannot land on a table because physics never left its clear floor anchor")
	_expect(Vector2(exit_actor.global_position.x - exit_seat.global_position.x, exit_actor.global_position.z - exit_seat.global_position.z).length() < 3.1, "standing chooses a nearby floor point instead of teleporting away")
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
	_expect(interaction.contains("begin_seated_visual"), "Seating must move only the visual body onto the chair")
	_expect(interaction.contains("begin_stand_up_visual_exit"), "Standing must return only the visual body to the unchanged physics root")
	_expect(interaction.contains("_set_actor_global_rotation(seat_rotation)"), "Seat placement must apply the authored global seat rotation in global space")
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
		var interaction = actor.get_interaction()
		_expect(interaction.current_seat_stand_position is Vector3 and actor.global_position.distance_to(interaction.current_seat_stand_position) < 0.001, "%s physics root must stay at its reachable floor anchor" % label)
		_expect((-actor.global_basis.z).dot(seat.global_basis.z) > 0.999, "%s actor must face the chair front" % label)
		var body = actor.get_body_projection()
		_expect(body != null and body.global_position.distance_to(seat.get_seat_position(actor)) < 0.001, "%s visual body must remain centered at the authored seat pose" % label)
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
