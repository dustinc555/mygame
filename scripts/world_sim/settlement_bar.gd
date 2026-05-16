@tool
extends "res://scripts/world_sim/settlement_facility_instance.gd"

class_name SettlementBar

const BAR_FUNCTION = preload("res://resources/world_sim/facility_functions/bar.tres")
const BAR_VENUE_SCRIPT = preload("res://scripts/world/venues/bar_venue.gd")
const MERCHANT_HUMANOID_SCRIPT = preload("res://scripts/characters/merchant_humanoid.gd")
const MERCHANT_ROLE_SCRIPT = preload("res://scripts/roles/merchant_role.gd")
const JOB_PROVIDER_SCRIPT = preload("res://scripts/jobs/job_provider.gd")
const JOB_DEFINITION_SCRIPT = preload("res://scripts/jobs/job_definition.gd")
const MERCHANT_PRICE_SCRIPT = preload("res://scripts/items/merchant_price.gd")
const MERCHANT_STOCK_SCRIPT = preload("res://scripts/items/merchant_stock.gd")
const BAR_GUARD_POST_SCRIPT = preload("res://scripts/world/venues/bar_guard_post.gd")
const BAR_SERVICE_POINT_SCRIPT = preload("res://scripts/world/venues/bar_service_point.gd")
const FOOD_ITEM = preload("res://resources/items/food.tres")
const SILVER_ITEM = preload("res://resources/items/silver.tres")
const SHOPKEEPER_CONVERSATION = preload("res://resources/conversations/generic_shopkeeper.tres")
const WAITER_CONVERSATION = preload("res://resources/conversations/waiter_order.tres")
const TABLE_SCENE = preload("res://scenes/world/props/bar_table.tscn")
const STOOL_SCENE = preload("res://scenes/world/props/stool_chair.tscn")
const BED_SCENE = preload("res://scenes/world/props/simple_bed.tscn")

@export var bar_venue_path: NodePath = NodePath("BarVenue")
@export var guard_posts_root_path: NodePath = NodePath("GuardPosts")
@export var furniture_root_path: NodePath = NodePath("Furniture")
@export var barkeeper_name := "Barkeeper"
@export var waiter_name := "Waiter"
@export var guard_name := "Bar Guard"
@export var staff_stable_id_prefix := ""
@export var staff_squad_name := ""
@export var sync_staff_from_owner := true


func _ready() -> void:
	_repair_authoring_tree()
	super._ready()


func _repair_authoring_tree() -> void:
	_apply_bar_defaults()
	super._repair_authoring_tree()
	if not is_inside_tree() or not auto_create_standard_roots:
		return
	_ensure_root(guard_posts_root_path)
	_ensure_root(furniture_root_path)
	_ensure_bar_venue()
	_ensure_furniture()
	_ensure_staff()
	_ensure_guard_and_service_points()
	_sync_bar_authoring()


func get_bar_venue() -> Node:
	return get_node_or_null(bar_venue_path)


func _apply_bar_defaults() -> void:
	if facility_function == null:
		facility_function = BAR_FUNCTION
	building_root_path = NodePath("BuildingSlot")
	staff_root_path = NodePath("Staff")
	service_points_root_path = NodePath("ServicePoints")
	storage_root_path = NodePath("Storage")
	job_providers_root_path = NodePath("JobProviders")
	activity_points_root_path = NodePath("ActivityPoints")
	facility_type = "bar"
	if display_name.is_empty() or display_name == "Facility":
		display_name = "Settlement Bar"


func _ensure_bar_venue() -> Node:
	var venue := get_bar_venue()
	if venue != null:
		return venue
	venue = Node3D.new()
	venue.name = "BarVenue"
	venue.set_script(BAR_VENUE_SCRIPT)
	add_child(venue)
	_set_editor_owner(venue)
	return venue


func _ensure_furniture() -> void:
	var furniture := _ensure_root(furniture_root_path)
	var tables := _ensure_child_root(furniture, "Tables")
	var stools := _ensure_child_root(furniture, "Stools")
	var beds := _ensure_child_root(furniture, "Beds")
	_ensure_scene_child(tables, "TableA", TABLE_SCENE, Transform3D(Basis(Vector3.UP, deg_to_rad(4.0)), Vector3(1.25, 0.0, 1.25)))
	_ensure_scene_child(stools, "StoolAFront", STOOL_SCENE, Transform3D(Basis(Vector3.UP, deg_to_rad(184.0)), Vector3(1.25, 0.0, 2.55)))
	_ensure_scene_child(stools, "StoolABack", STOOL_SCENE, Transform3D(Basis(Vector3.UP, deg_to_rad(4.0)), Vector3(1.25, 0.0, -0.05)))
	_ensure_scene_child(beds, "BedA", BED_SCENE, Transform3D(Basis(Vector3.UP, deg_to_rad(-90.0)), Vector3(2.5, 3.0, -2.3)))


func _ensure_staff() -> void:
	var staff_root := _ensure_root(staff_root_path)
	var barkeeper := _ensure_staff_member(staff_root, "Barkeeper", barkeeper_name, Color(0.58, 0.43, 0.2, 1.0), Vector3(-0.15, 0.6, -2.85), SHOPKEEPER_CONVERSATION)
	_ensure_merchant_role(barkeeper)
	_ensure_job_provider(barkeeper)
	_ensure_staff_member(staff_root, "Waiter", waiter_name, Color(0.28, 0.47, 0.56, 1.0), Vector3(-1.1, 0.6, 0.5), WAITER_CONVERSATION)
	var guard := _ensure_staff_member(staff_root, "Guard", guard_name, Color(0.42, 0.42, 0.48, 1.0), Vector3(0.0, 0.6, 4.6), null)
	if _has_property(guard, "base_attack_damage"):
		guard.set("base_attack_damage", 20.0)


func _ensure_guard_and_service_points() -> void:
	var guard_posts := _ensure_root(guard_posts_root_path)
	var service_points := _ensure_root(service_points_root_path)
	var guard_post := guard_posts.get_node_or_null("EntranceGuardPost")
	if guard_post == null:
		guard_post = Node3D.new()
		guard_post.name = "EntranceGuardPost"
		guard_post.transform = Transform3D(Basis(Vector3.UP, deg_to_rad(-85.0)), Vector3(0.0, 0.05, 3.45))
		guard_post.set_script(BAR_GUARD_POST_SCRIPT)
		guard_posts.add_child(guard_post)
		_set_editor_owner(guard_post)
	var service_point := service_points.get_node_or_null("BarkeeperCounterPoint")
	if service_point == null:
		service_point = Node3D.new()
		service_point.name = "BarkeeperCounterPoint"
		service_point.transform = Transform3D(Basis(Vector3.UP, deg_to_rad(40.0)), Vector3(0.0, 0.35, -1.85))
		service_point.set_script(BAR_SERVICE_POINT_SCRIPT)
		service_points.add_child(service_point)
		_set_editor_owner(service_point)


func _sync_bar_authoring() -> void:
	var venue := get_bar_venue()
	if venue == null:
		return
	var barkeeper := get_node_or_null("Staff/Barkeeper")
	var waiter := get_node_or_null("Staff/Waiter")
	if not owner_faction_id.is_empty() and _has_property(venue, "owner_faction_name"):
		venue.set("owner_faction_name", owner_faction_id)
	if _has_property(venue, "owner_character_path"):
		venue.set("owner_character_path", venue.get_path_to(barkeeper))
	if _has_property(venue, "waiter_character_path"):
		venue.set("waiter_character_path", venue.get_path_to(waiter))
	_set_node_path_property(venue, "beds_root_path", "../Furniture/Beds")
	_set_node_path_property(venue, "seats_root_path", "../Furniture/Stools")
	_set_node_path_property(venue, "tables_root_path", "../Furniture/Tables")
	_set_node_path_property(venue, "guard_posts_root_path", "../GuardPosts")
	_set_node_path_property(venue, "service_points_root_path", "../ServicePoints")
	for staff_record in [
		{"node": barkeeper, "role": "barkeeper"},
		{"node": waiter, "role": "waiter"},
		{"node": get_node_or_null("Staff/Guard"), "role": "guard"},
	]:
		_sync_staff_member(staff_record.get("node"), str(staff_record.get("role")))
	var job_provider := barkeeper.get_node_or_null("JobProvider") if barkeeper != null else null
	if job_provider != null and _has_property(job_provider, "bar_venue_path"):
		job_provider.set("bar_venue_path", job_provider.get_path_to(venue))


func _ensure_staff_member(root: Node, node_name: String, member_name: String, color: Color, local_position: Vector3, conversation: Resource) -> Node:
	var staff := root.get_node_or_null(node_name)
	if staff != null:
		return staff
	staff = CharacterBody3D.new()
	staff.name = node_name
	staff.position = local_position
	staff.set_script(MERCHANT_HUMANOID_SCRIPT)
	staff.set("base_color", color)
	staff.set("member_name", member_name)
	staff.set("stable_id", "%s.%s" % [_get_staff_id_prefix(), node_name.to_lower()])
	if conversation != null:
		staff.set("conversation_definition", conversation)
	_add_basic_humanoid_children(staff)
	root.add_child(staff)
	_set_editor_owner_recursive(staff)
	return staff


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
		var ring_mesh := CylinderMesh.new()
		ring_mesh.top_radius = 0.72
		ring_mesh.bottom_radius = 0.72
		ring_mesh.height = 0.05
		ring_mesh.radial_segments = 24
		ring.mesh = ring_mesh
		actor.add_child(ring)


func _ensure_merchant_role(barkeeper: Node) -> void:
	if barkeeper == null or barkeeper.get_node_or_null("MerchantRole") != null:
		return
	var role := Node.new()
	role.name = "MerchantRole"
	role.set_script(MERCHANT_ROLE_SCRIPT)
	role.set("prices", [_merchant_price(FOOD_ITEM), _merchant_price(SILVER_ITEM)])
	role.set("initial_stock", [_merchant_stock(FOOD_ITEM, 12), _merchant_stock(SILVER_ITEM, 100)])
	barkeeper.add_child(role)
	_set_editor_owner(role)


func _ensure_job_provider(barkeeper: Node) -> void:
	if barkeeper == null or barkeeper.get_node_or_null("JobProvider") != null:
		return
	var provider := Node.new()
	provider.name = "JobProvider"
	provider.set_script(JOB_PROVIDER_SCRIPT)
	provider.set("jobs", [_job_definition("Guard duty", "bar_guard", "guard_post", 20.0, 2), _job_definition("Serving tables", "bar_server", "server_shift", 20.0, 1)])
	provider.set("wage_item_definition", SILVER_ITEM)
	barkeeper.add_child(provider)
	_set_editor_owner(provider)


func _merchant_price(item: Resource) -> Resource:
	var price: Resource = MERCHANT_PRICE_SCRIPT.new()
	price.set("item_definition", item)
	return price


func _merchant_stock(item: Resource, quantity: int) -> Resource:
	var stock: Resource = MERCHANT_STOCK_SCRIPT.new()
	stock.set("item_definition", item)
	stock.set("quantity", quantity)
	return stock


func _job_definition(display: String, job_id: String, algorithm: String, interval: float, pay: int) -> Resource:
	var job: Resource = JOB_DEFINITION_SCRIPT.new()
	job.set("display_name", display)
	job.set("job_id", job_id)
	job.set("algorithm_id", algorithm)
	job.set("pay_interval_seconds", interval)
	job.set("pay_per_interval", pay)
	return job


func _ensure_child_root(parent: Node, root_name: String) -> Node:
	var child := parent.get_node_or_null(root_name)
	if child != null:
		return child
	child = Node3D.new()
	child.name = root_name
	parent.add_child(child)
	_set_editor_owner(child)
	return child


func _ensure_scene_child(parent: Node, child_name: String, scene: PackedScene, transform: Transform3D) -> Node:
	var child := parent.get_node_or_null(child_name)
	if child != null:
		return child
	child = scene.instantiate()
	child.name = child_name
	parent.add_child(child)
	if child is Node3D:
		(child as Node3D).transform = transform
	_set_editor_owner_recursive(child)
	return child


func _sync_staff_member(staff: Node, role: String) -> void:
	if staff == null:
		return
	if sync_staff_from_owner and not owner_faction_id.is_empty() and _has_property(staff, "faction_name"):
		staff.set("faction_name", owner_faction_id)
	if _has_property(staff, "squad_name") and not _get_bar_squad_name().is_empty():
		staff.set("squad_name", _get_bar_squad_name())
	if _has_property(staff, "stable_id"):
		var current_stable_id := str(staff.get("stable_id"))
		if current_stable_id.is_empty() or current_stable_id.begins_with("settlement_bar."):
			staff.set("stable_id", "%s.%s" % [_get_staff_id_prefix(), role])


func _get_staff_id_prefix() -> String:
	if not staff_stable_id_prefix.is_empty():
		return staff_stable_id_prefix
	return get_facility_id()


func _get_bar_squad_name() -> String:
	if not staff_squad_name.is_empty():
		return staff_squad_name
	return get_facility_id()


func _set_node_path_property(target: Object, property_name: String, value: String) -> void:
	if _has_property(target, property_name):
		target.set(property_name, NodePath(value))


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
