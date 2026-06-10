extends "res://scripts/characters/humanoid_character.gd"

class_name RustdeadHumanoidCharacter

const RUSTDEAD_RACE = preload("res://resources/character_races/rustdead.tres")
const RUSTDEAD_APPEARANCE_DATA_SCRIPT = preload("res://scripts/character_appearance/character_appearance_data.gd")
const RUSTDEAD_TIER_LIBRARY = preload("res://scripts/characters/rustdead_tier_library.gd")

const RUSTDEAD_IDLE_ANIMATION_NAME := "Zombie_Idle"
const RUSTDEAD_WALK_ANIMATION_NAME := "Zombie_Walk_Fwd"
const RUSTDEAD_RUN_ANIMATION_NAME := "Zombie_Run_Fwd"
const RUSTDEAD_BITE_ANIMATION_NAME := "Zombie_Bite"
const RUSTDEAD_SCRATCH_ANIMATION_NAME := "Zombie_Scratch"
const RUSTDEAD_SPAWN_ANIMATION_NAME := "Zombie_Spawn"
const RUSTDEAD_ANIMATION_NAMES: Array[String] = [
	RUSTDEAD_IDLE_ANIMATION_NAME,
	RUSTDEAD_WALK_ANIMATION_NAME,
	RUSTDEAD_RUN_ANIMATION_NAME,
	RUSTDEAD_BITE_ANIMATION_NAME,
	RUSTDEAD_SCRATCH_ANIMATION_NAME,
	RUSTDEAD_SPAWN_ANIMATION_NAME,
]
const CINDER_BURNED_MATERIAL_META := "cinder_burned"
const CINDER_SCORCH_OVERLAY_META := "cinder_scorch_overlay"

static var _cinder_burn_overlay_material: Material
static var _cinder_burn_overlay_texture: Texture2D

@export var fresh_skin_color := Color(0.64, 0.19, 0.16, 1.0)
@export var cinder_burn_duration_seconds := 2.0
@export var rustdead_tier_definition: Resource
@export var rustdead_tier_id := "fresh"
@export_range(0.0, 2.0, 0.01) var rustdead_passive_bonus := 0.2

var _cinder_burn_remaining := 0.0
var _cinder_burn_attacker: HumanoidCharacter
var _cinder_burn_effect: Node3D
var _cinder_burn_fire_seed := 0.0
var _allow_cinder_true_death := false
var _is_cinder_burned := false


func _ready() -> void:
	_ensure_rustdead_humanoid_defaults()
	super._ready()


func _exit_tree() -> void:
	_clear_cinder_burned_visuals()
	_free_rustdead_visual_root_for_exit()
	_clear_cinder_burn_effect()
	super._exit_tree()


func _process(delta: float) -> void:
	_process_cinder_burn(delta)
	super._process(delta)


func _setup_character_visual() -> void:
	super._setup_character_visual()
	if _is_cinder_burned:
		_apply_cinder_burned_visuals()


func _create_body_projection() -> BodyProjection:
	return RustdeadBodyProjection.new()


func requires_fire_to_die() -> bool:
	return true


func set_rustdead_tier_definition(tier_definition: Resource) -> void:
	rustdead_tier_definition = tier_definition
	_apply_rustdead_tier_definition()


func get_rustdead_tier_definition() -> Resource:
	return rustdead_tier_definition


func get_rustdead_tier_id() -> String:
	return rustdead_tier_id


func get_rustdead_passive_bonus() -> float:
	return maxf(0.0, rustdead_passive_bonus)


func can_be_destroyed_by_cinder() -> bool:
	return is_downed_state() and not is_fire_destruction_in_progress()


func is_fire_destruction_in_progress() -> bool:
	return _cinder_burn_remaining > 0.0


func is_cinder_burned() -> bool:
	return _is_cinder_burned


func has_cinder_burned_visuals() -> bool:
	var visual_root := get_node_or_null(CHARACTER_VISUAL_NODE_NAME)
	if visual_root != null and _node_has_cinder_burned_material(visual_root):
		return true
	var body_mesh := get_node_or_null("BodyMesh")
	return body_mesh != null and _node_has_cinder_burned_material(body_mesh)


func begin_cinder_burn(attacker: HumanoidCharacter = null) -> bool:
	if not can_be_destroyed_by_cinder():
		return false
	_cinder_burn_attacker = attacker
	_cinder_burn_remaining = maxf(0.05, cinder_burn_duration_seconds)
	_cinder_burn_fire_seed = _rng.randf() * TAU
	_downed_recover_delay_remaining = maxf(_downed_recover_delay_remaining, _cinder_burn_remaining + 1.0)
	if _is_getting_up:
		_cancel_get_up()
	_is_cinder_burned = true
	_apply_cinder_burned_visuals()
	_enter_cinder_dead_state_in_place()
	_spawn_cinder_burn_effect()
	_show_world_notice("Burning", Color(1.0, 0.45, 0.12, 1.0), 1.6)
	state_changed.emit()
	return true


func force_kill(attacker: HumanoidCharacter = null) -> void:
	if _allow_cinder_true_death:
		super.force_kill(attacker)
		return
	if life_state == NpcRules.LifeState.DEAD:
		return
	var lethal_wounds := max_hp - get_death_point(max_hp)
	var current_wounds := get_total_wound_damage()
	if current_wounds < lethal_wounds:
		_current_blunt_damage += lethal_wounds - current_wounds
	blood = minf(blood, 0.0)
	_recalculate_vitals()
	if not is_downed_state():
		_enter_unconscious_state()


func _should_enter_dead_state_from_vitals() -> bool:
	return false


func _should_enter_dying_state_from_vitals() -> bool:
	return false


func _is_downed_recovery_locked() -> bool:
	return is_fire_destruction_in_progress()


func _ensure_rustdead_humanoid_defaults() -> void:
	character_race = RUSTDEAD_RACE
	_apply_rustdead_tier_definition()
	if appearance_data == null:
		appearance_data = RUSTDEAD_APPEARANCE_DATA_SCRIPT.new()
	elif appearance_data.has_method("make_copy"):
		appearance_data = appearance_data.make_copy()
	appearance_data.character_race = RUSTDEAD_RACE
	if appearance_data.visual_body_type == APPEARANCE_VISUAL_BODY_TYPE_AUTO:
		appearance_data.visual_body_type = visual_body_type
	if not bool(appearance_data.skin_color_customized):
		appearance_data.skin_color_customized = true
		appearance_data.skin_color = fresh_skin_color
	appearance_data.eyebrow_style = null


func _apply_rustdead_tier_definition() -> void:
	if rustdead_tier_definition == null:
		rustdead_tier_definition = RUSTDEAD_TIER_LIBRARY.get_tier_by_id(rustdead_tier_id)
	if rustdead_tier_definition == null:
		rustdead_tier_definition = RUSTDEAD_TIER_LIBRARY.get_default_tier()
	if rustdead_tier_definition != null:
		rustdead_tier_id = str(rustdead_tier_definition.call("get_id")) if rustdead_tier_definition.has_method("get_id") else rustdead_tier_id
		rustdead_passive_bonus = maxf(0.0, float(rustdead_tier_definition.get("passive_bonus")))


func _apply_automatic_eyebrow_style() -> void:
	if appearance_data == null:
		return
	appearance_data.eyebrow_style = null
	appearance_data.eyebrow_color = Color(0.08, 0.015, 0.018, 1.0)


func _build_unarmed_combat_animation_set():
	var animation_set = COMBAT_ANIMATION_SET_SCRIPT.new()
	animation_set.stance_id = UNARMED_STANCE_ID
	animation_set.idle_animation_name = RUSTDEAD_IDLE_ANIMATION_NAME
	animation_set.block_animation_name = ""
	animation_set.fallback_hit_reaction_names = PackedStringArray([HIT_CHEST_ANIMATION_NAME, HIT_HEAD_ANIMATION_NAME, HIT_STOMACH_ANIMATION_NAME])
	animation_set.attacks = [
		_make_combat_attack("rustdead_bite", [RUSTDEAD_BITE_ANIMATION_NAME], 1.15, 0.52, [HIT_HEAD_ANIMATION_NAME, HIT_CHEST_ANIMATION_NAME]),
		_make_combat_attack("rustdead_scratch", [RUSTDEAD_SCRATCH_ANIMATION_NAME], 1.0, 0.48, [HIT_CHEST_ANIMATION_NAME, HIT_STOMACH_ANIMATION_NAME]),
	]
	return animation_set


func _collect_stat_modifiers() -> Array:
	var modifiers := super._collect_stat_modifiers()
	var bonus := get_rustdead_passive_bonus()
	if bonus <= 0.0:
		return modifiers
	var multiplier := 1.0 + bonus
	modifiers.append({"stat": "healing_rate", "mul": multiplier})
	modifiers.append({"stat": "blood_recovery_rate", "mul": multiplier})
	if _is_unarmed_combat_stance():
		modifiers.append({"stat": "attack_damage", "mul": multiplier})
		modifiers.append({"stat": "cut_ratio", "mul": multiplier})
	return modifiers


func _get_current_combat_idle_animation_name(animation_set) -> String:
	if _get_current_combat_animation_stance_id() == UNARMED_STANCE_ID and _character_animation_player != null and _character_animation_player.has_animation(RUSTDEAD_IDLE_ANIMATION_NAME):
		return RUSTDEAD_IDLE_ANIMATION_NAME
	return super._get_current_combat_idle_animation_name(animation_set)


func _process_cinder_burn(delta: float) -> void:
	if _cinder_burn_remaining <= 0.0:
		return
	_cinder_burn_remaining = maxf(0.0, _cinder_burn_remaining - delta)
	_downed_recover_delay_remaining = maxf(_downed_recover_delay_remaining, _cinder_burn_remaining + 0.5)
	_update_cinder_burn_effect_position()
	_update_cinder_burn_effect()
	if _cinder_burn_remaining <= 0.0:
		_finish_cinder_burn()


func _spawn_cinder_burn_effect() -> void:
	_clear_cinder_burn_effect()
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
	_update_cinder_burn_effect()


func _update_cinder_burn_effect_position() -> void:
	if _cinder_burn_effect == null or not is_instance_valid(_cinder_burn_effect):
		return
	_cinder_burn_effect.global_position = get_follow_anchor_position() + Vector3(0.0, 0.35, 0.0)


func _update_cinder_burn_effect() -> void:
	if _cinder_burn_effect == null or not is_instance_valid(_cinder_burn_effect):
		return
	var duration := maxf(cinder_burn_duration_seconds, 0.05)
	var elapsed := duration - _cinder_burn_remaining
	var intensity := minf(1.0, elapsed / 0.75) * minf(1.0, _cinder_burn_remaining / 3.0)
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


func _finish_cinder_burn() -> void:
	_clear_cinder_burn_effect()
	_cinder_burn_attacker = null
	_show_world_notice("Burned", Color(0.9, 0.28, 0.08, 1.0), 1.6)


func _enter_cinder_dead_state_in_place() -> void:
	if life_state == NpcRules.LifeState.DEAD:
		return
	_report_murder_crime_if_needed()
	var previous_state := life_state
	life_state = NpcRules.LifeState.DEAD
	_notify_law_order_actor_death()
	_cancel_get_up()
	COMBAT_COORDINATOR.release_character(self)
	running = false
	_clear_actor_move_target()
	_clear_combat_action()
	_combat_reaction_remaining = 0.0
	_combat_reaction_source = null
	if _carried_character != null:
		drop_carried_character()
	if _active_job_provider != null and _active_job_provider.has_method("pause_worker_job"):
		_active_job_provider.pause_worker_job(self, false)
	velocity = Vector3.ZERO
	life_state_changed.emit(previous_state, life_state)
	died.emit(self)
	state_changed.emit()


func _clear_cinder_burn_effect() -> void:
	if _cinder_burn_effect == null:
		return
	var effect := _cinder_burn_effect
	_cinder_burn_effect = null
	if is_instance_valid(effect):
		var parent := effect.get_parent()
		if parent != null:
			parent.remove_child(effect)
		effect.free()


func _apply_cinder_burned_visuals() -> void:
	var visual_root := get_node_or_null(CHARACTER_VISUAL_NODE_NAME)
	if visual_root != null:
		_apply_cinder_burn_overlay(visual_root)
	var body_mesh := get_node_or_null("BodyMesh")
	if body_mesh != null:
		_apply_cinder_burn_overlay(body_mesh)


func _clear_cinder_burned_visuals() -> void:
	var visual_root := get_node_or_null(CHARACTER_VISUAL_NODE_NAME)
	if visual_root != null:
		_clear_cinder_burn_overlay(visual_root)
	var body_mesh := get_node_or_null("BodyMesh")
	if body_mesh != null:
		_clear_cinder_burn_overlay(body_mesh)


func _free_rustdead_visual_root_for_exit() -> void:
	var visual_root := get_node_or_null(CHARACTER_VISUAL_NODE_NAME)
	if visual_root == null:
		return
	_strip_meshes_for_exit(visual_root)
	remove_child(visual_root)
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
