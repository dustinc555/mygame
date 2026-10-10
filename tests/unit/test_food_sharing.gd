extends GutTest

const BAG = preload("res://features/inventory/resources/items/medium_leather_bag.tres")
const FOOD = preload("res://features/inventory/resources/items/food.tres")
const STORAGE = preload("res://features/inventory/bridge/item_storage_view.gd")
const ACTIONS = preload("res://features/inventory/bridge/inventory_item_actions.gd")
const SHARING = preload("res://features/inventory/bridge/food_sharing_controller.gd")
var context: BootstrapContext
var bridge: GecsWorldController
var population: PopulationController
var party: PartyManager
var clock: WorldTimeController
var sharing
var donor: HumanoidCharacter
var recipient: HumanoidCharacter
var view

func before_each() -> void:
	var root := Node3D.new()
	add_child_autofree(root)
	context = BootstrapContext.new(root)
	bridge = GecsWorldController.new()
	root.add_child(bridge)
	context.register(GecsWorldController.SERVICE_ID, bridge)
	bridge.initialize(context)
	party = PartyManager.new()
	party.name = "PartyManager"
	root.add_child(party)
	population = PopulationController.new()
	root.add_child(population)
	context.register(PopulationController.SERVICE_ID, population)
	population.initialize(context)
	clock = WorldTimeController.new()
	root.add_child(clock)
	context.register(WorldTimeController.SERVICE_ID, clock)
	clock.set_process(false)
	donor = _actor("donor")
	recipient = _actor("recipient")
	recipient.position = Vector3(4, 0, 0)
	party.set_party_members([donor, recipient])
	assert_true(donor.inventory.add_entry_with_contents(BAG, 1, {}, {}, "shared.bag"))
	assert_true(donor.inventory.add_item(FOOD))
	var bag_entry = donor.inventory.entries[0]
	var inventory_controller := PartyInventoryController.new()
	root.add_child(inventory_controller)
	inventory_controller.set_process(false)
	inventory_controller._context = context
	inventory_controller.root_scene = root
	inventory_controller._on_inventory_equip_requested(donor, bag_entry, donor, "backpack")
	assert_eq(donor.get_equipped_item("backpack"), BAG)
	view = STORAGE.new()
	assert_true(view.bind(donor, "shared.bag", bridge))
	root.add_child(view)
	assert_true(view.inventory.add_entry_with_contents(FOOD, 1, {}, {"origin": "bag"}, "meal.one"))
	assert_true(view.inventory.add_entry_with_contents(FOOD, 1, {}, {"origin": "bag"}, "meal.two"))
	sharing = SHARING.new()
	root.add_child(sharing)
	sharing.initialize(context)

func _actor(id: String, enter_tree := true) -> HumanoidCharacter:
	var actor := HumanoidCharacter.new()
	actor.appearance_data = CharacterAppearanceData.new()
	actor.appearance_data.character_race = load("res://features/actors/resources/character_races/human.tres")
	actor.appearance_data.body_archetype = load("res://features/actors/resources/character_body_archetypes/human_male.tres")
	actor.stable_id = id
	actor.hunger_enabled = true
	actor.process_mode = Node.PROCESS_MODE_DISABLED
	if enter_tree:
		context.root_scene.add_child(actor)
		population.register_actor(actor)
		bridge.register_actor(actor)
	return actor

func after_each() -> void:
	sharing.free()
	bridge.unregister_actor(donor)
	bridge.unregister_actor(recipient)

func _hungry() -> void:
	recipient.get_needs().hunger_stage = NpcRules.HungerStage.HUNGRY

func test_pre_tree_membership_waits_for_restored_needs_and_feeds_once() -> void:
	var pending := _actor("pending", false)
	var record := bridge.get_population_record(recipient.stable_id).duplicate(true)
	record["actor_id"] = pending.stable_id
	record["needs_state"]["hunger_stage"] = NpcRules.HungerStage.HUNGRY
	population.apply_record_to_actor(pending, record)
	assert_null(pending.get_needs(), "Record hydration publishes membership before capabilities exist")
	sharing._track(pending)
	await get_tree().process_frame
	var id := pending.get_instance_id()
	assert_false(sharing._members.has(id))
	assert_false(sharing._dirty_suppliers.has(id))
	assert_false(sharing._hungry.has(id))
	donor.set_share_food_enabled(true)
	pending.position = Vector3(4, 0, 0)
	context.root_scene.add_child(pending)
	population.register_actor(pending)
	bridge.register_actor(pending)
	await get_tree().process_frame
	assert_true(pending.is_food_effect_active(), "Hydrated hunger must wake sharing without another hunger change")
	assert_eq(view.inventory.count_item(FOOD), 1, "Duplicate membership notifications cannot consume twice")
	assert_false(pending.ready.is_connected(sharing._track.bind(pending)))
	bridge.unregister_actor(pending)

func test_leaving_party_before_ready_cancels_pending_subscription() -> void:
	var pending := _actor("pending", false)
	party.register_party_member(pending)
	assert_true(pending.ready.is_connected(sharing._track.bind(pending)))
	party.unregister_party_member(pending)
	assert_false(pending.ready.is_connected(sharing._track.bind(pending)))
	context.root_scene.add_child(pending)
	population.register_actor(pending)
	bridge.register_actor(pending)
	pending.get_needs().hunger_stage = NpcRules.HungerStage.HUNGRY
	donor.set_share_food_enabled(true)
	await get_tree().process_frame
	assert_false(sharing._members.has(pending.get_instance_id()))
	assert_false(pending.is_food_effect_active())
	assert_eq(view.inventory.count_item(FOOD), 2)
	party.register_party_member(pending)
	await get_tree().process_frame
	assert_true(pending.is_food_effect_active(), "A later genuine rejoin must still acquire a needs subscription")
	assert_eq(view.inventory.count_item(FOOD), 1)
	bridge.unregister_actor(pending)

func test_replacing_controller_cancels_pending_ready_callback() -> void:
	var pending := _actor("pending", false)
	party.register_party_member(pending)
	var old_callback: Callable = sharing._track.bind(pending)
	context.root_scene.remove_child(sharing)
	assert_false(pending.ready.is_connected(old_callback), "Exiting controllers must release not-yet-ready members")
	sharing.free()
	sharing = SHARING.new()
	context.root_scene.add_child(sharing)
	sharing.initialize(context)
	context.root_scene.add_child(pending)
	population.register_actor(pending)
	bridge.register_actor(pending)
	pending.get_needs().hunger_stage = NpcRules.HungerStage.HUNGRY
	donor.set_share_food_enabled(true)
	await get_tree().process_frame
	assert_true(pending.is_food_effect_active())
	assert_eq(view.inventory.count_item(FOOD), 1)
	bridge.unregister_actor(pending)

func test_share_setting_is_immediately_durable_and_old_saves_default_off() -> void:
	donor.set_share_food_enabled(true)
	assert_eq(bridge.get_population_record(donor.stable_id).get("share_food_enabled"), true)
	var saved := bridge.get_population_record(donor.stable_id)
	donor.set_share_food_enabled(false)
	population.apply_record_to_actor(donor, saved)
	assert_true(donor.is_share_food_enabled())
	var record := CGamePopulationRecord.new()
	record.apply_record({"actor_id": "legacy", "auto_burn_rustdead_enabled": true})
	assert_eq(record.to_record().get("share_food_enabled"), false)
	assert_false(record.to_record().has("auto_burn_rustdead_enabled"))

func test_food_waits_for_hunger_then_wakes_on_need_signal() -> void:
	donor.set_share_food_enabled(true)
	sharing.check_pending_meals()
	assert_eq(view.inventory.count_item(FOOD), 2)
	_hungry()
	await get_tree().process_frame
	assert_true(recipient.is_food_effect_active())
	assert_eq(view.inventory.count_item(FOOD), 1)
	assert_eq(donor.inventory.count_item(FOOD), 1)
	for i in 20:
		clock.minute_changed.emit(i, 0, 0, i)
	assert_eq(view.inventory.count_item(FOOD), 1, "Do not eat again while digesting")


func test_instant_hunger_action_wakes_normal_backpack_sharing() -> void:
	var controller := WorldInteractionController.new()
	context.root_scene.add_child(controller)
	controller.set_process(false)
	controller.population_controller = population
	donor.set_share_food_enabled(true)
	sharing.check_pending_meals()
	assert_false(recipient.is_food_effect_active())
	assert_true(controller._execute_npc_instant_action(WorldInteractionController.NPC_ACTION_DEGRADE_HUNGER, recipient).success)
	await get_tree().process_frame
	assert_true(recipient.is_food_effect_active())
	assert_eq(view.inventory.count_item(FOOD), 1)
	assert_eq(donor.inventory.count_item(FOOD), 1)


func test_range_retries_on_world_minutes_and_settings_control_reach() -> void:
	_hungry()
	donor.set_share_food_enabled(true)
	sharing.settings = sharing.settings.duplicate()
	sharing.settings.distance = 3.0
	sharing.check_pending_meals()
	assert_false(recipient.is_food_effect_active())
	sharing.settings.distance = 5.0
	clock.minute_changed.emit(1, 0, 0, 1)
	assert_true(recipient.is_food_effect_active())

func test_non_party_and_unconscious_recipients_cannot_take_food() -> void:
	_hungry()
	donor.set_share_food_enabled(true)
	party.unregister_party_member(recipient)
	sharing.check_pending_meals()
	assert_false(recipient.is_food_effect_active())
	party.register_party_member(recipient)
	recipient.force_unconscious()
	sharing.check_pending_meals()
	assert_false(recipient.is_food_effect_active())
	assert_eq(view.inventory.count_item(FOOD), 2)

func test_personal_food_and_unequipped_bags_are_never_shared() -> void:
	_hungry()
	donor.set_share_food_enabled(true)
	view.inventory.entries.clear()
	view.inventory.changed.emit()
	sharing.check_pending_meals()
	assert_false(recipient.is_food_effect_active())
	assert_eq(donor.inventory.count_item(FOOD), 1)
	assert_true(view.inventory.add_item(FOOD))
	donor.get_equipment().unequip_item_from_slot("backpack")
	sharing.check_pending_meals()
	assert_false(recipient.is_food_effect_active())

func test_exact_personal_stack_and_stale_bag_actions_use_same_rules() -> void:
	assert_true(donor.inventory.add_entry_with_contents(FOOD, 1, {}, {"distinct": true}, "clicked"))
	var clicked = donor.inventory.entries.back()
	assert_true(ACTIONS.eat(donor, clicked))
	assert_false(donor.inventory.entries.has(clicked))
	assert_eq(donor.inventory.count_item(FOOD), 1)
	assert_eq(view.inventory.count_item(FOOD), 2)
	donor.get_needs().food_effect_remaining_seconds = 0
	var entry = view.inventory.entries[0]
	view._invalidate()
	assert_false(ACTIONS.eat(view, entry))
	assert_eq(view.inventory.count_item(FOOD), 2)

func test_share_food_replaces_burn_button_and_work_is_label_only() -> void:
	var hud = preload("res://features/ui/projection/game_hud.tscn").instantiate()
	add_child_autofree(hud)
	var row = hud.get_node("HudLayout/BottomHud/RightHud/BottomInfoRow/CommandDock/Margin/CommandColumn/BehaviorRows/AssistRow")
	var share = row.get_node_or_null("ShareFoodButton")
	assert_not_null(share)
	if share != null:
		assert_eq(share.text, "Share Food")
		assert_true(share.toggle_mode)
	assert_null(row.get_node_or_null("BurnRustdeadButton"))
	assert_eq(row.get_node("JobsButton").text, "Work")
	assert_false(donor.get_interaction().has_method("try_assign_auto_burn_action"))

func test_meal_observers_see_exact_stack_already_debited() -> void:
	_hungry()
	donor.set_share_food_enabled(true)
	var observed_counts: Array[int] = []
	recipient.get_needs().food_need_changed.connect(func():
		if recipient.is_food_effect_active():
			observed_counts.append(view.inventory.count_item(FOOD)))
	sharing.check_pending_meals()
	assert_eq(observed_counts, [1], "Digestion cannot be published before the exact food debit")

func test_save_load_restores_policy_and_needs_before_queued_meals() -> void:
	var simulation := WorldSimulationController.new()
	context.root_scene.add_child(simulation)
	simulation.initialize(context)
	donor.set_share_food_enabled(true)
	assert_true(simulation.save_world_to_file("user://food-sharing.tres"))
	donor.set_share_food_enabled(false)
	_hungry()
	var stale: InventoryData = view.inventory
	assert_true(stale.add_item(FOOD))
	assert_true(simulation.load_world_from_file("user://food-sharing.tres"))
	assert_false(stale.add_item(FOOD), "Old projections cannot overwrite loaded food")
	await get_tree().process_frame
	assert_true(donor.is_share_food_enabled())
	assert_false(recipient.get_needs().wants_food(), "Queued work must see loaded needs, not unsaved hunger")
	assert_false(recipient.is_food_effect_active())
	view.free()
	view = STORAGE.new()
	assert_true(view.bind(donor, "shared.bag", bridge))
	context.root_scene.add_child(view)
	assert_eq(view.inventory.count_item(FOOD), 2)
	donor.set_share_food_enabled(false)
	assert_eq(bridge.get_population_record(donor.stable_id).get("share_food_enabled"), false)
	_hungry()
	sharing.check_pending_meals()
	assert_eq(view.inventory.count_item(FOOD), 2)
	donor.set_share_food_enabled(true)
	sharing.check_pending_meals()
	assert_true(recipient.is_food_effect_active())
	assert_eq(view.inventory.count_item(FOOD), 1)
	assert_eq(donor.inventory.count_item(FOOD), 1)

func test_empty_supplier_wakes_on_restock_and_digestion_expiry() -> void:
	view.inventory.entries.clear()
	view.inventory.changed.emit()
	donor.set_share_food_enabled(true)
	_hungry()
	sharing.check_pending_meals()
	assert_false(recipient.is_food_effect_active())
	assert_true(view.inventory.add_item_count(FOOD, 2))
	await get_tree().process_frame
	assert_true(recipient.is_food_effect_active())
	assert_eq(view.inventory.count_item(FOOD), 1)
	recipient.get_needs().food_effect_remaining_seconds = 0
	await get_tree().process_frame
	assert_true(recipient.is_food_effect_active())
	assert_eq(view.inventory.count_item(FOOD), 0)

func test_one_meal_cannot_feed_two_hungry_members() -> void:
	var third := _actor("third")
	third.position = Vector3(3, 0, 0)
	party.register_party_member(third)
	assert_true(view.inventory.remove_entry(view.inventory.entries.back()))
	_hungry()
	third.get_needs().hunger_stage = NpcRules.HungerStage.HUNGRY
	donor.set_share_food_enabled(true)
	sharing.check_pending_meals()
	assert_ne(recipient.is_food_effect_active(), third.is_food_effect_active(), "Exactly one meal and one recipient")
	assert_eq(view.inventory.count_item(FOOD), 0)
	assert_eq(donor.inventory.count_item(FOOD), 1)
	bridge.unregister_actor(third)

func test_recipient_projection_loss_and_replacement_reacquires_food() -> void:
	_hungry()
	donor.set_share_food_enabled(true)
	population.unregister_actor(recipient)
	bridge.unregister_actor(recipient)
	recipient.free()
	sharing.check_pending_meals()
	assert_eq(view.inventory.count_item(FOOD), 2, "A disappeared recipient cannot consume queued food")
	recipient = _actor("recipient")
	recipient.position = Vector3(4, 0, 0)
	party.register_party_member(recipient)
	_hungry()
	await get_tree().process_frame
	assert_true(recipient.is_food_effect_active(), "Fresh realization wakes sharing without a timer or toggle")
	assert_eq(view.inventory.count_item(FOOD), 1)

func test_hud_toggle_changes_only_selected_characters_and_roundtrips_selection() -> void:
	var hud = preload("res://features/ui/projection/game_hud.tscn").instantiate()
	add_child_autofree(hud)
	var controller := WorldInteractionController.new()
	context.root_scene.add_child(controller)
	controller.set_process(false)
	controller.party_manager = party
	var rows = hud.get_node("HudLayout/BottomHud/RightHud/BottomInfoRow/CommandDock/Margin/CommandColumn/BehaviorRows")
	var buttons := {
		"walk_button": "MoveRow/MovementSegment/WalkButton",
		"running_button": "MoveRow/MovementSegment/RunningButton",
		"sneaking_button": "MoveRow/MovementSegment/SneakingButton",
		"aggressive_button": "FightRow/CombatSegment/AggressiveButton",
		"defensive_button": "FightRow/CombatSegment/DefensiveButton",
		"passive_button": "FightRow/CombatSegment/PassiveButton",
		"auto_heal_button": "AssistRow/AutoHealButton",
		"share_food_button": "AssistRow/ShareFoodButton",
		"jobs_button": "AssistRow/JobsButton",
	}
	for property in buttons:
		controller.set(property, rows.get_node(buttons[property]))
	controller._setup_command_bar()
	party.selection_changed.connect(controller._update_command_bar)
	party.select_only(donor)
	controller.share_food_button.button_pressed = true
	assert_true(donor.is_share_food_enabled())
	assert_false(recipient.is_share_food_enabled())
	assert_eq(bridge.get_population_record(donor.stable_id).get("share_food_enabled"), true)
	party.select_only(recipient)
	assert_false(controller.share_food_button.button_pressed)
	party.set_selection([donor, recipient])
	assert_true(controller.share_food_button.button_pressed, "Mixed selection displays enabled")
	controller.share_food_button.button_pressed = false
	assert_false(donor.is_share_food_enabled())
	assert_false(recipient.is_share_food_enabled())
	controller.share_food_button.button_pressed = true
	assert_true(donor.is_share_food_enabled())
	assert_true(recipient.is_share_food_enabled())
	party.clear_selection()
	assert_true(controller.share_food_button.disabled)
