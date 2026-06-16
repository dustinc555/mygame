extends Node3D

const PARTY_MEMBER_SCENE := preload("res://scenes/characters/party_member.tscn")

@export var character_record_paths: PackedStringArray = PackedStringArray()
@export var faction_id := "Player"
@export var squad_name := "Rustwash"
@export var hostile_faction_ids: PackedStringArray = PackedStringArray()
@export_range(0, 2, 1) var combat_stance := NpcRules.CombatStance.DEFENSIVE
@export var role_id := "player_party"
@export var important := true
@export var spawn_spacing := 1.8
@export var member_colors: PackedColorArray = PackedColorArray()
@export var max_defer_frames := 30

var _spawned := false


func _ready() -> void:
	_spawn_when_ready()


func _spawn_when_ready() -> void:
	var attempts := 0
	while attempts < max_defer_frames:
		if _try_spawn_party():
			return
		attempts += 1
		await get_tree().process_frame
	_try_spawn_party()


func _try_spawn_party() -> bool:
	if _spawned:
		return true
	var root_scene := _get_root_scene()
	if root_scene == null:
		return false
	var party_root := _get_party_root(root_scene)
	var party_manager := root_scene.get_node_or_null("PartyManager") as PartyManager
	var population_controller := _get_controller(root_scene, "PopulationController", "population_controller")
	var gecs_world := _get_controller(root_scene, "GecsWorldController", "gecs_world_controller")
	if party_root == null or party_manager == null or population_controller == null or gecs_world == null:
		return false

	var spawned_members: Array[WorldActor] = []
	var total_count := character_record_paths.size()
	for index in range(total_count):
		var source_record := _load_character_record(character_record_paths[index])
		if source_record.is_empty():
			continue
		var scene_record := _record_for_scene(source_record, index, total_count, party_root)
		if scene_record.is_empty():
			continue
		var actor_id := str(scene_record.get("actor_id", ""))
		var upserted_record = gecs_world.call("upsert_population_record", scene_record)
		if upserted_record is Dictionary:
			scene_record = upserted_record
		var member := _find_existing_member(party_root, actor_id)
		if member == null:
			member = PARTY_MEMBER_SCENE.instantiate() as WorldActor
			if member == null:
				continue
			member.name = _node_name_for_actor_id(actor_id)
			population_controller.call("apply_record_to_actor", member, scene_record)
			member.position = _local_spawn_position(index, total_count)
			party_root.add_child(member)
		else:
			population_controller.call("apply_record_to_actor", member, scene_record)
			member.position = _local_spawn_position(index, total_count)
		population_controller.call("register_actor", member, "", {"role_id": role_id})
		gecs_world.call("register_actor", member, "", {"role_id": role_id})
		party_manager.register_party_member(member)
		spawned_members.append(member)

	if not spawned_members.is_empty() and _party_selection_empty(party_manager):
		party_manager.select_only(spawned_members[0])
	_spawned = true
	return true


func _load_character_record(record_path: String) -> Dictionary:
	var clean_path := record_path.strip_edges()
	if clean_path.is_empty():
		return {}
	var file_access := FileAccess.open(clean_path, FileAccess.READ)
	if file_access == null:
		push_error("Character record missing: %s" % clean_path)
		return {}
	var parsed = JSON.parse_string(file_access.get_as_text())
	if not (parsed is Dictionary):
		push_error("Character record is not a JSON object: %s" % clean_path)
		return {}
	return _normalize_record(parsed as Dictionary)


func _normalize_record(source_record: Dictionary) -> Dictionary:
	var record := source_record.duplicate(true)
	var appearance_value = record.get("appearance", {})
	if appearance_value is Dictionary:
		var appearance: Dictionary = (appearance_value as Dictionary).duplicate(true)
		for color_key in ["hair_color", "beard_color", "eyebrow_color", "skin_color"]:
			if appearance.has(color_key):
				appearance[color_key] = _color_from_json(appearance[color_key])
		record["appearance"] = appearance
	var inventory_value = record.get("inventory_entries", [])
	if inventory_value is Array:
		var inventory_entries: Array = []
		for entry_value in inventory_value:
			if entry_value is Dictionary:
				var entry: Dictionary = (entry_value as Dictionary).duplicate(true)
				if entry.has("grid_position"):
					entry["grid_position"] = _vector2i_from_json(entry["grid_position"])
				inventory_entries.append(entry)
		record["inventory_entries"] = inventory_entries
	return record


func _record_for_scene(source_record: Dictionary, record_index: int, total_count: int, party_root: Node3D) -> Dictionary:
	var actor_id := str(source_record.get("actor_id", "")).strip_edges()
	if actor_id.is_empty():
		push_error("Character record has no actor_id")
		return {}
	var record := source_record.duplicate(true)
	var spawn_position := party_root.to_global(_local_spawn_position(record_index, total_count))
	record["actor_id"] = actor_id
	record["stable_id"] = actor_id
	record["faction_id"] = faction_id
	record["squad_name"] = squad_name
	record["hostile_faction_ids"] = Array(hostile_faction_ids)
	record["combat_stance"] = combat_stance
	record["role_id"] = role_id
	record["life_state"] = NpcRules.LifeState.ALIVE
	record["realization_state"] = "ledger"
	record["last_world_position"] = spawn_position
	record["last_world_position_initialized"] = true
	record["important"] = important
	if record_index >= 0 and record_index < member_colors.size():
		record["base_color"] = member_colors[record_index]
	return record


func _local_spawn_position(record_index: int, total_count: int) -> Vector3:
	var centered_index := float(record_index) - float(maxi(total_count - 1, 0)) * 0.5
	return position + Vector3(0.0, 0.0, centered_index * spawn_spacing)


func _find_existing_member(party_root: Node3D, actor_id: String) -> WorldActor:
	for child in party_root.get_children():
		var actor := child as WorldActor
		if actor == null:
			continue
		if str(actor.stable_id).strip_edges() == actor_id:
			return actor
		if actor.has_meta("actor_record_id") and str(actor.get_meta("actor_record_id")).strip_edges() == actor_id:
			return actor
	return null


func _get_party_root(root_scene: Node) -> Node3D:
	var parent_node := get_parent() as Node3D
	if parent_node != null and parent_node.name == "PartyMembers":
		return parent_node
	var party_root := root_scene.get_node_or_null("PartyMembers") as Node3D
	return party_root


func _get_root_scene() -> Node:
	var parent_node := get_parent()
	if parent_node != null and parent_node.get_parent() != null:
		return parent_node.get_parent()
	return get_tree().current_scene if is_inside_tree() else null


func _get_controller(root_scene: Node, node_name: String, group_name: String) -> Node:
	var bootstrap := root_scene.get_node_or_null("GameBootstrap")
	if bootstrap != null:
		var local_controller := bootstrap.get_node_or_null(node_name)
		if local_controller != null:
			return local_controller
	var grouped_controller := get_tree().get_first_node_in_group(group_name) if is_inside_tree() else null
	return grouped_controller as Node


func _party_selection_empty(party_manager: PartyManager) -> bool:
	var selected_value = party_manager.get("selected_members")
	return not (selected_value is Array) or (selected_value as Array).is_empty()


func _color_from_json(value) -> Color:
	if value is Color:
		return value
	if value is Array:
		var values: Array = value
		var red := float(values[0]) if values.size() > 0 else 1.0
		var green := float(values[1]) if values.size() > 1 else red
		var blue := float(values[2]) if values.size() > 2 else green
		var alpha := float(values[3]) if values.size() > 3 else 1.0
		return Color(red, green, blue, alpha)
	return Color.WHITE


func _vector2i_from_json(value) -> Vector2i:
	if value is Vector2i:
		return value
	if value is Array:
		var values: Array = value
		var x := int(values[0]) if values.size() > 0 else 0
		var y := int(values[1]) if values.size() > 1 else 0
		return Vector2i(x, y)
	return Vector2i.ZERO


func _node_name_for_actor_id(actor_id: String) -> String:
	var node_name := ""
	var capitalize_next := true
	for index in range(actor_id.length()):
		var character := actor_id.substr(index, 1)
		if (character >= "a" and character <= "z") or (character >= "A" and character <= "Z") or (character >= "0" and character <= "9"):
			node_name += character.to_upper() if capitalize_next else character
			capitalize_next = false
		else:
			capitalize_next = true
	return node_name if not node_name.is_empty() else "Character"
