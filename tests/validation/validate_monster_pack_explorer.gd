extends SceneTree
## Standalone explorer: all imported monsters, real clips only, safe switching.
const SCENE := "res://tools/monster_pack_explorer/monster_pack_explorer.tscn"
var failures: Array[String] = []
func _initialize() -> void:
	call_deferred("_run")
func _run() -> void:
	if not ResourceLoader.exists(SCENE):
		push_error("Monster Pack Explorer scene is missing")
		quit(1)
		return
	var explorer = load(SCENE).instantiate()
	root.add_child(explorer)
	await process_frame
	var expected_paths := {}
	for file_name in DirAccess.get_files_at(explorer.PACK_DIR):
		if file_name.get_extension().to_lower() != "glb":
			continue
		var definition: Dictionary = explorer.equipment_preview.manifest.get("models", {}).get(file_name, {})
		if str(definition.get("equipment_variant_of", "")).is_empty():
			expected_paths[explorer.PACK_DIR.path_join(file_name)] = true
	var seen_paths := {}
	for monster in explorer.monsters:
		_expect(expected_paths.has(monster.path) and not seen_paths.has(monster.path), "monster entries must uniquely match canonical non-equipment sources")
		seen_paths[monster.path] = true
	_expect(not seen_paths.is_empty() and seen_paths.size() == expected_paths.size(), "all canonical monster sources must be listed")
	var records: Array = []
	var previous_clip := ""
	for index in explorer.monsters.size():
		explorer.select_monster(index)
		await process_frame
		if not previous_clip.is_empty():
			_expect(explorer.clips[explorer._selected_clip].name == previous_clip, "changing monsters preserves the selected animation")
			_expect(explorer.animation_select.get_item_text(explorer.animation_select.selected) == previous_clip, "animation selector matches retained playback")
		_expect(is_instance_valid(explorer.model), "selected model instantiates")
		_expect(explorer.model_bounds.size.length() > 0.01, "model has visible mesh bounds")
		if explorer.monsters[index].name != "Lycan":
			_expect(not explorer.equipment_preview.options.is_empty(), "equipped monsters expose actual item choices")
		var preview = explorer.equipment_preview
		if explorer.monsters[index].name == "Puglin":
			var race = load("res://features/actors/resources/character_races/puglin.tres")
			var body = race.default_male_archetype
			_expect(preview.wearer.appearance_data.character_race == race, "Puglin uses the canonical race, not a preview copy")
			_expect(preview.wearer.appearance_data.body_archetype == body and preview._projection._body_archetype == body, "Puglin rendering and equipment share the canonical body")
			_expect(explorer.model.scene_file_path == body.visual_scene.resource_path, "Puglin explorer uses the canonical body scene")
			_expect(preview.wearer.get_equipment_slot_names() == race.get_equipment_slots(), "Puglin slots come from the race")
			var bronze = load("res://features/inventory/resources/items/bronze_sword.tres")
			_expect(preview.options.weapon.has(bronze), "bronze sword remains available for grip inspection")
			preview.equipment.equip_item_to_slot(bronze, "weapon")
			var socket: Node3D = preview._projection._slot_visuals.weapon.get_parent()
			_expect(socket.transform.is_equal_approx(body.grip_socket_profile.right_hand_one_hand), "Puglin weapon socket uses its body's grip profile")
			_expect(not explorer.model.get_node("Armature/Skeleton3D/Puglin_Stick").visible, "canonical body contains no visible decorative stick")
		var current_clip: String = explorer.clips[explorer._selected_clip].name
		for slot in preview.options:
			var original = preview.equipment.get_equipped_item(slot)
			for option in range(1, preview.options[slot].size() + 1):
				preview.choose_item(slot, option)
				_expect(preview._projection._slot_visuals.has(slot), "every equipment choice mounts on selected model")
			preview.choose_item(slot, 0)
			_expect(not preview._projection._slot_visuals.has(slot), "None removes equipment visually")
			if original != null: preview.equipment.equip_item_to_slot(original, slot)
		_expect(explorer.clips[explorer._selected_clip].name == current_clip, "gear switching preserves animation")
		if str(explorer.monsters[index].name).begins_with("Skeleton"):
			_expect(preview.options.weapon.size() == 2 and preview.options.head.size() == 2, "both skeleton variants share weapons and helmets")
		var names: Array = []
		_expect(not explorer.clips.is_empty(), "every monster receives Universal Animation Library clips")
		for clip_index in explorer.clips.size():
			explorer.select_clip(clip_index)
			var entry: Dictionary = explorer.clips[clip_index]
			var player: AnimationPlayer = entry.player
			_expect(player.has_animation(entry.name), "listed animation exists on selected monster")
			_expect(player.is_playing(), "selecting an animation starts playback automatically")
			_expect(player.get_animation(entry.name).loop_mode == Animation.LOOP_LINEAR, "selected animation loops")
			player.seek(player.get_animation(entry.name).length * 0.5, true)
			names.append(entry.name)
		previous_clip = explorer.clips[explorer._selected_clip].name
		records.append({"monster": explorer.monsters[index].name, "clips": names})
	explorer.filter_monsters("skeleton")
	_expect(explorer.monster_list.item_count == 1, "skeleton search returns one body, not equipment variants")
	if explorer.monster_list.item_count == 1:
		_expect(explorer.monster_list.get_item_text(0) == "Skeleton", "skeleton has no source-file variant suffix")
	explorer.filter_monsters("not a monster")
	_expect(explorer.monster_list.item_count == 0, "empty search is safe")
	explorer.filter_monsters("")
	_expect(explorer.monster_list.item_count == expected_paths.size(), "clearing search restores all unique bodies")
	var file := FileAccess.open("user://monster-explorer-validation.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(records, "\t"))
	file.close()
	explorer.free()
	for failure in failures: push_error(failure)
	print("MONSTER_PACK_EXPLORER_OK" if failures.is_empty() else "MONSTER_PACK_EXPLORER_FAILED")
	quit(0 if failures.is_empty() else 1)
func _expect(value: bool, message: String) -> void:
	if not value: failures.append(message)
