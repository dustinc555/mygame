extends Node

class_name DemoSimBootstrap

const DEMO_SIM_ENTITY_ID := "demo_sim:state"
const WORLD_SQUAD_ENTITY_ID := "world_squad:state"
const GECS_WORLD_SCRIPT := preload("res://addons/gecs/ecs/world.gd")
const GECS_ENTITY_SCRIPT := preload("res://addons/gecs/ecs/entity.gd")
const DEMO_SIM_STATE_SCRIPT := preload("res://scripts/ecs/components/c_game_demo_sim_state.gd")
const WORLD_SQUAD_STATE_SCRIPT := preload("res://scripts/ecs/components/c_game_world_squad_state.gd")

@export var world_definition: Resource

var _ecs_world
var _sim_state_entity
var _sim_state_component
var _world_squad_state_entity
var _world_squad_state_component
var _sim_runner: Node


func _ready() -> void:
	add_to_group("demo_sim_bootstrap")
	_ensure_world()
	_ensure_state_entity()
	_ensure_world_squad_state_entity()
	_sim_runner = _find_sim_runner()


func _exit_tree() -> void:
	var ecs_singleton := get_node_or_null("/root/ECS")
	if ecs_singleton != null and ecs_singleton.get("world") == _ecs_world:
		ecs_singleton.set("world", null)


func get_sim_state() -> Dictionary:
	_ensure_state_entity()
	_ensure_world_squad_state_entity()
	var state := {}
	if _sim_state_component != null and _sim_state_component.has_method("to_state"):
		state = _sim_state_component.call("to_state")
	state["world_squad_state"] = get_world_squad_state()
	return state


func get_world_squad_state() -> Dictionary:
	_ensure_world_squad_state_entity()
	if _world_squad_state_component != null and _world_squad_state_component.has_method("to_state"):
		return _world_squad_state_component.call("to_state")
	return {}


func update_sim(fixed_delta: float) -> void:
	_ensure_state_entity()
	if _ecs_world != null and _ecs_world.has_method("process"):
		_ecs_world.call("process", fixed_delta)


func get_sim_metrics() -> Dictionary:
	var metrics := {}
	var runner := _get_sim_runner()
	if runner != null and runner.has_method("get_metrics"):
		metrics = runner.call("get_metrics")
	metrics["state"] = get_sim_state()
	return metrics


func _ensure_world() -> void:
	if _ecs_world != null and is_instance_valid(_ecs_world):
		_set_active_ecs_world()
		return
	_ecs_world = get_node_or_null("DemoSimECSWorld")
	if _ecs_world == null:
		_ecs_world = GECS_WORLD_SCRIPT.new()
		_ecs_world.name = "DemoSimECSWorld"
		add_child(_ecs_world)
	if _ecs_world.has_method("initialize"):
		_ecs_world.call("initialize")
	_set_active_ecs_world()


func _ensure_state_entity() -> void:
	_ensure_world()
	if _ecs_world == null:
		return
	if _sim_state_entity == null or not is_instance_valid(_sim_state_entity):
		_sim_state_entity = _find_entity_by_id(DEMO_SIM_ENTITY_ID)
	if _sim_state_entity == null:
		_sim_state_entity = GECS_ENTITY_SCRIPT.new()
		_sim_state_entity.name = "DemoSimState"
		_sim_state_entity.id = DEMO_SIM_ENTITY_ID
		_ecs_world.call("add_entity", _sim_state_entity, [DEMO_SIM_STATE_SCRIPT.new()])
		_sim_state_component = _sim_state_entity.call("get_component", DEMO_SIM_STATE_SCRIPT)
		if _sim_state_component != null and _sim_state_component.has_method("apply_state"):
			_sim_state_component.call("apply_state", _initial_state())
		return
	_sim_state_component = _sim_state_entity.call("get_component", DEMO_SIM_STATE_SCRIPT)


func _ensure_world_squad_state_entity() -> void:
	_ensure_world()
	if _ecs_world == null:
		return
	if _world_squad_state_entity == null or not is_instance_valid(_world_squad_state_entity):
		_world_squad_state_entity = _find_entity_by_id(WORLD_SQUAD_ENTITY_ID)
	if _world_squad_state_entity == null:
		_world_squad_state_entity = GECS_ENTITY_SCRIPT.new()
		_world_squad_state_entity.name = "WorldSquadState"
		_world_squad_state_entity.id = WORLD_SQUAD_ENTITY_ID
		_ecs_world.call("add_entity", _world_squad_state_entity, [WORLD_SQUAD_STATE_SCRIPT.new()])
	_world_squad_state_component = _world_squad_state_entity.call("get_component", WORLD_SQUAD_STATE_SCRIPT)
	if _world_squad_state_component == null or not _world_squad_state_component.has_method("apply_state"):
		return
	if _world_squad_state_is_empty():
		_world_squad_state_component.call("apply_state", _initial_world_squad_state())


func _world_squad_state_is_empty() -> bool:
	if _world_squad_state_component == null:
		return true
	var active_squads = _world_squad_state_component.get("active_squads")
	return not (active_squads is Dictionary) or active_squads.is_empty()


func _find_entity_by_id(entity_id: String):
	var registry = _ecs_world.get("entity_id_registry")
	if registry is Dictionary:
		var entity = registry.get(entity_id)
		if entity != null and is_instance_valid(entity):
			return entity
	return null


func _initial_state() -> Dictionary:
	return {
		"state_id": "demo_sim",
		"world_id": _world_definition_id(),
		"world_definition_path": _world_definition_path(),
	}


func _initial_world_squad_state() -> Dictionary:
	var active_squads := {}
	var faction_locations := _settlement_locations_by_faction_id()
	var squad_templates := _world_squad_templates()
	for index in range(squad_templates.size()):
		var template := squad_templates[index]
		var squad_id := _squad_id_for_template(template, index)
		var faction_id := _template_faction_id(template)
		active_squads[squad_id] = _squad_record_from_template(
			squad_id,
			faction_id,
			template,
			faction_locations.get(faction_id, Vector3.ZERO)
		)
	return {
		"state_id": "world_squads",
		"squad_index": active_squads.size(),
		"active_squads": active_squads,
	}


func _squad_record_from_template(squad_id: String, faction_id: String, template: Resource, location: Vector3) -> Dictionary:
	var member_count := _resource_int(template, "member_count", 1)
	var base_strength := _resource_float(template, "base_strength", 0.0)
	var base_attack_damage := _resource_float(template, "base_attack_damage", 0.0)
	return {
		"squad_id": squad_id,
		"faction_id": faction_id,
		"location": location,
		"objective_id": "hold_position",
		"member_count": member_count,
		"strength": base_strength + float(member_count) * base_attack_damage,
		"morale": 1.0,
		"supplies": _resource_float(template, "food_capacity", 0.0),
		"state": "idle",
	}


func _world_squad_templates() -> Array[Resource]:
	var result: Array[Resource] = []
	if world_definition == null:
		return result
	var templates = world_definition.get("squad_templates")
	if not (templates is Array):
		return result
	for template in templates:
		if template is Resource:
			result.append(template)
	return result


func _settlement_locations_by_faction_id() -> Dictionary:
	var result := {}
	if world_definition == null:
		return result
	var placements = world_definition.get("settlement_placements")
	if not (placements is Array):
		return result
	for placement in placements:
		if not (placement is Resource):
			continue
		var settlement_definition := placement.get("settlement_definition") as Resource
		var faction_id := _settlement_faction_id(settlement_definition)
		if faction_id.is_empty() or result.has(faction_id):
			continue
		result[faction_id] = _placement_world_position(placement)
	return result


func _settlement_faction_id(settlement_definition: Resource) -> String:
	if settlement_definition == null:
		return ""
	if settlement_definition.has_method("get_faction_id"):
		return str(settlement_definition.call("get_faction_id")).strip_edges()
	var faction_definition := settlement_definition.get("faction_definition") as Resource
	return _resource_id(faction_definition)


func _placement_world_position(placement: Resource) -> Vector3:
	var transform_value = placement.get("world_transform")
	if transform_value is Transform3D:
		var world_transform: Transform3D = transform_value
		return world_transform.origin
	var settlement_definition := placement.get("settlement_definition") as Resource
	if settlement_definition != null:
		var position_value = settlement_definition.get("world_position")
		if position_value is Vector3:
			return position_value
	return Vector3.ZERO


func _squad_id_for_template(template: Resource, index: int) -> String:
	var template_id := _resource_id(template)
	if template_id.is_empty():
		template_id = "squad_%02d" % index
	return "demo_squad:%s" % template_id


func _template_faction_id(template: Resource) -> String:
	if template != null and template.has_method("get_faction_id"):
		return str(template.call("get_faction_id")).strip_edges()
	var faction_definition := template.get("faction_definition") as Resource if template != null else null
	return _resource_id(faction_definition)


func _resource_id(resource: Resource) -> String:
	if resource != null and resource.has_method("get_id"):
		return str(resource.call("get_id")).strip_edges()
	return ""


func _resource_int(resource: Resource, property_name: String, default_value: int) -> int:
	return int(resource.get(property_name)) if resource != null else default_value


func _resource_float(resource: Resource, property_name: String, default_value: float) -> float:
	return float(resource.get(property_name)) if resource != null else default_value


func _world_definition_id() -> String:
	if world_definition != null and world_definition.has_method("get_id"):
		return str(world_definition.call("get_id")).strip_edges()
	return ""


func _world_definition_path() -> String:
	return str(world_definition.resource_path) if world_definition != null else ""


func _set_active_ecs_world() -> void:
	var ecs_singleton := get_node_or_null("/root/ECS")
	if ecs_singleton != null:
		ecs_singleton.set("world", _ecs_world)


func _get_sim_runner() -> Node:
	if _sim_runner != null and is_instance_valid(_sim_runner):
		return _sim_runner
	_sim_runner = _find_sim_runner()
	return _sim_runner


func _find_sim_runner() -> Node:
	var direct := get_node_or_null("FixedTickSimRunner")
	if direct != null:
		return direct
	for child in get_children():
		if child.is_in_group("fixed_tick_sim_runner"):
			return child
	return null
