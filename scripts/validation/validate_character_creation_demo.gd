extends SceneTree

const CHARACTER_CREATION_DEMO_SCENE := preload("res://scenes/test_levels/character_creation_demo.tscn")
const CHARACTER_APPEARANCE_DATA_SCRIPT := preload("res://scripts/character_appearance/character_appearance_data.gd")
const SKIN_TEXTURE_BUILDER := preload("res://scripts/character_appearance/skin_texture_builder.gd")
const HUMAN_RACE := preload("res://resources/character_races/human.tres")
const HUMAN_FEMALE_BODY_ARCHETYPE := preload("res://resources/character_body_archetypes/human_female.tres")
const FEMALE_DARK_TEXTURE: Texture2D = preload("res://assets/vendor/quaternius/universal_base_characters/base_characters/T_Superhero_Female_Dark_BaseColor.png")
const HAIR_BUNS := preload("res://resources/character_appearance/hair_buns.tres")
const BEARD_FULL := preload("res://resources/character_appearance/beard_full.tres")
const SILVER_ITEM := preload("res://resources/items/silver.tres")
const PEASANT_TUNIC := preload("res://resources/items/peasant_tunic.tres")
const PEASANT_TROUSERS := preload("res://resources/items/peasant_trousers.tres")
const PEASANT_SHOES := preload("res://resources/items/peasant_shoes.tres")
const IRON_SWORD := preload("res://resources/items/iron_sword.tres")
const ROUND_SHIELD := preload("res://resources/items/round_shield.tres")
const VISUAL_BODY_TYPE_FEMALE := 3
const DEFAULT_SKIN_COLOR := Color(0.58, 0.38, 0.27, 1.0)
const CUSTOM_SKIN_COLOR := Color(0.74, 0.45, 0.31, 1.0)
const FEMALE_SKIN_SAMPLE_UV := Vector2(0.5, 0.5)
const FEMALE_UNDERWEAR_SAMPLE_UV := Vector2(0.023, 0.344)

var _failures: Array[String] = []
var _scene: Node
var _appearance_controller: Node
var _party_manager: PartyManager


func _initialize() -> void:
	root.size = Vector2i(1280, 720)
	call_deferred("_run")


func _run() -> void:
	_validate_skeleton_slider_offsets()
	await _load_scene()
	_validate_custom_skin_texture_mask()
	await _run_creation_save_case()
	await _run_creation_cancel_case()
	if _failures.is_empty():
		print("CHARACTER_CREATION_DEMO_OK")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	print("CHARACTER_CREATION_DEMO_FAILED count=%d" % _failures.size())
	quit(1)


func _load_scene() -> void:
	_scene = CHARACTER_CREATION_DEMO_SCENE.instantiate()
	root.add_child(_scene)
	await _wait_frames(90)
	_appearance_controller = _scene.get_node_or_null("GameBootstrap/CharacterAppearanceController")
	_party_manager = _scene.get_node_or_null("PartyManager") as PartyManager
	if _appearance_controller == null:
		_fail("CharacterAppearanceController was not found")
	if _party_manager == null:
		_fail("PartyManager was not found")


func _run_creation_save_case() -> void:
	if _appearance_controller == null:
		return
	if not _appearance_controller.is_editor_open():
		_fail("Creation editor did not open automatically")
		return
	if not paused:
		_fail("SceneTree was not paused while creation editor was open")
	var editor = _appearance_controller.get_editor_window()
	if editor == null or editor.draft_appearance == null:
		_fail("Creation editor draft was missing")
		return
	if not editor.creation_controls_visible():
		_fail("Creation-only Race/Sex/body/skin controls are hidden in creation mode")
	if Array(editor.get_race_option_labels()) != ["Human"]:
		_fail("Creation race options are not Human-only")
	editor.set_character_name("Kaia")
	editor.set_creation_body_type(VISUAL_BODY_TYPE_FEMALE)
	await _validate_editor_height_keeps_feet_planted(editor)
	editor.set_creation_skeleton_sliders(0.62, -0.35, 0.18, 0.28)
	editor.set_skin_color_value(CUSTOM_SKIN_COLOR)
	editor.reset_skin_color_to_default()
	if not _colors_match(editor.get_preview_skin_color(), DEFAULT_SKIN_COLOR):
		_fail("Skin color reset did not restore the default color")
	editor.set_skin_color_value(Color(CUSTOM_SKIN_COLOR.r, CUSTOM_SKIN_COLOR.g, CUSTOM_SKIN_COLOR.b, 0.25))
	editor.draft_appearance.hair_style = HAIR_BUNS
	editor.draft_appearance.hair_color = Color(0.08, 0.045, 0.025, 1.0)
	editor.draft_appearance.beard_style = BEARD_FULL
	editor._rebuild_preview()
	if editor.draft_appearance.beard_style != null:
		_fail("Female creation draft kept a beard after preview rebuild")
	if not _colors_match(editor.draft_appearance.eyebrow_color, editor.draft_appearance.hair_color):
		_fail("Creation draft eyebrow color does not track hair color")
	if not _colors_match(editor.get_preview_skin_color(), CUSTOM_SKIN_COLOR):
		_fail("Preview skin color does not match creation draft skin color")
	if not editor.preview_has_custom_skin_material():
		_fail("Creation preview did not apply textured custom skin material")
	editor.save_current()
	await _wait_frames(8)
	if paused:
		_fail("SceneTree stayed paused after creation save")
	var created: HumanoidCharacter = null
	if _scene.has_method("get_created_member"):
		created = _scene.call("get_created_member") as HumanoidCharacter
	if created == null:
		_fail("Created character did not spawn")
		return
	_expect_created_character(created)


func _run_creation_cancel_case() -> void:
	if _appearance_controller == null:
		return
	var party_count_before := _get_party_member_count()
	if not bool(_appearance_controller.open_creation_editor()):
		_fail("Creation editor could not reopen for cancel case")
		return
	await _wait_frames(4)
	var editor = _appearance_controller.get_editor_window()
	if editor == null:
		_fail("Creation editor missing in cancel case")
		return
	editor.set_character_name("Canceled")
	editor.cancel_current()
	await _wait_frames(6)
	if paused:
		_fail("SceneTree stayed paused after creation cancel")
	if _get_party_member_count() != party_count_before:
		_fail("Creation cancel spawned an extra party member")


func _expect_created_character(created: HumanoidCharacter) -> void:
	if created.member_name != "Kaia":
		_fail("Created character name mismatch")
	if not created.is_player_party_member():
		_fail("Created character is not marked as a player party member")
	if _party_manager != null:
		if not _party_manager.party_members.has(created):
			_fail("Created character was not registered with PartyManager")
		if not _party_manager.selected_members.has(created):
			_fail("Created character was not selected after spawn")
	var appearance = created.appearance_data
	if appearance == null:
		_fail("Created character appearance missing")
		return
	if appearance.character_race != HUMAN_RACE:
		_fail("Created character race is not Human")
	if appearance.body_archetype != HUMAN_FEMALE_BODY_ARCHETYPE:
		_fail("Created character body archetype is not female human")
	if int(appearance.visual_body_type) != VISUAL_BODY_TYPE_FEMALE:
		_fail("Created character sex/body type is not female")
	_expect_close(appearance.height_slider, 0.62, "height slider")
	_expect_close(appearance.shoulder_width_slider, -0.35, "shoulder slider")
	_expect_close(appearance.arm_length_slider, 0.18, "arm length slider")
	_expect_close(appearance.neck_length_slider, 0.28, "neck length slider")
	if not appearance.skin_color_customized:
		_fail("Created character did not save custom skin color")
	if not _colors_match(appearance.skin_color, CUSTOM_SKIN_COLOR):
		_fail("Created character skin color mismatch")
	if not created.has_custom_skin_material():
		_fail("Created character did not apply textured custom skin material")
	_expect_created_feet_grounded(created)
	if appearance.hair_style != HAIR_BUNS:
		_fail("Created character hair style mismatch")
	if appearance.beard_style != null:
		_fail("Created female character saved a beard")
	if not _colors_match(appearance.eyebrow_color, appearance.hair_color):
		_fail("Created character eyebrow color does not track hair color")
	_expect_silver(created, 10)
	_expect_equipped(created, "chest", PEASANT_TUNIC)
	_expect_equipped(created, "legs", PEASANT_TROUSERS)
	_expect_equipped(created, "feet", PEASANT_SHOES)
	_expect_equipped(created, "weapon", IRON_SWORD)
	_expect_equipped(created, "offhand", ROUND_SHIELD)


func _expect_created_feet_grounded(created: HumanoidCharacter) -> void:
	var body := created.get_body_projection()
	var foot_y := float(body.get_visual_foot_anchor_y() if body != null else INF)
	var ground_y := float(body.get_visual_ground_y() if body != null else 0.0)
	if not is_finite(foot_y) or not is_finite(ground_y):
		_fail("Created character foot grounding could not be measured")
		return
	if foot_y < ground_y - 0.025:
		_fail("Created character feet are below visual ground: feet %.3f ground %.3f" % [foot_y, ground_y])


func _validate_skeleton_slider_offsets() -> void:
	var appearance = CHARACTER_APPEARANCE_DATA_SCRIPT.new()
	appearance.height_slider = 1.0
	var height_offsets: Dictionary = appearance.get_body_pose_offsets({})
	_expect_positive_y_offset(height_offsets, "calf_l", "height should lengthen left thigh")
	_expect_positive_y_offset(height_offsets, "foot_l", "height should lengthen left lower leg")
	_expect_positive_y_offset(height_offsets, "spine_03", "height should lengthen torso")
	if height_offsets.has("Head"):
		_fail("Height slider should not directly stretch the neck/head")

	appearance = CHARACTER_APPEARANCE_DATA_SCRIPT.new()
	appearance.arm_length_slider = 1.0
	var arm_offsets: Dictionary = appearance.get_body_pose_offsets({})
	_expect_positive_y_offset(arm_offsets, "lowerarm_l", "arm slider should lengthen left upper arm")
	_expect_positive_y_offset(arm_offsets, "hand_l", "arm slider should lengthen left forearm")

	appearance = CHARACTER_APPEARANCE_DATA_SCRIPT.new()
	appearance.neck_length_slider = 1.0
	var neck_offsets: Dictionary = appearance.get_body_pose_offsets({})
	_expect_positive_y_offset(neck_offsets, "Head", "neck slider should move the head from the neck")
	if neck_offsets.has("neck_01"):
		_fail("Neck slider should not lengthen the upper torso")

	appearance = CHARACTER_APPEARANCE_DATA_SCRIPT.new()
	appearance.shoulder_width_slider = -1.0
	var narrow_offsets: Dictionary = appearance.get_body_pose_offsets({})
	appearance.shoulder_width_slider = 0.0
	var neutral_offsets: Dictionary = appearance.get_body_pose_offsets({})
	appearance.shoulder_width_slider = 1.0
	var wide_offsets: Dictionary = appearance.get_body_pose_offsets({})
	if not (_get_offset(narrow_offsets, "clavicle_l").x < _get_offset(neutral_offsets, "clavicle_l").x and _get_offset(neutral_offsets, "clavicle_l").x < _get_offset(wide_offsets, "clavicle_l").x):
		_fail("Left shoulder slider is not monotonic")
	if not (_get_offset(narrow_offsets, "clavicle_r").x > _get_offset(neutral_offsets, "clavicle_r").x and _get_offset(neutral_offsets, "clavicle_r").x > _get_offset(wide_offsets, "clavicle_r").x):
		_fail("Right shoulder slider is not monotonic")


func _validate_editor_height_keeps_feet_planted(editor) -> void:
	editor.set_creation_skeleton_sliders(0.0, 0.0, 0.0, 0.0)
	await _wait_frames(2)
	var baseline_foot_y := float(editor.get_preview_foot_anchor_y())
	editor.set_creation_skeleton_sliders(1.0, 0.0, 0.0, 0.0)
	await _wait_frames(2)
	var tall_foot_y := float(editor.get_preview_foot_anchor_y())
	if not is_finite(baseline_foot_y) or not is_finite(tall_foot_y):
		_fail("Could not read preview foot anchor for height grounding")
		return
	if absf(tall_foot_y - baseline_foot_y) > 0.01:
		_fail("Height slider moved preview feet vertically: baseline %.3f tall %.3f" % [baseline_foot_y, tall_foot_y])


func _validate_custom_skin_texture_mask() -> void:
	if SKIN_TEXTURE_BUILDER.get_skin_mask_at_uv(VISUAL_BODY_TYPE_FEMALE, FEMALE_SKIN_SAMPLE_UV) < 0.5:
		_fail("Female skin sample is not included in the custom skin mask")
	if SKIN_TEXTURE_BUILDER.get_skin_mask_at_uv(VISUAL_BODY_TYPE_FEMALE, FEMALE_UNDERWEAR_SAMPLE_UV) > 0.01:
		_fail("Female underwear sample is incorrectly included in the custom skin mask")
	var texture := SKIN_TEXTURE_BUILDER.build_skin_texture(SKIN_TEXTURE_BUILDER.HUMAN_RACE_ID, VISUAL_BODY_TYPE_FEMALE, CUSTOM_SKIN_COLOR)
	if texture == null:
		_fail("Custom skin texture could not be generated")
		return
	var custom_image := texture.get_image()
	if custom_image == null:
		_fail("Custom skin texture image could not be read")
		return
	var base_image := _get_readable_image(FEMALE_DARK_TEXTURE)
	if base_image == null:
		_fail("Base female skin texture could not be read")
		return
	base_image.resize(custom_image.get_width(), custom_image.get_height(), Image.INTERPOLATE_BILINEAR)
	var base_skin := _sample_image_uv(base_image, FEMALE_SKIN_SAMPLE_UV)
	var custom_skin := _sample_image_uv(custom_image, FEMALE_SKIN_SAMPLE_UV)
	if _color_distance(base_skin, custom_skin) < 0.02:
		_fail("Custom skin texture did not change the sampled skin color")
	var base_underwear := _sample_image_uv(base_image, FEMALE_UNDERWEAR_SAMPLE_UV)
	var custom_underwear := _sample_image_uv(custom_image, FEMALE_UNDERWEAR_SAMPLE_UV)
	if _color_distance(base_underwear, custom_underwear) > 0.015:
		_fail("Custom skin texture changed the sampled underwear color")


func _expect_silver(actor: HumanoidCharacter, amount: int) -> void:
	if actor.inventory == null:
		_fail("Created character inventory missing")
		return
	var count := actor.inventory.count_item(SILVER_ITEM)
	if count != amount:
		_fail("Expected created character to have %d silver, got %d" % [amount, count])


func _expect_equipped(actor: HumanoidCharacter, slot_name: String, item: Resource) -> void:
	if actor.get_equipped_item(slot_name) != item:
		_fail("Created character equipment mismatch for %s" % slot_name)


func _get_party_member_count() -> int:
	var party_root := _scene.get_node_or_null("PartyMembers") if _scene != null else null
	if party_root == null:
		return 0
	var count := 0
	for child in party_root.get_children():
		if child is HumanoidCharacter:
			count += 1
	return count


func _expect_close(actual: float, expected: float, label: String) -> void:
	if absf(actual - expected) > 0.001:
		_fail("Expected %s %.3f, got %.3f" % [label, expected, actual])


func _expect_positive_y_offset(offsets: Dictionary, bone_name: String, label: String) -> void:
	if _get_offset(offsets, bone_name).y <= 0.001:
		_fail(label)


func _get_offset(offsets: Dictionary, bone_name: String) -> Vector3:
	return offsets.get(bone_name, Vector3.ZERO) as Vector3


func _colors_match(left: Color, right: Color) -> bool:
	return absf(left.r - right.r) < 0.001 \
		and absf(left.g - right.g) < 0.001 \
		and absf(left.b - right.b) < 0.001 \
		and absf(left.a - right.a) < 0.001


func _color_distance(left: Color, right: Color) -> float:
	return absf(left.r - right.r) + absf(left.g - right.g) + absf(left.b - right.b)


func _sample_image_uv(image: Image, uv: Vector2) -> Color:
	var x := clampi(int(round(clampf(uv.x, 0.0, 1.0) * float(image.get_width() - 1))), 0, image.get_width() - 1)
	var y := clampi(int(round(clampf(uv.y, 0.0, 1.0) * float(image.get_height() - 1))), 0, image.get_height() - 1)
	return image.get_pixel(x, y)


func _get_readable_image(texture: Texture2D) -> Image:
	if texture == null:
		return null
	var image := texture.get_image()
	if image == null:
		return null
	if image.is_compressed():
		var error := image.decompress()
		if error != OK:
			return null
	image.convert(Image.FORMAT_RGBA8)
	return image


func _wait_frames(frame_count: int) -> void:
	for _index in range(frame_count):
		await process_frame


func _fail(message: String) -> void:
	_failures.append(message)
