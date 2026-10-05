extends GutTest
## The real lighting controller in a tiny test-owned world, without town startup.

const LIGHTING := preload("res://features/world/projection/lighting/day_night_lighting_controller.gd")
var world: Node3D
var clock: WorldTimeController
var lighting: Node


func before_each() -> void:
	world = add_child_autofree(Node3D.new())
	clock = WorldTimeController.new()
	world.add_child(clock)
	clock.set_process(false)
	var context := BootstrapContext.new(world)
	context.register(WorldTimeController.SERVICE_ID, clock)
	lighting = LIGHTING.new()
	lighting.sky_settings = lighting.sky_settings.duplicate(true)
	world.add_child(lighting)
	lighting.initialize(context)
	lighting.set_process(false)


func test_celestial_background_cannot_be_nearby_world_geometry() -> void:
	assert_eq(world.find_children("*", "MeshInstance3D", true, false).size(), 0,
		"Sun, moon, rings and stars must be in the sky, never in front of distant terrain")
	assert_eq(lighting.environment.background_mode, Environment.BG_SKY)
	assert_not_null(lighting.environment.sky.sky_material)


func test_presentation_does_not_change_the_existing_stealth_curve() -> void:
	# A sky art pass must not alter established gameplay's sun-altitude inputs.
	for minute in [360.0, 420.0, 540.0, 720.0, 1020.0, 1080.0, 1200.0, 1440.0]:
		clock.total_world_minutes = minute
		lighting._on_minutes_advanced(minute)
		var altitude := sin((fposmod(minute / 1440.0, 1.0) - 0.25) * TAU)
		var daylight := smoothstep(-0.03, 0.28, altitude)
		var night := smoothstep(0.04, 0.42, -altitude)
		var twilight := (1.0 - smoothstep(0.0, 0.34, absf(altitude))) * (1.0 - minf(daylight, night) * 0.35)
		var expected := clampf(lerpf(0.16, 0.95, daylight) + twilight * 0.12 + night * 0.06, 0.08, 1.0)
		assert_almost_eq(lighting.get_stealth_ambient_visibility(), expected, 0.00001, "Existing visibility at minute %s" % minute)


func test_fractional_clock_ticks_move_the_sky_without_waiting_for_a_minute() -> void:
	var before: Vector3 = lighting.sky_material.get_shader_parameter("sun_direction")
	clock.advance_minutes(0.25)
	var after: Vector3 = lighting.sky_material.get_shader_parameter("sun_direction")
	assert_gt(before.distance_to(after), 0.0001)
	assert_eq(after, lighting.sample_sky_state(clock.total_world_minutes)["sun_direction"])


func test_paused_clock_freezes_celestial_motion_and_wind() -> void:
	clock.request_manual_pause()
	var before: Dictionary = lighting.sample_sky_state(clock.total_world_minutes)
	clock._process(60.0)
	assert_eq(lighting.sample_sky_state(clock.total_world_minutes), before)
	assert_eq(lighting.sky_material.get_shader_parameter("cloud_offset"), before["cloud_offset"])
	clock.release_manual_pause()
	clock._process(1.0)
	assert_ne(lighting.sky_material.get_shader_parameter("cloud_offset"), before["cloud_offset"])


func test_save_restore_reconstructs_the_same_sky_immediately() -> void:
	clock.advance_minutes(124.375)
	var saved := clock.serialize_state()
	var before: Dictionary = lighting.sample_sky_state(clock.total_world_minutes)
	clock.advance_days(9.5)
	clock.apply_serialized_state(saved)
	for property in [&"sun_direction", &"moon_direction", &"planet_direction", &"cloud_offset", &"planet_spin", &"aurora_phase"]:
		assert_eq(lighting.sky_material.get_shader_parameter(property), before[property], "Restored %s" % property)


func test_midnight_has_no_daily_cloud_or_orbit_reset() -> void:
	var before: Dictionary = lighting.sample_sky_state(1439.999)
	var after: Dictionary = lighting.sample_sky_state(1440.001)
	for property in ["sun_direction", "moon_direction", "planet_direction", "cloud_offset"]:
		assert_lt(before[property].distance_to(after[property]), 0.001, "Continuous %s" % property)
	assert_lt(absf(before["planet_spin"] - after["planet_spin"]), 0.001)


func test_shader_sun_and_moon_match_the_actual_directional_lights() -> void:
	for hour in [0, 6, 12, 18, 23]:
		clock.set_time_of_day(hour)
		assert_almost_eq(lighting.sun.global_basis.z, lighting.sky_material.get_shader_parameter("sun_direction"), Vector3.ONE * 0.00001)
		assert_almost_eq(lighting.moon.global_basis.z, lighting.sky_material.get_shader_parameter("moon_direction"), Vector3.ONE * 0.00001)


func test_moon_has_a_full_and_new_phase_over_its_authored_period() -> void:
	lighting.sky_settings.moon_phase_offset = 0.0
	var full: Dictionary = lighting.sample_sky_state(0.0)
	var new_moon: Dictionary = lighting.sample_sky_state(lighting.sky_settings.moon_orbit_days * 1440.0 * 0.5)
	assert_gt(full["moon_phase"], 0.99)
	assert_lt(new_moon["moon_phase"], 0.01)


func test_size_and_brightness_controls_apply_without_restarting() -> void:
	lighting.sky_settings.planet_diameter_degrees = 40.0
	assert_almost_eq(lighting.sky_material.get_shader_parameter("planet_radius"), sin(deg_to_rad(20.0)), 0.00001)
	lighting.sky_settings.nebula_brightness = 0.25
	assert_eq(lighting.sky_material.get_shader_parameter("nebula_brightness"), 0.25)
	lighting.sky_settings.planet_diameter_degrees = 500.0
	assert_eq(lighting.sky_settings.planet_diameter_degrees, 70.0)


func test_surface_replacement_updates_the_live_material() -> void:
	var replacement := GradientTexture2D.new()
	lighting.sky_settings.planet_surface = replacement
	assert_same(lighting.sky_material.get_shader_parameter("planet_surface"), replacement)
	lighting.sky_settings.moon_surface = replacement
	assert_same(lighting.sky_material.get_shader_parameter("moon_surface"), replacement)
	lighting.sky_settings.ring_profile = replacement
	assert_same(lighting.sky_material.get_shader_parameter("ring_profile"), replacement)


func test_cloud_wind_is_authored_in_game_hours_not_days() -> void:
	lighting.sky_settings.cloud_wind_speed = 0.25
	var start: Vector2 = lighting.sample_sky_state(0.0)["cloud_offset"]
	var after_hour: Vector2 = lighting.sample_sky_state(60.0)["cloud_offset"]
	assert_almost_eq(absf(start.angle_to(after_hour)), 0.25, 0.00001)
	lighting.sky_settings.cloud_wind_speed = 0.0
	assert_eq(lighting.sample_sky_state(0.0)["cloud_offset"], lighting.sample_sky_state(9000.0)["cloud_offset"])


func test_ring_art_controls_update_the_live_material() -> void:
	var properties: Array[StringName] = []
	for property in lighting.sky_settings.get_property_list():
		properties.append(property.name)
	var values := {&"ring_inner_radius": 1.3, &"ring_outer_radius": 1.8,
		&"ring_density": 0.25, &"ring_brightness": 0.7}
	for property in values:
		assert_has(properties, property, "Ring design must have an editable %s control" % property)
		if not properties.has(property):
			return
		lighting.sky_settings.set(property, values[property])
		assert_almost_eq(lighting.sky_material.get_shader_parameter(property), values[property], 0.00001)


func test_no_duplicate_subscription_when_initialized_again() -> void:
	var connection_count := clock.world_minutes_advanced.get_connections().size()
	lighting.initialize(lighting._context)
	assert_eq(clock.world_minutes_advanced.get_connections().size(), connection_count)
	assert_eq(world.find_children("*", "DirectionalLight3D", true, false).size(), 2)
