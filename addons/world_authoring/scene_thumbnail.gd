@tool
extends SubViewport

## One-shot, editor-only previews of real static scene geometry. PackedScene
## preview-cache entries are optional in Godot, so the catalog renders its own
## images without saving/reopening source scenes or running gameplay scripts.
const IMAGE_SIZE := 256
var _jobs: Array[Dictionary] = []
var _active: Dictionary = {}
var _visuals: Node3D
var _camera: Camera3D

func _init() -> void:
	size = Vector2i(IMAGE_SIZE, IMAGE_SIZE)
	own_world_3d = true
	transparent_bg = true
	render_target_update_mode = SubViewport.UPDATE_DISABLED
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0, 0, 0, 0)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color.WHITE
	environment.environment.ambient_light_energy = 0.65
	add_child(environment)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-45, -35, 0)
	key.light_energy = 1.7
	add_child(key)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-20, 140, 0)
	fill.light_energy = 0.65
	add_child(fill)
	_camera = Camera3D.new()
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.near = 0.01
	_camera.far = 100000
	add_child(_camera)
	set_process(false)

func request(scene_path: String, callback: Callable) -> void:
	_jobs.append({"path": scene_path, "callback": callback})
	set_process(true)

func _process(_delta: float) -> void:
	if not _active.is_empty():
		return
	if _jobs.is_empty():
		set_process(false)
		return
	var job: Dictionary = _jobs.pop_front()
	var packed := load(str(job.path)) as PackedScene
	if packed == null:
		if job.callback.is_valid():
			job.callback.call(null)
		return
	var source := packed.instantiate()
	_visuals = Node3D.new()
	_copy_meshes(source, Transform3D.IDENTITY, _visuals)
	source.free()
	if _visuals.get_child_count() == 0:
		_visuals.free()
		_visuals = null
		if job.callback.is_valid():
			job.callback.call(null)
		return
	var bounds := AABB()
	var first := true
	for mesh: MeshInstance3D in _visuals.get_children():
		var mesh_bounds := mesh.transform * mesh.get_aabb()
		bounds = mesh_bounds if first else bounds.merge(mesh_bounds)
		first = false
	add_child(_visuals)
	var span := maxf(bounds.size.x, maxf(bounds.size.y, bounds.size.z))
	var center := bounds.get_center()
	_camera.position = center + Vector3(1, 0.75, 1).normalized() * maxf(span * 3.0, 1.0)
	_camera.look_at(center, Vector3.UP)
	var view_bounds := _camera.transform.affine_inverse() * bounds
	_camera.size = maxf(maxf(view_bounds.size.x, view_bounds.size.y) * 1.15, 0.1)
	_camera.make_current()
	_active = job
	render_target_update_mode = SubViewport.UPDATE_ONCE
	# Let the normal editor frame draw the preview. force_draw redraws the
	# entire town as well, turning a thumbnail queue into repeated stalls.
	RenderingServer.frame_post_draw.connect(_capture, CONNECT_ONE_SHOT)

func _capture() -> void:
	var image := get_texture().get_image()
	var texture := ImageTexture.create_from_image(image) if image != null and not image.is_empty() else null
	var callback: Callable = _active.callback
	_active.clear()
	_visuals.queue_free()
	_visuals = null
	render_target_update_mode = SubViewport.UPDATE_DISABLED
	if callback.is_valid():
		callback.call(texture)

func _exit_tree() -> void:
	if RenderingServer.frame_post_draw.is_connected(_capture):
		RenderingServer.frame_post_draw.disconnect(_capture)

static func _copy_meshes(node: Node, parent_transform: Transform3D, destination: Node3D) -> void:
	var transform := parent_transform
	if node is Node3D:
		if not node.visible:
			return
		transform *= node.transform
	if node is MeshInstance3D and node.mesh != null:
		var mesh := MeshInstance3D.new()
		mesh.mesh = node.mesh
		mesh.transform = transform
		mesh.material_override = node.material_override
		for surface in range(node.mesh.get_surface_count()):
			mesh.set_surface_override_material(surface, node.get_surface_override_material(surface))
		destination.add_child(mesh)
	# Containers and props author their model as data; their ModelRoot is empty
	# until _ready. Copy that data explicitly rather than running gameplay nodes
	# in the preview viewport (which would register storage/collisions/services).
	for property in node.get_property_list():
		if property.name != "visual_scene":
			continue
		var packed := node.get("visual_scene") as PackedScene
		if packed != null:
			var visual := packed.instantiate()
			var visual_transform: Transform3D = node.get("visual_transform")
			_copy_meshes(visual, transform * visual_transform, destination)
			visual.free()
		break
	for child in node.get_children(true):
		_copy_meshes(child, transform, destination)
