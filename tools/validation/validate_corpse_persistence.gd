extends SceneTree

var _failed := false


func _initialize() -> void:
	var population := FileAccess.get_file_as_string("res://features/world_sim/sim/population/population_controller.gd")
	var gecs := FileAccess.get_file_as_string("res://features/core/gecs_world_controller.gd")
	var settlement := FileAccess.get_file_as_string("res://features/settlements/bridge/settlement_controller.gd")
	var realization := FileAccess.get_file_as_string("res://features/world_sim/bridge/population_realization_controller.gd")
	var furnace := FileAccess.get_file_as_string("res://features/world/bridge/props/body_furnace.gd")
	var component := FileAccess.get_file_as_string("res://features/world_sim/sim/population/c_game_population_record.gd")
	var faction_squads := FileAccess.get_file_as_string("res://features/world_sim/sim/faction_world_sim_controller.gd")
	var nests := FileAccess.get_file_as_string("res://features/world_sim/sim/nests/nest_world_sim_plugin.gd")
	var encounters := FileAccess.get_file_as_string("res://features/world_sim/sim/encounter_controller.gd")
	var law_order := FileAccess.get_file_as_string("res://features/settlements/sim/law/law_order_controller.gd")
	var interaction := FileAccess.get_file_as_string("res://features/world/bridge/world_interaction_controller.gd")
	_expect(population.contains("signal person_died") and population.contains("update_population_death"), "death is not persisted immediately")
	_expect(gecs.contains("live_vitals.life_state = NpcRules.LifeState.DEAD"), "realized actor GECS vitals are not made terminal before projection")
	_expect(interaction.contains("population_controller.mark_record_dead(actor_id, target)") and not interaction.contains("target.life_state = NpcRules.LifeState.DEAD"), "instant Kill bypasses GECS death truth")
	_expect(not population.contains("func remove_actor_record") and not gecs.contains("func remove_population_record"), "gameplay still exposes permanent-person deletion")
	_expect(gecs.contains("func _clear_population_records_for_load"), "save loading lacks an explicit snapshot-rebuild clear path")
	_expect(population.contains("actor_script_path"), "person records cannot reconstruct authored bodies")
	_expect(settlement.contains("int(child.get(\"life_state\")) == NpcRules.LifeState.DEAD"), "hourly staff cleanup can delete corpses")
	_expect(realization.contains("get_corpse_population_records_near") and realization.contains("realize_record_actor"), "corpse LOD does not reproject durable people")
	_expect(population.contains("dead_projection_registered.emit(actor_id)") and realization.contains("func _on_dead_projection_registered"), "live deaths do not register their corpse projection synchronously")
	_expect(not realization.contains("actor.reparent(root)"), "live ragdolls are reparented and can jump away from their death position")
	_expect(realization.contains("MAX_CORPSE_REALIZATION_FAILURES") and realization.contains("failures >= MAX_CORPSE_REALIZATION_FAILURES"), "corpse realization retries are not bounded")
	_expect(component.contains("body_state") and component.contains("last_world_transform"), "person records lack durable remains state or transform")
	_expect(furnace.contains("set_person_body_state") and not furnace.contains("remove_actor_record"), "furnace still deletes person records")
	_expect(not population.substr(population.find("func ensure_generated_population"), population.find("\n\nfunc ", population.find("func ensure_generated_population") + 1) - population.find("func ensure_generated_population")).contains("_remove_actor_record"), "population resizing still deletes people")
	_expect(faction_squads.contains("population.call(\"unregister_actor\", node)"), "faction LOD does not preserve person records")
	_expect(faction_squads.contains("_generate_squad_records(_get_population_controller()"), "offscreen faction members do not exist as permanent people")
	_expect(nests.contains("person_ids_by_squad") and nests.contains("next_person_sequence") and nests.contains("_ensure_nest_squad_people"), "nest members lack permanent non-reused person IDs")
	_expect(encounters.contains("apply_offscreen_squad_casualties"), "offscreen combat casualties do not kill specific permanent people")
	_expect(encounters.contains("register_offscreen_prisoner") and law_order.contains("func register_offscreen_prisoner"), "offscreen captures do not create canonical prisoner records")
	if _failed:
		quit(1)
	else:
		print("CORPSE_PERSISTENCE_OK")
		quit(0)


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error(message)
