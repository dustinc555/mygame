@tool
extends "res://features/settlements/bridge/settlement_facility_instance.gd"

class_name SettlementKeep

const KEEP_LAYOUT_VERSION := 1
const SELECTION_RING_VISUAL = preload("res://features/actors/projection/selection_ring_visual.gd")
const KEEP_FUNCTION = preload("res://features/world_sim/resources/facility_functions/keep.tres")
const DEFAULT_BUILDING_SCENE = preload("res://features/world/projection/buildings/settlement_keep_building.tscn")
const PLANNING_TABLE_SCENE = preload("res://features/world/projection/props/keep/planning_table.tscn")
const MAYOR_CHAIR_SCENE = preload("res://features/world/projection/props/keep/mayor_chair.tscn")
const RAIDER_CHAIR_SCENE = preload("res://features/world/projection/props/keep/raider_chair.tscn")
const RULER_CONVERSATION = preload("res://features/conversation/resources/town_ruler.tres")
const FACTION_HUMANOID_SCRIPT = preload("res://features/actors/projection/humanoid/faction_humanoid.gd")
const BAR_GUARD_POST_SCRIPT = preload("res://features/settlements/bridge/venues/bar_guard_post.gd")
const BANDAGE_ITEM = preload("res://features/inventory/resources/items/bandage.tres")
const HATCHET_ITEM = preload("res://features/inventory/resources/items/hatchet.tres")
const ROUND_SHIELD_ITEM = preload("res://features/inventory/resources/items/round_shield.tres")
const META_GENERATED := "keep_generated"
const META_ROLE := "keep_role"
const META_INDEX := "keep_index"
const META_LAYOUT_VERSION := "keep_layout_version"
const META_LAST_DEFAULT_TRANSFORM := "keep_last_default_transform"
const META_LAYOUT_CUSTOM := "keep_layout_custom"
const META_CHAIR_STYLE := "keep_chair_style"
const META_SETTLEMENT_ROLE := "settlement_staff_role"
const META_SETTLEMENT_ROLE_INDEX := "settlement_staff_role_index"
const META_SETTLEMENT_SLOT_ID := "settlement_staff_slot_id"
const STAFF_ROLE_OWNER_GROUP := "settlement_staff_role_owner"
const DEFAULT_REPLACEMENT_DELAY_DAYS := 7.0
const STAFF_PERCEPTION_RANGE := Vector2i(5, 12)
const GUARD_PERCEPTION_RANGE := Vector2i(14, 24)
const ELITE_MAYOR_GUARD_PERCEPTION_RANGE := Vector2i(90, 100)

@export var furniture_root_path: NodePath = NodePath("Furniture")
@export var guard_posts_root_path: NodePath = NodePath("GuardPosts")
@export var auto_create_default_building := true:
	set(value):
		auto_create_default_building = value
		_repair_authoring_tree()
@export var auto_create_planning_table := true:
	set(value):
		auto_create_planning_table = value
		_repair_authoring_tree()
@export var auto_create_ruler_chair := true:
	set(value):
		auto_create_ruler_chair = value
		_repair_authoring_tree()
@export var population_appearance_profile: Resource:
	set(value):
		population_appearance_profile = value
		_repair_authoring_tree()
@export var population_name_profile: Resource:
	set(value):
		population_name_profile = value
		_repair_authoring_tree()
@export var sync_default_layout := true:
	set(value):
		sync_default_layout = value
		_repair_authoring_tree()
@export var ruler_title := "Ruler"
@export var ruler_name := ""
@export_enum("mayor", "raider") var ruler_chair_style := "mayor":
	set(value):
		ruler_chair_style = str(value)
		_repair_authoring_tree()
@export var ruler_actor_path: NodePath:
	set(value):
		ruler_actor_path = value
		_repair_authoring_tree()
@export_range(0, 12, 1) var guard_count := 2:
	set(value):
		guard_count = clampi(int(value), 0, 12)
		_repair_authoring_tree()
@export_range(0, 12, 1) var guard_post_count := 0:
	set(value):
		guard_post_count = clampi(int(value), 0, 12)
		_repair_authoring_tree()
@export var guard_name := "Keep Guard"
@export var assigned_guard_paths: Array[NodePath] = []:
	set(value):
		assigned_guard_paths = value
		_repair_authoring_tree()
@export var staff_stable_id_prefix := ""
@export var staff_squad_name := ""
@export var sync_staff_from_owner := true

var _guard_post_by_actor_id: Dictionary = {}


func _ready() -> void:
	add_to_group(STAFF_ROLE_OWNER_GROUP)
	_repair_authoring_tree()
	super._ready()
	call_deferred("_seat_ruler_in_chair")


func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		return
	_process_guard_staff()


func _repair_authoring_tree() -> void:
	_apply_keep_defaults()
	if not is_inside_tree() or not auto_create_standard_roots:
		return
	_apply_function_defaults()
	_ensure_root(building_root_path)
	_ensure_root(staff_root_path)
	_ensure_root(furniture_root_path)
	_ensure_root(guard_posts_root_path)
	_ensure_default_building()
	_ensure_planning_table()
	_ensure_ruler_chair()
	_ensure_guard_posts()
	_ensure_staff()
	if not Engine.is_editor_hint():
		call_deferred("_seat_ruler_in_chair")


func get_facility_id() -> String:
	if not facility_id.strip_edges().is_empty():
		return facility_id
	var settlement_id := _get_ancestor_settlement_id()
	var local_id := _to_snake_id(name)
	return local_id if settlement_id.is_empty() else "%s.%s" % [settlement_id, local_id]


func get_facility_record(settlement_id := "") -> Dictionary:
	var record := super.get_facility_record(settlement_id)
	record["facility_id"] = get_facility_id()
	record["ruler_title"] = ruler_title
	record["planning_table_count"] = 1 if get_planning_table() != null else 0
	record["ruler_count"] = 1 if get_ruler_actor() != null else 0
	record["guard_count"] = get_guard_actors().size()
	record["guard_post_count"] = get_guard_posts().size()
	return record


func get_settlement_staff_slots() -> Array[Dictionary]:
	var slots: Array[Dictionary] = []
	_append_staff_slot(slots, "ruler", 0, get_ruler_actor(), _ruler_display_name(), "settlement_leader")
	for index in range(guard_count):
		_append_staff_slot(slots, "guard", index, _get_guard_actor_for_slot(index), _indexed_display_name(guard_name, index), "settlement_authority")
	return slots


func fill_settlement_staff_slot(slot_id: String, slot_record: Dictionary) -> Node:
	var role := str(slot_record.get("role_id", "")).strip_edges().to_lower()
	var role_index: int = max(0, int(slot_record.get("role_index", 0)))
	if role.is_empty():
		role = _role_from_slot_id(slot_id)
	var existing := get_ruler_actor() if role == "ruler" else _get_guard_actor_for_slot(role_index)
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
			_prepare_claimed_resident_for_role(actor, role, role_index)
		else:
			actor = _create_generated_staff_for_role(role, role_index, staff_root)
		if actor == null:
			return null
		SettlementFacility.adopt_staff_record(actor, worker_actor_id, slot_id, staff_root)
	else:
		actor = _claim_available_resident_for_role(role, role_index, staff_root)
		if actor == null:
			if _should_defer_staff_to_settlement_population():
				return null
			actor = _create_generated_staff_for_role(role, role_index, staff_root)
		else:
			_prepare_claimed_resident_for_role(actor, role, role_index)
		if actor == null:
			return null
	if role == "ruler":
		call_deferred("_seat_ruler_in_chair")
	return actor


func _append_staff_slot(slots: Array[Dictionary], role: String, role_index: int, actor: Node, staff_display_name: String, authority_scope: String) -> void:
	var actor_alive := _is_actor_alive(actor)
	var slot := {
		"slot_id": _staff_slot_id(role, role_index),
		"role_id": role,
		"role_index": role_index,
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


func get_planning_table() -> Node:
	return get_node_or_null("Furniture/PlanningTable")


func get_ruler_chair() -> Node:
	return get_node_or_null("Furniture/RulerChair")


func get_ruler_actor() -> Node:
	var assigned := _get_assigned_actor(ruler_actor_path)
	return assigned if assigned != null else get_node_or_null("Staff/Ruler")


func get_guard_actors() -> Array[Node]:
	var guards := _get_assigned_actors(assigned_guard_paths)
	var staff_root := get_node_or_null(staff_root_path)
	if staff_root == null:
		return guards
	for child in staff_root.get_children():
		if _generated_child_index(str(child.name), "Guard") >= 0 and child is HumanoidCharacter and _is_actor_alive(child) and not guards.has(child):
			guards.append(child)
	return guards


func _get_guard_actor_for_slot(role_index: int) -> Node:
	var slot_id := _staff_slot_id("guard", role_index)
	var by_slot := _find_role_actor_by_slot_id(slot_id)
	if by_slot != null:
		return by_slot
	if role_index < assigned_guard_paths.size():
		var assigned := _get_assigned_actor(assigned_guard_paths[role_index])
		if assigned != null:
			return assigned
	var generated_index := role_index - assigned_guard_paths.size()
	return get_node_or_null("%s/%s" % [str(staff_root_path), _indexed_name("Guard", generated_index)])


func _find_role_actor_by_slot_id(slot_id: String) -> Node:
	for actor in _all_potential_role_actors():
		if actor != null and str(actor.get_meta(META_SETTLEMENT_SLOT_ID, "")) == slot_id:
			return actor
	return null


func _all_potential_role_actors() -> Array[Node]:
	var actors: Array[Node] = []
	var ruler := _get_assigned_actor(ruler_actor_path)
	if ruler != null:
		actors.append(ruler)
	for actor in _get_assigned_actors_raw(assigned_guard_paths):
		if not actors.has(actor):
			actors.append(actor)
	var staff_root := get_node_or_null(staff_root_path)
	if staff_root != null:
		for child in staff_root.get_children():
			if child is HumanoidCharacter and not actors.has(child):
				actors.append(child)
	return actors


func _claim_available_resident_for_role(role: String, _role_index: int, staff_root: Node) -> Node:
	var settlement := _get_ancestor_settlement()
	if settlement == null or staff_root == null:
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
		candidate.name = _available_child_name(staff_root, "Ruler" if role == "ruler" else "Guard")
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


func _prepare_claimed_resident_for_role(actor: Node, role: String, role_index: int) -> void:
	if actor == null:
		return
	actor.set_script(FACTION_HUMANOID_SCRIPT)
	actor.set_meta(META_GENERATED, true)
	_apply_staff_role_defaults(actor, _display_name_for_role(role, role_index), _color_for_role(role), _conversation_for_role(role), _indexed_name(role, role_index), role_index)
	if actor is Node3D:
		(actor as Node3D).position = _local_position_for_role(role, role_index)


func _create_generated_staff_for_role(role: String, role_index: int, staff_root: Node) -> Node:
	var node_name := _available_child_name(staff_root, "Ruler" if role == "ruler" else "Guard")
	return _ensure_staff_member(staff_root, node_name, _display_name_for_role(role, role_index), _color_for_role(role), _local_position_for_role(role, role_index), _conversation_for_role(role), _indexed_name(role, role_index), role_index)


func _available_child_name(root: Node, preferred_name: String) -> String:
	if root == null or root.get_node_or_null(preferred_name) == null:
		return preferred_name
	return _next_generated_child_name(root, preferred_name)


func _display_name_for_role(role: String, role_index: int) -> String:
	return _ruler_display_name() if role == "ruler" else _indexed_display_name(guard_name, role_index)


func _color_for_role(role: String) -> Color:
	return Color(0.47, 0.36, 0.18, 1.0) if role == "ruler" else Color(0.36, 0.36, 0.42, 1.0)


func _conversation_for_role(role: String) -> Resource:
	return RULER_CONVERSATION if role == "ruler" else null


func _local_position_for_role(role: String, role_index: int) -> Vector3:
	return _ruler_local_position() if role == "ruler" else _guard_local_position(role_index)


func get_guard_posts() -> Array[Node]:
	return _children_at(guard_posts_root_path)


func get_available_guard_post(worker: HumanoidCharacter, excluded_post = null):
	var available_posts: Array = []
	for post in get_guard_posts():
		if post == null or post == excluded_post:
			continue
		if post.has_method("is_available_for") and not post.call("is_available_for", worker):
			continue
		available_posts.append(post)
	if available_posts.is_empty():
		return null
	return available_posts[0]


func _apply_keep_defaults() -> void:
	if facility_function == null:
		facility_function = KEEP_FUNCTION
	building_root_path = NodePath("BuildingSlot")
	staff_root_path = NodePath("Staff")
	service_points_root_path = NodePath("")
	storage_root_path = NodePath("")
	job_providers_root_path = NodePath("")
	activity_points_root_path = NodePath("")
	facility_type = "keep"
	if display_name.is_empty() or display_name == "Facility":
		display_name = "Settlement Keep"


func _ensure_planning_table() -> Node:
	if not auto_create_planning_table:
		return null
	var furniture := _ensure_root(furniture_root_path)
	if furniture == null:
		return null
	var default_transform := _layout_default_transform(furniture_root_path, "PlanningTable", Transform3D(Basis(), Vector3(0.0, 0.0, -1.2)))
	var table := furniture.get_node_or_null("PlanningTable")
	if table != null:
		_sync_generated_layout_node(table, "planning_table", 0, default_transform)
		return table
	table = PLANNING_TABLE_SCENE.instantiate()
	table.name = "PlanningTable"
	furniture.add_child(table)
	if table is Node3D:
		(table as Node3D).transform = default_transform
	_tag_generated_layout_node(table, "planning_table", 0, default_transform)
	_set_editor_owner_recursive(table)
	return table


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
	_set_editor_owner_recursive(building)
	return building


func _ensure_ruler_chair() -> Node:
	if not auto_create_ruler_chair:
		return null
	var furniture := _ensure_root(furniture_root_path)
	if furniture == null:
		return null
	var default_transform := _layout_default_transform(furniture_root_path, "RulerChair", _ruler_chair_transform())
	var chair := furniture.get_node_or_null("RulerChair")
	if chair != null and _generated_chair_style(chair) != ruler_chair_style:
		var current_transform := (chair as Node3D).transform if chair is Node3D else default_transform
		furniture.remove_child(chair)
		chair.queue_free()
		chair = null
		default_transform = current_transform
	if chair != null:
		_sync_generated_layout_node(chair, "ruler_chair", 0, default_transform)
		chair.set_meta(META_CHAIR_STYLE, ruler_chair_style)
		return chair
	chair = _ruler_chair_scene().instantiate()
	chair.name = "RulerChair"
	furniture.add_child(chair)
	if chair is Node3D:
		(chair as Node3D).transform = default_transform
	_tag_generated_layout_node(chair, "ruler_chair", 0, default_transform)
	chair.set_meta(META_CHAIR_STYLE, ruler_chair_style)
	_set_editor_owner_recursive(chair)
	return chair


func _ruler_chair_scene() -> PackedScene:
	return RAIDER_CHAIR_SCENE if ruler_chair_style == "raider" else MAYOR_CHAIR_SCENE


func _ensure_guard_posts() -> void:
	var root := _ensure_root(guard_posts_root_path)
	if root == null:
		return
	var effective_guard_post_count := _effective_guard_post_count()
	for guard_index in range(effective_guard_post_count):
		var post_name := _indexed_name("GuardPost", guard_index)
		var default_transform := _layout_default_transform(guard_posts_root_path, post_name, _guard_post_transform(guard_index))
		var post := root.get_node_or_null(post_name)
		if post == null:
			post = Node3D.new()
			post.name = post_name
			post.transform = default_transform
			post.set_script(BAR_GUARD_POST_SCRIPT)
			root.add_child(post)
			_set_editor_owner(post)
		elif post is Node3D:
			_sync_generated_layout_node(post, "guard", guard_index, default_transform)
		if not post.has_method("get_work_position"):
			post.set_script(BAR_GUARD_POST_SCRIPT)
		if _has_property(post, "debug_color"):
			post.set("debug_color", Color(0.35, 0.78, 1.0, 0.76))
		_tag_generated_layout_node(post, "guard", guard_index, default_transform)
		_refresh_authoring_marker(post)
	_trim_generated_children(root, "GuardPost", effective_guard_post_count)


func _ensure_staff() -> void:
	var staff_root := _ensure_root(staff_root_path)
	if staff_root == null:
		return
	var defer_staff := _should_defer_staff_to_settlement_population()
	var ruler := _get_assigned_actor(ruler_actor_path)
	var generated_ruler_count := 0
	if ruler == null and not defer_staff:
		generated_ruler_count = 1
		ruler = _ensure_staff_member(staff_root, "Ruler", _ruler_display_name(), Color(0.47, 0.36, 0.18, 1.0), _ruler_local_position(), RULER_CONVERSATION, "ruler", 0)
	elif ruler != null:
		_apply_staff_role_defaults(ruler, _ruler_display_name(), Color(0.47, 0.36, 0.18, 1.0), RULER_CONVERSATION, "ruler", 0)
	if not defer_staff:
		_trim_generated_children(staff_root, "Ruler", generated_ruler_count)

	var assigned_guards := _get_assigned_actors(assigned_guard_paths)
	for guard_index in range(assigned_guards.size()):
		_apply_staff_role_defaults(assigned_guards[guard_index], _indexed_display_name(guard_name, guard_index), Color(0.36, 0.36, 0.42, 1.0), null, _indexed_name("guard", guard_index), guard_index)
	var generated_guard_count: int = 0 if defer_staff else max(0, guard_count - assigned_guards.size())
	for guard_index in range(generated_guard_count):
		var role_index := assigned_guards.size() + guard_index
		_ensure_staff_member(staff_root, _indexed_name("Guard", guard_index), _indexed_display_name(guard_name, role_index), Color(0.36, 0.36, 0.42, 1.0), _guard_local_position(role_index), null, _indexed_name("guard", role_index), role_index)
	if not defer_staff:
		_trim_generated_children(staff_root, "Guard", generated_guard_count)


func _seat_ruler_in_chair() -> void:
	if Engine.is_editor_hint() or not is_inside_tree():
		return
	var ruler := get_ruler_actor() as HumanoidCharacter
	var chair := get_ruler_chair()
	if ruler == null or chair == null or not chair.has_method("claim_sitter"):
		return
	if ruler.has_method("sit_at_seat_immediately"):
		ruler.call("sit_at_seat_immediately", chair)


func _process_guard_staff() -> void:
	var guards := get_guard_actors()
	for guard in guards:
		var humanoid_guard := guard as HumanoidCharacter
		if humanoid_guard == null or not is_instance_valid(humanoid_guard):
			continue
		_process_guard_post_assignment(humanoid_guard)


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
	var post = get_available_guard_post(guard)
	if post == null:
		return null
	if post.has_method("claim_worker") and not post.call("claim_worker", guard):
		return null
	_guard_post_by_actor_id[guard.get_instance_id()] = post
	return post


func _ensure_staff_member(root: Node, node_name: String, member_name: String, color: Color, local_position: Vector3, conversation: Resource, role: String, role_index: int) -> Node:
	var staff := root.get_node_or_null(node_name)
	if staff != null and not _is_actor_alive(staff):
		node_name = _next_generated_child_name(root, node_name)
		staff = null
	if staff != null and not _is_generated_staff(staff):
		node_name = _next_generated_child_name(root, node_name)
		staff = null
	if staff != null:
		if staff is Node3D and _is_generated_staff(staff):
			(staff as Node3D).position = local_position
		_apply_staff_role_defaults(staff, member_name, color, conversation, role, role_index)
		staff.set_meta(META_GENERATED, true)
		return staff
	staff = CharacterBody3D.new()
	staff.name = node_name
	staff.position = local_position
	staff.set_script(FACTION_HUMANOID_SCRIPT)
	staff.set_meta(META_GENERATED, true)
	if _has_property(staff, "stable_id"):
		staff.set("stable_id", "%s.%s" % [_get_staff_id_prefix(), node_name.to_lower()])
	_apply_staff_role_defaults(staff, member_name, color, conversation, role, role_index)
	_add_basic_humanoid_children(staff)
	root.add_child(staff)
	return staff


func _apply_staff_role_defaults(staff: Node, member_name: String, color: Color, conversation: Resource, role: String, role_index: int) -> void:
	if staff == null:
		return
	var role_key := _role_key(role)
	if not role_key.is_empty():
		staff.set_meta(META_SETTLEMENT_ROLE, role_key)
		staff.set_meta(META_SETTLEMENT_ROLE_INDEX, role_index)
		staff.set_meta(META_SETTLEMENT_SLOT_ID, _staff_slot_id(role_key, role_index))
		staff.set_meta("settlement_actor_category", "staff")
	if _has_property(staff, "base_color"):
		staff.set("base_color", color)
	if _has_property(staff, "member_name") and (_is_generated_staff(staff) or str(staff.get("member_name")).strip_edges().is_empty() or str(staff.get("member_name")) == "Character"):
		staff.set("member_name", member_name)
	if conversation != null and _has_property(staff, "conversation_definition"):
		staff.set("conversation_definition", conversation)
	var owner_faction := _get_effective_owner_faction_id()
	if sync_staff_from_owner and not owner_faction.is_empty() and _has_property(staff, "faction_name"):
		staff.set("faction_name", owner_faction)
	if not staff_squad_name.is_empty() and _has_property(staff, "squad_name"):
		staff.set("squad_name", staff_squad_name)
	if role.begins_with("guard") and _has_property(staff, "base_attack_damage"):
		staff.set("base_attack_damage", 12.0)
	if _has_property(staff, "stable_id") and str(staff.get("stable_id")).strip_edges().is_empty():
		staff.set("stable_id", "%s.%s" % [_get_staff_id_prefix(), role])
	_apply_authority_group(staff, role_key)
	_apply_population_generation_to_staff(staff, role, role_index)
	_apply_guard_starting_equipment(staff, role)
	_apply_staff_role_skills(staff, role, role_index)
	_apply_role_suffix(staff, role)
	_sync_staff_actor_population_record(staff)
	if not Engine.is_editor_hint() and staff.is_inside_tree() and staff.has_method("refresh_nameplate"):
		staff.call("refresh_nameplate")


func _sync_staff_actor_population_record(actor: Node) -> void:
	if actor == null or Engine.is_editor_hint() or not actor.is_inside_tree():
		return
	var settlement_id := _get_ancestor_settlement_id()
	if settlement_id.is_empty():
		return
	var population_controller := get_tree().get_first_node_in_group("population_controller")
	if population_controller != null and population_controller.has_method("register_actor"):
		population_controller.call("register_actor", actor, settlement_id, {})


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
	if actor.get_node_or_null("SelectionRing") == null:
		var ring := MeshInstance3D.new()
		ring.name = "SelectionRing"
		ring.transform = Transform3D(Basis(), Vector3(0.0, 0.03, 0.0))
		ring.visible = false
		SELECTION_RING_VISUAL.setup_ring(ring)
		actor.add_child(ring)


func _ruler_display_name() -> String:
	var explicit_name := ruler_name.strip_edges()
	if not explicit_name.is_empty():
		return explicit_name
	var title := ruler_title.strip_edges()
	return title if not title.is_empty() else "Ruler"


func _ruler_chair_transform() -> Transform3D:
	var chair_basis := Basis()
	chair_basis.x = Vector3(0.9998561, 0.0, -0.016963685)
	chair_basis.y = Vector3(0.0, 1.0, 0.0)
	chair_basis.z = Vector3(0.016963685, 0.0, 0.9998561)
	return Transform3D(chair_basis, Vector3(0.0, 0.0, -4.35))


func _ruler_local_position() -> Vector3:
	return Vector3(0.0, 0.6, -3.55)


func _guard_post_transform(index: int) -> Transform3D:
	if index == 0:
		return Transform3D(Basis(Vector3.UP, deg_to_rad(25.0)), Vector3(-4.4, 0.05, 3.9))
	if index == 1:
		return Transform3D(Basis(Vector3.UP, deg_to_rad(-25.0)), Vector3(4.4, 0.05, 3.9))
	var side_index := index - 2
	var side := -1.0 if side_index % 2 == 0 else 1.0
	var row := int(float(side_index) / 2.0)
	return Transform3D(Basis(Vector3.UP, deg_to_rad(90.0 * -side)), Vector3(4.7 * side, 0.05, 1.4 - float(row) * 1.6))


func _effective_guard_post_count() -> int:
	return max(guard_count, guard_post_count)


func _guard_local_position(index: int) -> Vector3:
	var post_transform := _layout_default_transform(guard_posts_root_path, _indexed_name("GuardPost", index), _guard_post_transform(index))
	return Vector3(post_transform.origin.x, 0.6, post_transform.origin.z)


func _apply_population_generation_to_staff(staff: Node, role: String, role_index: int) -> void:
	if staff == null or Engine.is_editor_hint() or not _is_generated_staff(staff):
		return
	var seed_key := "%s:%s:%d:%s" % [_get_staff_id_prefix(), role, role_index, str(staff.name)]
	var appearance_profile := _get_effective_population_appearance_profile()
	if appearance_profile != null and appearance_profile.has_method("apply_to_actor"):
		appearance_profile.call("apply_to_actor", staff, _make_staff_rng("appearance:%s" % seed_key), true)
	var name_profile := _get_effective_population_name_profile()
	if name_profile != null and name_profile.has_method("generate_name") and _has_property(staff, "member_name"):
		var appearance = staff.get("appearance_data")
		var body_type := int(appearance.visual_body_type) if appearance != null else int(staff.get("visual_body_type"))
		var generated_name := str(name_profile.call("generate_name", body_type, _make_staff_rng("name:%s" % seed_key), _used_staff_names(staff))).strip_edges()
		if not generated_name.is_empty():
			staff.set("member_name", generated_name)


func _apply_staff_role_skills(staff: Node, role: String, role_index: int) -> void:
	if staff == null or Engine.is_editor_hint() or not _is_generated_staff(staff) or not staff.has_method("get_skill_level") or not staff.has_method("set_skill_level"):
		return
	var perception_range := _perception_range_for_role(role)
	var rng := _make_staff_rng("skill:%s:%d:%s" % [role, role_index, str(staff.name)])
	staff.call("set_skill_level", SkillRules.ATTRIBUTE_PERCEPTION, _roll_center_biased_level(perception_range.x, perception_range.y, rng))


func _perception_range_for_role(role: String) -> Vector2i:
	if _role_label(role) != "guard":
		return STAFF_PERCEPTION_RANGE
	return ELITE_MAYOR_GUARD_PERCEPTION_RANGE if ruler_chair_style.strip_edges().to_lower() == "mayor" else GUARD_PERCEPTION_RANGE


func _roll_center_biased_level(minimum: int, maximum: int, rng: RandomNumberGenerator) -> int:
	var low := mini(minimum, maximum)
	var high := maxi(minimum, maximum)
	if low == high:
		return low
	var t := (rng.randf() + rng.randf()) * 0.5
	return clampi(int(round(lerpf(float(low), float(high), t))), low, high)


func _apply_guard_starting_equipment(staff: Node, role: String) -> void:
	if _role_label(role) != "guard" or not _has_property(staff, "starting_equipment"):
		return
	var starting_equipment: Array = (staff.get("starting_equipment") as Array).duplicate()
	var changed := false
	for item in [BANDAGE_ITEM, HATCHET_ITEM, ROUND_SHIELD_ITEM]:
		if item == null or starting_equipment.has(item):
			continue
		var slot_name := _item_equip_slot(item)
		if not slot_name.is_empty() and _equipment_list_has_slot(starting_equipment, slot_name):
			continue
		starting_equipment.append(item)
		changed = true
		if not Engine.is_editor_hint() and not slot_name.is_empty() and staff.is_inside_tree() and staff.has_method("get_equipped_item") and staff.has_method("equip_item_to_slot") and staff.call("get_equipped_item", slot_name) == null:
			staff.call("equip_item_to_slot", item, slot_name)
	if changed:
		staff.set("starting_equipment", starting_equipment)


func _get_settlement_starting_equipment() -> Array:
	var settlement := _get_ancestor_settlement()
	if settlement == null:
		return []
	return _find_starting_equipment_for_faction(settlement, _get_effective_owner_faction_id())


func _find_starting_equipment_for_faction(root: Node, target_faction_id: String) -> Array:
	if root == null:
		return []
	if root is SettlementPopulationSpawner and _has_property(root, "starting_equipment"):
		var node_faction := str(root.get("faction_id")) if _has_property(root, "faction_id") else ""
		if target_faction_id.is_empty() or node_faction.is_empty() or node_faction == target_faction_id:
			return (root.get("starting_equipment") as Array).duplicate()
	for child in root.get_children():
		var equipment := _find_starting_equipment_for_faction(child, target_faction_id)
		if not equipment.is_empty():
			return equipment
	return []


func _equipment_list_has_slot(items: Array, slot_name: String) -> bool:
	for item in items:
		if _item_equip_slot(item) == slot_name:
			return true
	return false


func _item_equip_slot(item: Resource) -> String:
	if item == null or not _has_property(item, "equip_slot"):
		return ""
	return str(item.get("equip_slot"))


func _make_staff_rng(seed_key: String) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = max(1, absi(seed_key.hash()))
	return rng


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


func _apply_role_suffix(staff: Node, role: String) -> void:
	if staff == null or not _has_property(staff, "member_name"):
		return
	var label := _role_label(role)
	if label.is_empty():
		return
	var staff_display_name := _strip_role_suffix(str(staff.get("member_name"))).strip_edges()
	if staff_display_name.is_empty():
		staff_display_name = label.capitalize()
	staff.set("member_name", "%s (%s)" % [staff_display_name, label])


func _role_key(role: String) -> String:
	var normalized := role.strip_edges().to_lower()
	if normalized == "ruler":
		return "ruler"
	if normalized == "guard" or normalized.begins_with("guard"):
		return "guard"
	return ""


func _role_from_slot_id(slot_id: String) -> String:
	var suffix := slot_id.get_slice(".", slot_id.get_slice_count(".") - 1)
	return _role_key(suffix)


func _staff_slot_id(role: String, role_index: int) -> String:
	return "%s.%s" % [get_facility_id(), _indexed_name(role, role_index)]


func _apply_authority_group(staff: Node, role_key: String) -> void:
	if staff == null or Engine.is_editor_hint():
		return
	if staff.has_method("set_settlement_authority"):
		staff.call("set_settlement_authority", role_key == "guard" or role_key == "ruler")
	if staff.has_method("set_private_security"):
		staff.call("set_private_security", false)
	if staff.has_method("set_faction_soldier"):
		staff.call("set_faction_soldier", role_key == "guard")


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


func _role_label(role: String) -> String:
	var normalized := role.strip_edges().to_lower()
	if normalized == "ruler":
		var title := ruler_title.strip_edges()
		return title if not title.is_empty() else "ruler"
	if normalized == "guard" or normalized.begins_with("guard"):
		return "guard"
	return ""


func _strip_role_suffix(staff_display_name: String) -> String:
	var result := staff_display_name.strip_edges()
	var suffix_start := result.rfind(" (")
	if suffix_start >= 0 and result.ends_with(")"):
		return result.substr(0, suffix_start).strip_edges()
	return result


func _get_effective_population_appearance_profile() -> Resource:
	if population_appearance_profile != null:
		return population_appearance_profile
	var settlement := _get_ancestor_settlement()
	if settlement == null:
		return null
	return _find_population_appearance_profile(settlement)


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


func _should_defer_staff_to_settlement_population() -> bool:
	return not Engine.is_editor_hint() and _get_ancestor_settlement() != null


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


func _children_at(root_path: NodePath) -> Array[Node]:
	var root := get_node_or_null(root_path)
	var children: Array[Node] = []
	if root == null:
		return children
	for child in root.get_children():
		children.append(child)
	return children


func _get_assigned_actor(actor_path: NodePath) -> Node:
	if actor_path.is_empty():
		return null
	return get_node_or_null(actor_path)


func _get_assigned_actors(actor_paths: Array[NodePath]) -> Array[Node]:
	var actors: Array[Node] = []
	for actor_path in actor_paths:
		var actor := _get_assigned_actor(actor_path)
		if actor != null and _is_actor_alive(actor) and not actors.has(actor):
			actors.append(actor)
	return actors


func _get_assigned_actors_raw(actor_paths: Array[NodePath]) -> Array[Node]:
	var actors: Array[Node] = []
	for actor_path in actor_paths:
		var actor := _get_assigned_actor(actor_path)
		if actor != null and not actors.has(actor):
			actors.append(actor)
	return actors


func _indexed_name(base_name: String, index: int) -> String:
	return base_name if index == 0 else "%s%d" % [base_name, index + 1]


func _indexed_display_name(base_name: String, index: int) -> String:
	return base_name if index == 0 else "%s %d" % [base_name, index + 1]


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


func _trim_generated_children(root: Node, base_name: String, kept_count: int) -> void:
	if root == null:
		return
	var generated_children: Array[Node] = []
	for child in root.get_children():
		var child_index := _generated_child_index(str(child.name), base_name)
		if child_index >= 0 and _is_generated_child_for_trim(child, base_name):
			generated_children.append(child)
	for child_index in range(generated_children.size()):
		if child_index < kept_count:
			continue
		var child := generated_children[child_index]
		root.remove_child(child)
		child.queue_free()


func _is_generated_child(child: Node) -> bool:
	return child != null and child.has_meta(META_GENERATED) and bool(child.get_meta(META_GENERATED))


func _is_generated_staff(staff: Node) -> bool:
	if staff == null or not _has_property(staff, "stable_id"):
		return _is_generated_child(staff)
	var current_stable_id := str(staff.get("stable_id"))
	return _is_generated_child(staff) or current_stable_id.is_empty() or current_stable_id.begins_with("%s." % _get_staff_id_prefix())


func _layout_default_transform(root_path: NodePath, node_name: String, fallback: Transform3D) -> Transform3D:
	var authored: Variant = _current_scene_default_transform(root_path, node_name)
	if authored != null:
		return authored as Transform3D
	authored = _packed_scene_default_transform(root_path, node_name)
	return authored as Transform3D if authored != null else fallback


func _current_scene_default_transform(root_path: NodePath, node_name: String) -> Variant:
	var node := get_node_or_null(_layout_node_path(root_path, node_name)) as Node3D
	if node == null:
		return null
	if _is_editing_this_scene() or not _meta_bool(node, META_LAYOUT_CUSTOM, false) and not _meta_bool(node, META_GENERATED, false):
		return node.transform
	return null


func _packed_scene_default_transform(root_path: NodePath, node_name: String) -> Variant:
	var scene_path := scene_file_path
	if scene_path.is_empty():
		return null
	var scene := load(scene_path) as PackedScene
	if scene == null:
		return null
	var instance := scene.instantiate()
	var node := instance.get_node_or_null(_layout_node_path(root_path, node_name)) as Node3D
	var result = null
	if node != null:
		result = node.transform
	instance.free()
	return result


func _layout_node_path(root_path: NodePath, node_name: String) -> NodePath:
	var root_text := str(root_path)
	return NodePath(node_name if root_text.is_empty() else "%s/%s" % [root_text, node_name])


func _is_editing_this_scene() -> bool:
	if not Engine.is_editor_hint() or not is_inside_tree():
		return false
	var tree := get_tree()
	return tree != null and tree.edited_scene_root == self


func _sync_generated_layout_node(node: Node, role: String, index: int, default_transform: Transform3D) -> void:
	if node == null or not (node is Node3D) or not sync_default_layout:
		return
	var node3d := node as Node3D
	if _meta_bool(node, META_LAYOUT_CUSTOM, false):
		return
	var last_default = node.get_meta(META_LAST_DEFAULT_TRANSFORM) if node.has_meta(META_LAST_DEFAULT_TRANSFORM) else null
	if last_default is Transform3D:
		if _transforms_close(node3d.transform, default_transform):
			pass
		elif _transforms_close(node3d.transform, last_default):
			node3d.transform = default_transform
		else:
			node.set_meta(META_LAYOUT_CUSTOM, true)
			return
	elif _meta_bool(node, META_GENERATED, false) and not _transforms_close(node3d.transform, default_transform):
		node.set_meta(META_LAYOUT_CUSTOM, true)
		return
	_tag_generated_layout_node(node, role, index, default_transform)


func _tag_generated_layout_node(node: Node, role: String, index: int, default_transform: Transform3D) -> void:
	if node == null:
		return
	node.set_meta(META_GENERATED, true)
	node.set_meta(META_ROLE, role)
	node.set_meta(META_INDEX, index)
	node.set_meta(META_LAYOUT_VERSION, KEEP_LAYOUT_VERSION)
	if not _meta_bool(node, META_LAYOUT_CUSTOM, false):
		node.set_meta(META_LAST_DEFAULT_TRANSFORM, default_transform)


func _generated_chair_style(node: Node) -> String:
	if node == null:
		return ruler_chair_style
	if node.has_meta(META_CHAIR_STYLE):
		return str(node.get_meta(META_CHAIR_STYLE))
	return "raider" if str(node.name).to_lower().contains("raider") else "mayor"


func _meta_bool(node: Node, key: String, fallback: bool) -> bool:
	if node == null or not node.has_meta(key):
		return fallback
	return bool(node.get_meta(key))


func _transforms_close(left: Transform3D, right: Transform3D) -> bool:
	return left.origin.distance_to(right.origin) <= 0.001 and _basis_close(left.basis, right.basis)


func _basis_close(left: Basis, right: Basis) -> bool:
	return left.x.distance_to(right.x) <= 0.001 and left.y.distance_to(right.y) <= 0.001 and left.z.distance_to(right.z) <= 0.001


func _is_generated_child_for_trim(child: Node, base_name: String) -> bool:
	if child == null:
		return false
	if base_name in ["Ruler", "Guard"]:
		return _is_generated_staff(child)
	return not _meta_bool(child, META_LAYOUT_CUSTOM, false)


func _refresh_authoring_marker(node: Node) -> void:
	if Engine.is_editor_hint() and node != null and node.has_method("_refresh_debug_marker"):
		node.call("_refresh_debug_marker")


func _next_generated_child_name(root: Node, preferred_name: String) -> String:
	if root == null:
		return preferred_name
	var index := 2
	var candidate := "%s%d" % [preferred_name, index]
	while root.get_node_or_null(candidate) != null:
		index += 1
		candidate = "%s%d" % [preferred_name, index]
	return candidate


func _get_staff_id_prefix() -> String:
	if not staff_stable_id_prefix.is_empty():
		return staff_stable_id_prefix
	return "npc.%s" % get_facility_id()


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
