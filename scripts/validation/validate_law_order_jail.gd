extends SceneTree

const JAIL_LAW_DEMO_SCENE := preload("res://scenes/test_levels/jail_law_demo.tscn")
const WORLD_ITEM_SCENE := preload("res://scenes/world/items/world_item.tscn")
const FACTION_HUMANOID_SCRIPT := preload("res://scripts/characters/faction_humanoid.gd")
const SETTLEMENT_TOWN_SCRIPT := preload("res://scripts/world_sim/settlement_town.gd")
const SETTLEMENT_DEFINITION_SCRIPT := preload("res://scripts/world_sim/settlement_definition.gd")
const FARMERS_FACTION := preload("res://resources/world_sim/factions/farmers.tres")
const BANDAGE := preload("res://resources/items/bandage.tres")
const EXPENSIVE_VASE := preload("res://resources/items/expensive_vase.tres")
const HATCHET := preload("res://resources/items/hatchet.tres")
const ROUND_SHIELD := preload("res://resources/items/round_shield.tres")

const DEMO_FACTION_ID := "Farmers"
const DEMO_SETTLEMENT_ID := "jail_demo_town"
const PLAYER_START_POSITION := Vector3(-10.0, 0.6, -7.0)
const THEFT_PICKUP_POSITION := Vector3(-7.0, 0.6, -4.8)

var _failures: Array[String] = []
var _scene: Node


func _initialize() -> void:
	root.size = Vector2i(1280, 720)
	call_deferred("_run")


func _run() -> void:
	_scene = JAIL_LAW_DEMO_SCENE.instantiate()
	root.add_child(_scene)
	await _wait_frames(180)
	await _validate_demo_authority_equipment()
	await _validate_player_assault_local_law_response()
	await _validate_expired_warrant_cleanup()
	await _validate_unwitnessed_stolen_metadata()
	await _validate_witnessed_theft_jail_release()
	_validate_stolen_metadata_expiry_and_transfer()
	_validate_same_settlement_stolen_sale_rules()
	await _validate_no_jail_ejection_fallback()
	if _failures.is_empty():
		print("LAW_ORDER_JAIL_OK")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	print("LAW_ORDER_JAIL_FAILED count=%d" % _failures.size())
	quit(1)


func _validate_demo_authority_equipment() -> void:
	var player := _get_player()
	var town := _scene.get_node_or_null("JailDemoTown") if _scene != null else null
	var jail := _get_jail()
	var city_guard := _scene.get_node_or_null("JailDemoTown/Guards/Guard") as HumanoidCharacter
	var jail_guard := _scene.get_node_or_null("JailDemoTown/Facilities/Jail/Staff/Guard") as HumanoidCharacter
	for guard in [city_guard, jail_guard]:
		if guard == null:
			_fail("Demo authority guard should exist for equipment validation")
			continue
		if guard.get_equipped_item(ItemDefinition.EQUIP_SLOT_WEAPON) != HATCHET:
			_fail("Authority guard should spawn with a hatchet")
		elif HATCHET.grip_profile == null or str(HATCHET.grip_profile.get("animation_stance_id")) != EquipmentGripProfile.GRIP_CLASS_ONE_HAND_MELEE:
			_fail("Hatchet should use the shared one-hand melee animation stance")
		if guard.get_equipped_item(ItemDefinition.EQUIP_SLOT_OFFHAND) != ROUND_SHIELD:
			_fail("Authority guard should spawn with a round shield")
		if guard.inventory == null or guard.inventory.count_item(BANDAGE) != 1:
			_fail("Authority guard should carry one bandage")
	_validate_guard_post_preserves_combat(town, city_guard, player, "Town")
	_validate_guard_post_preserves_combat(jail, jail_guard, player, "Jail")
	_validate_combat_order_priority(city_guard, player)
	await _validate_no_nav_long_range_combat_chase(city_guard, player)


func _validate_player_assault_local_law_response() -> void:
	var player := _get_player()
	var law := _get_law_controller()
	var town := _scene.get_node_or_null("JailDemoTown") if _scene != null else null
	var jail := _get_jail()
	var city_guard := _scene.get_node_or_null("JailDemoTown/Guards/Guard") as HumanoidCharacter
	var jail_guard := _scene.get_node_or_null("JailDemoTown/Facilities/Jail/Staff/Guard") as HumanoidCharacter
	var warden := jail.get_node_or_null("Staff/Warden") as HumanoidCharacter if jail != null else null
	if player == null or law == null or town == null or city_guard == null or jail_guard == null or warden == null:
		_fail("Player assault validation requires player, law controller, town, city guard, jail guard, and warden")
		return
	var saved_transforms := _save_actor_transforms([player, city_guard, jail_guard, warden])
	_reset_validation_combat_actors([player, city_guard, jail_guard, warden])
	law.call("_clear_warrant_for_actor", player, DEMO_FACTION_ID)
	player.global_position = Vector3(-6.1, 0.6, -2.0)
	city_guard.global_position = Vector3(-5.1, 0.6, -2.0)
	jail_guard.global_position = Vector3(-8.0, 0.6, -2.0)
	warden.global_position = Vector3(-7.0, 0.6, -4.0)
	player.assign_attack_target(city_guard, true, true, true)
	await _wait_frames(8)
	var record: Dictionary = law.call("get_warrant_record", player, DEMO_FACTION_ID)
	if record.is_empty() or not bool(law.call("actor_has_active_warrant", player, DEMO_FACTION_ID)):
		_fail("Player-issued Attack on a settlement guard should immediately create an assault warrant")
	elif not _record_has_crime(record, LawOrderController.CRIME_ASSAULT):
		_fail("Player-issued Attack warrant should include an assault crime")
	elif str(record.get("authority_alert_mode", "")) != "local":
		_fail("Player-issued Attack should use a local combat alarm, got '%s'" % str(record.get("authority_alert_mode", "")))
	elif not bool(record.get("public_known", false)):
		_fail("Nearby same-settlement witnesses should make the assault public")
	if not _is_law_responder_arresting_actor(city_guard, player):
		_fail("Attacked authority guard should answer the assault as a law arrest")
	if not _is_law_responder_arresting_actor(jail_guard, player):
		_fail("Nearby jail guard should answer the local assault alarm")
	if not _is_law_responder_arresting_actor(warden, player):
		_fail("Warden should answer detected local assault as a soldier")
	law.call("_clear_warrant_for_actor", player, DEMO_FACTION_ID)
	_reset_validation_combat_actors([player, city_guard, jail_guard, warden])
	_restore_actor_transforms(saved_transforms)
	await _validate_victim_only_assault_clears_on_death(player, law, town)


func _validate_victim_only_assault_clears_on_death(player: HumanoidCharacter, law: Node, town: Node) -> void:
	if player == null or law == null or town == null:
		_fail("Victim-only assault validation requires player, law controller, and town")
		return
	var saved_transforms := _save_actor_transforms([player])
	var victim := _make_validation_humanoid("IsolatedAssaultVictim", "npc.jail_demo_town.isolated_victim", Vector3(70.0, 0.6, 0.0))
	victim.set("faction_name", DEMO_FACTION_ID)
	town.add_child(victim)
	await _wait_frames(8)
	_reset_validation_combat_actors([player, victim])
	law.call("_clear_warrant_for_actor", player, DEMO_FACTION_ID)
	player.global_position = Vector3(69.2, 0.6, 0.0)
	player.assign_attack_target(victim, true, true, true)
	await _wait_frames(8)
	var record: Dictionary = law.call("get_warrant_record", player, DEMO_FACTION_ID)
	if record.is_empty() or not bool(law.call("actor_has_active_warrant", player, DEMO_FACTION_ID)):
		_fail("Victim-only player assault should create an active provisional warrant while the victim lives")
	elif bool(record.get("public_known", false)):
		_fail("Victim-only assault should not become public without a nearby civilian or guard witness")
	victim.set("_last_direct_attacker_id", player.get_instance_id())
	victim.force_kill(player)
	await _wait_frames(8)
	if bool(law.call("actor_has_active_warrant", player, DEMO_FACTION_ID)):
		_fail("Victim-only assault and murder should clear when the only witness dies")
	_reset_validation_combat_actors([player, victim])
	law.call("_clear_warrant_for_actor", player, DEMO_FACTION_ID)
	victim.queue_free()
	_restore_actor_transforms(saved_transforms)


func _validate_expired_warrant_cleanup() -> void:
	var player := _get_player()
	var law := _get_law_controller()
	var world_time := _get_world_time_controller()
	var city_guard := _scene.get_node_or_null("JailDemoTown/Guards/Guard") as HumanoidCharacter
	if player == null or law == null or world_time == null or city_guard == null:
		_fail("Expired warrant cleanup validation requires player, law controller, world time, and city guard")
		return
	var saved_transforms := _save_actor_transforms([player, city_guard])
	_reset_validation_combat_actors([player, city_guard])
	law.call("_clear_warrant_for_actor", player, DEMO_FACTION_ID)
	player.global_position = city_guard.global_position + Vector3(0.9, 0.0, 0.0)
	law.call("report_crime", player, DEMO_FACTION_ID, DEMO_SETTLEMENT_ID, LawOrderController.CRIME_THEFT, 1, city_guard, city_guard)
	await _wait_frames(12)
	if str(player.call("get_legal_status").status_label).is_empty() or not bool(law.call("actor_has_active_warrant", player, DEMO_FACTION_ID)):
		_fail("Witnessed theft should create visible law status before warrant expiry")
	world_time.call("advance_days", 2.0)
	await _wait_frames(8)
	if bool(law.call("actor_has_active_warrant", player, DEMO_FACTION_ID)):
		_fail("Expired warrant should clear the active warrant record")
	if not str(player.call("get_legal_status").status_label).is_empty() or not str(player.call("get_legal_status").warrant_summary).is_empty():
		_fail("Expired warrant should clear actor law status metadata")
	if _is_law_responder_arresting_actor(city_guard, player):
		_fail("Expired warrant should disengage active law responders")
	_reset_validation_combat_actors([player, city_guard])
	_restore_actor_transforms(saved_transforms)


func _validate_unwitnessed_stolen_metadata() -> void:
	var player := _get_player()
	var law := _get_law_controller()
	if player == null or law == null:
		_fail("Player and LawOrderController should exist for unwitnessed theft validation")
		return
	var hidden_item := WORLD_ITEM_SCENE.instantiate() as WorldItem
	hidden_item.name = "HiddenOwnedVase"
	hidden_item.item_definition = EXPENSIVE_VASE
	hidden_item.owner_faction_name = DEMO_FACTION_ID
	hidden_item.theft_value = 10
	hidden_item.theft_noise_radius = 0.0
	_scene.add_child(hidden_item)
	hidden_item.global_position = Vector3(44.0, 0.45, 0.0)
	player.global_position = Vector3(44.0, 0.6, -1.0)
	var picked_up := hidden_item.try_pickup(player)
	await _wait_frames(4)
	if not picked_up:
		_fail("Unwitnessed owned item pickup should succeed")
		return
	var entry: InventoryData.InventoryEntry = _find_inventory_entry(player.inventory, EXPENSIVE_VASE)
	if entry == null:
		_fail("Unwitnessed stolen item should enter player inventory")
		return
	if not player.inventory.is_entry_stolen(entry):
		_fail("Unwitnessed theft should still mark the item as stolen")
	if bool(law.call("actor_has_active_warrant", player, DEMO_FACTION_ID)):
		_fail("Unwitnessed theft should not create an active warrant")
	player.inventory.remove_entry(entry)
	player.global_position = PLAYER_START_POSITION


func _validate_witnessed_theft_jail_release() -> void:
	var player := _get_player()
	var law := _get_law_controller()
	var world_time := _get_world_time_controller()
	var jail := _get_jail()
	var city_guard := _scene.get_node_or_null("JailDemoTown/Guards/Guard") as HumanoidCharacter
	var warden := jail.get_node_or_null("Staff/Warden") as HumanoidCharacter if jail != null else null
	var vase := _scene.get_node_or_null("JailDemoTown/OwnedVase") as WorldItem
	if player == null or law == null or world_time == null or jail == null or city_guard == null or warden == null or vase == null:
		_fail("Jail demo scene should provide player, law controller, world time, jail, warden, city guard, and owned vase")
		return
	_validate_jail_cell_authoring(jail)
	if not player.inventory.add_item_count(BANDAGE, 1):
		_fail("Player inventory should accept a legal bandage before arrest")
		return
	player.global_position = THEFT_PICKUP_POSITION
	var picked_up := vase.try_pickup(player)
	await _wait_frames(8)
	if not picked_up:
		_fail("Witnessed owned vase pickup should succeed as theft")
		return
	var stolen_entry: InventoryData.InventoryEntry = _find_inventory_entry(player.inventory, EXPENSIVE_VASE)
	if stolen_entry == null or not player.inventory.is_entry_stolen(stolen_entry):
		_fail("Witnessed theft should place a stolen vase entry in inventory")
	if not bool(law.call("actor_has_active_warrant", player, DEMO_FACTION_ID)):
		_fail("Witnessed theft should create a faction warrant")
	if not city_guard.has_hostility_with(player):
		_fail("Witnessed theft should alert the city guard responder")
	if warden.has_hostility_with(city_guard) or warden.get_current_combat_target() == city_guard:
		_fail("Jail warden should not defend the thief by fighting the city guard")
	var live_combat_resolved := await _validate_live_law_combat(city_guard, player)
	if not live_combat_resolved:
		return
	if player.life_state == NpcRules.LifeState.DEAD:
		_fail("Authority arrest damage should not kill a wanted actor")
		return
	if not player.is_downed_state():
		_fail("Authority arrest damage should knock out a wanted actor")
		return
	if player.hp <= player.get_death_point(player.max_hp):
		_fail("Authority arrest damage should clamp HP above the death threshold")
	if player.blood < 80.0:
		_fail("Authority arrest damage should not cause severe blood loss")
	law.call("_process_warrants")
	await _wait_frames(2)
	if bool(player.call("is_law_prisoner")):
		_fail("Unconscious wanted actor should not teleport directly into jail")
	if player.inventory.count_item(BANDAGE) != 1 or player.inventory.count_item(EXPENSIVE_VASE) != 1:
		_fail("Jail intake should not confiscate inventory before cell placement")
	var carried := await _wait_until(func() -> bool: return _find_guard_carrying_actor(player) != null, 180)
	var custody_guard := _find_guard_carrying_actor(player)
	if not carried:
		_fail("Authority guard should carry the unconscious wanted actor before jail intake")
		return
	var carry_animation := _get_current_animation(player)
	if carry_animation != "LiftAir_Fall":
		_fail("Carried prisoner should hold the LiftAir_Fall carry pose, got '%s'" % carry_animation)
	if bool(player.call("is_law_prisoner")):
		_fail("Carried actor should not be finalized as a prisoner before cell placement")
	var jailed := await _wait_until(func() -> bool: return bool(player.call("is_law_prisoner")), 2400)
	if not jailed:
		_fail("Carried wanted actor should be placed in a jail cell and admitted guard_order=%s guard_carried=%s guard_has_move=%s guard_move=%s guard_pos=%s player_life=%s player_pos=%s player_carried=%s" % [str(custody_guard.get("_current_order_type") if custody_guard != null else -1), str(custody_guard.get_carried_character() if custody_guard != null else null), str(custody_guard.get("_has_move_target") if custody_guard != null else false), str(custody_guard.get("_move_target") if custody_guard != null else Vector3.ZERO), str(custody_guard.global_position if custody_guard != null else Vector3.ZERO), str(player.life_state), str(player.global_position), str(player.is_carried())])
		return
	await _validate_cell_lay_building_visibility(player, jail)
	if custody_guard != null and (warden.has_hostility_with(custody_guard) or warden.get_current_combat_target() == custody_guard):
		_fail("Jail warden should not become hostile to the arresting guard during custody")
	var cell := _find_cell_holding(jail, player)
	if cell == null:
		_fail("Jail admission should assign the prisoner to a cell")
	else:
		var prisoner_position: Vector3 = cell.call("get_prisoner_position", player)
		if player.global_position.distance_to(prisoner_position) > 0.35:
			_fail("Prisoner should be placed at the authored cell prisoner point")
		if prisoner_position.y > -0.2:
			_fail("Prisoner cell point should be lowered so the prisoner rests on the cage floor")
		var prisoner_rotation: Vector3 = cell.call("get_prisoner_rotation", player)
		if absf(angle_difference(player.global_rotation.y, prisoner_rotation.y)) > 0.1:
			_fail("Prisoner should face the authored cell prisoner direction")
	if player.is_carried() or _find_guard_carrying_actor(player) != null:
		_fail("Prisoner should no longer be carried after cell placement")
	if not bool(player.call("is_in_cell_custody")):
		_fail("Prisoner should enter locked cell custody after placement")
	if bool(player.call("is_ragdoll_active")):
		_fail("Prisoner should not keep ragdoll simulation active in the cell")
	var lay_frozen := await _wait_until(func() -> bool: return bool(player.get("_cell_custody_lay_pose_frozen")), 420)
	if not lay_frozen:
		_fail("Unconscious prisoner should freeze partway through IdleToLay in the cell anim=%s remaining=%.3f current=%s life=%s" % [str(player.get("_cell_custody_unconscious_pose_animation")), float(player.get("_cell_custody_lay_freeze_remaining")), _get_current_animation(player), str(player.life_state)])
	elif str(player.get("_cell_custody_unconscious_pose_animation")) != "IdleToLay":
		_fail("Unconscious prisoner cell pose should use IdleToLay")
	if custody_guard != null and custody_guard.has_hostility_with(player):
		_fail("Authority guard should disengage combat after custody placement")
	if not bool(player.call("is_law_prisoner")):
		_fail("Unconscious wanted actor should be admitted to jail")
	if player.inventory.count_item(BANDAGE) != 0 or player.inventory.count_item(EXPENSIVE_VASE) != 0:
		_fail("Jail intake should confiscate legal and stolen inventory")
	var locker = jail.call("get_prisoner_locker")
	var locker_inventory = locker.get("inventory") if locker != null else null
	if locker_inventory == null:
		_fail("Jail should have a prisoner locker inventory after intake")
	elif locker_inventory.count_item(BANDAGE) != 1 or locker_inventory.count_item(EXPENSIVE_VASE) != 1:
		_fail("Prisoner locker should hold confiscated legal and stolen items")
	player.set("_downed_recover_delay_remaining", 0.0)
	var woke := await _wait_until(func() -> bool: return player.life_state == NpcRules.LifeState.ALIVE, 1200)
	if not woke:
		_fail("Prisoner should wake in cell after recovery delay")
	elif str(player.get("_cell_custody_wake_animation")) != "LayToIdle" and _get_current_animation(player) != "LayToIdle":
		_fail("Conscious prisoner should play LayToIdle from the cell lay pose")
	await _wait_until(func() -> bool: return str(player.get("_cell_custody_wake_animation")).is_empty(), 240)
	if _get_current_animation(player) == "LayToIdle":
		_fail("Conscious prisoner should return to normal idle after LayToIdle finishes")
	# --- LOD round-trip: prisoner must return to the SAME cell when re-realized ---
	# Simulate the actor LOD-unloading and respawning outside the cell by dropping
	# cell custody and displacing it; the law reconcile should re-seat it.
	var pre_lod_cell := _find_cell_holding(jail, player)
	player.call("exit_cell_custody", player.global_position + Vector3(25.0, 0.0, 25.0), player.global_rotation)
	if bool(player.call("is_in_cell_custody")):
		_fail("LOD setup: prisoner should leave cell custody when their actor unloads")
	law.call("_process_prisoners")
	await _wait_frames(2)
	if not bool(player.call("is_in_cell_custody")):
		_fail("LOD round-trip: realized prisoner should be re-seated in cell custody")
	var post_lod_cell := _find_cell_holding(jail, player)
	if post_lod_cell == null or post_lod_cell != pre_lod_cell:
		_fail("LOD round-trip: realized prisoner should return to the same cell")
	var warden_ground_y := warden.global_position.y
	var warden_post := _get_warden_home_post(jail)
	if warden_post == null:
		_fail("Jail should have a warden post before sentence delivery")
		return
	var raised_post_position := warden_post.global_position
	raised_post_position.y = warden_ground_y + 1.25
	warden_post.global_position = raised_post_position
	_force_sentence_decision_ready(law, player)
	law.call("_process_prisoners")
	var sentence_delivered := await _wait_until(func() -> bool: return _sentence_notification_given(law, player), 1500)
	if not sentence_delivered:
		_fail("Warden should tell the prisoner their sentence before release")
		return
	_close_active_conversation()
	var warden_returned := await _wait_until(func() -> bool: return _is_warden_at_home_post(jail, warden), 900)
	if not warden_returned:
		var post := _get_warden_home_post(jail)
		_fail("Warden should return to the warden post after sentencing warden_pos=%s post_pos=%s law_returning=%s sentence_move=%s has_move=%s move_target=%s" % [str(warden.global_position), str(post.global_position if post != null else Vector3.ZERO), str(warden.call("is_law_custody_returning") if warden.has_method("is_law_custody_returning") else false), str(warden.call("is_law_sentence_moving") if warden.has_method("is_law_sentence_moving") else false), str(warden.get("_has_move_target")), str(warden.get("_move_target"))])
		return
	if absf(warden.global_position.y - warden_ground_y) > 0.08:
		_fail("Warden should not snap to the elevated warden-post marker height warden_y=%.3f expected_y=%.3f post_y=%.3f" % [warden.global_position.y, warden_ground_y, warden_post.global_position.y])
		return
	world_time.call("advance_hours", 11.0)
	law.call("_process_prisoners")
	await _wait_frames(8)
	if bool(player.call("is_law_prisoner")):
		_fail("Sentence expiry should release the prisoner")
	if player.inventory.count_item(BANDAGE) != 1:
		_fail("Legal confiscated item should be returned on release")
	if player.inventory.count_item(EXPENSIVE_VASE) != 0:
		_fail("Stolen goods should be forfeited on legal release")
	if bool(law.call("actor_has_active_warrant", player, DEMO_FACTION_ID)):
		_fail("Release after sentence should clear the active warrant")


func _validate_cell_lay_building_visibility(player: HumanoidCharacter, jail: Node) -> void:
	var building := jail.get_node_or_null("BuildingSlot/CurrentBuilding") if jail != null else null
	var visibility_controller := root.find_child("BuildingVisibilityController", true, false)
	var party_manager := _scene.get_node_or_null("PartyManager") as PartyManager if _scene != null else null
	if player == null or building == null or visibility_controller == null or party_manager == null:
		_fail("Cell lay visibility validation requires player, jail building, visibility controller, and party manager")
		return
	party_manager.select_only(player)
	await _wait_frames(4)
	if str(player.get("_cell_custody_unconscious_pose_animation")) != "IdleToLay" or bool(player.get("_cell_custody_lay_pose_frozen")):
		_fail("Cell lay visibility validation should run during the active IdleToLay custody animation")
	if not bool(building.call("is_actor_inside", player)):
		_fail("Jail building should consider focused prisoner inside during cell lay-down animation")
	if visibility_controller.call("get_active_building") != building:
		_fail("Focused prisoner should keep the jail building hidden during cell lay-down animation")


func _validate_live_law_combat(city_guard: HumanoidCharacter, player: HumanoidCharacter) -> bool:
	if city_guard == null or player == null:
		_fail("Live law combat validation requires guard and player")
		return false
	player.set("base_dodge_chance", 0.0)
	player.set("base_block_chance", 0.0)
	player.set_skill_level(SkillRules.ATTRIBUTE_DEXTERITY, 0)
	city_guard.set("base_attack_damage", 38.0)
	city_guard.set("attack_cooldown_seconds", 0.25)
	var guard_engaged := await _wait_until(func() -> bool: return city_guard.is_in_combat() and city_guard.get_current_combat_target() == player, 180)
	if not guard_engaged:
		_fail("Authority guard should keep a live law-arrest combat target after witnessed theft")
		return false
	var player_defending := await _wait_until(func() -> bool: return player.is_in_combat() and _is_law_responder_arresting_actor(player.get_current_combat_target(), player), 180)
	if not player_defending:
		_fail("Wanted player party member should self-defend when the guard engages player_order=%s player_ai=%s player_target=%s player_protected=%s player_stance=%s guard_ai=%s guard_target=%s player_hostile=%s guard_hostile=%s" % [str(player.get("_current_order_type")), str(player.call("_get_active_ai_job_type")), str(player.get_current_combat_target()), str(player.call("is_protected_from_combat")), str(player.get("combat_stance")), str(city_guard.call("_get_active_ai_job_type")), str(city_guard.get_current_combat_target()), str(player.has_hostility_with(city_guard)), str(city_guard.has_hostility_with(player))])
		return false
	var initial_distance := city_guard.global_position.distance_to(player.global_position)
	var closed_distance_condition := func() -> bool:
		var distance := city_guard.global_position.distance_to(player.global_position)
		return distance <= city_guard.get_attack_range() + 0.45 or distance < initial_distance - 0.35
	var closed_distance := await _wait_until(closed_distance_condition, 360)
	if not closed_distance:
		_fail("Authority guard should close distance during live law combat")
		return false
	var landed_hit := await _wait_until(func() -> bool: return player.get_total_wound_damage() > 0.0 or player.is_downed_state() or player.life_state == NpcRules.LifeState.DEAD, 900)
	if not landed_hit:
		_fail("Authority guard should land a real combat hit during law arrest")
		return false
	var subdued := await _wait_until(func() -> bool: return player.is_downed_state() or player.life_state == NpcRules.LifeState.DEAD, 1500)
	if not subdued:
		_fail("Authority guard should subdue the wanted player through live combat")
		return false
	return player.is_downed_state()


func _validate_stolen_metadata_expiry_and_transfer() -> void:
	var metadata: Dictionary = {
		InventoryData.META_STOLEN: true,
		InventoryData.META_STOLEN_FROM_FACTION_ID: DEMO_FACTION_ID,
		InventoryData.META_STOLEN_FROM_SETTLEMENT_ID: DEMO_SETTLEMENT_ID,
		InventoryData.META_STOLEN_BY_ACTOR_ID: "player.validation",
		InventoryData.META_STOLEN_AT_MINUTE: 0,
		InventoryData.META_STOLEN_EXPIRES_AT_MINUTE: 10 * 24 * 60,
	}
	var source := InventoryData.new(4, 4, 100.0, false)
	var target := InventoryData.new(4, 4, 100.0, false)
	if not source.add_item_count_with_metadata(EXPENSIVE_VASE, 1, metadata):
		_fail("Inventory should accept metadata-bearing stolen entry")
		return
	var entry := source.entries[0]
	if not source.move_entry_to_inventory(entry, target, Vector2i.ZERO):
		_fail("Metadata-bearing stolen entry should transfer between inventories")
		return
	var moved_entry := target.entries[0]
	if not target.is_entry_stolen(moved_entry):
		_fail("Transferred stolen entry should preserve stolen metadata")
	var cleared := target.clear_expired_stolen_metadata((10 * 24 * 60) + 1)
	if cleared != 1 or target.is_entry_stolen(moved_entry):
		_fail("Stolen metadata should clear after the ten day expiry")


func _validate_same_settlement_stolen_sale_rules() -> void:
	var player := _get_player()
	var law := _get_law_controller()
	var witness := _scene.get_node_or_null("JailDemoTown/Residents/Witness") as HumanoidCharacter
	if player == null or law == null or witness == null:
		_fail("Sale validation requires player, law controller, and same-settlement merchant witness")
		return
	var metadata: Dictionary = {
		InventoryData.META_STOLEN: true,
		InventoryData.META_STOLEN_FROM_FACTION_ID: DEMO_FACTION_ID,
		InventoryData.META_STOLEN_FROM_SETTLEMENT_ID: DEMO_SETTLEMENT_ID,
		InventoryData.META_STOLEN_BY_ACTOR_ID: player.stable_id,
		InventoryData.META_STOLEN_AT_MINUTE: 0,
		InventoryData.META_STOLEN_EXPIRES_AT_MINUTE: 10 * 24 * 60,
	}
	if not player.inventory.add_item_count_with_metadata(EXPENSIVE_VASE, 1, metadata):
		_fail("Player inventory should accept a metadata-bearing stolen sale item")
		return
	var entry: InventoryData.InventoryEntry = _find_inventory_entry(player.inventory, EXPENSIVE_VASE)
	if entry == null:
		_fail("Could not find metadata-bearing sale item")
		return
	if bool(law.call("can_sell_entry_to_merchant", player, witness, entry)):
		_fail("Same-settlement merchant should refuse actively stolen goods")
	law.call("_clear_warrant_for_actor", player, DEMO_FACTION_ID)
	var distant_merchant := Node3D.new()
	distant_merchant.name = "DistantMerchant"
	distant_merchant.position = Vector3(180.0, 0.0, 0.0)
	_scene.add_child(distant_merchant)
	if not bool(law.call("can_sell_entry_to_merchant", player, distant_merchant, entry)):
		_fail("Different-settlement merchant should accept stolen goods while tag is active")
	distant_merchant.queue_free()
	player.inventory.remove_entry(entry)


func _validate_no_jail_ejection_fallback() -> void:
	var law := _get_law_controller()
	if law == null:
		_fail("Law controller should exist for no-jail fallback validation")
		return
	var settlement: Node3D = SETTLEMENT_TOWN_SCRIPT.new()
	settlement.name = "NoJailTown"
	settlement.set("settlement_definition", _make_settlement_definition("no_jail_town", "No Jail Town"))
	settlement.set("town_border_radius", 12.0)
	_scene.add_child(settlement)
	var actor := _make_validation_humanoid("NoJailCriminal", "npc.no_jail.criminal", Vector3.ZERO)
	settlement.add_child(actor)
	await _wait_frames(8)
	actor.global_position = settlement.global_position
	law.call("report_crime", actor, DEMO_FACTION_ID, "no_jail_town", LawOrderController.CRIME_THEFT, 10, null, null)
	actor.set("life_state", NpcRules.LifeState.UNCONSCIOUS)
	law.call("_process_warrants")
	await _wait_frames(4)
	if settlement.global_position.distance_to(actor.global_position) <= 12.0:
		_fail("No-jail fallback should eject the prisoner outside the town border")
	if int(actor.get("life_state")) != NpcRules.LifeState.UNCONSCIOUS:
		_fail("No-jail fallback should not heal or revive the ejected prisoner")
	if bool(law.call("actor_has_active_warrant", actor, DEMO_FACTION_ID)):
		_fail("No-jail fallback should clear the processed warrant after ejection")
	settlement.queue_free()


func _make_settlement_definition(settlement_id: String, display_name: String) -> Resource:
	var definition: Resource = SETTLEMENT_DEFINITION_SCRIPT.new()
	definition.set("settlement_id", settlement_id)
	definition.set("display_name", display_name)
	definition.set("faction_definition", FARMERS_FACTION)
	return definition


func _make_validation_humanoid(node_name: String, stable_id: String, local_position: Vector3) -> HumanoidCharacter:
	var actor := CharacterBody3D.new()
	actor.name = node_name
	actor.set_script(FACTION_HUMANOID_SCRIPT)
	actor.position = local_position
	actor.set("member_name", node_name)
	actor.set("stable_id", stable_id)
	actor.set("faction_name", "Player")
	var collision := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.45
	capsule.height = 1.1
	collision.shape = capsule
	collision.position.y = 0.95
	actor.add_child(collision)
	var body := MeshInstance3D.new()
	body.name = "BodyMesh"
	body.position.y = 0.95
	var mesh := CapsuleMesh.new()
	mesh.radius = 0.45
	body.mesh = mesh
	actor.add_child(body)
	return actor as HumanoidCharacter


func _find_inventory_entry(inventory: InventoryData, definition: Resource) -> InventoryData.InventoryEntry:
	if inventory == null:
		return null
	for entry in inventory.entries:
		if entry.definition == definition:
			return entry
	return null


func _find_cell_holding(jail: Node, actor: Node) -> Node:
	if jail == null or actor == null or not jail.has_method("get_cells"):
		return null
	for cell in jail.call("get_cells"):
		if cell == null or not cell.has_method("get_cell_id"):
			continue
		if cell.has_method("has_occupant") and bool(cell.call("has_occupant", actor)):
			return cell
	return null


func _validate_jail_cell_authoring(jail: Node) -> void:
	if jail == null or not jail.has_method("get_cells"):
		return
	if absf(HumanoidCharacter.CELL_CUSTODY_LAY_FREEZE_RATIO - 0.6) > 0.001:
		_fail("Cell custody lay animation should freeze at 60 percent")
	var cells: Array = jail.call("get_cells")
	if cells.is_empty():
		_fail("Jail should have authored cells")
		return
	var first_cell = cells[0]
	var visual_transform: Transform3D = first_cell.get("visual_transform") if first_cell != null and first_cell.get("visual_transform") != null else Transform3D.IDENTITY
	if visual_transform.basis.x.length() < 1.2:
		_fail("Reusable jail cell cage should be enlarged")
	if first_cell != null and first_cell.has_method("get_prisoner_position"):
		var prisoner_position: Vector3 = first_cell.call("get_prisoner_position", null)
		if prisoner_position.y > -0.2:
			_fail("Reusable jail cell prisoner point should be lowered to the cage floor")
	if cells.size() >= 3:
		var previous_cell := cells[0] as Node3D
		for index in range(1, 3):
			var current_cell := cells[index] as Node3D
			if previous_cell == null or current_cell == null:
				continue
			var horizontal_spacing := Vector2(current_cell.global_position.x - previous_cell.global_position.x, current_cell.global_position.z - previous_cell.global_position.z).length()
			if horizontal_spacing < 2.3:
				_fail("Authored jail cells should be spaced for enlarged cages")
			previous_cell = current_cell


func _validate_guard_post_preserves_combat(owner: Node, guard: HumanoidCharacter, target: HumanoidCharacter, label: String) -> void:
	if owner == null or guard == null or target == null:
		_fail("%s guard-post combat validation requires owner, guard, and target" % label)
		return
	if not owner.has_method("_process_guard_post_assignment"):
		if label == "Town":
			return
		_fail("%s should expose guard-post assignment for validation" % label)
		return
	var original_transform := guard.global_transform
	guard.disengage_combat_with(target)
	target.disengage_combat_with(guard)
	guard.global_position = original_transform.origin + Vector3(8.0, 0.0, 0.0)
	guard.assign_attack_target(target, false, false, false)
	owner.call("_process_guard_post_assignment", guard)
	if guard.get_current_combat_target() != target or not guard.is_in_combat():
		_fail("%s guard-post assignment should not cancel active combat" % label)
	guard.disengage_combat_with(target)
	target.disengage_combat_with(guard)
	guard.global_transform = original_transform
	guard.velocity = Vector3.ZERO


func _validate_combat_order_priority(guard: HumanoidCharacter, target: HumanoidCharacter) -> void:
	if guard == null or target == null:
		_fail("Combat order priority validation requires guard and target")
		return
	var guard_transform := guard.global_transform
	var target_transform := target.global_transform
	_reset_validation_combat_pair(guard, target)
	guard.global_position = Vector3(-7.0, 0.6, -2.0)
	target.global_position = Vector3(-4.5, 0.6, -2.0)
	guard.assign_attack_target(target, false, false, false)
	guard.set_move_target(guard.global_position + Vector3(5.0, 0.0, 0.0), false)
	if guard.get_current_combat_target() != target or not guard.is_in_combat():
		_fail("Non-player movement should not cancel active combat")
	guard.set_move_target(guard.global_position + Vector3(5.0, 0.0, 0.0), true)
	if guard.is_in_combat():
		_fail("Player-issued movement should be able to cancel active combat")
	_restore_validation_combat_pair(guard, target, guard_transform, target_transform)


func _validate_no_nav_long_range_combat_chase(guard: HumanoidCharacter, target: HumanoidCharacter) -> void:
	if guard == null or target == null:
		_fail("Long-range combat chase validation requires guard and target")
		return
	var guard_transform := guard.global_transform
	var target_transform := target.global_transform
	_reset_validation_combat_pair(guard, target)
	guard.global_position = Vector3(-12.0, 0.6, -6.0)
	target.global_position = Vector3(-2.0, 0.6, -6.0)
	var initial_distance := guard.global_position.distance_to(target.global_position)
	guard.assign_attack_target(target, false, false, false)
	await _wait_frames(45)
	if guard.get_current_combat_target() != target or not guard.is_in_combat():
		_fail("Long-range combat chase should not drop attack orders in the jail demo")
	elif guard.global_position.distance_to(target.global_position) >= initial_distance - 0.25:
		_fail("Long-range combat chase should pursue the target without requiring navmesh pathing")
	_restore_validation_combat_pair(guard, target, guard_transform, target_transform)


func _reset_validation_combat_pair(left: HumanoidCharacter, right: HumanoidCharacter) -> void:
	left.call("_clear_all_active_orders")
	right.call("_clear_all_active_orders")
	left.disengage_combat_with(right)
	right.disengage_combat_with(left)
	left.velocity = Vector3.ZERO
	right.velocity = Vector3.ZERO


func _reset_validation_combat_actors(actors: Array) -> void:
	for actor in actors:
		if not (actor is HumanoidCharacter):
			continue
		(actor as HumanoidCharacter).call("_clear_all_active_orders")
		(actor as HumanoidCharacter).call("clear_all_personal_hostility")
		(actor as HumanoidCharacter).velocity = Vector3.ZERO
	for left_index in range(actors.size()):
		var left := actors[left_index] as HumanoidCharacter
		if left == null:
			continue
		for right_index in range(left_index + 1, actors.size()):
			var right := actors[right_index] as HumanoidCharacter
			if right == null:
				continue
			left.disengage_combat_with(right)
			right.disengage_combat_with(left)


func _restore_validation_combat_pair(left: HumanoidCharacter, right: HumanoidCharacter, left_transform: Transform3D, right_transform: Transform3D) -> void:
	_reset_validation_combat_pair(left, right)
	left.global_transform = left_transform
	right.global_transform = right_transform


func _save_actor_transforms(actors: Array) -> Dictionary:
	var transforms := {}
	for actor in actors:
		if actor is HumanoidCharacter:
			transforms[actor] = (actor as HumanoidCharacter).global_transform
	return transforms


func _restore_actor_transforms(transforms: Dictionary) -> void:
	for actor in transforms.keys():
		if actor is HumanoidCharacter:
			(actor as HumanoidCharacter).global_transform = transforms[actor]
			(actor as HumanoidCharacter).velocity = Vector3.ZERO


func _record_has_crime(record: Dictionary, crime_type: String) -> bool:
	var crimes: Array = record.get("crimes", [])
	for crime in crimes:
		if crime is Dictionary and str(crime.get("crime_type", "")) == crime_type:
			return true
	return false


func _force_sentence_decision_ready(law: Node, actor: HumanoidCharacter) -> void:
	if law == null or actor == null:
		return
	var key := str(actor.get("stable_id"))
	var records: Dictionary = law.get("prisoner_records") if law.get("prisoner_records") != null else {}
	if not records.has(key):
		return
	var record: Dictionary = records[key]
	record["sentence_decision_at_minute"] = -1
	record["sentence_decision_given"] = false
	records[key] = record
	law.set("prisoner_records", records)


func _sentence_notification_given(law: Node, actor: HumanoidCharacter) -> bool:
	if law == null or actor == null:
		return false
	var key := str(actor.get("stable_id"))
	var records: Dictionary = law.get("prisoner_records") if law.get("prisoner_records") != null else {}
	if not records.has(key):
		return false
	var record: Dictionary = records[key]
	return bool(record.get("sentence_notification_given", false))


func _close_active_conversation() -> void:
	var controller := root.find_child("ConversationController", true, false)
	if controller != null and controller.has_method("_end_conversation"):
		controller.call("_end_conversation")


func _is_warden_at_home_post(jail: Node, warden: HumanoidCharacter) -> bool:
	var post := _get_warden_home_post(jail)
	if post == null or warden == null:
		return false
	return _horizontal_distance(warden.global_position, post.global_position) <= 0.75


func _horizontal_distance(left: Vector3, right: Vector3) -> float:
	return Vector2(left.x - right.x, left.z - right.z).length()


func _get_warden_home_post(jail: Node) -> Node3D:
	return jail.get_node_or_null("WardenPosts/WardenPost") as Node3D if jail != null else null


func _is_law_responder_arresting_actor(responder: HumanoidCharacter, actor: HumanoidCharacter) -> bool:
	return responder != null and responder.has_method("is_law_arresting") and bool(responder.call("is_law_arresting", actor))


func _find_guard_carrying_actor(actor: HumanoidCharacter) -> HumanoidCharacter:
	if actor == null:
		return null
	for node in root.get_tree().get_nodes_in_group("npc_character"):
		var guard := node as HumanoidCharacter
		if guard != null and guard.has_method("get_carried_character") and guard.call("get_carried_character") == actor:
			return guard
	return null


func _get_player() -> HumanoidCharacter:
	return _scene.get_node_or_null("PartyMembers/Mira") as HumanoidCharacter if _scene != null else null


func _get_jail() -> Node:
	return _scene.get_node_or_null("JailDemoTown/Facilities/Jail") if _scene != null else null


func _get_law_controller() -> Node:
	return root.find_child("LawOrderController", true, false)


func _get_world_time_controller() -> Node:
	return root.find_child("WorldTimeController", true, false)


func _get_current_animation(actor: HumanoidCharacter) -> String:
	var body := actor.get_body_projection()
	return body.get_current_clip() if body != null else ""


func _wait_frames(count: int) -> void:
	for _index in range(count):
		await process_frame


func _wait_until(condition: Callable, max_frames: int) -> bool:
	for _index in range(max_frames):
		if bool(condition.call()):
			return true
		await process_frame
	return bool(condition.call())


func _fail(message: String) -> void:
	_failures.append(message)
