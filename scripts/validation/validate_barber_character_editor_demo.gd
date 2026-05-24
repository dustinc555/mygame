extends SceneTree

const BARBER_DEMO_SCENE := preload("res://scenes/test_levels/barber_character_editor_demo.tscn")
const SILVER_ITEM := preload("res://resources/items/silver.tres")
const HAIR_LONG := preload("res://resources/character_appearance/hair_long.tres")
const HAIR_BUZZED := preload("res://resources/character_appearance/hair_buzzed.tres")
const BEARD_FULL := preload("res://resources/character_appearance/beard_full.tres")
const EYEBROWS_FINE := preload("res://resources/character_appearance/eyebrows_female.tres")
const EYEBROWS_REGULAR := preload("res://resources/character_appearance/eyebrows_regular.tres")
const VISUAL_BODY_TYPE_MALE := 2
const VISUAL_BODY_TYPE_FEMALE := 3
const VIEW_FULL_BODY := 0
const VIEW_FACE := 1
const CLOTHING_EQUIPMENT_SLOTS := ["undershirt", "hands", "chest", "legs", "feet", "backpack", "head"]
const MALE_HAIR_IDS: Array[String] = ["hair_buzzed", "hair_simple_parted", "hair_long"]
const FEMALE_HAIR_IDS: Array[String] = ["hair_buns", "hair_long", "hair_buzzed_female"]

var _failures: Array[String] = []
var _scene: Node
var _mira: HumanoidCharacter
var _tomas: HumanoidCharacter
var _barber: HumanoidCharacter
var _appearance_controller: Node
var _world_time: WorldTimeController


func _initialize() -> void:
	root.size = Vector2i(1280, 720)
	call_deferred("_run")


func _run() -> void:
	await _load_scene()
	_run_initial_state_checks()
	await _run_mira_edit_case()
	await _run_tomas_cancel_case()
	await _run_tomas_edit_case()
	if _failures.is_empty():
		print("BARBER_CHARACTER_EDITOR_DEMO_OK")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	print("BARBER_CHARACTER_EDITOR_DEMO_FAILED count=%d" % _failures.size())
	quit(1)


func _load_scene() -> void:
	_scene = BARBER_DEMO_SCENE.instantiate()
	root.add_child(_scene)
	await _wait_frames(60)
	_mira = _scene.get_node_or_null("PartyMembers/Mira") as HumanoidCharacter
	_tomas = _scene.get_node_or_null("PartyMembers/Tomas") as HumanoidCharacter
	_barber = _scene.get_node_or_null("NPCs/Barber") as HumanoidCharacter
	_appearance_controller = _scene.get_node_or_null("GameBootstrap/CharacterAppearanceController")
	_world_time = _scene.get_node_or_null("GameBootstrap/WorldTimeController") as WorldTimeController
	if _mira == null:
		_fail("Mira was not found")
	if _tomas == null:
		_fail("Tomas was not found")
	if _barber == null:
		_fail("Barber was not found")
	if _appearance_controller == null:
		_fail("CharacterAppearanceController was not found")
	if _world_time == null:
		_fail("WorldTimeController was not found")


func _run_initial_state_checks() -> void:
	if _mira != null:
		_expect_silver(_mira, 10, "Mira")
		_expect_clothed(_mira, "Mira")
	if _tomas != null:
		_expect_silver(_tomas, 10, "Tomas")
		_expect_clothed(_tomas, "Tomas")
	if _barber != null:
		_expect_clothed(_barber, "Barber")
	_expect_world_paused(false, "initial scene")


func _run_mira_edit_case() -> void:
	if _appearance_controller == null or _mira == null or _barber == null:
		return
	var start_position := _mira.global_position
	var start_hair := _style_id(_mira.appearance_data.hair_style)
	var start_beard := _style_id(_mira.appearance_data.beard_style)
	var start_eyebrows := _style_id(_mira.appearance_data.eyebrow_style)
	var opened: bool = _appearance_controller.open_barber_editor(_mira, _barber)
	await _wait_frames(4)
	if not opened or not _appearance_controller.is_editor_open():
		_fail("Mira could not open barber editor")
		return
	_expect_world_paused(true, "Mira editor open")
	_expect_silver(_mira, 9, "Mira after opening barber editor")
	_expect_silver(_tomas, 10, "Tomas after Mira opened barber editor")
	var editor = _appearance_controller.get_editor_window()
	if editor == null or editor.draft_appearance == null:
		_fail("Editor draft was not created for Mira")
		return
	_expect_preview_isolated(editor, _mira, "Mira")
	await _expect_clothes_toggle_persists(editor, _mira, "Mira")
	await _expect_face_view_frames_closer(editor, "Mira")
	await _expect_preview_can_rotate(editor, "Mira")
	await _spam_preview_changes(editor, _mira, start_position, start_hair, start_beard, start_eyebrows, "Mira before save")
	editor.draft_appearance.hair_style = HAIR_LONG
	editor.draft_appearance.beard_style = null
	editor.draft_appearance.eyebrow_style = EYEBROWS_REGULAR
	editor.draft_appearance.hair_color = Color(0.32, 0.17, 0.08, 1.0)
	editor.draft_appearance.eyebrow_color = Color(0.95, 0.2, 0.85, 1.0)
	editor._rebuild_preview()
	_expect_draft_eyebrows(editor, EYEBROWS_FINE, "Mira before Save")
	if _style_id(_mira.appearance_data.hair_style) == _style_id(HAIR_LONG):
		_fail("Mira live hair changed before Save")
	_expect_actor_stable(_mira, start_position, "Mira before Save")
	var portrait_child_id_before_save := _get_party_portrait_root_child_id(_mira, "Mira before Save")
	editor.save_current()
	await _wait_frames(6)
	_expect_world_paused(false, "Mira editor saved")
	_expect_actor_stable(_mira, start_position, "Mira after Save")
	_expect_style(_mira, HAIR_LONG, null, EYEBROWS_FINE, "Mira")
	_expect_party_portrait_rebuilt(_mira, portrait_child_id_before_save, "Mira after Save")
	if _appearance_controller.is_editor_open():
		_fail("Editor stayed open after saving Mira")


func _run_tomas_cancel_case() -> void:
	if _appearance_controller == null or _tomas == null or _barber == null:
		return
	var start_position := _tomas.global_position
	var start_hair := _style_id(_tomas.appearance_data.hair_style)
	var start_beard := _style_id(_tomas.appearance_data.beard_style)
	var start_eyebrows := _style_id(_tomas.appearance_data.eyebrow_style)
	var opened: bool = _appearance_controller.open_barber_editor(_tomas, _barber)
	await _wait_frames(4)
	if not opened or not _appearance_controller.is_editor_open():
		_fail("Tomas could not open barber editor for cancel case")
		return
	_expect_world_paused(true, "Tomas cancel editor open")
	_expect_silver(_tomas, 9, "Tomas after opening cancel editor")
	var editor = _appearance_controller.get_editor_window()
	if editor == null or editor.draft_appearance == null:
		_fail("Editor draft was not created for Tomas cancel case")
		return
	_expect_preview_isolated(editor, _tomas, "Tomas cancel")
	await _expect_clothes_toggle_persists(editor, _tomas, "Tomas cancel")
	await _expect_preview_can_rotate(editor, "Tomas cancel")
	await _spam_preview_changes(editor, _tomas, start_position, start_hair, start_beard, start_eyebrows, "Tomas cancel before close")
	var portrait_child_id_before_cancel := _get_party_portrait_root_child_id(_tomas, "Tomas before Cancel")
	editor.cancel_current()
	await _wait_frames(6)
	_expect_world_paused(false, "Tomas editor canceled")
	_expect_actor_stable(_tomas, start_position, "Tomas after Cancel")
	_expect_style_ids(_tomas, start_hair, start_beard, start_eyebrows, "Tomas after Cancel")
	_expect_party_portrait_unchanged(_tomas, portrait_child_id_before_cancel, "Tomas after Cancel")


func _run_tomas_edit_case() -> void:
	if _appearance_controller == null or _tomas == null or _barber == null:
		return
	var start_position := _tomas.global_position
	var start_hair := _style_id(_tomas.appearance_data.hair_style)
	var start_beard := _style_id(_tomas.appearance_data.beard_style)
	var start_eyebrows := _style_id(_tomas.appearance_data.eyebrow_style)
	var opened: bool = _appearance_controller.open_barber_editor(_tomas, _barber)
	await _wait_frames(4)
	if not opened or not _appearance_controller.is_editor_open():
		_fail("Tomas could not open barber editor")
		return
	_expect_world_paused(true, "Tomas editor open")
	_expect_silver(_tomas, 8, "Tomas after opening barber editor")
	_expect_silver(_mira, 9, "Mira after Tomas opened barber editor")
	var editor = _appearance_controller.get_editor_window()
	if editor == null or editor.draft_appearance == null:
		_fail("Editor draft was not created for Tomas")
		return
	_expect_preview_isolated(editor, _tomas, "Tomas")
	await _expect_face_view_frames_closer(editor, "Tomas")
	await _expect_preview_can_rotate(editor, "Tomas")
	await _spam_preview_changes(editor, _tomas, start_position, start_hair, start_beard, start_eyebrows, "Tomas before save")
	editor.draft_appearance.hair_style = HAIR_BUZZED
	editor.draft_appearance.beard_style = BEARD_FULL
	editor.draft_appearance.eyebrow_style = EYEBROWS_FINE
	editor.draft_appearance.hair_color = Color(0.08, 0.07, 0.055, 1.0)
	editor.draft_appearance.eyebrow_color = Color(0.7, 0.25, 0.1, 1.0)
	editor._rebuild_preview()
	_expect_draft_eyebrows(editor, EYEBROWS_REGULAR, "Tomas before Save")
	var portrait_child_id_before_save := _get_party_portrait_root_child_id(_tomas, "Tomas before Save")
	editor.save_current()
	await _wait_frames(6)
	_expect_world_paused(false, "Tomas editor saved")
	_expect_actor_stable(_tomas, start_position, "Tomas after Save")
	_expect_style(_tomas, HAIR_BUZZED, BEARD_FULL, EYEBROWS_REGULAR, "Tomas")
	_expect_style(_mira, HAIR_LONG, null, EYEBROWS_FINE, "Mira after Tomas save")
	_expect_party_portrait_rebuilt(_tomas, portrait_child_id_before_save, "Tomas after Save")


func _spam_preview_changes(editor, actor: HumanoidCharacter, start_position: Vector3, start_hair: String, start_beard: String, start_eyebrows: String, label: String) -> void:
	var hair_options := [HAIR_LONG, HAIR_BUZZED, null]
	var beard_options := [BEARD_FULL, null]
	var expected_eyebrows := _expected_eyebrow_style_for_actor(actor)
	var wrong_eyebrows := EYEBROWS_REGULAR if _get_actor_resolved_body_type(actor) == VISUAL_BODY_TYPE_FEMALE else EYEBROWS_FINE
	for index in range(24):
		editor.draft_appearance.hair_style = hair_options[index % hair_options.size()]
		editor.draft_appearance.beard_style = beard_options[index % beard_options.size()]
		editor.draft_appearance.eyebrow_style = null if index % 2 == 0 else wrong_eyebrows
		editor.draft_appearance.hair_color = Color(0.1 + float(index % 7) * 0.09, 0.04 + float(index % 4) * 0.08, 0.03 + float(index % 5) * 0.06, 1.0)
		editor.draft_appearance.beard_color = Color(0.08 + float(index % 5) * 0.11, 0.05, 0.04 + float(index % 3) * 0.09, 1.0)
		editor.draft_appearance.eyebrow_color = Color(0.9, 0.1, 0.8, 1.0)
		editor._rebuild_preview()
		await _wait_frames(1)
		_expect_preview_isolated(editor, actor, "%s spam %d" % [label, index])
		_expect_draft_eyebrows(editor, expected_eyebrows, "%s spam %d" % [label, index])
		_expect_actor_stable(actor, start_position, "%s spam %d" % [label, index])
		_expect_style_ids(actor, start_hair, start_beard, start_eyebrows, "%s spam %d" % [label, index])


func _expect_silver(actor: HumanoidCharacter, amount: int, label: String) -> void:
	if actor == null or actor.inventory == null:
		_fail("%s inventory missing" % label)
		return
	var count := actor.inventory.count_item(SILVER_ITEM)
	if count != amount:
		_fail("Expected %s to have %d silver, got %d" % [label, amount, count])


func _expect_clothed(actor: HumanoidCharacter, label: String) -> void:
	if actor.get_equipped_item("chest") == null:
		_fail("%s has no chest clothing" % label)
	if actor.get_equipped_item("legs") == null:
		_fail("%s has no leg clothing" % label)
	if actor.get_equipped_item("feet") == null:
		_fail("%s has no shoes" % label)


func _expect_world_paused(expected: bool, label: String) -> void:
	if _world_time == null:
		_fail("Cannot check world pause for %s; WorldTimeController missing" % label)
		return
	var world_paused := bool(_world_time.is_world_paused())
	if world_paused != expected:
		_fail("Expected world paused=%s for %s, got %s" % [str(expected), label, str(world_paused)])
	if paused != expected:
		_fail("Expected SceneTree paused=%s for %s, got %s" % [str(expected), label, str(paused)])


func _expect_preview_isolated(editor, actor: HumanoidCharacter, label: String) -> void:
	if editor == null:
		_fail("Preview editor missing for %s" % label)
		return
	if not editor.preview_uses_own_world():
		_fail("Preview does not use its own World3D for %s" % label)
	if not editor.has_opaque_modal_background():
		_fail("Editor background is not fully opaque for %s" % label)
	if not editor.preview_has_studio_environment():
		_fail("Preview studio environment is missing for %s" % label)
	if editor.preview_contains_live_actor_nodes():
		_fail("Preview contains live actor, collision, or navigation nodes for %s" % label)
	if not editor.preview_is_playing_idle():
		_fail("Preview is not playing idle animation for %s" % label)
	if not editor.preview_faces_camera():
		_fail("Preview is not face-forward for %s" % label)
	_expect_preview_body_matches_actor(editor, actor, label)
	_expect_preview_clothing_matches_actor(editor, actor, label)
	_expect_beard_controls_match_actor(editor, actor, label)
	_expect_hair_options_match_actor(editor, actor, label)
	_expect_automatic_eyebrows_match_actor(editor, actor, label)
	_expect_creation_controls_hidden(editor, label)
	_expect_default_skin_untouched(actor, label)
	_expect_custom_eyebrows_replace_base(editor, label)
	_expect_preview_feet_above_floor(editor, label)
	for node in get_nodes_in_group("humanoid_character"):
		if str(node.name).contains("Preview"):
			_fail("Preview leaked into humanoid_character group for %s" % label)


func _expect_preview_can_rotate(editor, label: String) -> void:
	var start_rotation := float(editor.get_preview_rotation_y())
	var start_pitch := float(editor.get_preview_pitch_x())
	editor.rotate_preview_by(0.75)
	await _wait_frames(1)
	if absf(float(editor.get_preview_rotation_y()) - start_rotation) < 0.1:
		_fail("Preview did not rotate for %s" % label)
	if editor.preview_faces_camera():
		_fail("Preview still reports face-forward after rotation for %s" % label)
	editor.reset_preview_rotation()
	await _wait_frames(1)
	if absf(float(editor.get_preview_rotation_y())) > 0.001:
		_fail("Preview reset did not return to front for %s" % label)
	if not editor.preview_faces_camera():
		_fail("Preview is not face-forward after reset for %s" % label)
	editor.pitch_preview_by(0.18)
	await _wait_frames(1)
	if float(editor.get_preview_pitch_x()) <= start_pitch:
		_fail("Preview did not pitch up for %s" % label)
	editor.pitch_preview_by(-0.36)
	await _wait_frames(1)
	if float(editor.get_preview_pitch_x()) >= start_pitch:
		_fail("Preview did not pitch down for %s" % label)
	var start_distance := float(editor.get_preview_camera_distance())
	editor.zoom_preview_by_steps(1.0)
	await _wait_frames(1)
	var zoomed_in_distance := float(editor.get_preview_camera_distance())
	if zoomed_in_distance >= start_distance:
		_fail("Preview did not zoom in for %s" % label)
	editor.zoom_preview_by_steps(-2.0)
	await _wait_frames(1)
	if float(editor.get_preview_camera_distance()) <= zoomed_in_distance:
		_fail("Preview did not zoom out for %s" % label)
	editor.reset_preview_zoom()
	await _wait_frames(1)
	if absf(float(editor.get_preview_camera_distance()) - start_distance) > 0.01:
		_fail("Preview zoom reset did not restore distance for %s" % label)
	editor.reset_preview_rotation()


func _expect_clothes_toggle_persists(editor, actor: HumanoidCharacter, label: String) -> void:
	var slot_name := _first_preview_clothing_slot(actor)
	if slot_name.is_empty():
		return
	editor.set_preview_clothes_visible(false)
	editor._rebuild_preview()
	await _wait_frames(1)
	if editor.get_preview_clothes_visible():
		_fail("Preview clothes state did not store hidden for %s" % label)
	if editor.preview_clothing_slot_visible(slot_name):
		_fail("Preview clothing became visible after hidden rebuild for %s" % label)
	editor.set_preview_clothes_visible(true)
	editor._rebuild_preview()
	await _wait_frames(1)
	if not editor.get_preview_clothes_visible():
		_fail("Preview clothes state did not store shown for %s" % label)
	if not editor.preview_clothing_slot_visible(slot_name):
		_fail("Preview clothing stayed hidden after shown rebuild for %s" % label)


func _expect_face_view_frames_closer(editor, label: String) -> void:
	if editor._face_view_button == null or not (editor._face_view_button is CheckButton):
		_fail("Face view toggle is missing for %s" % label)
	elif str(editor._face_view_button.text) != "Face":
		_fail("Face view control is not the compact Face toggle for %s" % label)
	editor.set_preview_view_mode(VIEW_FULL_BODY)
	await _wait_frames(1)
	var full_distance := float(editor.get_preview_camera_distance())
	if editor._face_view_button != null and editor._face_view_button.button_pressed:
		_fail("Face toggle stayed pressed in full-body view for %s" % label)
	editor.set_preview_view_mode(VIEW_FACE)
	await _wait_frames(1)
	var face_distance := float(editor.get_preview_camera_distance())
	if int(editor.get_preview_view_mode()) != VIEW_FACE:
		_fail("Face view did not activate for %s" % label)
	if editor._face_view_button != null and not editor._face_view_button.button_pressed:
		_fail("Face toggle did not reflect face view for %s" % label)
	if face_distance >= full_distance:
		_fail("Face view is not closer for %s: face %.3f full %.3f" % [label, face_distance, full_distance])
	editor.set_preview_view_mode(VIEW_FULL_BODY)
	await _wait_frames(1)


func _expect_preview_body_matches_actor(editor, actor: HumanoidCharacter, label: String) -> void:
	if actor == null:
		_fail("Cannot check preview body for %s; actor missing" % label)
		return
	var expected_body_type := _get_actor_resolved_body_type(actor)
	var preview_body_type := int(editor.get_preview_body_type())
	if preview_body_type != expected_body_type:
		_fail("Expected preview body type %d for %s, got %d" % [expected_body_type, label, preview_body_type])


func _expect_preview_clothing_matches_actor(editor, actor: HumanoidCharacter, label: String) -> void:
	if actor == null:
		_fail("Cannot check preview clothing for %s; actor missing" % label)
		return
	var body_archetype := _get_actor_resolved_body_archetype(actor)
	for slot_name in CLOTHING_EQUIPMENT_SLOTS:
		var item := actor.get_equipped_item(slot_name)
		if item == null:
			continue
		if item.get_equipped_scene_for_body_archetype(body_archetype) == null:
			continue
		if not editor.preview_has_clothing_slot(slot_name):
			_fail("Preview is missing %s clothing for %s" % [slot_name, label])
		var equipment_visual := item.get_equipment_visual_for_body_archetype(body_archetype)
		if equipment_visual != null and float(equipment_visual.get("surface_offset_ratio")) > 0.0:
			if float(editor.get_preview_clothing_surface_offset(slot_name)) <= 0.0:
				_fail("Preview did not apply clothing surface offset for %s on %s" % [slot_name, label])


func _first_preview_clothing_slot(actor: HumanoidCharacter) -> String:
	if actor == null:
		return ""
	var body_archetype := _get_actor_resolved_body_archetype(actor)
	for slot_name in CLOTHING_EQUIPMENT_SLOTS:
		var item := actor.get_equipped_item(slot_name)
		if item != null and item.get_equipped_scene_for_body_archetype(body_archetype) != null:
			return slot_name
	return ""


func _expect_beard_controls_match_actor(editor, actor: HumanoidCharacter, label: String) -> void:
	var body_type := _get_actor_resolved_body_type(actor)
	if body_type == VISUAL_BODY_TYPE_FEMALE:
		if editor.beard_controls_visible():
			_fail("Female preview shows beard controls for %s" % label)
		if editor.draft_appearance != null and editor.draft_appearance.beard_style != null:
			_fail("Female draft kept a beard for %s" % label)
		if editor.get_beard_option_count() > 1:
			_fail("Female preview has beard style options for %s" % label)
	else:
		if not editor.beard_controls_visible():
			_fail("Male preview hides beard controls for %s" % label)
		if editor.get_beard_option_count() <= 1:
			_fail("Male preview has no beard style option for %s" % label)


func _expect_hair_options_match_actor(editor, actor: HumanoidCharacter, label: String) -> void:
	var expected := FEMALE_HAIR_IDS if _get_actor_resolved_body_type(actor) == VISUAL_BODY_TYPE_FEMALE else MALE_HAIR_IDS
	var actual := Array(editor.get_hair_option_style_ids())
	if actual != expected:
		_fail("Unexpected hair options for %s: expected %s got %s" % [label, str(expected), str(actual)])


func _expect_creation_controls_hidden(editor, label: String) -> void:
	if editor != null and editor.has_method("creation_controls_visible") and editor.creation_controls_visible():
		_fail("Barber mode exposes creation-only Race/Sex/body/skin controls for %s" % label)


func _expect_default_skin_untouched(actor: HumanoidCharacter, label: String) -> void:
	if actor == null:
		return
	if actor.appearance_data != null and bool(actor.appearance_data.skin_color_customized):
		_fail("Default barber actor unexpectedly has custom skin data for %s" % label)
	if actor.has_method("has_custom_skin_material") and actor.has_custom_skin_material():
		_fail("Default barber actor received a custom skin material for %s" % label)


func _expect_automatic_eyebrows_match_actor(editor, actor: HumanoidCharacter, label: String) -> void:
	var expected := _expected_eyebrow_style_for_actor(actor)
	_expect_draft_eyebrows(editor, expected, label)
	if _editor_has_text(editor, "Eyebrows"):
		_fail("Eyebrow style control is still exposed for %s" % label)
	if _editor_has_text(editor, "Eyebrow color"):
		_fail("Eyebrow color control is still exposed for %s" % label)
	if expected != null and not bool(expected.get("colorize")):
		_fail("Automatic eyebrow style is not colorized for %s" % label)


func _expect_draft_eyebrows(editor, expected: Resource, label: String) -> void:
	if editor == null or editor.draft_appearance == null:
		_fail("Cannot check draft eyebrows for %s; draft missing" % label)
		return
	if _style_id(editor.draft_appearance.eyebrow_style) != _style_id(expected):
		_fail("Unexpected automatic eyebrows for %s: expected %s got %s" % [label, _style_id(expected), _style_id(editor.draft_appearance.eyebrow_style)])
	if not _colors_match(editor.draft_appearance.eyebrow_color, editor.draft_appearance.hair_color):
		_fail("Draft eyebrow color does not track hair color for %s" % label)


func _expect_custom_eyebrows_replace_base(editor, label: String) -> void:
	if editor.draft_appearance == null or editor.draft_appearance.eyebrow_style == null:
		return
	if not editor.preview_has_custom_eyebrows():
		_fail("Custom eyebrows are missing for %s" % label)
	if editor.preview_has_visible_base_eyebrows():
		_fail("Base eyebrows stayed visible under custom eyebrows for %s" % label)


func _expect_preview_feet_above_floor(editor, label: String) -> void:
	var lowest_y := float(editor.get_preview_lowest_visual_y())
	var floor_y := float(editor.get_preview_floor_y())
	if lowest_y < floor_y - 0.005:
		_fail("Preview feet sink below floor for %s: feet %.3f floor %.3f" % [label, lowest_y, floor_y])


func _get_actor_resolved_body_type(actor: HumanoidCharacter) -> int:
	if actor != null and actor.has_method("get_resolved_visual_body_type"):
		return int(actor.get_resolved_visual_body_type())
	if actor != null:
		var raw_type := int(actor.visual_body_type)
		if raw_type == VISUAL_BODY_TYPE_FEMALE:
			return VISUAL_BODY_TYPE_FEMALE
	return VISUAL_BODY_TYPE_MALE


func _get_actor_resolved_body_archetype(actor: HumanoidCharacter) -> Resource:
	if actor != null and actor.has_method("get_resolved_body_archetype"):
		return actor.get_resolved_body_archetype()
	return actor.body_archetype if actor != null else null


func _expected_eyebrow_style_for_actor(actor: HumanoidCharacter) -> Resource:
	return EYEBROWS_FINE if _get_actor_resolved_body_type(actor) == VISUAL_BODY_TYPE_FEMALE else EYEBROWS_REGULAR


func _expect_actor_stable(actor: HumanoidCharacter, expected_position: Vector3, label: String) -> void:
	if actor == null:
		_fail("Cannot check actor stability for %s; actor missing" % label)
		return
	var distance := actor.global_position.distance_to(expected_position)
	if distance > 0.001:
		_fail("%s moved during editor changes: expected %s got %s" % [label, str(expected_position), str(actor.global_position)])
	if actor.global_position.length() > 100.0:
		_fail("%s was flung far from the level: %s" % [label, str(actor.global_position)])


func _expect_style(actor: HumanoidCharacter, hair: Resource, beard: Resource, eyebrows: Resource, label: String) -> void:
	if actor == null or actor.appearance_data == null:
		_fail("%s appearance data missing" % label)
		return
	if _style_id(actor.appearance_data.hair_style) != _style_id(hair):
		_fail("%s hair style mismatch" % label)
	if _style_id(actor.appearance_data.beard_style) != _style_id(beard):
		_fail("%s beard style mismatch" % label)
	if _style_id(actor.appearance_data.eyebrow_style) != _style_id(eyebrows):
		_fail("%s eyebrow style mismatch" % label)
	if not _colors_match(actor.appearance_data.eyebrow_color, actor.appearance_data.hair_color):
		_fail("%s eyebrow color does not track hair color" % label)


func _expect_style_ids(actor: HumanoidCharacter, hair_id: String, beard_id: String, eyebrow_id: String, label: String) -> void:
	if actor == null or actor.appearance_data == null:
		_fail("%s appearance data missing" % label)
		return
	if _style_id(actor.appearance_data.hair_style) != hair_id:
		_fail("%s live hair changed before Save" % label)
	if _style_id(actor.appearance_data.beard_style) != beard_id:
		_fail("%s live beard changed before Save" % label)
	if _style_id(actor.appearance_data.eyebrow_style) != eyebrow_id:
		_fail("%s live eyebrow changed before Save" % label)
	if not _colors_match(actor.appearance_data.eyebrow_color, actor.appearance_data.hair_color):
		_fail("%s live eyebrow color does not track hair color" % label)


func _expect_party_portrait_rebuilt(actor: HumanoidCharacter, previous_child_id: int, label: String) -> void:
	var current_child_id := _get_party_portrait_root_child_id(actor, label)
	if previous_child_id == 0 or current_child_id == 0:
		return
	if current_child_id == previous_child_id:
		_fail("Party portrait did not rebuild for %s" % label)


func _expect_party_portrait_unchanged(actor: HumanoidCharacter, previous_child_id: int, label: String) -> void:
	var current_child_id := _get_party_portrait_root_child_id(actor, label)
	if previous_child_id == 0 or current_child_id == 0:
		return
	if current_child_id != previous_child_id:
		_fail("Party portrait rebuilt unexpectedly for %s" % label)


func _get_party_portrait_root_child_id(actor: HumanoidCharacter, label: String) -> int:
	var card := _get_party_portrait_card(actor, label)
	if card == null:
		return 0
	var portrait_root = card.get("portrait_root") as Node3D
	if portrait_root == null:
		_fail("Party portrait root missing for %s" % label)
		return 0
	if portrait_root.get_child_count() <= 0:
		_fail("Party portrait has no visual copy for %s" % label)
		return 0
	return portrait_root.get_child(0).get_instance_id()


func _get_party_portrait_card(actor: HumanoidCharacter, label: String) -> Node:
	var portrait_flow := _scene.get_node_or_null("GameHUD/HudLayout/BottomHud/RightHud/BottomInfoRow/PortraitBar/Margin/PortraitColumn/PortraitScroll/PortraitFlow")
	if portrait_flow == null:
		_fail("Party portrait flow missing for %s" % label)
		return null
	for child in portrait_flow.get_children():
		if child.get("member") == actor:
			return child
	_fail("Party portrait card missing for %s" % label)
	return null


func _style_id(style: Resource) -> String:
	return "" if style == null else str(style.get("style_id"))


func _colors_match(left: Color, right: Color) -> bool:
	return absf(left.r - right.r) < 0.001 \
		and absf(left.g - right.g) < 0.001 \
		and absf(left.b - right.b) < 0.001 \
		and absf(left.a - right.a) < 0.001


func _editor_has_text(root_node: Node, text: String) -> bool:
	if root_node is Label and (root_node as Label).text == text:
		return true
	if root_node is Button and (root_node as Button).text == text:
		return true
	for child in root_node.get_children():
		if _editor_has_text(child, text):
			return true
	return false


func _wait_frames(frame_count: int) -> void:
	for _index in range(frame_count):
		await process_frame


func _fail(message: String) -> void:
	_failures.append(message)
