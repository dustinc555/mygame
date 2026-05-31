extends SceneTree

const DEMO_WORLD_SCENE := preload("res://scenes/worlds/demo_world/demo_world.tscn")
const RUSTDEAD_NEST_TYPE := preload("res://resources/world_sim/nests/rustdead.tres")
const ANCIENT_VENT_SCENE_PATH := "res://scenes/world/nests/rustdead/ancient_vent_01.tscn"
const AI_JOB_SCRIPT := preload("res://scripts/ai/ai_job.gd")
const AI_PATROL_STEP_SCRIPT := preload("res://scripts/ai/steps/ai_patrol_step.gd")
const AI_NEST_ASSAULT_STEP_SCRIPT := preload("res://scripts/ai/steps/ai_nest_assault_step.gd")

const GUARANTEED_MARKER_ID := "demo_rustdead_west_vent"
const PATROL_SOURCE_ID := "nest_patrol"
const ASSAULT_SOURCE_ID := "nest_assault"
const NEST_VISUAL_NAME := "ActiveNestVisual"
const NEST_INTERACTION_BODY_NAME := "NestInteractionBody"
const NEST_SCRAP_ROOT_NAME := "NestScrapPiles"

var _failures: Array[String] = []
var _scene: Node


func _initialize() -> void:
	root.size = Vector2i(1280, 720)
	call_deferred("_run")


func _run() -> void:
	_validate_nest_type_definition()
	_validate_ai_job_contract()
	_scene = DEMO_WORLD_SCENE.instantiate()
	root.add_child(_scene)
	await _wait_frames(180)
	_validate_demo_markers()
	_validate_controller_runtime()
	await _validate_assault_job_start()
	if _failures.is_empty():
		print("RUSTDEAD_NESTS_OK")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	print("RUSTDEAD_NESTS_FAILED count=%d" % _failures.size())
	quit(1)


func _validate_nest_type_definition() -> void:
	if str(RUSTDEAD_NEST_TYPE.call("get_id")) != "rustdead":
		_fail("Rustdead nest type should use stable id rustdead")
	if float(RUSTDEAD_NEST_TYPE.get("default_initial_activation_chance")) != 0.5:
		_fail("Rustdead nest default activation chance should be 50%")
	if int(RUSTDEAD_NEST_TYPE.get("small_population_min")) != 8 or int(RUSTDEAD_NEST_TYPE.get("small_population_max")) != 12:
		_fail("Small Rustdead nest population should be 8-12")
	if int(RUSTDEAD_NEST_TYPE.get("small_patrol_squad_count")) != 2:
		_fail("Small Rustdead nest should define 2 patrol squads")
	if int(RUSTDEAD_NEST_TYPE.get("small_patrol_squad_min")) != 3 or int(RUSTDEAD_NEST_TYPE.get("small_patrol_squad_max")) != 5:
		_fail("Small Rustdead patrol squad size should be 3-5")
	if int(RUSTDEAD_NEST_TYPE.get("small_attack_squad_min")) != 3 or int(RUSTDEAD_NEST_TYPE.get("small_attack_squad_max")) != 7:
		_fail("Small Rustdead attack squad size should be 3-7")
	if float(RUSTDEAD_NEST_TYPE.get("wander_radius")) != 500.0:
		_fail("Rustdead wander radius should be 500m")
	if float(RUSTDEAD_NEST_TYPE.get("attack_radius")) != 1000.0:
		_fail("Rustdead attack radius should be 1000m")
	if float(RUSTDEAD_NEST_TYPE.get("daily_attack_chance")) != 0.05:
		_fail("Rustdead daily attack chance should be 5%")
	if int(RUSTDEAD_NEST_TYPE.get("respawn_cooldown_days")) != 7:
		_fail("Destroyed Rustdead nests should become eligible after about 7 days")
	var visual_scenes: Array = RUSTDEAD_NEST_TYPE.get("visual_scenes") if RUSTDEAD_NEST_TYPE.get("visual_scenes") is Array else []
	if visual_scenes.is_empty():
		_fail("Rustdead nest type should define authored visual scene variants")
	elif visual_scenes[0] == null or str((visual_scenes[0] as PackedScene).resource_path) != ANCIENT_VENT_SCENE_PATH:
		_fail("Rustdead nest visual should use authored scene %s" % ANCIENT_VENT_SCENE_PATH)


func _validate_ai_job_contract() -> void:
	if AI_JOB_SCRIPT.priority_for_type(AI_JOB_SCRIPT.JobType.PATROL) <= AI_JOB_SCRIPT.priority_for_type(AI_JOB_SCRIPT.JobType.AMBIENT_ACTIVITY):
		_fail("Patrol jobs should outrank ambient activity")
	if AI_JOB_SCRIPT.priority_for_type(AI_JOB_SCRIPT.JobType.NEST_ASSAULT) <= AI_JOB_SCRIPT.priority_for_type(AI_JOB_SCRIPT.JobType.PATROL):
		_fail("Nest assault jobs should outrank patrol jobs")
	if AI_JOB_SCRIPT.priority_for_type(AI_JOB_SCRIPT.JobType.NEST_ASSAULT) >= AI_JOB_SCRIPT.priority_for_type(AI_JOB_SCRIPT.JobType.SELF_DEFENSE):
		_fail("Self-defense should be able to interrupt nest assault jobs")
	var job = AI_JOB_SCRIPT.new()
	job.job_type = AI_JOB_SCRIPT.JobType.PATROL
	job.data = {"marker_id": "test_marker"}
	if str(job.get_debug_snapshot().get("data", {}).get("marker_id", "")) != "test_marker":
		_fail("AiJob debug snapshots should expose job data payloads")
	var patrol_step = AI_PATROL_STEP_SCRIPT.new()
	if str(patrol_step.get("step_id")) != "patrol":
		_fail("Patrol AI step should identify as patrol")
	var assault_step = AI_NEST_ASSAULT_STEP_SCRIPT.new()
	if str(assault_step.get("step_id")) != "nest_assault":
		_fail("Nest assault AI step should identify as nest_assault")


func _validate_demo_markers() -> void:
	var markers := get_nodes_in_group("nest_placement_marker")
	if markers.size() < 3:
		_fail("Demo world should author at least three nest placement markers")
	var guaranteed_marker := _scene.get_node_or_null("NestMarkers/RustdeadWestVent")
	if guaranteed_marker == null:
		_fail("Demo world should include the guaranteed Rustdead west vent marker")
		return
	if str(guaranteed_marker.get("marker_id")) != GUARANTEED_MARKER_ID:
		_fail("Guaranteed Rustdead marker should use stable marker id %s" % GUARANTEED_MARKER_ID)
	if not guaranteed_marker.call("get_allowed_nest_type_ids").has("rustdead"):
		_fail("Guaranteed Rustdead marker should allow Rustdead nests")
	if float(guaranteed_marker.call("get_activation_chance", 0.5)) != 1.0:
		_fail("Guaranteed Rustdead marker should override activation to 100% for demo coverage")
	if str(guaranteed_marker.get("display_name")) != "Ancient Vent":
		_fail("Rustdead nest marker should inspect as Ancient Vent")


func _validate_controller_runtime() -> void:
	var nest_controller := _get_controller("nest_controller")
	if nest_controller == null:
		_fail("NestController should be bootstrapped into the demo world")
		return
	var summary: Dictionary = nest_controller.call("get_debug_summary")
	if int(summary.get("marker_count", 0)) < 3:
		_fail("NestController should collect authored demo nest markers")
	if int(summary.get("active_count", 0)) < 1:
		_fail("NestController should activate the guaranteed Rustdead marker")
	var states: Dictionary = summary.get("nest_states", {})
	var state: Dictionary = states.get(GUARANTEED_MARKER_ID, {})
	if state.is_empty():
		_fail("Guaranteed Rustdead marker should have persistent nest state")
		return
	if not bool(state.get("active", false)):
		_fail("Guaranteed Rustdead marker should be active")
	if str(state.get("nest_type_id", "")) != "rustdead":
		_fail("Guaranteed active nest should be Rustdead")
	var population_target := int(state.get("population_target", 0))
	if population_target < 8 or population_target > 12:
		_fail("Active small Rustdead nest population target should be 8-12, got %d" % population_target)
	var patrol_squad_ids: Array = state.get("patrol_squad_ids", []) if state.get("patrol_squad_ids", []) is Array else []
	if patrol_squad_ids.size() != 2:
		_fail("Active small Rustdead nest should have exactly 2 patrol squads")
	_validate_nest_visual_and_click_target()
	_validate_spawned_actors(state, patrol_squad_ids, population_target)
	_validate_spawned_scrap_piles(state)
	_validate_attack_target_selection(nest_controller)


func _validate_nest_visual_and_click_target() -> void:
	var marker := _scene.get_node_or_null("NestMarkers/RustdeadWestVent")
	if marker == null:
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
		_fail("NestController should not generate a sibling interaction body; collision belongs inside the authored nest scene")
	var interaction_body: StaticBody3D = null
	if visual != null:
		interaction_body = visual.get_node_or_null(NEST_INTERACTION_BODY_NAME) as StaticBody3D
	if interaction_body == null:
		_fail("Active Rustdead nest scene should include an editable physics click target")
	else:
		var collision := interaction_body.get_node_or_null("CollisionShape3D") as CollisionShape3D
		if collision == null or collision.shape == null:
			_fail("Active Rustdead nest scene should include an editable collision shape")


func _validate_spawned_actors(state: Dictionary, patrol_squad_ids: Array, population_target: int) -> void:
	var actor_ids: Array = state.get("actor_ids", []) if state.get("actor_ids", []) is Array else []
	if actor_ids.size() != population_target:
		_fail("Runtime Rustdead actor count should match population target %d, got %d" % [population_target, actor_ids.size()])
	var patrol_counts := {}
	var active_patrol_jobs := 0
	var patrol_debug_sample := ""
	for actor_id_value in actor_ids:
		var actor := _find_actor(str(actor_id_value))
		if actor == null:
			_fail("Missing spawned Rustdead actor %s" % str(actor_id_value))
			continue
		if not actor.has_method("requires_fire_to_die") or not bool(actor.call("requires_fire_to_die")):
			_fail("Spawned nest actor %s should be Rustdead and require fire to die" % str(actor_id_value))
		var squad_id := str(actor.get("world_squad_id"))
		if patrol_squad_ids.has(squad_id):
			patrol_counts[squad_id] = int(patrol_counts.get(squad_id, 0)) + 1
			if patrol_debug_sample.is_empty() and actor.has_method("get_ai_debug_snapshot"):
				patrol_debug_sample = str(actor.call("get_ai_debug_snapshot"))
			if actor.has_method("has_active_ai_job_from_source") and bool(actor.call("has_active_ai_job_from_source", PATROL_SOURCE_ID)):
				active_patrol_jobs += 1
	for squad_id_value in patrol_squad_ids:
		var count := int(patrol_counts.get(str(squad_id_value), 0))
		if count < 3 or count > 5:
			_fail("Patrol squad %s should have 3-5 actors, got %d" % [str(squad_id_value), count])
	if active_patrol_jobs < 1:
		_fail("At least one Rustdead patrol actor should receive a patrol AI job; sample_ai=%s" % patrol_debug_sample)


func _validate_spawned_scrap_piles(state: Dictionary) -> void:
	var marker := _scene.get_node_or_null("NestMarkers/RustdeadWestVent")
	if marker == null:
		return
	var specs: Array = state.get("scrap_pile_specs", []) if state.get("scrap_pile_specs", []) is Array else []
	if specs.size() < 3 or specs.size() > 5:
		_fail("Rustdead nest should persist 3-5 scrap pile specs, got %d" % specs.size())
	var root_node := marker.get_node_or_null(NEST_SCRAP_ROOT_NAME)
	if root_node == null:
		_fail("Rustdead nest should spawn temporary scrap piles around the marker")
		return
	var piles: Array[ScavengingResourceNode] = []
	for child in root_node.get_children():
		var pile := child as ScavengingResourceNode
		if pile != null:
			piles.append(pile)
	if piles.size() < 3 or piles.size() > 5:
		_fail("Rustdead nest should spawn 3-5 scrap piles, got %d" % piles.size())
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


func _validate_attack_target_selection(nest_controller: Node) -> void:
	var marker := _scene.get_node_or_null("NestMarkers/RustdeadWestVent") as Node3D
	if marker == null:
		return
	var target_id := str(nest_controller.call("_find_attack_target_settlement", marker.global_position, 1000.0, str(RUSTDEAD_NEST_TYPE.call("get_faction_id"))))
	if target_id != "surf_city":
		_fail("West Rustdead nest should target closest non-Rustdead settlement surf_city, got %s" % target_id)


func _validate_assault_job_start() -> void:
	var nest_controller := _get_controller("nest_controller")
	var marker := _scene.get_node_or_null("NestMarkers/RustdeadWestVent") as Node3D
	if nest_controller == null or marker == null:
		return
	var summary: Dictionary = nest_controller.call("get_debug_summary")
	var states: Dictionary = summary.get("nest_states", {})
	var state: Dictionary = states.get(GUARANTEED_MARKER_ID, {})
	if state.is_empty():
		return
	var before_actor_ids: Array = state.get("actor_ids", []) if state.get("actor_ids", []) is Array else []
	var before_actor_count := before_actor_ids.size()
	var rng := RandomNumberGenerator.new()
	rng.seed = 424242
	if not bool(nest_controller.call("_start_settlement_attack", marker, state, RUSTDEAD_NEST_TYPE, 42, rng)):
		_fail("Rustdead nest should be able to start an assault against the closest settlement")
		return
	await _wait_frames(10)
	var actor_ids: Array = state.get("actor_ids", []) if state.get("actor_ids", []) is Array else []
	var spawned_count := actor_ids.size() - before_actor_count
	if spawned_count < 3 or spawned_count > 7:
		_fail("Rustdead assault should spawn 3-7 attackers, got %d" % spawned_count)
	var active_assault_jobs := 0
	for index in range(before_actor_count, actor_ids.size()):
		var actor := _find_actor(str(actor_ids[index]))
		if actor == null:
			_fail("Missing assault Rustdead actor %s" % str(actor_ids[index]))
			continue
		if actor.has_method("has_active_ai_job_from_source") and bool(actor.call("has_active_ai_job_from_source", ASSAULT_SOURCE_ID)):
			active_assault_jobs += 1
	if active_assault_jobs < 1:
		_fail("At least one spawned Rustdead attacker should receive a nest assault AI job")


func _find_actor(actor_id: String) -> Node:
	for node in get_nodes_in_group("humanoid_character"):
		if str(node.get("stable_id")) == actor_id:
			return node
	return null


func _get_controller(group_name: String) -> Node:
	var nodes := get_nodes_in_group(group_name)
	return nodes[0] if not nodes.is_empty() else null


func _wait_frames(count: int) -> void:
	for _i in range(count):
		await process_frame


func _fail(message: String) -> void:
	_failures.append(message)
