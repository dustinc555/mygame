extends Node3D

class_name LawDebugOverlay

const REFRESH_SECONDS := 0.5
const MAX_ACTOR_RINGS := 32

var show_actor_radii := false
var show_crime_events := true
var _remaining := 0.0


func set_actor_radii_visible(value: bool) -> void:
	show_actor_radii = value
	_remaining = 0.0


func set_crime_events_visible(value: bool) -> void:
	show_crime_events = value
	_remaining = 0.0


func _process(delta: float) -> void:
	if not visible:
		return
	_remaining -= delta
	if _remaining > 0.0:
		return
	_remaining = REFRESH_SECONDS
	_rebuild()


func _rebuild() -> void:
	for child in get_children():
		child.queue_free()
	var alerts := BootstrapContext.service(CrimeAlertController.SERVICE_ID) as CrimeAlertController
	if alerts == null:
		return
	if show_crime_events:
		for event_record in alerts.get_active_events():
			var origin = event_record.get("origin", Vector3.ZERO)
			if origin is Vector3:
				_add_ring(origin, float(event_record.get("radius", 40.0)), Color(1.0, 0.18, 0.08, 0.9))
	if not show_actor_radii:
		return
	var query := BootstrapContext.service(ActorQueryController.SERVICE_ID) as ActorQueryController
	if query == null:
		return
	var actors := query.get_alive_actors(true)
	actors.sort_custom(func(a: Node3D, b: Node3D) -> bool: return a.global_position.distance_squared_to(_focus_position()) < b.global_position.distance_squared_to(_focus_position()))
	for index in range(mini(actors.size(), MAX_ACTOR_RINGS)):
		var actor := actors[index] as WorldActor
		if actor != null:
			_add_ring(actor.global_position, alerts.get_alert_radius(), Color(1.0, 0.76, 0.12, 0.38))


func _focus_position() -> Vector3:
	var camera := get_viewport().get_camera_3d()
	return camera.global_position if camera != null else Vector3.ZERO


func _add_ring(origin: Vector3, radius: float, color: Color) -> void:
	var vertices := PackedVector3Array()
	const SEGMENTS := 64
	for index in range(SEGMENTS):
		var a0 := TAU * float(index) / float(SEGMENTS)
		var a1 := TAU * float(index + 1) / float(SEGMENTS)
		vertices.append(Vector3(cos(a0) * radius, 0.25, sin(a0) * radius))
		vertices.append(Vector3(cos(a1) * radius, 0.25, sin(a1) * radius))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, arrays)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = color
	material.no_depth_test = true
	var instance := MeshInstance3D.new()
	instance.position = origin
	instance.mesh = mesh
	instance.material_override = material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(instance)
