extends Node

class_name DayNightLightingController

@export var sun_energy := 1.25
@export var moon_energy := 0.46
@export var twilight_energy := 0.28
@export var celestial_distance := 180.0
@export var sun_disk_radius := 4.0
@export var moon_disk_radius := 5.8

var root_scene: Node
var world_time: Node
var sun: DirectionalLight3D
var moon: DirectionalLight3D
var world_environment: WorldEnvironment
var environment: Environment
var celestial_root: Node3D
var sun_disk: MeshInstance3D
var moon_disk: MeshInstance3D
var moon_halo_inner: MeshInstance3D
var moon_halo_outer: MeshInstance3D
var moon_glimmer: MeshInstance3D
var _glimmer_time := 0.0
var _initialized := false
var _stealth_ambient_visibility := 0.75


func initialize(target_root: Node, _target_hud: CanvasLayer = null) -> void:
	root_scene = target_root
	_try_initialize()


func _ready() -> void:
	_try_initialize()


func _process(delta: float) -> void:
	if not _initialized or world_time == null:
		return
	_glimmer_time += delta
	_apply_lighting(world_time.get_day_fraction())


func _try_initialize() -> void:
	if _initialized or root_scene == null or not is_inside_tree():
		return
	world_time = get_parent().get_node_or_null("WorldTimeController")
	if world_time == null:
		return
	sun = _ensure_directional_light("Sun")
	moon = _ensure_directional_light("Moon")
	world_environment = _ensure_world_environment()
	environment = world_environment.environment
	if environment == null:
		environment = Environment.new()
		world_environment.environment = environment
	environment.background_mode = Environment.BG_COLOR
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	sun.shadow_enabled = true
	moon.shadow_enabled = true
	moon.light_color = Color(0.38, 0.56, 1.0, 1.0)
	_ensure_celestial_bodies()
	_initialized = true
	_apply_lighting(world_time.get_day_fraction())


func _ensure_directional_light(node_name: String) -> DirectionalLight3D:
	var existing := root_scene.get_node_or_null(node_name) as DirectionalLight3D
	if existing != null:
		return existing
	var light := DirectionalLight3D.new()
	light.name = node_name
	root_scene.add_child(light)
	return light


func _ensure_world_environment() -> WorldEnvironment:
	var existing := root_scene.get_node_or_null("WorldEnvironment") as WorldEnvironment
	if existing != null:
		return existing
	var node := WorldEnvironment.new()
	node.name = "WorldEnvironment"
	root_scene.add_child(node)
	return node


func _ensure_celestial_bodies() -> void:
	celestial_root = root_scene.get_node_or_null("SkyCelestials") as Node3D
	if celestial_root == null:
		celestial_root = Node3D.new()
		celestial_root.name = "SkyCelestials"
		root_scene.add_child(celestial_root)
	celestial_root.top_level = true
	sun_disk = _ensure_celestial_sphere("SunDisk", sun_disk_radius, Color(1.0, 0.72, 0.28, 1.0))
	moon_disk = _ensure_celestial_sphere("MoonDisk", moon_disk_radius, Color(0.70, 0.86, 1.0, 1.0))
	moon_halo_inner = _ensure_celestial_sphere("MoonHaloInner", moon_disk_radius * 1.8, Color(0.30, 0.58, 1.0, 0.22))
	moon_halo_outer = _ensure_celestial_sphere("MoonHaloOuter", moon_disk_radius * 2.85, Color(0.13, 0.28, 0.92, 0.12))
	moon_glimmer = _ensure_celestial_sphere("MoonGlimmer", moon_disk_radius * 2.2, Color(0.68, 0.95, 1.0, 0.10))


func _ensure_celestial_sphere(node_name: String, radius: float, color: Color) -> MeshInstance3D:
	var existing := celestial_root.get_node_or_null(node_name) as MeshInstance3D
	if existing != null:
		return existing
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = node_name
	var sphere := SphereMesh.new()
	sphere.radius = radius
	sphere.height = radius * 2.0
	sphere.radial_segments = 64
	sphere.rings = 32
	mesh_instance.mesh = sphere
	mesh_instance.material_override = _make_celestial_material(color)
	celestial_root.add_child(mesh_instance)
	return mesh_instance


func _make_celestial_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = color
	return material


func _apply_lighting(day_fraction: float) -> void:
	var sun_angle := (day_fraction - 0.25) * TAU
	var sun_altitude := sin(sun_angle)
	var sun_horizontal := sqrt(maxf(0.0, 1.0 - sun_altitude * sun_altitude))
	var orbit_angle := day_fraction * TAU + deg_to_rad(35.0)
	var sun_direction := Vector3(cos(orbit_angle) * sun_horizontal, -sun_altitude, sin(orbit_angle) * sun_horizontal).normalized()
	var moon_direction := -sun_direction

	_orient_light(sun, sun_direction)
	_orient_light(moon, moon_direction)

	var day_amount := _smoothstep(-0.03, 0.28, sun_altitude)
	var night_amount := _smoothstep(0.04, 0.42, -sun_altitude)
	var twilight_amount := (1.0 - _smoothstep(0.0, 0.34, absf(sun_altitude))) * (1.0 - minf(day_amount, night_amount) * 0.35)

	sun.light_energy = maxf(day_amount * sun_energy, twilight_amount * twilight_energy)
	moon.light_energy = night_amount * moon_energy + twilight_amount * 0.08

	var dawn_color := Color(1.0, 0.64, 0.36, 1.0)
	var day_color := Color(1.0, 0.93, 0.78, 1.0)
	var dusk_color := Color(1.0, 0.44, 0.28, 1.0)
	var is_morning := day_fraction < 0.5
	sun.light_color = (dawn_color if is_morning else dusk_color).lerp(day_color, day_amount)
	moon.light_color = Color(0.34, 0.52, 1.0, 1.0).lerp(Color(0.52, 0.68, 1.0, 1.0), twilight_amount * 0.35)

	var night_sky := Color(0.018, 0.028, 0.085, 1.0)
	var twilight_sky := Color(0.43, 0.22, 0.42, 1.0).lerp(Color(0.88, 0.42, 0.23, 1.0), 0.35 if is_morning else 0.65)
	var day_sky := Color(0.48, 0.67, 0.95, 1.0)
	var sky_color := night_sky.lerp(twilight_sky, twilight_amount).lerp(day_sky, day_amount)
	environment.background_color = sky_color

	var night_ambient := Color(0.045, 0.07, 0.16, 1.0)
	var twilight_ambient := Color(0.34, 0.19, 0.34, 1.0).lerp(Color(0.55, 0.30, 0.20, 1.0), 0.4 if is_morning else 0.7)
	var day_ambient := Color(0.62, 0.62, 0.58, 1.0)
	environment.ambient_light_color = night_ambient.lerp(twilight_ambient, twilight_amount).lerp(day_ambient, day_amount)
	environment.ambient_light_energy = lerpf(0.32, 1.08, day_amount) + twilight_amount * 0.12
	_stealth_ambient_visibility = clampf(lerpf(0.16, 0.95, day_amount) + twilight_amount * 0.12 + night_amount * 0.06, 0.08, 1.0)
	_apply_celestial_bodies(-sun_direction, -moon_direction, day_amount, night_amount, twilight_amount)


func get_stealth_ambient_visibility() -> float:
	return _stealth_ambient_visibility


func _apply_celestial_bodies(sun_body_direction: Vector3, moon_body_direction: Vector3, day_amount: float, night_amount: float, twilight_amount: float) -> void:
	if celestial_root == null:
		return
	var anchor := _get_celestial_anchor()
	sun_disk.global_position = anchor + sun_body_direction.normalized() * celestial_distance
	moon_disk.global_position = anchor + moon_body_direction.normalized() * celestial_distance
	moon_halo_inner.global_position = moon_disk.global_position
	moon_halo_outer.global_position = moon_disk.global_position
	moon_glimmer.global_position = moon_disk.global_position

	var sun_visibility := clampf(day_amount * 0.96 + twilight_amount * 0.78, 0.0, 1.0)
	var moon_visibility := clampf(night_amount + twilight_amount * 0.55, 0.0, 1.0)
	var glimmer := 0.5 + 0.5 * sin(_glimmer_time * 1.7)
	var slow_glimmer := 0.5 + 0.5 * sin(_glimmer_time * 0.73 + 1.6)

	_set_celestial_alpha(sun_disk, Color(1.0, 0.72, 0.28, 1.0), sun_visibility)
	_set_celestial_alpha(moon_disk, Color(0.70, 0.86, 1.0, 1.0), moon_visibility * (0.88 + glimmer * 0.10))
	_set_celestial_alpha(moon_halo_inner, Color(0.30, 0.58, 1.0, 1.0), moon_visibility * (0.16 + glimmer * 0.08))
	_set_celestial_alpha(moon_halo_outer, Color(0.13, 0.28, 0.92, 1.0), moon_visibility * (0.08 + slow_glimmer * 0.06))
	_set_celestial_alpha(moon_glimmer, Color(0.68, 0.95, 1.0, 1.0), moon_visibility * (0.05 + glimmer * 0.08))

	sun_disk.visible = sun_visibility > 0.02
	moon_disk.visible = moon_visibility > 0.02
	moon_halo_inner.visible = moon_visibility > 0.02
	moon_halo_outer.visible = moon_visibility > 0.02
	moon_glimmer.visible = moon_visibility > 0.02
	moon_halo_inner.scale = Vector3.ONE * (1.0 + glimmer * 0.045)
	moon_halo_outer.scale = Vector3.ONE * (1.0 + slow_glimmer * 0.08)
	moon_glimmer.scale = Vector3.ONE * (1.0 + glimmer * 0.12)


func _get_celestial_anchor() -> Vector3:
	var camera := get_viewport().get_camera_3d()
	if camera != null:
		return camera.global_position
	if root_scene is Node3D:
		return (root_scene as Node3D).global_position
	return Vector3.ZERO


func _set_celestial_alpha(mesh_instance: MeshInstance3D, color: Color, alpha: float) -> void:
	if mesh_instance == null:
		return
	var material := mesh_instance.material_override as StandardMaterial3D
	if material == null:
		return
	material.albedo_color = Color(color.r, color.g, color.b, clampf(alpha, 0.0, 1.0))


func _orient_light(light: DirectionalLight3D, direction: Vector3) -> void:
	if light == null or direction.length_squared() <= 0.0001:
		return
	light.look_at(light.global_position + direction, Vector3.UP)


func _smoothstep(edge0: float, edge1: float, value: float) -> float:
	if is_equal_approx(edge0, edge1):
		return 0.0
	var t := clampf((value - edge0) / (edge1 - edge0), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)
