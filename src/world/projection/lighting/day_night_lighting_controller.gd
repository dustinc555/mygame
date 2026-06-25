extends Node

class_name DayNightLightingController

const ALIEN_MOON_TEXTURE := preload("res://assets/vendor/quaternius/sci_fi_essentials_kit/gltf/planet_textures/T_Water_2.png")
const CLOUDS_2_TEXTURE := preload("res://assets/vendor/quaternius/sci_fi_essentials_kit/gltf/planet_textures/T_Clouds_2.png")
const DISTANT_PLANET_TEXTURE := preload("res://assets/vendor/quaternius/sci_fi_essentials_kit/gltf/planet_textures/T_Ground_2.png")
const EQUATOR_TEXTURE := preload("res://assets/vendor/quaternius/sci_fi_essentials_kit/gltf/planet_textures/T_GradientEquator.png")
const HOLOGRAM_TEXTURE := preload("res://assets/vendor/quaternius/sci_fi_essentials_kit/gltf/planet_textures/T_HologramPlanet.png")
const NOISE_GRAINY_TEXTURE := preload("res://assets/vendor/quaternius/sci_fi_essentials_kit/gltf/planet_textures/T_Noise_Grainy.png")
const PLANET_LINES_TEXTURE := preload("res://assets/vendor/quaternius/sci_fi_essentials_kit/gltf/planet_textures/T_PlanetLines.png")
const RINGS_TEXTURE := preload("res://assets/vendor/quaternius/sci_fi_essentials_kit/gltf/planet_textures/T_Rings.png")
const SMALL_PLANET_TEXTURE_A := preload("res://assets/vendor/quaternius/sci_fi_essentials_kit/gltf/planet_textures/T_Ground_1.png")
const SMALL_PLANET_TEXTURE_B := preload("res://assets/vendor/quaternius/sci_fi_essentials_kit/gltf/planet_textures/T_AlienDotted.png")
const SMALL_PLANET_TEXTURE_C := preload("res://assets/vendor/quaternius/sci_fi_essentials_kit/gltf/planet_textures/T_Clouds_1.png")
const STREAKS_TEXTURE := preload("res://assets/vendor/quaternius/sci_fi_essentials_kit/gltf/planet_textures/T_Streaks.png")

const SKY_PANORAMA_WIDTH := 1024
const SKY_PANORAMA_HEIGHT := 512
const SKY_PANORAMA_BUCKETS_PER_DAY := 24
const SKY_PANORAMA_FALLBACK_WIDTH := 64
const SKY_PANORAMA_FALLBACK_HEIGHT := 32
const SKY_CROSSFADE_SECONDS := 7.0
const SKY_CLOUD_ROTATION_SPEED := 0.00055
const SKY_NEBULA_ROTATION_SPEED := 0.00016
const SKY_CLEAR_ROTATION_SPEED := 0.00005
const SKY_CROSSFADE_SHADER_CODE := """
shader_type sky;

uniform sampler2D current_panorama : source_color, filter_linear, repeat_enable;
uniform sampler2D next_panorama : source_color, filter_linear, repeat_enable;
uniform float fade_amount : hint_range(0.0, 1.0) = 0.0;
uniform float panorama_rotation = 0.0;

vec2 panorama_uv(vec3 direction) {
	float longitude = atan(direction.x, direction.z);
	float latitude = asin(clamp(direction.y, -1.0, 1.0));
	return vec2(fract(longitude / 6.28318530718), 0.5 - latitude / 3.14159265359);
}

void sky() {
	vec2 uv = panorama_uv(normalize(EYEDIR));
	uv.x = fract(uv.x + panorama_rotation);
	vec3 current_color = texture(current_panorama, uv).rgb;
	vec3 next_color = texture(next_panorama, uv).rgb;
	COLOR = mix(current_color, next_color, clamp(fade_amount, 0.0, 1.0));
	ALPHA = 1.0;
}
"""

@export var sun_energy := 1.25
@export var moon_energy := 0.46
@export var twilight_energy := 0.28
@export var celestial_distance := 180.0
@export var sun_disk_radius := 4.0
@export var moon_disk_radius := 5.8
@export var distant_planet_radius := 18.5
@export var minor_planet_radius := 3.6
@export var horizon_min_altitude := 0.07
@export var horizon_fade_altitude := 0.18
@export_range(0, 500, 1) var star_count := 380
@export var star_field_distance := 235.0
@export_range(0.05, 0.95, 0.01) var nebula_coverage := 0.34

var root_scene: Node
var world_time: Node
var sun: DirectionalLight3D
var moon: DirectionalLight3D
var world_environment: WorldEnvironment
var environment: Environment
var sky: Sky
var sky_material: ShaderMaterial
var celestial_root: Node3D
var sun_disk: MeshInstance3D
var moon_disk: MeshInstance3D
var moon_halo_inner: MeshInstance3D
var moon_halo_outer: MeshInstance3D
var moon_glimmer: MeshInstance3D
var distant_planet_disk: MeshInstance3D
var distant_planet_ring: MeshInstance3D
var small_planet_a_disk: MeshInstance3D
var small_planet_b_disk: MeshInstance3D
var small_planet_c_disk: MeshInstance3D
var equator_planet_disk: MeshInstance3D
var hologram_planet_disk: MeshInstance3D
var line_planet_disk: MeshInstance3D
var streak_planet_disk: MeshInstance3D
var grain_planet_disk: MeshInstance3D
var stone_planet_disk: MeshInstance3D
var star_field_root: Node3D
var _star_records: Array[Dictionary] = []
var _star_mesh: SphereMesh
var _sky_visible_texture: ImageTexture
var _sky_panorama_texture: ImageTexture
var _sky_panorama_bucket := -1
var _sky_panorama_mode := ""
var _sky_panorama_thread: Thread
var _sky_panorama_build_bucket := -1
var _sky_panorama_build_mode := ""
var _sky_panorama_build_active := false
var _sky_panorama_queued_bucket := -1
var _sky_panorama_queued_mode := ""
var _sky_panorama_queued_day_fraction := 0.0
var _sky_panorama_queued_top := Color.BLACK
var _sky_panorama_queued_horizon := Color.BLACK
var _sky_panorama_queued_nebula_visibility := 0.0
var _sky_panorama_queued_cloud_visibility := 0.0
var _sky_crossfade_active := false
var _sky_crossfade_elapsed := 0.0
var _sky_crossfade_target_texture: ImageTexture
var _sky_panorama_rotation := 0.0
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
	_poll_sky_panorama_build()
	_update_sky_panorama_rotation(delta)
	_update_sky_crossfade(delta)


func _exit_tree() -> void:
	if _sky_panorama_thread != null and _sky_panorama_thread.is_started():
		_sky_panorama_thread.wait_to_finish()
	_sky_panorama_thread = null


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
	environment.background_mode = Environment.BG_SKY
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_ensure_panorama_sky()
	sun.shadow_enabled = true
	moon.shadow_enabled = true
	moon.light_color = Color(0.38, 0.56, 1.0, 1.0)
	_ensure_celestial_bodies()
	_initialized = true
	# TODO(save/load): Apply restored world time before showing/crossfading sky, so loading a midnight save cannot briefly display the default daytime sky.
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


func _ensure_panorama_sky() -> void:
	if environment == null:
		return
	sky = environment.sky
	if sky == null:
		sky = Sky.new()
		environment.sky = sky
	sky.process_mode = Sky.PROCESS_MODE_AUTOMATIC
	sky.radiance_size = Sky.RADIANCE_SIZE_256
	sky_material = sky.sky_material as ShaderMaterial
	if sky_material == null or sky_material.shader == null or sky_material.shader.code != SKY_CROSSFADE_SHADER_CODE:
		var shader := Shader.new()
		shader.code = SKY_CROSSFADE_SHADER_CODE
		sky_material = ShaderMaterial.new()
		sky_material.shader = shader
		sky.sky_material = sky_material
	sky_material.set_shader_parameter("fade_amount", 0.0)
	sky_material.set_shader_parameter("panorama_rotation", _sky_panorama_rotation)


func _ensure_celestial_bodies() -> void:
	celestial_root = root_scene.get_node_or_null("SkyCelestials") as Node3D
	if celestial_root == null:
		celestial_root = Node3D.new()
		celestial_root.name = "SkyCelestials"
		root_scene.add_child(celestial_root)
	celestial_root.top_level = true
	sun_disk = _ensure_celestial_sphere("SunDisk", sun_disk_radius, Color(1.0, 0.72, 0.28, 1.0), null, 1)
	moon_disk = _ensure_celestial_sphere("MoonDisk", moon_disk_radius, Color(0.66, 0.80, 1.0, 1.0), ALIEN_MOON_TEXTURE, 3)
	moon_halo_inner = _ensure_celestial_sphere("MoonHaloInner", moon_disk_radius * 1.8, Color(0.30, 0.58, 1.0, 0.22), null, -2)
	moon_halo_outer = _ensure_celestial_sphere("MoonHaloOuter", moon_disk_radius * 2.85, Color(0.13, 0.28, 0.92, 0.12), null, -3)
	moon_glimmer = _ensure_celestial_sphere("MoonGlimmer", moon_disk_radius * 2.2, Color(0.68, 0.95, 1.0, 0.10), null, -1)
	distant_planet_disk = _ensure_celestial_sphere("DistantAlienPlanet", distant_planet_radius, Color(0.92, 0.62, 0.36, 1.0), DISTANT_PLANET_TEXTURE, 2)
	distant_planet_ring = _ensure_celestial_ring("DistantAlienPlanetRings", distant_planet_radius * 1.08, distant_planet_radius * 1.78, Color(0.78, 0.58, 0.36, 0.42), RINGS_TEXTURE, 1)
	small_planet_a_disk = _ensure_celestial_sphere("SmallAlienPlanetA", minor_planet_radius * 1.18, Color(0.90, 0.58, 1.0, 1.0), SMALL_PLANET_TEXTURE_B, 1)
	small_planet_b_disk = _ensure_celestial_sphere("SmallAlienPlanetB", minor_planet_radius * 0.86, Color(1.0, 0.46, 0.34, 1.0), DISTANT_PLANET_TEXTURE, 1)
	small_planet_c_disk = _ensure_celestial_sphere("SmallAlienPlanetC", minor_planet_radius * 0.62, Color(0.74, 0.86, 1.0, 1.0), CLOUDS_2_TEXTURE, 1)
	equator_planet_disk = _ensure_celestial_sphere("EquatorGlowPlanet", minor_planet_radius * 0.78, Color(0.70, 1.0, 0.92, 1.0), EQUATOR_TEXTURE, 1)
	hologram_planet_disk = _ensure_celestial_sphere("HologramSignalPlanet", minor_planet_radius * 1.04, Color(1.0, 0.64, 0.92, 1.0), HOLOGRAM_TEXTURE, 1)
	line_planet_disk = _ensure_celestial_sphere("LineScriptPlanet", minor_planet_radius * 0.95, Color(0.58, 0.92, 1.0, 1.0), PLANET_LINES_TEXTURE, 1)
	streak_planet_disk = _ensure_celestial_sphere("StreakedDreamPlanet", minor_planet_radius * 0.72, Color(1.0, 0.78, 0.46, 1.0), STREAKS_TEXTURE, 1)
	grain_planet_disk = _ensure_celestial_sphere("GrainyVioletPlanet", minor_planet_radius * 0.58, Color(0.74, 0.56, 1.0, 1.0), NOISE_GRAINY_TEXTURE, 1)
	stone_planet_disk = _ensure_celestial_sphere("StoneMoonletPlanet", minor_planet_radius * 0.66, Color(0.82, 0.70, 0.56, 1.0), SMALL_PLANET_TEXTURE_A, 1)
	_remove_legacy_nebula_geometry()
	_ensure_star_field()


func _ensure_celestial_sphere(node_name: String, radius: float, color: Color, texture: Texture2D = null, render_priority: int = 0) -> MeshInstance3D:
	var existing := celestial_root.get_node_or_null(node_name) as MeshInstance3D
	if existing != null:
		_configure_celestial_sphere(existing, radius, color, texture, render_priority)
		return existing
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = node_name
	_configure_celestial_sphere(mesh_instance, radius, color, texture, render_priority)
	celestial_root.add_child(mesh_instance)
	return mesh_instance


func _configure_celestial_sphere(mesh_instance: MeshInstance3D, radius: float, color: Color, texture: Texture2D = null, render_priority: int = 0) -> void:
	var sphere := SphereMesh.new()
	sphere.radius = radius
	sphere.height = radius * 2.0
	sphere.radial_segments = 64
	sphere.rings = 32
	mesh_instance.mesh = sphere
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mesh_instance.material_override = _make_celestial_material(color, texture, render_priority)


func _ensure_celestial_ring(node_name: String, inner_radius: float, outer_radius: float, color: Color, texture: Texture2D, render_priority: int = 0) -> MeshInstance3D:
	var existing := celestial_root.get_node_or_null(node_name) as MeshInstance3D
	if existing != null:
		_configure_celestial_ring(existing, inner_radius, outer_radius, color, texture, render_priority)
		return existing
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = node_name
	_configure_celestial_ring(mesh_instance, inner_radius, outer_radius, color, texture, render_priority)
	celestial_root.add_child(mesh_instance)
	return mesh_instance


func _configure_celestial_ring(mesh_instance: MeshInstance3D, inner_radius: float, outer_radius: float, color: Color, texture: Texture2D, render_priority: int = 0) -> void:
	var torus := TorusMesh.new()
	torus.inner_radius = inner_radius
	torus.outer_radius = outer_radius
	torus.rings = 18
	torus.ring_segments = 144
	mesh_instance.mesh = torus
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mesh_instance.material_override = _make_celestial_material(color, texture, render_priority, true, true)


func _make_celestial_material(color: Color, texture: Texture2D = null, render_priority: int = 0, additive: bool = false, disable_cull: bool = false) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if additive:
		material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	if disable_cull:
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.render_priority = render_priority
	material.albedo_color = color
	material.albedo_texture = texture
	return material


func _remove_legacy_nebula_geometry() -> void:
	for node_name in ["AuroraNebulaRibbonA", "AuroraNebulaRibbonB", "AuroraNebulaRibbonC", "AuroraNebulaPuffs"]:
		var existing := celestial_root.get_node_or_null(node_name)
		if existing != null:
			existing.queue_free()


func _ensure_star_field() -> void:
	star_field_root = celestial_root.get_node_or_null("StarField") as Node3D
	if star_field_root == null:
		star_field_root = Node3D.new()
		star_field_root.name = "StarField"
		celestial_root.add_child(star_field_root)
	star_field_root.top_level = true
	for child in star_field_root.get_children():
		star_field_root.remove_child(child)
		child.queue_free()
	_star_records.clear()
	if star_count <= 0:
		return
	_star_mesh = SphereMesh.new()
	_star_mesh.radius = 0.5
	_star_mesh.height = 1.0
	_star_mesh.radial_segments = 8
	_star_mesh.rings = 4
	var rng := RandomNumberGenerator.new()
	rng.seed = 794237
	for index in range(star_count):
		var star_record := _create_star_record(rng, index)
		var star := MeshInstance3D.new()
		star.name = "Star%03d" % index
		star.mesh = _star_mesh
		star.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		star.position = star_record["direction"] * star_field_distance
		star.scale = Vector3.ONE * float(star_record["size"])
		var material := _make_celestial_material(star_record["color"])
		star.material_override = material
		star_field_root.add_child(star)
		star_record["node"] = star
		star_record["material"] = material
		_star_records.append(star_record)


func _create_star_record(rng: RandomNumberGenerator, index: int) -> Dictionary:
	var in_star_river := rng.randf() < 0.42
	var hero_glimmer := index < 12 or rng.randf() < 0.09
	var size := rng.randf_range(0.18, 0.42)
	var base_alpha := rng.randf_range(0.32, 0.84)
	if in_star_river:
		size *= rng.randf_range(0.82, 1.18)
		base_alpha *= rng.randf_range(0.62, 0.92)
	if hero_glimmer:
		size = rng.randf_range(0.48, 1.02)
		base_alpha = rng.randf_range(0.72, 1.0)
	return {
		"direction": _star_river_direction(rng) if in_star_river else _random_sky_direction(rng),
		"color": _star_color(rng, hero_glimmer, in_star_river),
		"size": size,
		"base_alpha": base_alpha,
		"twinkle_speed": rng.randf_range(0.22, 1.12),
		"twinkle_phase": rng.randf_range(0.0, TAU),
		"slow_speed": rng.randf_range(0.07, 0.34),
		"slow_phase": rng.randf_range(0.0, TAU),
		"pulse_speed": rng.randf_range(0.045, 0.14),
		"pulse_phase": rng.randf_range(0.0, TAU),
		"pulse_strength": rng.randf_range(0.18, 0.58) if hero_glimmer else rng.randf_range(0.04, 0.16),
		"pulse_scale": rng.randf_range(0.22, 0.52) if hero_glimmer else rng.randf_range(0.04, 0.16),
	}


func _random_sky_direction(rng: RandomNumberGenerator) -> Vector3:
	var y := rng.randf_range(0.10, 0.98)
	var angle := rng.randf_range(0.0, TAU)
	var horizontal := sqrt(maxf(0.0, 1.0 - y * y))
	return Vector3(cos(angle) * horizontal, y, sin(angle) * horizontal).normalized()


func _star_river_direction(rng: RandomNumberGenerator) -> Vector3:
	var angle := rng.randf_range(0.0, TAU)
	var band_height := 0.44 + 0.22 * sin(angle * 1.7 + 0.8)
	var y := clampf(band_height + rng.randf_range(-0.075, 0.075), 0.12, 0.94)
	var horizontal := sqrt(maxf(0.0, 1.0 - y * y))
	var river_angle := angle + deg_to_rad(24.0)
	return Vector3(cos(river_angle) * horizontal, y, sin(river_angle) * horizontal).normalized()


func _star_color(rng: RandomNumberGenerator, hero_glimmer: bool, in_star_river: bool) -> Color:
	var roll := rng.randf()
	if hero_glimmer:
		if roll < 0.30:
			return Color(0.78, 0.56, 1.0, 1.0)
		if roll < 0.56:
			return Color(0.58, 0.78, 1.0, 1.0)
		if roll < 0.78:
			return Color(0.76, 1.0, 0.94, 1.0)
		return Color(1.0, 0.78, 0.42, 1.0)
	if in_star_river:
		return Color(0.78, 0.92, 1.0, 1.0).lerp(Color(0.70, 0.46, 1.0, 1.0), rng.randf_range(0.0, 0.42))
	if roll < 0.12:
		return Color(1.0, 0.82, 0.55, 1.0)
	if roll < 0.26:
		return Color(0.94, 0.62, 1.0, 1.0)
	if roll < 0.46:
		return Color(0.66, 0.82, 1.0, 1.0)
	return Color(0.94, 0.97, 1.0, 1.0)


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

	var night_sky_top := Color(0.038, 0.052, 0.135, 1.0)
	var night_sky_horizon := Color(0.075, 0.090, 0.205, 1.0)
	var twilight_sky_top := Color(0.22, 0.11, 0.38, 1.0).lerp(Color(0.55, 0.24, 0.24, 1.0), 0.35 if is_morning else 0.65)
	var twilight_sky_horizon := Color(0.46, 0.20, 0.48, 1.0).lerp(Color(0.88, 0.42, 0.23, 1.0), 0.35 if is_morning else 0.65)
	var day_sky_top := Color(0.40, 0.61, 0.92, 1.0)
	var day_sky_horizon := Color(0.66, 0.78, 0.98, 1.0)
	var sky_top := night_sky_top.lerp(twilight_sky_top, twilight_amount).lerp(day_sky_top, day_amount)
	var sky_horizon := night_sky_horizon.lerp(twilight_sky_horizon, twilight_amount).lerp(day_sky_horizon, day_amount)
	var sky_color := sky_top.lerp(sky_horizon, 0.55)
	environment.background_color = sky_color
	_apply_sky_background(day_fraction, sky_top, sky_horizon, day_amount, night_amount, twilight_amount)

	var night_ambient := Color(0.045, 0.07, 0.16, 1.0)
	var twilight_ambient := Color(0.34, 0.19, 0.34, 1.0).lerp(Color(0.55, 0.30, 0.20, 1.0), 0.4 if is_morning else 0.7)
	var day_ambient := Color(0.62, 0.62, 0.58, 1.0)
	environment.ambient_light_color = night_ambient.lerp(twilight_ambient, twilight_amount).lerp(day_ambient, day_amount)
	environment.ambient_light_energy = lerpf(0.32, 1.08, day_amount) + twilight_amount * 0.12
	_stealth_ambient_visibility = clampf(lerpf(0.16, 0.95, day_amount) + twilight_amount * 0.12 + night_amount * 0.06, 0.08, 1.0)
	_apply_celestial_bodies(-sun_direction, -moon_direction, day_fraction, day_amount, night_amount, twilight_amount)


func get_stealth_ambient_visibility() -> float:
	return _stealth_ambient_visibility


func _apply_sky_background(day_fraction: float, sky_top: Color, sky_horizon: Color, day_amount: float, night_amount: float, twilight_amount: float) -> void:
	if sky_material == null:
		return
	var daylight_nebula_fade := 1.0 - _smoothstep(0.08, 0.20, day_amount)
	var nebula_visibility := clampf((night_amount * 1.18 + twilight_amount * 0.18) * daylight_nebula_fade, 0.0, 1.0)
	var cloud_visibility := clampf(day_amount * 0.92 + twilight_amount * 0.22 - night_amount * 0.58, 0.0, 1.0)
	var mode := _sky_panorama_mode_for(nebula_visibility, cloud_visibility)
	var bucket := int(floor(day_fraction * float(SKY_PANORAMA_BUCKETS_PER_DAY)))
	if _sky_panorama_texture == null or bucket != _sky_panorama_bucket or mode != _sky_panorama_mode:
		_request_sky_panorama_update(bucket, mode, day_fraction, sky_top, sky_horizon, nebula_visibility, cloud_visibility)


func _sky_panorama_mode_for(nebula_visibility: float, cloud_visibility: float) -> String:
	if cloud_visibility > 0.12:
		return "clouds"
	if nebula_visibility > 0.08:
		return "nebula"
	return "clear"


func _request_sky_panorama_update(bucket: int, mode: String, day_fraction: float, sky_top: Color, sky_horizon: Color, nebula_visibility: float, cloud_visibility: float) -> void:
	if _sky_panorama_build_active:
		if mode == _sky_panorama_build_mode:
			_sky_panorama_build_bucket = bucket
			_sky_panorama_queued_bucket = -1
			return
		_sky_panorama_queued_bucket = bucket
		_sky_panorama_queued_mode = mode
		_sky_panorama_queued_day_fraction = day_fraction
		_sky_panorama_queued_top = sky_top
		_sky_panorama_queued_horizon = sky_horizon
		_sky_panorama_queued_nebula_visibility = nebula_visibility
		_sky_panorama_queued_cloud_visibility = cloud_visibility
		return
	_begin_sky_panorama_build(bucket, mode, day_fraction, sky_top, sky_horizon, nebula_visibility, cloud_visibility)


func _begin_sky_panorama_build(bucket: int, mode: String, day_fraction: float, sky_top: Color, sky_horizon: Color, nebula_visibility: float, cloud_visibility: float) -> void:
	if _sky_panorama_texture == null:
		_apply_sky_panorama_fallback(mode, sky_top, sky_horizon)
	_sky_panorama_build_bucket = bucket
	_sky_panorama_build_mode = mode
	_sky_panorama_build_active = true
	_sky_panorama_queued_bucket = -1
	_sky_panorama_queued_mode = ""
	_sky_panorama_thread = Thread.new()
	var error := _sky_panorama_thread.start(Callable(self, "_build_sky_panorama_thread").bind(day_fraction, sky_top, sky_horizon, nebula_visibility, cloud_visibility, nebula_coverage), Thread.PRIORITY_NORMAL)
	if error != OK:
		push_warning("Could not start sky panorama build thread: %d" % error)
		_sky_panorama_build_bucket = -1
		_sky_panorama_build_mode = ""
		_sky_panorama_build_active = false
		_sky_panorama_thread = null


func _apply_sky_panorama_fallback(mode: String, sky_top: Color, sky_horizon: Color) -> void:
	var image := Image.create(SKY_PANORAMA_FALLBACK_WIDTH, SKY_PANORAMA_FALLBACK_HEIGHT, false, Image.FORMAT_RGBA8)
	for y in range(SKY_PANORAMA_FALLBACK_HEIGHT):
		var v := float(y) / float(SKY_PANORAMA_FALLBACK_HEIGHT - 1)
		var horizon_mix := pow(clampf(v, 0.0, 1.0), 1.55)
		var color := sky_top.lerp(sky_horizon, horizon_mix)
		for x in range(SKY_PANORAMA_FALLBACK_WIDTH):
			image.set_pixel(x, y, color)
	_sky_panorama_texture = ImageTexture.create_from_image(image)
	_apply_sky_texture_immediate(_sky_panorama_texture)
	_sky_panorama_mode = mode


func _poll_sky_panorama_build() -> void:
	if not _sky_panorama_build_active or _sky_panorama_thread == null:
		return
	if _sky_panorama_thread.is_alive():
		return
	var image := _sky_panorama_thread.wait_to_finish() as Image
	_sky_panorama_thread = null
	_sky_panorama_build_active = false
	if image != null:
		var texture := ImageTexture.create_from_image(image)
		_start_sky_crossfade(texture)
		_sky_panorama_texture = texture
		_sky_panorama_bucket = _sky_panorama_build_bucket
		_sky_panorama_mode = _sky_panorama_build_mode
	_sky_panorama_build_bucket = -1
	_sky_panorama_build_mode = ""
	if _sky_panorama_queued_bucket >= 0 and (_sky_panorama_queued_bucket != _sky_panorama_bucket or _sky_panorama_queued_mode != _sky_panorama_mode):
		_begin_sky_panorama_build(
			_sky_panorama_queued_bucket,
			_sky_panorama_queued_mode,
			_sky_panorama_queued_day_fraction,
			_sky_panorama_queued_top,
			_sky_panorama_queued_horizon,
			_sky_panorama_queued_nebula_visibility,
			_sky_panorama_queued_cloud_visibility
		)
	else:
		_sky_panorama_queued_bucket = -1
		_sky_panorama_queued_mode = ""


func _apply_sky_texture_immediate(texture: ImageTexture) -> void:
	if sky_material == null or texture == null:
		return
	_sky_visible_texture = texture
	_sky_crossfade_active = false
	_sky_crossfade_elapsed = 0.0
	_sky_crossfade_target_texture = null
	sky_material.set_shader_parameter("current_panorama", texture)
	sky_material.set_shader_parameter("next_panorama", texture)
	sky_material.set_shader_parameter("fade_amount", 0.0)


func _start_sky_crossfade(next_texture: ImageTexture) -> void:
	if sky_material == null or next_texture == null:
		return
	if _sky_visible_texture == null:
		_apply_sky_texture_immediate(next_texture)
		return
	_sky_crossfade_target_texture = next_texture
	_sky_crossfade_elapsed = 0.0
	_sky_crossfade_active = true
	sky_material.set_shader_parameter("current_panorama", _sky_visible_texture)
	sky_material.set_shader_parameter("next_panorama", next_texture)
	sky_material.set_shader_parameter("fade_amount", 0.0)


func _update_sky_crossfade(delta: float) -> void:
	if not _sky_crossfade_active or sky_material == null or _sky_crossfade_target_texture == null:
		return
	_sky_crossfade_elapsed += delta
	var fade_amount := clampf(_sky_crossfade_elapsed / maxf(SKY_CROSSFADE_SECONDS, 0.01), 0.0, 1.0)
	sky_material.set_shader_parameter("fade_amount", fade_amount)
	if fade_amount >= 1.0:
		_apply_sky_texture_immediate(_sky_crossfade_target_texture)


func _update_sky_panorama_rotation(delta: float) -> void:
	if sky_material == null:
		return
	var rotation_speed := SKY_CLEAR_ROTATION_SPEED
	match _sky_panorama_mode:
		"clouds":
			rotation_speed = SKY_CLOUD_ROTATION_SPEED
		"nebula":
			rotation_speed = SKY_NEBULA_ROTATION_SPEED
	_sky_panorama_rotation = fposmod(_sky_panorama_rotation + delta * rotation_speed, 1.0)
	sky_material.set_shader_parameter("panorama_rotation", _sky_panorama_rotation)


func _build_sky_panorama_thread(day_fraction: float, sky_top: Color, sky_horizon: Color, nebula_visibility: float, cloud_visibility: float, coverage: float) -> Image:
	var noise_set := _make_nebula_noise_set()
	var image := Image.create(SKY_PANORAMA_WIDTH, SKY_PANORAMA_HEIGHT, false, Image.FORMAT_RGBA8)
	for y in range(SKY_PANORAMA_HEIGHT):
		var v := float(y) / float(SKY_PANORAMA_HEIGHT - 1)
		var latitude := lerpf(PI * 0.5, -PI * 0.5, v)
		var sin_latitude := sin(latitude)
		var cos_latitude := cos(latitude)
		for x in range(SKY_PANORAMA_WIDTH):
			var u := float(x) / float(SKY_PANORAMA_WIDTH)
			var longitude := u * TAU
			var direction := Vector3(sin(longitude) * cos_latitude, sin_latitude, cos(longitude) * cos_latitude).normalized()
			var color := _sample_sky_panorama_pixel_with_noises(
				direction,
				day_fraction,
				sky_top,
				sky_horizon,
				nebula_visibility,
				cloud_visibility,
				noise_set,
				coverage
			)
			image.set_pixel(x, y, color)
	return image


func _make_nebula_noise_set() -> Dictionary:
	return {
		"large": _make_nebula_noise(81423, 0.82, 5),
		"medium": _make_nebula_noise(44107, 1.35, 4),
		"detail": _make_nebula_noise(12977, 2.65, 3),
		"warp": _make_nebula_noise(73519, 0.95, 4),
		"holes": _make_nebula_noise(98291, 1.85, 3),
		"presence": _make_nebula_noise(67241, 0.42, 4),
	}


func _make_nebula_noise(noise_seed: int, frequency: float, octaves: int) -> FastNoiseLite:
	var noise := FastNoiseLite.new()
	noise.seed = noise_seed
	noise.noise_type = FastNoiseLite.NoiseType.TYPE_SIMPLEX_SMOOTH
	noise.fractal_octaves = octaves
	noise.frequency = frequency
	return noise


func _sample_sky_panorama_pixel_with_noises(direction: Vector3, day_fraction: float, sky_top: Color, sky_horizon: Color, nebula_visibility: float, cloud_visibility: float, noise_set: Dictionary, coverage: float) -> Color:
	var horizon_mix := pow(clampf(1.0 - maxf(direction.y, 0.0), 0.0, 1.0), 1.55)
	var base := sky_top.lerp(sky_horizon, horizon_mix)
	base.r = maxf(base.r, 0.025)
	base.g = maxf(base.g, 0.030)
	base.b = maxf(base.b, 0.085)
	var color := Color(
		base.r,
		base.g,
		base.b,
		1.0
	)
	if nebula_visibility > 0.001:
		var density := _sample_nebula_density_with_noises(direction, day_fraction, noise_set, coverage) * nebula_visibility
		if density > 0.0001:
			var nebula := _sample_nebula_color_with_noises(direction, day_fraction, density, noise_set)
			color = Color(
				clampf(color.r + nebula.r * density * 3.10, 0.0, 1.0),
				clampf(color.g + nebula.g * density * 3.10, 0.0, 1.0),
				clampf(color.b + nebula.b * density * 3.10, 0.0, 1.0),
				1.0
			)
	if cloud_visibility > 0.001:
		return _blend_day_clouds(color, direction, day_fraction, cloud_visibility, _sample_cloud_density_with_noises(direction, day_fraction, noise_set))
	return color


func _sample_nebula_density_with_noises(direction: Vector3, day_fraction: float, noise_set: Dictionary, coverage: float) -> float:
	var noise_large := noise_set["large"] as FastNoiseLite
	var noise_medium := noise_set["medium"] as FastNoiseLite
	var noise_detail := noise_set["detail"] as FastNoiseLite
	var noise_warp := noise_set["warp"] as FastNoiseLite
	var noise_holes := noise_set["holes"] as FastNoiseLite
	var noise_presence := noise_set["presence"] as FastNoiseLite
	var p := _rotate_y(direction, day_fraction * TAU * 0.02)
	var warp := Vector3(
		_noise_3d(noise_warp, p * 2.10 + Vector3(13.2, 2.8, 9.1)),
		_noise_3d(noise_warp, p * 2.45 + Vector3(4.8, 17.6, 1.2)),
		_noise_3d(noise_warp, p * 1.85 + Vector3(9.4, 3.1, 21.7))
	) - Vector3(0.5, 0.5, 0.5)
	var domain := p * 2.25 + warp * 2.25
	var broad := _noise_3d(noise_large, domain * 0.50 + Vector3(2.3, 8.7, 4.1))
	var medium := _noise_3d(noise_medium, domain * 1.05 + Vector3(18.0, 3.2, 7.4))
	var detail := _noise_3d(noise_detail, domain * 1.90 + Vector3(1.7, 15.1, 11.8))
	var ridge := 1.0 - absf(_noise_3d(noise_medium, domain * 1.55 + Vector3(6.8, 12.4, 2.6)) * 2.0 - 1.0)
	var holes := _noise_3d(noise_holes, domain * 1.90 + Vector3(24.3, 5.9, 13.8))
	var field := broad * 0.95 + medium * 0.34 + ridge * 0.20 + detail * 0.025
	field *= lerpf(0.82, 1.18, _smoothstep(0.10, 0.90, holes))
	var coverage_amount := clampf(coverage, 0.05, 0.95)
	var presence_domain := _rotate_y(Vector3(direction.x * 0.70, direction.y * 1.12, direction.z * 0.94).normalized(), deg_to_rad(38.0) + day_fraction * TAU * 0.012)
	var presence_a := _noise_3d(noise_presence, presence_domain * 0.74 + Vector3(31.4, 11.2, 5.7))
	var presence_b := _noise_3d(noise_large, presence_domain * 0.38 + Vector3(4.6, 27.8, 16.5))
	var presence_c := _noise_3d(noise_presence, presence_domain * 1.16 + Vector3(18.6, 4.2, 33.1))
	var main_presence := presence_a * 0.58 + presence_b * 0.30 + presence_c * 0.12
	var main_threshold := lerpf(0.60, 0.28, coverage_amount)
	var main_mask := _smoothstep(main_threshold, main_threshold + 0.18, main_presence)
	var satellite_field := _smoothstep(0.50, 0.84, presence_c * 0.46 + medium * 0.32 + ridge * 0.22)
	var satellite_anchor := _smoothstep(main_threshold - 0.16, main_threshold + 0.22, main_presence)
	var satellite_mask := satellite_field * satellite_anchor * (1.0 - main_mask * 0.30) * lerpf(0.32, 0.56, coverage_amount)
	var lower_breakup := _smoothstep(0.20, 0.82, holes * 0.42 + detail * 0.34 + presence_c * 0.24)
	var lower_edge := lerpf(0.14, 0.34, lower_breakup)
	var main_altitude := _smoothstep(lower_edge + 0.06, lower_edge + 0.40, direction.y)
	var satellite_altitude := _smoothstep(lower_edge - 0.05, lower_edge + 0.28, direction.y)
	var high_body := 0.82 + _smoothstep(0.36, 0.76, direction.y) * 0.18
	var internal_breakup := 1.0 - _smoothstep(0.64, 0.90, holes * 0.52 + detail * 0.30 + (1.0 - ridge) * 0.18) * 0.22
	var presence_mask := clampf(main_mask * main_altitude + satellite_mask * satellite_altitude, 0.0, 1.0) * high_body * internal_breakup
	var zenith_falloff := 1.0 - _smoothstep(0.96, 1.0, absf(direction.y))
	return clampf(pow(_smoothstep(0.58, 0.96, field), 1.08) * presence_mask * zenith_falloff * 2.20, 0.0, 1.0)


func _sample_nebula_color_with_noises(direction: Vector3, day_fraction: float, density: float, noise_set: Dictionary) -> Color:
	var noise_medium := noise_set["medium"] as FastNoiseLite
	var noise_detail := noise_set["detail"] as FastNoiseLite
	var p := _rotate_y(direction, day_fraction * TAU * 0.018)
	var chroma := _noise_3d(noise_medium, p * 3.40 + Vector3(8.0, 19.0, 4.0))
	var aurora := _smoothstep(0.58, 0.96, _noise_3d(noise_detail, p * 6.80 + Vector3(1.0, 6.0, 13.0)))
	var deep_teal := Color(0.03, 0.42, 0.42, 1.0)
	var cyan := Color(0.10, 0.92, 0.72, 1.0)
	var emerald := Color(0.05, 1.0, 0.24, 1.0)
	var aurora_green := Color(0.58, 1.0, 0.30, 1.0)
	var blue_shadow := Color(0.05, 0.26, 0.70, 1.0)
	var emerald_amount := clampf(0.38 + aurora * 0.30 + density * 0.24, 0.0, 0.92)
	var aurora_amount := clampf(aurora * (0.10 + density * 0.18), 0.0, 0.30)
	var blue_shadow_amount := clampf((1.0 - _smoothstep(0.28, 0.72, chroma)) * (0.04 + (1.0 - density) * 0.08), 0.0, 0.16)
	var blue_domain_a := Vector3(p.x * 1.20 + p.y * 0.20, p.y * 0.52, p.z * 0.76 - p.x * 0.16)
	var blue_domain_b := Vector3(p.x * 0.62 - p.z * 0.20, p.y * 0.58 + p.x * 0.10, p.z * 1.28)
	var purple_domain := Vector3(p.x * 0.92 + p.z * 0.18, p.y * 0.48 - p.x * 0.08, p.z * 0.88)
	var blue_break_a := _smoothstep(0.26, 0.72, _noise_3d(noise_detail, blue_domain_a * 3.20 + Vector3(6.4, 37.2, 12.5)))
	var blue_break_b := _smoothstep(0.30, 0.74, _noise_3d(noise_detail, blue_domain_b * 2.95 + Vector3(34.7, 2.4, 27.1)))
	var purple_break := _smoothstep(0.30, 0.72, _noise_3d(noise_detail, purple_domain * 3.60 + Vector3(22.8, 11.4, 38.5)))
	var blue_field_a := _smoothstep(0.40, 0.72, _noise_3d(noise_medium, blue_domain_a * 0.96 + Vector3(41.8, 7.3, 18.6))) * lerpf(0.52, 1.0, blue_break_a)
	var blue_field_b := _smoothstep(0.42, 0.74, _noise_3d(noise_medium, blue_domain_b * 0.88 + Vector3(17.6, 29.5, 5.8))) * lerpf(0.48, 1.0, blue_break_b)
	var purple_field := _smoothstep(0.38, 0.70, _noise_3d(noise_medium, purple_domain * 0.94 + Vector3(8.9, 45.3, 21.6))) * lerpf(0.52, 1.0, purple_break)
	purple_field = pow(purple_field, 0.92)
	var gas_tint_mask := _smoothstep(0.003, 0.045, density) * (1.0 - _smoothstep(0.165, 0.300, density) * 0.38)
	var blue_wisp_amount := clampf(maxf(blue_field_a * 0.68, blue_field_b * 0.58) * gas_tint_mask * (0.66 + density * 0.52), 0.0, 0.54)
	var pink_wisp_amount := clampf(purple_field * gas_tint_mask * (0.88 + aurora * 0.34 + density * 0.42), 0.0, 0.68)
	var dark_blue := Color(0.025, 0.08, 1.0, 1.0)
	var rose := Color(0.92, 0.015, 1.0, 1.0)
	return deep_teal.lerp(cyan, _smoothstep(0.18, 0.82, chroma)).lerp(emerald, emerald_amount).lerp(aurora_green, aurora_amount).lerp(blue_shadow, blue_shadow_amount).lerp(dark_blue, blue_wisp_amount).lerp(rose, pink_wisp_amount)


func _sample_cloud_density_with_noises(direction: Vector3, day_fraction: float, noise_set: Dictionary) -> float:
	var noise_large := noise_set["large"] as FastNoiseLite
	var noise_medium := noise_set["medium"] as FastNoiseLite
	var noise_detail := noise_set["detail"] as FastNoiseLite
	var p := _rotate_y(direction, day_fraction * TAU * 0.035)
	var wind := Vector3(day_fraction * 2.7, 0.0, -day_fraction * 1.4)
	var domain := Vector3(p.x * 1.18, p.y * 0.42 + 0.62, p.z * 1.18) + wind
	var broad := _noise_3d(noise_large, domain * 0.62 + Vector3(12.5, 2.1, 18.4))
	var medium := _noise_3d(noise_medium, domain * 1.32 + Vector3(3.7, 21.6, 6.5))
	var detail := _noise_3d(noise_detail, domain * 3.10 + Vector3(19.0, 8.2, 1.3))
	return _cloud_density_from_fields(direction, broad, medium, detail)


func _cloud_density_from_fields(direction: Vector3, broad: float, medium: float, detail: float) -> float:
	var field := broad * 0.86 + medium * 0.36 + detail * 0.10
	var broken_edges := 0.72 + detail * 0.28
	var density := _smoothstep(0.50, 0.78, field) * broken_edges
	var altitude := _smoothstep(-0.08, 0.26, direction.y)
	var zenith_softening := 1.0 - _smoothstep(0.88, 1.0, direction.y) * 0.34
	return clampf(density * altitude * zenith_softening, 0.0, 1.0)


func _blend_day_clouds(base: Color, direction: Vector3, day_fraction: float, cloud_visibility: float, cloud_density: float) -> Color:
	if cloud_visibility <= 0.001 or cloud_density <= 0.001:
		return base
	var lit_edge := _smoothstep(0.42, 0.86, cloud_density)
	var cloud_color := Color(0.84, 0.90, 1.0, 1.0).lerp(Color(0.98, 0.99, 1.0, 1.0), lit_edge)
	var horizon_warmth := _smoothstep(-0.06, 0.22, 1.0 - absf(direction.y))
	cloud_color = cloud_color.lerp(Color(1.0, 0.94, 0.84, 1.0), horizon_warmth * 0.10 * (0.5 + 0.5 * sin(day_fraction * TAU)))
	var alpha := clampf(cloud_density * cloud_visibility * 0.96, 0.0, 0.86)
	return Color(
		clampf(lerpf(base.r, cloud_color.r, alpha), 0.0, 1.0),
		clampf(lerpf(base.g, cloud_color.g, alpha), 0.0, 1.0),
		clampf(lerpf(base.b, cloud_color.b, alpha), 0.0, 1.0),
		1.0
	)


func _noise_3d(noise: FastNoiseLite, point: Vector3) -> float:
	return clampf(noise.get_noise_3d(point.x, point.y, point.z) * 0.5 + 0.5, 0.0, 1.0)


func _rotate_y(point: Vector3, angle: float) -> Vector3:
	var sine := sin(angle)
	var cosine := cos(angle)
	return Vector3(point.x * cosine - point.z * sine, point.y, point.x * sine + point.z * cosine)


func _apply_celestial_bodies(sun_body_direction: Vector3, moon_body_direction: Vector3, day_fraction: float, day_amount: float, night_amount: float, twilight_amount: float) -> void:
	if celestial_root == null:
		return
	var anchor := _get_celestial_anchor()
	var sun_altitude := sun_body_direction.normalized().y
	var moon_altitude := moon_body_direction.normalized().y
	var sun_horizon_visibility := _smoothstep(-0.025, horizon_fade_altitude, sun_altitude)
	var moon_horizon_visibility := _smoothstep(-0.025, horizon_fade_altitude, moon_altitude)
	sun_disk.global_position = anchor + _get_skyline_direction(sun_body_direction) * celestial_distance
	moon_disk.global_position = anchor + _get_skyline_direction(moon_body_direction) * celestial_distance
	moon_halo_inner.global_position = moon_disk.global_position
	moon_halo_outer.global_position = moon_disk.global_position
	moon_glimmer.global_position = moon_disk.global_position
	_apply_night_planets(anchor, day_fraction, day_amount, night_amount, twilight_amount)

	var sun_visibility := clampf((day_amount * 0.96 + twilight_amount * 0.78) * sun_horizon_visibility, 0.0, 1.0)
	var moon_visibility := clampf((night_amount + twilight_amount * 0.55) * moon_horizon_visibility, 0.0, 1.0)
	var glimmer := 0.5 + 0.5 * sin(_glimmer_time * 1.7)
	var slow_glimmer := 0.5 + 0.5 * sin(_glimmer_time * 0.73 + 1.6)

	_set_celestial_alpha(sun_disk, Color(1.0, 0.72, 0.28, 1.0), sun_visibility)
	_set_celestial_alpha(moon_disk, Color(0.66, 0.80, 1.0, 1.0), moon_visibility * 0.94)
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
	moon_disk.rotation = Vector3(deg_to_rad(6.0), day_fraction * TAU * 1.35, deg_to_rad(-11.0))
	var star_visibility := clampf(night_amount + twilight_amount * 0.46 - day_amount * 0.82, 0.0, 1.0)
	_apply_star_field(anchor, day_fraction, star_visibility)


func _get_skyline_direction(direction: Vector3) -> Vector3:
	if direction.length_squared() <= 0.0001:
		return Vector3.UP
	var normalized := direction.normalized()
	if normalized.y >= horizon_min_altitude:
		return normalized
	var horizontal := Vector3(normalized.x, 0.0, normalized.z)
	if horizontal.length_squared() <= 0.0001:
		horizontal = Vector3.FORWARD
	var horizontal_length := sqrt(maxf(0.0, 1.0 - horizon_min_altitude * horizon_min_altitude))
	return (horizontal.normalized() * horizontal_length + Vector3.UP * horizon_min_altitude).normalized()


func _apply_night_planets(anchor: Vector3, day_fraction: float, day_amount: float, night_amount: float, twilight_amount: float) -> void:
	var planet_visibility := clampf(night_amount * 0.82 + twilight_amount * 0.34 - day_amount * 0.42, 0.0, 0.86)
	var faint_visibility := clampf(night_amount * 0.56 + twilight_amount * 0.26 - day_amount * 0.52, 0.0, 0.62)
	var large_visibility := clampf(0.46 + night_amount * 0.30 + twilight_amount * 0.16 - day_amount * 0.06, 0.0, 0.78)
	var hologram_pulse := 0.74 + 0.26 * sin(_glimmer_time * 1.25 + day_fraction * TAU)
	var large_direction := _orbiting_planet_direction(day_fraction, 132.0, 0.10, 0.57, 0.16)
	_apply_sky_planet(
		distant_planet_disk,
		anchor,
		large_direction,
		celestial_distance * 0.92,
		Vector3(deg_to_rad(-8.0), -day_fraction * TAU * 0.16, deg_to_rad(18.0)),
		Color(0.92, 0.62, 0.36, 1.0),
		large_visibility
	)
	_apply_sky_planet(
		distant_planet_ring,
		anchor,
		large_direction,
		celestial_distance * 0.92,
		Vector3(deg_to_rad(64.0), -day_fraction * TAU * 0.16, deg_to_rad(18.0)),
		Color(0.78, 0.58, 0.36, 1.0),
		large_visibility * (0.42 + hologram_pulse * 0.12)
	)
	_apply_sky_planet(
		small_planet_a_disk,
		anchor,
		_orbiting_planet_direction(day_fraction, 42.0, -0.30, 0.68, 0.16),
		celestial_distance * 0.86,
		Vector3(deg_to_rad(14.0), day_fraction * TAU * 0.18, deg_to_rad(-23.0)),
		Color(0.90, 0.58, 1.0, 1.0),
		planet_visibility * 0.70
	)
	_apply_sky_planet(
		small_planet_b_disk,
		anchor,
		_orbiting_planet_direction(day_fraction, 226.0, 0.34, 0.48, 0.20),
		celestial_distance * 0.98,
		Vector3(deg_to_rad(-18.0), -day_fraction * TAU * 0.16, deg_to_rad(9.0)),
		Color(1.0, 0.46, 0.34, 1.0),
		planet_visibility * 0.50
	)
	_apply_sky_planet(
		small_planet_c_disk,
		anchor,
		_orbiting_planet_direction(day_fraction, 306.0, 0.22, 0.78, 0.13),
		celestial_distance * 1.04,
		Vector3(deg_to_rad(6.0), day_fraction * TAU * 0.11, deg_to_rad(31.0)),
		Color(0.74, 0.86, 1.0, 1.0),
		planet_visibility * 0.46
	)
	_apply_sky_planet(
		equator_planet_disk,
		anchor,
		_orbiting_planet_direction(day_fraction, 166.0, -0.42, 0.72, 0.12),
		celestial_distance * 0.96,
		Vector3(deg_to_rad(4.0), day_fraction * TAU * 0.28, deg_to_rad(-7.0)),
		Color(0.70, 1.0, 0.92, 1.0),
		planet_visibility * 0.54
	)
	_apply_sky_planet(
		hologram_planet_disk,
		anchor,
		_orbiting_planet_direction(day_fraction, 284.0, 0.18, 0.61, 0.18),
		celestial_distance * 1.02,
		Vector3(deg_to_rad(-12.0), -day_fraction * TAU * 0.44, deg_to_rad(16.0)),
		Color(1.0, 0.64, 0.92, 1.0),
		planet_visibility * (0.34 + hologram_pulse * 0.22)
	)
	_apply_sky_planet(
		line_planet_disk,
		anchor,
		_orbiting_planet_direction(day_fraction, 330.0, -0.20, 0.80, 0.10),
		celestial_distance * 0.90,
		Vector3(deg_to_rad(22.0), day_fraction * TAU * 0.36, deg_to_rad(4.0)),
		Color(0.58, 0.92, 1.0, 1.0),
		planet_visibility * 0.50
	)
	_apply_sky_planet(
		streak_planet_disk,
		anchor,
		_orbiting_planet_direction(day_fraction, 94.0, 0.30, 0.44, 0.14),
		celestial_distance * 1.08,
		Vector3(deg_to_rad(-28.0), day_fraction * TAU * 0.22, deg_to_rad(34.0)),
		Color(1.0, 0.78, 0.46, 1.0),
		faint_visibility * 0.58
	)
	_apply_sky_planet(
		grain_planet_disk,
		anchor,
		_orbiting_planet_direction(day_fraction, 250.0, -0.36, 0.84, 0.08),
		celestial_distance * 1.10,
		Vector3(deg_to_rad(8.0), -day_fraction * TAU * 0.26, deg_to_rad(-19.0)),
		Color(0.74, 0.56, 1.0, 1.0),
		faint_visibility * 0.46
	)
	_apply_sky_planet(
		stone_planet_disk,
		anchor,
		_orbiting_planet_direction(day_fraction, 12.0, 0.46, 0.37, 0.12),
		celestial_distance * 1.05,
		Vector3(deg_to_rad(-6.0), day_fraction * TAU * 0.32, deg_to_rad(26.0)),
		Color(0.82, 0.70, 0.56, 1.0),
		faint_visibility * 0.52
	)


func _orbiting_planet_direction(day_fraction: float, base_angle_degrees: float, orbit_speed: float, altitude: float, wobble: float) -> Vector3:
	var angle := deg_to_rad(base_angle_degrees) + day_fraction * TAU * orbit_speed
	var y := clampf(altitude + wobble * sin(angle), 0.12, 0.94)
	var horizontal := sqrt(maxf(0.0, 1.0 - y * y))
	return Vector3(cos(angle) * horizontal, y, sin(angle) * horizontal).normalized()


func _apply_sky_planet(planet: MeshInstance3D, anchor: Vector3, direction: Vector3, distance: float, rotation: Vector3, color: Color, visibility: float) -> void:
	if planet == null:
		return
	planet.global_position = anchor + direction.normalized() * distance
	planet.rotation = rotation
	_set_celestial_alpha(planet, color, visibility)
	planet.visible = visibility > 0.025


func _apply_star_field(anchor: Vector3, day_fraction: float, star_visibility: float) -> void:
	if star_field_root == null:
		return
	star_field_root.global_position = anchor
	star_field_root.rotation = Vector3(0.0, day_fraction * TAU + deg_to_rad(18.0), 0.0)
	star_field_root.visible = star_visibility > 0.015
	if not star_field_root.visible:
		return
	for record in _star_records:
		var star := record.get("node", null) as MeshInstance3D
		var material := record.get("material", null) as StandardMaterial3D
		if star == null or material == null:
			continue
		var twinkle := 0.5 + 0.5 * sin(_glimmer_time * float(record["twinkle_speed"]) + float(record["twinkle_phase"]))
		var slow_glimmer := 0.5 + 0.5 * sin(_glimmer_time * float(record["slow_speed"]) + float(record["slow_phase"]))
		var pulse_wave := 0.5 + 0.5 * sin(_glimmer_time * float(record["pulse_speed"]) + float(record["pulse_phase"]))
		var pulse := pow(clampf(pulse_wave, 0.0, 1.0), 8.0)
		var shimmer := 0.68 + twinkle * 0.22 + slow_glimmer * 0.10 + pulse * float(record["pulse_strength"])
		var alpha := clampf(float(record["base_alpha"]) * star_visibility * shimmer, 0.0, 1.0)
		var color: Color = record["color"]
		material.albedo_color = Color(color.r, color.g, color.b, alpha)
		star.visible = alpha > 0.012
		var scale_amount := float(record["size"]) * (1.0 + pulse * float(record["pulse_scale"]) + (twinkle - 0.5) * 0.06)
		star.scale = Vector3.ONE * scale_amount


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
	var shader_material := mesh_instance.material_override as ShaderMaterial
	if shader_material != null:
		shader_material.set_shader_parameter("tint_color", Color(color.r, color.g, color.b, clampf(alpha, 0.0, 1.0)))
		return
	var material := mesh_instance.material_override as StandardMaterial3D
	if material == null:
		return
	material.albedo_color = Color(color.r, color.g, color.b, clampf(alpha, 0.0, 1.0))


func _orient_light(light: DirectionalLight3D, direction: Vector3) -> void:
	if light == null or direction.length_squared() <= 0.0001:
		return
	var normalized := direction.normalized()
	var up := Vector3.FORWARD if absf(normalized.dot(Vector3.UP)) > 0.98 else Vector3.UP
	light.look_at(light.global_position + normalized, up)


func _smoothstep(edge0: float, edge1: float, value: float) -> float:
	if is_equal_approx(edge0, edge1):
		return 0.0
	var t := clampf((value - edge0) / (edge1 - edge0), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)
