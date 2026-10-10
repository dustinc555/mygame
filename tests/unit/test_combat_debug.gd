extends GutTest

const OVERLAY_PATH := "res://features/combat/projection/combat_debug_overlay.gd"
var _settings := preload("res://features/combat/resources/combat_pursuit_settings.tres")

func test_combat_window_exposes_default_off_leash_and_shared_runtime_control() -> void:
	var debug := DebugMenu.new()
	add_child_autofree(debug)
	assert_has(debug.get_window_titles(), "Combat Debug")
	debug.toggle_window("Combat Debug")
	assert_true(debug.is_window_open("Combat Debug"))
	var check := debug.find_child("ShowPursuitLeashes", true, false) as CheckButton
	var distance := debug.find_child("PursuitLeashDistance", true, false) as SpinBox
	assert_not_null(check)
	assert_not_null(distance)
	if check == null or distance == null:
		return
	assert_false(check.button_pressed)
	var overlay := debug.find_child("CombatLeashes", true, false) as Node3D
	assert_not_null(overlay)
	assert_false(overlay.is_processing())
	check.button_pressed = true
	assert_true(overlay.visible)
	assert_true(overlay.is_processing())
	var original: float = _settings.leash_distance
	distance.value = 60.0
	assert_eq(_settings.leash_distance, 60.0, "UI changes the same resource used by targeting")
	assert_true(_settings.contains(Vector3.ZERO, Vector3(60, 0, 0)))
	assert_false(_settings.contains(Vector3.ZERO, Vector3(61, 0, 0)))
	distance.value = original
	check.button_pressed = false
	assert_false(overlay.visible)
	assert_false(overlay.is_processing())

func test_overlay_draws_actual_target_distance_and_has_no_work_when_off() -> void:
	if not ResourceLoader.exists(OVERLAY_PATH):
		fail_test("Combat leash overlay is missing")
		return
	var overlay = load(OVERLAY_PATH).new()
	add_child_autofree(overlay)
	assert_false(overlay.is_processing())
	assert_eq(overlay.get_child_count(), 0, "Disabled overlay creates no mesh or labels")
	overlay.set_enabled(true)
	overlay.draw_records([{"actor_id": "fighter", "target_id": "opponent", "from": Vector3.ZERO, "to": Vector3(30, 0, 40), "status": "Chasing", "leashed": true}])
	var line := overlay.get_node("LeashLines") as MeshInstance3D
	var label := overlay.get_node("LeashLabel0") as Label3D
	assert_eq(line.mesh.get_surface_count(), 1)
	assert_true(label.text.contains("50.0 / 100 m"), "Distance must come from geometry, not a stored label")
	var vertices: PackedVector3Array = line.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	assert_eq(vertices[0], Vector3(0, 0.15, 0))
	assert_eq(vertices[1], Vector3(30, 0.15, 40))
	assert_almost_eq(Vector2(vertices[2].x, vertices[2].z).length(), 100.0, 0.001, "Boundary uses the shared leash setting")
	overlay.set_enabled(false)
	assert_false(overlay.is_processing())
	assert_false(overlay.visible)
	assert_eq(line.mesh.get_surface_count(), 0, "Turning off clears stale debug geometry")

func test_runtime_leash_control_updates_existing_overlay_geometry_and_label() -> void:
	var panel = preload("res://features/combat/projection/combat_debug_panel.gd").new()
	add_child_autofree(panel)
	var distance := panel.get_node("PursuitLeashDistance") as SpinBox
	var check := panel.get_node("ShowPursuitLeashes") as CheckButton
	var overlay = panel.get_node("CombatLeashes")
	var original := distance.value
	check.button_pressed = true
	distance.value = 60.0
	overlay.draw_records([{"from": Vector3.ZERO, "to": Vector3(30, 0, 40), "status": "Chasing", "leashed": true}])
	var line := overlay.get_node("LeashLines") as MeshInstance3D
	var label := overlay.get_node("LeashLabel0") as Label3D
	var vertices: PackedVector3Array = line.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	assert_almost_eq(Vector2(vertices[2].x, vertices[2].z).length(), 60.0, 0.001, "Runtime control changes the real boundary geometry")
	assert_true(label.text.contains("50.0 / 60 m"), "Runtime control changes the actual leash label")
	distance.value = original
