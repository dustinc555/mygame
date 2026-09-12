extends SubViewportContainer
## Small isolated studio; no actor/model configuration belongs here.
const RULER = preload("res://tools/outfitter/outfitter_ruler.gd")
var ruler: Control
var world: Node3D
var camera: Camera3D
var floor_mesh: MeshInstance3D
var focus := Vector3(0, 0.95, 0)
var distance := 3.5
var yaw := PI
var pitch := 0.05
var tracking: Node3D

func _ready() -> void:
	stretch = true
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	var viewport := SubViewport.new()
	viewport.own_world_3d = true
	viewport.msaa_3d = Viewport.MSAA_2X
	add_child(viewport)
	world = Node3D.new()
	viewport.add_child(world)
	camera = Camera3D.new()
	camera.current = true
	camera.fov = 40
	camera.near = 0.01
	world.add_child(camera)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("19212b")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color("dce6ff")
	environment.environment.ambient_light_energy = 0.65
	world.add_child(environment)
	for settings in [Vector3(-40, -35, 1.4), Vector3(-20, 145, 0.45)]:
		var light := DirectionalLight3D.new()
		light.rotation_degrees = Vector3(settings.x, settings.y, 0)
		light.light_energy = settings.z
		world.add_child(light)
	floor_mesh = MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(30, 30)
	floor_mesh.mesh = plane
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("29313b")
	floor_mesh.material_override = material
	floor_mesh.position.y = -0.015
	world.add_child(floor_mesh)
	ruler = RULER.new()
	ruler.name = "HeightRuler"
	ruler.camera = camera
	resized.connect(func(): ruler.queue_redraw())
	gui_input.connect(_input_view)
	update_camera()

func _process(_delta: float) -> void:
	if is_instance_valid(tracking):
		focus = tracking.global_position
		update_camera()

func frame_body(body: BodyProjection) -> void:
	tracking = null
	var bounds := body.get_visual_local_bounds()
	focus = bounds.get_center()
	camera.fov = 40
	var aspect := maxf(size.x / maxf(size.y, 1.0), 1.0)
	var extent := maxf(bounds.size.y, bounds.size.x / aspect)
	distance = maxf(extent / (2.0 * tan(deg_to_rad(camera.fov * 0.5))) * 1.15, 0.25)
	update_camera()

func set_body_reference(bounds: AABB) -> void:
	# Geometry units are world meters; this is a scale, not an actor-height claim.
	floor_mesh.position.y = bounds.position.y - 0.015
	ruler.configure(bounds)

func frame_hand(hand: Node3D) -> bool:
	return track_hand(hand, true)

func track_hand(hand: Node3D, reframe: bool = false) -> bool:
	# Losing/rebuilding a socket never resets the user's last view.
	tracking = hand
	if not is_instance_valid(hand): return false
	focus = hand.global_position
	if reframe:
		distance = 1.05
		camera.fov = 20
	update_camera()
	return true

func set_view(new_yaw: float, new_pitch: float, new_distance: float) -> void:
	yaw = new_yaw
	pitch = clampf(new_pitch, -1.4, 1.4)
	distance = clampf(new_distance, 0.12, 30.0)
	update_camera()

func update_camera() -> void:
	camera.position = focus + Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch)) * distance
	camera.look_at(focus)
	if ruler != null and ruler.visible: ruler.queue_redraw()

func _input_view(event: InputEvent) -> void:
	if event is InputEventMouseMotion and (event.button_mask & (MOUSE_BUTTON_MASK_LEFT | MOUSE_BUTTON_MASK_RIGHT)) != 0:
		set_view(yaw - event.relative.x * 0.008, pitch + event.relative.y * 0.008, distance)
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP: set_view(yaw, pitch, distance * 0.9)
		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN: set_view(yaw, pitch, distance / 0.9)
