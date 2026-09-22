@tool
extends SettlementFacilityInstance
class_name SettlementShop

const STOCK_POLICY = preload("res://features/settlements/resources/merchant_stock_policy.gd")
const STOCK = preload("res://features/inventory/resources/items/merchant_stock.gd")
const CONVERSATION = preload("res://features/conversation/resources/generic_shopkeeper.tres")
const SILVER = preload("res://features/inventory/resources/items/silver.tres")
@export var merchant_profile: MerchantProfile = preload("res://features/settlements/resources/merchants/general.tres")
@export var stock_overrides: Dictionary = {}
@export_range(0, 100000, 1) var starting_silver := 100
@export_range(4, 64, 1) var stock_columns := 20
@export_range(4, 64, 1) var stock_rows := 20
@export_range(1, 365, 1) var replenishment_days := 3
@export_range(0, 23, 1) var replenishment_hour := 8
var _merchant: HumanoidCharacter
var _counter: ShopCounter
var _counter_cached := false
var _duty_target := Vector3.INF
var _tick := 0.0


func _ready() -> void:
	super._ready()
	if Engine.is_editor_hint():
		set_process(false)
		return
	_home_resident_projection = HOME_RESIDENT_PROJECTION.new()
	_home_resident_projection.setup(self)
	get_tree().node_added.connect(_on_furniture_changed)
	get_tree().node_removed.connect(_on_furniture_changed)


func get_assignment_slot_specs() -> Array[Dictionary]:
	var specs := super.get_assignment_slot_specs()
	# Employment and residence bind the SAME persistent character. A room is
	# not another generated town NPC; moving away can change these relations.
	for spec in specs.duplicate():
		if str(spec.get("role_id", "")) != "merchant": continue
		var home: Dictionary = spec.duplicate(true)
		home["slot_id"] = str(spec.slot_id) + ".home"
		home["assignment_domain"] = "residence"
		home["assignment_exclusivity_group"] = "residence"
		home["role_id"] = "resident"
		home["population_cost"] = 0
		home["preferred_actor_id"] = ""
		home["preferred_character_path"] = ""
		home["resident_employment_slot_id"] = str(spec.slot_id)
		specs.append(home)
	return specs


func effective_stock() -> Dictionary:
	return STOCK_POLICY.resolve(merchant_profile.stock if merchant_profile != null else {}, stock_overrides)


func configure_settlement_assignment_actor(actor: Node, slot_id: String, record: Dictionary) -> void:
	super.configure_settlement_assignment_actor(actor, slot_id, record)
	if str(record.get("assignment_domain", "")) != "employment" or str(record.get("role_id", "")) != "merchant": return
	if is_instance_valid(_merchant) and _merchant != actor:
		release_settlement_assignment_duty(_merchant)
	_merchant = actor as HumanoidCharacter
	if _merchant == null: return
	_merchant.conversation_definition = CONVERSATION
	var role := actor.get_node_or_null("MerchantRole") as MerchantRole
	if role == null:
		role = MerchantRole.new()
		role.name = "MerchantRole"
		configure_new_merchant(role)
		actor.add_child(role)
	role.trade_availability = _is_available_for_trade
	sync_property_ownership.call_deferred()
	sync_door_policy.call_deferred()


func _is_available_for_trade() -> bool:
	if not is_instance_valid(_merchant) or not _merchant.is_on_counter_duty(): return false
	var jobs := BootstrapContext.service(&"job_system")
	return jobs != null and bool(jobs.call("can_execute_assignment_duty", _merchant))


func configure_new_merchant(role: MerchantRole) -> void:
	if merchant_profile == null: return
	role.shop_inventory_columns = stock_columns
	role.shop_inventory_rows = stock_rows
	var rules := effective_stock()
	role.trading_policy = {"stock": rules, "buys_any": merchant_profile.buys_any_sellable_item, "buy_price": merchant_profile.default_buy_price, "sell_price": merchant_profile.default_sell_price, "days": replenishment_days, "hour": replenishment_hour}
	for path in rules:
		var quantity := int(rules[path].get("quantity", 0))
		if quantity <= 0: continue
		var item := load(str(path)) as ItemDefinition
		if item == null or item.is_currency_item(): continue
		var stock := STOCK.new()
		stock.item_definition = item
		stock.quantity = quantity
		role.initial_stock.append(stock)
	var money := STOCK.new()
	money.item_definition = SILVER
	money.quantity = starting_silver
	role.initial_stock.append(money)


func stock_capacity_warning() -> String:
	var check := StockCapacityCheck.new(effective_stock(), stock_columns, stock_rows, starting_silver)
	while not check.done:
		check.step()
	return check.warning


## Same packing rules for synchronous validation and frame-budgeted editor
## feedback. One step inserts at most one stack; UI callers can yield safely.
class StockCapacityCheck extends RefCounted:
	var done := false
	var warning := ""
	var _inventory: InventoryData
	var _rules: Dictionary
	var _paths: Array
	var _index := 0
	var _remaining := 0
	var _item: ItemDefinition
	var _silver: int

	func _init(rules: Dictionary, columns: int, rows: int, silver: int) -> void:
		_inventory = InventoryData.new(columns, rows, 0.0, false)
		_rules = rules.duplicate(true)
		_paths = _rules.keys()
		_silver = silver

	func step() -> void:
		if done: return
		if _remaining <= 0:
			if _index >= _paths.size():
				if _silver > 0 and not _inventory.add_item_count(SILVER, _silver):
					warning = "Leave room for starting silver: reduce stock or increase stock rows/columns."
				done = true
				return
			var path: String = str(_paths[_index])
			_index += 1
			_remaining = int(_rules[path].get("quantity", 0))
			if _remaining <= 0: return
			_item = load(path) as ItemDefinition
			if _item == null or _item.is_currency_item():
				_remaining = 0
				return
		var amount := mini(_remaining, _inventory.get_stack_limit(_item))
		if not _inventory.add_item_count(_item, amount):
			warning = "Stock does not fit: %s. Reduce quantities or increase stock rows/columns." % _item.display_name
			done = true
		_remaining -= amount


## Buildings belong to characters; town jurisdiction is a separate relation.
## Future renewable tax/leases and ruler revocation must not transfer stock
## merely because employment, affiliation or the building owner changes.
func get_property_owner_character() -> HumanoidCharacter:
	return _merchant if is_instance_valid(_merchant) and _merchant.life_state != NpcRules.LifeState.DEAD else null


func get_property_owner_role_id() -> String:
	return "merchant"


func _on_furniture_changed(node: Node) -> void:
	if node == _counter or (node is ShopCounter and is_ancestor_of(node)):
		if is_instance_valid(_merchant): release_settlement_assignment_duty(_merchant)
		_counter_cached = false
	if is_ancestor_of(node) and (node.has_method("claim_sleeper") or node.has_method("claim_sitter")):
		_home_resident_projection = HOME_RESIDENT_PROJECTION.new()
		_home_resident_projection.setup(self)


func _exit_tree() -> void:
	if not Engine.is_editor_hint() and is_instance_valid(_merchant):
		release_settlement_assignment_duty(_merchant)


func _find_counter(node: Node) -> ShopCounter:
	if node == null: return null
	if node is ShopCounter and (node.facility_role_ids.is_empty() or node.supports_facility_role("merchant")): return node
	for child in node.get_children():
		var found := _find_counter(child)
		if found != null: return found
	return null


func _process(delta: float) -> void:
	_tick += delta
	if _tick < 0.25: return
	_tick = 0.0
	if not is_instance_valid(_merchant): return
	var jobs := BootstrapContext.service(&"job_system")
	if jobs == null or not bool(jobs.call("can_execute_assignment_duty", _merchant)):
		release_settlement_assignment_duty(_merchant)
		return
	if not _counter_cached:
		_counter = _find_counter(get_node_or_null("Furniture"))
		_counter_cached = true
	if not is_instance_valid(_counter):
		release_settlement_assignment_duty(_merchant)
		return
	if not _counter.claim_worker(_merchant): return
	var target := _counter.get_staff_stand_position()
	# Match navigation's horizontal arrival tolerance; the character origin
	# need not coincide with floor height. Retain a separate floor check.
	var offset := _merchant.global_position - target
	if Vector2(offset.x, offset.z).length() > _counter.staff_work_radius or absf(offset.y) > _merchant.move_target_vertical_tolerance:
		_merchant.end_counter_duty()
		if not _merchant.has_move_target() or not _merchant.get_move_target().is_equal_approx(target):
			_duty_target = target
			_merchant.set_move_target(target, false)
	elif not _merchant.is_on_counter_duty():
		_merchant.begin_counter_duty(_counter.get_customer_position())


func release_settlement_assignment_duty(actor: Node) -> void:
	if not is_instance_valid(actor) or actor != _merchant: return
	if is_instance_valid(_counter): _counter.release_worker(_merchant)
	_merchant.end_counter_duty()
	var interaction := _merchant.get_interaction()
	var interrupted := _merchant.has_active_player_order() or _merchant.is_in_combat() or (interaction != null and interaction.has_direct_law_move())
	if not interrupted and _duty_target != Vector3.INF and _merchant.has_move_target() and _merchant.get_move_target().is_equal_approx(_duty_target):
		_merchant._clear_actor_move_target()
	_duty_target = Vector3.INF
