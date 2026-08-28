extends Node3D

signal navigation_ready

@export var auto_run_sequence := true

@onready var navigation_region: NavigationRegion3D = $NavigationRegion3D
@onready var actor: HumanoidCharacter = $NavigationRegion3D/Actor
@onready var chair: SittableSeat = $NavigationRegion3D/Chair
@onready var entry_anchor: Marker3D = $NavigationRegion3D/EntryAnchor
@onready var exit_target: Marker3D = $NavigationRegion3D/ExitTarget
@onready var camera: Camera3D = $Camera3D

var ready_for_test := false


func _ready() -> void:
	camera.look_at(Vector3(0.8, 0.8, 0.0), Vector3.UP)
	call_deferred("_prepare_navigation")


func _prepare_navigation() -> void:
	await get_tree().physics_frame
	await get_tree().physics_frame
	var navigation_map := navigation_region.get_world_3d().navigation_map
	NavigationServer3D.map_set_cell_size(navigation_map, navigation_region.navigation_mesh.cell_size)
	NavigationServer3D.map_set_cell_height(navigation_map, navigation_region.navigation_mesh.cell_height)
	navigation_region.bake_navigation_mesh(false)
	for _frame in range(8):
		await get_tree().physics_frame
	ready_for_test = navigation_region.navigation_mesh != null and navigation_region.navigation_mesh.get_polygon_count() > 0
	navigation_ready.emit()
	if auto_run_sequence and ready_for_test:
		seat_actor()
		for _frame in 300:
			await get_tree().physics_frame
			if actor.is_sitting():
				break
		await get_tree().create_timer(2.0).timeout
		issue_exit_order()


func seat_actor() -> bool:
	actor.stop_movement()
	actor.global_position = entry_anchor.global_position
	var interaction = actor.get_interaction()
	interaction.stop_seat_assignment()
	interaction.assign_seat_target(chair, false)
	return not interaction.is_sitting and interaction.current_seat_target == chair and actor.has_move_target()


func issue_exit_order() -> void:
	actor.set_move_target(exit_target.global_position, true)


func reached_exit() -> bool:
	return actor.global_position.distance_to(exit_target.global_position) <= 0.8
