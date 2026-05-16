@tool
extends Node3D

class_name BarServiceArea

const SILVER_ITEM = preload("res://resources/items/silver.tres")

@export var service_area_id := ""
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
@export var guards_root_path: NodePath = NodePath("Staff")
@export var waiters_root_path: NodePath = NodePath("Staff")
@export var waiter_character_path: NodePath = NodePath("Staff/Waiter")
@export var waiter_service_delay_seconds := 7.0
@export var waiter_service_distance := 2.4
@export var table_service_radius := 2.8
@export var guard_shuffle_min_seconds := 120.0
@export var guard_shuffle_max_seconds := 180.0

var _bed_rentals: Dictionary = {}
var _active_service_seat
var _active_service_customer: HumanoidCharacter
var _active_service_waiter: HumanoidCharacter
var _service_conversation_started := false
var inventory: InventoryData
var _trade_proxy_position := Vector3.ZERO
var _has_trade_proxy_position := false
var _proxied_owner: HumanoidCharacter
var _guard_post_by_actor_id: Dictionary = {}
var _guard_shuffle_remaining_by_actor_id: Dictionary = {}
var _rng := RandomNumberGenerator.new()

signal inventory_changed


func _ready() -> void:
	_rng.randomize()
	add_to_group("bar_service_area")
	if Engine.is_editor_hint():
		return
	_register_scoped_children()
	_sync_trade_inventory()


func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	_process_waiter_service()
	_process_guard_staff(delta)


func refresh_scope() -> void:
	if Engine.is_editor_hint():
		return
	_register_scoped_children()
	_sync_trade_inventory()


func get_owner_character() -> HumanoidCharacter:
	return get_node_or_null(owner_character_path) as HumanoidCharacter


func get_owner_faction_name() -> String:
	if not owner_faction_name.is_empty():
		return owner_faction_name
	var owner_character := get_owner_character()
	return owner_character.faction_name if owner_character != null else ""


func get_barkeeper_inventory():
	var owner_character := get_owner_character()
	var merchant_role := get_merchant_role()
	if merchant_role != null:
		return merchant_role.get_shop_inventory()
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
	if owner_character == null:
		return false
	var merchant_role := get_merchant_role()
	if merchant_role != null:
		inventory = merchant_role.get_shop_inventory()
	elif owner_character.inventory != null:
		inventory = owner_character.inventory
	else:
		return false
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


func get_available_guard_post(worker: HumanoidCharacter, excluded_post = null):
	var available_posts: Array = []
	for post in _collect_nodes(guard_posts_root_path):
		if post == null or post == excluded_post:
			continue
		if post.has_method("is_available_for") and post.is_available_for(worker):
			available_posts.append(post)
	if available_posts.is_empty():
		return null
	return available_posts[_rng.randi_range(0, available_posts.size() - 1)]


func get_service_point():
	return get_barkeeper_service_point()


func get_barkeeper_service_point():
	for point in _collect_nodes(service_points_root_path):
		if _is_service_point_role(point, "barkeeper"):
			return point
	var points := _collect_nodes(service_points_root_path)
	return points[0] if not points.is_empty() else null


func get_available_waiter_point(worker: HumanoidCharacter, excluded_point = null):
	var fallback = null
	for point in get_waiter_service_points():
		if point == excluded_point:
			continue
		if not point.has_method("is_available_for"):
			continue
		if not point.is_available_for(worker):
			continue
		if point.has_method("get_assigned_worker") and point.get_assigned_worker() == null:
			return point
		if fallback == null:
			fallback = point
	return fallback


func claim_waiter_point(worker: HumanoidCharacter, point) -> bool:
	if worker == null or point == null:
		return false
	for service_point in get_waiter_service_points():
		if service_point != point and service_point.has_method("release_worker"):
			service_point.release_worker(worker)
	if point.has_method("claim_worker"):
		return point.claim_worker(worker)
	return true


func release_waiter_point(worker: HumanoidCharacter, point = null) -> void:
	for service_point in get_waiter_service_points():
		if point != null and service_point != point:
			continue
		if service_point.has_method("release_worker"):
			service_point.release_worker(worker)


func get_guard_posts() -> Array:
	return _collect_nodes(guard_posts_root_path)


func get_guard_characters() -> Array[HumanoidCharacter]:
	var guards: Array[HumanoidCharacter] = []
	var root := get_node_or_null(guards_root_path)
	if root != null:
		for child in root.get_children():
			if child is HumanoidCharacter and str(child.name).begins_with("Guard"):
				guards.append(child as HumanoidCharacter)
	return guards


func get_service_points() -> Array:
	return _collect_nodes(service_points_root_path)


func get_waiter_service_points() -> Array:
	var points: Array = []
	for point in _collect_nodes(service_points_root_path):
		if _is_service_point_role(point, "waiter"):
			points.append(point)
	return points


func get_waiter_character() -> HumanoidCharacter:
	var explicit_waiter := get_node_or_null(waiter_character_path) as HumanoidCharacter
	if explicit_waiter != null:
		return explicit_waiter
	var waiters := get_waiter_characters()
	return waiters[0] if not waiters.is_empty() else null


func get_waiter_characters() -> Array[HumanoidCharacter]:
	var waiters: Array[HumanoidCharacter] = []
	var explicit_waiter := get_node_or_null(waiter_character_path) as HumanoidCharacter
	if explicit_waiter != null:
		waiters.append(explicit_waiter)
	var root := get_node_or_null(waiters_root_path)
	if root != null:
		for child in root.get_children():
			if child is HumanoidCharacter and str(child.name).begins_with("Waiter") and not waiters.has(child):
				waiters.append(child as HumanoidCharacter)
	return waiters


func serves_actor(actor: Node) -> bool:
	if actor == null:
		return false
	return actor == get_owner_character() or get_waiter_characters().has(actor)


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
		if bed.has_method("set_bar_service_area"):
			bed.set_bar_service_area(self)
	for seat in _collect_nodes(seats_root_path):
		if seat.has_method("set_bar_service_area"):
			seat.set_bar_service_area(self)


func _process_waiter_service() -> void:
	if _active_service_seat != null:
		_continue_waiter_service(_active_service_waiter)
		return
	var seat = _find_waiting_player_seat()
	if seat == null:
		return
	var customer: HumanoidCharacter = seat.get_sitter()
	if customer == null:
		return
	var waiter := _find_waiter_for_service(seat)
	if waiter == null:
		return
	_mark_table_service_requested(seat)
	_active_service_seat = seat
	_active_service_customer = customer
	_active_service_waiter = waiter
	_service_conversation_started = false


func _process_guard_staff(delta: float) -> void:
	for guard in get_guard_characters():
		if guard == null or guard.life_state != NpcRules.LifeState.ALIVE:
			_release_guard_post_for(guard)
			continue
		_process_guard_post_assignment(guard, delta)


func _process_guard_post_assignment(guard: HumanoidCharacter, delta: float) -> void:
	var actor_id := guard.get_instance_id()
	var post = _guard_post_by_actor_id.get(actor_id)
	if post == null or not is_instance_valid(post) or (post.has_method("is_available_for") and not post.is_available_for(guard)):
		post = _claim_guard_post_for(guard)
		if post == null:
			return
	var remaining := float(_guard_shuffle_remaining_by_actor_id.get(actor_id, _next_guard_shuffle_seconds())) - delta
	if remaining <= 0.0:
		post = _try_shuffle_guard_post(guard, post)
		remaining = _next_guard_shuffle_seconds()
	_guard_shuffle_remaining_by_actor_id[actor_id] = remaining
	if post == null or not post.has_method("get_work_position"):
		return
	var work_position: Vector3 = post.get_work_position()
	if guard.global_position.distance_to(work_position) > guard.interact_distance:
		guard.set_move_target(work_position, false)


func _claim_guard_post_for(guard: HumanoidCharacter):
	var post = get_available_guard_post(guard)
	if post == null:
		return null
	if post.has_method("claim_worker") and not post.claim_worker(guard):
		return null
	_guard_post_by_actor_id[guard.get_instance_id()] = post
	_guard_shuffle_remaining_by_actor_id[guard.get_instance_id()] = _next_guard_shuffle_seconds()
	return post


func _try_shuffle_guard_post(guard: HumanoidCharacter, current_post):
	if get_guard_posts().size() <= 1:
		return current_post
	var next_post = get_available_guard_post(guard, current_post)
	if next_post == null:
		return current_post
	if next_post.has_method("claim_worker") and not next_post.claim_worker(guard):
		return current_post
	if current_post != null and current_post.has_method("release_worker"):
		current_post.release_worker(guard)
	_guard_post_by_actor_id[guard.get_instance_id()] = next_post
	return next_post


func _release_guard_post_for(guard: HumanoidCharacter) -> void:
	if guard == null:
		return
	var actor_id := guard.get_instance_id()
	var post = _guard_post_by_actor_id.get(actor_id)
	if post != null and is_instance_valid(post) and post.has_method("release_worker"):
		post.release_worker(guard)
	_guard_post_by_actor_id.erase(actor_id)
	_guard_shuffle_remaining_by_actor_id.erase(actor_id)


func _continue_waiter_service(waiter: HumanoidCharacter) -> void:
	if waiter == null or not is_instance_valid(waiter) or waiter.life_state != NpcRules.LifeState.ALIVE:
		_clear_waiter_service()
		return
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
	var target_position: Vector3 = _get_waiter_service_position(waiter, _active_service_seat)
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


func _find_waiter_for_service(seat) -> HumanoidCharacter:
	var best_waiter: HumanoidCharacter
	var best_distance := INF
	var target_position := global_position
	if seat != null and seat.has_method("get_service_position"):
		target_position = seat.get_service_position(null)
	for waiter in get_waiter_characters():
		if waiter == null or waiter.life_state != NpcRules.LifeState.ALIVE:
			continue
		var distance := waiter.global_position.distance_squared_to(target_position)
		if distance < best_distance:
			best_distance = distance
			best_waiter = waiter
	return best_waiter


func _get_waiter_service_position(waiter: HumanoidCharacter, seat) -> Vector3:
	if seat != null and seat.has_method("get_service_position"):
		return seat.get_service_position(waiter)
	return seat.get_interaction_position(waiter)


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
	_active_service_waiter = null
	_service_conversation_started = false


func _return_waiter_to_service_point(waiter: HumanoidCharacter) -> void:
	if waiter == null or waiter.life_state != NpcRules.LifeState.ALIVE:
		return
	var service_point = get_available_waiter_point(waiter)
	if service_point == null or not is_instance_valid(service_point):
		return
	if not claim_waiter_point(waiter, service_point):
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


func _is_service_point_role(point, role: String) -> bool:
	if point == null:
		return false
	if point.has_method("is_point_role"):
		return point.is_point_role(role)
	var point_name := str(point.name).to_lower()
	if role == "barkeeper":
		return point_name.contains("barkeeper") or point_name.contains("counter")
	if role == "waiter":
		return point_name.contains("waiter")
	return false


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


func _next_guard_shuffle_seconds() -> float:
	var min_seconds := maxf(1.0, guard_shuffle_min_seconds)
	var max_seconds := maxf(min_seconds, guard_shuffle_max_seconds)
	return randf_range(min_seconds, max_seconds)


func _now_seconds() -> float:
	return Time.get_ticks_msec() / 1000.0
