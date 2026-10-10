extends GutTest

# Real perspective projection and physics queries, without actor simulation.
class QuietActor extends WorldActor:
	func _enter_tree() -> void: pass
	func _ready() -> void:
		add_to_group("world_actor")
		set_process(false)
		set_physics_process(false)

var viewport: SubViewport
var world: Node3D
var camera: Camera3D
var interaction: WorldInteractionController
var actor: QuietActor
var floor_body: StaticBody3D

func before_each() -> void:
	viewport = SubViewport.new()
	viewport.size = Vector2i(960, 540)
	viewport.own_world_3d = true
	add_child(viewport)
	world = Node3D.new()
	viewport.add_child(world)
	camera = Camera3D.new()
	world.add_child(camera)
	camera.position = Vector3(0, 24, 50)
	camera.look_at(Vector3(0, 1.2, 0))
	camera.make_current()
	interaction = WorldInteractionController.new()
	world.add_child(interaction)
	interaction.camera = camera
	floor_body = _box(Vector3(0, -0.1, 0), Vector3(200, 0.2, 200))
	actor = _actor_at(Vector3.ZERO)
	await _sync_physics()

func after_each() -> void:
	viewport.queue_free()
	await get_tree().process_frame

func test_ground_beside_distant_person_is_not_replaced_by_character() -> void:
	var cursor := camera.unproject_position(Vector3(0, 1.2, 0)) + Vector2(18, 0)
	var actual_hit := interaction._raycast_from_screen(cursor)
	assert_same(actual_hit.get("collider"), floor_body, "Fixture click physically misses the body and hits ground")
	var picked := interaction._raycast_target_from_screen(cursor)
	assert_same(picked.get("collider"), floor_body, "Empty space beside a distant person must keep its ground click")
	assert_false(interaction._is_hold_move_blocked(cursor), "A nearby person must not block held movement either")

func test_direct_body_hit_still_selects_at_near_and_far_distances() -> void:
	for distance in [5.0, 55.0, 180.0]:
		camera.position = Vector3(0, 1.2, distance)
		camera.look_at(Vector3(0, 1.2, 0))
		var cursor := camera.unproject_position(Vector3(0, 1.2, 0))
		assert_same(interaction._pick_inspectable_target(cursor), actor, "Direct hit at camera distance %s" % distance)

func test_same_pixel_offset_hits_near_body_but_misses_distant_body() -> void:
	var center := Vector3(0, 1.2, 0)
	camera.position = Vector3(0, 1.2, 5)
	camera.look_at(center)
	var cursor := camera.unproject_position(center) + Vector2(12, 0)
	assert_same(interaction._pick_inspectable_target(cursor), actor, "Near body occupies the cursor position")
	camera.position.z = 55
	assert_null(interaction._pick_inspectable_target(cursor), "The body shrinks with perspective; empty space does not remain clickable")

func test_furniture_beside_actor_keeps_its_exact_hit() -> void:
	var furniture := _box(Vector3(1.5, 0.8, 0), Vector3(0.7, 1.6, 0.7))
	furniture.add_to_group("world_container")
	await _sync_physics()
	var cursor := camera.unproject_position(furniture.global_position)
	assert_same(interaction._raycast_from_screen(cursor).get("collider"), furniture)
	assert_same(interaction._pick_inspectable_target(cursor), furniture, "Furniture must not lose priority to a nearby chest")

func test_adjacent_characters_do_not_capture_the_gap_between_them() -> void:
	actor.position.x = -0.7
	var other := _actor_at(Vector3(0.7, 0, 0))
	await _sync_physics()
	for target in [actor, other]:
		assert_same(interaction._pick_inspectable_target(camera.unproject_position(target.position + Vector3(0, 1.2, 0))), target)
	var gap := camera.unproject_position(Vector3(0, 1.2, 0))
	assert_same(interaction._raycast_target_from_screen(gap).get("collider"), floor_body)

func test_visible_wall_occludes_actor() -> void:
	var wall := _box(Vector3(0, 1.5, 1), Vector3(3, 3, 0.2))
	await _sync_physics()
	var cursor := camera.unproject_position(Vector3(0, 1.2, 0))
	assert_same(interaction._raycast_target_from_screen(cursor).get("collider"), wall)

func test_camera_hidden_wall_is_click_transparent() -> void:
	var wall := _box(Vector3(0, 1.5, 1), Vector3(3, 3, 0.2))
	wall.set_meta("world_building_hidden_by_camera", true)
	await _sync_physics()
	var cursor := camera.unproject_position(Vector3(0, 1.2, 0))
	assert_same(interaction._pick_inspectable_target(cursor), actor)

func test_nearer_character_wins_over_character_behind_it() -> void:
	camera.position = Vector3(0, 1.2, 12)
	camera.look_at(Vector3(0, 1.2, 0))
	var nearer := _actor_at(Vector3(0, 0, 3))
	await _sync_physics()
	assert_same(interaction._pick_inspectable_target(camera.unproject_position(Vector3(0, 1.2, 0))), nearer)

func test_right_click_miss_issues_movement_without_opening_actor_context() -> void:
	actor.player_party_member = true
	var party := PartyManager.new()
	world.add_child(party)
	party.selected_members = [actor]
	interaction.party_manager = party
	interaction.root = world
	var cursor := camera.unproject_position(Vector3(0, 1.2, 0)) + Vector2(18, 0)
	var destination: Vector3 = interaction._pick_ground_hit(cursor)["position"]
	assert_true(interaction._handle_right_click(cursor), "Ground click starts the normal move/held-move route")
	assert_null(interaction.context_member, "No person context is selected on a miss")
	assert_eq(actor.get_move_target(), destination)

func test_direct_party_right_click_selects_context_without_movement() -> void:
	actor.player_party_member = true
	var party := PartyManager.new()
	world.add_child(party)
	party.selected_members = [actor]
	interaction.party_manager = party
	assert_false(interaction._handle_right_click(camera.unproject_position(Vector3(0, 1.2, 0))))
	assert_same(interaction.context_member, actor)
	assert_false(actor.has_move_target())

func _actor_at(at: Vector3) -> QuietActor:
	var result := QuietActor.new()
	result.position = at
	var shape := CollisionShape3D.new()
	shape.name = "CollisionShape3D"
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.3
	capsule.height = 1.8
	shape.shape = capsule
	shape.position.y = 0.9
	result.add_child(shape)
	world.add_child(result)
	return result

func _box(at: Vector3, size: Vector3) -> StaticBody3D:
	var result := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	result.add_child(shape)
	result.position = at
	world.add_child(result)
	return result

func _sync_physics() -> void:
	await get_tree().physics_frame
	await get_tree().physics_frame
