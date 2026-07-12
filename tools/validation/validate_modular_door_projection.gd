extends SceneTree

const DOOR_SCENE := preload("res://scenes/building_pieces/quaternius/medieval_village_woodbrick/door_wood_flat.tscn")
const PIPELINE_PATH := "res://features/core/navigation/world_nav_bake_pipeline.gd"
const BLOCKER_LAYER := 8


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var bake_mask := int(load(PIPELINE_PATH).NAV_BAKED_COLLISION_MASK)
	_expect(bake_mask & BLOCKER_LAYER == 0, "Nav bake mask must exclude the door blocker layer.")
	_expect(bake_mask & 1 != 0 and bake_mask & 4 != 0, "Nav bake mask must keep world and furniture layers baked.")
	var root := Node3D.new()
	get_root().add_child(root)
	var door := DOOR_SCENE.instantiate()
	door.door_id = "validation.flat"
	root.add_child(door)
	var blocker := door.get_node("ClosedBlocker") as StaticBody3D
	_expect(blocker.get_parent() == door, "Closed modular doors must provide a static collision blocker.")
	_expect(_static_collider_vertex_count(root, bake_mask) == 0, "Door blockers must be excluded from baked navigation geometry.")
	blocker.collision_layer = 1
	_expect(_static_collider_vertex_count(root, bake_mask) > 0, "Navigation validation must detect ordinary static collision.")
	blocker.collision_layer = BLOCKER_LAYER
	door.apply_door_state({"is_open": true}, false)
	_expect(blocker.get_parent() == door and blocker.collision_layer == 0, "Open doors must disable physics without changing nav geometry.")
	_expect(not is_zero_approx((door.get_node("HingePivot") as Node3D).rotation.y), "Open doors must rotate around the hinge pivot.")
	door.apply_door_state({"is_open": false}, false)
	_expect(blocker.get_parent() == door, "Closing must restore the static collision blocker.")
	_expect(blocker.collision_layer == BLOCKER_LAYER, "Closing must restore runtime-only door collision.")
	_expect(is_zero_approx((door.get_node("HingePivot") as Node3D).rotation.y), "Closing must restore the hinge rotation.")
	var auto_open_area := door.get_node("AutoOpenArea") as Area3D
	_expect(auto_open_area.collision_mask == 2, "AutoOpenArea must monitor the actor collision layer.")
	root.free()
	print("MODULAR_DOOR_PROJECTION_OK")
	quit()


func _expect(condition: bool, message: String) -> void:
	if not condition:
		push_error(message)
		quit(1)


func _static_collider_vertex_count(root: Node, bake_mask: int) -> int:
	var nav_mesh := NavigationMesh.new()
	nav_mesh.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	nav_mesh.geometry_collision_mask = bake_mask
	nav_mesh.geometry_source_geometry_mode = NavigationMesh.SOURCE_GEOMETRY_ROOT_NODE_CHILDREN
	var geometry := NavigationMeshSourceGeometryData3D.new()
	NavigationServer3D.parse_source_geometry_data(nav_mesh, geometry, root)
	return geometry.get_vertices().size()
