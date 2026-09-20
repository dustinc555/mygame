extends SceneTree

const THRONE_PATH := "res://features/world/projection/props/furniture/throne/simple_town_throne.tscn"
const MODEL_PATH := "res://assets/world/props/furniture/simple_town_throne.glb"
const FACILITY_TOOLS_PATH := "res://addons/world_authoring/facility_tools.gd"

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var scene := load(THRONE_PATH) as PackedScene
	_expect(scene != null, "Simple town throne scene must load")
	_expect(ResourceLoader.exists(MODEL_PATH), "Simple town throne model must be imported")
	if scene != null:
		var throne := scene.instantiate()
		root.add_child(throne)
		_expect(throne.has_method("claim_sitter"), "Throne must be an individual sittable furniture item")
		_expect(throne.has_method("supports_facility_role") and bool(throne.call("supports_facility_role", "ruler")), "Throne must advertise the ruler role")
		_expect(throne.get("seated_floor_local_offset") == Vector3(0.0, 0.08, 0.24), "Throne seat pose must keep the sitter clear of the back panel")
		_expect(throne.get_child_count() == 2, "Throne scene must contain only its model and collision, not a furniture cluster")
		var collision := throne.get_node_or_null("BodyCollision") as CollisionShape3D
		var model := throne.get_node_or_null("Model") as Node3D
		_expect(collision != null and collision.shape is BoxShape3D, "Throne must have authored box collision")
		_expect(model != null and model.scale.is_equal_approx(Vector3.ONE * 3.6), "Throne visual must retain its enlarged authored scale")
		if collision != null and collision.shape is BoxShape3D:
			var size := (collision.shape as BoxShape3D).size
			_expect(size.is_equal_approx(Vector3(0.8, 1.8, 0.79)), "Throne collision must match the scaled model")
		throne.free()
	var tools = load(FACILITY_TOOLS_PATH).new(null)
	var catalog: Array = tools.get_furniture_catalog()
	_expect(catalog.any(func(entry): return str(entry.get("path", "")) == THRONE_PATH), "Actual furniture catalog must expose the throne scene")
	tools.teardown()
	_finish()


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
		push_error(message)


func _finish() -> void:
	if _failures.is_empty():
		print("SIMPLE_TOWN_THRONE_OK")
	else:
		print("SIMPLE_TOWN_THRONE_FAILED count=%d" % _failures.size())
	quit(0 if _failures.is_empty() else 1)
