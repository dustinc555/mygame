extends GutTest

const DEGRADE := &"degrade_hunger_level"

# Control only the pick result; exercise the production click dispatcher and action.
class TargetedInteraction extends WorldInteractionController:
	var picked: WorldActor
	func _pick_inspectable_target(_position: Vector2) -> Object:
		return picked

var root: Node3D
var context: BootstrapContext
var previous_context: BootstrapContext
var bridge: GecsWorldController
var population: PopulationController
var party: PartyManager
var interaction: TargetedInteraction
var actor: HumanoidCharacter
var debug: DebugMenu

func before_each() -> void:
	root = Node3D.new()
	add_child_autofree(root)
	context = BootstrapContext.new(root)
	previous_context = BootstrapContext.active
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
	actor = HumanoidCharacter.new()
	actor.appearance_data = CharacterAppearanceData.new()
	actor.appearance_data.character_race = load("res://features/actors/resources/character_races/human.tres")
	actor.appearance_data.body_archetype = load("res://features/actors/resources/character_body_archetypes/human_male.tres")
	actor.stable_id = "hunger.debug.actor"
	actor.member_name = "Hunger Target"
	actor.hunger_enabled = true
	actor.process_mode = Node.PROCESS_MODE_DISABLED
	root.add_child(actor)
	population.register_actor(actor)
	bridge.register_actor(actor)
	party.register_party_member(actor)
	interaction = TargetedInteraction.new()
	root.add_child(interaction)
	interaction.set_process(false)
	interaction.population_controller = population
	interaction.picked = actor
	context.register(WorldInteractionController.SERVICE_ID, interaction)
	BootstrapContext.active = context
	debug = DebugMenu.new()
	root.add_child(debug)
	debug.set_process(false)

func after_each() -> void:
	BootstrapContext.active = previous_context
	bridge.unregister_actor(actor)

func _click(button := MOUSE_BUTTON_LEFT) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.pressed = true
	return event

func test_share_food_has_no_hover_hint() -> void:
	var hud = preload("res://features/ui/projection/game_hud.tscn").instantiate()
	add_child_autofree(hud)
	var share := hud.find_child("ShareFoodButton", true, false) as Button
	assert_not_null(share)
	assert_eq(share.tooltip_text, "")

func test_button_then_party_target_degrades_one_stage_and_persists() -> void:
	debug.toggle_window("NPC Instant Actions")
	var button := debug.find_child("DegradeHungerLevelButton", true, false) as Button
	assert_not_null(button)
	if button == null:
		return
	assert_eq(button.text, "Degrade Hunger Level")
	var needed: Array[bool] = []
	actor.get_needs().food_need_changed.connect(func(): needed.append(actor.get_needs().wants_food()))
	button.pressed.emit()
	assert_eq(interaction._pending_npc_instant_action, DEGRADE)
	assert_true(interaction._handle_npc_instant_action_input(_click()))
	assert_eq(actor.get_hunger_stage(), NpcRules.HungerStage.HUNGRY)
	assert_eq(actor.hunger, 100.0)
	assert_eq(needed, [true], "Normal food-sharing eligibility must wake")
	assert_eq(interaction._pending_npc_instant_action, &"")
	assert_false(debug._npc_action_status.text.contains("Corpse"))
	assert_true(debug._npc_action_status.text.contains("Hungry"))
	assert_eq(population.get_actor_record(actor.stable_id).needs_state.hunger_stage, NpcRules.HungerStage.HUNGRY)

func test_each_use_is_one_stage_even_at_empty_meter_and_does_not_clear_digestion() -> void:
	var needs := actor.get_needs()
	for meter in [0.0, 35.0, 100.0]:
		needs.hunger_stage = NpcRules.HungerStage.WELL_NOURISHED
		needs.hunger = meter
		needs.food_effect_rate = 0.25
		needs.food_effect_remaining_seconds = 12.0
		var result := interaction._execute_npc_instant_action(DEGRADE, actor)
		assert_true(result.success)
		assert_eq(needs.hunger_stage, NpcRules.HungerStage.HUNGRY)
		assert_eq(needs.hunger, 100.0)
		assert_eq(needs.food_effect_rate, 0.25)
		assert_eq(needs.food_effect_remaining_seconds, 12.0)
		assert_true(interaction._execute_npc_instant_action(DEGRADE, actor).success)
		assert_eq(needs.hunger_stage, NpcRules.HungerStage.STARVING)
		var unchanged := needs.durable_state()
		assert_false(interaction._execute_npc_instant_action(DEGRADE, actor).success)
		assert_eq(needs.durable_state(), unchanged, "Already Starving must not drain further")

func test_disabled_hunger_dead_or_unregistered_targets_are_unchanged() -> void:
	actor.hunger_enabled = false
	var original := actor.get_needs().durable_state()
	assert_false(interaction._execute_npc_instant_action(DEGRADE, actor).success)
	assert_eq(actor.get_needs().durable_state(), original)
	actor.hunger_enabled = true
	population.mark_record_dead(actor.stable_id, actor)
	original = actor.get_needs().durable_state()
	assert_false(interaction._execute_npc_instant_action(DEGRADE, actor).success)
	assert_eq(actor.get_needs().durable_state(), original)
	var unregistered := WorldActor.new()
	unregistered.hunger_enabled = true
	root.add_child(unregistered)
	assert_false(interaction._execute_npc_instant_action(DEGRADE, unregistered).success)
	assert_eq(unregistered.get_hunger_stage(), NpcRules.HungerStage.WELL_NOURISHED)
	assert_false(interaction._execute_npc_instant_action(DEGRADE, null).success)

func test_invalid_pick_can_retry_and_cancel_or_close_prevents_later_mutation() -> void:
	assert_true(interaction.arm_crop_debug_action(WorldInteractionController.CROP_ACTION_ADVANCE))
	assert_true(interaction.arm_npc_instant_action(DEGRADE))
	assert_eq(interaction._pending_crop_debug_action, &"", "Only one debug picking mode can own the click")
	interaction.picked = null
	assert_true(interaction._handle_npc_instant_action_input(_click()))
	assert_eq(interaction._pending_npc_instant_action, DEGRADE)
	assert_true(interaction._handle_npc_instant_action_input(_click(MOUSE_BUTTON_RIGHT)))
	interaction.picked = actor
	assert_false(interaction._handle_npc_instant_action_input(_click()))
	assert_eq(actor.get_hunger_stage(), NpcRules.HungerStage.WELL_NOURISHED)
	assert_true(interaction.arm_npc_instant_action(DEGRADE))
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	assert_true(interaction._handle_npc_instant_action_input(escape))
	assert_eq(interaction._pending_npc_instant_action, &"")
	debug.toggle_window("NPC Instant Actions")
	assert_true(interaction.arm_npc_instant_action(DEGRADE))
	debug.toggle_window("NPC Instant Actions")
	assert_eq(interaction._pending_npc_instant_action, &"")
	assert_false(interaction._handle_npc_instant_action_input(_click()))

func test_kill_still_refuses_party_and_still_persists_non_party_corpses() -> void:
	assert_false(interaction._execute_npc_instant_action(WorldInteractionController.NPC_ACTION_KILL, actor).success)
	assert_true(interaction.arm_npc_instant_action(WorldInteractionController.NPC_ACTION_KILL))
	interaction._handle_npc_instant_action_input(_click())
	assert_eq(actor.life_state, NpcRules.LifeState.ALIVE)
	party.unregister_party_member(actor)
	interaction._handle_npc_instant_action_input(_click())
	assert_eq(actor.life_state, NpcRules.LifeState.DEAD)
	assert_eq(population.get_actor_record(actor.stable_id).body_state, "corpse")
	assert_true(debug._npc_action_status.text.contains("Corpse persisted"))


func test_hunger_action_also_accepts_non_party_characters() -> void:
	party.unregister_party_member(actor)
	assert_true(interaction.arm_npc_instant_action(DEGRADE))
	assert_true(interaction._handle_npc_instant_action_input(_click()))
	assert_eq(actor.get_hunger_stage(), NpcRules.HungerStage.HUNGRY)
	assert_eq(actor.life_state, NpcRules.LifeState.ALIVE)


func test_degraded_hunger_roundtrips_full_session_save_load() -> void:
	var simulation := WorldSimulationController.new()
	root.add_child(simulation)
	simulation.initialize(context)
	assert_true(interaction._execute_npc_instant_action(DEGRADE, actor).success)
	assert_true(simulation.save_world_to_file("user://debug-hunger.tres"))
	assert_true(interaction._execute_npc_instant_action(DEGRADE, actor).success)
	assert_eq(actor.get_hunger_stage(), NpcRules.HungerStage.STARVING)
	assert_true(simulation.load_world_from_file("user://debug-hunger.tres"))
	await get_tree().process_frame
	assert_eq(actor.get_hunger_stage(), NpcRules.HungerStage.HUNGRY)
	assert_eq(actor.hunger, 100.0)
