extends SceneTree

const TWO_TOWNS_SCENE := preload("res://scenes/test_levels/two_towns_road_test.tscn")
const SKIN_TEXTURE_BUILDER := preload("res://scripts/character_appearance/skin_texture_builder.gd")
const FARMER_PROFILE := preload("res://resources/world_sim/population_appearance_profiles/farmer_peasant.tres")
const RAIDER_PROFILE := preload("res://resources/world_sim/population_appearance_profiles/raider_scrapper.tres")
const FARMER_NAME_PROFILE := preload("res://resources/world_sim/population_name_profiles/farmer_names.tres")
const RAIDER_NAME_PROFILE := preload("res://resources/world_sim/population_name_profiles/raider_names.tres")
const CAPTIVE_NAME_PROFILE := preload("res://resources/world_sim/population_name_profiles/captive_names.tres")
const FARMER_PERSONALITY_PROFILE := preload("res://resources/world_sim/personality_profiles/farmer_communal.tres")
const RAIDER_PERSONALITY_PROFILE := preload("res://resources/world_sim/personality_profiles/raider_predatory.tres")
const COMMON_LAW_PROFILE := preload("res://resources/world_sim/law_profiles/common_settlement_law.tres")
const RAIDER_LAW_PROFILE := preload("res://resources/world_sim/law_profiles/raider_challenge_law.tres")
const SLAVE_PROFILE := preload("res://resources/world_sim/population_appearance_profiles/slave_rags.tres")
const PEASANT_TUNIC := preload("res://resources/items/peasant_tunic.tres")
const PEASANT_TROUSERS := preload("res://resources/items/peasant_trousers.tres")
const PEASANT_SHOES := preload("res://resources/items/peasant_shoes.tres")
const RANGER_JERKIN := preload("res://resources/items/ranger_jerkin.tres")
const RANGER_LEGGINGS := preload("res://resources/items/ranger_leggings.tres")
const RANGER_BOOTS := preload("res://resources/items/ranger_boots.tres")
const RANGER_HOOD := preload("res://resources/items/ranger_hood.tres")
const HATCHET := preload("res://resources/items/hatchet.tres")
const IRON_SWORD := preload("res://resources/items/iron_sword.tres")
const BANDAGE := preload("res://resources/items/bandage.tres")
const SILVER := preload("res://resources/items/silver.tres")
const VISUAL_BODY_TYPE_MALE := 2
const VISUAL_BODY_TYPE_FEMALE := 3

var _failures: Array[String] = []
var _scene: Node


func _initialize() -> void:
	root.size = Vector2i(1280, 720)
	call_deferred("_run")


func _run() -> void:
	_scene = TWO_TOWNS_SCENE.instantiate()
	root.add_child(_scene)
	await _wait_frames(120)
	_validate_culture_profile_source("Settlements/FarmerCrossing/Residents", FARMER_NAME_PROFILE, FARMER_PERSONALITY_PROFILE, COMMON_LAW_PROFILE, "Farmer")
	_validate_culture_profile_source("Settlements/RaiderCamp/Residents", RAIDER_NAME_PROFILE, RAIDER_PERSONALITY_PROFILE, RAIDER_LAW_PROFILE, "Raider")
	_validate_faction_diplomacy_and_events()
	_validate_resident_group("Settlements/FarmerCrossing/Residents", FARMER_PROFILE, FARMER_NAME_PROFILE, [PEASANT_TUNIC], [PEASANT_TROUSERS], [PEASANT_SHOES], [], HATCHET, "Farmer")
	_validate_resident_group("Settlements/RaiderCamp/Residents", RAIDER_PROFILE, RAIDER_NAME_PROFILE, [RANGER_JERKIN, PEASANT_TUNIC], [RANGER_LEGGINGS, PEASANT_TROUSERS], [RANGER_BOOTS, PEASANT_SHOES], [RANGER_HOOD], IRON_SWORD, "Raider")
	_validate_slave_group("Settlements/RaiderCamp/Residents/Slaves")
	var farmer_names := _collect_resident_name_map("Settlements/FarmerCrossing/Residents", "Farmer")
	var raider_names := _collect_resident_name_map("Settlements/RaiderCamp/Residents", "Raider")
	root.remove_child(_scene)
	_scene.queue_free()
	await _wait_frames(5)
	_scene = TWO_TOWNS_SCENE.instantiate()
	root.add_child(_scene)
	await _wait_frames(120)
	_validate_name_stability("Settlements/FarmerCrossing/Residents", farmer_names, "Farmer")
	_validate_name_stability("Settlements/RaiderCamp/Residents", raider_names, "Raider")
	if _failures.is_empty():
		print("TWO_TOWNS_POPULATION_APPEARANCE_OK")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	print("TWO_TOWNS_POPULATION_APPEARANCE_FAILED count=%d" % _failures.size())
	quit(1)


func _validate_resident_group(path: String, profile: Resource, name_profile: Resource, chest_pool: Array, leg_pool: Array, feet_pool: Array, head_pool: Array, weapon: Resource, label: String) -> void:
	var root_node := _scene.get_node_or_null(path)
	if root_node == null:
		_fail("%s resident root missing" % label)
		return
	var residents: Array[HumanoidCharacter] = []
	var seen_names := {}
	for child in root_node.get_children():
		if child is HumanoidCharacter:
			residents.append(child as HumanoidCharacter)
	if residents.size() <= 3:
		_fail("%s population did not include generated residents; count=%d" % [label, residents.size()])
	for resident in residents:
		_validate_resident(resident, profile, name_profile, chest_pool, leg_pool, feet_pool, head_pool, weapon, label, seen_names)


func _validate_culture_profile_source(path: String, name_profile: Resource, personality_profile: Resource, law_profile: Resource, label: String) -> void:
	var root_node := _scene.get_node_or_null(path)
	if root_node == null:
		_fail("%s resident root missing for culture profile source" % label)
		return
	if root_node.get("population_name_profile") != null:
		_fail("%s spawner should use faction name fallback unless this local population is intentionally specialized" % label)
	var settlement_definition := root_node.get("settlement_definition") as Resource
	if settlement_definition == null:
		_fail("%s spawner has no settlement definition for culture profile fallback" % label)
		return
	if settlement_definition.has_method("get_population_name_profile") and settlement_definition.call("get_population_name_profile") != name_profile:
		_fail("%s faction/settlement name profile fallback is not wired" % label)
	if settlement_definition.has_method("get_personality_profile") and settlement_definition.call("get_personality_profile") != personality_profile:
		_fail("%s faction/settlement personality profile fallback is not wired" % label)
	if settlement_definition.has_method("get_law_profile") and settlement_definition.call("get_law_profile") != law_profile:
		_fail("%s faction/settlement law profile fallback is not wired" % label)


func _validate_faction_diplomacy_and_events() -> void:
	var faction_controller := _get_controller("faction_controller")
	if faction_controller == null:
		_fail("Faction controller missing")
		return
	if not bool(faction_controller.call("are_hostile", "Farmers", "Raiders")):
		_fail("Farmers and Raiders should be formally hostile through war diplomacy")
	if bool(faction_controller.call("are_hostile", "Player", "Raiders")):
		_fail("Raiders should not be default hostile to Player")
	if str(faction_controller.call("get_diplomatic_state", "Farmers", "Raiders")) != "war":
		_fail("Farmers and Raiders should start in formal war")
	if str(faction_controller.call("get_diplomatic_state", "Player", "Farmers")) != "neutral":
		_fail("Player and Farmers should start neutral")
	if str(faction_controller.call("get_diplomatic_state", "Player", "Raiders")) != "neutral":
		_fail("Player and Raiders should start neutral")
	if bool(faction_controller.call("should_player_help_faction", "Farmers")):
		_fail("Player should not auto-help neutral Farmers by default")
	faction_controller.call("set_help_allies", true)
	if bool(faction_controller.call("should_player_help_faction", "Farmers")):
		_fail("Help allies should not auto-help neutral Farmers")
	faction_controller.call("set_diplomatic_state", "Player", "Farmers", "alliance")
	if not bool(faction_controller.call("should_player_help_faction", "Farmers")):
		_fail("Help allies should auto-help formal allies")
	faction_controller.call("set_diplomatic_state", "Player", "Farmers", "neutral")
	faction_controller.call("set_help_allies", false)
	_validate_party_starting_state()
	_validate_party_portrait_bar_size()
	_validate_faction_menu_ui(faction_controller)
	_validate_forced_raid_prompt()
	_validate_local_conflict_event(faction_controller)


func _validate_party_starting_state() -> void:
	var mira := _scene.get_node_or_null("PartyMembers/Mira") as HumanoidCharacter
	var tomas := _scene.get_node_or_null("PartyMembers/Tomas") as HumanoidCharacter
	var newbie := _scene.get_node_or_null("PartyMembers/Newbie") as HumanoidCharacter
	var stealth := _scene.get_node_or_null("PartyMembers/Stealth") as HumanoidCharacter
	if mira == null or tomas == null or newbie == null or stealth == null:
		_fail("Expected Mira, Tomas, Newbie, and Stealth party members")
		return
	if mira.get_skill_level(SkillRules.ATTRIBUTE_CHARISMA) != 40:
		_fail("Mira should start with Charisma 40")
	if tomas.get_skill_level(SkillRules.ATTRIBUTE_CHARISMA) != 20:
		_fail("Tomas should start with Charisma 20")
	if mira.get_skill_level(SkillRules.SUBTERFUGE_SNEAKING) != 20:
		_fail("Mira should start with Sneaking 20")
	if tomas.get_skill_level(SkillRules.SUBTERFUGE_SNEAKING) != 50:
		_fail("Tomas should start with Sneaking 50")
	if newbie.get_skill_level(SkillRules.SUBTERFUGE_SNEAKING) != SkillRules.DEFAULT_LEVEL:
		_fail("Newbie should start with default Sneaking 1")
	if newbie.get_skill_level(SkillRules.ATTRIBUTE_CHARISMA) != SkillRules.DEFAULT_LEVEL:
		_fail("Newbie should start with default Charisma 1")
	if newbie.get_skill_level(SkillRules.ATTRIBUTE_PERCEPTION) != SkillRules.DEFAULT_LEVEL:
		_fail("Newbie should start with default Perception 1")
	if stealth.get_skill_level(SkillRules.SUBTERFUGE_SNEAKING) != 80:
		_fail("Stealth should start with Sneaking 80")
	for member in [mira, tomas, newbie, stealth]:
		if member.inventory == null:
			_fail("%s should have an inventory" % member.member_name)
			continue
		if member.inventory.count_item(BANDAGE) != 1:
			_fail("%s should start with 1 bandage, got %d" % [member.member_name, member.inventory.count_item(BANDAGE)])
		if member.inventory.count_item(SILVER) != 10:
			_fail("%s should start with 10 silver, got %d" % [member.member_name, member.inventory.count_item(SILVER)])


func _validate_party_portrait_bar_size() -> void:
	var hud := _scene.get_node_or_null("GameHUD")
	if hud == null:
		_fail("GameHUD missing for party portrait bar validation")
		return
	var portrait_scroll := hud.get_node_or_null("HudLayout/BottomHud/RightHud/BottomInfoRow/PortraitBar/Margin/PortraitColumn/PortraitScroll") as ScrollContainer
	if portrait_scroll == null:
		_fail("Party portrait scroll container missing")
		return
	var portrait_flow := portrait_scroll.get_node_or_null("PortraitFlow") as Control
	if portrait_flow == null:
		_fail("Party portrait flow container missing")
		return
	if portrait_flow.get_child_count() < 4:
		_fail("Expected party portrait cards for the starter party")
	for child in portrait_flow.get_children():
		var card := child as Control
		if card == null:
			continue
		if card.custom_minimum_size.y > 68.0:
			_fail("Party portrait card should stay compact enough to avoid default vertical scroll, got %.1f" % card.custom_minimum_size.y)
		var portrait_image := card.get_node_or_null("Margin/VBox/PortraitImage") as Control
		if portrait_image != null and portrait_image.custom_minimum_size.y > 42.0:
			_fail("Party portrait image should stay compact enough to avoid default vertical scroll, got %.1f" % portrait_image.custom_minimum_size.y)
	var vertical_bar := portrait_scroll.get_v_scroll_bar()
	if vertical_bar != null and vertical_bar.visible:
		_fail("Default party portrait row should not show a vertical scrollbar; scroll_size=%s flow_min=%s vbar_max=%.1f page=%.1f" % [portrait_scroll.size, portrait_flow.get_combined_minimum_size(), vertical_bar.max_value, vertical_bar.page])


func _validate_faction_menu_ui(faction_controller: Node) -> void:
	var hud := _scene.get_node_or_null("GameHUD")
	if hud == null:
		_fail("GameHUD missing for factions menu")
		return
	var factions_button := hud.get_node_or_null("HudLayout/BottomHud/RightHud/BottomInfoRow/PortraitBar/Margin/PortraitColumn/SquadCommandStrip/FactionsButton") as Button
	if factions_button == null:
		_fail("Factions menu button missing")
	if hud.get_node_or_null("FactionsButton") != null:
		_fail("Factions menu button should live in the bottom HUD, not float as a root HUD child")
	if hud.get_node_or_null("FactionsWindow") != null:
		_fail("Factions menu should not use a raw Window node")
	if hud.get_node_or_null("FactionsPanel") != null:
		_fail("Factions panel should live in the inventory/menu layer, not as a root HUD child")
	var menu_layer := hud.get_node_or_null("InventoryWindowLayer") as Control
	if menu_layer == null:
		_fail("GameHUD missing inventory/menu layer for factions panel")
		return
	var panel := menu_layer.get_node_or_null("FactionsPanel") as Control
	if panel == null:
		_fail("Factions panel missing")
		return
	var hud_layout := hud.get_node_or_null("HudLayout")
	if hud_layout != null and menu_layer.get_index() <= hud_layout.get_index():
		_fail("Inventory/menu layer should render above the main HUD layout")
	if not (panel is PanelContainer):
		_fail("Factions menu should be a HUD-styled PanelContainer")
	if panel.custom_minimum_size.x < 700.0 or panel.custom_minimum_size.y < 440.0:
		_fail("Factions panel default size is too small")
	if panel.get_node_or_null("Margin/Column/TitleBar") == null:
		_fail("Factions panel missing draggable title bar")
	var body := panel.get_node_or_null("Margin/Column/Body")
	if body == null:
		_fail("Factions panel missing body")
		return
	if body.get_node_or_null("HelpAlliesToggle") == null:
		_fail("Factions panel missing Help allies toggle")
	if body.get_node_or_null("HeaderRow") == null:
		_fail("Factions panel missing column headers")
	var reputation_bar := body.find_child("ReputationBar", true, false) as ProgressBar
	if reputation_bar == null:
		_fail("Factions panel missing reputation bar")
	else:
		if reputation_bar.custom_minimum_size.y > 6.0:
			_fail("Factions reputation bar should be thin")
		var fill_style := reputation_bar.get_theme_stylebox("fill") as StyleBoxFlat
		if fill_style == null or fill_style.bg_color.g < 0.6 or fill_style.bg_color.b < 0.55:
			_fail("Factions reputation bar fill should be teal")
	panel.position = Vector2(5000.0, 5000.0)
	if faction_controller != null and faction_controller.has_method("_clamp_factions_panel_to_viewport"):
		faction_controller.call("_clamp_factions_panel_to_viewport")
	var viewport_size := root.size
	var max_position := Vector2(maxf(0.0, float(viewport_size.x) - panel.size.x), maxf(0.0, float(viewport_size.y) - panel.size.y))
	if panel.position.x > max_position.x + 0.1 or panel.position.y > max_position.y + 0.1:
		_fail("Factions panel did not clamp to the viewport")


func _validate_forced_raid_prompt() -> void:
	var settlement_controller := _get_controller("settlement_controller")
	var event_controller := _get_controller("world_event_choice_controller")
	var world_squad_controller := _get_controller("world_squad_controller")
	var world_time := _scene.get_node_or_null("GameBootstrap/WorldTimeController")
	if settlement_controller == null or event_controller == null or world_squad_controller == null or world_time == null:
		_fail("Controllers missing for forced raid prompt validation")
		return
	var farmer_anchor: Node3D = settlement_controller.call("get_settlement_anchor", "farmer_crossing") as Node3D
	var player := _scene.get_node_or_null("PartyMembers/Mira") as Node3D
	if farmer_anchor == null or player == null:
		_fail("Could not position player for forced raid prompt validation")
		return
	var prompt_position: Vector3 = farmer_anchor.call("get_spawn_position", "defense") if farmer_anchor.has_method("get_spawn_position") else farmer_anchor.global_position
	player.global_position = prompt_position
	var event_id := "raider_camp:farmer_crossing:%d" % int(world_time.call("get_absolute_hour"))
	var event_count_before := int(event_controller.call("get_event_count"))
	if not bool(settlement_controller.call("force_food_raid", "raider_camp", "farmer_crossing")):
		_fail("Forced Raider raid request failed")
		return
	if int(event_controller.call("get_event_count")) != event_count_before:
		_fail("Forced Raider raid should not create a world conflict event during travel")
	if bool(event_controller.call("is_prompt_visible")):
		_fail("Forced Raider raid should not show a prompt during travel")
	var squad_id := _first_squad_id(world_squad_controller)
	if squad_id.is_empty():
		_fail("Forced Raider raid did not create a world squad")
		return
	var squad_state: Dictionary = world_squad_controller.call("get_squad_state", squad_id)
	if str(squad_state.get("phase_id", "")) != "travel":
		_fail("Forced Raider raid should start in travel phase")
	if squad_state.get("operation_profile") == null:
		_fail("Forced Raider raid should use an operation profile")
	_validate_generated_raid_squad_members(world_squad_controller, squad_state)
	world_squad_controller.call("debug_force_phase", squad_id, "planning")
	if int(event_controller.call("get_event_count")) != event_count_before:
		_fail("Forced Raider raid should not create a world conflict event during planning")
	if bool(event_controller.call("is_prompt_visible")):
		_fail("Forced Raider raid should not show a help prompt during planning")
	squad_state = world_squad_controller.call("get_squad_state", squad_id)
	if str(squad_state.get("phase_id", "")) != "planning":
		_fail("Forced Raider raid should enter planning phase before battle")
	var leader := _node_from_path(str(squad_state.get("leader_actor_path", "")))
	if leader == null or leader.get("conversation_definition") == null:
		_fail("Planning Raider leader should expose a parley conversation")
	else:
		_validate_raider_parley_conversation(leader.get("conversation_definition") as Resource)
	world_squad_controller.call("debug_force_phase", squad_id, "battle")
	if int(event_controller.call("get_event_count")) <= event_count_before:
		_fail("Forced Raider raid should create a world conflict event when battle starts")
	var event = event_controller.call("get_event", event_id)
	if event == null:
		_fail("Forced Raider raid battle conflict event missing expected id")
	else:
		if str(event.side_a_faction_id) != "Raiders" or str(event.side_b_faction_id) != "Farmers":
			_fail("Forced Raider raid battle conflict event has wrong factions")
		if not bool(event.call("is_player_in_radius", _scene)):
			_fail("Player should be in forced Raider raid battle prompt radius")
	if not bool(event_controller.call("is_prompt_visible")):
		_fail("Forced Raider raid did not show the local choice prompt in battle")
	if not bool(world_time.call("is_world_paused")):
		_fail("Forced Raider raid battle prompt did not pause the world")
	if event_controller.has_method("debug_ignore_event"):
		event_controller.call("debug_ignore_event", event_id)
	if bool(event_controller.call("is_prompt_visible")):
		_fail("Forced Raider raid prompt did not hide after debug ignore")
	if bool(world_time.call("is_world_paused")):
		_fail("Forced Raider raid prompt did not release world pause after ignore")


func _validate_raider_parley_conversation(conversation: Resource) -> void:
	if conversation == null or not conversation.has_method("get_node_by_id"):
		_fail("Raider parley conversation is not usable")
		return
	var demand_node = conversation.call("get_node_by_id", "demand")
	if demand_node == null:
		_fail("Raider parley conversation missing demand node")
		return
	var found_skill_check := false
	for response in demand_node.responses:
		if response == null:
			continue
		if str(response.get("text")).to_lower() == "leave.":
			_fail("Raider parley should rely on the automatic Leave option")
		var skill_check := {}
		var skill_check_value = response.get("skill_check")
		if skill_check_value is Dictionary:
			skill_check = skill_check_value
		if not skill_check.is_empty() and str(skill_check.get("skill_id", "")) == "attribute.charisma":
			found_skill_check = true
			if not str(response.get("text")).contains("This farm isn't worth your blood"):
				_fail("Raider parley persuade response needs in-world wording")
			if float(skill_check.get("base_chance", 0.0)) != 0.25 or float(skill_check.get("chance_per_level", 0.0)) != 0.03:
				_fail("Raider parley charisma check has wrong chance formula")
	if not found_skill_check:
		_fail("Raider parley conversation missing charisma percent check")


func _validate_generated_raid_squad_members(world_squad_controller: Node, squad_state: Dictionary) -> void:
	var seen_names := {}
	var paths: Array = squad_state.get("actor_paths", [])
	if paths.is_empty():
		_fail("Forced Raider raid should spawn squad actors")
		return
	for path in paths:
		var actor := world_squad_controller.get_node_or_null(path) as HumanoidCharacter
		if actor == null:
			_fail("Forced Raider raid actor path could not be resolved")
			continue
		_validate_resident(actor, RAIDER_PROFILE, RAIDER_NAME_PROFILE, [RANGER_JERKIN, PEASANT_TUNIC], [RANGER_LEGGINGS, PEASANT_TROUSERS], [RANGER_BOOTS, PEASANT_SHOES], [RANGER_HOOD], IRON_SWORD, "Raider squad", seen_names)


func _validate_local_conflict_event(faction_controller: Node) -> void:
	var event_controller := _get_controller("world_event_choice_controller")
	if event_controller == null:
		_fail("World event choice controller missing")
		return
	var raider := _scene.get_node_or_null("Settlements/RaiderCamp/Residents/RaiderA") as HumanoidCharacter
	var farmer := _scene.get_node_or_null("Settlements/FarmerCrossing/Residents/FarmerA") as HumanoidCharacter
	var player := _scene.get_node_or_null("PartyMembers/Mira") as HumanoidCharacter
	if raider == null or farmer == null or player == null:
		_fail("Could not find actors for local conflict event validation")
		return
	var event_id := "validation:farm_raid_choice"
	var event = event_controller.call("create_conflict_event", {
		"event_id": event_id,
		"title": "Validation Conflict",
		"side_a_faction_id": "Raiders",
		"side_a_label": "Raiders",
		"side_b_faction_id": "Farmers",
		"side_b_label": "Farmers",
		"world_position": player.global_position,
		"event_radius": 35.0,
		"participation_seconds_required": 20.0,
		"side_a_actor_paths": [raider.get_path()],
		"side_b_actor_paths": [farmer.get_path()],
	})
	if event == null:
		_fail("Local conflict event was not created")
		return
	if not bool(event_controller.call("is_prompt_visible")):
		_fail("Local conflict event should prompt immediately when player is already in range")
	event_controller.call("debug_choose_side", event_id, "Farmers")
	if bool(event_controller.call("is_prompt_visible")):
		_fail("Local conflict prompt should hide after choosing a side")
	if not player.is_hostile_to(raider):
		_fail("Choosing Farmers should make Raiders temporary event enemies")
	var farmer_rep_before := int(faction_controller.call("get_reputation", "Player", "Farmers"))
	var raider_rep_before := int(faction_controller.call("get_reputation", "Player", "Raiders"))
	event_controller.call("debug_advance_event_participation", event_id, 20.0)
	if int(faction_controller.call("get_reputation", "Player", "Farmers")) <= farmer_rep_before:
		_fail("Helping Farmers should award Farmer reputation after participation")
	if int(faction_controller.call("get_favor_points", "Farmers")) <= 0:
		_fail("Helping Farmers should award Farmer favor after participation")
	if int(faction_controller.call("get_reputation", "Player", "Raiders")) >= raider_rep_before:
		_fail("Helping Farmers should reduce Raider reputation after participation")


func _validate_slave_group(path: String) -> void:
	var root_node := _scene.get_node_or_null(path)
	if root_node == null:
		_fail("Raider slave spawner missing")
		return
	var residents: Array[HumanoidCharacter] = []
	var seen_names := {}
	for child in root_node.get_children():
		if child is HumanoidCharacter:
			residents.append(child as HumanoidCharacter)
	if residents.size() != 3:
		_fail("Raider camp should generate exactly 3 captives; count=%d" % residents.size())
	for resident in residents:
		var resident_label := "Captive %s" % resident.name
		if resident.faction_name != "Captives":
			_fail("%s should use Captives faction" % resident_label)
		if int(resident.combat_stance) != NpcRules.CombatStance.PASSIVE:
			_fail("%s should be passive" % resident_label)
		if resident.get_equipped_item("weapon") != null:
			_fail("%s should not spawn with a weapon" % resident_label)
		_validate_population_name(resident, CAPTIVE_NAME_PROFILE, "Captive", resident_label, seen_names)
		_validate_equipment(resident, [PEASANT_TUNIC], [PEASANT_TROUSERS], [PEASANT_SHOES], [], null, resident_label)
		if resident.appearance_data != null:
			_validate_skeleton_ranges(resident.appearance_data, SLAVE_PROFILE, resident_label)


func _validate_resident(resident: HumanoidCharacter, profile: Resource, name_profile: Resource, chest_pool: Array, leg_pool: Array, feet_pool: Array, head_pool: Array, weapon: Resource, label: String, seen_names: Dictionary) -> void:
	var resident_label := "%s %s" % [label, resident.name]
	_validate_population_name(resident, name_profile, label, resident_label, seen_names)
	var appearance = resident.appearance_data
	if appearance == null:
		_fail("%s has no appearance data" % resident_label)
		return
	if appearance.character_race == null:
		_fail("%s has no generated race" % resident_label)
	if appearance.body_archetype == null:
		_fail("%s has no generated body archetype" % resident_label)
	var body_type := int(appearance.visual_body_type)
	if body_type != VISUAL_BODY_TYPE_MALE and body_type != VISUAL_BODY_TYPE_FEMALE:
		_fail("%s has invalid generated body type %d" % [resident_label, body_type])
	_validate_body_type_allowed(body_type, profile, resident_label)
	_validate_equipment(resident, chest_pool, leg_pool, feet_pool, head_pool, weapon, resident_label)
	_validate_hair_and_beard(appearance, profile, body_type, resident_label)
	_validate_skin(appearance, resident_label)
	_validate_skeleton_ranges(appearance, profile, resident_label)
	_validate_perception_range(resident, 2, 8, resident_label)
	if not resident.has_custom_skin_material():
		_fail("%s did not apply generated custom skin material" % resident_label)


func _validate_population_name(resident: HumanoidCharacter, name_profile: Resource, label: String, resident_label: String, seen_names: Dictionary) -> void:
	var display_name := str(resident.get("member_name")).strip_edges()
	if display_name.is_empty():
		_fail("%s has an empty generated display name" % resident_label)
		return
	if display_name.begins_with("%s " % label):
		_fail("%s still uses placeholder display name '%s'" % [resident_label, display_name])
	if name_profile == null or not name_profile.has_method("contains_name"):
		_fail("%s has no usable name profile" % resident_label)
	elif not bool(name_profile.call("contains_name", display_name)):
		_fail("%s generated display name '%s' outside the name profile" % [resident_label, display_name])
	var nameplate := resident.get_node_or_null("Nameplate") as Label3D
	if nameplate == null:
		_fail("%s has no visible nameplate after generated naming" % resident_label)
	elif nameplate.text != display_name:
		_fail("%s visible nameplate '%s' did not refresh to generated name '%s'" % [resident_label, nameplate.text, display_name])
	var name_key := display_name.to_lower()
	if seen_names.has(name_key):
		_fail("%s duplicated generated display name '%s'" % [resident_label, display_name])
	seen_names[name_key] = true


func _collect_resident_name_map(path: String, label: String) -> Dictionary:
	var result := {}
	var root_node := _scene.get_node_or_null(path)
	if root_node == null:
		_fail("%s resident root missing for name snapshot" % label)
		return result
	for child in root_node.get_children():
		if child is HumanoidCharacter:
			var stable_id := str(child.get("stable_id"))
			if stable_id.is_empty():
				_fail("%s %s has no stable id for name snapshot" % [label, child.name])
			else:
				result[stable_id] = str(child.get("member_name"))
	return result


func _validate_name_stability(path: String, expected_names: Dictionary, label: String) -> void:
	var root_node := _scene.get_node_or_null(path)
	if root_node == null:
		_fail("%s resident root missing for deterministic name check" % label)
		return
	var seen_ids := {}
	for child in root_node.get_children():
		if not (child is HumanoidCharacter):
			continue
		var stable_id := str(child.get("stable_id"))
		var display_name := str(child.get("member_name"))
		seen_ids[stable_id] = true
		if not expected_names.has(stable_id):
			_fail("%s %s generated unexpected stable id '%s' in deterministic name check" % [label, child.name, stable_id])
		elif str(expected_names[stable_id]) != display_name:
			_fail("%s %s generated nondeterministic name '%s'; expected '%s'" % [label, child.name, display_name, str(expected_names[stable_id])])
	for stable_id in expected_names.keys():
		if not seen_ids.has(stable_id):
			_fail("%s stable id '%s' missing from deterministic name check" % [label, stable_id])


func _validate_equipment(resident: HumanoidCharacter, chest_pool: Array, leg_pool: Array, feet_pool: Array, head_pool: Array, weapon: Resource, label: String) -> void:
	_expect_equipped_in(resident, "chest", chest_pool, label)
	_expect_equipped_in(resident, "legs", leg_pool, label)
	_expect_equipped_in(resident, "feet", feet_pool, label)
	if not head_pool.is_empty() and resident.get_equipped_item("head") != null:
		_expect_equipped_in(resident, "head", head_pool, label)
	if weapon != null and resident.get_equipped_item("weapon") != weapon:
		_fail("%s did not preserve expected weapon" % label)


func _validate_body_type_allowed(body_type: int, profile: Resource, label: String) -> void:
	var flags := int(profile.get("allowed_body_type_flags"))
	if body_type == VISUAL_BODY_TYPE_MALE and (flags & 1) == 0:
		_fail("%s generated male body outside profile filter" % label)
	if body_type == VISUAL_BODY_TYPE_FEMALE and (flags & 2) == 0:
		_fail("%s generated female body outside profile filter" % label)


func _validate_hair_and_beard(appearance, profile: Resource, body_type: int, label: String) -> void:
	if appearance.hair_style == null:
		_fail("%s has no generated hair style" % label)
	else:
		_expect_style_supports_body(appearance.hair_style, body_type, "%s hair" % label)
	if not _color_in_palette(appearance.hair_color, profile.call("get_natural_hair_colors") as Array):
		_fail("%s hair color is not from the natural palette" % label)
	if appearance.beard_style != null:
		if body_type != VISUAL_BODY_TYPE_MALE:
			_fail("%s generated a beard on a non-male body" % label)
		_expect_style_supports_body(appearance.beard_style, body_type, "%s beard" % label)
		if not _colors_match(appearance.beard_color, appearance.hair_color):
			_fail("%s beard color does not match hair color" % label)


func _validate_skin(appearance, label: String) -> void:
	if not bool(appearance.skin_color_customized):
		_fail("%s does not have generated custom skin color" % label)
	if not _color_in_palette(appearance.skin_color, SKIN_TEXTURE_BUILDER.NATURAL_SKIN_TONES):
		_fail("%s skin color is not from the natural skin palette" % label)


func _validate_skeleton_ranges(appearance, profile: Resource, label: String) -> void:
	_expect_in_range(float(appearance.height_slider), profile.get("height_range") as Vector2, "%s height" % label)
	_expect_in_range(float(appearance.shoulder_width_slider), profile.get("shoulder_range") as Vector2, "%s shoulders" % label)
	_expect_in_range(float(appearance.arm_length_slider), profile.get("arm_length_range") as Vector2, "%s arms" % label)
	_expect_in_range(float(appearance.neck_length_slider), profile.get("neck_length_range") as Vector2, "%s neck" % label)


func _validate_perception_range(resident: HumanoidCharacter, minimum: int, maximum: int, label: String) -> void:
	if resident == null:
		return
	var perception := resident.get_skill_level(SkillRules.ATTRIBUTE_PERCEPTION)
	if perception < minimum or perception > maximum:
		_fail("%s perception %d outside expected %d..%d" % [label, perception, minimum, maximum])


func _expect_equipped_in(resident: HumanoidCharacter, slot_name: String, pool: Array, label: String) -> void:
	var item := resident.get_equipped_item(slot_name)
	if item == null or not pool.has(item):
		_fail("%s has invalid %s equipment" % [label, slot_name])


func _expect_style_supports_body(style: Resource, body_type: int, label: String) -> void:
	if style == null or not style.has_method("supports_body_type"):
		return
	var body_type_id := "female" if body_type == VISUAL_BODY_TYPE_FEMALE else "male"
	if not bool(style.call("supports_body_type", body_type_id)):
		_fail("%s style does not support %s" % [label, body_type_id])


func _expect_in_range(value: float, range_value: Vector2, label: String) -> void:
	var low := minf(range_value.x, range_value.y) - 0.001
	var high := maxf(range_value.x, range_value.y) + 0.001
	if value < low or value > high:
		_fail("%s %.3f outside %.3f..%.3f" % [label, value, low, high])


func _color_in_palette(color: Color, palette: Array) -> bool:
	for value in palette:
		if value is Color and _colors_match(color, value):
			return true
	return false


func _colors_match(left: Color, right: Color) -> bool:
	return absf(left.r - right.r) < 0.001 \
		and absf(left.g - right.g) < 0.001 \
		and absf(left.b - right.b) < 0.001 \
		and absf(left.a - right.a) < 0.001


func _wait_frames(frame_count: int) -> void:
	for _index in range(frame_count):
		await process_frame


func _get_controller(group_name: String) -> Node:
	var nodes := get_nodes_in_group(group_name)
	return nodes[0] if not nodes.is_empty() else null


func _first_squad_id(world_squad_controller: Node) -> String:
	if world_squad_controller == null or not world_squad_controller.has_method("serialize_state"):
		return ""
	var squads: Dictionary = world_squad_controller.call("serialize_state")
	for squad_id in squads.keys():
		return str(squad_id)
	return ""


func _node_from_path(path: String) -> Node:
	if path.is_empty():
		return null
	return root.get_node_or_null(NodePath(path))


func _fail(message: String) -> void:
	_failures.append(message)
