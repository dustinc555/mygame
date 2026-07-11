@tool
extends Node3D

class_name BarServiceArea

## Emitted when a waiter reaches a served customer and a table-service chat should
## start. The venue does not orchestrate conversations -- it announces the event and
## SettlementBar wires this to ConversationController.begin_conversation. Inverting
## this (instead of the bar reaching up into the conversation service) keeps the
## venue off the settlement dependency cycle.
signal service_conversation_requested(customer: HumanoidCharacter, waiter: HumanoidCharacter)

const SILVER_ITEM = preload("res://features/inventory/resources/items/silver.tres")
const COMBAT_INTERVENTION_STAFF_GROUP := "combat_intervention_staff"
const CUSTOMER_ORDER_LINES := [
	"Bread and something to drink.",
	"Whatever's cheap.",
	"A loaf for the road.",
	"Something warm, if you have it.",
	"Just food. I'm starving.",
	"Bread for the table.",
]
const CUSTOMER_THANKS_LINES := [
	"Thanks.",
	"About time.",
	"That'll do.",
	"Looks good.",
	"Appreciate it.",
]
const CUSTOMER_READY_LINES := [
	"Ready over here.",
	"Can you take my order?",
	"When you have a moment.",
	"Over here.",
	"(waves)",
]

@export var service_area_id := ""
@export var owner_character_path: NodePath
@export var owner_faction_name := ""
@export var currency_item: Resource = SILVER_ITEM
@export var bed_rent_price := 1
@export var bed_rent_duration_seconds := 3600.0
@export var beds_root_path: NodePath = NodePath("Furniture")
@export var seats_root_path: NodePath = NodePath("Furniture")
@export var tables_root_path: NodePath = NodePath("Furniture")
@export var guard_posts_root_path: NodePath = NodePath("GuardPosts")
@export var service_points_root_path: NodePath
@export var guards_root_path: NodePath = NodePath("Staff")
@export var waiters_root_path: NodePath = NodePath("Staff")
@export var waiter_character_path: NodePath = NodePath("Staff/Waiter")
@export var waiter_character_paths: Array[NodePath] = []
@export var guard_character_paths: Array[NodePath] = []
@export var waiter_service_delay_seconds := 7.0
@export var waiter_order_prompt_interval_seconds := 10.0
@export var waiter_order_prompt_jitter_seconds := 3.0
@export var waiter_customer_repeat_cooldown_seconds := 45.0
@export var waiter_order_claim_timeout_seconds := 30.0
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

# Counter duty bookkeeping (owner working the barkeeper point).
var _counter_duty_owner: HumanoidCharacter
var _counter_duty_merchant: MerchantRole
var _barkeeper_counter: Node3D
var _barkeeper_counter_lookup_complete := false
var _owner_conversation_gesture_played := false
var _conversation_controller: ConversationController
var _conversation_controller_lookup_pending := true
var _guard_post_by_actor_id: Dictionary = {}
var _guard_shuffle_remaining_by_actor_id: Dictionary = {}
var _next_waiter_order_prompt_seconds := 0.0
var _pending_waiter_order: Dictionary = {}
var _seat_order_cooldown_until: Dictionary = {}
var _waiter_order_sequence := 0
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
	_process_owner_counter_duty()


func refresh_scope() -> void:
	if Engine.is_editor_hint():
		return
	_barkeeper_counter = null
	_barkeeper_counter_lookup_complete = false
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
	if owner_character != null:
		return owner_character.get_node_or_null("MerchantRole") as MerchantRole
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


func has_waiter_service() -> bool:
	return _find_waiter_for_service(null) != null


func can_call_waiter_for_customer(customer: HumanoidCharacter) -> bool:
	if _active_service_seat != null:
		return false
	var seat = get_seat_for_customer(customer)
	if seat == null:
		return false
	return _find_waiter_for_service(seat) != null


func call_waiter_for_customer(customer: HumanoidCharacter) -> Dictionary:
	if customer == null or not is_instance_valid(customer) or customer.life_state != NpcRules.LifeState.ALIVE:
		return {"allowed": false, "message": "Cannot order right now"}
	if not customer.is_player_party_member():
		return {"allowed": false, "message": "Only party members can call a waiter"}
	if _active_service_seat != null:
		return {"allowed": false, "message": "Waiter is already on the way"}
	var seat = get_seat_for_customer(customer)
	if seat == null:
		return {"allowed": false, "message": "Sit at a bar table first"}
	var waiter := _find_waiter_for_service(seat)
	if waiter == null:
		return {"allowed": false, "message": "No waiter available"}
	_mark_table_service_requested(seat)
	_active_service_seat = seat
	_active_service_customer = customer
	_active_service_waiter = waiter
	_service_conversation_started = false
	return {"allowed": true, "message": ""}


func get_available_guard_post(worker: WorldActor, excluded_post = null):
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
	if _barkeeper_counter_lookup_complete:
		return _barkeeper_counter if _barkeeper_counter != null and is_instance_valid(_barkeeper_counter) else null
	_barkeeper_counter_lookup_complete = true
	_barkeeper_counter = _find_shop_counter(get_node_or_null(tables_root_path))
	return _barkeeper_counter


func get_barkeeper_order_position(_worker: HumanoidCharacter = null) -> Vector3:
	var point = get_barkeeper_service_point()
	if point != null and point.has_method("get_work_position"):
		return point.get_work_position()
	var owner_character := get_owner_character()
	if owner_character != null:
		return owner_character.global_position
	return global_position


func claim_waiting_customer_seat(worker: HumanoidCharacter):
	return _claim_waiting_customer_seat(worker, false)


func has_waiting_customer_for_service(worker: HumanoidCharacter, include_player_party := false, include_npcs := true) -> bool:
	return _find_waiting_customer_seat(worker, include_player_party, include_npcs, false) != null


func has_pending_waiter_order_for_worker(worker: HumanoidCharacter) -> bool:
	return not _get_or_create_waiter_order(worker, false).is_empty()


func get_pending_waiter_order_for_worker(worker: HumanoidCharacter) -> Dictionary:
	return _get_or_create_waiter_order(worker, false)


func claim_waiter_order(worker: HumanoidCharacter) -> Dictionary:
	return _get_or_create_waiter_order(worker, true)


func release_waiter_customer_service(seat) -> void:
	if _pending_order_matches_seat(seat):
		_pending_waiter_order["status"] = "pending"
		_pending_waiter_order["claimed_by"] = null
		_pending_waiter_order["claimed_at"] = 0.0
		return
	if seat != null and is_instance_valid(seat) and seat.has_method("clear_service_request"):
		seat.clear_service_request()


func complete_waiter_customer_service(seat) -> void:
	var completed := false
	if seat != null and is_instance_valid(seat) and seat.has_method("mark_service_completed"):
		seat.mark_service_completed()
		completed = true
	if completed:
		_record_waiter_order_completion(seat)
		schedule_next_waiter_order_prompt()


func schedule_next_waiter_order_prompt() -> void:
	var base_delay := maxf(waiter_order_prompt_interval_seconds, 0.0)
	var jitter := maxf(waiter_order_prompt_jitter_seconds, 0.0)
	if base_delay <= 0.0 and jitter <= 0.0:
		_next_waiter_order_prompt_seconds = 0.0
		return
	var delay := base_delay
	if jitter > 0.0:
		delay += _rng.randf_range(-jitter, jitter)
	_next_waiter_order_prompt_seconds = _now_seconds() + maxf(delay, 0.0)


func get_customer_for_seat(seat) -> HumanoidCharacter:
	if seat != null and is_instance_valid(seat) and seat.has_method("get_sitter"):
		return seat.get_sitter()
	return null


func get_seat_for_customer(customer: HumanoidCharacter):
	if customer == null or not is_instance_valid(customer) or not customer.has_method("is_sitting") or not customer.is_sitting():
		return null
	for seat in _collect_seat_nodes():
		if seat != null and seat.has_method("get_sitter") and seat.get_sitter() == customer:
			return seat
	return null


func get_waiter_customer_service_position(waiter: HumanoidCharacter, seat) -> Vector3:
	return _get_waiter_service_position(waiter, seat)


func generate_customer_order_text(_customer: HumanoidCharacter = null) -> String:
	return CUSTOMER_ORDER_LINES[_rng.randi_range(0, CUSTOMER_ORDER_LINES.size() - 1)]


func generate_customer_thanks_text(_customer: HumanoidCharacter = null) -> String:
	return CUSTOMER_THANKS_LINES[_rng.randi_range(0, CUSTOMER_THANKS_LINES.size() - 1)]


func generate_customer_ready_text(_customer: HumanoidCharacter = null) -> String:
	return CUSTOMER_READY_LINES[_rng.randi_range(0, CUSTOMER_READY_LINES.size() - 1)]


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
	for guard_path in guard_character_paths:
		var explicit_guard := get_node_or_null(guard_path) as HumanoidCharacter
		if explicit_guard != null and not guards.has(explicit_guard):
			guards.append(explicit_guard)
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
	for waiter_path in waiter_character_paths:
		explicit_waiter = get_node_or_null(waiter_path) as HumanoidCharacter
		if explicit_waiter != null and not waiters.has(explicit_waiter):
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


func _claim_waiting_customer_seat(worker: HumanoidCharacter, include_player_party: bool):
	return _find_waiting_customer_seat(worker, include_player_party, true, true)


func _get_or_create_waiter_order(worker: HumanoidCharacter, claim: bool) -> Dictionary:
	_prune_waiter_order_state()
	if not _pending_waiter_order.is_empty():
		if not _can_worker_use_pending_order(worker):
			return {}
		if claim:
			_claim_pending_waiter_order(worker)
		return _pending_waiter_order.duplicate(false)
	if (waiter_order_prompt_interval_seconds > 0.0 or waiter_order_prompt_jitter_seconds > 0.0) and _now_seconds() < _next_waiter_order_prompt_seconds:
		return {}
	var seat = _select_waiter_order_seat(worker, false, true)
	if seat == null:
		return {}
	var customer := get_customer_for_seat(seat)
	if customer == null:
		return {}
	_waiter_order_sequence += 1
	_pending_waiter_order = {
		"order_id": "%s.order.%d" % [service_area_id if not service_area_id.is_empty() else str(get_path()), _waiter_order_sequence],
		"seat": seat,
		"customer": customer,
		"order_text": generate_customer_order_text(customer),
		"status": "pending",
		"created_at": _now_seconds(),
		"claimed_by": null,
		"claimed_at": 0.0,
	}
	if seat.has_method("mark_service_requested"):
		seat.mark_service_requested()
	customer.show_world_speech(generate_customer_ready_text(customer), 1.8)
	if claim:
		_claim_pending_waiter_order(worker)
	return _pending_waiter_order.duplicate(false)


func _claim_pending_waiter_order(worker: HumanoidCharacter) -> void:
	if worker == null or _pending_waiter_order.is_empty():
		return
	_pending_waiter_order["status"] = "claimed"
	_pending_waiter_order["claimed_by"] = worker
	_pending_waiter_order["claimed_at"] = _now_seconds()


func _can_worker_use_pending_order(worker: HumanoidCharacter) -> bool:
	if worker == null or _pending_waiter_order.is_empty():
		return false
	var seat = _pending_waiter_order.get("seat")
	var customer: HumanoidCharacter = _pending_waiter_order.get("customer")
	if seat == null or not is_instance_valid(seat) or customer == null or not is_instance_valid(customer):
		_pending_waiter_order.clear()
		return false
	if customer == worker or customer.life_state != NpcRules.LifeState.ALIVE or not customer.has_method("is_sitting") or not customer.is_sitting():
		_pending_waiter_order.clear()
		return false
	var claimed_by: HumanoidCharacter = _pending_waiter_order.get("claimed_by")
	if claimed_by == null:
		return true
	if not is_instance_valid(claimed_by):
		_pending_waiter_order["claimed_by"] = null
		_pending_waiter_order["status"] = "pending"
		return true
	if claimed_by == worker:
		return true
	var claimed_at := float(_pending_waiter_order.get("claimed_at", 0.0))
	if waiter_order_claim_timeout_seconds > 0.0 and _now_seconds() - claimed_at >= waiter_order_claim_timeout_seconds:
		_pending_waiter_order["claimed_by"] = null
		_pending_waiter_order["status"] = "pending"
		_pending_waiter_order["claimed_at"] = 0.0
		return true
	return false


func _select_waiter_order_seat(worker: HumanoidCharacter, include_player_party: bool, include_npcs: bool):
	var seats: Array = []
	for seat in _collect_seat_nodes():
		if seat == null or not seat.has_method("is_waiting_customer_for_service"):
			continue
		if _is_seat_on_waiter_order_cooldown(seat):
			continue
		if not seat.is_waiting_customer_for_service(waiter_service_delay_seconds, include_player_party, include_npcs):
			continue
		var seated_customer := get_customer_for_seat(seat)
		if seated_customer == null or seated_customer == worker:
			continue
		seats.append(seat)
	if seats.is_empty():
		return null
	return seats[_rng.randi_range(0, seats.size() - 1)]


func _find_waiting_customer_seat(worker: HumanoidCharacter, include_player_party: bool, include_npcs: bool, mark_requested: bool):
	var now_seconds := _now_seconds()
	if (waiter_order_prompt_interval_seconds > 0.0 or waiter_order_prompt_jitter_seconds > 0.0) and now_seconds < _next_waiter_order_prompt_seconds:
		return null
	var best_seat
	var best_distance := INF
	for seat in _collect_seat_nodes():
		if seat == null or not seat.has_method("is_waiting_customer_for_service"):
			continue
		if _is_seat_on_waiter_order_cooldown(seat):
			continue
		if not seat.is_waiting_customer_for_service(waiter_service_delay_seconds, include_player_party, include_npcs):
			continue
		var seated_customer := get_customer_for_seat(seat)
		if seated_customer == null or seated_customer == worker:
			continue
		var target_position := _get_waiter_service_position(worker, seat)
		var distance := worker.global_position.distance_squared_to(target_position) if worker != null else 0.0
		if distance < best_distance:
			best_distance = distance
			best_seat = seat
	if mark_requested and best_seat != null and best_seat.has_method("mark_service_requested"):
		best_seat.mark_service_requested()
		var selected_customer := get_customer_for_seat(best_seat)
		if selected_customer != null:
			selected_customer.show_world_speech(generate_customer_ready_text(selected_customer), 1.8)
	return best_seat


func _record_waiter_order_completion(seat) -> void:
	if seat == null:
		return
	var key := _node_key(seat)
	if not key.is_empty():
		_seat_order_cooldown_until[key] = _now_seconds() + maxf(waiter_customer_repeat_cooldown_seconds, 0.0)
	if _pending_order_matches_seat(seat):
		_pending_waiter_order.clear()


func _pending_order_matches_seat(seat) -> bool:
	return seat != null and not _pending_waiter_order.is_empty() and _pending_waiter_order.get("seat") == seat


func _is_seat_on_waiter_order_cooldown(seat) -> bool:
	var key := _node_key(seat)
	if key.is_empty():
		return false
	var until := float(_seat_order_cooldown_until.get(key, 0.0))
	if until <= _now_seconds():
		_seat_order_cooldown_until.erase(key)
		return false
	return true


func _prune_waiter_order_state() -> void:
	if _pending_waiter_order.is_empty():
		return
	var seat = _pending_waiter_order.get("seat")
	var customer: HumanoidCharacter = _pending_waiter_order.get("customer")
	if seat == null or not is_instance_valid(seat) or customer == null or not is_instance_valid(customer):
		_pending_waiter_order.clear()
		return
	if customer.life_state != NpcRules.LifeState.ALIVE or not customer.has_method("is_sitting") or not customer.is_sitting():
		_pending_waiter_order.clear()
		return
	var claimed_by: HumanoidCharacter = _pending_waiter_order.get("claimed_by")
	if claimed_by != null and (not is_instance_valid(claimed_by) or (waiter_order_claim_timeout_seconds > 0.0 and _now_seconds() - float(_pending_waiter_order.get("claimed_at", 0.0)) >= waiter_order_claim_timeout_seconds)):
		_pending_waiter_order["claimed_by"] = null
		_pending_waiter_order["status"] = "pending"
		_pending_waiter_order["claimed_at"] = 0.0


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
	for bed in _collect_bed_nodes():
		if bed.has_method("set_bar_service_area"):
			bed.set_bar_service_area(self)
	for seat in _collect_seat_nodes():
		if seat.has_method("set_bar_service_area"):
			seat.set_bar_service_area(self)
	_register_combat_intervention_staff()


func _register_combat_intervention_staff() -> void:
	var staff: Array[HumanoidCharacter] = []
	var owner_character := get_owner_character()
	if owner_character != null:
		staff.append(owner_character)
	for guard in get_guard_characters():
		if guard != null and not staff.has(guard):
			staff.append(guard)
	for waiter in get_waiter_characters():
		if waiter != null and not staff.has(waiter):
			staff.append(waiter)
	for actor in staff:
		actor.add_to_group(COMBAT_INTERVENTION_STAFF_GROUP)


func _process_waiter_service() -> void:
	if _active_service_seat != null:
		_continue_waiter_service(_active_service_waiter)


func _process_guard_staff(delta: float) -> void:
	for guard in get_guard_characters():
		if guard == null or guard.life_state != NpcRules.LifeState.ALIVE:
			_release_guard_post_for(guard)
			continue
		if guard.is_in_combat():
			continue
		_process_guard_post_assignment(guard, delta)


func _process_guard_post_assignment(guard: WorldActor, delta: float) -> void:
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


func _claim_guard_post_for(guard: WorldActor):
	var post = get_available_guard_post(guard)
	if post == null:
		return null
	if post.has_method("claim_worker") and not post.claim_worker(guard):
		return null
	_guard_post_by_actor_id[guard.get_instance_id()] = post
	_guard_shuffle_remaining_by_actor_id[guard.get_instance_id()] = _next_guard_shuffle_seconds()
	return post


func _try_shuffle_guard_post(guard: WorldActor, current_post):
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


## The owner works their counter by default: walk to the barkeeper service
## point, hold the Counter idle there, gesture on conversation (Counter_Show)
## and on completed trades (Counter_Give).
func _process_owner_counter_duty() -> void:
	var owner_character := get_owner_character()
	if owner_character != _counter_duty_owner:
		_release_counter_duty()
		_counter_duty_owner = owner_character
	if owner_character == null or not is_instance_valid(owner_character):
		return
	_connect_owner_trade_gesture(owner_character)
	if owner_character.life_state != NpcRules.LifeState.ALIVE \
			or owner_character.is_in_combat() or owner_character.is_sitting():
		if owner_character.is_on_counter_duty():
			owner_character.end_counter_duty()
		return
	var point = get_barkeeper_service_point()
	if point == null or not point.has_method("get_work_position"):
		return
	if point.has_method("is_available_for") and not point.is_available_for(owner_character):
		return
	var work_position: Vector3 = point.get_work_position()
	# Tighter than the point's work_radius on purpose: the counter pose is
	# calibrated to an exact stand distance; stopping anywhere in a 1.1m ring
	# leaves the hands short of (or through) the counter top. 0.5 leaves room
	# for steering slack — nav arrival regularly settles ~0.35 from the mark.
	var work_radius := 0.5
	var flat_distance := Vector2(owner_character.global_position.x - work_position.x, owner_character.global_position.z - work_position.z).length()
	if flat_distance > work_radius:
		if owner_character.is_on_counter_duty():
			owner_character.end_counter_duty()
		owner_character.set_move_target(work_position, false)
		return
	if point.has_method("claim_worker") and not point.claim_worker(owner_character):
		return
	if not owner_character.is_on_counter_duty():
		owner_character.begin_counter_duty(_counter_duty_face_position(point))
	_update_owner_conversation_gesture(owner_character)


func _counter_duty_face_position(point: Node3D) -> Vector3:
	if point.has_method("get_customer_position"):
		return point.get_customer_position()
	# Non-counter custom work points face the nearest counter customer side.
	var best_position := point.global_position + point.global_basis.z
	var best_distance := 3.0
	if is_inside_tree():
		for counter in get_tree().get_nodes_in_group("shop_counter"):
			if not (counter is Node3D) or not counter.has_method("get_customer_position"):
				continue
			var distance: float = (counter as Node3D).global_position.distance_to(point.global_position)
			if distance < best_distance:
				best_distance = distance
				best_position = counter.get_customer_position()
	return best_position


func _find_shop_counter(root: Node) -> Node3D:
	if root == null:
		return null
	if root is Node3D and root.has_method("get_staff_stand_position") and root.has_method("get_customer_position"):
		return root as Node3D
	for child in root.get_children():
		var counter := _find_shop_counter(child)
		if counter != null:
			return counter
	return null


func _connect_owner_trade_gesture(owner_character: HumanoidCharacter) -> void:
	var merchant := owner_character.get_node_or_null("MerchantRole") as MerchantRole
	if merchant == _counter_duty_merchant:
		return
	if _counter_duty_merchant != null and is_instance_valid(_counter_duty_merchant) \
			and _counter_duty_merchant.shop_inventory_changed.is_connected(_on_owner_shop_inventory_changed):
		_counter_duty_merchant.shop_inventory_changed.disconnect(_on_owner_shop_inventory_changed)
	_counter_duty_merchant = merchant
	if merchant != null and not merchant.shop_inventory_changed.is_connected(_on_owner_shop_inventory_changed):
		merchant.shop_inventory_changed.connect(_on_owner_shop_inventory_changed)


func _on_owner_shop_inventory_changed() -> void:
	var owner_character := get_owner_character()
	if owner_character != null and owner_character.is_on_counter_duty():
		owner_character.play_counter_gesture(HumanoidBodyProjection.COUNTER_GIVE_ANIMATION_NAME)


func _update_owner_conversation_gesture(owner_character: HumanoidCharacter) -> void:
	if _conversation_controller_lookup_pending:
		_conversation_controller_lookup_pending = false
		_conversation_controller = BootstrapContext.service(ConversationController.SERVICE_ID) as ConversationController
	if _conversation_controller == null:
		return
	var talking: bool = _conversation_controller.active_target == owner_character
	if talking and not _owner_conversation_gesture_played:
		owner_character.play_counter_gesture(HumanoidBodyProjection.COUNTER_SHOW_ANIMATION_NAME)
	_owner_conversation_gesture_played = talking


func _release_counter_duty() -> void:
	if _barkeeper_counter != null and is_instance_valid(_barkeeper_counter) \
			and _counter_duty_owner != null and _barkeeper_counter.has_method("release_worker"):
		_barkeeper_counter.release_worker(_counter_duty_owner)
	if _counter_duty_owner != null and is_instance_valid(_counter_duty_owner) \
			and _counter_duty_owner.is_on_counter_duty():
		_counter_duty_owner.end_counter_duty()
	if _counter_duty_merchant != null and is_instance_valid(_counter_duty_merchant) \
			and _counter_duty_merchant.shop_inventory_changed.is_connected(_on_owner_shop_inventory_changed):
		_counter_duty_merchant.shop_inventory_changed.disconnect(_on_owner_shop_inventory_changed)
	_counter_duty_owner = null
	_counter_duty_merchant = null
	_owner_conversation_gesture_played = false


func _release_guard_post_for(guard: WorldActor) -> void:
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
	if waiter.is_in_combat():
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
	if _active_service_seat.has_method("get_sitter") and _active_service_seat.get_sitter() != _active_service_customer:
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
	service_conversation_requested.emit(_active_service_customer, waiter)
	_return_waiter_to_service_point(waiter)
	_clear_waiter_service()


func _find_waiter_for_service(seat) -> HumanoidCharacter:
	var best_waiter: HumanoidCharacter
	var best_distance := INF
	var target_position := global_position
	if seat != null and seat.has_method("get_service_position"):
		target_position = seat.get_service_position(null)
	for waiter in get_waiter_characters():
		if waiter == null or waiter.life_state != NpcRules.LifeState.ALIVE:
			continue
		if waiter.is_in_combat():
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
	for seat in _collect_seat_nodes():
		if seat != null and seat.global_position.distance_to(origin_seat.global_position) <= table_service_radius and seat.has_method("mark_service_requested"):
			seat.mark_service_requested()


func _mark_table_service_completed(origin_seat) -> void:
	for seat in _collect_seat_nodes():
		if seat != null and seat.global_position.distance_to(origin_seat.global_position) <= table_service_radius and seat.has_method("mark_service_completed"):
			seat.mark_service_completed()


func _clear_waiter_service() -> void:
	_active_service_seat = null
	_active_service_customer = null
	_active_service_waiter = null
	_service_conversation_started = false


func _return_waiter_to_service_point(waiter: HumanoidCharacter) -> void:
	if waiter == null or waiter.life_state != NpcRules.LifeState.ALIVE or waiter.is_in_combat():
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


func _collect_bed_nodes() -> Array:
	var nodes: Array = []
	_collect_matching_furniture_nodes(get_node_or_null(beds_root_path), nodes, "bed")
	return nodes


func _collect_seat_nodes() -> Array:
	var nodes: Array = []
	_collect_matching_furniture_nodes(get_node_or_null(seats_root_path), nodes, "seat")
	return nodes


func _collect_matching_furniture_nodes(root: Node, nodes: Array, furniture_kind: String) -> void:
	if root == null:
		return
	if _matches_furniture_kind(root, furniture_kind):
		nodes.append(root)
		return
	for child in root.get_children():
		_collect_matching_furniture_nodes(child, nodes, furniture_kind)


func _matches_furniture_kind(node: Node, furniture_kind: String) -> bool:
	if node == null:
		return false
	if furniture_kind == "bed":
		return node.has_method("request_sleep") and node.has_method("get_sleep_position")
	if furniture_kind == "seat":
		return node.has_method("claim_sitter") and node.has_method("get_seat_position")
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
