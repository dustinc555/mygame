extends Node3D
## GPU-only, self-terminating sky workflow: real production shader, pause/restore,
## camera travel, and opaque geometry both farther away than the former sky meshes.
## Run: godot --path . res://tests/validation/validate_celestial_sky_rendered.tscn
## Images/results: .test-results/celestial-sky/ (or SKY_CAPTURE_PREFIX).

var clock: WorldTimeController
var lighting: DayNightLightingController
var camera: Camera3D
var failures: Array[String] = []
var prefix: String


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if DisplayServer.get_name() == "headless":
		push_error("Celestial sky image validation requires a native GPU display, not the dummy renderer")
		get_tree().quit(1)
		return
	get_window().size = Vector2i(1600, 900)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	prefix = OS.get_environment("SKY_CAPTURE_PREFIX")
	if prefix.is_empty():
		prefix = ProjectSettings.globalize_path("res://.test-results/celestial-sky/rendered")
	DirAccess.make_dir_recursive_absolute(prefix.get_base_dir())
	clock = WorldTimeController.new()
	add_child(clock)
	clock.set_process(false)
	clock.set_time_of_day(22)
	var context := BootstrapContext.new(self)
	context.register(WorldTimeController.SERVICE_ID, clock)
	lighting = DayNightLightingController.new()
	lighting.sky_settings = lighting.sky_settings.duplicate(true)
	add_child(lighting)
	lighting.initialize(context)
	camera = Camera3D.new()
	camera.fov = 75.0
	camera.far = 10000.0
	add_child(camera)
	camera.current = true
	camera.look_at(lighting.sample_sky_state(clock.total_world_minutes)["planet_direction"])
	_run.call_deferred()


func _run() -> void:
	var baseline := await capture("initial")
	camera.position += Vector3(1000.0, 400.0, -800.0)
	var translated := await capture("translated")
	check(image_difference(baseline, translated) < 0.003, "Camera translation has no celestial parallax")
	clock.request_manual_pause()
	var saved := clock.serialize_state()
	clock._process(120.0)
	var paused := await capture("paused")
	check(image_difference(translated, paused) < 0.003, "Paused clock freezes rendered sky")
	clock.advance_minutes(60.0)
	var advanced := await capture("advanced")
	check(image_difference(paused, advanced) > 0.015, "Advancing world time visibly changes the sky")
	clock.apply_serialized_state(saved)
	var restored := await capture("restored")
	check(image_difference(paused, restored) < 0.003, "Restoring the saved clock restores the rendered sky")
	var ring_density := lighting.sky_settings.ring_density
	var ring_profile := lighting.sky_settings.ring_profile
	lighting.sky_settings.ring_density = 0.0
	var without_rings := await capture("zero-ring-density")
	check(image_difference(restored, without_rings) > 0.005, "Ring density visibly changes the rendered rings")
	var transparent := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	transparent.fill(Color(1.0, 1.0, 1.0, 0.0))
	lighting.sky_settings.ring_profile = ImageTexture.create_from_image(transparent)
	lighting.sky_settings.ring_density = ring_density
	var transparent_rings := await capture("transparent-ring-profile")
	check(image_difference(without_rings, transparent_rings) < 0.003, "Zero ring density removes both particles and their shadow")
	lighting.sky_settings.ring_profile = ring_profile
	var blocker := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(220.0, 220.0)
	blocker.mesh = quad
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(0.0, 1.0, 0.0)
	blocker.material_override = material
	add_child(blocker)
	blocker.global_basis = camera.global_basis
	for distance in [450.0, 4500.0]:
		blocker.global_position = camera.global_position - camera.global_basis.z * distance
		blocker.scale = Vector3.ONE * (distance / 450.0)
		var blocked := await capture("occlusion-%s" % int(distance))
		var center := blocked.get_pixel(blocked.get_width() / 2, blocked.get_height() / 2)
		check(center.g > 0.6 and center.r < 0.1 and center.b < 0.1, "World geometry at %s metres occludes the giant" % distance)
	clock.release_manual_pause()
	var result := {"failures": failures, "renderer": RenderingServer.get_video_adapter_name(), "size": [baseline.get_width(), baseline.get_height()]}
	var output := FileAccess.open(prefix + "-result.json", FileAccess.WRITE)
	output.store_string(JSON.stringify(result, "\t"))
	print("CELESTIAL_SKY_RENDERED_RESULT ", JSON.stringify(result))
	get_tree().quit(0 if failures.is_empty() else 1)


func capture(label: String) -> Image:
	for frame in range(20):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	image.save_png(prefix + "-" + label + ".png")
	return image


func image_difference(a: Image, b: Image) -> float:
	var difference := 0.0
	var samples := 0
	for y in range(4, a.get_height(), 8):
		for x in range(4, a.get_width(), 8):
			var first := a.get_pixel(x, y)
			var second := b.get_pixel(x, y)
			difference += absf(first.r - second.r) + absf(first.g - second.g) + absf(first.b - second.b)
			samples += 3
	return difference / float(samples)


func check(condition: bool, message: String) -> void:
	if condition:
		print("CELESTIAL_SKY_PASS ", message)
	else:
		failures.append(message)
		push_error(message)
