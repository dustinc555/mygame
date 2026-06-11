extends HumanoidBodyProjection
class_name RustdeadBodyProjection

# Rustdead (zombie) humanoid visual adapter. PRESENTATION ONLY -- never owns truth.
#
# Holds rustdead-specific presentation: remapped zombie clips, the extra zombie
# clip set, automatic eyebrow policy, and cinder-burn visuals. Rustdead constants
# are read through the untyped `actor` at runtime (the actor is a
# RustdeadHumanoidCharacter, which defines them).

const CINDER_BURNED_MATERIAL_META := "cinder_burned"
const CINDER_SCORCH_OVERLAY_META := "cinder_scorch_overlay"

static var _cinder_burn_overlay_material: Material
static var _cinder_burn_overlay_texture: Texture2D

var _cinder_burn_effect: Node3D
var _cinder_burn_fire_seed := 0.0
var _cinder_burn_visual_rng := RandomNumberGenerator.new()


func _exit_tree() -> void:
	clear_cinder_burned_visuals()
	_free_rustdead_visual_root_for_exit()
	clear_cinder_burn_effect()


func setup_visual() -> void:
	super.setup_visual()
	if actor != null and actor.is_cinder_burned():
		apply_cinder_burned_visuals()


func play_clip(animation_name: String, speed_ratio: float = 0.0, force_restart: bool = false, blend_seconds: float = DEFAULT_MOVE_BLEND_SECONDS) -> bool:
	var resolved_animation := _resolve_rustdead_clip_name(animation_name)
	if resolved_animation != animation_name and not has_clip(resolved_animation):
		resolved_animation = animation_name
	return super.play_clip(resolved_animation, speed_ratio, force_restart, blend_seconds)


func has_clip(animation_name: String) -> bool:
	var resolved_animation := _resolve_rustdead_clip_name(animation_name)
	return super.has_clip(resolved_animation) or (resolved_animation != animation_name and super.has_clip(animation_name))


func _resolve_rustdead_clip_name(animation_name: String) -> String:
	if animation_name == actor.IDLE_ANIMATION_NAME or animation_name == actor.TIRED_IDLE_ANIMATION_NAME or animation_name == actor.UNARMED_COMBAT_IDLE_ANIMATION_NAME:
		return actor.RUSTDEAD_IDLE_ANIMATION_NAME
	elif animation_name == actor.WALK_ANIMATION_NAME:
		return actor.RUSTDEAD_WALK_ANIMATION_NAME
	elif animation_name == actor.JOG_ANIMATION_NAME:
		return actor.RUSTDEAD_RUN_ANIMATION_NAME
	return animation_name


func _get_clip_speed(animation_name: String, speed_ratio: float) -> float:
	if animation_name == actor.RUSTDEAD_WALK_ANIMATION_NAME:
		return lerpf(0.72, 1.08, speed_ratio)
	elif animation_name == actor.RUSTDEAD_RUN_ANIMATION_NAME:
		return lerpf(0.82, 1.22, speed_ratio)
	return super._get_clip_speed(animation_name, speed_ratio)


func _copy_character_animations(animation_library: AnimationLibrary) -> void:
	super._copy_character_animations(animation_library)
	var ual2_source: Node = actor.UAL2_ANIMATION_SOURCE_SCENE.instantiate()
	var ual2_player := _find_animation_player(ual2_source)
	if ual2_player != null:
		_copy_named_animations(ual2_player, animation_library, actor.RUSTDEAD_ANIMATION_NAMES)
	ual2_source.queue_free()


func get_available_idle_clip_names() -> Array[String]:
	if has_clip(actor.RUSTDEAD_IDLE_ANIMATION_NAME):
		var names: Array[String] = []
		names.append(String(actor.RUSTDEAD_IDLE_ANIMATION_NAME))
		return names
	return super.get_available_idle_clip_names()


func apply_automatic_eyebrow_style() -> void:
	if actor.appearance_data == null:
		return
	actor.appearance_data.eyebrow_style = null
	actor.appearance_data.eyebrow_color = Color(0.08, 0.015, 0.018, 1.0)


func begin_cinder_burn_visuals() -> void:
	_cinder_burn_visual_rng.randomize()
	_cinder_burn_fire_seed = _cinder_burn_visual_rng.randf() * TAU
	apply_cinder_burned_visuals()


func spawn_cinder_burn_effect(remaining_seconds: float, duration_seconds: float) -> void:
	clear_cinder_burn_effect()
	_cinder_burn_effect = Node3D.new()
	_cinder_burn_effect.name = "CinderBurnEffect"
	add_child(_cinder_burn_effect)
	_cinder_burn_effect.top_level = true
	_update_cinder_burn_effect_position()
	for index in range(7):
		var flame := MeshInstance3D.new()
		flame.name = "Flame%02d" % index
		var flame_mesh := SphereMesh.new()
		flame_mesh.radius = 0.32
		flame_mesh.height = 0.75
		flame_mesh.radial_segments = 12
		flame_mesh.rings = 6
		flame.mesh = flame_mesh
		var flame_material := StandardMaterial3D.new()
		flame_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		flame_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		flame_material.albedo_color = Color(1.0, 0.32 + float(index % 3) * 0.14, 0.04, 0.72)
		flame_material.emission_enabled = true
		flame_material.emission = Color(1.0, 0.33, 0.06, 1.0)
		flame_material.emission_energy_multiplier = 2.8
		flame.material_override = flame_material
		var angle := TAU * float(index) / 7.0
		var radius := 0.18 + 0.18 * float(index % 2)
		flame.position = Vector3(cos(angle) * radius, 0.16 + 0.04 * float(index % 3), sin(angle) * radius)
		var base_scale := Vector3(0.34 + 0.04 * float(index % 3), 0.95 + 0.12 * float(index % 2), 0.34 + 0.03 * float(index % 4))
		flame.scale = base_scale
		flame.set_meta("cinder_flame", true)
		flame.set_meta("base_scale", base_scale)
		flame.set_meta("base_position", flame.position)
		flame.set_meta("phase", _cinder_burn_fire_seed + float(index) * 0.91)
		_cinder_burn_effect.add_child(flame)
	for index in range(4):
		var smoke := MeshInstance3D.new()
		smoke.name = "Smoke%02d" % index
		var smoke_mesh := SphereMesh.new()
		smoke_mesh.radius = 0.38
		smoke_mesh.height = 0.42
		smoke_mesh.radial_segments = 10
		smoke_mesh.rings = 5
		smoke.mesh = smoke_mesh
		var smoke_material := StandardMaterial3D.new()
		smoke_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		smoke_material.albedo_color = Color(0.08, 0.07, 0.06, 0.26)
		smoke.material_override = smoke_material
		var angle := _cinder_burn_fire_seed + TAU * float(index) / 4.0
		smoke.position = Vector3(cos(angle) * 0.24, 0.85 + 0.12 * float(index), sin(angle) * 0.24)
		var base_scale := Vector3.ONE * (0.65 + float(index) * 0.08)
		smoke.scale = base_scale
		smoke.set_meta("cinder_smoke", true)
		smoke.set_meta("base_scale", base_scale)
		smoke.set_meta("base_position", smoke.position)
		smoke.set_meta("phase", _cinder_burn_fire_seed + float(index) * 1.37)
		_cinder_burn_effect.add_child(smoke)
	var light := OmniLight3D.new()
	light.name = "CinderLight"
	light.light_color = Color(1.0, 0.42, 0.12, 1.0)
	light.light_energy = 2.2
	light.omni_range = 4.0
	light.position = Vector3(0.0, 0.9, 0.0)
	light.set_meta("cinder_light", true)
	_cinder_burn_effect.add_child(light)
	update_cinder_burn_visuals(remaining_seconds, duration_seconds)


func update_cinder_burn_visuals(remaining_seconds: float, duration_seconds: float) -> void:
	_update_cinder_burn_effect_position()
	_update_cinder_burn_effect(remaining_seconds, duration_seconds)


func finish_cinder_burn_visuals() -> void:
	clear_cinder_burn_effect()


func clear_cinder_burn_effect() -> void:
	if _cinder_burn_effect == null:
		return
	var effect := _cinder_burn_effect
	_cinder_burn_effect = null
	if is_instance_valid(effect):
		var parent := effect.get_parent()
		if parent != null:
			parent.remove_child(effect)
		effect.free()


func apply_cinder_burned_visuals() -> void:
	var visual_root := get_visual_root()
	if visual_root != null:
		_apply_cinder_burn_overlay(visual_root)
	var body_mesh := actor.get_node_or_null("BodyMesh")
	if body_mesh != null:
		_apply_cinder_burn_overlay(body_mesh)


func clear_cinder_burned_visuals() -> void:
	var visual_root := get_visual_root()
	if visual_root != null:
		_clear_cinder_burn_overlay(visual_root)
	var body_mesh := actor.get_node_or_null("BodyMesh") if actor != null else null
	if body_mesh != null:
		_clear_cinder_burn_overlay(body_mesh)


func has_cinder_burned_visuals() -> bool:
	var visual_root := get_visual_root()
	if visual_root != null and _node_has_cinder_burned_material(visual_root):
		return true
	var body_mesh := actor.get_node_or_null("BodyMesh")
	return body_mesh != null and _node_has_cinder_burned_material(body_mesh)


func _update_cinder_burn_effect_position() -> void:
	if _cinder_burn_effect == null or not is_instance_valid(_cinder_burn_effect):
		return
	_cinder_burn_effect.global_position = actor.get_follow_anchor_position() + Vector3(0.0, 0.35, 0.0)


func _update_cinder_burn_effect(remaining_seconds: float, duration_seconds: float) -> void:
	if _cinder_burn_effect == null or not is_instance_valid(_cinder_burn_effect):
		return
	var duration := maxf(duration_seconds, 0.05)
	var elapsed := duration - remaining_seconds
	var intensity := minf(1.0, elapsed / 0.75) * minf(1.0, remaining_seconds / 3.0)
	for child in _cinder_burn_effect.get_children():
		if child is MeshInstance3D and bool(child.get_meta("cinder_flame", false)):
			var base_scale: Vector3 = child.get_meta("base_scale")
			var base_position: Vector3 = child.get_meta("base_position")
			var phase := float(child.get_meta("phase", 0.0))
			var pulse := 0.72 + 0.28 * sin(elapsed * 9.0 + phase)
			child.scale = base_scale * maxf(0.01, pulse * intensity)
			child.position = base_position + Vector3(0.0, sin(elapsed * 7.0 + phase) * 0.08 * intensity, 0.0)
			var material := child.material_override as StandardMaterial3D
			if material != null:
				var alpha := clampf(0.18 + 0.62 * intensity, 0.0, 0.82)
				material.albedo_color.a = alpha
				material.emission_energy_multiplier = 1.0 + 2.4 * intensity
		elif child is MeshInstance3D and bool(child.get_meta("cinder_smoke", false)):
			var base_scale: Vector3 = child.get_meta("base_scale")
			var base_position: Vector3 = child.get_meta("base_position")
			var phase := float(child.get_meta("phase", 0.0))
			var drift := Vector3(cos(elapsed * 1.1 + phase), 0.0, sin(elapsed * 0.9 + phase)) * 0.08 * intensity
			child.position = base_position + drift + Vector3(0.0, sin(elapsed * 1.7 + phase) * 0.08, 0.0)
			child.scale = base_scale * (0.75 + 0.35 * intensity + 0.08 * sin(elapsed * 2.0 + phase))
			var material := child.material_override as StandardMaterial3D
			if material != null:
				material.albedo_color.a = clampf(0.05 + 0.22 * intensity, 0.0, 0.28)
		elif child is OmniLight3D and bool(child.get_meta("cinder_light", false)):
			var light := child as OmniLight3D
			light.light_energy = intensity * (1.4 + 0.8 * sin(elapsed * 12.0 + _cinder_burn_fire_seed))


func _free_rustdead_visual_root_for_exit() -> void:
	var visual_root := get_visual_root()
	if visual_root == null:
		return
	_strip_meshes_for_exit(visual_root)
	var parent := visual_root.get_parent()
	if parent != null:
		parent.remove_child(visual_root)
	visual_root.free()


func _strip_meshes_for_exit(root: Node) -> void:
	if root == null:
		return
	if root is MeshInstance3D:
		(root as MeshInstance3D).mesh = null
	for child in root.get_children():
		_strip_meshes_for_exit(child)


func _apply_cinder_burn_overlay(root: Node) -> void:
	if root == null:
		return
	if root is MeshInstance3D:
		_apply_cinder_burn_overlay_to_mesh(root as MeshInstance3D)
	for child in root.get_children():
		_apply_cinder_burn_overlay(child)


func _clear_cinder_burn_overlay(root: Node) -> void:
	if root == null:
		return
	if root is MeshInstance3D:
		var mesh_instance := root as MeshInstance3D
		if mesh_instance.material_overlay != null and bool(mesh_instance.material_overlay.get_meta(CINDER_SCORCH_OVERLAY_META, false)):
			mesh_instance.material_overlay = _get_cinder_burn_clear_material()
		if mesh_instance.material_override != null and bool(mesh_instance.material_override.get_meta(CINDER_SCORCH_OVERLAY_META, false)):
			mesh_instance.material_override = _get_cinder_burn_clear_material()
	for child in root.get_children():
		_clear_cinder_burn_overlay(child)


func _apply_cinder_burn_overlay_to_mesh(mesh_instance: MeshInstance3D) -> void:
	mesh_instance.material_override = _get_cinder_burn_overlay_material()


func _node_has_cinder_burned_material(root: Node) -> bool:
	if root == null:
		return false
	if root is MeshInstance3D and _mesh_has_cinder_burned_material(root as MeshInstance3D):
		return true
	for child in root.get_children():
		if _node_has_cinder_burned_material(child):
			return true
	return false


func _mesh_has_cinder_burned_material(mesh_instance: MeshInstance3D) -> bool:
	if mesh_instance.material_overlay != null and bool(mesh_instance.material_overlay.get_meta(CINDER_BURNED_MATERIAL_META, false)):
		return true
	if mesh_instance.material_override != null and bool(mesh_instance.material_override.get_meta(CINDER_BURNED_MATERIAL_META, false)):
		return true
	for surface_index in range(mesh_instance.get_surface_override_material_count()):
		var material := mesh_instance.get_surface_override_material(surface_index)
		if material != null and bool(material.get_meta(CINDER_BURNED_MATERIAL_META, false)):
			return true
	return false


func _get_cinder_burn_overlay_material() -> Material:
	if _cinder_burn_overlay_material != null:
		return _cinder_burn_overlay_material
	var material := StandardMaterial3D.new()
	material.resource_name = "Cinder Burn Overlay"
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.albedo_texture = _get_cinder_burn_overlay_texture()
	material.albedo_color = Color(0.004, 0.0035, 0.003, 1.0)
	material.roughness = 1.0
	material.set_meta(CINDER_BURNED_MATERIAL_META, true)
	material.set_meta(CINDER_SCORCH_OVERLAY_META, true)
	_cinder_burn_overlay_material = material
	return _cinder_burn_overlay_material


func _get_cinder_burn_clear_material() -> Material:
	var material := StandardMaterial3D.new()
	material.resource_name = "Cleared Cinder Surface"
	material.albedo_color = Color(0.02, 0.018, 0.015, 1.0)
	material.roughness = 1.0
	return material


func _get_cinder_burn_overlay_texture() -> Texture2D:
	if _cinder_burn_overlay_texture != null:
		return _cinder_burn_overlay_texture
	var size := 128
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	for y in range(size):
		for x in range(size):
			var uv := Vector2(float(x) / float(size - 1), float(y) / float(size - 1))
			var mask := _get_cinder_burn_overlay_mask(uv, x, y)
			var ash := _cinder_overlay_noise01(x, y, 29)
			var shade := 0.006 + ash * 0.028
			var color := Color(shade, shade * 0.9, shade * 0.78, mask)
			if mask > 0.58 and _cinder_overlay_noise01(x, y, 53) > 0.88:
				color = Color(0.18, 0.16, 0.13, mask * 0.86)
			image.set_pixel(x, y, color)
	_cinder_burn_overlay_texture = ImageTexture.create_from_image(image)
	return _cinder_burn_overlay_texture


func _get_cinder_burn_overlay_mask(uv: Vector2, x: int, y: int) -> float:
	var center := uv - Vector2(0.5, 0.5)
	var radial := maxf(0.0, 1.0 - center.length() / 0.92)
	var lobe_a := maxf(0.0, 1.0 - uv.distance_to(Vector2(0.32, 0.62)) / 0.52)
	var lobe_b := maxf(0.0, 1.0 - uv.distance_to(Vector2(0.68, 0.38)) / 0.48)
	var lobe_c := maxf(0.0, 1.0 - uv.distance_to(Vector2(0.55, 0.77)) / 0.44)
	var lobe_d := maxf(0.0, 1.0 - uv.distance_to(Vector2(0.46, 0.28)) / 0.36)
	var crack := 0.5 + 0.5 * sin((uv.x * 15.0 + uv.y * 8.0 + _cinder_overlay_noise01(x, y, 7) * 2.0) * PI)
	var grain := _cinder_overlay_noise01(x, y, 13)
	var mask := radial * 0.7 + lobe_a * 0.46 + lobe_b * 0.44 + lobe_c * 0.34 + lobe_d * 0.26 + crack * 0.2 + grain * 0.24 - 0.13
	mask = clampf(mask, 0.0, 1.0)
	return mask * mask * (3.0 - 2.0 * mask)


func _cinder_overlay_noise01(x: int, y: int, salt: int) -> float:
	var value := sin(float(x * 23 + salt * 41) * 12.9898 + float(y * 31 + salt * 17) * 78.233) * 43758.5453
	return value - floor(value)
