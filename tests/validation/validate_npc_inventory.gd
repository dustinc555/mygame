extends "res://tests/validation/law_order_cases.gd"

## Real actors, navigation, inventory windows, perception, law and GECS records.
## The inherited fixture owns startup/cleanup; no alternative gameplay services.
const LOOT_SWORD = preload("res://features/inventory/resources/items/iron_sword.tres")
const LOOT_METADATA := {"origin": "body-loot-fixture", "quality": 0.73}

func _case_names() -> Array[String]:
	return ["_unseen_body_inventory", "_witnessed_faction_body_inventory", "_raider_body_inventory", "_living_pickpocket", "_npc_sentence_is_background"]

func _inventory_ui() -> PartyInventoryController:
	return BootstrapContext.service(PartyInventoryController.SERVICE_ID) as PartyInventoryController

func _target() -> HumanoidCharacter:
	return _scene.get_node("CustodyTown/Residents/Witness") as HumanoidCharacter

func _prepare_body(faction_id := FACTION_ID, position := Vector3(44, 0.1, 0)) -> String:
	var target := _target()
	FIXTURE.reset_order(target)
	target.faction_name = faction_id
	target.global_position = position
	_get_player().global_position = position + Vector3(0, 0, -8)
	if not target.inventory.add_entry_with_contents(LOOT_SWORD, 1, {}, LOOT_METADATA):
		_fail("Body fixture must seed an actual personal sword stack")
		return ""
	var entry = _find_inventory_entry(target.inventory, LOOT_SWORD)
	var stack_id := str(entry.stack_id)
	_inventory_ui()._on_inventory_equip_requested(target, entry, target, "weapon")
	if target.get_equipment().get_equipped_stack_id("weapon") != stack_id:
		_fail("Fixture must equip the exact personally carried sword")
		return ""
	target.get_vitals().set_blunt_damage(target.max_hp + 8.0)
	if not target.is_downed_state():
		_fail("Body fixture must be combat unconscious, not sleeping")
		return ""
	return stack_id

func _approach_inventory(target: HumanoidCharacter, action: String) -> bool:
	var world_input := BootstrapContext.service(WorldInteractionController.SERVICE_ID) as WorldInteractionController
	var party := _scene.get_node("PartyManager") as PartyManager
	party.select_only(_get_player())
	world_input.context_humanoid = target
	world_input._on_context_menu_id_pressed(world_input.ACTION_LOOT if action == "loot" else world_input.ACTION_PICKPOCKET)
	if not await _wait_until(func() -> bool: return _inventory_ui().secondary_inventory_window != null, 600):
		_fail("NPC inventory action must physically approach and open the production window")
		return false
	var view = _inventory_ui().secondary_inventory_window.inventory_owner
	if view.get_owner_character() != target or view.get_actor() != _get_player() or view.action != action:
		_fail("Inventory window must retain the exact acting character, target and intent")
		return false
	return true

func _unseen_body_inventory() -> void:
	var stack_id := _prepare_body()
	if stack_id.is_empty() or not await _approach_inventory(_target(), "loot"):
		return
	var ui := _inventory_ui()
	var view = ui.secondary_inventory_window.inventory_owner
	var player := _get_player()
	var cell := player.inventory.find_first_space(LOOT_SWORD)
	ui.secondary_inventory_window.unequip_requested.emit(view, "weapon", player, cell)
	var entry = _find_inventory_entry(player.inventory, LOOT_SWORD)
	if entry == null or str(entry.stack_id) != stack_id or entry.metadata != LOOT_METADATA:
		_fail("Unseen body loot must transfer the exact equipped sword and metadata")
	if _target().get_equipment().get_equipped_item("weapon") != null:
		_fail("Looted sword cannot remain duplicated on its body")
	var gecs := BootstrapContext.service(GecsWorldController.SERVICE_ID) as GecsWorldController
	var durable := gecs.get_item_stack(stack_id)
	if str(durable.get("owner_actor_id", "")) != player.stable_id or durable.get("metadata", {}) != LOOT_METADATA:
		_fail("Body transfer must persist exact ownership and metadata in GECS")
	if _get_law_controller().actor_has_active_warrant(player, FACTION_ID):
		_fail("Unseen body loot cannot generate a town warrant")
	ui._close_all_inventory_windows()
	if not await _approach_inventory(_target(), "loot"):
		return
	if ui.secondary_inventory_window.inventory_owner.get_equipped_item("weapon") != null:
		_fail("Reopened body cannot recreate looted equipment")

func _witnessed_faction_body_inventory() -> void:
	var stack_id := _prepare_body()
	if stack_id.is_empty() or not await _approach_inventory(_target(), "loot"):
		return
	var player := _get_player()
	FIXTURE.reset_order(_city_guard)
	_city_guard.global_position = player.global_position + Vector3(0, 0, -2)
	_city_guard.look_at(player.global_position, Vector3.UP)
	var perception := BootstrapContext.service(PerceptionController.SERVICE_ID) as PerceptionController
	if not bool(perception.evaluate_observer(_city_guard, player).get("clearly_seen", false)):
		_fail("Witnessed theft fixture must have actual visual perception")
		return
	var ui := _inventory_ui()
	var view = ui.secondary_inventory_window.inventory_owner
	ui.secondary_inventory_window.unequip_requested.emit(view, "weapon", player, player.inventory.find_first_space(LOOT_SWORD))
	if _target().get_equipment().get_equipped_stack_id("weapon") != stack_id or not _get_law_controller().actor_has_active_warrant(player, FACTION_ID):
		_fail("A faction witness must stop taking its friend's sword and report this thief")
	if _get_law_controller().actor_has_active_warrant(_target(), FACTION_ID):
		_fail("The victim cannot inherit the player's theft warrant")

func _raider_body_inventory() -> void:
	# Inside town jurisdiction with an actual town witness, not an empty world.
	var stack_id := _prepare_body("raiders", Vector3(-10, 0.1, 0))
	if stack_id.is_empty() or not await _approach_inventory(_target(), "loot"):
		return
	var player := _get_player()
	FIXTURE.reset_order(_city_guard)
	_city_guard.global_position = player.global_position + Vector3(0, 0, -2)
	_city_guard.look_at(player.global_position, Vector3.UP)
	var perception := BootstrapContext.service(PerceptionController.SERVICE_ID) as PerceptionController
	if not bool(perception.evaluate_observer(_city_guard, player).get("clearly_seen", false)):
		_fail("Town witness must actually see the raider-body looter")
		return
	var ui := _inventory_ui()
	var view = ui.secondary_inventory_window.inventory_owner
	ui.secondary_inventory_window.unequip_requested.emit(view, "weapon", player, player.inventory.find_first_space(LOOT_SWORD))
	var entry = _find_inventory_entry(player.inventory, LOOT_SWORD)
	if entry == null or str(entry.stack_id) != stack_id or _get_law_controller().actor_has_active_warrant(player, FACTION_ID):
		_fail("Town witnesses must allow raider body loot without a town theft warrant")


func _living_pickpocket() -> void:
	var target := _target()
	var player := _get_player()
	FIXTURE.reset_order(target)
	target.global_position = Vector3(44, 0.1, 0)
	player.global_position = Vector3(44, 0.1, -6)
	# Target looks away. Contact still requires Sleight of Hand, not only LOS.
	target.rotation.y = PI
	player.sneaking = true
	player.set_skill_level(SkillRules.SUBTERFUGE_SLEIGHT_OF_HAND, 100)
	player.set_skill_level(SkillRules.ATTRIBUTE_DEXTERITY, 100)
	if not target.inventory.add_entry_with_contents(LEGAL_ITEM, 1, LEGAL_CONTENTS, LOOT_METADATA):
		_fail("Pickpocket fixture must seed a real carried item")
		return
	var entry = _find_inventory_entry(target.inventory, LEGAL_ITEM)
	var stack_id := str(entry.stack_id)
	if not await _approach_inventory(target, "pickpocket"):
		return
	var ownership := BootstrapContext.service(OwnershipController.SERVICE_ID) as OwnershipController
	ownership._rng.seed = 123
	var ui := _inventory_ui()
	ui.secondary_inventory_window.quick_transfer_requested.emit(ui.secondary_inventory_window.inventory_owner, entry)
	var taken = _find_inventory_entry(player.inventory, LEGAL_ITEM)
	if taken == null or str(taken.stack_id) != stack_id or taken.contained_item_counts != LEGAL_CONTENTS:
		_fail("Successful Sleight of Hand must move the original carried stack and contents")
	if not ownership.last_steal_roll_summary.begins_with("pickpocket: Sleight of Hand"):
		_fail("Living inventory take must execute the skill contest")

func _npc_sentence_is_background() -> void:
	var prisoner := _target()
	var law := _get_law_controller()
	if not await _carry_into_custody(prisoner):
		return
	await _wake_fixture_prisoner(prisoner)
	_advance_to_sentence_decision(law, prisoner)
	law._process_prisoners()
	var record: Dictionary = law.prisoner_records.get(prisoner.stable_id, {})
	if not bool(record.get("sentence_decision_given", false)) or int(record.get("release_at_minute", -1)) < 0:
		_fail("NPC custody must receive an autonomous sentence")
	var conversation := BootstrapContext.service(ConversationController.SERVICE_ID) as ConversationController
	if conversation._system_conversation_active or not _get_jail()._pending_sentence_announcements.is_empty():
		_fail("NPC-versus-NPC custody must never queue or open player dialogue")
	var release_at := int(record.get("release_at_minute", -1))
	_get_world_time_controller().advance_minutes(maxf(0.0, release_at + 1 - _get_world_time_controller().get_absolute_minute()))
	law._process_prisoners()
	if prisoner.is_law_prisoner() or prisoner.is_in_cell_custody() or law.prisoner_records.has(prisoner.stable_id):
		_fail("NPC sentence must expire and release without a conversation")
	if _get_player().is_law_prisoner() or law.actor_has_active_warrant(_get_player(), FACTION_ID) or conversation._system_conversation_active:
		_fail("Uninvolved player must remain outside the NPC law case")
