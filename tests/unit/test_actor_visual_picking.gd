extends GutTest

class QuietHumanoid extends HumanoidCharacter:
	func _process(_delta: float) -> void: pass
	func _physics_process(_delta: float) -> void: pass

class SeatCollider extends StaticBody3D:
	var sitter: WorldActor
	func get_sitter() -> WorldActor: return sitter

var viewport: SubViewport
var world: Node3D
var camera: Camera3D
var interaction: WorldInteractionController
var actor: HumanoidCharacter
var body: HumanoidBodyProjection

func before_each() -> void:
	viewport = SubViewport.new()
	viewport.own_world_3d = true
	viewport.size = Vector2i(960, 540)
	add_child(viewport)
	world = Node3D.new()
	viewport.add_child(world)
	camera = Camera3D.new()
	world.add_child(camera)
	camera.make_current()
	interaction = WorldInteractionController.new()
	world.add_child(interaction)
	interaction.camera = camera
	actor = QuietHumanoid.new()
	var mesh := MeshInstance3D.new()
	mesh.name = "BodyMesh"
	mesh.mesh = CapsuleMesh.new()
	mesh.position.y = 1.0
	actor.add_child(mesh)
	var collider := CollisionShape3D.new()
	collider.name = "CollisionShape3D"
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.4
	capsule.height = 1.1
	collider.shape = capsule
	collider.position.y = 0.95
	actor.add_child(collider)
	world.add_child(actor)
	body = actor.get_body_projection()
	await get_tree().physics_frame
	await get_tree().physics_frame

func after_each() -> void:
	viewport.queue_free()
	await get_tree().process_frame

func test_seated_character_is_picked_at_visible_body_not_empty_physics_anchor() -> void:
	actor.position.x = 2.0
	actor.begin_seated_visual(Vector3.ZERO, Vector3.ZERO)
	body.play_clip("Sitting_Idle", 0.0, true, 0.0)
	body.seek_clip("Sitting_Idle", 0.2, true, 0.0)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var skeleton := body.get_skeleton()
	var chest := skeleton.global_transform * skeleton.get_bone_global_pose(skeleton.find_bone("spine_03")).origin
	camera.position = chest + Vector3(0, 0, 6)
	camera.look_at(chest)
	assert_same(interaction._pick_inspectable_target(camera.unproject_position(chest)), actor, "Click the visible sitter, not the separate movement capsule")
	var empty_anchor := camera.unproject_position(actor.global_position + Vector3(0, 0.95, 0))
	assert_null(interaction._pick_inspectable_target(empty_anchor), "The invisible standing capsule must not steal ground clicks beside the chair")

func test_visible_head_is_clickable_above_the_short_movement_capsule() -> void:
	var head := _bone_position("Head")
	camera.position = head + Vector3(0, 0, 6)
	camera.look_at(head)
	assert_same(interaction._pick_inspectable_target(camera.unproject_position(head)), actor)

func test_real_body_shrinks_with_camera_distance_without_a_pixel_halo() -> void:
	var chest := _bone_position("spine_03")
	for distance in [5.0, 55.0, 180.0]:
		camera.position = chest + Vector3(0, 0, distance)
		camera.look_at(chest)
		var cursor := camera.unproject_position(chest)
		assert_same(interaction._pick_inspectable_target(cursor), actor, "The body itself remains targetable at %s" % distance)
		if distance > 50:
			assert_null(interaction._pick_inspectable_target(cursor + Vector2(12, 0)), "Empty space beside the visible body stays empty at %s" % distance)

func test_wall_blocks_posed_body_even_when_movement_capsule_is_elsewhere() -> void:
	actor.position.x = 2.0
	actor.begin_seated_visual(Vector3.ZERO, Vector3.ZERO)
	var chest := _bone_position("spine_03")
	camera.position = chest + Vector3(0, 0, 6)
	camera.look_at(chest)
	var wall := StaticBody3D.new()
	_add_box_shape(wall, Vector3(2, 2, 0.2))
	wall.position = chest + Vector3(0, 0, 1)
	world.add_child(wall)
	await get_tree().physics_frame
	await get_tree().physics_frame
	assert_same(interaction._raycast_target_from_screen(camera.unproject_position(chest)).get("collider"), wall)
	wall.set_meta("world_building_hidden_by_camera", true)
	assert_same(interaction._pick_inspectable_target(camera.unproject_position(chest)), actor)

func test_occupied_chair_is_transparent_only_for_its_own_sitters_body() -> void:
	var chest := _bone_position("spine_03")
	camera.position = chest + Vector3(0, 0, 6)
	camera.look_at(chest)
	var chair := SeatCollider.new()
	chair.add_to_group("sittable_seat")
	chair.sitter = actor
	_add_box_shape(chair, Vector3(1, 1, 0.4))
	chair.position = chest + Vector3(0, 0, 0.5)
	world.add_child(chair)
	await get_tree().physics_frame
	await get_tree().physics_frame
	assert_same(interaction._pick_inspectable_target(camera.unproject_position(chest)), actor)
	chair.sitter = null
	assert_same(interaction._pick_inspectable_target(camera.unproject_position(chest)), chair, "An unrelated chair still occludes the body")

func test_hidden_body_cannot_be_selected_through_its_invisible_movement_capsule() -> void:
	var chest := _bone_position("spine_03")
	camera.position = chest + Vector3(0, 0, 6)
	camera.look_at(chest)
	body.hide()
	assert_null(interaction._pick_inspectable_target(camera.unproject_position(chest)))

func test_freed_body_does_not_leave_a_cached_click_target() -> void:
	var chest := _bone_position("spine_03")
	camera.position = chest + Vector3(0, 0, 6)
	camera.look_at(chest)
	var cursor := camera.unproject_position(chest)
	assert_same(interaction._pick_inspectable_target(cursor), actor)
	actor.queue_free()
	await get_tree().process_frame
	await get_tree().physics_frame
	assert_null(interaction._pick_inspectable_target(cursor))

func test_downed_body_keeps_picking_at_actual_ragdoll_pose() -> void:
	actor.force_kill()
	await get_tree().physics_frame
	await get_tree().physics_frame
	var chest := _bone_position("spine_03")
	camera.position = chest + Vector3(0, 2, 6)
	camera.look_at(chest)
	assert_same(interaction._pick_inspectable_target(camera.unproject_position(chest)), actor)

func test_bone_capsule_hits_sides_and_endcaps_but_not_empty_space() -> void:
	var picker = preload("res://features/world/bridge/actor_body_picker.gd")
	var side: PackedVector3Array = picker.intersect_capsule(Vector3(2, 0, 0), Vector3(-2, 0, 0), Vector3(0, -2, 0), Vector3(0, 2, 0), 0.2)
	assert_false(side.is_empty())
	if not side.is_empty():
		assert_almost_eq(side[0], Vector3(0.2, 0, 0), Vector3.ONE * 0.0001)
	var cap: PackedVector3Array = picker.intersect_capsule(Vector3(0, 4, 0), Vector3(0, 0, 0), Vector3(0, -2, 0), Vector3(0, 2, 0), 0.2)
	assert_false(cap.is_empty())
	if not cap.is_empty():
		assert_almost_eq(cap[0], Vector3(0, 2.2, 0), Vector3.ONE * 0.0001)
	assert_true(picker.intersect_capsule(Vector3(2, 0, 0.21), Vector3(-2, 0, 0.21), Vector3(0, -2, 0), Vector3(0, 2, 0), 0.2).is_empty())

func _bone_position(bone_name: String) -> Vector3:
	var skeleton := body.get_skeleton()
	return skeleton.global_transform * skeleton.get_bone_global_pose(skeleton.find_bone(bone_name)).origin

func _add_box_shape(target: CollisionObject3D, size: Vector3) -> void:
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	target.add_child(shape)
