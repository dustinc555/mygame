extends GutTest

const SHELLS := "res://features/world/projection/buildings/shells/modular/"

func test_cottage_chimney_shaft_meets_roof_without_floating_or_burial() -> void:
	var shell := (load(SHELLS + "small_wood_cottage.tscn") as PackedScene).instantiate()
	autofree(shell)
	var chimney := shell.get_node("Pieces/Chimney/Model/Prop_Chimney") as MeshInstance3D
	var source := (load("res://assets/vendor/quaternius/medieval_village_megakit/gltf_godot/Prop_Chimney.gltf") as PackedScene).instantiate()
	autofree(source)
	var source_mesh := (source.find_child("Prop_Chimney", true, false) as MeshInstance3D).mesh
	var chimney_transform := _relative_transform(chimney, shell)
	var roof_faces := PackedVector3Array()
	for piece: Node in shell.get_node("Pieces").get_children():
		if not str(piece.name).begins_with("RoofCap"):
			continue
		for mesh_node: MeshInstance3D in piece.find_children("*", "MeshInstance3D", true, false):
			var relative := _relative_transform(mesh_node, shell)
			for point: Vector3 in mesh_node.mesh.get_faces():
				roof_faces.append(relative * point)
	assert_gt(roof_faces.size(), 0, "Measure the actual roof, not a copied height constant")
	var tested := 0
	var maximum_gap := 0.0
	for surface in chimney.mesh.get_surface_count():
		# Identify the shaft from its untouched source, not the cap details.
		if source_mesh.surface_get_material(surface).resource_name != "MI_Brick":
			continue
		var vertices: PackedVector3Array = chimney.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
		var top := -INF
		for vertex in vertices:
			top = maxf(top, vertex.y)
		for vertex in vertices:
			if vertex.y >= top - 0.001:
				continue
			var point := chimney_transform * vertex
			var roof_height := -INF
			for index in range(0, roof_faces.size(), 3):
				var hit = Geometry3D.ray_intersects_triangle(point + Vector3.UP * 50.0, Vector3.DOWN,
					roof_faces[index], roof_faces[index + 1], roof_faces[index + 2])
				if hit != null:
					roof_height = maxf(roof_height, hit.y)
			assert_true(is_finite(roof_height), "Every shaft corner has real roof underneath")
			maximum_gap = maxf(maximum_gap, absf(point.y - roof_height))
			tested += 1
	assert_gte(tested, 4, "Inspect every lower corner, not just the lowest edge")
	assert_lt(maximum_gap, 0.002, "Chimney-to-roof gap or burial must stay below 2 mm")


func _relative_transform(node: Node3D, ancestor: Node) -> Transform3D:
	var result := Transform3D.IDENTITY
	var current: Node = node
	while current != ancestor:
		if current is Node3D:
			result = current.transform * result
		current = current.get_parent()
	return result
