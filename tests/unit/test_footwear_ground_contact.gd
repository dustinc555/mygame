extends GutTest

class FixtureActor extends HumanoidCharacter:
	func _ready() -> void:
		pass

func _fixture() -> Dictionary:
	var actor := FixtureActor.new()
	actor.process_mode = Node.PROCESS_MODE_DISABLED
	add_child_autofree(actor)
	var projection := HumanoidBodyProjection.new()
	actor.add_child(projection)
	projection.bind_actor(actor)
	var visual := Node3D.new()
	projection.add_child(visual)
	projection._visual_root = visual
	var model := Node3D.new()
	visual.add_child(model)
	var skeleton := Skeleton3D.new()
	model.add_child(skeleton)
	skeleton.add_bone("foot_l")
	projection._character_skeleton = skeleton
	var mesh := MeshInstance3D.new()
	model.add_child(mesh)
	mesh.skeleton = mesh.get_path_to(skeleton)
	mesh.skin = Skin.new()
	mesh.skin.add_named_bind("foot_l", Transform3D.IDENTITY)
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3(-0.1,-0.06,0), Vector3(0.1,-0.06,0), Vector3(0,-0.06,0.2)])
	arrays[Mesh.ARRAY_BONES] = PackedInt32Array([0,0,0,0, 0,0,0,0, 0,0,0,0])
	arrays[Mesh.ARRAY_WEIGHTS] = PackedFloat32Array([1,0,0,0, 1,0,0,0, 1,0,0,0])
	mesh.mesh = ArrayMesh.new()
	mesh.mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return {"actor":actor, "projection":projection, "visual":visual, "skeleton":skeleton, "mesh":mesh}

func _sole_y(f: Dictionary) -> float:
	return (f.skeleton.global_transform * f.skeleton.get_bone_global_pose(0) * Vector3(0,-0.06,0)).y

func test_actual_sole_not_ankle_is_grounded_and_repeat_is_idempotent() -> void:
	var f := _fixture()
	var actor_transform: Transform3D = f.actor.transform
	var source_arrays: Array = f.mesh.mesh.surface_get_arrays(0)
	f.projection.refresh_foot_ground_alignment()
	assert_almost_eq(_sole_y(f), 0.002, 0.001, "Real supported mesh sole reaches floor clearance")
	var first: Vector3 = f.visual.position
	for repeat in 5:
		f.projection.refresh_foot_ground_alignment()
		assert_almost_eq(f.visual.position, first, Vector3.ONE * 0.00001, "No feedback oscillation")
	assert_eq(f.actor.transform, actor_transform, "Collision/navigation actor never moves")
	assert_eq(f.mesh.mesh.surface_get_arrays(0), source_arrays, "Never reshape accepted mesh")

func test_airborne_does_not_snap_to_capsule_floor() -> void:
	var f := _fixture()
	f.actor.process_mode = Node.PROCESS_MODE_INHERIT
	f.actor.set_process(false)
	f.actor.set_physics_process(false)
	f.projection.refresh_foot_ground_alignment()
	assert_eq(f.visual.position, Vector3.ZERO, "No support means no floor correction")

func test_explicit_studio_floor_can_be_changed_and_released() -> void:
	var f := _fixture()
	f.actor.process_mode = Node.PROCESS_MODE_INHERIT
	f.actor.set_process(false)
	f.actor.set_physics_process(false)
	f.projection.set_preview_ground_height(0.025)
	assert_almost_eq(_sole_y(f), 0.027, 0.001, "Studio supplies the visible floor, not the actor capsule")
	f.projection.set_preview_ground_height(-0.025)
	assert_almost_eq(_sole_y(f), -0.023, 0.001, "Changing the floor does not accumulate the previous lift")
	f.projection.set_preview_ground_height(NAN)
	assert_almost_eq(f.visual.position, Vector3.ZERO, Vector3.ONE * 0.00001, "Leaving preview restores unsupported live behavior")

func test_articulated_toe_support_is_not_lost_behind_lower_rest_heel() -> void:
	var f := _fixture()
	f.skeleton.add_bone("ball_l")
	f.skeleton.set_bone_parent(1, 0)
	var toe := MeshInstance3D.new()
	f.mesh.get_parent().add_child(toe)
	toe.skeleton = toe.get_path_to(f.skeleton)
	toe.skin = Skin.new()
	toe.skin.add_named_bind("ball_l", Transform3D.IDENTITY)
	var arrays: Array = f.mesh.mesh.surface_get_arrays(0)
	# In rest these toe points are higher and inside the heel's support outline.
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3(-0.02,-0.04,0.01), Vector3(0.02,-0.04,0.01), Vector3(0,-0.04,0.02)])
	toe.mesh = ArrayMesh.new()
	toe.mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	f.skeleton.set_bone_pose_position(1, Vector3(0,-0.05,0))
	f.projection.refresh_foot_ground_alignment()
	var point: Vector3 = f.skeleton.global_transform * f.skeleton.get_bone_global_pose(1) * Vector3(0,-0.04,0.02)
	assert_almost_eq(point.y, 0.002, 0.001, "Animated toes must retain their own support samples")

func test_feet_equipment_refresh_invalidates_sole_cache() -> void:
	var f := _fixture()
	f.projection.refresh_foot_ground_alignment()
	var shoe: MeshInstance3D = f.mesh.duplicate()
	var footwear := Node3D.new()
	footwear.name = "Equipped_Feet"
	f.visual.add_child(footwear)
	footwear.add_child(shoe)
	shoe.skeleton = shoe.get_path_to(f.skeleton)
	var arrays := shoe.mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	for index in vertices.size(): vertices[index].y -= 0.03
	arrays[Mesh.ARRAY_VERTEX] = vertices
	shoe.mesh = ArrayMesh.new()
	shoe.mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	# Normal slot refresh must invalidate data, including when removing footwear.
	f.projection._footwear_support_dirty = true
	f.projection.refresh_foot_ground_alignment()
	assert_almost_eq(f.visual.position.y, 0.092, 0.001)
	f.projection.refresh_equipment_slots(["feet"])
	f.projection.refresh_foot_ground_alignment()
	assert_almost_eq(f.visual.position.y, 0.062, 0.001, "Removed soles cannot retain lift")

func test_actual_sloped_floor_prevents_supported_sole_penetration() -> void:
	var f := _fixture()
	f.actor.collision_mask = 1
	var floor := StaticBody3D.new()
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(4,0.1,4)
	collider.shape = shape
	floor.add_child(collider)
	floor.rotation.z = 0.25
	floor.position = -floor.basis.y * 0.05
	add_child_autofree(floor)
	await get_tree().physics_frame
	await get_tree().physics_frame
	f.projection.refresh_foot_ground_alignment()
	var right: Vector3 = f.skeleton.global_transform * Vector3(0.1,-0.06,0)
	assert_gte(right.y, tan(0.25) * right.x + 0.001, "Query physical sloped support, not capsule-bottom plane")

