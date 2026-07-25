@tool
@icon("res://addons/world_authoring/icons/town.svg")
extends "res://features/settlements/bridge/settlement_anchor.gd"

class_name SettlementTown

const SETTLEMENT_GUARD_POST_SCRIPT = preload("res://features/settlements/bridge/venues/settlement_guard_post.gd")
const STAFF_ROLE_OWNER_GROUP := "settlement_staff_role_owner"
const META_SETTLEMENT_ROLE := "settlement_staff_role"
const META_SETTLEMENT_ROLE_INDEX := "settlement_staff_role_index"
const META_SETTLEMENT_SLOT_ID := "settlement_staff_slot_id"
const DEFAULT_REPLACEMENT_DELAY_DAYS := 7.0

@export var facilities_root_path: NodePath = NodePath("Facilities")
@export var keeps_root_path: NodePath = NodePath("Keeps")
@export var bars_root_path: NodePath = NodePath("Bars")
@export var fields_root_path: NodePath = NodePath("Fields")
@export var shops_root_path: NodePath = NodePath("Shops")
@export var mines_root_path: NodePath = NodePath("Mines")
@export var housing_root_path: NodePath = NodePath("Housing")
@export var activity_points_root_path: NodePath = NodePath("ActivityPoints")
@export var storage_root_path: NodePath = NodePath("Storage")
@export var territory_root_path: NodePath = NodePath("Territory")
@export var guards_root_path: NodePath = NodePath("Guards")
@export var guard_posts_root_path: NodePath = NodePath("GuardPosts")
# Guard/staff counts, naming, and realization policy live on the
# SettlementDefinition — the single sim-truth home the Town dock edits.
# These properties proxy the definition so readers keep property access;
# realization policy additionally accepts a runtime placement override
# written by the zone/world loaders.
var guard_count: int:
	get:
		var definition := _settlement_definition_typed()
		return clampi(definition.guard_count, 0, 24) if definition != null else 0
var guard_post_count: int:
	get:
		var definition := _settlement_definition_typed()
		return clampi(definition.guard_post_count, 0, 24) if definition != null else 0
var guard_name: String:
	get:
		var definition := _settlement_definition_typed()
		return definition.get_guard_name() if definition != null else "Town Guard"
var staff_stable_id_prefix: String:
	get:
		var definition := _settlement_definition_typed()
		return definition.staff_stable_id_prefix if definition != null else ""
var staff_squad_name: String:
	get:
		var definition := _settlement_definition_typed()
		return definition.staff_squad_name if definition != null else ""
var use_settlement_population_for_guards: bool:
	get:
		var definition := _settlement_definition_typed()
		return definition.use_settlement_population_for_guards if definition != null else true
var actor_realization_policy: String:
	get:
		if not _realization_policy_override.is_empty():
			return _realization_policy_override
		var definition := _settlement_definition_typed()
		return definition.get_actor_realization_policy() if definition != null else ""
	set(value):
		_realization_policy_override = str(value).strip_edges()
@export var auto_town_border_from_footprint := true:
	set(value):
		auto_town_border_from_footprint = value
		_refresh_town_border_debug()
@export var town_border_radius := 24.0:
	set(value):
		town_border_radius = value
		_refresh_town_border_debug()
@export_range(0.0, 30.0, 0.5) var town_border_padding := 6.0:
	set(value):
		town_border_padding = maxf(0.0, float(value))
		_refresh_town_border_debug()
@export_range(0.25, 10.0, 0.25) var town_border_dash_length := 2.0:
	set(value):
		town_border_dash_length = maxf(0.25, float(value))
		_refresh_town_border_debug()
@export_range(0.0, 10.0, 0.25) var town_border_dash_gap := 1.0:
	set(value):
		town_border_dash_gap = maxf(0.0, float(value))
		_refresh_town_border_debug()
@export var town_border_debug_color := Color(0.62, 1.0, 0.94, 0.34):
	set(value):
		town_border_debug_color = value
		_refresh_town_border_debug()
@export var editor_show_debug_shape := true:
	set(value):
		editor_show_debug_shape = value
		_sync_town_border_debug_visibility()

var _town_border_debug: MeshInstance3D
var _town_border_refresh_timer := 0.0
var _last_town_border_signature := ""
var _last_border_watch_signature := 0
var _realization_policy_override := ""
var _last_guard_authoring_signature := ""


func _settlement_definition_typed() -> SettlementDefinition:
	return settlement_definition as SettlementDefinition


func _enter_tree() -> void:
	call_deferred("_refresh_town_border_debug")


func _ready() -> void:
	super._ready()
	add_to_group("settlement_town")
	add_to_group(STAFF_ROLE_OWNER_GROUP)
	set_process(Engine.is_editor_hint())
	_repair_guard_authoring_tree()
	_refresh_town_border_debug()
	if not Engine.is_editor_hint():
		_register_with_population_realization.call_deferred()


func _exit_tree() -> void:
	if Engine.is_editor_hint() or get_tree() == null:
		return
	var settlement_controller := get_tree().get_first_node_in_group("settlement_controller")
	if settlement_controller != null and settlement_controller.has_method("unregister_settlement_anchor"):
		settlement_controller.call("unregister_settlement_anchor", self)
	var controller := get_tree().get_first_node_in_group("population_realization_controller")
	if controller != null and controller.has_method("unregister_settlement"):
		controller.call("unregister_settlement", self)


func _register_with_population_realization() -> void:
	if not is_inside_tree() or get_tree() == null:
		return
	var settlement_controller := get_tree().get_first_node_in_group("settlement_controller")
	if settlement_controller != null and settlement_controller.has_method("register_settlement_anchor"):
		settlement_controller.call("register_settlement_anchor", self)
	var controller := get_tree().get_first_node_in_group("population_realization_controller")
	if controller != null and controller.has_method("register_settlement"):
		controller.call("register_settlement", self)


func _process(delta: float) -> void:
	if not Engine.is_editor_hint():
		return
	_town_border_refresh_timer -= delta
	if _town_border_refresh_timer > 0.0:
		return
	_town_border_refresh_timer = 0.25
	_poll_guard_authoring_signature()
	if editor_show_debug_shape:
		# Cheap watch first: integer-hash facility identities/transforms and
		# modular piece transforms. The deep bounds recompute only runs when
		# something actually changed — an idle editor pays ~nothing here.
		var watch := _border_watch_signature()
		if watch != _last_border_watch_signature:
			_last_border_watch_signature = watch
			_refresh_town_border_debug_if_changed()


## Guard counts now live on the definition .tres, which has no setter hook
## into this node — poll the authored values in the editor so the generated
## guard/post tree tracks Town dock and inspector edits.
func _poll_guard_authoring_signature() -> void:
	var signature := "%d:%d:%s" % [guard_count, guard_post_count, use_settlement_population_for_guards]
	if signature == _last_guard_authoring_signature:
		return
	_last_guard_authoring_signature = signature
	_repair_guard_authoring_tree()


func get_facility_nodes() -> Array:
	# Facilities are direct town children (flat model); the recursive walk
	# also still finds anything under legacy container roots ("Facilities").
	var facilities: Array = []
	_collect_facilities(self, facilities)
	return facilities


## Flat-model composed facilities standing directly under the town root.
func get_direct_facility_children() -> Array:
	var result: Array = []
	for child in get_children():
		if child is Node3D and child.has_method("get_facility_record"):
			result.append(child)
	return result


func get_facility_records() -> Array[Dictionary]:
	var records: Array[Dictionary] = []
	var settlement_id := get_settlement_id()
	for facility in get_facility_nodes():
		if facility.has_method("get_facility_record"):
			records.append(facility.call("get_facility_record", settlement_id))
	return records


func get_activity_points() -> Array:
	var points: Array = []
	var activity_root := get_node_or_null(activity_points_root_path)
	if activity_root != null:
		_collect_activity_points(activity_root, points)
	for facility in get_facility_nodes():
		if facility.has_method("get_activity_points"):
			for point in facility.call("get_activity_points"):
				if not points.has(point):
					points.append(point)
	return points


func get_job_provider_nodes() -> Array:
	var providers: Array = []
	_collect_nodes_with_group(self, "job_provider", providers)
	return providers


func get_bar_service_area_nodes() -> Array:
	var service_areas: Array = []
	_collect_nodes_with_group(self, "bar_service_area", service_areas)
	return service_areas


func get_settlement_staff_slots() -> Array[Dictionary]:
	var slots: Array[Dictionary] = []
	for index in range(guard_count):
		var actor := _get_guard_actor_for_slot(index)
		_append_guard_slot(slots, index, actor)
	return slots


func get_staff_realization_parent() -> Node3D:
	return _ensure_child_root(guards_root_path)


func configure_settlement_staff_actor(actor: Node, slot_id: String, slot_record: Dictionary) -> void:
	var role_index: int = max(0, int(slot_record.get("role_index", _role_index_from_slot_id(slot_id))))
	var guards_root := _ensure_child_root(guards_root_path)
	if actor == null or guards_root == null:
		return
	actor.name = _available_child_name(guards_root, _indexed_name("Guard", role_index))
	_prepare_guard_actor(actor, role_index)


func get_guard_actors() -> Array[Node]:
	var guards: Array[Node] = []
	var root := get_node_or_null(guards_root_path)
	if root == null:
		return guards
	for child in root.get_children():
		if child is HumanoidCharacter and _is_actor_alive(child):
			guards.append(child)
	return guards


func get_guard_posts() -> Array[Node]:
	var root := get_node_or_null(guard_posts_root_path)
	var posts: Array[Node] = []
	if root == null:
		return posts
	for child in root.get_children():
		posts.append(child)
	return posts


func get_available_guard_post(worker: HumanoidCharacter, excluded_post = null):
	for post in get_guard_posts():
		if post == null or post == excluded_post:
			continue
		if post.has_method("is_available_for") and not post.call("is_available_for", worker):
			continue
		return post
	return null


func get_town_border_record() -> Dictionary:
	var shape := _get_town_border_shape()
	shape["settlement_id"] = get_settlement_id()
	shape["display_name"] = str(settlement_definition.get("display_name")) if settlement_definition != null else str(name)
	return shape


func contains_town_border_position(world_position: Vector3) -> bool:
	var shape := _get_town_border_shape()
	match str(shape.get("shape_mode", "circle")):
		"box":
			var local := to_local(world_position)
			var bounds_min: Vector2 = shape.get("bounds_min", Vector2.ZERO)
			var bounds_max: Vector2 = shape.get("bounds_max", Vector2.ZERO)
			return Rect2(bounds_min, bounds_max - bounds_min).has_point(Vector2(local.x, local.z))
		_:
			var radius := float(shape.get("radius", town_border_radius))
			if radius <= 0.0:
				return false
			var flat_center := Vector2(global_position.x, global_position.z)
			var flat_position := Vector2(world_position.x, world_position.z)
			return flat_center.distance_to(flat_position) <= radius


func set_town_border_debug_visible(value: bool) -> void:
	if _town_border_debug == null or not is_instance_valid(_town_border_debug):
		_create_town_border_debug()
	if _town_border_debug != null:
		_town_border_debug.visible = editor_show_debug_shape if Engine.is_editor_hint() else value


func _repair_guard_authoring_tree() -> void:
	if not is_inside_tree():
		return
	# Guard roots exist only when guards are actually authored: a town with
	# zero guard counts stays a minimal root + Facilities scene.
	var effective_posts: int = max(guard_count, guard_post_count)
	var wants_guards := guard_count > 0 and (Engine.is_editor_hint() or not use_settlement_population_for_guards)
	var guards_root := _ensure_child_root(guards_root_path) if wants_guards else get_node_or_null(guards_root_path)
	var posts_root := _ensure_child_root(guard_posts_root_path) if effective_posts > 0 else get_node_or_null(guard_posts_root_path)
	if posts_root != null:
		for index in range(effective_posts):
			_ensure_guard_post(posts_root, index)
		_trim_generated_children(posts_root, "GuardPost", effective_posts)
	if guards_root != null and (Engine.is_editor_hint() or not use_settlement_population_for_guards):
		for index in range(guard_count):
			_ensure_guard_actor(guards_root, index)
		_trim_generated_children(guards_root, "Guard", guard_count)


func _append_guard_slot(slots: Array[Dictionary], role_index: int, actor: Node) -> void:
	var actor_dead := actor != null and int(actor.get("life_state")) == NpcRules.LifeState.DEAD
	var slot := {
		"slot_id": _staff_slot_id("guard", role_index),
		"role_id": "guard",
		"role_index": role_index,
		"display_name": _indexed_display_name(guard_name, role_index),
		"population_cost": 1,
		"replacement_delay_days": DEFAULT_REPLACEMENT_DELAY_DAYS,
		"filled": actor != null and not actor_dead,
		"authority_scope": "settlement_authority",
	}
	if actor_dead:
		slot["dead_actor_key"] = _actor_key(actor)
	slots.append(slot)


func _ensure_guard_post(root: Node, index: int) -> Node:
	var post_name := _indexed_name("GuardPost", index)
	var post := root.get_node_or_null(post_name)
	var post_transform := _guard_post_transform(index)
	if post == null:
		post = Node3D.new()
		post.name = post_name
		post.transform = post_transform
		post.set_script(SETTLEMENT_GUARD_POST_SCRIPT)
		root.add_child(post)
		_set_editor_owner(post)
	elif post is Node3D:
		post.transform = post_transform if not bool(post.get_meta("settlement_guard_post_custom", false)) else post.transform
	if not post.has_method("get_work_position"):
		post.set_script(SETTLEMENT_GUARD_POST_SCRIPT)
	if _has_property(post, "debug_color"):
		post.set("debug_color", Color(0.35, 0.78, 1.0, 0.76))
	post.set_meta("settlement_guard_post_generated", true)
	post.set_meta("settlement_guard_post_index", index)
	return post


func _ensure_guard_actor(root: Node, index: int) -> Node:
	var actor := root.get_node_or_null(_indexed_name("Guard", index))
	if actor != null and not _is_actor_alive(actor):
		actor = null
	if actor != null:
		_prepare_guard_actor(actor, index)
	return actor


func _prepare_guard_actor(actor: Node, index: int) -> void:
	if actor == null:
		return
	actor.set_meta(META_SETTLEMENT_ROLE, "guard")
	actor.set_meta(META_SETTLEMENT_ROLE_INDEX, index)
	actor.set_meta(META_SETTLEMENT_SLOT_ID, _staff_slot_id("guard", index))
	actor.set_meta("settlement_actor_category", "staff")
	if _has_property(actor, "member_name") and (str(actor.get("member_name")).strip_edges().is_empty() or str(actor.get("member_name")) == "Character"):
		actor.set("member_name", _indexed_display_name(guard_name, index))
	var faction_id := _get_settlement_faction_id()
	if not faction_id.is_empty() and _has_property(actor, "faction_name"):
		actor.set("faction_name", faction_id)
	if _has_property(actor, "squad_name"):
		actor.set("squad_name", _get_staff_squad_name())
	if _has_property(actor, "stable_id") and str(actor.get("stable_id")).strip_edges().is_empty():
		actor.set("stable_id", "%s.%s" % [_get_staff_id_prefix(), _indexed_name("guard", index)])
	if _has_property(actor, "auto_heal_enabled"):
		actor.set("auto_heal_enabled", true)
	if _has_property(actor, "auto_burn_rustdead_enabled"):
		actor.set("auto_burn_rustdead_enabled", true)
	if not Engine.is_editor_hint():
		if actor.has_method("set_settlement_authority"):
			actor.call("set_settlement_authority", true)
		if actor.has_method("set_private_security"):
			actor.call("set_private_security", false)
		if actor.has_method("set_faction_soldier"):
			actor.call("set_faction_soldier", true)
	if actor is Node3D:
		(actor as Node3D).position = _guard_local_position(index)


func _should_defer_guards_to_settlement_population() -> bool:
	return use_settlement_population_for_guards and not Engine.is_editor_hint()


func _get_guard_actor_for_slot(index: int) -> Node:
	var slot_id := _staff_slot_id("guard", index)
	var root := get_node_or_null(guards_root_path)
	if root == null:
		return null
	for child in root.get_children():
		if str(child.get_meta(META_SETTLEMENT_SLOT_ID, "")) == slot_id:
			return child
	return root.get_node_or_null(_indexed_name("Guard", index))


func _claim_available_resident_for_guard(index: int, guards_root: Node) -> Node:
	var resident_root := get_node_or_null(resident_root_path)
	if resident_root == null:
		return null
	for candidate in _collect_claimable_residents(resident_root):
		if not _can_claim_resident_for_guard(candidate):
			continue
		var candidate_global_transform := (candidate as Node3D).global_transform if candidate is Node3D else Transform3D.IDENTITY
		candidate.get_parent().remove_child(candidate)
		guards_root.add_child(candidate)
		if candidate is Node3D:
			(candidate as Node3D).global_transform = candidate_global_transform
		candidate.name = _available_child_name(guards_root, _indexed_name("Guard", index))
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


func _can_claim_resident_for_guard(actor: Node) -> bool:
	if not _is_actor_alive(actor):
		return false
	if actor.has_method("is_player_party_member") and bool(actor.call("is_player_party_member")):
		return false
	if str(actor.get_meta(META_SETTLEMENT_SLOT_ID, "")).strip_edges() != "":
		return false
	if actor.has_method("get_active_job_provider") and actor.call("get_active_job_provider") != null:
		return false
	return true


func _guard_post_transform(index: int) -> Transform3D:
	var side := -1.0 if index % 2 == 0 else 1.0
	var row := int(float(index) / 2.0)
	return Transform3D(Basis(Vector3.UP, deg_to_rad(90.0 * -side)), Vector3(7.0 * side, 0.05, -2.0 + float(row) * 2.0))


func _guard_local_position(index: int) -> Vector3:
	var post_transform := _guard_post_transform(index)
	return Vector3(post_transform.origin.x, 0.6, post_transform.origin.z)


func _staff_slot_id(role: String, index: int) -> String:
	return "%s.%s" % [get_settlement_id(), _indexed_name(role, index)]


func _role_index_from_slot_id(slot_id: String) -> int:
	var suffix := slot_id.get_slice(".", slot_id.get_slice_count(".") - 1)
	if suffix == "guard":
		return 0
	if suffix.begins_with("guard"):
		var index_text := suffix.substr("guard".length())
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
	var children: Array[Node] = []
	for child in root.get_children():
		var index := _generated_child_index(str(child.name), base_name)
		if index >= 0 and bool(child.get_meta("settlement_guard_post_generated", child.has_meta(META_SETTLEMENT_SLOT_ID))):
			children.append(child)
	for child_index in range(children.size()):
		if child_index < kept_count:
			continue
		var child := children[child_index]
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
	return actor != null and str(actor.get_meta(META_SETTLEMENT_ROLE, "")) == "guard"


## Public accessor for the owning faction id (the world-sim brains read this to decide
## raids and defenders). Resolves through the settlement/faction definitions.
func get_faction_id() -> String:
	return _get_settlement_faction_id()


func _get_settlement_faction_id() -> String:
	if settlement_definition != null and not Engine.is_editor_hint() and settlement_definition.has_method("get_faction_id"):
		return str(settlement_definition.call("get_faction_id"))
	return _settlement_definition_faction_id(settlement_definition)


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


func _get_staff_id_prefix() -> String:
	if not staff_stable_id_prefix.strip_edges().is_empty():
		return staff_stable_id_prefix
	return "npc.%s.town_guard" % get_settlement_id()


func _get_staff_squad_name() -> String:
	return staff_squad_name if not staff_squad_name.strip_edges().is_empty() else str(name)


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


func _ensure_child_root(root_path: NodePath) -> Node:
	if root_path.is_empty():
		return null
	var existing := get_node_or_null(root_path)
	if existing != null:
		return existing
	var root_name := str(root_path)
	if root_name.contains("/"):
		return null
	var root := Node3D.new()
	root.name = root_name
	add_child(root)
	_set_editor_owner(root)
	return root


func _has_property(target: Object, property_name: String) -> bool:
	if target == null:
		return false
	for property in target.get_property_list():
		if str(property.get("name", "")) == property_name:
			return true
	return false


func _set_editor_owner(node: Node) -> void:
	if not Engine.is_editor_hint():
		return
	var tree := get_tree()
	if tree == null or tree.edited_scene_root == null:
		return
	node.owner = tree.edited_scene_root


func _set_editor_owner_recursive(node: Node) -> void:
	_set_editor_owner(node)
	for child in node.get_children():
		_set_editor_owner_recursive(child)


func _collect_facilities(root: Node, facilities: Array) -> void:
	for child in root.get_children():
		if child.has_method("get_facility_record") and not facilities.has(child):
			facilities.append(child)
		_collect_facilities(child, facilities)


func _get_border_root_paths() -> Array[NodePath]:
	return [
		housing_root_path,
		facilities_root_path,
		bars_root_path,
		keeps_root_path,
		shops_root_path,
		storage_root_path,
	]


func _collect_activity_points(root: Node, points: Array) -> void:
	for child in root.get_children():
		if child.has_method("get_activity_record"):
			points.append(child)
		_collect_activity_points(child, points)


func _collect_nodes_with_group(root: Node, group_name: String, nodes: Array) -> void:
	if root.is_in_group(group_name) and not nodes.has(root):
		nodes.append(root)
	for child in root.get_children():
		_collect_nodes_with_group(child, group_name, nodes)


func _get_town_border_shape() -> Dictionary:
	if auto_town_border_from_footprint:
		var auto_rect := _get_auto_town_border_rect()
		if auto_rect.size.x > 0.0 and auto_rect.size.y > 0.0:
			var center_local := auto_rect.get_center()
			return {
				"shape_mode": "box",
				"center": global_transform * Vector3(center_local.x, 0.0, center_local.y),
				"bounds_min": auto_rect.position,
				"bounds_max": auto_rect.position + auto_rect.size,
				"radius": maxf(auto_rect.size.x, auto_rect.size.y) * 0.5,
				"polygon_points": PackedVector2Array([
					auto_rect.position,
					Vector2(auto_rect.position.x + auto_rect.size.x, auto_rect.position.y),
					auto_rect.position + auto_rect.size,
					Vector2(auto_rect.position.x, auto_rect.position.y + auto_rect.size.y),
				]),
			}
	return {
		"shape_mode": "circle",
		"center": global_position,
		"radius": town_border_radius,
		"bounds_min": Vector2(-town_border_radius, -town_border_radius),
		"bounds_max": Vector2(town_border_radius, town_border_radius),
		"polygon_points": _circle_points(town_border_radius, 96),
	}


func _get_auto_town_border_rect() -> Rect2:
	var bounds := {
		"has": false,
		"min": Vector2.ZERO,
		"max": Vector2.ZERO,
	}
	for facility in get_direct_facility_children():
		_collect_border_bounds(facility, bounds)
	for root_path in _get_border_root_paths():
		var root := get_node_or_null(root_path)
		if root == null:
			continue
		for child in root.get_children():
			_collect_border_bounds(child, bounds)
	if not bool(bounds["has"]):
		return Rect2()
	var min_point: Vector2 = bounds["min"]
	var max_point: Vector2 = bounds["max"]
	var padding := maxf(town_border_padding, 0.0)
	min_point -= Vector2.ONE * padding
	max_point += Vector2.ONE * padding
	return Rect2(min_point, max_point - min_point)


func _collect_border_bounds(node: Node, bounds: Dictionary) -> void:
	if _should_skip_border_subtree(node):
		return
	# Modular shells contribute their authored piece bounds — flat cost per
	# piece, never a recursion into piece scene internals, mesh AABBs, or
	# collision debug meshes. Shells without modular pieces (legacy authored
	# buildings) fall through to the per-mesh walk below.
	if node is Node3D and node.has_method("get_modular_pieces"):
		var pieces: Array = node.call("get_modular_pieces")
		if not pieces.is_empty():
			for piece_value in pieces:
				var piece := piece_value as Node3D
				if piece == null or not piece.is_inside_tree():
					continue
				var size_value = piece.get("bounds_size_meters")
				if size_value is Vector3:
					var size := size_value as Vector3
					var piece_bounds := AABB(Vector3(-size.x * 0.5, 0.0, -size.z * 0.5), size)
					for corner in _aabb_corners(piece_bounds):
						_expand_border_bounds(bounds, piece.global_transform * corner)
				else:
					_expand_border_bounds(bounds, piece.global_position)
			return
	if not _should_skip_border_node(node) and node is Node3D:
		_include_node3d_border_bounds(node as Node3D, bounds)
	for child in node.get_children():
		_collect_border_bounds(child, bounds)


## Cheap per-tick change detector for the editor border: integer-hashes the
## same node set the bounds walk reads (facility identities, transforms,
## modular piece transforms, child counts) without any AABB math or mesh
## access. The expensive bounds recompute runs only when this value moves.
func _border_watch_signature() -> int:
	var accumulator := hash([auto_town_border_from_footprint, town_border_radius, town_border_padding])
	if not auto_town_border_from_footprint:
		return accumulator
	for facility in get_direct_facility_children():
		accumulator = _accumulate_border_watch(accumulator, facility)
	for root_path in _get_border_root_paths():
		var root := get_node_or_null(root_path)
		if root == null:
			continue
		for child in root.get_children():
			accumulator = _accumulate_border_watch(accumulator, child)
	return accumulator


func _accumulate_border_watch(accumulator: int, node: Node) -> int:
	if _should_skip_border_subtree(node):
		return accumulator
	var node_3d := node as Node3D
	if node_3d != null and node_3d.is_inside_tree():
		accumulator = hash([accumulator, node.name, node_3d.transform, node.get_child_count()])
		if node.has_method("get_modular_pieces"):
			var pieces: Array = node.call("get_modular_pieces")
			if not pieces.is_empty():
				for piece_value in pieces:
					var piece := piece_value as Node3D
					if piece != null and piece.is_inside_tree():
						accumulator = hash([accumulator, piece.transform])
				return accumulator
	for child in node.get_children():
		accumulator = _accumulate_border_watch(accumulator, child)
	return accumulator


func _should_skip_border_subtree(node: Node) -> bool:
	if node == null:
		return true
	if node == _town_border_debug or str(node.name) in ["TownBorderDebug", "TerritoryDebug", "StateLabel"]:
		return true
	if str(node.name) in ["Staff", "GuardPosts", "ServicePoints", "JobProviders", "ActivityPoints"]:
		return true
	if node is Label3D:
		return true
	if node.has_method("get_activity_record"):
		return true
	return false


func _should_skip_border_node(node: Node) -> bool:
	if node == null:
		return true
	if str(node.name) in ["BuildingSlot", "Cells", "Lockers", "Storage", "ModelRoot"]:
		return true
	return false


func _include_node3d_border_bounds(node: Node3D, bounds: Dictionary) -> void:
	if not node.is_inside_tree():
		return
	var mesh_instance := node as MeshInstance3D
	if mesh_instance != null and mesh_instance.mesh != null:
		var aabb := mesh_instance.mesh.get_aabb()
		for corner in _aabb_corners(aabb):
			_expand_border_bounds(bounds, node.global_transform * corner)
		return
	var collision_shape := node as CollisionShape3D
	if collision_shape != null and collision_shape.shape != null:
		var debug_mesh := collision_shape.shape.get_debug_mesh()
		for corner in _aabb_corners(debug_mesh.get_aabb() if debug_mesh != null else AABB(Vector3.ZERO, Vector3.ZERO)):
			_expand_border_bounds(bounds, node.global_transform * corner)
		return
	if node.get_child_count() > 0:
		return
	_expand_border_bounds(bounds, node.global_position)


func _aabb_corners(aabb: AABB) -> Array[Vector3]:
	var end := aabb.position + aabb.size
	return [
		Vector3(aabb.position.x, aabb.position.y, aabb.position.z),
		Vector3(end.x, aabb.position.y, aabb.position.z),
		Vector3(aabb.position.x, aabb.position.y, end.z),
		Vector3(end.x, aabb.position.y, end.z),
		Vector3(aabb.position.x, end.y, aabb.position.z),
		Vector3(end.x, end.y, aabb.position.z),
		Vector3(aabb.position.x, end.y, end.z),
		Vector3(end.x, end.y, end.z),
	]


func _expand_border_bounds(bounds: Dictionary, world_position: Vector3) -> void:
	var local := to_local(world_position)
	var point := Vector2(local.x, local.z)
	if not bool(bounds["has"]):
		bounds["has"] = true
		bounds["min"] = point
		bounds["max"] = point
		return
	var min_point: Vector2 = bounds["min"]
	var max_point: Vector2 = bounds["max"]
	bounds["min"] = Vector2(minf(min_point.x, point.x), minf(min_point.y, point.y))
	bounds["max"] = Vector2(maxf(max_point.x, point.x), maxf(max_point.y, point.y))


func _town_border_outline_points(shape: Dictionary) -> PackedVector2Array:
	var points = shape.get("polygon_points", PackedVector2Array())
	if points is PackedVector2Array and points.size() >= 3:
		return points
	return _circle_points(float(shape.get("radius", town_border_radius)), 96)


func _circle_points(target_radius: float, segments: int) -> PackedVector2Array:
	var points := PackedVector2Array()
	if target_radius <= 0.0:
		return points
	for index in range(max(segments, 3)):
		var angle := TAU * float(index) / float(max(segments, 3))
		points.append(Vector2(cos(angle), sin(angle)) * target_radius)
	return points


func _build_dashed_outline_mesh(points: PackedVector2Array) -> ArrayMesh:
	var vertices := PackedVector3Array()
	if points.size() >= 2:
		for index in range(points.size()):
			var start := points[index]
			var end := points[0] if index == points.size() - 1 else points[index + 1]
			_append_dashed_edge(vertices, start, end)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, arrays)
	return mesh


func _append_dashed_edge(vertices: PackedVector3Array, start: Vector2, end: Vector2) -> void:
	var delta := end - start
	var length := delta.length()
	if length <= 0.001:
		return
	var direction := delta / length
	var dash := maxf(town_border_dash_length, 0.25)
	var gap := maxf(town_border_dash_gap, 0.0)
	var cursor := 0.0
	while cursor < length:
		var dash_end := minf(cursor + dash, length)
		var from := start + direction * cursor
		var to := start + direction * dash_end
		vertices.append(Vector3(from.x, 0.0, from.y))
		vertices.append(Vector3(to.x, 0.0, to.y))
		cursor += dash + gap


func _create_town_border_debug() -> void:
	var shape := _get_town_border_shape()
	var points := _town_border_outline_points(shape)
	if points.size() < 3:
		return
	_town_border_debug = get_node_or_null("TownBorderDebug") as MeshInstance3D
	if _town_border_debug == null:
		_town_border_debug = MeshInstance3D.new()
		_town_border_debug.name = "TownBorderDebug"
		add_child(_town_border_debug)
		_set_editor_owner(_town_border_debug)
	_town_border_debug.mesh = _build_dashed_outline_mesh(points)
	_town_border_debug.position = Vector3(0.0, 0.16, 0.0)
	_town_border_debug.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_town_border_debug.material_override = _make_debug_material(town_border_debug_color)
	_town_border_debug.visible = Engine.is_editor_hint() and editor_show_debug_shape


func _refresh_town_border_debug() -> void:
	if not is_inside_tree():
		return
	_create_town_border_debug()
	_last_town_border_signature = _town_border_signature(_get_town_border_shape())


func _refresh_town_border_debug_if_changed() -> void:
	if not is_inside_tree():
		return
	var shape := _get_town_border_shape()
	var signature := _town_border_signature(shape)
	if signature == _last_town_border_signature:
		return
	_last_town_border_signature = signature
	_create_town_border_debug()


func _sync_town_border_debug_visibility() -> void:
	if _town_border_debug == null or not is_instance_valid(_town_border_debug):
		return
	if Engine.is_editor_hint():
		_town_border_debug.visible = editor_show_debug_shape


func _make_debug_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = color
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.no_depth_test = true
	return material


func _town_border_signature(shape: Dictionary) -> String:
	var bounds_min: Vector2 = shape.get("bounds_min", Vector2.ZERO)
	var bounds_max: Vector2 = shape.get("bounds_max", Vector2.ZERO)
	return "%s:%.3f:%.3f:%.3f:%.3f" % [str(shape.get("shape_mode", "circle")), bounds_min.x, bounds_min.y, bounds_max.x, bounds_max.y]
