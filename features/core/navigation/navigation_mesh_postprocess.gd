extends RefCounted

class_name NavigationMeshPostprocess

## Post-processes a baked NavigationMesh to work around Godot issue #85548.
##
## Adapted from Terrain3D's editor baker (addons/terrain_3d/menu/baker.gd,
## MIT License, Copyright (c) Cory Petkovsek, Roope Palmroos, and contributors;
## see addons/terrain_3d/LICENSE.txt). Copied rather than referenced because
## the addon script is an editor-plugin node and cannot be loaded at runtime.
##
## Safe to run off the main thread: operates only on the NavigationMesh
## resource, never on the scene tree.


static func apply(nav_mesh: NavigationMesh) -> void:
	# Round all vertices to the nearest cell_size/cell_height so the mesh
	# contains no edges shorter than one cell (one cause of #85548).
	var vertices := _round_vertices(nav_mesh)
	# Rounding can collapse edges to zero length; drop degenerate polygons.
	var polygons := _remove_empty_polygons(nav_mesh, vertices)
	# Baking can also produce overlapping polygons; remove those.
	_remove_overlapping_polygons(nav_mesh, vertices, polygons)
	nav_mesh.clear_polygons()
	nav_mesh.set_vertices(vertices)
	for polygon in polygons:
		nav_mesh.add_polygon(polygon)


static func _round_vertices(nav_mesh: NavigationMesh) -> PackedVector3Array:
	var cell_size := Vector3(nav_mesh.cell_size, nav_mesh.cell_height, nav_mesh.cell_size)
	# Round a little harder to avoid rounding errors with non-power-of-two
	# cell sizes putting two non-matching edges in the same map cell.
	var round_factor := cell_size * 1.001
	var vertices: PackedVector3Array = nav_mesh.get_vertices()
	for i in range(vertices.size()):
		vertices[i] = (vertices[i] / round_factor).floor() * round_factor
	return vertices


static func _remove_empty_polygons(nav_mesh: NavigationMesh, vertices: PackedVector3Array) -> Array[PackedInt32Array]:
	var polygons: Array[PackedInt32Array] = []
	for i in range(nav_mesh.get_polygon_count()):
		var old_polygon: PackedInt32Array = nav_mesh.get_polygon(i)
		var new_polygon: PackedInt32Array = []
		# Remove duplicate vertices (introduced by rounding) from the polygon.
		var polygon_vertices: PackedVector3Array = []
		for index in old_polygon:
			var vertex: Vector3 = vertices[index]
			if polygon_vertices.has(vertex):
				continue
			polygon_vertices.push_back(vertex)
			new_polygon.push_back(index)
		if new_polygon.size() <= 2:
			continue
		polygons.push_back(new_polygon)
	return polygons


static func _remove_overlapping_polygons(nav_mesh: NavigationMesh, vertices: PackedVector3Array, polygons: Array[PackedInt32Array]) -> void:
	# An 'overlap' is an edge shared by 3+ polygons; a 'bad polygon' contains
	# 2+ overlaps. Removing bad polygons removes overlaps without creating
	# holes in practice (see godotengine/godot#85548).
	var cell_size := Vector3(nav_mesh.cell_size, nav_mesh.cell_height, nav_mesh.cell_size)
	var edges: Dictionary = {}
	for polygon_index in range(polygons.size()):
		var polygon: PackedInt32Array = polygons[polygon_index]
		for j in range(polygon.size()):
			var vertex: Vector3 = vertices[polygon[j]]
			var next_vertex: Vector3 = vertices[polygon[(j + 1) % polygon.size()]]
			# Cell coordinates (Vector3i) make the key immune to float error;
			# sorting makes it order-independent across neighboring polygons.
			var edge_key: Array = [Vector3i(vertex / cell_size), Vector3i(next_vertex / cell_size)]
			edge_key.sort()
			if not edges.has(edge_key):
				edges[edge_key] = []
			edges[edge_key].push_back(polygon_index)
	var overlap_count: Dictionary = {}
	for connections in edges.values():
		if connections.size() <= 2:
			continue
		for polygon_index in connections:
			overlap_count[polygon_index] = overlap_count.get(polygon_index, 0) + 1
	var bad_polygons: Array = []
	for polygon_index in overlap_count.keys():
		if overlap_count[polygon_index] >= 2:
			bad_polygons.push_back(polygon_index)
	bad_polygons.sort()
	for i in range(bad_polygons.size() - 1, -1, -1):
		polygons.remove_at(bad_polygons[i])
