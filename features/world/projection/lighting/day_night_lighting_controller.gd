extends Node
class_name DayNightLightingController
## Owns the sky and its matching directional lights, never world-space sky meshes.
## WorldTimeController is the sole animation clock, including pause and save/load.

const SERVICE_ID := &"day_night_lighting"
const Settings = preload("res://features/world/resources/sky/sky_settings.gd")
const SKY_SHADER := preload("res://features/world/projection/lighting/celestial_sky.gdshader")
const MINUTES_PER_DAY := 1440.0

@export var sky_settings: Settings = preload("res://features/world/resources/sky/sky_settings.tres"):
	set(value):
		if sky_settings != null and sky_settings.changed.is_connected(_on_settings_changed):
			sky_settings.changed.disconnect(_on_settings_changed)
		sky_settings = value if value != null else Settings.new()
		if _initialized:
			sky_settings.changed.connect(_on_settings_changed)
			_on_settings_changed()

var root_scene: Node
var _context: BootstrapContext
var world_time: Node
var sun: DirectionalLight3D
var moon: DirectionalLight3D
var world_environment: WorldEnvironment
var environment: Environment
var sky: Sky
var sky_material: ShaderMaterial
var _initialized := false
var _last_minutes := -INF
var _stealth_ambient_visibility := 0.75


func initialize(context: BootstrapContext) -> void:
	root_scene = context.root_scene
	_context = context
	_try_initialize()


func _ready() -> void:
	_try_initialize()


func _exit_tree() -> void:
	if sky_settings != null and sky_settings.changed.is_connected(_on_settings_changed):
		sky_settings.changed.disconnect(_on_settings_changed)
	if is_instance_valid(world_time):
		if world_time.world_minutes_advanced.is_connected(_on_minutes_advanced):
			world_time.world_minutes_advanced.disconnect(_on_minutes_advanced)
		if world_time.time_changed.is_connected(_on_time_changed):
			world_time.time_changed.disconnect(_on_time_changed)
	_initialized = false


func _try_initialize() -> void:
	if _initialized or root_scene == null or not is_inside_tree():
		return
	world_time = _context.require(WorldTimeController.SERVICE_ID) if _context != null else null
	if world_time == null:
		return
	sun = _ensure_directional_light("Sun")
	moon = _ensure_directional_light("Moon")
	world_environment = root_scene.get_node_or_null("WorldEnvironment") as WorldEnvironment
	if world_environment == null:
		world_environment = WorldEnvironment.new()
		world_environment.name = "WorldEnvironment"
		root_scene.add_child(world_environment)
	environment = world_environment.environment.duplicate(true) if world_environment.environment != null else Environment.new()
	world_environment.environment = environment
	environment.background_mode = Environment.BG_SKY
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.glow_enabled = true
	environment.glow_intensity = 0.55
	environment.glow_bloom = 0.0
	environment.glow_hdr_threshold = 1.5
	sky = Sky.new()
	# Detailed background is independent of this deliberately cheap lighting cubemap.
	sky.process_mode = Sky.PROCESS_MODE_REALTIME
	sky.radiance_size = Sky.RADIANCE_SIZE_256
	sky_material = ShaderMaterial.new()
	sky_material.shader = SKY_SHADER
	sky.sky_material = sky_material
	environment.sky = sky
	sun.shadow_enabled = true
	moon.shadow_enabled = true
	# Sun/moon disks are drawn once by our shader, not by Godot light sky disks.
	sun.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY
	moon.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY
	var legacy := root_scene.get_node_or_null("SkyCelestials")
	if legacy != null:
		root_scene.remove_child(legacy)
		legacy.queue_free()
	_initialized = true
	world_time.world_minutes_advanced.connect(_on_minutes_advanced)
	world_time.time_changed.connect(_on_time_changed)
	sky_settings.changed.connect(_on_settings_changed)
	_on_settings_changed()


func _ensure_directional_light(node_name: String) -> DirectionalLight3D:
	var light := root_scene.get_node_or_null(node_name) as DirectionalLight3D
	if light == null:
		light = DirectionalLight3D.new()
		light.name = node_name
		root_scene.add_child(light)
	return light


func _on_minutes_advanced(minutes: float) -> void:
	_apply_lighting(minutes)


func _on_time_changed(_day: int, _weekday: String, _hour: int, _minute: int, _phase: String, _speed: String) -> void:
	_apply_lighting(world_time.total_world_minutes)


func _on_settings_changed() -> void:
	if not _initialized:
		return
	for property in [&"planet_surface", &"moon_surface", &"ring_profile", &"ring_inner_radius", &"ring_outer_radius", &"ring_density", &"ring_brightness", &"nebula_brightness", &"nebula_coverage", &"nebula_teal", &"nebula_violet", &"star_brightness", &"cloud_coverage", &"aurora_brightness"]:
		sky_material.set_shader_parameter(property, sky_settings.get(property))
	sky_material.set_shader_parameter("planet_radius", sin(deg_to_rad(sky_settings.planet_diameter_degrees * 0.5)))
	sky_material.set_shader_parameter("moon_radius", sin(deg_to_rad(sky_settings.moon_diameter_degrees * 0.5)))
	sky_material.set_shader_parameter("sun_radius", deg_to_rad(sky_settings.sun_diameter_degrees * 0.5))
	_last_minutes = -INF
	_apply_lighting(world_time.total_world_minutes)


## A deterministic visual ephemeris. Only periodic angles wrap; the clock does not.
## This is also used by rendered validation, rather than copying orbital equations.
func sample_sky_state(absolute_minutes: float) -> Dictionary:
	var days := absolute_minutes / MINUTES_PER_DAY
	var sun_angle := fposmod(days - 0.25, 1.0) * TAU
	var sun_direction := _orbit_direction(sun_angle, deg_to_rad(23.0))
	var phase := fposmod(days / sky_settings.moon_orbit_days + sky_settings.moon_phase_offset, 1.0) * TAU
	var moon_direction := _orbit_direction(sun_angle + PI + phase, deg_to_rad(28.0))
	var star_basis := Basis(Vector3(0.0, 0.82, 0.57).normalized(), fposmod(days, 1.0) * TAU)
	var heading := deg_to_rad(sky_settings.planet_heading_degrees) + fposmod(days / sky_settings.planet_orbit_days, 1.0) * TAU
	var altitude := deg_to_rad(sky_settings.planet_altitude_degrees)
	var planet_direction := star_basis * Vector3(sin(heading) * cos(altitude), sin(altitude), cos(heading) * cos(altitude))
	var planet_axis := (star_basis * Vector3(sin(deg_to_rad(sky_settings.planet_axial_tilt_degrees)), 0.90, 0.35)).normalized()
	var planet_right := planet_axis.cross(Vector3.FORWARD).normalized()
	var planet_basis := Basis(planet_right, planet_axis, planet_right.cross(planet_axis)).orthonormalized()
	var day_amount := smoothstep(-0.03, 0.28, sun_direction.y)
	var night_amount := smoothstep(0.04, 0.42, -sun_direction.y)
	var twilight_amount := (1.0 - smoothstep(0.0, 0.34, absf(sun_direction.y))) * (1.0 - minf(day_amount, night_amount) * 0.35)
	return {
		"sun_direction": sun_direction,
		"moon_direction": moon_direction,
		"planet_direction": planet_direction.normalized(),
		"planet_basis": planet_basis,
		"star_basis": star_basis.inverse(),
		"planet_spin": fposmod(days / sky_settings.planet_rotation_days, 1.0),
		"moon_phase": clampf((1.0 - moon_direction.dot(sun_direction)) * 0.5, 0.0, 1.0),
		"day_amount": day_amount,
		"night_amount": night_amount,
		"twilight_amount": twilight_amount,
		# Bounded periodic wind coordinates remain continuous through day boundaries.
		"cloud_offset": Vector2(sin(days * 24.0 * sky_settings.cloud_wind_speed), cos(days * 24.0 * sky_settings.cloud_wind_speed)) * 12.0,
		"aurora_phase": fposmod(days * 4.0, TAU),
	}


func _orbit_direction(angle: float, tilt: float) -> Vector3:
	return Vector3(cos(angle), sin(angle) * cos(tilt), sin(angle) * sin(tilt)).rotated(Vector3.UP, deg_to_rad(35.0)).normalized()


func _apply_lighting(absolute_minutes: float) -> void:
	if not _initialized or absolute_minutes == _last_minutes:
		return
	_last_minutes = absolute_minutes
	var state := sample_sky_state(absolute_minutes)
	for property in [&"sun_direction", &"moon_direction", &"planet_direction", &"planet_basis", &"star_basis", &"planet_spin", &"day_amount", &"night_amount", &"twilight_amount", &"cloud_offset", &"aurora_phase"]:
		sky_material.set_shader_parameter(property, state[property])
	var day: float = state["day_amount"]
	var twilight: float = state["twilight_amount"]
	var sun_direction: Vector3 = state["sun_direction"]
	var moon_direction: Vector3 = state["moon_direction"]
	_orient_light(sun, -sun_direction)
	_orient_light(moon, -moon_direction)
	sun.light_energy = maxf(day * sky_settings.sun_energy, twilight * sky_settings.twilight_energy)
	moon.light_energy = sky_settings.moon_energy * smoothstep(-0.04, 0.25, moon_direction.y) * float(state["moon_phase"]) * (1.0 - day)
	sun.light_color = Color(1.0, 0.55, 0.30).lerp(Color(1.0, 0.94, 0.83), day)
	moon.light_color = Color(0.66, 0.76, 0.94)
	environment.ambient_light_color = Color(0.18, 0.23, 0.34).lerp(Color(0.45, 0.28, 0.29), twilight).lerp(Color(0.62, 0.62, 0.58), day)
	environment.ambient_light_energy = lerpf(sky_settings.night_ambient_energy, 1.08, day) + twilight * 0.12
	# Preserve gameplay's existing visibility curve independently of art direction.
	var gameplay_altitude := sin((fposmod(absolute_minutes / MINUTES_PER_DAY, 1.0) - 0.25) * TAU)
	var gameplay_day := smoothstep(-0.03, 0.28, gameplay_altitude)
	var gameplay_night := smoothstep(0.04, 0.42, -gameplay_altitude)
	var gameplay_twilight := (1.0 - smoothstep(0.0, 0.34, absf(gameplay_altitude))) * (1.0 - minf(gameplay_day, gameplay_night) * 0.35)
	_stealth_ambient_visibility = clampf(lerpf(0.16, 0.95, gameplay_day) + gameplay_twilight * 0.12 + gameplay_night * 0.06, 0.08, 1.0)


func get_stealth_ambient_visibility() -> float:
	return _stealth_ambient_visibility


func _orient_light(light: DirectionalLight3D, direction: Vector3) -> void:
	var up := Vector3.FORWARD if absf(direction.dot(Vector3.UP)) > 0.98 else Vector3.UP
	light.look_at(light.global_position + direction, up)
