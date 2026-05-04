extends Node3D

class_name BarVenue

const SILVER_ITEM = preload("res://resources/items/silver.tres")

@export var venue_id := ""
@export var owner_character_path: NodePath
@export var owner_faction_name := ""
@export var currency_item: Resource = SILVER_ITEM
@export var bed_rent_price := 1
@export var bed_rent_duration_seconds := 3600.0
@export var beds_root_path: NodePath = NodePath("Furniture/Beds")
@export var seats_root_path: NodePath = NodePath("Furniture/Stools")
@export var tables_root_path: NodePath = NodePath("Furniture/Tables")
@export var guard_posts_root_path: NodePath = NodePath("GuardPosts")
@export var service_points_root_path: NodePath = NodePath("ServicePoints")
@export var waiter_character_path: NodePath = NodePath("Staff/Waiter")
@export var waiter_service_delay_seconds := 7.0
@export var waiter_service_distance := 2.4
@export var table_service_radius := 2.8

var _bed_rentals: Dictionary = {}
var _active_service_seat
var _active_service_customer: HumanoidCharacter
var _service_conversation_started := false
var inventory: InventoryData
var _trade_proxy_position := Vector3.ZERO
var _has_trade_proxy_position := false
var _proxied_owner: HumanoidCharacter

signal inventory_changed


func _ready() -> void:
	add_to_group("bar_venue")
	_register_scoped_children()
	_sync_trade_inventory()


func _process(_delta: float) -> void:
	_process_waiter_service()


func get_owner_character() -> HumanoidCharacter:
	return get_node_or_null(owner_character_path) as HumanoidCharacter


func get_owner_faction_name() -> String:
	if not owner_faction_name.is_empty():
		return owner_faction_name
	var owner_character := get_owner_character()
	return owner_character.faction_name if owner_character != null else ""


func get_barkeeper_inventory():
	var owner_character := get_owner_character()
	return owner_character.inventory if owner_character != null else null


func set_trade_proxy_position(world_position: Vector3) -> void:
	_trade_proxy_position = world_position
	_has_trade_proxy_position = true
	_sync_trade_inventory()


func get_inventory_for_display() -> InventoryData:
	_sync_trade_inventory()
	return inventory


func get_inventory_display_name() -> String:
	var owner_character := get_owner_character()
	if owner_character != null:
		return "%s Stock" % owner_character.member_name
	return "Bar Stock"


func get_inventory_display_title() -> String:
	return get_inventory_display_name()


func get_inventory_world_position() -> Vector3:
	if _has_trade_proxy_position:
		return _trade_proxy_position
	var owner_character := get_owner_character()
	return owner_character.global_position if owner_character != null else global_position


func get_inventory_cell_size() -> Vector2:
	var owner_character := get_owner_character()
	if owner_character != null and owner_character.has_method("get_inventory_cell_size"):
		return owner_character.get_inventory_cell_size()
	return Vector2(30.0, 30.0)


func shows_inventory_weight() -> bool:
	return false


func get_merchant_role() -> MerchantRole:
	var owner_character := get_owner_character()
	if owner_character != null and owner_character.has_method("get_merchant_role"):
		return owner_character.get_merchant_role()
	return null


func _sync_trade_inventory() -> bool:
	var owner_character := get_owner_character()
	if owner_character == null or owner_character.inventory == null:
		return false
	inventory = owner_character.inventory
	if _proxied_owner != owner_character:
		if _proxied_owner != null and _proxied_owner.inventory_changed.is_connected(_on_proxy_inventory_changed):
			_proxied_owner.inventory_changed.disconnect(_on_proxy_inventory_changed)
		_proxied_owner = owner_character
		if not _proxied_owner.inventory_changed.is_connected(_on_proxy_inventory_changed):
			_proxied_owner.inventory_changed.connect(_on_proxy_inventory_changed)
	return true


func _on_proxy_inventory_changed() -> void:
	inventory_changed.emit()


func request_bed_sleep(actor: HumanoidCharacter, bed) -> Dictionary:
	if actor == null or bed == null:
		return {"allowed": false, "message": "Cannot sleep here"}
	var faction_name := actor.faction_name
	if _is_bed_rented_to_faction(bed, faction_name):
		return {"allowed": true, "message": ""}
	if currency_item == null or bed_rent_price <= 0:
		_record_bed_rental(bed, faction_name)
		return {"allowed": true, "message": "Bed rented"}
	if actor.inventory == null or actor.inventory.count_item(currency_item) < bed_rent_price:
		return {"allowed": false, "message": "Need %d silver to rent bed" % bed_rent_price}
	if not actor.inventory.remove_item_count(currency_item, bed_rent_price):
		return {"allowed": false, "message": "Need %d silver to rent bed" % bed_rent_price}
	_record_bed_rental(bed, faction_name)
	return {"allowed": true, "message": "Bed rented for %d silver" % bed_rent_price}


func get_available_guard_post(worker: HumanoidCharacter):
	for post in _collect_nodes(guard_posts_root_path):
		if post != null and post.has_method("is_available_for") and post.is_available_for(worker):
			return post
	return null


func get_service_point():
	var points := _collect_nodes(service_points_root_path)
	return points[0] if not points.is_empty() else null


func get_guard_posts() -> Array:
	return _collect_nodes(guard_posts_root_path)


func get_service_points() -> Array:
	return _collect_nodes(service_points_root_path)


func get_waiter_character() -> HumanoidCharacter:
	return get_node_or_null(waiter_character_path) as HumanoidCharacter


func _is_bed_rented_to_faction(bed, faction_name: String) -> bool:
	if bed == null or faction_name.is_empty():
		return false
	var bed_key := _node_key(bed)
	var rentals: Dictionary = _bed_rentals.get(bed_key, {})
	var expires_at := float(rentals.get(faction_name, 0.0))
	return expires_at > _now_seconds()


func _record_bed_rental(bed, faction_name: String) -> void:
	if bed == null or faction_name.is_empty():
		return
	var bed_key := _node_key(bed)
	var rentals: Dictionary = _bed_rentals.get(bed_key, {})
	rentals[faction_name] = _now_seconds() + bed_rent_duration_seconds
	_bed_rentals[bed_key] = rentals


func _register_scoped_children() -> void:
	for bed in _collect_nodes(beds_root_path):
		if bed.has_method("set_bar_venue"):
			bed.set_bar_venue(self)
	for seat in _collect_nodes(seats_root_path):
		if seat.has_method("set_bar_venue"):
			seat.set_bar_venue(self)


func _process_waiter_service() -> void:
	var waiter: HumanoidCharacter = get_waiter_character()
	if waiter == null or waiter.life_state != NpcRules.LifeState.ALIVE:
		return
	if _active_service_seat != null:
		_continue_waiter_service(waiter)
		return
	var seat = _find_waiting_player_seat()
	if seat == null:
		return
	var customer: HumanoidCharacter = seat.get_sitter()
	if customer == null:
		return
	_mark_table_service_requested(seat)
	_active_service_seat = seat
	_active_service_customer = customer
	_service_conversation_started = false


func _continue_waiter_service(waiter: HumanoidCharacter) -> void:
	if _active_service_seat == null or not is_instance_valid(_active_service_seat):
		_return_waiter_to_service_point(waiter)
		_clear_waiter_service()
		return
	if _active_service_customer == null or not is_instance_valid(_active_service_customer):
		_return_waiter_to_service_point(waiter)
		_clear_waiter_service()
		return
	if not _active_service_customer.is_sitting():
		_return_waiter_to_service_point(waiter)
		_clear_waiter_service()
		return
	var target_position: Vector3 = _active_service_seat.get_interaction_position(waiter)
	if waiter.global_position.distance_to(target_position) > waiter_service_distance:
		waiter.set_move_target(target_position, false)
		return
	if _service_conversation_started:
		return
	_service_conversation_started = true
	_mark_table_service_completed(_active_service_seat)
	var conversation_controller = _get_conversation_controller()
	if conversation_controller != null:
		conversation_controller.begin_conversation(_active_service_customer, waiter)
	_return_waiter_to_service_point(waiter)
	_clear_waiter_service()


func _find_waiting_player_seat():
	for seat in _collect_nodes(seats_root_path):
		if seat != null and seat.has_method("is_waiting_for_service") and seat.is_waiting_for_service(waiter_service_delay_seconds):
			return seat
	return null


func _mark_table_service_requested(origin_seat) -> void:
	for seat in _collect_nodes(seats_root_path):
		if seat != null and seat.global_position.distance_to(origin_seat.global_position) <= table_service_radius and seat.has_method("mark_service_requested"):
			seat.mark_service_requested()


func _mark_table_service_completed(origin_seat) -> void:
	for seat in _collect_nodes(seats_root_path):
		if seat != null and seat.global_position.distance_to(origin_seat.global_position) <= table_service_radius and seat.has_method("mark_service_completed"):
			seat.mark_service_completed()


func _clear_waiter_service() -> void:
	_active_service_seat = null
	_active_service_customer = null
	_service_conversation_started = false


func _return_waiter_to_service_point(waiter: HumanoidCharacter) -> void:
	if waiter == null or waiter.life_state != NpcRules.LifeState.ALIVE:
		return
	var service_point = get_service_point()
	if service_point == null or not is_instance_valid(service_point):
		return
	if not service_point.has_method("get_work_position"):
		return
	var work_position: Vector3 = service_point.get_work_position()
	if waiter.global_position.distance_to(work_position) > waiter.interact_distance:
		waiter.set_move_target(work_position, false)


func _get_conversation_controller():
	var scene := get_tree().current_scene
	if scene == null:
		return null
	return scene.get_node_or_null("GameBootstrap/ConversationController")


func _collect_nodes(root_path: NodePath) -> Array:
	var nodes: Array = []
	var root := get_node_or_null(root_path)
	if root == null:
		return nodes
	for child in root.get_children():
		nodes.append(child)
	return nodes


func _node_key(node) -> String:
	if node == null:
		return ""
	return str(node.get_path())


func _now_seconds() -> float:
	return Time.get_ticks_msec() / 1000.0
