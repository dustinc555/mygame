extends "res://tests/validation/test_case.gd"

const DEMO_WORLD_SCENE_PATH := "res://scenes/worlds/demo_world/demo_world.tscn"
const RUSTDEAD_NEST_TYPE_PATH := "res://features/world_sim/resources/nests/rustdead.tres"
const ANCIENT_VENT_SCENE_PATH := "res://features/world_sim/sim/nests/rustdead/ancient_vent_01.tscn"
const AI_JOB_SCRIPT_PATH := "res://features/ai/bridge/ai_job.gd"
const AI_PATROL_STEP_SCRIPT_PATH := "res://features/ai/bridge/steps/ai_patrol_step.gd"
const AI_NEST_ASSAULT_STEP_SCRIPT_PATH := "res://features/ai/bridge/steps/ai_nest_assault_step.gd"
const AI_UTILITY_ADAPTER_PATH := "res://features/ai/bridge/ai_utility_adapter.gd"
const COMBAT_COORDINATOR_PATH := "res://features/combat/bridge/combat_coordinator.gd"
const SKIN_TEXTURE_BUILDER_PATH := "res://features/actors/projection/appearance/skin_texture_builder.gd"

const WEST_MARKER_ID := "demo_rustdead_west_vent"
const PATROL_SOURCE_ID := "nest_patrol"
const ASSAULT_SOURCE_ID := "nest_assault"
const NEST_VISUAL_NAME := "ActiveNestVisual"
const NEST_INTERACTION_BODY_NAME := "NestInteractionBody"
const NEST_SCRAP_ROOT_NAME := "NestScrapPiles"
const VISUAL_BODY_TYPE_MALE := 2
const RUSTDEAD_TIER_LIBRARY_PATH := "res://features/actors/projection/rustdead/rustdead_tier_library.gd"
const MAX_VISUAL_FOOT_SINK := 0.035
const WROUGHT_MIN_SKIN_METALLIC := 0.30
const ANCIENT_MIN_SKIN_METALLIC := 0.58
const BODY_SKIN_MATERIAL_NAMES := [
	"MI_Regular_Male", "MI_Regular_Female", "MI_Superhero_Male",
	"MI_Superhero_Female", "MI_Teen_Male", "MI_Teen_Female",
]

var _failures: Array[String] = []
var _scene: Node


func _initialize() -> void:
	root.size = Vector2i(1280, 720)
	call_deferred("_run")


func _run() -> void:
	_validate_nest_type_definition()
	_validate_ai_job_contract()
	await _validate_nest_job_lifecycle()
	var demo_world_scene := load(DEMO_WORLD_SCENE_PATH) as PackedScene
	if demo_world_scene == null:
		_fail("Demo world scene should load from %s" % DEMO_WORLD_SCENE_PATH)
		_print_failures_and_quit()
		return
	_scene = demo_world_scene.instantiate()
	demo_world_scene = null
	root.add_child(_scene)
	await _wait_frames(180)
	_validate_demo_markers()
	await _validate_plugin_runtime()
	await _validate_assault_job_start()
	await _cleanup_scene()
	if _failures.is_empty():
		print("RUSTDEAD_NESTS_OK")
		quit(0)
		return
	_print_failures_and_quit()


func _print_failures_and_quit() -> void:
	for failure in _failures:
		push_error(failure)
	print("RUSTDEAD_NESTS_FAILED count=%d" % _failures.size())
	quit(1)


func _validate_nest_type_definition() -> void:
	var rustdead_nest_type := _load_rustdead_nest_type()
	if rustdead_nest_type == null:
		_fail("Rustdead nest type should load from %s" % RUSTDEAD_NEST_TYPE_PATH)
		return
	if str(rustdead_nest_type.call("get_id")) != "rustdead":
		_fail("Rustdead nest type should use stable id rustdead")
	if float(rustdead_nest_type.get("default_initial_activation_chance")) != 0.5:
		_fail("Rustdead nest default activation chance should be 50%")
	if int(rustdead_nest_type.get("small_population_min")) != 8 or int(rustdead_nest_type.get("small_population_max")) != 12:
		_fail("Small Rustdead nest population should be 8-12")
	if int(rustdead_nest_type.get("small_patrol_squad_count")) != 2:
		_fail("Small Rustdead nest should define 2 patrol squads")
	if int(rustdead_nest_type.get("small_patrol_squad_min")) != 3 or int(rustdead_nest_type.get("small_patrol_squad_max")) != 5:
		_fail("Small Rustdead patrol squad size should be 3-5")
	if int(rustdead_nest_type.get("small_attack_squad_min")) != 3 or int(rustdead_nest_type.get("small_attack_squad_max")) != 7:
		_fail("Small Rustdead attack squad size should be 3-7")
	if float(rustdead_nest_type.get("wander_radius")) != 500.0:
		_fail("Rustdead wander radius should be 500m")
	if float(rustdead_nest_type.get("attack_radius")) != 1000.0:
		_fail("Rustdead attack radius should be 1000m")
	if float(rustdead_nest_type.get("daily_attack_chance")) != 0.05:
		_fail("Rustdead daily attack chance should be 5%")
	if int(rustdead_nest_type.get("respawn_cooldown_days")) != 7:
		_fail("Destroyed Rustdead nests should become eligible after about 7 days")
	var visual_scenes: Array = rustdead_nest_type.get("visual_scenes") if rustdead_nest_type.get("visual_scenes") is Array else []
	if visual_scenes.is_empty():
		_fail("Rustdead nest type should define authored visual scene variants")
	elif visual_scenes[0] == null or str((visual_scenes[0] as PackedScene).resource_path) != ANCIENT_VENT_SCENE_PATH:
		_fail("Rustdead nest visual should use authored scene %s" % ANCIENT_VENT_SCENE_PATH)


func _validate_ai_job_contract() -> void:
	var ai_job_script = load(AI_JOB_SCRIPT_PATH)
	var ai_patrol_step_script = load(AI_PATROL_STEP_SCRIPT_PATH)
	var ai_nest_assault_step_script = load(AI_NEST_ASSAULT_STEP_SCRIPT_PATH)
	if ai_job_script == null or ai_patrol_step_script == null or ai_nest_assault_step_script == null:
		_fail("AI job scripts should load for Rustdead nest validation")
		return
	if ai_job_script.priority_for_type(ai_job_script.JobType.PATROL) <= ai_job_script.priority_for_type(ai_job_script.JobType.AMBIENT_ACTIVITY):
		_fail("Patrol jobs should outrank ambient activity")
	if ai_job_script.priority_for_type(ai_job_script.JobType.NEST_ASSAULT) <= ai_job_script.priority_for_type(ai_job_script.JobType.PATROL):
		_fail("Nest assault jobs should outrank patrol jobs")
	if ai_job_script.priority_for_type(ai_job_script.JobType.NEST_ASSAULT) >= ai_job_script.priority_for_type(ai_job_script.JobType.SELF_DEFENSE):
		_fail("Self-defense should be able to interrupt nest assault jobs")
	var job = ai_job_script.new()
	job.job_type = ai_job_script.JobType.PATROL
	job.data = {"marker_id": "test_marker"}
	if str(job.get_debug_snapshot().get("data", {}).get("marker_id", "")) != "test_marker":
		_fail("AiJob debug snapshots should expose job data payloads")
	var patrol_step = ai_patrol_step_script.new()
	if str(patrol_step.get("step_id")) != "patrol":
		_fail("Patrol AI step should identify as patrol")
	var assault_step = ai_nest_assault_step_script.new()
	if str(assault_step.get("step_id")) != "nest_assault":
		_fail("Nest assault AI step should identify as nest_assault")


func _validate_nest_job_lifecycle() -> void:
	var failures_before := _failures.size()
	var scene := Node3D.new()
	root.add_child(scene)
	var context := BootstrapContext.new(scene)
	var previous_context := BootstrapContext.active
	BootstrapContext.active = context
	var bridge := GecsWorldController.new()
	scene.add_child(bridge)
	context.register(bridge.SERVICE_ID, bridge)
	bridge.initialize(context)
	bridge.set_process(false)
	var queries := ActorQueryController.new()
	scene.add_child(queries)
	context.register(ActorQueryController.SERVICE_ID, queries)
	queries.initialize(context)
	var plugin := NestWorldSimPlugin.new()
	scene.add_child(plugin)
	plugin.initialize(context)
	var marker := NestPlacementMarker.new()
	marker.marker_id = "lifecycle_nest"
	scene.add_child(marker)
	var actor := RustdeadHumanoidCharacter.new()
	actor.stable_id = "nest.lifecycle.leader"
	actor.faction_name = "Rustdead"
	scene.add_child(actor)
	actor.set_physics_process(false)
	bridge.register_actor(actor)
	var enemy := HumanoidCharacter.new()
	enemy.stable_id = "nest.lifecycle.enemy"
	enemy.position = Vector3(0, 0, -4)
	enemy.faction_name = "Player"
	scene.add_child(enemy)
	enemy.set_physics_process(false)
	bridge.register_actor(enemy)
	await _wait_frames(2)
	var ai = bridge.get_actor_entity(actor).get_component(CGameAiState)
	var job = plugin._make_patrol_job(actor, marker, {})
	if not plugin._request_nest_job(actor, job) or ai.active_driver == null:
		_fail("Nest patrol submission must install its driver, not merely report true")
		await _free_job_scene(scene)
		BootstrapContext.active = previous_context
		return
	_step_job_world(bridge)
	actor.assign_attack_target(enemy, false)
	_step_job_world(bridge)
	if ai.active_job != null or ai.active_driver != null:
		_fail("Real patrol completed by combat takeover must clear GECS job and driver")
	if int(ai.last_completed_job.get("status", -1)) != AiJob.JobStatus.SUCCEEDED:
		_fail("Patrol completion must retain its terminal result")
	bridge.unregister_actor(enemy)
	enemy.queue_free()
	await _wait_frames(2)
	_step_job_world(bridge)
	var next_job = plugin._make_patrol_job(actor, marker, {})
	if not plugin._request_nest_job(actor, next_job):
		_fail("Completed patrol must allow the next equal-priority patrol")
	if ai.active_driver != null:
		ai.active_driver.cancel()
	_step_job_world(bridge)
	if ai.active_job != null or ai.active_driver != null:
		_fail("Cancelled patrol must clear GECS job and driver")
	if not plugin._request_nest_job(actor, plugin._make_patrol_job(actor, marker, {})):
		_fail("Cancelled patrol must allow reacquisition")
	_step_job_world(bridge)
	if ai.active_driver == null or ai.active_driver.last_status != AiTaskStep.StepStatus.RUNNING:
		_fail("Second cancellation must exercise a RUNNING real patrol")
	else:
		ai.active_driver.cancel()
	_step_job_world(bridge)
	if ai.active_job != null or ai.active_driver != null:
		_fail("Cancelling a RUNNING patrol must also clear GECS state")
	if not plugin._request_nest_job(actor, plugin._make_patrol_job(actor, marker, {})):
		_fail("Running-patrol cancellation must allow another patrol before LOD")
	bridge.unregister_actor(actor)
	actor.queue_free()
	await _wait_frames(2)
	_step_job_world(bridge)
	if ai.active_job != null or ai.active_driver != null:
		_fail("Unregister must cancel the LOD projection's volatile patrol driver")
	var restored := RustdeadHumanoidCharacter.new()
	restored.stable_id = "nest.lifecycle.leader"
	restored.faction_name = "Rustdead"
	scene.add_child(restored)
	restored.set_physics_process(false)
	bridge.register_actor(restored)
	if not plugin._request_nest_job(restored, plugin._make_patrol_job(restored, marker, {})):
		_fail("Fresh realization of the same identity must acquire its patrol")
	var unregistered := RustdeadHumanoidCharacter.new()
	if plugin._request_nest_job(unregistered, plugin._make_patrol_job(unregistered, marker, {})):
		_fail("Nest job must refuse an actor with no registered GECS state")
	unregistered.free()
	await _free_job_scene(scene)
	BootstrapContext.active = previous_context
	if _failures.size() == failures_before:
		print("NEST_JOB_LIFECYCLE_OK completion=true cancellation=true reacquisition=true lod=true refusal=true")


func _step_job_world(bridge: GecsWorldController) -> void:
	for _tick in range(20):
		bridge.world.process(0.05)


func _free_job_scene(scene: Node) -> void:
	scene.queue_free()
	await _wait_frames(3)


func _validate_demo_markers() -> void:
	var markers := get_nodes_in_group("nest_placement_marker")
	if markers.size() < 3:
		_fail("Demo world should author at least three nest placement markers")
	var west_marker := _scene.get_node_or_null("Zones/DemoZone/NestMarkers/RustdeadWestVent")
	if west_marker == null:
		_fail("Demo zone should include the Rustdead west vent marker")
		return
	if str(west_marker.get("marker_id")) != WEST_MARKER_ID:
		_fail("Rustdead west marker should use stable marker id %s" % WEST_MARKER_ID)
	if not west_marker.call("get_allowed_nest_type_ids").has("rustdead"):
		_fail("Rustdead west marker should allow Rustdead nests")
	if float(west_marker.call("get_activation_chance", 0.5)) != 0.5:
		_fail("Rustdead west marker should use randomized default activation chance")
	if str(west_marker.get("display_name")) != "Ancient Vent":
		_fail("Rustdead nest marker should inspect as Ancient Vent")
	var loader := _scene.get_node_or_null("WorldLoader")
	var definition = loader.get("world_definition") if loader != null else null
	if definition == null or int(definition.get("minimum_initial_active_nests")) != 1:
		_fail("Demo world should guarantee at least 1 initial active nest through WorldDefinition")


func _validate_plugin_runtime() -> void:
	var nest_plugin := _get_controller("nest_world_sim_plugin")
	if nest_plugin == null:
		_fail("NestWorldSimPlugin should be registered into the world-sim ticker")
		return
	var summary: Dictionary = nest_plugin.call("get_debug_summary")
	if int(summary.get("marker_count", 0)) < 3:
		_fail("NestWorldSimPlugin should collect authored demo nest markers")
	if int(summary.get("active_count", 0)) < 1:
		_fail("NestWorldSimPlugin should activate at least one Rustdead marker")
	var states: Dictionary = summary.get("nest_states", {})
	var state := _first_active_rustdead_state(states)
	if state.is_empty():
		_fail("Demo world should have an active Rustdead nest state")
		return
	var population_target := int(state.get("population_target", 0))
	if population_target < 8 or population_target > 12:
		_fail("Active small Rustdead nest population target should be 8-12, got %d" % population_target)
	var patrol_squad_ids: Array = state.get("patrol_squad_ids", []) if state.get("patrol_squad_ids", []) is Array else []
	if patrol_squad_ids.size() != 2:
		_fail("Active small Rustdead nest should have exactly 2 patrol squads")
	var marker_id := str(state.get("marker_id", ""))
	_validate_world_sim_squads(marker_id, patrol_squad_ids, population_target)
	_validate_nest_visual_and_click_target(marker_id)
	await _validate_spawned_squad(nest_plugin, marker_id, patrol_squad_ids)
	_validate_spawned_scrap_piles(state, marker_id)
	_validate_scrap_specs_for_all_nest_sizes(nest_plugin)
	_validate_attack_target_selection(nest_plugin)
	await _validate_tier_skin_hydration(nest_plugin, marker_id)


func _validate_tier_skin_hydration(nest_plugin: Node, marker_id: String) -> void:
	# The nest chooses a tier before PopulationController hydrates an existing
	# person's independently generated appearance. Exercise that exact spawn
	# path without relying on a random nest containing a Wrought or Ancient.
	var failures_before := _failures.size()
	var population := _get_controller("population_controller") as PopulationController
	var marker := _find_nest_marker(marker_id) as NestPlacementMarker
	var nest_type := _load_rustdead_nest_type()
	if population == null or marker == null or nest_type == null:
		_fail("Tier skin hydration requires the live population and nest")
		return
	var faction: Resource = nest_type.get("faction_definition")
	var generation_context := {
		"faction_id": "Rustdead",
		"population_appearance_profile": faction.call("get_character_realizer"),
		"population_name_profile": faction.call("get_population_name_profile"),
	}
	var checked := 0
	for tier: Resource in RustdeadTierLibrary.get_tiers():
		var tier_id := str(tier.call("get_id"))
		var indices: PackedInt32Array = tier.get("skin_tone_indices")
		for body_type in [SkinTextureBuilder.VISUAL_BODY_TYPE_MALE, SkinTextureBuilder.VISUAL_BODY_TYPE_FEMALE]:
			var record := population.ensure_authored_record("skin_regression", tier_id, body_type, generation_context, {"faction_id": "Rustdead", "role_id": "nest_member"})
			var actor_id := str(record.get("actor_id", ""))
			var archetype: Resource = RustdeadHumanoidCharacter.RUSTDEAD_RACE.default_female_archetype if body_type == SkinTextureBuilder.VISUAL_BODY_TYPE_FEMALE else RustdeadHumanoidCharacter.RUSTDEAD_RACE.default_male_archetype
			var saved_appearance := {
				"character_race": RustdeadHumanoidCharacter.RUSTDEAD_RACE.resource_path,
				"body_archetype": archetype.resource_path,
				"visual_body_type": body_type,
				"skin_color_customized": true,
				"skin_color": SkinTextureBuilder.RUSTDEAD_SKIN_TONES[2],
			}
			record = population.update_actor_record(actor_id, {
				"appearance": saved_appearance,
				"equipment_slots": {},
				"inventory_entries": [],
				"skill_levels": {SkillRules.ATTRIBUTE_TOUGHNESS: 1},
			})
			var state := {"marker_id": marker_id, "nest_type_id": "rustdead", "rustdead_tiers_by_actor": {actor_id: tier_id}}
			var actor := nest_plugin.call("_spawn_nest_actor", marker, state, nest_type, "skin_regression", body_type, marker.global_position, actor_id) as RustdeadHumanoidCharacter
			if actor == null:
				_fail("Skin regression must spawn concrete Rustdead %s" % actor_id)
				continue
			actor.set_physics_process(false)
			var saved_person_appearance: Dictionary = population.get_actor_record(actor_id).appearance.duplicate(true)
			_validate_tier_skin_surfaces(actor, "spawn_hydrated")
			var appearance := actor.get_appearance_copy()
			appearance.skin_color = SkinTextureBuilder.RUSTDEAD_SKIN_TONES[indices[-1]]
			appearance.visual_toughness_level = CharacterVisualRules.HEROIC_TOUGHNESS_LEVEL
			appearance.visual_age_years = CharacterVisualRules.DEFAULT_ADULT_AGE
			actor.apply_appearance_data(appearance)
			_validate_tier_skin_surfaces(actor, "authored_heroic")
			_validate_skin_material_oracle(actor)
			var body := actor.get_body_projection() as RustdeadBodyProjection
			if body.appearance_data.skin_color != appearance.skin_color:
				_fail("Already tier-authored skin must not be recolored for %s" % actor_id)
			population.apply_record_to_actor(actor, record)
			_validate_tier_skin_surfaces(actor, "live_hydrated")
			body.rebuild_visual_for_equipment()
			_validate_tier_skin_surfaces(actor, "equipment_rebuild")
			SkinTextureBuilder.clear_runtime_caches()
			appearance = actor.get_appearance_copy()
			appearance.visual_age_years = CharacterVisualRules.TEEN_MAX_AGE
			actor.apply_appearance_data(appearance)
			_validate_tier_skin_surfaces(actor, "cold_cache_teen")
			if actor.appearance_data.skin_color != saved_appearance.skin_color or population.get_actor_record(actor_id).appearance != saved_person_appearance:
				_fail("Skin projection must not rewrite the durable person's appearance for %s" % actor_id)
			var old_instance := actor.get_instance_id()
			population.unregister_actor(actor)
			actor.queue_free()
			await process_frame
			await process_frame
			actor = nest_plugin.call("_spawn_nest_actor", marker, state, nest_type, "skin_regression", body_type, marker.global_position, actor_id) as RustdeadHumanoidCharacter
			if actor == null:
				_fail("Skin regression must re-realize %s" % actor_id)
				continue
			actor.set_physics_process(false)
			if actor.get_instance_id() == old_instance or actor.get_rustdead_tier_id() != tier_id:
				_fail("Skin re-realization must retain tier on a fresh concrete actor for %s" % actor_id)
			_validate_tier_skin_surfaces(actor, "re_realized")
			population.unregister_actor(actor)
			actor.queue_free()
			await process_frame
			await process_frame
			checked += 1
	if checked != 8:
		_fail("Tier skin hydration must exercise all four tiers on both bodies, got %d" % checked)
	if _failures.size() == failures_before:
		print("RUSTDEAD_TIER_SKIN_HYDRATION_OK actors=%d stages=6 variants=regular,heroic,teen" % checked)


func _validate_tier_skin_surfaces(actor: RustdeadHumanoidCharacter, stage: String) -> void:
	var body := actor.get_body_projection() as RustdeadBodyProjection
	var tier := actor.get_rustdead_tier_definition()
	var indices: PackedInt32Array = tier.get("skin_tone_indices")
	var surfaces: Array[Dictionary] = []
	_collect_tier_skin_surfaces(actor, actor, surfaces)
	var checked := 0
	var trace: Array[Dictionary] = []
	for surface in surfaces:
		var material := surface.material as BaseMaterial3D
		trace.append({"node": surface.node, "surface": surface.surface, "source_name": surface.source_name, "body_skin": surface.body_skin, "texture": material.albedo_texture.resource_path if material.albedo_texture != null else "", "metallic": material.metallic, "roughness": material.roughness})
		if not surface.body_skin:
			continue
		checked += 1
		var paths: Array[String] = []
		for tone_index in indices:
			paths.append(SkinTextureBuilder.get_generated_skin_texture_path("rustdead", body.get_resolved_visual_body_type(), tone_index, SkinTextureBuilder.detect_body_variant(body.get_visual_root())))
		if material.albedo_texture == null or not paths.has(material.albedo_texture.resource_path):
			_fail("%s %s body skin must use its authored %s palette, got %s" % [actor.stable_id, stage, actor.get_rustdead_tier_id(), str(trace[-1].texture)])
	if checked == 0:
		_fail("%s %s must expose actual imported body skin surfaces" % [actor.stable_id, stage])
	_validate_rustdead_actor_metallic_material(actor, actor.get_rustdead_tier_id(), "%s/%s" % [actor.stable_id, stage])
	print("RUSTDEAD_SKIN_SURFACES " + JSON.stringify({"actor_id": actor.stable_id, "stage": stage, "tier": actor.get_rustdead_tier_id(), "input_tone": SkinTextureBuilder.get_nearest_skin_tone_index(actor.appearance_data.skin_color, "rustdead"), "projected_tone": SkinTextureBuilder.get_nearest_skin_tone_index(body.appearance_data.skin_color, "rustdead"), "surfaces": trace}))


func _collect_tier_skin_surfaces(node: Node, actor: Node, result: Array[Dictionary]) -> void:
	# Identify canonical body slots from the imported mesh, independently of
	# which texture/override is currently applied (eyes and gear are not skin).
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.mesh != null:
			for surface_index in range(mesh_instance.mesh.get_surface_count()):
				var source := mesh_instance.mesh.surface_get_material(surface_index)
				var material := mesh_instance.get_active_material(surface_index) as BaseMaterial3D
				if material != null:
					result.append({
						"node": str(actor.get_path_to(node)),
						"surface": surface_index,
						"source_name": source.resource_name if source != null else "",
						"body_skin": source != null and str(source.resource_name) in BODY_SKIN_MATERIAL_NAMES,
						"material": material,
					})
	for child in node.get_children():
		_collect_tier_skin_surfaces(child, actor, result)


func _validate_skin_material_oracle(actor: RustdeadHumanoidCharacter) -> void:
	var tier_id := actor.get_rustdead_tier_id()
	if tier_id not in ["wrought", "ancient"]:
		return
	var surfaces: Array[Dictionary] = []
	_collect_tier_skin_surfaces(actor, actor, surfaces)
	for surface in surfaces:
		if not surface.body_skin:
			continue
		var material := surface.material as BaseMaterial3D
		var properties: Array[String] = ["metallic"]
		if tier_id == "ancient":
			properties.append("roughness")
		for property_name in properties:
			var saved_value: float = material.get(property_name)
			material.set(property_name, 0.0 if property_name == "metallic" else 1.0)
			var before := _failures.size()
			_validate_rustdead_actor_metallic_material(actor, tier_id, actor.stable_id)
			material.set(property_name, saved_value)
			var expected_text := "skin should be metallic" if property_name == "metallic" else "skin should be lower roughness"
			if _failures.size() == before + 1 and _failures[-1].contains(expected_text):
				var rejection: String = _failures.pop_back()
				print("RUSTDEAD_SKIN_ORACLE_REJECTED " + JSON.stringify({"actor_id": actor.stable_id, "property": property_name, "rejection": rejection}))
			else:
				_fail("Skin oracle must reject a genuine incorrect %s on %s" % [property_name, actor.stable_id])


func _validate_nest_visual_and_click_target(marker_id: String) -> void:
	var marker := _find_nest_marker(marker_id)
	if marker == null:
		_fail("Active Rustdead nest %s should have a placement marker" % marker_id)
		return
	var visual := marker.get_node_or_null(NEST_VISUAL_NAME) as Node3D
	if visual == null:
		_fail("Active Rustdead nest should spawn a visible ancient vent mesh")
	else:
		if visual.scene_file_path != ANCIENT_VENT_SCENE_PATH:
			_fail("Active Rustdead nest should instantiate authored ancient vent scene, got %s" % visual.scene_file_path)
		var mesh := visual.get_node_or_null("Mesh") as Node3D
		if mesh == null:
			_fail("Ancient vent scene should own the mesh as a child component")
		elif mesh.scale.distance_to(Vector3.ONE * 4.0) > 0.01:
			_fail("Ancient vent mesh child should be scaled 4x in the authored scene; scale=%s" % str(mesh.scale))
	if marker.get_node_or_null(NEST_INTERACTION_BODY_NAME) != null:
		_fail("NestWorldSimPlugin should not generate a sibling interaction body; collision belongs inside the authored nest scene")
	var interaction_body: StaticBody3D = null
	if visual != null:
		interaction_body = visual.get_node_or_null(NEST_INTERACTION_BODY_NAME) as StaticBody3D
	if interaction_body == null:
		_fail("Active Rustdead nest scene should include an editable physics click target")
	else:
		var collision := interaction_body.get_node_or_null("CollisionShape3D") as CollisionShape3D
		if collision == null or collision.shape == null:
			_fail("Active Rustdead nest scene should include an editable collision shape")


func _validate_world_sim_squads(marker_id: String, patrol_squad_ids: Array, population_target: int) -> void:
	var patrol_total := 0
	for squad_id_value in patrol_squad_ids:
		var record := _world_sim_squad_record(str(squad_id_value))
		if record.is_empty():
			_fail("Rustdead patrol squad %s should exist as a GECS world-sim squad" % str(squad_id_value))
			continue
		if str(record.get("owner_kind", "")) != "nest" or str(record.get("owner_id", "")) != marker_id:
			_fail("Rustdead patrol squad %s should be owned by nest %s" % [str(squad_id_value), marker_id])
		if str(record.get("objective", "")) != "patrol":
			_fail("Rustdead patrol squad %s should use patrol objective" % str(squad_id_value))
		var member_count := int(record.get("member_count", 0))
		patrol_total += member_count
		if member_count < 3 or member_count > 5:
			_fail("Patrol squad %s GECS member_count should be 3-5, got %d" % [str(squad_id_value), member_count])
	var guard_record := _world_sim_squad_record("nest:%s:guard" % marker_id)
	var guard_count := int(guard_record.get("member_count", 0)) if not guard_record.is_empty() else 0
	if patrol_total + guard_count != population_target:
		_fail("Rustdead GECS squad counts should sum to population target %d, got %d" % [population_target, patrol_total + guard_count])


func _validate_spawned_squad(nest_plugin: Node, marker_id: String, patrol_squad_ids: Array) -> void:
	if patrol_squad_ids.is_empty():
		return
	var squad_id := str(patrol_squad_ids[0])
	var record := _world_sim_squad_record(squad_id)
	if record.is_empty():
		return
	nest_plugin.call("realize_nest_squad", record)
	await _wait_frames(10)
	var actors := _find_actors_for_squad(squad_id)
	var expected_count := int(record.get("member_count", 0))
	if actors.size() != expected_count:
		_fail("Realized Rustdead squad %s should spawn %d actors, got %d" % [squad_id, expected_count, actors.size()])
	var active_patrol_jobs := 0
	var patrol_debug_sample := ""
	for actor in actors:
		var actor_id := str(actor.get("stable_id"))
		if not actor is RustdeadHumanoidCharacter:
			_fail("Nest actor %s must retain the concrete Rustdead subclass" % actor_id)
		if not actor.has_method("requires_fire_to_die") or not bool(actor.call("requires_fire_to_die")):
			_fail("Spawned nest actor %s should be Rustdead and require fire to die" % actor_id)
		_validate_rustdead_actor_tier(actor, actor_id)
		var appearance = actor.get("appearance_data")
		if appearance != null:
			if appearance.eyebrow_style != null:
				_fail("Spawned Rustdead actor %s should not keep normal eyebrows" % actor_id)
		if str(actor.get("world_squad_id")) != squad_id:
			_fail("Realized Rustdead actor %s should keep GECS squad id %s, got %s" % [actor_id, squad_id, str(actor.get("world_squad_id"))])
		var ai_state = _ai_state_of(actor)
		if patrol_debug_sample.is_empty() and ai_state != null:
			patrol_debug_sample = str(ai_state.active_source_id)
		if _has_patrol_job(actor):
			active_patrol_jobs += 1
	if active_patrol_jobs < 1:
		_fail("At least one Rustdead patrol actor should receive a patrol AI job; sample_ai=%s" % patrol_debug_sample)
	# Deterministic Fresh hair/beard availability stays in the 5v10 demo test;
	# a random population sample may legitimately be bald. Here retain the
	# exact person's appearance through serialization and LOD instead.
	var saved_nests: Dictionary = nest_plugin.serialize_state().duplicate(true)
	nest_plugin.apply_serialized_state(saved_nests)
	var before := {}
	for actor in actors:
		var actor_id := str(actor.get("stable_id"))
		var saved_marker: Dictionary = (saved_nests.get("nest_states", {}) as Dictionary).get(marker_id, {})
		if str((saved_marker.get("rustdead_tiers_by_actor", {}) as Dictionary).get(actor_id, "")) != actor.get_rustdead_tier_id():
			_fail("Serialized nests must retain the tier for durable person %s" % actor_id)
		before[actor_id] = {
			"instance_id": actor.get_instance_id(),
			"tier": actor.call("get_rustdead_tier_id"),
			"max_hp": actor.get("max_hp"),
			"skills": _skill_levels_of(actor),
			"hair": actor.appearance_data.hair_style.resource_path if actor.appearance_data.hair_style != null else "",
			"beard": actor.appearance_data.beard_style.resource_path if actor.appearance_data.beard_style != null else "",
		}
	var survivors := int(nest_plugin.call("derealize_nest_squad", squad_id))
	if survivors != expected_count:
		_fail("Derealized Rustdead squad %s should persist %d survivors, got %d" % [squad_id, expected_count, survivors])
	await _wait_frames(3)
	if not _find_actors_for_squad(squad_id).is_empty():
		_fail("Derealization must free the old Rustdead projections")
	nest_plugin.call("realize_nest_squad", record)
	await _wait_frames(10)
	var after := _find_actors_for_squad(squad_id)
	if after.size() != before.size():
		_fail("Rustdead re-realization must restore every surviving identity")
	var restored_patrol_count := 0
	for actor in after:
		var actor_id := str(actor.get("stable_id"))
		if not before.has(actor_id):
			_fail("Rustdead re-realization changed identity to %s" % actor_id)
			continue
		var saved: Dictionary = before[actor_id]
		if actor.get_instance_id() == saved.instance_id or not actor is RustdeadHumanoidCharacter:
			_fail("Rustdead re-realization must create a fresh concrete subclass for %s" % actor_id)
		if actor.call("get_rustdead_tier_id") != saved.tier or not is_equal_approx(actor.get("max_hp"), saved.max_hp):
			_fail("Rustdead re-realization must preserve tier and max HP for %s" % actor_id)
		if _skill_levels_of(actor) != saved.skills:
			_fail("Rustdead re-realization must preserve saved skills for %s" % actor_id)
		var hair := str(actor.appearance_data.hair_style.resource_path) if actor.appearance_data.hair_style != null else ""
		var beard := str(actor.appearance_data.beard_style.resource_path) if actor.appearance_data.beard_style != null else ""
		if hair != saved.hair or beard != saved.beard:
			_fail("Rustdead re-realization must retain the person's hair/beard for %s" % actor_id)
		if _has_patrol_job(actor):
			restored_patrol_count += 1
	# The squad leader patrols; followers use the existing squad movement owner.
	if restored_patrol_count < 1:
		_fail("Re-realized Rustdead squad must reacquire its leader's patrol")


func _ai_state_of(actor):
	var bridge := _get_controller("gecs_world_controller")
	if bridge == null:
		return null
	var entity = bridge.get_actor_entity(actor)
	return entity.get_component(CGameAiState) if entity != null else null


func _has_patrol_job(actor) -> bool:
	var state = _ai_state_of(actor)
	return state != null and state.active_source_id == PATROL_SOURCE_ID and state.active_driver != null


func _skill_levels_of(actor: WorldActor) -> Dictionary:
	var levels := {}
	for definition in SkillRules.get_all_definitions():
		levels[definition.skill_id] = actor.get_skill_level(definition.skill_id)
	return levels


func _validate_rustdead_actor_tier(actor: Node, actor_id: String) -> void:
	if not actor.has_method("get_rustdead_tier_definition"):
		_fail("Spawned Rustdead actor %s should expose a tier definition" % actor_id)
		return
	var tier := actor.call("get_rustdead_tier_definition") as Resource
	if tier == null:
		_fail("Spawned Rustdead actor %s should have a tier definition" % actor_id)
		return
	if actor.has_method("get_rustdead_passive_bonus") and absf(float(actor.call("get_rustdead_passive_bonus")) - float(tier.get("passive_bonus"))) > 0.001:
		_fail("Spawned Rustdead actor %s passive should match tier" % actor_id)
	# Systemic population generation gives people durable proper names. Tier
	# display labels remain covered by the deterministic 5v10 tier/resource test.
	var population := _get_controller("population_controller")
	var person: Dictionary = population.get_actor_record(actor_id) if population != null else {}
	if person.is_empty() or str(actor.member_name) != str(person.get("member_name", "")):
		_fail("Spawned Rustdead %s must retain its durable population name" % actor_id)
	var hp_range: Vector2 = tier.call("get_max_hp_range")
	var max_hp := float(actor.get("max_hp"))
	if max_hp < hp_range.x - 0.001 or max_hp > hp_range.y + 0.001:
		_fail("Spawned Rustdead actor %s max HP %.2f should be in tier range %s" % [actor_id, max_hp, str(hp_range)])
	_validate_rustdead_actor_skill_ranges(actor, tier, actor_id)
	_validate_rustdead_actor_blood(actor, actor_id)
	_validate_rustdead_actor_feet(actor, actor_id)
	_validate_rustdead_actor_metallic_material(actor, str(tier.call("get_id")) if tier.has_method("get_id") else "", actor_id)


func _validate_rustdead_actor_skill_ranges(actor: Node, tier: Resource, actor_id: String) -> void:
	var rustdead_tier_library = _load_valid_rustdead_tier_library()
	if rustdead_tier_library == null:
		return
	var tier_range: Vector2i = tier.call("get_stat_range")
	var non_tier_range: Vector2i = rustdead_tier_library.get_non_tier_skill_range()
	for definition in SkillRules.get_all_definitions():
		var actual := int(actor.call("get_skill_level", definition.skill_id))
		var expected_range := tier_range if rustdead_tier_library.is_tier_scaled_skill_id(definition.skill_id) else non_tier_range
		var range_label := "tier" if rustdead_tier_library.is_tier_scaled_skill_id(definition.skill_id) else "non-tier Rustdead"
		if actual < expected_range.x or actual > expected_range.y:
			_fail("Spawned Rustdead actor %s skill %s should be in %s range %d-%d, got %d" % [actor_id, definition.skill_id, range_label, expected_range.x, expected_range.y, actual])
			return
	if str(tier.call("get_id")) == "ancient":
		_validate_ancient_non_tier_actor_skill_is_low(actor, actor_id, SkillRules.ATTRIBUTE_CHARISMA)
		_validate_ancient_non_tier_actor_skill_is_low(actor, actor_id, SkillRules.COMBAT_SWORDS_ONE_HANDED)
		_validate_ancient_non_tier_actor_skill_is_low(actor, actor_id, SkillRules.SUBTERFUGE_SNEAKING)
		_validate_ancient_non_tier_actor_skill_is_low(actor, actor_id, SkillRules.CRAFT_BLACKSMITHING)
		_validate_ancient_non_tier_actor_skill_is_low(actor, actor_id, SkillRules.TECH_ROBOTICS)


func _validate_ancient_non_tier_actor_skill_is_low(actor: Node, actor_id: String, skill_id: String) -> void:
	var rustdead_tier_library = _load_valid_rustdead_tier_library()
	if rustdead_tier_library == null:
		return
	var non_tier_range: Vector2i = rustdead_tier_library.get_non_tier_skill_range()
	var actual := int(actor.call("get_skill_level", skill_id))
	if actual > non_tier_range.y:
		_fail("Spawned Ancient Rustdead actor %s should not scale non-physical skill %s above %d, got %d" % [actor_id, skill_id, non_tier_range.y, actual])


func _validate_rustdead_actor_blood(actor: Node, actor_id: String) -> void:
	var toughness := int(actor.call("get_skill_level", SkillRules.ATTRIBUTE_TOUGHNESS)) if actor.has_method("get_skill_level") else 0
	var base_max_blood := float(actor.call("get_base_max_blood")) if actor.has_method("get_base_max_blood") else 100.0
	var expected_max_blood := SkillRules.get_max_blood_for_toughness(base_max_blood, toughness)
	var max_blood := float(actor.get("max_blood"))
	if absf(max_blood - expected_max_blood) > 0.05:
		_fail("Spawned Rustdead actor %s max blood %.2f should scale from Toughness %d to %.2f" % [actor_id, max_blood, toughness, expected_max_blood])
	if toughness > 0 and max_blood <= 100.0:
		_fail("Spawned Rustdead actor %s max blood should exceed 100 when Toughness is above zero" % actor_id)
	if absf(float(actor.get("blood")) - max_blood) > 0.05:
		_fail("Spawned Rustdead actor %s should start with blood filled to max blood" % actor_id)


func _validate_rustdead_actor_feet(actor: Node, actor_id: String) -> void:
	if not actor.has_method("get_body_projection"):
		_fail("Spawned Rustdead actor %s should expose visual foot anchors" % actor_id)
		return
	var body = actor.call("get_body_projection")
	if body == null or not body.has_method("get_visual_foot_anchor_y") or not body.has_method("get_visual_ground_y"):
		_fail("Spawned Rustdead actor %s should expose visual foot anchors" % actor_id)
		return
	var foot_y := float(body.call("get_visual_foot_anchor_y"))
	if foot_y == INF:
		_fail("Spawned Rustdead actor %s should expose a valid visual foot anchor" % actor_id)
		return
	var ground_y := float(body.call("get_visual_ground_y"))
	if foot_y < ground_y - MAX_VISUAL_FOOT_SINK:
		_fail("Spawned Rustdead actor %s visual feet should not sink below ground: foot=%.3f ground=%.3f" % [actor_id, foot_y, ground_y])


func _validate_rustdead_actor_metallic_material(actor: Node, tier_id: String, actor_id: String) -> void:
	if tier_id != "wrought" and tier_id != "ancient":
		return
	var surfaces: Array[Dictionary] = []
	_collect_tier_skin_surfaces(actor, actor, surfaces)
	var checked := 0
	for surface in surfaces:
		if not surface.body_skin:
			continue
		checked += 1
		var material := surface.material as BaseMaterial3D
		var min_metallic := ANCIENT_MIN_SKIN_METALLIC if tier_id == "ancient" else WROUGHT_MIN_SKIN_METALLIC
		if material.albedo_texture == null or not str(material.albedo_texture.resource_path).contains("/character_skin/rustdead/"):
			_fail("Spawned Rustdead actor %s body surface %s must use generated Rustdead skin" % [actor_id, surface.node])
		if material.metallic < min_metallic:
			_fail("Spawned Rustdead actor %s %s skin should be metallic, got metallic=%.2f on %s" % [actor_id, tier_id, material.metallic, surface.node])
		if tier_id == "ancient" and material.roughness > 0.45:
			_fail("Spawned Rustdead actor %s Ancient Rustdead skin should be lower roughness chrome/iron, got %.2f" % [actor_id, material.roughness])
	if checked == 0:
		_fail("Spawned Rustdead actor %s should expose generated Rustdead body skin material for metallic validation" % actor_id)


func _validate_spawned_scrap_piles(state: Dictionary, marker_id: String) -> void:
	var marker := _find_nest_marker(marker_id)
	if marker == null:
		return
	var specs: Array = state.get("scrap_pile_specs", []) if state.get("scrap_pile_specs", []) is Array else []
	var count_range := _expected_scrap_count_range(str(state.get("size_id", "small")))
	if specs.size() < count_range.x or specs.size() > count_range.y:
		_fail("Rustdead nest should persist %d-%d scrap pile specs, got %d" % [count_range.x, count_range.y, specs.size()])
	var root_node := marker.get_node_or_null(NEST_SCRAP_ROOT_NAME)
	if root_node == null:
		_fail("Rustdead nest should spawn temporary scrap piles around the marker")
		return
	var piles: Array[ScavengingResourceNode] = []
	for child in root_node.get_children():
		var pile := child as ScavengingResourceNode
		if pile != null:
			piles.append(pile)
	if piles.size() < count_range.x or piles.size() > count_range.y:
		_fail("Rustdead nest should spawn %d-%d scrap piles, got %d" % [count_range.x, count_range.y, piles.size()])
	var small_count := 0
	var medium_or_larger_count := 0
	for pile in piles:
		if not pile.is_in_group("scavenging_resource"):
			_fail("Nest scrap pile %s should use the scavenging resource feature" % pile.name)
		if pile.pile_size == ScavengingResourceNode.PileSize.SMALL:
			small_count += 1
		if pile.pile_size >= ScavengingResourceNode.PileSize.MEDIUM:
			medium_or_larger_count += 1
		var expected_display_name := _expected_scrap_display_name(pile.pile_size)
		if expected_display_name != "" and pile.display_name != expected_display_name:
			_fail("Nest scrap pile %s should keep canonical display name %s, got %s" % [pile.name, expected_display_name, pile.display_name])
		if _is_deprecated_nest_scrap_display_name(pile.display_name):
			_fail("Nest scrap pile %s should not use deprecated robot scrap label %s" % [pile.name, pile.display_name])
		if pile.current_charges <= 0:
			_fail("Nest scrap pile %s should start with salvage charges" % pile.name)
	if small_count < 1:
		_fail("Rustdead nest scrap should trend small and include at least one small pile")
	if medium_or_larger_count < 1:
		_fail("Rustdead nest scrap should guarantee at least one medium-or-larger pile")


func _validate_scrap_specs_for_all_nest_sizes(nest_plugin: Node) -> void:
	for size_id in ["small", "medium", "large"]:
		var marker := NestPlacementMarker.new()
		marker.marker_id = "validation_%s_rustdead_vent" % size_id
		match size_id:
			"medium":
				marker.size = NestPlacementMarker.SIZE_MEDIUM
			"large":
				marker.size = NestPlacementMarker.SIZE_LARGE
			_:
				marker.size = NestPlacementMarker.SIZE_SMALL
		var rng := RandomNumberGenerator.new()
		rng.seed = 9000 + size_id.hash()
		var specs: Array = nest_plugin.call("_create_scrap_pile_specs", marker, rng)
		var count_range := _expected_scrap_count_range(size_id)
		if specs.size() < count_range.x or specs.size() > count_range.y:
			_fail("%s Rustdead nest should create %d-%d scrap piles, got %d" % [size_id.capitalize(), count_range.x, count_range.y, specs.size()])
		var large_count := 0
		for spec_value in specs:
			var spec: Dictionary = spec_value if spec_value is Dictionary else {}
			if str(spec.get("size_id", "")) == "large":
				large_count += 1
		if size_id == "medium" and large_count < 1:
			_fail("Medium Rustdead nest should guarantee at least one large scavenge pile")
		if size_id == "large" and large_count < 2:
			_fail("Large Rustdead nest should guarantee at least two large scavenge piles")
		marker.free()


func _expected_scrap_count_range(size_id: String) -> Vector2i:
	match size_id:
		"medium":
			return Vector2i(5, 8)
		"large":
			return Vector2i(7, 11)
		_:
			return Vector2i(3, 5)


func _expected_scrap_display_name(pile_size: int) -> String:
	match pile_size:
		ScavengingResourceNode.PileSize.SMALL:
			return "Twisted Scrap Heap"
		ScavengingResourceNode.PileSize.MEDIUM:
			return "Scrap Pile"
		ScavengingResourceNode.PileSize.LARGE:
			return "Half-Buried Robot Wreck"
		_:
			return ""


func _is_deprecated_nest_scrap_display_name(display_name: String) -> bool:
	return display_name in ["Small Robot Scrap", "Robot Scrap Pile", "Large Robot Wreck"]


func _validate_attack_target_selection(nest_plugin: Node) -> void:
	var marker := _scene.get_node_or_null("Zones/DemoZone/NestMarkers/RustdeadWestVent") as Node3D
	if marker == null:
		return
	var rustdead_nest_type := _load_rustdead_nest_type()
	if rustdead_nest_type == null:
		_fail("Rustdead nest type should load from %s" % RUSTDEAD_NEST_TYPE_PATH)
		return
	var target_id := str(nest_plugin.call("_find_attack_target_settlement", marker.global_position, 1000.0, str(rustdead_nest_type.call("get_faction_id"))))
	if target_id != "surf_city":
		_fail("West Rustdead nest should target closest non-Rustdead settlement surf_city, got %s" % target_id)


func _validate_assault_job_start() -> void:
	var nest_plugin := _get_controller("nest_world_sim_plugin")
	if nest_plugin == null:
		return
	var summary: Dictionary = nest_plugin.call("get_debug_summary")
	var states: Dictionary = summary.get("nest_states", {})
	var state := _first_active_rustdead_state(states)
	if state.is_empty():
		return
	var marker := _find_nest_marker(str(state.get("marker_id", "")))
	if marker == null:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = 424242
	var rustdead_nest_type := _load_rustdead_nest_type()
	if rustdead_nest_type == null:
		_fail("Rustdead nest type should load from %s" % RUSTDEAD_NEST_TYPE_PATH)
		return
	var started := bool(nest_plugin.call("_start_settlement_attack", marker, state, rustdead_nest_type, 42, rng))
	rustdead_nest_type = null
	if not started:
		_fail("Rustdead nest should be able to start an assault against the closest settlement")
		return
	await _wait_frames(10)
	var attack_squad_id := "nest:%s:attack:%03d" % [marker.call("get_marker_id"), 42]
	var attack_record := _world_sim_squad_record(attack_squad_id)
	if attack_record.is_empty():
		_fail("Rustdead assault should create GECS attack squad %s" % attack_squad_id)
		return
	var spawned_count := int(attack_record.get("member_count", 0))
	if spawned_count < 3 or spawned_count > 7:
		_fail("Rustdead assault data squad should have 3-7 attackers, got %d" % spawned_count)
	nest_plugin.call("realize_nest_squad", attack_record)
	await _wait_frames(10)
	var active_assault_jobs := 0
	for actor in _find_actors_for_squad(attack_squad_id):
		if actor == null:
			continue
		var ai = _ai_state_of(actor)
		if ai != null and ai.active_source_id == ASSAULT_SOURCE_ID and ai.active_driver != null:
			active_assault_jobs += 1
	if active_assault_jobs < 1:
		_fail("At least one spawned Rustdead attacker should receive a nest assault AI job")


func _first_active_rustdead_state(states: Dictionary) -> Dictionary:
	for state_value in states.values():
		var state: Dictionary = state_value if state_value is Dictionary else {}
		if bool(state.get("active", false)) and str(state.get("nest_type_id", "")) == "rustdead":
			return state
	return {}


func _find_nest_marker(marker_id: String) -> Node3D:
	if marker_id.is_empty():
		return null
	for node in get_nodes_in_group("nest_placement_marker"):
		if node.has_method("get_marker_id") and str(node.call("get_marker_id")) == marker_id:
			return node as Node3D
	return null


func _find_actor(actor_id: String) -> Node:
	for node in get_nodes_in_group("humanoid_character"):
		if str(node.get("stable_id")) == actor_id:
			return node
	return null


func _find_actors_for_squad(squad_id: String) -> Array[Node]:
	var result: Array[Node] = []
	for node in get_nodes_in_group("humanoid_character"):
		if str(node.get("world_squad_id")) == squad_id:
			result.append(node)
	return result


func _world_sim_squad_record(squad_id: String) -> Dictionary:
	var gecs := _get_controller("gecs_world_controller")
	if gecs == null or not gecs.has_method("get_world_sim_squads"):
		return {}
	for record in gecs.call("get_world_sim_squads"):
		if record is Dictionary and str((record as Dictionary).get("squad_id", "")) == squad_id:
			return (record as Dictionary)
	return {}


func _get_controller(group_name: String) -> Node:
	var nodes := get_nodes_in_group(group_name)
	return nodes[0] if not nodes.is_empty() else null


func _wait_frames(count: int) -> void:
	for _i in range(count):
		await process_frame


func _cleanup_scene() -> void:
	if _scene != null and is_instance_valid(_scene):
		root.remove_child(_scene)
		_scene.free()
	_scene = null
	await process_frame
	await physics_frame
	_cleanup_runtime_state()
	await process_frame


func _cleanup_runtime_state() -> void:
	var combat_coordinator = load(COMBAT_COORDINATOR_PATH)
	if combat_coordinator != null and combat_coordinator.has_method("reset_all_state"):
		combat_coordinator.reset_all_state()
	var ai_utility_adapter = load(AI_UTILITY_ADAPTER_PATH)
	if ai_utility_adapter != null and ai_utility_adapter.has_method("clear_runtime_caches"):
		ai_utility_adapter.clear_runtime_caches()
	var skin_texture_builder = load(SKIN_TEXTURE_BUILDER_PATH)
	if skin_texture_builder != null and skin_texture_builder.has_method("clear_runtime_caches"):
		skin_texture_builder.clear_runtime_caches()


func _load_rustdead_nest_type() -> Resource:
	return load(RUSTDEAD_NEST_TYPE_PATH) as Resource


func _load_valid_rustdead_tier_library():
	var rustdead_tier_library = load(RUSTDEAD_TIER_LIBRARY_PATH)
	if rustdead_tier_library == null:
		_fail("Rustdead tier library should load from %s" % RUSTDEAD_TIER_LIBRARY_PATH)
		return null
	for method_name in ["get_non_tier_skill_range", "is_tier_scaled_skill_id"]:
		if not rustdead_tier_library.has_method(method_name):
			_fail("Rustdead tier library should expose %s()" % method_name)
			return null
	return rustdead_tier_library


func _fail(message: String) -> void:
	_failures.append(message)
