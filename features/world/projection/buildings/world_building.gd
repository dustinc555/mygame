@tool
@icon("res://addons/world_authoring/icons/world_building.svg")
extends Node3D

class_name WorldBuilding

const MODULAR_BUILDING_PIECE_SCRIPT := preload("res://features/world/projection/buildings/modular_building_piece.gd")

@export var display_name := "Building"
## Intentional raise above the terrain (foundation on uneven ground). Ground
## snap at load re-solves the terrain Y, then adds this back on top.
@export var foundation_height := 0.0
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
@export var modular_pieces_root_path := NodePath("Pieces")
## See-through corridor between camera and the followed actor: pieces inside
## it turn SHADOWS_ONLY (camera loses them; light/physics/nav keep them).
@export_range(0.5, 12.0, 0.1) var see_through_camera_radius_meters := 4.5
@export_range(0.25, 8.0, 0.1) var see_through_actor_radius_meters := 2.2
## The corridor stops this far short of the actor so their backdrop stays.
@export_range(0.0, 4.0, 0.1) var see_through_focus_pull_back_meters := 1.5

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
var _hidden_modular_piece_instance_ids: Dictionary = {}
var _modular_piece_cache: Array = []
var _modular_piece_cache_dirty := true
var _modular_floor_footprints: Array = []
var _modular_bounds_dirty := true
var _watched_modular_pieces_root: Node
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


func is_actor_inside(actor: WorldActor) -> bool:
	if actor == null:
		return false
	if not levels.is_empty():
		return get_level_index_for_actor(actor) >= 0
	if _interior_actor_ids.has(actor.get_instance_id()) or _is_actor_inside_area(actor, _get_interior_area()):
		return true
	return _is_actor_inside_modular_bounds(actor)


## Modular buildings need no authored interior Area3D: you are inside when
## you stand over an actual interior floor piece. Merged boxes are wrong —
## an L-shaped house's front notch, the porch steps, and the strip along the
## outside of a wall are all outdoors.
func _is_actor_inside_modular_bounds(actor: WorldActor) -> bool:
	var footprints := _get_modular_floor_footprints()
	if footprints.is_empty():
		return false
	for probe_position in _actor_visibility_probe_positions(actor):
		for footprint in footprints:
			var local_probe: Vector3 = footprint["from_world"] * probe_position
			var half: Vector2 = footprint["half_extents"]
			if absf(local_probe.x) <= half.x and absf(local_probe.z) <= half.y \
					and local_probe.y >= -0.6 and local_probe.y <= 2.6:
				return true
	return false


func _get_modular_floor_footprints() -> Array:
	if not _modular_bounds_dirty:
		return _modular_floor_footprints
	_modular_floor_footprints.clear()
	for piece in get_modular_pieces():
		if not (piece is Node3D) or str(piece.get("category")) != "floor":
			continue
		var size := _modular_piece_bounds_size(piece)
		_modular_floor_footprints.append({
			"from_world": (piece as Node3D).global_transform.affine_inverse(),
			"half_extents": Vector2(size.x * 0.5, size.z * 0.5),
		})
	_modular_bounds_dirty = false
	return _modular_floor_footprints


func set_visibility_for_camera(show_interior: bool, camera_world_position: Vector3, actor: WorldActor = null, camera_focused := false) -> void:
	# Modular see-through only opens for the camera-followed (double-clicked)
	# actor, matching the demo-building focus pattern — selection alone never
	# hides modular pieces.
	var focus_position: Variant = null
	if show_interior and camera_focused and actor != null and is_instance_valid(actor) and actor.is_inside_tree():
		focus_position = actor.global_position
	if not levels.is_empty():
		_refresh_level_visibility(show_interior, camera_world_position, actor)
		_refresh_modular_piece_visibility(show_interior, camera_world_position, _active_level_index, focus_position)
		return
	var next_roof_hidden := show_interior
	var next_hidden_side := ""
	if show_interior:
		next_hidden_side = _get_camera_facing_side(camera_world_position)
	if _roof_hidden == next_roof_hidden and _hidden_side == next_hidden_side:
		_refresh_modular_piece_visibility(show_interior, camera_world_position, -1, focus_position)
		return
	_roof_hidden = next_roof_hidden
	_hidden_side = next_hidden_side
	_refresh_occluders()
	_refresh_modular_piece_visibility(show_interior, camera_world_position, -1, focus_position)


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
	return population_capacity_id if not population_capacity_id.is_empty() else str(name)


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


func get_access_state_label_for_actor(actor: WorldActor, world_minutes: int = -1) -> String:
	return "Restricted" if is_actor_trespassing_now(actor, world_minutes) else get_access_state_label(world_minutes)


func get_occupancy_label() -> String:
	var owner_faction := get_owner_faction_name()
	if not owner_faction.is_empty():
		return owner_faction
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


func is_actor_trespassing_now(actor: WorldActor, world_minutes: int = -1) -> bool:
	if actor == null or not actor.is_player_party_member() or actor.life_state != NpcRules.LifeState.ALIVE:
		return false
	if not is_private_now(world_minutes):
		return false
	return not is_actor_authorized(actor)


func is_actor_authorized(actor: WorldActor) -> bool:
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
	_world_time = BootstrapContext.service(WorldTimeController.SERVICE_ID) as WorldTimeController
	return _world_time


func _get_law_order_controller() -> Node:
	var tree := get_tree()
	if tree == null:
		return null
	for node in tree.get_nodes_in_group("law_order_controller"):
		return node
	return null


func _process_trespass(delta: float) -> void:
	var actor_ids := _inside_actors.keys()
	for actor_id in actor_ids:
		# Check validity on the raw value BEFORE casting — a tracked actor may have been
		# freed by LOD derealization, and casting a freed object crashes.
		var raw = _inside_actors.get(actor_id)
		if raw == null or not is_instance_valid(raw):
			_clear_trespass_state(actor_id)
			_inside_actors.erase(actor_id)
			continue
		var actor := raw as WorldActor
		if actor == null or not is_actor_inside(actor):
			if actor != null:
				_clear_active_trespass_meta(actor)
			_clear_trespass_state(actor_id)
			_inside_actors.erase(actor_id)
			continue
		if not _is_actor_trespassing(actor):
			_clear_active_trespass_meta(actor)
			_clear_trespass_state(actor_id)
			continue
		_set_active_trespass_meta(actor)
		var remaining := float(_trespass_warning_remaining.get(actor_id, 0.0)) - delta
		if remaining <= 0.0:
			_issue_trespass_response(actor)
		else:
			_trespass_warning_remaining[actor_id] = remaining


func _is_actor_trespassing(actor: WorldActor) -> bool:
	return is_actor_trespassing_now(actor)


func _issue_trespass_response(actor: WorldActor) -> void:
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


func _escalate_trespass(actor: WorldActor, witness: HumanoidCharacter = null) -> void:
	if actor == null:
		return
	var actor_id := actor.get_instance_id()
	_trespass_escalated[actor_id] = true
	_trespass_warning_remaining[actor_id] = _get_trespass_warning_interval_seconds()
	var lead_witness := witness if witness != null else _find_trespass_witness(actor)
	if lead_witness != null:
		_turn_witness_toward_actor(lead_witness, actor)
		lead_witness.show_world_speech("Guards! Trespasser!", 4.0)
	var law_controller := _get_law_order_controller()
	if law_controller != null and law_controller.has_method("report_trespass"):
		law_controller.call("report_trespass", actor, self, lead_witness)
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


func _find_trespass_witness(actor: WorldActor) -> HumanoidCharacter:
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


func _find_trespass_responders(actor: WorldActor) -> Array[HumanoidCharacter]:
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
			if humanoid.has_method("is_settlement_authority") and bool(humanoid.call("is_settlement_authority")) and (humanoid.faction_name == jurisdiction or (alarm_town != null and _is_node_descendant_of(humanoid, alarm_town))):
				responders.append(humanoid)
	return responders


func _turn_witness_toward_actor(witness: HumanoidCharacter, actor: WorldActor) -> void:
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


func _remember_inside_actor(actor: WorldActor) -> void:
	if actor != null:
		_inside_actors[actor.get_instance_id()] = actor


func _forget_inside_actor(actor: WorldActor) -> void:
	if actor == null:
		return
	var actor_id := actor.get_instance_id()
	_clear_active_trespass_meta(actor)
	_inside_actors.erase(actor_id)
	_clear_trespass_state(actor_id)


func _set_active_trespass_meta(actor: WorldActor) -> void:
	if actor == null:
		return
	var status := actor.get_legal_status()
	status.active_crime_label = "Committing a crime! (Trespassing)"
	status.active_crime_kind = "active"
	status.active_crime_source_id = get_instance_id()


func _clear_active_trespass_meta(actor: WorldActor) -> void:
	if actor == null:
		return
	var status := actor.get_legal_status()
	if status.active_crime_source_id != get_instance_id():
		return
	status.clear_active_crime()


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


func get_or_create_modular_pieces_root() -> Node3D:
	var pieces_root := get_node_or_null(modular_pieces_root_path) as Node3D
	if pieces_root != null:
		_watch_modular_pieces_root(pieces_root)
		return pieces_root
	pieces_root = Node3D.new()
	pieces_root.name = "Pieces"
	add_child(pieces_root)
	if Engine.is_editor_hint():
		pieces_root.owner = owner if owner != null else self
	elif owner != null:
		pieces_root.owner = owner
	_watch_modular_pieces_root(pieces_root)
	return pieces_root


func get_modular_pieces_root() -> Node3D:
	var pieces_root := get_node_or_null(modular_pieces_root_path) as Node3D
	if pieces_root != null:
		_watch_modular_pieces_root(pieces_root)
	return pieces_root


func get_modular_pieces() -> Array:
	var pieces_root := get_modular_pieces_root()
	if pieces_root == null:
		_modular_piece_cache.clear()
		_modular_piece_cache_dirty = true
		return []
	if _modular_piece_cache_dirty:
		_modular_piece_cache.clear()
		_collect_modular_pieces(pieces_root, _modular_piece_cache)
		_modular_piece_cache_dirty = false
	return _modular_piece_cache


func invalidate_modular_piece_cache() -> void:
	_modular_piece_cache_dirty = true
	_modular_bounds_dirty = true


func is_modular_piece_hidden(piece: Node) -> bool:
	return piece != null and _hidden_modular_piece_instance_ids.has(piece.get_instance_id())


func get_modular_piece_for_node(node: Node) -> Node:
	var current := node
	while current != null and current != self:
		if current.get_script() == MODULAR_BUILDING_PIECE_SCRIPT:
			return current
		current = current.get_parent()
	return null


func should_skip_modular_collider(collider: Object) -> bool:
	if not (collider is Node):
		return false
	var piece := get_modular_piece_for_node(collider as Node)
	return piece != null and is_modular_piece_hidden(piece)


func _refresh_modular_piece_visibility(show_interior: bool, camera_world_position: Vector3, active_level_index: int, focus_position: Variant = null) -> void:
	_hidden_modular_piece_instance_ids.clear()
	for piece in get_modular_pieces():
		var hidden := _should_hide_modular_piece(piece, show_interior, camera_world_position, active_level_index, focus_position)
		_set_modular_piece_hidden(piece, hidden)


## Hidden pieces stay in the world for everything except the camera: their
## meshes flip to SHADOWS_ONLY (light still blocked), collision and nav are
## untouched, and click picking skips them via the hidden set. Only state
## transitions touch the meshes; steady state costs nothing.
func _set_modular_piece_hidden(piece: Node, hidden: bool) -> void:
	var was_hidden := bool(piece.get_meta("world_building_hidden_by_camera", false))
	if hidden != was_hidden:
		if piece is Node3D:
			(piece as Node3D).visible = true
		_apply_piece_shadow_only(piece, hidden)
	piece.set_meta("world_building_hidden_by_camera", hidden)
	if hidden:
		_hidden_modular_piece_instance_ids[piece.get_instance_id()] = true


func _apply_piece_shadow_only(node: Node, hidden: bool) -> void:
	if node is GeometryInstance3D:
		var geometry := node as GeometryInstance3D
		if hidden:
			if not geometry.has_meta("world_building_cast_shadow_restore"):
				geometry.set_meta("world_building_cast_shadow_restore", int(geometry.cast_shadow))
			geometry.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
		elif geometry.has_meta("world_building_cast_shadow_restore"):
			geometry.cast_shadow = int(geometry.get_meta("world_building_cast_shadow_restore")) as GeometryInstance3D.ShadowCastingSetting
			geometry.remove_meta("world_building_cast_shadow_restore")
	for child in node.get_children():
		_apply_piece_shadow_only(child, hidden)


func _should_hide_modular_piece(piece: Node, show_interior: bool, camera_world_position: Vector3, active_level_index: int, focus_position: Variant = null) -> bool:
	if piece == null or not show_interior:
		return false
	if piece.has_method("should_hide_with_camera") and not bool(piece.call("should_hide_with_camera")):
		return false
	var piece_level := _get_modular_piece_level(piece)
	if active_level_index >= 0:
		if piece_level > active_level_index:
			return true
		if piece_level < active_level_index:
			return false
	# Modular pieces hide only for the camera-followed actor, following the
	# demo-building pattern: levels above the actor vanish wholesale, the
	# actor's own level only loses walls inside the camera corridor, and
	# floors/stairs/roofs at or below the actor never hide.
	if focus_position == null:
		return false
	if _get_modular_piece_occluder_side(piece) == "none":
		return false
	if not (piece is Node3D):
		return false
	var piece_base_y := to_local((piece as Node3D).global_position).y
	var actor_level_y := to_local(focus_position).y
	if piece_base_y > actor_level_y + 1.5:
		return true
	if not _is_modular_side_piece(piece):
		return false
	if _is_piece_actor_standing_surface(piece, focus_position):
		return false
	return _is_modular_piece_in_view_corridor(piece, camera_world_position, focus_position)


func _is_modular_side_piece(piece: Node) -> bool:
	var category := str(piece.get("category"))
	return category == "wall" or category == "wall_door" or category == "wall_window" or category == "window" or category == "door" or category == "corner"


## Never hide what the actor is standing on or anything at/below their feet:
## the floor under them, the stairs they are climbing, the roof deck they
## stand on. Feet = actor origin (capsule sits above it).
func _is_piece_actor_standing_surface(piece: Node, feet_position: Vector3) -> bool:
	if not (piece is Node3D):
		return false
	var node := piece as Node3D
	var size := _modular_piece_bounds_size(piece)
	# Whole piece sits at or below the feet level (floors of their level and
	# everything under it).
	if node.global_position.y + size.y <= feet_position.y + 0.35:
		return true
	# The piece's own volume holds their feet (stairs mid-flight, thick decks).
	var local_feet := node.global_transform.affine_inverse() * feet_position
	var margin := 0.5
	return absf(local_feet.x) <= size.x * 0.5 + margin \
		and local_feet.y >= -margin and local_feet.y <= size.y + margin \
		and absf(local_feet.z) <= size.z * 0.5 + margin


## Capsule test against the camera -> actor sight line. The corridor tapers
## toward the actor and stops short of them so their backdrop stays visible.
func _is_modular_piece_in_view_corridor(piece: Node, camera_world_position: Vector3, focus_position: Vector3) -> bool:
	if not (piece is Node3D):
		return false
	var node := piece as Node3D
	var size := _modular_piece_bounds_size(piece)
	var center := node.global_position + node.global_transform.basis.y * (size.y * 0.5)
	var piece_radius := (size * 0.5).length()
	var sight := focus_position - camera_world_position
	var sight_length := sight.length()
	if sight_length <= 0.01:
		return false
	var pulled_length := maxf(sight_length - see_through_focus_pull_back_meters, 0.1)
	var segment := sight * (pulled_length / sight_length)
	# Only pieces whose entire volume ends strictly in front of the actor can
	# block the view. Project the piece's oriented box onto the sight axis:
	# a wall at the actor's depth (the divider they stand before, and its
	# neighbors) reaches their depth and must stay solid.
	var direction := sight / sight_length
	var piece_basis := node.global_transform.basis
	var depth_extent := absf(direction.dot(piece_basis.x)) * size.x * 0.5 \
		+ absf(direction.dot(piece_basis.y)) * size.y * 0.5 \
		+ absf(direction.dot(piece_basis.z)) * size.z * 0.5
	var center_depth := direction.dot(center - camera_world_position)
	if center_depth + depth_extent >= pulled_length:
		return false
	var t := clampf((center - camera_world_position).dot(segment) / segment.length_squared(), 0.0, 1.0)
	var closest := camera_world_position + segment * t
	var corridor_radius := lerpf(see_through_camera_radius_meters, see_through_actor_radius_meters, t)
	return center.distance_to(closest) <= corridor_radius + piece_radius


func _modular_piece_bounds_size(piece: Node) -> Vector3:
	var bounds: Variant = piece.get("bounds_size_meters")
	if bounds is Vector3 and (bounds as Vector3).length_squared() > 0.01:
		return bounds as Vector3
	return Vector3(2.0, 3.0, 2.0)


func _get_modular_piece_level(piece: Node) -> int:
	if piece.has_method("get_building_level"):
		return max(0, int(piece.call("get_building_level")))
	return max(0, int(piece.get("building_level"))) if piece.get("building_level") != null else 0


func _get_modular_piece_occluder_side(piece: Node) -> String:
	if piece.has_method("get_occluder_side"):
		return str(piece.call("get_occluder_side"))
	var side = piece.get("occluder_side")
	return str(side) if side != null else "auto"


func _collect_modular_pieces(node: Node, result: Array) -> void:
	if node.get_script() == MODULAR_BUILDING_PIECE_SCRIPT:
		result.append(node)
	for child in node.get_children():
		_collect_modular_pieces(child, result)


func _watch_modular_pieces_root(pieces_root: Node) -> void:
	if _watched_modular_pieces_root == pieces_root:
		return
	if _watched_modular_pieces_root != null and is_instance_valid(_watched_modular_pieces_root):
		if _watched_modular_pieces_root.child_entered_tree.is_connected(_on_modular_pieces_root_child_changed):
			_watched_modular_pieces_root.child_entered_tree.disconnect(_on_modular_pieces_root_child_changed)
		if _watched_modular_pieces_root.child_exiting_tree.is_connected(_on_modular_pieces_root_child_changed):
			_watched_modular_pieces_root.child_exiting_tree.disconnect(_on_modular_pieces_root_child_changed)
	_watched_modular_pieces_root = pieces_root
	_modular_piece_cache_dirty = true
	if _watched_modular_pieces_root == null:
		return
	if not _watched_modular_pieces_root.child_entered_tree.is_connected(_on_modular_pieces_root_child_changed):
		_watched_modular_pieces_root.child_entered_tree.connect(_on_modular_pieces_root_child_changed)
	if not _watched_modular_pieces_root.child_exiting_tree.is_connected(_on_modular_pieces_root_child_changed):
		_watched_modular_pieces_root.child_exiting_tree.connect(_on_modular_pieces_root_child_changed)


func _on_modular_pieces_root_child_changed(_child: Node) -> void:
	invalidate_modular_piece_cache()


func is_hidden_occluder_shape(shape_index: int) -> bool:
	var owner_node := _get_collision_shape_owner(shape_index)
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
	if is_hidden_occluder_shape(shape_index):
		return true
	if _active_level_index < 0:
		return false
	var owner_node := _get_collision_shape_owner(shape_index)
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


func _get_collision_shape_owner(shape_index: int) -> Node:
	if shape_index < 0:
		return null
	if not has_method("shape_find_owner") or not has_method("shape_owner_get_owner"):
		return null
	var owner_id := int(call("shape_find_owner", shape_index))
	if owner_id < 0:
		return null
	return call("shape_owner_get_owner", owner_id) as Node


func _get_interior_area() -> Area3D:
	return get_node_or_null(interior_area_path) as Area3D


func get_level_index_for_actor(actor: WorldActor) -> int:
	if actor == null or not actor.is_inside_tree():
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
	for level_index in range(levels.size() - 1, -1, -1):
		if _is_actor_inside_level_area(actor, level_index):
			return level_index
	return -1


func _is_actor_inside_level_area(actor: WorldActor, level_index: int) -> bool:
	if actor == null or not _is_valid_level_index(level_index):
		return false
	var level: BuildingLevelDefinition = levels[level_index]
	if level == null:
		return false
	var area := _get_level_area(level_index)
	if area == null:
		return false
	for probe_position in _actor_visibility_probe_positions(actor):
		var local_y := to_local(probe_position).y
		if local_y >= level.min_local_y and local_y < level.max_local_y and _area_contains_world_position(area, probe_position):
			return true
	return false


func _is_actor_inside_area(actor: WorldActor, area: Area3D) -> bool:
	if actor == null or area == null:
		return false
	for probe_position in _actor_visibility_probe_positions(actor):
		if _area_contains_world_position(area, probe_position):
			return true
	return false


func _actor_visibility_probe_positions(actor: WorldActor) -> Array[Vector3]:
	var positions: Array[Vector3] = []
	if actor == null or not actor.is_inside_tree():
		return positions
	positions.append(actor.global_position)
	var collision_shape := actor.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if collision_shape != null and collision_shape.is_inside_tree() and collision_shape.shape != null:
		var bounds := _shape_local_bounds(collision_shape.shape)
		if bounds.size.length_squared() > 0.0:
			var center := bounds.position + bounds.size * 0.5
			positions.append(collision_shape.global_transform * center)
			positions.append(collision_shape.global_transform * Vector3(center.x, bounds.position.y, center.z))
			positions.append(collision_shape.global_transform * Vector3(center.x, bounds.position.y + bounds.size.y, center.z))
			return positions
	positions.append(actor.global_position + Vector3(0.0, 0.6, 0.0))
	positions.append(actor.global_position + Vector3(0.0, 1.2, 0.0))
	return positions


func _area_contains_world_position(area: Area3D, world_position: Vector3) -> bool:
	if area == null or not area.is_inside_tree():
		return false
	for child in area.get_children():
		var collision_shape := child as CollisionShape3D
		if collision_shape == null or not collision_shape.is_inside_tree() or collision_shape.disabled or collision_shape.shape == null:
			continue
		if _shape_contains_local_position(collision_shape.shape, collision_shape.global_transform.affine_inverse() * world_position):
			return true
	return false


func _shape_contains_local_position(shape: Shape3D, local_position: Vector3) -> bool:
	if shape is BoxShape3D:
		var half_size := (shape as BoxShape3D).size * 0.5
		return absf(local_position.x) <= half_size.x and absf(local_position.y) <= half_size.y and absf(local_position.z) <= half_size.z
	if shape is SphereShape3D:
		return local_position.length_squared() <= pow((shape as SphereShape3D).radius, 2.0)
	if shape is CapsuleShape3D:
		var capsule := shape as CapsuleShape3D
		var half_height := maxf(0.0, capsule.height * 0.5 - capsule.radius)
		var clamped_y := clampf(local_position.y, -half_height, half_height)
		return Vector3(local_position.x, local_position.y - clamped_y, local_position.z).length_squared() <= capsule.radius * capsule.radius
	return _shape_local_bounds(shape).has_point(local_position)


func _shape_local_bounds(shape: Shape3D) -> AABB:
	if shape is BoxShape3D:
		var size := (shape as BoxShape3D).size
		return AABB(-size * 0.5, size)
	if shape is SphereShape3D:
		var radius := (shape as SphereShape3D).radius
		return AABB(Vector3.ONE * -radius, Vector3.ONE * radius * 2.0)
	if shape is CapsuleShape3D:
		var capsule := shape as CapsuleShape3D
		var radius := capsule.radius
		return AABB(Vector3(-radius, -capsule.height * 0.5, -radius), Vector3(radius * 2.0, capsule.height, radius * 2.0))
	return AABB()


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


func _refresh_level_visibility(show_interior: bool, camera_world_position: Vector3, actor: WorldActor) -> void:
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


func _apply_level_visibility(level_index: int, visible_flag: bool, active: bool = true) -> void:
	if level_index < 0 or level_index >= levels.size():
		return
	var level: BuildingLevelDefinition = levels[level_index]
	if level == null:
		return
	for node_path in level.content_paths:
		_apply_node_visibility(get_node_or_null(node_path), visible_flag)
	_apply_extra_level_visibility(level_index, visible_flag)
	_apply_occluder_visibility(level.front_occluder_paths, not visible_flag or (active and _hidden_side == "front"))
	_apply_occluder_visibility(level.right_occluder_paths, not visible_flag or (active and _hidden_side == "right"))
	_apply_occluder_visibility(level.back_occluder_paths, not visible_flag or (active and _hidden_side == "back"))
	_apply_occluder_visibility(level.left_occluder_paths, not visible_flag or (active and _hidden_side == "left"))


func _apply_registered_level_visibility(level_index: int) -> void:
	var visible_flag := true
	if _active_level_index >= 0:
		visible_flag = level_index <= _active_level_index
	_apply_extra_level_visibility(level_index, visible_flag)


func _apply_extra_level_visibility(level_index: int, visible_flag: bool) -> void:
	for node_path in _extra_level_content_paths.get(level_index, []):
		_apply_node_visibility(get_node_or_null(node_path), visible_flag)


func _apply_node_visibility(node: Node, visible_flag: bool) -> void:
	if node == null:
		return
	if node is Node3D:
		node.visible = visible_flag
	for child in node.get_children():
		_apply_node_visibility(child, visible_flag)


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
	if body is WorldActor:
		_remember_inside_actor(body as WorldActor)
		_interior_actor_ids[body.get_instance_id()] = true


func _on_interior_body_exited(body: Node) -> void:
	if body is WorldActor:
		_forget_inside_actor(body as WorldActor)
		_interior_actor_ids.erase(body.get_instance_id())


func _on_level_body_entered(body: Node, level_index: int) -> void:
	if body is WorldActor and level_index >= 0 and level_index < _level_actor_ids.size():
		_remember_inside_actor(body as WorldActor)
		_level_actor_ids[level_index][body.get_instance_id()] = true


func _on_level_body_exited(body: Node, level_index: int) -> void:
	if body is WorldActor and level_index >= 0 and level_index < _level_actor_ids.size():
		_level_actor_ids[level_index].erase(body.get_instance_id())
		if not is_actor_inside(body as WorldActor):
			_forget_inside_actor(body as WorldActor)
