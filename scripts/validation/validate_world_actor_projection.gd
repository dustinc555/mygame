extends SceneTree

class EcsPlaceholder:
	extends Node
	var debug := false

class ProjectionFakeBridge:
	extends Node
	var records: Dictionary = {}
	var slots: Array[Dictionary] = []

	func get_population_records() -> Dictionary:
		return records

	func get_equipment_slots(actor_id := "") -> Array[Dictionary]:
		if actor_id.is_empty():
			return slots
		var filtered: Array[Dictionary] = []
		for slot in slots:
			if str(slot.get("actor_id", "")) == actor_id:
				filtered.append(slot)
		return filtered

const DEMO_WORLD_SCENE_PATH := "res://scenes/worlds/demo_world/demo_world.tscn"
const CONTROLLER_SCRIPT := preload("res://scripts/controllers/world_actor_projection_controller.gd")
const MIRA_RECORD_PATH := "res://resources/worlds/demo_world/population/mira.tres"
const TOMAS_RECORD_PATH := "res://resources/worlds/demo_world/population/tomas.tres"
const MIRA_EXPECTED_ITEMS := [
	"res://resources/items/ranger_jerkin.tres",
	"res://resources/items/steel_sword.tres",
]
const TOMAS_EXPECTED_ITEMS := [
	"res://resources/items/iron_axe.tres",
	"res://resources/items/peasant_tunic.tres",
]

var _failures: Array[String] = []
var _ecs_placeholder: Node
var _registered_ecs_placeholder := false


func _initialize() -> void:
	call_deferred("_run_validation")


func _run_validation() -> void:
	await process_frame
	_run_direct_projection_validation()
	_ensure_ecs_placeholder()
	var scene_resource := load(DEMO_WORLD_SCENE_PATH) as PackedScene
	if scene_resource == null:
		_failures.append("Demo world scene loads for projection validation")
		_finish()
		return
	var scene := scene_resource.instantiate()
	root.add_child(scene)
	call_deferred("_run_demo_projection_validation", scene)


func _run_direct_projection_validation() -> void:
	var scene_root := Node3D.new()
	scene_root.name = "ProjectionValidationRoot"
	root.add_child(scene_root)
	var projection_root := Node3D.new()
	projection_root.name = "WorldActorProjections"
	scene_root.add_child(projection_root)

	var bridge := ProjectionFakeBridge.new()
	bridge.name = "GecsWorldController"
	scene_root.add_child(bridge)

	var controller := Node.new()
	controller.name = "WorldActorProjectionController"
	controller.set_script(CONTROLLER_SCRIPT)
	scene_root.add_child(controller)
	controller.initialize(scene_root)

	var mira_record := _load_record(MIRA_RECORD_PATH)
	mira_record["actor_id"] = "validation.humanoid"
	mira_record["stable_id"] = "validation.humanoid"
	mira_record["member_name"] = "Projection Human"
	mira_record["last_world_position"] = Vector3(10.0, 0.5, -2.0)
	var animal_record := {
		"actor_id": "validation.animal",
		"stable_id": "validation.animal",
		"member_name": "Projection Animal",
		"projection_kind": "animal_placeholder",
		"life_state": 0,
		"base_color": Color(0.2, 0.6, 0.95, 1.0),
		"last_world_position": Vector3(11.0, 0.5, -2.0),
	}
	var unsupported_record := {
		"actor_id": "validation.unsupported",
		"stable_id": "validation.unsupported",
		"member_name": "Unsupported",
		"projection_kind": "minotaur_placeholder",
		"life_state": 0,
		"last_world_position": Vector3(12.0, 0.5, -2.0),
	}
	bridge.records = {
		"validation.humanoid": mira_record,
		"validation.animal": animal_record,
		"validation.unsupported": unsupported_record,
	}
	bridge.slots = [
		{"actor_id": "validation.humanoid", "slot_name": "weapon", "item_definition_path": "res://resources/items/steel_sword.tres", "stack_id": ""},
		{"actor_id": "validation.humanoid", "slot_name": "chest", "item_definition_path": "res://resources/items/ranger_jerkin.tres", "stack_id": ""},
	]

	controller.sync_projections()
	_expect(controller.get_projection_count() == 2, "Direct controller projects supported humanoid and placeholder records only")
	_expect(controller.can_project_kind("humanoid"), "Controller accepts humanoid projection kind")
	_expect(controller.can_project_kind("animal_placeholder"), "Controller accepts animal placeholder projection kind")
	_expect(not controller.can_project_kind("minotaur_placeholder"), "Controller rejects unsupported projection kind")
	var unsupported: Dictionary = controller.get_unsupported_projection_kinds()
	_expect(int(unsupported.get("minotaur_placeholder", 0)) == 1, "Controller records unsupported projection kind")

	var humanoid: Node = controller.get_projection_for_actor("validation.humanoid")
	_validate_humanoid_projection(humanoid, mira_record, ["res://resources/items/ranger_jerkin.tres", "res://resources/items/steel_sword.tres"], "Direct humanoid")
	var animal: Node = controller.get_projection_for_actor("validation.animal")
	_validate_placeholder_projection(animal, "Direct animal placeholder")
	_expect(controller.get_projection_for_actor("validation.unsupported") == null, "Unsupported record has no projection node")

	scene_root.queue_free()


func _run_demo_projection_validation(scene: Node) -> void:
	for _index in range(16):
		await process_frame
	_promote_root_ecs_singleton()
	var bootstrap := scene.get_node_or_null("GameBootstrap")
	_expect(bootstrap != null, "GameBootstrap exists for projection validation")
	if bootstrap == null:
		_finish()
		return
	var gecs := bootstrap.get_node_or_null("GecsWorldController")
	var controller := bootstrap.get_node_or_null("WorldActorProjectionController")
	_expect(gecs != null, "GecsWorldController exists for projection validation")
	_expect(controller != null, "WorldActorProjectionController is bootstrapped")
	if gecs == null or controller == null:
		_finish()
		return
	controller.sync_projections()
	await process_frame

	var mira_record: Dictionary = gecs.call("get_population_record", "player.mira") if gecs.has_method("get_population_record") else {}
	var tomas_record: Dictionary = gecs.call("get_population_record", "player.tomas") if gecs.has_method("get_population_record") else {}
	_expect(str(mira_record.get("projection_kind", "")) == "humanoid", "Mira GECS record requests humanoid projection")
	_expect(str(tomas_record.get("projection_kind", "")) == "humanoid", "Tomas GECS record requests humanoid projection")
	_validate_humanoid_projection(controller.get_projection_for_actor("player.mira"), mira_record, MIRA_EXPECTED_ITEMS, "Mira integrated")
	_validate_humanoid_projection(controller.get_projection_for_actor("player.tomas"), tomas_record, TOMAS_EXPECTED_ITEMS, "Tomas integrated")
	_expect(scene.get_node_or_null("WorldActorProjections") != null, "Projection root is owned by world scene")
	_expect(get_nodes_in_group("projected_humanoid_actor").size() >= 2, "Humanoid projections register visible actor group")
	_finish()


func _validate_humanoid_projection(projection: Node, record: Dictionary, expected_item_paths: Array, label: String) -> void:
	_expect(projection != null, "%s projection exists" % label)
	if projection == null:
		return
	_expect(str(projection.get("projection_kind")) == "humanoid", "%s projection kind is humanoid" % label)
	_expect(projection.is_in_group("projected_world_actor"), "%s projection is in generic actor group" % label)
	_expect(projection.is_in_group("projected_humanoid_actor"), "%s projection is in humanoid actor group" % label)
	_validate_selection_ring(projection, label)
	var expected_position = record.get("last_world_position", Vector3.ZERO)
	if expected_position is Vector3:
		_expect((projection as Node3D).global_position.is_equal_approx(expected_position), "%s projection uses GECS world position" % label)
	var debug_state: Dictionary = projection.get_projection_debug_state() if projection.has_method("get_projection_debug_state") else {}
	var body_state: Dictionary = debug_state.get("body_state", {}) if debug_state.get("body_state", {}) is Dictionary else {}
	_expect(str(body_state.get("body_adapter_id", "")) == "humanoid", "%s uses humanoid body adapter" % label)
	var appearance: Dictionary = record.get("appearance", {}) if record.get("appearance", {}) is Dictionary else {}
	_expect(str(body_state.get("body_archetype", "")) == str(appearance.get("body_archetype", "")), "%s resolves authored body archetype" % label)
	_expect(bool(body_state.get("world_skeleton_ready", false)), "%s world body visual exposes a skeleton" % label)
	_expect(bool(body_state.get("portrait_skeleton_ready", false)), "%s portrait source exposes a skeleton" % label)
	_expect(bool(body_state.get("world_idle_animation_ready", false)), "%s world body has idle animation" % label)
	var attached: Array = body_state.get("attached_item_paths", []) if body_state.get("attached_item_paths", []) is Array else []
	for item_path in expected_item_paths:
		_expect(attached.has(str(item_path)), "%s attaches equipped visual: %s" % [label, str(item_path)])


func _validate_placeholder_projection(projection: Node, label: String) -> void:
	_expect(projection != null, "%s projection exists" % label)
	if projection == null:
		return
	_expect(str(projection.get("projection_kind")) == "animal_placeholder", "%s projection kind is animal placeholder" % label)
	_expect(projection.is_in_group("projected_world_actor"), "%s projection is in generic actor group" % label)
	_expect(not projection.is_in_group("projected_humanoid_actor"), "%s does not register humanoid group" % label)
	var debug_state: Dictionary = projection.get_projection_debug_state() if projection.has_method("get_projection_debug_state") else {}
	var body_state: Dictionary = debug_state.get("body_state", {}) if debug_state.get("body_state", {}) is Dictionary else {}
	_expect(str(body_state.get("body_adapter_id", "")) == "placeholder", "%s uses placeholder body adapter" % label)
	_expect(bool(body_state.get("placeholder_visual_ready", false)), "%s creates placeholder visual" % label)


func _validate_selection_ring(projection: Node, label: String) -> void:
	var ring := projection.get_node_or_null("SelectionRing") as MeshInstance3D
	_expect(ring != null, "%s has main-style SelectionRing node" % label)
	if ring == null:
		return
	_expect(ring.mesh is ArrayMesh, "%s selection marker uses generated ring mesh, not filled disk" % label)
	_expect(projection.get_node_or_null("SelectionMarker") == null, "%s does not use old filled SelectionMarker disk" % label)
	var material := ring.material_override as StandardMaterial3D
	_expect(material != null, "%s selection ring has material override" % label)
	if material == null:
		return
	_expect(_colors_close(material.albedo_color, Color(0.28, 0.78, 1.0, 1.0)), "%s selection ring uses main selected blue" % label)
	_expect(material.emission_enabled, "%s selection ring is emissive like main" % label)


func _colors_close(left: Color, right: Color) -> bool:
	return absf(left.r - right.r) < 0.001 and absf(left.g - right.g) < 0.001 and absf(left.b - right.b) < 0.001 and absf(left.a - right.a) < 0.001


func _load_record(path: String) -> Dictionary:
	var definition := load(path)
	if definition == null or not definition.has_method("to_record"):
		_failures.append("Population record definition loads: %s" % path)
		return {}
	return definition.call("to_record")


func _finish() -> void:
	if _failures.is_empty():
		print("WORLD_ACTOR_PROJECTION_VALIDATION_OK")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	quit(1)


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
