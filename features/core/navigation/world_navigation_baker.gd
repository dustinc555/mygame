extends NavigationRegion3D

class_name WorldNavigationBaker

@export var source_root_paths: Array[NodePath] = []
@export var source_group_name := "world_navigation_source"
@export var bake_on_ready := true
@export var bake_on_thread := false
@export var agent_radius := 0.5
@export var agent_height := 1.5
@export var agent_max_slope := 60.0
@export var agent_max_climb := 0.25
@export var cell_size := 0.25
@export var cell_height := 0.25


func _ready() -> void:
	if navigation_mesh == null:
		navigation_mesh = NavigationMesh.new()
	_configure_navigation_mesh()
	_register_source_roots()
	if bake_on_ready:
		bake_navigation_mesh(bake_on_thread)


func _configure_navigation_mesh() -> void:
	navigation_mesh.agent_radius = agent_radius
	navigation_mesh.agent_height = agent_height
	navigation_mesh.agent_max_slope = agent_max_slope
	navigation_mesh.agent_max_climb = agent_max_climb
	navigation_mesh.cell_size = cell_size
	navigation_mesh.cell_height = cell_height
	navigation_mesh.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	navigation_mesh.geometry_source_geometry_mode = NavigationMesh.SOURCE_GEOMETRY_GROUPS_WITH_CHILDREN
	navigation_mesh.geometry_source_group_name = source_group_name


func _register_source_roots() -> void:
	if source_root_paths.is_empty():
		var source_root := get_parent()
		if source_root != null:
			source_root.add_to_group(source_group_name)
		return
	for source_root_path in source_root_paths:
		var source_root := get_node_or_null(source_root_path)
		if source_root != null:
			source_root.add_to_group(source_group_name)
