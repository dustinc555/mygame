extends GutTest

class Actor extends HumanoidCharacter:
	var levels := {}
	var xp := {}
	var attacks := 0
	var fighting := false
	var bag := InventoryData.new()
	var gear := EquipmentCapability.new()
	var carried := InventoryCapability.new()
	var interactions := InteractionCapability.new()
	func _ready() -> void:
		gear.setup(self)
		carried.setup(self)
		carried.inventory = bag
		interactions.setup(self)
		add_to_group("npc_character")
	func _process(_delta: float) -> void: pass
	func _physics_process(_delta: float) -> void: pass
	func get_inventory_for_display() -> InventoryData: return bag
	func get_equipment() -> EquipmentCapability: return gear
	func get_inventory() -> InventoryCapability: return carried
	func get_interaction() -> InteractionCapability: return interactions
	func is_in_combat() -> bool: return fighting
	func get_skill_level(id: String) -> int: return int(levels.get(id, 0))
	func add_skill_xp(id: String, amount: float, _reason := "") -> int:
		xp[id] = float(xp.get(id, 0.0)) + amount
		return 0
	func show_world_speech(_text: String, _duration: float = 2.0) -> void: pass
	func assign_attack_target(_target: Node, _player := true, _notify := true, _allies := true) -> bool:
		attacks += 1
		return true

class Perception extends Node:
	var seen := {}
	func evaluate_observer(observer: WorldActor, _subject: WorldActor) -> Dictionary:
		return {"clearly_seen": bool(seen.get(observer.stable_id, false))}

class Law extends Node:
	var reports: Array = []
	func report_theft_if_witnessed(actor: WorldActor, target, witnesses: Array = []) -> Dictionary:
		reports.append({"actor": actor, "target": target, "witnesses": witnesses})
		return {}

class LawBoundary extends LawOrderController:
	var recorded := {}
	func _ready() -> void: pass
	func _process(_delta: float) -> void: pass
	func _settlement_faction_id(_settlement: Node) -> String: return "town"
	func report_crime(actor: WorldActor, faction_id: String, _settlement_id: String, crime_type: String, _severity: int, witness: WorldActor = null, _target = null, _options: Dictionary = {}) -> Dictionary:
		recorded = {"actor": actor, "faction": faction_id, "type": crime_type, "witness": witness}
		return recorded

class Interaction extends WorldInteractionController:
	var clicked: Actor
	var shown: Array = []
	func _ready() -> void: pass
	func _process(_delta: float) -> void: pass
	func _raycast_target_from_screen(_point: Vector2) -> Dictionary:
		return {"collider": clicked, "position": clicked.global_position}
	func _show_context_menu_actions(_point: Vector2, actions: Array) -> void: shown = actions

var thief: Actor
var target: Actor
var guard: Actor
var ownership: OwnershipController
var perception: Perception
var law: Law
var menu: Interaction
var inventories: PartyInventoryController
const SWORD = preload("res://features/inventory/resources/items/iron_sword.tres")
const BREAD = preload("res://features/inventory/resources/items/bread.tres")

func before_each() -> void:
	thief = _actor("player", "player")
	thief.player_party_member = true
	target = _actor("victim", "town")
	guard = _actor("guard", "town")
	ownership = OwnershipController.new()
	add_child_autofree(ownership)
	perception = Perception.new()
	add_child_autofree(perception)
	law = Law.new()
	add_child_autofree(law)
	var context := BootstrapContext.new(self)
	context.register(&"perception", perception)
	context.register(&"law_order", law)
	context.register(&"ownership", ownership)
	ownership.initialize(context)
	menu = Interaction.new()
	add_child_autofree(menu)
	menu.party_manager = PartyManager.new()
	menu.add_child(menu.party_manager)
	menu.party_manager.selected_members = [thief]
	menu.clicked = target
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1280, 900)
	add_child_autofree(viewport)
	var layer := Control.new()
	viewport.add_child(layer)
	layer.size = Vector2(1280, 900)
	inventories = PartyInventoryController.new()
	add_child_autofree(inventories)
	inventories.set_process(false)
	inventories._context = context
	inventories.inventory_window_layer = layer
	inventories.party_manager = menu.party_manager
	menu.inventory_controller = inventories
	thief.npc_inventory_target_reached.connect(menu._on_npc_inventory_target_reached)

func _actor(id: String, faction: String) -> Actor:
	var actor := Actor.new()
	actor.stable_id = id
	actor.faction_name = faction
	add_child_autofree(actor)
	return actor

func labels() -> Array:
	menu._handle_right_click(Vector2.ZERO)
	return menu.shown.map(func(action): return action.label)

func test_sneaking_right_click_offers_pickpocket() -> void:
	thief.sneaking = true
	assert_has(labels(), "Pickpocket")
	thief.sneaking = false
	assert_does_not_have(labels(), "Pickpocket")

func test_combat_ko_offers_loot_but_sleep_does_not() -> void:
	target.life_state = NpcRules.LifeState.UNCONSCIOUS
	assert_has(labels(), "Loot")
	target.life_state = NpcRules.LifeState.ASLEEP
	assert_does_not_have(labels(), "Loot")
	target.life_state = NpcRules.LifeState.DEAD
	assert_has(labels(), "Loot")

func test_seen_guard_body_theft_reports_and_refuses_take() -> void:
	target.life_state = NpcRules.LifeState.UNCONSCIOUS
	perception.seen[guard.stable_id] = true
	assert_false(ownership.request_take_item(thief, target))
	assert_eq(law.reports.size(), 1)
	if not law.reports.is_empty():
		assert_eq(law.reports[0].actor, thief)
		assert_eq(law.reports[0].witnesses, [guard])

func test_unseen_body_loot_has_no_omniscient_nearby_witness() -> void:
	target.life_state = NpcRules.LifeState.UNCONSCIOUS
	assert_true(ownership.request_take_item(thief, target))
	assert_true(law.reports.is_empty())

func test_town_witness_does_not_protect_a_raider_body() -> void:
	target.life_state = NpcRules.LifeState.UNCONSCIOUS
	target.faction_name = "raiders"
	perception.seen[guard.stable_id] = true
	assert_true(ownership.request_take_item(thief, target))
	assert_true(law.reports.is_empty())

func test_pickpocket_uses_sleight_of_hand_against_the_victim() -> void:
	thief.sneaking = true
	var rng := RandomNumberGenerator.new()
	rng.seed = 123
	var draw := rng.randf()
	assert_gt(draw, 0.03)
	assert_lt(draw, 0.97)
	ownership._rng.seed = 123
	assert_false(ownership.request_take_item(thief, target), "Unskilled attempt must fail this controlled draw")
	assert_gt(float(thief.xp.get(SkillRules.SUBTERFUGE_SLEIGHT_OF_HAND, 0.0)), 0.0)
	law.reports.clear()
	thief.levels[SkillRules.SUBTERFUGE_SLEIGHT_OF_HAND] = 100
	thief.levels[SkillRules.ATTRIBUTE_DEXTERITY] = 100
	ownership._rng.seed = 123
	assert_true(ownership.request_take_item(thief, target), "Same draw with high skill succeeds")
	assert_true(law.reports.is_empty())

func open_body():
	target.life_state = NpcRules.LifeState.UNCONSCIOUS
	inventories.call("open_npc_inventory", thief, target, "loot")
	assert_not_null(inventories.secondary_inventory_window)
	return inventories.secondary_inventory_window.inventory_owner if inventories.secondary_inventory_window != null else null

func test_menu_dispatch_approach_and_arrival_open_personal_inventory() -> void:
	target.life_state = NpcRules.LifeState.UNCONSCIOUS
	target.global_position = Vector3(8, 0, 0)
	labels()
	menu._on_context_menu_id_pressed(menu.ACTION_LOOT)
	assert_eq(thief.interactions.current_trade_target, target)
	thief.interactions.process_trade_interaction()
	assert_null(inventories.secondary_inventory_window, "Do not open remotely")
	thief.global_position = target.global_position
	thief.interactions.process_trade_interaction()
	assert_not_null(inventories.secondary_inventory_window)
	if inventories.secondary_inventory_window != null:
		assert_same(inventories.secondary_inventory_window.inventory_owner.get_inventory_for_display(), target.inventory)
	assert_true(law.reports.is_empty(), "Opening is not stealing")

func test_window_quick_transfer_moves_exact_item_only_when_unseen() -> void:
	assert_true(target.bag.add_item(BREAD))
	var entry = target.bag.entries[0]
	entry.metadata = {"origin": "guard provisions"}
	var view = open_body()
	if view == null: return
	perception.seen[guard.stable_id] = true
	inventories.secondary_inventory_window.quick_transfer_requested.emit(view, entry)
	assert_has(target.bag.entries, entry)
	assert_eq(thief.bag.count_item(BREAD), 0)
	perception.seen.clear()
	law.reports.clear()
	inventories.secondary_inventory_window.quick_transfer_requested.emit(view, entry)
	assert_eq(target.bag.count_item(BREAD), 0)
	assert_eq(thief.bag.count_item(BREAD), 1)
	assert_eq(thief.bag.entries[0].stack_id, entry.stack_id)
	assert_eq(thief.bag.entries[0].metadata, {"origin": "guard provisions"})
	assert_true(law.reports.is_empty())

func test_equipped_sword_take_checks_witness_before_mutation() -> void:
	target.gear.equip_item_to_slot(SWORD, "weapon", "guard-sword")
	var view = open_body()
	if view == null: return
	perception.seen[guard.stable_id] = true
	inventories.secondary_inventory_window.unequip_requested.emit(view, "weapon", thief, Vector2i.ZERO)
	assert_same(target.gear.get_equipped_item("weapon"), SWORD)
	assert_eq(thief.bag.count_item(SWORD), 0)
	assert_eq(law.reports.size(), 1)
	perception.seen.clear()
	inventories.secondary_inventory_window.unequip_requested.emit(view, "weapon", thief, Vector2i.ZERO)
	assert_null(target.gear.get_equipped_item("weapon"))
	assert_eq(thief.bag.count_item(SWORD), 1)
	assert_eq(thief.bag.entries[0].stack_id, "guard-sword")

func test_direct_equipment_transfer_cannot_bypass_theft() -> void:
	target.gear.equip_item_to_slot(SWORD, "weapon", "guard-sword")
	var view = open_body()
	if view == null: return
	perception.seen[guard.stable_id] = true
	inventories.secondary_inventory_window.equipment_transfer_requested.emit(view, "weapon", thief, "weapon")
	assert_same(target.gear.get_equipped_item("weapon"), SWORD)
	assert_null(thief.gear.get_equipped_item("weapon"))
	assert_eq(law.reports.size(), 1)

func test_full_bag_never_rolls_or_reports_a_take_that_cannot_commit() -> void:
	assert_true(target.bag.add_item(BREAD))
	var view = open_body()
	if view == null: return
	thief.bag.columns = 0
	perception.seen[guard.stable_id] = true
	inventories._on_inventory_quick_transfer_requested(view, target.bag.entries[0])
	assert_eq(target.bag.count_item(BREAD), 1)
	assert_true(law.reports.is_empty())

func test_recovery_or_lod_invalidates_body_window_and_pending_drag() -> void:
	assert_true(target.bag.add_item(BREAD))
	var entry = target.bag.entries[0]
	var view = open_body()
	if view == null: return
	target.life_state = NpcRules.LifeState.ALIVE
	inventories._on_inventory_transfer_requested(view, thief, entry, Vector2i.ZERO)
	assert_has(target.bag.entries, entry)
	inventories._enforce_open_inventory_context()
	assert_null(inventories.secondary_inventory_window)
	view = open_body()
	if view == null: return
	target.queue_free()
	inventories._enforce_open_inventory_context()
	assert_null(inventories.secondary_inventory_window)

func test_body_crime_uses_owner_faction_not_local_jurisdiction() -> void:
	var boundary := LawBoundary.new()
	add_child_autofree(boundary)
	target.life_state = NpcRules.LifeState.UNCONSCIOUS
	target.faction_name = "raiders"
	assert_true(boundary.report_theft_if_witnessed(thief, target, [guard]).is_empty(), "Town cannot report a raider body's property")
	guard.faction_name = "raiders"
	var crime := boundary.report_theft_if_witnessed(thief, target, [guard])
	assert_eq(crime.get("faction"), "raiders")
	assert_eq(crime.get("actor"), thief)
	assert_eq(crime.get("type"), LawOrderController.CRIME_THEFT)

func test_pickpocket_bag_take_rolls_per_item_not_on_open() -> void:
	thief.sneaking = true
	assert_true(target.bag.add_item(BREAD))
	var entry = target.bag.entries[0]
	inventories.open_npc_inventory(thief, target, "pickpocket")
	assert_not_null(inventories.secondary_inventory_window)
	if inventories.secondary_inventory_window == null: return
	var view = inventories.secondary_inventory_window.inventory_owner
	assert_true(thief.xp.is_empty())
	ownership._rng.seed = 123
	inventories._on_inventory_quick_transfer_requested(view, entry)
	assert_has(target.bag.entries, entry)
	assert_eq(thief.bag.count_item(BREAD), 0)
	thief.levels[SkillRules.SUBTERFUGE_SLEIGHT_OF_HAND] = 100
	thief.levels[SkillRules.ATTRIBUTE_DEXTERITY] = 100
	ownership._rng.seed = 123
	inventories._on_inventory_quick_transfer_requested(view, entry)
	assert_eq(thief.bag.count_item(BREAD), 1)
	assert_eq(target.bag.count_item(BREAD), 0)

func test_bag_to_equipment_and_drop_shortcuts_check_theft() -> void:
	assert_true(target.bag.add_item(SWORD))
	var entry = target.bag.entries[0]
	target.gear.equip_item_to_slot(SWORD, "weapon", "equipped-sword")
	var view = open_body()
	if view == null: return
	perception.seen[guard.stable_id] = true
	inventories._on_inventory_equip_requested(view, entry, thief, "weapon")
	inventories._on_inventory_item_drop_requested(view, entry)
	inventories._on_inventory_equipment_drop_requested(view, "weapon")
	assert_has(target.bag.entries, entry)
	assert_eq(target.gear.get_equipped_stack_id("weapon"), "equipped-sword")
	assert_null(thief.gear.get_equipped_item("weapon"))
	assert_eq(law.reports.size(), 3)

func test_body_view_excludes_merchant_and_work_stock() -> void:
	var role := MerchantRole.new()
	role.name = "MerchantRole"
	target.add_child(role)
	assert_true(role.get_shop_inventory().add_item(BREAD))
	target.carried.work_inventory_override = role.get_shop_inventory()
	var view = open_body()
	if view == null: return
	assert_same(view.get_inventory_for_display(), target.bag)
	assert_eq(view.get_inventory_for_display().count_item(BREAD), 0)
	assert_null(inventories.trade_session)

func test_new_trade_order_clears_old_pickpocket_intent() -> void:
	thief.sneaking = true
	thief.interactions.assign_npc_inventory_target(target, "pickpocket")
	thief.interactions.assign_trade_target(guard)
	assert_eq(thief.interactions.current_npc_inventory_action, "")
	assert_eq(thief.interactions.current_trade_target, guard)

func test_loot_window_stays_open_during_the_battle() -> void:
	var view = open_body()
	if view == null: return
	thief.fighting = true
	inventories._enforce_open_inventory_context()
	assert_not_null(inventories.secondary_inventory_window)
	thief.global_position = Vector3(10, 0, 0)
	inventories._enforce_open_inventory_context()
	assert_null(inventories.secondary_inventory_window, "Battle access still enforces physical reach")
