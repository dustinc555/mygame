extends Node3D

class_name SettlementPopulationSpawner

@export var settlement_definition: Resource
@export var member_name_prefix := "Resident"
@export var stable_id_prefix := "resident"
@export var faction_id := ""
@export var squad_name := ""
@export var base_color := Color(0.62, 0.62, 0.62, 1.0)
@export var color_variation := 0.08
@export var hostile_faction_ids: PackedStringArray = PackedStringArray()
@export_range(0, 2, 1) var combat_stance := NpcRules.CombatStance.DEFENSIVE
@export var population_appearance_profile: Resource
@export var population_name_profile: Resource
@export var desired_population_override := -1
@export_enum("Orderly Ring", "Messy Camp") var spawn_layout := 0
@export var spawn_radius := 7.0
@export var spawn_inner_radius := 2.0
@export var y_offset := 0.6
@export var random_seed := 1
@export_range(1, 100, 1) var resident_perception_min := 2
@export_range(1, 100, 1) var resident_perception_max := 8

var _population_spawn_defer_attempts := 0
var _resyncing_population := false
var _realization_dirty := true


func _ready() -> void:
	add_to_group("population_spawner")
	call_deferred("_register_with_realization_controller")
	call_deferred("_spawn_missing_residents")


func _exit_tree() -> void:
	_unregister_from_realization_controller()


func resync_population_realization() -> void:
	if _resyncing_population:
		return
	var population_controller := _get_population_controller()
	if population_controller == null:
		return
	_resyncing_population = true
	_spawn_missing_residents_from_records(population_controller)
	_resyncing_population = false
	_realization_dirty = false


func _remove_unbound_resident_bodies(population_controller: Node) -> void:
	for child in get_children():
		if not (child is WorldActor):
			continue
		var actor_id := str(child.get_meta("actor_record_id", "")).strip_edges()
		if not actor_id.is_empty() and not population_controller.call("get_actor_record", actor_id).is_empty():
			continue
		remove_child(child)
		child.queue_free()


func get_settlement_id() -> String:
	return _get_settlement_id()


func needs_population_realization_resync() -> bool:
	return _realization_dirty


func mark_population_realization_dirty() -> void:
	_realization_dirty = true


func clear_population_realization_dirty() -> void:
	_realization_dirty = false


func get_effective_realization_policy() -> String:
	return _get_effective_realization_policy()


func get_settlement_node() -> Node:
	return _get_settlement_node()


func get_realization_origin() -> Vector3:
	var settlement := _get_settlement_node()
	return (settlement as Node3D).global_position if settlement is Node3D else global_position


func has_realized_population() -> bool:
	return _count_existing_residents() > 0


func _spawn_missing_residents() -> void:
	var population_controller := _get_population_controller()
	if population_controller == null and _population_spawn_defer_attempts < 5:
		_population_spawn_defer_attempts += 1
		call_deferred("_spawn_missing_residents")
		return
	if population_controller != null:
		_spawn_missing_residents_from_records(population_controller)
		return
	push_error("Population realization rejected for %s: PopulationController is unavailable" % _get_settlement_id())


func _spawn_missing_residents_from_records(population_controller: Node) -> void:
	_remove_unbound_resident_bodies(population_controller)
	var desired_count: int = _get_desired_population()
	# Census-seeded settlements already own their people; the main-population
	# spawner's job is only to realize them. Sub-population spawners (a
	# different faction inside the town, e.g. captives in a raider camp) and
	# census-less test scenes keep minting their own records.
	var records: Array = []
	if _spawner_owns_settlement_population(population_controller):
		records = population_controller.call("get_seeded_resident_records", _get_settlement_id())
	if records.is_empty():
		var context := _build_population_generation_context(_count_existing_residents())
		records = population_controller.call("ensure_generated_population", _get_settlement_id(), _get_spawner_id(), desired_count, context)
	var rng := RandomNumberGenerator.new()
	rng.seed = max(1, _effective_generation_seed())
	var character_realizer := BootstrapContext.service(PopulationCharacterRealizer.SERVICE_ID) as PopulationCharacterRealizer
	if character_realizer == null:
		push_error("Population realization rejected for %s: PopulationCharacterRealizer is unavailable" % _get_settlement_id())
		return
	_ensure_record_spawn_positions(population_controller, records, desired_count, rng)
	var forced_realization_ids := _staff_bootstrap_realization_ids(records)
	var spawned_count := 0
	for record_value in records:
		if not (record_value is Dictionary):
			continue
		var record: Dictionary = record_value
		var existing_actor := _find_child_actor_for_record(record)
		if existing_actor is Node3D and population_controller.has_method("update_actor_record"):
			var updated_record: Dictionary = population_controller.call("update_actor_record", str(record.get("actor_id", "")), {
				"last_world_position": (existing_actor as Node3D).global_position,
				"last_world_position_initialized": true,
			})
			if not updated_record.is_empty():
				record = updated_record
		var actor_id := str(record.get("actor_id", ""))
		var should_realize := forced_realization_ids.has(actor_id) or _should_realize_record(record)
		if existing_actor != null:
			if not should_realize:
				_unrealize_actor(existing_actor, population_controller)
			continue
		if not should_realize:
			continue
		var resident_index: int = max(1, int(record.get("generation_index", spawned_count + 1)))
		var actor := character_realizer.realize_actor(actor_id, self, self, "%s%02d" % [member_name_prefix.replace(" ", ""), resident_index])
		if actor == null:
			continue
		actor.position = _record_local_spawn_position(record, resident_index - 1, max(desired_count, 1), rng)
		if population_controller.has_method("update_realized_actor_position"):
			population_controller.call("update_realized_actor_position", actor_id, actor.global_position)
		spawned_count += 1
	if _count_existing_residents() > 0:
		_notify_settlement_population_ready()
	_realization_dirty = false


## True when this spawner realizes the settlement's own people (its faction
## matches the settlement's), as opposed to a sub-population with its own
## faction and generation flavor.
func _spawner_owns_settlement_population(population_controller: Node) -> bool:
	if not population_controller.has_method("get_seeded_resident_records"):
		return false
	var spawner_faction := faction_id.strip_edges()
	if spawner_faction.is_empty():
		return true
	var definition_faction := ""
	if settlement_definition != null and settlement_definition.has_method("get_faction_id"):
		definition_faction = str(settlement_definition.call("get_faction_id"))
	return spawner_faction == definition_faction

func _build_population_generation_context(_existing_count: int) -> Dictionary:
	var type_set := _get_effective_character_type_set()
	return {
		"start_index": 0,
		"generation_seed": _effective_generation_seed(),
		"member_name_prefix": member_name_prefix,
		"faction_id": _get_faction_id(),
		"squad_name": squad_name if not squad_name.is_empty() else str(get_parent().name),
		"role_id": "resident",
		"base_color": base_color,
		"hostile_faction_ids": Array(hostile_faction_ids),
		"combat_stance": combat_stance,
		"population_appearance_profile": _get_effective_character_realizer(),
		"population_name_profile": _get_effective_population_name_profile(),
		"character_type": type_set.call("resolve_character_type", "", "resident") as Resource if type_set != null and type_set.has_method("resolve_character_type") else null,
		"resident_perception_min": resident_perception_min,
		"resident_perception_max": resident_perception_max,
	}


func _get_effective_character_realizer() -> Resource:
	if population_appearance_profile != null:
		return population_appearance_profile
	return settlement_definition.call("get_character_realizer") as Resource if settlement_definition != null and settlement_definition.has_method("get_character_realizer") else null


func _get_effective_character_type_set() -> Resource:
	return settlement_definition.call("get_character_type_set") as Resource if settlement_definition != null and settlement_definition.has_method("get_character_type_set") else null


func _should_realize_record(record: Dictionary) -> bool:
	var realization_controller := _get_population_realization_controller()
	if realization_controller == null or not realization_controller.has_method("should_realize_actor"):
		return _get_effective_realization_policy() == "full_town"
	return bool(realization_controller.call("should_realize_actor", _get_settlement_node(), record))


func _get_effective_realization_policy() -> String:
	var settlement := _get_settlement_node()
	if settlement != null:
		var value = settlement.get("actor_realization_policy")
		if value != null and not str(value).strip_edges().is_empty():
			return str(value).strip_edges()
	var realization_controller := _get_population_realization_controller()
	if realization_controller != null:
		var default_policy = realization_controller.get("default_realization_policy")
		if default_policy != null and not str(default_policy).strip_edges().is_empty():
			return str(default_policy).strip_edges()
	return "near_player"


func _register_with_realization_controller() -> void:
	var realization_controller := _get_population_realization_controller()
	if realization_controller != null and realization_controller.has_method("register_spawner"):
		realization_controller.call("register_spawner", self)


func _unregister_from_realization_controller() -> void:
	var realization_controller := _get_population_realization_controller()
	if realization_controller != null and realization_controller.has_method("unregister_spawner"):
		realization_controller.call("unregister_spawner", self)


func _find_child_actor_for_record(record: Dictionary) -> Node:
	var actor_id := str(record.get("actor_id", ""))
	if actor_id.is_empty():
		return null
	var population_controller := _get_population_controller()
	if population_controller != null and population_controller.has_method("get_live_actor"):
		var live_actor := population_controller.call("get_live_actor", actor_id) as Node
		if live_actor != null:
			return live_actor
	for child in get_children():
		if not child.has_method("assign_attack_target"):
			continue
		if str(child.get("stable_id")) == actor_id:
			return child
		if child.has_meta("actor_record_id") and str(child.get_meta("actor_record_id")) == actor_id:
			return child
	return null


func _get_effective_population_name_profile() -> Resource:
	if population_name_profile != null:
		return population_name_profile
	var settlement_profile := _get_settlement_population_name_profile()
	if settlement_profile != null:
		return settlement_profile
	return null


func _get_settlement_population_name_profile() -> Resource:
	if settlement_definition == null:
		return null
	if settlement_definition.has_method("get_population_name_profile"):
		return settlement_definition.call("get_population_name_profile") as Resource
	return settlement_definition.get("population_name_profile") as Resource


func _get_desired_population() -> int:
	if desired_population_override >= 0:
		return desired_population_override
	var settlement_controller := _get_settlement_controller()
	if settlement_controller == null or not settlement_controller.has_method("get_settlement_state"):
		return 0
	var state: Dictionary = settlement_controller.call("get_settlement_state", _get_settlement_id())
	if state.is_empty():
		return 0
	var population: int = max(0, int(state.get("population", 0)))
	var assigned: int = max(0, int(state.get("population_assigned", 0)))
	var target: int = max(0, int(state.get("population_target", 0)))
	if target <= 0:
		return 0
	if population > target:
		return mini(_count_existing_or_record_residents(), max(0, target - assigned))
	return max(0, population - assigned)


func _count_existing_residents() -> int:
	var count := 0
	for child in get_children():
		if child.has_method("assign_attack_target"):
			count += 1
	return count


func _count_existing_or_record_residents() -> int:
	var count := _count_existing_residents()
	var population_controller := _get_population_controller()
	if population_controller == null or not population_controller.has_method("get_records_for_settlement"):
		return count
	var record_count := 0
	for record in population_controller.call("get_records_for_settlement", _get_settlement_id()):
		if not (record is Dictionary):
			continue
		if str(record.get("generation_source", "")) != _get_spawner_id():
			continue
		if str(record.get("role_id", "resident")) != "resident":
			continue
		record_count += 1
	return maxi(count, record_count)


func _get_faction_id() -> String:
	if not faction_id.is_empty():
		return faction_id
	if settlement_definition != null and settlement_definition.has_method("get_faction_id"):
		return str(settlement_definition.call("get_faction_id"))
	return ""


func _get_settlement_id() -> String:
	if settlement_definition != null and settlement_definition.has_method("get_id"):
		return str(settlement_definition.call("get_id"))
	var settlement := _get_settlement_node()
	if settlement != null and settlement.has_method("get_settlement_id"):
		return str(settlement.call("get_settlement_id"))
	return str(get_parent().name) if get_parent() != null else str(name)


func _get_spawner_id() -> String:
	if not stable_id_prefix.strip_edges().is_empty():
		return stable_id_prefix.strip_edges()
	return name


func _get_settlement_node() -> Node:
	var current := get_parent()
	while current != null:
		if current is SettlementAnchor or current.is_in_group("settlement_anchor"):
			return current
		current = current.get_parent()
	return null


func _get_population_controller() -> Node:
	if not is_inside_tree():
		return null
	var nodes := get_tree().get_nodes_in_group("population_controller")
	return nodes[0] as Node if not nodes.is_empty() else null


func _get_settlement_controller() -> Node:
	if not is_inside_tree():
		return null
	var nodes := get_tree().get_nodes_in_group("settlement_controller")
	return nodes[0] as Node if not nodes.is_empty() else null


func _notify_settlement_population_ready() -> void:
	var settlement_controller := _get_settlement_controller()
	if settlement_controller != null and settlement_controller.has_method("bootstrap_staff_vacancies"):
		settlement_controller.call("bootstrap_staff_vacancies", _get_settlement_id())


func _get_population_realization_controller() -> Node:
	if not is_inside_tree():
		return null
	var nodes := get_tree().get_nodes_in_group("population_realization_controller")
	return nodes[0] as Node if not nodes.is_empty() else null


func _staff_bootstrap_realization_ids(records: Array) -> Dictionary:
	var forced := {}
	if _get_effective_realization_policy() != "important_plus_near":
		return forced
	var settlement_controller := _get_settlement_controller()
	if settlement_controller == null or not settlement_controller.has_method("get_staff_vacancy_realization_count"):
		return forced
	var needed: int = max(0, int(settlement_controller.call("get_staff_vacancy_realization_count", _get_settlement_id())))
	if needed <= 0:
		return forced
	for record_value in records:
		if needed <= 0:
			break
		if not (record_value is Dictionary):
			continue
		var record: Dictionary = record_value
		if str(record.get("role_id", "resident")) != "resident":
			continue
		var actor_id := str(record.get("actor_id", ""))
		if actor_id.is_empty():
			continue
		forced[actor_id] = true
		needed -= 1
	return forced


func _get_occupancy_multiplier() -> float:
	if settlement_definition != null and settlement_definition.has_method("get_occupancy_multiplier"):
		return maxf(0.0, float(settlement_definition.call("get_occupancy_multiplier")))
	return 1.0


## The settlement definition's generation_seed (when authored non-zero) wins
## over the node's random_seed so a town's people are reproducible from its
## .tres alone; the node export remains the fallback for definition-less
## spawners (test scenes).
func _effective_generation_seed() -> int:
	var definition := settlement_definition as SettlementDefinition
	if definition != null and definition.generation_seed != 0:
		return definition.generation_seed
	return random_seed


func _ensure_record_spawn_positions(population_controller: Node, records: Array, desired_count: int, rng: RandomNumberGenerator) -> void:
	if population_controller == null or not population_controller.has_method("update_actor_record"):
		return
	for index in range(records.size()):
		var record_value = records[index]
		if not (record_value is Dictionary):
			continue
		var record: Dictionary = record_value
		if _record_has_initialized_world_position(record):
			continue
		var generation_index: int = max(1, int(record.get("generation_index", index + 1)))
		var local_position: Vector3 = _spawn_position(generation_index - 1, max(desired_count, 1), rng)
		var world_position: Vector3 = global_transform * local_position
		var actor_id := str(record.get("actor_id", ""))
		if actor_id.is_empty():
			continue
		var updated: Dictionary = population_controller.call("update_actor_record", actor_id, {
			"last_world_position": world_position,
			"last_world_position_initialized": true,
		})
		if not updated.is_empty():
			records[index] = updated


func _record_local_spawn_position(record: Dictionary, index: int, count: int, rng: RandomNumberGenerator) -> Vector3:
	var stored_position = record.get("last_world_position", null)
	if stored_position is Vector3 and _record_has_initialized_world_position(record):
		return global_transform.affine_inverse() * (stored_position as Vector3)
	return _spawn_position(index, count, rng)


func _record_has_initialized_world_position(record: Dictionary) -> bool:
	if not bool(record.get("last_world_position_initialized", false)):
		return false
	return record.get("last_world_position", null) is Vector3


func _unrealize_actor(actor: Node, population_controller: Node) -> void:
	if actor == null or not is_instance_valid(actor):
		return
	if actor.has_method("is_player_party_member") and bool(actor.call("is_player_party_member")):
		return
	if population_controller != null and population_controller.has_method("unregister_actor"):
		population_controller.call("unregister_actor", actor)
	actor.queue_free()


func _spawn_position(index: int, count: int, rng: RandomNumberGenerator) -> Vector3:
	if spawn_layout == 1:
		var random_angle := rng.randf_range(0.0, TAU)
		var random_radius := rng.randf_range(spawn_inner_radius, spawn_radius)
		return Vector3(cos(random_angle) * random_radius, y_offset, sin(random_angle) * random_radius)
	var ring_angle := TAU * float(index) / maxf(float(count), 1.0)
	var ring_radius := spawn_radius + rng.randf_range(-0.8, 0.8)
	return Vector3(cos(ring_angle) * ring_radius, y_offset, sin(ring_angle) * ring_radius)


func _varied_color(rng: RandomNumberGenerator) -> Color:
	var offset := rng.randf_range(-color_variation, color_variation)
	return Color(
		clampf(base_color.r + offset, 0.0, 1.0),
		clampf(base_color.g + offset, 0.0, 1.0),
		clampf(base_color.b + offset, 0.0, 1.0),
		base_color.a
	)


func _has_property(target: Object, property_name: String) -> bool:
	if target == null:
		return false
	for property in target.get_property_list():
		if str(property.get("name", "")) == property_name:
			return true
	return false
