extends SceneTree

const HUMAN_MALE_BODY := "res://resources/character_body_archetypes/human_male.tres"
const HUMAN_FEMALE_BODY := "res://resources/character_body_archetypes/human_female.tres"
const HUMAN_MALE_GRIP_PROFILE := "res://resources/humanoid_grip_socket_profiles/human_male.tres"
const HUMAN_FEMALE_GRIP_PROFILE := "res://resources/humanoid_grip_socket_profiles/human_female.tres"
const DEFAULT_GRIP_PROFILE := "res://resources/humanoid_grip_socket_profiles/default.tres"
const EQUIPMENT_GRIP_PROFILE_DIR := "res://resources/equipment_grip_profiles"

const T_IDENTITY := [1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0]
const T_HUMAN_MALE_RIGHT_HAND_ONE_HAND := [0.9999674, -0.008080745, 3.0307135e-10, 0.008080778, 0.99996775, -5.031495e-10, -2.9899638e-10, 5.0519944e-10, 1.0, -0.03097117, 0.08993864, 3.7252903e-08]
const T_HUMAN_FEMALE_RIGHT_HAND_ONE_HAND := [0.9999674, -0.008080745, 3.0274805e-10, 0.0080807805, 0.99996793, 0.0, -3.0559022e-10, 0.0, 1.0, -0.03097117, 0.052304804, -0.0005973056]

const SOCKET_IDS := [
	"right_hand_one_hand",
	"left_hand_shield",
	"right_hand_two_hand_primary",
	"left_hand_two_hand_secondary",
	"right_hand_polearm_primary",
	"left_hand_polearm_secondary",
	"left_hand_bow_grip",
	"right_hand_bow_draw",
	"right_hand_crossbow_grip",
	"left_hand_crossbow_support",
	"right_hand_thrown",
]

var _failures: Array[String] = []


func _initialize() -> void:
	_validate_grip_profiles()
	_validate_human_grip_socket_profiles()
	_validate_equipped_items()
	_validate_wearable_visuals()
	if _failures.is_empty():
		print("EQUIPMENT_GRIP_DATA_VALIDATION_OK")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	quit(1)


func _validate_grip_profiles() -> void:
	var paths := _resource_paths_in(EQUIPMENT_GRIP_PROFILE_DIR)
	_expect(not paths.is_empty(), "Equipment grip profile directory has resources")
	for path in paths:
		var profile := load(path)
		_expect(profile != null, "Grip profile loads: %s" % path)
		if profile == null:
			continue
		_expect(not str(profile.get("profile_id")).strip_edges().is_empty(), "Grip profile id exists: %s" % path)
		_expect(not str(profile.get("display_name")).strip_edges().is_empty(), "Grip profile display name exists: %s" % path)
		_expect(not str(profile.get("grip_class_id")).strip_edges().is_empty(), "Grip profile class exists: %s" % path)
		_expect(not str(profile.get("primary_bone")).strip_edges().is_empty(), "Grip profile primary bone exists: %s" % path)
		_expect(not str(profile.get("primary_socket_id")).strip_edges().is_empty(), "Grip profile primary socket exists: %s" % path)
		_expect(str(profile.get("primary_grip_marker")) == "GripPoint_Primary", "Grip profile primary marker preserved: %s" % path)
		if bool(profile.get("requires_two_hands")):
			_expect(not str(profile.get("secondary_bone")).strip_edges().is_empty(), "Two-hand grip profile secondary bone exists: %s" % path)
			_expect(not str(profile.get("secondary_socket_id")).strip_edges().is_empty(), "Two-hand grip profile secondary socket exists: %s" % path)


func _validate_human_grip_socket_profiles() -> void:
	_validate_body_grip_profile(HUMAN_MALE_BODY, HUMAN_MALE_GRIP_PROFILE)
	_validate_body_grip_profile(HUMAN_FEMALE_BODY, HUMAN_FEMALE_GRIP_PROFILE)
	_validate_socket_profile(DEFAULT_GRIP_PROFILE, T_HUMAN_MALE_RIGHT_HAND_ONE_HAND)
	_validate_socket_profile(HUMAN_MALE_GRIP_PROFILE, T_HUMAN_MALE_RIGHT_HAND_ONE_HAND)
	_validate_socket_profile(HUMAN_FEMALE_GRIP_PROFILE, T_HUMAN_FEMALE_RIGHT_HAND_ONE_HAND)


func _validate_body_grip_profile(body_path: String, grip_profile_path: String) -> void:
	var body := load(body_path)
	_expect(body != null, "Human body archetype loads: %s" % body_path)
	if body == null:
		return
	_expect(_resource_path(body.get("grip_socket_profile")) == grip_profile_path, "Human body grip socket profile preserved: %s" % body_path)


func _validate_socket_profile(profile_path: String, right_hand_transform_values: Array) -> void:
	var profile := load(profile_path)
	_expect(profile != null, "Humanoid grip socket profile loads: %s" % profile_path)
	if profile == null:
		return
	for socket_id in SOCKET_IDS:
		var actual_transform = profile.call("get_socket_transform", socket_id) if profile.has_method("get_socket_transform") else profile.get(socket_id)
		if typeof(actual_transform) != TYPE_TRANSFORM3D:
			_failures.append("Socket transform missing: %s %s" % [profile_path, socket_id])
			continue
		var expected_values := right_hand_transform_values if socket_id == "right_hand_one_hand" else T_IDENTITY
		_expect_transform(actual_transform, _transform_from_values(expected_values), "Humanoid socket transform preserved: %s %s" % [profile_path, socket_id])


func _validate_equipped_items() -> void:
	for item_path in ItemDefinitionIndex.all_item_paths():
		var item := load(item_path) as ItemDefinition
		if item == null or item.equipped_scene == null and item.grip_profile == null:
			continue
		_expect(item.equipped_scene != null, "Equipped scene exists: %s" % item_path)
		_expect(item.grip_profile != null, "Grip profile exists: %s" % item_path)
		_expect(typeof(item.equipped_transform) == TYPE_TRANSFORM3D, "Equipped transform exists: %s" % item_path)
		if item.equipped_scene != null and item.grip_profile != null:
			_validate_equipped_scene_marker(item_path, item.equipped_scene, item.grip_profile)


func _validate_equipped_scene_marker(item_path: String, equipped_scene: PackedScene, grip_profile: Resource) -> void:
	var instance := equipped_scene.instantiate()
	_expect(instance != null, "Equipped scene instantiates: %s" % item_path)
	if instance == null:
		return
	var marker_name := str(grip_profile.get("primary_grip_marker")) if grip_profile != null else "GripPoint_Primary"
	_expect(instance.find_child(marker_name, true, false) != null, "Equipped scene exposes %s: %s" % [marker_name, item_path])
	instance.free()


func _validate_wearable_visuals() -> void:
	var bodies := {
		"human_male": load(HUMAN_MALE_BODY),
		"human_female": load(HUMAN_FEMALE_BODY),
	}
	for body_id in bodies.keys():
		_expect(bodies[body_id] != null, "Wearable validation body loads: %s" % body_id)
	for item_path in ItemDefinitionIndex.all_item_paths():
		var item := load(item_path) as ItemDefinition
		if item == null or item.equipped_visuals.is_empty():
			continue
		_expect(item.is_equippable(), "Wearable item is equippable: %s" % item_path)
		for body_id in bodies.keys():
			var body := bodies[body_id] as Resource
			if body == null:
				continue
			var visual = item.get_equipment_visual_for_body_archetype(body)
			_expect(visual != null, "Wearable has %s visual mapping: %s" % [body_id, item_path])
			if visual == null:
				continue
			_expect(_resource_path(visual.get("body_archetype")) == _resource_path(body), "Wearable %s body archetype preserved: %s" % [body_id, item_path])
			_expect(visual.get("visual_scene") is PackedScene, "Wearable %s visual scene exists: %s" % [body_id, item_path])
			_expect(str(visual.get("visual_layer")).strip_edges() != "", "Wearable %s visual layer exists: %s" % [body_id, item_path])
			_expect(str(visual.get("visual_coverage")).strip_edges() != "", "Wearable %s visual coverage exists: %s" % [body_id, item_path])
			_expect(typeof(visual.get("equipped_transform")) == TYPE_TRANSFORM3D, "Wearable %s equipped transform exists: %s" % [body_id, item_path])


func _resource_paths_in(directory_path: String) -> Array[String]:
	var result: Array[String] = []
	var dir := DirAccess.open(directory_path)
	if dir == null:
		return result
	dir.list_dir_begin()
	while true:
		var name := dir.get_next()
		if name.is_empty():
			break
		if name.begins_with("."):
			continue
		var path := "%s/%s" % [directory_path, name]
		if dir.current_is_dir():
			result.append_array(_resource_paths_in(path))
		elif name.ends_with(".tres"):
			result.append(path)
	dir.list_dir_end()
	result.sort()
	return result


func _transform_from_values(values: Array) -> Transform3D:
	return Transform3D(
		Basis(
			Vector3(float(values[0]), float(values[3]), float(values[6])),
			Vector3(float(values[1]), float(values[4]), float(values[7])),
			Vector3(float(values[2]), float(values[5]), float(values[8]))
		),
		Vector3(float(values[9]), float(values[10]), float(values[11]))
	)


func _expect_transform(actual: Transform3D, expected: Transform3D, message: String) -> void:
	_expect(actual.is_equal_approx(expected), "%s expected %s got %s" % [message, str(expected), str(actual)])


func _resource_path(value) -> String:
	if value is Resource:
		return (value as Resource).resource_path
	return ""


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
