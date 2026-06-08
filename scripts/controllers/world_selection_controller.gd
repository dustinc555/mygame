extends Node

class_name WorldSelectionController

const CHARACTER_SKILLS_WINDOW_SCRIPT = preload("res://scripts/ui/character_skills_window.gd")

signal selection_changed(actor_id: String, details_snapshot: Dictionary)

@export var details_panel_path := NodePath("HudLayout/BottomHud/InspectorSlot/HumanoidDetailsPanel")
@export_range(0.05, 2.0, 0.05) var details_refresh_interval_seconds := 0.25
@export_range(10.0, 10000.0, 10.0) var max_raycast_distance := 2000.0
@export_flags_3d_physics var selection_collision_mask := 0xFFFFFFFF

var root_scene: Node
var hud_layer: CanvasLayer
var _details_panel: Node
var _selected_actor_ids: Array[String] = []
var _selected_actor_id := ""
var _selected_projection: Node
var _last_snapshot: Dictionary = {}
var _refresh_elapsed := 0.0
var _skills_window: CharacterSkillsWindow


func initialize(target_root: Node, target_hud: CanvasLayer = null) -> void:
	root_scene = target_root
	hud_layer = target_hud
	_bind_details_panel()
	_refresh_details_panel()


func _ready() -> void:
	add_to_group("world_selection_controller")


func _process(delta: float) -> void:
	if _selected_actor_id.is_empty():
		return
	_refresh_elapsed += delta
	if _refresh_elapsed < details_refresh_interval_seconds:
		return
	_refresh_elapsed = 0.0
	refresh_selection_details()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		_handle_mouse_button(event as InputEventMouseButton)
		return
	if event is InputEventKey:
		_handle_key(event as InputEventKey)


func select_projection(projection: Node, add_select := false) -> bool:
	if projection == null or not is_instance_valid(projection):
		return false
	return select_actor_id(str(projection.get("actor_id")), add_select)


func select_actor_id(actor_id: String, add_select := false) -> bool:
	var normalized_id := actor_id.strip_edges()
	if normalized_id.is_empty():
		clear_selection()
		return false
	if _population_record(normalized_id).is_empty():
		return false
	var next_ids: Array[String] = []
	if add_select:
		next_ids = _selected_actor_ids.duplicate()
	for id in next_ids:
		if id == normalized_id:
			_apply_selection(next_ids, normalized_id)
			return true
	if add_select:
		next_ids.append(normalized_id)
	else:
		next_ids = [normalized_id]
	_apply_selection(next_ids, normalized_id)
	return true


func select_actor_ids(actor_ids: Array, add_select := false) -> bool:
	var next_ids: Array[String] = []
	if add_select:
		for selected_id in _selected_actor_ids:
			next_ids.append(selected_id)
	for actor_id_value in actor_ids:
		var actor_id := str(actor_id_value).strip_edges()
		if actor_id.is_empty() or _population_record(actor_id).is_empty() or next_ids.has(actor_id):
			continue
		next_ids.append(actor_id)
	if next_ids.is_empty():
		clear_selection()
		return false
	_apply_selection(next_ids, next_ids[0])
	return true


func clear_selection() -> void:
	for actor_id in _selected_actor_ids:
		_set_projection_selected_for(actor_id, false)
	_selected_actor_ids.clear()
	_selected_actor_id = ""
	_selected_projection = null
	_last_snapshot = {}
	_refresh_details_panel()
	selection_changed.emit("", {})


func refresh_selection_details() -> Dictionary:
	if _selected_actor_id.is_empty():
		_refresh_details_panel()
		return {}
	var record := _population_record(_selected_actor_id)
	if record.is_empty():
		var next_ids: Array[String] = []
		for actor_id in _selected_actor_ids:
			if actor_id != _selected_actor_id and not _population_record(actor_id).is_empty():
				next_ids.append(actor_id)
		if next_ids.is_empty():
			clear_selection()
			return {}
		_apply_selection(next_ids, next_ids[0])
		return _last_snapshot.duplicate(true)
	_selected_projection = _projection_for_actor(_selected_actor_id)
	_last_snapshot = _details_snapshot(record)
	_refresh_details_panel()
	selection_changed.emit(_selected_actor_id, _last_snapshot.duplicate(true))
	return _last_snapshot.duplicate(true)


func get_selected_actor_id() -> String:
	return _selected_actor_id


func get_selected_actor_ids() -> Array[String]:
	return _selected_actor_ids.duplicate()


func get_selected_projection() -> Node:
	return _selected_projection if _selected_projection != null and is_instance_valid(_selected_projection) else null


func get_selected_details_snapshot() -> Dictionary:
	return _last_snapshot.duplicate(true)


func _apply_selection(actor_ids: Array[String], primary_actor_id: String) -> void:
	for actor_id in _selected_actor_ids:
		if not actor_ids.has(actor_id):
			_set_projection_selected_for(actor_id, false)
	_selected_actor_ids.clear()
	for actor_id in actor_ids:
		if actor_id.is_empty() or _selected_actor_ids.has(actor_id):
			continue
		_selected_actor_ids.append(actor_id)
		_set_projection_selected_for(actor_id, true)
	_selected_actor_id = primary_actor_id if _selected_actor_ids.has(primary_actor_id) else (_selected_actor_ids[0] if not _selected_actor_ids.is_empty() else "")
	_selected_projection = _projection_for_actor(_selected_actor_id) if not _selected_actor_id.is_empty() else null
	var record := _population_record(_selected_actor_id) if not _selected_actor_id.is_empty() else {}
	_last_snapshot = _details_snapshot(record) if not record.is_empty() else {}
	_refresh_elapsed = 0.0
	_refresh_details_panel()
	selection_changed.emit(_selected_actor_id, _last_snapshot.duplicate(true))


func _handle_mouse_button(event: InputEventMouseButton) -> void:
	if not event.pressed:
		return
	if event.button_index != MOUSE_BUTTON_LEFT or event.double_click:
		return
	var projection := _projection_from_screen_position(event.position)
	if projection == null:
		return
	if select_projection(projection, event.alt_pressed):
		get_viewport().set_input_as_handled()


func _handle_key(event: InputEventKey) -> void:
	if not event.pressed or event.echo:
		return
	if event.keycode == KEY_ESCAPE and not _selected_actor_id.is_empty():
		clear_selection()
		get_viewport().set_input_as_handled()


func _projection_from_screen_position(screen_position: Vector2) -> Node:
	var camera := _current_camera()
	if camera == null:
		return null
	var world := camera.get_world_3d()
	if world == null:
		return null
	var origin := camera.project_ray_origin(screen_position)
	var end := origin + camera.project_ray_normal(screen_position) * max_raycast_distance
	var query := PhysicsRayQueryParameters3D.create(origin, end, selection_collision_mask)
	query.collide_with_areas = true
	query.collide_with_bodies = true
	var hit := world.direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return null
	return _projection_from_collider(hit.get("collider"))


func _projection_from_collider(collider) -> Node:
	var current := collider as Node
	while current != null:
		if current.is_in_group("projected_world_actor"):
			return current
		current = current.get_parent()
	return null


func _current_camera() -> Camera3D:
	var viewport := get_viewport()
	if viewport != null:
		var camera := viewport.get_camera_3d()
		if camera != null:
			return camera
	if root_scene != null:
		return root_scene.find_child("Camera3D", true, false) as Camera3D
	return null


func _details_snapshot(record: Dictionary) -> Dictionary:
	var actor_id := str(record.get("actor_id", record.get("stable_id", _selected_actor_id))).strip_edges()
	var equipment_slots := _equipment_slots_for_actor(actor_id, record)
	var stat_profile := _stat_profile_for_actor(actor_id, record)
	var effective_stats: Dictionary = stat_profile.get("effective_stats", {}) if stat_profile.get("effective_stats", {}) is Dictionary else {}
	var modifiers: Array = stat_profile.get("modifiers", []) if stat_profile.get("modifiers", []) is Array else []
	var skill_levels: Dictionary = record.get("skill_levels", {}) if record.get("skill_levels", {}) is Dictionary else {}
	var skill_xp: Dictionary = record.get("skill_xp", {}) if record.get("skill_xp", {}) is Dictionary else {}
	var squad_record := _squad_record_for_record(record)
	var encounter_record := _encounter_record_for_squad(squad_record)
	var life_state := int(record.get("life_state", 0))
	var move_order: Dictionary = record.get("move_order", {}) if record.get("move_order", {}) is Dictionary else {}
	var locomotion_state: Dictionary = record.get("locomotion_state", {}) if record.get("locomotion_state", {}) is Dictionary else {}
	var objective_summary := _objective_summary(record, squad_record)
	var combat_summary := _combat_summary(record, squad_record, encounter_record, effective_stats)
	return {
		"actor_id": actor_id,
		"projection_kind": str(record.get("projection_kind", "")),
		"member_name": str(record.get("member_name", actor_id)),
		"faction_id": str(record.get("faction_id", "")),
		"party_id": str(record.get("party_id", "")),
		"player_party_member": bool(record.get("player_party_member", false)),
		"player_controllable": bool(record.get("player_controllable", false)),
		"squad_name": str(record.get("squad_name", "")),
		"role_id": str(record.get("role_id", "")),
		"life_state": life_state,
		"life_state_text": _life_state_text(life_state),
		"hunger": float(record.get("hunger", 100.0)),
		"hunger_stage": int(record.get("hunger_stage", NpcRules.HungerStage.WELL_NOURISHED)),
		"hunger_stage_text": NpcRules.get_hunger_stage_label(int(record.get("hunger_stage", NpcRules.HungerStage.WELL_NOURISHED))),
		"fatigue": float(record.get("fatigue", 100.0)),
		"fatigue_stage": int(record.get("fatigue_stage", NpcRules.FatigueStage.WELL_RESTED)),
		"fatigue_stage_text": NpcRules.get_fatigue_stage_label(int(record.get("fatigue_stage", NpcRules.FatigueStage.WELL_RESTED))),
		"hp": float(record.get("hp", 0.0)),
		"max_hp": float(record.get("max_hp", 0.0)),
		"blood": float(record.get("blood", 0.0)),
		"max_blood": float(record.get("max_blood", 0.0)),
		"open_cut_damage": float(record.get("open_cut_damage", 0.0)),
		"bandaged_cut_damage": float(record.get("bandaged_cut_damage", 0.0)),
		"blunt_damage": float(record.get("blunt_damage", 0.0)),
		"bleed_rate": float(record.get("bleed_rate", 0.0)),
		"base_attack_damage": float(record.get("base_attack_damage", 0.0)),
		"base_dodge_chance": float(record.get("base_dodge_chance", 0.0)),
		"base_block_chance": float(record.get("base_block_chance", 0.0)),
		"effective_attack_damage": float(effective_stats.get("attack_damage", record.get("base_attack_damage", 0.0))),
		"effective_dodge_chance": float(effective_stats.get("dodge_chance", record.get("base_dodge_chance", 0.0))),
		"effective_block_chance": float(effective_stats.get("block_chance", record.get("base_block_chance", 0.0))),
		"equipment_stat_profile": stat_profile.duplicate(true),
		"equipment_stat_modifiers": modifiers.duplicate(true),
		"combat_stance": int(record.get("combat_stance", 0)),
		"movement_mode": int(record.get("movement_mode", 0)),
		"move_order": move_order.duplicate(true),
		"locomotion_state": locomotion_state.duplicate(true),
		"auto_heal_enabled": bool(record.get("auto_heal_enabled", false)),
		"auto_burn_rustdead_enabled": bool(record.get("auto_burn_rustdead_enabled", false)),
		"ledger_activity_state": str(record.get("ledger_activity_state", "")),
		"equipment_slots": equipment_slots.duplicate(true),
		"equipment_summary": _equipment_summary(equipment_slots),
		"skill_levels": skill_levels.duplicate(true),
		"skill_xp": skill_xp.duplicate(true),
		"stats_summary": _stats_summary(skill_levels),
		"skills_summary": _skills_summary(skill_levels),
		"wounds_summary": _wounds_summary(record),
		"objective_summary": objective_summary,
		"combat_summary": combat_summary,
		"squad_record": squad_record.duplicate(true),
		"encounter_record": encounter_record.duplicate(true),
	}


func _population_record(actor_id: String) -> Dictionary:
	var bridge := _get_gecs_world()
	if bridge == null:
		return {}
	var record = bridge.call("get_population_record_core", actor_id) if bridge.has_method("get_population_record_core") else (bridge.call("get_population_record", actor_id) if bridge.has_method("get_population_record") else {})
	return record if record is Dictionary else {}


func _equipment_slots_for_actor(actor_id: String, record: Dictionary) -> Dictionary:
	var from_record: Dictionary = record.get("equipment_slots", {}) if record.get("equipment_slots", {}) is Dictionary else {}
	if not from_record.is_empty():
		return from_record.duplicate(true)
	var bridge := _get_gecs_world()
	var result := {}
	if bridge != null and bridge.has_method("get_equipment_slots"):
		for slot in bridge.call("get_equipment_slots", actor_id):
			if not (slot is Dictionary):
				continue
			var slot_name := str((slot as Dictionary).get("slot_name", "")).strip_edges()
			var item_id := str((slot as Dictionary).get("item_id", "")).strip_edges()
			if not slot_name.is_empty() and not item_id.is_empty():
				result[slot_name] = item_id
	return result


func _stat_profile_for_actor(actor_id: String, record: Dictionary) -> Dictionary:
	var bridge := _get_gecs_world()
	if bridge != null and bridge.has_method("get_actor_stat_profile"):
		var profile = bridge.call("get_actor_stat_profile", actor_id, record)
		if profile is Dictionary:
			return (profile as Dictionary).duplicate(true)
	return {}


func _squad_record_for_record(record: Dictionary) -> Dictionary:
	var combat := _get_combat_controller()
	if combat == null or not combat.has_method("get_world_squad_state"):
		return {}
	var squad_state: Dictionary = combat.call("get_world_squad_state")
	var active_squads: Dictionary = squad_state.get("active_squads", {}) if squad_state.get("active_squads", {}) is Dictionary else {}
	var squad_name := str(record.get("squad_name", "")).strip_edges()
	var actor_id := str(record.get("actor_id", "")).strip_edges()
	if not squad_name.is_empty() and active_squads.has(squad_name) and active_squads[squad_name] is Dictionary:
		return (active_squads[squad_name] as Dictionary).duplicate(true)
	for squad in active_squads.values():
		if not (squad is Dictionary):
			continue
		var member_ids: Array = (squad as Dictionary).get("member_ids", []) if (squad as Dictionary).get("member_ids", []) is Array else []
		if member_ids.has(actor_id):
			return (squad as Dictionary).duplicate(true)
	return {}


func _encounter_record_for_squad(squad_record: Dictionary) -> Dictionary:
	if squad_record.is_empty():
		return {}
	var encounter_id := str(squad_record.get("active_encounter_id", "")).strip_edges()
	if encounter_id.is_empty():
		return {}
	var combat := _get_combat_controller()
	if combat == null or not combat.has_method("get_world_encounter_state"):
		return {}
	var encounter_state: Dictionary = combat.call("get_world_encounter_state")
	var encounters: Dictionary = encounter_state.get("encounters_by_id", {}) if encounter_state.get("encounters_by_id", {}) is Dictionary else {}
	var record = encounters.get(encounter_id, encounters.get(int(encounter_id), {}))
	return record.duplicate(true) if record is Dictionary else {}


func _objective_summary(record: Dictionary, squad_record: Dictionary) -> String:
	if not squad_record.is_empty():
		var objective := str(squad_record.get("objective_id", "hold_position"))
		var state := str(squad_record.get("objective_state", "idle"))
		return "%s (%s)" % [_display_token(objective), _display_token(state)]
	var move_order: Dictionary = record.get("move_order", {}) if record.get("move_order", {}) is Dictionary else {}
	if bool(move_order.get("active", false)):
		return "Moving"
	var activity := str(record.get("ledger_activity_state", "routine")).strip_edges()
	return _display_token(activity if not activity.is_empty() else "routine")


func _combat_summary(record: Dictionary, squad_record: Dictionary, encounter_record: Dictionary, effective_stats: Dictionary = {}) -> String:
	var parts: Array[String] = []
	parts.append("Stance: %s" % _stance_text(int(record.get("combat_stance", 0))))
	if not effective_stats.is_empty():
		parts.append("Damage: %s" % _format_decimal(float(effective_stats.get("attack_damage", record.get("base_attack_damage", 0.0))), 1))
	if not squad_record.is_empty():
		var encounter_id := str(squad_record.get("active_encounter_id", "")).strip_edges()
		parts.append("Encounter: %s" % (encounter_id if not encounter_id.is_empty() else "none"))
	if not encounter_record.is_empty():
		parts.append("State: %s" % _display_token(str(encounter_record.get("state", "active"))))
	return "; ".join(parts)


func _wounds_summary(record: Dictionary) -> String:
	var life_state := int(record.get("life_state", 0))
	if life_state != 0:
		return "Wounds: %s" % _life_state_text(life_state)
	var hp := float(record.get("hp", 0.0))
	var max_hp := float(record.get("max_hp", 0.0))
	if max_hp > 0.0 and hp < max_hp:
		return "Wounds: hurt"
	return "Wounds: none"


func _stats_summary(skill_levels: Dictionary) -> String:
	var ids := [
		"attribute.strength",
		"attribute.dexterity",
		"attribute.endurance",
		"attribute.toughness",
		"attribute.perception",
	]
	var parts: Array[String] = []
	for skill_id in ids:
		if skill_levels.has(skill_id):
			parts.append("%s %d" % [_short_skill_label(skill_id), int(skill_levels[skill_id])])
	return ", ".join(parts) if not parts.is_empty() else "-"


func _skills_summary(skill_levels: Dictionary) -> String:
	var entries: Array[Dictionary] = []
	for skill_id_value in skill_levels.keys():
		var skill_id := str(skill_id_value)
		if skill_id.begins_with("attribute."):
			continue
		entries.append({"id": skill_id, "level": int(skill_levels[skill_id_value])})
	entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.get("level", 0)) > int(b.get("level", 0)))
	var parts: Array[String] = []
	for index in range(mini(entries.size(), 3)):
		var entry: Dictionary = entries[index]
		parts.append("%s %d" % [_short_skill_label(str(entry.get("id", ""))), int(entry.get("level", 0))])
	return ", ".join(parts) if not parts.is_empty() else "-"


func _equipment_summary(equipment_slots: Dictionary) -> String:
	if equipment_slots.is_empty():
		return "-"
	var preferred := ["weapon", "offhand", "head", "chest", "legs", "feet"]
	var parts: Array[String] = []
	for slot_name in preferred:
		if equipment_slots.has(slot_name):
			parts.append("%s: %s" % [_display_token(slot_name), _item_name(str(equipment_slots[slot_name]))])
	for slot_name_value in equipment_slots.keys():
		var slot_name := str(slot_name_value)
		if preferred.has(slot_name):
			continue
		parts.append("%s: %s" % [_display_token(slot_name), _item_name(str(equipment_slots[slot_name_value]))])
	return "; ".join(parts)


func _item_name(item_path: String) -> String:
	var identifier := item_path.strip_edges()
	return _display_token(identifier.get_file().get_basename() if identifier.begins_with("res://") else identifier)


func _format_decimal(value: float, digits: int) -> String:
	var rounded := snappedf(value, pow(10.0, -digits))
	var text := str(rounded)
	if text.contains("."):
		while text.ends_with("0"):
			text = text.substr(0, text.length() - 1)
		if text.ends_with("."):
			text = text.substr(0, text.length() - 1)
	return text


func _projection_for_actor(actor_id: String) -> Node:
	var projection_controller := _get_projection_controller()
	if projection_controller != null and projection_controller.has_method("get_projection_for_actor"):
		var projection = projection_controller.call("get_projection_for_actor", actor_id)
		if projection is Node:
			return projection
	return null


func _set_projection_selected_for(actor_id: String, selected: bool) -> void:
	var projection := _projection_for_actor(actor_id)
	if projection == null:
		return
	if selected:
		projection.add_to_group("selected_actor")
		var record := _population_record(actor_id)
		if bool(record.get("player_party_member", false)):
			projection.add_to_group("selected_party_member")
	else:
		projection.remove_from_group("selected_actor")
		projection.remove_from_group("selected_party_member")
	if projection.has_method("set_selected"):
		projection.call("set_selected", selected)


func _refresh_details_panel() -> void:
	_bind_details_panel()
	if _details_panel == null:
		return
	if _last_snapshot.is_empty():
		if _details_panel.has_method("show_empty"):
			_details_panel.call("show_empty")
		return
	if _details_panel.has_method("show_character_snapshot"):
		_details_panel.call("show_character_snapshot", _last_snapshot)


func _bind_details_panel() -> void:
	if _details_panel != null and is_instance_valid(_details_panel):
		return
	if hud_layer != null:
		_details_panel = hud_layer.get_node_or_null(details_panel_path)
	if _details_panel == null and root_scene != null:
		var hud := root_scene.get_node_or_null("GameHUD")
		if hud != null:
			_details_panel = hud.get_node_or_null(details_panel_path)
	if _details_panel != null and _details_panel.has_signal("inspector_action_requested"):
		var action_callable := Callable(self, "_on_inspector_action_requested")
		if not _details_panel.is_connected("inspector_action_requested", action_callable):
			_details_panel.connect("inspector_action_requested", action_callable)


func _on_inspector_action_requested(actor_id: String, action_key: String) -> void:
	match action_key:
		"inventory":
			_open_inventory_window(actor_id)
		"skills":
			_open_skills_window(actor_id)


func _open_inventory_window(actor_id: String) -> void:
	var normalized_id := actor_id.strip_edges()
	if normalized_id.is_empty():
		return
	var controller := _get_party_inventory_controller()
	if controller != null and controller.has_method("open_inventory_for_actor_id"):
		controller.call("open_inventory_for_actor_id", normalized_id)


func _open_skills_window(actor_id: String) -> void:
	var normalized_id := actor_id.strip_edges()
	if normalized_id.is_empty():
		return
	var record := _population_record(normalized_id)
	if record.is_empty():
		return
	var window := _ensure_skills_window()
	if window == null:
		return
	window.show_for_actor_id(normalized_id, record)


func _ensure_skills_window() -> CharacterSkillsWindow:
	if _skills_window != null and is_instance_valid(_skills_window):
		return _skills_window
	var parent := _skills_window_parent()
	if parent == null:
		return null
	_skills_window = CHARACTER_SKILLS_WINDOW_SCRIPT.new() as CharacterSkillsWindow
	_skills_window.name = "CharacterSkillsWindow"
	parent.add_child(_skills_window)
	_skills_window.setup(root_scene, hud_layer)
	return _skills_window


func _skills_window_parent() -> Node:
	var hud := hud_layer if hud_layer != null else (root_scene.get_node_or_null("GameHUD") if root_scene != null else null)
	if hud != null:
		var layer := hud.get_node_or_null("InventoryWindowLayer")
		return layer if layer != null else hud
	return root_scene


func _get_gecs_world() -> Node:
	var parent_node := get_parent()
	if parent_node != null:
		var local := parent_node.get_node_or_null("GecsWorldController")
		if local != null:
			return local
	return get_tree().get_first_node_in_group("gecs_world_controller") if is_inside_tree() else null


func _get_projection_controller() -> Node:
	var parent_node := get_parent()
	if parent_node != null:
		var local := parent_node.get_node_or_null("WorldActorProjectionController")
		if local != null:
			return local
	return get_tree().get_first_node_in_group("world_actor_projection_controller") if is_inside_tree() else null


func _get_combat_controller() -> Node:
	var parent_node := get_parent()
	if parent_node != null:
		var local := parent_node.get_node_or_null("WorldMapCombatSimController")
		if local != null:
			return local
	return get_tree().get_first_node_in_group("world_map_combat_sim_controller") if is_inside_tree() else null


func _get_party_inventory_controller() -> Node:
	var parent_node := get_parent()
	if parent_node != null:
		var local := parent_node.get_node_or_null("PartyInventoryController")
		if local != null:
			return local
	return get_tree().get_first_node_in_group("party_inventory_controller") if is_inside_tree() else null


func _life_state_text(life_state: int) -> String:
	var label := NpcRules.get_life_state_label(life_state)
	return label if label != "Unknown" else "State %d" % life_state


func _stance_text(stance: int) -> String:
	match stance:
		0:
			return "Aggressive"
		1:
			return "Defensive"
		2:
			return "Passive"
	return "Stance %d" % stance


func _short_skill_label(skill_id: String) -> String:
	var text := skill_id.get_slice(".", skill_id.get_slice_count(".") - 1)
	var words := text.split("_")
	for index in range(words.size()):
		words[index] = str(words[index]).capitalize()
	return " ".join(words)


func _display_token(value: String) -> String:
	var text := value.strip_edges()
	if text.is_empty():
		return "-"
	var words := text.replace(".", "_").split("_")
	for index in range(words.size()):
		words[index] = str(words[index]).capitalize()
	return " ".join(words)
