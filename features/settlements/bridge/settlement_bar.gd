@tool
@icon("res://addons/world_authoring/icons/facility_bar.svg")
extends "res://features/settlements/bridge/settlement_facility_instance.gd"

class_name SettlementBar

const BAR_LAYOUT_VERSION := 1
const SELECTION_RING_VISUAL = preload("res://features/actors/projection/selection_ring_visual.gd")
const META_GENERATED := "facility_generated"
const META_ROLE := "facility_role"
const META_INDEX := "facility_index"
const META_LAYOUT_VERSION := "facility_layout_version"
const META_LAST_DEFAULT_TRANSFORM := "facility_last_default_transform"
const META_LAYOUT_CUSTOM := "facility_layout_custom"
const META_STOCK_GENERATED := "bar_stock_generated"
const META_STOCK_GENERATED_QUANTITY := "bar_stock_generated_quantity"
const META_SETTLEMENT_ROLE := "settlement_staff_role"
const META_SETTLEMENT_ROLE_INDEX := "settlement_staff_role_index"
const META_SETTLEMENT_SLOT_ID := "settlement_staff_slot_id"
const STAFF_ROLE_OWNER_GROUP := "settlement_staff_role_owner"
const DEFAULT_REPLACEMENT_DELAY_DAYS := 7.0
const BAR_FUNCTION = preload("res://features/world_sim/resources/facility_functions/bar.tres")
const BAR_SERVICE_AREA_SCRIPT = preload("res://features/settlements/bridge/venues/bar_service_area.gd")
const MERCHANT_HUMANOID_SCRIPT = preload("res://features/actors/projection/humanoid/merchant_humanoid.gd")
const BARBER_HUMANOID_SCRIPT = preload("res://features/actors/projection/humanoid/barber_humanoid.gd")
const MERCHANT_ROLE_SCRIPT = preload("res://features/settlements/bridge/merchant_role.gd")
const JOB_PROVIDER_SCRIPT = preload("res://features/settlements/bridge/job_provider.gd")
const JOB_DEFINITION_SCRIPT = preload("res://features/settlements/resources/jobs/job_definition.gd")
const MERCHANT_PRICE_SCRIPT = preload("res://features/inventory/resources/items/merchant_price.gd")
const MERCHANT_STOCK_SCRIPT = preload("res://features/inventory/resources/items/merchant_stock.gd")
const BAR_GUARD_POST_SCRIPT = preload("res://features/settlements/bridge/venues/bar_guard_post.gd")
const BAR_SERVICE_POINT_SCRIPT = preload("res://features/settlements/bridge/venues/bar_service_point.gd")
const FACILITY_VISIT_POINT_SCRIPT = preload("res://features/settlements/bridge/facility_visit_activity_point.gd")
const BREAD_ITEM = preload("res://features/inventory/resources/items/bread.tres")
const FOOD_ITEM = preload("res://features/inventory/resources/items/food.tres")
const SILVER_ITEM = preload("res://features/inventory/resources/items/silver.tres")
const BANDAGE_ITEM = preload("res://features/inventory/resources/items/bandage.tres")
const HATCHET_ITEM = preload("res://features/inventory/resources/items/hatchet.tres")
const SHOPKEEPER_CONVERSATION = preload("res://features/conversation/resources/generic_shopkeeper.tres")
const WAITER_CONVERSATION = preload("res://features/conversation/resources/waiter_order.tres")
const BARBER_CONVERSATION = preload("res://features/conversation/resources/barber_services.tres")
const DEFAULT_BUILDING_SCENE = preload("res://features/world/projection/buildings/woodbrick_shop_medium.tscn")
const LEGACY_FURNITURE_ROOT_NAMES := ["Tables", "Stools", "Beds"]
const WAITER_POINTS_ROOT_PATH := NodePath("WaiterPoints")
const STAFF_PERCEPTION_RANGE := Vector2i(5, 12)
const GUARD_PERCEPTION_RANGE := Vector2i(14, 24)

@export var bar_service_area_path: NodePath = NodePath("BarServiceArea")
@export var guard_posts_root_path: NodePath = NodePath("GuardPosts")
@export var furniture_root_path: NodePath = NodePath("Furniture")
@export var auto_create_default_building := true
@export var population_appearance_profile: Resource:
	set(value):
		population_appearance_profile = value
		_repair_authoring_tree()
@export var population_name_profile: Resource:
	set(value):
		population_name_profile = value
		_repair_authoring_tree()
@export_group("Staff Roles")
## Facilities start empty: every role is opt-in through these fields (the
## Facility dock's staff buttons drive them). At runtime the settlement
## population fills opted-in slots with real residents.
@export var has_barkeeper := false:
	set(value):
		has_barkeeper = value
		_repair_authoring_tree()
@export var barkeeper_actor_path: NodePath:
	set(value):
		barkeeper_actor_path = value
		_repair_authoring_tree()
@export var barkeeper_name := "Barkeeper"
@export_range(0, 12, 1) var waiter_count: int = 0:
	set(value):
		waiter_count = _clamp_count(value, 0, 12)
		_repair_authoring_tree()
@export var assigned_waiter_paths: Array[NodePath] = []:
	set(value):
		assigned_waiter_paths = value
		_repair_authoring_tree()
@export var waiter_name := "Waiter"
@export_range(0, 12, 1) var guard_count: int = 0:
	set(value):
		guard_count = _clamp_count(value, 0, 12)
		_repair_authoring_tree()
@export var assigned_guard_paths: Array[NodePath] = []:
	set(value):
		assigned_guard_paths = value
		_repair_authoring_tree()
@export var guard_name := "Bar Guard"
@export var has_barber := false:
	set(value):
		has_barber = value
		_repair_authoring_tree()
@export var barber_actor_path: NodePath:
	set(value):
		barber_actor_path = value
		_repair_authoring_tree()
@export var barber_name := "Barber"
@export_group("Visitors")
@export_range(0, 24, 1) var visitor_capacity := 4:
	set(value):
		visitor_capacity = _clamp_count(value, 0, 24)
		_repair_authoring_tree()
@export_group("Advanced Points")
@export_range(0, 12, 1) var waiter_point_count: int = 0:
	set(value):
		waiter_point_count = _clamp_count(value, 0, 12)
		_repair_authoring_tree()
@export_range(0, 12, 1) var guard_post_count: int = 0:
	set(value):
		guard_post_count = _clamp_count(value, 0, 12)
		_repair_authoring_tree()
@export_range(0, 12, 1) var guard_job_slot_count: int = 0:
	set(value):
		guard_job_slot_count = _clamp_count(value, 0, 12)
		_repair_authoring_tree()
@export var sync_default_layout := true:
	set(value):
		sync_default_layout = value
		_repair_authoring_tree()
@export_group("")
@export var staff_stable_id_prefix := ""
@export var staff_squad_name := ""
@export var sync_staff_from_owner := true
@export var use_settlement_population_for_staff := true
@export_range(0, 8, 1) var beds_building_level_index := 1
@export_group("Stock")
@export_enum("parent_settlement_supply", "standalone_fallback") var stock_source := "parent_settlement_supply":
	set(value):
		stock_source = str(value)
		_repair_authoring_tree()
@export_range(0.0, 1.0, 0.01) var standalone_stock_ratio := 0.75:
	set(value):
		standalone_stock_ratio = clampf(float(value), 0.0, 1.0)
		_repair_authoring_tree()
@export_range(0, 100, 1) var max_bread_stock := 12:
	set(value):
		max_bread_stock = max(0, int(value))
		_repair_authoring_tree()
@export_range(0, 100, 1) var max_food_stock := 8:
	set(value):
		max_food_stock = max(0, int(value))
		_repair_authoring_tree()
@export_range(0, 1000, 1) var max_silver_stock := 100:
	set(value):
		max_silver_stock = max(0, int(value))
		_repair_authoring_tree()
@export_group("")


func _ready() -> void:
	add_to_group(STAFF_ROLE_OWNER_GROUP)
	_repair_authoring_tree()
	super._ready()
	if not Engine.is_editor_hint():
		_connect_service_conversation.call_deferred()
		_ensure_staff_population_records.call_deferred()


## World-init case: an authored staffer standing in the facility without a
## population record gets one minted from their live body, so the world sim
## can own them like any spawned resident.
func _ensure_staff_population_records() -> void:
	if not is_inside_tree():
		return
	var staff_root := get_node_or_null(staff_root_path)
	if staff_root == null:
		return
	var population = get_tree().get_first_node_in_group("population_controller")
	if population == null or not population.has_method("register_actor"):
		return
	for staff in staff_root.get_children():
		if not (staff is HumanoidCharacter) or not _is_actor_alive(staff):
			continue
		if not str(staff.get_meta("actor_record_id", "")).is_empty():
			continue
		var role := str(staff.get_meta(META_SETTLEMENT_ROLE, "worker"))
		population.call("register_actor", staff, "", {"role_id": role})


## Runtime wiring host for the bar's table-service chat. The venue announces the
## event via BarServiceArea.service_conversation_requested; this composition node
## (which creates the service area and sits OUTSIDE the settlement dependency
## cycle) owns the ConversationController reference. Bars spawn before core
## services register, so we connect the signal to our OWN handler here (needs only
## the always-present service area) and resolve ConversationController LAZILY at
## emit time -- matching the original per-event lookup, which fires long after
## bootstrap when a waiter actually serves a customer.
func _connect_service_conversation() -> void:
	var service_area := get_bar_service_area() as BarServiceArea
	if service_area == null:
		return
	if not service_area.service_conversation_requested.is_connected(_on_service_conversation_requested):
		service_area.service_conversation_requested.connect(_on_service_conversation_requested)


func _on_service_conversation_requested(customer: HumanoidCharacter, waiter: HumanoidCharacter) -> void:
	var conversation_controller := BootstrapContext.service(ConversationController.SERVICE_ID) as ConversationController
	if conversation_controller != null:
		conversation_controller.begin_conversation(customer, waiter)


func _repair_authoring_tree() -> void:
	_apply_bar_defaults()
	super._repair_authoring_tree()
	if not is_inside_tree() or not auto_create_standard_roots:
		return
	_ensure_root(guard_posts_root_path)
	_ensure_root(furniture_root_path)
	_ensure_bar_service_area()
	_ensure_default_building()
	_ensure_staff()
	_ensure_guard_and_service_points()
	_ensure_visitor_activity_points()
	_sync_bar_authoring()
	_sync_building_level_content()


func get_bar_service_area() -> Node:
	return get_node_or_null(bar_service_area_path)


func get_facility_id() -> String:
	if not facility_id.strip_edges().is_empty():
		return facility_id
	var settlement_id := _get_ancestor_settlement_id()
	var local_id := _to_snake_id(name)
	if settlement_id.is_empty():
		return local_id
	return "%s.%s" % [settlement_id, local_id]


func get_facility_record(settlement_id := "") -> Dictionary:
	var record := super.get_facility_record(settlement_id)
	record["facility_id"] = get_facility_id()
	record["owner_faction_id"] = _get_effective_owner_faction_id()
	return record


func can_actor_visit_facility(actor: Node) -> bool:
	if actor == null or not is_instance_valid(actor):
		return false
	if actor.has_method("is_player_party_member") and bool(actor.call("is_player_party_member")):
		return false
	if actor.has_method("get_active_job_provider") and actor.call("get_active_job_provider") != null:
		return false
	if _is_bar_role_actor(actor):
		return false
	if _is_marked_special_bar_visitor(actor):
		return false
	return _is_actor_under_settlement_resident_root(actor)


func get_settlement_staff_slots() -> Array[Dictionary]:
	var slots: Array[Dictionary] = []
	if has_barkeeper or _get_assigned_actor(barkeeper_actor_path) != null:
		_append_staff_slot(slots, "barkeeper", 0, _get_role_actor_for_slot("barkeeper", 0), "Barkeeper")
	for index in range(waiter_count):
		_append_staff_slot(slots, "waiter", index, _get_role_actor_for_slot("waiter", index), _indexed_display_name(waiter_name, index))
	for index in range(guard_count):
		_append_staff_slot(slots, "guard", index, _get_role_actor_for_slot("guard", index), _indexed_display_name(guard_name, index), "private_security")
	if has_barber:
		_append_staff_slot(slots, "barber", 0, _get_role_actor_for_slot("barber", 0), "Barber")
	return slots


func fill_settlement_staff_slot(slot_id: String, slot_record: Dictionary) -> Node:
	var role := str(slot_record.get("role_id", "")).strip_edges().to_lower()
	var role_index: int = max(0, int(slot_record.get("role_index", 0)))
	if role.is_empty():
		role = _role_from_slot_id(slot_id)
	var existing := _get_role_actor_for_slot(role, role_index)
	if _is_actor_alive(existing):
		return existing
	var staff_root := _ensure_root(staff_root_path)
	if staff_root == null:
		return null
	var worker_actor_id := str(slot_record.get("worker_actor_id", "")).strip_edges()
	var actor: Node = null
	if not worker_actor_id.is_empty():
		# Ledger-assigned worker: claim its specific live body if already realized, else build one
		# from the record. The world-sim assignment — not a scramble for any free body — decides who.
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
	if role == "barkeeper":
		_ensure_merchant_role(actor)
		_ensure_job_provider(actor)
	elif role == "barber":
		_send_barber_to_seat(actor)
	_send_actor_to_service_point(actor, role)
	_sync_bar_authoring()
	return actor


func _append_staff_slot(slots: Array[Dictionary], role: String, role_index: int, actor: Node, staff_display_name: String, authority_scope := "facility_staff") -> void:
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


func _apply_bar_defaults() -> void:
	if facility_function == null:
		facility_function = BAR_FUNCTION
	building_root_path = NodePath("BuildingSlot")
	staff_root_path = NodePath("Staff")
	service_points_root_path = WAITER_POINTS_ROOT_PATH if _effective_waiter_point_count() > 0 else NodePath("")
	storage_root_path = NodePath("")
	job_providers_root_path = NodePath("")
	activity_points_root_path = NodePath("ActivityPoints")
	facility_type = "bar"
	if display_name.is_empty() or display_name == "Facility":
		display_name = "Settlement Bar"


func _ensure_bar_service_area() -> Node:
	var service_area := get_bar_service_area()
	if service_area != null:
		return service_area
	var legacy_venue := get_node_or_null("BarVenue")
	if legacy_venue != null:
		legacy_venue.name = "BarServiceArea"
		legacy_venue.set_script(BAR_SERVICE_AREA_SCRIPT)
		return legacy_venue
	service_area = Node3D.new()
	service_area.name = "BarServiceArea"
	service_area.set_script(BAR_SERVICE_AREA_SCRIPT)
	add_child(service_area)
	_set_editor_owner(service_area)
	return service_area


func _ensure_default_building() -> void:
	if not auto_create_default_building:
		return
	var root := get_building_root()
	if root == null or root.get_child_count() > 0:
		return
	var building := DEFAULT_BUILDING_SCENE.instantiate()
	building.name = "CurrentBuilding"
	root.add_child(building)
	_set_editor_owner_recursive(building)


## Furniture is never script-generated: it is authored (or produced by the
## furnish pass) and discovered via FurnitureRules at runtime. A fresh bar
## spawns as the shell plus function points only.
func _ensure_staff() -> void:
	var staff_root := _ensure_root(staff_root_path)
	# In the editor, staff are pure configuration (role toggles + counts); no
	# placeholder bodies get generated or kept — they configure nothing and
	# clutter the scene. Bodies exist only at runtime: realized from the
	# settlement population, or generated on the spot in standalone scenes.
	var defer_staff := _should_defer_staff_to_settlement_population() or Engine.is_editor_hint()
	var trim_generated := Engine.is_editor_hint() or not _should_defer_staff_to_settlement_population()
	var barkeeper := _get_assigned_actor(barkeeper_actor_path)
	var generated_barkeeper_count := 0
	if has_barkeeper and barkeeper == null and not defer_staff:
		generated_barkeeper_count = 1
		barkeeper = _ensure_staff_member(staff_root, "Barkeeper", barkeeper_name, Color(0.58, 0.43, 0.2, 1.0), _point_local_position(_barkeeper_point_transform()), SHOPKEEPER_CONVERSATION, MERCHANT_HUMANOID_SCRIPT, "barkeeper", 0)
	if trim_generated:
		_trim_generated_children(staff_root, "Barkeeper", generated_barkeeper_count)
	if barkeeper != null:
		_apply_assigned_role_defaults(barkeeper, "barkeeper", SHOPKEEPER_CONVERSATION)
		_ensure_merchant_role(barkeeper)
		_ensure_job_provider(barkeeper)
	_sync_job_provider_jobs(barkeeper.get_node_or_null("JobProvider") if barkeeper != null else null)
	var assigned_waiters := _get_assigned_actors(assigned_waiter_paths)
	for waiter_index in range(assigned_waiters.size()):
		_apply_assigned_role_defaults(assigned_waiters[waiter_index], _indexed_name("waiter", waiter_index), WAITER_CONVERSATION)
	var generated_waiter_count: int = 0 if defer_staff else max(0, waiter_count - assigned_waiters.size())
	for waiter_index in range(generated_waiter_count):
		var role_index := assigned_waiters.size() + waiter_index
		_ensure_staff_member(staff_root, _indexed_name("Waiter", waiter_index), _indexed_display_name(waiter_name, role_index), Color(0.28, 0.47, 0.56, 1.0), _waiter_local_position(role_index), WAITER_CONVERSATION, MERCHANT_HUMANOID_SCRIPT, _indexed_name("waiter", role_index), role_index)
	if trim_generated:
		_trim_generated_children(staff_root, "Waiter", generated_waiter_count)
	var assigned_guards := _get_assigned_actors(assigned_guard_paths)
	for guard_index in range(assigned_guards.size()):
		var guard := assigned_guards[guard_index]
		_apply_assigned_role_defaults(guard, _indexed_name("guard", guard_index), null)
		if _has_property(guard, "base_attack_damage"):
			guard.set("base_attack_damage", 20.0)
	var generated_guard_count: int = 0 if defer_staff else max(0, guard_count - assigned_guards.size())
	for guard_index in range(generated_guard_count):
		var role_index := assigned_guards.size() + guard_index
		var guard := _ensure_staff_member(staff_root, _indexed_name("Guard", guard_index), _indexed_display_name(guard_name, role_index), Color(0.42, 0.42, 0.48, 1.0), _guard_local_position(role_index), null, MERCHANT_HUMANOID_SCRIPT, _indexed_name("guard", role_index), role_index)
		if _has_property(guard, "base_attack_damage"):
			guard.set("base_attack_damage", 20.0)
	if trim_generated:
		_trim_generated_children(staff_root, "Guard", generated_guard_count)
	var barber := _get_assigned_actor(barber_actor_path)
	var generated_barber_count := 0
	if has_barber and barber == null and not defer_staff:
		generated_barber_count = 1
		barber = _ensure_staff_member(staff_root, "Barber", barber_name, Color(0.54, 0.38, 0.68, 1.0), _point_local_position(_barber_idle_transform()), BARBER_CONVERSATION, BARBER_HUMANOID_SCRIPT, "barber", 0)
	if has_barber and barber != null:
		_sync_staff_member(barber, "barber")
		if _has_property(barber, "conversation_definition"):
			barber.set("conversation_definition", BARBER_CONVERSATION)
	if trim_generated:
		_trim_generated_children(staff_root, "Barber", generated_barber_count)


func _ensure_guard_and_service_points() -> void:
	var guard_posts := _ensure_root(guard_posts_root_path)
	_migrate_legacy_guard_post_names(guard_posts)
	var effective_guard_post_count := _effective_guard_post_count()
	for guard_index in range(effective_guard_post_count):
		var post_name := _guard_post_name(guard_index)
		_ensure_guard_post(guard_posts, post_name, _layout_default_transform(guard_posts_root_path, post_name, _guard_post_transform(guard_index)))
	_trim_generated_children(guard_posts, "GuardPost", effective_guard_post_count)
	var effective_waiter_point_count := _effective_waiter_point_count()
	var service_points := get_node_or_null(WAITER_POINTS_ROOT_PATH)
	if effective_waiter_point_count <= 0:
		if service_points != null:
			remove_child(service_points)
			service_points.queue_free()
		return
	service_points = _ensure_root(WAITER_POINTS_ROOT_PATH)
	for waiter_index in range(effective_waiter_point_count):
		var point_name := _waiter_point_name(waiter_index)
		_ensure_service_point(service_points, point_name, _layout_default_transform(WAITER_POINTS_ROOT_PATH, point_name, _waiter_point_transform(waiter_index)), "waiter", Color(0.0, 0.82, 0.78, 0.76))
	_trim_generated_children(service_points, "WaiterPoint", effective_waiter_point_count)
	_trim_generated_children(service_points, "BarberPoint", 0)


func _ensure_visitor_activity_points() -> void:
	var root := _ensure_root(activity_points_root_path)
	if root == null:
		return
	_trim_generated_children(root, "VisitorPoint", 0)
	var kept_visit_points := 1 if visitor_capacity > 0 else 0
	if kept_visit_points > 0:
		_ensure_facility_visit_point(root)
	_trim_generated_children(root, "FacilityVisitPoint", kept_visit_points)


func _ensure_facility_visit_point(root: Node) -> Node:
	var point_name := "FacilityVisitPoint"
	var point := root.get_node_or_null(point_name)
	if point == null:
		point = Node3D.new()
		point.name = point_name
		root.add_child(point)
		_set_editor_owner(point)
	if point.get_script() != FACILITY_VISIT_POINT_SCRIPT:
		point.set_script(FACILITY_VISIT_POINT_SCRIPT)
	var default_transform := _layout_default_transform(activity_points_root_path, point_name, _hangout_point_transform(0))
	if point is Node3D:
		_sync_generated_layout_node(point, "visitor", 0, default_transform)
	point.set("activity_type", "social")
	point.set("target_path", NodePath(""))
	if _has_property(point, "facility_path"):
		point.set("facility_path", point.get_path_to(self))
	if _has_property(point, "visit_seats_root_path"):
		var furniture := get_node_or_null(furniture_root_path)
		point.set("visit_seats_root_path", point.get_path_to(furniture) if furniture != null else furniture_root_path)
	if _has_property(point, "standing_points_root_path"):
		point.set("standing_points_root_path", NodePath(""))
	if _has_property(point, "visitor_capacity_property"):
		point.set("visitor_capacity_property", "visitor_capacity")
	point.set("display_name", "Bar Visit Spot")
	point.set("exclusive", false)
	point.set("weight", maxf(4.0, float(visitor_capacity) * 4.0))
	if _has_property(point, "assignment_min_seconds"):
		point.set("assignment_min_seconds", 25.0)
	if _has_property(point, "assignment_max_seconds"):
		point.set("assignment_max_seconds", 35.0)
	_tag_generated_layout_node(point, "visitor", 0, default_transform)
	return point


func _sync_bar_authoring() -> void:
	var service_area := get_bar_service_area()
	if service_area == null:
		return
	var barkeeper := _get_barkeeper_actor()
	if not _is_actor_alive(barkeeper):
		barkeeper = null
	var waiters := _get_role_actors("waiter")
	var waiter := waiters[0] if not waiters.is_empty() else null
	var guards := _get_role_actors("guard")
	if _has_property(service_area, "service_area_id"):
		var current_service_area_id := str(service_area.get("service_area_id"))
		if current_service_area_id.is_empty() or current_service_area_id.begins_with("settlement_bar."):
			service_area.set("service_area_id", "%s.service_area" % get_facility_id())
	var owner_faction := _get_effective_owner_faction_id()
	if not owner_faction.is_empty() and _has_property(service_area, "owner_faction_name"):
		service_area.set("owner_faction_name", owner_faction)
	if _has_property(service_area, "owner_character_path"):
		service_area.set("owner_character_path", service_area.get_path_to(barkeeper) if barkeeper != null else NodePath(""))
	if _has_property(service_area, "waiter_character_path"):
		service_area.set("waiter_character_path", service_area.get_path_to(waiter) if waiter != null else NodePath(""))
	if _has_property(service_area, "waiter_character_paths"):
		service_area.set("waiter_character_paths", _paths_from(service_area, waiters))
	if _has_property(service_area, "guard_character_paths"):
		service_area.set("guard_character_paths", _paths_from(service_area, guards))
	_set_node_path_property(service_area, "beds_root_path", "../Furniture")
	_set_node_path_property(service_area, "seats_root_path", "../Furniture")
	_set_node_path_property(service_area, "tables_root_path", "../Furniture")
	_set_node_path_property(service_area, "guard_posts_root_path", "../GuardPosts")
	_set_node_path_property(service_area, "service_points_root_path", "../WaiterPoints" if _effective_waiter_point_count() > 0 else "")
	_set_node_path_property(service_area, "guards_root_path", "../Staff")
	_set_node_path_property(service_area, "waiters_root_path", "../Staff")
	_sync_staff_member(barkeeper, "barkeeper")
	for waiter_index in range(waiters.size()):
		_sync_staff_member(waiters[waiter_index], _indexed_name("waiter", waiter_index))
	for guard_index in range(guards.size()):
		_sync_staff_member(guards[guard_index], _indexed_name("guard", guard_index))
	if has_barber:
		var barber := _get_barber_actor()
		_sync_staff_member(barber, "barber")
		_send_barber_to_seat(barber)
	var job_provider := barkeeper.get_node_or_null("JobProvider") if barkeeper != null else null
	_sync_job_provider_jobs(job_provider)
	if job_provider != null and _has_property(job_provider, "bar_service_area_path"):
		job_provider.set("bar_service_area_path", job_provider.get_path_to(service_area))
	if service_area.has_method("refresh_scope"):
		service_area.call("refresh_scope")


func _sync_building_level_content() -> void:
	var building := _get_current_building()
	if building == null:
		return
	if building.has_method("register_extra_level_content"):
		for furniture_item in _collect_furniture_items():
			var level_index := beds_building_level_index if _is_bed_furniture(furniture_item) else 0
			_register_building_level_content(building, level_index, furniture_item)


func _register_building_level_content(building: Node, level_index: int, content: Node) -> void:
	if content == null:
		return
	building.call("register_extra_level_content", level_index, building.get_path_to(content))


func _collect_furniture_items() -> Array[Node]:
	var furniture := get_node_or_null(furniture_root_path)
	var items: Array[Node] = []
	if furniture == null:
		return items
	for child in furniture.get_children():
		if _is_legacy_furniture_root(child):
			for item in child.get_children():
				items.append(item)
		else:
			items.append(child)
	return items


func _is_legacy_furniture_root(node: Node) -> bool:
	return node != null and LEGACY_FURNITURE_ROOT_NAMES.has(str(node.name))


func _is_bed_furniture(node: Node) -> bool:
	return node != null and node.has_method("request_sleep") and node.has_method("get_sleep_position")


func _ensure_service_point(root: Node, point_name: String, point_transform: Transform3D, role: String, color: Color) -> Node:
	var point := root.get_node_or_null(point_name)
	if point == null:
		point = Node3D.new()
		point.name = point_name
		point.transform = point_transform
		point.set_script(BAR_SERVICE_POINT_SCRIPT)
		root.add_child(point)
		_set_editor_owner(point)
	elif point is Node3D:
		_sync_generated_layout_node(point, role, _generated_child_index(point_name, _point_base_name(point_name)), point_transform)
	if not point.has_method("get_work_position"):
		point.set_script(BAR_SERVICE_POINT_SCRIPT)
	if _has_property(point, "point_role"):
		point.set("point_role", role)
	if _has_property(point, "debug_color"):
		point.set("debug_color", color)
	_tag_generated_layout_node(point, role, _generated_child_index(point_name, _point_base_name(point_name)), point_transform)
	_refresh_authoring_marker(point)
	return point


func _ensure_guard_post(root: Node, post_name: String, post_transform: Transform3D) -> Node:
	var post := root.get_node_or_null(post_name)
	if post == null:
		post = Node3D.new()
		post.name = post_name
		post.transform = post_transform
		post.set_script(BAR_GUARD_POST_SCRIPT)
		root.add_child(post)
		_set_editor_owner(post)
	elif post is Node3D:
		_sync_generated_layout_node(post, "guard", _generated_child_index(post_name, "GuardPost"), post_transform)
	if not post.has_method("get_work_position"):
		post.set_script(BAR_GUARD_POST_SCRIPT)
	_tag_generated_layout_node(post, "guard", _generated_child_index(post_name, "GuardPost"), post_transform)
	_refresh_authoring_marker(post)
	return post


func _ensure_staff_member(root: Node, node_name: String, member_name: String, color: Color, local_position: Vector3, conversation: Resource, script: Script, role: String, role_index: int) -> Node:
	var staff := root.get_node_or_null(node_name)
	if staff != null and not _is_actor_alive(staff):
		node_name = _next_generated_child_name(root, node_name)
		staff = null
	if staff != null and not _is_generated_staff(staff):
		node_name = _next_generated_child_name(root, node_name)
		staff = null
	if staff != null:
		if staff is Node3D and _should_sync_generated_staff_position(staff):
			_sync_generated_layout_node(staff, role, role_index, Transform3D(Basis(), local_position))
		_apply_staff_role_defaults(staff, member_name, color, conversation, role, role_index)
		_tag_generated_layout_node(staff, role, role_index, Transform3D(Basis(), local_position))
		return staff
	staff = CharacterBody3D.new()
	staff.name = node_name
	staff.position = local_position
	# The character generator decides the actor class (a quadbot facility
	# spawns quadbots, not humanoids in a quadbot costume); the role script
	# is only the humanoid default.
	var profile := _get_effective_population_appearance_profile()
	var profile_script := profile.get("actor_script") as Script if profile != null else null
	staff.set_script(profile_script if profile_script != null else script)
	staff.set("stable_id", "%s.%s" % [_get_staff_id_prefix(), node_name.to_lower()])
	# Tag BEFORE role defaults: the appearance/name/skill generation inside
	# _apply_staff_role_defaults only touches generated staff, and the tag is
	# what marks this actor as generated. Tagging after left staff bald.
	_tag_generated_layout_node(staff, role, role_index, Transform3D(Basis(), local_position))
	_apply_staff_role_defaults(staff, member_name, color, conversation, role, role_index)
	_add_basic_humanoid_children(staff)
	root.add_child(staff)
	_set_editor_owner_recursive(staff)
	return staff


func _apply_staff_role_defaults(staff: Node, member_name: String, color: Color, conversation: Resource, role: String, role_index: int) -> void:
	if staff == null:
		return
	if _has_property(staff, "base_color"):
		staff.set("base_color", color)
	if _has_property(staff, "member_name") and _is_generated_staff(staff):
		staff.set("member_name", member_name)
	if conversation != null and _has_property(staff, "conversation_definition"):
		staff.set("conversation_definition", conversation)
	_sync_staff_member(staff, role)
	# Bar staff defend themselves but never respond like soldiers — the actor
	# default is AGGRESSIVE (raiders/guards), wrong for waiters and barkeepers.
	if _has_property(staff, "combat_stance"):
		staff.set("combat_stance", NpcRules.combat_stance_for_role(role))
	_apply_population_generation_to_staff(staff, role, role_index)
	_apply_staff_role_skills(staff, role, role_index)
	_sync_staff_actor_population_record(staff)


func _should_sync_generated_staff_position(staff: Node) -> bool:
	return _is_generated_staff(staff)


func _add_basic_humanoid_children(actor: Node) -> void:
	if actor.get_node_or_null("CollisionShape3D") == null:
		var collision := CollisionShape3D.new()
		collision.name = "CollisionShape3D"
		collision.transform = Transform3D(Basis(), Vector3(0.0, 0.95, 0.0))
		var capsule_shape := CapsuleShape3D.new()
		capsule_shape.radius = 0.4
		capsule_shape.height = 1.1
		collision.shape = capsule_shape
		actor.add_child(collision)
	if actor.get_node_or_null("BodyMesh") == null:
		var body := MeshInstance3D.new()
		body.name = "BodyMesh"
		body.transform = Transform3D(Basis(), Vector3(0.0, 0.95, 0.0))
		var capsule_mesh := CapsuleMesh.new()
		capsule_mesh.radius = 0.4
		body.mesh = capsule_mesh
		actor.add_child(body)
	if actor.get_node_or_null("SelectionRing") == null:
		var ring := MeshInstance3D.new()
		ring.name = "SelectionRing"
		ring.transform = Transform3D(Basis(), Vector3(0.0, 0.03, 0.0))
		ring.visible = false
		SELECTION_RING_VISUAL.setup_ring(ring)
		actor.add_child(ring)


func _ensure_merchant_role(barkeeper: Node) -> void:
	if barkeeper == null:
		return
	var role := barkeeper.get_node_or_null("MerchantRole")
	if role == null:
		role = Node.new()
		role.name = "MerchantRole"
		role.set_script(MERCHANT_ROLE_SCRIPT)
		barkeeper.add_child(role)
		_set_editor_owner(role)
	elif not (role is MerchantRole):
		role.set_script(MERCHANT_ROLE_SCRIPT)
	_sync_bar_merchant_role(role)


func _ensure_job_provider(barkeeper: Node) -> void:
	if barkeeper == null:
		return
	var provider := barkeeper.get_node_or_null("JobProvider")
	if provider == null:
		provider = Node.new()
		provider.name = "JobProvider"
		provider.set_script(JOB_PROVIDER_SCRIPT)
		barkeeper.add_child(provider)
		_set_editor_owner(provider)
	elif not (provider is JobProvider):
		provider.set_script(JOB_PROVIDER_SCRIPT)
	_ensure_bar_job_definitions(provider)
	provider.set("wage_item_definition", SILVER_ITEM)


func _sync_job_provider_jobs(provider: Node) -> void:
	if provider == null or not _has_property(provider, "jobs"):
		return
	_ensure_bar_job_definitions(provider)
	var provider_jobs: Array = provider.get("jobs")
	for job in provider_jobs:
		if job == null:
			continue
		match str(job.get("algorithm_id")):
			"guard_post":
				job.set("slot_count", max(_effective_guard_job_slot_count(), 1))
			"server_shift":
				job.set("slot_count", max(waiter_count, 1))


func _ensure_bar_job_definitions(provider: Node) -> void:
	if provider == null or not _has_property(provider, "jobs"):
		return
	var jobs: Array = (provider.get("jobs") as Array).duplicate()
	if not _job_algorithm_exists(jobs, "guard_post"):
		jobs.append(_job_definition("Guard duty", "bar_guard", "guard_post", 20.0, 2))
	if not _job_algorithm_exists(jobs, "server_shift"):
		jobs.append(_job_definition("Serving tables", "bar_server", "server_shift", 20.0, 1))
	provider.set("jobs", jobs)


func _job_algorithm_exists(jobs: Array, algorithm_id: String) -> bool:
	for job in jobs:
		if job != null and str(job.get("algorithm_id")) == algorithm_id:
			return true
	return false


func _merchant_price(item: Resource) -> Resource:
	var price: Resource = MERCHANT_PRICE_SCRIPT.new()
	price.set("item_definition", item)
	return price


func _merchant_stock(item: Resource, quantity: int) -> Resource:
	var stock: Resource = MERCHANT_STOCK_SCRIPT.new()
	stock.set("item_definition", item)
	stock.set("quantity", quantity)
	stock.set_meta(META_STOCK_GENERATED, true)
	stock.set_meta(META_STOCK_GENERATED_QUANTITY, quantity)
	return stock


func _sync_bar_merchant_role(role: Node) -> void:
	if role == null:
		return
	# This mirrors parent settlement supply for default stock only. Future economy work should restock through settlement storage instead of minting merchant inventory here.
	_ensure_merchant_prices(role, [BREAD_ITEM, FOOD_ITEM, SILVER_ITEM])
	var stock_ratio := _get_effective_stock_ratio()
	for stock in _default_bar_stock(stock_ratio):
		var item := stock.get("item") as Resource
		var quantity := int(stock.get("quantity", 0))
		if item == null:
			continue
		_ensure_merchant_initial_stock(role, item, quantity)
		if quantity > 0:
			_ensure_seeded_inventory_stock(role, item, quantity)


func _ensure_merchant_prices(role: Node, items: Array) -> void:
	if role == null or not _has_property(role, "prices"):
		return
	var prices: Array = (role.get("prices") as Array).duplicate()
	for item in items:
		if item == null or _merchant_price_exists(prices, item):
			continue
		prices.append(_merchant_price(item))
	role.set("prices", prices)


func _merchant_price_exists(prices: Array, item: Resource) -> bool:
	for price in prices:
		if price != null and price.get("item_definition") == item:
			return true
	return false


func _ensure_merchant_initial_stock(role: Node, item: Resource, quantity: int) -> void:
	if role == null or item == null or not _has_property(role, "initial_stock"):
		return
	var initial_stock: Array = (role.get("initial_stock") as Array).duplicate()
	for stock in initial_stock:
		if stock != null and stock.get("item_definition") == item:
			_sync_generated_merchant_stock_quantity(stock, quantity)
			return
	if quantity <= 0:
		return
	initial_stock.append(_merchant_stock(item, quantity))
	role.set("initial_stock", initial_stock)


func _sync_generated_merchant_stock_quantity(stock: Object, quantity: int) -> void:
	if stock == null or not bool(stock.get_meta(META_STOCK_GENERATED, false)):
		return
	var previous_generated_quantity := int(stock.get_meta(META_STOCK_GENERATED_QUANTITY, int(stock.get("quantity"))))
	if int(stock.get("quantity")) != previous_generated_quantity:
		return
	stock.set("quantity", quantity)
	stock.set_meta(META_STOCK_GENERATED_QUANTITY, quantity)


func _ensure_seeded_inventory_stock(role: Node, item: Resource, quantity: int) -> void:
	if Engine.is_editor_hint() or role == null or item == null or quantity <= 0 or not role.is_inside_tree() or not role.has_method("get_shop_inventory"):
		return
	if _has_property(role, "_stock_seeded") and not bool(role.get("_stock_seeded")):
		return
	var inventory = role.call("get_shop_inventory")
	if inventory != null and inventory.has_method("count_item") and int(inventory.call("count_item", item)) <= 0:
		inventory.call("add_item_count", item, quantity)


func _default_bar_stock(stock_ratio: float) -> Array[Dictionary]:
	return [
		{"item": BREAD_ITEM, "quantity": _scaled_stock_quantity(max_bread_stock, stock_ratio)},
		{"item": FOOD_ITEM, "quantity": _scaled_stock_quantity(max_food_stock, stock_ratio)},
		{"item": SILVER_ITEM, "quantity": _scaled_stock_quantity(max_silver_stock, stock_ratio)},
	]


func _scaled_stock_quantity(max_quantity: int, stock_ratio: float) -> int:
	if max_quantity <= 0 or stock_ratio <= 0.0:
		return 0
	return clampi(int(round(float(max_quantity) * clampf(stock_ratio, 0.0, 1.0))), 0, max_quantity)


func _get_effective_stock_ratio() -> float:
	if stock_source == "standalone_fallback":
		return clampf(standalone_stock_ratio, 0.0, 1.0)
	var state := _get_parent_settlement_state()
	if not state.is_empty() and state.has("food_ratio"):
		return clampf(float(state.get("food_ratio", standalone_stock_ratio)), 0.0, 1.0)
	var definition_ratio := _get_ancestor_settlement_food_ratio()
	if definition_ratio >= 0.0:
		return definition_ratio
	return clampf(standalone_stock_ratio, 0.0, 1.0)


func _get_parent_settlement_state() -> Dictionary:
	var settlement_id := _get_ancestor_settlement_id()
	if settlement_id.is_empty() or not is_inside_tree():
		return {}
	var settlement_controller := _get_settlement_controller()
	if settlement_controller == null or not settlement_controller.has_method("get_settlement_state"):
		return {}
	return settlement_controller.call("get_settlement_state", settlement_id) as Dictionary


func _get_settlement_controller() -> Node:
	if not is_inside_tree():
		return null
	for node in get_tree().get_nodes_in_group("settlement_controller"):
		if node != null and node.has_method("get_settlement_state"):
			return node
	return null


func _get_ancestor_settlement_food_ratio() -> float:
	var definition := _get_ancestor_settlement_definition()
	if definition == null:
		return -1.0
	var max_food := maxf(_resource_float_value(definition, "max_food", 1.0), 1.0)
	return clampf(_resource_float_value(definition, "starting_food", max_food) / max_food, 0.0, 1.0)


func _resource_float_value(resource: Resource, property_name: String, fallback: float) -> float:
	if resource == null:
		return fallback
	var value = resource.get(property_name)
	return fallback if value == null else float(value)


func _job_definition(display: String, job_id: String, algorithm: String, interval: float, pay: int) -> Resource:
	var job: Resource = JOB_DEFINITION_SCRIPT.new()
	job.set("display_name", display)
	job.set("job_id", job_id)
	job.set("algorithm_id", algorithm)
	job.set("pay_interval_seconds", interval)
	job.set("pay_per_interval", pay)
	return job


func _indexed_name(base_name: String, index: int) -> String:
	return base_name if index == 0 else "%s%d" % [base_name, index + 1]


func _indexed_display_name(base_name: String, index: int) -> String:
	return base_name if index == 0 else "%s %d" % [base_name, index + 1]


func _waiter_point_name(index: int) -> String:
	return _indexed_name("WaiterPoint", index)


func _guard_post_name(index: int) -> String:
	return _indexed_name("GuardPost", index)


func _barkeeper_point_transform() -> Transform3D:
	return Transform3D(Basis(Vector3.UP, deg_to_rad(40.0)), Vector3(0.0, 0.35, -1.85))


func _waiter_point_transform(index: int) -> Transform3D:
	var column := index % 4
	var row := int(float(index) / 4.0)
	return Transform3D(Basis(Vector3.UP, deg_to_rad(8.0)), Vector3(3.0 + float(column) * 0.75, 0.35, 0.65 + float(row) * 0.9))


func _barber_idle_transform() -> Transform3D:
	return Transform3D(Basis(Vector3.UP, deg_to_rad(-90.0)), Vector3(-2.0, 0.35, 1.7))


func _hangout_point_transform(index: int) -> Transform3D:
	var column := index % 4
	var row := int(float(index) / 4.0)
	return Transform3D(Basis(Vector3.UP, deg_to_rad(180.0)), Vector3(-2.2 + float(column) * 1.15, 0.05, 2.1 + float(row) * 0.85))


func _guard_post_transform(index: int) -> Transform3D:
	if index == 0:
		return Transform3D(Basis(Vector3.UP, deg_to_rad(-85.0)), Vector3(3.1, 0.05, 4.35))
	var guard_index := index - 1
	var column := guard_index % 3
	var row := int(float(guard_index) / 3.0)
	return Transform3D(Basis(Vector3.UP, deg_to_rad(-85.0)), Vector3(-1.4 + float(column) * 1.4, 0.05, 4.25 + float(row) * 0.85))


func _waiter_local_position(index: int) -> Vector3:
	var point_name := _waiter_point_name(index)
	var point_transform := _layout_default_transform(service_points_root_path, point_name, _waiter_point_transform(index))
	return Vector3(point_transform.origin.x, 0.6, point_transform.origin.z)


func _guard_local_position(index: int) -> Vector3:
	var post_name := _guard_post_name(index)
	var post_transform := _layout_default_transform(guard_posts_root_path, post_name, _guard_post_transform(index))
	return Vector3(post_transform.origin.x, 0.6, post_transform.origin.z + 1.15)


func _point_local_position(point_transform: Transform3D) -> Vector3:
	return Vector3(point_transform.origin.x, 0.6, point_transform.origin.z)


func _effective_waiter_point_count() -> int:
	return max(waiter_count, waiter_point_count)


func _effective_guard_post_count() -> int:
	return max(guard_count, guard_post_count)


func _effective_guard_job_slot_count() -> int:
	return max(guard_count, guard_job_slot_count)


func _clamp_count(value, minimum: int, maximum: int) -> int:
	if value == null:
		return minimum
	return clampi(int(value), minimum, maximum)


func _migrate_legacy_guard_post_names(root: Node) -> void:
	if root == null or root.get_node_or_null("GuardPost") != null:
		return
	var legacy_post := root.get_node_or_null("EntranceGuardPost")
	if legacy_post != null:
		legacy_post.name = "GuardPost"


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


func _point_base_name(point_name: String) -> String:
	for base_name in ["WaiterPoint", "FacilityVisitPoint", "GuardPost"]:
		if _generated_child_index(point_name, base_name) >= 0:
			return base_name
	return point_name


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
	node.set_meta(META_LAYOUT_VERSION, BAR_LAYOUT_VERSION)
	if not _meta_bool(node, META_LAYOUT_CUSTOM, false):
		node.set_meta(META_LAST_DEFAULT_TRANSFORM, default_transform)


func _meta_bool(node: Node, key: String, fallback: bool) -> bool:
	if node == null or not node.has_meta(key):
		return fallback
	return bool(node.get_meta(key))


func _transforms_close(left: Transform3D, right: Transform3D) -> bool:
	return left.origin.distance_to(right.origin) <= 0.001 \
		and _basis_close(left.basis, right.basis)


func _basis_close(left: Basis, right: Basis) -> bool:
	return left.x.distance_to(right.x) <= 0.001 \
		and left.y.distance_to(right.y) <= 0.001 \
		and left.z.distance_to(right.z) <= 0.001


func _is_generated_child_for_trim(child: Node, base_name: String) -> bool:
	if child == null:
		return false
	if base_name in ["Barkeeper", "Waiter", "Guard", "Barber"]:
		return _is_generated_staff(child)
	return not _meta_bool(child, META_LAYOUT_CUSTOM, false)


func _is_generated_staff(staff: Node) -> bool:
	if staff == null or not _has_property(staff, "stable_id"):
		return false
	var current_stable_id := str(staff.get("stable_id"))
	return current_stable_id.is_empty() or current_stable_id.begins_with("SettlementBar.") or current_stable_id.begins_with("settlement_bar.") or current_stable_id.begins_with("%s." % _get_staff_id_prefix())


func _next_generated_child_name(root: Node, preferred_name: String) -> String:
	if root == null:
		return preferred_name
	var index := 2
	var candidate := "%s%d" % [preferred_name, index]
	while root.get_node_or_null(candidate) != null:
		index += 1
		candidate = "%s%d" % [preferred_name, index]
	return candidate


func _refresh_authoring_marker(node: Node) -> void:
	if Engine.is_editor_hint() and node.has_method("_refresh_debug_marker"):
		node.call("_refresh_debug_marker")


func _ensure_child_root(parent: Node, root_name: String) -> Node:
	var child := parent.get_node_or_null(root_name)
	if child != null:
		return child
	child = Node3D.new()
	child.name = root_name
	parent.add_child(child)
	_set_editor_owner(child)
	return child


func _sync_staff_member(staff: Node, role: String) -> void:
	if staff == null:
		return
	var role_base := _role_base(role)
	var role_index := _role_index_from_role(role, role_base)
	if not role_base.is_empty():
		staff.set_meta(META_SETTLEMENT_ROLE, role_base)
		staff.set_meta(META_SETTLEMENT_ROLE_INDEX, role_index)
		staff.set_meta(META_SETTLEMENT_SLOT_ID, _staff_slot_id(role_base, role_index))
		staff.set_meta("settlement_actor_category", "staff")
	var owner_faction := _get_effective_owner_faction_id()
	if sync_staff_from_owner and not owner_faction.is_empty() and _has_property(staff, "faction_name"):
		staff.set("faction_name", owner_faction)
	if _has_property(staff, "squad_name") and not _get_bar_squad_name().is_empty():
		staff.set("squad_name", _get_bar_squad_name())
	if _has_property(staff, "combat_stance") and role_base in ["barkeeper", "waiter", "guard", "barber"] and int(staff.get("combat_stance")) == NpcRules.CombatStance.PASSIVE:
		staff.set("combat_stance", NpcRules.CombatStance.DEFENSIVE)
	if _has_property(staff, "stable_id"):
		var current_stable_id := str(staff.get("stable_id"))
		if current_stable_id.is_empty() or current_stable_id.begins_with("settlement_bar."):
			staff.set("stable_id", "%s.%s" % [_get_staff_id_prefix(), role])
	_apply_security_groups(staff, role_base)
	_apply_bar_guard_equipment(staff, role_base)
	_apply_role_suffix(staff, role)


func _apply_assigned_role_defaults(staff: Node, role: String, conversation: Resource) -> void:
	if staff == null:
		return
	_sync_staff_member(staff, role)
	if conversation != null and _has_property(staff, "conversation_definition"):
		staff.set("conversation_definition", conversation)


func _apply_role_suffix(staff: Node, role: String) -> void:
	if staff == null or not _has_property(staff, "member_name"):
		return
	var role_base := _role_base(role)
	if role_base.is_empty():
		return
	var staff_display_name := _strip_role_suffix(str(staff.get("member_name"))).strip_edges()
	if staff_display_name.is_empty():
		staff_display_name = role_base.capitalize()
	staff.set("member_name", "%s (%s)" % [staff_display_name, role_base])
	if not Engine.is_editor_hint() and staff.is_inside_tree() and staff.has_method("refresh_nameplate"):
		staff.call("refresh_nameplate")


func _role_base(role: String) -> String:
	var normalized := role.strip_edges().to_lower()
	for role_name in ["barkeeper", "waiter", "guard", "barber"]:
		if normalized == role_name or normalized.begins_with(role_name):
			return role_name
	return ""


func _role_index_from_role(role: String, role_base: String) -> int:
	if role_base.is_empty():
		return 0
	var normalized := role.strip_edges().to_lower()
	if normalized == role_base:
		return 0
	var suffix := normalized.substr(role_base.length())
	return max(0, int(suffix) - 1) if suffix.is_valid_int() else 0


func _staff_slot_id(role: String, role_index: int) -> String:
	return "%s.%s" % [get_facility_id(), _indexed_name(role, role_index)]


func _apply_security_groups(staff: Node, role_base: String) -> void:
	if staff == null or Engine.is_editor_hint():
		return
	if staff.has_method("set_settlement_authority"):
		staff.call("set_settlement_authority", false)
	if staff.has_method("set_private_security"):
		staff.call("set_private_security", role_base == "guard")
	if staff.has_method("set_faction_soldier"):
		staff.call("set_faction_soldier", false)


func _apply_bar_guard_equipment(staff: Node, role_base: String) -> void:
	if staff == null or role_base != "guard" or not _has_property(staff, "starting_equipment"):
		return
	var starting_equipment: Array = (staff.get("starting_equipment") as Array).duplicate()
	for item in [BANDAGE_ITEM, HATCHET_ITEM]:
		if item == null or starting_equipment.has(item):
			continue
		starting_equipment.append(item)
		var slot_name := str(item.get("equip_slot")) if _has_property(item, "equip_slot") else ""
		if not Engine.is_editor_hint() and not slot_name.is_empty() and staff.has_method("get_equipped_item") and staff.has_method("equip_item_to_slot") and staff.call("get_equipped_item", slot_name) == null:
			staff.call("equip_item_to_slot", item, slot_name)
	staff.set("starting_equipment", starting_equipment)


func _is_actor_alive(actor: Node) -> bool:
	if actor == null or not is_instance_valid(actor):
		return false
	if _has_property(actor, "life_state"):
		return int(actor.get("life_state")) == NpcRules.LifeState.ALIVE
	return true


func _strip_role_suffix(staff_display_name: String) -> String:
	var result := staff_display_name.strip_edges()
	for role_name in ["barkeeper", "waiter", "guard", "barber"]:
		var suffix := " (%s)" % role_name
		if result.to_lower().ends_with(suffix):
			return result.substr(0, result.length() - suffix.length()).strip_edges()
	return result


func _get_barkeeper_actor() -> Node:
	var assigned := _get_assigned_actor(barkeeper_actor_path)
	return assigned if assigned != null else get_node_or_null("Staff/Barkeeper")


func _get_barber_actor() -> Node:
	var assigned := _get_assigned_actor(barber_actor_path)
	return assigned if assigned != null else get_node_or_null("Staff/Barber")


func _get_role_actor_for_slot(role: String, role_index: int) -> Node:
	var slot_id := _staff_slot_id(role, role_index)
	var by_slot := _find_role_actor_by_slot_id(slot_id)
	if by_slot != null:
		return by_slot
	match role:
		"barkeeper":
			return _get_barkeeper_actor()
		"barber":
			return _get_barber_actor()
		"waiter":
			return _get_role_actor_by_index("waiter", role_index, assigned_waiter_paths, "Waiter")
		"guard":
			return _get_role_actor_by_index("guard", role_index, assigned_guard_paths, "Guard")
		_:
			return null


func _find_role_actor_by_slot_id(slot_id: String) -> Node:
	for actor in _all_potential_role_actors():
		if actor != null and str(actor.get_meta(META_SETTLEMENT_SLOT_ID, "")) == slot_id:
			return actor
	return null


func _get_role_actor_by_index(_role: String, role_index: int, assigned_paths: Array[NodePath], generated_base_name: String) -> Node:
	if role_index < assigned_paths.size():
		var assigned := _get_assigned_actor(assigned_paths[role_index])
		if assigned != null:
			return assigned
	var generated_index := role_index - assigned_paths.size()
	return get_node_or_null("%s/%s" % [str(staff_root_path), _indexed_name(generated_base_name, generated_index)])


func _all_potential_role_actors() -> Array[Node]:
	var actors: Array[Node] = []
	for path in [barkeeper_actor_path, barber_actor_path]:
		var actor := _get_assigned_actor(path)
		if actor != null and not actors.has(actor):
			actors.append(actor)
	for actor in _get_assigned_actors_raw(assigned_waiter_paths):
		if not actors.has(actor):
			actors.append(actor)
	for actor in _get_assigned_actors_raw(assigned_guard_paths):
		if not actors.has(actor):
			actors.append(actor)
	var root := get_node_or_null(staff_root_path)
	if root != null:
		for child in root.get_children():
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
		candidate.name = _available_child_name(staff_root, _role_node_base_name(role))
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
	var script := _script_for_role(role)
	if script != null:
		actor.set_script(script)
	actor.set_meta(META_GENERATED, true)
	_apply_staff_role_defaults(actor, _display_name_for_role(role, role_index), _color_for_role(role), _conversation_for_role(role), _indexed_name(role, role_index), role_index)
	if actor is Node3D:
		(actor as Node3D).position = _local_position_for_role(role, role_index)


func _sync_staff_actor_population_record(actor: Node) -> void:
	if actor == null or Engine.is_editor_hint() or not actor.is_inside_tree():
		return
	var settlement_id := _get_ancestor_settlement_id()
	if settlement_id.is_empty():
		return
	var population_controller := get_tree().get_first_node_in_group("population_controller")
	if population_controller != null and population_controller.has_method("register_actor"):
		population_controller.call("register_actor", actor, settlement_id, {})


func _create_generated_staff_for_role(role: String, role_index: int, staff_root: Node) -> Node:
	var node_name := _available_child_name(staff_root, _role_node_base_name(role))
	return _ensure_staff_member(staff_root, node_name, _display_name_for_role(role, role_index), _color_for_role(role), _local_position_for_role(role, role_index), _conversation_for_role(role), _script_for_role(role), _indexed_name(role, role_index), role_index)


func _available_child_name(root: Node, preferred_name: String) -> String:
	if root == null or root.get_node_or_null(preferred_name) == null:
		return preferred_name
	return _next_generated_child_name(root, preferred_name)


func _role_from_slot_id(slot_id: String) -> String:
	var suffix := slot_id.get_slice(".", slot_id.get_slice_count(".") - 1)
	return _role_base(suffix)


func _role_node_base_name(role: String) -> String:
	match role:
		"barkeeper":
			return "Barkeeper"
		"waiter":
			return "Waiter"
		"guard":
			return "Guard"
		"barber":
			return "Barber"
		_:
			return "Staff"


func _display_name_for_role(role: String, role_index: int) -> String:
	match role:
		"barkeeper":
			return barkeeper_name
		"waiter":
			return _indexed_display_name(waiter_name, role_index)
		"guard":
			return _indexed_display_name(guard_name, role_index)
		"barber":
			return barber_name
		_:
			return "Staff"


func _color_for_role(role: String) -> Color:
	match role:
		"barkeeper":
			return Color(0.58, 0.43, 0.2, 1.0)
		"waiter":
			return Color(0.28, 0.47, 0.56, 1.0)
		"guard":
			return Color(0.42, 0.42, 0.48, 1.0)
		"barber":
			return Color(0.54, 0.38, 0.68, 1.0)
		_:
			return Color(0.62, 0.62, 0.62, 1.0)


func _conversation_for_role(role: String) -> Resource:
	match role:
		"barkeeper":
			return SHOPKEEPER_CONVERSATION
		"waiter":
			return WAITER_CONVERSATION
		"barber":
			return BARBER_CONVERSATION
		_:
			return null


func _script_for_role(role: String) -> Script:
	return BARBER_HUMANOID_SCRIPT if role == "barber" else MERCHANT_HUMANOID_SCRIPT


func _local_position_for_role(role: String, role_index: int) -> Vector3:
	match role:
		"barkeeper":
			return _point_local_position(_barkeeper_point_transform())
		"waiter":
			return _waiter_local_position(role_index)
		"guard":
			return _guard_local_position(role_index)
		"barber":
			return _point_local_position(_barber_idle_transform())
		_:
			return Vector3.ZERO


func _actor_key(actor: Node) -> String:
	if actor == null:
		return ""
	if _has_property(actor, "stable_id"):
		var stable_id := str(actor.get("stable_id")).strip_edges()
		if not stable_id.is_empty():
			return stable_id
	return str(actor.get_path()) if actor.is_inside_tree() else str(actor.get_instance_id())


func _get_role_actors(role: String) -> Array[Node]:
	var actors: Array[Node] = []
	match role:
		"waiter":
			actors.append_array(_get_assigned_actors(assigned_waiter_paths))
			_collect_generated_role_actors(actors, "Waiter")
		"guard":
			actors.append_array(_get_assigned_actors(assigned_guard_paths))
			_collect_generated_role_actors(actors, "Guard")
		"barber":
			var barber := _get_barber_actor()
			if barber != null:
				actors.append(barber)
	return actors


func _is_bar_role_actor(actor: Node) -> bool:
	if actor == null:
		return false
	if actor == _get_barkeeper_actor():
		return true
	for role in ["waiter", "guard", "barber"]:
		if _get_role_actors(role).has(actor):
			return true
	return false


func _is_marked_special_bar_visitor(actor: Node) -> bool:
	if actor == null:
		return false
	for group_name in ["special_npc", "hireable_npc", "hireling", "mercenary", "bar_staff"]:
		if actor.is_in_group(group_name):
			return true
	for meta_name in ["bar_visitor_excluded", "town_activity_excluded", "special_npc"]:
		if bool(actor.get_meta(meta_name, false)):
			return true
	var actor_category := str(actor.get_meta("settlement_actor_category", ""))
	return not actor_category.is_empty() and actor_category != "townie" and actor_category != "resident"


func _is_actor_under_settlement_resident_root(actor: Node) -> bool:
	var settlement := _get_ancestor_settlement()
	if settlement == null or actor == null:
		return false
	var resident_root_path = settlement.get("resident_root_path")
	if resident_root_path == null:
		return false
	var resident_root := settlement.get_node_or_null(resident_root_path)
	return resident_root != null and _is_descendant_of(actor, resident_root)


func _is_descendant_of(node: Node, ancestor: Node) -> bool:
	var current := node
	while current != null:
		if current == ancestor:
			return true
		current = current.get_parent()
	return false


func _collect_generated_role_actors(actors: Array[Node], base_name: String) -> void:
	var root := get_node_or_null(staff_root_path)
	if root == null:
		return
	for child in root.get_children():
		if _generated_child_index(str(child.name), base_name) >= 0 and child is HumanoidCharacter and _is_actor_alive(child) and not actors.has(child):
			actors.append(child)


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


func _paths_from(origin: Node, actors: Array[Node]) -> Array[NodePath]:
	var paths: Array[NodePath] = []
	if origin == null:
		return paths
	for actor in actors:
		if actor != null and is_instance_valid(actor):
			paths.append(origin.get_path_to(actor))
	return paths


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
			_apply_role_suffix(staff, role)
			if not Engine.is_editor_hint() and staff.is_inside_tree() and staff.has_method("refresh_nameplate"):
				staff.call("refresh_nameplate")


func _apply_staff_role_skills(staff: Node, role: String, role_index: int) -> void:
	if staff == null or Engine.is_editor_hint() or not _is_generated_staff(staff) or not staff.has_method("get_skill_level") or not staff.has_method("set_skill_level"):
		return
	var perception_range := GUARD_PERCEPTION_RANGE if str(role).strip_edges().to_lower().begins_with("guard") else STAFF_PERCEPTION_RANGE
	var rng := _make_staff_rng("skill:%s:%d:%s" % [role, role_index, str(staff.name)])
	staff.call("set_skill_level", SkillRules.ATTRIBUTE_PERCEPTION, _roll_center_biased_level(perception_range.x, perception_range.y, rng))


func _roll_center_biased_level(minimum: int, maximum: int, rng: RandomNumberGenerator) -> int:
	var low := mini(minimum, maximum)
	var high := maxi(minimum, maximum)
	if low == high:
		return low
	var t := (rng.randf() + rng.randf()) * 0.5
	return clampi(int(round(lerpf(float(low), float(high), t))), low, high)


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


func _get_effective_population_appearance_profile() -> Resource:
	if population_appearance_profile != null:
		return population_appearance_profile
	var settlement := _get_ancestor_settlement()
	if settlement != null:
		# Live inheritance: ask the town for ITS effective profile (own field,
		# then definition, then faction) — changing the town changes every
		# inheriting facility. The subtree scan is only a legacy fallback and
		# must not run first: it would pick up sibling facilities' overrides.
		if settlement.has_method("get_effective_population_appearance_profile"):
			var town_profile := settlement.call("get_effective_population_appearance_profile") as Resource
			if town_profile != null:
				return town_profile
		var found := _find_population_appearance_profile(settlement)
		if found != null:
			return found
	return _definition_chain_population_profile("population_appearance_profile")


func _get_effective_population_name_profile() -> Resource:
	if population_name_profile != null:
		return population_name_profile
	var settlement := _get_ancestor_settlement()
	if settlement != null and settlement.has_method("get_effective_population_name_profile"):
		var town_effective := settlement.call("get_effective_population_name_profile") as Resource
		if town_effective != null:
			return town_effective
	if settlement != null and _has_property(settlement, "population_name_profile"):
		var town_profile := settlement.get("population_name_profile") as Resource
		if town_profile != null:
			return town_profile
	var definition := _get_ancestor_settlement_definition()
	var profile: Resource = null
	if definition != null and definition.has_method("get_population_name_profile"):
		profile = definition.call("get_population_name_profile") as Resource
	elif definition != null:
		profile = definition.get("population_name_profile") as Resource
	if profile != null:
		return profile
	return _definition_chain_population_profile("population_name_profile")


## Settlement-definition fallback chain: the definition's own generator
## profile, then its faction's. Facility and town node overrides are checked
## by the callers before reaching here.
func _definition_chain_population_profile(property_name: String) -> Resource:
	var definition := _get_ancestor_settlement_definition()
	if definition == null:
		return null
	var profile := definition.get(property_name) as Resource
	if profile != null:
		return profile
	var faction := definition.get("faction_definition") as Resource
	if faction != null:
		return faction.get(property_name) as Resource
	return null


func _find_population_appearance_profile(root: Node) -> Resource:
	if root == null:
		return null
	# Sibling facilities' overrides are facility-local, not town defaults.
	if root != self and root is SettlementFacility and not root.is_ancestor_of(self):
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
	return use_settlement_population_for_staff and not Engine.is_editor_hint() and _get_ancestor_settlement() != null


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


func _collect_visitor_seats(root: Node, seats: Array[Node]) -> void:
	if root == null:
		return
	if _is_sittable_furniture(root):
		seats.append(root)
		return
	for child in root.get_children():
		_collect_visitor_seats(child, seats)


func _is_sittable_furniture(node: Node) -> bool:
	return node != null and node.has_method("claim_sitter") and node.has_method("get_seat_position")


func _send_barber_to_seat(actor: Node) -> void:
	if actor == null or Engine.is_editor_hint():
		return
	if actor.has_method("is_sitting") and bool(actor.call("is_sitting")):
		return
	var seat := _barber_seat_for_actor(actor)
	if seat != null and _seat_bar_occupant(actor, seat):
		return


func _barber_seat_for_actor(actor: Node) -> Node:
	var seats: Array[Node] = []
	_collect_visitor_seats(get_node_or_null(furniture_root_path), seats)
	if seats.is_empty():
		return null
	var target_position := _barber_idle_position()
	return _nearest_available_seat(actor, seats, target_position)


func _seat_bar_occupant(actor: Node, seat: Node) -> bool:
	if actor == null or seat == null:
		return false
	if actor.has_method("sit_at_seat_immediately") and bool(actor.call("sit_at_seat_immediately", seat)):
		return true
	if actor.has_method("assign_seat_target"):
		actor.call("assign_seat_target", seat, false)
		return true
	return false


func _nearest_available_seat(actor: Node, seats: Array[Node], target_position: Vector3) -> Node:
	var best: Node
	var best_distance := INF
	for seat in seats:
		if not _seat_available_for_actor(seat, actor):
			continue
		var seat_node := seat as Node3D
		if seat_node == null or not seat_node.is_inside_tree():
			continue
		var distance := seat_node.global_position.distance_squared_to(target_position)
		if distance < best_distance:
			best_distance = distance
			best = seat
	return best


func _seat_available_for_actor(seat: Node, actor: Node) -> bool:
	if seat == null:
		return false
	if seat.has_method("is_occupied") and bool(seat.call("is_occupied")):
		return seat.has_method("get_sitter") and seat.call("get_sitter") == actor
	return true


func _barber_idle_position() -> Vector3:
	return global_transform * _barber_idle_transform().origin


func _send_actor_to_service_point(actor: Node, role: String) -> void:
	if actor == null or Engine.is_editor_hint() or not actor.has_method("set_move_target"):
		return
	var service_area := get_bar_service_area()
	if service_area == null:
		return
	if role == "barkeeper" and service_area.has_method("get_barkeeper_service_point"):
		var counter = service_area.call("get_barkeeper_service_point")
		if counter != null and counter.has_method("get_work_position"):
			actor.call("set_move_target", counter.call("get_work_position"), false)
		return
	if not service_area.has_method("get_service_points"):
		return
	for point in service_area.call("get_service_points"):
		if point != null and point.has_method("is_point_role") and bool(point.call("is_point_role", role)) and point.has_method("get_work_position"):
			actor.call("set_move_target", point.call("get_work_position"), false)
			return


func _get_staff_id_prefix() -> String:
	if not staff_stable_id_prefix.is_empty():
		return staff_stable_id_prefix
	return "npc.%s" % get_facility_id()


func _get_bar_squad_name() -> String:
	if not staff_squad_name.is_empty():
		return staff_squad_name
	return get_facility_id()


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


func _get_ancestor_settlement_id() -> String:
	var definition := _get_ancestor_settlement_definition()
	var definition_id := _resource_definition_id(definition)
	if not definition_id.is_empty():
		return _to_snake_id(definition_id)
	var settlement := _get_ancestor_settlement()
	return _to_snake_id(settlement.name) if settlement != null else ""


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


func _set_node_path_property(target: Object, property_name: String, value: String) -> void:
	if _has_property(target, property_name):
		target.set(property_name, NodePath(value))


func _get_current_building() -> Node:
	var root := get_building_root()
	if root == null:
		return null
	for child in root.get_children():
		var building := _find_building_with_level_content(child)
		if building != null:
			return building
	return null


func _find_building_with_level_content(root: Node) -> Node:
	if root.has_method("register_extra_level_content"):
		return root
	for child in root.get_children():
		var building := _find_building_with_level_content(child)
		if building != null:
			return building
	return null


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
