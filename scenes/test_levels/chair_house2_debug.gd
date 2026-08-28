extends NavigationRegion3D

signal debug_ready
signal movement_started

@export var auto_run_sequence := false

@onready var house2: Node3D = $House2
@onready var actor_a: HumanoidCharacter = $ActorA
@onready var actor_b: HumanoidCharacter = $ActorB
@onready var camera: Camera3D = $Camera3D

var ready_for_test := false
var seats: Array[Node] = []
var outside_targets: Array[Vector3] = []
var movement_routes: Dictionary = {}


func _ready() -> void:
	camera.look_at(house2.global_position + Vector3.UP * 1.0, Vector3.UP)
	call_deferred("_prepare_demo")


func _prepare_demo() -> void:
	await get_tree().physics_frame
	await get_tree().physics_frame
	var navigation_map := get_world_3d().navigation_map
	NavigationServer3D.map_set_cell_size(navigation_map, navigation_mesh.cell_size)
	NavigationServer3D.map_set_cell_height(navigation_map, navigation_mesh.cell_height)
	bake_navigation_mesh(false)
	for _frame in range(10):
		await get_tree().physics_frame
	_open_front_door()
	seats = _collect_seats(house2.get_node_or_null("Furniture"))
	seats.sort_custom(func(left: Node, right: Node) -> bool: return str(left.get_path()) < str(right.get_path()))
	if seats.size() < 2:
		return
	outside_targets = _outside_targets()
	if outside_targets.size() != 2:
		return
	var seated_a := await _seat_in_first_reachable_chair(actor_a)
	var seated_b := await _seat_in_first_reachable_chair(actor_b)
	ready_for_test = seated_a and seated_b and actor_a.is_sitting() and actor_b.is_sitting()
	var table := house2.get_node_or_null("Furniture/Table1") as Node3D
	if table != null:
		camera.global_position = table.global_position + Vector3(4.5, 3.2, 4.5)
		camera.look_at(table.global_position + Vector3.UP * 0.8, Vector3.UP)
	var building := house2.get_node("BuildingSlot/CurrentBuilding")
	building.set_visibility_for_camera(true, camera.global_position, actor_a, true)
	debug_ready.emit()
	if auto_run_sequence and ready_for_test:
		await get_tree().create_timer(3.0).timeout
		issue_movement_orders()


func _seat_in_first_reachable_chair(actor: HumanoidCharacter) -> bool:
	for seat in seats:
		if seat.is_occupied():
			continue
		actor.global_position = seat.get_interaction_position(actor)
		actor.get_interaction().assign_seat_target(seat, false)
		for _frame in range(600):
			await get_tree().physics_frame
			if actor.is_sitting():
				return true
			if actor.get_interaction().current_seat_target == null:
				break
		actor.get_interaction().stop_seat_assignment()
	return false


func issue_movement_orders() -> void:
	if not ready_for_test:
		return
	var door := house2.get_node("BuildingSlot/CurrentBuilding/Pieces/FrontDoor")
	var sides: Array[Vector3] = door.get_interaction_positions()
	if sides.size() != 2:
		return
	var inside_index := 0 if actor_a.global_position.distance_to(sides[0]) <= actor_a.global_position.distance_to(sides[1]) else 1
	var inside_point := sides[inside_index]
	var outside_point := sides[1 - inside_index]
	movement_routes[actor_a.get_instance_id()] = [inside_point, outside_point, outside_targets[0]]
	movement_routes[actor_b.get_instance_id()] = [inside_point, outside_point, outside_targets[1]]
	_start_next_route_point(actor_a)
	_start_next_route_point(actor_b)
	set_process(true)
	movement_started.emit()


func _process(_delta: float) -> void:
	for actor in [actor_a, actor_b]:
		var route: Array = movement_routes.get(actor.get_instance_id(), [])
		if route.is_empty() or actor.has_move_target():
			continue
		_start_next_route_point(actor)
	if not movement_routes.is_empty() and movement_routes.values().all(func(route: Array) -> bool: return route.is_empty()):
		set_process(false)


func _start_next_route_point(actor: HumanoidCharacter) -> void:
	var route: Array = movement_routes.get(actor.get_instance_id(), [])
	if route.is_empty():
		return
	var target: Vector3 = route.pop_front()
	movement_routes[actor.get_instance_id()] = route
	actor.set_move_target(target, true)


func both_outside() -> bool:
	if outside_targets.size() != 2:
		return false
	return actor_a.global_position.distance_to(outside_targets[0]) <= 1.0 \
		and actor_b.global_position.distance_to(outside_targets[1]) <= 1.0 \
		and not house2.get_node("BuildingSlot/CurrentBuilding").is_actor_inside(actor_a) \
		and not house2.get_node("BuildingSlot/CurrentBuilding").is_actor_inside(actor_b)


func _open_front_door() -> void:
	var door := house2.get_node_or_null("BuildingSlot/CurrentBuilding/Pieces/FrontDoor")
	if door != null and door.has_method("apply_door_state"):
		door.call("apply_door_state", {"is_open": true, "is_locked": false}, false)


func _outside_targets() -> Array[Vector3]:
	var door := house2.get_node_or_null("BuildingSlot/CurrentBuilding/Pieces/FrontDoor") as Node3D
	if door == null:
		return []
	var normal := door.global_basis.z.normalized()
	var inside_sample := (actor_a.global_position + actor_b.global_position) * 0.5
	var inside_side := signf(normal.dot(inside_sample - door.global_position))
	if is_zero_approx(inside_side):
		inside_side = 1.0
	var outward := -normal * inside_side
	var lateral := door.global_basis.x.normalized()
	var base := door.global_position + outward * 5.0
	return [base + lateral * 0.65, base - lateral * 0.65]


func _collect_seats(node: Node) -> Array[Node]:
	var found: Array[Node] = []
	if node == null:
		return found
	if node.has_method("claim_sitter") and node.has_method("get_seat_position"):
		found.append(node)
	for child in node.get_children():
		found.append_array(_collect_seats(child))
	return found
