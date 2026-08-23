extends SceneTree
## Real GECS lifecycle contract for O(1) farm plot/header/cell indexes.

var _ecs_placeholder: Node
var _failures: Array[String] = []


func _init() -> void:
	if not Engine.has_singleton("ECS"):
		_ecs_placeholder = Node.new()
		_ecs_placeholder.name = "ECS"
		Engine.register_singleton("ECS", _ecs_placeholder)
	call_deferred("_run")


func _run() -> void:
	var holder := Node.new()
	holder.name = "JobsGecsIndexLifecycleRoot"
	root.add_child(holder)
	var context := BootstrapContext.new(holder)
	var controller_script = load("res://features/core/gecs_world_controller.gd")
	var controller = controller_script.new()
	holder.add_child(controller)
	controller.initialize(context)
	controller.upsert_farm_plot_state(_plot_state("farm:indexed-real", "0:0", 1))
	_expect(str(controller.get_farm_plot_state("farm:indexed-real").get("plot_id", "")) == "farm:indexed-real", "indexed full plot read resolves the authoritative entity")
	_expect(str(controller.get_farm_plot_header_state("farm:indexed-real").get("owner_faction_id", "")) == "Player", "indexed plot header preserves authority")
	_expect(int((controller.get_farm_plot_cell_record("farm:indexed-real", "0:0") as Dictionary).get("cell", {}).get("request_revision", 0)) == 1, "indexed cell read resolves the exact durable cell")
	controller.remove_farm_plot_state("farm:indexed-real")
	_expect(controller.get_farm_plot_state("farm:indexed-real").is_empty(), "removed plot has no indexed full state")
	_expect(controller.get_farm_plot_header_state("farm:indexed-real").is_empty(), "removed plot has no indexed header")
	_expect(controller.get_farm_plot_cell_record("farm:indexed-real", "0:0").is_empty(), "removed plot has no stale indexed cell")
	controller.upsert_farm_plot_state(_plot_state("farm:replacement-real", "3:4", 9))
	controller._farm_plot_entity_by_id.clear()
	var recovered: Dictionary = controller.get_farm_plot_cell_record("farm:replacement-real", "3:4")
	_expect(int((recovered.get("cell", {}) as Dictionary).get("request_revision", 0)) == 9, "cold indexed lookup rebuilds from authoritative GECS state")
	_expect(controller._farm_plot_entity_by_id.has("farm:replacement-real"), "cold lookup restores the maintained O(1) id map")
	controller.remove_farm_plot_state("farm:replacement-real")
	root.remove_child(holder)
	holder.free()
	_cleanup_ecs()
	if _failures.is_empty():
		print("JOBS_GECS_INDEX_LIFECYCLE_OK")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	print("JOBS_GECS_INDEX_LIFECYCLE_FAILED count=%d" % _failures.size())
	quit(1)


func _plot_state(plot_id: String, cell_key: String, revision: int) -> Dictionary:
	return {
		"plot_id": plot_id,
		"owner_faction_id": "Player",
		"settlement_id": "indexed-town",
		"crop_policy_id": "tomato",
		"field_deleted": false,
		"state_revision": revision,
		"cells": {cell_key: {
			"state": "untilled",
			"requested_operation": "till",
			"request_revision": revision,
			"world_position": Vector3.ZERO,
		}},
		"soil_remnants": {},
	}


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _cleanup_ecs() -> void:
	var ecs_node := root.get_node_or_null("ECS")
	if Engine.has_singleton("ECS"):
		Engine.unregister_singleton("ECS")
	if ecs_node != null and is_instance_valid(ecs_node):
		ecs_node.free()
	elif _ecs_placeholder != null and is_instance_valid(_ecs_placeholder):
		_ecs_placeholder.free()
