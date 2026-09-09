extends SceneTree
## Fixed-angle Forward+ review renders for an exact production prop wrapper.
##
## This developer-only SceneTree script creates a neutral temporary stage, loads
## the wrapper named on the command line, measures its visible mesh bounds, and
## captures four deterministic views beside a 1.8 m reference. It never edits or
## saves the wrapper. Both baseline and candidate travel through this same path,
## so the only intended difference between their images is the canonical GLB.
## These renders expose scale, grounding, silhouette, materials, and broad
## decimation drift; they do not prove gameplay placement or replace human review.

const VIEW_SIZE := Vector2i(1000, 760)


func _initialize() -> void:
	call_deferred("_render")


func _render() -> void:
	var options := _parse_options()
	var scene_path: String = options.get("scene", "")
	var output_directory: String = options.get("output-dir", "")
	var prefix: String = options.get("prefix", "candidate")
	if scene_path.is_empty() or output_directory.is_empty():
		_fail("Usage: --scene=res://path/to/wrapper.tscn --output-dir=/absolute/path [--prefix=name]")
		return

	var resource := load(scene_path) as PackedScene
	if resource == null:
		_fail("Could not load production wrapper: %s" % scene_path)
		return
	var absolute_output := output_directory
	if output_directory.begins_with("res://"):
		absolute_output = ProjectSettings.globalize_path(output_directory)
	var directory_error := DirAccess.make_dir_recursive_absolute(absolute_output)
	if directory_error != OK:
		_fail("Could not create output directory: %s" % error_string(directory_error))
		return

	var viewport := SubViewport.new()
	viewport.size = VIEW_SIZE
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.msaa_3d = Viewport.MSAA_4X
	viewport.use_taa = true
	root.add_child(viewport)

	var stage := Node3D.new()
	viewport.add_child(stage)
	_add_environment(stage)
	_add_lighting(stage)

	var prop := resource.instantiate() as Node3D
	if prop == null:
		_fail("Production wrapper root is not Node3D: %s" % scene_path)
		return
	stage.add_child(prop)
	await process_frame
	await process_frame

	var bounds := _mesh_bounds(prop)
	if bounds.size == Vector3.ZERO:
		_fail("Production wrapper contains no measurable mesh: %s" % scene_path)
		return
	_add_ground(stage, bounds.position.y)
	_add_reference(stage, bounds)

	var center := bounds.get_center()
	var radius := maxf(bounds.size.x, maxf(bounds.size.y, bounds.size.z))
	var distance := maxf(radius * 2.35, 5.0)
	var camera := Camera3D.new()
	camera.fov = 48.0
	camera.current = true
	stage.add_child(camera)
	var views := {
		"front_oblique": Vector3(0.75, 0.48, 0.75).normalized(),
		"rear_oblique": Vector3(-0.75, 0.48, -0.75).normalized(),
		"side": Vector3(1.0, 0.24, 0.0).normalized(),
		"high": Vector3(0.58, 0.95, 0.58).normalized(),
	}

	for view_name: String in views:
		camera.position = center + (views[view_name] as Vector3) * distance
		camera.look_at(center, Vector3.UP)
		await process_frame
		await RenderingServer.frame_post_draw
		var output_path := absolute_output.path_join("%s_%s.png" % [prefix, view_name])
		var save_error := viewport.get_texture().get_image().save_png(output_path)
		if save_error != OK:
			_fail("Could not save %s: %s" % [output_path, error_string(save_error)])
			return
		print("STATIC_PROP_REVIEW_RENDER=%s" % output_path)

	viewport.queue_free()
	await process_frame
	print("STATIC_PROP_REVIEW_OK")
	quit(0)


func _parse_options() -> Dictionary:
	var options := {}
	for argument in OS.get_cmdline_user_args():
		if not argument.begins_with("--") or not argument.contains("="):
			continue
		var separator := argument.find("=")
		options[argument.substr(2, separator - 2)] = argument.substr(separator + 1)
	return options


func _mesh_bounds(root_node: Node3D) -> AABB:
	var found := []
	_collect_mesh_bounds(root_node, root_node.global_transform.affine_inverse(), found)
	if found.is_empty():
		return AABB()
	var result: AABB = found[0]
	for index in range(1, found.size()):
		result = result.merge(found[index])
	return result


func _collect_mesh_bounds(node: Node, world_to_root: Transform3D, found: Array) -> void:
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		var mesh_instance := node as MeshInstance3D
		var to_root := world_to_root * mesh_instance.global_transform
		found.append(to_root * mesh_instance.mesh.get_aabb())
	for child in node.get_children():
		_collect_mesh_bounds(child, world_to_root, found)


func _add_reference(stage: Node3D, bounds: AABB) -> void:
	var reference := MeshInstance3D.new()
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.22
	capsule.height = 1.8
	reference.mesh = capsule
	reference.position = Vector3(bounds.position.x - 0.65, bounds.position.y + 0.9, bounds.get_center().z)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("4a91e8")
	material.roughness = 0.65
	reference.material_override = material
	stage.add_child(reference)


func _add_ground(stage: Node3D, height: float) -> void:
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(30.0, 30.0)
	ground.mesh = plane
	ground.position.y = height - 0.015
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("292d32")
	material.roughness = 0.92
	ground.material_override = material
	stage.add_child(ground)


func _add_environment(stage: Node3D) -> void:
	var world_environment := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_SKY
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	environment.ambient_light_energy = 0.75
	environment.tonemap_mode = Environment.TONE_MAPPER_AGX
	var sky := Sky.new()
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color("26364a")
	sky_material.sky_horizon_color = Color("8290a1")
	sky_material.ground_bottom_color = Color("12171d")
	sky_material.ground_horizon_color = Color("606973")
	sky.sky_material = sky_material
	environment.sky = sky
	world_environment.environment = environment
	stage.add_child(world_environment)


func _add_lighting(stage: Node3D) -> void:
	var sun := DirectionalLight3D.new()
	sun.light_color = Color("ffe4c4")
	sun.light_energy = 1.25
	sun.shadow_enabled = true
	sun.rotation_degrees = Vector3(-52.0, -38.0, 0.0)
	stage.add_child(sun)
	var fill := OmniLight3D.new()
	fill.light_color = Color("a7c7ff")
	fill.light_energy = 7.0
	fill.omni_range = 14.0
	fill.position = Vector3(-4.0, 5.0, 4.0)
	stage.add_child(fill)


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
