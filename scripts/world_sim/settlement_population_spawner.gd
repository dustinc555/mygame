extends Node3D

class_name SettlementPopulationSpawner

const FACTION_HUMANOID_SCRIPT = preload("res://scripts/characters/faction_humanoid.gd")

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
@export_enum("Orderly Ring", "Messy Camp") var spawn_layout := 0
@export var spawn_radius := 7.0
@export var spawn_inner_radius := 2.0
@export var y_offset := 0.6
@export var random_seed := 1


func _ready() -> void:
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
		actor.set("starting_equipment", starting_equipment)
		actor.position = _spawn_position(resident_index - 1, desired_count, rng)
		_add_basic_humanoid_children(actor)
		add_child(actor)


func _get_desired_population() -> int:
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
