extends SceneTree

class EcsPlaceholder:
	extends Node
	var debug := false

const DEMO_WORLD_SCENE_PATH := "res://scenes/worlds/demo_world/demo_world.tscn"
const EXPECTED_SETTLEMENT_IDS := ["surf_city", "east_raiders_camp", "paradise_hills"]
const EXPECTED_PLAYER_RECORDS := {
	"player.mira": {
		"member_name": "Mira",
		"max_hp": 118.0,
		"weapon": "steel_sword",
		"weapon_path": "res://resources/items/equipment/weapons/swords/steel_sword.tres",
		"chest": "ranger_jerkin",
		"chest_path": "res://resources/items/equipment/armor/chest/ranger_jerkin.tres",
		"combat_skill": "combat.swords_one_handed",
		"visual_body_type": 3,
	},
	"player.tomas": {
		"member_name": "Tomas",
		"max_hp": 116.0,
		"weapon": "iron_axe",
		"weapon_path": "res://resources/items/equipment/weapons/axes/iron_axe.tres",
		"chest": "peasant_tunic",
		"chest_path": "res://resources/items/equipment/clothing/peasant_tunic.tres",
		"combat_skill": "combat.axes_one_handed",
		"visual_body_type": 2,
	},
}

var _failures: Array[String] = []
var _ecs_placeholder: Node
var _registered_ecs_placeholder := false


func _initialize() -> void:
	_ensure_ecs_placeholder()
	var scene_resource := load(DEMO_WORLD_SCENE_PATH) as PackedScene
	if scene_resource == null:
		push_error("Failed to load %s" % DEMO_WORLD_SCENE_PATH)
		quit(1)
		return
	var scene := scene_resource.instantiate()
	root.add_child(scene)
	call_deferred("_run_validation", scene)


func _run_validation(scene: Node) -> void:
	for _index in range(12):
		await process_frame
	_validate(scene)
	if _failures.is_empty():
		print("DEMO_WORLD_GECS_VALIDATION_OK")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	quit(1)


func _validate(scene: Node) -> void:
	_promote_root_ecs_singleton()
	var bootstrap := scene.get_node_or_null("GameBootstrap")
	_expect(bootstrap != null, "GameBootstrap exists in demo_world.tscn")
	if bootstrap == null:
		return
	var gecs := bootstrap.get_node_or_null("GecsWorldController")
	var combat := bootstrap.get_node_or_null("WorldMapCombatSimController")
	var loader := scene.get_node_or_null("WorldLoader")
	_expect(gecs != null, "GecsWorldController exists under GameBootstrap")
	_expect(combat != null, "WorldMapCombatSimController exists under GameBootstrap")
	_expect(loader != null, "WorldLoader exists in demo world")
	_expect(get_nodes_in_group("demo_sim_bootstrap").is_empty(), "DemoSimBootstrap is absent from playable demo world")
	if gecs == null or combat == null:
		return
	_validate_shared_ecs_world(gecs, combat)
	_validate_towns(scene, loader)
	_validate_settlement_state(gecs)
	_validate_faction_state(gecs)
	_validate_player_population_records(gecs)
	_validate_world_squad_state(gecs, combat)
	_validate_projected_placements(scene)
	_validate_camera_control(scene)
	_validate_hud_shell(scene)


func _validate_shared_ecs_world(gecs: Node, combat: Node) -> void:
	var ecs_node := root.get_node_or_null("ECS")
	_expect(ecs_node != null, "/root/ECS exists")
	var gecs_world = gecs.get("world")
	_expect(gecs_world != null, "GecsWorldController owns a GECS world")
	if ecs_node != null:
		_expect(ecs_node.get("world") == gecs_world, "/root/ECS.world is the GameBootstrap GECS world")
	_expect(not bool(combat.get("use_isolated_ecs_world")), "WorldMapCombatSimController uses shared GECS world")
	_expect(combat.get("_ecs_world") == gecs_world, "WorldMapCombatSimController references shared GECS world")


func _validate_towns(scene: Node, loader: Node) -> void:
	var towns_root := scene.get_node_or_null("Towns")
	_expect(towns_root != null, "Towns root exists")
	if towns_root != null:
		_expect(towns_root.get_child_count() == EXPECTED_SETTLEMENT_IDS.size(), "WorldLoader instantiated 3 town scenes")
	_expect(get_nodes_in_group("settlement_town").size() == EXPECTED_SETTLEMENT_IDS.size(), "3 settlement_town authoring nodes registered")
	if loader != null:
		var loaded_towns = loader.get("loaded_towns")
		_expect(loaded_towns is Array and loaded_towns.size() == EXPECTED_SETTLEMENT_IDS.size(), "WorldLoader.loaded_towns has 3 entries")


func _validate_settlement_state(gecs: Node) -> void:
	var states: Dictionary = gecs.call("get_settlement_states") if gecs.has_method("get_settlement_states") else {}
	for settlement_id in EXPECTED_SETTLEMENT_IDS:
		_expect(states.has(settlement_id), "GECS has settlement state: %s" % settlement_id)
		if states.has(settlement_id):
			var state: Dictionary = states[settlement_id]
			_expect(state.get("world_position", null) is Vector3, "Settlement has world_position: %s" % settlement_id)
			_expect(int(state.get("max_occupancy", 0)) > 0, "Settlement has population capacity: %s" % settlement_id)
			_expect((state.get("facilities", {}) is Dictionary) and not (state.get("facilities", {}) as Dictionary).is_empty(), "Settlement has facility records: %s" % settlement_id)


func _validate_faction_state(gecs: Node) -> void:
	var faction_state: Dictionary = gecs.call("get_faction_state") if gecs.has_method("get_faction_state") else {}
	var diplomatic_states = faction_state.get("diplomatic_states", {})
	var faction_outlooks = faction_state.get("faction_outlooks", {})
	_expect(diplomatic_states is Dictionary and not diplomatic_states.is_empty(), "GECS faction diplomatic states exist")
	_expect(faction_outlooks is Dictionary and not faction_outlooks.is_empty(), "GECS faction outlooks exist")


func _validate_player_population_records(gecs: Node) -> void:
	for actor_id in EXPECTED_PLAYER_RECORDS.keys():
		var expected: Dictionary = EXPECTED_PLAYER_RECORDS[actor_id]
		var record: Dictionary = gecs.call("get_population_record", actor_id) if gecs.has_method("get_population_record") else {}
		_expect(not record.is_empty(), "GECS has player population record: %s" % actor_id)
		if record.is_empty():
			continue
		_expect(str(record.get("stable_id", "")) == actor_id, "Player record stable_id: %s" % actor_id)
		_expect(str(record.get("member_name", "")) == str(expected.get("member_name", "")), "Player record member name: %s" % actor_id)
		_expect(str(record.get("faction_id", "")) == "Player", "Player record faction: %s" % actor_id)
		_expect(str(record.get("squad_name", "")) == "PlayerParty", "Player record squad: %s" % actor_id)
		_expect(str(record.get("role_id", "")) == "party_member", "Player record role: %s" % actor_id)
		_expect(str(record.get("party_id", "")) == "player_party", "Player record party id: %s" % actor_id)
		_expect(bool(record.get("player_party_member", false)), "Player record party member flag: %s" % actor_id)
		_expect(bool(record.get("player_controllable", false)), "Player record controllable flag: %s" % actor_id)
		_expect(str(record.get("projection_kind", "")) == "humanoid", "Player record humanoid projection hook: %s" % actor_id)
		_expect(str(record.get("realization_state", "")) == "ledger", "Player record starts without live visual dependency: %s" % actor_id)
		_expect(bool(record.get("important", false)), "Player record important flag: %s" % actor_id)
		_expect(int(record.get("life_state", -1)) == 0, "Player record alive life state: %s" % actor_id)
		_expect(absf(float(record.get("max_hp", 0.0)) - float(expected.get("max_hp", 0.0))) < 0.01, "Player record max HP: %s" % actor_id)
		_expect(float(record.get("hp", 0.0)) > 0.0, "Player record HP: %s" % actor_id)
		_expect(float(record.get("blood", 0.0)) > 0.0 and float(record.get("max_blood", 0.0)) > 0.0, "Player record blood vitals: %s" % actor_id)
		_expect(float(record.get("base_attack_damage", 0.0)) > 0.0, "Player record combat damage: %s" % actor_id)
		var skill_levels: Dictionary = record.get("skill_levels", {}) if record.get("skill_levels", {}) is Dictionary else {}
		_expect(int(skill_levels.get("attribute.strength", 0)) > 0, "Player record has attribute skills: %s" % actor_id)
		_expect(int(skill_levels.get(str(expected.get("combat_skill", "")), 0)) > 0, "Player record has combat skill: %s" % actor_id)
		var appearance: Dictionary = record.get("appearance", {}) if record.get("appearance", {}) is Dictionary else {}
		_expect(str(appearance.get("character_race", "")) == "res://resources/character_races/human.tres", "Player record human race appearance: %s" % actor_id)
		_expect(not str(appearance.get("body_archetype", "")).is_empty(), "Player record body archetype appearance: %s" % actor_id)
		_expect(int(appearance.get("visual_body_type", 0)) == int(expected.get("visual_body_type", 0)), "Player record visual body type: %s" % actor_id)
		var equipment_slots: Dictionary = record.get("equipment_slots", {}) if record.get("equipment_slots", {}) is Dictionary else {}
		var equipment_slot_paths: Dictionary = record.get("equipment_slot_paths", {}) if record.get("equipment_slot_paths", {}) is Dictionary else {}
		_expect(str(equipment_slots.get("weapon", "")) == str(expected.get("weapon", "")), "Player record weapon equipment: %s" % actor_id)
		_expect(str(equipment_slots.get("chest", "")) == str(expected.get("chest", "")), "Player record chest equipment: %s" % actor_id)
		_expect(str(equipment_slot_paths.get("weapon", "")) == str(expected.get("weapon_path", "")), "Player record weapon equipment path: %s" % actor_id)
		_expect(str(equipment_slot_paths.get("chest", "")) == str(expected.get("chest_path", "")), "Player record chest equipment path: %s" % actor_id)
		var inventory_entries: Array = record.get("inventory_entries", []) if record.get("inventory_entries", []) is Array else []
		_expect(_inventory_has_item(inventory_entries, "res://resources/items/consumables/bandage.tres"), "Player record has inventory entries: %s" % actor_id)


func _inventory_has_item(entries: Array, item_path: String) -> bool:
	var item_id := ItemDefinitionIndex.item_id_for(item_path)
	for entry in entries:
		if entry is Dictionary and (str((entry as Dictionary).get("item_id", "")) == item_id or str((entry as Dictionary).get("item_definition_path", "")) == item_path):
			return true
	return false


func _validate_world_squad_state(gecs: Node, combat: Node) -> void:
	var bridge_state: Dictionary = gecs.call("get_world_squad_state") if gecs.has_method("get_world_squad_state") else {}
	var combat_state: Dictionary = combat.call("get_world_squad_state") if combat.has_method("get_world_squad_state") else {}
	var active_squads = combat_state.get("active_squads", {})
	_expect(active_squads is Dictionary and active_squads.size() >= 3, "WorldMapCombatSimController has demo squad state")
	_expect(bridge_state.get("active_squads", {}) is Dictionary and (bridge_state.get("active_squads", {}) as Dictionary).size() >= 3, "GECS bridge can read world squad state")


func _validate_projected_placements(scene: Node) -> void:
	var projector := scene.get_node_or_null("WorldMapPlacementProjector")
	_expect(projector != null, "WorldMapPlacementProjector exists")
	if projector == null or not projector.has_method("get_projected_town_marker_data"):
		return
	var town_markers: Array = projector.call("get_projected_town_marker_data")
	_expect(town_markers.size() == EXPECTED_SETTLEMENT_IDS.size(), "Map projector resolves 3 settlement placements")


func _validate_camera_control(scene: Node) -> void:
	var rig := scene.get_node_or_null("CameraRig")
	var camera := scene.get_node_or_null("CameraRig/CameraPivot/Camera3D") as Camera3D
	_expect(rig != null and rig.has_method("follow_target"), "CameraRig has world camera controller")
	_expect(camera != null and camera.current, "Demo world camera is current")


func _validate_hud_shell(scene: Node) -> void:
	var hud := scene.get_node_or_null("GameHUD") as CanvasLayer
	_expect(hud != null, "GameHUD is bootstrapped")
	if hud == null:
		return
	_expect(hud.visible, "GameHUD is visible")
	var required_paths := [
		"SelectionRect",
		"ProgressLayer",
		"ContextMenu",
		"FloatingNotice",
		"WorldClockPanel/Margin/ClockRow/TimeLabel",
		"WorldClockPanel/Margin/ClockRow/PhaseLabel",
		"WorldClockPanel/Margin/ClockRow/SpeedButtonRow/PauseButton",
		"WorldClockPanel/Margin/ClockRow/SpeedButtonRow/SlowButton",
		"WorldClockPanel/Margin/ClockRow/SpeedButtonRow/NormalButton",
		"WorldClockPanel/Margin/ClockRow/SpeedButtonRow/FastButton",
		"WorldClockPanel/Margin/ClockRow/SpeedButtonRow/VeryFastButton",
		"FPSLabel",
		"HudLayout/BottomHud/InspectorSlot/HumanoidDetailsPanel",
		"HudLayout/BottomHud/RightHud/BottomInfoRow/CommandDock",
		"HudLayout/BottomHud/RightHud/BottomInfoRow/CommandDock/Margin/CommandColumn/BehaviorRows/MoveRow/MovementSegment/WalkButton",
		"HudLayout/BottomHud/RightHud/BottomInfoRow/CommandDock/Margin/CommandColumn/BehaviorRows/MoveRow/MovementSegment/RunningButton",
		"HudLayout/BottomHud/RightHud/BottomInfoRow/CommandDock/Margin/CommandColumn/BehaviorRows/MoveRow/MovementSegment/SneakingButton",
		"HudLayout/BottomHud/RightHud/BottomInfoRow/CommandDock/Margin/CommandColumn/BehaviorRows/FightRow/CombatSegment/AggressiveButton",
		"HudLayout/BottomHud/RightHud/BottomInfoRow/CommandDock/Margin/CommandColumn/BehaviorRows/FightRow/CombatSegment/DefensiveButton",
		"HudLayout/BottomHud/RightHud/BottomInfoRow/CommandDock/Margin/CommandColumn/BehaviorRows/FightRow/CombatSegment/PassiveButton",
		"HudLayout/BottomHud/RightHud/BottomInfoRow/CommandDock/Margin/CommandColumn/BehaviorRows/AssistRow/AutoHealButton",
		"HudLayout/BottomHud/RightHud/BottomInfoRow/CommandDock/Margin/CommandColumn/BehaviorRows/AssistRow/BurnRustdeadButton",
		"HudLayout/BottomHud/RightHud/BottomInfoRow/PortraitBar/Margin/PortraitColumn/SquadTabs/AllButton",
		"HudLayout/BottomHud/RightHud/BottomInfoRow/PortraitBar/Margin/PortraitColumn/SquadTabs/AddSquadButton",
		"HudLayout/BottomHud/RightHud/BottomInfoRow/PortraitBar/Margin/PortraitColumn/SquadCommandStrip/SquadName",
		"HudLayout/BottomHud/RightHud/BottomInfoRow/PortraitBar/Margin/PortraitColumn/SquadCommandStrip/FormationButton",
		"HudLayout/BottomHud/RightHud/BottomInfoRow/PortraitBar/Margin/PortraitColumn/SquadCommandStrip/SquadAIButton",
		"HudLayout/BottomHud/RightHud/BottomInfoRow/PortraitBar/Margin/PortraitColumn/PortraitScroll/PortraitFlow",
		"InventoryWindowLayer",
		"PauseOverlay",
		"ConversationWindow",
	]
	for path in required_paths:
		_expect(hud.get_node_or_null(NodePath(path)) != null, "GameHUD node exists: %s" % path)
	var fps_label := hud.get_node_or_null("FPSLabel") as Label
	_expect(fps_label != null and fps_label.mouse_filter == Control.MOUSE_FILTER_IGNORE, "Performance overlay ignores input")
	if fps_label != null:
		_expect(fps_label.text.contains("FPS:"), "Performance overlay includes FPS")
		_expect(fps_label.text.contains("GECS:"), "Performance overlay includes GECS timing")
		_expect(fps_label.text.contains("Actors:"), "Performance overlay includes actor count")
	for path in [
		"HudLayout/BottomHud/RightHud/BottomInfoRow/PortraitBar/Margin/PortraitColumn/SquadCommandStrip/FormationButton",
		"HudLayout/BottomHud/RightHud/BottomInfoRow/PortraitBar/Margin/PortraitColumn/SquadCommandStrip/SquadAIButton",
	]:
		var button := hud.get_node_or_null(NodePath(path)) as Button
		_expect(button != null and button.disabled, "GameHUD disabled shell button: %s" % path)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _ensure_ecs_placeholder() -> void:
	if Engine.has_singleton("ECS"):
		return
	_ecs_placeholder = EcsPlaceholder.new()
	_ecs_placeholder.name = "ECSPlaceholder"
	Engine.register_singleton("ECS", _ecs_placeholder)
	_registered_ecs_placeholder = true


func _promote_root_ecs_singleton() -> void:
	if not _registered_ecs_placeholder:
		return
	var ecs_node := root.get_node_or_null("ECS")
	if ecs_node == null:
		return
	Engine.unregister_singleton("ECS")
	if _ecs_placeholder != null:
		_ecs_placeholder.free()
		_ecs_placeholder = null
	Engine.register_singleton("ECS", ecs_node)
	_registered_ecs_placeholder = false
