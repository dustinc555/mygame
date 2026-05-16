@tool
extends "res://scripts/world_sim/settlement_facility_instance.gd"

class_name SettlementBar

const BAR_FUNCTION = preload("res://resources/world_sim/facility_functions/bar.tres")
const BAR_SERVICE_AREA_SCRIPT = preload("res://scripts/world/venues/bar_service_area.gd")
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
const DEFAULT_BUILDING_SCENE = preload("res://scenes/world/buildings/bar_scene.tscn")
const TABLE_SCENE = preload("res://scenes/world/props/bar_table.tscn")
const STOOL_SCENE = preload("res://scenes/world/props/stool_chair.tscn")
const BED_SCENE = preload("res://scenes/world/props/simple_bed.tscn")

@export var bar_service_area_path: NodePath = NodePath("BarServiceArea")
@export var guard_posts_root_path: NodePath = NodePath("GuardPosts")
@export var furniture_root_path: NodePath = NodePath("Furniture")
@export var auto_create_default_building := true
@export var barkeeper_name := "Barkeeper"
@export var waiter_name := "Waiter"
@export var guard_name := "Bar Guard"
@export_range(1, 12, 1) var waiter_count: int = 1:
	set(value):
		waiter_count = _clamp_count(value, 1, 12)
		_repair_authoring_tree()
@export_range(0, 12, 1) var waiter_point_count: int = 1:
	set(value):
		waiter_point_count = _clamp_count(value, 0, 12)
		_repair_authoring_tree()
@export_range(0, 12, 1) var guard_count: int = 1:
	set(value):
		guard_count = _clamp_count(value, 0, 12)
		_repair_authoring_tree()
@export_range(0, 12, 1) var guard_post_count: int = 1:
	set(value):
		guard_post_count = _clamp_count(value, 0, 12)
		_repair_authoring_tree()
@export var staff_stable_id_prefix := ""
@export var staff_squad_name := ""
@export var sync_staff_from_owner := true
@export_range(0, 8, 1) var beds_building_level_index := 1


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
	_ensure_bar_service_area()
	_ensure_default_building()
	_ensure_furniture()
	_ensure_staff()
	_ensure_guard_and_service_points()
	_sync_bar_authoring()
	_sync_building_level_content()


func get_bar_service_area() -> Node:
	return get_node_or_null(bar_service_area_path)


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


func _ensure_furniture() -> void:
	var furniture := _ensure_root(furniture_root_path)
	var tables := _ensure_child_root(furniture, "Tables")
	var stools := _ensure_child_root(furniture, "Stools")
	var beds := _ensure_child_root(furniture, "Beds")
	_ensure_scene_child(tables, "TableA", TABLE_SCENE, Transform3D(Basis(Vector3.UP, deg_to_rad(4.0)), Vector3(1.25, 0.0, 1.25)))
	_ensure_scene_child(stools, "StoolAFront", STOOL_SCENE, Transform3D(Basis(Vector3.UP, deg_to_rad(184.0)), Vector3(1.25, 0.0, 2.55)))
	_ensure_scene_child(stools, "StoolABack", STOOL_SCENE, Transform3D(Basis(Vector3.UP, deg_to_rad(4.0)), Vector3(1.25, 0.0, -0.05)))
	_ensure_scene_child(beds, "BedA", BED_SCENE, Transform3D(Basis(Vector3.UP, deg_to_rad(-90.0)), Vector3(2.5, 3.0, -2.3)))
	_ensure_scene_child(beds, "BedB", BED_SCENE, Transform3D(Basis(Vector3.UP, deg_to_rad(-90.0)), Vector3(2.5, 3.0, 0.0)))
	_ensure_scene_child(beds, "BedC", BED_SCENE, Transform3D(Basis(Vector3.UP, deg_to_rad(-90.0)), Vector3(2.5, 3.0, 2.3)))


func _ensure_staff() -> void:
	var staff_root := _ensure_root(staff_root_path)
	var barkeeper := _ensure_staff_member(staff_root, "Barkeeper", barkeeper_name, Color(0.58, 0.43, 0.2, 1.0), Vector3(-0.15, 0.6, -2.85), SHOPKEEPER_CONVERSATION)
	_ensure_merchant_role(barkeeper)
	_ensure_job_provider(barkeeper)
	_sync_job_provider_jobs(barkeeper.get_node_or_null("JobProvider") if barkeeper != null else null)
	for waiter_index in range(waiter_count):
		_ensure_staff_member(staff_root, _indexed_name("Waiter", waiter_index), _indexed_display_name(waiter_name, waiter_index), Color(0.28, 0.47, 0.56, 1.0), _waiter_local_position(waiter_index), WAITER_CONVERSATION)
	_trim_generated_children(staff_root, "Waiter", waiter_count)
	for guard_index in range(guard_count):
		var guard := _ensure_staff_member(staff_root, _indexed_name("Guard", guard_index), _indexed_display_name(guard_name, guard_index), Color(0.42, 0.42, 0.48, 1.0), _guard_local_position(guard_index), null)
		if _has_property(guard, "base_attack_damage"):
			guard.set("base_attack_damage", 20.0)
	_trim_generated_children(staff_root, "Guard", guard_count)


func _ensure_guard_and_service_points() -> void:
	var guard_posts := _ensure_root(guard_posts_root_path)
	var service_points := _ensure_root(service_points_root_path)
	_migrate_legacy_guard_post_names(guard_posts)
	for guard_index in range(guard_post_count):
		_ensure_guard_post(guard_posts, _guard_post_name(guard_index), _guard_post_transform(guard_index))
	_trim_generated_children(guard_posts, "GuardPost", guard_post_count)
	_ensure_service_point(service_points, "BarkeeperCounterPoint", Transform3D(Basis(Vector3.UP, deg_to_rad(40.0)), Vector3(0.0, 0.35, -1.85)), "barkeeper", Color(0.36, 1.0, 0.48, 0.76))
	for waiter_index in range(waiter_point_count):
		_ensure_service_point(service_points, _waiter_point_name(waiter_index), _waiter_point_transform(waiter_index), "waiter", Color(0.0, 0.82, 0.78, 0.76))
	_trim_generated_children(service_points, "WaiterPoint", waiter_point_count)


func _sync_bar_authoring() -> void:
	var service_area := get_bar_service_area()
	if service_area == null:
		return
	var barkeeper := get_node_or_null("Staff/Barkeeper")
	var waiter := get_node_or_null("Staff/Waiter")
	if _has_property(service_area, "service_area_id"):
		var current_service_area_id := str(service_area.get("service_area_id"))
		if current_service_area_id.is_empty() or current_service_area_id.begins_with("settlement_bar."):
			service_area.set("service_area_id", "%s.service_area" % get_facility_id())
	if not owner_faction_id.is_empty() and _has_property(service_area, "owner_faction_name"):
		service_area.set("owner_faction_name", owner_faction_id)
	if _has_property(service_area, "owner_character_path"):
		service_area.set("owner_character_path", service_area.get_path_to(barkeeper))
	if _has_property(service_area, "waiter_character_path"):
		service_area.set("waiter_character_path", service_area.get_path_to(waiter))
	_set_node_path_property(service_area, "beds_root_path", "../Furniture/Beds")
	_set_node_path_property(service_area, "seats_root_path", "../Furniture/Stools")
	_set_node_path_property(service_area, "tables_root_path", "../Furniture/Tables")
	_set_node_path_property(service_area, "guard_posts_root_path", "../GuardPosts")
	_set_node_path_property(service_area, "service_points_root_path", "../ServicePoints")
	_set_node_path_property(service_area, "guards_root_path", "../Staff")
	_set_node_path_property(service_area, "waiters_root_path", "../Staff")
	_sync_staff_member(barkeeper, "barkeeper")
	for waiter_index in range(waiter_count):
		_sync_staff_member(get_node_or_null("Staff/%s" % _indexed_name("Waiter", waiter_index)), _indexed_name("waiter", waiter_index))
	for guard_index in range(guard_count):
		_sync_staff_member(get_node_or_null("Staff/%s" % _indexed_name("Guard", guard_index)), _indexed_name("guard", guard_index))
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
		_register_building_level_content(building, 0, get_node_or_null("%s/Tables" % str(furniture_root_path)))
		_register_building_level_content(building, 0, get_node_or_null("%s/Stools" % str(furniture_root_path)))
		_register_building_level_content(building, beds_building_level_index, get_node_or_null("%s/Beds" % str(furniture_root_path)))


func _register_building_level_content(building: Node, level_index: int, content: Node) -> void:
	if content == null:
		return
	building.call("register_extra_level_content", level_index, building.get_path_to(content))


func _ensure_service_point(root: Node, point_name: String, point_transform: Transform3D, role: String, color: Color) -> Node:
	var point := root.get_node_or_null(point_name)
	if point == null:
		point = Node3D.new()
		point.name = point_name
		point.transform = point_transform
		point.set_script(BAR_SERVICE_POINT_SCRIPT)
		root.add_child(point)
		_set_editor_owner(point)
	elif not point.has_method("get_work_position"):
		point.set_script(BAR_SERVICE_POINT_SCRIPT)
	if _has_property(point, "point_role"):
		point.set("point_role", role)
	if _has_property(point, "debug_color"):
		point.set("debug_color", color)
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
	elif not post.has_method("get_work_position"):
		post.set_script(BAR_GUARD_POST_SCRIPT)
	_refresh_authoring_marker(post)
	return post


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


func _sync_job_provider_jobs(provider: Node) -> void:
	if provider == null or not _has_property(provider, "jobs"):
		return
	var provider_jobs: Array = provider.get("jobs")
	for job in provider_jobs:
		if job == null:
			continue
		match str(job.get("algorithm_id")):
			"guard_post":
				job.set("slot_count", max(guard_count, 1))
			"server_shift":
				job.set("slot_count", max(waiter_count, 1))


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


func _indexed_name(base_name: String, index: int) -> String:
	return base_name if index == 0 else "%s%d" % [base_name, index + 1]


func _indexed_display_name(base_name: String, index: int) -> String:
	return base_name if index == 0 else "%s %d" % [base_name, index + 1]


func _waiter_point_name(index: int) -> String:
	return _indexed_name("WaiterPoint", index)


func _guard_post_name(index: int) -> String:
	return _indexed_name("GuardPost", index)


func _waiter_point_transform(index: int) -> Transform3D:
	var column := index % 4
	var row := int(index / 4)
	return Transform3D(Basis(Vector3.UP, deg_to_rad(8.0)), Vector3(-1.25 + float(column) * 0.75, 0.35, 0.65 + float(row) * 0.9))


func _guard_post_transform(index: int) -> Transform3D:
	if index == 0:
		return Transform3D(Basis(Vector3.UP, deg_to_rad(-85.0)), Vector3(0.0, 0.05, 3.45))
	var guard_index := index - 1
	var column := guard_index % 3
	var row := int(guard_index / 3)
	return Transform3D(Basis(Vector3.UP, deg_to_rad(-85.0)), Vector3(-1.4 + float(column) * 1.4, 0.05, 4.25 + float(row) * 0.85))


func _waiter_local_position(index: int) -> Vector3:
	var point_transform := _waiter_point_transform(index)
	return Vector3(point_transform.origin.x, 0.6, point_transform.origin.z)


func _guard_local_position(index: int) -> Vector3:
	var post_transform := _guard_post_transform(index)
	return Vector3(post_transform.origin.x, 0.6, post_transform.origin.z + 1.15)


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
	for child in root.get_children():
		var child_index := _generated_child_index(str(child.name), base_name)
		if child_index >= kept_count:
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
