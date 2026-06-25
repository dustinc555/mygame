extends SceneTree

const QUADBOT_CHARACTER_SCRIPT := preload("res://src/actors/projection/quadbot/quadbot_character.gd")
const QUADBOT_BODY_PROJECTION_SCRIPT := preload("res://src/actors/projection/quadbot/quadbot_body_projection.gd")
const HUMANOID_BODY_PROJECTION_SCRIPT := preload("res://src/actors/projection/humanoid/humanoid_body_projection.gd")
const PARTY_MANAGER_SCRIPT := preload("res://src/core/party/party_manager.gd")
const HUMANOID_DETAILS_CONTROLLER_SCRIPT := preload("res://src/ui/bridge/humanoid_details_controller.gd")
const BLEED_SPLOTCH_CONTROLLER_SCRIPT := preload("res://src/world/projection/bleed_splotch_controller.gd")
const GAME_HUD_SCENE := preload("res://src/ui/projection/game_hud.tscn")
const QUADBOT_RACE := preload("res://resources/character_races/quadbot.tres")
const QUADBOT_BODY_ARCHETYPE := preload("res://resources/character_body_archetypes/quadbot.tres")
const QUADBOT_APPEARANCE_PROFILE := preload("res://resources/world_sim/population_appearance_profiles/quadbot.tres")
const QUADBOT_NAME_PROFILE := preload("res://resources/world_sim/population_name_profiles/quadbot_names.tres")
const ROBOT_OIL := preload("res://resources/bleed_fluids/robot_oil.tres")
const SELECTION_RING_VISUAL := preload("res://src/actors/projection/selection_ring_visual.gd")

const EXPECTED_QUADBOT_SKILL_BASE_LEVEL := 40
const EXPECTED_DAMAGE_RATIO := 2.0 / 3.0
const ROBOT_DEATH_ANIMATION_NAME := "RobotDeath"
const MAX_VISUAL_FOOT_SINK := 0.005
const MIN_RAGDOLL_HEIGHT_RATIO := 0.88
const MIN_RAGDOLL_PHYSICS_SIZE_RATIO := 0.70
const MAX_RAGDOLL_PHYSICS_SIZE_RATIO := 1.25
const MIN_RAGDOLL_SKELETON_SIZE_RATIO := 0.88
const MAX_RAGDOLL_SKELETON_SIZE_RATIO := 1.25
const MAX_SKELETON_ANCESTOR_SCALE_DELTA := 0.001
const OIL_DRIP_FLOOD_TEST_FRAMES := 120
const OIL_HIT_MIN_VISIBLE_SPLASH_AMOUNT := 8.0


class OilSplashProbe:
	extends Node
	var splash_count := 0
	var drip_count := 0
	var pool_count := 0
	var last_fluid: Resource
	var last_drip_fluid: Resource
	var last_pool_fluid: Resource
	var last_amount := 0.0

	func _ready() -> void:
		add_to_group("bleed_splotch_controller")

	func spawn_hit_splash(_source: Node3D, fluid: Resource, amount: float) -> void:
		splash_count += 1
		last_fluid = fluid
		last_amount = amount

	func spawn_bleed_drip(_source: Node3D, fluid: Resource, _severity: float) -> void:
		drip_count += 1
		last_drip_fluid = fluid

	func spawn_bleed_pool(_source: Node3D, fluid: Resource, _severity: float) -> void:
		pool_count += 1
		last_pool_fluid = fluid


var _failures: Array[String] = []
var _actor
var _cut_validation_attacker
var _oil_splash_probe: OilSplashProbe
var _oil_persistence_controller: Node
var _oil_persistence_floor: StaticBody3D
var _party_manager: PartyManager
var _hud_layer: CanvasLayer
var _details_controller: Node


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_validate_resources()
	await _spawn_robot_actor()
	await _validate_robot_oil_splotch_controller_persistence()
	_validate_actor_defaults()
	await _validate_robot_cut_damage_conversion()
	await _validate_robot_no_auto_recovery_and_oil_leak()
	await _validate_robot_ui_semantics()
	await _validate_robot_offline_and_bandage_rules()
	await _validate_robot_get_up_finishes()
	_validate_robot_visuals_and_animations()
	_validate_robot_combat_profile()
	_validate_party_control()
	await _validate_robot_death_visuals()
	await _cleanup()
	if _failures.is_empty():
		print("QUADBOT_CHARACTER_OK")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	print("QUADBOT_CHARACTER_FAILED count=%d" % _failures.size())
	quit(1)


func _validate_resources() -> void:
	if _race_id(QUADBOT_RACE) != "quadbot":
		_fail("QuadBot race should use race_id quadbot")
	if str(QUADBOT_BODY_ARCHETYPE.get("archetype_id")) != "quadbot":
		_fail("QuadBot body archetype should use quadbot")
	if str(QUADBOT_BODY_ARCHETYPE.get("race_id")) != "quadbot":
		_fail("QuadBot body archetype should point at quadbot race_id")
	if QUADBOT_BODY_ARCHETYPE.get("visual_scene") == null:
		_fail("QuadBot body archetype should reference QuadOrb visual scene")
	if QUADBOT_RACE.get("bleed_fluid") != ROBOT_OIL:
		_fail("QuadBot race should use robot oil bleed fluid")
	if QUADBOT_RACE.get("default_male_archetype") != QUADBOT_BODY_ARCHETYPE:
		_fail("QuadBot race male default should be QuadBot")
	if QUADBOT_RACE.get("default_female_archetype") != QUADBOT_BODY_ARCHETYPE:
		_fail("QuadBot race female default should be QuadBot")
	_validate_quadbot_appearance_profile()
	_validate_robot_name_profile()
	_validate_robot_oil_resource()


func _validate_robot_oil_resource() -> void:
	if str(ROBOT_OIL.get("fluid_id")) != "robot_oil":
		_fail("Robot oil should use robot_oil fluid_id")
	if str(ROBOT_OIL.get("display_name")) != "Oil":
		_fail("Robot oil display name should be Oil")
	if not bool(ROBOT_OIL.get("uses_custom_ui_color")):
		_fail("Robot oil should use custom UI color")
	var fresh_color: Color = ROBOT_OIL.get("fresh_color")
	var bar_color: Color = ROBOT_OIL.get("ui_bar_color")
	if fresh_color.r > 0.05 or fresh_color.g > 0.05 or fresh_color.b > 0.05:
		_fail("Robot oil fresh color should be black-ish")
	if bar_color.r > 0.05 or bar_color.g > 0.05 or bar_color.b > 0.05:
		_fail("Robot oil UI bar color should be black-ish")


func _validate_quadbot_appearance_profile() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 404
	var appearance := QUADBOT_APPEARANCE_PROFILE.call("create_appearance", rng) as Resource
	if appearance == null:
		_fail("Robot appearance profile should create appearance data")
		return
	if _race_id(appearance.get("character_race")) != "quadbot":
		_fail("QuadBot appearance should use quadbot race")
	if appearance.get("body_archetype") != QUADBOT_BODY_ARCHETYPE:
		_fail("QuadBot appearance should use QuadBot body archetype")
	if int(appearance.get("visual_body_type")) != CharacterAppearanceData.VISUAL_BODY_TYPE_NONE:
		_fail("QuadBot appearance should use no humanoid visual body")
	if appearance.get("hair_style") != null or appearance.get("beard_style") != null or appearance.get("eyebrow_style") != null:
		_fail("QuadBot appearance should not use humanoid hair/beard/eyebrows")


func _validate_robot_name_profile() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	var generated_name := str(QUADBOT_NAME_PROFILE.call("generate_name", CharacterAppearanceData.VISUAL_BODY_TYPE_NONE, rng, {}))
	if generated_name.is_empty():
		_fail("QuadBot name profile should generate a name")
	elif not bool(QUADBOT_NAME_PROFILE.call("contains_name", generated_name)):
		_fail("QuadBot name profile should contain generated name %s" % generated_name)


func _spawn_robot_actor() -> void:
	_party_manager = PARTY_MANAGER_SCRIPT.new() as PartyManager
	root.add_child(_party_manager)
	_actor = QUADBOT_CHARACTER_SCRIPT.new()
	_actor.name = "QuadBotValidationActor"
	_actor.member_name = "QO-17"
	_actor.show_nameplate = false
	_actor.faction_name = "Player"
	_add_basic_actor_children(_actor)
	root.add_child(_actor)
	await process_frame
	await process_frame


func _add_basic_actor_children(actor: WorldActor) -> void:
	var collision_shape := CollisionShape3D.new()
	collision_shape.name = "CollisionShape3D"
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.45
	capsule.height = 1.1
	collision_shape.shape = capsule
	collision_shape.position = Vector3(0.0, 0.95, 0.0)
	actor.add_child(collision_shape)

	var body_mesh := MeshInstance3D.new()
	body_mesh.name = "BodyMesh"
	var capsule_mesh := CapsuleMesh.new()
	capsule_mesh.radius = 0.45
	body_mesh.mesh = capsule_mesh
	body_mesh.position = Vector3(0.0, 0.95, 0.0)
	actor.add_child(body_mesh)

	var selection_ring := MeshInstance3D.new()
	selection_ring.name = "SelectionRing"
	selection_ring.visible = false
	SELECTION_RING_VISUAL.setup_ring(selection_ring)
	actor.add_child(selection_ring)


func _validate_actor_defaults() -> void:
	if _actor == null:
		_fail("Robot actor was not spawned")
		return
	if _actor.get_script() != QUADBOT_CHARACTER_SCRIPT:
		_fail("QuadBot actor should use QuadBotCharacter")
	if _race_id(_actor.character_race) != "quadbot":
		_fail("QuadBot actor should default to quadbot race")
	if _actor.body_archetype != QUADBOT_BODY_ARCHETYPE:
		_fail("QuadBot actor should default to QuadBot body archetype")
	if _actor.visual_body_type != CharacterAppearanceData.VISUAL_BODY_TYPE_NONE:
		_fail("QuadBot actor should not request a humanoid visual body")
	if not is_equal_approx(_actor.max_hp, 200.0) or not is_equal_approx(_actor.hp, _actor.max_hp):
		_fail("Robot actor should start with 200 Hull, got hp=%.1f max_hp=%.1f" % [_actor.hp, _actor.max_hp])
	if _actor.get_bleed_fluid() != ROBOT_OIL:
		_fail("Robot actor should use robot oil fluid")
	if _actor.get_vital_fluid_label() != "Oil":
		_fail("Robot actor vital fluid label should be Oil")
	if _actor.get_health_vital_label() != "Hull":
		_fail("Robot actor health vital label should be Hull")
	if _actor.shows_hunger_vital() or _actor.shows_fatigue_vital():
		_fail("Robot actor should hide hunger and fatigue vitals")
	var fallback_red := Color(0.83, 0.24, 0.24, 1.0)
	var oil_bar_color = _actor.get_vital_fluid_bar_color(fallback_red)
	if oil_bar_color == fallback_red or oil_bar_color.r > 0.05 or oil_bar_color.g > 0.05 or oil_bar_color.b > 0.05:
		_fail("Robot oil UI bar color should override red fallback with black oil")
	_validate_robot_skill_variance(_actor)


func _validate_robot_ui_semantics() -> void:
	_hud_layer = GAME_HUD_SCENE.instantiate() as CanvasLayer
	root.add_child(_hud_layer)
	_details_controller = HUMANOID_DETAILS_CONTROLLER_SCRIPT.new()
	root.add_child(_details_controller)
	_details_controller.call("initialize", root, _hud_layer)
	await process_frame
	_details_controller.call("inspect_humanoid", _actor)
	await process_frame
	var blood_label := _hud_label("HudLayout/BottomHud/InspectorSlot/HumanoidDetailsPanel/Margin/DetailsVBox/BloodRow/BloodLabel")
	var hp_label := _hud_label("HudLayout/BottomHud/InspectorSlot/HumanoidDetailsPanel/Margin/DetailsVBox/HpRow/HpLabel")
	var hunger_row := _hud_control("HudLayout/BottomHud/InspectorSlot/HumanoidDetailsPanel/Margin/DetailsVBox/HungerRow")
	var fatigue_row := _hud_control("HudLayout/BottomHud/InspectorSlot/HumanoidDetailsPanel/Margin/DetailsVBox/FatigueRow")
	var blood_fill := _hud_color_rect("HudLayout/BottomHud/InspectorSlot/HumanoidDetailsPanel/Margin/DetailsVBox/BloodRow/BloodBarFrame/BloodBarStack/BloodFill")
	if blood_label == null or blood_label.text != "Oil":
		_fail("Robot details panel should label fluid as Oil")
	if hp_label == null or hp_label.text != "Hull":
		_fail("Robot details panel should label health as Hull")
	if hunger_row == null or hunger_row.visible:
		_fail("Robot details panel should hide Hunger row")
	if fatigue_row == null or fatigue_row.visible:
		_fail("Robot details panel should hide Fatigue row")
	if blood_fill == null or blood_fill.color.r > 0.05 or blood_fill.color.g > 0.05 or blood_fill.color.b > 0.05:
		_fail("Robot details panel should fill Oil bar with black oil color")
	if blood_fill != null:
		_reset_actor_damage(_actor)
		_actor.set("_current_blunt_damage", _actor.max_hp * 0.35)
		_actor.set_focused(true)
		_details_controller.call("_update_panel")
		if blood_fill.color.r <= 0.05 and blood_fill.color.g <= 0.05 and blood_fill.color.b <= 0.05:
			_fail("Focused damaged robot Oil bar should blink/tint from damage state")
		_actor.set_focused(false)
		_reset_actor_damage(_actor)


func _validate_robot_offline_and_bandage_rules() -> void:
	var offline_actor = QUADBOT_CHARACTER_SCRIPT.new()
	offline_actor.name = "QuadBotOfflineValidationActor"
	offline_actor.member_name = "QO-OFF"
	offline_actor.show_nameplate = false
	_add_basic_actor_children(offline_actor)
	root.add_child(offline_actor)
	await process_frame
	await process_frame
	if offline_actor.can_receive_bandage():
		_fail("Robot should not receive bandages")
	offline_actor.blood = 0.0
	offline_actor.call("_recalculate_vitals")
	await process_frame
	if offline_actor.life_state != NpcRules.LifeState.UNCONSCIOUS:
		_fail("Robot oil depletion should enter unconscious/offline state, got %d" % offline_actor.life_state)
	if offline_actor.get_life_state_label() != "Offline":
		_fail("Robot unconscious label should be Offline")
	offline_actor.queue_free()
	await process_frame


func _validate_robot_cut_damage_conversion() -> void:
	_cut_validation_attacker = QUADBOT_CHARACTER_SCRIPT.new()
	_cut_validation_attacker.name = "QuadBotCutValidationAttacker"
	_cut_validation_attacker.member_name = "QO-CUT"
	_cut_validation_attacker.show_nameplate = false
	_add_basic_actor_children(_cut_validation_attacker)
	root.add_child(_cut_validation_attacker)
	_oil_splash_probe = OilSplashProbe.new()
	root.add_child(_oil_splash_probe)
	await process_frame
	await process_frame
	_reset_actor_damage(_actor)
	_actor.base_block_chance = 0.0
	var starting_blood = _actor.blood
	var result := "dodged"
	for _attempt in range(20):
		result = _actor.receive_attack(_cut_validation_attacker, 0.0, 24.0)
		if result == "hit" or result == "blocked":
			break
	if result != "hit" and result != "blocked":
		_fail("Robot cut conversion test expected hit or blocked, got %s" % result)
	if _actor.get_open_cut_damage() > 0.001:
		_fail("Robot should convert incoming cut damage away from open cut wounds")
	if _actor.get_blunt_damage() <= 0.0:
		_fail("Robot should convert incoming cut damage into blunt damage")
	if _actor.blood >= starting_blood:
		_fail("Robot hit should lose oil scaled from resolved damage")
	if _actor.get_bleed_rate() > 0.001:
		_fail("Robot hit oil loss should not create organic bleed rate")
	if _oil_splash_probe.splash_count <= 0 or _oil_splash_probe.last_fluid != ROBOT_OIL or _oil_splash_probe.last_amount <= 0.0:
		_fail("Robot hit should create an oil impact splash")
	if _oil_splash_probe.last_amount < OIL_HIT_MIN_VISIBLE_SPLASH_AMOUNT:
		_fail("Robot hit oil splash should be visible, got amount %.2f" % _oil_splash_probe.last_amount)
	var first_loss = starting_blood - _actor.blood
	_reset_actor_damage(_actor)
	var second_starting_blood = _actor.blood
	_actor.call("_on_resolved_damage", 24.0, 0.0)
	var second_loss = second_starting_blood - _actor.blood
	if second_loss <= first_loss:
		_fail("Robot oil hit loss should scale with damage")
	_reset_actor_damage(_actor)
	await process_frame


func _validate_robot_oil_splotch_controller_persistence() -> void:
	_oil_persistence_floor = StaticBody3D.new()
	_oil_persistence_floor.name = "OilPersistenceFloor"
	var floor_shape := CollisionShape3D.new()
	var floor_box := BoxShape3D.new()
	floor_box.size = Vector3(20.0, 0.2, 20.0)
	floor_shape.shape = floor_box
	floor_shape.position = Vector3(0.0, -0.1, 0.0)
	_oil_persistence_floor.add_child(floor_shape)
	root.add_child(_oil_persistence_floor)
	_oil_persistence_controller = BLEED_SPLOTCH_CONTROLLER_SCRIPT.new()
	root.add_child(_oil_persistence_controller)
	if _oil_persistence_controller.has_method("initialize"):
		_oil_persistence_controller.call("initialize", root)
	await process_frame
	var before_hit_count := _oil_splotch_count()
	_oil_persistence_controller.call("spawn_hit_splash", _actor, ROBOT_OIL, 24.0)
	await process_frame
	var after_hit_count := _oil_splotch_count()
	if after_hit_count <= before_hit_count:
		_fail("Robot oil hit splashes should create real persistent decals")
	_reset_actor_damage(_actor)
	_actor.set("_bleed_splotch_controller", null)
	_actor.set("_current_blunt_damage", _actor.max_hp * 0.65)
	_actor.call("_recalculate_vitals")
	var before_leak_count := _oil_splotch_count()
	for _frame in range(240):
		_actor.call("_process_recovery", 1.0 / 60.0)
		await process_frame
	var after_leak_count := _oil_splotch_count()
	if after_leak_count <= before_leak_count:
		_fail("Robot oil leaks should create real persistent drip decals")
	await _wait_frames(120)
	if _oil_splotch_count() < after_leak_count:
		_fail("Robot oil decals should persist like blood decals")
	_reset_actor_damage(_actor)
	_actor.set("_bleed_splotch_controller", null)
	if _oil_persistence_controller != null:
		_oil_persistence_controller.queue_free()
		_oil_persistence_controller = null
	var splotch_root := root.get_node_or_null("BleedSplotches")
	if splotch_root != null:
		splotch_root.queue_free()
	if _oil_persistence_floor != null:
		_oil_persistence_floor.queue_free()
		_oil_persistence_floor = null
	await process_frame


func _oil_splotch_count() -> int:
	var splotch_root := root.get_node_or_null("BleedSplotches")
	return splotch_root.get_child_count() if splotch_root != null else 0


func _validate_robot_no_auto_recovery_and_oil_leak() -> void:
	_reset_actor_damage(_actor)
	_actor.blood = _actor.max_blood * 0.75
	_actor.set("_current_blunt_damage", _actor.max_hp * 0.35)
	_actor.call("_recalculate_vitals")
	var starting_damage = _actor.get_blunt_damage()
	var starting_oil = _actor.blood
	_actor.call("_process_recovery", 1.0)
	if _actor.get_blunt_damage() < starting_damage - 0.001:
		_fail("Robot should not auto-heal hull damage")
	if _actor.blood >= starting_oil:
		_fail("Damaged robot below 75% Hull should leak oil instead of regenerating it")
	if float(_actor.call("get_robot_oil_leak_rate")) <= 0.0:
		_fail("Damaged robot below 75% Hull should report an oil leak rate")
	_validate_robot_oil_leak_splotch_cadence()
	var leaked_oil = _actor.blood
	_actor.set("_current_blunt_damage", _actor.max_hp * 0.10)
	_actor.call("_process_recovery", 1.0)
	if _actor.blood < leaked_oil - 0.001:
		_fail("Robot above 75% Hull should not passive-leak oil")
	_actor.blood = 0.0
	_actor.call("_recalculate_vitals")
	await _wait_frames(20)
	if _actor.life_state != NpcRules.LifeState.UNCONSCIOUS:
		_fail("Robot at 0 Oil should remain Offline until repaired")
	_reset_actor_damage(_actor)


func _validate_robot_oil_leak_splotch_cadence() -> void:
	if _oil_splash_probe == null:
		_fail("Robot oil leak cadence validation missing splotch probe")
		return
	var starting_drips := _oil_splash_probe.drip_count
	for _frame in range(OIL_DRIP_FLOOD_TEST_FRAMES):
		_actor.call("_process_bleed_splotches", 12.0, 1.0, 1.0 / 60.0)
	var spawned_drips := _oil_splash_probe.drip_count - starting_drips
	if spawned_drips <= 0:
		_fail("Robot oil leak should spawn persistent oil drips")
	if spawned_drips > 12:
		_fail("Robot oil leak should batch drips instead of flooding the splotch cap, got %d drips" % spawned_drips)
	if spawned_drips > 0 and _oil_splash_probe.last_drip_fluid != ROBOT_OIL:
		_fail("Robot oil leak drips should use robot oil fluid")


func _validate_robot_get_up_finishes() -> void:
	var get_up_actor = QUADBOT_CHARACTER_SCRIPT.new()
	get_up_actor.name = "RobotGetUpValidationActor"
	get_up_actor.member_name = "QO-UP"
	get_up_actor.show_nameplate = false
	_add_basic_actor_children(get_up_actor)
	root.add_child(get_up_actor)
	await process_frame
	await process_frame
	get_up_actor.call("_enter_unconscious_state")
	await process_frame
	_reset_actor_damage(get_up_actor)
	get_up_actor.call("_begin_get_up")
	if not bool(get_up_actor.get("_is_getting_up")):
		_fail("Robot get-up should enter getting-up state instead of spamming notices")
	await _wait_frames(8)
	if get_up_actor.life_state != NpcRules.LifeState.ALIVE:
		_fail("Robot get-up should finish and return to ALIVE")
	if bool(get_up_actor.get("_is_getting_up")):
		_fail("Robot get-up should clear getting-up state")
	get_up_actor.queue_free()
	await process_frame


func _validate_robot_visuals_and_animations() -> void:
	var body = _actor.get_body_projection() if _actor != null else null
	if body == null or body.get_script() != QUADBOT_BODY_PROJECTION_SCRIPT:
		_fail("QuadBot actor should use QuadBotBodyProjection")
		return
	if body.get_script() == HUMANOID_BODY_PROJECTION_SCRIPT:
		_fail("Robot actor should not use HumanoidBodyProjection")
	var visual_root = body.get_visual_root()
	if visual_root == null:
		_fail("Robot body should create a QuadOrb visual root")
	if body.get_primary_animation_player() == null:
		_fail("Robot body should expose the QuadOrb AnimationPlayer")
	_validate_selection_ring_mesh(_actor)
	var foot_y = body.get_visual_foot_anchor_y()
	var ground_y = body.get_visual_ground_y()
	if foot_y == INF or foot_y < ground_y - MAX_VISUAL_FOOT_SINK:
		_fail("Robot visual feet should not sink below ground: foot=%.3f ground=%.3f" % [foot_y, ground_y])
	for clip_name in ["Idle", "Walk", "Run", "Attack"]:
		if not body.has_clip(clip_name):
			_fail("Robot body should have QuadOrb clip %s" % clip_name)
	if body.has_clip("Death01") or body.has_clip("Death02"):
		_fail("Robot body should not expose humanoid death clips")
	if not body.play_clip(_actor.WALK_ANIMATION_NAME, 0.5, true):
		_fail("Robot body should map humanoid walk request to QuadOrb Walk")
	elif body.get_current_clip() != "Walk":
		_fail("Robot walk request should play Walk, got %s" % body.get_current_clip())
	if not body.play_clip(_actor.JOG_ANIMATION_NAME, 0.5, true):
		_fail("Robot body should map humanoid jog request to QuadOrb Run")
	elif body.get_current_clip() != "Run":
		_fail("Robot jog request should play Run, got %s" % body.get_current_clip())
	if not body.play_clip("Attack", 0.0, true):
		_fail("Robot body should play QuadOrb Attack")
	if not body.play_clip("Idle", 0.0, true):
		_fail("Robot body should play QuadOrb Idle")
	elif body.get_current_clip() != "Idle" or not body.is_current_clip_playing():
		_fail("Robot idle animation should keep playing while idle")


func _validate_robot_combat_profile() -> void:
	var profile = _actor.get_body_weapon_damage_profile()
	var blunt_base := float(profile.get("blunt_base", 0.0))
	var cut_base := float(profile.get("cut_base", 0.0))
	var total_base := blunt_base + cut_base
	if total_base <= 0.0:
		_fail("Robot body weapon should have damage")
		return
	if not is_equal_approx(blunt_base / total_base, EXPECTED_DAMAGE_RATIO):
		_fail("Robot body weapon should be 2/3 blunt and 1/3 cut")
	if total_base < 10.0:
		_fail("Robot body weapon should have high base damage")
	var damage_bases = _actor.get_combat_damage_bases()
	var blunt_damage_base := float(damage_bases.get("blunt_base", 0.0))
	var cut_damage_base := float(damage_bases.get("cut_base", 0.0))
	var damage_total := blunt_damage_base + cut_damage_base
	if damage_total <= total_base:
		_fail("Robot combat bases should scale from varied 40-ish stats")
	elif not is_equal_approx(blunt_damage_base / damage_total, EXPECTED_DAMAGE_RATIO):
		_fail("Robot scaled combat bases should preserve 2/3 blunt ratio")
	var animation_set = _actor.call("_build_unarmed_combat_animation_set")
	if animation_set == null or animation_set.get("attacks") == null or animation_set.get("attacks").is_empty():
		_fail("Robot should provide a natural attack animation set")
		return
	var first_attack = animation_set.get("attacks")[0]
	if first_attack == null or not Array(first_attack.get("animation_names")).has("Attack"):
		_fail("Robot natural attack should use QuadOrb Attack clip")


func _validate_party_control() -> void:
	if _party_manager == null or _actor == null:
		_fail("Party control validation missing actor or manager")
		return
	_party_manager.register_party_member(_actor)
	if not _actor.is_player_party_member():
		_fail("Robot should register as player party member")
	if not _party_manager.party_members.has(_actor):
		_fail("Party manager should track robot actor")
	_party_manager.select_only(_actor)
	if not _actor.is_selected:
		_fail("Party manager should select robot actor")
	_validate_selection_ring_mesh(_actor)
	_party_manager.set_followed_member(_actor)
	if not _actor.is_focused:
		_fail("Party manager should focus robot actor")


func _validate_selection_ring_mesh(actor: WorldActor) -> void:
	var selection_ring: MeshInstance3D = null
	if actor != null:
		selection_ring = actor.get_node_or_null("SelectionRing") as MeshInstance3D
	if selection_ring == null:
		_fail("Robot selection ring should exist")
		return
	if selection_ring.mesh == null:
		_fail("Robot selection ring should have a mesh")
	elif selection_ring.mesh is CylinderMesh:
		_fail("Robot selection ring should not be a flat CylinderMesh disk")


func _validate_robot_skill_variance(actor) -> void:
	var unique_levels := {}
	var total := 0
	var count := 0
	for definition in SkillRules.get_all_definitions():
		if definition == null:
			continue
		var skill_id := str(definition.get("skill_id"))
		if skill_id.is_empty():
			continue
		var level = actor.get_skill_level(skill_id)
		if level < QUADBOT_CHARACTER_SCRIPT.QUADBOT_SKILL_MIN_LEVEL or level > QUADBOT_CHARACTER_SCRIPT.QUADBOT_SKILL_MAX_LEVEL:
			_fail("QuadBot skill %s expected varied %d-ish range, got %d" % [skill_id, EXPECTED_QUADBOT_SKILL_BASE_LEVEL, level])
		unique_levels[level] = true
		total += level
		count += 1
	if unique_levels.size() < 4:
		_fail("Robot generated skills should not be flat")
	if count > 0:
		var average := float(total) / float(count)
		if average < 32.0 or average > 48.0:
			_fail("QuadBot generated skills should average near %d, got %.2f" % [EXPECTED_QUADBOT_SKILL_BASE_LEVEL, average])


func _validate_robot_death_visuals() -> void:
	var body = _actor.get_body_projection() if _actor != null else null
	if body == null:
		_fail("Robot death validation missing body projection")
		return
	var before_bounds := _get_visual_bounds(body)
	var before_model_scale := _get_robot_model_scale(body)
	var before_skeleton_bounds := _get_visual_skeleton_bounds(body)
	var before_scale_delta := _get_skeleton_ancestor_scale_delta(body)
	if before_scale_delta > MAX_SKELETON_ANCESTOR_SCALE_DELTA:
		_fail("Robot skeleton ancestors must be unit scale before ragdoll; delta=%.4f" % before_scale_delta)
	_actor.force_kill()
	await _wait_physics_frames(24)
	await process_frame
	if _actor.life_state != NpcRules.LifeState.DEAD:
		_fail("Robot force_kill should enter dead life state")
	if body.get_current_clip() == ROBOT_DEATH_ANIMATION_NAME or body.has_clip(ROBOT_DEATH_ANIMATION_NAME):
		_fail("Robot death should not use a fake death animation clip")
	if not body.is_ragdoll_active():
		_fail("Robot death should enter robot ragdoll state immediately")
	if body.has_method("is_physics_ragdoll_active") and not bool(body.call("is_physics_ragdoll_active")):
		_fail("Robot death should use physics ragdoll, not scripted tilt")
	if body.has_method("is_physical_bone_ragdoll_active") and not bool(body.call("is_physical_bone_ragdoll_active")):
		_fail("Robot death should use PhysicalBoneSimulator3D ragdoll")
	var animation_player = body.get_primary_animation_player()
	if animation_player != null and animation_player.is_playing():
		_fail("Robot death should stop QuadOrb animation playback")
	var collision_shape := _actor.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if collision_shape != null and not collision_shape.disabled:
		_fail("Robot death should disable actor collision for collapse physics")
	var after_bounds := _get_visual_bounds(body)
	var after_model_scale := _get_robot_model_scale(body)
	var after_scale_delta := _get_skeleton_ancestor_scale_delta(body)
	if after_scale_delta > MAX_SKELETON_ANCESTOR_SCALE_DELTA:
		_fail("Robot skeleton ancestors must stay unit scale during ragdoll; delta=%.4f" % after_scale_delta)
	if before_model_scale.length_squared() > 0.0001 and after_model_scale.distance_to(before_model_scale) > 0.001:
		_fail("Robot ragdoll should not change QuadOrb model scale; before=%s after=%s" % [before_model_scale, after_model_scale])
	if before_bounds.size.y > 0.001 and after_bounds.size.y < before_bounds.size.y * MIN_RAGDOLL_HEIGHT_RATIO:
		_fail("Robot ragdoll should preserve visual height; before=%.3f after=%.3f" % [before_bounds.size.y, after_bounds.size.y])
	var visual_world_bounds := _get_visual_world_bounds(body)
	var physics_bounds := _get_ragdoll_physics_bounds(body)
	var visual_extent := _max_bound_axis(visual_world_bounds)
	var physics_extent := _max_bound_axis(physics_bounds)
	if visual_extent > 0.001 and physics_extent < visual_extent * MIN_RAGDOLL_PHYSICS_SIZE_RATIO:
		_fail("Robot physics ragdoll should preserve fitted visual size; visual=%.3f physics=%.3f" % [visual_extent, physics_extent])
	if visual_extent > 0.001 and physics_extent > visual_extent * MAX_RAGDOLL_PHYSICS_SIZE_RATIO:
		_fail("Robot physics ragdoll should not overscale fitted visual size; visual=%.3f physics=%.3f" % [visual_extent, physics_extent])
	var after_skeleton_bounds := _get_visual_skeleton_bounds(body)
	_validate_ragdoll_skeleton_bounds(before_skeleton_bounds, after_skeleton_bounds, physics_bounds)


func _get_visual_bounds(body: Node) -> AABB:
	if body != null and body.has_method("get_visual_local_bounds"):
		return body.call("get_visual_local_bounds") as AABB
	return AABB()


func _get_visual_world_bounds(body: Node) -> AABB:
	if body != null and body.has_method("get_visual_world_bounds"):
		return body.call("get_visual_world_bounds") as AABB
	return AABB()


func _get_ragdoll_physics_bounds(body: Node) -> AABB:
	if body != null and body.has_method("get_ragdoll_physical_bone_world_bounds"):
		return body.call("get_ragdoll_physical_bone_world_bounds") as AABB
	return AABB()


func _get_visual_skeleton_bounds(body: Node) -> AABB:
	if body != null and body.has_method("get_visual_skeleton_world_bounds"):
		return body.call("get_visual_skeleton_world_bounds") as AABB
	return AABB()


func _get_robot_model_scale(body: Node) -> Vector3:
	var model := body.get_node_or_null("CharacterVisual/QuadOrbModel") as Node3D if body != null else null
	return model.scale if model != null else Vector3.ZERO


func _get_skeleton_ancestor_scale_delta(body: Node) -> float:
	if body != null and body.has_method("get_max_skeleton_ancestor_scale_delta"):
		return float(body.call("get_max_skeleton_ancestor_scale_delta"))
	return 0.0


func _validate_ragdoll_skeleton_bounds(before_bounds: AABB, after_bounds: AABB, _physics_bounds: AABB) -> void:
	if before_bounds.size.length_squared() <= 0.0001 or after_bounds.size.length_squared() <= 0.0001:
		_fail("Robot ragdoll validation should measure visible skeleton bounds")
		return
	_validate_axis_ratio("x", before_bounds.size.x, after_bounds.size.x)
	_validate_axis_ratio("y", before_bounds.size.y, after_bounds.size.y)
	_validate_axis_ratio("z", before_bounds.size.z, after_bounds.size.z)


func _validate_axis_ratio(axis_name: String, before_size: float, after_size: float) -> void:
	if before_size <= 0.001:
		return
	var ratio := after_size / before_size
	if ratio < MIN_RAGDOLL_SKELETON_SIZE_RATIO:
		_fail("Robot visible ragdoll skeleton should not shrink on %s axis; ratio=%.3f" % [axis_name, ratio])
	if ratio > MAX_RAGDOLL_SKELETON_SIZE_RATIO:
		_fail("Robot visible ragdoll skeleton should not stretch on %s axis; ratio=%.3f" % [axis_name, ratio])


func _max_bound_axis(bounds: AABB) -> float:
	return maxf(maxf(bounds.size.x, bounds.size.y), bounds.size.z)


func _cleanup() -> void:
	if _actor != null:
		_actor.queue_free()
		_actor = null
	if _cut_validation_attacker != null:
		_cut_validation_attacker.queue_free()
		_cut_validation_attacker = null
	if _oil_splash_probe != null:
		_oil_splash_probe.queue_free()
		_oil_splash_probe = null
	if _oil_persistence_controller != null:
		_oil_persistence_controller.queue_free()
		_oil_persistence_controller = null
	if _oil_persistence_floor != null:
		_oil_persistence_floor.queue_free()
		_oil_persistence_floor = null
	if _party_manager != null:
		_party_manager.queue_free()
		_party_manager = null
	if _details_controller != null:
		_details_controller.queue_free()
		_details_controller = null
	if _hud_layer != null:
		_hud_layer.queue_free()
		_hud_layer = null
	await process_frame
	await process_frame


func _race_id(race: Resource) -> String:
	return str(race.get("race_id")).strip_edges().to_lower() if race != null else ""


func _hud_label(path: String) -> Label:
	return _hud_layer.get_node_or_null(path) as Label if _hud_layer != null else null


func _hud_control(path: String) -> Control:
	return _hud_layer.get_node_or_null(path) as Control if _hud_layer != null else null


func _hud_color_rect(path: String) -> ColorRect:
	return _hud_layer.get_node_or_null(path) as ColorRect if _hud_layer != null else null


func _reset_actor_damage(actor: WorldActor) -> void:
	actor.set("_current_blunt_damage", 0.0)
	actor.set("_current_open_cut_damage", 0.0)
	actor.set("_current_bandaged_cut_damage", 0.0)
	actor.set("_bleed_rate", 0.0)
	actor.set("_bleed_burst_rate", 0.0)
	actor.blood = actor.max_blood
	actor.hp = actor.max_hp


func _wait_frames(count: int) -> void:
	for _index in range(count):
		await process_frame


func _wait_physics_frames(count: int) -> void:
	for _index in range(count):
		await physics_frame


func _fail(message: String) -> void:
	_failures.append(message)
