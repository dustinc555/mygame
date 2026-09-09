extends SceneTree
## Run: godot --headless --path . --script res://tools/validation/validate_farming_gecs_bridge.gd

var _ecs_placeholder: Node


func _init() -> void:
	if not Engine.has_singleton("ECS"):
		_ecs_placeholder = Node.new()
		Engine.register_singleton("ECS", _ecs_placeholder)
	call_deferred("_run")


func _run() -> void:
	var root := Node.new()
	root.name = "FarmingGecsValidationRoot"
	get_root().add_child(root)
	var context := BootstrapContext.new(root)
	var controller_script = load("res://features/core/gecs_world_controller.gd")
	var controller = controller_script.new()
	root.add_child(controller)
	controller.initialize(context)
	var created: Dictionary = controller.upsert_farm_plot_state({
		"plot_id": "farm:integration",
		"owner_faction_id": "player",
		"cells": {"0:0": {"status": "untilled"}},
	})
	_expect(created.get("plot_id") == "farm:integration", "upsert returns the durable plot")
	var states: Dictionary = controller.get_farm_plot_states()
	_expect(states.has("farm:integration"), "query returns the plot by id")
	controller.remove_farm_plot_state("farm:integration")
	_expect(not controller.get_farm_plot_states().has("farm:integration"), "remove deletes the GECS entity")
	var water: Dictionary = controller.upsert_farm_water_source_state({
		"source_id": "well:integration", "owner_faction_name": "Player", "capacity": 25.0, "current_water": 9.0, "renewable": false,
	})
	_expect(is_equal_approx(float(water.get("current_water", 0.0)), 9.0), "water source upsert preserves finite capacity")
	_expect(str(water.get("owner_faction_name", "")) == "Player", "water source upsert preserves durable ownership")
	_expect(controller.get_farm_water_source_states().has("well:integration"), "water source query returns durable source")
	controller.upsert_farm_water_source_state({
		"source_id": "well:totals", "settlement_id": "town", "source_kind": "well",
		"owner_faction_name": "Player", "capacity": 25.0, "current_water": 9.0,
		"recharge_per_world_minute": 2.0,
	})
	var water_totals: Dictionary = controller.get_farm_water_totals_for_settlement("town")
	_expect(is_equal_approx(float(water_totals.get("well_output_per_day", 0.0)), 2880.0), "water ledger aggregate updates on source upsert")
	controller.remove_farm_water_source_state("well:totals")
	water_totals = controller.get_farm_water_totals_for_settlement("town")
	_expect(is_equal_approx(float(water_totals.get("well_output_per_day", -1.0)), 0.0), "water ledger aggregate updates on source removal")
	controller.upsert_farm_plot_state({
		"plot_id": "farm:totals", "settlement_id": "town", "owner_faction_id": "Player",
		"cells": {
			"0:0": {"state": "growing", "crop_id": "wheat"},
			"1:0": {"state": "growing", "crop_id": "barley"},
		},
	})
	var crop_counts: Dictionary = controller.get_growing_farm_crop_counts_for_settlement("town")
	_expect(int(crop_counts.get("wheat", 0)) == 1 and int(crop_counts.get("barley", 0)) == 1, "crop ledger aggregate updates on plot upsert")
	controller.upsert_farm_plot_cells("farm:totals", {"0:0": {"state": "harvestable", "crop_id": "wheat"}})
	crop_counts = controller.get_growing_farm_crop_counts_for_settlement("town")
	_expect(int(crop_counts.get("wheat", 0)) == 0 and int(crop_counts.get("barley", 0)) == 1, "crop ledger aggregate updates from changed cells")
	controller.remove_farm_plot_state("farm:totals")
	_expect(controller.get_growing_farm_crop_counts_for_settlement("town").is_empty(), "crop ledger aggregate updates on plot removal")
	print("FARMING_GECS_BRIDGE_OK")
	root.free()
	if _ecs_placeholder != null:
		Engine.unregister_singleton("ECS")
		_ecs_placeholder.free()
	quit(0)


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	push_error(message)
	quit(1)
