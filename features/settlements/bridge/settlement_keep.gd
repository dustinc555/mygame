@tool
@icon("res://addons/world_authoring/icons/facility_keep.svg")
extends "res://features/settlements/bridge/settlement_facility_instance.gd"

class_name SettlementKeep

const KEEP_FUNCTION = preload("res://features/world_sim/resources/facility_functions/keep.tres")
const RULER_CONVERSATION = preload("res://features/conversation/resources/town_ruler.tres")
const FACILITY_GUARD_POST_SCRIPT = preload("res://features/settlements/bridge/venues/facility_guard_post.gd")

const STAFF_ROLE_OWNER_GROUP := "settlement_staff_role_owner"
const META_SETTLEMENT_ROLE := "settlement_staff_role"
const META_SETTLEMENT_ROLE_INDEX := "settlement_staff_role_index"
const META_SETTLEMENT_SLOT_ID := "settlement_staff_slot_id"

@export var ruler_title := "Ruler"
@export var ruler_name := ""
@export var guard_name := "Keep Guard"
@export var staff_stable_id_prefix := ""
@export var staff_squad_name := ""
@export var sync_staff_from_owner := true

var _ruler_workstation: Node3D
var _ruler_seats: Array[Node] = []
var _guard_posts: Array[Node] = []


func _ready() -> void:
	add_to_group(STAFF_ROLE_OWNER_GROUP)
	_apply_keep_defaults()
	super._ready()
	refresh_facility_capabilities()
	if not Engine.is_editor_hint():
		sync_property_ownership()


func _repair_authoring_tree() -> void:
	_apply_keep_defaults()
	# Keep composition is authored. Missing furniture is a valid empty state;
	# repair must never generate functional nodes or placeholder staff.
	if not Engine.is_editor_hint() and is_inside_tree():
		sync_property_ownership()


func refresh_facility_capabilities() -> void:
	_ruler_workstation = null
	_ruler_seats.clear()
	_guard_posts.clear()
	var furniture := get_node_or_null("Furniture")
	if furniture != null:
		_collect_facility_capabilities(furniture)
	var guard_posts := get_node_or_null("GuardPosts")
	if guard_posts != null:
		_collect_facility_capabilities(guard_posts)
	if not Engine.is_editor_hint():
		sync_property_ownership()


func _collect_facility_capabilities(node: Node) -> void:
	if node != self and node is WorldActor:
		return
	if node != self:
		if _ruler_workstation == null and node is Node3D and _supports_role(node, "ruler") and node.has_method("get_staff_stand_position") and node.has_method("get_customer_position"):
			_ruler_workstation = node as Node3D
		if _supports_role(node, "ruler") and node.has_method("claim_sitter") and node.has_method("get_seat_position"):
			_ruler_seats.append(node)
		if node.get_script() == FACILITY_GUARD_POST_SCRIPT or _is_guard_post_capability(node):
			_guard_posts.append(node)
	for child in node.get_children():
		_collect_facility_capabilities(child)


func _supports_role(node: Node, role_id: String) -> bool:
	return node != null and node.has_method("supports_facility_role") and bool(node.call("supports_facility_role", role_id))


func _is_guard_post_capability(node: Node) -> bool:
	return node != null \
		and node.has_method("get_work_position") \
		and node.has_method("claim_worker") \
		and node.has_method("release_worker") \
		and node.has_method("is_available_for") \
		and node.has_method("is_worker_at_post")


func get_ruler_workstation() -> Node3D:
	return _ruler_workstation if _ruler_workstation != null and is_instance_valid(_ruler_workstation) else null


func get_ruler_idle_seat() -> Node:
	for seat in _ruler_seats:
		if seat != null and is_instance_valid(seat):
			return seat
	return null


func get_ruler_seats() -> Array[Node]:
	var seats: Array[Node] = []
	for seat in _ruler_seats:
		if seat != null and is_instance_valid(seat):
			seats.append(seat)
	return seats


func get_guard_posts() -> Array[Node]:
	var posts: Array[Node] = []
	for post in _guard_posts:
		if post != null and is_instance_valid(post):
			posts.append(post)
	return posts


func get_available_guard_post(worker: WorldActor, excluded_post = null):
	for post in get_guard_posts():
		if post == excluded_post:
			continue
		if not post.has_method("is_available_for") or bool(post.call("is_available_for", worker)):
			return post
	return null


func get_facility_id() -> String:
	if not facility_id.strip_edges().is_empty():
		return facility_id
	var settlement_id := _get_ancestor_settlement_id()
	var local_id := _to_snake_id(name)
	return local_id if settlement_id.is_empty() else "%s.%s" % [settlement_id, local_id]


func get_facility_record(settlement_id := "") -> Dictionary:
	var record := super.get_facility_record(settlement_id)
	record["facility_id"] = get_facility_id()
	record["owner_faction_id"] = get_property_owner_faction()
	record["ruler_title"] = ruler_title
	record["ruler_workstation_count"] = 1 if get_ruler_workstation() != null else 0
	record["ruler_seat_count"] = get_ruler_seats().size()
	record["ruler_count"] = 1 if _is_actor_alive(get_ruler_actor()) else 0
	record["guard_count"] = get_guard_actors().size()
	record["guard_post_count"] = get_guard_posts().size()
	return record


func get_property_owner_character() -> HumanoidCharacter:
	var ruler := get_ruler_actor() as HumanoidCharacter
	return ruler if _is_actor_alive(ruler) else null


func get_property_owner_role_id() -> String:
	return "ruler"


func get_property_owner_faction() -> String:
	return _get_effective_owner_faction_id()


func sync_property_ownership() -> void:
	var ruler := get_property_owner_character()
	_stamp_property_ownership(self, ruler, get_property_owner_faction())
	if ruler == null:
		_clear_property_owner_character(self)


func _clear_property_owner_character(node: Node) -> void:
	if node != self and node is WorldActor:
		return
	if node != self and _has_property(node, "owner_character_path"):
		node.set("owner_character_path", NodePath(""))
	for child in node.get_children():
		_clear_property_owner_character(child)


func configure_settlement_assignment_actor(actor: Node, slot_id: String, slot_record: Dictionary) -> void:
	super.configure_settlement_assignment_actor(actor, slot_id, slot_record)
	var role := str(slot_record.get("role_id", "")).strip_edges().to_lower()
	var role_index: int = max(0, int(slot_record.get("role_index", 0)))
	var staff_root := get_node_or_null(staff_root_path)
	if actor == null or staff_root == null:
		return
	if role not in ["ruler", "guard"]:
		return
	actor.name = _indexed_name("Ruler" if role == "ruler" else "Guard", role_index)
	_prepare_staff_actor(actor, role, role_index, slot_id, slot_record)
	if role == "ruler" and not bool(slot_record.get("preserve_durable_transform", false)):
		_seat_ruler_at_idle.call_deferred()
		sync_property_ownership.call_deferred()


func _prepare_staff_actor(actor: Node, role: String, role_index: int, slot_id: String, slot_record: Dictionary) -> void:
	if actor == null:
		return
	actor.set_meta(META_SETTLEMENT_ROLE, role)
	actor.set_meta(META_SETTLEMENT_ROLE_INDEX, role_index)
	actor.set_meta(META_SETTLEMENT_SLOT_ID, slot_id)
	actor.set_meta("settlement_actor_category", "staff")
	if _has_property(actor, "member_name") and str(actor.get("member_name")).strip_edges().is_empty():
		actor.set("member_name", str(slot_record.get("display_name", _display_name_for_role(role, role_index))))
	if role == "ruler" and _has_property(actor, "conversation_definition"):
		actor.set("conversation_definition", RULER_CONVERSATION)
	var owner_faction := get_property_owner_faction()
	if sync_staff_from_owner and not owner_faction.is_empty() and _has_property(actor, "faction_name"):
		actor.set("faction_name", owner_faction)
	if not staff_squad_name.is_empty() and _has_property(actor, "squad_name"):
		actor.set("squad_name", staff_squad_name)
	_apply_authority_group(actor, role)
	_position_staff_at_idle(actor, role, role_index)
	if actor.has_method("refresh_nameplate"):
		actor.call("refresh_nameplate")


func _position_staff_at_idle(actor: Node, role: String, role_index: int) -> void:
	if not (actor is Node3D):
		return
	var target: Node3D
	if role == "ruler":
		target = get_ruler_idle_seat() as Node3D
	else:
		var posts := get_guard_posts()
		target = posts[role_index % posts.size()] as Node3D if not posts.is_empty() else null
	if target != null:
		(actor as Node3D).global_position = target.global_position


func _seat_ruler_at_idle() -> void:
	if Engine.is_editor_hint() or not is_inside_tree():
		return
	var ruler := get_ruler_actor() as HumanoidCharacter
	var seat := get_ruler_idle_seat()
	if ruler == null or seat == null:
		return
	var interaction = ruler.get_interaction()
	if interaction != null:
		interaction.sit_at_seat_immediately(seat)


func get_ruler_actor() -> Node:
	return _find_actor_by_slot_id(get_role_slot_id("ruler", 0))


func get_guard_actors() -> Array[Node]:
	var guards: Array[Node] = []
	var staff_root := get_node_or_null(staff_root_path)
	if staff_root == null:
		return guards
	for child in staff_root.get_children():
		if str(child.get_meta(META_SETTLEMENT_ROLE, "")) == "guard" and _is_actor_alive(child):
			guards.append(child)
	return guards


func _find_actor_by_slot_id(slot_id: String) -> Node:
	var staff_root := get_node_or_null(staff_root_path)
	if staff_root == null:
		return null
	for child in staff_root.get_children():
		if str(child.get_meta(META_SETTLEMENT_SLOT_ID, "")) == slot_id:
			return child
	return null


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


func _apply_authority_group(staff: Node, role: String) -> void:
	if staff.has_method("set_settlement_authority"):
		staff.call("set_settlement_authority", true)
	if staff.has_method("set_private_security"):
		staff.call("set_private_security", false)
	if staff.has_method("set_faction_soldier"):
		staff.call("set_faction_soldier", role == "guard")


func _get_effective_owner_faction_id() -> String:
	return super.get_property_owner_faction()


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
	var definition_id := _resource_definition_id(_get_ancestor_settlement_definition())
	if not definition_id.is_empty():
		return _to_snake_id(definition_id)
	var settlement := _get_ancestor_settlement()
	return _to_snake_id(settlement.name) if settlement != null else ""


func _resource_definition_id(definition: Resource) -> String:
	if definition == null:
		return ""
	if definition.has_method("get_id"):
		return str(definition.call("get_id"))
	for property_name in ["settlement_id", "faction_id", "display_name"]:
		if _has_property(definition, property_name):
			var value := str(definition.get(property_name)).strip_edges()
			if not value.is_empty():
				return value
	return ""


func _ruler_display_name() -> String:
	return ruler_name.strip_edges() if not ruler_name.strip_edges().is_empty() else ruler_title.strip_edges()


func _display_name_for_role(role: String, role_index: int) -> String:
	return _ruler_display_name() if role == "ruler" else _indexed_display_name(guard_name, role_index)


func _get_staff_id_prefix() -> String:
	return staff_stable_id_prefix if not staff_stable_id_prefix.is_empty() else "npc.%s" % get_facility_id()


func _is_actor_alive(actor: Node) -> bool:
	if actor == null or not is_instance_valid(actor):
		return false
	return int(actor.get("life_state")) == NpcRules.LifeState.ALIVE if _has_property(actor, "life_state") else true


func _indexed_name(base_name: String, index: int) -> String:
	return base_name if index == 0 else "%s%d" % [base_name, index + 1]


func _indexed_display_name(base_name: String, index: int) -> String:
	return base_name if index == 0 else "%s %d" % [base_name, index + 1]


func _to_snake_id(value: String) -> String:
	var result := ""
	for character in value.to_lower():
		result += character if character.is_valid_identifier() or character.is_valid_int() else "_"
	while result.contains("__"):
		result = result.replace("__", "_")
	return result.trim_prefix("_").trim_suffix("_")


func _has_property(target: Object, property_name: String) -> bool:
	if target == null:
		return false
	for property in target.get_property_list():
		if str(property.get("name", "")) == property_name:
			return true
	return false
