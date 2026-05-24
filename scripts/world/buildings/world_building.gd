@tool
extends StaticBody3D

class_name WorldBuilding

@export var display_name := "Building"
@export_enum("home", "bar", "shop", "weapon_shop", "armor_shop", "travel_shop", "potion_shop", "jail", "storage", "guard", "farm", "mine", "generic") var building_type := "home"
@export var owner_character_path: NodePath
@export var owner_faction_name := ""
@export_enum("default", "occupied", "abandoned", "public", "scheduled", "private") var access_mode := "default"
@export var use_law_profile_trespass_rules := true
@export_range(0, 23, 1) var public_open_hour := 8
@export_range(0, 23, 1) var public_close_hour := 21
@export_range(1.0, 30.0, 0.5) var trespass_warning_interval_seconds := 3.0
@export_range(1, 6, 1) var trespass_warnings_before_alarm := 2
@export var trespass_notice_radius := 18.0
@export var population_capacity_id := ""
@export_range(0, 1000, 1) var population_capacity := 0
@export var levels: Array[BuildingLevelDefinition] = []
@export var click_local_y := 0.1
@export var interior_area_path: NodePath
@export var roof_occluder_paths: Array[NodePath] = []
@export var front_occluder_paths: Array[NodePath] = []
@export var right_occluder_paths: Array[NodePath] = []
@export var back_occluder_paths: Array[NodePath] = []
@export var left_occluder_paths: Array[NodePath] = []

var _interior_actor_ids: Dictionary = {}
var _roof_hidden := false
var _hidden_side := ""
var _level_actor_ids: Array[Dictionary] = []
var _active_level_index := -1
var _extra_level_content_paths: Dictionary = {}
var _inside_actors: Dictionary = {}
var _trespass_warning_remaining: Dictionary = {}
var _trespass_warning_counts: Dictionary = {}
var _trespass_escalated: Dictionary = {}
var _world_time: WorldTimeController
const SIDE_SWITCH_HYSTERESIS := 0.45


func _ready() -> void:
	add_to_group("world_building")
	set_process(not Engine.is_editor_hint())
	_level_actor_ids.clear()
	for level_index in range(levels.size()):
		_level_actor_ids.append({})
		var occupancy_area := _get_level_area(level_index)
		if occupancy_area != null:
			if not occupancy_area.body_entered.is_connected(_on_level_body_entered.bind(level_index)):
				occupancy_area.body_entered.connect(_on_level_body_entered.bind(level_index))
			if not occupancy_area.body_exited.is_connected(_on_level_body_exited.bind(level_index)):
				occupancy_area.body_exited.connect(_on_level_body_exited.bind(level_index))
	var interior_area := _get_interior_area()
	if interior_area != null:
		if not interior_area.body_entered.is_connected(_on_interior_body_entered):
			interior_area.body_entered.connect(_on_interior_body_entered)
		if not interior_area.body_exited.is_connected(_on_interior_body_exited):
			interior_area.body_exited.connect(_on_interior_body_exited)
	if levels.is_empty():
		_apply_occluder_visibility(roof_occluder_paths, false)
		_apply_occluder_visibility(front_occluder_paths, false)
		_apply_occluder_visibility(right_occluder_paths, false)
		_apply_occluder_visibility(back_occluder_paths, false)
		_apply_occluder_visibility(left_occluder_paths, false)
	else:
		_refresh_level_visibility(false, Vector3.ZERO, null)


func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	_process_trespass(delta / maxf(Engine.time_scale, 0.001))


func is_actor_inside(actor: HumanoidCharacter) -> bool:
	if actor == null:
		return false
	if not levels.is_empty():
		return get_level_index_for_actor(actor) >= 0
	return _interior_actor_ids.has(actor.get_instance_id())


func set_visibility_for_camera(show_interior: bool, camera_world_position: Vector3, actor: HumanoidCharacter = null) -> void:
	if not levels.is_empty():
		_refresh_level_visibility(show_interior, camera_world_position, actor)
		return
	var next_roof_hidden := show_interior
	var next_hidden_side := ""
	if show_interior:
		next_hidden_side = _get_camera_facing_side(camera_world_position)
	if _roof_hidden == next_roof_hidden and _hidden_side == next_hidden_side:
		return
	_roof_hidden = next_roof_hidden
	_hidden_side = next_hidden_side
	_refresh_occluders()


func register_extra_level_content(level_index: int, content_path: NodePath) -> void:
	if not _is_valid_level_index(level_index) or content_path.is_empty():
		return
	var paths: Array = _extra_level_content_paths.get(level_index, [])
	if paths.has(content_path):
		return
	paths.append(content_path)
	_extra_level_content_paths[level_index] = paths
	_apply_registered_level_visibility(level_index)


func get_population_capacity_id() -> String:
	return population_capacity_id if not population_capacity_id.is_empty() else name


func get_explicit_owner_character() -> HumanoidCharacter:
	return get_node_or_null(owner_character_path) as HumanoidCharacter


func get_owner_faction_name() -> String:
	if not owner_faction_name.is_empty():
		return owner_faction_name
	var owner_character := get_explicit_owner_character()
	if owner_character != null:
		return owner_character.faction_name
	var facility := get_ancestor_facility()
	if facility != null:
		var facility_owner := str(facility.get("owner_faction_id"))
		if not facility_owner.is_empty():
			return facility_owner
	return ""


func get_ancestor_facility() -> SettlementFacility:
	var current := get_parent()
	while current != null:
		if current is SettlementFacility:
			return current as SettlementFacility
		current = current.get_parent()
	return null


func get_ancestor_settlement() -> SettlementAnchor:
	var current := get_parent()
	while current != null:
		if current is SettlementAnchor:
			return current as SettlementAnchor
		current = current.get_parent()
	return null


func get_jurisdiction_faction_name() -> String:
	var settlement := get_ancestor_settlement()
	if settlement == null:
		return ""
	var definition = settlement.get("settlement_definition")
	return str(definition.call("get_faction_id")) if definition != null and definition.has_method("get_faction_id") else ""


func get_jurisdiction_display_name() -> String:
	var settlement := get_ancestor_settlement()
	if settlement == null:
		return ""
	var definition = settlement.get("settlement_definition")
	if definition != null:
		var display := str(definition.get("display_name"))
		if not display.is_empty():
			return display
	return settlement.name.capitalize()


func get_building_type_label() -> String:
	match building_type:
		"home", "housing":
			return "Home"
		"bar":
			return "Bar"
		"shop":
			return "Shop"
		"weapon_shop":
			return "Weapon Shop"
		"armor_shop":
			return "Armor Shop"
		"travel_shop":
			return "Travel Shop"
		"potion_shop":
			return "Potion Shop"
		"jail", "police":
			return "Jail"
		"storage":
			return "Storage"
		"guard":
			return "Guard Post"
		"farm":
			return "Farm"
		"mine":
			return "Mine"
		_:
			return "Building"


func get_effective_access_mode() -> String:
	if access_mode != "default":
		return access_mode
	match building_type:
		"home":
			return "occupied"
		"bar":
			return "public"
		"shop", "weapon_shop", "armor_shop", "travel_shop", "potion_shop":
			return "scheduled"
		"generic":
			return "public"
		_:
			return "private"


func get_access_state_label(world_minutes: int = -1) -> String:
	match get_effective_access_mode():
		"abandoned":
			return "Abandoned"
		"occupied":
			return "Private"
		"private":
			return "Private"
		"scheduled":
			return "Public" if is_public_now(world_minutes) else "Closed"
		_:
			return "Public"


func get_occupancy_label() -> String:
	var owner := get_owner_faction_name()
	if not owner.is_empty():
		return owner
	match get_effective_access_mode():
		"occupied":
			return "Occupied"
		"abandoned":
			return "None"
		_:
			return "None"


func get_hours_label(world_minutes: int = -1) -> String:
	match get_effective_access_mode():
		"public":
			return "24/7"
		"scheduled":
			if is_public_now(world_minutes):
				return "%02d:00-%02d:00" % [public_open_hour, public_close_hour]
			return "Opens %02d:00" % public_open_hour
		_:
			return ""


func is_public_now(world_minutes: int = -1) -> bool:
	var mode := get_effective_access_mode()
	if mode == "abandoned" or mode == "public":
		return true
	if mode == "occupied" or mode == "private":
		return false
	var hour := _get_world_hour(world_minutes)
	if public_open_hour == public_close_hour:
		return true
	if public_open_hour < public_close_hour:
		return hour >= public_open_hour and hour < public_close_hour
	return hour >= public_open_hour or hour < public_close_hour


func is_private_now(world_minutes: int = -1) -> bool:
	return not is_public_now(world_minutes)


func is_actor_authorized(actor: HumanoidCharacter) -> bool:
	if actor == null:
		return false
	var owner_character := get_explicit_owner_character()
	if owner_character != null:
		return actor == owner_character or (not owner_character.faction_name.is_empty() and actor.faction_name == owner_character.faction_name)
	var owner_faction := get_owner_faction_name()
	if not owner_faction.is_empty():
		return actor.faction_name == owner_faction
	var jurisdiction := get_jurisdiction_faction_name()
	return not jurisdiction.is_empty() and actor.faction_name == jurisdiction


func _get_world_hour(world_minutes: int = -1) -> int:
	if world_minutes >= 0:
		return int(floor(fposmod(float(world_minutes), 24.0 * 60.0) / 60.0))
	var world_time := _get_world_time_controller()
	return world_time.get_hour() if world_time != null else 12


func _get_world_time_controller() -> WorldTimeController:
	if _world_time != null and is_instance_valid(_world_time):
		return _world_time
	var tree := get_tree()
	if tree == null:
		return null
	var root := tree.root
	_world_time = root.find_child("WorldTimeController", true, false) as WorldTimeController if root != null else null
	return _world_time


func _process_trespass(delta: float) -> void:
	var actor_ids := _inside_actors.keys()
	for actor_id in actor_ids:
		var actor := _inside_actors.get(actor_id) as HumanoidCharacter
		if actor == null or not is_instance_valid(actor) or not is_actor_inside(actor):
			_clear_trespass_state(actor_id)
			_inside_actors.erase(actor_id)
			continue
		if not _is_actor_trespassing(actor):
			_clear_trespass_state(actor_id)
			continue
		var remaining := float(_trespass_warning_remaining.get(actor_id, 0.0)) - delta
		if remaining <= 0.0:
			_issue_trespass_response(actor)
		else:
			_trespass_warning_remaining[actor_id] = remaining


func _is_actor_trespassing(actor: HumanoidCharacter) -> bool:
	if actor == null or not actor.is_player_party_member() or actor.life_state != NpcRules.LifeState.ALIVE:
		return false
	if not is_private_now():
		return false
	return not is_actor_authorized(actor)


func _issue_trespass_response(actor: HumanoidCharacter) -> void:
	if actor == null:
		return
	var actor_id := actor.get_instance_id()
	if bool(_trespass_escalated.get(actor_id, false)):
		_trespass_warning_remaining[actor_id] = _get_trespass_warning_interval_seconds()
		return
	var warning_count := int(_trespass_warning_counts.get(actor_id, 0))
	var witness := _find_trespass_witness(actor)
	if warning_count < _get_trespass_warnings_before_alarm():
		if witness != null:
			_turn_witness_toward_actor(witness, actor)
			witness.show_world_speech("You aren't supposed to be here.", 3.0)
		else:
			actor.show_world_notice("Private property", Color(1.0, 0.78, 0.38, 1.0), 2.0)
		_trespass_warning_counts[actor_id] = warning_count + 1
		_trespass_warning_remaining[actor_id] = _get_trespass_warning_interval_seconds()
		return
	_escalate_trespass(actor, witness)


func _escalate_trespass(actor: HumanoidCharacter, witness: HumanoidCharacter = null) -> void:
	if actor == null:
		return
	var actor_id := actor.get_instance_id()
	_trespass_escalated[actor_id] = true
	_trespass_warning_remaining[actor_id] = _get_trespass_warning_interval_seconds()
	var lead_witness := witness if witness != null else _find_trespass_witness(actor)
	if lead_witness != null:
		_turn_witness_toward_actor(lead_witness, actor)
		lead_witness.show_world_speech("Guards! Trespasser!", 4.0)
	var escalation := _get_trespass_escalation()
	if escalation == "warning_only":
		return
	if escalation == "victim_only":
		var owner_character := get_explicit_owner_character()
		var responder := owner_character if owner_character != null else lead_witness
		if responder != null and responder != actor:
			responder.assign_attack_target(actor, false)
		return
	for responder in _find_trespass_responders(actor):
		if responder == null or responder == actor:
			continue
		responder.assign_attack_target(actor, false)


func _find_trespass_witness(actor: HumanoidCharacter) -> HumanoidCharacter:
	var best_witness: HumanoidCharacter = null
	var best_distance := INF
	for responder in _find_trespass_responders(actor):
		var distance := responder.global_position.distance_to(actor.global_position)
		if distance <= _get_trespass_notice_radius() and distance < best_distance:
			best_distance = distance
			best_witness = responder
	return best_witness


func get_effective_law_profile() -> Resource:
	var settlement := get_ancestor_settlement()
	if settlement == null:
		return null
	var definition = settlement.get("settlement_definition")
	if definition != null and definition.has_method("get_law_profile"):
		return definition.call("get_law_profile") as Resource
	return definition.get("law_profile") as Resource if definition != null else null


func _get_trespass_warning_interval_seconds() -> float:
	var profile := get_effective_law_profile()
	return _law_float(profile, "trespass_warning_interval_seconds", trespass_warning_interval_seconds) if use_law_profile_trespass_rules else trespass_warning_interval_seconds


func _get_trespass_warnings_before_alarm() -> int:
	var profile := get_effective_law_profile()
	return _law_int(profile, "trespass_warnings_before_alarm", trespass_warnings_before_alarm) if use_law_profile_trespass_rules else trespass_warnings_before_alarm


func _get_trespass_notice_radius() -> float:
	var profile := get_effective_law_profile()
	return _law_float(profile, "trespass_notice_radius", trespass_notice_radius) if use_law_profile_trespass_rules else trespass_notice_radius


func _get_trespass_escalation() -> String:
	var profile := get_effective_law_profile()
	return _law_string(profile, "trespass_escalation", "settlement_alarm") if use_law_profile_trespass_rules else "settlement_alarm"


func _law_float(profile: Resource, property_name: String, fallback: float) -> float:
	if profile == null:
		return fallback
	var value = profile.get(property_name)
	return fallback if value == null else float(value)


func _law_int(profile: Resource, property_name: String, fallback: int) -> int:
	if profile == null:
		return fallback
	var value = profile.get(property_name)
	return fallback if value == null else int(value)


func _law_string(profile: Resource, property_name: String, fallback: String) -> String:
	if profile == null:
		return fallback
	var value = profile.get(property_name)
	return fallback if value == null else str(value)


func _find_trespass_responders(actor: HumanoidCharacter) -> Array[HumanoidCharacter]:
	var responders: Array[HumanoidCharacter] = []
	var owner_character := get_explicit_owner_character()
	var owner_faction := get_owner_faction_name()
	var jurisdiction := get_jurisdiction_faction_name()
	var alarm_town := get_ancestor_settlement()
	for node in get_tree().get_nodes_in_group("npc_character"):
		if not (node is HumanoidCharacter):
			continue
		var humanoid := node as HumanoidCharacter
		if humanoid == actor or humanoid.life_state != NpcRules.LifeState.ALIVE or humanoid.player_party_member:
			continue
		if owner_character != null:
			if humanoid == owner_character or humanoid.faction_name == owner_character.faction_name:
				responders.append(humanoid)
		elif not owner_faction.is_empty():
			if humanoid.faction_name == owner_faction:
				responders.append(humanoid)
		elif not jurisdiction.is_empty():
			if humanoid.faction_name == jurisdiction or (alarm_town != null and _is_node_descendant_of(humanoid, alarm_town)):
				responders.append(humanoid)
	return responders


func _turn_witness_toward_actor(witness: HumanoidCharacter, actor: HumanoidCharacter) -> void:
	if witness == null or actor == null:
		return
	var target_position := Vector3(actor.global_position.x, witness.global_position.y, actor.global_position.z)
	if witness.global_position.distance_squared_to(target_position) <= 0.001:
		return
	witness.look_at(target_position, Vector3.UP)
	witness.rotation.x = 0.0
	witness.rotation.z = 0.0


func _is_node_descendant_of(node: Node, ancestor: Node) -> bool:
	var current := node
	while current != null:
		if current == ancestor:
			return true
		current = current.get_parent()
	return false


func _remember_inside_actor(actor: HumanoidCharacter) -> void:
	if actor != null:
		_inside_actors[actor.get_instance_id()] = actor


func _forget_inside_actor(actor: HumanoidCharacter) -> void:
	if actor == null:
		return
	var actor_id := actor.get_instance_id()
	_inside_actors.erase(actor_id)
	_clear_trespass_state(actor_id)


func _clear_trespass_state(actor_id: int) -> void:
	_trespass_warning_remaining.erase(actor_id)
	_trespass_warning_counts.erase(actor_id)
	_trespass_escalated.erase(actor_id)


func get_population_capacity_record(settlement_id := "") -> Dictionary:
	return {
		"capacity_id": get_population_capacity_id(),
		"settlement_id": settlement_id,
		"display_name": display_name if not display_name.is_empty() else get_population_capacity_id().capitalize(),
		"source_type": "building",
		"world_position": global_position,
		"population_capacity": max(0, population_capacity),
	}


func _refresh_occluders() -> void:
	_apply_occluder_visibility(roof_occluder_paths, _roof_hidden)
	_apply_occluder_visibility(front_occluder_paths, _hidden_side == "front")
	_apply_occluder_visibility(right_occluder_paths, _hidden_side == "right")
	_apply_occluder_visibility(back_occluder_paths, _hidden_side == "back")
	_apply_occluder_visibility(left_occluder_paths, _hidden_side == "left")


func _apply_occluder_visibility(paths: Array[NodePath], hidden: bool) -> void:
	for node_path in paths:
		var node := get_node_or_null(node_path)
		if node is Node3D:
			node.visible = not hidden


func is_hidden_occluder_shape(shape_index: int) -> bool:
	if shape_index < 0:
		return false
	var owner_id := shape_find_owner(shape_index)
	if owner_id < 0:
		return false
	var owner_node := shape_owner_get_owner(owner_id)
	if not (owner_node is CollisionShape3D):
		return false
	var node_path := get_path_to(owner_node)
	if not levels.is_empty():
		if _active_level_index < 0 or _active_level_index >= levels.size():
			return false
		var level: BuildingLevelDefinition = levels[_active_level_index]
		if level == null:
			return false
		return (
			(_hidden_side == "front" and level.front_occluder_paths.has(node_path))
			or (_hidden_side == "right" and level.right_occluder_paths.has(node_path))
			or (_hidden_side == "back" and level.back_occluder_paths.has(node_path))
			or (_hidden_side == "left" and level.left_occluder_paths.has(node_path))
		)
	return (
		(_roof_hidden and roof_occluder_paths.has(node_path))
		or (_hidden_side == "front" and front_occluder_paths.has(node_path))
		or (_hidden_side == "right" and right_occluder_paths.has(node_path))
		or (_hidden_side == "back" and back_occluder_paths.has(node_path))
		or (_hidden_side == "left" and left_occluder_paths.has(node_path))
	)


func should_project_click_shape(shape_index: int) -> bool:
	if shape_index < 0:
		return false
	if is_hidden_occluder_shape(shape_index):
		return true
	if _active_level_index < 0:
		return false
	var owner_id := shape_find_owner(shape_index)
	if owner_id < 0:
		return false
	var owner_node := shape_owner_get_owner(owner_id)
	if not (owner_node is CollisionShape3D):
		return false
	var node_path := get_path_to(owner_node)
	for level_index in range(levels.size()):
		if level_index == _active_level_index:
			continue
		var level: BuildingLevelDefinition = levels[level_index]
		if level == null:
			continue
		if _level_has_content_path(level_index, level, node_path):
			return true
		if level.front_occluder_paths.has(node_path) or level.right_occluder_paths.has(node_path) or level.back_occluder_paths.has(node_path) or level.left_occluder_paths.has(node_path):
			return true
	return false


func _get_interior_area() -> Area3D:
	return get_node_or_null(interior_area_path) as Area3D


func get_level_index_for_actor(actor: HumanoidCharacter) -> int:
	if actor == null:
		return -1
	var actor_id := actor.get_instance_id()
	var local_y := to_local(actor.global_position).y
	for level_index in range(_level_actor_ids.size() - 1, -1, -1):
		if not _level_actor_ids[level_index].has(actor_id):
			continue
		var level: BuildingLevelDefinition = levels[level_index]
		if level == null:
			continue
		if local_y >= level.min_local_y and local_y < level.max_local_y:
			return level_index
	for level_index in range(_level_actor_ids.size() - 1, -1, -1):
		if _level_actor_ids[level_index].has(actor_id):
			return level_index
	return -1


func is_roof_level(level_index: int) -> bool:
	if level_index < 0 or level_index >= levels.size():
		return false
	var level: BuildingLevelDefinition = levels[level_index]
	return level != null and level.is_roof


func _get_camera_facing_side(camera_world_position: Vector3) -> String:
	var local_camera_position := to_local(camera_world_position)
	var abs_x := absf(local_camera_position.x)
	var abs_z := absf(local_camera_position.z)
	if _hidden_side == "right" or _hidden_side == "left":
		if abs_z + SIDE_SWITCH_HYSTERESIS < abs_x:
			return "right" if local_camera_position.x > 0.0 else "left"
	elif _hidden_side == "front" or _hidden_side == "back":
		if abs_x + SIDE_SWITCH_HYSTERESIS < abs_z:
			return "front" if local_camera_position.z > 0.0 else "back"
	if abs_x > abs_z:
		return "right" if local_camera_position.x > 0.0 else "left"
	return "front" if local_camera_position.z > 0.0 else "back"


func _refresh_level_visibility(show_interior: bool, camera_world_position: Vector3, actor: HumanoidCharacter) -> void:
	var next_level_index := -1
	var next_hidden_side := ""
	if show_interior:
		next_level_index = get_level_index_for_actor(actor)
		if next_level_index >= 0 and not is_roof_level(next_level_index):
			next_hidden_side = _get_camera_facing_side(camera_world_position)
	if _active_level_index == next_level_index and _hidden_side == next_hidden_side:
		return
	_active_level_index = next_level_index
	_hidden_side = next_hidden_side
	if _active_level_index < 0:
		for level_index in range(levels.size()):
			_apply_level_visibility(level_index, true, false)
		return
	for level_index in range(levels.size()):
		_apply_level_visibility(level_index, level_index <= _active_level_index, level_index == _active_level_index)


func _apply_level_visibility(level_index: int, visible: bool, active: bool = true) -> void:
	if level_index < 0 or level_index >= levels.size():
		return
	var level: BuildingLevelDefinition = levels[level_index]
	if level == null:
		return
	for node_path in level.content_paths:
		_apply_node_visibility(get_node_or_null(node_path), visible)
	_apply_extra_level_visibility(level_index, visible)
	_apply_occluder_visibility(level.front_occluder_paths, not visible or (active and _hidden_side == "front"))
	_apply_occluder_visibility(level.right_occluder_paths, not visible or (active and _hidden_side == "right"))
	_apply_occluder_visibility(level.back_occluder_paths, not visible or (active and _hidden_side == "back"))
	_apply_occluder_visibility(level.left_occluder_paths, not visible or (active and _hidden_side == "left"))


func _apply_registered_level_visibility(level_index: int) -> void:
	var visible := true
	if _active_level_index >= 0:
		visible = level_index <= _active_level_index
	_apply_extra_level_visibility(level_index, visible)


func _apply_extra_level_visibility(level_index: int, visible: bool) -> void:
	for node_path in _extra_level_content_paths.get(level_index, []):
		_apply_node_visibility(get_node_or_null(node_path), visible)


func _apply_node_visibility(node: Node, visible: bool) -> void:
	if node == null:
		return
	if node is Node3D:
		node.visible = visible
	for child in node.get_children():
		_apply_node_visibility(child, visible)


func _get_level_area(level_index: int) -> Area3D:
	if not _is_valid_level_index(level_index):
		return null
	var level: BuildingLevelDefinition = levels[level_index]
	if level == null:
		return null
	return get_node_or_null(level.occupancy_area_path) as Area3D


func _level_has_content_path(level_index: int, level: BuildingLevelDefinition, node_path: NodePath) -> bool:
	for content_path in level.content_paths:
		if _node_path_is_or_descendant(node_path, content_path):
			return true
	for content_path in _extra_level_content_paths.get(level_index, []):
		if _node_path_is_or_descendant(node_path, content_path):
			return true
	return false


func _node_path_is_or_descendant(node_path: NodePath, ancestor_path: NodePath) -> bool:
	if node_path == ancestor_path:
		return true
	var node_path_text := str(node_path)
	var ancestor_path_text := str(ancestor_path)
	return not ancestor_path_text.is_empty() and node_path_text.begins_with("%s/" % ancestor_path_text)


func _is_valid_level_index(level_index: int) -> bool:
	return level_index >= 0 and level_index < levels.size()


func project_click_to_active_level(ray_origin: Vector3, ray_direction: Vector3) -> Variant:
	if levels.is_empty():
		if not _roof_hidden and _hidden_side.is_empty():
			return null
		return _project_click_to_local_y(ray_origin, ray_direction, click_local_y)
	if _active_level_index < 0 or _active_level_index >= levels.size():
		return null
	var level: BuildingLevelDefinition = levels[_active_level_index]
	if level == null:
		return null
	return _project_click_to_local_y(ray_origin, ray_direction, level.click_local_y)


func _project_click_to_local_y(ray_origin: Vector3, ray_direction: Vector3, local_y: float) -> Variant:
	var plane_point := to_global(Vector3(0.0, local_y, 0.0))
	var plane := Plane(global_transform.basis.y.normalized(), plane_point)
	var hit: Variant = plane.intersects_ray(ray_origin, ray_direction)
	return hit


func _on_interior_body_entered(body: Node) -> void:
	if body is HumanoidCharacter:
		_remember_inside_actor(body as HumanoidCharacter)
		_interior_actor_ids[body.get_instance_id()] = true


func _on_interior_body_exited(body: Node) -> void:
	if body is HumanoidCharacter:
		_forget_inside_actor(body as HumanoidCharacter)
		_interior_actor_ids.erase(body.get_instance_id())


func _on_level_body_entered(body: Node, level_index: int) -> void:
	if body is HumanoidCharacter and level_index >= 0 and level_index < _level_actor_ids.size():
		_remember_inside_actor(body as HumanoidCharacter)
		_level_actor_ids[level_index][body.get_instance_id()] = true


func _on_level_body_exited(body: Node, level_index: int) -> void:
	if body is HumanoidCharacter and level_index >= 0 and level_index < _level_actor_ids.size():
		_level_actor_ids[level_index].erase(body.get_instance_id())
		if not is_actor_inside(body as HumanoidCharacter):
			_forget_inside_actor(body as HumanoidCharacter)
