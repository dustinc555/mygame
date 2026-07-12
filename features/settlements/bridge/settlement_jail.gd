@tool
@icon("res://addons/world_authoring/icons/facility_jail.svg")
extends "res://features/settlements/bridge/settlement_facility_instance.gd"

class_name SettlementJail

const JAIL_FUNCTION = preload("res://features/world_sim/resources/facility_functions/jail.tres")
const DEFAULT_BUILDING_SCENE = preload("res://features/world/projection/buildings/deprecated/initial_buildings/settlement_keep_building.tscn")
const FACTION_HUMANOID_SCRIPT = preload("res://features/actors/projection/humanoid/faction_humanoid.gd")
const SETTLEMENT_GUARD_POST_SCRIPT = preload("res://features/settlements/bridge/venues/settlement_guard_post.gd")
const JAIL_CELL_SCRIPT = preload("res://features/settlements/bridge/jail_cell.gd")
const JAIL_CELL_SCENE = preload("res://features/settlements/bridge/jail_cell.tscn")
const PRISONER_LOCKER_SCENE = preload("res://features/world/projection/containers/prisoner_locker_container.tscn")
const BANDAGE_ITEM = preload("res://features/inventory/resources/items/bandage.tres")
const HATCHET_ITEM = preload("res://features/inventory/resources/items/hatchet.tres")
const ROUND_SHIELD_ITEM = preload("res://features/inventory/resources/items/round_shield.tres")

const STAFF_ROLE_OWNER_GROUP := "settlement_staff_role_owner"
const META_GENERATED := "jail_generated"
const META_ROLE := "jail_role"
const META_INDEX := "jail_index"
const META_SETTLEMENT_ROLE := "settlement_staff_role"
const META_SETTLEMENT_ROLE_INDEX := "settlement_staff_role_index"
const META_SETTLEMENT_SLOT_ID := "settlement_staff_slot_id"
const DEFAULT_REPLACEMENT_DELAY_DAYS := 7.0
const GUARD_PERCEPTION_RANGE := Vector2i(12, 22)
const WARDEN_PERCEPTION_RANGE := Vector2i(18, 30)
const SENTENCE_ROUTE_STALL_SECONDS := 6.0
const SENTENCE_ROUTE_PROGRESS_EPSILON := 0.12
const SENTENCE_STALLED_DELIVERY_DISTANCE := 3.0
const WARDEN_POST_DEBUG_COLOR := Color(0.25, 1.0, 0.35, 0.82)

@export var guard_posts_root_path: NodePath = NodePath("GuardPosts")
@export var warden_posts_root_path: NodePath = NodePath("WardenPosts")
@export var cells_root_path: NodePath = NodePath("Cells")
@export var lockers_root_path: NodePath = NodePath("Lockers")
@export var entry_point_path: NodePath = NodePath("EntryPoint")
@export var auto_create_default_building := true:
	set(value):
		auto_create_default_building = value
		_repair_authoring_tree()
@export var warden_name := "Warden"
@export_range(0, 12, 1) var guard_count := 2:
	set(value):
		guard_count = clampi(int(value), 0, 12)
		_repair_authoring_tree()
@export_range(0, 12, 1) var guard_post_count := 0:
	set(value):
		guard_post_count = clampi(int(value), 0, 12)
		_repair_authoring_tree()
@export var guard_name := "Jail Guard"
@export_range(0, 24, 1) var cell_count := 3:
	set(value):
		cell_count = clampi(int(value), 0, 24)
		_repair_authoring_tree()
@export_range(1, 12, 1) var prisoners_per_cell := 1:
	set(value):
		prisoners_per_cell = max(1, int(value))
		_repair_authoring_tree()
@export var population_appearance_profile: Resource:
	set(value):
		population_appearance_profile = value
		_repair_authoring_tree()
@export var population_name_profile: Resource:
	set(value):
		population_name_profile = value
		_repair_authoring_tree()
@export var staff_stable_id_prefix := ""
@export var staff_squad_name := ""
@export var sync_staff_from_owner := true
@export var cell_lock_difficulties: Array[int] = [5, 35, 70]
@export_range(0, 100, 1) var locker_lock_difficulty := 70

var _guard_post_by_actor_id: Dictionary = {}
var _pending_sentence_announcements: Array[Dictionary] = []


func _ready() -> void:
	add_to_group("settlement_jail")
	add_to_group(STAFF_ROLE_OWNER_GROUP)
	_repair_authoring_tree()
	super._ready()


func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	_process_sentence_announcements(delta)
	_process_warden_home_return()
	for guard in get_guard_actors():
		_process_guard_post_assignment(guard as HumanoidCharacter)


func _repair_authoring_tree() -> void:
	_apply_jail_defaults()
	if not is_inside_tree() or not auto_create_standard_roots:
		return
	if Engine.is_editor_hint() and not _is_editing_jail_base_scene():
		return
	_ensure_root(building_root_path)
	_ensure_root(staff_root_path)
	_ensure_root(guard_posts_root_path)
	_ensure_root(warden_posts_root_path)
	_ensure_root(cells_root_path)
	_ensure_root(lockers_root_path)
	_ensure_default_building()
	_ensure_guard_posts()
	_ensure_warden_posts()
	_ensure_cells()
	_ensure_prisoner_locker()
	_ensure_staff()


func get_facility_id() -> String:
	if not facility_id.strip_edges().is_empty():
		return facility_id
	var settlement_id := _get_ancestor_settlement_id()
	var local_id := _to_snake_id(name)
	return local_id if settlement_id.is_empty() else "%s.%s" % [settlement_id, local_id]


func get_facility_record(settlement_id := "") -> Dictionary:
	var record := super.get_facility_record(settlement_id)
	record["facility_id"] = get_facility_id()
	record["warden_count"] = 1 if _is_actor_alive(get_warden_actor()) else 0
	record["jail_guard_count"] = get_guard_actors().size()
	record["guard_post_count"] = get_guard_posts().size()
	record["cell_count"] = get_cells().size()
	record["prisoner_capacity"] = get_prisoner_capacity()
	record["locker_count"] = 1 if get_prisoner_locker() != null else 0
	return record


func get_settlement_staff_slots() -> Array[Dictionary]:
	var slots: Array[Dictionary] = []
	_append_staff_slot(slots, "warden", 0, get_warden_actor(), warden_name, "settlement_authority")
	for index in range(guard_count):
		_append_staff_slot(slots, "guard", index, _get_guard_actor_for_slot(index), _indexed_display_name(guard_name, index), "settlement_authority")
	return slots


func fill_settlement_staff_slot(slot_id: String, slot_record: Dictionary) -> Node:
	var role := str(slot_record.get("role_id", "")).strip_edges().to_lower()
	var role_index: int = max(0, int(slot_record.get("role_index", _role_index_from_slot_id(slot_id))))
	var existing := get_warden_actor() if role == "warden" else _get_guard_actor_for_slot(role_index)
	if _is_actor_alive(existing):
		return existing
	var staff_root := _ensure_root(staff_root_path)
	if staff_root == null:
		return null
	var worker_actor_id := str(slot_record.get("worker_actor_id", "")).strip_edges()
	var actor: Node = null
	if not worker_actor_id.is_empty():
		# Ledger-assigned worker: claim its specific live body if realized, else build from record.
		actor = SettlementFacility.resolve_live_worker(self, worker_actor_id)
		if actor != null:
			_prepare_staff_actor(actor, role, role_index, true)
		else:
			actor = _create_staff_actor(role, role_index, staff_root)
		if actor != null:
			SettlementFacility.adopt_staff_record(actor, worker_actor_id, slot_id, staff_root)
	else:
		actor = _claim_available_resident_for_role(role, role_index, staff_root)
		if actor == null:
			if _should_defer_staff_to_settlement_population():
				return null
			actor = _create_staff_actor(role, role_index, staff_root)
		else:
			_prepare_staff_actor(actor, role, role_index, true)
	return actor


func get_warden_actor() -> Node:
	return _find_actor_by_slot_id(_staff_slot_id("warden", 0), "Warden")


func _process_warden_home_return() -> void:
	var warden := get_warden_actor() as HumanoidCharacter
	if warden == null or warden.life_state != NpcRules.LifeState.ALIVE:
		return
	if warden.is_in_combat():
		return
	if warden.has_method("is_handling_carried_character") and bool(warden.call("is_handling_carried_character")):
		return
	if _is_warden_sentence_delivery_active(warden):
		return
	var post := _ensure_warden_post()
	if post == null:
		return
	var home_position := post.global_position
	if _horizontal_distance(warden.global_position, home_position) <= _warden_home_arrival_distance(warden):
		if warden.has_method("clear_law_custody_return"):
			warden.call("clear_law_custody_return")
		if warden.has_method("clear_law_sentence_move"):
			warden.call("clear_law_sentence_move")
		if warden.has_method("_clear_actor_move_target"):
			warden.call("_clear_actor_move_target")
		warden.velocity = Vector3.ZERO
		return
	if warden.has_method("clear_law_sentence_move"):
		warden.call("clear_law_sentence_move")
	if warden.has_method("assign_law_custody_return_target"):
		warden.call("assign_law_custody_return_target", home_position)
	else:
		warden.set_move_target(home_position, false)


func _ensure_warden_posts() -> void:
	var root := _ensure_root(warden_posts_root_path)
	if root == null:
		return
	var post := root.get_node_or_null("WardenPost") as Node3D
	if post == null:
		post = Node3D.new()
		post.name = "WardenPost"
		post.transform = _default_warden_post_transform()
		root.add_child(post)
		_set_editor_owner(post)
	_prepare_warden_post(post)


func _ensure_warden_post() -> Node3D:
	var root := get_node_or_null(warden_posts_root_path)
	if root == null:
		_ensure_warden_posts()
		root = get_node_or_null(warden_posts_root_path)
	if root == null:
		return null
	var post := root.get_node_or_null("WardenPost") as Node3D
	if post == null:
		_ensure_warden_posts()
		post = root.get_node_or_null("WardenPost") as Node3D
	if post != null:
		_prepare_warden_post(post)
	return post


func _prepare_warden_post(post: Node3D) -> void:
	if post == null:
		return
	if not post.has_method("get_work_position"):
		post.set_script(SETTLEMENT_GUARD_POST_SCRIPT)
	if _has_property(post, "debug_color"):
		post.set("debug_color", WARDEN_POST_DEBUG_COLOR)
	if _has_property(post, "editor_show_debug_marker"):
		post.set("editor_show_debug_marker", true)
	post.set_meta(META_GENERATED, true)
	post.set_meta(META_ROLE, "warden_post")
	post.set_meta(META_INDEX, 0)


func _default_warden_post_transform() -> Transform3D:
	return Transform3D(Basis(Vector3(-0.12043145, 0.0, -0.9927216), Vector3(0.0, 1.0, 0.0), Vector3(0.9927216, 0.0, -0.12043145)), Vector3(1.3208423, 0.6, 4.1061177))


func _horizontal_distance(left: Vector3, right: Vector3) -> float:
	return Vector2(left.x - right.x, left.z - right.z).length()


func _warden_home_arrival_distance(warden: HumanoidCharacter) -> float:
	if warden != null and _has_property(warden, "navigation_target_desired_distance"):
		return maxf(0.35, float(warden.get("navigation_target_desired_distance")) + 0.05)
	return 0.65


func _is_warden_sentence_delivery_active(_warden: HumanoidCharacter) -> bool:
	if _pending_sentence_announcements.is_empty():
		return false
	var entry := _pending_sentence_announcements[0]
	var raw = entry.get("actor")
	if raw == null or not is_instance_valid(raw):
		return false
	var actor := raw as HumanoidCharacter
	return actor != null and actor.life_state == NpcRules.LifeState.ALIVE and actor.is_law_prisoner() and _has_pending_sentence_notification(actor)


func _has_pending_sentence_notification(actor: HumanoidCharacter) -> bool:
	if actor == null:
		return false
	var tree := get_tree()
	if tree == null:
		return false
	for controller in tree.get_nodes_in_group("law_order_controller"):
		if controller != null and controller.has_method("has_pending_prisoner_sentence_notification"):
			return bool(controller.call("has_pending_prisoner_sentence_notification", actor))
	return false


func get_guard_actors() -> Array[Node]:
	var guards: Array[Node] = []
	var root := get_node_or_null(staff_root_path)
	if root == null:
		return guards
	for child in root.get_children():
		if child is HumanoidCharacter and str(child.get_meta(META_SETTLEMENT_ROLE, "")) == "guard" and _is_actor_alive(child):
			guards.append(child)
	return guards


func get_guard_posts() -> Array[Node]:
	return _children_at(guard_posts_root_path)


func get_cells() -> Array[Node]:
	return _children_at(cells_root_path)


func _find_cell_by_id(cell_id: String) -> Node:
	if cell_id.strip_edges().is_empty():
		return null
	for cell in get_cells():
		if cell != null and cell.has_method("get_cell_id") and str(cell.call("get_cell_id")) == cell_id:
			return cell
	return null


# Re-seat an already-jailed prisoner into their cell after their actor node
# LOD-realizes (no re-confiscation -- their items are already in the locker).
# Truth lives in the law controller's prisoner_records (jail_id/cell_id), which
# survive the actor being unloaded; this restores the physical placement.
func restore_prisoner_to_cell(actor: WorldActor, record: Dictionary) -> bool:
	if actor == null or actor.life_state == NpcRules.LifeState.DEAD:
		return false
	var cell := _find_cell_by_id(str(record.get("cell_id", "")))
	if cell == null:
		cell = _find_cell_for_prisoner(actor)
	if cell == null:
		cell = get_available_cell(actor, actor)
	if cell == null:
		return false
	var already_assigned := cell.has_method("has_occupant") and bool(cell.call("has_occupant", actor))
	if not already_assigned:
		if not cell.has_method("assign_prisoner") or not bool(cell.call("assign_prisoner", actor)):
			return false
	var prisoner_position: Vector3 = cell.call("get_prisoner_position", actor) if cell.has_method("get_prisoner_position") else actor.global_position
	var prisoner_rotation: Vector3 = cell.call("get_prisoner_rotation", actor) if cell.has_method("get_prisoner_rotation") else actor.global_rotation
	actor.enter_cell_custody(cell, prisoner_position, prisoner_rotation)
	return true


func get_prisoner_capacity() -> int:
	var total := 0
	for cell in get_cells():
		if cell != null and cell.has_method("get_cell_record"):
			total += int(cell.call("get_cell_record").get("prisoner_capacity", 0))
	return total


func get_available_cell(actor: Node = null, reference: Node = null) -> Node:
	var reference_position := _cell_selection_reference_position(reference if reference != null else actor)
	var best_cell: Node = null
	var best_distance := INF
	for cell in get_cells():
		if cell == null or not cell.has_method("can_assign_prisoner") or not bool(cell.call("can_assign_prisoner", actor)):
			continue
		if reference_position == Vector3.INF:
			return cell
		var cell_position := _cell_selection_position(cell, actor)
		var distance := reference_position.distance_squared_to(cell_position)
		if distance < best_distance:
			best_distance = distance
			best_cell = cell
	return best_cell


func _cell_selection_reference_position(reference: Node) -> Vector3:
	return (reference as Node3D).global_position if reference is Node3D else Vector3.INF


func _cell_selection_position(cell: Node, actor: Node = null) -> Vector3:
	if cell != null and cell.has_method("get_interaction_position"):
		var interaction_position: Variant = cell.call("get_interaction_position", actor)
		if interaction_position is Vector3:
			return interaction_position
	return (cell as Node3D).global_position if cell is Node3D else Vector3.ZERO


func get_entry_position(_actor: Node = null) -> Vector3:
	var point := get_node_or_null(entry_point_path) as Node3D
	return point.global_position if point != null else global_transform * Vector3(0.0, 0.6, 7.8)


func get_exit_position(actor: Node = null) -> Vector3:
	var entry_position := get_entry_position(actor)
	var direction := entry_position - global_position
	direction.y = 0.0
	if direction.length_squared() <= 0.001:
		return entry_position
	return entry_position + direction.normalized() * 1.5


func is_actor_inside_jail(actor: Node) -> bool:
	if not (actor is Node3D):
		return false
	var building_root := get_building_root()
	if building_root != null:
		for building in building_root.get_children():
			if building != null and building.has_method("is_actor_inside") and bool(building.call("is_actor_inside", actor)):
				return true
	var local_position := global_transform.affine_inverse() * (actor as Node3D).global_position
	return absf(local_position.x) <= 6.2 and local_position.z >= -7.2 and local_position.z <= 7.1 and local_position.y >= -1.0 and local_position.y <= 4.8


func get_cell_interaction_route(cell: Node, actor: Node = null) -> Array[Vector3]:
	var route: Array[Vector3] = []
	var entry_position := get_entry_position(actor)
	var interaction_position := entry_position
	if cell != null and cell.has_method("get_interaction_position"):
		interaction_position = cell.call("get_interaction_position", actor)
	var actor_starts_outside := actor is Node3D and not is_actor_inside_jail(actor)
	if actor_starts_outside and (actor as Node3D).global_position.distance_to(entry_position) > 0.75:
		route.append(entry_position)
	var local_interaction := global_transform.affine_inverse() * interaction_position
	var aisle_position := global_transform * Vector3(0.0, local_interaction.y, 0.0)
	if (route.is_empty() or route[route.size() - 1].distance_to(aisle_position) > 0.75) and aisle_position.distance_to(interaction_position) > 0.75:
		route.append(aisle_position)
	var cell_row_position := global_transform * Vector3(0.0, local_interaction.y, local_interaction.z)
	if (route.is_empty() or route[route.size() - 1].distance_to(cell_row_position) > 0.75) and cell_row_position.distance_to(interaction_position) > 0.75:
		route.append(cell_row_position)
	if route.is_empty() or route[route.size() - 1].distance_to(interaction_position) > 0.75:
		route.append(interaction_position)
	return route


func get_prisoner_locker() -> Node:
	var root := get_node_or_null(lockers_root_path)
	return root.get_node_or_null("PrisonerLocker") if root != null else null


func admit_prisoner(actor: WorldActor, warrant: Dictionary, law_controller: Node = null) -> bool:
	if actor == null or actor.life_state == NpcRules.LifeState.DEAD:
		return false
	var cell := _find_cell_for_prisoner(actor)
	var locker := get_prisoner_locker()
	if cell == null or locker == null:
		return false
	actor.velocity = Vector3.ZERO
	_stabilize_prisoner(actor)
	_confiscate_prisoner_items(actor, locker, warrant, law_controller)
	var status := actor.get_legal_status()
	status.is_prisoner = true
	status.jail_id = get_facility_id()
	status.cell_id = str(cell.call("get_cell_id"))
	return true


func tell_prisoner_sentence(actor: WorldActor, record: Dictionary) -> bool:
	if actor == null:
		return false
	var crimes := _crime_summary(record)
	var release_at := int(record.get("release_at_minute", -1))
	var duration_minutes: int = max(0, release_at - _now_minute()) if release_at >= 0 else max(1, int(record.get("sentence_minutes", 1)))
	var duration := _minutes_label(duration_minutes)
	return _queue_sentence_announcement(actor, "You are sentenced for %s. You serve %s." % [crimes, duration])


func _queue_sentence_announcement(actor: WorldActor, message: String) -> bool:
	if actor == null or message.is_empty():
		return false
	for index in range(_pending_sentence_announcements.size()):
		if _pending_sentence_announcements[index].get("actor") == actor:
			_pending_sentence_announcements[index]["message"] = message
			return true
	_pending_sentence_announcements.append({"actor": actor, "message": message})
	return true


func _process_sentence_announcements(delta: float) -> void:
	if _pending_sentence_announcements.is_empty():
		return
	var entry := _pending_sentence_announcements[0]
	var raw = entry.get("actor")
	if raw == null or not is_instance_valid(raw):
		_pending_sentence_announcements.pop_front()
		return
	var actor := raw as WorldActor
	if actor == null:
		_pending_sentence_announcements.pop_front()
		return
	if not actor.is_law_prisoner():
		_pending_sentence_announcements.pop_front()
		return
	if actor.life_state == NpcRules.LifeState.DEAD:
		_pending_sentence_announcements.pop_front()
		return
	if actor.life_state != NpcRules.LifeState.ALIVE:
		return
	if not _has_pending_sentence_notification(actor):
		_pending_sentence_announcements.pop_front()
		return
	var warden := get_warden_actor() as HumanoidCharacter
	if warden == null or not is_instance_valid(warden) or warden.life_state != NpcRules.LifeState.ALIVE:
		return
	_prepare_warden_for_sentence_delivery(warden)
	entry = _ensure_sentence_route(entry, actor, warden)
	_pending_sentence_announcements[0] = entry
	var route: Array = entry.get("route", [])
	if route.is_empty():
		return
	var route_index := clampi(int(entry.get("route_index", 0)), 0, route.size() - 1)
	var reach_distance := _get_sentence_route_reach_distance(warden)
	while route_index < route.size() - 1 and route[route_index] is Vector3 and warden.global_position.distance_to(route[route_index]) <= reach_distance:
		route_index += 1
	entry["route_index"] = route_index
	_pending_sentence_announcements[0] = entry
	var route_target: Vector3 = route[route_index]
	entry = _update_sentence_route_stall(entry, route, route_index, warden, route_target, delta)
	route_index = clampi(int(entry.get("route_index", route_index)), 0, route.size() - 1)
	_pending_sentence_announcements[0] = entry
	route_target = route[route_index]
	var delivery_distance := warden.global_position.distance_to(route_target)
	var stalled_close_enough := bool(entry.get("sentence_route_final_close", false))
	if delivery_distance > reach_distance and not stalled_close_enough:
		_assign_warden_sentence_move(warden, route_target)
		return
	_face_warden_toward_actor(warden, actor)
	if warden.has_method("clear_law_sentence_move"):
		warden.call("clear_law_sentence_move")
	if _open_sentence_conversation(warden, actor, str(entry.get("message", ""))) and _notify_sentence_delivered(actor):
		_pending_sentence_announcements.pop_front()


func _get_sentence_announcement_position(actor: WorldActor) -> Vector3:
	var cell := _find_cell_for_prisoner(actor)
	if cell != null and cell.has_method("get_interaction_position"):
		var cell_position: Variant = cell.call("get_interaction_position", actor)
		if cell_position is Vector3:
			return cell_position
	return actor.global_position if actor != null else global_position


func _prepare_warden_for_sentence_delivery(warden: HumanoidCharacter) -> void:
	if warden == null:
		return
	if warden.has_method("disengage_combat_with"):
		warden.call("disengage_combat_with")


func _ensure_sentence_route(entry: Dictionary, actor: WorldActor, warden: HumanoidCharacter) -> Dictionary:
	var route_value: Variant = entry.get("route", [])
	if route_value is Array and not route_value.is_empty() and not _should_rebuild_sentence_route(route_value, warden):
		return entry
	entry["route"] = _build_sentence_route(actor, warden)
	entry["route_index"] = 0
	return entry


func _should_rebuild_sentence_route(route: Array, warden: HumanoidCharacter) -> bool:
	if route.is_empty():
		return true
	if not (route[0] is Vector3):
		return true
	if warden == null or not is_actor_inside_jail(warden):
		return false
	return (route[0] as Vector3).distance_squared_to(get_entry_position(warden)) <= 0.64


func _build_sentence_route(actor: WorldActor, warden: HumanoidCharacter) -> Array[Vector3]:
	var route: Array[Vector3] = []
	var final_position := _get_sentence_announcement_position(actor)
	var cell := _find_cell_for_prisoner(actor)
	if cell != null and cell.has_method("get_interaction_route"):
		var route_value: Variant = cell.call("get_interaction_route", warden)
		if route_value is Array:
			for point in route_value:
				if point is Vector3:
					_append_sentence_route_point(route, point)
	_append_sentence_route_point(route, final_position)
	return route


func _append_sentence_route_point(route: Array[Vector3], point: Vector3) -> void:
	if not route.is_empty() and route[route.size() - 1].distance_squared_to(point) <= 0.04:
		return
	route.append(point)


func _get_sentence_route_reach_distance(warden: HumanoidCharacter) -> float:
	return maxf(warden.interact_distance if warden != null else 0.75, 0.9)


func _update_sentence_route_stall(entry: Dictionary, route: Array, route_index: int, warden: HumanoidCharacter, route_target: Vector3, delta: float) -> Dictionary:
	if warden == null:
		return entry
	var distance := warden.global_position.distance_to(route_target)
	var last_index := int(entry.get("sentence_route_last_index", -1))
	var last_distance := float(entry.get("sentence_route_last_distance", INF))
	if last_index != route_index or distance < last_distance - SENTENCE_ROUTE_PROGRESS_EPSILON:
		entry["sentence_route_last_index"] = route_index
		entry["sentence_route_last_distance"] = distance
		entry["sentence_route_stall_seconds"] = 0.0
		entry["sentence_route_final_close"] = false
		return entry
	var stalled_seconds := float(entry.get("sentence_route_stall_seconds", 0.0)) + delta
	entry["sentence_route_stall_seconds"] = stalled_seconds
	if stalled_seconds < SENTENCE_ROUTE_STALL_SECONDS:
		return entry
	entry["sentence_route_stall_seconds"] = 0.0
	entry["sentence_route_last_distance"] = INF
	if route_index < route.size() - 1:
		entry["route_index"] = route_index + 1
		entry["sentence_route_final_close"] = false
	elif distance <= SENTENCE_STALLED_DELIVERY_DISTANCE:
		entry["sentence_route_final_close"] = true
	return entry


func _assign_warden_sentence_move(warden: HumanoidCharacter, target_position: Vector3) -> void:
	if warden == null:
		return
	if warden.has_method("assign_law_sentence_move_target"):
		warden.call("assign_law_sentence_move_target", target_position)
	else:
		warden.set_move_target(target_position, false)


func _face_warden_toward_actor(warden: HumanoidCharacter, actor: WorldActor) -> void:
	if warden == null or actor == null:
		return
	var target_position := Vector3(actor.global_position.x, warden.global_position.y, actor.global_position.z)
	if warden.global_position.distance_squared_to(target_position) <= 0.001:
		return
	warden.look_at(target_position, Vector3.UP)
	warden.rotation.x = 0.0
	warden.rotation.z = 0.0


func _open_sentence_conversation(warden: HumanoidCharacter, actor: WorldActor, message: String) -> bool:
	var conversation_controller := _get_conversation_controller()
	if conversation_controller != null and conversation_controller.has_method("begin_system_conversation"):
		return bool(conversation_controller.call("begin_system_conversation", warden, actor, message, "Understood"))
	return false


func _notify_sentence_delivered(actor: WorldActor) -> bool:
	var tree := get_tree()
	if tree == null:
		return false
	for controller in tree.get_nodes_in_group("law_order_controller"):
		if controller != null and controller.has_method("complete_prisoner_sentence_delivery"):
			return bool(controller.call("complete_prisoner_sentence_delivery", actor))
	return false


func _get_conversation_controller() -> Node:
	var tree := get_tree()
	if tree == null:
		return null
	for controller in tree.get_nodes_in_group("conversation_controller"):
		return controller
	return null


func release_prisoner(actor: WorldActor, record: Dictionary, escaped := false) -> void:
	if actor == null:
		return
	var locker := get_prisoner_locker()
	if locker != null:
		_restore_prisoner_items(actor, locker, record, escaped)
	var cell := _find_cell_for_prisoner(actor)
	if cell != null:
		cell.call("release_prisoner", actor)
		if actor.has_method("exit_cell_custody"):
			actor.call("exit_cell_custody", cell.call("get_release_position"), cell.call("get_release_rotation") if cell.has_method("get_release_rotation") else actor.global_rotation)
		else:
			actor.global_position = cell.call("get_release_position")
	actor.get_legal_status().clear_prisoner()
	actor.velocity = Vector3.ZERO


func _apply_jail_defaults() -> void:
	if facility_function == null:
		facility_function = JAIL_FUNCTION
	building_root_path = NodePath("BuildingSlot")
	staff_root_path = NodePath("Staff")
	service_points_root_path = NodePath("")
	storage_root_path = NodePath("")
	job_providers_root_path = NodePath("")
	activity_points_root_path = NodePath("")
	lockers_root_path = NodePath("Lockers")
	facility_type = "jail"
	if display_name.is_empty() or display_name == "Facility":
		display_name = "Settlement Jail"


func _ensure_default_building() -> Node:
	if not auto_create_default_building:
		return null
	var root := get_building_root()
	if root == null:
		return null
	if root.get_child_count() > 0:
		return root.get_child(0)
	var building := DEFAULT_BUILDING_SCENE.instantiate()
	building.name = "CurrentBuilding"
	root.add_child(building)
	if _has_property(building, "display_name"):
		building.set("display_name", "Jail")
	if _has_property(building, "building_type"):
		building.set("building_type", "jail")
	if _has_property(building, "access_mode"):
		building.set("access_mode", "public")
	if _has_property(building, "use_law_profile_trespass_rules"):
		building.set("use_law_profile_trespass_rules", false)
	_set_editor_owner_recursive(building)
	return building


func _ensure_guard_posts() -> void:
	var root := _ensure_root(guard_posts_root_path)
	if root == null:
		return
	var effective_count: int = max(guard_count, guard_post_count)
	for index in range(effective_count):
		var post_name := _indexed_name("GuardPost", index)
		var post := root.get_node_or_null(post_name)
		if post == null:
			post = Node3D.new()
			post.name = post_name
			post.transform = _guard_post_transform(index)
			post.set_script(SETTLEMENT_GUARD_POST_SCRIPT)
			root.add_child(post)
			_set_editor_owner(post)
		if not post.has_method("get_work_position"):
			post.set_script(SETTLEMENT_GUARD_POST_SCRIPT)
		if _has_property(post, "debug_color"):
			post.set("debug_color", Color(0.35, 0.78, 1.0, 0.76))
		post.set_meta(META_GENERATED, true)
		post.set_meta(META_ROLE, "guard_post")
		post.set_meta(META_INDEX, index)
	_trim_generated_children(root, "GuardPost", effective_count)


func _ensure_cells() -> void:
	var root := _ensure_root(cells_root_path)
	if root == null:
		return
	for index in range(cell_count):
		var cell_name := _indexed_name("Cell", index)
		var cell := root.get_node_or_null(cell_name)
		if cell == null:
			cell = JAIL_CELL_SCENE.instantiate()
			cell.name = cell_name
			if cell is Node3D:
				(cell as Node3D).position = Vector3(-4.2 + float(index % 4) * 2.6, 0.05, -6.035112 - float(int(float(index) / 4.0)) * 1.9)
			root.add_child(cell)
			_set_editor_owner_recursive(cell)
		elif not cell.has_method("get_cell_record"):
			cell.set_script(JAIL_CELL_SCRIPT)
		if _has_property(cell, "prisoner_capacity"):
			cell.set("prisoner_capacity", prisoners_per_cell)
		if _has_property(cell, "lock_difficulty"):
			cell.set("lock_difficulty", int(cell_lock_difficulties[index]) if index < cell_lock_difficulties.size() else 70)
		cell.set_meta(META_GENERATED, true)
		cell.set_meta(META_ROLE, "cell")
		cell.set_meta(META_INDEX, index)
	_trim_generated_children(root, "Cell", cell_count)


func _ensure_prisoner_locker() -> Node:
	var root := _ensure_root(lockers_root_path)
	if root == null:
		return null
	var locker := root.get_node_or_null("PrisonerLocker")
	if locker == null:
		locker = PRISONER_LOCKER_SCENE.instantiate()
		locker.name = "PrisonerLocker"
		if locker is Node3D:
			(locker as Node3D).transform = Transform3D(Basis(Vector3(0.06444523, 0.0, -0.9979212), Vector3(0.0, 1.0, 0.0), Vector3(0.9979212, 0.0, 0.06444523)), Vector3(5.281292, 0.0, -3.8477674))
		root.add_child(locker)
		_set_editor_owner_recursive(locker)
	if _has_property(locker, "lock_difficulty"):
		locker.set("lock_difficulty", locker_lock_difficulty)
	if _has_property(locker, "owner_faction_name"):
		locker.set("owner_faction_name", _get_effective_owner_faction_id())
	locker.set_meta(META_GENERATED, true)
	locker.set_meta(META_ROLE, "prisoner_locker")
	return locker


func _ensure_staff() -> void:
	var root := _ensure_root(staff_root_path)
	if root == null:
		return
	if _should_defer_staff_to_settlement_population():
		return
	_ensure_staff_actor(root, "warden", 0)
	for index in range(guard_count):
		_ensure_staff_actor(root, "guard", index)
	_trim_generated_children(root, "Guard", guard_count)


func _is_editing_jail_base_scene() -> bool:
	if not Engine.is_editor_hint():
		return true
	var tree := get_tree()
	return tree != null and tree.edited_scene_root == self


func _ensure_staff_actor(root: Node, role: String, index: int) -> Node:
	var node_name := "Warden" if role == "warden" else _indexed_name("Guard", index)
	var actor := root.get_node_or_null(node_name)
	if actor != null and not _is_actor_alive(actor):
		actor = null
	if actor == null:
		return _create_staff_actor(role, index, root)
	_prepare_staff_actor(actor, role, index)
	return actor


func _create_staff_actor(role: String, index: int, root: Node) -> Node:
	var actor := CharacterBody3D.new()
	actor.name = _available_child_name(root, "Warden" if role == "warden" else _indexed_name("Guard", index))
	actor.position = _local_position_for_role(role, index)
	actor.set_script(FACTION_HUMANOID_SCRIPT)
	_prepare_staff_actor(actor, role, index)
	_add_basic_humanoid_children(actor)
	root.add_child(actor)
	_set_editor_owner_recursive(actor)
	return actor


func _prepare_staff_actor(actor: Node, role: String, index: int, apply_default_position := false) -> void:
	if actor == null:
		return
	actor.set_script(FACTION_HUMANOID_SCRIPT)
	actor.set_meta(META_GENERATED, true)
	actor.set_meta(META_SETTLEMENT_ROLE, role)
	actor.set_meta(META_SETTLEMENT_ROLE_INDEX, index)
	actor.set_meta(META_SETTLEMENT_SLOT_ID, _staff_slot_id(role, index))
	actor.set_meta("settlement_actor_category", "staff")
	if _has_property(actor, "member_name") and (_is_generated_staff(actor) or str(actor.get("member_name")).strip_edges().is_empty() or str(actor.get("member_name")) == "Character"):
		actor.set("member_name", _display_name_for_role(role, index))
	_apply_role_suffix(actor, role)
	var faction_id := _get_effective_owner_faction_id()
	if sync_staff_from_owner and not faction_id.is_empty() and _has_property(actor, "faction_name"):
		actor.set("faction_name", faction_id)
	if _has_property(actor, "squad_name"):
		actor.set("squad_name", _get_staff_squad_name())
	if _has_property(actor, "stable_id") and str(actor.get("stable_id")).strip_edges().is_empty():
		actor.set("stable_id", "%s.%s" % [_get_staff_id_prefix(), _indexed_name(role, index)])
	if _has_property(actor, "base_attack_damage"):
		actor.set("base_attack_damage", 12.0)
	_apply_staff_starting_equipment(actor, role)
	if not Engine.is_editor_hint():
		if actor.has_method("set_settlement_authority"):
			actor.call("set_settlement_authority", true)
		if actor.has_method("set_private_security"):
			actor.call("set_private_security", false)
		if actor.has_method("set_faction_soldier"):
			actor.call("set_faction_soldier", true)
	_apply_population_generation_to_actor(actor, role, index)
	_apply_staff_skills(actor, role, index)
	if apply_default_position and actor is Node3D:
		(actor as Node3D).position = _local_position_for_role(role, index)
	_sync_staff_actor_population_record(actor)


func _sync_staff_actor_population_record(actor: Node) -> void:
	if actor == null or Engine.is_editor_hint() or not actor.is_inside_tree():
		return
	var settlement_id := _get_ancestor_settlement_id()
	if settlement_id.is_empty():
		return
	var population_controller := get_tree().get_first_node_in_group("population_controller")
	if population_controller != null and population_controller.has_method("register_actor"):
		population_controller.call("register_actor", actor, settlement_id, {})


func _apply_staff_starting_equipment(actor: Node, role: String) -> void:
	if actor == null or not _has_property(actor, "starting_equipment"):
		return
	var starting_equipment: Array = (actor.get("starting_equipment") as Array).duplicate()
	for item in [BANDAGE_ITEM, HATCHET_ITEM if role == "guard" else null, ROUND_SHIELD_ITEM if role == "guard" else null]:
		if item == null or starting_equipment.has(item):
			continue
		starting_equipment.append(item)
		var slot_name := str(item.get("equip_slot")) if _has_property(item, "equip_slot") else ""
		if not Engine.is_editor_hint() and not slot_name.is_empty() and actor.has_method("get_equipped_item") and actor.has_method("equip_item_to_slot") and actor.call("get_equipped_item", slot_name) == null:
			actor.call("equip_item_to_slot", item, slot_name)
	actor.set("starting_equipment", starting_equipment)


func _append_staff_slot(slots: Array[Dictionary], role: String, index: int, actor: Node, staff_display_name: String, authority_scope: String) -> void:
	var actor_alive := _is_actor_alive(actor)
	var slot := {
		"slot_id": _staff_slot_id(role, index),
		"role_id": role,
		"role_index": index,
		"display_name": staff_display_name,
		"population_cost": 1,
		"replacement_delay_days": DEFAULT_REPLACEMENT_DELAY_DAYS,
		"filled": actor_alive,
		"authority_scope": authority_scope,
	}
	if actor != null:
		slot["actor_path"] = get_path_to(actor) if actor.is_inside_tree() else NodePath("")
		if not actor_alive:
			slot["dead_actor_key"] = _actor_key(actor)
	slots.append(slot)


func _find_actor_by_slot_id(slot_id: String, fallback_name: String) -> Node:
	var root := get_node_or_null(staff_root_path)
	if root == null:
		return null
	for child in root.get_children():
		if str(child.get_meta(META_SETTLEMENT_SLOT_ID, "")) == slot_id:
			return child
	return root.get_node_or_null(fallback_name)


func _get_guard_actor_for_slot(index: int) -> Node:
	return _find_actor_by_slot_id(_staff_slot_id("guard", index), _indexed_name("Guard", index))


func _claim_available_resident_for_role(role: String, index: int, staff_root: Node) -> Node:
	var settlement := _get_ancestor_settlement()
	if settlement == null:
		return null
	var resident_root_path = settlement.get("resident_root_path")
	if resident_root_path == null:
		return null
	var resident_root := settlement.get_node_or_null(resident_root_path)
	if resident_root == null:
		return null
	for candidate in _collect_claimable_residents(resident_root):
		if not _can_claim_resident_for_staff(candidate):
			continue
		var candidate_global_transform := (candidate as Node3D).global_transform if candidate is Node3D else Transform3D.IDENTITY
		candidate.get_parent().remove_child(candidate)
		staff_root.add_child(candidate)
		if candidate is Node3D:
			(candidate as Node3D).global_transform = candidate_global_transform
		candidate.name = _available_child_name(staff_root, "Warden" if role == "warden" else _indexed_name("Guard", index))
		return candidate
	return null


func _collect_claimable_residents(root: Node) -> Array[Node]:
	var residents: Array[Node] = []
	_collect_claimable_residents_recursive(root, residents)
	return residents


func _collect_claimable_residents_recursive(node: Node, residents: Array[Node]) -> void:
	if node == null:
		return
	if node is HumanoidCharacter:
		residents.append(node)
		return
	for child in node.get_children():
		_collect_claimable_residents_recursive(child, residents)


func _can_claim_resident_for_staff(actor: Node) -> bool:
	if not _is_actor_alive(actor):
		return false
	if actor.has_method("is_player_party_member") and bool(actor.call("is_player_party_member")):
		return false
	if str(actor.get_meta(META_SETTLEMENT_SLOT_ID, "")).strip_edges() != "":
		return false
	if actor.has_method("get_active_job_provider") and actor.call("get_active_job_provider") != null:
		return false
	return true


func _process_guard_post_assignment(guard: HumanoidCharacter) -> void:
	if guard == null:
		return
	if guard.is_in_combat():
		return
	if guard.has_method("is_handling_carried_character") and bool(guard.call("is_handling_carried_character")):
		return
	var actor_id := guard.get_instance_id()
	var post = _guard_post_by_actor_id.get(actor_id)
	if post == null or not is_instance_valid(post) or (post.has_method("is_available_for") and not post.call("is_available_for", guard)):
		post = _claim_guard_post_for(guard)
		if post == null:
			return
	if not post.has_method("get_work_position"):
		return
	var work_position: Vector3 = post.call("get_work_position")
	if guard.global_position.distance_to(work_position) > guard.interact_distance:
		guard.set_move_target(work_position, false)


func _claim_guard_post_for(guard: HumanoidCharacter):
	for post in get_guard_posts():
		if post == null:
			continue
		if post.has_method("is_available_for") and not post.call("is_available_for", guard):
			continue
		if post.has_method("claim_worker") and not post.call("claim_worker", guard):
			continue
		_guard_post_by_actor_id[guard.get_instance_id()] = post
		return post
	return null


## Typed vitals writes: the old property-name reflection here was invisible
## to the analyzer and silently broke when members were renamed.
func _stabilize_prisoner(actor: WorldActor) -> void:
	if actor == null or actor.life_state == NpcRules.LifeState.DEAD:
		return
	actor.blood = maxf(actor.blood, actor.max_blood * 0.55)
	var vitals := actor.get_vitals()
	if vitals == null:
		return
	vitals.set_open_cut_damage(0.0)
	vitals.set_bleed_rate(0.0)
	vitals.set_bleed_burst_rate(0.0)
	vitals.recalculate_vitals()


func _confiscate_prisoner_items(actor: WorldActor, locker: Node, warrant: Dictionary, law_controller: Node = null) -> void:
	if actor == null or locker == null or actor.get("inventory") == null:
		return
	var locker_inventory = _ensure_locker_inventory(locker)
	if locker_inventory == null:
		return
	var prisoner_key := actor.stable_id if not actor.stable_id.strip_edges().is_empty() else str(actor.get_instance_id())
	var case_id := str(warrant.get("case_id", "%s:%s" % [prisoner_key, get_facility_id()]))
	for entry in actor.inventory.entries.duplicate():
		var metadata: Dictionary = entry.metadata.duplicate(true)
		metadata[InventoryData.META_LAW_PRISONER_KEY] = prisoner_key
		metadata[InventoryData.META_LAW_CASE_ID] = case_id
		_add_entry_to_locker(locker_inventory, entry.definition, entry.count, entry.contained_item_counts, metadata)
	actor.inventory.entries.clear()
	actor.inventory.changed.emit()
	if actor.has_method("get_equipment_slot_names") and actor.has_method("unequip_item_from_slot"):
		for slot_name in actor.call("get_equipment_slot_names"):
			var item = actor.call("unequip_item_from_slot", str(slot_name))
			if item == null:
				continue
			_add_entry_to_locker(locker_inventory, item, 1, {}, {
				InventoryData.META_LAW_PRISONER_KEY: prisoner_key,
				InventoryData.META_LAW_CASE_ID: case_id,
			})
	locker_inventory.changed.emit()
	if law_controller != null and law_controller.has_method("register_prisoner_locker_transfer"):
		law_controller.call("register_prisoner_locker_transfer", actor, locker, warrant)


func _restore_prisoner_items(actor: WorldActor, locker: Node, _record: Dictionary, escaped: bool) -> void:
	if actor == null or locker == null or actor.get("inventory") == null:
		return
	var locker_inventory = _ensure_locker_inventory(locker)
	if locker_inventory == null:
		return
	var prisoner_key := actor.stable_id if not actor.stable_id.strip_edges().is_empty() else str(actor.get_instance_id())
	for entry in locker_inventory.entries.duplicate():
		if str(entry.metadata.get(InventoryData.META_LAW_PRISONER_KEY, "")) != prisoner_key:
			continue
		locker_inventory.entries.erase(entry)
		var metadata: Dictionary = entry.metadata.duplicate(true)
		metadata.erase(InventoryData.META_LAW_PRISONER_KEY)
		metadata.erase(InventoryData.META_LAW_CASE_ID)
		if bool(metadata.get(InventoryData.META_STOLEN, false)) and not escaped:
			continue
		if not actor.inventory.add_entry_with_contents(entry.definition, entry.count, entry.contained_item_counts, metadata):
			locker_inventory.entries.append(entry)
	locker_inventory.changed.emit()
	actor.inventory.changed.emit()


func _add_entry_to_locker(locker_inventory, definition, count: int, contained_item_counts: Dictionary, metadata: Dictionary) -> bool:
	if locker_inventory == null or definition == null or count <= 0:
		return false
	var slot: Vector2i = locker_inventory.find_first_space(definition)
	if slot == Vector2i(-1, -1):
		return false
	locker_inventory.entries.append(InventoryData.InventoryEntry.new(definition, slot, count, contained_item_counts, metadata))
	return true


func _ensure_locker_inventory(locker: Node):
	if locker == null:
		return null
	if locker.get("inventory") != null:
		return locker.get("inventory")
	var inventory := InventoryData.new(12, 8, 0.0, false)
	locker.set("inventory", inventory)
	return inventory


func _find_cell_for_prisoner(actor: Node) -> Node:
	if actor == null:
		return null
	if actor.has_method("get_cell_custody_target"):
		var custody_cell = actor.call("get_cell_custody_target")
		if custody_cell != null:
			return custody_cell
	for cell in get_cells():
		if cell == null or not cell.has_method("has_occupant"):
			continue
		if bool(cell.call("has_occupant", actor)):
			return cell
	return null


func _crime_summary(record: Dictionary) -> String:
	var labels: Array[String] = []
	for crime in record.get("crimes", []):
		var label := str(crime.get("crime_type", "crime")).replace("_", " ")
		if not labels.has(label):
			labels.append(label)
	return ", ".join(labels) if not labels.is_empty() else "your crimes"


func _minutes_label(minutes: int) -> String:
	if minutes >= 24 * 60:
		return "%d days" % int(ceil(float(minutes) / float(24 * 60)))
	if minutes >= 60:
		return "%d hours" % int(ceil(float(minutes) / 60.0))
	return "%d minutes" % max(0, minutes)


func _now_minute() -> int:
	var tree := get_tree()
	if tree == null:
		return 0
	for controller in tree.get_nodes_in_group("world_time_controller"):
		if controller != null and controller.has_method("get_absolute_minute"):
			return int(controller.call("get_absolute_minute"))
	return 0


func _set_property_if_present(target: Object, property_name: String, value) -> void:
	if _has_property(target, property_name):
		target.set(property_name, value)


func _children_at(root_path: NodePath) -> Array[Node]:
	var root := get_node_or_null(root_path)
	var children: Array[Node] = []
	if root == null:
		return children
	for child in root.get_children():
		children.append(child)
	return children


func _guard_post_transform(index: int) -> Transform3D:
	var side := -1.0 if index % 2 == 0 else 1.0
	var row := int(float(index) / 2.0)
	return Transform3D(Basis(Vector3.UP, deg_to_rad(90.0 * -side)), Vector3(4.7 * side, 0.05, 0.2060163 - float(row) * 1.6))


func _local_position_for_role(role: String, index: int) -> Vector3:
	if role == "warden":
		var warden_post := _ensure_warden_post()
		if warden_post != null:
			return global_transform.affine_inverse() * warden_post.global_position if is_inside_tree() else warden_post.position
		return _default_warden_post_transform().origin
	var guard_post_transform := _guard_post_transform(index)
	return Vector3(guard_post_transform.origin.x, 0.6, guard_post_transform.origin.z)


func _display_name_for_role(role: String, index: int) -> String:
	return warden_name if role == "warden" else _indexed_display_name(guard_name, index)


func _staff_slot_id(role: String, index: int) -> String:
	return "%s.%s" % [get_facility_id(), _indexed_name(role, index)]


func _role_index_from_slot_id(slot_id: String) -> int:
	var suffix := slot_id.get_slice(".", slot_id.get_slice_count(".") - 1)
	for role in ["warden", "guard"]:
		if suffix == role:
			return 0
		if suffix.begins_with(role):
			var index_text := suffix.substr(role.length())
			return max(0, int(index_text) - 1) if index_text.is_valid_int() else 0
	return 0


func _indexed_name(base_name: String, index: int) -> String:
	return base_name if index == 0 else "%s%d" % [base_name, index + 1]


func _indexed_display_name(base_name: String, index: int) -> String:
	return base_name if index == 0 else "%s %d" % [base_name, index + 1]


func _available_child_name(root: Node, preferred_name: String) -> String:
	if root == null or root.get_node_or_null(preferred_name) == null:
		return preferred_name
	var index := 2
	var candidate := "%s%d" % [preferred_name, index]
	while root.get_node_or_null(candidate) != null:
		index += 1
		candidate = "%s%d" % [preferred_name, index]
	return candidate


func _trim_generated_children(root: Node, base_name: String, kept_count: int) -> void:
	if root == null:
		return
	var generated_children: Array[Node] = []
	for child in root.get_children():
		var child_index := _generated_child_index(str(child.name), base_name)
		if child_index >= 0 and bool(child.get_meta(META_GENERATED, false)):
			generated_children.append(child)
	for child_index in range(generated_children.size()):
		if child_index < kept_count:
			continue
		var child := generated_children[child_index]
		root.remove_child(child)
		child.queue_free()


func _generated_child_index(child_name: String, base_name: String) -> int:
	if child_name == base_name:
		return 0
	if not child_name.begins_with(base_name):
		return -1
	var suffix := child_name.substr(base_name.length())
	if suffix.is_empty() or not suffix.is_valid_int():
		return -1
	var ordinal := int(suffix)
	return ordinal - 1 if ordinal >= 2 else -1


func _is_generated_staff(actor: Node) -> bool:
	return actor != null and bool(actor.get_meta(META_GENERATED, false))


func _apply_role_suffix(actor: Node, role: String) -> void:
	if actor == null or not _has_property(actor, "member_name"):
		return
	var label := "warden" if role == "warden" else "guard"
	var actor_display_name := _strip_role_suffix(str(actor.get("member_name"))).strip_edges()
	if actor_display_name.is_empty():
		actor_display_name = _display_name_for_role(role, 0)
	actor.set("member_name", "%s (%s)" % [actor_display_name, label])
	if not Engine.is_editor_hint() and actor.is_inside_tree() and actor.has_method("refresh_nameplate"):
		actor.call("refresh_nameplate")


func _strip_role_suffix(staff_display_name: String) -> String:
	var result := staff_display_name.strip_edges()
	var suffix_start := result.rfind(" (")
	if suffix_start >= 0 and result.ends_with(")"):
		return result.substr(0, suffix_start).strip_edges()
	return result


func _apply_population_generation_to_actor(actor: Node, role: String, index: int) -> void:
	if actor == null or Engine.is_editor_hint() or not _is_generated_staff(actor):
		return
	var seed_key := "%s:%s:%d:%s" % [_get_staff_id_prefix(), role, index, str(actor.name)]
	var appearance_profile := _get_effective_population_appearance_profile()
	if appearance_profile != null and appearance_profile.has_method("apply_to_actor"):
		appearance_profile.call("apply_to_actor", actor, _make_staff_rng("appearance:%s" % seed_key), true)
	var name_profile := _get_effective_population_name_profile()
	if name_profile != null and name_profile.has_method("generate_name") and _has_property(actor, "member_name"):
		var appearance = actor.get("appearance_data")
		# appearance_data may be unset at creation; body type 0 is the neutral seed.
		var body_type := int(appearance.visual_body_type) if appearance != null else 0
		var generated_name := str(name_profile.call("generate_name", body_type, _make_staff_rng("name:%s" % seed_key), _used_staff_names(actor))).strip_edges()
		if not generated_name.is_empty():
			actor.set("member_name", generated_name)
			_apply_role_suffix(actor, role)


func _apply_staff_skills(actor: Node, role: String, index: int) -> void:
	if actor == null or Engine.is_editor_hint() or not actor.has_method("get_skill_level") or not actor.has_method("set_skill_level"):
		return
	var perception_range := WARDEN_PERCEPTION_RANGE if role == "warden" else GUARD_PERCEPTION_RANGE
	var rng := _make_staff_rng("skill:%s:%d:%s" % [role, index, str(actor.name)])
	actor.call("set_skill_level", SkillRules.ATTRIBUTE_PERCEPTION, _roll_center_biased_level(perception_range.x, perception_range.y, rng))


func _get_effective_population_appearance_profile() -> Resource:
	if population_appearance_profile != null:
		return population_appearance_profile
	var settlement := _get_ancestor_settlement()
	return _find_population_appearance_profile(settlement) if settlement != null else null


func _get_effective_population_name_profile() -> Resource:
	if population_name_profile != null:
		return population_name_profile
	var definition := _get_ancestor_settlement_definition()
	if definition != null and definition.has_method("get_population_name_profile"):
		return definition.call("get_population_name_profile") as Resource
	return definition.get("population_name_profile") as Resource if definition != null and _has_property(definition, "population_name_profile") else null


func _find_population_appearance_profile(root: Node) -> Resource:
	if root == null:
		return null
	if _has_property(root, "population_appearance_profile"):
		var profile := root.get("population_appearance_profile") as Resource
		if profile != null:
			return profile
	for child in root.get_children():
		var profile := _find_population_appearance_profile(child)
		if profile != null:
			return profile
	return null


func _used_staff_names(excluded_staff: Node = null) -> Dictionary:
	var names := {}
	var root := get_node_or_null(staff_root_path)
	if root == null:
		return names
	for child in root.get_children():
		if child == excluded_staff or not _has_property(child, "member_name"):
			continue
		var staff_display_name := _strip_role_suffix(str(child.get("member_name"))).strip_edges()
		if not staff_display_name.is_empty():
			names[staff_display_name.to_lower()] = true
	return names


func _make_staff_rng(seed_key: String) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = max(1, absi(seed_key.hash()))
	return rng


func _roll_center_biased_level(minimum: int, maximum: int, rng: RandomNumberGenerator) -> int:
	var low := mini(minimum, maximum)
	var high := maxi(minimum, maximum)
	if low == high:
		return low
	var t := (rng.randf() + rng.randf()) * 0.5
	return clampi(int(round(lerpf(float(low), float(high), t))), low, high)


func _get_staff_id_prefix() -> String:
	if not staff_stable_id_prefix.strip_edges().is_empty():
		return staff_stable_id_prefix
	return "npc.%s" % get_facility_id()


func _get_staff_squad_name() -> String:
	if not staff_squad_name.strip_edges().is_empty():
		return staff_squad_name
	var settlement := _get_ancestor_settlement()
	return str(settlement.name) if settlement != null else get_facility_id()


func _get_effective_owner_faction_id() -> String:
	if not owner_faction_id.strip_edges().is_empty():
		return owner_faction_id
	var definition := _get_ancestor_settlement_definition()
	if definition != null and not Engine.is_editor_hint() and definition.has_method("get_faction_id"):
		return str(definition.call("get_faction_id"))
	return _settlement_definition_faction_id(definition)


func _settlement_definition_faction_id(definition: Resource) -> String:
	if definition == null or not _has_property(definition, "faction_definition"):
		return ""
	return _resource_definition_id(definition.get("faction_definition") as Resource)


func _resource_definition_id(definition: Resource) -> String:
	if definition == null:
		return ""
	if not Engine.is_editor_hint() and definition.has_method("get_id"):
		return str(definition.call("get_id"))
	if _has_property(definition, "settlement_id") and not str(definition.get("settlement_id")).strip_edges().is_empty():
		return str(definition.get("settlement_id"))
	if _has_property(definition, "faction_id") and not str(definition.get("faction_id")).strip_edges().is_empty():
		return str(definition.get("faction_id"))
	return str(definition.get("display_name")) if _has_property(definition, "display_name") else ""


func _should_defer_staff_to_settlement_population() -> bool:
	if Engine.is_editor_hint():
		return false
	var settlement := _get_ancestor_settlement()
	return settlement != null and _has_population_spawner(settlement)


func _has_population_spawner(root: Node) -> bool:
	if root == null:
		return false
	if root.is_in_group("population_spawner") or root.has_method("resync_population_realization"):
		return true
	for child in root.get_children():
		if _has_population_spawner(child):
			return true
	return false


func _get_ancestor_settlement() -> Node:
	var current := get_parent()
	while current != null:
		if current is SettlementAnchor:
			return current
		current = current.get_parent()
	return null


func _get_ancestor_settlement_definition() -> Resource:
	var settlement := _get_ancestor_settlement()
	return settlement.get("settlement_definition") as Resource if settlement != null and _has_property(settlement, "settlement_definition") else null


func _get_ancestor_settlement_id() -> String:
	var definition := _get_ancestor_settlement_definition()
	var definition_id := _resource_definition_id(definition)
	if not definition_id.is_empty():
		return _to_snake_id(definition_id)
	var settlement := _get_ancestor_settlement()
	return _to_snake_id(settlement.name) if settlement != null else ""


func _is_actor_alive(actor: Node) -> bool:
	if actor == null or not is_instance_valid(actor):
		return false
	if _has_property(actor, "life_state"):
		return int(actor.get("life_state")) == NpcRules.LifeState.ALIVE
	return true


func _actor_key(actor: Node) -> String:
	if actor == null:
		return ""
	if _has_property(actor, "stable_id"):
		var stable_id := str(actor.get("stable_id")).strip_edges()
		if not stable_id.is_empty():
			return stable_id
	return str(actor.get_path()) if actor.is_inside_tree() else str(actor.get_instance_id())


func _add_basic_humanoid_children(actor: Node) -> void:
	if actor.get_node_or_null("CollisionShape3D") == null:
		var collision := CollisionShape3D.new()
		collision.name = "CollisionShape3D"
		collision.transform = Transform3D(Basis(), Vector3(0.0, 0.95, 0.0))
		var capsule_shape := CapsuleShape3D.new()
		capsule_shape.radius = 0.45
		capsule_shape.height = 1.1
		collision.shape = capsule_shape
		actor.add_child(collision)
	if actor.get_node_or_null("BodyMesh") == null:
		var body := MeshInstance3D.new()
		body.name = "BodyMesh"
		body.transform = Transform3D(Basis(), Vector3(0.0, 0.95, 0.0))
		var capsule_mesh := CapsuleMesh.new()
		capsule_mesh.radius = 0.45
		body.mesh = capsule_mesh
		actor.add_child(body)


func _to_snake_id(value: String) -> String:
	var result := ""
	var previous_was_separator := true
	for index in range(value.length()):
		var character := value.substr(index, 1)
		var lower := character.to_lower()
		var is_upper := character >= "A" and character <= "Z"
		var is_alnum := (lower >= "a" and lower <= "z") or (character >= "0" and character <= "9")
		if is_alnum:
			if is_upper and not previous_was_separator and not result.ends_with("_"):
				result += "_"
			result += lower
			previous_was_separator = false
		elif not previous_was_separator:
			result += "_"
			previous_was_separator = true
	return result.trim_suffix("_")


func _has_property(target: Object, property_name: String) -> bool:
	if target == null:
		return false
	for property in target.get_property_list():
		if str(property.get("name", "")) == property_name:
			return true
	return false


func _set_editor_owner_recursive(node: Node) -> void:
	_set_editor_owner(node)
	for child in node.get_children():
		_set_editor_owner_recursive(child)
