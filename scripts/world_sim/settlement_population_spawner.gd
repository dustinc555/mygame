extends Node3D

class_name SettlementPopulationSpawner

const FACTION_HUMANOID_SCRIPT = preload("res://scripts/characters/faction_humanoid.gd")
const POPULATION_NAME_PROFILE_SCRIPT = preload("res://scripts/world_sim/population_name_profile.gd")

@export var settlement_definition: Resource
@export var member_name_prefix := "Resident"
@export var stable_id_prefix := "resident"
@export var faction_id := ""
@export var squad_name := ""
@export var base_color := Color(0.62, 0.62, 0.62, 1.0)
@export var color_variation := 0.08
@export var hostile_faction_ids: PackedStringArray = PackedStringArray()
@export_range(0, 2, 1) var combat_stance := NpcRules.CombatStance.DEFENSIVE
@export var starting_equipment: Array[Resource] = []
@export var population_appearance_profile: Resource
@export var population_name_profile: Resource
@export var apply_profile_to_existing_residents := true
@export var apply_name_profile_to_existing_residents := true
@export var desired_population_override := -1
@export_enum("Orderly Ring", "Messy Camp") var spawn_layout := 0
@export var spawn_radius := 7.0
@export var spawn_inner_radius := 2.0
@export var y_offset := 0.6
@export var random_seed := 1
@export_range(1, 100, 1) var resident_perception_min := 2
@export_range(1, 100, 1) var resident_perception_max := 8

var _used_population_names: Dictionary = {}
var _default_population_name_profile: Resource


func _ready() -> void:
	_used_population_names.clear()
	_apply_profile_to_existing_residents()
	if apply_name_profile_to_existing_residents:
		_apply_name_profile_to_existing_residents()
	else:
		_collect_existing_population_names()
	_apply_default_skills_to_existing_residents()
	_spawn_missing_residents()


func _spawn_missing_residents() -> void:
	var desired_count: int = _get_desired_population()
	var existing_count: int = _count_existing_residents()
	var missing_count: int = max(0, desired_count - existing_count)
	if missing_count <= 0:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = max(1, random_seed)
	for index in range(missing_count):
		var resident_index := existing_count + index + 1
		var actor := CharacterBody3D.new()
		actor.name = "%s%02d" % [member_name_prefix.replace(" ", ""), resident_index]
		actor.set_script(FACTION_HUMANOID_SCRIPT)
		actor.set("member_name", "%s %02d" % [member_name_prefix, resident_index])
		actor.set("stable_id", "%s.%02d" % [stable_id_prefix, resident_index])
		actor.set("faction_name", _get_faction_id())
		actor.set("squad_name", squad_name if not squad_name.is_empty() else get_parent().name)
		actor.set("hostile_factions", hostile_faction_ids)
		actor.set("combat_stance", combat_stance)
		actor.set("base_color", _varied_color(rng))
		actor.set("starting_equipment", starting_equipment.duplicate())
		_apply_profile_to_actor(actor, resident_index)
		_apply_name_profile_to_actor(actor, resident_index)
		_apply_default_skills_to_actor(actor, resident_index)
		actor.position = _spawn_position(resident_index - 1, desired_count, rng)
		_add_basic_humanoid_children(actor)
		add_child(actor)


func _apply_profile_to_existing_residents() -> void:
	if not apply_profile_to_existing_residents or population_appearance_profile == null:
		return
	var resident_index := 1
	for child in get_children():
		if child.has_method("assign_attack_target"):
			_apply_profile_to_actor(child, resident_index)
			resident_index += 1


func _apply_name_profile_to_existing_residents() -> void:
	var name_profile := _get_effective_population_name_profile()
	if name_profile == null:
		_collect_existing_population_names()
		return
	var resident_index := 1
	for child in get_children():
		if child.has_method("assign_attack_target"):
			_apply_name_profile_to_actor(child, resident_index, name_profile)
			resident_index += 1


func _apply_default_skills_to_existing_residents() -> void:
	var resident_index := 1
	for child in get_children():
		if child.has_method("assign_attack_target"):
			_apply_default_skills_to_actor(child, resident_index)
			resident_index += 1


func _apply_profile_to_actor(actor: Node, resident_index: int) -> void:
	if population_appearance_profile == null or actor == null or not population_appearance_profile.has_method("apply_to_actor"):
		return
	var rng := _make_resident_rng(resident_index, str(actor.get("stable_id")))
	population_appearance_profile.call("apply_to_actor", actor, rng, true)


func _apply_name_profile_to_actor(actor: Node, resident_index: int, name_profile: Resource = null) -> void:
	if name_profile == null:
		name_profile = _get_effective_population_name_profile()
	if name_profile == null or actor == null or not name_profile.has_method("generate_name"):
		return
	if actor.is_inside_tree() and not apply_name_profile_to_existing_residents:
		return
	var appearance = actor.get("appearance_data")
	var body_type := int(appearance.visual_body_type) if appearance != null else int(actor.get("visual_body_type"))
	var rng := _make_resident_rng(resident_index, "%s:name" % str(actor.get("stable_id")))
	var generated_name := str(name_profile.call("generate_name", body_type, rng, _used_population_names)).strip_edges()
	if generated_name.is_empty():
		return
	actor.set("member_name", generated_name)
	_used_population_names[generated_name.to_lower()] = true
	if actor.is_inside_tree() and actor.has_method("refresh_nameplate"):
		actor.call("refresh_nameplate")


func _apply_default_skills_to_actor(actor: Node, resident_index: int) -> void:
	if actor == null or not actor.has_method("get_skill_level") or not actor.has_method("set_skill_level"):
		return
	var current_perception := int(actor.call("get_skill_level", SkillRules.ATTRIBUTE_PERCEPTION))
	if current_perception > SkillRules.DEFAULT_LEVEL:
		return
	var rng := _make_resident_rng(resident_index, "%s:perception" % str(actor.get("stable_id")))
	actor.call("set_skill_level", SkillRules.ATTRIBUTE_PERCEPTION, _roll_center_biased_level(resident_perception_min, resident_perception_max, rng))


func _get_effective_population_name_profile() -> Resource:
	if population_name_profile != null:
		return population_name_profile
	var settlement_profile := _get_settlement_population_name_profile()
	if settlement_profile != null:
		return settlement_profile
	if _default_population_name_profile == null:
		_default_population_name_profile = POPULATION_NAME_PROFILE_SCRIPT.new()
		_default_population_name_profile.set("profile_id", "default_population_names")
		_default_population_name_profile.set("display_name", "Default Population Names")
	return _default_population_name_profile


func _get_settlement_population_name_profile() -> Resource:
	if settlement_definition == null:
		return null
	if settlement_definition.has_method("get_population_name_profile"):
		return settlement_definition.call("get_population_name_profile") as Resource
	return settlement_definition.get("population_name_profile") as Resource


func _collect_existing_population_names() -> void:
	for child in get_children():
		if not child.has_method("assign_attack_target"):
			continue
		var display_name := str(child.get("member_name")).strip_edges()
		if not display_name.is_empty():
			_used_population_names[display_name.to_lower()] = true


func _get_desired_population() -> int:
	if desired_population_override >= 0:
		return desired_population_override
	var max_occupancy := _get_authored_population_capacity()
	if max_occupancy <= 0:
		return 0
	return max(0, int(round(float(max_occupancy) * _get_occupancy_multiplier())))


func _count_existing_residents() -> int:
	var count := 0
	for child in get_children():
		if child.has_method("assign_attack_target"):
			count += 1
	return count


func _get_faction_id() -> String:
	if not faction_id.is_empty():
		return faction_id
	if settlement_definition != null and settlement_definition.has_method("get_faction_id"):
		return str(settlement_definition.call("get_faction_id"))
	return ""


func _get_authored_population_capacity() -> int:
	var node: Node = get_parent()
	while node != null:
		if node.has_method("get_authored_population_capacity"):
			return max(0, int(node.call("get_authored_population_capacity")))
		node = node.get_parent()
	return 0


func _get_occupancy_multiplier() -> float:
	if settlement_definition != null and settlement_definition.has_method("get_occupancy_multiplier"):
		return maxf(0.0, float(settlement_definition.call("get_occupancy_multiplier")))
	return 1.0


func _make_resident_rng(resident_index: int, stable_id := "") -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	var seed_key := "%d:%s:%d:%s" % [random_seed, stable_id_prefix, resident_index, stable_id]
	rng.seed = max(1, absi(seed_key.hash()))
	return rng


func _roll_center_biased_level(minimum: int, maximum: int, rng: RandomNumberGenerator) -> int:
	var low := mini(minimum, maximum)
	var high := maxi(minimum, maximum)
	if low == high:
		return low
	var t := (rng.randf() + rng.randf()) * 0.5
	return clampi(int(round(lerpf(float(low), float(high), t))), low, high)


func _spawn_position(index: int, count: int, rng: RandomNumberGenerator) -> Vector3:
	if spawn_layout == 1:
		var angle := rng.randf_range(0.0, TAU)
		var radius := rng.randf_range(spawn_inner_radius, spawn_radius)
		return Vector3(cos(angle) * radius, y_offset, sin(angle) * radius)
	var angle := TAU * float(index) / maxf(float(count), 1.0)
	var radius := spawn_radius + rng.randf_range(-0.8, 0.8)
	return Vector3(cos(angle) * radius, y_offset, sin(angle) * radius)


func _varied_color(rng: RandomNumberGenerator) -> Color:
	var offset := rng.randf_range(-color_variation, color_variation)
	return Color(
		clampf(base_color.r + offset, 0.0, 1.0),
		clampf(base_color.g + offset, 0.0, 1.0),
		clampf(base_color.b + offset, 0.0, 1.0),
		base_color.a
	)


func _add_basic_humanoid_children(actor: Node) -> void:
	var collision := CollisionShape3D.new()
	collision.name = "CollisionShape3D"
	collision.transform = Transform3D(Basis(), Vector3(0.0, 0.95, 0.0))
	var capsule_shape := CapsuleShape3D.new()
	capsule_shape.radius = 0.45
	capsule_shape.height = 1.1
	collision.shape = capsule_shape
	actor.add_child(collision)

	var body := MeshInstance3D.new()
	body.name = "BodyMesh"
	body.transform = Transform3D(Basis(), Vector3(0.0, 0.95, 0.0))
	var capsule_mesh := CapsuleMesh.new()
	capsule_mesh.radius = 0.45
	body.mesh = capsule_mesh
	actor.add_child(body)
