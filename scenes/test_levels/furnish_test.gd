extends Node3D

## Independent furnish-pass proving scene: instantiates the woodbrick shop
## shell alone, runs FacilityFurnisher with the bar rules, and spawns the
## results — no town, no bootstrap, just the generator's output. Top-down
## plan view with upper level and roof hidden so layout and chair facing are
## visible at a glance.
##
## Env vars (for automated visual checks):
##   FURNISH_SEED            layout seed (default 1)
##   FURNISH_TEST_SCREENSHOT absolute PNG path; capture after spawn, then quit

const SHELL_SCENE := preload("res://features/world/projection/buildings/woodbrick_shop_medium.tscn")
const RULES := preload("res://features/settlements/resources/furnishing/bar.tres")

var _screenshot_path := ""
var _frames_until_capture := 20


func _ready() -> void:
	_screenshot_path = OS.get_environment("FURNISH_TEST_SCREENSHOT")
	_build_light_rig()
	var shell := SHELL_SCENE.instantiate() as Node3D
	add_child(shell)
	_hide_upper_and_roof(shell)
	var focus: Variant = _furnish(shell)
	_build_camera(_shell_center(shell), focus)


## Returns the first cluster's world position for close-up framing.
func _furnish(shell: Node3D) -> Variant:
	var seed_text := OS.get_environment("FURNISH_SEED")
	var seed_value := int(seed_text) if not seed_text.is_empty() else 1
	var furnisher := FacilityFurnisher.new()
	var placements := furnisher.furnish(shell, RULES, seed_value)
	if placements.is_empty():
		push_error("Furnish test: %s" % furnisher.last_error())
		return null
	var furniture_root := Node3D.new()
	furniture_root.name = "Furniture"
	add_child(furniture_root)
	var focus: Variant = null
	for placement in placements:
		var node := (placement["scene"] as PackedScene).instantiate() as Node3D
		furniture_root.add_child(node)
		node.transform = shell.transform * placement["transform"]
		if focus == null and placement["kind"] == "cluster":
			focus = node.global_position
		print("  %s %s at %s" % [placement["kind"], (placement["scene"] as PackedScene).resource_path.get_file(), node.global_position])
	print("Furnish test seed %d: %d placements" % [seed_value, placements.size()])
	return focus


func _hide_upper_and_roof(shell: Node3D) -> void:
	if not shell.has_method("get_modular_pieces"):
		return
	# FURNISH_TEST_LEVEL picks which storey the plan view exposes (default 0):
	# everything above that storey's ceiling is hidden.
	var view_level := int(OS.get_environment("FURNISH_TEST_LEVEL")) if not OS.get_environment("FURNISH_TEST_LEVEL").is_empty() else 0
	var ceiling := 2.0 + 3.0 * view_level
	for piece_value in shell.call("get_modular_pieces"):
		var piece := piece_value as Node3D
		if piece == null:
			continue
		var category := str(piece.get("category"))
		if category.begins_with("roof") or piece.position.y > ceiling:
			piece.visible = false


func _shell_center(shell: Node3D) -> Vector3:
	var total := Vector3.ZERO
	var count := 0
	if shell.has_method("get_modular_pieces"):
		for piece_value in shell.call("get_modular_pieces"):
			var piece := piece_value as Node3D
			if piece != null and str(piece.get("category")) == "floor":
				total += piece.global_position
				count += 1
	return total / maxf(count, 1.0)


## FURNISH_TEST_VIEW: "plan" (default, orthographic top-down), "persp" (low
## southern angle), or "cluster" (close-up on the first table cluster so
## chair facing is unambiguous).
func _build_camera(center: Vector3, focus: Variant) -> void:
	var camera := Camera3D.new()
	add_child(camera)
	var view := OS.get_environment("FURNISH_TEST_VIEW")
	if view == "cluster" and focus != null:
		var target: Vector3 = focus
		camera.global_position = target + Vector3(0.2, 4.6, 2.4)
		camera.look_at(target + Vector3(0.0, 0.3, 0.0), Vector3.UP)
	elif view == "persp":
		camera.global_position = center + Vector3(1.0, 6.5, 10.5)
		camera.look_at(center + Vector3(0.0, 0.5, 0.0), Vector3.UP)
	else:
		camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		camera.size = 15.0
		camera.global_position = center + Vector3(0.0, 22.0, 0.01)
		camera.look_at(center, Vector3.FORWARD)
	camera.current = true


func _build_light_rig() -> void:
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-65.0, 30.0, 0.0)
	sun.light_energy = 1.2
	add_child(sun)
	var environment := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.16, 0.17, 0.19)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.9, 0.9, 0.95)
	env.ambient_light_energy = 0.7
	environment.environment = env
	add_child(environment)


func _process(_delta: float) -> void:
	if _screenshot_path.is_empty():
		return
	_frames_until_capture -= 1
	if _frames_until_capture > 0:
		return
	var image := get_viewport().get_texture().get_image()
	image.save_png(_screenshot_path)
	print("Furnish test screenshot: %s" % _screenshot_path)
	_screenshot_path = ""
	get_tree().quit()
